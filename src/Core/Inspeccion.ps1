<#
.SYNOPSIS
    Qué hay dentro de una carpeta, para poder decidir sin borrarla antes.

.DESCRIPTION
    Ante "Caché de Electron - 1,2 GB" el usuario no tiene forma de saber
    qué contiene, y la decisión que se le pide es irreversible. Esto
    responde a las tres preguntas que de verdad se hacen: cuántos archivos
    son, de cuándo es lo más reciente, y qué es lo que ocupa.

    Ver [USO-05] en docs/HOJA-DE-RUTA.md.

    -------------------------------------------------------------------
    LO QUE ESTA FUNCION NO HACE, Y POR QUE

    NO ABRE NINGUN ARCHIVO. Solo enumera. Nombre, tamaño y fecha salen de
    la entrada de directorio, sin tocar el contenido. Eso importa por dos
    motivos: abrir un marcador de OneDrive lo DESCARGARIA -y mirar qué
    hay dentro no puede costarle datos a nadie, ver [COR-03]- y porque
    abrir miles de archivos para "ver qué hay" seria absurdamente lento.

    NO SIGUE ENLACES. Un punto de reanalisis apunta fuera del arbol: si
    se siguiera, "qué hay dentro de esta carpeta" acabaria enumerando
    medio disco, o dando vueltas en un ciclo.

    NO DEVUELVE RUTAS CON EL PREFIJO DE RUTA LARGA. El recorrido lo usa
    -si no, se atascaria a los 260 caracteres, ver [COR-02]- pero lo
    quita antes de devolver nada. Ese prefijo no puede escaparse a lo que
    ve el usuario ni a lo que compara la guardia.

    -------------------------------------------------------------------
    CUANDO NO PUEDE MIRARLO TODO

    Hay un tope de archivos. Sin el, pedir el detalle de una carpeta
    enorme por error congelaria la ventana, que es justo lo que [USO-07]
    acaba de arreglar en el analisis.

    Pero un tope crea un problema nuevo: los "diez mayores" de un
    recorrido a medias pueden no ser los diez mayores de verdad. Por eso
    se devuelve Truncado, y quien lo ensenye TIENE que decirlo. Un
    "los mayores son estos" calculado sobre la mitad del arbol es
    exactamente la clase de dato que parece cierto y no lo es.
#>

# Tope de archivos que se recorren antes de rendirse. Alto a proposito:
# una cache de desarrollo con cien mil archivos entra de sobra, y solo
# salta en carpetas que ya no son "una carpeta" sino medio disco.
$script:MaximoArchivosDetalle = 300000

function New-DetalleCarpeta {
    <#
    .SYNOPSIS
        El objeto vacio, para que todos los caminos devuelvan la misma
        forma y quien lo lea no tenga que comprobar si existe cada campo.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria.')]
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Archivos     = 0
        Carpetas     = 0
        Bytes        = 0.0
        Ultimo       = $null
        Mayores      = @()
        EnNube       = 0
        Inaccesibles = 0
        Truncado     = $false
    }
}

function Get-DetalleCarpeta {
    <#
    .SYNOPSIS
        Recorre una carpeta y devuelve de qué está hecha.

    .PARAMETER Cuantos
        Cuántos de los mayores se devuelven.

    .OUTPUTS
        Archivos, Carpetas, Bytes, Ultimo, Mayores, EnNube, Inaccesibles,
        Truncado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        [int] $Cuantos = 10
    )

    $detalle = New-DetalleCarpeta
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $detalle }

    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $detalle }

    # Un archivo suelto es su propio detalle: un archivo, su tamaño y él
    # mismo como el mayor. Responder "cero archivos" seria technicamente
    # cierto y practicamente falso.
    if (-not $item.PSIsContainer) {
        $detalle.Archivos = 1
        $detalle.Bytes    = [double]$item.Length
        $detalle.Ultimo   = $item.LastWriteTime
        $detalle.Mayores  = @([pscustomobject]@{
            Nombre = $item.Name
            Ruta   = ConvertFrom-RutaLarga -Ruta $item.FullName
            Bytes  = [double]$item.Length
            EnNube = (Test-ArchivoEnNube -Archivo $item)
        })
        return $detalle
    }

    if (Test-EsEnlace $item) { return $detalle }

    # Se guardan TODOS los archivos y se ordena al final, en vez de
    # mantener una lista de diez ordenada en cada paso. Con cien mil
    # archivos, un Sort-Object al final es una sola pasada; insertar
    # ordenando es cien mil inserciones.
    $todos = [Collections.Generic.List[object]]::new()
    $ticksUltimo = 0L
    $bytes = 0.0

    $pendientes = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pendientes.Push((Get-CarpetaParaRecorrer -Carpeta $item))

    while ($pendientes.Count -gt 0) {
        $actual = $pendientes.Pop()

        # Dos try independientes, uno por bucle: con uno solo, un "acceso
        # denegado" al enumerar los archivos se llevaria por delante el
        # recorrido de las subcarpetas y se perderia la rama entera. Es la
        # leccion de [SEG-40], y aqui se repite por el mismo motivo.
        try {
            foreach ($archivo in $actual.EnumerateFiles()) {
                if ($todos.Count -ge $script:MaximoArchivosDetalle) {
                    $detalle.Truncado = $true
                    break
                }
                $ticks = $archivo.LastWriteTime.Ticks
                if ($ticks -gt $ticksUltimo) { $ticksUltimo = $ticks }

                $enNube = Test-ArchivoEnNube -Archivo $archivo
                # Un marcador de nube ocupa unos kilobytes en el disco, no
                # su tamaño logico. Se cuenta y se marca, pero no se suma:
                # decir que una carpeta ocupa 4 GB cuando en el disco hay
                # 40 KB es la contabilidad falsa de [VIS-03] y [COR-03].
                if (-not $enNube) { $bytes += [double]$archivo.Length }

                $todos.Add([pscustomobject]@{
                    Nombre = $archivo.Name
                    Ruta   = ConvertFrom-RutaLarga -Ruta $archivo.FullName
                    Bytes  = [double]$archivo.Length
                    EnNube = $enNube
                })
            }
        } catch {
            $detalle.Inaccesibles++
        }

        if ($detalle.Truncado) { break }

        try {
            foreach ($sub in $actual.EnumerateDirectories()) {
                if ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $detalle.Carpetas++
                $pendientes.Push($sub)
            }
        } catch {
            $detalle.Inaccesibles++
        }
    }

    $detalle.Archivos = $todos.Count
    $detalle.Bytes    = $bytes
    $detalle.EnNube   = @($todos | Where-Object { $_.EnNube }).Count
    $detalle.Ultimo   = if ($ticksUltimo -gt 0) { [datetime]::new($ticksUltimo) } else { $null }
    $detalle.Mayores  = @($todos | Sort-Object Bytes -Descending | Select-Object -First $Cuantos)

    return $detalle
}

function Format-DetalleCarpeta {
    <#
    .SYNOPSIS
        El detalle en texto, listo para ensenyar.

    .DESCRIPTION
        Aparte de quien lo dibuja, por el motivo de siempre en este
        proyecto: una ventana de WPF no arranca en las pruebas y una
        cadena si. Aqui es donde se decide QUE se le cuenta al usuario
        antes de que decida borrar, y eso tiene que poder comprobarse.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Detalle,
        [string] $Ruta = ''
    )

    if ($null -eq $Detalle) { return 'No se ha podido mirar dentro.' }

    $lineas = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Ruta)) { $lineas.Add($Ruta); $lineas.Add('') }

    if ($Detalle.Archivos -eq 0) {
        $lineas.Add('No hay ni un archivo aquí dentro.')
        if ($Detalle.Inaccesibles -gt 0) {
            $lineas.Add('')
            $lineas.Add(('Aunque {0} {1} no se {2} podido leer: puede que haya algo ahí.' -f
                         $Detalle.Inaccesibles,
                         $(if ($Detalle.Inaccesibles -eq 1) { 'carpeta' } else { 'carpetas' }),
                         $(if ($Detalle.Inaccesibles -eq 1) { 'haya' } else { 'hayan' })))
        }
        return ($lineas -join [Environment]::NewLine)
    }

    $lineas.Add(('{0} {1} en {2} {3}, {4} en total.' -f
                 $Detalle.Archivos, $(if ($Detalle.Archivos -eq 1) { 'archivo' } else { 'archivos' }),
                 $Detalle.Carpetas, $(if ($Detalle.Carpetas -eq 1) { 'subcarpeta' } else { 'subcarpetas' }),
                 (Format-Tamano $Detalle.Bytes)))

    if ($null -ne $Detalle.Ultimo) {
        $lineas.Add(('Lo más reciente es de {0} ({1}).' -f
                     $Detalle.Ultimo.ToString('yyyy-MM-dd'), (Format-Antiguedad $Detalle.Ultimo)))
    }

    if ($Detalle.EnNube -gt 0) {
        $lineas.Add(('{0} {1} solo en la nube: no ocupan ese espacio en el disco.' -f
                     $Detalle.EnNube,
                     $(if ($Detalle.EnNube -eq 1) { 'archivo está' } else { 'archivos están' })))
    }

    if ($Detalle.Inaccesibles -gt 0) {
        $lineas.Add(('{0} {1} no se {2} podido leer: lo de dentro no está contado.' -f
                     $Detalle.Inaccesibles,
                     $(if ($Detalle.Inaccesibles -eq 1) { 'carpeta' } else { 'carpetas' }),
                     $(if ($Detalle.Inaccesibles -eq 1) { 'ha' } else { 'han' })))
    }

    $lineas.Add('')
    if ($Detalle.Truncado) {
        # Sin esto, "los mayores son estos" seria un dato que parece cierto
        # y no lo es: el archivo más grande puede estar en la parte que no
        # se llegó a mirar.
        $lineas.Add(('Los mayores de los primeros {0} archivos (hay más y no se han mirado todos):' -f
                     $Detalle.Archivos))
    } else {
        $lineas.Add('Lo que más ocupa:')
    }

    foreach ($mayor in @($Detalle.Mayores)) {
        $lineas.Add(('   {0}   {1}{2}' -f
                     (Format-Tamano $mayor.Bytes).PadLeft(10),
                     $mayor.Nombre,
                     $(if ($mayor.EnNube) { '   (en la nube)' } else { '' })))
    }

    return ($lineas -join [Environment]::NewLine)
}
