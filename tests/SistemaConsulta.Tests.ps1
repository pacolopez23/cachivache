<#
    Las seis funciones que preguntan al sistema, y que por eso llevaban
    meses sin una sola prueba.

    Test-ProcesoAbierto, Get-CarpetaConocida, Get-GuidVolumen,
    Get-DestinoAccesoDirecto, Get-EstadoArranque y Get-BibliotecasSteam
    consultan cosas que aqui no existen: el registro de Windows, WMI, los
    objetos COM del Explorador, la instalacion de Steam. La salida facil
    era escribir seis pruebas de "en Linux devuelve nulo" y darlas por
    cubiertas. Eso se queda VERDE aunque la funcion este completamente
    rota en Windows, que es el unico sitio donde se ejecuta de verdad.

    Aqui se hace lo contrario, y en este orden:

      1. CASI TODAS SON "consultar" + "decidir con lo consultado", y la
         segunda mitad se puede probar entera. Se sustituye la consulta
         -con Mock, con el parametro -Shell que la propia funcion ofrece,
         o con un arbol de archivos de verdad en una carpeta temporal- y
         se comprueba la decision: como se normaliza una letra de unidad,
         de donde sale el GUID, que bit del byte de arranque manda, que
         biblioteca de Steam se descarta por no estar montada.

      2. LO QUE SE PUEDE AFIRMAR EN CUALQUIER SISTEMA: que no lanzan
         nunca -varias estan escritas para devolver vacio en vez de
         explotar, y ese es un contrato de verdad-, que devuelven el tipo
         prometido, y que con entrada vacia o basura fallan cerrado.

      3. LO QUE NO SE PUEDE TOCAR AQUI va marcado con -Skip y con un
         comentario que dice que queda fuera y por que. Hay tres huecos y
         estan escritos con su nombre; una nota honesta vale mas que una
         asercion falsa.

    DOS APANOS QUE MERECEN EXPLICACION:

      * Get-CimInstance NO EXISTE fuera de Windows, asi que "Mock
        Get-CimInstance" no se puede escribir: Pester exige que el comando
        exista. Se sustituye con un ALIAS de ambito de script hacia una
        funcion propia. Un alias se resuelve antes que un cmdlet, y la
        busqueda de comandos de PowerShell es dinamica, asi que la funcion
        de produccion -que se dot-sourceo en otro sitio- lo ve igual. Se
        usa un alias y no una funcion llamada Get-CimInstance porque el
        analizador prohibe redefinir cmdlets del sistema.

      * $script:EsWindows se calcula en BeforeDiscovery y NO en BeforeAll.
        Pester evalua -Skip durante el DESCUBRIMIENTO, cuando ningun
        BeforeAll se ha ejecutado todavia: calculado en BeforeAll vale
        $null, "-Skip:(-not $null)" es "-Skip:$true", y las pruebas se
        saltarian TAMBIEN en Windows sin que nada lo dijera. Es la cuarta
        vez que el descubrimiento de Pester muerde en este proyecto.
        Y ojo con la expresion: $IsWindows no existe en 5.1 -vale $null-,
        y 5.1 solo corre en Windows, de modo que "no lo se" cuenta como
        Windows.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeDiscovery {
    $script:EsWindows = ($IsWindows -or ($null -eq $IsWindows))
}

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    $script:EsWindows = ($IsWindows -or ($null -eq $IsWindows))

    # Un unico taller para todo el archivo. Todo lo que se escribe cuelga
    # de aqui y se borra en el AfterAll de mas abajo.
    $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-consulta-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Taller -Force)

    # USERPROFILE SE DEFINE A PROPOSITO, Y NO ES COMODIDAD.
    #
    # Get-CarpetaConocida -Nombre 'Downloads' termina en
    # "Join-Path $env:USERPROFILE 'Downloads'" (FileSystem.ps1, ~1576) sin
    # comprobar antes que la variable exista. Donde no existe -aqui, y en
    # cualquier contenedor de la integracion continua que no sea Windows-
    # Join-Path LANZA "Cannot bind argument to parameter 'Path' because it
    # is null", asi que la funcion no devuelve $null: revienta. Esta
    # anotado como hallazgo y NO se ha tocado el codigo de produccion.
    #
    # Se define la variable para que el resto del archivo mida la funcion
    # y no la ausencia de la variable; el hueco queda escrito en la prueba
    # saltada de mas abajo, con su nombre.
    $script:PerfilDelSistema = $env:USERPROFILE
    $env:USERPROFILE = Join-Path $script:Taller 'PerfilBase'
    [void](New-Item -ItemType Directory -Path $env:USERPROFILE -Force)
}

AfterAll {
    $env:USERPROFILE = $script:PerfilDelSistema
    Remove-Item -LiteralPath $script:Taller -Recurse -Force -ErrorAction SilentlyContinue
}


# ---------------------------------------------------------------------
#  Test-ProcesoAbierto
# ---------------------------------------------------------------------
#
# La unica de las seis que funciona igual en Linux que en Windows:
# Get-Process existe en los dos sitios. Asi que aqui no hay nada que
# saltarse, y se prueba tambien contra la tabla de procesos de verdad.

Describe 'Test-ProcesoAbierto: contra el sistema de verdad' {

    It 'encuentra el proceso que esta ejecutando esta misma prueba' {
        # Sin esta, todo lo demas de este bloque va contra un Mock y no
        # demostraria que la funcion sabe hablar con el sistema.
        $yo = [Diagnostics.Process]::GetCurrentProcess().ProcessName
        @(Test-ProcesoAbierto -Nombres @($yo)) | Should -Contain $yo
    }

    It 'un nombre que no puede existir no se da por abierto' {
        $inventado = 'cachivache-proceso-inventado-' + [guid]::NewGuid().ToString('N')
        @(Test-ProcesoAbierto -Nombres @($inventado)).Count | Should -Be 0
    }

    It 'cuando no encuentra nada, el resultado se recorre sin reventar' {
        # OJO CON LA TENTACION de escribir aqui "$null -eq $r | Should
        # -BeFalse": es MENTIRA y pasaria por casualidad. Un "return @()"
        # asignado a una variable se desenvuelve a $null en PowerShell,
        # en 5.1 y en 7. Lo que de verdad se puede exigir -y es lo que
        # necesita quien llama- es que recorrerlo no lance y que envuelto
        # en @() cuente cero.
        $r = Test-ProcesoAbierto -Nombres @('cachivache-nada-de-nada')
        @($r).Count | Should -Be 0
        { foreach ($x in $r) { [void]$x } } | Should -Not -Throw
    }

    It 'una lista vacia o nula se responde en el acto, sin preguntar al sistema' {
        Mock Get-Process { throw 'no se debe consultar la tabla de procesos para una lista vacia' }
        @(Test-ProcesoAbierto -Nombres @()).Count   | Should -Be 0
        @(Test-ProcesoAbierto -Nombres $null).Count | Should -Be 0
        @(Test-ProcesoAbierto).Count                | Should -Be 0
        Should -Invoke Get-Process -Times 0 -Exactly
    }
}

Describe 'Test-ProcesoAbierto: la decision, con la consulta sustituida' {

    BeforeAll {
        # Tres procesos inventados con nombres que no puede tener nadie:
        # asi la prueba dice lo mismo en una maquina vacia y en la del
        # usuario con cincuenta programas abiertos.
        Mock Get-Process {
            @(
                [pscustomobject]@{ ProcessName = 'chrome' }
                [pscustomobject]@{ ProcessName = 'Discord' }
                [pscustomobject]@{ ProcessName = 'steam' }
            )
        }
    }

    It 'separa los que estan de los que no' {
        $r = @(Test-ProcesoAbierto -Nombres @('chrome', 'firefox', 'steam'))
        $r.Count | Should -Be 2
        $r       | Should -Contain 'chrome'
        $r       | Should -Contain 'steam'
        $r       | Should -Not -Contain 'firefox'
    }

    It 'no distingue mayusculas: el modulo pide "Discord" y el sistema dice "discord"' {
        # El HashSet se construye con OrdinalIgnoreCase justo por esto.
        # Sin ello el aviso de "cierra el programa" no saldria nunca en la
        # mitad de los casos, y el usuario perderia lo que hubiera en la
        # cache del programa abierto sin que nadie se lo advirtiera.
        @(Test-ProcesoAbierto -Nombres @('DISCORD')).Count | Should -Be 1
        @(Test-ProcesoAbierto -Nombres @('cHrOmE')).Count  | Should -Be 1
    }

    It 'devuelve el nombre TAL COMO se pidio, no como lo escribe el sistema' {
        # Lo que se devuelve va a un aviso que lee una persona, y ese
        # aviso tiene que decir el nombre del programa como lo llama el
        # modulo, no como lo llama el ejecutable.
        Test-ProcesoAbierto -Nombres @('DISCORD') | Should -BeExactly 'DISCORD'
    }

    It 'conserva el orden en que se preguntaron' {
        $r = @(Test-ProcesoAbierto -Nombres @('steam', 'chrome'))
        $r[0] | Should -Be 'steam'
        $r[1] | Should -Be 'chrome'
    }

    It 'UNA sola consulta aunque se pregunten quince nombres' {
        # [REN-55]: la version anterior hacia un Get-Process -Name por
        # nombre, y cada uno enumera la tabla de procesos ENTERA. El
        # modulo de caches llama con quince nombres de golpe. Esta es la
        # prueba que impide que alguien vuelva a meter la consulta dentro
        # del bucle sin que nadie se entere.
        $quince = 1..15 | ForEach-Object { "programa$_" }
        [void](Test-ProcesoAbierto -Nombres @($quince))
        Should -Invoke Get-Process -Times 1 -Exactly
    }
}

Describe 'Test-ProcesoAbierto: si el sistema no contesta' {

    It 'sin tabla de procesos no acusa a nadie de estar abierto, y no lanza' {
        # Contrato escrito en el propio codigo: sin lista no se puede
        # afirmar que ninguno este abierto, asi que se devuelve vacio. El
        # aviso desaparece, pero nada se borra por eso y el programa sigue.
        Mock Get-Process { throw 'acceso denegado' }
        { Test-ProcesoAbierto -Nombres @('chrome') } | Should -Not -Throw
        @(Test-ProcesoAbierto -Nombres @('chrome')).Count | Should -Be 0
    }
}


# ---------------------------------------------------------------------
#  Get-CarpetaConocida
# ---------------------------------------------------------------------
#
# Cinco de las seis carpetas salen de [Environment]::GetFolderPath, que
# fuera de Windows devuelve cadena vacia para todas. La sexta -Descargas-
# es la unica con decision propia: lee el registro, expande las variables
# de entorno y cae al perfil si no hay nada. Esa se prueba entera.

Describe 'Get-CarpetaConocida: el conjunto cerrado de nombres' {

    It 'un nombre que no esta en la lista se rechaza antes de mirar nada' {
        # Falla cerrado: no devuelve la carpeta del usuario ni la raiz del
        # disco por descuido, lanza. Una carpeta conocida equivocada aqui
        # es una zona de analisis equivocada mas adelante.
        { Get-CarpetaConocida -Nombre 'Basura' }   | Should -Throw
        { Get-CarpetaConocida -Nombre '' }         | Should -Throw
        { Get-CarpetaConocida -Nombre 'desktop ' } | Should -Throw
    }

    It 'sin nombre no lanza: devuelve nulo' {
        { Get-CarpetaConocida } | Should -Not -Throw
        Get-CarpetaConocida | Should -BeNullOrEmpty
    }

    It 'ninguno de los seis nombres validos lanza: <Nombre>' -ForEach @(
        @{ Nombre = 'Desktop' }
        @{ Nombre = 'Documents' }
        @{ Nombre = 'Pictures' }
        @{ Nombre = 'Music' }
        @{ Nombre = 'Videos' }
        @{ Nombre = 'Downloads' }
    ) {
        { Get-CarpetaConocida -Nombre $Nombre } | Should -Not -Throw
    }

    It 'lo que devuelve es texto o nulo, nunca otra cosa: <Nombre>' -ForEach @(
        @{ Nombre = 'Desktop' }
        @{ Nombre = 'Documents' }
        @{ Nombre = 'Pictures' }
        @{ Nombre = 'Music' }
        @{ Nombre = 'Videos' }
        @{ Nombre = 'Downloads' }
    ) {
        $r = Get-CarpetaConocida -Nombre $Nombre
        if ($null -ne $r) { $r | Should -BeOfType [string] }
    }

    It 'las cinco carpetas de Environment devuelven una ruta que existe' -Skip:(-not $script:EsWindows) {
        # SOLO EN WINDOWS, y no por comodidad: fuera de Windows
        # [Environment]::GetFolderPath('MyPictures') devuelve CADENA VACIA
        # -comprobado-, asi que aqui la funcion devuelve $null para las
        # cinco y no hay nada que afirmar. Esta prueba es la mitad que
        # solo puede correr en la integracion continua de Windows.
        foreach ($n in @('Desktop', 'Documents', 'Pictures', 'Music', 'Videos')) {
            $r = Get-CarpetaConocida -Nombre $n
            $r | Should -Not -BeNullOrEmpty -Because "$n existe en cualquier Windows"
            $r | Should -Not -Match '\\$' -Because 'la barra final se recorta'
        }
    }

    It 'Descargas devuelve $null -y no lanza- si el perfil del usuario no esta definido' {
        # NACIO SALTADA, COMO HALLAZGO. La rama 'Downloads' acababa en
        # "Join-Path $env:USERPROFILE 'Downloads'" sin comprobar la
        # variable, y Join-Path LANZA con -Path nulo. En Windows la
        # variable existe siempre, asi que el programa no lo notaba nunca;
        # fuera de Windows -o en un servicio con el entorno pelado-
        # Get-CarpetaConocida dejaba de devolver $null y pasaba a
        # reventar, que es justo lo contrario de lo que hace el resto de
        # la funcion. Ya esta arreglado, y por eso ya no se salta.
        #
        # Se afirma $null Y que no lanza, las dos cosas: "no lanza" sola
        # la cumpliria tambien una funcion que devolviera una ruta
        # inventada colgando de la nada, que es peor que no contestar.
        $previo = $env:USERPROFILE
        try {
            Remove-Item -Path 'Env:\USERPROFILE' -ErrorAction SilentlyContinue
            { Get-CarpetaConocida -Nombre 'Downloads' } | Should -Not -Throw
            Get-CarpetaConocida -Nombre 'Downloads' | Should -BeNullOrEmpty
        } finally {
            $env:USERPROFILE = $previo
        }
    }
}

Describe 'Get-CarpetaConocida: Descargas, que es la unica que decide' {

    BeforeAll {
        $script:GuidDescargas = '{374DE290-123F-4565-9164-39C4925E467B}'
        $script:PerfilPrevio  = $env:USERPROFILE
        $env:USERPROFILE      = Join-Path $script:Taller 'Perfil'
        [void](New-Item -ItemType Directory -Path $env:USERPROFILE -Force)
    }

    AfterAll {
        $env:USERPROFILE = $script:PerfilPrevio
        Remove-Item -Path 'Env:\CACHIVACHE_ZONA' -ErrorAction SilentlyContinue
    }

    It 'lee la redireccion del registro y expande las variables de entorno' {
        # El registro guarda "%USERPROFILE%\Downloads" SIN expandir. Si se
        # devolviera tal cual, todo lo que colgara de ahi apuntaria a una
        # carpeta con un porcentaje en el nombre y el analisis miraria a
        # un sitio que no existe.
        $env:CACHIVACHE_ZONA = 'Z_ZONA_DE_PRUEBA'
        Mock Get-ItemProperty { [pscustomobject]@{ '{374DE290-123F-4565-9164-39C4925E467B}' = '%CACHIVACHE_ZONA%\Descargas' } }

        Get-CarpetaConocida -Nombre 'Downloads' | Should -Be 'Z_ZONA_DE_PRUEBA\Descargas'
    }

    It 'recorta la barra invertida final' {
        # El registro la trae unas veces si y otras no. Sin recortarla, la
        # misma carpeta se compara consigo misma y sale distinta, que es
        # justo lo que rompio la deteccion de carpetas anidadas.
        Mock Get-ItemProperty { [pscustomobject]@{ '{374DE290-123F-4565-9164-39C4925E467B}' = 'Z_RAIZ\Descargas\' } }
        Get-CarpetaConocida -Nombre 'Downloads' | Should -Be 'Z_RAIZ\Descargas'
    }

    It 'sin valor en el registro cae al perfil del usuario' {
        Mock Get-ItemProperty { $null }
        Get-CarpetaConocida -Nombre 'Downloads' | Should -Be (Join-Path $env:USERPROFILE 'Downloads')
    }

    It 'un valor vacio en el registro tambien cae al perfil' {
        # "Existe la clave" no es lo mismo que "dice algo". Un valor vacio
        # devuelto tal cual dejaria la ruta de Descargas en cadena vacia,
        # y una ruta vacia recorrida es la carpeta actual del proceso.
        Mock Get-ItemProperty { [pscustomobject]@{ '{374DE290-123F-4565-9164-39C4925E467B}' = '' } }
        Get-CarpetaConocida -Nombre 'Downloads' | Should -Be (Join-Path $env:USERPROFILE 'Downloads')
    }

    It 'una clave que no existe no lanza: el -ErrorAction se la traga' {
        # Se emula el error NO TERMINANTE que produce de verdad
        # Get-ItemProperty sobre una clave ausente, que es lo que silencia
        # el -ErrorAction SilentlyContinue de la funcion. No se emula un
        # "throw": un error terminante SI se propagaria, porque aqui no
        # hay try/catch, y escribir una prueba que dijera lo contrario
        # seria afirmar una robustez que el codigo no tiene.
        Mock Get-ItemProperty { Write-Error 'no existe' }
        { Get-CarpetaConocida -Nombre 'Downloads' } | Should -Not -Throw
        Get-CarpetaConocida -Nombre 'Downloads' | Should -Be (Join-Path $env:USERPROFILE 'Downloads')
    }

    It 'no pregunta al registro por las carpetas que resuelve Environment' {
        Mock Get-ItemProperty { throw 'Desktop no se lee del registro' }
        { Get-CarpetaConocida -Nombre 'Desktop' } | Should -Not -Throw
        Should -Invoke Get-ItemProperty -Times 0 -Exactly
    }
}


# ---------------------------------------------------------------------
#  Get-GuidVolumen
# ---------------------------------------------------------------------

Describe 'Get-GuidVolumen: sin WMI delante' {

    It 'no lanza aunque no exista ni el cmdlet: devuelve cadena vacia' {
        # Fuera de Windows Get-CimInstance NI SIQUIERA EXISTE, asi que lo
        # que salta es un CommandNotFoundException. El try/catch de la
        # funcion lo absorbe igual, y eso es lo que se comprueba: quien
        # llama recibe texto, nunca una excepcion.
        { Get-GuidVolumen -Unidad 'C:' } | Should -Not -Throw
        Get-GuidVolumen -Unidad 'C:' | Should -BeOfType [string]
    }

    It 'sin unidad falla cerrado' {
        # Parametro obligatorio. Devolver el GUID de "cualquier volumen"
        # ante una unidad vacia seria mirar la papelera del disco
        # equivocado.
        # Sin -Unidad NO se llama a pelo a proposito: un parametro
        # obligatorio sin valor abre un PROMPT interactivo y la suite se
        # queda colgada para siempre en la integracion continua. Lo que se
        # comprueba es que ni el vacio ni el nulo se cuelan.
        { Get-GuidVolumen -Unidad '' }    | Should -Throw
        { Get-GuidVolumen -Unidad $null } | Should -Throw
        (Get-Command Get-GuidVolumen).Parameters['Unidad'].Attributes |
            Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory } |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-GuidVolumen: la decision, con la consulta sustituida' {

    BeforeAll {
        # Ver la cabecera del archivo: alias en vez de funcion porque
        # Get-CimInstance no existe fuera de Windows -no se puede mockear-
        # y porque redefinir un cmdlet del sistema lo prohibe el analizador.
        function Get-VolumenesDePrueba {
            [CmdletBinding()]
            [OutputType([object[]])]
            param([string] $ClassName)

            if ($script:VolumenesLanzan) { throw 'WMI no responde' }
            return $script:Volumenes
        }
        Set-Alias -Name Get-CimInstance -Value Get-VolumenesDePrueba -Scope Script

        $script:VolumenesLanzan = $false
        $script:Volumenes = @(
            [pscustomobject]@{ DriveLetter = 'C:'; DeviceID = '\\?\Volume{aaaaaaaa-1111-2222-3333-444444444444}\' }
            [pscustomobject]@{ DriveLetter = 'D:'; DeviceID = '\\?\Volume{BBBBBBBB-5555-6666-7777-888888888888}\' }
            [pscustomobject]@{ DriveLetter = $null; DeviceID = '\\?\Volume{cccccccc-9999-0000-1111-222222222222}\' }
        )
    }

    AfterAll {
        Remove-Item -Path 'Alias:\Get-CimInstance' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach { $script:VolumenesLanzan = $false }

    It 'saca el GUID de dentro del DeviceID, que es lo que guarda el registro' {
        # DeviceID llega como \\?\Volume{guid}\ y el registro de la
        # papelera indexa por {guid} pelado. Devolver el DeviceID entero
        # dejaria la busqueda de la papelera sin encontrar nunca su clave.
        Get-GuidVolumen -Unidad 'C:' | Should -Be '{aaaaaaaa-1111-2222-3333-444444444444}'
    }

    It 'acepta el GUID en mayusculas' {
        Get-GuidVolumen -Unidad 'D:' | Should -Be '{BBBBBBBB-5555-6666-7777-888888888888}'
    }

    It 'normaliza la unidad: <Entrada> es la misma unidad que "C:"' -ForEach @(
        @{ Entrada = 'C:'   }
        @{ Entrada = 'C'    }
        @{ Entrada = 'C:\'  }
        @{ Entrada = 'C:/'  }
        @{ Entrada = 'C:\\' }
    ) {
        # Quien llama tiene la unidad en cuatro formas distintas segun de
        # donde venga -del selector, de una ruta, del registro-, y las
        # cuatro tienen que dar el mismo volumen.
        Get-GuidVolumen -Unidad $Entrada | Should -Be '{aaaaaaaa-1111-2222-3333-444444444444}'
    }

    It 'una letra que no esta montada devuelve cadena vacia, no la del vecino' {
        Get-GuidVolumen -Unidad 'Z:' | Should -Be ''
    }

    It 'un volumen sin letra no se confunde con ninguna unidad' {
        # Los volumenes montados en carpeta y las particiones de sistema
        # aparecen en Win32_Volume con DriveLetter vacio. Compararlos con
        # una letra normalizada tiene que dar siempre falso.
        Get-GuidVolumen -Unidad ':' | Should -Be ''
    }

    It 'un DeviceID sin GUID dentro devuelve cadena vacia' {
        $script:Volumenes = @([pscustomobject]@{ DriveLetter = 'C:'; DeviceID = '\\?\HarddiskVolume4' })
        Get-GuidVolumen -Unidad 'C:' | Should -Be ''
        $script:Volumenes = @([pscustomobject]@{ DriveLetter = 'C:'; DeviceID = $null })
        Get-GuidVolumen -Unidad 'C:' | Should -Be ''
    }

    It 'si la consulta lanza, se devuelve cadena vacia y no se propaga' {
        $script:VolumenesLanzan = $true
        { Get-GuidVolumen -Unidad 'C:' } | Should -Not -Throw
        Get-GuidVolumen -Unidad 'C:' | Should -Be ''
    }

    It 'sin ningun volumen devuelve cadena vacia' {
        $script:Volumenes = @()
        Get-GuidVolumen -Unidad 'C:' | Should -Be ''
    }

    It 'nunca devuelve nulo: siempre texto' {
        # Quien llama concatena el resultado dentro de una ruta de
        # registro. Un $null ahi no lanza, construye una ruta a otra clave.
        $script:Volumenes = @()
        $r = Get-GuidVolumen -Unidad 'Q:'
        $null -eq $r | Should -BeFalse
        $r | Should -BeOfType [string]
    }
}


# ---------------------------------------------------------------------
#  Get-DestinoAccesoDirecto
# ---------------------------------------------------------------------
#
# Esta es la mas facil de las seis y la que menos excusa tenia: la propia
# funcion ofrece el parametro -Shell precisamente para que se le pueda
# inyectar el objeto. Nadie lo habia usado.

Describe 'Get-DestinoAccesoDirecto: con un shell inyectado' {

    BeforeAll {
        function New-ShellDePrueba {
            <#
            .SYNOPSIS
                Doble del objeto COM WScript.Shell. Anota la ruta que le
                pidieron para poder comprobar que se le pasa sin tocar.
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'No cambia ningun estado: arma un objeto en memoria.')]
            [CmdletBinding()]
            [OutputType([psobject])]
            param([string] $Destino = 'C:\Juegos\juego.exe', [switch] $Lanza, [switch] $DevuelveNulo)

            $shell = [pscustomobject]@{
                Pedida       = $null
                Destino      = $Destino
                Lanza        = [bool]$Lanza
                DevuelveNulo = [bool]$DevuelveNulo
            }
            Add-Member -InputObject $shell -MemberType ScriptMethod -Name CreateShortcut -Value {
                param($Ruta)
                $this.Pedida = $Ruta
                if ($this.Lanza)        { throw 'el archivo .lnk esta corrupto' }
                if ($this.DevuelveNulo) { return $null }
                return [pscustomobject]@{ TargetPath = $this.Destino }
            }
            return $shell
        }
    }

    It 'devuelve el destino que dice el acceso directo' {
        $shell = New-ShellDePrueba -Destino 'D:\Programas\cosa.exe'
        Get-DestinoAccesoDirecto -Ruta 'C:\Menu\cosa.lnk' -Shell $shell | Should -Be 'D:\Programas\cosa.exe'
    }

    It 'le pasa la ruta al shell sin tocarla' {
        # Nada de Resolve-Path ni de normalizar por el camino: un .lnk en
        # una carpeta que el proceso no puede resolver seguiria siendo un
        # .lnk que el shell si sabe abrir.
        $shell = New-ShellDePrueba
        [void](Get-DestinoAccesoDirecto -Ruta 'C:\Con Espacios\a b.lnk' -Shell $shell)
        $shell.Pedida | Should -BeExactly 'C:\Con Espacios\a b.lnk'
    }

    It 'un acceso directo que no apunta a nada devuelve cadena vacia' {
        $shell = New-ShellDePrueba -Destino ''
        Get-DestinoAccesoDirecto -Ruta 'C:\Menu\roto.lnk' -Shell $shell | Should -Be ''
    }

    It 'si el shell lanza, se devuelve cadena vacia y no se propaga' {
        # Un solo .lnk corrupto en el menu Inicio no puede tumbar el
        # recorrido entero de las entradas de arranque.
        $shell = New-ShellDePrueba -Lanza
        { Get-DestinoAccesoDirecto -Ruta 'C:\Menu\roto.lnk' -Shell $shell } | Should -Not -Throw
        Get-DestinoAccesoDirecto -Ruta 'C:\Menu\roto.lnk' -Shell $shell | Should -Be ''
    }

    It 'si el shell devuelve nulo, tampoco lanza' {
        # Leer una propiedad de $null no lanza en PowerShell, y por eso
        # esto sale vacio en vez de reventar. Queda escrito para que se
        # note el dia que alguien meta Set-StrictMode por medio.
        $shell = New-ShellDePrueba -DevuelveNulo
        { Get-DestinoAccesoDirecto -Ruta 'C:\Menu\raro.lnk' -Shell $shell } | Should -Not -Throw
        Get-DestinoAccesoDirecto -Ruta 'C:\Menu\raro.lnk' -Shell $shell | Should -BeNullOrEmpty
    }

    It 'sin ruta falla cerrado, y sin llegar a molestar al shell' {
        $shell = New-ShellDePrueba
        # Igual que en Get-GuidVolumen: la llamada sin -Ruta no se escribe
        # porque abriria un prompt interactivo y colgaria la suite.
        { Get-DestinoAccesoDirecto -Ruta '' -Shell $shell }    | Should -Throw
        { Get-DestinoAccesoDirecto -Ruta $null -Shell $shell } | Should -Throw
        $shell.Pedida | Should -BeNullOrEmpty
    }

    It 'reutiliza el shell que se le da: no crea uno por acceso directo' {
        # El modulo de arranque resuelve decenas de .lnk seguidos. Crear
        # un objeto COM por cada uno es la diferencia entre un parpadeo y
        # varios segundos, y es la razon de que el parametro exista.
        $shell = New-ShellDePrueba -Destino 'C:\a.exe'
        foreach ($i in 1..5) {
            Get-DestinoAccesoDirecto -Ruta "C:\Menu\p$i.lnk" -Shell $shell | Should -Be 'C:\a.exe'
        }
        $shell.Pedida | Should -BeExactly 'C:\Menu\p5.lnk'
    }
}

Describe 'Get-DestinoAccesoDirecto: sin shell, creandolo el mismo' {

    It 'un .lnk que no existe no lanza y no inventa un destino' {
        # Fuera de Windows no hay COM y salta al crear el objeto; en
        # Windows si hay COM, CreateShortcut sobre un archivo inexistente
        # devuelve un acceso directo nuevo con TargetPath vacio y NO
        # escribe nada en disco -solo .Save() escribe-. Las dos ramas
        # tienen que acabar en lo mismo: vacio y sin excepcion.
        $inventado = Join-Path $script:Taller ('no-existe-' + [guid]::NewGuid().ToString('N') + '.lnk')
        { Get-DestinoAccesoDirecto -Ruta $inventado } | Should -Not -Throw
        Get-DestinoAccesoDirecto -Ruta $inventado | Should -BeNullOrEmpty
        Test-Path -LiteralPath $inventado | Should -BeFalse -Because 'resolver un acceso directo no crea archivos'
    }

    # QUEDA FUERA: resolver un .lnk DE VERDAD, escrito por Windows, con su
    # formato binario y su destino dentro. Un .lnk no se puede fabricar
    # aqui sin el propio WScript.Shell, que es justo lo que no existe. Esa
    # mitad -que el objeto COM se crea bien y que TargetPath sale de un
    # archivo real- solo la puede ver la integracion continua de Windows,
    # y hoy no la ve nadie.
}


# ---------------------------------------------------------------------
#  Get-EstadoArranque
# ---------------------------------------------------------------------

Describe 'Get-EstadoArranque: sin registro delante' {

    It 'no lanza y devuelve una tabla vacia cuando no hay ninguna clave' {
        Mock Get-ItemProperty { $null }
        { Get-EstadoArranque } | Should -Not -Throw
        $r = Get-EstadoArranque
        $r | Should -BeOfType [hashtable]
        $r.Count | Should -Be 0
    }

    It 'mira las cuatro claves de StartupApproved, no solo una' {
        # Run, Run32, StartupFolder y la de maquina. Quedarse con una sola
        # deja entradas desactivadas contadas como activas, que es
        # exactamente el dato que el usuario ve en la columna.
        Mock Get-ItemProperty { $null }
        [void](Get-EstadoArranque)
        Should -Invoke Get-ItemProperty -Times 4 -Exactly
    }

    It 'no lanza contra el registro de verdad de esta maquina' {
        # Sin Mock: en Linux las cuatro consultas fallan en silencio y en
        # Windows leen de verdad. En los dos casos el contrato es el mismo.
        { Get-EstadoArranque } | Should -Not -Throw
        Get-EstadoArranque | Should -BeOfType [hashtable]
    }
}

Describe 'Get-EstadoArranque: la decision, con el registro sustituido' {

    BeforeAll {
        # Nombre -> byte[] tal como los guarda Windows. Solo la clave que
        # se pida devuelve algo; asi se puede comprobar tambien el orden
        # en que se leen.
        function New-ValoresArranque {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'No cambia ningun estado: arma un objeto en memoria.')]
            [CmdletBinding()]
            [OutputType([psobject])]
            param([hashtable] $Valores)

            $o = [pscustomobject]@{}
            foreach ($k in $Valores.Keys) {
                Add-Member -InputObject $o -NotePropertyName $k -NotePropertyValue $Valores[$k]
            }
            return $o
        }
    }

    It 'el bit 0 a cero es ACTIVADO y a uno es DESACTIVADO' {
        # Es toda la regla, y esta al reves de lo que uno diria: un cero
        # significa que la entrada arranca. Invertirla convertiria la
        # columna en una mentira sistematica.
        Mock Get-ItemProperty {
            New-ValoresArranque -Valores @{
                'Activada'   = [byte[]]@(0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                'Desactivada' = [byte[]]@(0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            }
        }
        $r = Get-EstadoArranque
        $r['Activada']    | Should -BeTrue
        $r['Desactivada'] | Should -BeFalse
    }

    It 'solo mira el bit 0: el resto del byte no cambia el veredicto' {
        # Windows usa los demas bits para otras cosas. Comparar el byte
        # entero contra 2 -que es lo que se ve por ahi copiado- deja de
        # funcionar en cuanto Windows escribe un 0x06.
        Mock Get-ItemProperty {
            New-ValoresArranque -Valores @{
                'Cero'    = [byte[]]@(0x00)
                'Seis'    = [byte[]]@(0x06)
                'Siete'   = [byte[]]@(0x07)
                'Ochenta' = [byte[]]@(0x80)
            }
        }
        $r = Get-EstadoArranque
        $r['Cero']    | Should -BeTrue
        $r['Seis']    | Should -BeTrue
        $r['Ochenta'] | Should -BeTrue
        $r['Siete']   | Should -BeFalse
    }

    It 'ignora las propiedades PS* que anade el proveedor' {
        # PSPath, PSParentPath y compania no son entradas de arranque. Sin
        # el filtro aparecerian como programas en la lista del usuario.
        Mock Get-ItemProperty {
            New-ValoresArranque -Valores @{
                'PSPath'       = [byte[]]@(0x00)
                'PSParentPath' = [byte[]]@(0x00)
                'Programa'     = [byte[]]@(0x00)
            }
        }
        $r = Get-EstadoArranque
        $r.Count | Should -Be 1
        $r.ContainsKey('Programa') | Should -BeTrue
        $r.ContainsKey('PSPath')   | Should -BeFalse
    }

    It 'ignora lo que no sea byte[]' {
        Mock Get-ItemProperty {
            New-ValoresArranque -Valores @{
                'Texto'   = 'no soy un byte'
                'Numero'  = 3
                'Nada'    = $null
                'Buena'   = [byte[]]@(0x00)
            }
        }
        $r = Get-EstadoArranque
        $r.Count | Should -Be 1
        $r.ContainsKey('Buena') | Should -BeTrue
    }

    It 'un byte[] vacio no se lee: leerlo seria salirse del array' {
        Mock Get-ItemProperty { New-ValoresArranque -Valores @{ 'Vacia' = [byte[]]@() } }
        { Get-EstadoArranque } | Should -Not -Throw
        (Get-EstadoArranque).Count | Should -Be 0
    }

    It 'la clave de maquina se lee la ultima y gana sobre la del usuario' {
        # HKLM va el cuarto en la lista, asi que sobrescribe. Es una
        # decision de precedencia, no un descuido: si el administrador ha
        # desactivado algo para todo el equipo, eso es lo que se ensena.
        Mock Get-ItemProperty {
            if ($Path -like 'HKLM:*') {
                New-ValoresArranque -Valores @{ 'Compartida' = [byte[]]@(0x03) }
            } else {
                New-ValoresArranque -Valores @{ 'Compartida' = [byte[]]@(0x02) }
            }
        }
        (Get-EstadoArranque)['Compartida'] | Should -BeFalse -Because 'manda lo que dice HKLM, que se lee el ultimo'
    }

    It 'junta lo que encuentra en claves distintas' {
        Mock Get-ItemProperty {
            if ($Path -like '*StartupFolder*') {
                New-ValoresArranque -Valores @{ 'DesdeCarpeta' = [byte[]]@(0x00) }
            } elseif ($Path -like 'HKLM:*') {
                New-ValoresArranque -Valores @{ 'DesdeMaquina' = [byte[]]@(0x01) }
            } else {
                $null
            }
        }
        $r = Get-EstadoArranque
        $r.Count | Should -Be 2
        $r['DesdeCarpeta'] | Should -BeTrue
        $r['DesdeMaquina'] | Should -BeFalse
    }
}


# ---------------------------------------------------------------------
#  Get-BibliotecasSteam
# ---------------------------------------------------------------------
#
# La mitad de esta funcion es puro sistema de archivos, y esa se prueba
# entera: se fabrica una instalacion de Steam de verdad en una carpeta
# temporal, con su libraryfolders.vdf en las dos ubicaciones historicas,
# una biblioteca montada, otra declarada pero ausente -el disco externo
# desconectado- y un archivo corrupto.
#
# El registro se sustituye SIEMPRE con Mock, tambien en Windows: si no,
# la prueba pasaria en Linux -donde HKCU no contesta- y en la maquina del
# usuario leeria su Steam real y afirmaria cualquier cosa.

Describe 'Get-BibliotecasSteam: bibliotecas declaradas en el VDF' {

    BeforeAll {
        Mock Get-ItemProperty { $null }   # HKCU:\SOFTWARE\Valve\Steam no dice nada

        $script:Steam    = Join-Path (Join-Path $script:Taller 'PFX86') 'Steam'
        $script:AppsUno  = Join-Path $script:Steam 'steamapps'
        $script:Config   = Join-Path $script:Steam 'config'
        $script:LibB     = Join-Path $script:Taller 'DiscoD'
        $script:AppsDos  = Join-Path $script:LibB 'steamapps'
        $script:LibAusente = Join-Path $script:Taller 'DiscoExternoDesconectado'

        foreach ($d in @($script:AppsUno, $script:Config, $script:AppsDos, $script:LibAusente)) {
            [void](New-Item -ItemType Directory -Path $d -Force)
        }

        $script:PfPrevio    = $env:ProgramFiles
        $script:Pfx86Previo = ${env:ProgramFiles(x86)}
        ${env:ProgramFiles(x86)} = Join-Path $script:Taller 'PFX86'
        $env:ProgramFiles        = Join-Path $script:Taller 'PFvacio'
        [void](New-Item -ItemType Directory -Path $env:ProgramFiles -Force)

        function Set-Vdf {
            <#
            .SYNOPSIS
                Escribe un libraryfolders.vdf con las rutas indicadas, con
                las barras escapadas como las escribe Valve.
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Solo escribe en la carpeta temporal de la propia prueba.')]
            [CmdletBinding()]
            param([string] $Carpeta, [string[]] $Rutas, [string] $Texto)

            $destino = Join-Path $Carpeta 'libraryfolders.vdf'
            if ($PSBoundParameters.ContainsKey('Texto')) {
                [IO.File]::WriteAllText($destino, $Texto)
                return
            }
            $lineas = [Collections.Generic.List[string]]::new()
            $lineas.Add('"libraryfolders"')
            $lineas.Add('{')
            $i = 0
            foreach ($r in @($Rutas)) {
                $lineas.Add(('    "{0}"' -f $i))
                $lineas.Add('    {')
                $lineas.Add(('        "path"        "{0}"' -f ($r -replace '\\', '\\')))
                $lineas.Add('    }')
                $i++
            }
            $lineas.Add('}')
            [IO.File]::WriteAllText($destino, (@($lineas) -join "`r`n"))
        }

        function Remove-Vdf {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Solo borra en la carpeta temporal de la propia prueba.')]
            [CmdletBinding()]
            param()
            foreach ($c in @($script:AppsUno, $script:Config)) {
                Remove-Item -LiteralPath (Join-Path $c 'libraryfolders.vdf') -Force -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        $env:ProgramFiles        = $script:PfPrevio
        ${env:ProgramFiles(x86)} = $script:Pfx86Previo
    }

    BeforeEach { Remove-Vdf }

    It 'sin VDF devuelve solo la biblioteca de la instalacion' {
        $r = @(Get-BibliotecasSteam)
        $r.Count | Should -Be 1
        $r[0]    | Should -Be $script:AppsUno
    }

    It 'anade la biblioteca declarada en steamapps/libraryfolders.vdf' {
        Set-Vdf -Carpeta $script:AppsUno -Rutas @($script:LibB)
        $r = @(Get-BibliotecasSteam)
        $r.Count | Should -Be 2
        $r       | Should -Contain $script:AppsDos
    }

    It 'lee tambien la ubicacion historica config/libraryfolders.vdf' {
        # Steam movio el archivo de sitio hace anos y las dos ubicaciones
        # siguen vivas segun la antiguedad de la instalacion. Mirar solo
        # una deja fuera justo las bibliotecas grandes.
        Set-Vdf -Carpeta $script:Config -Rutas @($script:LibB)
        @(Get-BibliotecasSteam) | Should -Contain $script:AppsDos
    }

    It 'una biblioteca declarada cuyo disco NO esta montado se descarta' {
        # El contrato escrito en la propia funcion: un disco externo
        # desconectado sigue apareciendo en el archivo. Proponer algo de
        # ahi seria proponer sobre un disco que no esta, y el modulo de
        # juegos acabaria contando cero bytes de una carpeta inexistente.
        Set-Vdf -Carpeta $script:AppsUno -Rutas @($script:LibAusente)
        $r = @(Get-BibliotecasSteam)
        $r.Count | Should -Be 1 -Because 'la carpeta steamapps de esa biblioteca no existe'
        $r       | Should -Not -Contain (Join-Path $script:LibAusente 'steamapps')
    }

    It 'no repite una biblioteca declarada dos veces' {
        Set-Vdf -Carpeta $script:AppsUno -Rutas @($script:LibB, $script:LibB)
        Set-Vdf -Carpeta $script:Config  -Rutas @($script:LibB)
        $r = @(Get-BibliotecasSteam)
        $r.Count | Should -Be 2
        @($r | Where-Object { $_ -eq $script:AppsDos }).Count | Should -Be 1
    }

    It 'no repite la propia instalacion cuando el VDF la declara' {
        # El VDF real de Steam SIEMPRE se declara a si mismo como
        # biblioteca "0". Sin la comprobacion de duplicados, la carpeta
        # principal se recorreria dos veces y todo lo que hay dentro se
        # contaria por partida doble.
        Set-Vdf -Carpeta $script:AppsUno -Rutas @($script:Steam, $script:LibB)
        $r = @(Get-BibliotecasSteam)
        $r.Count | Should -Be 2
        @($r | Where-Object { $_ -eq $script:AppsUno }).Count | Should -Be 1
    }

    It 'un VDF vacio no rompe nada' {
        Set-Vdf -Carpeta $script:AppsUno -Texto ''
        { Get-BibliotecasSteam } | Should -Not -Throw
        @(Get-BibliotecasSteam).Count | Should -Be 1
    }

    It 'un VDF corrupto no rompe nada' {
        # Steam escribe este archivo mientras se actualiza y un apagon lo
        # deja a medias. Que el limpiador no arranque por eso seria una
        # averia peor que la que se venia a arreglar.
        Set-Vdf -Carpeta $script:AppsUno -Texto "\x00\x01 no soy un VDF `"path`" sin cerrar {{{{ \x00"
        { Get-BibliotecasSteam } | Should -Not -Throw
        @(Get-BibliotecasSteam).Count | Should -Be 1
    }

    It 'un VDF a medio escribir, cortado por la mitad, tampoco' {
        Set-Vdf -Carpeta $script:AppsUno -Texto @"
"libraryfolders"
{
    "0"
    {
        "path"        "
"@
        { Get-BibliotecasSteam } | Should -Not -Throw
        @(Get-BibliotecasSteam).Count | Should -Be 1
    }

    It 'una ruta vacia dentro del VDF se ignora' {
        Set-Vdf -Carpeta $script:AppsUno -Texto @"
"libraryfolders"
{
    "0"
    {
        "path"        ""
    }
}
"@
        @(Get-BibliotecasSteam).Count | Should -Be 1
    }

    It 'devuelve rutas de carpetas que existen de verdad' {
        Set-Vdf -Carpeta $script:AppsUno -Rutas @($script:LibB, $script:LibAusente)
        foreach ($r in @(Get-BibliotecasSteam)) {
            Test-Path -LiteralPath $r | Should -BeTrue -Because "$r se ha devuelto como biblioteca"
        }
    }

    It 'lo que se devuelve son cadenas, y una lista aunque haya una sola' {
        $r = Get-BibliotecasSteam
        @($r).Count | Should -Be 1
        @($r)[0] | Should -BeOfType [string]
    }
}

Describe 'Get-BibliotecasSteam: cuando no hay Steam' {

    BeforeAll {
        Mock Get-ItemProperty { $null }

        $script:PfPrevio2    = $env:ProgramFiles
        $script:Pfx86Previo2 = ${env:ProgramFiles(x86)}
        $vacia = Join-Path $script:Taller 'SinSteam'
        [void](New-Item -ItemType Directory -Path $vacia -Force)
        ${env:ProgramFiles(x86)} = $vacia
        $env:ProgramFiles        = $vacia
    }

    AfterAll {
        $env:ProgramFiles        = $script:PfPrevio2
        ${env:ProgramFiles(x86)} = $script:Pfx86Previo2
    }

    It 'sin instalacion de Steam no se devuelve ninguna biblioteca' {
        # Igual que en Test-ProcesoAbierto: el "return @()" se desenvuelve
        # a $null al asignarlo, asi que exigir "no es nulo" seria exigir
        # algo que PowerShell no hace. Lo que importa es que el modulo de
        # juegos, que hace foreach sobre esto, no de ni una vuelta ni
        # reviente.
        $r = Get-BibliotecasSteam
        @($r).Count | Should -Be 0
        { foreach ($x in $r) { [void]$x } } | Should -Not -Throw
    }

    It 'no lanza' {
        { Get-BibliotecasSteam } | Should -Not -Throw
    }
}

Describe 'Get-BibliotecasSteam: el registro manda sobre las carpetas de programas' {

    BeforeAll {
        # Se monta un Steam VALIDO en ProgramFiles(x86) y ademas se hace
        # que el registro conteste con una ruta que no existe. Si el
        # resultado sale vacio, queda demostrado que la funcion se queda
        # con lo que dice el registro y NO cae al plan B: la busqueda por
        # carpetas es un ultimo recurso, no un complemento.
        #
        # Es lo unico que se puede afirmar aqui sobre la rama del
        # registro, y se puede afirmar en los dos sistemas.
        $script:SteamB   = Join-Path (Join-Path $script:Taller 'PFX86b') 'Steam'
        [void](New-Item -ItemType Directory -Path (Join-Path $script:SteamB 'steamapps') -Force)

        $script:PfPrevio3    = $env:ProgramFiles
        $script:Pfx86Previo3 = ${env:ProgramFiles(x86)}
        ${env:ProgramFiles(x86)} = Join-Path $script:Taller 'PFX86b'
        $env:ProgramFiles        = Join-Path $script:Taller 'PFX86b'

        Mock Get-ItemProperty { [pscustomobject]@{ SteamPath = 'Z:/ruta/que/no/existe/Steam' } }
    }

    AfterAll {
        $env:ProgramFiles        = $script:PfPrevio3
        ${env:ProgramFiles(x86)} = $script:Pfx86Previo3
    }

    It 'con SteamPath en el registro no se busca por ProgramFiles' {
        @(Get-BibliotecasSteam).Count | Should -Be 0 `
            -Because 'el registro dijo donde esta Steam, y ahi no hay nada; buscarlo ademas por carpetas inventaria una instalacion'
    }

    # QUEDA FUERA: comprobar que una SteamPath VALIDA del registro se
    # resuelve a su carpeta steamapps. La funcion normaliza el valor con
    # -replace '/', '\' antes de usarlo, y una ruta con barras invertidas
    # no existe en Linux, asi que aqui no se puede montar un caso que
    # encuentre nada por esa via. Se cubre en Windows o no se cubre.
}
