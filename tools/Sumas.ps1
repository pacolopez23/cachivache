<#
.SYNOPSIS
    El formato de las sumas SHA-256 que se publican con cada version.
    Calculo puro, sin tocar el disco.

.DESCRIPTION
    Aparte de Publicar-Sumas.ps1, igual que Banco-Decisiones.ps1 lo esta de
    Banco-Pruebas.ps1: este archivo se puede dot-sourcear sin que pase nada,
    el otro escribe archivos.

    Y aparte tambien porque el formato IMPORTA mas de lo que parece. Un
    archivo de sumas no es un texto informativo: es un archivo que otros
    programas leen. `sha256sum -c SHA256SUMS.txt`, winget y Scoop esperan una
    forma exacta, y cualquiera de estos descuidos lo rompe sin que se note al
    mirarlo:

    - Mayusculas. Get-FileHash devuelve el hash en MAYUSCULAS y sha256sum
      escribe en minusculas. Comparar a ojo funciona igual; comparar con una
      herramienta, no.
    - Un solo espacio. El separador son DOS espacios exactos.
    - Saltos de linea de Windows. El \r sobrante se cuela en el nombre del
      archivo y ninguna linea casa.
    - El BOM. Este proyecto exige BOM en todo .ps1 y .xaml -y con razon, ver
      la invariante de codificacion-, pero aqui es al reves: un BOM al
      principio hace que la PRIMERA linea no valide, y solo la primera. Es el
      peor fallo posible, porque parece que funciona.

    Ninguno de los cuatro se ve leyendo el archivo. Todos se ven aqui.

    Ver [DIS-02].
#>

function Format-SumasSha256 {
    <#
    .SYNOPSIS
        El contenido de SHA256SUMS.txt a partir de los pares nombre/hash.

    .PARAMETER Entradas
        Tabla ordenada o lista de hashtables con Nombre y Hash.

    .OUTPUTS
        El texto completo, con saltos LF y salto final. Sin BOM: quien lo
        escriba tiene que usar una codificacion que no lo ponga.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()]
        [object[]] $Entradas
    )

    if (-not $Entradas) { return '' }

    $lineas = foreach ($e in $Entradas) {
        $nombre = [string]$e.Nombre
        $hash   = [string]$e.Hash

        if ([string]::IsNullOrWhiteSpace($nombre) -or [string]::IsNullOrWhiteSpace($hash)) {
            throw 'Una entrada de sumas no tiene nombre o no tiene hash.'
        }
        # El nombre lleva ruta: quien verifica lo hace desde la carpeta donde
        # descargo los archivos, y una ruta del agente de integracion continua
        # ahi no existe.
        if ($nombre -match '[\\/]') {
            throw ("El nombre '$nombre' lleva ruta, y el archivo de sumas solo admite nombres.")
        }

        # Dos espacios, y en minusculas. Ver la cabecera.
        '{0}  {1}' -f $hash.ToLowerInvariant(), $nombre
    }

    # Salto final incluido: sha256sum se queja de una ultima linea sin
    # terminar, y unas herramientas la ignoran y otras no.
    return (($lineas -join "`n") + "`n")
}

function Format-TablaSumas {
    <#
    .SYNOPSIS
        Las mismas sumas, en tabla de Markdown para el cuerpo de la version.

    .DESCRIPTION
        Van en los DOS sitios a proposito. El archivo sirve para verificar
        con una herramienta; la tabla sirve para verificar A OJO sin
        descargar un segundo archivo, que es lo que hace la gente. Y sobre
        todo: si las sumas solo viven dentro de un archivo que se descarga
        del mismo sitio que el paquete, quien pueda cambiar uno puede cambiar
        el otro. En el cuerpo de la version quedan escritas donde el paquete
        no llega.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()]
        [object[]] $Entradas
    )

    if (-not $Entradas) { return '' }

    $filas = foreach ($e in $Entradas) {
        '| `{0}` | `{1}` |' -f ([string]$e.Nombre), ([string]$e.Hash).ToLowerInvariant()
    }

    return (@(
        '| Archivo | SHA-256 |'
        '|---|---|'
        $filas
    ) -join "`n")
}

function Test-SumaSha256Valida {
    <#
    .SYNOPSIS
        Si una cadena tiene forma de suma SHA-256.

    .DESCRIPTION
        Sesenta y cuatro digitos hexadecimales. Existe para que un hash
        vacio, truncado o con un espacio dentro no llegue a publicarse:
        publicar una suma mal es peor que no publicarla, porque quien la
        comprueba y no le cuadra concluye que el paquete esta adulterado.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Suma
    )

    if ([string]::IsNullOrWhiteSpace($Suma)) { return $false }
    return $Suma -match '^[0-9a-fA-F]{64}$'
}
