<#
.SYNOPSIS
    Cachés de aplicaciones, herramientas de desarrollo y del sistema.
.DESCRIPTION
    Todo lo de este módulo lo vuelve a crear el programa correspondiente sin
    intervencion. Siempre se vacía el CONTENIDO y se deja la carpeta, porque
    muchas aplicaciones fallan si su carpeta de cache desaparece.
#>

$BuscarCaches = {
    param($Configuracion, $Sync)

    $LA = $env:LOCALAPPDATA
    $RA = $env:APPDATA
    $UP = $env:USERPROFILE

    # Menor = $true significa que suele ocupar poco y solo se propone en
    # perfil exhaustivo o con "incluir elementos pequeños" activado.
    $plantilla = @(
        # --- Desarrollo -------------------------------------------------
        @{ N = 'Caché de npm';               R = "$LA\npm-cache";        M = 'Contenido'; Menor = $false; E = 'Se recrea. El siguiente npm install descargara de la red.' }
        @{ N = 'Cache de Yarn';              R = "$LA\Yarn\Cache";       M = 'Contenido'; Menor = $false; E = 'Se recrea en la siguiente instalación.' }
        @{ N = 'Cache de pnpm';              R = "$LA\pnpm-cache";       M = 'Contenido'; Menor = $true;  E = 'Se recrea.' }
        @{ N = 'Caché de Gradle';            R = "$UP\.gradle\caches";   M = 'Contenido'; Menor = $false; E = 'Se recrea. El siguiente build de Android o Java tardará más.' }
        # Aviso explicito: estos tres no son SOLO cache. "mvn install",
        # "dotnet pack" y "cargo publish --dry-run" dejan ahi artefactos
        # locales que no estan en ningun repositorio remoto, asi que
        # vaciarlos puede romper una compilacion sin red de forma que no
        # se arregla volviendo a descargar. Ver [FAL-06].
        @{ N = 'Repositorio local de Maven'; R = "$UP\.m2\repository";   M = 'Contenido'; Menor = $true;  A = 'Puede contener artefactos instalados en local con "mvn install" que no están en ningún repositorio remoto.'; E = 'Se vuelve a descargar en el siguiente build.' }
        @{ N = 'Cache de pip';               R = "$LA\pip\Cache";        M = 'Contenido'; Menor = $false; E = 'Se recrea.' }
        @{ N = 'Paquetes de NuGet';          R = "$UP\.nuget\packages";  M = 'Contenido'; Menor = $true;  A = 'Puede contener paquetes generados en local con "dotnet pack" que no están publicados.'; E = 'Se vuelven a descargar al compilar .NET.' }
        @{ N = 'Registro de Cargo (Rust)';   R = "$UP\.cargo\registry";  M = 'Contenido'; Menor = $true;  E = 'Se vuelve a descargar al compilar.' }
        @{ N = 'Caché de compilación de Go'; R = "$LA\go-build";         M = 'Contenido'; Menor = $true;  E = 'Se regenera al compilar.' }
        @{ N = 'Caché de Composer';          R = "$LA\Composer";         M = 'Contenido'; Menor = $true;  E = 'Se recrea.' }
        @{ N = 'Caché de Docker Desktop';    R = "$LA\Docker\log";       M = 'Contenido'; Menor = $true;  E = 'Solo registros. Sin efecto.' }
        # Herramientas de desarrollo que faltaban. Ver [DET-61].
        # .gradle\wrapper\dists guarda una distribucion entera de Gradle
        # POR VERSION usada -unos 200 MB cada una- y no se limpia sola.
        @{ N = 'Distribuciones de Gradle';   R = "$UP\.gradle\wrapper\dists"; M = 'Contenido'; Menor = $false; E = 'Se vuelven a descargar en el siguiente build.' }
        @{ N = 'Demonios de Gradle';         R = "$UP\.gradle\daemon";         M = 'Contenido'; Menor = $true;  E = 'Solo registros del proceso en segundo plano. Sin efecto.' }
        @{ N = 'Paquetes de conda';          R = "$UP\.conda\pkgs";            M = 'Contenido'; Menor = $false; E = 'Se vuelven a descargar al crear el siguiente entorno.' }
        @{ N = 'Caché de Yarn Berry';        R = "$LA\Yarn\Berry\cache";      M = 'Contenido'; Menor = $true;  E = 'Se recrea.' }
        @{ N = 'Navegadores de Playwright';  R = "$LA\ms-playwright";           M = 'Contenido'; Menor = $false; E = 'Se vuelven a descargar al ejecutar las pruebas.' }
        @{ N = 'Caché de electron-builder';  R = "$LA\electron-builder\Cache"; M = 'Contenido'; Menor = $true;  E = 'Se recrea al empaquetar.' }

        # --- Gráficos y juegos -------------------------------------------
        @{ N = 'Shaders NVIDIA (DXCache)';   R = "$LA\NVIDIA\DXCache";   M = 'Contenido'; Menor = $false; E = 'Se regenera. El primer arranque de cada juego irá algo más lento.' }
        @{ N = 'Shaders NVIDIA (GLCache)';   R = "$LA\NVIDIA\GLCache";   M = 'Contenido'; Menor = $true;  E = 'Se regenera.' }
        @{ N = 'Caché DirectX (D3DSCache)';  R = "$LA\D3DSCache";        M = 'Contenido'; Menor = $true;  E = 'Se regenera.' }
        @{ N = 'Caché de shaders AMD';       R = "$LA\AMD\DxCache";      M = 'Contenido'; Menor = $true;  E = 'Se regenera.' }
        # El resto de cachés de sombreadores que faltaban. Todas las
        # regenera sola la tarjeta grafica la primera vez que arranca cada
        # juego, y en un equipo con muchos juegos suman varios GB.
        # Ver [DET-60] en docs/PLAN-ACCION.md.
        @{ N = 'Shaders NVIDIA (ComputeCache)'; R = "$LA\NVIDIA\ComputeCache";         M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché de NVIDIA (NV_Cache)';    R = "$LA\NVIDIA Corporation\NV_Cache"; M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché de shaders AMD (DXC)';    R = "$LA\AMD\DxcCache";                M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché de shaders AMD (OpenGL)'; R = "$LA\AMD\GLCache";                 M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché de shaders AMD (Vulkan)'; R = "$LA\AMD\VkCache";                 M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché de shaders de Intel';     R = "$LA\Intel\ShaderCache";           M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        # Steam y Epic YA NO estan aqui: los propone 33-Juegos, que ademas
        # cubre el resto de plataformas. Tenerlos en los dos sitios
        # significaba dos filas identicas para la misma ruta.
        #
        # Y el de Epic estaba mal apuntado: señalaba "Saved" ENTERO, que
        # incluye Config\Windows\GameUserSettings.ini -los ajustes del
        # lanzador- ademas de los registros y la cache web. El modulo de
        # juegos apunta a Saved\Logs y Saved\webcache por separado.
        # Ver [FAL-04] en docs/PLAN-ACCION.md.

        # --- Aplicaciones de escritorio -----------------------------------
        @{ N = 'Caché de Discord';           R = "$RA\discord\Cache";               M = 'Contenido'; Menor = $true; E = 'Sin efecto. Cierra Discord antes.' }
        # Spotify\Storage es la cache de reproduccion; Spotify\Data es la
        # musica DESCARGADA para escuchar sin conexion. No son lo mismo, y
        # con tarifa limitada la diferencia se paga. Ver [FAL-07].
        @{ N = 'Caché de Spotify';           R = "$LA\Spotify\Storage";             M = 'Contenido'; Menor = $true; E = 'Se regenera al reproducir.' }
        @{ N = 'Música sin conexión de Spotify'; R = "$LA\Spotify\Data";            M = 'Contenido'; Menor = $true; A = 'Es la música que descargaste para escuchar sin conexión: hay que volver a bajarla.'; E = 'Se vuelve a descargar la música guardada sin conexión.' }
        @{ N = 'Caché de Teams';             R = "$RA\Microsoft\Teams\Cache";       M = 'Contenido'; Menor = $true; E = 'Sin efecto. Cierra Teams antes.' }
        @{ N = 'Caché de VS Code';           R = "$RA\Code\Cache";                  M = 'Contenido'; Menor = $true; E = 'Se regenera. Cierra VS Code antes.' }
        @{ N = 'Datos compilados de VS Code';R = "$RA\Code\CachedData";             M = 'Contenido'; Menor = $true; E = 'Se regenera al abrir VS Code.' }
        @{ N = 'Caché de Slack';             R = "$RA\Slack\Cache";                 M = 'Contenido'; Menor = $true; E = 'Se regenera. Cierra Slack antes.' }
        @{ N = 'Caché de Postman';           R = "$RA\Postman\Cache";               M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché de GitHub Desktop';    R = "$LA\GitHubDesktop\Cache";         M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        # NO se apunta a "$RA\Zoom\data" entero: ahi vive zoomus.enc.db,
        # que es el historial de chat local, y las grabaciones locales.
        # Solo los registros. Ver [FAL-05] en docs/PLAN-ACCION.md.
        @{ N = 'Registros de Zoom';          R = "$RA\Zoom\logs";                   M = 'Contenido'; Menor = $true; E = 'Sin efecto.' }
        @{ N = 'Caché de Obsidian';          R = "$RA\obsidian\Cache";              M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Caché multimedia de Adobe';  R = "$RA\Adobe\Common\Media Caché Files"; M = 'Contenido'; Menor = $false; E = 'Se regenera. La próxima previsualizacion tardará más.' }
        @{ N = 'Caché de archivos de Office';R = "$LA\Microsoft\Office\16.0\OfficeFileCache"; M = 'Contenido'; Menor = $true; E = 'Se regenera. Cierra Office antes.' }

        # --- Sistema ------------------------------------------------------
        @{ N = 'Miniaturas del Explorador';  R = "$LA\Microsoft\Windows\Explorer";  M = 'Miniaturas'; Menor = $true; E = 'Se regeneran al abrir las carpetas.' }
        @{ N = 'Volcados de programas rotos';R = "$LA\CrashDumps";                  M = 'Contenido'; Menor = $true;  E = 'Sin efecto.' }
        @{ N = 'Caché de Internet de Windows'; R = "$LA\Microsoft\Windows\INetCache"; M = 'Contenido'; Menor = $true; E = 'Se regenera al navegar. No borra contraseñas, cookies ni historial.' }
        @{ N = 'Informes de error en cola';  R = "$LA\Microsoft\Windows\WER\ReportQueue"; M = 'Contenido'; Menor = $true; E = 'Se regeneran si vuelve a fallar algo.' }
        @{ N = 'Temporales del usuario';     R = "$LA\Temp";                        M = 'Contenido'; Menor = $false; E = 'Sin efecto. Los archivos en uso se saltan solos.' }
    )

    $raices = @(
        $LA, $RA,
        "$UP\.gradle", "$UP\.m2", "$UP\.nuget", "$UP\.cargo", "$UP\.conda"
    ) | Where-Object { $_ }

    # Programas que bloquean sus propios archivos de cache.
    $procesosQueBloquean = Test-ProcesoAbierto @(
        'chrome', 'msedge', 'firefox', 'discord', 'Spotify', 'Teams', 'ms-teams',
        'Code', 'slack', 'steam', 'EpicGamesLauncher', 'node', 'java', 'studio64', 'devenv'
    )

    Invoke-BusquedaPorLista -ModuloId 'caches' -Categoria 'Cachés' `
                            -Entradas $plantilla -Raices $raices -Sync $Sync `
                            -MinimoBytes 1MB -ForzarPermanente `
                            -IncluirMenores:$Configuracion.IncluirMenores `
                            -NotaExtra {
        param($entrada)
        # Que el programa este abierto es INFORMACIÓN, no un aviso. Iba en
        # -Aviso, y desde que New-Candidato garantiza que nada con aviso se
        # marca solo, eso habría dejado sin marcar las cachés más
        # habituales por el mero hecho de tener el navegador abierto.
        foreach ($proceso in $procesosQueBloquean) {
            if ($entrada.N -match "(?i)$([regex]::Escape($proceso))") {
                return " - $proceso está abierto: parte no se podra borrar"
            }
        }
        return ''
    }.GetNewClosure()

    # --- JetBrains: una carpeta caches por producto y versión -------------
    $jetbrains = Join-Path $LA 'JetBrains'
    if (Test-Path -LiteralPath $jetbrains) {
        foreach ($producto in @(Get-ChildItem -LiteralPath $jetbrains -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Cancelacion $Sync) { break }
            $cache = Join-Path $producto.FullName 'caches'
            if (-not (Test-Path -LiteralPath $cache)) { continue }
            # La guardia primero: cuesta mil veces menos que la medición y
            # descarta lo mismo. Ver docs/RENDIMIENTO.md (sección 7).
            if (-not (Test-RutaSegura $cache $raices)) { continue }
            $bytes = Measure-Ruta $cache
            if ($bytes -lt 1MB) { continue }

            New-Candidato -ModuloId 'caches' -Categoria 'Cachés' `
                          -Nombre "JetBrains - $($producto.Name)" -Ruta $cache -Bytes $bytes `
                          -Info 'se vacía el contenido, la carpeta se queda' `
                          -Efecto 'Se regenera al abrir el IDE. La primera indexación tardará más.' `
                          -Metodo 'Contenido' -Raices $raices -Riesgo 'Bajo' -Preseleccionado $true -ForzarPermanente
        }
    }

    # --- Cache de Firefox: solo las subcarpetas cache2 ---------------------
    $perfilesFirefox = Join-Path $LA 'Mozilla\Firefox\Profiles'
    if ((Test-Path -LiteralPath $perfilesFirefox) -and (Test-RutaSegura $perfilesFirefox $raices)) {
        # La guardia se ha adelantado al bucle: si la carpeta de perfiles
        # esta vetada, medir cache2 de cada perfil es trabajo tirado.
        $bytes = 0.0
        foreach ($perfil in @(Get-ChildItem -LiteralPath $perfilesFirefox -Directory -Force -ErrorAction SilentlyContinue)) {
            $bytes += Measure-Ruta (Join-Path $perfil.FullName 'cache2')
        }
        if ($bytes -ge 1MB) {
            $aviso = if (Test-ProcesoAbierto @('firefox')) { 'Firefox está abierto: ciérralo antes para vaciar la caché entera.' } else { '' }
            New-Candidato -ModuloId 'caches' -Categoria 'Cachés' -Nombre 'Caché de Firefox' `
                          -Ruta $perfilesFirefox -Bytes $bytes `
                          -Info 'solo las carpetas cache2 de cada perfil' `
                          -Efecto 'No borra contraseñas, marcadores, cookies ni historial.' `
                          -Aviso $aviso -Metodo 'FirefoxCache' -Raices $raices `
                          -Riesgo 'Bajo' -Preseleccionado $true -ForzarPermanente
        }
    }
}

New-ModuloLimpieza -Id 'caches' -Orden 10 `
    -Nombre 'Cachés de aplicaciones y desarrollo' `
    -Descripcion 'Archivos que el sistema y los programas vuelven a crear solos. Se vacía el contenido, nunca la carpeta.' `
    -Riesgo 'Bajo' `
    -Perfiles @('conservador', 'equilibrado', 'agresivo') `
    -Buscar $BuscarCaches
