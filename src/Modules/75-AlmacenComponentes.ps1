<#
.SYNOPSIS
    Almacén de componentes de Windows (WinSxS).
.DESCRIPTION
    WinSxS NUNCA se toca a mano: borrar algo de ahi rompe Windows Update y
    puede impedir el arranque. La única forma correcta de reducirlo es que
    lo haga el propio Windows con DISM, así que este módulo se limita a
    preguntarle a DISM cuanto se podría recuperar y a ofrecer el comando
    oficial como acción explicita.
#>

$BuscarAlmacenComponentes = {
    param($Configuracion, $Sync)

    # Mismo resolutor que el resto del programa: System32 del propio
    # equipo, nunca el PATH.
    $dism = Resolve-EjecutableDeSistema -Nombre 'Dism.exe'
    if ($null -eq $dism) { return }

    Set-Progreso $Sync 'Preguntando a DISM por el almacén de componentes (puede tardar un minuto)...'

    $salida = ''
    try {
        $salida = & $dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
    } catch {
        return
    }
    if (Test-Cancelacion $Sync) { return }

    # La línea "Number of Reclaimable Packages" de DISM es un CONTEO, sin
    # unidad: la busqueda anterior por "reclaimable|recuperable" + número +
    # unidad no encontraba nunca nada y el candidato salia siempre con
    # "0 B recuperables" aunque DISM si recomendara limpiar. Las líneas que
    # SI llevan unidad son "Backups and Disabled Features" y "Cache and
    # Temporary Data"; su suma es la estimación real. Ver [C-05] en
    # docs/OPTIMIZACIONES.md.
    # Las etiquetas van en el IDIOMA DE WINDOWS, no en inglés. [C-04]
    # arreglo el número por cultura pero dejo los rotulos en inglés, así
    # que en un Windows en castellano -el público de este programa, la
    # interfaz esta en castellano- nunca casaba nada: el módulo caia
    # siempre en "No se ha podido leer la estimación de DISM" y tiraba a la
    # basura la consulta más cara de todo el análisis, que puede durar un
    # minuto. Se aceptan las dos variantes.
    #
    # "caracteristicas" y "cache" sin tilde a propósito: la salida de DISM
    # llega decodificada con la página de códigos de la consola, así que
    # las tildes pueden venir mal. Se busca por el trozo sin acentos.
    $recuperable = 0.0
    $seHaInterpretado = $false
    $lineas = $salida -split "`r?`n"
    foreach ($linea in $lineas) {
        if ($linea -match '(?i)(backups and disabled features|copias de seguridad y caracter|caché and temporary data|datos temporales y en cach).*?:\s*([\d.,]+)\s*(KB|MB|GB)') {
            $numero = ConvertFrom-NumeroLocal $Matches[2]
            $recuperable += ConvertTo-BytesConUnidad -Numero $numero -Unidad $Matches[3]
            $seHaInterpretado = $true
        }
    }

    # El castellano no dice "Recomendada: si", dice "Se recomienda la
    # limpieza del almacén de componentes". Son dos formas distintas y hay
    # que reconocer las dos.
    $recomendada = ($salida -match '(?i)(recommended|recomendada).*?:\s*(yes|si|s.)') -or
                   ($salida -match '(?i)se recomienda')
    $winsxs = Join-Path $env:SystemRoot 'WinSxS'
    $ocupado = Measure-Ruta $winsxs

    if (-not $seHaInterpretado -and -not $recomendada) {
        New-Candidato -ModuloId 'componentes' -Categoria 'Almacén de componentes' `
                      -Nombre 'No se ha podido leer la estimación de DISM' -Ruta $winsxs -Bytes 0 `
                      -Info "WinSxS ocupa $(Format-Tamano $ocupado); no se ha podido interpretar la salida de DISM" `
                      -Efecto 'Puede que DISM haya cambiado el formato de su salida en esta versión de Windows.' `
                      -Metodo 'Informativo' -Raices @() -Riesgo 'Bajo' -Preseleccionado $false
        return
    }

    if ($recuperable -lt 100MB -and -not $recomendada) {
        New-Candidato -ModuloId 'componentes' -Categoria 'Almacén de componentes' `
                      -Nombre 'WinSxS está en buen estado' -Ruta $winsxs -Bytes 0 `
                      -Info "ocupa $(Format-Tamano $ocupado), DISM no recomienda limpiarlo ahora" `
                      -Efecto 'No hay nada que hacer. Windows limpia este almacén solo con una tarea programada.' `
                      -Metodo 'Informativo' -Raices @() -Riesgo 'Bajo' -Preseleccionado $false
        return
    }

    $infoRecuperable = if ($seHaInterpretado) {
        "WinSxS ocupa $(Format-Tamano $ocupado); DISM estima $(Format-Tamano $recuperable) recuperables"
    } else {
        "WinSxS ocupa $(Format-Tamano $ocupado); DISM recomienda limpiarlo pero no se ha podido interpretar cuanto recuperaria"
    }

    New-Candidato -ModuloId 'componentes' -Categoria 'Almacén de componentes' `
                  -Nombre 'Compactar el almacén de componentes con DISM' -Ruta $winsxs -Bytes $recuperable `
                  -Info $infoRecuperable `
                  -Efecto 'Ejecuta el comando oficial de Windows (DISM /StartComponentCleanup). Puede tardar entre 10 y 40 minutos y no se debe interrumpir.' `
                  -Aviso 'Después de esto no se podrán desinstalar las actualizaciones ya instaladas.' `
                  -Metodo 'Comando' `
                  -Ejecutable 'dism' -Argumentos @('/Online', '/Cleanup-Image', '/StartComponentCleanup') `
                  -Comando ('"{0}" /Online /Cleanup-Image /StartComponentCleanup' -f $dism) `
                  -Raices @() -Riesgo 'Medio' -Preseleccionado $false
}

New-ModuloLimpieza -Id 'componentes' -Orden 75 `
    -Nombre 'Almacén de componentes (WinSxS)' `
    -Descripcion 'Consulta a DISM cuánto se puede compactar y ejecuta el comando oficial. Nunca borra archivos de WinSxS a mano.' `
    -Riesgo 'Medio' -RequiereAdmin `
    -Perfiles @('agresivo') `
    -Buscar $BuscarAlmacenComponentes
