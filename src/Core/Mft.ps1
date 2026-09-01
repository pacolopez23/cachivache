<#
.SYNOPSIS
    Lectura de la tabla maestra de archivos de NTFS. Las piezas puras del
    camino rapido de [VEL-01].

.DESCRIPTION
    WizTree es cuarenta veces mas rapido que WinDirStat por una sola razon:
    no recorre carpetas. Abre el volumen en crudo y lee la MFT -la tabla
    maestra-, que es un archivo mas del disco donde NTFS guarda un registro
    de tamanyo fijo por cada archivo y cada carpeta que existen. Ahi estan
    el nombre, el padre y el tamanyo de todo, seguidos, sin una sola
    llamada por carpeta.

    -------------------------------------------------------------------
    LO QUE ESTE ARCHIVO ES, Y LO QUE NO ES

    Este archivo NO engancha con nada todavia. Es deliberado. La pregunta
    que [VEL-01] tenia sin responder no era "se puede escribir", sino
    "compensa en PowerShell": WizTree esta en C++, y parsear un millon de
    registros binarios desde un lenguaje interpretado puede salir mas caro
    que el recorrido que ya hay. La respuesta medida esta en
    docs/VEL-01-MEDICION.md, y hay que leerla ANTES de engancharlo.

    Asi que aqui hay tres funciones PURAS -decidir si se puede, entender el
    sector de arranque, entender un registro- que se prueban enteras sin
    Windows, y UNA que toca el disco y que no se ha podido ejecutar en
    ningun sitio.

    -------------------------------------------------------------------
    POR QUE TODO ESTO ES PURO SOBRE ARRAYS DE BYTES

    Porque es la unica forma de probarlo. Aqui no hay NTFS, no hay volumen
    que abrir y no hay privilegios que pedir. Un parseador binario que solo
    se pueda ejercitar contra un disco real seria, en este proyecto,
    exactamente lo mismo que un mecanismo de XAML: codigo que nadie ha
    visto funcionar. Recibiendo bytes se le puede construir a mano un
    sector de arranque y un registro sinteticos, y entonces el parseo queda
    probado de verdad. Ver tests/Mft.Tests.ps1.

    -------------------------------------------------------------------
    EL RETROCESO NO ES UN EXTRA, ES EL CAMINO NORMAL

    La tabla maestra es de NTFS, exige administrador y no existe en una
    llave USB en exFAT. O sea que el recorrido por carpetas de
    Get-ElementosDelArbol no desaparece: sigue siendo el camino por
    defecto, y esto -si algun dia compensa- seria un atajo para el caso
    bueno. Por eso Test-PuedeLeerTablaMaestra devuelve el MOTIVO por el que
    no se puede y no un booleano: un "no" que no dice por que obliga a
    quien lo recibe a inventarse la explicacion.

    Y por eso Read-TablaMaestra devuelve $null ante cualquier problema en
    vez de lanzar. Quien la llame tiene que poder escribir "si no hay tabla,
    recorro carpetas" sin un try alrededor.
#>

function Test-PuedeLeerTablaMaestra {
    <#
    .SYNOPSIS
        Motivo por el que NO se puede leer la tabla maestra de una unidad,
        o cadena vacia si se puede. Decision pura.

    .DESCRIPTION
        No consulta nada: recibe los tres datos y decide. Quien los consulta
        es el llamante, que en Windows los tiene ya -DriveFormat y DriveType
        de System.IO.DriveInfo, y el grupo de administradores del testigo
        actual-, y aqui llegan como texto para poder probar las nueve
        combinaciones sin un disco delante.

    .PARAMETER SistemaArchivos
        'NTFS', 'exFAT', 'FAT32'... Tal cual lo devuelve DriveFormat.

    .PARAMETER TipoUnidad
        El nombre de System.IO.DriveType: 'Fixed', 'Removable', 'Network',
        'CDRom', 'Ram', 'Unknown', 'NoRootDirectory'.

    .PARAMETER EsAdministrador
        Si el proceso corre elevado. Abrir \\.\C: en crudo lo exige: sin
        ello CreateFile falla con acceso denegado.

    .NOTES
        EL ORDEN DE LAS COMPROBACIONES NO ES CASUAL. Se mira primero lo que
        el usuario NO puede cambiar -el tipo de unidad, el sistema de
        archivos- y lo ultimo lo unico que si puede -reabrir como
        administrador-. Al reves, a quien analiza una carpeta de red se le
        estaria diciendo "reinicia el programa como administrador" para algo
        que seguiria sin funcionar despues de hacerlo. Un consejo que no
        arregla nada es peor que no dar ninguno.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $SistemaArchivos,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $TipoUnidad,
        [Parameter(Mandatory)] [AllowNull()] [bool] $EsAdministrador
    )

    # Sin datos NO se responde que si. El sintoma de "no he podido
    # averiguar el sistema de archivos" es identico al de "es NTFS" si
    # nadie los distingue, y esta funcion decide si se abre un volumen en
    # crudo: la duda tiene que caer siempre del lado del recorrido normal.
    if ([string]::IsNullOrWhiteSpace($TipoUnidad) -or [string]::IsNullOrWhiteSpace($SistemaArchivos)) {
        return 'No se han podido leer los datos de la unidad, así que se recorren las carpetas.'
    }

    $tipo = $TipoUnidad.Trim()
    if ($tipo -eq 'Network') {
        return 'La tabla maestra está en el disco y esta unidad es de red: no hay disco que abrir.'
    }
    # Fija o extraible, y nada mas. Un CD no tiene MFT, y un disco RAM
    # tampoco. Se comprueba por lista blanca y no descartando la de red:
    # asi un tipo nuevo cae del lado seguro sin que nadie lo recuerde.
    if ($tipo -ne 'Fixed' -and $tipo -ne 'Removable') {
        return ('La tabla maestra solo se lee en discos fijos o extraíbles, y esta unidad es de tipo {0}.' -f $tipo)
    }

    $formato = $SistemaArchivos.Trim()
    if ($formato -ne 'NTFS') {
        return ('La tabla maestra es de NTFS y esta unidad está formateada en {0}.' -f $formato)
    }

    if (-not $EsAdministrador) {
        return 'Leer la tabla maestra exige permisos de administrador, y el programa no los tiene.'
    }

    return ''
}

function Get-DatosArranqueNtfs {
    <#
    .SYNOPSIS
        Entiende el sector de arranque de un volumen NTFS. Devuelve $null
        si no lo es. Calculo puro sobre bytes.

    .DESCRIPTION
        El primer sector del volumen lleva el bloque de parametros del BIOS,
        y de ahi salen los cuatro numeros sin los cuales no se puede leer
        nada mas: cuanto mide un sector, cuantos sectores tiene un cluster,
        cuanto mide un registro de la MFT y en que cluster empieza la MFT.

        Los desplazamientos son los del formato, y estan escritos en
        hexadecimal a proposito: asi se pueden contrastar con cualquier
        documentacion del formato sin traducirlos mentalmente.

    .NOTES
        DEVOLVER $null Y NO NUMEROS ABSURDOS ES EL PUNTO DE ESTA FUNCION.
        Un sector que no es de NTFS -o que es basura porque la lectura
        fallo a medias- da igualmente numeros al interpretarlo: 40.000
        bytes por sector, un cluster de MFT en la posicion 2^60. Con esos
        numeros el llamante buscaria fuera del disco y el fallo aparecerian
        muy lejos de aqui. Por eso se comprueban la firma Y los rangos, y
        cualquier cosa rara sale por el mismo sitio: $null, que significa
        "esto no es un volumen NTFS que yo sepa leer".
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes
    )

    if ($null -eq $Bytes -or $Bytes.Length -lt 512) {
        Write-Verbose 'El sector de arranque no llega a 512 bytes.'
        return $null
    }

    # La firma "NTFS    " -cuatro letras y cuatro espacios- en el
    # desplazamiento 3, justo detras del salto de tres bytes. Se compara
    # byte a byte y no convirtiendo a texto: un volumen ajeno puede llevar
    # ahi cualquier secuencia, y decodificarla podria dar una cadena que
    # se parezca lo bastante.
    $firma = @(0x4E, 0x54, 0x46, 0x53, 0x20, 0x20, 0x20, 0x20)
    for ($i = 0; $i -lt 8; $i++) {
        if ($Bytes[3 + $i] -ne $firma[$i]) {
            Write-Verbose 'El sector de arranque no lleva la firma de NTFS.'
            return $null
        }
    }

    $bytesPorSector = [BitConverter]::ToUInt16($Bytes, 0x0B)
    # Potencia de dos entre 256 y 8192. Fuera de ahi el sector no es un
    # sector: es basura que casualmente empieza por NTFS.
    if ($bytesPorSector -lt 256 -or $bytesPorSector -gt 8192 -or
        ($bytesPorSector -band ($bytesPorSector - 1)) -ne 0) {
        Write-Verbose 'El sector de arranque da un tamaño de sector imposible.'
        return $null
    }

    # Sectores por cluster. Si el byte pasa de 0x80 se lee como negativo, y
    # entonces son 2 elevado a su valor absoluto. Esa regla no es una
    # rareza teorica: es como Windows 10 en adelante describe los volumenes
    # con clusters de mas de 64 KB, y leerla como un entero sin signo daria
    # 249 sectores por cluster en vez de 128.
    $bruto = [int]$Bytes[0x0D]
    if ($bruto -gt 0x80) { $sectoresPorCluster = [int][Math]::Pow(2, 256 - $bruto) }
    else                 { $sectoresPorCluster = $bruto }
    if ($sectoresPorCluster -lt 1 -or $sectoresPorCluster -gt 65536) {
        Write-Verbose 'El sector de arranque da un tamaño de cluster imposible.'
        return $null
    }

    $bytesPorCluster = [double]$bytesPorSector * $sectoresPorCluster

    # Y la misma regla, otra vez, para el tamanyo del registro de la MFT:
    # positivo son clusters por registro; negativo son 2 elevado a su valor
    # absoluto, pero esta vez EN BYTES, no en clusters. La asimetria es del
    # formato, no de esta lectura, y es la clase de detalle que se copia
    # mal una vez y luego da registros de 1 GB.
    $brutoRegistro = [int]$Bytes[0x40]
    if ($brutoRegistro -gt 0x7F) { $bytesPorRegistro = [double][Math]::Pow(2, 256 - $brutoRegistro) }
    else                         { $bytesPorRegistro = [double]$brutoRegistro * $bytesPorCluster }
    if ($bytesPorRegistro -lt 256 -or $bytesPorRegistro -gt 65536) {
        Write-Verbose 'El sector de arranque da un tamaño de registro imposible.'
        return $null
    }

    # El cluster donde empieza la MFT y el total de sectores son de 64 bits.
    # Se leen en dos mitades para no depender de como convierte PowerShell
    # un UInt64 al operar con el: en 5.1 mezclar UInt64 con Int64 en una
    # expresion lanza mas veces de lo que parece. Ver docs/RELEVO.md.
    $clusterMft    = Get-EnteroLargoLe -Bytes $Bytes -Desde 0x30
    $totalSectores = Get-EnteroLargoLe -Bytes $Bytes -Desde 0x28
    if ($clusterMft -le 0) {
        Write-Verbose 'El sector de arranque no dice dónde empieza la tabla maestra.'
        return $null
    }

    return [pscustomobject]@{
        BytesPorSector     = [int]$bytesPorSector
        SectoresPorCluster = [int]$sectoresPorCluster
        BytesPorCluster    = $bytesPorCluster
        BytesPorRegistro   = $bytesPorRegistro
        ClusterMft         = $clusterMft
        TotalSectores      = $totalSectores
    }
}

function Get-EnteroLargoLe {
    <#
    .SYNOPSIS
        Los 8 bytes de un entero sin signo, en el orden de Intel, como
        double. Calculo puro.

    .DESCRIPTION
        Se devuelve double y no UInt64 aposta. Los tres numeros grandes que
        salen de aqui -el cluster de la MFT, el total de sectores, el
        tamanyo de un archivo- se van a multiplicar y sumar despues, y en
        PowerShell 5.1 operar con UInt64 acaba en conversiones que lanzan.
        El resto del programa ya usa double para los bytes por lo mismo:
        ver Bytes en el indice de disco.

        Un double representa exactamente los enteros hasta 2^53, o sea 9
        petabytes contados en bytes. El dia que eso se quede corto, este
        no sera el problema.

    .NOTES
        Se leen dos mitades de 32 bits en vez de un ToUInt64 porque el
        resultado de ToUInt64 es UInt64, y basta con restarle algo o
        compararlo con un literal para toparse con la conversion que se
        queria evitar.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes,
        [Parameter(Mandatory)] [int] $Desde
    )

    if ($null -eq $Bytes -or $Desde -lt 0 -or ($Desde + 8) -gt $Bytes.Length) { return 0.0 }

    $bajo = [double][BitConverter]::ToUInt32($Bytes, $Desde)
    $alto = [double][BitConverter]::ToUInt32($Bytes, $Desde + 4)
    return ($alto * 4294967296.0) + $bajo
}

function Get-RegistroMft {
    <#
    .SYNOPSIS
        Entiende UN registro de la tabla maestra. Devuelve $null si los
        bytes no son un registro. Calculo puro.

    .DESCRIPTION
        Un registro empieza por "FILE" y lleva, detras de una cabecera fija,
        una lista de atributos de longitud variable. De ahi salen las cinco
        cosas que hacen falta para dibujar un disco entero:

          * Nombre           - del atributo $FILE_NAME (0x30).
          * ReferenciaPadre  - del mismo atributo. Es el numero de registro
                               de la carpeta que lo contiene, y es lo que
                               permite reconstruir el arbol despues sin
                               volver a tocar el disco.
          * EsCarpeta        - de las banderas de la cabecera.
          * EnUso            - de las mismas banderas. Un registro borrado
                               sigue ahi con su nombre y su tamanyo, y
                               contarlo seria ensenyar espacio que no
                               existe.
          * Bytes            - del atributo $DATA (0x80).

    .NOTES
        POR QUE SE APLICAN LAS CORRECCIONES DE SECUENCIA, Y POR QUE UN
        REGISTRO QUE NO CUADRA SE TIRA.

        NTFS pisa los DOS ULTIMOS BYTES DE CADA SECTOR de un registro con
        un numero de secuencia, y guarda los originales en una tablita al
        principio. Es su forma de detectar una escritura que se quedo a
        medias: si los dos ultimos bytes de cada sector no llevan todos el
        mismo numero, el registro esta roto.

        Sin deshacer eso, un registro de 1 KB en sectores de 512 tiene DOS
        BYTES CORROMPIDOS en mitad de los datos, justo en el 510. Y no
        falla ruidosamente: falla en el nombre de un archivo de cada
        tantos, o en el byte alto de un tamanyo. La clase de error que sale
        en una captura de pantalla del usuario y no en ninguna prueba.

        Por eso ademas, si la comprobacion no cuadra, se devuelve $null en
        vez de seguir: un registro que NTFS mismo considera roto no es un
        archivo del que se pueda decir nada.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes
    )

    # 42 bytes es la cabecera mas corta que puede existir y aun apuntar a
    # un atributo. Por debajo de eso no hay nada que leer.
    if ($null -eq $Bytes -or $Bytes.Length -lt 42) { return $null }

    if ($Bytes[0] -ne 0x46 -or $Bytes[1] -ne 0x49 -or
        $Bytes[2] -ne 0x4C -or $Bytes[3] -ne 0x45) {
        # No empieza por "FILE". Un hueco de la MFT lleva "BAAD" o ceros, y
        # los dos son normales: la tabla tiene registros sin usar.
        return $null
    }

    $largo = $Bytes.Length

    # --- Correcciones de secuencia -----------------------------------
    # Se trabaja sobre una COPIA. Deshacer las correcciones es escribir en
    # el array, y el array es del llamante: en el lector de verdad viene de
    # un buffer grande que se reutiliza, asi que pisarlo seria corromper
    # los registros siguientes.
    $b = $Bytes.Clone()
    $desplazamientoUsa = [BitConverter]::ToUInt16($b, 0x04)
    $entradasUsa       = [BitConverter]::ToUInt16($b, 0x06)

    if ($entradasUsa -lt 2 -or $desplazamientoUsa -lt 42 -or
        ($desplazamientoUsa + ($entradasUsa * 2)) -gt $largo) {
        return $null
    }

    $sectores = $entradasUsa - 1
    if ($sectores -le 0 -or ($largo % $sectores) -ne 0) { return $null }
    $bytesPorSector = [int]($largo / $sectores)
    if ($bytesPorSector -lt 4) { return $null }

    $marcaBaja = $b[$desplazamientoUsa]
    $marcaAlta = $b[$desplazamientoUsa + 1]
    for ($s = 0; $s -lt $sectores; $s++) {
        $fin = (($s + 1) * $bytesPorSector) - 2
        if ($b[$fin] -ne $marcaBaja -or $b[$fin + 1] -ne $marcaAlta) {
            Write-Verbose 'Un registro de la tabla maestra no cuadra con su marca de secuencia.'
            return $null
        }
        $origen = $desplazamientoUsa + 2 + ($s * 2)
        $b[$fin]     = $b[$origen]
        $b[$fin + 1] = $b[$origen + 1]
    }

    # --- Cabecera ----------------------------------------------------
    $banderas   = [BitConverter]::ToUInt16($b, 0x16)
    $enUso      = ($banderas -band 0x0001) -ne 0
    $esCarpeta  = ($banderas -band 0x0002) -ne 0
    $primerAtributo = [BitConverter]::ToUInt16($b, 0x14)

    $nombre         = ''
    $espacioNombre  = -1
    $referenciaPadre = 0.0
    $bytesDatos     = 0.0
    $bytesNombre    = 0.0
    $vistoDatos     = $false

    # --- Atributos ---------------------------------------------------
    # Bucle acotado y con todos los limites comprobados a mano. Estos bytes
    # vienen de un disco que puede estar danyado o formateado por otro
    # sistema: una longitud de atributo de cero deja el bucle dando vueltas
    # para siempre, y una fuera de rango lanza una excepcion de indice a
    # 300.000 registros de haber empezado.
    $pos = [int]$primerAtributo
    $vueltas = 0
    while ($pos -ge 42 -and ($pos + 16) -le $largo -and $vueltas -lt 128) {
        $vueltas++
        $tipo = [BitConverter]::ToUInt32($b, $pos)
        # LA "L" NO ES DECORACION. En PowerShell el literal 0xFFFFFFFF es
        # un Int32 y vale MENOS UNO, asi que comparar contra el un UInt32
        # da SIEMPRE falso: el fin de la lista de atributos no se
        # reconocia nunca y el bucle seguia leyendo basura hasta agotar el
        # tope de vueltas. No lanzaba, no avisaba, y los tamanyos salian
        # mal de vez en cuando. Con la L el literal es Int64 y la
        # comparacion se hace en 64 bits, que es donde los dos numeros
        # significan lo mismo.
        if ($tipo -eq 0xFFFFFFFFL) { break }

        $longitud = [int][BitConverter]::ToUInt32($b, $pos + 4)
        # Las dos comprobaciones van SEPARADAS aposta, aunque las dos
        # acaben igual. Juntas en un solo if no se podia romper una sin
        # romper la otra, y una invariante que no se puede ver fallar sola
        # no se sabe si protege las dos cosas o solo una.
        #
        # Y las dos devuelven $null en vez de cortar el bucle y seguir con
        # lo leido hasta ahi, por el mismo criterio que la marca de
        # secuencia: un atributo que mide cero -o que se sale del
        # registro- significa que estos bytes no son el registro que dicen
        # ser, y de un registro asi no se puede afirmar nada. Devolver un
        # objeto a medias seria peor: pasaria por un archivo de verdad.
        if ($longitud -le 0) { return $null }
        if (($pos + $longitud) -gt $largo) { return $null }

        $noResidente = $b[$pos + 8]

        if ($tipo -eq 0x30 -and $noResidente -eq 0) {
            # $FILE_NAME. Siempre es residente: NTFS lo garantiza, y si
            # alguna vez no lo fuera no habria nombre que leer aqui.
            $desplazamientoValor = [BitConverter]::ToUInt16($b, $pos + 0x14)
            $valor = $pos + $desplazamientoValor
            if (($valor + 0x42) -le $largo) {
                $letras = [int]$b[$valor + 0x40]
                $espacio = [int]$b[$valor + 0x41]
                if ($letras -gt 0 -and ($valor + 0x42 + ($letras * 2)) -le $largo) {
                    # UN ARCHIVO PUEDE TENER VARIOS $FILE_NAME: el largo de
                    # Windows y el corto de MS-DOS ("PROGRA~1"). Se elige
                    # por espacio de nombres y no por el primero que
                    # aparezca, porque el orden no esta garantizado y
                    # ensenyar "PROGRA~1" en el mapa del disco seria
                    # ensenyar un nombre que el usuario no reconoce.
                    #   0 POSIX  1 Win32  2 DOS  3 Win32 y DOS a la vez
                    $prioridad = 0
                    if     ($espacio -eq 1) { $prioridad = 3 }
                    elseif ($espacio -eq 3) { $prioridad = 2 }
                    elseif ($espacio -eq 0) { $prioridad = 1 }
                    if ($prioridad -gt $espacioNombre) {
                        $espacioNombre = $prioridad
                        $nombre = [Text.Encoding]::Unicode.GetString($b, $valor + 0x42, $letras * 2)
                        $referenciaPadre = Get-ReferenciaMft -Bytes $b -Desde $valor
                        # El tamanyo que guarda $FILE_NAME es de reserva:
                        # NTFS solo lo actualiza al cerrar el archivo, asi
                        # que puede estar viejo. Solo se usa si no hay $DATA.
                        $bytesNombre = Get-EnteroLargoLe -Bytes $b -Desde ($valor + 0x30)
                    }
                }
            }
        } elseif ($tipo -eq 0x80 -and $b[$pos + 9] -eq 0) {
            # $DATA, y sin nombre: el flujo principal. Los flujos alternos
            # -los que llevan nombre- son bytes de verdad en el disco, pero
            # no son el tamanyo del archivo, y sumarlos aqui haria que un
            # archivo con la marca de "descargado de internet" pesara mas
            # que su contenido.
            if ($noResidente -eq 0) {
                $bytesDatos = [double][BitConverter]::ToUInt32($b, $pos + 0x10)
            } elseif (($pos + 0x38) -le $largo) {
                # No residente: el tamanyo REAL, no el reservado. Un archivo
                # de 1 byte reserva un cluster entero, y ensenyar 4 KB por
                # cada uno inflaria el total del disco.
                $bytesDatos = Get-EnteroLargoLe -Bytes $b -Desde ($pos + 0x30)
            }
            $vistoDatos = $true
        }

        $pos += $longitud
    }

    if (-not $vistoDatos) { $bytesDatos = $bytesNombre }
    # Una carpeta no ocupa bytes de datos: lo que cuelga de ella se cuenta
    # en sus hijos, y sumar aqui su indice seria contar dos veces.
    if ($esCarpeta) { $bytesDatos = 0.0 }

    return [pscustomobject]@{
        Nombre          = $nombre
        ReferenciaPadre = $referenciaPadre
        EsCarpeta       = $esCarpeta
        EnUso           = $enUso
        Bytes           = $bytesDatos
    }
}

function Get-ReferenciaMft {
    <#
    .SYNOPSIS
        El numero de registro de una referencia de 8 bytes de NTFS.
        Calculo puro.

    .DESCRIPTION
        Una referencia de archivo son 48 bits de numero de registro y 16 de
        numero de secuencia. Los de secuencia HAY QUE QUITARLOS: sirven
        para detectar referencias a un registro que ya se reutilizo, y
        dejarlos dentro convierte "la carpeta 5" en "la carpeta
        281474976710661", que no casa con ningun padre y deja el archivo
        colgando de la nada.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes,
        [Parameter(Mandatory)] [int] $Desde
    )

    if ($null -eq $Bytes -or $Desde -lt 0 -or ($Desde + 6) -gt $Bytes.Length) { return 0.0 }

    $bajo  = [double][BitConverter]::ToUInt32($Bytes, $Desde)
    $medio = [double][BitConverter]::ToUInt16($Bytes, $Desde + 4)
    return ($medio * 4294967296.0) + $bajo
}

function Read-TablaMaestra {
    <#
    .SYNOPSIS
        Abre un volumen en crudo y devuelve los registros de la tabla
        maestra. NO VERIFICADO: solo se puede ejecutar en Windows.

    .DESCRIPTION
        ESTA FUNCION NO SE HA EJECUTADO NUNCA. Es la unica parte de este
        archivo que toca el disco, y en el entorno donde se escribio no hay
        NTFS, ni volumen que abrir, ni privilegios que pedir. Las tres
        funciones puras de arriba estan probadas byte a byte; esta no, y
        hasta que alguien la ejecute en un Windows real hay que tratarla
        como una hipotesis escrita en PowerShell.

        Esta aparte justamente por eso: para que la frontera entre lo
        probado y lo no probado sea un limite de funcion y no una linea
        perdida en mitad de otra cosa.

        NUNCA LANZA. Ante cualquier problema -no es Windows, no hay
        permisos, el volumen no es NTFS, la lectura falla a medias- devuelve
        $null, y quien llama cae al recorrido por carpetas de siempre. Un
        camino rapido que puede tirar el analisis entero no es un camino
        rapido: es un riesgo.

    .PARAMETER Unidad
        'C:' -sin barra final-. Se compone \\.\C:, que es como se abre un
        volumen en crudo en Windows.

    .PARAMETER MaximoRegistros
        Tope de registros a leer. Existe porque la MFT de un disco con uso
        son cientos de miles de registros y este camino esta sin medir en
        un disco de verdad: leerla entera a ciegas es justo lo que no se
        debe hacer la primera vez que se ejecuta algo.

    .NOTES
        LO QUE FALTA, Y HAY QUE DECIRLO CLARO: aqui se leen los registros
        SEGUIDOS desde donde empieza la MFT, y la MFT puede estar
        FRAGMENTADA. Leerla entera y bien exige interpretar la lista de
        tramos del atributo $DATA de su registro cero, que es codigo que
        tampoco se podria probar aqui. Asi que esto lee el primer trozo y
        nada mas. Ver docs/VEL-01-MEDICION.md.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Unidad,
        [int] $MaximoRegistros = 100000
    )

    # $IsWindows NO EXISTE en PowerShell 5.1: vale $null, y "-not $IsWindows"
    # seria verdadero justo en Windows. Ver docs/RELEVO.md.
    $esWindows = $IsWindows -or ($null -eq $IsWindows)
    if (-not $esWindows) {
        Write-Verbose 'La tabla maestra solo se puede leer en Windows.'
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($Unidad)) { return $null }

    $letra = $Unidad.Trim().TrimEnd([char]'\', [char]'/')
    if ($letra -notmatch '^[A-Za-z]:$') {
        Write-Verbose 'Hace falta una letra de unidad, por ejemplo C: sin barra.'
        return $null
    }

    $flujo = $null
    try {
        # FileShare ReadWrite y no None: el volumen del sistema lo tiene
        # abierto Windows entero. Pedir acceso exclusivo fallaria siempre.
        $flujo = [IO.FileStream]::new(
            ('\\.\' + $letra), [IO.FileMode]::Open, [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite)

        $arranque = [byte[]]::new(512)
        if ($flujo.Read($arranque, 0, 512) -ne 512) { return $null }

        $datos = Get-DatosArranqueNtfs -Bytes $arranque
        if ($null -eq $datos) { return $null }

        $tamanoRegistro = [int]$datos.BytesPorRegistro
        $inicio = $datos.ClusterMft * $datos.BytesPorCluster
        [void]$flujo.Seek($inicio, [IO.SeekOrigin]::Begin)

        # Se lee por bloques grandes y no registro a registro: una lectura
        # de 1 KB por archivo son un millon de llamadas al sistema, y ese
        # coste se comeria entera la ventaja de no recorrer carpetas.
        $porBloque = [Math]::Max(1, [int](1MB / $tamanoRegistro))
        $bloque = [byte[]]::new($porBloque * $tamanoRegistro)
        $registros = [Collections.Generic.List[object]]::new()

        while ($registros.Count -lt $MaximoRegistros) {
            $leidos = $flujo.Read($bloque, 0, $bloque.Length)
            if ($leidos -lt $tamanoRegistro) { break }

            $cuantos = [int]($leidos / $tamanoRegistro)
            for ($i = 0; $i -lt $cuantos; $i++) {
                $uno = [byte[]]::new($tamanoRegistro)
                [Array]::Copy($bloque, $i * $tamanoRegistro, $uno, 0, $tamanoRegistro)
                $registro = Get-RegistroMft -Bytes $uno
                # Los huecos y los registros borrados no son un error: la
                # MFT esta llena de los dos.
                if ($null -ne $registro -and $registro.EnUso) { $registros.Add($registro) }
                if ($registros.Count -ge $MaximoRegistros) { break }
            }
        }

        return $registros
    } catch {
        # Acceso denegado sin elevacion, unidad que no existe, volumen que
        # se desconecta a media lectura. Ninguno de esos casos justifica
        # tirar el analisis: se devuelve $null y se recorren las carpetas.
        Write-Verbose ("No se ha podido leer la tabla maestra de {0}: {1}" -f $Unidad, $_.Exception.Message)
        return $null
    } finally {
        if ($null -ne $flujo) { $flujo.Dispose() }
    }
}
