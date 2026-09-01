<#
.SYNOPSIS
    Accesos directos .lnk cuyo destino ya no existe.
.DESCRIPTION
    Se descartan los accesos de la Store (shell:, ms-...) y los que apuntan
    a direcciones web, que no tienen ruta en disco y darian falso positivo.
    El destino se vuelve a comprobar justo antes de borrar.
#>

$BuscarAccesosRotos = {
    param($Configuracion, $Sync)

    # @($Configuracion.ZonasUsuario) es deliberado y no redundante: si
    # ZonasUsuario llegara como un string suelto en vez de un array de un
    # elemento (ver [C-07] en docs/OPTIMIZACIONES.md), "$string + @(...)"
    # concatena texto en vez de arrays y el módulo devuelve cero resultados
    # en silencio.
    $zonas = @(
        @($Configuracion.ZonasUsuario) +
        @(
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu')
        )
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    if ($zonas.Count -eq 0) { return }

    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return }

    # Tipo de cada unidad, para distinguir un disco fijo de uno extraible o
    # de red sin consultar WMI por cada acceso directo. DriveType 3 = disco
    # fijo. Ver [C-14] en docs/OPTIMIZACIONES.md.
    $tiposUnidad = @{}
    try {
        foreach ($disco in Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop) {
            if ($disco.DeviceID) { $tiposUnidad[$disco.DeviceID.ToUpperInvariant()] = [int]$disco.DriveType }
        }
    } catch {
        Write-Verbose "No se han podido listar las unidades: $($_.Exception.Message)"
    }

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Comprobando destinos en $(Get-RutaCorta $zona)..."

        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        # El filtro sigue siendo el de Windows, no un Where-Object: en un
        # menu Inicio con cientos de carpetas la diferencia se nota.
        #
        # SIN -MedirEnDisco, Y ES UNA DECISION, NO UN OLVIDO. [VIS-05]
        # existe para dejar de prometer espacio que no se va a liberar, y
        # aqui no hay espacio que prometer: un .lnk son uno o dos
        # kilobytes, por debajo del cluster con el que NTFS empieza a
        # comprimir. La diferencia entre lo que ocupa y lo que mide seria
        # de bytes, invisible en pantalla, y a cambio se pagaria una
        # llamada al sistema por cada acceso directo del menu Inicio, que
        # son cientos. Este modulo borra accesos rotos, no libera disco.
        Get-ElementosDelArbol -Ruta $zona -Filtro '*.lnk' |
        ForEach-Object {
            if (Test-Cancelacion $Sync) { return }

            $destino = Get-DestinoAccesoDirecto -Ruta $_.FullName -Shell $shell
            if ([string]::IsNullOrWhiteSpace($destino)) { return }
            # Aplicaciones de la Store y enlaces web: no tienen ruta real.
            if ($destino -match '^(shell:|ms-|http|mailto:)') { return }
            # Una ruta de red (\\servidor\recurso) da el mismo Test-Path
            # $false tanto si el acceso directo esta roto de verdad como si
            # el NAS esta simplemente apagado ahora mismo. No hay forma
            # fiable de distinguirlos sin intentar conectar, así que no se
            # juzgan: es el falso positivo más probable de todo el
            # programa, y encima salia premarcado.
            if ($destino -match '^\\\\') { return }
            if (Test-Path -LiteralPath $destino -ErrorAction SilentlyContinue) { return }
            if (-not (Test-RutaSegura $_.FullName $zonas)) { return }

            # Unidad extraible (USB, tarjeta SD...) sin conectar ahora
            # mismo: mismo problema que la red. Se propone igualmente,
            # porque a veces si esta roto de verdad, pero con aviso
            # explicito y SIN premarcar.
            $aviso = ''
            $preseleccionado = $true
            $raiz = [IO.Path]::GetPathRoot($destino)
            if ($raiz) {
                $letra = $raiz.TrimEnd('\')
                if ($tiposUnidad.ContainsKey($letra) -and $tiposUnidad[$letra] -ne 3) {
                    $aviso = 'El destino está en una unidad extraíble: puede que solo esté desconectada ahora mismo, no rota.'
                    $preseleccionado = $false
                }
            }

            # Test-Path responde $false por DOS motivos distintos que no se
            # parecen en nada: "no existe" y "no tengo permiso para
            # mirar". El segundo es el caso normal en dos sitios:
            #
            #   * Program Files\WindowsApps, con la lista de control de
            #     acceso restringida, donde vive TODA aplicacion de la
            #     Store instalada como escritorio. Sus accesos directos
            #     estan perfectamente sanos y aqui salian premarcados para
            #     borrar.
            #   * El perfil de OTRO usuario del equipo, que este no puede
            #     leer aunque el destino este ahi.
            #
            # No se puede afirmar que esten rotos, asi que se proponen -a
            # veces si lo estan- pero con aviso y sin premarcar. Ver
            # [FAL-01] en docs/PLAN-ACCION.md.
            $destinoNormalizado = $destino.Replace('/', '\')
            $perfilPropio = if ($env:USERPROFILE) { $env:USERPROFILE.TrimEnd('\') } else { '' }
            $carpetaUsuarios = if ($env:SystemDrive) { $env:SystemDrive + '\Users\' } else { '' }

            $sinPermiso = $false
            if ($destinoNormalizado -match '(?i)\\WindowsApps\\') { $sinPermiso = $true }
            if ($carpetaUsuarios -and
                $destinoNormalizado.StartsWith($carpetaUsuarios, [StringComparison]::OrdinalIgnoreCase) -and
                -not ($perfilPropio -and $destinoNormalizado.StartsWith($perfilPropio + '\', [StringComparison]::OrdinalIgnoreCase))) {
                $sinPermiso = $true
            }

            if ($sinPermiso) {
                $aviso = 'No se puede comprobar el destino: está en una carpeta que este usuario no tiene permiso para leer, así que puede existir y estar bien.'
                $preseleccionado = $false
            }

            New-Candidato -ModuloId 'accesos' -Categoria 'Accesos directos rotos' `
                          -Nombre $_.Name -Ruta $_.FullName -Bytes $_.Length `
                          -Info "apunta a: $(Get-RutaElidida $destino 60)" `
                          -Efecto 'El destino ya no existe: este acceso directo no abre nada.' `
                          -Aviso $aviso -Metodo 'Ruta' -Raices $zonas -Riesgo 'Bajo' -Preseleccionado $preseleccionado
        }
    }

    if ($shell) {
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
        catch { Write-Verbose "No se ha podido liberar el objeto COM: $($_.Exception.Message)" }
    }
}

New-ModuloLimpieza -Id 'accesos' -Orden 45 `
    -Nombre 'Accesos directos rotos' `
    -Descripcion 'Archivos .lnk cuyo destino ya no existe: no abren nada.' `
    -Riesgo 'Bajo' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarAccesosRotos
