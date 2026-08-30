<#
.SYNOPSIS
    Instaladores y archivos antiguos en la carpeta Descargas.
.DESCRIPTION
    Solo se propone lo que casi siempre se puede volver a descargar:
    instaladores, imágenes de disco y comprimidos. Nunca se propone un
    documento, una foto ni un video, aunque sea antiguo y ocupe mucho.
#>

$BuscarDescargas = {
    param($Configuracion, $Sync)

    $zonas = @($Configuracion.Descargas) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    if ($zonas.Count -eq 0) { return }

    $limite = (Get-Date).AddDays(-$Configuracion.DiasSinUso)

    $tipos = @{
        '.exe'  = 'Instalador de Windows'
        '.msi'  = 'Instalador de Windows'
        '.msix' = 'Paquete de aplicación'
        '.appx' = 'Paquete de aplicación'
        '.iso'  = 'Imagen de disco'
        '.img'  = 'Imagen de disco'
        '.dmg'  = 'Imagen de disco de macOS'
        '.pkg'  = 'Instalador de macOS'
        '.deb'  = 'Paquete de Linux'
        '.rpm'  = 'Paquete de Linux'
        '.cab'  = 'Archivo comprimido de Windows'
        '.zip'  = 'Archivo comprimido'
        '.rar'  = 'Archivo comprimido'
        '.7z'   = 'Archivo comprimido'
        '.tar'  = 'Archivo comprimido'
        '.gz'   = 'Archivo comprimido'
        # Formatos de instalador y de paquete que faltaban. Ver [DET-65].
        '.msu'         = 'Actualización de Windows'
        '.msp'         = 'Parche de Windows'
        '.msixbundle'  = 'Paquete de aplicación'
        '.appxbundle'  = 'Paquete de aplicación'
        '.jar'         = 'Aplicación de Java'
        '.apk'         = 'Aplicación de Android'
        '.vhd'         = 'Disco virtual'
        '.vhdx'        = 'Disco virtual'
        '.esd'         = 'Imagen comprimida de Windows'
        '.bz2'         = 'Archivo comprimido'
        '.xz'          = 'Archivo comprimido'
        '.zst'         = 'Archivo comprimido'
    }

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Revisando $(Get-RutaCorta $zona)..."

        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        Get-ElementosDelArbol -Ruta $zona |
        # Solo LastWriteTime, NO la fecha de ultimo acceso, y es una
        # decision meditada en contra de lo que proponia [FAL-12].
        #
        # La idea era detectar la aplicacion portable que se ejecuta desde
        # Descargas sin que su .exe se modifique nunca. Pero en Windows la
        # actualizacion de la fecha de acceso viene DESACTIVADA de fabrica
        # (NtfsDisableLastAccessUpdate), asi que en la mayoria de equipos
        # no dice nada; y donde si esta activa, la tocan el antivirus, la
        # indexacion de busqueda y cualquier copia de seguridad, con lo que
        # archivos de hace anyos aparecen como "usados hoy".
        #
        # Los dos errores no cuestan lo mismo. Fiarse de la fecha de acceso
        # haria DESAPARECER candidatos legitimos en silencio, y el usuario
        # no puede echar de menos lo que no ve. No fiarse hace que una
        # aplicacion portable salga en una lista que este modulo nunca
        # premarca, y ahi el usuario decide en un segundo. Se prefiere el
        # error que se ve.
        Where-Object {
            $tipos.ContainsKey($_.Extension.ToLowerInvariant()) -and
            $_.LastWriteTime -lt $limite -and
            $_.Length -ge ($Configuracion.MinimoMB * 1MB)
        } |
        ForEach-Object {
            if (Test-Cancelacion $Sync) { return }
            if (-not (Test-RutaSegura $_.FullName $zonas)) { return }

            $tipo = $tipos[$_.Extension.ToLowerInvariant()]
            # Los comprimidos pueden contener cualquier cosa: más riesgo. Un
            # instalador o una imagen de disco sueltos son de los candidatos
            # más seguros del programa: se vuelven a descargar tal cual. La
            # escala se había quedado a medio escribir (ver [C-10]). Se
            # mantiene -Preseleccionado $false explicito más abajo aunque
            # "Bajo" premarcaria por defecto: este módulo no premarca nada.
            $esComprimido = $_.Extension -match '(?i)^\.(zip|rar|7z|tar|gz|bz2|xz|zst)$'

            # Una imagen de disco grande casi nunca es un instalador que se
            # vuelve a bajar: suele ser una maquina virtual, un respaldo o
            # una imagen que costo horas de descarga. Se propone igual,
            # pero avisando. Ver [FAL-12].
            $esImagenGrande = ($_.Extension -match '(?i)^\.(iso|img|vhd|vhdx|esd)$') -and $_.Length -ge 1GB

            $riesgo = if ($esComprimido -or $esImagenGrande) { 'Medio' } else { 'Bajo' }
            $aviso  = if ($esComprimido) {
                'Es un comprimido: comprueba que no guarda nada tuyo dentro.'
            } elseif ($esImagenGrande) {
                'Es una imagen de disco de más de 1 GB: puede ser una máquina virtual o un respaldo, no un instalador.'
            } else { '' }

            New-Candidato -ModuloId 'descargas' -Categoria 'Descargas antiguas' `
                          -Nombre $_.Name -Ruta $_.FullName -Bytes $_.Length `
                          -Info "$tipo - descargado $($_.LastWriteTime.ToString('yyyy-MM-dd')) ($(Format-Antiguedad $_.LastWriteTime))" `
                          -Efecto 'Se puede volver a descargar de su página original.' `
                          -Aviso $aviso -Metodo 'Ruta' -Raices $zonas `
                          -Riesgo $riesgo -Preseleccionado $false
        }
    }
}

New-ModuloLimpieza -Id 'descargas' -Orden 35 `
    -Nombre 'Instaladores y descargas antiguas' `
    -Descripcion 'Instaladores, imágenes de disco y comprimidos viejos en la carpeta Descargas. Nunca propone documentos ni fotos.' `
    -Riesgo 'Medio' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarDescargas
