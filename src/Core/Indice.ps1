<#
.SYNOPSIS
    Índice de disco: una sola pasada que responde "dónde se fue el espacio".

.DESCRIPTION
    Es la pieza que le faltaba al programa para dejar de ser solo un
    limpiador. Cachivache sabía encontrar basura; no sabía enseñar el
    disco. WizTree y WinDirStat hacen justo lo contrario, y por eso mucha
    gente tiene los dos instalados.

    De UN recorrido salen las dos cosas:

      * El total de cada carpeta, que es lo que dibuja el mapa de árbol.
      * Los archivos más grandes, que es la vista de archivos.

    -------------------------------------------------------------------
    POR QUE SE GUARDAN LAS CARPETAS ENTERAS Y LOS ARCHIVOS NO

    Un disco con uso tiene cientos de miles de archivos y unas decenas de
    miles de carpetas. Guardar un registro por archivo son decenas de MB
    de memoria y no hace falta para nada de lo que se quiere enseñar:

      * El mapa de árbol dibuja CARPETAS. Un rectángulo por archivo sería
        ilegible mucho antes de ser útil.
      * La vista de archivos ordena por tamaño, y a nadie le interesa el
        archivo número 40.000.

    Así que las carpetas se agregan todas -son pocas y cuestan una entrada
    cada una- y de los archivos se guardan solo los que superan un umbral.
    El umbral es un parámetro, no una constante escondida: quien quiera
    verlo todo puede pedirlo y pagar la memoria.

    -------------------------------------------------------------------
    LO QUE ESTO NO ES

    No es la tabla maestra de NTFS. WizTree lee la tabla directamente y
    por eso recorre un disco de 250 GB en un segundo, cuarenta veces más
    rápido que enumerar carpetas. Esto es el recorrido normal, hecho una
    sola vez y bien.

    El día que se implemente [VEL-01], la lectura de la tabla maestra
    entra como PROVEEDOR ALTERNATIVO de esta misma función: mismo
    resultado, mismo contrato, otra forma de rellenarlo. Por eso el
    resultado no expone nada de cómo se obtuvo. Ver docs/HOJA-DE-RUTA.md.
#>

function New-EntradaCarpeta {
    <#
    .SYNOPSIS
        Fila del índice para una carpeta.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Ruta, [int] $Nivel = 0)

    return [pscustomobject]@{
        Ruta     = $Ruta
        Nombre   = Split-Path $Ruta -Leaf
        Nivel    = $Nivel
        # Bytes de los archivos que cuelgan de aquí, a cualquier
        # profundidad. Es lo que dibuja el mapa.
        Bytes    = 0.0
        # Bytes de los archivos que están DIRECTAMENTE aquí, sin contar
        # subcarpetas. Sirve para explicar "esta carpeta pesa 8 GB, pero
        # 7,9 son de una subcarpeta".
        Propios  = 0.0
        Archivos = 0
        Ultimo   = [datetime]'1900-01-01'
    }
}

function New-IndiceDisco {
    <#
    .SYNOPSIS
        Recorre una o varias rutas y devuelve el índice de espacio.

    .PARAMETER Rutas
        Carpetas raíz por las que empezar.
    .PARAMETER MinimoArchivoBytes
        Tamaño a partir del cual un archivo se guarda en la lista. Los
        más pequeños suman en su carpeta pero no se guardan uno a uno.
    .PARAMETER MaximoArchivos
        Tope de archivos guardados. Al alcanzarlo se sube el umbral solo,
        de modo que la memoria no crece sin control en un disco enorme y
        aun así se conservan siempre los mayores.
    .PARAMETER ContarEnlacesDuros
        Cuenta una sola vez el contenido compartido. Caro: ver
        Get-IdentidadArchivo.

    .NOTES
        El recorrido es con pila propia y no con AllDirectories, por el
        mismo motivo que Get-ResumenArbol: hay que poder SALTAR los puntos
        de reanálisis. Seguirlos significaría contar dos veces el destino
        de una unión, o dar vueltas en un ciclo.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo lee el disco y compone un objeto en memoria.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Rutas,
        [double] $MinimoArchivoBytes = 1MB,
        [int]    $MaximoArchivos     = 20000,
        [switch] $ContarEnlacesDuros,
        $Sync = $null
    )

    $carpetas = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $archivos = [Collections.Generic.List[object]]::new()

    $vistos = $null
    if ($ContarEnlacesDuros) {
        $vistos = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }

    $totalBytes   = 0.0
    $totalArchivos = 0
    $compartidos  = 0
    $inaccesibles = 0
    $umbral       = [double]$MinimoArchivoBytes

    foreach ($raiz in @($Rutas)) {
        if ([string]::IsNullOrWhiteSpace($raiz)) { continue }
        if (Test-Cancelacion $Sync) { break }

        $item = Get-Item -LiteralPath $raiz -Force -ErrorAction SilentlyContinue
        if ($null -eq $item -or -not $item.PSIsContainer) { continue }
        if (Test-EsEnlace $item) { continue }

        Set-Progreso $Sync "Indexando $(Get-RutaCorta $raiz)..."

        $nivelRaiz = ($item.FullName.TrimEnd([char]'\', [char]'/') -split '[\\/]').Count
        $pendientes = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
        $pendientes.Push($item)

        while ($pendientes.Count -gt 0) {
            if (Test-Cancelacion $Sync) { break }
            $actual = $pendientes.Pop()

            $nivel = ($actual.FullName.TrimEnd([char]'\', [char]'/') -split '[\\/]').Count - $nivelRaiz
            if (-not $carpetas.ContainsKey($actual.FullName)) {
                $carpetas[$actual.FullName] = New-EntradaCarpeta -Ruta $actual.FullName -Nivel $nivel
            }
            $entrada = $carpetas[$actual.FullName]

            # --- Archivos de ESTA carpeta -----------------------------
            try {
                foreach ($archivo in $actual.EnumerateFiles()) {
                    $totalArchivos++
                    $entrada.Archivos++

                    if ($archivo.LastWriteTime -gt $entrada.Ultimo) {
                        $entrada.Ultimo = $archivo.LastWriteTime
                    }

                    $sumar = $true
                    if ($null -ne $vistos) {
                        $identidad = Get-IdentidadArchivo -Ruta $archivo.FullName
                        if ($null -ne $identidad -and -not $vistos.Add($identidad)) {
                            $sumar = $false
                            $compartidos++
                        }
                    }
                    if (-not $sumar) { continue }

                    $tamaño = [double]$archivo.Length
                    $entrada.Propios += $tamaño
                    $totalBytes      += $tamaño

                    if ($tamaño -ge $umbral) {
                        $archivos.Add([pscustomobject]@{
                            Ruta      = $archivo.FullName
                            Nombre    = $archivo.Name
                            Carpeta   = $actual.FullName
                            Extension = $archivo.Extension.ToLowerInvariant()
                            Bytes     = $tamaño
                            Ultimo    = $archivo.LastWriteTime
                        })

                        # Al llegar al tope se conservan los mayores y se
                        # sube el umbral al mas pequeño que ha quedado.
                        # Asi la memoria no crece sin control y la lista
                        # sigue siendo la de los archivos que importan.
                        if ($archivos.Count -ge $MaximoArchivos) {
                            $ordenados = @($archivos | Sort-Object Bytes -Descending |
                                           Select-Object -First ([int]($MaximoArchivos / 2)))
                            $archivos.Clear()
                            foreach ($a in $ordenados) { $archivos.Add($a) }
                            if ($ordenados.Count -gt 0) {
                                $umbral = [double]$ordenados[-1].Bytes
                            }
                        }
                    }
                }
            } catch {
                $inaccesibles++
            }

            # --- Subcarpetas ------------------------------------------
            try {
                foreach ($sub in $actual.EnumerateDirectories()) {
                    if ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    $pendientes.Push($sub)
                }
            } catch {
                $inaccesibles++
            }
        }
    }

    # --- Propagar los totales hacia arriba ---------------------------
    # De más profunda a menos profunda: cuando se suma una carpeta a su
    # padre, esa carpeta ya tiene dentro todo lo suyo. Una sola pasada
    # sobre las carpetas, sin volver a tocar el disco.
    Set-Progreso $Sync 'Sumando carpetas...'
    foreach ($entrada in @($carpetas.Values)) { $entrada.Bytes = $entrada.Propios }

    foreach ($entrada in @($carpetas.Values | Sort-Object Nivel -Descending)) {
        if ($entrada.Nivel -le 0) { continue }
        $padre = Split-Path $entrada.Ruta -Parent
        if ([string]::IsNullOrWhiteSpace($padre)) { continue }
        if ($carpetas.ContainsKey($padre)) {
            $carpetas[$padre].Bytes    += $entrada.Bytes
            $carpetas[$padre].Archivos += $entrada.Archivos
            if ($entrada.Ultimo -gt $carpetas[$padre].Ultimo) {
                $carpetas[$padre].Ultimo = $entrada.Ultimo
            }
        }
    }

    return [pscustomobject]@{
        Carpetas     = $carpetas
        Archivos     = @($archivos | Sort-Object Bytes -Descending)
        Raices       = @($Rutas)
        Bytes        = $totalBytes
        TotalArchivos = $totalArchivos
        Compartidos  = $compartidos
        Inaccesibles = $inaccesibles
        # Umbral REAL con el que ha acabado la lista de archivos, que
        # puede ser mayor que el pedido si se alcanzo el tope. Quien lo
        # muestre tiene que poder decir "solo los mayores de X".
        UmbralArchivo = $umbral
    }
}

function Get-HijasDirectas {
    <#
    .SYNOPSIS
        Subcarpetas inmediatas de una ruta dentro del índice, ordenadas de
        mayor a menor.
    .DESCRIPTION
        Lo que necesita el mapa de árbol para dibujar un nivel: los hijos
        directos, no todo el subárbol.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Indice,
        [Parameter(Mandatory)] [string] $Ruta
    )

    $prefijo = $Ruta.TrimEnd([char]'\', [char]'/')
    $separador = [IO.Path]::DirectorySeparatorChar
    $resultado = [Collections.Generic.List[object]]::new()

    foreach ($entrada in $Indice.Carpetas.Values) {
        $padre = Split-Path $entrada.Ruta -Parent
        if ([string]::IsNullOrWhiteSpace($padre)) { continue }
        if ($padre.TrimEnd([char]'\', [char]'/').Equals($prefijo, [StringComparison]::OrdinalIgnoreCase)) {
            $resultado.Add($entrada)
        }
    }

    # Los archivos sueltos de la propia carpeta se representan como un
    # bloque más, para que el mapa sume el 100% y no quede un hueco sin
    # explicar. Sin esto, una carpeta con 5 GB de archivos propios y una
    # subcarpeta de 1 GB parecería que ocupa 1 GB.
    if ($Indice.Carpetas.ContainsKey($prefijo)) {
        $propia = $Indice.Carpetas[$prefijo]
        if ($propia.Propios -gt 0) {
            $resultado.Add([pscustomobject]@{
                Ruta     = $prefijo + $separador
                Nombre   = '(archivos de esta carpeta)'
                Nivel    = $propia.Nivel + 1
                Bytes    = $propia.Propios
                Propios  = $propia.Propios
                Archivos = 0
                Ultimo   = $propia.Ultimo
            })
        }
    }

    return @($resultado | Sort-Object Bytes -Descending)
}
