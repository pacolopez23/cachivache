<#
.SYNOPSIS
    Las decisiones que hacen falta para REUTILIZAR el indice guardado sin
    mentirle al usuario. Calculo puro.

.DESCRIPTION
    Hasta hoy, IndicePersistente.ps1 e IndiceIncremental.ps1 -1.666 lineas
    entre los dos, con 1.700 de pruebas- no los llamaba NADIE desde el
    programa. Estaban escritos y verdes y ningun camino pasaba por ellos.
    Este archivo es lo que faltaba para que "cachivache espacio" sea su
    primer consumidor de verdad.

    -------------------------------------------------------------------
    EL PROBLEMA QUE HAY QUE RESOLVER, Y QUE NO EXISTIA EN EL PLAN ORIGINAL

    El plan era: guardar el indice, y al volver leer el diario de cambios
    de NTFS para ponerlo al dia. Asi el indice reutilizado estaria al dia
    y se podria presentar como si fuera de ahora.

    Ese plan murio el 5 de septiembre de 2026: el diario se lee bien, pero
    parsearlo cuesta 70 minutos contra los 42 segundos de recorrer el
    disco, y ademas solo conserva entre 10 y 80 minutos de historia. Ver
    docs/VEL-02-MEDICION.md.

    Asi que queda el indice guardado SIN forma de ponerlo al dia. Y eso
    cambia lo que se puede prometer:

        un indice reutilizado NO dice lo que hay en el disco.
        Dice lo que habia cuando se guardo.

    Sigue siendo util -es la diferencia entre un segundo y cuarenta y dos,
    y para "donde se fue el espacio" una foto de hace diez minutos vale
    igual-, pero solo si SE DICE. Un programa que presenta datos viejos
    como si fueran de ahora es exactamente lo que este proyecto no hace, y
    por eso la frase que lo avisa vive aqui, en una funcion probada, y no
    en un Write-Host suelto dentro del comando.

    -------------------------------------------------------------------
    POR QUE 'sin-diario' Y NO UNA CADENA VACIA

    Test-IndiceUtilizable EXIGE un identificador de diario, y con razon:
    naciendo para un mundo con diario, no tener identificador es no poder
    contrastar nada. Aqui no hay diario, asi que se guarda y se comprueba
    una marca fija.

    No es un apanyo para colarse por la comprobacion: es lo correcto. El
    dia que alguien vuelva a intentar el camino del diario -en C#, que es
    la puerta que quedo abierta-, los indices guardados hoy traeran
    'sin-diario' donde el programa nuevo espera un identificador de verdad,
    y Test-IndiceUtilizable los rechazara SOLO. Que es justo lo que tiene
    que pasar: un indice guardado sin diario no se puede poner al dia con
    el diario.

    Y deja la caducidad de siete dias como unica red, que es lo que
    Get-CaducidadIndice ya decia que pasaria cuando el diario no estuviera.
#>

function Get-MarcaSinDiario {
    <#
    .SYNOPSIS
        Lo que se guarda en el campo del diario cuando no hay diario.

    .NOTES
        Es una funcion y no una cadena repetida en dos sitios por el patron
        central del proyecto: quien GUARDA y quien COMPRUEBA tienen que
        decir lo mismo, y dos literales iguales acaban siendo dos literales
        distintos. Si estos dos dejaran de coincidir, el indice se
        rechazaria siempre y nadie sabria por que: el programa no fallaria,
        solo dejaria de ir rapido.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return 'sin-diario'
}

function Get-HuellaVolumen {
    <#
    .SYNOPSIS
        Una huella del volumen, para notar que la letra de unidad es hoy
        OTRO disco. Calculo puro.

    .DESCRIPTION
        NO ES UN NUMERO DE SERIE, Y NO SE LLAMA ASI A PROPOSITO.

        Lo que Test-IndiceUtilizable quiere en su campo SerieVolumen es
        algo que cambie cuando cambia el disco. El numero de serie de NTFS
        seria lo ideal, pero .NET no lo expone: hay que ir a CIM, que
        cuesta decenas de milisegundos y solo existe en Windows. La misma
        razon por la que Extraibles.ps1 usa DriveInfo y no Win32_LogicalDisk.

        Asi que se compone una huella con tres cosas que si son gratis:
        el sistema de archivos, el tamanyo total y la fecha de creacion de
        la raiz -que es cuando se formateo el volumen-. Otro disco en la
        misma letra tendria que coincidir en las tres para colarse.

        QUE NO CAZA, y hay que decirlo: dos particiones clonadas bit a bit.
        Contra eso la red que queda es la caducidad de siete dias. Es una
        huella, no una identidad, y por eso el nombre.

    .PARAMETER Creacion
        Se pasa como parametro, y no se lee aqui, para que esta funcion sea
        pura y se pueda probar sin un disco delante.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Formato = '',
        [AllowNull()] $Bytes = 0,
        [AllowNull()] $Creacion = $null
    )

    # LAS LOCALES SE LLAMAN DISTINTO QUE LOS PARAMETROS, Y ESO NO ES
    # ESTILO. En PowerShell los nombres de variable NO distinguen
    # mayusculas: $bytes y $Bytes son LA MISMA VARIABLE. La primera version
    # de esto empezaba con
    #
    #     $bytes = 0.0
    #     if ($null -ne $Bytes) { $bytes = [double]$Bytes }
    #
    # y esa primera linea BORRABA EL ARGUMENTO antes de leerlo: llamando
    # con -Bytes 500107862016 salia una huella con 0. Sin lanzar, sin aviso
    # del analizador, y con el mismo aspecto de un disco al que no se le ha
    # podido preguntar el tamanyo. Se vio al ejecutarlo a mano.
    #
    # Lo taimado es lo que paso con $Formato: alli la asignacion era
    # "$formato = $Formato.Trim()", o sea la variable a partir de si misma,
    # que funciona perfectamente. O sea que el mismo patron estaba bien en
    # un campo y roto en los otros dos, y el que funcionaba tapaba a los
    # que no.
    $txtFormato = if ($null -eq $Formato) { '' } else { $Formato.Trim() }

    $numBytes = 0.0
    if ($null -ne $Bytes) { try { $numBytes = [double]$Bytes } catch { $numBytes = 0.0 } }
    if ($numBytes -lt 0) { $numBytes = 0.0 }

    # La fecha en formato redondo y en UTC. Sin la 'o' -o con la cultura
    # del sistema- la misma fecha se escribiria distinto en un equipo en
    # espanyol y en uno en ingles, y la huella dejaria de coincidir consigo
    # misma al cambiar el idioma de Windows.
    $txtCreacion = 'sin-fecha'
    if ($Creacion -is [datetime]) {
        $txtCreacion = $Creacion.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }

    return ('{0}|{1:F0}|{2}' -f $txtFormato, $numBytes, $txtCreacion)
}

function Get-HuellaVolumenDeZonas {
    <#
    .SYNOPSIS
        La huella de TODOS los volumenes que tocan unas carpetas. Lo unico
        de este archivo que mira el disco.

    .DESCRIPTION
        Un analisis puede abarcar varias unidades a la vez -"C:\Users\x" y
        "D:\Juegos"-, y entonces el indice deja de ser creible en cuanto
        CUALQUIERA de las dos cambie. Por eso se concatenan las huellas de
        todas, ordenadas para que el orden en que se pidieron las carpetas
        no cambie el resultado.

        NUNCA LANZA. Una unidad que no responde deja su hueco marcado, y
        eso ya hace que la huella no coincida con la guardada: se recorre
        el disco, que es el camino seguro. Fallar aqui tumbaria el comando
        entero por no poder hacer una optimizacion.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Zonas)

    $raices = @()
    if ($null -ne $Zonas) {
        $raices = @($Zonas |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object {
                try { [IO.Path]::GetPathRoot(([string]$_).Trim()) } catch { '' }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.ToLowerInvariant() } |
            Sort-Object -Unique)
    }
    if ($raices.Count -eq 0) { return '' }

    $partes = @()
    foreach ($raiz in $raices) {
        $formato  = ''
        $total    = 0
        $creacion = $null
        try {
            $unidad = [IO.DriveInfo]::new($raiz)
            $formato = $unidad.DriveFormat
            $total   = $unidad.TotalSize
        } catch {
            Write-Verbose ('No se ha podido leer la unidad {0}: {1}' -f $raiz, $_.Exception.Message)
        }
        try { $creacion = [IO.Directory]::GetCreationTimeUtc($raiz) } catch { $creacion = $null }
        $partes += ('{0}={1}' -f $raiz, (Get-HuellaVolumen -Formato $formato -Bytes $total -Creacion $creacion))
    }
    return ($partes -join ';')
}

function Get-NombreIndiceEspacio {
    <#
    .SYNOPSIS
        Como se llama el archivo del indice de un conjunto de carpetas.
        Calculo puro.

    .DESCRIPTION
        UN INDICE VALE PARA LAS CARPETAS QUE MIDIO, Y PARA NINGUNA OTRA, y
        el formato del archivo no guarda cuales fueron. Se podria anyadir
        un campo a la cabecera; se resuelve en el NOMBRE, que no obliga a
        cambiar el formato ni a subir su version.

        Analizar "Descargas" y luego "Descargas y Documentos" da dos
        nombres distintos, asi que el segundo no encuentra indice y
        recorre, en vez de ensenyar el total del primero como si fuera el
        del segundo. Que seria mentir por defecto.

        EL ORDEN NO CUENTA y las mayusculas tampoco: en Windows
        "C:\Users\x" y "c:\users\X" son la misma carpeta, y pedir las dos
        zonas en otro orden es pedir lo mismo. Sin normalizar, el indice se
        perderia cada vez que la configuracion devolviera las zonas en otro
        orden, y el usuario veria un recorrido completo sin saber por que.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Zonas)

    $lista = @()
    if ($null -ne $Zonas) {
        $lista = @($Zonas |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim().TrimEnd([char]'\', [char]'/').ToLowerInvariant() } |
            Sort-Object -Unique)
    }
    if ($lista.Count -eq 0) { return '' }

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lista -join '|')))
    } finally {
        $sha.Dispose()
    }
    # Dieciseis caracteres: 64 bits. Para distinguir los pocos conjuntos de
    # carpetas que un usuario llega a pedir, sobra de largo, y un nombre de
    # archivo de 64 caracteres no lo lee nadie.
    $corto = -join (@($bytes[0..7]) | ForEach-Object { $_.ToString('x2') })
    return ('espacio-{0}.idx' -f $corto)
}

function Get-AvisoIndiceReutilizado {
    <#
    .SYNOPSIS
        Lo que se le dice al usuario cuando NO se ha mirado el disco.
        Calculo puro.

    .DESCRIPTION
        ESTA FRASE ES LA MITAD DEL PUNTO. Reutilizar el indice sin decirlo
        convertiria "cachivache espacio" en un programa que ensenya datos
        viejos con cara de recien medidos. La frase dice las dos cosas que
        el usuario necesita: DE CUANDO son los datos, y COMO pedir que se
        vuelva a mirar.

        La antiguedad la escribe Format-Duracion, que es quien decide en
        todo el programa como se escribe una duracion en castellano.

    .PARAMETER Escrito
        Cuando se guardo el indice.
    .PARAMETER Ahora
        Se pasa desde fuera, igual que en Test-IndiceUtilizable, para que
        esto se pueda probar sin esperar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Escrito,
        [Parameter(Mandatory)] [AllowNull()] $Ahora
    )

    $desde = $null
    if ($Escrito -is [datetime]) { $desde = $Escrito }
    $hasta = $null
    if ($Ahora -is [datetime]) { $hasta = $Ahora }

    # Sin fechas creibles NO se calla: se avisa igual, sin la antiguedad.
    # Callar seria presentar datos viejos como nuevos, que es justo lo que
    # esta funcion existe para impedir; y un reloj raro no es motivo para
    # dejar de avisar.
    if ($null -eq $desde -or $null -eq $hasta -or $hasta -lt $desde) {
        return 'Datos del índice guardado: no se ha vuelto a mirar el disco. Usa -Recorrer para medirlo otra vez.'
    }

    return ('Datos del índice guardado hace {0}: no se ha vuelto a mirar el disco. Usa -Recorrer para medirlo otra vez.' -f
            (Format-Duracion ($hasta - $desde)))
}
