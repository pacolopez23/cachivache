<#
.SYNOPSIS
    Carpetas regenerables dentro de proyectos de programacion.
.DESCRIPTION
    node_modules, dist, build, target, __pycache__ y compañía: todo lo que
    vuelve solo con un comando. Nunca se toca código fuente ni la carpeta
    .git, y las carpetas ambiguas (out, build, dist) solo se proponen si
    junto a ellas hay un manifiesto de proyecto que lo justifique.
#>

$BuscarProyectos = {
    param($Configuracion, $Sync)

    $raices = @($Configuracion.RaicesProyecto | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($raices.Count -eq 0) { return }

    # Carpetas cuyo nombre ya es prueba suficiente.
    $patronInequivoco = '^(node_modules|\.next|\.nuxt|\.svelte-kit|\.turbo|\.parcel-cache|__pycache__|\.pytest_cache|\.mypy_cache|\.tox|\.gradle|Pods)$'
    # Carpetas ambiguas: "build" puede ser código fuente de alguien.
    #
    # "vendor" y "target" estaban arriba, entre las inequivocas, y no lo
    # son. En Go, vendor/ SE VERSIONA a proposito y es lo que permite
    # compilar sin red: borrarlo no es limpiar, es romper el proyecto. Y
    # "target" es un nombre de carpeta corriente fuera de Rust y de Maven.
    # Bajan a ambiguas, donde hay que demostrar con un manifiesto al lado
    # que son lo que parecen. Ver [FAL-08] en docs/PLAN-ACCION.md.
    $patronAmbiguo    = '^(dist|build|out|obj|bin|\.venv|venv|target|vendor)$'

    $manifiestos = @('package.json', 'pom.xml', 'build.gradle', 'build.gradle.kts',
                     'CMakeLists.txt', 'Cargo.toml', 'go.mod', 'pyproject.toml',
                     'requirements.txt', 'composer.json', 'Gemfile')

    $efectos = @{
        'node_modules'  = 'Vuelve con: npm install'
        '.next'         = 'Vuelve con: npm run build'
        '.nuxt'         = 'Vuelve con: npm run build'
        'target'        = 'Vuelve con: mvn package o gradle build'
        '__pycache__'   = 'Vuelve solo al ejecutar Python'
        '.venv'         = 'Vuelve con: python -m venv .venv && pip install -r requirements.txt'
        'venv'          = 'Vuelve con: python -m venv venv && pip install -r requirements.txt'
        'vendor'        = 'Vuelve con: composer install'
        '.gradle'       = 'Vuelve con el siguiente build'
    }

    foreach ($raiz in $raices) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Buscando proyectos en $(Get-RutaCorta $raiz)..."

        # Recorrido con PODA, no filtrado del resultado.
        #
        # Antes esto era "Get-ChildItem -Recurse -Directory" seguido de un
        # Where-Object. La diferencia parece de estilo y no lo es: -Recurse
        # entra DENTRO de cada node_modules y enumera sus decenas de miles
        # de subdirectorios, y solo despues los descarta con una regex. Con
        # diez proyectos Node son del orden de 300.000 directorios
        # enumerados para quedarse con unos 5.000.
        #
        # Al encontrar una carpeta regenerable no hay nada que buscar
        # dentro: se emite y NO se desciende. Eso arregla de paso un fallo
        # de contabilidad que no era de rendimiento: todo paquete npm trae
        # su propio package.json, asi que sus 'dist', 'build' y 'lib'
        # pasaban el filtro de manifiesto y se proponian por separado
        # ADEMAS del node_modules que los contiene. Los mismos bytes se
        # sumaban dos veces en el total que ve el usuario, y borrar el
        # padre dejaba a los hijos apuntando a rutas que ya no existian.
        # Ver [REN-32] y [R-06] en docs/OPTIMIZACIONES.md.
        $encontradas = [Collections.Generic.List[IO.DirectoryInfo]]::new()
        $pendientes  = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
        $pendientes.Push((Get-Item -LiteralPath $raiz -Force -ErrorAction SilentlyContinue))

        while ($pendientes.Count -gt 0) {
            if (Test-Cancelacion $Sync) { break }
            $actual = $pendientes.Pop()
            if ($null -eq $actual) { continue }

            try   { $hijas = @($actual.EnumerateDirectories()) }
            catch { continue }

            foreach ($hija in $hijas) {
                if ($hija.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                # El control de versiones no se toca ni se recorre.
                if ($hija.Name -eq '.git' -or $hija.Name -eq '.svn') { continue }

                $esCandidata = $hija.Name -match $patronInequivoco -or
                               $hija.Name -match $patronAmbiguo -or
                               ($hija.Name -eq 'cache' -and $actual.Name -eq '.angular')

                if ($esCandidata) {
                    $encontradas.Add($hija)
                    continue    # <- la poda: no se entra
                }
                $pendientes.Push($hija)
            }
        }

        foreach ($carpeta in $encontradas) {
            if (Test-Cancelacion $Sync) { break }

            # Las ambiguas exigen un manifiesto de proyecto al lado.
            if ($carpeta.Name -match $patronAmbiguo) {
                $padre = $carpeta.Parent.FullName
                $tieneManifiesto = $false
                foreach ($manifiesto in $manifiestos) {
                    if (Test-Path -LiteralPath (Join-Path $padre $manifiesto)) { $tieneManifiesto = $true; break }
                }
                if (-not $tieneManifiesto) {
                    $tieneManifiesto = @(Get-ChildItem -LiteralPath $padre -File -Filter '*.*proj' -ErrorAction SilentlyContinue).Count -gt 0
                }
                if (-not $tieneManifiesto) { continue }
            }

            # Preguntar antes de medir. Aquí es donde más se nota: medir un
            # node_modules de 30.000 archivos son cientos de milisegundos y
            # la guardia cuesta uno. Ver docs/RENDIMIENTO.md (sección 7).
            if (-not (Test-RutaSegura $carpeta.FullName $raices)) { continue }

            Set-Progreso $Sync "Midiendo: $(Get-RutaElidida $carpeta.FullName)"
            $bytes = Measure-Ruta $carpeta.FullName
            if ($bytes -lt ($Configuracion.MinimoMB * 1MB)) { continue }

            $efecto = 'Se regenera al recompilar el proyecto.'
            if ($efectos.ContainsKey($carpeta.Name)) { $efecto = $efectos[$carpeta.Name] }

            # Un proyecto tocado esta semana probablemente está en marcha.
            $dias = [int]((Get-Date) - $carpeta.LastWriteTime).TotalDays
            $riesgo = if ($dias -lt 7) { 'Medio' } else { 'Bajo' }
            $aviso  = if ($dias -lt 7) { 'Proyecto activo: lo has tocado esta semana.' } else { '' }

            New-Candidato -ModuloId 'proyectos' -Categoria 'Proyectos regenerables' `
                          -Nombre (Get-RutaCorta $carpeta.FullName) -Ruta $carpeta.FullName -Bytes $bytes `
                          -Info "$($carpeta.Name) - último cambio $($carpeta.LastWriteTime.ToString('yyyy-MM-dd')) ($(Format-Antiguedad $carpeta.LastWriteTime))" `
                          -Efecto $efecto -Aviso $aviso -Metodo 'Ruta' -Raices $raices -Riesgo $riesgo
        }
    }
}

New-ModuloLimpieza -Id 'proyectos' -Orden 20 `
    -Nombre 'Carpetas regenerables de proyectos' `
    -Descripcion 'node_modules, dist, build, target, __pycache__, .venv... Nunca se toca código fuente ni .git.' `
    -Riesgo 'Bajo' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarProyectos
