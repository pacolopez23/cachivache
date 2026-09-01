<#
    Las cuatro funciones que deciden QUE BINARIO se lanza y DONDE se
    escribe, que hasta hoy no nombraba ninguna prueba.

    Las dos primeras son la defensa contra el secuestro del orden de
    busqueda de Windows:

      Resolve-EjecutableDeSistema  ancla cualquier herramienta de Windows
                                   a System32 del propio equipo. Sin ese
                                   anclaje, un nombre suelto lo resuelve
                                   Windows mirando antes la carpeta del
                                   programa y el directorio actual, y el
                                   .zip se descomprime donde quiera el
                                   usuario. El modulo de archivos de
                                   sistema lo hacia asi DENTRO de la rama
                                   que solo corre como administrador.

      Get-RutaPowerShell           es la UNICA linea del programa que
                                   ejecuta algo elevado. Un powershell.exe
                                   ajeno resuelto por orden de busqueda
                                   ahi no es una molestia: es una
                                   escalada de privilegios.

    POR QUE HAY UN System32 DE MENTIRA. Las cuatro leen variables de
    entorno de Windows -$env:SystemRoot, $env:LOCALAPPDATA- que en Linux
    estan vacias, asi que aqui devolverian $null siempre y una prueba que
    se conformara con eso no estaria probando ni una sola de sus
    decisiones: pasaria igual de verde con el cuerpo de la funcion
    borrado. Por eso se fabrica un arbol de carpetas de mentira, se apunta
    la variable ahi, y se ejercita la logica de verdad. Mismo criterio que
    ya usa Comandos.Tests.ps1 con 'dism'.

    Y las rutas esperadas se calculan con LA MISMA expresion Join-Path que
    usa el codigo, nunca a mano: en Windows 'System32\x.exe' son dos
    niveles y en Linux Join-Path normaliza las barras, asi que suponer el
    camino en vez de construirlo es como se escribe una prueba que crea un
    archivo donde nadie lo busca y aprueba por el motivo equivocado.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Los parametros que PowerShell anyade solo, para poder preguntar por
    # los que declara de verdad una funcion.
    $script:Comunes = @([Management.Automation.PSCmdlet]::CommonParameters) +
                      @([Management.Automation.PSCmdlet]::OptionalCommonParameters)
}

Describe 'Resolve-EjecutableDeSistema: nada que no cuelgue de System32' {

    BeforeAll {
        $script:SystemRootAnterior = $env:SystemRoot

        $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('sys32-' + [guid]::NewGuid().ToString('N'))
        $script:System32 = Join-Path $script:Taller 'System32'
        [void](New-Item -ItemType Directory -Path $script:System32 -Force)

        # Lo legitimo: una herramienta de Windows en su sitio.
        $script:DismEsperado = Join-Path (Join-Path $script:Taller 'System32') 'Dism.exe'
        Set-Content -LiteralPath $script:DismEsperado -Value 'no es un ejecutable de verdad'

        # Una CARPETA con nombre de programa: existe, pero no es un
        # archivo. Sin -PathType Leaf se devolveria como si lo fuera.
        [void](New-Item -ItemType Directory -Path (Join-Path $script:System32 'carpeta.exe') -Force)

        # EL CEBO QUE IMPORTA: un ejecutable que existe de verdad JUSTO
        # FUERA de System32. Sin la comprobacion de separadores y de '..',
        # Join-Path + Test-Path lo alcanzarian sin quejarse.
        $script:Fuera = Join-Path $script:Taller 'evil.exe'
        Set-Content -LiteralPath $script:Fuera -Value 'el binario del atacante'

        # Y otro DENTRO de un subdirectorio: alcanzable con una barra en
        # el nombre si nadie prohibe las barras.
        [void](New-Item -ItemType Directory -Path (Join-Path $script:System32 'sub') -Force)
        $script:EnSubcarpeta = Join-Path (Join-Path $script:System32 'sub') 'Dism.exe'
        Set-Content -LiteralPath $script:EnSubcarpeta -Value 'otro binario'

        $env:SystemRoot = $script:Taller
    }

    AfterAll {
        $env:SystemRoot = $script:SystemRootAnterior
        Remove-Item -LiteralPath $script:Taller -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'resuelve un nombre normal a la ruta anclada bajo System32' {
        Resolve-EjecutableDeSistema -Nombre 'Dism.exe' | Should -Be $script:DismEsperado
    }

    It 'devuelve un unico valor, no una lista' {
        # .Count sobre un objeto suelto vale $null en 5.1: se envuelve en
        # @() para que esto signifique lo mismo en las dos versiones.
        @(Resolve-EjecutableDeSistema -Nombre 'Dism.exe').Count | Should -Be 1
    }

    It 'devuelve $null si el nombre no existe bajo System32' {
        Resolve-EjecutableDeSistema -Nombre 'NoExisteEnAbsoluto.exe' | Should -BeNullOrEmpty
    }

    It 'una carpeta con nombre de programa no se resuelve como si fuera un ejecutable' {
        # Guarda: si el cebo no estuviera, esta prueba no comprobaria nada.
        Test-Path -LiteralPath (Join-Path $script:System32 'carpeta.exe') -PathType Container |
            Should -BeTrue -Because 'sin la carpeta cebo esta prueba no mira nada'
        Resolve-EjecutableDeSistema -Nombre 'carpeta.exe' | Should -BeNullOrEmpty
    }

    It 'no se puede salir de System32 con .. aunque el archivo exista de verdad' {
        # LA GUARDA ES LA PRUEBA: se comprueba que, sin el filtro, la ruta
        # compuesta SI llegaria al binario de fuera. Si esta linea dejara
        # de ser cierta, las de abajo pasarian por no encontrar nada, que
        # es exactamente la prueba hueca que se quiere evitar.
        Test-Path -LiteralPath (Join-Path $script:System32 '..\evil.exe') -PathType Leaf |
            Should -BeTrue -Because 'el cebo tiene que ser alcanzable para que rechazarlo signifique algo'

        foreach ($salida in @('..\evil.exe', '../evil.exe', '..\..\evil.exe', '..')) {
            Resolve-EjecutableDeSistema -Nombre $salida |
                Should -BeNullOrEmpty -Because "'$salida' sale de System32"
        }
    }

    It 'un nombre con barra no se resuelve, ni siquiera hacia dentro de System32' {
        # Mismo criterio que arriba: el destino existe, asi que el $null
        # solo puede venir del filtro de separadores.
        Test-Path -LiteralPath $script:EnSubcarpeta -PathType Leaf |
            Should -BeTrue -Because 'sin el cebo, el rechazo no significaria nada'

        foreach ($conBarra in @('sub\Dism.exe', 'sub/Dism.exe')) {
            Resolve-EjecutableDeSistema -Nombre $conBarra |
                Should -BeNullOrEmpty -Because "'$conBarra' no es un nombre de archivo, es una ruta"
        }
    }

    It 'un nombre con dos puntos no se resuelve' {
        # En Windows 'C:Dism.exe' es una ruta relativa a la unidad y
        # 'C:\...' una absoluta: las dos dejarian de estar ancladas al
        # System32 de este equipo, que es lo unico que hace fiable el
        # resultado.
        foreach ($conDosPuntos in @('C:Dism.exe', 'C:\Windows\System32\Dism.exe', 'x:y')) {
            Resolve-EjecutableDeSistema -Nombre $conDosPuntos |
                Should -BeNullOrEmpty -Because "'$conDosPuntos' lleva unidad"
        }
    }

    It 'los dos puntos se rechazan aunque no vayan con separador' {
        # El filtro mira '..' en cualquier posicion, no solo formando un
        # nivel: es deliberadamente conservador porque el coste de
        # rechazar un nombre raro es cero y el de aceptarlo, ejecutar algo
        # de fuera de System32.
        Resolve-EjecutableDeSistema -Nombre '..Dism.exe' | Should -BeNullOrEmpty
    }

    It 'un SystemRoot vacio o en blanco no resuelve nada' {
        # Con SystemRoot en blanco, Join-Path compondria una ruta relativa
        # al directorio actual: justo el sitio del que esta funcion existe
        # para no fiarse.
        try {
            foreach ($vacio in @('', '   ')) {
                $env:SystemRoot = $vacio
                Resolve-EjecutableDeSistema -Nombre 'Dism.exe' |
                    Should -BeNullOrEmpty -Because 'sin SystemRoot no hay System32 en el que confiar'
            }
        } finally {
            $env:SystemRoot = $script:Taller
        }
        # Y se comprueba que el nombre volveria a resolver: si no, lo de
        # arriba habria pasado por el motivo equivocado.
        Resolve-EjecutableDeSistema -Nombre 'Dism.exe' | Should -Be $script:DismEsperado
    }

    It 'no consulta el PATH' {
        # La cabecera del archivo promete que "ninguna de las dos consulta
        # jamas el PATH". Eso fue mentira hasta [SEG-30] en la funcion
        # hermana, asi que aqui se convierte en algo verificable: si
        # alguien mete un Get-Command, esta prueba lanza.
        Mock Get-Command { throw 'Resolve-EjecutableDeSistema no debe consultar el PATH' }

        { Resolve-EjecutableDeSistema -Nombre 'Dism.exe' } | Should -Not -Throw
        { Resolve-EjecutableDeSistema -Nombre 'vssadmin.exe' } | Should -Not -Throw
    }

    It 'un nombre en blanco no revienta' {
        # No puede ser cadena vacia -el parametro es Mandatory-, pero si
        # espacios. Que no lance importa porque quien llama esta a mitad
        # de un analisis.
        { Resolve-EjecutableDeSistema -Nombre '   ' } | Should -Not -Throw
        Resolve-EjecutableDeSistema -Nombre '   ' | Should -BeNullOrEmpty
    }
}

Describe 'Get-RutaPowerShell: la unica linea que se lanza elevada' {

    BeforeAll {
        $script:SystemRootAnterior = $env:SystemRoot

        $script:Windir = Join-Path ([IO.Path]::GetTempPath()) ('windir-' + [guid]::NewGuid().ToString('N'))

        # La ruta se compone con la MISMA expresion que el codigo. En
        # Windows son cuatro niveles de carpeta; en Linux, Join-Path
        # normaliza las barras invertidas. Componerla a mano seria
        # inventarse un camino que la funcion no mira.
        $script:PsEsperado = Join-Path $script:Windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        [void](New-Item -ItemType Directory -Path (Split-Path $script:PsEsperado -Parent) -Force)
        Set-Content -LiteralPath $script:PsEsperado -Value 'el powershell de Windows'

        # Un segundo arbol IGUAL pero sin el powershell.exe legitimo y con
        # dos cebos en los sitios donde el orden de busqueda de Windows
        # miraria antes. Aqui la respuesta correcta es $null: mejor no
        # ofrecer elevacion que elevar cualquier cosa.
        $script:SoloCebos = Join-Path ([IO.Path]::GetTempPath()) ('cebos-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $script:SoloCebos 'System32') -Force)
        $script:CeboRaiz = Join-Path $script:SoloCebos 'powershell.exe'
        $script:CeboSystem32 = Join-Path (Join-Path $script:SoloCebos 'System32') 'powershell.exe'
        Set-Content -LiteralPath $script:CeboRaiz -Value 'el powershell del atacante'
        Set-Content -LiteralPath $script:CeboSystem32 -Value 'el powershell del atacante'

        $env:SystemRoot = $script:Windir
    }

    AfterAll {
        $env:SystemRoot = $script:SystemRootAnterior
        Remove-Item -LiteralPath $script:Windir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:SoloCebos -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'devuelve exactamente el powershell.exe de System32\WindowsPowerShell\v1.0' {
        Get-RutaPowerShell | Should -Be $script:PsEsperado
    }

    It 'la ruta devuelta cuelga del SystemRoot de este equipo' {
        # Lo que hace fiable el resultado no es el nombre del archivo, es
        # de donde cuelga. Una ruta escrita a mano -C:\Windows\...- pasaria
        # la prueba de arriba en un Windows real y seria falsa en cualquier
        # equipo con Windows instalado en otro sitio.
        (Get-RutaPowerShell).StartsWith($script:Windir) | Should -BeTrue
    }

    It 'devuelve un unico valor, no una lista' {
        @(Get-RutaPowerShell).Count | Should -Be 1
    }

    It 'no cae en un powershell.exe colocado en la raiz de Windows ni en System32' {
        try {
            $env:SystemRoot = $script:SoloCebos

            # Guardas: los dos cebos existen y son alcanzables. Sin esto,
            # el $null de abajo podria venir de que no hay nada que
            # encontrar en vez de de que se rechaza lo que hay.
            Test-Path -LiteralPath $script:CeboRaiz -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $script:CeboSystem32 -PathType Leaf | Should -BeTrue

            Get-RutaPowerShell |
                Should -BeNullOrEmpty -Because 'no elevar es mejor que elevar un binario ajeno'
        } finally {
            $env:SystemRoot = $script:Windir
        }
    }

    It 'un SystemRoot vacio o en blanco devuelve $null' {
        try {
            foreach ($vacio in @('', '   ')) {
                $env:SystemRoot = $vacio
                Get-RutaPowerShell | Should -BeNullOrEmpty
            }
        } finally {
            $env:SystemRoot = $script:Windir
        }
        Get-RutaPowerShell | Should -Be $script:PsEsperado
    }

    It 'no consulta el PATH' {
        Mock Get-Command { throw 'Get-RutaPowerShell no debe consultar el PATH' }
        { Get-RutaPowerShell } | Should -Not -Throw
    }

    It 'no acepta ningun parametro: quien llama no elige que se eleva' {
        # No es una formalidad. Si esta funcion admitiera una ruta, el
        # destino de la unica llamada elevada del programa pasaria a
        # decidirlo quien llama, y el anclaje a System32 dejaria de valer
        # de nada.
        $declarados = @((Get-Command Get-RutaPowerShell).Parameters.Keys |
                        Where-Object { $script:Comunes -notcontains $_ })
        $declarados | Should -BeNullOrEmpty -Because 'lo que se eleva no puede venir de fuera'
    }
}

Describe 'Test-EsAdministrador' {

    # LO QUE AQUI NO SE PUEDE CUBRIR, Y POR QUE.
    #
    # La rama buena de esta funcion pregunta a WindowsIdentity, que solo
    # existe en Windows: en Linux, .NET lanza al llamarla y se ejecuta el
    # catch. Y en Windows, decidir si la respuesta es correcta exigiria un
    # oraculo independiente -que el proceso este elevado de verdad-, cosa
    # que las pruebas no controlan ni deben controlar. Asi que aqui se
    # comprueba lo que si se puede: que nunca lanza, que devuelve un
    # booleano de verdad, que es estable, y sobre todo QUE FALLA HACIA EL
    # LADO SEGURO. Lo que queda sin cubrir es el IsInRole verdadero de un
    # proceso elevado; eso solo lo ve la integracion continua en Windows,
    # y aun alli solo con el valor que le toque.

    It 'devuelve un booleano de verdad, no $null ni una cadena' {
        # Quien la llama la usa como condicion: un $null se leeria como
        # "no soy administrador" por casualidad, no por decision.
        $r = Test-EsAdministrador
        @($r).Count | Should -Be 1
        $r -is [bool] | Should -BeTrue
    }

    It 'no lanza nunca, ni siquiera donde la identidad de Windows no existe' {
        { Test-EsAdministrador } | Should -Not -Throw
    }

    It 'es estable: dos llamadas seguidas dicen lo mismo' {
        Test-EsAdministrador | Should -Be (Test-EsAdministrador)
    }

    # El valor de -Skip lo lee Pester en el DESCUBRIMIENTO, y lo que se
    # asigna en un BeforeAll todavia no existe entonces: $script:EsWindows
    # llegaria como $null y las dos pruebas se ejecutarian en las dos
    # plataformas. Por eso la condicion se escribe entera aqui.
    It 'si no se puede saber, la respuesta es NO' -Skip:($IsWindows -or ($null -eq $IsWindows)) {
        # Aqui la llamada a WindowsIdentity lanza, asi que esto ejercita
        # el catch. Que el catch devuelva $false y no $true es la unica
        # decision que toma la funcion: creerse administrador sin serlo
        # llevaria al programa a saltarse la elevacion y a intentar
        # borrados privilegiados que fallarian uno a uno.
        Test-EsAdministrador | Should -BeFalse
    }

    It 'en Windows responde lo mismo que la propia API, ni mas ni menos' `
        -Skip:(-not ($IsWindows -or ($null -eq $IsWindows))) {
        # No es repetir la implementacion por gusto: esto cae en rojo si
        # alguien devuelve una constante, invierte la condicion o consulta
        # un rol distinto del de administrador -por ejemplo PowerUser-,
        # que son las tres formas en que esta funcion puede mentir.
        $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identidad)
        $esperado = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Test-EsAdministrador | Should -Be $esperado
    }
}

Describe 'Get-CarpetaDatos' {

    BeforeAll {
        $script:LocalAnterior = $env:LOCALAPPDATA
        $script:TempAnterior = $env:TEMP
        $script:BaseDatos = Join-Path ([IO.Path]::GetTempPath()) ('datos-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:BaseDatos -Force)
    }

    AfterAll {
        $env:LOCALAPPDATA = $script:LocalAnterior
        $env:TEMP = $script:TempAnterior
        Remove-Item -LiteralPath $script:BaseDatos -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'cuelga de LOCALAPPDATA y se llama Cachivache' {
        $base = Join-Path $script:BaseDatos 'caso-local'
        try {
            $env:LOCALAPPDATA = $base
            $carpeta = Get-CarpetaDatos
            @($carpeta).Count | Should -Be 1
            $carpeta | Should -Be (Join-Path $base 'Cachivache')
        } finally {
            $env:LOCALAPPDATA = $script:LocalAnterior
        }
    }

    It 'crea la carpeta y sus dos subcarpetas, no solo devuelve el nombre' {
        # La funcion promete carpeta PARA GUARDAR: si solo compusiera la
        # ruta, el registro y los informes fallarian al escribir mucho mas
        # tarde y lejos de aqui. Ya paso una vez con informes que se
        # anunciaban guardados sin escribirse.
        $base = Join-Path $script:BaseDatos 'caso-crea'
        try {
            $env:LOCALAPPDATA = $base
            $carpeta = Get-CarpetaDatos
            Test-Path -LiteralPath $carpeta -PathType Container | Should -BeTrue
            foreach ($sub in @('informes', 'registros')) {
                Test-Path -LiteralPath (Join-Path $carpeta $sub) -PathType Container |
                    Should -BeTrue -Because "hace falta la subcarpeta '$sub'"
            }
        } finally {
            $env:LOCALAPPDATA = $script:LocalAnterior
        }
    }

    It 'llamarla dos veces no lanza ni se lleva por delante lo ya guardado' {
        # Se llama en cada arranque y desde varios sitios. Un New-Item
        # -Force sobre una carpeta que ya existe no borra nada, y esta
        # prueba es lo que impide que alguien lo cambie por algo que si.
        $base = Join-Path $script:BaseDatos 'caso-idem'
        try {
            $env:LOCALAPPDATA = $base
            $primera = Get-CarpetaDatos
            $informe = Join-Path (Join-Path $primera 'informes') 'informe-viejo.html'
            Set-Content -LiteralPath $informe -Value 'un informe de una ejecucion anterior'

            $segunda = Get-CarpetaDatos
            $segunda | Should -Be $primera
            Test-Path -LiteralPath $informe -PathType Leaf |
                Should -BeTrue -Because 'los informes anteriores no se tocan'
        } finally {
            $env:LOCALAPPDATA = $script:LocalAnterior
        }
    }

    It 'sin LOCALAPPDATA cae a TEMP' {
        # La rama de respaldo. Sin ella, un entorno sin LOCALAPPDATA
        # dejaria al programa componiendo una ruta relativa al directorio
        # actual, que es justo lo que el docblock dice que no quiere.
        $base = Join-Path $script:BaseDatos 'caso-temp'
        try {
            foreach ($vacio in @('', '   ')) {
                $env:LOCALAPPDATA = $vacio
                $env:TEMP = $base
                Get-CarpetaDatos | Should -Be (Join-Path $base 'Cachivache')
            }
        } finally {
            $env:LOCALAPPDATA = $script:LocalAnterior
            $env:TEMP = $script:TempAnterior
        }
    }

    It 'nunca escribe dentro del arbol del proyecto' {
        # El motivo escrito en el docblock: el repositorio se tiene que
        # poder clonar en solo lectura y no se ensucia con datos
        # generados. Si alguien cambiara la base por la carpeta del
        # programa, esto se pone rojo.
        $base = Join-Path $script:BaseDatos 'caso-fuera'
        try {
            $env:LOCALAPPDATA = $base
            $carpeta = Get-CarpetaDatos
            $carpeta.StartsWith($script:Raiz) |
                Should -BeFalse -Because 'los datos generados no viven en el repositorio'
            $carpeta.StartsWith($base) | Should -BeTrue
        } finally {
            $env:LOCALAPPDATA = $script:LocalAnterior
        }
    }
}
