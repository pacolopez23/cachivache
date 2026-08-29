<#
.SYNOPSIS
    Carpetas sin un solo archivo dentro, en todo su subarbol.
.DESCRIPTION
    No liberan espacio: ordenan. Se excluyen las carpetas espejo del sistema
    (Mis imágenes, Favoritos, Vinculos...), que parecen vacías pero son
    enlaces heredados, y se saltan los junctions.

    Una cadena de carpetas vacías anidadas (a\b\c, sin un solo archivo en
    ningún nivel) se propone UNA vez, por su carpeta más alta, no una por
    nivel. Antes solo se detectaban las hojas y hacia falta ejecutar el
    programa tantas veces como niveles tuviera la cadena. Ver [C-09] en
    docs/OPTIMIZACIONES.md.
#>

$BuscarCarpetasVacias = {
    param($Configuracion, $Sync)

    $zonas = @($Configuracion.ZonasUsuario)
    if ($zonas.Count -eq 0) { return }

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Revisando $(Get-RutaCorta $zona)..."

        # Carpetas candidatas a estar vacías. Las que se excluyen aquí
        # (enlaces, node_modules, .git, carpetas espejo) NO son candidatas y
        # además cuentan como contenido para su carpeta padre: una carpeta
        # que solo contiene un .git no esta vacía.
        # Recorrido propio con PODA, no -Recurse mas filtro. Las carpetas
        # excluidas -node_modules, .git, .svn, .hg- no solo no son
        # candidatas: no hay ninguna razon para entrar en ellas, y son
        # justo las que mas subdirectorios tienen. Antes se enumeraban
        # enteras para descartarlas despues con una regex sobre la ruta.
        # Ver [REN-31] en docs/PLAN-ACCION.md.
        $excluidas = @('node_modules', '.git', '.svn', '.hg')
        $candidatas = [Collections.Generic.List[IO.DirectoryInfo]]::new()
        $porVisitar = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
        $porVisitar.Push((Get-Item -LiteralPath $zona -Force -ErrorAction SilentlyContinue))

        while ($porVisitar.Count -gt 0) {
            if (Test-Cancelacion $Sync) { break }
            $actual = $porVisitar.Pop()
            if ($null -eq $actual) { continue }

            try   { $hijas = @($actual.EnumerateDirectories()) }
            catch { continue }

            foreach ($hija in $hijas) {
                if ($hija.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($excluidas -contains $hija.Name) { continue }
                if (Test-CarpetaEspejo $hija.Name)   { continue }
                $candidatas.Add($hija)
                $porVisitar.Push($hija)
            }
        }
        if ($candidatas.Count -eq 0) { continue }

        # --- Paso 1: de abajo arriba, quien tiene el subarbol limpio ------
        # Se recorren de más profunda a menos profunda, de modo que cuando
        # se evalua una carpeta ya se sabe el veredicto de todas sus hijas.
        # Cada carpeta se mira UNA vez y solo un nivel: el coste total es
        # lineal, no cuadratico. Ver [R-05].
        $limpia = @{}
        $porProfundidad = @($candidatas | Sort-Object -Property @{
            Expression = { ($_.FullName -split '[\\/]').Count }
        } -Descending)

        foreach ($dir in $porProfundidad) {
            if (Test-Cancelacion $Sync) { break }
            # EnumerateFileSystemInfos y no Get-ChildItem: la pregunta es
            # "hay algo aqui que no sea una carpeta limpia", y se responde
            # en cuanto aparece el primer archivo. Get-ChildItem construye
            # un objeto de PowerShell por cada elemento del directorio
            # ANTES de que se pueda mirar ninguno.
            $estaLimpia = $true
            $hijos = @()
            try   { $hijos = $dir.EnumerateFileSystemInfos() }
            catch { $hijos = @() }

            foreach ($hijo in $hijos) {
                if ($hijo -isnot [IO.DirectoryInfo]) { $estaLimpia = $false; break }
                # Una subcarpeta solo "no cuenta" si sabemos que ella misma
                # esta limpia. Si no la conocemos (estaba excluida, es un
                # enlace, o no se pudo leer), cuenta como contenido.
                if (-not $limpia.ContainsKey($hijo.FullName) -or -not $limpia[$hijo.FullName]) {
                    $estaLimpia = $false; break
                }
            }
            $limpia[$dir.FullName] = $estaLimpia
        }
        if (Test-Cancelacion $Sync) { break }

        # --- Paso 2: emitir solo la cima de cada cadena -------------------
        foreach ($dir in $candidatas) {
            if (Test-Cancelacion $Sync) { break }
            if (-not $limpia[$dir.FullName]) { continue }

            # Si el padre también esta limpio, ya se propondra el, y borrarlo
            # se lleva esta por delante. Solo se emite la carpeta más alta.
            $padre = Split-Path $dir.FullName -Parent
            if ($limpia.ContainsKey($padre) -and $limpia[$padre]) { continue }

            if (-not (Test-RutaSegura $dir.FullName $zonas)) { continue }

            $niveles = @($candidatas | Where-Object {
                $_.FullName.StartsWith($dir.FullName + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
            }).Count
            $info = if ($niveles -gt 0) {
                "creada $($dir.CreationTime.ToString('yyyy-MM-dd')) - contiene $niveles subcarpetas, todas vacías"
            } else {
                "creada $($dir.CreationTime.ToString('yyyy-MM-dd'))"
            }

            # Premarcar una carpeta vacia DENTRO de AppData es inofensivo:
            # ahi no organiza nadie a mano. Premarcarla en el Escritorio o
            # en Documentos no lo es. Una carpeta vacia que el usuario
            # acaba de crear para ordenar -"Fotos boda\Sin clasificar",
            # "Proyecto 2026"- esta vacia justo porque todavia no ha metido
            # nada, y desaparecia sola por venir marcada por defecto.
            #
            # Se exige ademas cierta antiguedad: una carpeta creada hoy es,
            # por definicion, algo que alguien acaba de hacer a proposito.
            # Ver [FAL-02] en docs/PLAN-ACCION.md.
            $enAppData = $false
            foreach ($base in @($env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData)) {
                if ([string]::IsNullOrWhiteSpace($base)) { continue }
                if ($dir.FullName.StartsWith($base.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar,
                                             [StringComparison]::OrdinalIgnoreCase)) {
                    $enAppData = $true
                    break
                }
            }

            $diasDesdeCreacion = [int]((Get-Date) - $dir.CreationTime).TotalDays
            $marcar = $enAppData -or ($diasDesdeCreacion -ge $Configuracion.DiasSinUso)

            $aviso = if (-not $marcar) {
                'Creada hace poco y fuera de AppData: puede ser una carpeta que hayas hecho tú para ordenar.'
            } else { '' }

            New-Candidato -ModuloId 'vacias' -Categoria 'Carpetas vacías' `
                          -Nombre (Get-RutaCorta $dir.FullName) -Ruta $dir.FullName -Bytes 0 `
                          -Info $info `
                          -Efecto 'Ni un solo archivo en toda la carpeta. No libera espacio: ordena.' `
                          -Aviso $aviso `
                          -Metodo 'CarpetaVacia' -Raices $zonas -Riesgo 'Bajo' -Preseleccionado $marcar
        }
    }
}

New-ModuloLimpieza -Id 'vacias' -Orden 40 `
    -Nombre 'Carpetas vacías' `
    -Descripcion 'Carpetas sin un solo archivo dentro. Ordenan, no liberan espacio.' `
    -Riesgo 'Bajo' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarCarpetasVacias
