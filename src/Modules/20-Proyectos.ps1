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
        #
        # La pila propia que habia aqui hacia justo eso, pero SIN el
        # prefijo de ruta larga: un node_modules a cinco niveles de una
        # ruta ya honda no se veia. Ahora la pila es la compartida de
        # Get-ElementosDelArbol, que si lo pone. Ver [COR-08].
        #
        # La regla de que es candidata se escribe UNA vez y se usa en los
        # dos sitios que la necesitan -que se emite y donde no se entra-,
        # porque son la misma pregunta: si se separaran, un dia se podaria
        # una carpeta que no se propone o se propondria una en la que
        # ademas se ha entrado, que es el doble conteo de [R-06] otra vez.
        $esRegenerable = {
            param($Carpeta)
            if ($Carpeta.Name -match $patronInequivoco) { return $true }
            if ($Carpeta.Name -match $patronAmbiguo)    { return $true }
            # El unico caso que depende del padre: .angular\cache.
            return ($Carpeta.Name -eq 'cache' -and
                    [IO.Path]::GetFileName($Carpeta.DirectoryName) -eq '.angular')
        }

        $noDescender = {
            param($Carpeta)
            # El control de versiones no se toca ni se recorre. Se devuelve
            # igualmente y lo descarta el filtro de abajo, que es quien
            # decide que se propone.
            if ($Carpeta.Name -eq '.git' -or $Carpeta.Name -eq '.svn') { return $true }
            return (& $esRegenerable $Carpeta)
        }

        $encontradas = [Collections.Generic.List[object]]::new()
        Get-ElementosDelArbol -Ruta $raiz -Que Carpetas `
                              -NoDescender $noDescender `
                              -Cancelado { Test-Cancelacion $Sync } |
            ForEach-Object {
                if (& $esRegenerable $_) { $encontradas.Add($_) }
            }

        foreach ($carpeta in $encontradas) {
            if (Test-Cancelacion $Sync) { break }

            # Las ambiguas exigen un manifiesto de proyecto al lado.
            if ($carpeta.Name -match $patronAmbiguo) {
                $padre = $carpeta.DirectoryName
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
