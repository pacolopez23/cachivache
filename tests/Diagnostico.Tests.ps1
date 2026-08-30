<#
    Lo que existia solo en la consola, ahora tambien en la ventana. [USO-12].

    Las dos capacidades de este punto -anonimizar las rutas del informe y
    copiar el diagnostico- YA ESTABAN ESCRITAS y probadas: viven en
    Export-Informe* (-Anonimo) y en Get-InformeDiagnostico. Lo que faltaba
    era el camino para llegar a ellas desde la ventana, porque el camino
    normal de este programa es hacer doble clic en Cachivache.exe, que
    arranca sin ninguna consola donde escribir. Es la leccion de [CNF-02]:
    una capacidad que solo existe en la consola es una capacidad que la
    mayoria de los usuarios no tiene.

    Por eso estas pruebas no comprueban QUE hacen esas funciones -de eso ya
    se encargan Report.Tests.ps1 y Log.Tests.ps1- sino que los dos caminos
    llaman A LA MISMA, que es la parte que puede volver a separarse. Es el
    patron de [ARQ-01], donde el bucle de borrado existia dos veces y las
    dos copias ya habian divergido.
#>

BeforeAll {
    $script:Raiz     = Split-Path $PSScriptRoot -Parent
    $script:CarpetaUI = Join-Path (Join-Path $script:Raiz 'src') 'UI'

    # Los comentarios se quitan ANTES de buscar nada. En este repositorio
    # una prueba de texto ha encontrado los comentarios del propio autor
    # seis veces, y aqui es especialmente facil: los comentarios de estos
    # archivos citan '-Anonimo' y 'Get-InformeDiagnostico' por su nombre
    # para explicar por que estan.
    function Get-CodigoSinComentarios {
        param([Parameter(Mandatory)] [string] $Ruta)
        $texto = Get-Content -Raw -LiteralPath $Ruta
        return ($texto -replace '(?s)<#.*?#>', '' -replace '(?m)^\s*#.*$', '')
    }

    $script:CodigoEventos = Get-CodigoSinComentarios (Join-Path $script:CarpetaUI 'Window.Eventos.ps1')
    $script:CodigoCli     = Get-CodigoSinComentarios (Join-Path (Join-Path $script:Raiz 'src') 'Cli/Cli.ps1')
    $script:CodigoEntrada = Get-CodigoSinComentarios (Join-Path $script:Raiz 'Cachivache.ps1')
    $script:XamlResultados = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUI 'Panel.Resultados.xaml')
    $script:XamlAcerca     = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUI 'Panel.Acerca.xaml')
}

Describe 'USO-12: la guarda de estas pruebas' {

    It 'se ha leido codigo de verdad en los cuatro sitios' {
        # Sin esto, un archivo que se moviera de sitio dejaria las cadenas
        # vacias y TODAS las comprobaciones de abajo pasarian celebrando
        # que no encuentran nada malo.
        $script:CodigoEventos.Length  | Should -BeGreaterThan 10000
        $script:CodigoCli.Length      | Should -BeGreaterThan 3000
        $script:CodigoEntrada.Length  | Should -BeGreaterThan 1000
        $script:XamlResultados.Length | Should -BeGreaterThan 5000
    }

    It 'quitar los comentarios no se ha llevado el codigo por delante' {
        $script:CodigoEventos | Should -Match 'Add_Click'
        $script:CodigoCli     | Should -Match 'Invoke-CachivacheCli'
    }
}

Describe 'USO-12: anonimizar las rutas del informe' {

    It 'la casilla existe en Resultados, pegada al boton de guardar' {
        $script:XamlResultados | Should -Match 'x:Name="ChkAnonimizar"'

        # Pegada de verdad: entre la casilla y el boton no puede haberse
        # colado otra cosa. Una opcion que cambia lo que produce un boton y
        # vive lejos de el es una opcion que se activa, se olvida y
        # sorprende. Es el mismo razonamiento que puso la casilla de
        # simular junto al boton rojo.
        $posCasilla = $script:XamlResultados.IndexOf('x:Name="ChkAnonimizar"')
        $posBoton   = $script:XamlResultados.IndexOf('x:Name="BtnExportar"')
        $posCasilla | Should -BeGreaterThan 0
        $posBoton   | Should -BeGreaterThan $posCasilla
        $entreMedias = $script:XamlResultados.Substring($posCasilla, $posBoton - $posCasilla)
        # Un solo <Button entre medias: el que abre el propio BtnExportar.
        @([regex]::Matches($entreMedias, '<Button')).Count | Should -Be 1
    }

    It 'la casilla tiene rotulo y explicacion' {
        $script:XamlResultados | Should -Match 'Content="Anonimizar rutas"'
        $script:XamlResultados | Should -Match 'ToolTip="En el informe que guardes'
    }

    It 'las tres exportaciones de la ventana pasan -Anonimo' {
        # Las tres, no dos. El fallo natural aqui es acordarse del HTML y
        # olvidarse del CSV, y entonces el usuario marca la casilla, exporta
        # a CSV y publica su nombre de usuario creyendo lo contrario. Es
        # peor que no tener la casilla.
        $exportaciones = @([regex]::Matches($script:CodigoEventos, 'Export-Informe(Html|Csv|Json)[^\r\n]*'))
        $exportaciones.Count | Should -BeGreaterOrEqual 3 -Because 'si no se encuentran, esta prueba no comprueba nada'

        $sinAnonimo = @($exportaciones |
            Where-Object { $_.Value -notmatch '-Anonimo' } |
            ForEach-Object { $_.Value.Trim() })

        # Las exportaciones automaticas -el informe del analisis y el de la
        # limpieza, que se generan solos- viven en otros archivos y no
        # llevan casilla: aqui solo se miran las del cierre $exportar.
        $sinAnonimo | Should -BeNullOrEmpty -Because (
            'la casilla tiene que valer para los tres formatos, no solo para el HTML')
    }

    It 'lo que se pasa es el valor de la casilla, no una constante' {
        # -Anonimo:$true cableado pasaria la prueba de arriba y haria que la
        # casilla no sirviera para nada.
        $script:CodigoEventos | Should -Match '\$anonimo\s*=\s*\[bool\]\$c\.ChkAnonimizar\.IsChecked'
        $script:CodigoEventos | Should -Not -Match '-Anonimo:\$true'
        $script:CodigoEventos | Should -Not -Match '-Anonimo:\$false'
    }

    It 'la ventana DICE si el informe salio anonimizado' {
        # [USO-15]: hacer el trabajo y no decirlo es, desde el lado de quien
        # mira, indistinguible de no hacerlo. Dos informes con el mismo
        # nombre y distinto contenido, sin nada que los distinga, obligan a
        # abrirlos y buscar dentro tu propio nombre de usuario.
        $script:CodigoEventos | Should -Match 'anonimizadas'
    }

    It 'la consola sigue haciendo lo mismo, y por la misma puerta' {
        $script:CodigoEntrada | Should -Match '\[switch\]\s*\$InformeAnonimo'
        $exportacionesCli = @([regex]::Matches($script:CodigoCli, 'Export-Informe(Html|Csv|Json)[^\r\n]*'))
        $exportacionesCli.Count | Should -BeGreaterOrEqual 3
        @($exportacionesCli | Where-Object { $_.Value -match '-Candidatos \$todos' -and $_.Value -notmatch '-Anonimo' }) |
            Should -BeNullOrEmpty
    }

    It 'la anonimizacion se escribe una sola vez en todo el programa' {
        # LA invariante de este punto. El dia que la ventana se escriba su
        # propio sustituidor de rutas, los dos caminos empiezan a producir
        # informes distintos, y el que se adjunta a una incidencia es el de
        # la ventana. Es exactamente [ARQ-01] con otro disfraz.
        $definiciones = 0
        foreach ($archivo in @(Get-ChildItem (Join-Path $script:Raiz 'src') -Filter '*.ps1' -Recurse)) {
            $texto = Get-CodigoSinComentarios $archivo.FullName
            $definiciones += @([regex]::Matches($texto, 'function\s+ConvertTo-RutaAnonima')).Count
        }
        $definiciones | Should -Be 1 -Because 'dos sustituidores de rutas son dos informes distintos'
    }

    It 'la ventana llega a ella por -Anonimo, no por su cuenta' {
        # La ventana no puede tocar la anonimizacion directamente: su unica
        # via es el parametro de las tres funciones de Report.ps1, que es la
        # misma que usa la consola.
        $culpables = @()
        foreach ($archivo in @(Get-ChildItem $script:CarpetaUI -Filter '*.ps1' -Recurse)) {
            $texto = Get-CodigoSinComentarios $archivo.FullName
            if ($texto -match 'ConvertTo-RutaAnonima') { $culpables += $archivo.Name }
        }
        $culpables | Should -BeNullOrEmpty -Because (
            'la interfaz pide informes anonimos, no los anonimiza ella')
    }
}

Describe 'USO-12: copiar el diagnostico' {

    It 'el boton existe en Acerca de' {
        $script:XamlAcerca | Should -Match 'x:Name="BtnCopiarDiagnostico"'
        $script:XamlAcerca | Should -Match 'Content="Copiar diagnóstico"'
    }

    It 'la ventana y la consola llaman a la MISMA funcion' {
        $script:CodigoEventos | Should -Match 'Get-InformeDiagnostico'
        $script:CodigoEntrada | Should -Match 'Get-InformeDiagnostico'
    }

    It 'lo que se copia es lo que devuelve esa funcion' {
        # Copiar otra cosa -el texto del panel de registro, por ejemplo-
        # pasaria la prueba de arriba y dejaria al usuario adjuntando algo
        # que no es el diagnostico.
        $script:CodigoEventos | Should -Match '(?s)\$diagnostico = Get-InformeDiagnostico.*Clipboard\]::SetText\(\$diagnostico\)'
    }

    It 'nadie se escribe su propio diagnostico' {
        # La cabecera del informe aparece UNA sola vez en todo el programa,
        # en Log.ps1. Si apareciera otra, habria dos diagnosticos que
        # divergirian al primer dato que se anyada a uno de los dos, y una
        # incidencia traeria mas informacion que otra segun por donde se
        # hubiera copiado.
        $cabeceras = 0
        foreach ($archivo in @(Get-ChildItem (Join-Path $script:Raiz 'src') -Filter '*.ps1' -Recurse)) {
            $texto = Get-CodigoSinComentarios $archivo.FullName
            $cabeceras += @([regex]::Matches($texto, '=== Diagnostico de Cachivache ===')).Count
        }
        $cabeceras | Should -Be 1 -Because 'el diagnostico se arma en Log.ps1 y en ningun otro sitio'
    }

    It 'se confirma que se ha copiado' {
        # Copiar al portapapeles no se ve, y desde Acerca de no se ve
        # tampoco el panel de Registro: sin confirmacion, pulsar el boton y
        # que no pase nada es indistinguible de que este roto. Ver [USO-15].
        $script:CodigoEventos | Should -Match 'portapapeles'
    }

    It 'si el portapapeles falla, se dice, y no se lleva la ventana por delante' {
        # Otro programa puede tener el portapapeles bloqueado, y entonces
        # SetText lanza. Sin try, la excepcion sale del manejador.
        $bloque = [regex]::Match($script:CodigoEventos,
            '(?s)\$c\.BtnCopiarDiagnostico\.Add_Click\(\{.*?\n    \}\)')
        $bloque.Success | Should -BeTrue -Because 'si no se encuentra el manejador, esta prueba no comprueba nada'
        $bloque.Value | Should -Match 'try'
        $bloque.Value | Should -Match 'catch'
        $bloque.Value | Should -Match 'Show-Aviso'
    }
}

Describe 'USO-12: los controles nuevos estan donde la ventana los busca' {

    <#
        Window.ps1 resuelve los controles por nombre con FindName. Un nombre
        que no este en esa lista deja $c.Loquesea a $null, y $null.Add_Click
        revienta o, peor, la asignacion se va a la nada y el control
        simplemente no responde: un boton muerto y ningun error.

        Invariantes.Tests.ps1 ya protege esto para toda la ventana. Se
        repite aqui acotado a los cuatro controles de este punto porque, si
        alguna vez alguien decide dejar de comprobarlo en general, estos
        cuatro no se van de rositas.
    #>

    BeforeAll {
        $texto = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUI 'Window.ps1')
        $script:BloqueControles = [regex]::Match($texto,
            '(?s)\$c = @\{\}.*?\$c\[\$nombre\] = \$ventana\.FindName').Value
    }

    It 'la prueba encuentra la lista: si no, no comprueba nada' {
        $script:BloqueControles.Length | Should -BeGreaterThan 500
    }

    It '<Control> esta en la lista que Window.ps1 resuelve' -ForEach @(
        @{ Control = 'ChkAnonimizar' }
        @{ Control = 'TxtActualizacion' }
        @{ Control = 'BtnBuscarActualizacion' }
        @{ Control = 'BtnIrAVersionNueva' }
        @{ Control = 'BtnCopiarDiagnostico' }
    ) {
        $script:BloqueControles | Should -Match ("'" + $Control + "'")
    }
}
