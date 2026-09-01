<#
.SYNOPSIS
    Banco de medicion de [VEL-02]: ¿compensa guardar el indice en disco y
    actualizarlo con el diario de cambios de NTFS, en vez de volver a
    recorrer el disco entero?

.DESCRIPTION
    Este guion NO implementa el indice incremental. Mide si vale la pena
    implementarlo, igual que el banco de [VEL-01] midio la tabla maestra
    antes de construirla. Ver docs/VEL-02-MEDICION.md.

    La pregunta que contesta es un numero: EL PUNTO DE EQUILIBRIO. A partir
    de cuantos cambios deja de compensar el camino incremental y sale mas a
    cuenta volver a recorrer el disco.

    Se mide en tres bloques, que se corresponden con los tres costes del
    camino incremental:

      1. PERSISTENCIA. Guardar el indice y volver a cargarlo. Es lo primero
         porque puede matar la idea entera: si cargar un indice de un millon
         de entradas cuesta mas que los ~5 s del recorrido completo, no hay
         nada que discutir. Se comparan cuatro formatos.

      2. APLICAR. Dado un indice de N entradas y D cambios, cuanto cuesta
         actualizarlo y volver a propagar los totales por carpeta.

      3. DIARIO USN. El coste de PARSEAR un registro del diario de cambios.
         Ojo: lo que se mide aqui es el parseo sobre registros sinteticos
         construidos a mano, byte a byte, con el formato USN_RECORD_V2.
         LEER el diario de verdad exige DeviceIoControl con
         FSCTL_READ_USN_JOURNAL y NO SE PUEDE EJECUTAR FUERA DE WINDOWS.
         Ese trozo no se ha ejecutado nunca. Ver el documento.

    -------------------------------------------------------------------
    QUE TOCA ESTE GUION

    Crea archivos SOLO dentro de -Carpeta, que por omision es una carpeta
    propia dentro del temporal del sistema. No borra nada, ni dentro ni
    fuera: sobrescribe sus propios archivos, que tienen nombre fijo. Al
    terminar dice donde han quedado para que se puedan mirar o borrar a
    mano.

.PARAMETER Carpeta
    Donde deja los archivos de trabajo. Es el unico sitio que toca.
.PARAMETER Tamanos
    Tamanos de indice sintetico para el bloque de persistencia.
.PARAMETER Cambios
    Valores de D para el bloque de aplicar cambios.
.PARAMETER Pasadas
    Repeticiones de cada medida. Se guarda LA MEJOR, no la media: la peor
    pasada mide el contenedor, no el codigo.
.PARAMETER ArchivosReales
    Archivos de verdad que crea para medir el recorrido, que es la linea
    base contra la que se compara todo.
.PARAMETER TopeJson
    Por encima de este tamano no se intenta el formato JSON salvo que se
    pase -ForzarJson. Existe porque ConvertFrom-Json sobre un millon de
    objetos se lleva el proceso por delante; ver el documento.
.PARAMETER RegistrosPorArchivo
    Cuantos registros del diario genera de media UN archivo tocado. Un solo
    guardado produce varios: DATA_EXTEND, DATA_OVERWRITE, CLOSE... El punto
    de equilibrio sale en registros, y este factor lo traduce a archivos.
    NO ESTA MEDIDO: es un supuesto conservador y esta aqui para que se vea.
.PARAMETER ForzarJson
    Intenta JSON tambien en los tamanos grandes. Puede quedarse sin memoria.
.PARAMETER SinRecorrido
    Salta el bloque del recorrido real, que es el que crea archivos.
.PARAMETER Bloque
    Ejecuta solo un bloque.

.EXAMPLE
    ~/pwsh/pwsh -NoProfile -File tools/Banco-VEL02.ps1
#>
[CmdletBinding()]
param(
    [string]   $Carpeta             = (Join-Path ([IO.Path]::GetTempPath()) 'Banco-VEL02'),
    [int[]]    $Tamanos             = @(10000, 100000, 1000000),
    [int[]]    $Cambios             = @(100, 1000, 10000, 100000),
    [int]      $Pasadas             = 3,
    [int]      $ArchivosReales      = 20000,
    [int]      $TopeJson            = 200000,
    [double]   $RegistrosPorArchivo = 4.0,
    [switch]   $ForzarJson,
    [switch]   $SinRecorrido,
    [ValidateSet('Todo', 'Persistencia', 'Aplicar', 'Usn', 'Recorrido')]
    [string]   $Bloque              = 'Todo'
)

$ErrorActionPreference = 'Stop'

# El indice sintetico imita la forma de un disco con uso: 20.000 carpetas
# repartidas en tres niveles bajo la raiz. Con un millon de archivos salen
# 50 por carpeta, que es el orden de magnitud real. La profundidad importa
# porque propagar un cambio cuesta un salto por nivel.
$script:NivelesA = 20
$script:NivelesB = 40
$script:NivelesC = 25

# ======================================================================
#  Utilidades de medida
# ======================================================================

function Measure-Mejor {
    <#
    .SYNOPSIS
        Ejecuta un bloque varias veces y devuelve los segundos de la MEJOR
        pasada, o $null si el bloque revienta.

    .DESCRIPTION
        Se queda con la mejor y no con la media a proposito. Esto corre en
        un contenedor compartido: la pasada mala mide al vecino. La mejor
        es la unica que se puede atribuir al codigo.

        Y devuelve $null en vez de lanzar cuando el bloque falla, porque
        aqui un fallo ES un resultado: que ConvertFrom-Json se quede sin
        memoria con un millon de objetos es justo lo que hay que saber.

    .PARAMETER Bloque
        Lo que se mide.
    .PARAMETER Pasadas
        Cuantas veces se repite.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [scriptblock] $Bloque,
        [int] $Pasadas = 3
    )

    $mejor = [double]::MaxValue
    $reloj = [Diagnostics.Stopwatch]::new()
    for ($i = 0; $i -lt $Pasadas; $i++) {
        # Fuera del cronometro: recoger la basura de la pasada anterior no
        # es trabajo del codigo que se mide.
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        try {
            $reloj.Restart()
            & $Bloque | Out-Null
            $reloj.Stop()
        } catch {
            Write-Host ('      (falló: ' + $_.Exception.GetType().Name + ')') -ForegroundColor DarkYellow
            return $null
        }
        if ($reloj.Elapsed.TotalSeconds -lt $mejor) { $mejor = $reloj.Elapsed.TotalSeconds }
    }
    return $mejor
}

function Test-EsLineal {
    <#
    .SYNOPSIS
        Si el coste por unidad se mantiene estable entre dos medidas.

    .DESCRIPTION
        Calculo puro, y esta aqui por lo mismo que en [VEL-01]: extrapolar
        a un millon desde cien mil solo vale si la relacion es lineal. Si
        el coste por unidad se dispara -por memoria, por el recolector de
        basura, por lo que sea- la extrapolacion miente y hay que decirlo
        en vez de publicar el numero.

    .PARAMETER UnidadesA
        Unidades de la primera medida.
    .PARAMETER SegundosA
        Segundos de la primera medida.
    .PARAMETER UnidadesB
        Unidades de la segunda medida.
    .PARAMETER SegundosB
        Segundos de la segunda medida.
    .PARAMETER Tolerancia
        Desviacion admitida entre los dos costes por unidad, en tanto por
        uno. 0,25 es generoso a proposito: el ruido medido en [VEL-01] en
        este mismo entorno fue del 25 %.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [double] $UnidadesA,
        [Parameter(Mandatory)] [double] $SegundosA,
        [Parameter(Mandatory)] [double] $UnidadesB,
        [Parameter(Mandatory)] [double] $SegundosB,
        [double] $Tolerancia = 0.25
    )

    if ($UnidadesA -le 0 -or $UnidadesB -le 0) { return $false }
    $a = $SegundosA / $UnidadesA
    $b = $SegundosB / $UnidadesB
    if ($a -le 0) { return $false }
    return ([Math]::Abs($b - $a) / $a) -le $Tolerancia
}

function Get-PuntoDeEquilibrio {
    <#
    .SYNOPSIS
        A partir de cuantos registros del diario deja de compensar el
        camino incremental.

    .DESCRIPTION
        La cuenta entera del punto, en una funcion pura para que se pueda
        discutir sin volver a medir nada:

            incremental = cargar el indice + D * (coste por registro)
            completo    = recorrer el disco otra vez

        Guardar el indice al final NO entra en ninguno de los dos lados
        porque los dos lo pagan igual: el camino incremental tiene que
        reescribir el archivo y el completo tambien.

        Si cargar ya cuesta mas que recorrer, el punto de equilibrio es
        CERO: la idea no compensa nunca, ni con un solo archivo cambiado.

    .PARAMETER SegundosRecorrido
        Lo que cuesta volver a recorrer el disco entero.
    .PARAMETER SegundosCarga
        Lo que cuesta cargar el indice guardado.
    .PARAMETER MicrosPorRegistro
        Coste total por registro del diario: parsearlo, resolver su ruta,
        preguntar el tamaño del archivo y aplicarlo al indice.
    .PARAMETER RegistrosPorArchivo
        Registros que genera de media un archivo tocado.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [double] $SegundosRecorrido,
        [Parameter(Mandatory)] [double] $SegundosCarga,
        [Parameter(Mandatory)] [double] $MicrosPorRegistro,
        [double] $RegistrosPorArchivo = 4.0
    )

    $margen = $SegundosRecorrido - $SegundosCarga
    if ($margen -le 0 -or $MicrosPorRegistro -le 0) {
        return [pscustomobject]@{
            Margen     = $margen
            Registros  = 0
            Archivos   = 0
            Compensa   = $false
        }
    }

    $registros = [int][Math]::Floor(($margen * 1e6) / $MicrosPorRegistro)
    $archivos  = 0
    if ($RegistrosPorArchivo -gt 0) {
        $archivos = [int][Math]::Floor($registros / $RegistrosPorArchivo)
    }

    return [pscustomobject]@{
        Margen    = $margen
        Registros = $registros
        Archivos  = $archivos
        Compensa  = $true
    }
}

function Write-Titulo {
    <#
    .SYNOPSIS
        Cabecera de un bloque del banco.
    .PARAMETER Texto
        Lo que se escribe.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Texto)

    Write-Host ''
    Write-Host ('=== ' + $Texto + ' ' + ('=' * [Math]::Max(0, 66 - $Texto.Length))) -ForegroundColor Cyan
}

# ======================================================================
#  Datos sinteticos
# ======================================================================

function Get-CarpetasSinteticas {
    <#
    .SYNOPSIS
        Las rutas de carpeta del disco sintetico, en orden.
    .DESCRIPTION
        Se generan las combinaciones completas de los tres niveles en vez
        de calcular la carpeta a partir del indice del archivo. La primera
        version lo hacia con [int]($i/20), y [int] en PowerShell REDONDEA
        -no trunca-, asi que se saltaba combinaciones y luego el indice
        tenia archivos colgando de carpetas que no existian.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $total = $script:NivelesA * $script:NivelesB * $script:NivelesC
    $lista = [string[]]::new($total)
    $k = 0
    for ($a = 0; $a -lt $script:NivelesA; $a++) {
        for ($b = 0; $b -lt $script:NivelesB; $b++) {
            for ($c = 0; $c -lt $script:NivelesC; $c++) {
                $lista[$k] = 'C:\Usuarios\paco\Datos\N' + $a + '\M' + $b + '\S' + $c
                $k++
            }
        }
    }
    return ,$lista
}

function New-EntradasSinteticas {
    <#
    .SYNOPSIS
        N entradas de archivo con la forma que devuelve New-IndiceDisco.

    .DESCRIPTION
        Los mismos seis campos que pone New-IndiceDisco en su lista
        Archivos: Ruta, Nombre, Carpeta, Extension, Bytes, Ultimo. Medir
        la persistencia de una forma distinta de la real no diria nada.

        AVISO DE MEMORIA: un millon de estos objetos son del orden de un
        gigabyte y unos ocho segundos solo de construirlos. Ese dato ya es
        parte del resultado y sale impreso.

    .PARAMETER Cantidad
        Cuantas entradas.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone objetos en memoria.')]
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)] [int] $Cantidad)

    $carpetas = Get-CarpetasSinteticas
    $fecha    = [datetime]'2026-08-01'
    $lista    = [Collections.Generic.List[object]]::new($Cantidad)
    for ($i = 0; $i -lt $Cantidad; $i++) {
        $carpeta = $carpetas[$i % $carpetas.Length]
        $nombre  = 'archivo-' + $i + '.dat'
        $lista.Add([pscustomobject]@{
            Ruta      = $carpeta + '\' + $nombre
            Nombre    = $nombre
            Carpeta   = $carpeta
            Extension = '.dat'
            Bytes     = [double](1000 + ($i % 500000))
            Ultimo    = $fecha
        })
    }
    return $lista
}

function New-BuferUsn {
    <#
    .SYNOPSIS
        Un buffer con N registros USN_RECORD_V2 construidos a mano.

    .DESCRIPTION
        La estructura, tal como la documenta Microsoft. Los desplazamientos
        estan escritos aqui porque son lo que luego lee Get-RegistroUsn, y
        si los dos lados los inventaran por separado el banco mediria lo
        rapido que se obtiene una respuesta equivocada:

            0   RecordLength              DWORD
            4   MajorVersion              WORD    (2)
            6   MinorVersion              WORD    (0)
            8   FileReferenceNumber       ULONGLONG
            16  ParentFileReferenceNumber ULONGLONG
            24  Usn                       LONGLONG
            32  TimeStamp                 LARGE_INTEGER
            40  Reason                    DWORD
            44  SourceInfo                DWORD
            48  SecurityId                DWORD
            52  FileAttributes            DWORD
            56  FileNameLength            WORD    (bytes, no caracteres)
            58  FileNameOffset            WORD
            60  FileName                  WCHAR[]

        El registro se rellena hasta multiplo de ocho, que es lo que hace
        el sistema de verdad, y por eso RecordLength no coincide con
        60 + FileNameLength.

        Lo que NO hay aqui, y es justo lo que decide el punto: el registro
        USN no trae ni la RUTA ni el TAMAÑO del archivo. Trae el nombre y
        la referencia del padre. La ruta hay que componerla y el tamaño hay
        que ir a preguntarlo al disco. Los dos costes se miden aparte.

    .PARAMETER Cantidad
        Cuantos registros.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un array de bytes en memoria.')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [int] $Cantidad)

    $flujo    = [IO.MemoryStream]::new()
    $escritor = [IO.BinaryWriter]::new($flujo)
    try {
        for ($i = 0; $i -lt $Cantidad; $i++) {
            $nombre = 'documento-de-trabajo-' + $i + '.dat'
            $bytes  = [Text.Encoding]::Unicode.GetBytes($nombre)
            $largo  = 60 + $bytes.Length
            if (($largo % 8) -ne 0) { $largo += 8 - ($largo % 8) }

            $escritor.Write([uint32]$largo)
            $escritor.Write([uint16]2)
            $escritor.Write([uint16]0)
            $escritor.Write([uint64](1000 + $i))
            $escritor.Write([uint64](5000 + ($i % 20000)))
            $escritor.Write([int64](100000 + $i))
            $escritor.Write([int64]133000000000000000)
            # USN_REASON_DATA_EXTEND
            $escritor.Write([uint32]0x00000002)
            $escritor.Write([uint32]0)
            $escritor.Write([uint32]0)
            # FILE_ATTRIBUTE_ARCHIVE
            $escritor.Write([uint32]0x00000020)
            $escritor.Write([uint16]$bytes.Length)
            $escritor.Write([uint16]60)
            $escritor.Write($bytes)
            $relleno = $largo - 60 - $bytes.Length
            if ($relleno -gt 0) { $escritor.Write([byte[]]::new($relleno)) }
        }
        $escritor.Flush()
        # La coma no es cosmetica: sin ella PowerShell desenvuelve el array
        # y quien lo recoge se queda con un Object[]. Ver docs/RELEVO.md.
        return ,$flujo.ToArray()
    } finally {
        $escritor.Dispose()
        $flujo.Dispose()
    }
}

function Get-RegistroUsn {
    <#
    .SYNOPSIS
        Parsea UN registro del diario de cambios desde un buffer.

    .DESCRIPTION
        Escrita como se escribiria de verdad en este proyecto: funcion con
        parametros declarados y un pscustomobject de salida. Eso es
        deliberado, porque [VEL-01] demostro que en PowerShell el 80 % del
        coste de este tipo de bucle no es el parseo sino el envoltorio de
        la funcion -unos 12 microsegundos por llamada-, y medir una version
        escrita en linea daria un numero que el programa nunca tendria.

        El banco mide las dos, para que se vea cuanto de lo que cuesta es
        el idioma y cuanto el trabajo.

    .PARAMETER Bufer
        Buffer con uno o varios registros seguidos.
    .PARAMETER Desplazamiento
        Donde empieza el registro dentro del buffer.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [byte[]] $Bufer,
        [Parameter(Mandatory)] [int]    $Desplazamiento
    )

    $o = $Desplazamiento
    $largo = [BitConverter]::ToUInt32($Bufer, $o)
    # Un registro no puede medir menos que su cabecera. Con menos de eso el
    # recorrido avanzaria cero y se quedaria dando vueltas para siempre.
    if ($largo -lt 60) { return $null }

    $largoNombre = [BitConverter]::ToUInt16($Bufer, $o + 56)
    $offsetNombre = [BitConverter]::ToUInt16($Bufer, $o + 58)

    return [pscustomobject]@{
        Largo      = $largo
        Referencia = [BitConverter]::ToUInt64($Bufer, $o + 8)
        Padre      = [BitConverter]::ToUInt64($Bufer, $o + 16)
        Usn        = [BitConverter]::ToInt64($Bufer, $o + 24)
        Motivo     = [BitConverter]::ToUInt32($Bufer, $o + 40)
        Atributos  = [BitConverter]::ToUInt32($Bufer, $o + 52)
        Nombre     = [Text.Encoding]::Unicode.GetString($Bufer, $o + $offsetNombre, $largoNombre)
    }
}

# ======================================================================
#  Bloque 1 — Persistencia
# ======================================================================

function Invoke-BancoPersistencia {
    <#
    .SYNOPSIS
        Guardar y cargar el indice, en cuatro formatos.

    .DESCRIPTION
        Es el bloque que puede matar la idea entera, y por eso va primero.
        El recorrido completo de un millon de archivos son unos cinco
        segundos; si cargar el indice guardado cuesta mas que eso, no hay
        camino incremental que valga.

        Cuatro formatos, y cada uno acaba en la estructura que de verdad
        haria falta:

          JSON  ConvertTo-Json / ConvertFrom-Json
          CSV   Export-Csv / Import-Csv
          TSV   texto plano por tabuladores, [IO.File]::ReadAllLines
          BIN   BinaryWriter / BinaryReader

        Del TSV se miden DOS cargas: a diccionario y a pscustomobject. No
        es un detalle: [VEL-01] ya midio que componer un millon de objetos
        cuesta segundos por si solo, y el indice no necesita objetos, sino
        poder preguntar "cuanto media este archivo".

    .PARAMETER Carpeta
        Donde se escriben los archivos.
    .PARAMETER Tamanos
        Tamanos de indice a probar.
    .PARAMETER Pasadas
        Repeticiones.
    .PARAMETER TopeJson
        Tamano por encima del cual no se intenta JSON.
    .PARAMETER ForzarJson
        Intentarlo igualmente.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Carpeta,
        [Parameter(Mandatory)] [int[]]  $Tamanos,
        [int]    $Pasadas  = 3,
        [int]    $TopeJson = 200000,
        [switch] $ForzarJson
    )

    Write-Titulo 'BLOQUE 1 - Guardar y cargar el índice'
    $resultados = [Collections.Generic.List[object]]::new()

    foreach ($n in $Tamanos) {
        Write-Host ''
        Write-Host ('  ' + ('{0:N0}' -f $n) + ' entradas') -ForegroundColor White

        $reloj = [Diagnostics.Stopwatch]::StartNew()
        $script:entradas = New-EntradasSinteticas -Cantidad $n
        $construir = $reloj.Elapsed.TotalSeconds
        $memoria = [GC]::GetTotalMemory($false) / 1MB
        Write-Host ('    construir la lista de objetos en memoria : ' +
                    ('{0,7:N2} s' -f $construir) + '   (memoria del proceso: ' +
                    ('{0:N0}' -f $memoria) + ' MB)')

        $script:rutaJson = Join-Path $Carpeta 'indice.json'
        $script:rutaCsv  = Join-Path $Carpeta 'indice.csv'
        $script:rutaTsv  = Join-Path $Carpeta 'indice.tsv'
        $script:rutaBin  = Join-Path $Carpeta 'indice.bin'

        # --- JSON -----------------------------------------------------
        $tJsonG = $null; $tJsonC = $null; $bytesJson = 0
        if ($n -le $TopeJson -or $ForzarJson) {
            $tJsonG = Measure-Mejor -Pasadas $Pasadas -Bloque {
                $texto = $script:entradas | ConvertTo-Json -Depth 3 -Compress
                [IO.File]::WriteAllText($script:rutaJson, $texto)
            }
            if ($null -ne $tJsonG) { $bytesJson = (Get-Item -LiteralPath $script:rutaJson).Length }
        } else {
            Write-Host '    JSON  : no se intenta a este tamaño (usa -ForzarJson)' -ForegroundColor DarkYellow
        }

        # --- CSV ------------------------------------------------------
        $tCsvG = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $script:entradas | Export-Csv -LiteralPath $script:rutaCsv -NoTypeInformation -Encoding utf8
        }
        $bytesCsv = 0
        if ($null -ne $tCsvG) { $bytesCsv = (Get-Item -LiteralPath $script:rutaCsv).Length }

        # --- TSV ------------------------------------------------------
        $tTsvG = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $sb = [Text.StringBuilder]::new()
            foreach ($e in $script:entradas) {
                [void]$sb.Append($e.Ruta).Append("`t").Append([int64]$e.Bytes).Append("`t").Append($e.Ultimo.Ticks).Append("`n")
            }
            [IO.File]::WriteAllText($script:rutaTsv, $sb.ToString())
        }
        $bytesTsv = (Get-Item -LiteralPath $script:rutaTsv).Length

        # --- BIN ------------------------------------------------------
        $tBinG = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $fs = [IO.File]::Create($script:rutaBin)
            $bw = [IO.BinaryWriter]::new($fs, [Text.UTF8Encoding]::new($false))
            try {
                $bw.Write([int32]$script:entradas.Count)
                foreach ($e in $script:entradas) {
                    $bw.Write([string]$e.Ruta)
                    $bw.Write([int64]$e.Bytes)
                    $bw.Write([int64]$e.Ultimo.Ticks)
                }
            } finally { $bw.Dispose(); $fs.Dispose() }
        }
        $bytesBin = (Get-Item -LiteralPath $script:rutaBin).Length

        # A partir de aqui NO hace falta la lista de objetos. Se suelta antes
        # de cronometrar ninguna carga: al abrir el programa de verdad la
        # memoria esta vacia, y medir una carga con 1,6 GB de objetos vivos
        # al lado mide al recolector de basura, no al formato. Con las
        # cargas intercaladas entre las escrituras, el CSV de un millon de
        # entradas daba 10,9 s; soltando la lista antes, 3,4 s.
        $script:entradas = $null
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()

        # --- Cargas ---------------------------------------------------
        $tJsonC = $null
        if ($null -ne $tJsonG) {
            $tJsonC = Measure-Mejor -Pasadas $Pasadas -Bloque {
                $texto = [IO.File]::ReadAllText($script:rutaJson)
                $texto | ConvertFrom-Json
            }
        }

        $tCsvC = $null
        if ($null -ne $tCsvG) {
            $tCsvC = Measure-Mejor -Pasadas $Pasadas -Bloque {
                @(Import-Csv -LiteralPath $script:rutaCsv)
            }
        }

        $tTsvDicc = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $lineas = [IO.File]::ReadAllLines($script:rutaTsv)
            $d = [Collections.Generic.Dictionary[string, object]]::new($lineas.Length, [StringComparer]::OrdinalIgnoreCase)
            foreach ($l in $lineas) {
                $p = $l.Split([char]9)
                $d[$p[0]] = [int64]$p[1]
            }
            $d.Count
        }

        $tTsvObj = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $lineas = [IO.File]::ReadAllLines($script:rutaTsv)
            $lista = [Collections.Generic.List[object]]::new($lineas.Length)
            foreach ($l in $lineas) {
                $p = $l.Split([char]9)
                $lista.Add([pscustomobject]@{ Ruta = $p[0]; Bytes = [int64]$p[1]; Ultimo = [int64]$p[2] })
            }
            $lista.Count
        }

        $tBinC = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $fs = [IO.File]::OpenRead($script:rutaBin)
            $br = [IO.BinaryReader]::new($fs, [Text.UTF8Encoding]::new($false))
            try {
                $cuantos = $br.ReadInt32()
                $d = [Collections.Generic.Dictionary[string, object]]::new($cuantos, [StringComparer]::OrdinalIgnoreCase)
                for ($i = 0; $i -lt $cuantos; $i++) {
                    $ruta = $br.ReadString()
                    $tam  = $br.ReadInt64()
                    [void]$br.ReadInt64()
                    $d[$ruta] = $tam
                }
                $d.Count
            } finally { $br.Dispose(); $fs.Dispose() }
        }

        $fila = [pscustomobject]@{
            Entradas  = $n
            Construir = $construir
            JsonG     = $tJsonG;    JsonC = $tJsonC;    JsonBytes = $bytesJson
            CsvG      = $tCsvG;     CsvC  = $tCsvC;     CsvBytes  = $bytesCsv
            TsvG      = $tTsvG;     TsvD  = $tTsvDicc;  TsvO      = $tTsvObj; TsvBytes = $bytesTsv
            BinG      = $tBinG;     BinC  = $tBinC;     BinBytes  = $bytesBin
        }
        $resultados.Add($fila)

        Write-Host ('    JSON  guardar ' + (Format-Seg $tJsonG) + '  cargar ' + (Format-Seg $tJsonC) + '  ' + (Format-Tam $bytesJson))
        Write-Host ('    CSV   guardar ' + (Format-Seg $tCsvG)  + '  cargar ' + (Format-Seg $tCsvC)  + '  ' + (Format-Tam $bytesCsv))
        Write-Host ('    TSV   guardar ' + (Format-Seg $tTsvG)  + '  cargar ' + (Format-Seg $tTsvDicc) + '  ' + (Format-Tam $bytesTsv) + '  (a diccionario)')
        Write-Host ('    TSV   guardar ' + (Format-Seg $tTsvG)  + '  cargar ' + (Format-Seg $tTsvObj)  + '  ' + (Format-Tam $bytesTsv) + '  (a pscustomobject)')
        Write-Host ('    BIN   guardar ' + (Format-Seg $tBinG)  + '  cargar ' + (Format-Seg $tBinC)  + '  ' + (Format-Tam $bytesBin) + '  (a diccionario)')
    }

    return $resultados
}

function Format-Seg {
    <#
    .SYNOPSIS
        Segundos para la tabla, o un guion si la medida no existe.
    .PARAMETER Segundos
        La medida, o $null si el formato no pudo completarse.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Segundos)

    if ($null -eq $Segundos) { return '     -   ' }
    return ('{0,7:N2} s' -f [double]$Segundos)
}

function Format-Tam {
    <#
    .SYNOPSIS
        Tamaño de archivo para la tabla.
    .PARAMETER Bytes
        Bytes en disco.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Bytes)

    if ($null -eq $Bytes -or [double]$Bytes -le 0) { return '        -' }
    return ('{0,6:N1} MB' -f ([double]$Bytes / 1MB))
}

# ======================================================================
#  Bloque 2 — Aplicar los cambios al indice
# ======================================================================

function Invoke-BancoAplicar {
    <#
    .SYNOPSIS
        Cuanto cuesta actualizar un indice de N entradas con D cambios.

    .DESCRIPTION
        Se miden los dos caminos, porque la diferencia entre ellos es la
        mitad del punto:

          COMPLETO     Recorrer las N entradas de archivo y volver a sumar
                       todas las carpetas desde cero. Es lo que habria que
                       hacer si el indice guardara solo los archivos.
          INCREMENTAL  Por cada cambio, tocar su entrada y subir el delta
                       por la cadena de carpetas hasta la raiz.

        El resultado del completo es el que justifica guardar TAMBIEN la
        tabla de carpetas: si al cargar hay que volver a sumar un millon de
        archivos, la carga barata deja de serlo.

    .PARAMETER Entradas
        Tamano del indice.
    .PARAMETER Cambios
        Valores de D.
    .PARAMETER Pasadas
        Repeticiones.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [int]   $Entradas,
        [Parameter(Mandatory)] [int[]] $Cambios,
        [int] $Pasadas = 3
    )

    Write-Titulo 'BLOQUE 2 - Aplicar los cambios al índice'

    $carpetasRuta = Get-CarpetasSinteticas
    $reloj = [Diagnostics.Stopwatch]::StartNew()

    $script:arch = [Collections.Generic.Dictionary[string, object]]::new($Entradas + 100000, [StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $Entradas; $i++) {
        $script:arch[$carpetasRuta[$i % $carpetasRuta.Length] + '\a-' + $i + '.dat'] = [int64](1000 + ($i % 500000))
    }

    $script:carp = [Collections.Generic.Dictionary[string, object]]::new(30000, [StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $carpetasRuta) {
        $p = $t
        while ($true) {
            if ($script:carp.ContainsKey($p)) { break }
            $script:carp[$p] = [pscustomobject]@{ Ruta = $p; Bytes = [double]0; Propios = [double]0; Archivos = 0 }
            $j = $p.LastIndexOf('\')
            if ($j -lt 3) { break }
            $p = $p.Substring(0, $j)
        }
    }
    Write-Host ('  índice en memoria: ' + ('{0:N0}' -f $script:arch.Count) + ' archivos en ' +
                ('{0:N0}' -f $script:carp.Count) + ' carpetas  (montarlo: ' +
                ('{0:N2}' -f $reloj.Elapsed.TotalSeconds) + ' s)')

    # --- Propagacion completa ----------------------------------------
    $tCompleta = Measure-Mejor -Pasadas $Pasadas -Bloque {
        foreach ($e in $script:carp.Values) { $e.Bytes = 0.0; $e.Propios = 0.0; $e.Archivos = 0 }
        foreach ($ruta in $script:arch.Keys) {
            $b = $script:arch[$ruta]
            $p = $ruta.Substring(0, $ruta.LastIndexOf('\'))
            $e = $script:carp[$p]
            $e.Propios += $b
            $e.Archivos++
            while ($true) {
                $script:carp[$p].Bytes += $b
                $j = $p.LastIndexOf('\')
                if ($j -lt 3) { break }
                $p = $p.Substring(0, $j)
            }
        }
    }
    Write-Host ('  propagar TODO desde la tabla de archivos : ' + (Format-Seg $tCompleta))

    # --- Solo las carpetas, que es lo que hace New-IndiceDisco -------
    $tSoloCarpetas = Measure-Mejor -Pasadas $Pasadas -Bloque {
        foreach ($e in $script:carp.Values) { $e.Bytes = $e.Propios }
        foreach ($e in $script:carp.Values) {
            $p = $e.Ruta
            $j = $p.LastIndexOf('\')
            if ($j -lt 3) { continue }
            $padre = $p.Substring(0, $j)
            if ($script:carp.ContainsKey($padre)) { $script:carp[$padre].Bytes += $e.Bytes }
        }
    }
    Write-Host ('  propagar solo la tabla de carpetas       : ' + (Format-Seg $tSoloCarpetas))

    $resultados = [Collections.Generic.List[object]]::new()
    Write-Host ''
    foreach ($d in $Cambios) {
        $script:cambiosLista = [Collections.Generic.List[object]]::new($d)
        for ($j = 0; $j -lt $d; $j++) {
            $c = $carpetasRuta[$j % $carpetasRuta.Length]
            switch ($j % 3) {
                0 { $script:cambiosLista.Add([pscustomobject]@{ Tipo = 'alta'; Ruta = ($c + '\nuevo-' + $j + '.dat'); Bytes = [int64](5000 + $j) }) }
                1 { $script:cambiosLista.Add([pscustomobject]@{ Tipo = 'baja'; Ruta = ($c + '\a-' + $j + '.dat');    Bytes = [int64]0 }) }
                2 { $script:cambiosLista.Add([pscustomobject]@{ Tipo = 'mod';  Ruta = ($c + '\a-' + $j + '.dat');    Bytes = [int64](7000 + $j) }) }
            }
        }

        $t = Measure-Mejor -Pasadas $Pasadas -Bloque {
            foreach ($ch in $script:cambiosLista) {
                $r = $ch.Ruta
                $viejo = 0.0
                if ($script:arch.ContainsKey($r)) { $viejo = [double]$script:arch[$r] }
                $nuevo = [double]$ch.Bytes
                if ($ch.Tipo -eq 'baja') {
                    [void]$script:arch.Remove($r)
                    $nuevo = 0.0
                } else {
                    $script:arch[$r] = [int64]$ch.Bytes
                }
                $delta = $nuevo - $viejo
                $p = $r.Substring(0, $r.LastIndexOf('\'))
                if ($script:carp.ContainsKey($p)) { $script:carp[$p].Propios += $delta }
                while ($true) {
                    if ($script:carp.ContainsKey($p)) { $script:carp[$p].Bytes += $delta }
                    $j2 = $p.LastIndexOf('\')
                    if ($j2 -lt 3) { break }
                    $p = $p.Substring(0, $j2)
                }
            }
        }

        $micros = 0.0
        if ($null -ne $t -and $d -gt 0) { $micros = ($t * 1e6) / $d }
        $resultados.Add([pscustomobject]@{ Cambios = $d; Segundos = $t; Micros = $micros })
        Write-Host ('  D = ' + ('{0,7:N0}' -f $d) + '   ' + (Format-Seg $t) + '   ' +
                    ('{0,7:N2}' -f $micros) + ' µs por cambio')
    }

    return [pscustomobject]@{
        Completa      = $tCompleta
        SoloCarpetas  = $tSoloCarpetas
        Medidas       = $resultados
    }
}

# ======================================================================
#  Bloque 3 — El diario de cambios
# ======================================================================

function Invoke-BancoUsn {
    <#
    .SYNOPSIS
        Coste de parsear un registro del diario, y de convertirlo en algo
        que el indice pueda usar.

    .DESCRIPTION
        LO QUE AQUI NO SE MIDE, Y HAY QUE DECIRLO CADA VEZ: leer el diario
        de verdad es DeviceIoControl con FSCTL_READ_USN_JOURNAL sobre un
        manejador de \\.\C:, con privilegios de administrador y sobre NTFS.
        Nada de eso existe fuera de Windows. Lo que se mide es el parseo de
        registros sinteticos construidos byte a byte, exactamente como
        [VEL-01] midio los registros de la tabla maestra.

        Tres costes, y los tres hacen falta para el punto de equilibrio:

          1. Parsear el registro.
          2. Resolver su ruta. El registro trae la referencia del padre,
             no la ruta, asi que hace falta un diccionario de referencia a
             ruta que el indice guardado tendria que traer hecho.
          3. Preguntar el tamaño. El registro USN NO trae el tamaño del
             archivo. Por cada archivo tocado hay que ir al disco.

    .PARAMETER Pasadas
        Repeticiones.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([int] $Pasadas = 3)

    Write-Titulo 'BLOQUE 3 - Parsear el diario de cambios (USN)'
    Write-Host '  AVISO: leer el diario de verdad NO se ejecuta aquí. Solo el parseo.' -ForegroundColor Yellow

    $script:bufer = New-BuferUsn -Cantidad 64

    # Antes de medir, comprobar que el parseo es CORRECTO. Medir la
    # velocidad a la que se obtiene una respuesta equivocada no dice nada.
    $muestra = Get-RegistroUsn -Bufer $script:bufer -Desplazamiento 0
    if ($null -eq $muestra) { throw 'El registro USN de muestra no se parsea: el banco no puede medir nada.' }
    if ($muestra.Nombre -ne 'documento-de-trabajo-0.dat') { throw ('Nombre mal parseado: ' + $muestra.Nombre) }
    if ($muestra.Referencia -ne 1000) { throw ('Referencia mal parseada: ' + $muestra.Referencia) }
    if ($muestra.Padre -ne 5000) { throw ('Padre mal parseado: ' + $muestra.Padre) }
    if ($muestra.Motivo -ne 2) { throw ('Motivo mal parseado: ' + $muestra.Motivo) }
    Write-Host ('  muestra verificada: ' + $muestra.Nombre + ', ' + $muestra.Largo + ' bytes por registro')
    Write-Host ''

    $medidas = [Collections.Generic.List[object]]::new()
    foreach ($tamanoUsn in @(25000, 50000, 100000, 200000)) {
        $script:nUsn = $tamanoUsn
        $tFuncion = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $hechos = 0
            while ($hechos -lt $script:nUsn) {
                $o = 0
                while ($o -lt $script:bufer.Length -and $hechos -lt $script:nUsn) {
                    $x = Get-RegistroUsn -Bufer $script:bufer -Desplazamiento $o
                    $o += [int]$x.Largo
                    $hechos++
                }
            }
        }

        $tLinea = Measure-Mejor -Pasadas $Pasadas -Bloque {
            $hechos = 0
            while ($hechos -lt $script:nUsn) {
                $o = 0
                while ($o -lt $script:bufer.Length -and $hechos -lt $script:nUsn) {
                    $largo = [BitConverter]::ToUInt32($script:bufer, $o)
                    $ln = [BitConverter]::ToUInt16($script:bufer, $o + 56)
                    $on = [BitConverter]::ToUInt16($script:bufer, $o + 58)
                    $null = [pscustomobject]@{
                        Largo      = $largo
                        Referencia = [BitConverter]::ToUInt64($script:bufer, $o + 8)
                        Padre      = [BitConverter]::ToUInt64($script:bufer, $o + 16)
                        Usn        = [BitConverter]::ToInt64($script:bufer, $o + 24)
                        Motivo     = [BitConverter]::ToUInt32($script:bufer, $o + 40)
                        Atributos  = [BitConverter]::ToUInt32($script:bufer, $o + 52)
                        Nombre     = [Text.Encoding]::Unicode.GetString($script:bufer, $o + $on, $ln)
                    }
                    $o += [int]$largo
                    $hechos++
                }
            }
        }

        $medidas.Add([pscustomobject]@{
            Registros    = $script:nUsn
            Funcion      = $tFuncion
            MicrosFuncion = ($tFuncion * 1e6 / $script:nUsn)
            Linea        = $tLinea
            MicrosLinea  = ($tLinea * 1e6 / $script:nUsn)
        })
        Write-Host ('  N = ' + ('{0,7:N0}' -f $script:nUsn) +
                    '   función ' + (Format-Seg $tFuncion) + ' (' + ('{0,6:N2}' -f ($tFuncion * 1e6 / $script:nUsn)) + ' µs)' +
                    '   en línea ' + (Format-Seg $tLinea) + ' (' + ('{0,6:N2}' -f ($tLinea * 1e6 / $script:nUsn)) + ' µs)')
    }

    # --- Resolver la ruta desde la referencia del padre ---------------
    $script:refs = [Collections.Generic.Dictionary[uint64, string]]::new(30000)
    $carpetasRuta = Get-CarpetasSinteticas
    for ($i = 0; $i -lt $carpetasRuta.Length; $i++) { $script:refs[[uint64](5000 + $i)] = $carpetasRuta[$i] }

    $script:nRes = 100000
    $tResolver = Measure-Mejor -Pasadas $Pasadas -Bloque {
        for ($i = 0; $i -lt $script:nRes; $i++) {
            $padre = [uint64](5000 + ($i % 20000))
            $ruta = $null
            if ($script:refs.TryGetValue($padre, [ref]$ruta)) { $null = $ruta + '\documento-' + $i + '.dat' }
        }
    }
    Write-Host ''
    Write-Host ('  resolver la ruta desde la referencia del padre : ' +
                ('{0,6:N2}' -f ($tResolver * 1e6 / $script:nRes)) + ' µs por registro')

    return [pscustomobject]@{
        Medidas        = $medidas
        MicrosResolver = ($tResolver * 1e6 / $script:nRes)
    }
}

# ======================================================================
#  Bloque 4 — La linea base: el recorrido de verdad
# ======================================================================

function Invoke-BancoRecorrido {
    <#
    .SYNOPSIS
        Lo que cuesta el recorrido de hoy, sobre archivos de verdad.

    .DESCRIPTION
        Es la linea base contra la que se compara todo, y se mide en la
        misma sesion que el resto en vez de copiar el numero de [VEL-01],
        porque los dos lados tienen que haber corrido en la misma maquina
        el mismo dia para que la comparacion valga.

        Se miden tres cosas sobre el mismo arbol:

          * New-IndiceDisco, la funcion del programa. Es la referencia.
          * El recorrido construyendo ADEMAS la tabla por archivo, que es
            lo que [VEL-02] necesitaria y hoy no existe.
          * Preguntar el tamaño de un archivo suelto por su ruta, que es
            lo que habria que hacer por cada alta del diario.

        Y se mide a la mitad de tamaño tambien, para comprobar que la
        relacion es lineal ANTES de extrapolar a un millon.

    .PARAMETER Carpeta
        Carpeta de trabajo del banco.
    .PARAMETER Archivos
        Cuantos archivos de verdad crear.
    .PARAMETER Pasadas
        Repeticiones.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Carpeta,
        [int] $Archivos = 20000,
        [int] $Pasadas  = 3
    )

    Write-Titulo 'BLOQUE 4 - La línea base: el recorrido de hoy'

    $script:raiz = Join-Path $Carpeta 'arbol'
    $porCarpeta = 100
    $cuantasCarpetas = [int][Math]::Ceiling($Archivos / $porCarpeta)

    if (-not (Test-Path -LiteralPath $script:raiz)) {
        Write-Host ('  creando ' + ('{0:N0}' -f $Archivos) + ' archivos de verdad en ' + $script:raiz + ' ...')
        New-Item -ItemType Directory -Force -Path $script:raiz | Out-Null
        for ($c = 0; $c -lt $cuantasCarpetas; $c++) {
            $d = Join-Path $script:raiz ('c' + $c)
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            for ($f = 0; $f -lt $porCarpeta; $f++) {
                [IO.File]::WriteAllText((Join-Path $d ('f' + $f + '.dat')), 'x')
            }
        }
    } else {
        Write-Host ('  reutilizando el árbol que ya existe en ' + $script:raiz)
    }

    $script:rutas = [IO.Directory]::GetFiles($script:raiz, '*', [IO.SearchOption]::AllDirectories)
    Write-Host ('  archivos en el árbol: ' + ('{0:N0}' -f $script:rutas.Length))

    # New-IndiceDisco solo se mide si el nucleo ya esta cargado. Cargarlo
    # es cosa del cuerpo del guion, no de aqui: dot-sourcear dentro de una
    # funcion mete las funciones en el ambito de ESA funcion, y que un
    # bloque invocado con & las vea desde ahi es justo el tipo de apuesta
    # que docs/RELEVO.md prohibe.
    $tIndice = $null
    if ($null -ne (Get-Command -Name 'New-IndiceDisco' -ErrorAction SilentlyContinue)) {
        $tIndice = Measure-Mejor -Pasadas $Pasadas -Bloque {
            New-IndiceDisco -Rutas $script:raiz -MinimoArchivoBytes 1MB
        }
        Write-Host ('  New-IndiceDisco                          : ' + (Format-Seg $tIndice) +
                    '  (' + ('{0:N2}' -f ($tIndice * 1e6 / $script:rutas.Length)) + ' µs por archivo)')
    } else {
        Write-Host '  New-IndiceDisco: el núcleo no está cargado, se salta.' -ForegroundColor DarkYellow
    }

    # El recorrido que [VEL-02] necesitaria: ademas de los totales por
    # carpeta, UNA ENTRADA POR ARCHIVO. Hoy New-IndiceDisco no la guarda
    # -guarda solo los archivos por encima de un umbral- y sin ella no se
    # puede aplicar una baja del diario, porque no se sabe cuanto medía lo
    # que se ha borrado. La enumeracion va DENTRO de la medida: si se deja
    # fuera se esta midiendo rellenar un diccionario, no recorrer un disco.
    $tTabla = Measure-Mejor -Pasadas $Pasadas -Bloque {
        $d = [Collections.Generic.Dictionary[string, object]]::new(30000, [StringComparer]::OrdinalIgnoreCase)
        foreach ($p in [IO.Directory]::EnumerateFiles($script:raiz, '*', [IO.SearchOption]::AllDirectories)) {
            $d[$p] = [IO.FileInfo]::new($p).Length
        }
        $d.Count
    }
    Write-Host ('  recorrido + tabla por archivo            : ' + (Format-Seg $tTabla) +
                '  (' + ('{0:N2}' -f ($tTabla * 1e6 / $script:rutas.Length)) + ' µs por archivo)')

    # El coste de una sola alta del diario: preguntar el tamaño por ruta.
    $tStat = Measure-Mejor -Pasadas $Pasadas -Bloque {
        $s = 0.0
        foreach ($p in $script:rutas) { $s += [IO.FileInfo]::new($p).Length }
        $s
    }
    Write-Host ('  preguntar el tamaño por ruta             : ' +
                ('{0:N2}' -f ($tStat * 1e6 / $script:rutas.Length)) + ' µs por archivo')

    # Linealidad: la mitad del arbol.
    $script:mitad = $script:rutas[0..([int]($script:rutas.Length / 2) - 1)]
    $tMitad = Measure-Mejor -Pasadas $Pasadas -Bloque {
        $d = [Collections.Generic.Dictionary[string, object]]::new(30000, [StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $script:mitad) { $d[$p] = [IO.FileInfo]::new($p).Length }
        $d.Count
    }
    $tEntero = Measure-Mejor -Pasadas $Pasadas -Bloque {
        $d = [Collections.Generic.Dictionary[string, object]]::new(30000, [StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $script:rutas) { $d[$p] = [IO.FileInfo]::new($p).Length }
        $d.Count
    }
    $lineal = Test-EsLineal -UnidadesA $script:mitad.Length -SegundosA $tMitad -UnidadesB $script:rutas.Length -SegundosB $tEntero
    Write-Host ('  la mitad del árbol                       : ' + (Format-Seg $tMitad) +
                '  (' + ('{0:N2}' -f ($tMitad * 1e6 / $script:mitad.Length)) + ' µs por archivo)')
    Write-Host ('  el árbol entero, mismo trabajo           : ' + (Format-Seg $tEntero) +
                '  (' + ('{0:N2}' -f ($tEntero * 1e6 / $script:rutas.Length)) + ' µs por archivo)')
    if ($lineal) {
        Write-Host '  → la relación es lineal: se puede extrapolar a un millón.' -ForegroundColor Green
    } else {
        Write-Host '  → NO es lineal. Cuidado con extrapolar este número.' -ForegroundColor Red
    }

    return [pscustomobject]@{
        Archivos      = $script:rutas.Length
        Indice        = $tIndice
        Tabla         = $tTabla
        MicrosStat    = ($tStat * 1e6 / $script:rutas.Length)
        Lineal        = $lineal
    }
}

# ======================================================================
#  Principal
# ======================================================================

if (-not (Test-Path -LiteralPath $Carpeta)) {
    New-Item -ItemType Directory -Force -Path $Carpeta | Out-Null
}

Write-Host ''
Write-Host 'Banco de [VEL-02] — ¿compensa el índice incremental?' -ForegroundColor White
Write-Host ('PowerShell ' + $PSVersionTable.PSVersion + ' sobre ' + [Environment]::OSVersion.Platform)
Write-Host ('Carpeta de trabajo (lo único que se toca): ' + $Carpeta)
Write-Host ('Cada medida se repite ' + $Pasadas + ' veces y se guarda la mejor.')

$resRecorrido = $null
$resPersist   = $null
$resAplicar   = $null
$resUsn       = $null

if ($Bloque -eq 'Todo' -or $Bloque -eq 'Recorrido') {
    if (-not $SinRecorrido) {
        # El nucleo se carga AQUI, en ambito de guion, igual que hace
        # Cachivache.ps1. Indice.ps1 necesita Test-Cancelacion y
        # Set-Progreso (Progreso.ps1), Get-RutaCorta (Format.ps1) y
        # Test-EsEnlace (FileSystem.ps1); sin los tres, New-IndiceDisco
        # muere en la primera llamada.
        $raizRepo = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        $nucleo = @('Progreso.ps1', 'Format.ps1', 'FileSystem.ps1', 'Indice.ps1')
        $faltan = @($nucleo | Where-Object { -not (Test-Path -LiteralPath (Join-Path $raizRepo (Join-Path 'src/Core' $_))) })
        if ($faltan.Count -eq 0) {
            foreach ($archivoNucleo in $nucleo) { . (Join-Path $raizRepo (Join-Path 'src/Core' $archivoNucleo)) }
        }
        $resRecorrido = Invoke-BancoRecorrido -Carpeta $Carpeta -Archivos $ArchivosReales -Pasadas $Pasadas
    }
}
if ($Bloque -eq 'Todo' -or $Bloque -eq 'Persistencia') {
    $resPersist = Invoke-BancoPersistencia -Carpeta $Carpeta -Tamanos $Tamanos -Pasadas $Pasadas -TopeJson $TopeJson -ForzarJson:$ForzarJson
}
if ($Bloque -eq 'Todo' -or $Bloque -eq 'Aplicar') {
    $resAplicar = Invoke-BancoAplicar -Entradas 1000000 -Cambios $Cambios -Pasadas $Pasadas
}
if ($Bloque -eq 'Todo' -or $Bloque -eq 'Usn') {
    $resUsn = Invoke-BancoUsn -Pasadas $Pasadas
}

# --- El numero, que es el entregable ---------------------------------
if ($null -ne $resPersist -and $null -ne $resAplicar -and $null -ne $resUsn) {
    Write-Titulo 'EL PUNTO DE EQUILIBRIO'

    $grande = $resPersist | Where-Object { $_.Entradas -eq ($Tamanos | Sort-Object -Descending | Select-Object -First 1) } | Select-Object -First 1
    $carga = $grande.BinC
    if ($null -eq $carga) { $carga = $grande.TsvD }

    # La linea base del recorrido. Si el bloque 4 no ha corrido, se usa el
    # numero de [VEL-01]: 5 s por millon de archivos con New-IndiceDisco.
    $recorrido = 5.0
    $origenRecorrido = 'docs/VEL-01-MEDICION.md (extrapolación)'
    if ($null -ne $resRecorrido -and $null -ne $resRecorrido.Indice) {
        $recorrido = $resRecorrido.Indice * (1000000.0 / $resRecorrido.Archivos)
        $origenRecorrido = 'medido en esta pasada y extrapolado'
    }

    $usnGrande = $resUsn.Medidas | Select-Object -Last 1
    $microsAplicar = ($resAplicar.Medidas | Select-Object -Last 1).Micros
    $microsStat = 3.0
    if ($null -ne $resRecorrido) { $microsStat = $resRecorrido.MicrosStat }

    $porRegistro = $usnGrande.MicrosFuncion + $resUsn.MicrosResolver + $microsAplicar + $microsStat

    $punto = Get-PuntoDeEquilibrio -SegundosRecorrido $recorrido -SegundosCarga $carga `
        -MicrosPorRegistro $porRegistro -RegistrosPorArchivo $RegistrosPorArchivo

    Write-Host ''
    Write-Host ('  recorrer el disco entero (1.000.000)     : ' + ('{0,7:N2} s' -f $recorrido) + '   [' + $origenRecorrido + ']')
    Write-Host ('  cargar el índice guardado (1.000.000)    : ' + ('{0,7:N2} s' -f $carga))
    Write-Host ('  margen para el camino incremental        : ' + ('{0,7:N2} s' -f $punto.Margen))
    Write-Host ''
    Write-Host ('  parsear un registro USN                  : ' + ('{0,6:N2}' -f $usnGrande.MicrosFuncion) + ' µs')
    Write-Host ('  resolver su ruta                         : ' + ('{0,6:N2}' -f $resUsn.MicrosResolver) + ' µs')
    Write-Host ('  preguntar el tamaño al disco             : ' + ('{0,6:N2}' -f $microsStat) + ' µs')
    Write-Host ('  aplicarlo al índice y propagar           : ' + ('{0,6:N2}' -f $microsAplicar) + ' µs')
    Write-Host ('  TOTAL por registro del diario            : ' + ('{0,6:N2}' -f $porRegistro) + ' µs')
    Write-Host ''
    if ($punto.Compensa) {
        Write-Host ('  PUNTO DE EQUILIBRIO: ' + ('{0:N0}' -f $punto.Registros) + ' registros del diario') -ForegroundColor Green
        Write-Host ('  que a ' + $RegistrosPorArchivo + ' registros por archivo tocado son ~' +
                    ('{0:N0}' -f $punto.Archivos) + ' archivos cambiados.') -ForegroundColor Green
    } else {
        Write-Host '  NO COMPENSA NUNCA: cargar el índice ya cuesta más que recorrer el disco.' -ForegroundColor Red
    }
}

Write-Host ''
Write-Host ('Los archivos de trabajo se quedan en ' + $Carpeta + '. El banco no borra nada.')
Write-Host ''
