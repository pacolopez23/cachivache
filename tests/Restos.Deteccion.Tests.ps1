<#
    Banco de pruebas de DETECCION del modulo de restos de programas.
    Ver [SEG-01] y [SEG-02] en docs/PLAN-ACCION.md.

    No confundir con Modulos.Regresion.Tests.ps1, que fija fallos concretos
    ya corregidos. Esto es lo contrario: un arbol sintetico con doce casos
    -seis que SI son restos y seis que NO- que mide cuantos acierta el
    modulo. Es la metrica de la que dependen las fases 2 y 3 del plan, y la
    unica forma de saber si subir la sensibilidad ha roto la precision.

    Cada caso lleva el identificador del hallazgo que lo justifica, para
    que al leer un fallo se sepa que parte del plan esta sin hacer.

    Este archivo es ASCII puro a proposito, como el resto de la suite: los
    caracteres acentuados se construyen por codigo cuando hacen falta.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    <#
        Vocabulario de "lo que hay instalado" que ve el modulo. Se fija a
        mano en vez de leer el equipo real por dos motivos: las pruebas
        corren tambien en Linux, donde no hay registro ni Get-AppxPackage;
        y un vocabulario controlado es lo que permite distinguir un fallo
        de deteccion de una casualidad del equipo donde se ejecuta.

        Los tokens DEBILES son la clave del banco: salen de nombres de
        servicio, de proceso y de accesos directos del menu Inicio, y son
        genericos. Hoy [DET-10] los trata igual que a los fuertes y por
        subcadena, asi que cualquier carpeta que contenga "games" o
        "launcher" se declara conocida y no se mira jamas.
    #>
    $script:TokensFuertes = @(
        # Programas realmente instalados: DisplayName de la lista de
        # desinstalacion o carpeta de Archivos de programa.
        'cachivacheinstalado'
        'ubisoftgamelauncher'
    )
    $script:TokensDebiles = @(
        # Genericos que en un equipo real vienen de servicios, procesos,
        # editores y accesos directos del menu Inicio. Ninguno deberia
        # bastar por si solo para declarar conocida una carpeta.
        'ubisoft'
        'games'
        'launcher'
        'power'
        'themes'
    )

    function New-VocabularioDePrueba {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone un objeto en memoria.')]
        [CmdletBinding()]
        param()

        $v = New-VocabularioInstalado
        foreach ($t in $script:TokensFuertes) { Add-TokenVocabulario -Vocabulario $v -Texto $t -Fuerte }
        foreach ($t in $script:TokensDebiles) { Add-TokenVocabulario -Vocabulario $v -Texto $t }
        return $v
    }

    function New-ArbolDeRestos {
        <#
        .SYNOPSIS
            Fabrica un AppData falso con los doce casos del banco.
        .DESCRIPTION
            Devuelve la carpeta raiz. Las tres zonas que mira el modulo
            -Local, Roaming y ProgramData- mas LocalLow, que hoy no mira
            nadie (ver [DET-20]), cuelgan de ella.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo crea un arbol de prueba en una carpeta temporal propia.')]
        [CmdletBinding()]
        param([Parameter(Mandatory)] [string] $Raiz)

        # La distribucion es la real de un perfil de Windows, no una
        # comoda: el modulo deriva LocalLow de %USERPROFILE% y solo
        # encuentra la ruta si el arbol tiene la forma de verdad.
        $appData = Join-Path $Raiz 'AppData'
        $zonas = @{
            Local      = Join-Path $appData 'Local'
            Roaming    = Join-Path $appData 'Roaming'
            LocalLow   = Join-Path $appData 'LocalLow'
            Datos      = Join-Path $Raiz 'ProgramData'
        }
        foreach ($z in $zonas.Values) { New-Item -ItemType Directory -Path $z -Force | Out-Null }

        # Una carpeta con un archivo dentro y la fecha que se le pida. La
        # fecha del ARCHIVO es la que cuenta: Get-ResumenArbol devuelve el
        # maximo LastWriteTime de los archivos, no el de la carpeta.
        function New-CarpetaConEdad {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Solo crea una carpeta de prueba en una ruta temporal propia.')]
            [CmdletBinding()]
            param([string] $Ruta, [int] $Dias, [string] $Archivo = 'datos.dat')

            New-Item -ItemType Directory -Path $Ruta -Force | Out-Null
            $completa = Join-Path $Ruta $Archivo
            Set-Content -LiteralPath $completa -Value ('x' * 2048) -NoNewline
            (Get-Item -LiteralPath $completa).LastWriteTime = (Get-Date).AddDays(-$Dias)
        }

        # ---- SI son restos (deben aparecer) ---------------------------
        New-CarpetaConEdad (Join-Path (Join-Path $zonas.LocalLow 'UnityGameStudios') 'Cosmic Drift') 400
        New-CarpetaConEdad (Join-Path (Join-Path $zonas.Roaming 'Ubisoft') 'Bandera Roja') 400
        New-CarpetaConEdad (Join-Path $zonas.Local 'EA Games') 400
        New-CarpetaConEdad (Join-Path $zonas.Local 'Warframe Launcher') 400
        New-CarpetaConEdad (Join-Path $zonas.Local 'PowerDVD Cache') 400
        New-CarpetaConEdad (Join-Path $zonas.Local 'Presets Antiguos') 400

        # ---- NO son restos (no deben aparecer) ------------------------
        New-CarpetaConEdad (Join-Path $zonas.Local 'Cachivache Instalado') 400
        New-CarpetaConEdad (Join-Path (Join-Path $zonas.Roaming 'Ubisoft') 'Ubisoft Game Launcher') 400
        New-CarpetaConEdad (Join-Path $zonas.Local 'Programa Reciente') 2
        New-CarpetaConEdad (Join-Path $zonas.Local 'Microsoft') 400
        New-CarpetaConEdad (Join-Path $zonas.Local 'Bitdefender Restos') 400
        New-CarpetaConEdad (Join-Path $zonas.Datos 'Copias') 400

        # ---- Caso especial: resto CON partidas guardadas dentro -------
        # Debe aparecer, pero con aviso y sin premarcar. Es la invariante
        # que New-Candidato garantiza por construccion.
        $conPartidas = Join-Path $zonas.Local 'Mi Juego Retro'
        New-CarpetaConEdad (Join-Path $conPartidas 'saves') 400 'partida01.sav'

        return $zonas
    }
}

Describe 'Banco de deteccion de restos de programas' {

    BeforeAll {
        $script:Temporal = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-restos-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Temporal -Force | Out-Null
        $script:Zonas = New-ArbolDeRestos -Raiz $script:Temporal

        # El modulo lee las zonas de las variables de entorno, no de la
        # configuracion. Se sustituyen por el arbol falso y se restauran
        # en el AfterAll.
        $script:EntornoOriginal = @{
            LOCALAPPDATA = $env:LOCALAPPDATA
            APPDATA      = $env:APPDATA
            ProgramData  = $env:ProgramData
            USERPROFILE  = $env:USERPROFILE
        }
        $env:LOCALAPPDATA = $script:Zonas.Local
        $env:APPDATA      = $script:Zonas.Roaming
        $env:ProgramData  = $script:Zonas.Datos
        $env:USERPROFILE  = $script:Temporal

        # La guardia se inicializa DESPUES de sustituir el entorno: su
        # lista negra se construye a partir de estas mismas variables.
        Initialize-Guardia -Configuracion ([pscustomobject]@{
            Escritorio = ''; Documentos = ''; Descargas = ''
            Imagenes   = ''; Musica     = ''; Videos     = ''
            CarpetaDatos = ''
        })

        $script:Modulo = Get-ModuloLimpieza -Id 'restos' -Raiz $script:Raiz
        $script:Configuracion = [pscustomobject]@{
            MinimoMB   = 0
            DiasSinUso = 180
            Admin      = $true
        }
    }

    AfterAll {
        foreach ($clave in $script:EntornoOriginal.Keys) {
            Set-Item -Path "env:$clave" -Value $script:EntornoOriginal[$clave] -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:Temporal -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock Get-TokensProgramasInstalados { New-VocabularioDePrueba }

        $resultado = Invoke-ModuloLimpieza -Modulo $script:Modulo `
                                           -Configuracion $script:Configuracion `
                                           -Sync (New-EstadoSincronizado)
        $script:Nombres = @($resultado.Candidatos | ForEach-Object { $_.Nombre })
        $script:Candidatos = $resultado.Candidatos

        # Se comprueba por RUTA y no por nombre. Al modulo se le pide que
        # la basura se proponga, no que la proponga con una granularidad
        # concreta: proponer "LocalLow\UnityGameStudios" entero cubre
        # "Cosmic Drift" y ademas es mejor resultado -un elemento en vez
        # de varios, y mas bytes-. Un candidato cubre una ruta si es esa
        # ruta o un antepasado suyo.
        $script:Cubre = {
            param([string] $Objetivo)
            foreach ($c in $script:Candidatos) {
                if ($Objetivo.Equals($c.Ruta, [StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ($Objetivo.StartsWith($c.Ruta.TrimEnd([char]'\', [char]'/') + [IO.Path]::DirectorySeparatorChar,
                                         [StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
            return $false
        }
    }

    Context 'Lo que SI es un resto y debe aparecer' {

        It 'encuentra <Que> (<Id>)' -ForEach @(
            @{ Que = 'el juego de Unity en LocalLow'; Id = 'DET-20'
               Ruta = @('AppData', 'LocalLow', 'UnityGameStudios', 'Cosmic Drift')
               Porque = 'AppData\LocalLow no lo recorria ningun modulo, y es donde deja sus datos todo juego de Unity' }
            @{ Que = 'el juego bajo un editor instalado'; Id = 'DET-21'
               Ruta = @('AppData', 'Roaming', 'Ubisoft', 'Bandera Roja')
               Porque = 'esta a profundidad 2 bajo un editor que sigue instalado, y el modulo solo miraba el primer nivel' }
            @{ Que = 'la carpeta que contiene "games"'; Id = 'DET-10'
               Ruta = @('AppData', 'Local', 'EA Games')
               Porque = '"games" es un token debil y Test-TokenConocido casaba por subcadena' }
            @{ Que = 'la carpeta que contiene "launcher"'; Id = 'DET-10'
               Ruta = @('AppData', 'Local', 'Warframe Launcher')
               Porque = '"launcher" es un token debil' }
            @{ Que = 'la carpeta que contiene "power"'; Id = 'DET-10'
               Ruta = @('AppData', 'Local', 'PowerDVD Cache')
               Porque = '"power" viene de un servicio y no dice nada sobre PowerDVD' }
            @{ Que = 'la carpeta que contiene "eset"'; Id = 'SEG-12'
               Ruta = @('AppData', 'Local', 'Presets Antiguos')
               Porque = '"eset" estaba dentro de "Presets" y Test-NombreSensible casaba por subcadena' }
        ) {
            $objetivo = $script:Temporal
            foreach ($segmento in $Ruta) { $objetivo = Join-Path $objetivo $segmento }
            (& $script:Cubre $objetivo) | Should -BeTrue -Because $Porque
        }
    }

    Context 'Lo que NO es un resto y no debe aparecer' {

        It 'no propone "<Nombre>"' -ForEach @(
            @{ Nombre = 'Cachivache Instalado'
               Porque = 'coincide exactamente con un programa instalado' }
            @{ Nombre = 'Ubisoft Game Launcher'
               Porque = 'esta instalado, aunque cuelgue de un editor cuyas otras carpetas si son restos' }
            @{ Nombre = 'Programa Reciente'
               Porque = 'se toco hace dos dias y no llega al umbral de dias sin uso' }
            @{ Nombre = 'Microsoft'
               Porque = 'esta en la lista de carpetas protegidas del sistema' }
            @{ Nombre = 'Bitdefender Restos'
               Porque = 'lleva el nombre de un antivirus y la guardia veta los nombres sensibles' }
            @{ Nombre = 'Copias'
               Porque = 'es una carpeta de copias de seguridad' }
        ) {
            $script:Nombres | Should -Not -Contain $Nombre -Because $Porque
        }
    }

    Context 'Invariante: nada con partidas guardadas se premarca' {

        It 'propone la carpeta con partidas pero con aviso' {
            $candidato = $script:Candidatos | Where-Object { $_.Nombre -eq 'Mi Juego Retro' }
            $candidato | Should -Not -BeNullOrEmpty
            $candidato.Aviso | Should -Not -BeNullOrEmpty -Because 'contiene una subcarpeta saves con una partida dentro'
        }

        It 'no premarca ningun candidato que lleve aviso' {
            foreach ($candidato in $script:Candidatos) {
                if (-not [string]::IsNullOrWhiteSpace($candidato.Aviso)) {
                    $candidato.Seleccionado | Should -BeFalse -Because "el candidato $($candidato.Nombre) lleva aviso"
                }
            }
        }
    }

    Context 'Metrica del banco' {

        It 'acierta los doce casos' {
            # La coma delante de cada elemento es imprescindible: sin
            # ella PowerShell aplana el array de arrays y el bucle recorre
            # letra a letra.
            $debenAparecer = @(
                ,@('AppData', 'LocalLow', 'UnityGameStudios', 'Cosmic Drift')
                ,@('AppData', 'Roaming', 'Ubisoft', 'Bandera Roja')
                ,@('AppData', 'Local', 'EA Games')
                ,@('AppData', 'Local', 'Warframe Launcher')
                ,@('AppData', 'Local', 'PowerDVD Cache')
                ,@('AppData', 'Local', 'Presets Antiguos')
            )
            $noDebenAparecer = @('Cachivache Instalado', 'Ubisoft Game Launcher',
                                 'Programa Reciente', 'Microsoft', 'Bitdefender Restos', 'Copias')

            $fallos = @()
            foreach ($partes in $debenAparecer) {
                $objetivo = $script:Temporal
                foreach ($segmento in $partes) { $objetivo = Join-Path $objetivo $segmento }
                if (-not (& $script:Cubre $objetivo)) { $fallos += "no encuentra $($partes[-1])" }
            }
            foreach ($n in $noDebenAparecer) {
                if ($script:Nombres -contains $n) { $fallos += "propone $n" }
            }

            $fallos -join '; ' | Should -BeNullOrEmpty
        }
    }
}
