<#
.SYNOPSIS
    Restos de programas que ya no están instalados.
.DESCRIPTION
    Recorre AppData -Local, Roaming y LocalLow- y ProgramData buscando
    carpetas que no correspondan a nada instalado, en ejecución, registrado
    como servicio ni presente en el menu Inicio. Es el módulo con más
    posibilidad de falso positivo, así que nada viene marcado por defecto y
    además se inspecciona el interior en busca de partidas guardadas,
    perfiles y documentos.

    DOS NIVELES, NO UNO. Los restos de programas -y sobre todo los de
    juegos- casi nunca estan en el primer nivel de AppData. Estan en
    "Roaming\<Editor>\<Producto>": el editor sigue instalado porque tiene
    otro producto, y el juego que se desinstalo dejo su carpeta dentro.
    Mirando solo el primer nivel, todo eso era invisible por definicion, y
    esa es la mitad de la razon por la que este modulo no encontraba nada.
    La otra mitad estaba en Test-TokenConocido. Ver [DET-21] y [DET-10].

    LOCALLOW. Es donde deja sus datos todo juego hecho con Unity, que son
    la mayoria de los juegos pequenos, y no lo recorria ningun modulo del
    programa. Ver [DET-20].
#>

$BuscarRestosProgramas = {
    param($Configuracion, $Sync)

    $vocabulario = Get-TokensProgramasInstalados -Sync $Sync

    # Carpetas del sistema que nunca corresponden a un programa instalado
    # pero tampoco son basura. De estas NO se desciende al segundo nivel:
    # lo que hay dentro de "Microsoft" o de "Packages" tiene sus propias
    # reglas y no es asunto de este modulo.
    $protegidas = @(
        'microsoft', 'windows', 'windowsapps', 'packages', 'packagecache', 'programs',
        'temp', 'tempstate', 'crashdumps', 'connecteddevicesplatform', 'comms',
        'publishers', 'virtualstore', 'iconcache', 'history', 'inetcache',
        'applicationdata', 'locallow', 'lowlevel', 'elevateddiagnostics',
        'nvidia', 'nvidiacorporation', 'intel', 'amd', 'realtek', 'oracle', 'java',
        'javasoft', 'dotnet', 'powershell', 'windowspowershell', 'ssh', 'nvm', 'npm',
        'nodejs', 'd3dscache', 'placeholdertiles', 'placeholdertilelogofolder',
        'usoshared', 'usoprivate', 'systemdata', 'wer', 'diagnosis', 'installer',
        'driverstore', 'drivers', 'searchcache', 'clipsvc', 'deviceassociationservice',
        'notifications', 'fonts', 'startmenu', 'menuinicio', 'desktop', 'escritorio',
        'plantillas', 'templates', 'recent', 'sendto', 'printhood', 'nethood',
        'cookies', 'libraries', 'bibliotecas', 'identities', 'identitycrl',
        'credentials', 'protect', 'crypto', 'vault', 'systemcertificates',
        'commonfiles', 'internetexplorer', 'modifiablewindowsapps'
    )

    # LocalLow no tiene variable de entorno propia: se deriva del perfil.
    $localLow = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'AppData\LocalLow' } else { $null }

    $zonas = @($env:LOCALAPPDATA, $env:APPDATA, $localLow, $env:ProgramData) |
             Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    # Nombres de subcarpeta que casi siempre contienen algo que el usuario
    # querria conservar.
    $patronValioso = '^(saves?|savegames?|worlds?|profiles?|perfiles|projects?|proyectos|backups?|documents?|screenshots?|capturas|exports?|mods?|characters?|partidas)$'
    $extensionesValiosas = '^\.(docx?|xlsx?|pptx?|pdf|jpe?g|png|psd|ai|mp4|mov|sav|save|world|blend|kdbx)$'

    # ------------------------------------------------------------------
    # Decide si una carpeta concreta es un resto y, si lo es, la propone.
    # Se usa igual para el primer nivel y para el segundo; lo unico que
    # cambia es el contexto que se le pasa.
    # ------------------------------------------------------------------
    $evaluarCarpeta = {
        param($Carpeta, $Nivel, $NombreEditor)

        if (Test-EsEnlace $Carpeta)                                { return }
        if ($protegidas -contains (ConvertTo-Token $Carpeta.Name))  { return }
        if (Test-NombreSensible $Carpeta.Name)                      { return }
        if (Test-RutaIntocable $Carpeta.FullName)                   { return }

        # La guardia ANTES de medir. Medir cuesta un recorrido completo de
        # disco y preguntar cuesta microsegundos; una ruta vetada se
        # descarta igual despues de haberla recorrido entera. Era el unico
        # modulo que lo hacia al reves. Ver [REN-21] y docs/RENDIMIENTO.md.
        if (-not (Test-RutaSegura $Carpeta.FullName $zonas))        { return }

        # En el segundo nivel se prueban DOS nombres: el de la carpeta
        # sola y el del editor pegado al de la carpeta. Un producto suele
        # aparecer en la lista de programas instalados con el editor
        # delante -"Adobe Acrobat", no "Acrobat"-, asi que sin esta
        # segunda prueba descender un nivel convertiria en falso positivo
        # justo lo que si esta instalado. Ver [DET-21].
        if (Test-TokenConocido -Nombre $Carpeta.Name -Vocabulario $vocabulario) { return }
        if ($Nivel -eq 2 -and
            (Test-TokenConocido -Nombre "$NombreEditor $($Carpeta.Name)" -Vocabulario $vocabulario)) { return }

        Set-Progreso $Sync "Midiendo: $($Carpeta.Name)"

        # UNA sola pasada de disco: tamano, fecha, subcarpetas valiosas y
        # documentos personales salen del mismo recorrido. Antes eran
        # tres, mas un Get-ChildItem por cada subcarpeta valiosa
        # encontrada. Ver [REN-20].
        $resumen = Get-ResumenArbol -Carpeta $Carpeta `
                                    -PatronCarpetaValiosa $patronValioso `
                                    -PatronExtensionValiosa $extensionesValiosas

        if ($resumen.Bytes -lt ($Configuracion.MinimoMB * 1MB)) { return }

        $ultimo = if ($null -ne $resumen.Ultimo) { $resumen.Ultimo } else { $Carpeta.LastWriteTime }
        $dias = [int]((Get-Date) - $ultimo).TotalDays
        if ($dias -lt $Configuracion.DiasSinUso) { return }

        $avisos = @()
        foreach ($nombre in ($resumen.CarpetasValiosas | Select-Object -Unique)) {
            $avisos += "contiene una carpeta '$nombre'"
        }
        if ($resumen.ArchivosValiosos -gt 0) {
            $avisos += "$($resumen.ArchivosValiosos) archivos que parecen personales"
        }

        # Escala de riesgo. La anterior estaba rota de dos maneras a la
        # vez: el 'else' final devolvia 'Alto', y como el filtro de arriba
        # ya garantiza que han pasado los dias configurados, la rama
        # 'Medio' solo se alcanzaba por encima del ano. Resultado: todo
        # salia 'Alto' y la escala no distinguia nada.
        #
        # Y estaba invertida respecto al resto del programa. Aqui mas
        # antiguo es MAS seguro, no menos: una carpeta que lleva dos anos
        # sin que nadie la toque es justo la que menos falta hace.
        # Ver [FAL-20].
        $riesgo = if ($avisos.Count -gt 0) { 'Alto' }
                  elseif ($Nivel -eq 2)    { 'Medio' }
                  elseif ($dias -gt 365)   { 'Bajo' }
                  else                     { 'Medio' }

        $efecto = if ($Nivel -eq 2) {
            "Está dentro de '$NombreEditor', que sí sigue instalado, pero no coincide con ningún producto suyo que esté en el equipo."
        } else {
            'No coincide con ningún programa instalado, proceso, servicio ni acceso directo del menú Inicio.'
        }

        New-Candidato -ModuloId 'restos' -Categoria 'Restos de programas' `
                      -Nombre $Carpeta.Name -Ruta $Carpeta.FullName -Bytes $resumen.Bytes `
                      -Info "$($resumen.Archivos) archivos - sin tocar desde $($ultimo.ToString('yyyy-MM-dd')) ($(Format-Antiguedad $ultimo))" `
                      -Efecto $efecto `
                      -Aviso ($avisos -join '; ') -Metodo 'Ruta' -Raices $zonas `
                      -Riesgo $riesgo -Preseleccionado $false
    }

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Revisando $(Get-RutaCorta $zona)..."

        foreach ($carpeta in @(Get-ChildItem -LiteralPath $zona -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Cancelacion $Sync) { break }

            # Una carpeta de primer nivel que corresponde a algo instalado
            # no es un resto, pero PUEDE CONTENER restos: es el caso de un
            # editor con varios productos del que solo queda uno. Se baja
            # un nivel y se evalua cada hija por separado.
            #
            # Solo un nivel mas, y solo si la carpeta esta reconocida. Bajar
            # sin limite convertiria cualquier subcarpeta de datos de una
            # aplicacion viva en candidata, que es exactamente el falso
            # positivo que este modulo no se puede permitir.
            $esProtegida = $protegidas -contains (ConvertTo-Token $carpeta.Name)
            $esConocida  = Test-TokenConocido -Nombre $carpeta.Name -Vocabulario $vocabulario

            if ($esConocida -and -not $esProtegida -and -not (Test-EsEnlace $carpeta)) {
                foreach ($hija in @(Get-ChildItem -LiteralPath $carpeta.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                    if (Test-Cancelacion $Sync) { break }
                    & $evaluarCarpeta $hija 2 $carpeta.Name
                }
                continue
            }

            & $evaluarCarpeta $carpeta 1 ''
        }
    }
}

New-ModuloLimpieza -Id 'restos' -Orden 30 `
    -Nombre 'Restos de programas desinstalados' `
    -Descripcion 'Carpetas de AppData, LocalLow y ProgramData que no corresponden a ningún programa instalado. Detección automática: revisa la lista antes de borrar.' `
    -Riesgo 'Alto' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarRestosProgramas
