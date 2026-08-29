<#
.SYNOPSIS
    Restos que deja la desinstalación fuera de AppData: entradas fantasma
    del registro, carpetas huérfanas de Archivos de programa, versiones
    viejas de aplicaciones Electron e instaladores de controladores.
.DESCRIPTION
    30-RestosProgramas mira AppData y ProgramData. Este módulo mira el
    resto de sitios donde una desinstalación deja cosas atrás, que son
    justo los que más ocupan.

    NADA DE ESTE MÓDULO ESCRIBE EN EL REGISTRO. Las entradas fantasma se
    señalan como informativas y punto: quitarlas es cosa del usuario, y la
    regla de "el programa nunca escribe en el registro de Windows" no se
    negocia por un puñado de kilobytes. Lo que sí se propone borrar son
    carpetas de disco.

    Las tres fuentes, de más segura a menos:

      Versiones viejas de Electron  Discord, Slack, Teams y GitHub Desktop
                                    guardan cada version en "app-<numero>"
                                    y conservan las anteriores. 150-400 MB
                                    por version, y se acumulan solas. Que
                                    sobre la vieja es un hecho comprobable:
                                    hay otra mas nueva al lado.

      Instaladores de controladores  NVIDIA, AMD e Intel descomprimen el
                                    instalador en disco y lo dejan ahi.
                                    Unos 800 MB por version.

      Huerfanos de Archivos de programa  Carpetas sin entrada de
                                    desinstalacion, sin servicio y sin
                                    acceso del menu Inicio. Es lo mas
                                    incierto de los tres, asi que va con
                                    riesgo alto y nunca marcado.

    Ver [DET-40] a [DET-43] en docs/PLAN-ACCION.md.
#>

$BuscarRestosRegistro = {
    param($Configuracion, $Sync)

    $LA = $env:LOCALAPPDATA
    $RA = $env:APPDATA

    # ==================================================================
    # 1. Versiones antiguas de aplicaciones Electron / Squirrel
    # ==================================================================
    # El patron es universal: la aplicacion vive en "app-1.0.9042" y al
    # actualizarse crea "app-1.0.9043" al lado sin borrar la anterior.
    # Se conserva SIEMPRE la version mas alta y se proponen las demas.
    Set-Progreso $Sync 'Buscando versiones antiguas de aplicaciones...'

    $contenedores = @()
    foreach ($base in @($LA, $RA)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $contenedores += @(Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue)
    }

    foreach ($contenedor in $contenedores) {
        if (Test-Cancelacion $Sync) { break }
        if (Test-EsEnlace $contenedor) { continue }

        $versiones = @(Get-ChildItem -LiteralPath $contenedor.FullName -Directory -Force -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -match '^app-(\d+(\.\d+)*)$' })

        # Con una sola version no sobra ninguna: es la que se esta usando.
        if ($versiones.Count -lt 2) { continue }

        # Se ordena por version de verdad, no por texto: "app-1.0.10" es
        # posterior a "app-1.0.9", y comparadas como cadenas saldria al
        # reves y se propondria borrar justo la que esta en uso.
        $ordenadas = @($versiones | Sort-Object -Property @{ Expression = {
            $numero = $_.Name.Substring(4)
            try { [version]$numero } catch { [version]'0.0' }
        } })

        $masNueva = $ordenadas[-1]
        foreach ($vieja in $ordenadas[0..($ordenadas.Count - 2)]) {
            if (Test-Cancelacion $Sync) { break }
            if (Test-EsEnlace $vieja) { continue }
            if (-not (Test-RutaSegura $vieja.FullName @($contenedor.FullName))) { continue }

            $bytes = Measure-Ruta $vieja.FullName
            if ($bytes -lt ($Configuracion.MinimoMB * 1MB)) { continue }

            New-Candidato -ModuloId 'restosregistro' -Categoria 'Versiones antiguas de aplicaciones' `
                          -Nombre "$($contenedor.Name) - $($vieja.Name)" `
                          -Ruta $vieja.FullName -Bytes $bytes `
                          -Info "la versión en uso es $($masNueva.Name)" `
                          -Efecto "Versión anterior de $($contenedor.Name). La aplicación usa $($masNueva.Name) y no vuelve a esta." `
                          -Metodo 'Ruta' -Raices @($contenedor.FullName) -Riesgo 'Bajo'
        }
    }

    # ==================================================================
    # 2. Instaladores de controladores ya aplicados
    # ==================================================================
    # Son la carpeta donde el instalador se descomprime a si mismo. El
    # controlador ya esta instalado en el sistema: esto es el paquete,
    # no el controlador. El DriverStore de Windows -que si es el
    # controlador- sigue vetado por la guardia, y asi debe seguir.
    $unidad = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }

    $instaladores = @(
        @{ N = 'Instaladores de NVIDIA';      R = (Join-RutaNativa $unidad 'NVIDIA'); E = 'Carpeta donde el instalador de NVIDIA se descomprime. El controlador ya está instalado: esto es el paquete.' }
        @{ N = 'Instaladores de AMD';         R = (Join-RutaNativa $unidad 'AMD');    E = 'Carpeta donde el instalador de AMD se descomprime. El controlador ya está instalado.' }
        @{ N = 'Instaladores de Intel';       R = (Join-RutaNativa $unidad 'Intel');  E = 'Carpeta donde el instalador de Intel se descomprime. El controlador ya está instalado.' }
        @{ N = 'Instaladores del fabricante'; R = (Join-RutaNativa $unidad 'SWSetup'); E = 'Instaladores que deja el fabricante del equipo. Se pueden volver a descargar de su web.' }
        @{ N = 'Descargas de NVIDIA';         R = (Join-RutaNativa $env:ProgramData 'NVIDIA Corporation' 'Downloader'); E = 'Paquetes descargados por GeForce Experience. Se vuelven a bajar.' }
    )

    foreach ($entrada in $instaladores) {
        if (Test-Cancelacion $Sync) { break }
        if ([string]::IsNullOrWhiteSpace($entrada.R)) { continue }
        if (-not (Test-Path -LiteralPath $entrada.R)) { continue }

        # La raiz autorizada es la propia carpeta: se vacia por dentro y el
        # contenedor se queda, que es lo que menos puede sorprender.
        if (-not (Test-RutaSegura $entrada.R @($entrada.R))) { continue }

        Set-Progreso $Sync "Midiendo: $($entrada.N)"
        $bytes = Measure-Ruta $entrada.R
        if ($bytes -lt 50MB) { continue }

        New-Candidato -ModuloId 'restosregistro' -Categoria 'Instaladores de controladores' `
                      -Nombre $entrada.N -Ruta $entrada.R -Bytes $bytes `
                      -Info 'se vacía el contenido, la carpeta se queda' `
                      -Efecto $entrada.E `
                      -Metodo 'Contenido' -Raices @($entrada.R) -Riesgo 'Bajo'
    }

    # ==================================================================
    # 3. Entradas de desinstalación que apuntan a la nada
    # ==================================================================
    # SOLO INFORMATIVO. El programa no escribe en el registro.
    #
    # Además de ser ruido en "Aplicaciones instaladas", estas entradas
    # tienen un efecto que se nota en el propio Cachivache: alimentan el
    # vocabulario de programas instalados, así que hacen que carpetas de
    # programas ya desinstalados se den por reconocidas y no se propongan.
    Set-Progreso $Sync 'Revisando entradas de desinstalación...'

    $claves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $fantasmas = [Collections.Generic.List[string]]::new()
    foreach ($clave in $claves) {
        if (Test-Cancelacion $Sync) { break }
        foreach ($entrada in @(Get-ItemProperty -Path $clave -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($entrada.DisplayName)) { continue }
            # Sin InstallLocation no se puede afirmar nada: muchos
            # programas legitimos no la declaran.
            if ([string]::IsNullOrWhiteSpace($entrada.InstallLocation)) { continue }

            $ruta = [Environment]::ExpandEnvironmentVariables($entrada.InstallLocation).Trim('"', ' ')
            if ([string]::IsNullOrWhiteSpace($ruta)) { continue }
            if (Test-Path -LiteralPath $ruta) { continue }

            # Una unidad que no esta montada ahora mismo no significa que
            # el programa no exista: puede ser un disco externo.
            $letra = Get-LetraUnidad $ruta
            if ($letra -and -not (Test-Path -LiteralPath ($letra + '\'))) { continue }

            $fantasmas.Add("$($entrada.DisplayName) -> $ruta")
        }
    }

    if ($fantasmas.Count -gt 0) {
        New-Candidato -ModuloId 'restosregistro' -Categoria 'Entradas de desinstalación fantasma' `
                      -Nombre "$($fantasmas.Count) entradas apuntan a carpetas que ya no existen" `
                      -Ruta 'Registro de Windows' -Bytes 0 `
                      -Info (($fantasmas | Select-Object -First 8) -join '; ') `
                      -Efecto ('Aparecen en "Aplicaciones instaladas" pero su carpeta ya no está. ' +
                               'Este programa NUNCA escribe en el registro: solo te avisa. ' +
                               'Además hacen que Cachivache de por instalados programas que ya no lo están.') `
                      -Metodo 'Informativo' -Riesgo 'Bajo'
    }

    # ==================================================================
    # 4. Carpetas de Archivos de programa sin nada que las respalde
    # ==================================================================
    # Lo mas incierto del modulo: hay programas perfectamente instalados
    # que no dejan entrada de desinstalacion (los portables copiados a
    # mano, por ejemplo). Por eso va con riesgo Alto, con aviso y sin
    # marcar jamas.
    $vocabulario = Get-TokensProgramasInstalados -Sync $Sync

    $protegidas = @(
        'windowsapps', 'commonfiles', 'archivoscomunes', 'modifiablewindowsapps',
        'windowsdefender', 'windowsnt', 'windowsmediaplayer', 'windowsphotoviewer',
        'windowsportabledevices', 'windowssidebar', 'internetexplorer', 'microsoft',
        'microsoftoffice', 'microsoftsdks', 'microsoftvisualstudio', 'dotnet',
        'msbuild', 'referenceassemblies', 'uninstallinformation', 'desktop',
        'nvidiacorporation', 'amd', 'intel', 'realtek', 'application verifier'
    )

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        if (-not (Test-Path -LiteralPath $base)) { continue }
        if (Test-Cancelacion $Sync) { break }

        Set-Progreso $Sync "Revisando $(Get-RutaCorta $base)..."

        foreach ($carpeta in @(Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Cancelacion $Sync) { break }

            if (Test-EsEnlace $carpeta)                                { continue }
            if ($protegidas -contains (ConvertTo-Token $carpeta.Name))  { continue }
            if (Test-NombreSensible $carpeta.Name)                      { continue }
            if (Test-RutaIntocable $carpeta.FullName)                   { continue }
            if (-not (Test-RutaSegura $carpeta.FullName @($base)))      { continue }
            if (Test-TokenConocido -Nombre $carpeta.Name -Vocabulario $vocabulario) { continue }

            Set-Progreso $Sync "Midiendo: $($carpeta.Name)"
            $resumen = Get-ResumenArbol -Carpeta $carpeta
            if ($resumen.Bytes -lt ($Configuracion.MinimoMB * 1MB)) { continue }
            if ($resumen.Archivos -eq 0) { continue }

            New-Candidato -ModuloId 'restosregistro' -Categoria 'Huérfanos de Archivos de programa' `
                          -Nombre $carpeta.Name -Ruta $carpeta.FullName -Bytes $resumen.Bytes `
                          -Info "$($resumen.Archivos) archivos en $(Get-RutaElidida $base 40)" `
                          -Efecto 'No hay entrada de desinstalación, ni servicio, ni acceso del menú Inicio que corresponda a esta carpeta.' `
                          -Aviso 'Un programa portable copiado a mano tampoco deja entrada de desinstalación: comprueba que no lo usas.' `
                          -Metodo 'Ruta' -Raices @($base) -Riesgo 'Alto' -Preseleccionado $false
        }
    }
}

New-ModuloLimpieza -Id 'restosregistro' -Orden 32 `
    -Nombre 'Restos fuera de AppData' `
    -Descripcion 'Versiones antiguas de aplicaciones, instaladores de controladores ya aplicados, entradas de desinstalación que apuntan a la nada y carpetas huérfanas de Archivos de programa.' `
    -Riesgo 'Medio' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarRestosRegistro
