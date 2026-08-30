<#
.SYNOPSIS
    Archivos duplicados detectados por hash.
.DESCRIPTION
    Estrategia en dos fases para no calcular hashes de todo el disco:
      1. Agrupar por tamaño exacto. Dos archivos distintos casi nunca miden
         lo mismo al byte.
      2. Solo dentro de esos grupos se calcula el hash SHA-256.

    Se conserva SIEMPRE la copia más antigua (la original) y se proponen las
    demás. Nada viene marcado por defecto.
#>

$BuscarDuplicados = {
    param($Configuracion, $Sync)

    $zonas = @($Configuracion.ZonasUsuario)
    if ($zonas.Count -eq 0) { return }

    $minimo = [double]$Configuracion.MinimoDuplicadoMB * 1MB
    Set-Progreso $Sync 'Recopilando archivos para comparar...'

    $porTamano = @{}
    # Defensa en profundidad frente a zonas solapadas (p. ej. si en algún
    # equipo OneDrive contiene Escritorio o Documentos pese al filtro de
    # Config.ps1): el mismo archivo no debe indexarse dos veces con el
    # mismo FullName, o el programa acaba "encontrando" una copia de si
    # mismo y proponiendo borrar el único ejemplar. Ver [C-02].
    $rutasVistas = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # Cuantos se han dejado fuera por estar solo en la nube. Se cuenta para
    # poder DECIRLO: saltarse archivos en silencio es la otra forma de
    # mentir sobre lo que se ha mirado. Ver [COR-03] y [CNF-04].
    #
    # Va en una TABLA y no en una variable suelta. Con "$n++" tambien
    # funcionaria hoy -Where-Object y ForEach-Object ejecutan su bloque en
    # el ambito de quien llama, no en uno hijo, al contrario que & { } o
    # una funcion-, pero eso es una sutileza del lenguaje que aqui no
    # conviene tener de cimiento: el dia que este bloque se mueva dentro
    # de una funcion auxiliar, el contador se quedaria en cero, el aviso
    # no saldria NUNCA y no habria ni un error que lo delatara. Mutar el
    # contenido de un objeto por referencia funciona en los dos casos.
    #
    # (Y sí: el comentario anterior afirmaba que Where-Object crea un
    # ambito hijo. Es falso. Se comprobo antes de dejarlo escrito.)
    $contador = @{ Nube = 0 }

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        Get-ElementosDelArbol -Ruta $zona |
        Where-Object {
            # El filtro de nube va ANTES que nada: comparar duplicados
            # significa leer el contenido -Get-HuellaRapida y Get-FileHash-,
            # y leer un marcador de OneDrive lo DESCARGA. Con una carpeta
            # sincronizada de varios GB, buscar duplicados se convertia en
            # una descarga silenciosa que en una conexion medida le cuesta
            # dinero al usuario.
            #
            # Ademas no tendria sentido proponerlo: un marcador ocupa unos
            # kilobytes en el disco, asi que borrarlo no libera el espacio
            # que dice su tamaño. Es el mismo error de contabilidad que los
            # enlaces duros de [VIS-03].
            if (Test-ArchivoEnNube -Archivo $_) {
                $contador.Nube++
                return $false
            }
            $_.Length -ge $minimo -and
            $_.FullName -notmatch '\\node_modules\\|\\\.git\\|\\AppData\\|\\\$Recycle' -and
            -not (Test-EsEnlace $_)
        } |
        ForEach-Object {
            if (-not $rutasVistas.Add($_.FullName)) { return }

            $clave = [string]$_.Length
            if (-not $porTamano.ContainsKey($clave)) {
                $porTamano[$clave] = [Collections.Generic.List[object]]::new()
            }
            $porTamano[$clave].Add($_)
        }
    }

    # Se dice ANTES de salir por "no hay duplicados": si no, un usuario con
    # todo en OneDrive leeria "ningun duplicado" cuando lo cierto es que no
    # se ha mirado casi nada. Ver [COR-03].
    if ($contador.Nube -gt 0) {
        Write-Registro -Sync $Sync -Nivel 'OMITIDO' -Mensaje (
            '{0} archivos no se han comparado porque están solo en la nube: leerlos los descargaría.' -f $contador.Nube)
        Set-Progreso $Sync ('{0} archivos de la nube no se comparan (descargarlos costaría datos).' -f $contador.Nube)
    }

    $gruposCandidatos = @($porTamano.Keys | Where-Object { $porTamano[$_].Count -gt 1 })
    if ($gruposCandidatos.Count -eq 0) { return }

    $procesados = 0
    foreach ($clave in $gruposCandidatos) {
        if (Test-Cancelacion $Sync) { break }
        $procesados++
        Set-Progreso $Sync "Comparando contenido: grupo $procesados de $($gruposCandidatos.Count)"

        # --- Prefiltro barato antes del hash completo ------------------
        # Mismo tamaño no basta, pero mismo tamaño Y mismos 128 KB de los
        # extremos descarta casi todo sin leer el resto. Solo los grupos
        # que sobreviven a esto pagan el SHA-256 entero. Ver [REN-52].
        $porHuella = @{}
        foreach ($archivo in $porTamano[$clave]) {
            if (Test-Cancelacion $Sync) { break }
            $huella = Get-HuellaRapida -Ruta $archivo.FullName
            if ([string]::IsNullOrEmpty($huella)) { continue }
            if (-not $porHuella.ContainsKey($huella)) {
                $porHuella[$huella] = [Collections.Generic.List[object]]::new()
            }
            $porHuella[$huella].Add($archivo)
        }

        $porHash = @{}
        foreach ($huella in $porHuella.Keys) {
            # Un archivo solo con su huella no tiene con quien ser
            # duplicado: nos ahorramos leerlo entero.
            if ($porHuella[$huella].Count -lt 2) { continue }

            foreach ($archivo in $porHuella[$huella]) {
                if (Test-Cancelacion $Sync) { break }
                $hash = $null
                try {
                    $hash = (Get-FileHash -LiteralPath $archivo.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                } catch {
                    continue
                }
                if (-not $porHash.ContainsKey($hash)) {
                    $porHash[$hash] = [Collections.Generic.List[object]]::new()
                }
                $porHash[$hash].Add($archivo)
            }
        }

        foreach ($hash in $porHash.Keys) {
            if ($porHash[$hash].Count -lt 2) { continue }

            # ENLACES DUROS: dos rutas, un solo archivo, unos solos bytes.
            #
            # Tienen el mismo tamaño y el mismo hash -claro: son el mismo
            # contenido-, asi que llegaban hasta aqui como si fueran dos
            # copias. Y proponer borrar uno es doblemente falso: no libera
            # NI UN BYTE, porque el contenido sigue vivo mientras quede
            # otro enlace, y ademas el programa lo apuntaba como espacio
            # recuperado. Otra vez decir que se hizo algo que no se hizo.
            #
            # Aqui el coste de averiguarlo si compensa, al reves que en el
            # recorrido general: solo se pregunta por archivos que YA han
            # empatado en tamaño y en hash, que son un punyado.
            # Ver [VIS-03] en docs/HOJA-DE-RUTA.md.
            $porContenido = @{}
            $unicos = [Collections.Generic.List[object]]::new()
            foreach ($archivo in $porHash[$hash]) {
                $identidad = Get-IdentidadArchivo -Ruta $archivo.FullName
                if ($null -eq $identidad) {
                    # Un solo enlace: es un archivo independiente.
                    $unicos.Add($archivo)
                    continue
                }
                if ($porContenido.ContainsKey($identidad)) { continue }
                $porContenido[$identidad] = $true
                $unicos.Add($archivo)
            }
            # Se usa la lista LOCAL a partir de aqui, sin reasignar
            # $porHash[$hash]: modificar el diccionario mientras se
            # recorren sus claves lanza "Collection was modified".
            if ($unicos.Count -lt 2) { continue }

            # Cual se CONSERVA. Antes se ordenaba por CreationTime y se
            # guardaba la mas antigua, dando por hecho que la copia tiene
            # fecha posterior. En Windows eso no es fiable: un archivo
            # restaurado de una copia de seguridad, descargado otra vez o
            # traido de otro equipo tambien estrena CreationTime. Con esa
            # regla se podia acabar conservando el ejemplar que esta en
            # Descargas y proponiendo borrar el de la biblioteca ordenada,
            # que es exactamente al reves de lo que quiere el usuario.
            #
            # Ahora manda el SITIO: una copia en Documentos, Imagenes,
            # Musica o Videos gana a una en Descargas o en un temporal.
            # A igualdad de sitio, la menos enterrada; y solo entonces, la
            # mas antigua. Ver [FAL-10] en docs/PLAN-ACCION.md.
            $puntuar = {
                param($Archivo)
                $ruta = $Archivo.FullName
                $puntos = 0
                foreach ($biblioteca in @($Configuracion.Documentos, $Configuracion.Imagenes,
                                          $Configuracion.Musica, $Configuracion.Videos)) {
                    if ([string]::IsNullOrWhiteSpace($biblioteca)) { continue }
                    if ($ruta.StartsWith($biblioteca.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar,
                                         [StringComparison]::OrdinalIgnoreCase)) {
                        $puntos += 100
                        break
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($Configuracion.Descargas) -and
                    $ruta.StartsWith($Configuracion.Descargas.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar,
                                     [StringComparison]::OrdinalIgnoreCase)) {
                    $puntos -= 100
                }
                if ($ruta -match '(?i)[\\/](temp|tmp|cache)[\\/]') { $puntos -= 50 }
                # Menos profundidad, mejor: lo ordenado suele estar arriba.
                $puntos -= ($ruta -split '[\\/]').Count
                return $puntos
            }

            $copias = @($unicos |
                        Sort-Object -Property @{ Expression = { & $puntuar $_ }; Descending = $true },
                                              @{ Expression = { $_.CreationTime }; Descending = $false })

            $original = $copias[0]
            foreach ($copia in $copias[1..($copias.Count - 1)]) {
                # Un archivo identico DENTRO de un arbol de aplicacion no
                # es una copia sobrante: es una dependencia. Dos programas
                # portables en Documentos pueden traer la misma DLL, la
                # misma fuente o la misma textura, y borrar una de las dos
                # rompe uno de los dos programas sin que nada lo avise.
                # Ver [FAL-11].
                $carpeta = Split-Path $copia.FullName -Parent
                $hermanosEjecutables = @(Get-ChildItem -LiteralPath $carpeta -File -Force -ErrorAction SilentlyContinue |
                                         Where-Object { $_.Extension -match '(?i)^\.(exe|dll|sys|so|dylib)$' } |
                                         Select-Object -First 1)
                if ($hermanosEjecutables.Count -gt 0) { continue }

                # Único sitio del programa que levanta el veto por extensión
                # personal: se ha comprobado por hash que hay otra copia
                # identica, así que borrar esta no pierde información.
                if (-not (Test-RutaSegura -Ruta $copia.FullName -Raices $zonas -PermitirPersonales)) { continue }

                New-Candidato -ModuloId 'duplicados' -Categoria 'Archivos duplicados' `
                              -Nombre $copia.Name -Ruta $copia.FullName -Bytes $copia.Length `
                              -Info "copia identica de $(Get-RutaElidida $original.FullName 55)" `
                              -Efecto "Se conserva el original, creado el $($original.CreationTime.ToString('yyyy-MM-dd'))." `
                              -Aviso 'Comprueba que la copia que se conserva es la que quieres.' `
                              -Metodo 'Ruta' -Raices $zonas -Riesgo 'Medio' `
                              -PermitirPersonales -Preseleccionado $false
            }
        }
    }
}

New-ModuloLimpieza -Id 'duplicados' -Orden 55 `
    -Nombre 'Archivos duplicados' `
    -Descripcion 'Compara por tamaño y después por hash SHA-256. Conserva siempre la copia más antigua.' `
    -Riesgo 'Medio' `
    -Perfiles @('agresivo') `
    -Buscar $BuscarDuplicados
