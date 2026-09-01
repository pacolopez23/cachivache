<#
.SYNOPSIS
    Discos virtuales de WSL y capas de imagen de Docker.
.DESCRIPTION
    Los discos de WSL crecen pero no se encogen solos: aunque borres los
    archivos de dentro, el .vhdx sigue ocupando lo mismo en Windows. Este
    módulo mide cuanto ocupan y ofrece los comandos oficiales para
    reclamarlos. Nada se borra por las bravas.
#>

$BuscarDockerWsl = {
    param($Configuracion, $Sync)

    Set-Progreso $Sync 'Buscando discos virtuales de WSL y Docker...'
    $paquetes = Join-Path $env:LOCALAPPDATA 'Packages'
    $encontrados = @()

    # --- Distribuciones de WSL instaladas desde la Store ------------------
    if (Test-Path -LiteralPath $paquetes) {
        # Se mira SOLO en Packages\<paquete>\LocalState, que es donde WSL
        # guarda el disco. Antes se hacia -Recurse sobre cada paquete: en
        # un equipo con muchas aplicaciones de la Store son decenas de
        # miles de archivos enumerados para encontrar uno o dos .vhdx, y
        # ademas se entraba en carpetas de datos del usuario sin necesidad.
        # Ver [REN-51] en docs/PLAN-ACCION.md.
        foreach ($paquete in @(Get-ChildItem -LiteralPath $paquetes -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Cancelacion $Sync) { break }
            $estado = Join-RutaNativa $paquete.FullName 'LocalState'
            if (-not (Test-Path -LiteralPath $estado)) { continue }

            foreach ($disco in @(Get-ChildItem -LiteralPath $estado -Filter '*.vhdx' -File -Force -ErrorAction SilentlyContinue)) {
                $encontrados += $disco
            }
        }
    }

    # --- Docker Desktop --------------------------------------------------
    foreach ($carpeta in @(
        (Join-Path $env:LOCALAPPDATA 'Docker\wsl'),
        (Join-Path $env:APPDATA 'Docker\vms'))) {
        if (-not (Test-Path -LiteralPath $carpeta)) { continue }
        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        # -MedirEnDisco: [VIS-05]. Solo pregunta el tamano en disco de lo
        # que lleva el bit de comprimido, asi que en el caso normal no
        # cuesta ni una llamada al sistema. Sin esto, en una carpeta
        # comprimida el modulo promete liberar el tamano LOGICO y libera
        # bastante menos.
        Get-ElementosDelArbol -Ruta $carpeta -Filtro '*.vhdx' -MedirEnDisco |
            ForEach-Object { $encontrados += $_ }
    }

    foreach ($disco in $encontrados) {
        if (Test-Cancelacion $Sync) { break }
        if ($disco.Length -lt 500MB) { continue }

        $esDocker = $disco.FullName -match '(?i)docker'
        $efecto = if ($esDocker) {
            'Ejecuta "docker system prune -a" para borrar imágenes y contenedores sin usar, y después "wsl --shutdown" seguido de Optimize-VHD para compactar el disco.'
        } else {
            'Borra lo que sobre dentro de la distribución, ejecuta "wsl --shutdown" y compacta el disco con diskpart o con Optimize-VHD.'
        }

        New-Candidato -ModuloId 'dockerwsl' -Categoria 'WSL y Docker' `
                      -Nombre "Disco virtual: $(Split-Path (Split-Path $disco.FullName -Parent) -Leaf)" `
                      -Ruta $disco.FullName -Bytes $disco.Length `
                      -TamanoEnDisco $disco.TamanoEnDisco `
                      -Info "$($disco.Name) - último cambio $($disco.LastWriteTime.ToString('yyyy-MM-dd'))" `
                      -Efecto $efecto `
                      -Aviso 'Este archivo contiene TODO el sistema de archivos de esa distribución. Borrarlo destruye los datos que haya dentro.' `
                      -Metodo 'Informativo' -Raices @() -Riesgo 'Alto' -Preseleccionado $false
    }

    # --- Cache de compilación de Docker (esta si se puede vaciar) ----------
    # -CommandType Application: sin el, una función o un alias llamado
    # 'docker' en la sesión bastaba para crear el candidato, que luego
    # fallaba siempre al borrar porque Resolve-EjecutablePermitido si
    # filtra por tipo. Es el mismo fallo de [C-17], aquí repetido.
    if (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue) {
        New-Candidato -ModuloId 'dockerwsl' -Categoria 'WSL y Docker' `
                      -Nombre 'Limpiar imágenes y contenedores de Docker sin usar' `
                      -Ruta 'docker system prune' -Bytes 0 `
                      -Info 'ejecuta el comando oficial de Docker' `
                      -Efecto 'Borra contenedores parados, redes sin usar, imágenes colgadas y la caché de compilación.' `
                      -Aviso 'Se perderán los contenedores parados que quisieras reutilizar.' `
                      -Metodo 'Comando' -Ejecutable 'docker' -Argumentos @('system', 'prune', '-a', '-f') `
                      -Comando 'docker system prune -a -f' `
                      -Raices @() -Riesgo 'Medio' -Preseleccionado $false
    }
}

New-ModuloLimpieza -Id 'dockerwsl' -Orden 85 `
    -Nombre 'WSL y Docker' `
    -Descripcion 'Discos virtuales .vhdx que crecen y no se encogen solos, y la caché de imágenes de Docker.' `
    -Riesgo 'Alto' `
    -Perfiles @('agresivo') `
    -Buscar $BuscarDockerWsl
