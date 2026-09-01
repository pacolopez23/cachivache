<#
.SYNOPSIS
    Archivos temporales sueltos repartidos por las carpetas del usuario.
.DESCRIPTION
    .tmp, .bak, .old, autoguardados de Office, descargas a medias y bases de
    datos de miniaturas. Se excluye .log a propósito: hay programas que
    guardan información útil ahi.
#>

$BuscarTemporales = {
    param($Configuracion, $Sync)

    $zonas = @($Configuracion.ZonasUsuario)
    if ($zonas.Count -eq 0) { return }

    $nombresMetadatos = @('Thumbs.db', 'ehthumbs.db', '.DS_Store', 'desktop.ini.bak')

    # Un archivo de bloqueo de Office, una descarga a medias o un .tmp/.temp
    # muy reciente puede seguir en uso AHORA MISMO: el módulo no comprobaba
    # nada de esto y los premarcaba igual. Ver [C-15] en
    # docs/OPTIMIZACIONES.md.
    $limiteReciente = (Get-Date).AddMinutes(-30)
    $officeAbierto  = @(Test-ProcesoAbierto @('winword', 'excel', 'powerpnt')).Count -gt 0

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Revisando $(Get-RutaCorta $zona)..."

        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        # Este es el modulo donde mas se nota, porque es el que recorre las
        # carpetas del usuario enteras: un .tmp o un .dmp al fondo de un
        # node_modules anidado no se proponia nunca.
        # -MedirEnDisco: [VIS-05]. Solo pregunta el tamano en disco de lo
        # que lleva el bit de comprimido, asi que en el caso normal no
        # cuesta ni una llamada al sistema. Sin esto, en una carpeta
        # comprimida el modulo promete liberar el tamano LOGICO y libera
        # bastante menos.
        Get-ElementosDelArbol -Ruta $zona -MedirEnDisco |
        Where-Object {
            $_.FullName -notmatch '\\node_modules\\|\\\.git\\' -and
            (
                $_.Extension -match '^\.(tmp|bak|old|dmp|chk|gid|crdownload|partial|download|temp)$' -or
                $_.Name -like '~$*' -or
                # Solo la extensión, no cualquier nombre con ".~" en
                # cualquier posición (antes: '*.~*', que casaba de más).
                $_.Extension -like '.~*' -or
                $nombresMetadatos -contains $_.Name
            )
        } |
        ForEach-Object {
            if (Test-Cancelacion $Sync) { return }

            $esBloqueoOffice   = $_.Name -like '~$*'
            $esDescargaAMedias = $_.Extension -match '^\.(crdownload|partial|download)$'
            $esTmpGenerico     = $_.Extension -match '^\.(tmp|temp)$'

            # Office esta abierto: no hay forma barata de saber a que
            # documento pertenece cada ~$*, así que no se proponen mientras
            # cualquier Office este en marcha.
            if ($esBloqueoOffice -and $officeAbierto) { return }
            # Reciente: puede seguir escribiendose ahora mismo.
            if (($esBloqueoOffice -or $esDescargaAMedias -or $esTmpGenerico) -and
                $_.LastWriteTime -gt $limiteReciente) { return }

            if (-not (Test-RutaSegura $_.FullName $zonas)) { return }

            $categoria = 'Temporales sueltos'
            $efecto    = 'Archivo temporal. Ningún programa lo necesita.'
            if ($nombresMetadatos -contains $_.Name) {
                $categoria = 'Miniaturas y metadatos'
                $efecto    = 'Caché de miniaturas del Explorador. Se regenera al abrir la carpeta.'
            } elseif ($_.Name -like '~$*') {
                $categoria = 'Autoguardados de Office'
                $efecto    = 'Archivo de bloqueo de Word o Excel. Sobra si el documento no está abierto.'
            } elseif ($_.Extension -match '^\.(crdownload|partial|download)$') {
                $categoria = 'Descargas a medias'
                $efecto    = 'Descarga interrumpida. No sirve para nada: hay que volver a bajarla.'
            } elseif ($_.Extension -match '^\.(bak|old)$') {
                $categoria = 'Copias .bak y .old'
                $efecto    = 'Copia antigua que dejó algún programa al guardar.'
            }

            # Un .bak reciente puede ser la única copia de algo.
            $reciente = ((Get-Date) - $_.LastWriteTime).TotalDays -lt 7
            $riesgo = if ($_.Extension -match '^\.(bak|old)$') { 'Medio' } else { 'Bajo' }
            $aviso  = if ($reciente -and $riesgo -eq 'Medio') { 'Creado hace menos de una semana.' } else { '' }

            New-Candidato -ModuloId 'temporales' -Categoria $categoria `
                          -Nombre $_.Name -Ruta $_.FullName -Bytes $_.Length `
                          -TamanoEnDisco $_.TamanoEnDisco `
                          -Info "$(Get-RutaElidida $_.DirectoryName 55) - $($_.LastWriteTime.ToString('yyyy-MM-dd'))" `
                          -Efecto $efecto -Aviso $aviso -Metodo 'Ruta' -Raices $zonas -Riesgo $riesgo
        }
    }
}

New-ModuloLimpieza -Id 'temporales' -Orden 50 `
    -Nombre 'Temporales sueltos y miniaturas' `
    -Descripcion 'Archivos .tmp, .bak, .old, autoguardados de Office, descargas a medias y Thumbs.db repartidos por tus carpetas.' `
    -Riesgo 'Bajo' `
    -Perfiles @('conservador', 'equilibrado', 'agresivo') `
    -Buscar $BuscarTemporales
