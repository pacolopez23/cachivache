<#
    Aviso de version nueva. [DIS-05].

    La comparacion de versiones es calculo puro y es donde esta todo el
    riesgo del punto: si se equivoca, el programa o no avisa NUNCA o avisa
    SIEMPRE, y las dos averias son silenciosas. No hay ninguna otra prueba
    en el proyecto que pudiera notarlas, porque las dos dan una ventana que
    abre, un analizador limpio y una suite en verde.

    La consulta a la red se prueba SIN RED a proposito. Una suite que falla
    porque el equipo esta sin conexion es una suite que la gente aprende a
    ignorar, y a partir de ahi deja de proteger tambien todo lo demas.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Version.ps1')
}

Describe 'DIS-05: ConvertTo-PartesVersion' {

    It 'lee las tres partes de una etiqueta normal' {
        (ConvertTo-PartesVersion -Etiqueta '2.1.3') -join ',' | Should -Be '2,1,3'
    }

    It 'quita la v de delante, en minuscula y en mayuscula' {
        # La publicacion se etiqueta "v2.1.0" y la version instalada es
        # "2.1.0". Sin esto no son iguales NUNCA y el aviso saltaria
        # siempre, incluso recien descargado el programa.
        (ConvertTo-PartesVersion -Etiqueta 'v2.1.0') -join ',' | Should -Be '2,1,0'
        (ConvertTo-PartesVersion -Etiqueta 'V2.1.0') -join ',' | Should -Be '2,1,0'
    }

    It 'completa con ceros las etiquetas de dos partes y de una' {
        (ConvertTo-PartesVersion -Etiqueta '2.1') -join ',' | Should -Be '2,1,0'
        (ConvertTo-PartesVersion -Etiqueta '3')   -join ',' | Should -Be '3,0,0'
    }

    It 'devuelve numeros, no texto' {
        # Si devolviera cadenas, la comparacion de mas abajo seria
        # alfabetica sin que se notara aqui.
        $partes = ConvertTo-PartesVersion -Etiqueta '2.10.0'
        $partes.Count | Should -Be 3
        $partes[1] | Should -BeOfType [int]
        $partes[1] | Should -Be 10
    }

    It 'aguanta los espacios de sobra' {
        (ConvertTo-PartesVersion -Etiqueta '  v2.1.0  ') -join ',' | Should -Be '2,1,0'
    }

    It 'no entiende <Etiqueta>, y eso es lo correcto' -ForEach @(
        @{ Etiqueta = ''            }
        @{ Etiqueta = '   '         }
        @{ Etiqueta = 'v'           }
        @{ Etiqueta = 'no-es-una-version' }
        @{ Etiqueta = '2.1.0-beta'  }
        @{ Etiqueta = '2.1.0.4'     }
        @{ Etiqueta = '2..1'        }
        @{ Etiqueta = '2.1.'        }
        @{ Etiqueta = '-1.0.0'      }
        @{ Etiqueta = '2,1,0'       }
        @{ Etiqueta = 'release-2.1.0' }
        @{ Etiqueta = '99999999999.0.0' }
    ) {
        ConvertTo-PartesVersion -Etiqueta $Etiqueta | Should -BeNullOrEmpty
    }

    It 'no revienta con nulo' {
        # [AllowNull()] en un parametro Mandatory que puede recibirlo. Aqui
        # llega de verdad: la etiqueta viene de una respuesta de red que
        # puede no traer el campo.
        { ConvertTo-PartesVersion -Etiqueta $null } | Should -Not -Throw
        ConvertTo-PartesVersion -Etiqueta $null | Should -BeNullOrEmpty
    }
}

Describe 'DIS-05: Compare-VersionCachivache' {

    It 'la 2.10.0 es MAS NUEVA que la 2.9.0' {
        # LA prueba de este punto. Alfabeticamente "2.10.0" es MENOR que
        # "2.9.0", porque el caracter 1 va antes que el 9. El dia que se
        # publique la 2.10.0, una comparacion de cadenas deja a todo el
        # mundo sin enterarse, y nada mas en el programa se entera tampoco.
        Compare-VersionCachivache -Izquierda '2.10.0' -Derecha '2.9.0' | Should -Be 1
        Compare-VersionCachivache -Izquierda '2.9.0' -Derecha '2.10.0' | Should -Be -1
    }

    It 'la 3.0.0 es mas nueva que la 2.99.99' {
        Compare-VersionCachivache -Izquierda '3.0.0' -Derecha '2.99.99' | Should -Be 1
    }

    It 'solo se mira el numero siguiente cuando hay empate' {
        Compare-VersionCachivache -Izquierda '2.1.0' -Derecha '2.0.9' | Should -Be 1
        Compare-VersionCachivache -Izquierda '2.1.1' -Derecha '2.1.0' | Should -Be 1
    }

    It 'la v de la etiqueta y los ceros que faltan no cambian nada' {
        Compare-VersionCachivache -Izquierda 'v2.0.0' -Derecha '2.0.0' | Should -Be 0
        Compare-VersionCachivache -Izquierda '2.0'    -Derecha '2.0.0' | Should -Be 0
        Compare-VersionCachivache -Izquierda '2'      -Derecha '2.0.0' | Should -Be 0
    }

    It 'devuelve nulo -no cero- cuando alguna no se entiende' {
        # Cero significaria "son la misma version", que es una afirmacion
        # que aqui no se puede hacer. Quien llama tiene que poder
        # distinguir "iguales" de "no lo se".
        Compare-VersionCachivache -Izquierda 'basura' -Derecha '2.0.0' | Should -BeNullOrEmpty
        Compare-VersionCachivache -Izquierda '2.0.0' -Derecha 'basura' | Should -BeNullOrEmpty
        Compare-VersionCachivache -Izquierda $null -Derecha $null | Should -BeNullOrEmpty
    }

    It 'no revienta con nulo' {
        { Compare-VersionCachivache -Izquierda $null -Derecha $null } | Should -Not -Throw
    }
}

Describe 'DIS-05: Test-HayVersionNueva' {

    It 'avisa cuando la publicada es mayor' {
        Test-HayVersionNueva -Instalada '2.0.0' -Publicada 'v2.1.0'  | Should -BeTrue
        Test-HayVersionNueva -Instalada '2.9.0' -Publicada 'v2.10.0' | Should -BeTrue
    }

    It 'no avisa cuando son la misma' {
        Test-HayVersionNueva -Instalada '2.0.0' -Publicada 'v2.0.0' | Should -BeFalse
        Test-HayVersionNueva -Instalada '2.0.0' -Publicada 'v2.0'   | Should -BeFalse
    }

    It 'no avisa cuando la instalada es mas nueva que la publicada' {
        # Pasa mientras se trabaja en la version siguiente sin haberla
        # publicado todavia. Avisar ahi seria mandar al usuario a
        # descargarse una version mas vieja que la que tiene.
        Test-HayVersionNueva -Instalada '2.1.0' -Publicada 'v2.0.0' | Should -BeFalse
    }

    It 'no avisa de una preversion' {
        # De una beta no se avisa: quien la quiera, la busca. Sale gratis
        # porque la etiqueta con sufijo no se entiende y ante la duda se
        # calla.
        Test-HayVersionNueva -Instalada '2.0.0' -Publicada 'v2.1.0-beta' | Should -BeFalse
    }

    It 'ante cualquier duda se calla' {
        Test-HayVersionNueva -Instalada '2.0.0' -Publicada ''       | Should -BeFalse
        Test-HayVersionNueva -Instalada '2.0.0' -Publicada 'basura' | Should -BeFalse
        Test-HayVersionNueva -Instalada 'basura' -Publicada '9.9.9' | Should -BeFalse
    }

    It 'no revienta con nulo' {
        { Test-HayVersionNueva -Instalada $null -Publicada $null } | Should -Not -Throw
        Test-HayVersionNueva -Instalada $null -Publicada $null | Should -BeFalse
    }
}

Describe 'DIS-05: Get-AvisoActualizacion' {

    It 'dice que hay una nueva, con las dos versiones' {
        $aviso = Get-AvisoActualizacion -Instalada '2.0.0' -Publicada 'v2.10.0'
        $aviso.Hay     | Should -BeTrue
        $aviso.Version | Should -Be '2.10.0'
        $aviso.Texto   | Should -Match '2\.10\.0'
        $aviso.Texto   | Should -Match '2\.0\.0'
    }

    It 'dice que estas al dia sin ofrecer descarga' {
        $aviso = Get-AvisoActualizacion -Instalada '2.0.0' -Publicada 'v2.0.0'
        $aviso.Hay   | Should -BeFalse
        $aviso.Texto | Should -Match 'al día'
    }

    It 'dice que no ha podido comprobarlo, y no lo llama estar al dia' {
        # La diferencia importa: "estas al dia" es una AFIRMACION sobre el
        # mundo, y si la consulta ha fallado no se puede hacer. Es la misma
        # familia de mentira que [CNF-04].
        $aviso = Get-AvisoActualizacion -Instalada '2.0.0' -Publicada ''
        $aviso.Hay   | Should -BeFalse
        $aviso.Texto | Should -Match 'No se ha podido comprobar'
        $aviso.Texto | Should -Not -Match 'al día'
    }

    It 'nunca ensenya en pantalla el texto que llego de la red' {
        # La etiqueta viene de una respuesta HTTP, o sea, de fuera. Lo que
        # se pinta son los numeros que se han ENTENDIDO, nunca la cadena
        # tal cual: si no se entiende, se dice que no se ha podido
        # comprobar y punto.
        $veneno = '<b>PULSA AQUI</b> http://ejemplo.no/malo'
        $aviso = Get-AvisoActualizacion -Instalada '2.0.0' -Publicada $veneno
        $aviso.Hay   | Should -BeFalse
        $aviso.Texto | Should -Not -Match 'ejemplo'
        $aviso.Texto | Should -Not -Match 'PULSA'

        # La regla, dicha como regla y no como caso: lo que sale de aqui
        # con la etiqueta de la publicacion son numeros y puntos, o nada.
        # Sin esto, la comprobacion de arriba se puede seguir pasando por
        # casualidad segun por que rama caiga el texto.
        $aviso.Version | Should -Match '^$|^[0-9]+\.[0-9]+\.[0-9]+$'
        (Get-AvisoActualizacion -Instalada '2.0.0' -Publicada 'v2.10').Version |
            Should -Match '^[0-9]+\.[0-9]+\.[0-9]+$'
    }

    It 'una version instalada que no se entiende tampoco produce aviso' {
        $aviso = Get-AvisoActualizacion -Instalada 'lo-que-sea' -Publicada 'v9.9.9'
        $aviso.Hay | Should -BeFalse
    }

    It 'no revienta con nulo' {
        { Get-AvisoActualizacion -Instalada $null -Publicada $null } | Should -Not -Throw
        (Get-AvisoActualizacion -Instalada $null -Publicada $null).Hay | Should -BeFalse
    }
}

Describe 'DIS-05: las direcciones se derivan, no se escriben aparte' {

    It 'la pagina de la ultima publicacion cuelga del repositorio' {
        Get-UrlUltimaVersion -Repositorio 'https://github.com/quien/loquesea' |
            Should -Be 'https://github.com/quien/loquesea/releases/latest'
    }

    It 'la direccion de consulta sale de la del repositorio' {
        # Escribirlas por separado son dos sitios que hay que cambiar a la
        # vez. El sintoma de olvidarse de uno es que el aviso deja de
        # funcionar, en silencio y sin que falle nada.
        Get-UrlApiUltimaVersion -Repositorio 'https://github.com/quien/loquesea' |
            Should -Be 'https://api.github.com/repos/quien/loquesea/releases/latest'
    }

    It 'la barra final y el .git no cambian el resultado' {
        Get-UrlApiUltimaVersion -Repositorio 'https://github.com/quien/loquesea/' |
            Should -Be 'https://api.github.com/repos/quien/loquesea/releases/latest'
        Get-UrlApiUltimaVersion -Repositorio 'https://github.com/quien/loquesea.git' |
            Should -Be 'https://api.github.com/repos/quien/loquesea/releases/latest'
    }

    It 'las del repositorio de verdad estan bien formadas' {
        Get-UrlUltimaVersion    | Should -Match '^https://github\.com/[^/]+/[^/]+/releases/latest$'
        Get-UrlApiUltimaVersion | Should -Match '^https://api\.github\.com/repos/[^/]+/[^/]+/releases/latest$'
    }

    It 'una direccion que no es de GitHub no produce ninguna consulta' {
        # Cadena vacia, y Get-UltimaVersionPublicada no llega a abrir nada.
        Get-UrlApiUltimaVersion -Repositorio 'https://otro-sitio.example/quien/que' | Should -BeNullOrEmpty
        Get-UrlApiUltimaVersion -Repositorio 'https://github.com/solo-un-tramo'     | Should -BeNullOrEmpty
        Get-UrlApiUltimaVersion -Repositorio ''                                     | Should -BeNullOrEmpty
    }
}

Describe 'DIS-05: la consulta falla hacia dentro, nunca hacia el usuario' {

    <#
        Ninguna de estas pruebas toca la red. La primera ni siquiera abre un
        socket: la direccion no es una direccion, asi que revienta antes de
        salir del proceso. Es a proposito, para que esto siga probando lo
        mismo en un equipo sin conexion.
    #>

    It 'una direccion imposible no lanza y devuelve cadena vacia' {
        { Get-UltimaVersionPublicada -Url 'esto no es una direccion' -TiempoEspera 1 } | Should -Not -Throw
        Get-UltimaVersionPublicada -Url 'esto no es una direccion' -TiempoEspera 1 | Should -BeNullOrEmpty
    }

    It 'sin direccion no consulta nada' {
        Get-UltimaVersionPublicada -Url '' -TiempoEspera 1 | Should -BeNullOrEmpty
    }

    It 'devuelve texto, para que quien llama no tenga que mirar el tipo' {
        (Get-UltimaVersionPublicada -Url '' -TiempoEspera 1) | Should -BeOfType [string]
    }
}

Describe 'DIS-05: la ventana no decide por su cuenta lo que dice el panel' {

    <#
        La invariante del punto. La regla del proyecto es que la decision
        vive en una funcion pura y que dos sitios no pueden decidir lo
        mismo por separado; aqui hace ademas de red de seguridad de algo
        que no se puede ejecutar en este entorno, porque no hay WPF.

        Si manyana alguien compara versiones dentro del manejador del boton
        -con un -ne, o con un -lt sobre cadenas- todo seguiria pareciendo
        correcto: la ventana abriria, el analizador estaria limpio y las
        pruebas de arriba seguirian en verde probando una funcion que ya no
        usa nadie.
    #>

    BeforeAll {
        $script:CarpetaUI = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'
        $script:TextoEventos = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUI 'Window.Eventos.ps1')

        # Sin comentarios: una prueba de texto que busca en el codigo
        # encuentra tus propios comentarios, y en este repositorio ha
        # pasado seis veces. Justo encima de estas lineas hay comentarios
        # que hablan de comparar versiones.
        $script:CodigoEventos = ($script:TextoEventos -replace '(?s)<#.*?#>', '' -replace '(?m)^\s*#.*$', '')
    }

    It 'la prueba encuentra el codigo: si no, no comprueba nada' {
        $script:CodigoEventos.Length | Should -BeGreaterThan 10000
        $script:CodigoEventos | Should -Match 'BtnBuscarActualizacion'
    }

    It 'el panel se pinta con lo que devuelve Get-AvisoActualizacion' {
        $script:CodigoEventos | Should -Match 'Get-AvisoActualizacion'
        $script:CodigoEventos | Should -Match '\$c\.TxtActualizacion\.Text\s*=\s*\$aviso\.Texto'
        $script:CodigoEventos | Should -Match '\$c\.BtnIrAVersionNueva\.Visibility\s*=\s*if\s*\(\$aviso\.Hay\)'
    }

    It 'la ventana no compara versiones a mano en ningun sitio' {
        # Cualquier comparacion contra la version del programa que no pase
        # por las funciones de Version.ps1.
        $sospechosas = @([regex]::Matches($script:CodigoEventos,
            '\$script:VersionCachivache\s*-(eq|ne|lt|gt|le|ge)\b'))
        $sospechosas.Count | Should -Be 0 -Because (
            'comparar versiones es lo unico dificil de este punto y esta resuelto en una funcion pura')
    }

    It 'la consulta a la red no ocurre en el hilo de la interfaz' {
        # Get-UltimaVersionPublicada no puede aparecer llamada a secas: va
        # dentro del guion que se ejecuta en el runspace. Llamada desde el
        # manejador congelaria la ventana hasta seis segundos, con Windows
        # pintandola en blanco y "no responde" en el titulo.
        $script:CodigoEventos | Should -Match "(?s)\`$codigoVersion = @'.*Get-UltimaVersionPublicada.*'@"
        $script:CodigoEventos | Should -Match 'BeginInvoke'
        $script:CodigoEventos | Should -Match 'DispatcherTimer'

        # Y aparece UNA sola vez: la del guion del runspace. Cualquier otra
        # es una llamada sincrona en el hilo de la interfaz.
        @([regex]::Matches($script:CodigoEventos, 'Get-UltimaVersionPublicada')).Count |
            Should -Be 1 -Because 'la unica llamada esta dentro del guion que corre en el runspace'
    }

    It 'la consulta no se lanza sola: hace falta pulsar el boton' {
        # La promesa de privacidad del programa depende de esto. Si algun
        # dia esto se llamara desde el arranque o desde $mostrarPanel, el
        # programa se conectaria a un tercero sin que nadie lo pidiera.
        $lanzamientos = @([regex]::Matches($script:CodigoEventos, 'TemporizadorVersion\.Start\(\)'))
        $lanzamientos.Count | Should -Be 1 -Because 'solo el boton de Acerca de puede empezar una consulta'

        $ayudantes = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUI 'Window.Ayudantes.ps1')
        $ayudantes | Should -Not -Match 'Get-UltimaVersionPublicada'
        $ventana = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUI 'Window.ps1')
        $ventana | Should -Not -Match 'Get-UltimaVersionPublicada'
    }

    It 'Version.ps1 es el unico archivo del programa que abre una conexion' {
        # El programa entero tiene UNA sola puerta a la red, y esta
        # aislada en una funcion que no lanza. Si aparece otra, hay que
        # decidirlo otra vez, no heredarlo.
        $raiz = Split-Path $PSScriptRoot -Parent
        $culpables = @()
        foreach ($archivo in @(Get-ChildItem (Join-Path $raiz 'src') -Filter '*.ps1' -Recurse)) {
            if ($archivo.Name -eq 'Version.ps1') { continue }
            $texto = Get-Content -Raw -LiteralPath $archivo.FullName
            $texto = ($texto -replace '(?s)<#.*?#>', '' -replace '(?m)^\s*#.*$', '')
            if ($texto -match 'Invoke-RestMethod|Invoke-WebRequest|System\.Net\.WebClient|HttpClient') {
                $culpables += $archivo.Name
            }
        }
        $culpables | Should -BeNullOrEmpty -Because 'la unica conexion del programa vive en Get-UltimaVersionPublicada'
    }
}
