<#
    SIETE FUNCIONES QUE NINGUNA PRUEBA NOMBRABA.

    Salen de tests/datos/deuda-de-pruebas.txt, que es la lista de lo que
    queda por hacer. Estan juntas aqui porque comparten una forma: todas
    son la pieza pequenya de la que depende algo grande -el motor de
    borrado, el informe HTML, las preferencias que sobreviven al
    reinicio- y ninguna la miraba nadie.

    DOS DE ELLAS BORRAN ARCHIVOS DE VERDAD. Clear-CacheFirefox y
    Clear-Miniaturas no resuelven ninguna ruta por su cuenta: las dos
    exigen -Ruta obligatoria y no tocan nada fuera de ella. Por eso se
    pueden ejercitar aqui, y solo asi: contra un taller que monta este
    mismo archivo bajo [IO.Path]::GetTempPath() y que se borra en el
    AfterAll. Hay ademas una guarda que se niega a ejecutar si el taller
    no cuelga de la carpeta temporal, porque el dia que alguien copie
    este archivo y cambie la ruta, el fallo tiene que ser una prueba en
    rojo y no una carpeta del usuario vacia.

    Y se borra siempre con -Permanente. No es una preferencia: sin el,
    Remove-Elemento manda a la papelera a traves de Microsoft.VisualBasic,
    que solo existe de verdad en Windows, y la misma prueba diria una cosa
    aqui y otra en la integracion continua.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Sin guardia inicializada, Test-RutaIntocable bloquea TODO -es su
    # estado de fallo seguro- y Clear-CacheFirefox no borraria ni un
    # archivo. La prueba se quedaria en verde comprobando el vacio, que
    # es justo la prueba hueca que este proyecto persigue. Se inicializa
    # con carpetas personales vacias, igual que tests/Remove.Tests.ps1.
    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio   = ''
        Documentos   = ''
        Descargas    = ''
        Imagenes     = ''
        Musica       = ''
        Videos       = ''
        CarpetaDatos = ''
    })

    # Guarda de seguridad para todo el archivo: aqui se borra de verdad.
    $script:Temporal = [IO.Path]::GetTempPath()

    function script:New-TallerTemporal {
        param([string] $Prefijo)
        $carpeta = Join-Path $script:Temporal ($Prefijo + '-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $carpeta -Force)
        return $carpeta
    }

    function script:Remove-TallerTemporal {
        param([string] $Carpeta)
        if ($Carpeta -and (Test-Path -LiteralPath $Carpeta)) {
            Remove-Item -LiteralPath $Carpeta -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Un texto corto en cada archivo, no vacio: un archivo de cero bytes
    # se comporta distinto en alguna rama de medida y no hace falta que
    # aqui sea asi.
    function script:New-ArchivoDePrueba {
        param([string] $Ruta)
        [IO.File]::WriteAllText($Ruta, 'contenido de prueba')
    }
}

# =====================================================================
#  Initialize-MotorBorrado
# =====================================================================

Describe 'Initialize-MotorBorrado: deja el motor en condiciones de mandar a la papelera' {

    It 'deja el motor utilizable: dice que si Y el tipo que manda a la papelera resuelve' {
        # Las dos mitades, porque una sola no dice nada. Que devuelva
        # $true solo cuenta si despues se puede usar lo que dice haber
        # cargado: si el nombre del ensamblado se escribiera mal, el
        # Add-Type fallaria, el catch devolveria $false y la primera
        # asercion se pondria roja; si alguien cambiara el ensamblado por
        # otro que si existe pero no trae la papelera, seria la segunda.
        Initialize-MotorBorrado | Should -BeTrue

        $tipo = 'Microsoft.VisualBasic.FileIO.FileSystem' -as [type]
        $tipo | Should -Not -BeNullOrEmpty -Because (
            'Remove-Elemento llama a este tipo para mandar a la papelera; ' +
            'si no resuelve, el motor no esta montado por mucho que lo diga')
    }

    It 'es idempotente: el programa la llama en cada arranque de analisis' {
        # Window.Analisis.ps1 la invoca por runspace, asi que la segunda
        # llamada sobre un ensamblado ya cargado tiene que dar el mismo
        # veredicto en vez de fallar por "ya existe".
        $primera = Initialize-MotorBorrado
        $segunda = Initialize-MotorBorrado
        $tercera = Initialize-MotorBorrado

        $segunda | Should -Be $primera
        $tercera | Should -Be $primera
    }

    It 'nunca lanza: quien la llama decide que hacer con el no' {
        { Initialize-MotorBorrado } | Should -Not -Throw
    }

    It 'devuelve UN solo booleano, no una tuberia con restos dentro' {
        # Add-Type escupe los tipos cargados si se le olvida a alguien el
        # [void]. Con basura delante, "if (Initialize-MotorBorrado)" sigue
        # siendo cierto y el fallo pasa desapercibido hasta que alguien
        # compara el resultado con $true.
        # @() obligatorio: en 5.1, .Count sobre un objeto suelto es $null.
        $salida = @(Initialize-MotorBorrado)
        $salida.Count | Should -Be 1
        $salida[0]    | Should -BeOfType [bool]
    }
}

# =====================================================================
#  Clear-CacheFirefox
# =====================================================================

Describe 'Clear-CacheFirefox: vacia cache2 y NADA mas' {

    BeforeAll {
        $script:Ff = script:New-TallerTemporal 'cachivache-ff'
    }

    AfterAll {
        script:Remove-TallerTemporal $script:Ff
    }

    BeforeEach {
        # Se rehace entero en cada It: son pruebas que destruyen lo que
        # miran, y compartir el montaje las haria depender del orden.
        Get-ChildItem -LiteralPath $script:Ff -Force | Remove-Item -Recurse -Force

        $script:Perfil   = Join-Path $script:Ff 'a1b2c3d4.default-release'
        $script:Cache2   = Join-Path $script:Perfil 'cache2'
        $script:Entradas = Join-Path $script:Cache2 'entries'
        [void](New-Item -ItemType Directory -Path $script:Entradas -Force)

        # Dentro de cache2: basura de verdad, en dos niveles.
        script:New-ArchivoDePrueba (Join-Path $script:Cache2 'index.bin')
        script:New-ArchivoDePrueba (Join-Path $script:Entradas 'ABCDEF0123.bin')

        # Fuera de cache2, en el mismo perfil: lo que el usuario perderia
        # si esta funcion se pasara de lista. Son los tres archivos por
        # los que Firefox reconoce un perfil.
        script:New-ArchivoDePrueba (Join-Path $script:Perfil 'places.sqlite')
        script:New-ArchivoDePrueba (Join-Path $script:Perfil 'prefs.js')
        script:New-ArchivoDePrueba (Join-Path $script:Perfil 'logins.json')

        # Un perfil SIN cache2, para comprobar que no se inventa nada.
        $script:PerfilLimpio = Join-Path $script:Ff 'zz99zz99.otro'
        [void](New-Item -ItemType Directory -Path $script:PerfilLimpio -Force)
        script:New-ArchivoDePrueba (Join-Path $script:PerfilLimpio 'prefs.js')
    }

    It 'el taller esta donde tiene que estar y montado' {
        # GUARDA. Sin esto, un taller mal montado -o montado en el sitio
        # equivocado- dejaria a todas las de abajo comprobando el vacio y
        # pasando. Y la comprobacion de la carpeta temporal es lo unico
        # que separa esta prueba de borrar algo de alguien.
        $script:Ff | Should -Not -BeNullOrEmpty
        $script:Ff.StartsWith($script:Temporal) | Should -BeTrue -Because (
            'aqui se borra de verdad: el taller TIENE que colgar de la carpeta temporal')
        Test-Path -LiteralPath (Join-Path $script:Cache2 'index.bin')      | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Entradas 'ABCDEF0123.bin') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Perfil 'places.sqlite')  | Should -BeTrue
    }

    It 'vacia el cache2 de cada perfil, tambien lo que cuelga por debajo' {
        Clear-CacheFirefox -Ruta $script:Ff -Permanente -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:Cache2 'index.bin')        | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Entradas 'ABCDEF0123.bin') | Should -BeFalse
    }

    It 'y deja la carpeta cache2 en su sitio, que es la mitad del contrato' {
        # Firefox falla al arrancar si le desaparece la carpeta de cache
        # de debajo de los pies. Por eso el metodo se llama 'FirefoxCache'
        # y no 'Ruta': vacia, no borra el contenedor.
        Clear-CacheFirefox -Ruta $script:Ff -Permanente -Confirm:$false

        Test-Path -LiteralPath $script:Cache2 | Should -BeTrue -Because (
            'vaciar una cache no es borrar la carpeta: el programa que la creo la espera ahi')
    }

    It 'NO toca marcadores, contrasenyas ni preferencias del perfil' {
        # La prueba que de verdad importa. Si el bucle se equivocara de
        # nivel -si vaciara el perfil en vez de su cache2- aqui se ve, y
        # en ningun otro sitio.
        Clear-CacheFirefox -Ruta $script:Ff -Permanente -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:Perfil 'places.sqlite')     | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Perfil 'prefs.js')          | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Perfil 'logins.json')       | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:PerfilLimpio 'prefs.js')    | Should -BeTrue
        Test-Path -LiteralPath $script:PerfilLimpio                           | Should -BeTrue
    }

    It 'un perfil sin cache2 no la crea ni provoca nada' {
        { Clear-CacheFirefox -Ruta $script:Ff -Permanente -Confirm:$false } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $script:PerfilLimpio 'cache2') | Should -BeFalse
    }

    It 'con -WhatIf no borra ni un archivo' {
        # -WhatIf es lo que separa "voy a mirar" de "acabo de perder la
        # cache". Un SupportsShouldProcess sin el ShouldProcess dentro
        # compila, se anuncia en la ayuda y borra igual.
        Clear-CacheFirefox -Ruta $script:Ff -Permanente -WhatIf

        Test-Path -LiteralPath (Join-Path $script:Cache2 'index.bin')        | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Entradas 'ABCDEF0123.bin') | Should -BeTrue
    }

    It 'una ruta que no existe no revienta ni deja rastro' {
        # Firefox puede no estar instalado. El modulo llama igual.
        $inventada = Join-Path $script:Ff 'no-hay-nada-aqui'
        { Clear-CacheFirefox -Ruta $inventada -Permanente -Confirm:$false } | Should -Not -Throw
        Test-Path -LiteralPath $inventada | Should -BeFalse
    }
}

# =====================================================================
#  Clear-Miniaturas
# =====================================================================

Describe 'Clear-Miniaturas: solo los thumbcache_ e iconcache_ de esa carpeta' {

    BeforeAll {
        $script:Mn = script:New-TallerTemporal 'cachivache-mn'
    }

    AfterAll {
        script:Remove-TallerTemporal $script:Mn
    }

    BeforeEach {
        Get-ChildItem -LiteralPath $script:Mn -Force | Remove-Item -Recurse -Force

        # Lo que SI se borra.
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'thumbcache_32.db')
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'thumbcache_idx.db')
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'iconcache_16.db')

        # Lo que NO. 'Contrasenas.db' y 'notas.txt' son del usuario;
        # 'thumbcache_96.dbx' y 'thumbcachexx.db' comprueban que el patron
        # esta anclado por los dos extremos y no es un "contiene".
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'Contrasenas.db')
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'notas.txt')
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'thumbcache_96.dbx')
        script:New-ArchivoDePrueba (Join-Path $script:Mn 'copia_thumbcache_8.db')

        # Y una subcarpeta: esta funcion no baja niveles a proposito.
        $script:Sub = Join-Path $script:Mn 'sub'
        [void](New-Item -ItemType Directory -Path $script:Sub -Force)
        script:New-ArchivoDePrueba (Join-Path $script:Sub 'thumbcache_256.db')
    }

    It 'el taller esta donde tiene que estar y montado' {
        # Misma guarda que arriba, y por el mismo motivo.
        $script:Mn.StartsWith($script:Temporal) | Should -BeTrue -Because (
            'aqui se borra de verdad: el taller TIENE que colgar de la carpeta temporal')
        @(Get-ChildItem -LiteralPath $script:Mn -File -Force).Count | Should -Be 7
    }

    It 'borra las bases de miniaturas y de iconos del Explorador' {
        Clear-Miniaturas -Ruta $script:Mn -Permanente -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:Mn 'thumbcache_32.db')  | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Mn 'thumbcache_idx.db') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Mn 'iconcache_16.db')   | Should -BeFalse
    }

    It 'y deja en pie cualquier otro .db, aunque este en la misma carpeta' {
        # El patron esta anclado con ^ y $ por algo. Sin el ancla de
        # delante, 'copia_thumbcache_8.db' entraria; sin la de detras,
        # 'thumbcache_96.dbx' tambien. Y 'Contrasenas.db' es la razon por
        # la que ninguna de las dos puede faltar.
        Clear-Miniaturas -Ruta $script:Mn -Permanente -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:Mn 'Contrasenas.db')         | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Mn 'notas.txt')              | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Mn 'thumbcache_96.dbx')      | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Mn 'copia_thumbcache_8.db')  | Should -BeTrue
    }

    It 'no baja a las subcarpetas' {
        # Get-ChildItem sin -Recurse, y es deliberado: la carpeta del
        # Explorador es plana. Si alguien anyadiera el -Recurse "para
        # limpiar mejor", esta prueba lo dice.
        Clear-Miniaturas -Ruta $script:Mn -Permanente -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:Sub 'thumbcache_256.db') | Should -BeTrue
        Test-Path -LiteralPath $script:Sub | Should -BeTrue
    }

    It 'con -WhatIf no borra ni un archivo' {
        Clear-Miniaturas -Ruta $script:Mn -Permanente -WhatIf

        Test-Path -LiteralPath (Join-Path $script:Mn 'thumbcache_32.db') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Mn 'iconcache_16.db')  | Should -BeTrue
    }

    It 'una ruta que no existe no revienta' {
        $inventada = Join-Path $script:Mn 'no-hay-nada-aqui'
        { Clear-Miniaturas -Ruta $inventada -Permanente -Confirm:$false } | Should -Not -Throw
    }
}

# =====================================================================
#  Get-InformeEstiloCss
# =====================================================================

Describe 'Get-InformeEstiloCss: el CSS tiene que poder incrustarse sin romper el HTML' {

    BeforeAll {
        $script:Css = Get-InformeEstiloCss
    }

    It 'devuelve un bloque de estilos con reglas de verdad dentro' {
        # La guarda del apartado: sin ella, todo lo de abajo comprobaria
        # una cadena vacia y pasaria.
        $script:Css | Should -Not -BeNullOrEmpty
        # 20 no es un numero magico sacado del aire: es holgadamente menos
        # que las reglas que hay, y holgadamente mas que un bloque vacio o
        # un marcador de posicion.
        ([regex]::Matches($script:Css, '\{')).Count | Should -BeGreaterThan 20 -Because (
            'un CSS sin reglas dentro dejaria el informe en texto plano y nadie lo notaria aqui')
    }

    # OJO con el nombre de este It: Pester sustituye lo que va entre
    # angulos por un valor de -ForEach, asi que un "<style>" en el titulo
    # sale impreso como "$null" y el informe deja de decir que se probo.
    It 'abre y cierra la etiqueta de estilos exactamente una vez' {
        ([regex]::Matches($script:Css, '<style>')).Count  | Should -Be 1
        ([regex]::Matches($script:Css, '</style>')).Count | Should -Be 1
        $script:Css.Trim().StartsWith('<style>') | Should -BeTrue
        $script:Css.Trim().EndsWith('</style>')  | Should -BeTrue
    }

    It 'y no lleva ningun "</" suelto dentro, que es lo que cerraria el bloque antes de tiempo' {
        # Lo que termina un elemento <style> en HTML no es "</style>" sino
        # la secuencia "</" seguida del nombre. Un solo "</" perdido en un
        # comentario del CSS parte el informe en dos: el navegador cierra
        # los estilos ahi y pinta el resto del CSS como texto en la
        # pagina. Se mira el cuerpo, no la cadena entera, porque el cierre
        # de verdad va al final y ese si tiene que estar.
        $cuerpo = $script:Css.Substring(
                     $script:Css.IndexOf('<style>') + '<style>'.Length)
        $cuerpo = $cuerpo.Substring(0, $cuerpo.LastIndexOf('</style>'))

        $cuerpo | Should -Not -BeNullOrEmpty -Because 'si el cuerpo saliera vacio esto no comprobaria nada'
        $cuerpo | Should -Not -Match '</'
    }

    It 'incrustado en un HTML, el bloque de estilos se recupera ENTERO' {
        # La comprobacion de verdad: se monta la misma cabecera que arma
        # Export-InformeHtml y se extrae el bloque con una captura
        # perezosa, que es como lo haria un analizador. Si dentro hubiera
        # un cierre adelantado, la captura saldria corta y el CSS que
        # llega al navegador seria un trozo.
        $html = '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">' +
                $script:Css + '</head><body><div class="wrap"></div></body></html>'

        $m = [regex]::Match($html, '(?s)<style>(.*?)</style>')
        $m.Success | Should -BeTrue
        $m.Groups[1].Value.Length | Should -Be (
            $script:Css.Trim().Length - '<style>'.Length - '</style>'.Length) -Because (
            'lo que un analizador recupera tiene que ser el CSS entero, no hasta el primer corte')
        ([regex]::Matches($html, '<style>')).Count | Should -Be 1
    }

    It 'define las clases que el informe pinta de verdad' {
        # Coupling real entre las dos mitades de Report.ps1: si el CSS
        # deja de declarar .chip, los tres niveles de riesgo salen sin
        # color y el informe pierde justo la informacion por la que se
        # mira. Un CSS que no case con el HTML es peor que ninguno,
        # porque parece que hay estilo.
        foreach ($selector in @('.wrap{', '.sub{', '.card{', '.chip{', '.path{',
                                '.num{', '.aviso{', '.count{', 'table{', 'footer{')) {
            $script:Css.Contains($selector) | Should -BeTrue -Because (
                "Export-InformeHtml emite ese selector y el CSS tiene que declararlo: $selector")
        }
    }

    It 'no lanza y no depende de nada del equipo' {
        { Get-InformeEstiloCss } | Should -Not -Throw
        # Dos llamadas dan lo mismo: es una constante, no algo que mire el
        # disco ni la hora.
        Get-InformeEstiloCss | Should -Be $script:Css
    }
}

# =====================================================================
#  Get-CarpetaInformes
# =====================================================================

Describe 'Get-CarpetaInformes: un unico sitio que sepa donde viven los informes' {

    BeforeAll {
        $script:Datos = script:New-TallerTemporal 'cachivache-inf'

        # Get-CarpetaDatos lee %LOCALAPPDATA% y CREA carpetas. Se
        # redirige para no escribir en el perfil de nadie al ejecutar la
        # suite. [Environment] y no "$env:X = $null" porque en 5.1 asignar
        # nulo deja la variable en cadena vacia en vez de quitarla.
        $script:LocalAppDataOriginal = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $script:Datos)
    }

    AfterAll {
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $script:LocalAppDataOriginal)
        script:Remove-TallerTemporal $script:Datos
    }

    It 'compone una ruta absoluta y no lanza' {
        $ruta = Get-CarpetaInformes -CarpetaDatos $script:Datos
        { Get-CarpetaInformes -CarpetaDatos $script:Datos } | Should -Not -Throw

        $ruta | Should -Not -BeNullOrEmpty
        [IO.Path]::IsPathRooted($ruta) | Should -BeTrue -Because (
            'la ruta se usa tal cual para abrir el explorador: una relativa apuntaria a otro sitio segun quien llame')
    }

    It 'cuelga de la carpeta de datos que se le pasa, y anyade un nivel' {
        $ruta = Get-CarpetaInformes -CarpetaDatos $script:Datos

        $ruta.StartsWith($script:Datos) | Should -BeTrue
        $ruta | Should -Not -Be $script:Datos -Because (
            'si devolviera la carpeta de datos a secas, listar informes listaria tambien el registro y las preferencias')
        (Split-Path $ruta -Leaf) | Should -Be 'informes'
    }

    It 'sin argumentos usa la carpeta de datos del programa' {
        $ruta = Get-CarpetaInformes

        [IO.Path]::IsPathRooted($ruta) | Should -BeTrue
        $ruta.StartsWith($script:Datos) | Should -BeTrue -Because (
            'por defecto tiene que salir de Get-CarpetaDatos, que es quien sabe donde escribe el programa')
    }

    It 'es EL MISMO sitio donde New-NombreInforme escribe: la costura que existe para no repetir el Join-Path' {
        # El porque de esta funcion, segun su propia documentacion: antes
        # solo New-NombreInforme sabia donde estaban los informes, escondido
        # a mitad de su cuerpo, y quien quisiera leerlos repetia el
        # Join-Path a mano. Si las dos divergieran, el panel de Informes
        # se quedaria mirando una carpeta vacia mientras los informes se
        # escriben al lado, y nada avisaria.
        $carpeta = Get-CarpetaInformes -CarpetaDatos $script:Datos
        $nombre  = New-NombreInforme -Tipo 'analisis' -Extension 'html' -CarpetaDatos $script:Datos

        (Split-Path $nombre -Parent) | Should -Be $carpeta
    }
}

# =====================================================================
#  Get-RaizProyecto
# =====================================================================

Describe 'Get-RaizProyecto: encuentra la raiz del repositorio de verdad' {

    It 'devuelve una ruta absoluta, existente, y no lanza' {
        { Get-RaizProyecto } | Should -Not -Throw
        $raiz = Get-RaizProyecto

        $raiz | Should -Not -BeNullOrEmpty
        [IO.Path]::IsPathRooted($raiz) | Should -BeTrue
        Test-Path -LiteralPath $raiz | Should -BeTrue
    }

    It 'y es LA raiz: dentro estan src, tests y el propio arranque del nucleo' {
        # Comprobar que la ruta existe no basta: cualquier Split-Path de
        # mas devolveria una carpeta que tambien existe -la de encima- y
        # Get-ModulosLimpieza se quedaria sin encontrar un solo modulo,
        # con lo que el programa analizaria y no propondria nada. Sin
        # errores. Por eso se comprueba lo que TIENE que haber dentro.
        $raiz = Get-RaizProyecto

        Test-Path -LiteralPath (Join-Path $raiz 'src')   | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $raiz 'tests') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Bootstrap.ps1') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Join-Path $raiz 'src') 'Modules') | Should -BeTrue
    }

    It 'coincide con la raiz que calculan las propias pruebas' {
        # Dos maneras independientes de llegar al mismo sitio: la funcion
        # sube dos niveles desde src/Core, y este archivo sube uno desde
        # tests. Si discreparan, una de las dos esta mal y hasta ahora no
        # lo decia nadie.
        (Get-RaizProyecto).TrimEnd('\', '/') | Should -Be $script:Raiz.TrimEnd('\', '/')
    }

    It 'los modulos de limpieza se encuentran desde esa raiz' {
        # La consecuencia observable de que la raiz sea correcta. @()
        # obligatorio: en 5.1, .Count sobre un objeto suelto vale $null.
        @(Get-ModulosLimpieza -Raiz (Get-RaizProyecto)).Count | Should -BeGreaterThan 0
    }
}

# =====================================================================
#  Export-Preferencias
# =====================================================================

Describe 'Export-Preferencias: lo que se guarda se tiene que poder recuperar' {

    BeforeAll {
        $script:DatosPref = script:New-TallerTemporal 'cachivache-pref'
        $script:LocalAppDataPrevio = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $script:DatosPref)

        # Todo distinto de los valores por defecto de Import-Preferencias,
        # a proposito: si Export no escribiera nada, la lectura caeria a
        # los valores por defecto y una prueba montada sobre ellos pasaria
        # igual. Aqui no puede.
        $script:Preferidas = @{
            Tema              = 'claro'          # por defecto: el de Windows
            Perfil            = 'agresivo'       # por defecto: equilibrado
            DiasSinUso        = 90               # por defecto: 180
            MinimoMB          = 25               # por defecto: 10
            IncluirMenores    = $true            # por defecto: false
            Permanente        = $true            # por defecto: false
            ModulosActivos    = @('caches', 'temporales')
            UnidadesExcluidas = @('D:')
            RutasExcluidas    = @('C:\proyectos\vivo')
        }
    }

    AfterAll {
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $script:LocalAppDataPrevio)
        script:Remove-TallerTemporal $script:DatosPref
    }

    BeforeEach {
        $script:RutaPref = Get-RutaPreferencias
        if (Test-Path -LiteralPath $script:RutaPref) {
            Remove-Item -LiteralPath $script:RutaPref -Recurse -Force
        }
    }

    It 'escribe donde dice Get-RutaPreferencias, y no en otro sitio' {
        # GUARDA del apartado: si la redireccion de %LOCALAPPDATA% no
        # hubiera funcionado, todo lo de abajo estaria escribiendo en el
        # perfil de quien ejecuta la suite y pasando igual.
        $script:RutaPref.StartsWith($script:DatosPref) | Should -BeTrue -Because (
            'la suite no puede escribir preferencias en el perfil real de nadie')

        $resultado = Export-Preferencias -Preferencias $script:Preferidas -Confirm:$false
        Test-Path -LiteralPath $script:RutaPref | Should -BeTrue
        # El testigo positivo del $false de mas abajo: sin este, una
        # funcion que devolviera $false SIEMPRE pasaria aquella prueba.
        $resultado | Should -BeTrue -Because 'se ha guardado de verdad, y tiene que decirlo'
    }

    It 'ida y vuelta: lo guardado se recupera entero, valor a valor' {
        Export-Preferencias -Preferencias $script:Preferidas -Confirm:$false
        $leidas = Import-Preferencias

        $leidas.Tema           | Should -Be 'claro'
        $leidas.Perfil         | Should -Be 'agresivo'
        $leidas.DiasSinUso     | Should -Be 90
        $leidas.MinimoMB       | Should -Be 25
        $leidas.IncluirMenores | Should -BeTrue
        $leidas.Permanente     | Should -BeTrue
        # @() en las tres, por lo de 5.1 con .Count.
        @($leidas.ModulosActivos)    | Should -Be @('caches', 'temporales')
        @($leidas.UnidadesExcluidas) | Should -Be @('D:')
        @($leidas.RutasExcluidas)    | Should -Be @('C:\proyectos\vivo')
    }

    It 'lo escrito es JSON legible, no un volcado de PowerShell' {
        # El archivo es texto plano que el usuario puede abrir y editar
        # -asi lo dice la cabecera de Preferencias.ps1-, y ConvertFrom-Json
        # tiene que poder con el sin ayuda.
        Export-Preferencias -Preferencias $script:Preferidas -Confirm:$false

        $texto = Get-Content -LiteralPath $script:RutaPref -Raw -Encoding UTF8
        $texto | Should -Not -BeNullOrEmpty
        { $texto | ConvertFrom-Json } | Should -Not -Throw

        # La conversion se hace FUERA del scriptblock de Should. Dentro,
        # la asignacion se queda en el ambito del bloque y la variable
        # llega vacia al It: la prueba comparaba $null contra 'agresivo'.
        $objeto = $texto | ConvertFrom-Json
        $objeto.Perfil     | Should -Be 'agresivo'
        $objeto.DiasSinUso | Should -Be 90
    }

    It 'una ruta con barras invertidas sobrevive al viaje sin duplicarse' {
        # JSON escapa la barra invertida. Si alguien cambiara el
        # serializador por uno que no la desescapa al leer, las
        # exclusiones del usuario dejarian de casar con ninguna ruta real
        # y volverian a aparecer en cada analisis, en silencio.
        Export-Preferencias -Preferencias $script:Preferidas -Confirm:$false
        $leidas = Import-Preferencias

        @($leidas.RutasExcluidas)[0] | Should -Be 'C:\proyectos\vivo'
        @($leidas.RutasExcluidas)[0] | Should -Not -Match '\\\\'
    }

    It 'con -WhatIf no escribe nada' {
        Export-Preferencias -Preferencias $script:Preferidas -WhatIf
        Test-Path -LiteralPath $script:RutaPref | Should -BeFalse -Because (
            'declara SupportsShouldProcess: si el ShouldProcess no estuviera dentro, escribiria igual')
    }

    It 'si el destino no se puede escribir, la funcion DEVUELVE $false' {
        # ESTA ES LA PRUEBA DEL QUINTO EXPORTADOR.
        #
        # Nacio diciendo "lo que NO comprueba, porque hoy no ocurre, es
        # que la funcion se entere". Se entera desde que se arreglo: le
        # faltaba el -ErrorAction Stop, sin el cual Set-Content falla de
        # forma NO TERMINANTE, el catch no salta y la funcion volvia
        # muda. El usuario cerraba la ventana, la reabria al dia
        # siguiente y se encontraba los ajustes por defecto.
        #
        # Se afirma el valor devuelto Y NO SOLO que el archivo no exista,
        # porque son dos cosas distintas: que no se escriba es lo que
        # hacia ANTES tambien. Lo nuevo -y lo unico que permite avisar al
        # usuario- es que se sepa.
        #
        # El destino imposible se fabrica poniendo una CARPETA donde tiene
        # que ir el archivo. Vale igual en Windows y en Linux, y no
        # depende de permisos, que en la integracion continua no son los
        # mismos que aqui.
        [void](New-Item -ItemType Directory -Path $script:RutaPref -Force)

        $resultado = Export-Preferencias -Preferencias $script:Preferidas -Confirm:$false -ErrorAction SilentlyContinue
        $resultado | Should -BeFalse -Because (
            'sin -ErrorAction Stop esto vuelve vacio y quien llama cree que se guardo')

        # Sigue siendo la carpeta: no se ha colado un archivo por debajo.
        (Get-Item -LiteralPath $script:RutaPref).PSIsContainer | Should -BeTrue

        # 2>$null: al leer, Get-Content tropieza con la carpeta y escribe
        # un error NO TERMINANTE que su try/catch tampoco atrapa. Ensucia
        # la salida de la suite sin cambiar el resultado.
        $leidas = Import-Preferencias 2>$null
        $leidas.Perfil     | Should -Be 'equilibrado' -Because 'no se guardo nada, asi que toca el valor por defecto'
        $leidas.Perfil     | Should -Not -Be 'agresivo'
        $leidas.DiasSinUso | Should -Be 180
        @($leidas.RutasExcluidas).Count | Should -Be 0
    }
}

<#
    LO QUE ESTE ARCHIVO NO PRUEBA, Y POR QUE
    ========================================

    1. EL CAMINO A LA PAPELERA de Clear-CacheFirefox y Clear-Miniaturas.
       Sin -Permanente, Remove-Elemento llama a
       Microsoft.VisualBasic.FileIO.FileSystem, que fuera de Windows
       resuelve como tipo pero falla al ejecutarse. La misma prueba diria
       una cosa aqui y otra en Windows, asi que se ejercita solo el
       camino permanente. Lo de la papelera ya lo cubre Remove.Tests.ps1
       por el lado de Remove-Elemento.

    2. HALLAZGO, YA ARREGLADO: Export-Preferencias no se enteraba de que
       no habia guardado. Era el mismo fallo que documenta
       Export-InformeHtml en su propio cuerpo, y que persigue la
       invariante de tests/Cli.Tests.ps1... que no lo vio, porque
       enumeraba dos archivos por su nombre en vez de barrer src/ entero.
       Escribiendo estas pruebas aparecio este QUINTO exportador, y al
       barrer de verdad aparecio un SEXTO en Historial.ps1.

       Los dos arreglos estan en el codigo con su porque. Aqui queda la
       parte que corresponde a las pruebas, que son dos y hacen falta las
       dos:

         - la del destino imposible afirma que devuelve $false, no solo
           que el archivo no aparece: que no apareciera ya pasaba ANTES
           del arreglo, asi que sola no distingue nada;
         - y la del camino feliz afirma que devuelve $true, que es el
           testigo positivo sin el cual una funcion que devolviera
           siempre $false pasaria la anterior.

       La invariante de Cli.Tests.ps1 barre ahora todo src/ y pregunta
       "hay alguno mal?" en vez de "hacen bien estos cuatro?". La leccion
       esta en docs/RELEVO.md: una invariante que enumera los sitios
       donde ya hubo un fallo no es una invariante, es una lista de
       fallos pasados.
#>
