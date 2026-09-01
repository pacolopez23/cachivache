<#
    Pruebas de la vista de archivos: la capa de consulta sobre el indice.
    Ver [VIS-02] en docs/HOJA-DE-RUTA.md.

    El indice de estas pruebas es SINTETICO, hecho a mano con la misma
    forma que devuelve New-IndiceDisco. A proposito: lo que se prueba aqui
    es la consulta, no el recorrido del disco, y fabricar archivos reales
    para comprobar un orden solo anyade formas de fallar que no tienen
    nada que ver con lo que se esta mirando. El recorrido ya tiene sus
    pruebas en tests/Indice.Tests.ps1.

    Y el indice se construye en un BeforeAll, no en el cuerpo del
    Describe: una lista construida en el cuerpo se evalua en el
    DESCUBRIMIENTO de Pester y llega VACIA a los It, con la suite en verde
    diciendo lo contrario de la verdad. Ha mordido tres veces.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')


    function New-FilaFalsa {
        <#
        .SYNOPSIS
            Una fila de la lista Archivos del indice, con su misma forma.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone un objeto en memoria.')]
        [CmdletBinding()]
        param([string] $Nombre, [double] $Bytes, [string] $Carpeta = 'C:\datos')

        return [pscustomobject]@{
            # Concatenacion y no Join-Path: estas rutas son de Windows y la
            # suite corre tambien en Linux, donde Join-Path se queja de que
            # no existe la unidad C:. Aqui la ruta es solo una etiqueta.
            Ruta      = ($Carpeta + '\' + $Nombre)
            Nombre    = $Nombre
            Carpeta   = $Carpeta
            Extension = ([IO.Path]::GetExtension($Nombre)).ToLowerInvariant()
            Bytes     = $Bytes
            Ultimo    = [datetime]'2026-01-15'
        }
    }

    function New-IndiceFalso {
        <#
        .SYNOPSIS
            Indice sintetico con la misma forma que New-IndiceDisco.
        .PARAMETER Filas
            Lo que va en Archivos. Vacio simula un disco sin nada por
            encima del umbral.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone un objeto en memoria.')]
        [CmdletBinding()]
        param(
            [AllowNull()] $Filas,
            [double] $UmbralArchivo = 1MB
        )

        return [pscustomobject]@{
            Carpetas      = [Collections.Generic.Dictionary[string, object]]::new()
            Archivos      = @($Filas)
            Raices        = @('C:\datos')
            Bytes         = 0.0
            TotalArchivos = @($Filas).Count
            Compartidos   = 0
            Inaccesibles  = 0
            UmbralArchivo = $UmbralArchivo
        }
    }

    # Tamanyos elegidos para que el orden por BYTES y el orden por el
    # TEXTO formateado NO coincidan: 9,52 GB es alfabeticamente menor que
    # 980 MB, asi que una implementacion que ordene por Format-Tamano
    # pondria el de 980 MB por delante del de 9,52 GB.
    $script:FilasBase = @(
        (New-FilaFalsa -Nombre 'copia.iso'   -Bytes 10222739456)   #  9,52 GB
        (New-FilaFalsa -Nombre 'video.mkv'   -Bytes 1027604480)    #    980 MB
        (New-FilaFalsa -Nombre 'basura.tmp'  -Bytes 524288000)     #    500 MB
        (New-FilaFalsa -Nombre 'otro.tmp'    -Bytes 104857600)     #    100 MB
        (New-FilaFalsa -Nombre 'foto1.jpg'   -Bytes 5242880)       #      5 MB
        (New-FilaFalsa -Nombre 'foto2.jpg'   -Bytes 4194304)       #      4 MB
        (New-FilaFalsa -Nombre 'foto[1].jpg' -Bytes 3145728)       #      3 MB
        (New-FilaFalsa -Nombre 'anyo ñ.txt'  -Bytes 2097152)       #      2 MB
    )
}

Describe 'Test-CoincideComodin' {

    It 'un patron vacio casa con todo' {
        Test-CoincideComodin -Nombre 'lo que sea.bin' -Patron '' | Should -BeTrue
    }

    It 'un patron de solo espacios tambien casa con todo' {
        Test-CoincideComodin -Nombre 'lo que sea.bin' -Patron '   ' | Should -BeTrue
    }

    It 'un patron nulo casa con todo y no lanza' {
        { Test-CoincideComodin -Nombre 'algo.txt' -Patron $null } | Should -Not -Throw
        Test-CoincideComodin -Nombre 'algo.txt' -Patron $null | Should -BeTrue
    }

    It 'un nombre nulo no lanza y no casa con un patron concreto' {
        { Test-CoincideComodin -Nombre $null -Patron '*.tmp' } | Should -Not -Throw
        Test-CoincideComodin -Nombre $null -Patron '*.tmp' | Should -BeFalse
    }

    It 'los dos nulos a la vez no lanzan' {
        { Test-CoincideComodin -Nombre $null -Patron $null } | Should -Not -Throw
    }

    It '*.tmp casa con lo que acaba en .tmp y no con lo demas' {
        Test-CoincideComodin -Nombre 'basura.tmp'  -Patron '*.tmp' | Should -BeTrue
        Test-CoincideComodin -Nombre 'video.mkv'   -Patron '*.tmp' | Should -BeFalse
        # El punto es literal: sin escaparlo, "abctmp" casaria.
        Test-CoincideComodin -Nombre 'basuratmp'   -Patron '*.tmp' | Should -BeFalse
    }

    It 'foto?.jpg casa con un caracter y solo uno' {
        Test-CoincideComodin -Nombre 'foto1.jpg'  -Patron 'foto?.jpg' | Should -BeTrue
        Test-CoincideComodin -Nombre 'foto2.jpg'  -Patron 'foto?.jpg' | Should -BeTrue
        Test-CoincideComodin -Nombre 'foto.jpg'   -Patron 'foto?.jpg' | Should -BeFalse
        Test-CoincideComodin -Nombre 'foto12.jpg' -Patron 'foto?.jpg' | Should -BeFalse
    }

    It 'los corchetes son texto, que es justo lo que -like no hace' {
        # Esta es LA prueba de este apartado. Con -like, "foto[1].jpg" se
        # lee como "foto, un caracter de la clase [1], y .jpg", asi que
        # encuentra foto1.jpg -que NO es lo que el usuario pidio- y no
        # encuentra foto[1].jpg -que si lo es-. Las dos aserciones de
        # abajo son las dos mitades de ese error.
        Test-CoincideComodin -Nombre 'foto[1].jpg' -Patron 'foto[1].jpg' | Should -BeTrue
        Test-CoincideComodin -Nombre 'foto1.jpg'   -Patron 'foto[1].jpg' | Should -BeFalse

        # Y la comprobacion de que el error existe de verdad: si algun dia
        # -like dejara de comportarse asi, esta guarda avisaria de que la
        # prueba de arriba ya no esta comprobando nada.
        ('foto1.jpg' -like 'foto[1].jpg') | Should -BeTrue -Because 'es el defecto que esta funcion evita'
    }

    It 'no distingue mayusculas de minusculas' {
        Test-CoincideComodin -Nombre 'BASURA.TMP' -Patron '*.tmp' | Should -BeTrue
        Test-CoincideComodin -Nombre 'basura.tmp' -Patron '*.TMP' | Should -BeTrue
    }

    It 'recorta los espacios sobrantes del patron' {
        Test-CoincideComodin -Nombre 'basura.tmp' -Patron ' *.tmp ' | Should -BeTrue
    }

    It 'anclado a los dos extremos: un patron sin comodines es el nombre entero' {
        Test-CoincideComodin -Nombre 'video.mkv'      -Patron 'video.mkv' | Should -BeTrue
        Test-CoincideComodin -Nombre 'mi video.mkv'   -Patron 'video.mkv' | Should -BeFalse
        Test-CoincideComodin -Nombre 'video.mkv.bak'  -Patron 'video.mkv' | Should -BeFalse
    }

    It 'trata como texto los demas caracteres con significado en expresiones regulares' {
        foreach ($nombre in @('a+b.txt', 'a(b).txt', 'a^b.txt', 'a$b.txt', 'a{2}.txt', 'a|b.txt', 'a\b.txt')) {
            Test-CoincideComodin -Nombre $nombre -Patron $nombre |
                Should -BeTrue -Because "«$nombre» tiene que valerse a si mismo"
        }
    }

    It 'muchos asteriscos seguidos no cuelgan ni cambian el resultado' {
        $largo = ('a' * 200) + '.txt'
        $reloj = [Diagnostics.Stopwatch]::StartNew()
        $r = Test-CoincideComodin -Nombre $largo -Patron (('*' * 30) + 'zzz')
        $reloj.Stop()
        $r | Should -BeFalse
        $reloj.Elapsed.TotalSeconds | Should -BeLessThan 2
    }
}

Describe 'Get-VistaArchivos' {

    BeforeAll {
        $script:indice = New-IndiceFalso -Filas $script:FilasBase
    }

    It 'ordena por BYTES y no por el tamanyo formateado' {
        $vista = @(Get-VistaArchivos -Indice $script:indice -Cuantos 3)
        # 9,52 GB delante de 980 MB. Ordenar por el texto los invertiria,
        # porque "9,52 GB" es alfabeticamente menor que "980 MB".
        @($vista).Count | Should -Be 3
        $vista[0].Nombre | Should -Be 'copia.iso'
        $vista[1].Nombre | Should -Be 'video.mkv'
        $vista[2].Nombre | Should -Be 'basura.tmp'
    }

    It 'ordena por nombre cuando se le pide' {
        $vista = @(Get-VistaArchivos -Indice $script:indice -Cuantos 99 -Orden 'Nombre')
        @($vista).Count | Should -Be 8
        $vista[0].Nombre | Should -Be 'anyo ñ.txt'
        $vista[-1].Nombre | Should -Be 'video.mkv'
    }

    It 'recorta a los que se le piden' {
        @(Get-VistaArchivos -Indice $script:indice -Cuantos 1).Count | Should -Be 1
        @(Get-VistaArchivos -Indice $script:indice -Cuantos 8).Count | Should -Be 8
        # Pedir mas de los que hay devuelve los que hay, no falla.
        @(Get-VistaArchivos -Indice $script:indice -Cuantos 500).Count | Should -Be 8
    }

    It 'cero o menos filas devuelve una lista vacia y no lanza' {
        @(Get-VistaArchivos -Indice $script:indice -Cuantos 0).Count  | Should -Be 0
        @(Get-VistaArchivos -Indice $script:indice -Cuantos -5).Count | Should -Be 0
    }

    It 'busca con comodines sobre el nombre' {
        $tmp = @(Get-VistaArchivos -Indice $script:indice -Buscar '*.tmp' -Cuantos 99)
        @($tmp).Count | Should -Be 2
        # Y sigue ordenado por tamanyo dentro del filtro.
        $tmp[0].Nombre | Should -Be 'basura.tmp'
        $tmp[1].Nombre | Should -Be 'otro.tmp'
    }

    It 'la busqueda de un nombre con corchetes encuentra ese archivo y solo ese' {
        $r = @(Get-VistaArchivos -Indice $script:indice -Buscar 'foto[1].jpg' -Cuantos 99)
        @($r).Count | Should -Be 1
        $r[0].Nombre | Should -Be 'foto[1].jpg'
    }

    It 'foto?.jpg encuentra las dos fotos numeradas y no la de corchetes' {
        $r = @(Get-VistaArchivos -Indice $script:indice -Buscar 'foto?.jpg' -Cuantos 99)
        @($r | ForEach-Object { $_.Nombre }) | Should -Be @('foto1.jpg', 'foto2.jpg')
    }

    It 'una busqueda vacia no filtra' {
        @(Get-VistaArchivos -Indice $script:indice -Buscar '' -Cuantos 99).Count | Should -Be 8
        @(Get-VistaArchivos -Indice $script:indice -Buscar $null -Cuantos 99).Count | Should -Be 8
    }

    It 'una busqueda sin coincidencias devuelve una lista vacia y no lanza' {
        @(Get-VistaArchivos -Indice $script:indice -Buscar '*.iso.no' -Cuantos 99).Count | Should -Be 0
    }

    It 'un indice nulo devuelve una lista vacia y no lanza' {
        { Get-VistaArchivos -Indice $null } | Should -Not -Throw
        @(Get-VistaArchivos -Indice $null).Count | Should -Be 0
    }

    It 'un indice sin lista de archivos devuelve una lista vacia y no lanza' {
        $vacio = New-IndiceFalso -Filas $null
        { Get-VistaArchivos -Indice $vacio } | Should -Not -Throw
        @(Get-VistaArchivos -Indice $vacio).Count | Should -Be 0

        $sinPropiedad = [pscustomobject]@{ Bytes = 0.0 }
        { Get-VistaArchivos -Indice $sinPropiedad } | Should -Not -Throw
        @(Get-VistaArchivos -Indice $sinPropiedad).Count | Should -Be 0
    }

    It 'las filas nulas dentro de la lista se saltan sin lanzar' {
        $conNulos = New-IndiceFalso -Filas @($script:FilasBase[0], $null, $script:FilasBase[1])
        { Get-VistaArchivos -Indice $conNulos -Cuantos 99 } | Should -Not -Throw
        @(Get-VistaArchivos -Indice $conNulos -Cuantos 99).Count | Should -Be 2
    }

    It 'rechaza un orden que no existe' {
        { Get-VistaArchivos -Indice $script:indice -Orden 'Inventado' } | Should -Throw
    }
}

Describe 'Lo que sale de la vista NO es un candidato' {

    <#
        La regla de [VIS-02]: esta vista ensenya el disco, no lo limpia.
        Una fila con Seleccionado es una fila que la ventana sabe marcar,
        y marcar es el primer paso de borrar. La unica forma de que eso no
        pueda pasar es que la propiedad no exista en lo que se devuelve.
    #>

    BeforeAll {
        # Indice HOSTIL: sus filas llevan ya las propiedades de un
        # candidato. Si Get-VistaArchivos devolviera las filas tal cual en
        # vez de copiarlas, viajarian hasta la tabla.
        $script:hostil = New-IndiceFalso -Filas @(
            [pscustomobject]@{
                Ruta = 'C:\datos\trampa.iso'; Nombre = 'trampa.iso'; Carpeta = 'C:\datos'
                Extension = '.iso'; Bytes = 999999999.0; Ultimo = [datetime]'2026-01-15'
                Seleccionado = $true; Riesgo = 'Bajo'; Metodo = 'Ruta'; ModuloId = 'inventado'
                ClaveExclusion = 'x'; Hecho = $false; Aviso = ''; Efecto = ''
            }
        )
        $script:filaHostil = @(Get-VistaArchivos -Indice $script:hostil -Cuantos 9)[0]
        $script:propsHostil = @($script:filaHostil.PSObject.Properties.Name)
    }

    It 'ninguna fila devuelta trae las propiedades que hacen borrable a un candidato' {
        foreach ($prohibida in @('Seleccionado', 'Riesgo', 'Metodo', 'ModuloId',
                                 'ClaveExclusion', 'Hecho', 'Aviso', 'Efecto',
                                 'BytesLiberados', 'ForzarPermanente')) {
            $script:propsHostil | Should -Not -Contain $prohibida `
                -Because 'una fila informativa que se parece a un candidato acaba marcada'
        }
    }

    It 'devuelve exactamente los campos de mostrar, ni uno mas' {
        # La guarda: si esta lista se quedara vacia, la prueba de arriba
        # tampoco estaria comprobando nada.
        @($script:propsHostil).Count | Should -Be 6
        foreach ($esperada in @('Ruta', 'Nombre', 'Carpeta', 'Extension', 'Bytes', 'Ultimo')) {
            $script:propsHostil | Should -Contain $esperada
        }
    }

    It 'y aun asi conserva los datos que hay que ensenyar' {
        $script:filaHostil.Nombre | Should -Be 'trampa.iso'
        $script:filaHostil.Bytes  | Should -Be 999999999.0
    }
}

Describe 'Get-ResumenVistaArchivos: las tres situaciones' {

    <#
        Tres huecos que sin esto se ven iguales, y la tercera es la
        peligrosa porque hace creer que el analisis fallo.
    #>

    BeforeAll {
        $script:indice = New-IndiceFalso -Filas $script:FilasBase
    }

    It '(a) sin nada por encima del umbral lo dice, y dice que el analisis fue bien' {
        $texto = Get-ResumenVistaArchivos -Indice (New-IndiceFalso -Filas @() -UmbralArchivo 1MB)
        $texto | Should -Match 'Ningún archivo llega a'
        # Se compara contra Format-Tamano y no contra '1,0 MB' literal: el
        # separador decimal depende de la cultura, y la suite corre en
        # Linux con la invariante y en Windows en espanyol.
        $texto | Should -Match ([regex]::Escape((Format-Tamano 1MB)))
        $texto | Should -Match 'pequeños'
        $texto | Should -Not -Match 'coincide'
    }

    It '(b) con archivos pero sin coincidencias culpa a la busqueda, no al analisis' {
        $texto = Get-ResumenVistaArchivos -Indice $script:indice -Buscar '*.iso.no'
        $texto | Should -Match 'Ninguno de los 8 archivos'
        $texto | Should -Match '«\*\.iso\.no»'
        $texto | Should -Not -Match 'Ningún archivo llega a'
    }

    It '(c) con mas de los que se ensenyan nombra los DOS numeros' {
        $texto = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 3
        $texto | Should -Match 'Se muestran los 3 mayores de 8 archivos'
        $texto | Should -Match 'quedan 5 más sin mostrar'
    }

    It 'las tres situaciones dan tres textos DISTINTOS' {
        # La invariante de este apartado. Si dos coincidieran, el usuario
        # volveria a ver el mismo hueco para tres causas distintas, que es
        # exactamente el fallo que esto viene a arreglar.
        $a = Get-ResumenVistaArchivos -Indice (New-IndiceFalso -Filas @())
        $b = Get-ResumenVistaArchivos -Indice $script:indice -Buscar '*.iso.no'
        $c = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 3
        @($a, $b, $c) | Should -Not -Contain ''
        (@($a, $b, $c) | Select-Object -Unique).Count | Should -Be 3
    }

    It 'cuando se ensenya todo no promete que haya mas' {
        $texto = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 99
        $texto | Should -Match 'todos'
        $texto | Should -Not -Match 'sin mostrar'
    }

    It 'nunca escribe "1 elementos" ni "1 archivos" ni "queda 1 más" en plural' {
        $uno = New-IndiceFalso -Filas @($script:FilasBase[0])

        $solo = Get-ResumenVistaArchivos -Indice $uno -Cuantos 99
        $solo | Should -Match 'el único archivo'
        $solo | Should -Not -Match '1 archivos'

        $sinCoincidir = Get-ResumenVistaArchivos -Indice $uno -Buscar '*.zzz'
        $sinCoincidir | Should -Match 'El único archivo'
        $sinCoincidir | Should -Not -Match 'Ninguno de los 1'

        $dos = New-IndiceFalso -Filas @($script:FilasBase[0], $script:FilasBase[1])
        $cola = Get-ResumenVistaArchivos -Indice $dos -Cuantos 1
        $cola | Should -Match 'queda 1 más sin mostrar'
        $cola | Should -Not -Match 'quedan 1'
    }

    It 'dice el orden que se ha aplicado, no uno inventado' {
        $porTamano = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 3 -Orden 'Tamano'
        $porNombre = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 3 -Orden 'Nombre'
        $porTamano | Should -Match 'mayores'
        $porNombre | Should -Match 'orden alfabético'
        $porNombre | Should -Not -Match 'mayores'
    }

    It 'lleva tildes y enyes de verdad' {
        $texto = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 3
        # Sin esta guarda, un archivo guardado sin BOM dejaria los textos
        # llenos de simbolos raros y ninguna prueba se enteraria.
        $texto | Should -Match '[áéíóúñ]'
        $texto | Should -Not -Match 'Ã'
    }

    It 'un indice nulo no lanza y no dice que el analisis fallara' {
        { Get-ResumenVistaArchivos -Indice $null } | Should -Not -Throw
        $texto = Get-ResumenVistaArchivos -Indice $null
        [string]::IsNullOrWhiteSpace($texto) | Should -BeFalse
    }

    It 'un indice sin lista de archivos no lanza' {
        { Get-ResumenVistaArchivos -Indice (New-IndiceFalso -Filas $null) } | Should -Not -Throw
        { Get-ResumenVistaArchivos -Indice ([pscustomobject]@{ Bytes = 0.0 }) } | Should -Not -Throw
    }

    It 'pedir cero filas se dice, no se calla' {
        $texto = Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 0
        $texto | Should -Match 'no se está mostrando ninguno'
    }

    It 'ningun texto propone borrar nada' {
        $textos = @(
            (Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 3)
            (Get-ResumenVistaArchivos -Indice $script:indice -Cuantos 99)
            (Get-ResumenVistaArchivos -Indice $script:indice -Buscar '*.tmp' -Cuantos 1)
        )
        foreach ($t in $textos) {
            $t | Should -Match 'no se propone borrar nada'
        }
    }
}

Describe 'La vista y su resumen no pueden divergir' {

    <#
        Dos ValidateSet copiados a mano son dos listas que acaban diciendo
        cosas distintas, y entonces el resumen describe un orden que la
        consulta no ha aplicado. Es el mismo patron de [ARQ-01].

        Desde que el modo consola usa la vista son TRES los sitios que
        escriben la lista a mano: la consulta, el resumen y el parametro
        -Orden de Show-InformeEspacio. PowerShell no deja poner una llamada
        a funcion dentro de un atributo, asi que la copia es inevitable; lo
        que no es inevitable es que se separen sin que nadie se entere.
    #>

    BeforeAll {
        $script:ordenes = @(Get-OrdenesVistaArchivos)
        $script:archivoFuente = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'VistaArchivos.ps1'

        # Show-InformeEspacio vive en el modo consola, no en el nucleo, y
        # aqui solo se le miran los METADATOS: cargarlo no ejecuta nada.
        . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Cli') 'Espacio.ps1')

        # Los tres sitios que tienen que decir lo mismo. Si alguien anyade
        # un cuarto y no lo mete aqui, esta invariante no lo protege; por
        # eso la lista esta en un solo sitio y con el porque escrito.
        $script:ConOrden = @('Get-VistaArchivos', 'Get-ResumenVistaArchivos', 'Show-InformeEspacio')
    }

    It 'Get-OrdenesVistaArchivos dice algo' {
        @($script:ordenes).Count | Should -BeGreaterThan 1
    }

    It 'las tres funciones que hablan de orden estan cargadas' {
        # La guarda. Sin ella, si Espacio.ps1 dejara de cargarse, el bucle
        # de abajo recorreria una lista de nombres que no existen y la
        # prueba fallaria por el motivo equivocado -o peor, dejaria de
        # mirar el sitio nuevo sin decirlo.
        foreach ($nombre in $script:ConOrden) {
            @(Get-Command $nombre -ErrorAction SilentlyContinue).Count |
                Should -Be 1 -Because "$nombre tiene que existir para poder mirarle el ValidateSet"
        }
    }

    It 'las tres funciones aceptan exactamente los mismos ordenes' {
        foreach ($nombre in $script:ConOrden) {
            $atributo = @((Get-Command $nombre).Parameters['Orden'].Attributes |
                          Where-Object { $_ -is [ValidateSet] })
            @($atributo).Count | Should -Be 1 -Because "$nombre tiene que validar el orden"
            $valores = @($atributo[0].ValidValues | Sort-Object)
            ($valores -join ',') | Should -Be (($script:ordenes | Sort-Object) -join ',') `
                -Because "$nombre no puede aceptar un orden que la lista no conoce"
        }
    }

    It 'el archivo del nucleo no usa -like para los comodines' {
        # Las pruebas que buscan texto encuentran tus propios comentarios:
        # ha pasado siete veces. Se quitan los bloques <# #> ANTES que las
        # lineas que empiezan por #, porque al reves el primer paso se
        # lleva la linea del #> y el bloque se queda sin cierre.
        $texto = [IO.File]::ReadAllText($script:archivoFuente)
        $codigo = [regex]::Replace($texto, '(?s)<#.*?#>', '')
        $codigo = [regex]::Replace($codigo, '(?m)^\s*#.*$', '')

        # Guarda: si el despiece se comiera el archivo entero, esta prueba
        # pasaria sin mirar nada.
        $codigo | Should -Match 'function Test-CoincideComodin'
        $codigo | Should -Match 'regex\]::Escape'
        $codigo | Should -Not -Match '\-like'
    }
}
