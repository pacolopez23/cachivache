<#
    Pruebas de [USO-06] (menu contextual y doble clic) y [USO-13] (ocultar
    lo ya eliminado).

    Las dos cosas viven en la tabla de Resultados, y las dos tienen el
    mismo problema de fondo: aqui no arranca WPF, asi que ni el menu ni la
    casilla se pueden pulsar en ninguna prueba. Lo que SI se puede hacer es
    lo que este proyecto lleva haciendo desde [USO-04]: sacar la decision
    del XAML y meterla en algo que se puede leer -una propiedad de
    ItemVista, un cierre de la ventana- y despues atar por texto que la
    ventana no vuelva a decidirlo por su cuenta.

    Las tres decisiones que se protegen aqui:

      1. La clave de exclusion se COPIA del candidato, nunca se recalcula
         en la ventana. Dos sitios calculando la misma clave es como se
         llega a excluir una cosa y comparar otra.
      2. "Copiar ruta" no copia una etiqueta. El portapapeles no dice de
         donde salio lo que lleva dentro.
      3. Lo que se esconde en [USO-13] es lo que se borro BIEN. Un fallo
         se ve siempre, que es lo que dejo escrito [USO-02].

    Toda prueba de texto lleva su guarda previa: si no encuentra lo que
    busca, lo dice en vez de pasar celebrando que no hay nada mal.
#>

BeforeAll {
    $script:Raiz      = Split-Path $PSScriptRoot -Parent
    $script:CarpetaUi = Join-Path (Join-Path $script:Raiz 'src') 'UI'

    . (Join-Path $script:CarpetaUi 'Types.ps1')
    Initialize-TiposInterfaz

    # El nucleo entero: hacen falta Get-ClaveExclusion y Test-ClaveExcluida,
    # que son las funciones contra las que se comparan las decisiones de la
    # ventana. Es como carga Contrato.Tests.ps1.
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Codigo sin comentarios. Se quitan los de linea (#), los bloques
    # (<# #>) y ADEMAS los de C# (///), porque ItemVista es C# dentro de
    # una cadena de Types.ps1 y sus comentarios nombran a Get-ClaveExclusion
    # constantemente: sin quitarlos, la prueba de "la ventana no recalcula
    # la clave" fallaria contra la explicacion de por que no la recalcula.
    # Es la trampa que el relevo dice que ha mordido seis veces.
    function Get-CodigoSinComentarios {
        param([string] $Ruta)
        $lineas = @(Get-Content -LiteralPath $Ruta |
                    Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*///' })
        return [regex]::Replace(($lineas -join "`n"), '(?s)<#.*?#>', '')
    }

    $script:Eventos     = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Eventos.ps1')
    $script:Ayudantes   = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Ayudantes.ps1')
    $script:Analisis    = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Analisis.ps1')
    $script:Eliminacion = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Eliminacion.ps1')
    $script:Ventana     = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.ps1')

    # El XAML del panel, sin sus comentarios por el mismo motivo.
    $script:Panel = [regex]::Replace(
        (Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUi 'Panel.Resultados.xaml')),
        '(?s)<!--.*?-->', '')

    # Cada manejador del menu, acotado. Terminan todos en una linea de
    # ocho espacios y "})", que es la sangria en la que viven dentro del
    # bloque que comprueba que el menu existe.
    function Get-BloqueManejador {
        param([string] $Nombre)
        return [regex]::Match($script:Eventos,
            ('(?s)\$c\.{0}\.Add_Click\(\{{.*?\n        \}}\)' -f [regex]::Escape($Nombre))).Value
    }
}

Describe 'USO-06: la clave de exclusion viaja pegada a la fila' {

    <#
        Lo dejo escrito [ARQ-03] al cerrarse, dentro de la lista de campos
        que no van a la fila: "OJO SI SE HACE [USO-06]: hay que llevar esta
        clave a ItemVista, NO reconstruirla en la ventana".

        El motivo no es de estilo. Get-ClaveExclusion decide entre dos
        formas -la ruta cuando la hay, y una cadena sintetica cuando no- y
        esa regla ya se equivoco una vez: la primera version daba por ruta
        solo "C:\" y "\\", y la suite corre en Linux, asi que una ruta de
        verdad pasaba por etiqueta y la exclusion del usuario dejaba de
        aplicarse. Una segunda copia de esa regla en la ventana volveria a
        poder equivocarse sola.
    #>

    It 'la prueba lee los archivos: si no, no comprueba nada' {
        $script:Analisis.Length | Should -BeGreaterThan 2000
        $script:Eventos.Length  | Should -BeGreaterThan 2000
        Get-Command Get-ClaveExclusion -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'ItemVista declara la clave y la pregunta que se le hace' {
        $props = @([Cachivache.ItemVista].GetProperties() | ForEach-Object { $_.Name })
        $props | Should -Contain 'ClaveExclusion'
        $props | Should -Contain 'TieneRutaReal'
    }

    It 'la fila la copia del candidato, tal cual' {
        $script:Analisis | Should -Match '\$item\.ClaveExclusion = \$candidato\.ClaveExclusion'
    }

    It 'ningun archivo de la interfaz vuelve a calcularla' {
        # La prueba de verdad de este punto. Si la ventana llamara a
        # Get-ClaveExclusion por su cuenta, habria dos sitios decidiendo la
        # misma clave y podrian discrepar sin que nada fallara: se
        # excluiria una cosa y se compararia otra.
        $culpables = @()
        foreach ($archivo in (Get-ChildItem $script:CarpetaUi -Filter '*.ps1')) {
            $codigo = Get-CodigoSinComentarios $archivo.FullName
            if ($codigo -match 'Get-ClaveExclusion') { $culpables += $archivo.Name }
        }
        $culpables | Should -BeNullOrEmpty -Because (
            'la clave la decide el nucleo al nacer el candidato y viaja en la fila: ' +
            'recalcularla aqui es un segundo sitio que puede equivocarse solo')
    }

    It 'TieneRutaReal contesta lo mismo que decidio Get-ClaveExclusion' -ForEach @(
        @{ Ruta = 'C:\Users\ana\AppData\Local\Temp'; Real = $true  }
        @{ Ruta = 'D:/Proyectos/web';               Real = $true  }
        @{ Ruta = '\\servidor\datos\copias';        Real = $true  }
        @{ Ruta = '/tmp/basura';                    Real = $true  }
        @{ Ruta = 'docker system prune -a -f';      Real = $false }
        @{ Ruta = 'Papelera de reciclaje';          Real = $false }
        @{ Ruta = '';                               Real = $false }
    ) {
        # No se escribe la clave a mano: se pide a la funcion del nucleo,
        # que es justo lo que hace el candidato de verdad. Asi, el dia que
        # esa regla cambie, esta prueba cambia con ella en vez de quedarse
        # comprobando una copia vieja.
        $item = [Cachivache.ItemVista]::new()
        $item.Ruta = $Ruta
        $item.ClaveExclusion = Get-ClaveExclusion -Ruta $Ruta -ModuloId 'modulo' -Nombre 'Nombre'

        $item.TieneRutaReal | Should -Be $Real
    }

    It 'sin clave no hay ruta real: no se inventa una' {
        # Una fila construida a medias no puede colar una etiqueta como
        # ruta solo porque nadie le puso la clave.
        $item = [Cachivache.ItemVista]::new()
        $item.Ruta = 'C:\Windows'
        $item.TieneRutaReal | Should -BeFalse
    }

    It 'no revienta con nulos por ningun lado' {
        $item = [Cachivache.ItemVista]::new()
        { $item.TieneRutaReal } | Should -Not -Throw
        $item.TieneRutaReal | Should -BeFalse
        $item.Ruta = '   '
        $item.ClaveExclusion = '   '
        $item.TieneRutaReal | Should -BeFalse -Because 'tres espacios no son una ruta'
    }
}

Describe 'USO-06: el menu contextual esta declarado y enganchado' {

    BeforeAll {
        $script:Entradas = @('MenuAbrirUbicacion', 'MenuCopiarRuta',
                             'MenuExcluirSiempre', 'MenuDesmarcarGrupo')
        $script:BloqueMenu = [regex]::Match($script:Panel,
            '(?s)<DataGrid\.ContextMenu>.*?</DataGrid\.ContextMenu>').Value
    }

    It 'el menu esta en el panel: si no, esta prueba no mira nada' {
        $script:BloqueMenu | Should -Not -BeNullOrEmpty
        @([regex]::Matches($script:BloqueMenu, '<MenuItem ')).Count |
            Should -Be 4 -Because 'la hoja de ruta pide cuatro ordenes'
    }

    It 'cuelga de la tabla, que es lo que permite darles nombre' {
        # Dentro del estilo de fila los MenuItem nacen y mueren con el
        # panel virtualizado y FindName no los encuentra: habria que
        # repetir el apanyo de la cabecera de grupo.
        $script:Panel | Should -Match '(?s)<DataGrid x:Name="TablaResultados".*?<DataGrid\.ContextMenu>'
    }

    It 'la orden <Entrada> existe con su rotulo' -ForEach @(
        @{ Entrada = 'MenuAbrirUbicacion'; Rotulo = 'Abrir ubicación' }
        @{ Entrada = 'MenuCopiarRuta';     Rotulo = 'Copiar ruta' }
        @{ Entrada = 'MenuExcluirSiempre'; Rotulo = 'Excluir siempre esto' }
        @{ Entrada = 'MenuDesmarcarGrupo'; Rotulo = 'Desmarcar el grupo' }
    ) {
        # El rotulo con sus tildes: es texto que lee el usuario. Ver
        # [I18N-01].
        $script:BloqueMenu | Should -Match ('x:Name="{0}" Header="{1}"' -f $Entrada, [regex]::Escape($Rotulo))
    }

    It 'ni un disparador ni un conversor deciden nada dentro del menu' {
        # La regla de [USO-04]: aqui no hay WPF, asi que un mecanismo de
        # XAML que no se puede ejecutar no se puede verificar.
        $script:BloqueMenu | Should -Not -Match 'DataTrigger'
        $script:BloqueMenu | Should -Not -Match '<Style'
        $script:BloqueMenu | Should -Not -Match 'Converter='
    }

    It 'la entrada <Entrada> la resuelve Window.ps1 y la engancha la ventana' -ForEach @(
        @{ Entrada = 'MenuAbrirUbicacion' }
        @{ Entrada = 'MenuCopiarRuta' }
        @{ Entrada = 'MenuExcluirSiempre' }
        @{ Entrada = 'MenuDesmarcarGrupo' }
    ) {
        # Un nombre fuera de la lista de $c deja el control a $null y el
        # menu no responde, sin un solo error.
        $script:Ventana | Should -Match ("'{0}'" -f $Entrada)
        $script:Eventos | Should -Match ('\$c\.{0}\.Add_Click' -f $Entrada)
    }

    It 'si el XAML no trajera el menu, la ventana sigue abriendo' {
        # FindName devuelve $null sin quejarse y $null.Add_Click() SI
        # lanza: sin esta comprobacion se perderia el programa entero por
        # un menu contextual. Es lo mismo que hace el cartel de [USO-09].
        $script:Eventos | Should -Match '\$faltanMenuFila'
        $script:Eventos | Should -Match "(?s)\`$faltanMenuFila.*?Where-Object \{ \`$null -eq \`$c\[\`$_\] \}"
    }
}

Describe 'USO-06: abrir la ubicacion se decide en un solo sitio' {

    BeforeAll {
        # El manejador del doble clic, ACOTADO. La primera version de estas
        # dos pruebas buscaba "Add_MouseDoubleClick.*?abrirUbicacion" sobre
        # el archivo entero, y con "(?s)" ese ".*?" se comia media ventana
        # hasta encontrar la llamada del MENU: quitar la llamada del doble
        # clic no hacia fallar nada. Lo cazo la mutacion, que es para lo
        # que esta.
        $script:DobleClic = [regex]::Match($script:Eventos,
            '(?s)Add_MouseDoubleClick\(\{.*?\n    \}\)').Value
    }

    It 'existe el cierre y se encuentra el doble clic: si no, esto no mira nada' {
        $script:Ayudantes  | Should -Match '\$abrirUbicacion = \{'
        $script:DobleClic  | Should -Not -BeNullOrEmpty
        $script:DobleClic.Length | Should -BeLessThan 400 -Because 'si abarca medio archivo, no esta acotado'
    }

    It 'los tres caminos llaman al mismo cierre' {
        # El boton de la barra, la orden del menu y el doble clic. Tres
        # copias del mismo codigo divergen, y divergir aqui significa que
        # el doble clic abriria algo que el boton rechaza. Es [ARQ-01].
        $script:Eventos   | Should -Match '\$c\.BtnAbrirCarpeta\.Add_Click\(\{ & \$abrirUbicacion'
        $script:Eventos   | Should -Match '\$c\.MenuAbrirUbicacion\.Add_Click\(\{ & \$abrirUbicacion'
        $script:DobleClic | Should -Match '& \$abrirUbicacion'
    }

    It 'solo hay un sitio en toda la interfaz que abra la carpeta de una fila' {
        # Preguntar si la ruta es carpeta o archivo es la firma de "abrir
        # la ubicacion de esto": es lo que decide entre abrir la carpeta y
        # ensenyar el archivo dentro de ella. Si apareciera dos veces,
        # habria vuelto a haber dos copias de esa decision y de la
        # comprobacion de seguridad que la precede.
        #
        # No se cuenta "/select," porque tambien lo usa el guardado de
        # informes, que abre un archivo que acaba de escribir el propio
        # programa y no una ruta elegida en la tabla.
        $veces = 0
        foreach ($archivo in (Get-ChildItem $script:CarpetaUi -Filter '*.ps1')) {
            $codigo = Get-CodigoSinComentarios $archivo.FullName
            $veces += @([regex]::Matches($codigo, 'PSIsContainer')).Count
        }
        $veces | Should -Be 1
    }

    It 'no abre el archivo: lo ensenya en su carpeta' {
        # Abrir el archivo seria EJECUTAR algo que el programa acaba de
        # proponer borrar. Un doble clic no puede dar esa sorpresa.
        $cierre = [regex]::Match($script:Ayudantes, '(?s)\$abrirUbicacion = \{.*?\n    \}').Value
        $cierre | Should -Not -BeNullOrEmpty
        $cierre | Should -Match 'Get-RutaExplorador'
        $cierre | Should -Not -Match 'Start-Process -FilePath \$ruta'
    }

    It 'el doble clic sin fila elegida no dice nada' {
        # El doble clic tambien cae sobre la cabecera -donde ya ordena- y
        # sobre el hueco de debajo de la ultima fila. Un cuadro de dialogo
        # ahi seria un aviso por accidente.
        $script:DobleClic | Should -Match 'if \(\$null -eq \$item\) \{ return \}'
        $script:DobleClic | Should -Not -Match 'Show-Aviso'
    }

    It 'la ruta que no existe y la que no es ruta dicen cosas distintas' {
        $cierre = [regex]::Match($script:Ayudantes, '(?s)\$abrirUbicacion = \{.*?\n    \}').Value
        $cierre | Should -Match 'TieneRutaReal'
        $cierre | Should -Match 'Ya no existe'
    }
}

Describe 'USO-06: copiar ruta no deja una etiqueta en el portapapeles' {

    <#
        La decision del punto, y va escrita aqui porque no se puede leer en
        ninguna otra parte: cuando el elemento no tiene ruta de verdad -un
        comando del sistema, la papelera-, NO SE COPIA NADA.

        Copiar la etiqueta dejaria en el portapapeles algo que parece una
        ruta y no lo es. El portapapeles no dice de donde salio lo que
        lleva dentro, asi que quien lo pegue se entera en otro programa,
        mas tarde y sin ninguna pista. Y lo unico util que habria ahi -el
        comando- ya se ve entero en la propia fila, porque SECURITY.md
        exige ensenyarlo.

        Callarse tampoco vale: se dice que no hay ruta y por que.
    #>

    BeforeAll {
        $script:Copiar = Get-BloqueManejador 'MenuCopiarRuta'
    }

    It 'el manejador esta ahi: si no, esta prueba no mira nada' {
        $script:Copiar | Should -Not -BeNullOrEmpty
        $script:Copiar.Length | Should -BeGreaterThan 300
        $script:Copiar | Should -Match 'Clipboard'
    }

    It 'solo copia cuando hay una ruta de verdad' {
        $script:Copiar | Should -Match 'if \(-not \$item\.TieneRutaReal\)'
        $script:Copiar | Should -Match 'SetText\(\$item\.Ruta\)'
    }

    It 'la comprobacion va ANTES de tocar el portapapeles, y corta' {
        # Si la guarda estuviera despues, o no cortara, la etiqueta habria
        # entrado igual: el portapapeles no se puede deshacer.
        $iGuarda = $script:Copiar.IndexOf('TieneRutaReal')
        $iCopia  = $script:Copiar.IndexOf('SetText')
        $iGuarda | Should -BeGreaterThan -1
        $iCopia  | Should -BeGreaterThan $iGuarda

        $guarda = $script:Copiar.Substring($iGuarda, $iCopia - $iGuarda)
        $guarda | Should -Match 'return'
        $guarda | Should -Match 'No se ha copiado nada'
    }

    It 'el portapapeles se toca UNA sola vez en el manejador' {
        @([regex]::Matches($script:Copiar, 'SetText')).Count | Should -Be 1
    }

    It 'el motivo se explica con la misma frase que "abrir ubicación"' {
        # Si una lo llamara comando y la otra etiqueta, el usuario creeria
        # que son dos casos distintos.
        $script:Copiar    | Should -Match '& \$describirSinRuta'
        $script:Ayudantes | Should -Match '\$describirSinRuta = \{'
    }

    It 'copiar bien no abre un cuadro de dialogo' {
        # Copiar es frecuente y de riesgo cero, y quien lo pide pega justo
        # despues, que es donde lo comprueba. Al registro si va.
        $script:Copiar | Should -Match '& \$escribir'
    }
}

Describe 'USO-06: excluir siempre usa el camino de CNF-01, no uno nuevo' {

    BeforeAll {
        $script:Excluir = Get-BloqueManejador 'MenuExcluirSiempre'
    }

    It 'el manejador esta ahi: si no, esta prueba no mira nada' {
        $script:Excluir | Should -Not -BeNullOrEmpty
        $script:Excluir.Length | Should -BeGreaterThan 800
    }

    It 'guarda la clave de la fila, no una recompuesta' {
        $script:Excluir | Should -Match '\$item\.ClaveExclusion'
    }

    It 'la lista es la de las preferencias, que es donde vive desde CNF-01' {
        $script:Excluir | Should -Match '\$estado\.Preferencias\.RutasExcluidas ='
    }

    It 'y tambien la copia que miran el embudo y el motor de borrado' {
        # Las dos, porque solo se sincronizan al refrescar los discos: sin
        # esta linea la exclusion no valdria para la limpieza que el
        # usuario esta a punto de lanzar.
        $script:Excluir | Should -Match '\$estado\.Configuracion\.RutasExcluidas ='
    }

    It 'se guarda en disco al momento, no al cerrar la ventana' {
        # Lo que esto promete es "nunca mas". Un cierre anormal que se
        # llevara la exclusion por delante seria justo la promesa
        # incumplida que [CNF-01] vino a arreglar.
        $script:Excluir | Should -Match '& \$guardarPreferencias'
    }

    It 'pregunta antes: hoy esto no se puede deshacer desde la ventana' {
        $script:Excluir | Should -Match "MessageBox\]::Show\(\`$pregunta"
        $script:Excluir | Should -Match "'YesNo'"
        $script:Excluir | Should -Match "-ne 'Yes'\) \{ return \}"
    }

    It 'la pregunta nombra el elemento y ensenya la clave que se guarda' {
        # El menu actua sobre la fila SELECCIONADA. Nombrarla convierte un
        # "se abrio el menu sobre otra fila" en algo que se ve antes de que
        # pase, y no en una exclusion silenciosa de lo que no era.
        $script:Excluir | Should -Match '\$pregunta = \('
        $script:Excluir | Should -Match 'Se guarda esta clave'
        $script:Excluir | Should -Match '-f \$item\.Nombre, \$clave'
    }

    It 'pregunta si ya estaba excluido con la MISMA funcion que el motor' {
        # Con -contains diria "no estaba" de una carpeta hija de otra ya
        # excluida, y luego el motor la rechazaria igual.
        $script:Excluir | Should -Match 'Test-ClaveExcluida -Clave \$clave'
        $script:Excluir | Should -Not -Match '\$excluidas -contains'
    }

    It 'desmarca al momento lo que la exclusion cubre, con esa misma funcion' {
        # Sin esto la fila seguiria marcada, la limpieza intentaria
        # borrarla y el motor la rechazaria con un error en rojo: el
        # programa discutiendo consigo mismo delante del usuario.
        $script:Excluir | Should -Match 'Test-ClaveExcluida -Clave \$fila\.ClaveExclusion'
        $script:Excluir | Should -Match '\$fila\.Seleccionado = \$false'
        $script:Excluir | Should -Match '\$estado\.SuprimirResumen = \$true'
        $script:Excluir | Should -Match '& \$actualizarResumenSeleccion'
    }

    It 'no dice "1 elementos"' {
        # La cuenta de lo desmarcado tiene sus tres casos. Es el fallo que
        # ya salio en las cabeceras de grupo y en el historial.
        $script:Excluir | Should -Match '\$desmarcados -eq 0'
        $script:Excluir | Should -Match '\$desmarcados -eq 1'
    }

    It 'la exclusion que se guarda es la que compara el nucleo' {
        # Comprobacion de verdad, no de texto: se hace el mismo recorrido
        # que hace la ventana -clave del candidato, lista de preferencias,
        # Test-ClaveExcluida- para las dos formas de clave.
        $carpeta = Get-ClaveExclusion -Ruta 'C:\Proyectos\web' -ModuloId 'proyectos' -Nombre 'web'
        Test-ClaveExcluida -Clave $carpeta -Excluidas @($carpeta) | Should -BeTrue
        Test-ClaveExcluida -Clave 'C:\Proyectos\web\node_modules' -Excluidas @($carpeta) |
            Should -BeTrue -Because 'excluir una carpeta excluye lo que cuelga de ella'

        $comando = Get-ClaveExclusion -Ruta 'docker system prune -a -f' -ModuloId 'dockerwsl' -Nombre 'Cache de Docker'
        Test-ClaveExcluida -Clave $comando -Excluidas @($comando) | Should -BeTrue
        Test-ClaveExcluida -Clave 'C:\Proyectos\web' -Excluidas @($comando) |
            Should -BeFalse -Because 'una etiqueta no puede alcanzar a una carpeta'
    }
}

Describe 'USO-06: desmarcar el grupo es el mismo cierre que el boton de la cabecera' {

    It 'existe el cierre y lo llaman los dos' {
        $script:Eventos | Should -Match '\$marcarCategoria = \{'
        $script:Eventos | Should -Match '& \$marcarCategoria \$categoria \$marcar'
        $script:Eventos | Should -Match '& \$marcarCategoria \$item\.Categoria \$false'
    }

    It 'solo hay UN bucle que marque una categoria entera' {
        # Dos copias divergen: es [ARQ-01], que en este proyecto ya paso
        # con el bucle de borrado.
        @([regex]::Matches($script:Eventos, '\$item\.Seleccionado = \$Marcar')).Count | Should -Be 1

        # Y el manejador de los botones de la cabecera ya no recorre nada
        # por su cuenta: delega. Si volviera a tener su propio bucle,
        # habria dos sitios que pueden dejar de parecerse.
        $handler = [regex]::Match($script:Eventos,
            '(?s)\$c\.TablaResultados\.AddHandler\(.*?\n        \}\)').Value
        $handler | Should -Not -BeNullOrEmpty
        $handler | Should -Not -Match 'foreach'
        $handler | Should -Match '& \$marcarCategoria'
    }

    It 'el menu no puede marcar, solo desmarcar' {
        # Marcar una categoria entera desde el menu contextual seria marcar
        # a ciegas cosas que no se estan viendo. Desmarcar nunca hace danyo.
        $bloque = Get-BloqueManejador 'MenuDesmarcarGrupo'
        $bloque | Should -Not -BeNullOrEmpty
        $bloque | Should -Not -Match '\$true'
    }
}

Describe 'USO-13: ocultar lo ya eliminado esconde lo que se borro BIEN' {

    <#
        La decision del punto, tambien escrita aqui:

        ES UNA CASILLA Y NO ALGO AUTOMATICO. Esconder el resultado de la
        limpieza justo cuando el usuario acaba de pulsar el boton y va a
        mirar que ha pasado es hacer el trabajo y no decirlo, que es
        [USO-15] otra vez. Asi el resultado se ve siempre y esconderlo es
        una decision suya, reversible con un clic.

        Y SE OCULTA POR Hecho. Es la bandera que la ventana levanta SOLO
        cuando el elemento se borro de verdad; un fallo se queda con Hecho
        a falso y su texto en Estado, en rojo. Lo que fallo es lo unico que
        todavia se puede arreglar y reintentar: esconderlo seria dar por
        limpiado algo que sigue en el disco. Ver [USO-02].
    #>

    It 'la casilla esta en el panel: si no, esta prueba no mira nada' {
        $script:Panel | Should -Match '<CheckBox x:Name="ChkOcultarHechos"'
        $script:Panel | Should -Match 'Content="Ocultar lo ya eliminado"'
    }

    It 'nace desmarcada' {
        # Nacer marcada escondería el resultado de la limpieza anterior sin
        # que nadie lo hubiera pedido.
        $elemento = [regex]::Match($script:Panel, '(?s)<CheckBox x:Name="ChkOcultarHechos".*?/>').Value
        $elemento | Should -Not -BeNullOrEmpty
        $elemento | Should -Not -Match 'IsChecked'
    }

    It 'la casilla usa Checked y Unchecked, nunca Click' {
        # Click solo se levanta cuando pulsa el usuario: si algun dia el
        # codigo mueve la casilla, la tabla quedaria filtrada de una forma
        # y la casilla diciendo otra.
        $script:Eventos | Should -Match '\$c\.ChkOcultarHechos\.Add_Checked'
        $script:Eventos | Should -Match '\$c\.ChkOcultarHechos\.Add_Unchecked'
        $script:Eventos | Should -Not -Match '\$c\.ChkOcultarHechos\.Add_Click'
    }

    It 'tocarla vuelve a filtrar la tabla' {
        $script:Eventos | Should -Match '\$sincronizarOcultarHechos = \{ & \$aplicarFiltro \}'
    }

    It 'el predicado esconde por Hecho' {
        $script:Ayudantes | Should -Match '\$ocultarHechos = \[bool\]\$c\.ChkOcultarHechos\.IsChecked'
        $script:Ayudantes | Should -Match 'if \(\$ocultarHechos -and \$item\.Hecho\) \{ return \$false \}'
    }

    It 'y NUNCA por el estado, que es donde vive el fallo' {
        # La mutacion que esta prueba tiene que cazar es cambiar Hecho por
        # EstadoEsFallo o por Estado en la linea de arriba: escondería
        # justo lo unico que hay que mirar.
        $filtro = [regex]::Match($script:Ayudantes,
            '(?s)\$estado\.Vista\.Filter = \[Predicate\[object\]\] \{.*?\}\.GetNewClosure\(\)').Value
        $filtro | Should -Not -BeNullOrEmpty
        $filtro | Should -Match '\$item\.Hecho'
        $filtro | Should -Not -Match 'EstadoEsFallo'
        $filtro | Should -Not -Match '\$item\.Estado'
    }

    It 'un fallo NUNCA puede estar hecho, asi que no se puede esconder' {
        # La otra mitad de la regla, comprobada sobre la clase y no sobre
        # el texto: si la fila dice que algo fallo, Hecho es falso, y el
        # predicado de arriba solo esconde lo que tiene Hecho.
        foreach ($hecho in @($true, $false)) {
            foreach ($estado in @('', 'Eliminado', 'No se ha podido borrar: en uso')) {
                $item = [Cachivache.ItemVista]::new()
                $item.Hecho  = $hecho
                $item.Estado = $estado
                if ($item.EstadoEsFallo) {
                    $item.Hecho | Should -BeFalse -Because 'un fallo no esta hecho, y solo se esconde lo hecho'
                }
            }
        }
    }

    It 'Hecho significa "se borro de verdad", y lo pone la eliminacion' {
        # De esto depende todo lo anterior: si Hecho se levantara tambien
        # con un fallo, esconder por Hecho escondería fallos.
        $script:Eliminacion | Should -Match '\$item\.Hecho = \[bool\]\$item\.Origen\.Hecho'
        $script:Eliminacion | Should -Match 'if \(\$item\.Origen\.Hecho\) \{ \$item\.Seleccionado = \$false \}'
    }

    It 'la casilla no cuenta como filtro de busqueda' {
        # Test-HayFiltroPuesto contesta "hay un filtro de busqueda puesto",
        # y de esa respuesta depende el rotulo del boton del cartel de
        # tabla vacia ("Quitar el filtro de texto"). Si la casilla contara,
        # ese boton prometeria quitar algo que no quita.
        $script:Ayudantes | Should -Match (
            '-not \(Test-HayFiltroPuesto -TextoFiltro \$texto -RiesgoFiltro \$riesgo\) -and -not \$ocultarHechos')
        # "[^)]*" se para en el parentesis que cierra la llamada, asi que
        # esto mira DENTRO de los argumentos y no en la condicion entera.
        $script:Ayudantes | Should -Not -Match 'Test-HayFiltroPuesto[^)]*\$ocultarHechos'
    }

    It 'con la casilla puesta si hay predicado, aunque no haya filtro de texto' {
        # Sin esto la casilla no haria nada mientras no hubiera ademas un
        # filtro escrito: un control que se marca y no cambia nada es
        # indistinguible de uno roto.
        $bloque = [regex]::Match($script:Ayudantes,
            '(?s)\$ocultarHechos = \[bool\].*?\$estado\.Vista\.Filter = \[Predicate').Value
        $bloque | Should -Not -BeNullOrEmpty
        $bloque | Should -Match '\$estado\.Vista\.Filter = \$null'
    }
}
