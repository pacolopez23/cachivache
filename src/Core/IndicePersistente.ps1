<#
.SYNOPSIS
    El índice de espacio, guardado en disco y vuelto a leer. Persistencia
    binaria para [VEL-02].

.DESCRIPTION
    LA DECISION QUE MANDA SOBRE TODAS LAS DEMAS, y esta escrita aqui
    arriba porque de ella depende que este archivo pueda existir:

        EL INDICE GUARDADO SIRVE PARA PINTAR EL MAPA,
        NUNCA PARA DECIDIR QUE SE BORRA.

    Cachivache borra desde lo que acaba de ver con sus propios ojos en
    ESTA ejecucion: el recorrido de New-IndiceDisco y la revalidacion de
    la guardia. Si lo que hay en este archivo se equivoca -porque el disco
    cambio, porque alguien apago el diario de cambios, porque el archivo
    se escribio a medias-, el peor caso posible es un rectangulo mal
    dibujado en el mapa de arbol. Nunca un archivo borrado por error.

    De ahi que aqui NO haya ni una funcion que devuelva candidatos, ni
    nada que se les parezca. Lo que sale de aqui son totales para dibujar.
    Ver el apartado "Que pasa cuando el indice guardado esta obsoleto o
    corrupto" de docs/VEL-02-MEDICION.md.

    -------------------------------------------------------------------
    POR QUE BINARIO, Y POR QUE TRES TABLAS

    No es una preferencia: esta medido en docs/VEL-02-MEDICION.md, sobre
    indices sinteticos de hasta un millon de entradas.

      * JSON esta DESCARTADO. No es que sea lento: con un millon de
        entradas ConvertTo-Json no termina -el proceso muere por memoria
        sin llegar a lanzar, asi que no hay catch que valga-. A 100.000
        entradas si termina, y extrapolado da 5,3 s de guardado y 9,5 s
        de carga: los dos por encima de los 5,7 s del recorrido completo
        que se pretendia evitar.
      * CSV tarda seis veces mas que el binario en cargar.
      * Binario con BinaryWriter/BinaryReader carga un millon de entradas
        en 1,04 s. Es el unico formato que deja margen.

    Y se leen a DICCIONARIO, no a pscustomobject. El mismo archivo leido a
    objetos de PowerShell cuesta DOCE VECES mas (12,38 s contra 1,04 s).
    Componer un millon de PSCustomObject cuesta segundos por si solo, que
    es el mismo hallazgo de [VEL-01] visto desde el otro lado. El indice
    no necesita objetos: necesita poder contestar "cuanto media esto".

    Se guardan TRES tablas y no una:

      1. Los archivos.
      2. Las carpetas CON SUS TOTALES YA SUMADOS. Si solo se guardaran los
         archivos, al cargar habria que volver a sumar el millon de
         entradas para reconstruir los totales, y eso cuesta 6 s: MAS que
         recorrer el disco entero. La carga barata dejaria de serlo.
      3. La referencia de carpeta (el numero de referencia de NTFS) a su
         ruta. El registro del diario de cambios trae la referencia del
         padre, no la ruta; sin esta tabla hay que reconstruirla.

    -------------------------------------------------------------------
    LO QUE CUESTA DE VERDAD ESTA IMPLEMENTACION, QUE NO ES LO MEDIDO

    Hay que decirlo aqui porque la diferencia importa. Medido en este
    mismo entorno (Linux, PowerShell 7):

        10.000 entradas    guardar 0,06-0,19 s   cargar 0,05-0,13 s
        100.000 entradas   guardar 0,38 s        cargar 0,50 s
        1.000.000 entradas                       cargar 6,51 s

    El banco de VEL-02 cargaba el millon en 1,04 s. La diferencia es real
    y tiene explicacion: alli se leia a UN diccionario plano, y aqui se
    devuelve un registro por entrada con los seis campos que produce
    New-IndiceDisco, porque la promesa es que quien lo consuma no note de
    donde vino. Construir un millon de esos registros son cinco segundos
    de interprete, y eso ya no cabe en el margen de VEL-02.

    Lo que hace que esto siga compensando es que EL MILLON DE ENTRADAS DE
    ARCHIVO NO EXISTE en el programa: New-IndiceDisco corta la lista en
    MaximoArchivos -20.000 por omision- subiendo el umbral sola. Un indice
    de verdad son unas 20.000 entradas de archivo y unas decenas de miles
    de carpetas, o sea decimas de segundo. La cifra del millon solo
    aparece si alguien sube ese tope, y entonces hay que volver a mirar
    esto: la salida seria construir cada entrada con un literal @{...} en
    vez de con asignaciones sueltas, que va 2,3 veces mas rapido pero
    obliga a fiarse del orden en que PowerShell evalua un literal.

    -------------------------------------------------------------------
    QUE PASA CUANDO EL ARCHIVO NO ES DE FIAR

    Un indice que miente es peor que no tener indice. Aqui la regla del
    proyecto es la de siempre: ANTE LA DUDA, NO AFIRMAR. Un archivo
    truncado, con basura dentro, de una version del formato que no se
    conoce, de cero bytes, o que directamente no esta, devuelve $null.
    Ninguna de estas funciones lanza por eso. Quien llama recorre el disco
    de nuevo y ya esta, que cuesta cinco segundos y desde fuera solo se
    nota en que esta vez tardo lo de siempre.

    -------------------------------------------------------------------
    EL FORMATO, BYTE A BYTE

    CABECERA (se lee sola, sin tocar el cuerpo):

        firma        8 bytes  "CACHIDX" + 0x00
        Version      int32    version del formato
        SerieVolumen cadena   numero de serie del volumen
        IdDiario     cadena   identificador del diario USN
        UsnCorte     int64    USN hasta donde se leyo
        Entradas     int32    cuantas entradas de ARCHIVO trae el cuerpo
        Suma         cadena   suma de comprobacion del cuerpo
        Escrito      int64    fecha de escritura (DateTime.ToBinary)

    CUERPO (desde ahi hasta el final del archivo):

        LongitudCuerpo int64  bytes del cuerpo, contando estos ocho
        Raices         int32 + n cadenas
        Bytes          double
        TotalArchivos  int32
        Compartidos    int32
        Inaccesibles   int32
        UmbralArchivo  double
        Carpetas       int32 + n x (Ruta, Nombre, Nivel, Bytes, Propios,
                                    Archivos, Ultimo)
        Archivos       int32 + n x (Ruta, Nombre, Carpeta, Extension,
                                    Bytes, Ultimo)
        Referencias    int32 + n x (uint64, Ruta)

    Tres detalles del formato que tienen su motivo:

    1. LongitudCuerpo va DENTRO del cuerpo, no en la cabecera. Los siete
       campos de la cabecera son un contrato compartido con quien la
       valida y no se tocan. Pero hace falta una forma de detectar un
       archivo truncado SIN leer el cuerpo -que es justo lo que Get-
       CabeceraIndice existe para no hacer-, y comparar ese int64 con lo
       que queda de archivo cuesta ocho bytes y una resta.
    2. Las cadenas de la CABECERA se escriben con longitud int32 explicita
       y se leen comprobando que esa longitud cabe en lo que queda de
       archivo. Las del CUERPO usan el Write/ReadString de .NET, que es
       mucho mas rapido. La diferencia no es capricho: la cabecera se lee
       ANTES de que nada la haya validado, asi que una longitud
       disparatada en un archivo con basura pediria reservar un buffer
       enorme; el cuerpo solo se recorre DESPUES de que su suma de
       comprobacion haya cuadrado.
    3. Los bucles que recorren las tres tablas NO llaman a ninguna funcion
       de PowerShell por entrada. Una llamada a funcion cuesta unos 10 us
       -medido dos veces, en [VEL-01] y en [VEL-02]-, y a un millon de
       entradas eso solo son diez segundos. Todo va en linea a proposito,
       aunque se repita.
#>

# "CACHIDX" y un cero. Ocho bytes fijos al principio para que un archivo
# que no es de aqui se descarte en la primera lectura, antes de
# interpretar nada.
$script:FirmaIndicePersistente = [byte[]] @(0x43, 0x41, 0x43, 0x48, 0x49, 0x44, 0x58, 0x00)

# Sube cuando cambie la disposicion de arriba. Un archivo con OTRA version
# -mayor o menor- se descarta entero: no se puede leer un formato que no
# se conoce, porque los campos podrian no estar donde se esperan.
$script:VersionFormatoIndice = 1

function Get-VersionFormatoIndice {
    <#
    .SYNOPSIS
        La version del formato del indice que entiende este programa.

    .NOTES
        Se expone con una funcion, y no dejando que quien la necesite mire
        la variable, por lo mismo que Get-CaducidadIndice y
        Get-SueloCobertura: quien ESCRIBE la cabecera y quien la COMPRUEBA
        tienen que decir el mismo numero. Y ademas $script: dentro de un
        archivo dot-sourceado apunta al ambito de QUIEN LLAMA, asi que
        fuera del nucleo esa variable no es de fiar.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()
    return [int]$script:VersionFormatoIndice
}

# El mismo centinela que usa New-EntradaCarpeta para "aqui no hay fecha".
$script:FechaCeroIndice = [datetime]'1900-01-01'

function Write-CadenaIndice {
    <#
    .SYNOPSIS
        Escribe una cadena de la CABECERA: longitud en int32 y luego los
        bytes en UTF-8.

    .DESCRIPTION
        Solo para la cabecera. Ver el punto 2 de la nota del formato: las
        cadenas del cuerpo van con el ReadString de .NET, que es bastante
        mas rapido y no puede usarse aqui.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Escritor,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Texto
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Texto)
    $Escritor.Write([int]$bytes.Length)
    if ($bytes.Length -gt 0) { $Escritor.Write($bytes) }
}

function Read-CadenaIndice {
    <#
    .SYNOPSIS
        Lee una cadena de la CABECERA, comprobando que la longitud que
        declara cabe en lo que queda de archivo.

    .DESCRIPTION
        LANZA si no cabe, y eso es lo correcto: quien llama tiene el
        try/catch que convierte cualquier disparate en $null. Sin esta
        comprobacion, un archivo lleno de basura podria declarar una
        cadena de dos mil millones de caracteres y pedirle al proceso que
        reserve sitio para ella.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Lector)

    $flujo = $Lector.BaseStream
    $longitud = $Lector.ReadInt32()
    if ($longitud -lt 0 -or $longitud -gt ($flujo.Length - $flujo.Position)) {
        throw "Cadena imposible en la cabecera: dice $longitud bytes."
    }
    if ($longitud -eq 0) { return '' }
    return [Text.Encoding]::UTF8.GetString($Lector.ReadBytes($longitud))
}

function Read-CabeceraIndiceFlujo {
    <#
    .SYNOPSIS
        La cabecera leida de un flujo ya abierto, o $null si el archivo no
        es de aqui o es de una version que no se conoce.

    .DESCRIPTION
        Aparte porque la usan los dos caminos -Get-CabeceraIndice, que se
        para aqui, y Read-IndiceDisco, que sigue-. Que la cabecera se lea
        en UN solo sitio es lo que garantiza que los dos entiendan lo
        mismo por "cabecera valida".

        Al volver, el flujo queda posicionado justo al principio del
        cuerpo.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [AllowNull()] $Lector)

    $flujo = $Lector.BaseStream
    $firma = $Lector.ReadBytes($script:FirmaIndicePersistente.Length)
    if ($null -eq $firma -or $firma.Length -ne $script:FirmaIndicePersistente.Length) {
        return $null
    }
    for ($i = 0; $i -lt $firma.Length; $i++) {
        if ($firma[$i] -ne $script:FirmaIndicePersistente[$i]) { return $null }
    }

    $version = $Lector.ReadInt32()
    # Ni mayor ni menor: DISTINTA. Leer los campos siguientes de un
    # formato que no se conoce es inventarse lo que dicen.
    if ($version -ne $script:VersionFormatoIndice) { return $null }

    $serie    = Read-CadenaIndice -Lector $Lector
    $diario   = Read-CadenaIndice -Lector $Lector
    $corte    = $Lector.ReadInt64()
    $entradas = $Lector.ReadInt32()
    $suma     = Read-CadenaIndice -Lector $Lector
    $escrito  = [datetime]::FromBinary($Lector.ReadInt64())

    if ($entradas -lt 0) { return $null }

    # El cuerpo empieza por su propia longitud. Comparada con lo que queda
    # de archivo detecta un truncamiento -o un archivo con cosas pegadas
    # detras- sin leer ni una entrada. Es la comprobacion que permite que
    # Get-CabeceraIndice diga "no" sin pagar el segundo de carga.
    $declarada = $Lector.ReadInt64()
    $real = ($flujo.Length - $flujo.Position) + 8
    if ($declarada -ne $real) { return $null }

    return [pscustomobject]@{
        Version      = [int]$version
        SerieVolumen = [string]$serie
        IdDiario     = [string]$diario
        UsnCorte     = [long]$corte
        Entradas     = [int]$entradas
        Suma         = [string]$suma
        Escrito      = $escrito
    }
}

function Get-SumaCuerpoIndice {
    <#
    .SYNOPSIS
        Suma de comprobacion del cuerpo del indice, en hexadecimal.

    .DESCRIPTION
        Existe para detectar lo que la cabecera no puede: que el cuerpo
        este truncado, o que alguno de sus bytes haya cambiado. El caso
        tipico no es un ataque, es un apagon a mitad de escritura.

        SHA-256 y no algo mas barato porque el coste no esta aqui: son
        unos 65 MB para un millon de entradas, decimas de segundo, contra
        los cinco segundos y medio del recorrido que se quiere evitar. Con
        un algoritmo roto habria que explicar por que, y no hay nada que
        ganar.

        Un cuerpo nulo y un cuerpo vacio dan la MISMA suma a proposito: un
        indice sin entradas es un caso normal -un disco recien
        analizado que no tenia nada-, no un error.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes
    )

    try {
        $datos = $Bytes
        if ($null -eq $datos) { $datos = [byte[]]::new(0) }

        $algoritmo = [Security.Cryptography.SHA256]::Create()
        try {
            $resumen = $algoritmo.ComputeHash($datos)
        } finally {
            $algoritmo.Dispose()
        }

        $texto = [Text.StringBuilder]::new(64)
        foreach ($b in $resumen) { [void]$texto.Append($b.ToString('x2')) }
        return $texto.ToString()
    } catch {
        # Si ni siquiera se puede resumir, no se afirma nada: quien llama
        # vera que la suma no cuadra y recorrera de nuevo.
        return $null
    }
}

function Save-IndiceDisco {
    <#
    .SYNOPSIS
        Guarda el índice en disco, con su cabecera, de forma atómica.

    .PARAMETER Indice
        Lo que devuelve New-IndiceDisco. También vale lo que devuelve
        Read-IndiceDisco: la ida y vuelta se puede repetir.
    .PARAMETER Ruta
        Archivo destino.
    .PARAMETER SerieVolumen
        Número de serie del volumen, para detectar que la letra de unidad
        es hoy OTRO disco.
    .PARAMETER IdDiario
        Identificador del diario USN. Si cambia, la historia anterior ya
        no existe.
    .PARAMETER UsnCorte
        USN hasta donde se leyó el diario.
    .PARAMETER Referencias
        Tabla de referencia de carpeta a ruta. Puede ser $null.
    .PARAMETER Escrito
        Cuándo se escribe. Es un parámetro y no un Get-Date escondido para
        que la caducidad se pueda probar sin esperar días.

    .OUTPUTS
        [bool] Si se ha escrito. NO devuelve el índice ni nada que se
        parezca a un candidato: de aquí no sale nada que pueda borrarse.

    .NOTES
        ESCRITURA ATOMICA, igual que Add-EntradaHistorial y por el mismo
        motivo, que alli esta explicado largo: si el proceso muere -o el
        equipo se apaga- mientras se escribe, el archivo queda TRUNCADO.
        Y un indice truncado que se leyera como bueno es exactamente la
        forma de mentir que este archivo entero existe para evitar.

        Primero a un temporal al lado, y despues un reemplazo de UNA sola
        operacion con Move-Item -Force, que es lo mas cercano a un
        reemplazo atomico disponible en las dos versiones de PowerShell
        que el programa soporta. El temporal lleva el PID en el nombre por
        lo mismo que alli: dos procesos no se pisan el archivo intermedio,
        y el resto que deja un reemplazo fallido tiene SIEMPRE el mismo
        nombre, que la siguiente escritura de este proceso sobrescribe. No
        se borra aqui: dentro de src/Core solo Remove.ps1 borra archivos,
        y esa invariante vale mas que un .tmp huerfano en el caso raro.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Indice,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        [AllowNull()] [AllowEmptyString()] [string] $SerieVolumen = '',
        [AllowNull()] [AllowEmptyString()] [string] $IdDiario = '',
        [long] $UsnCorte = 0,
        [AllowNull()] $Referencias = $null,
        [datetime] $Escrito = (Get-Date)
    )

    if ($null -eq $Indice) { return $false }
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $false }
    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Guardar el índice de espacio')) { return $false }

    $memoria  = $null
    $escritor = $null
    $flujo    = $null
    $salida   = $null
    try {
        # --- El cuerpo, primero en memoria --------------------------------
        # Hace falta tenerlo entero para poder resumirlo antes de escribir
        # la cabecera, que va delante. Son unos 65 MB para un millon de
        # entradas: mucho menos que los 1,6 GB que ocupa la lista de
        # objetos de la que se parte.
        $memoria  = [IO.MemoryStream]::new()
        $escritor = [IO.BinaryWriter]::new($memoria, [Text.UTF8Encoding]::new($false))

        # Hueco para la longitud del cuerpo; se rellena al final, cuando ya
        # se sabe cuanto ocupa.
        $escritor.Write([long]0)

        $raices = [Collections.Generic.List[string]]::new()
        if ($null -ne $Indice.Raices) {
            foreach ($r in $Indice.Raices) {
                if ($null -ne $r) { $raices.Add([string]$r) }
            }
        }
        $escritor.Write([int]$raices.Count)
        foreach ($r in $raices) { $escritor.Write([string]$r) }

        $escritor.Write([double]$Indice.Bytes)
        $escritor.Write([int]$Indice.TotalArchivos)
        $escritor.Write([int]$Indice.Compartidos)
        $escritor.Write([int]$Indice.Inaccesibles)
        $escritor.Write([double]$Indice.UmbralArchivo)

        # --- Tabla 2: las carpetas, con los totales YA sumados ------------
        $carpetas = @()
        if ($null -ne $Indice.Carpetas) { $carpetas = @($Indice.Carpetas.Values) }
        $escritor.Write([int]$carpetas.Count)
        foreach ($c in $carpetas) {
            $escritor.Write([string]$c.Ruta)
            $escritor.Write([string]$c.Nombre)
            $escritor.Write([int]$c.Nivel)
            $escritor.Write([double]$c.Bytes)
            $escritor.Write([double]$c.Propios)
            $escritor.Write([int]$c.Archivos)
            $u = $c.Ultimo
            if ($u -isnot [datetime]) { $u = $script:FechaCeroIndice }
            $escritor.Write([long]$u.ToBinary())
        }

        # --- Tabla 1: los archivos ----------------------------------------
        $archivos = @()
        if ($null -ne $Indice.Archivos) { $archivos = @($Indice.Archivos) }
        $escritor.Write([int]$archivos.Count)
        foreach ($a in $archivos) {
            $escritor.Write([string]$a.Ruta)
            $escritor.Write([string]$a.Nombre)
            $escritor.Write([string]$a.Carpeta)
            $escritor.Write([string]$a.Extension)
            $escritor.Write([double]$a.Bytes)
            $u = $a.Ultimo
            if ($u -isnot [datetime]) { $u = $script:FechaCeroIndice }
            $escritor.Write([long]$u.ToBinary())
        }

        # --- Tabla 3: referencia de carpeta a ruta ------------------------
        $claves = @()
        if ($null -ne $Referencias -and $null -ne $Referencias.Keys) {
            $claves = @($Referencias.Keys)
        }
        $escritor.Write([int]$claves.Count)
        foreach ($k in $claves) {
            $escritor.Write([uint64]$k)
            $escritor.Write([string]$Referencias[$k])
        }

        $escritor.Flush()
        $memoria.Position = 0
        $escritor.Write([long]$memoria.Length)
        $escritor.Flush()
        $cuerpo = $memoria.ToArray()

        $suma = Get-SumaCuerpoIndice -Bytes $cuerpo
        if ([string]::IsNullOrEmpty($suma)) { return $false }

        # --- Al temporal, y despues el reemplazo de una sola operacion ----
        $temporal = "$Ruta.$PID.tmp"
        $flujo = [IO.File]::Open($temporal, [IO.FileMode]::Create, [IO.FileAccess]::Write,
                                 [IO.FileShare]::None)
        $salida = [IO.BinaryWriter]::new($flujo, [Text.UTF8Encoding]::new($false))
        $salida.Write($script:FirmaIndicePersistente)
        $salida.Write([int]$script:VersionFormatoIndice)
        Write-CadenaIndice -Escritor $salida -Texto $SerieVolumen
        Write-CadenaIndice -Escritor $salida -Texto $IdDiario
        $salida.Write([long]$UsnCorte)
        $salida.Write([int]$archivos.Count)
        Write-CadenaIndice -Escritor $salida -Texto $suma
        $salida.Write([long]$Escrito.ToBinary())
        $salida.Write($cuerpo)
        $salida.Flush()
        $salida.Dispose(); $salida = $null
        $flujo = $null

        Move-Item -LiteralPath $temporal -Destination $Ruta -Force -ErrorAction Stop
        return $true
    } catch {
        # No se avisa con un error: quien llama comprueba el resultado, y
        # no poder guardar el indice solo significa que la proxima vez se
        # recorrera el disco. Nada que el usuario tenga que decidir.
        Write-Verbose "No se ha podido guardar el índice: $($_.Exception.Message)"
        return $false
    } finally {
        if ($null -ne $salida)   { $salida.Dispose() }
        if ($null -ne $flujo)    { $flujo.Dispose() }
        if ($null -ne $escritor) { $escritor.Dispose() }
        if ($null -ne $memoria)  { $memoria.Dispose() }
    }
}

function Get-CabeceraIndice {
    <#
    .SYNOPSIS
        Solo la cabecera del índice, sin cargar el cuerpo. $null si el
        archivo no sirve.

    .DESCRIPTION
        Existe para poder decidir si el índice vale ANTES de pagar el
        segundo largo que cuesta cargarlo. Lee ocho bytes de firma, siete
        campos y la longitud del cuerpo; no toca ni una entrada.

        Devuelve $null -y no lanza- cuando el archivo no está, no es de
        aquí, es de una versión del formato que no se conoce, está
        truncado o tiene cosas pegadas detrás.

        Lo que NO comprueba es la suma del cuerpo: eso obligaría a leerlo
        entero, que es justo lo que esta función existe para no hacer. La
        comprueba Read-IndiceDisco.

    .OUTPUTS
        [pscustomobject] con exactamente siete campos: Version,
        SerieVolumen, IdDiario, UsnCorte, Entradas, Suma y Escrito.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta
    )

    $flujo  = $null
    $lector = $null
    try {
        if ([string]::IsNullOrWhiteSpace($Ruta)) { return $null }
        if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $null }

        # FileShare::ReadWrite: que otro proceso este reemplazando el
        # archivo no es motivo para fallar. Si lo que se lee no cuadra, ya
        # se descarta por la firma o por la longitud.
        $flujo = [IO.File]::Open($Ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                                 [IO.FileShare]::ReadWrite)
        $lector = [IO.BinaryReader]::new($flujo, [Text.UTF8Encoding]::new($false))
        return (Read-CabeceraIndiceFlujo -Lector $lector)
    } catch {
        return $null
    } finally {
        if ($null -ne $lector) { $lector.Dispose() }
        if ($null -ne $flujo)  { $flujo.Dispose() }
    }
}

function Read-IndiceDisco {
    <#
    .SYNOPSIS
        Carga el índice entero desde disco. $null si el archivo no sirve.

    .DESCRIPTION
        Devuelve la MISMA FORMA que produce New-IndiceDisco -Carpetas,
        Archivos, Raices, Bytes, TotalArchivos, Compartidos, Inaccesibles
        y UmbralArchivo- para que quien lo consuma no note de dónde vino.

        Con dos diferencias que hay que decir claras:

          * Cada entrada es un DICCIONARIO, no un pscustomobject. Se
            accede igual -$entrada.Ruta, $entrada.Bytes-, y Sort-Object y
            Where-Object funcionan igual, pero Select-Object
            -ExpandProperty NO: sobre un diccionario no encuentra la
            propiedad. El motivo está arriba: componer objetos multiplica
            por doce el tiempo de carga.
          * Trae además Referencias y Cabecera, que New-IndiceDisco no
            tiene porque no vienen de recorrer el disco.

        Devuelve $null, sin lanzar, ante cualquier archivo del que no se
        pueda afirmar que está entero: truncado, alterado, de otra
        versión, de cero bytes, con basura o inexistente.

    .OUTPUTS
        [pscustomobject] con los totales para dibujar el mapa. Aquí no hay
        candidatos ni nada que se les parezca: esto no decide qué se
        borra.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        # LAS DOS FORMAS DE LA TABLA DE ARCHIVOS, Y CUAL PEDIR.
        #
        # Por omision sale un array, que es lo que devuelve New-IndiceDisco
        # y lo que esperan el mapa, el informe y la vista de archivos: ahi
        # se RECORRE la lista entera una vez y un array es lo comodo.
        #
        # Con -ComoDiccionario sale una tabla ruta -> entrada, que es lo
        # que necesita Update-IndiceConCambios: ahi no se recorre nada, se
        # BUSCAN unos pocos miles de rutas sueltas entre un millon. Con un
        # array eso es un recorrido por cada cambio.
        #
        # Se decide aqui y no convirtiendo despues a proposito: convertir
        # obliga a construir primero la forma que no hace falta, que es
        # justo el coste que docs/VEL-02-MEDICION.md midio y evito.
        [switch] $ComoDiccionario
    )

    $flujo        = $null
    $lector       = $null
    $memoria      = $null
    $cuerpo       = $null
    $lectorCuerpo = $null
    try {
        if ([string]::IsNullOrWhiteSpace($Ruta)) { return $null }
        if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $null }

        $flujo = [IO.File]::Open($Ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                                 [IO.FileShare]::ReadWrite)
        $lector = [IO.BinaryReader]::new($flujo, [Text.UTF8Encoding]::new($false))

        $cabecera = Read-CabeceraIndiceFlujo -Lector $lector
        if ($null -eq $cabecera) { return $null }

        # El cuerpo entero, contando los ocho bytes de su longitud, que la
        # cabecera acaba de leer. Se retrocede para que la suma cubra
        # tambien esos ocho: si alguien los cambiara, la longitud dejaria
        # de cuadrar Y la suma tampoco.
        $flujo.Position = $flujo.Position - 8
        $restante = $flujo.Length - $flujo.Position
        if ($restante -lt 8 -or $restante -gt [int]::MaxValue) { return $null }

        $cuerpo = $lector.ReadBytes([int]$restante)
        if ($null -eq $cuerpo -or $cuerpo.Length -ne $restante) { return $null }

        $suma = Get-SumaCuerpoIndice -Bytes $cuerpo
        if ([string]::IsNullOrEmpty($suma)) { return $null }
        if (-not $suma.Equals([string]$cabecera.Suma, [StringComparison]::OrdinalIgnoreCase)) {
            # Truncado o alterado. No se repara nada ni se aprovecha "lo
            # que parece bueno": un indice que no se puede validar entero
            # se tira entero.
            return $null
        }

        $memoria = [IO.MemoryStream]::new($cuerpo, $false)
        $lectorCuerpo = [IO.BinaryReader]::new($memoria, [Text.UTF8Encoding]::new($false))

        $declarada = $lectorCuerpo.ReadInt64()
        if ($declarada -ne $cuerpo.Length) { return $null }

        $nRaices = $lectorCuerpo.ReadInt32()
        if ($nRaices -lt 0 -or $nRaices -gt ($memoria.Length - $memoria.Position)) { return $null }
        $raices = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $nRaices; $i++) { $raices.Add($lectorCuerpo.ReadString()) }

        $bytesTotal    = $lectorCuerpo.ReadDouble()
        $totalArchivos = $lectorCuerpo.ReadInt32()
        $compartidos   = $lectorCuerpo.ReadInt32()
        $inaccesibles  = $lectorCuerpo.ReadInt32()
        $umbral        = $lectorCuerpo.ReadDouble()

        # --- Las carpetas -------------------------------------------------
        # OrdinalIgnoreCase, igual que New-IndiceDisco: las rutas de
        # Windows no distinguen mayusculas y quien busque el padre de una
        # ruta tiene que encontrarlo escriba como escriba.
        $nCarpetas = $lectorCuerpo.ReadInt32()
        if ($nCarpetas -lt 0 -or $nCarpetas -gt ($memoria.Length - $memoria.Position)) {
            return $null
        }
        $carpetas = [Collections.Generic.Dictionary[string, object]]::new(
                        [StringComparer]::OrdinalIgnoreCase)
        for ($i = 0; $i -lt $nCarpetas; $i++) {
            # Todo en linea a proposito: una llamada a funcion por entrada
            # costaria unos 10 us, que a un millon de entradas son diez
            # segundos y se llevarian el punto entero por delante.
            $entrada = [Collections.Generic.Dictionary[string, object]]::new(
                           7, [StringComparer]::OrdinalIgnoreCase)
            $entrada['Ruta']     = $lectorCuerpo.ReadString()
            $entrada['Nombre']   = $lectorCuerpo.ReadString()
            $entrada['Nivel']    = $lectorCuerpo.ReadInt32()
            $entrada['Bytes']    = $lectorCuerpo.ReadDouble()
            $entrada['Propios']  = $lectorCuerpo.ReadDouble()
            $entrada['Archivos'] = $lectorCuerpo.ReadInt32()
            $entrada['Ultimo']   = [datetime]::FromBinary($lectorCuerpo.ReadInt64())
            $carpetas[[string]$entrada['Ruta']] = $entrada
        }

        # --- Los archivos -------------------------------------------------
        $nArchivos = $lectorCuerpo.ReadInt32()
        if ($nArchivos -lt 0 -or $nArchivos -gt ($memoria.Length - $memoria.Position)) {
            return $null
        }
        $archivos = [Collections.Generic.List[object]]::new($nArchivos)
        $porRuta  = [Collections.Generic.Dictionary[string, object]]::new(
                        [Math]::Max(1, $nArchivos), [StringComparer]::OrdinalIgnoreCase)
        for ($i = 0; $i -lt $nArchivos; $i++) {
            $entrada = [Collections.Generic.Dictionary[string, object]]::new(
                           6, [StringComparer]::OrdinalIgnoreCase)
            $entrada['Ruta']      = $lectorCuerpo.ReadString()
            $entrada['Nombre']    = $lectorCuerpo.ReadString()
            $entrada['Carpeta']   = $lectorCuerpo.ReadString()
            $entrada['Extension'] = $lectorCuerpo.ReadString()
            $entrada['Bytes']     = $lectorCuerpo.ReadDouble()
            $entrada['Ultimo']    = [datetime]::FromBinary($lectorCuerpo.ReadInt64())
            $archivos.Add($entrada)
            if ($ComoDiccionario) { $porRuta[[string]$entrada['Ruta']] = $entrada }
        }

        # El numero de entradas que anuncia la cabecera tiene que ser el
        # que hay. Si no, el archivo no es coherente consigo mismo.
        if ($archivos.Count -ne [int]$cabecera.Entradas) { return $null }

        # --- Referencia de carpeta a ruta ---------------------------------
        $nReferencias = $lectorCuerpo.ReadInt32()
        if ($nReferencias -lt 0 -or $nReferencias -gt ($memoria.Length - $memoria.Position)) {
            return $null
        }
        $referencias = [Collections.Generic.Dictionary[uint64, string]]::new()
        for ($i = 0; $i -lt $nReferencias; $i++) {
            $clave = $lectorCuerpo.ReadUInt64()
            $referencias[$clave] = $lectorCuerpo.ReadString()
        }

        return [pscustomobject]@{
            Carpetas      = $carpetas
            # ToArray y no la lista: New-IndiceDisco devuelve un array, y
            # la idea es que no se note de donde vino. El orden es el que
            # tenia al guardarse, asi que si venia ordenado por tamano
            # sigue estandolo.
            Archivos      = if ($ComoDiccionario) { $porRuta } else { $archivos.ToArray() }
            Raices        = $raices.ToArray()
            Bytes         = $bytesTotal
            TotalArchivos = $totalArchivos
            Compartidos   = $compartidos
            Inaccesibles  = $inaccesibles
            UmbralArchivo = $umbral
            Referencias   = $referencias
            Cabecera      = $cabecera
        }
    } catch {
        # Cualquier disparate -un archivo a medias, bytes cambiados, un
        # formato que no es este- acaba aqui y sale como $null. Quien
        # llama recorre el disco de nuevo, que es la respuesta segura.
        Write-Verbose "No se ha podido leer el índice: $($_.Exception.Message)"
        return $null
    } finally {
        if ($null -ne $lectorCuerpo) { $lectorCuerpo.Dispose() }
        if ($null -ne $memoria)      { $memoria.Dispose() }
        if ($null -ne $lector)       { $lector.Dispose() }
        if ($null -ne $flujo)        { $flujo.Dispose() }
    }
}
