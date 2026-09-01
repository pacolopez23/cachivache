<#
    LAS DOS FUNCIONES POR LAS QUE PASA TODA LA GUARDIA, Y QUE NADIE PROBABA.

    ConvertTo-RutaNormalizada es el embudo por el que pasan TODAS las
    comparaciones de texto de la guardia. Su docblock cuenta el fallo que
    tapa la linea que quita el prefijo "\\?\": sin ella, "\\?\C:\Windows"
    no casa con la lista negra "C:\Windows" -son cadenas distintas- y en
    cambio SI casa con el patron de recurso de red, que solo mira si la
    ruta empieza por dos barras. La guardia acertaria el veredicto por el
    motivo equivocado, y para una carpeta legitima del propio disco daria
    el veredicto contrario diciendo que es un recurso de red. Aqui se
    exigen las dos mitades: que el prefijo desaparezca Y que lo que queda
    no parezca red.

    Test-CadenaSinEnlaces es lo unico que convierte la lista blanca en una
    afirmacion sobre donde estan los bytes y no sobre una cadena de texto.
    El ataque que tapa esta escrito en su docblock y no necesita permisos
    de administrador:

        mklink /J "%USERPROFILE%\Downloads\copia" "D:\Contabilidad"

    A partir de ahi "...\Downloads\copia\facturas\2025.xlsx" empieza por la
    raiz autorizada y Test-BajoRaiz dice que si. Por eso las pruebas del
    enlace afirman las DOS cosas a la vez: que el texto sigue diciendo
    "esta dentro" y que Test-CadenaSinEnlaces dice que no. Sin la primera
    mitad, la prueba no distinguiria este caso de una ruta que simplemente
    cuelga de otro sitio, y no estaria probando el agujero.
#>

BeforeDiscovery {
    # -Skip SE EVALUA EN EL DESCUBRIMIENTO, no en la ejecucion. Una bandera
    # calculada en BeforeAll vale $null aqui, asi que -Skip:(-not $null)
    # seria -Skip:$true y saltarian TODAS las pruebas del enlace: otra vez
    # la suite en verde sin afirmar nada. Por eso la sonda va en
    # BeforeDiscovery, que es el hueco que Pester ejecuta en esa fase.
    #
    # Y hace falta sondear porque crear enlaces no siempre se puede: en
    # Windows PowerShell 5.1 un enlace simbolico exige el privilegio
    # SeCreateSymbolicLink o el modo desarrollador. El junction NO lo
    # exige -es justo el motivo por el que el ataque del docblock es
    # peligroso-, asi que en Windows se intenta primero ese.
    $script:PuedeEnlazar = $false
    $sonda = Join-Path ([IO.Path]::GetTempPath()) ('sonda-enlace-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path (Join-Path $sonda 'destino') -Force)
        # $IsWindows NO EXISTE en 5.1: vale $null, y "-not $IsWindows" seria
        # verdadero justo en Windows. De ahi el "-or ($null -eq $IsWindows)".
        $tipos = if ($IsWindows -or ($null -eq $IsWindows)) { @('Junction', 'SymbolicLink') } else { @('SymbolicLink') }
        foreach ($tipo in $tipos) {
            try {
                [void](New-Item -ItemType $tipo -Path (Join-Path $sonda 'enlace') `
                                -Target (Join-Path $sonda 'destino') -ErrorAction Stop)
                $script:PuedeEnlazar = $true
                break
            } catch { $script:PuedeEnlazar = $false }
        }
    } catch { $script:PuedeEnlazar = $false }
    finally {
        # Remove-Item sobre un enlace A UNA CARPETA lanza NullReferenceException
        # en 5.1, y -ErrorAction no lo tapa porque es del proveedor.
        # [IO.Directory]::Delete ademas nunca sigue el enlace.
        if (Test-Path -LiteralPath (Join-Path $sonda 'enlace')) {
            try   { [IO.Directory]::Delete((Join-Path $sonda 'enlace'), $false) }
            catch { Write-Verbose ('No se pudo retirar el enlace de sonda: ' + $_.Exception.Message) }
        }
        if (Test-Path -LiteralPath $sonda) {
            Remove-Item -LiteralPath $sonda -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Test-CadenaSinEnlaces mira el disco de verdad: hace falta un taller
    # con carpetas reales. La bandera se recalcula aqui porque BeforeAll
    # corre en la fase de ejecucion, no en la del descubrimiento.
    $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('guardia-cadena-' + [guid]::NewGuid().ToString('N'))

    #   taller/
    #     zona/                 <- la raiz autorizada
    #       suelto.txt
    #       sub/nieta/dentro.txt
    #       atajo -> ../fuera   <- el enlace del ataque
    #     fuera/
    #       oculto/secreto.txt
    $script:Zona    = Join-Path $script:Taller 'zona'
    $script:Nieta   = Join-Path (Join-Path $script:Zona 'sub') 'nieta'
    $script:Fuera   = Join-Path $script:Taller 'fuera'
    $script:Oculto  = Join-Path $script:Fuera 'oculto'
    [void](New-Item -ItemType Directory -Path $script:Nieta  -Force)
    [void](New-Item -ItemType Directory -Path $script:Oculto -Force)

    $script:ArchivoSuelto = Join-Path $script:Zona 'suelto.txt'
    $script:ArchivoHondo  = Join-Path $script:Nieta 'dentro.txt'
    $script:Secreto       = Join-Path $script:Oculto 'secreto.txt'

    # LOS DOS .tmp SON DE LA ULTIMA PRUEBA, Y LA EXTENSION IMPORTA.
    # Test-RutaSegura veta los .txt por extension personal, asi que con un
    # .txt las dos mitades de esa prueba darian $false por ese veto y no
    # por lo que se esta comprobando. Lo caza la mutacion: quitandole a
    # Test-RutaSegura la llamada a Test-CadenaSinEnlaces, la version con
    # .txt seguia en verde. Con .tmp el unico motivo de rechazo que queda
    # es el enlace.
    $script:BorrableLimpio = Join-Path $script:Nieta 'residuo.tmp'
    $script:BorrableFuera  = Join-Path $script:Oculto 'residuo.tmp'
    foreach ($f in @($script:ArchivoSuelto, $script:ArchivoHondo, $script:Secreto,
                     $script:BorrableLimpio, $script:BorrableFuera)) {
        Set-Content -LiteralPath $f -Value 'contenido' -Encoding ascii
    }

    # Solo hace falta para la ultima prueba, la de la costura con
    # Test-RutaSegura. Con carpetas conocidas en blanco para que la lista
    # negra no dependa del perfil de quien ejecute.
    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio = ''; Documentos = ''; Descargas = ''
        Imagenes   = ''; Musica     = ''; Videos     = ''
        CarpetaDatos = ''
    })

    $script:Atajo = Join-Path $script:Zona 'atajo'
    $script:PuedeEnlazar = $false
    $tipos = if ($IsWindows -or ($null -eq $IsWindows)) { @('Junction', 'SymbolicLink') } else { @('SymbolicLink') }
    foreach ($tipo in $tipos) {
        try {
            [void](New-Item -ItemType $tipo -Path $script:Atajo -Target $script:Fuera -ErrorAction Stop)
            $script:PuedeEnlazar = $true
            break
        } catch { $script:PuedeEnlazar = $false }
    }

    # Las dos rutas del ataque: el texto dice "cuelga de zona", los bytes
    # estan en "fuera".
    $script:CarpetaPorAtajo  = Join-Path $script:Atajo 'oculto'
    $script:SecretoPorAtajo  = Join-Path $script:CarpetaPorAtajo 'secreto.txt'
    $script:BorrablePorAtajo = Join-Path $script:CarpetaPorAtajo 'residuo.tmp'
}

AfterAll {
    if ($script:Atajo -and (Test-Path -LiteralPath $script:Atajo)) {
        # Ver el comentario de la sonda: en 5.1 esto NO se borra con
        # Remove-Item. Y borrarlo antes evita que el -Recurse de abajo
        # entre por el enlace y se lleve el destino real.
        try   { [IO.Directory]::Delete($script:Atajo, $false) }
        catch { Write-Verbose ('No se pudo retirar el atajo del taller: ' + $_.Exception.Message) }
    }
    if ($script:Taller -and (Test-Path -LiteralPath $script:Taller)) {
        Remove-Item -LiteralPath $script:Taller -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'ConvertTo-RutaNormalizada' {

    It 'una cadena vacia se queda en cadena vacia' {
        ConvertTo-RutaNormalizada '' | Should -BeExactly ''
    }

    It 'una cadena de solo espacios tambien, y no en espacios' {
        # Sin la guarda de IsNullOrWhiteSpace saldrian los espacios tal
        # cual, y una ruta "en blanco pero no vacia" pasaria por los
        # filtros que preguntan por cadena vacia.
        ConvertTo-RutaNormalizada '   ' | Should -BeExactly ''
    }

    It 'la barra normal, que Windows acepta, se convierte en invertida' {
        ConvertTo-RutaNormalizada 'C:/Users/Paco' | Should -BeExactly 'c:\users\paco'
    }

    It 'la barra final se quita, y tambien si hay varias' {
        ConvertTo-RutaNormalizada 'C:\Temp\'    | Should -BeExactly 'c:\temp'
        ConvertTo-RutaNormalizada 'C:\Temp\\\'  | Should -BeExactly 'c:\temp'
    }

    It 'las mayusculas bajan a minusculas' {
        ConvertTo-RutaNormalizada 'C:\WINDOWS\System32' | Should -BeExactly 'c:\windows\system32'
    }

    It 'el prefijo de ruta larga se despoja: si no, no casaria con la lista negra' {
        # Primera mitad del fallo del docblock: "\\?\C:\Windows" y
        # "C:\Windows" son cadenas distintas, asi que la lista negra
        # -que compara texto- no reconoceria la carpeta protegida.
        ConvertTo-RutaNormalizada '\\?\C:\Windows' | Should -BeExactly 'c:\windows'
    }

    It 'y despues de despojarlo ya no parece un recurso de red' {
        # Segunda mitad, y la peor: el filtro de red solo mira si la ruta
        # empieza por dos barras. Con el prefijo puesto, una carpeta del
        # propio disco se rechazaria diciendo "es un recurso de red".
        ConvertTo-RutaNormalizada '\\?\C:\Windows' | Should -Not -Match '^\\\\'
        ConvertTo-RutaNormalizada '\\?\D:\Juegos\Steam' | Should -Not -Match '^\\\\'
    }

    It 'un recurso de red de verdad sigue empezando por dos barras' {
        # La guarda del caso anterior: si "despojar el prefijo" se hubiera
        # implementado quitando barras a lo bruto, el filtro de red dejaria
        # de disparar donde tiene que disparar. Esta prueba lo impide.
        ConvertTo-RutaNormalizada '\\Servidor\Recurso\' | Should -BeExactly '\\servidor\recurso'
    }

    It 'y un recurso de red escrito en forma larga vuelve a parecerlo' {
        ConvertTo-RutaNormalizada '\\?\UNC\Servidor\Recurso' | Should -BeExactly '\\servidor\recurso'
    }

    It 'CONTRATO: cuatro formas de escribir la MISMA ruta acaban en la misma cadena' {
        # Esto es lo unico que la funcion promete de verdad. Todo lo
        # anterior son las piezas; esto es el porque.
        $formas = @(
            'C:\Users\Paco',
            'C:/Users/Paco/',
            'c:/USERS/paco\',
            '\\?\C:\USERS\PACO'
        )
        # @() alrededor: en 5.1 .Count sobre un objeto suelto vale $null.
        $distintas = @($formas | ForEach-Object { ConvertTo-RutaNormalizada $_ } | Select-Object -Unique)
        $distintas.Count | Should -Be 1
        $distintas[0]    | Should -BeExactly 'c:\users\paco'
    }
}

Describe 'Test-CadenaSinEnlaces' {

    It 'una raiz en blanco no autoriza nada' {
        Test-CadenaSinEnlaces -Ruta $script:ArchivoHondo -Raiz '   ' | Should -BeFalse
    }

    It 'una raiz vacia del todo devuelve que no, y no lanza' {
        # Esta prueba nacio afirmando "Should -Throw", porque eso era lo
        # que hacia el codigo: el Mandatory a secas rechazaba la cadena
        # vacia en el enlazador y la guarda de "falla cerrado" que hay
        # dentro NUNCA se ejecutaba con "". Se arreglo con AllowEmptyString
        # y ahora la guarda es alcanzable.
        #
        # El motivo de arreglarlo en vez de consagrarlo: una funcion de
        # seguridad que LANZA obliga a envolverla en un try, y un try es
        # justo donde un rechazo se convierte por descuido en un permiso.
        # Decir "no" es siempre mejor que explotar.
        Test-CadenaSinEnlaces -Ruta $script:ArchivoHondo -Raiz '' | Should -BeFalse
    }

    It 'una ruta vacia tampoco autoriza nada' {
        Test-CadenaSinEnlaces -Ruta '' -Raiz $script:Zona | Should -BeFalse
    }

    It 'una ruta que no existe se rechaza' {
        # Si un tramo no se puede leer no se puede afirmar que sea seguro.
        Test-CadenaSinEnlaces -Ruta (Join-Path $script:Nieta 'no-existe.txt') -Raiz $script:Zona |
            Should -BeFalse
    }

    It 'un archivo dentro de la raiz pasa' {
        Test-CadenaSinEnlaces -Ruta $script:ArchivoSuelto -Raiz $script:Zona | Should -BeTrue
    }

    It 'un archivo a dos carpetas de hondura tambien: se sube por su .Directory' {
        # Si la funcion arrancara el bucle desde el propio archivo en vez
        # de desde su carpeta, un FileInfo no tiene .Parent, el bucle no
        # daria ni una vuelta y esto devolveria $false.
        Test-CadenaSinEnlaces -Ruta $script:ArchivoHondo -Raiz $script:Zona | Should -BeTrue
    }

    It 'la carpeta que ES la raiz pasa' {
        Test-CadenaSinEnlaces -Ruta $script:Zona -Raiz $script:Zona | Should -BeTrue
    }

    It 'una carpeta intermedia limpia pasa' {
        Test-CadenaSinEnlaces -Ruta $script:Nieta -Raiz $script:Zona | Should -BeTrue
    }

    It 'la raiz se compara normalizada: con barra final da lo mismo' {
        $conBarra = $script:Zona + [IO.Path]::DirectorySeparatorChar
        Test-CadenaSinEnlaces -Ruta $script:ArchivoHondo -Raiz $conBarra | Should -BeTrue
    }

    It 'una ruta que cuelga de otro sitio se rechaza' {
        # Se sube hasta la raiz del disco sin encontrar la raiz autorizada.
        Test-CadenaSinEnlaces -Ruta $script:Secreto -Raiz $script:Zona | Should -BeFalse
    }

    It 'GUARDA: el atajo del taller es de verdad un punto de reanalisis' -Skip:(-not $script:PuedeEnlazar) {
        # Sin esta guarda, si New-Item hubiera creado una carpeta normal
        # las tres pruebas siguientes estarian mirando otra cosa.
        Test-EsEnlace (Get-Item -LiteralPath $script:Atajo -Force) | Should -BeTrue
    }

    It 'el enlace como ultimo tramo del camino se rechaza' -Skip:(-not $script:PuedeEnlazar) {
        Test-CadenaSinEnlaces -Ruta $script:Atajo -Raiz $script:Zona | Should -BeFalse
    }

    It 'EL ATAQUE: un enlace EN MEDIO del camino se rechaza aunque el texto diga que esta dentro' -Skip:(-not $script:PuedeEnlazar) {
        # Las dos afirmaciones juntas son la prueba. La primera es la que
        # la hace valer: sin ella este caso no se distinguiria de una ruta
        # que cuelga de otro sitio, que ya se rechaza por otro motivo.
        Test-BajoRaiz -Ruta $script:SecretoPorAtajo -Raices @($script:Zona) | Should -BeTrue
        Test-CadenaSinEnlaces -Ruta $script:SecretoPorAtajo -Raiz $script:Zona | Should -BeFalse
    }

    It 'y lo mismo cuando lo que cuelga del enlace es una carpeta' -Skip:(-not $script:PuedeEnlazar) {
        Test-BajoRaiz -Ruta $script:CarpetaPorAtajo -Raices @($script:Zona) | Should -BeTrue
        Test-CadenaSinEnlaces -Ruta $script:CarpetaPorAtajo -Raiz $script:Zona | Should -BeFalse
    }

    It 'COSTURA: el veredicto entero lo rechaza, y por ESTE motivo' -Skip:(-not $script:PuedeEnlazar) {
        # Que Test-RutaSegura llame de verdad a esta funcion. Si alguien
        # quitara esa llamada, Test-CadenaSinEnlaces seguiria perfecta y
        # el programa borraria al otro lado del enlace.
        #
        # PRIMERO EL TESTIGO POSITIVO, y no es adorno: sin
        # Initialize-Guardia, Test-RutaSegura devuelve $false para TODO
        # -Test-GuardiaLista lo bloquea- y la segunda linea pasaria sin
        # que la comprobacion del enlace existiera siquiera. Esta primera
        # linea es lo unico que separa "la guardia dice que no" de "la
        # guardia esta apagada".
        # Los dos son .tmp y estan a la misma hondura: lo unico que los
        # diferencia es que el segundo llega por el enlace.
        Test-RutaSegura -Ruta $script:BorrableLimpio   -Raices @($script:Zona) | Should -BeTrue
        Test-RutaSegura -Ruta $script:BorrablePorAtajo -Raices @($script:Zona) | Should -BeFalse

        # Y el mismo veredicto por el motivo correcto: rechazar por el
        # motivo equivocado ya paso una vez en este proyecto.
        Get-MotivoBloqueo -Ruta $script:BorrablePorAtajo -Raices @($script:Zona) |
            Should -BeExactly 'Alguna carpeta del camino es un enlace: la ruta no esta donde parece.'
    }
}
