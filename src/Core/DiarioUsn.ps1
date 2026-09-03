<#
.SYNOPSIS
    Lectura del diario de cambios de NTFS -el USN Journal-. La mitad
    binaria de [VEL-02]: convertir los bytes de un registro en un objeto.

.DESCRIPTION
    NTFS apunta en un diario, en orden, todo lo que le pasa a cada archivo
    del volumen: creado, escrito, renombrado, borrado. Ese diario es lo que
    permite que el indice guardado no haya que recalcularlo recorriendo el
    disco entero: se pregunta "que ha cambiado desde el USN de corte" y se
    aplican solo esos cambios. Quien decide QUE significa cada cambio para
    el indice es la otra mitad; aqui solo se entienden los bytes.

    -------------------------------------------------------------------
    LO QUE ESTE ARCHIVO ES, Y LO QUE NO ES

    Aqui NO se toca el disco ni se llama a Windows. Quien lee el diario de
    verdad es DeviceIoControl con FSCTL_READ_USN_JOURNAL sobre un manejador
    de \\.\C:, y eso solo existe en Windows, sobre NTFS y con permisos de
    administrador. Este archivo se queda con la mitad que si se puede
    probar entera sin nada de eso: entender el buffer que esa llamada
    devuelve.

    Es la misma division que en Mft.ps1, y por el mismo motivo: un
    parseador binario que solo se pueda ejercitar contra un volumen real
    seria, en este proyecto, lo mismo que un mecanismo de XAML: codigo que
    nadie ha visto funcionar. Recibiendo bytes se le construye un registro
    sintetico a mano y el parseo queda probado de verdad. Ver
    tests/DiarioUsn.Tests.ps1.

    -------------------------------------------------------------------
    LA ESTRUCTURA: USN_RECORD_V2, EN EL ORDEN DE INTEL

         0  RecordLength              DWORD     longitud TOTAL, con relleno
         4  MajorVersion              WORD      tiene que ser 2
         6  MinorVersion              WORD      tiene que ser 0
         8  FileReferenceNumber       ULONGLONG 48 bits de numero + 16 de secuencia
        16  ParentFileReferenceNumber ULONGLONG
        24  Usn                       LONGLONG
        32  TimeStamp                 LONGLONG  FILETIME: ticks de 100 ns desde 1601
        40  Reason                    DWORD     mascara de bits
        44  SourceInfo                DWORD
        48  SecurityId                DWORD
        52  FileAttributes            DWORD     0x10 = carpeta
        56  FileNameLength            WORD      en BYTES, no en caracteres
        58  FileNameOffset            WORD      desde el principio DEL REGISTRO
        60  FileName                  WCHAR[]   UTF-16LE, sin terminador

    RecordLength NO es 60 mas el nombre: el sistema rellena hasta multiplo
    de ocho. Por eso el recorrido avanza siempre lo que dice RecordLength y
    nunca lo que suma a ojo, y por eso hay una prueba con relleno en medio.

    -------------------------------------------------------------------
    ANTE LA DUDA, NO AFIRMAR

    Get-RegistroUsn devuelve $null en vez de lanzar, igual que
    Get-RegistroMft. Los bytes vienen de una llamada al sistema sobre un
    volumen que puede estar danyado, y quien los recorre esta en mitad de
    un bucle de decenas de miles: una excepcion de indice a la mitad se
    llevaria por delante la actualizacion entera del indice, y el camino de
    retroceso -recorrer el disco- tiene que seguir disponible sin un try
    alrededor.

    Y devuelve $null, y no un objeto a medias, por la misma razon que en la
    tabla maestra: un registro incompleto pasaria por un cambio de verdad, y
    un cambio inventado en el indice es peor que no tener indice.

    -------------------------------------------------------------------
    DEPENDE DE Mft.ps1

    Get-ReferenciaMft vive alli y no se duplica aqui: una referencia de
    archivo de NTFS es la misma estructura de 8 bytes en la tabla maestra y
    en el diario, y dos funciones decidiendo lo mismo es justo lo que este
    proyecto evita. En Bootstrap.ps1 este archivo va DESPUES de Mft.ps1; da
    igual para ejecutar -el nucleo se carga entero antes de correr nada-,
    pero asi se lee de arriba abajo.
#>

function Get-RegistroUsn {
    <#
    .SYNOPSIS
        Entiende UN registro USN_RECORD_V2 dentro de un buffer. Devuelve
        $null si esos bytes no son un registro. Calculo puro, nunca lanza.

    .PARAMETER Bytes
        El buffer entero, tal como lo devuelve la llamada al sistema. NO se
        modifica: aqui solo se lee, asi que -a diferencia de la tabla
        maestra, donde hay que deshacer las correcciones de secuencia- no
        hace falta copiar nada.

    .PARAMETER Desplazamiento
        Donde empieza el registro dentro del buffer. Los registros vienen
        pegados unos detras de otros, asi que este numero lo lleva quien
        recorre. Por omision, el principio.

    .OUTPUTS
        Un objeto con:

          Longitud               int       RecordLength, relleno incluido
          Referencia             uint64    FileReferenceNumber, tal cual
          ReferenciaPadre        uint64    ParentFileReferenceNumber, tal cual
          NumeroReferencia       double    la referencia SIN los 16 bits de secuencia
          NumeroReferenciaPadre  double    idem, del padre
          Usn                    long
          Marca                  datetime  UTC, o $null si el FILETIME no es una fecha
          Razon                  uint32    Reason
          Origen                 uint32    SourceInfo
          IdSeguridad            uint32    SecurityId
          Atributos              uint32    FileAttributes
          Nombre                 string    puede ser vacio
          EsCarpeta              bool      FILE_ATTRIBUTE_DIRECTORY

    .NOTES
        POR QUE HAY DOS NUMEROS PARA CADA REFERENCIA.

        Una referencia de archivo son 48 bits de numero de registro de la
        MFT y 16 de numero de secuencia. El numero de secuencia sube cada
        vez que NTFS reutiliza el registro para otro archivo, asi que la
        referencia entera identifica "este archivo en concreto" y el
        numero a secas identifica "esta fila de la tabla". En [VEL-01] se
        comprobo que lo segundo es lo que casa entre padre e hijo: la
        referencia del padre en un registro y la referencia del propio
        registro del padre solo coinciden con la secuencia fuera. Por eso
        se dan los dos, y el mascarado lo hace Get-ReferenciaMft, que es la
        misma funcion que usa la tabla maestra: si un dia cambiara la regla,
        cambiaria en los dos sitios a la vez.

        NumeroReferencia sale como double, y no como uint64, por lo que
        explica Get-ReferenciaMft: en 5.1 operar con UInt64 acaba en
        conversiones que lanzan, y 48 bits caben exactos en un double.
        Referencia, en cambio, se deja en uint64 tal cual: es un
        identificador que solo se compara por igualdad, y pasarlo a double
        lo redondearia -pasa de 2^53- y dos archivos distintos podrian
        salir iguales.

        RAZON Y ATRIBUTOS SON UINT32, Y ESO TIENE UNA TRAMPA PARA QUIEN LOS
        COMPARE. USN_REASON_CLOSE es 0x80000000, y en PowerShell ese
        literal es un Int32 NEGATIVO: "[uint32]0x80000000" LANZA al
        convertir, y "$Razon -band 0x80000000" compara en 64 bits contra
        -2147483648, o sea contra otro numero. Quien mire el bit alto tiene
        que escribir el literal con L -0x80000000L- para que sea Int64. Es
        la misma trampa del 0xFFFFFFFF que ya mordio en Mft.ps1.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes,
        [int] $Desplazamiento = 0
    )

    if ($null -eq $Bytes -or $Desplazamiento -lt 0) { return $null }

    # La cabecera fija son 60 bytes. Sin ellos enteros no hay ni longitud
    # que leer, y un ToUInt32 a dos bytes del final LANZA. Ese es justo el
    # final de buffer que se da siempre en la ultima vuelta del recorrido.
    if (($Desplazamiento + 60) -gt $Bytes.Length) { return $null }

    $o = $Desplazamiento

    # A long y no a int. ToUInt32 devuelve un UInt32, y un registro que
    # declare 0xFFFFFFFF -basura, o relleno leido al reves- REVIENTA al
    # convertirlo a int por desbordamiento. En long cabe y se rechaza por
    # absurdo, que es lo que toca.
    $largo = [long][BitConverter]::ToUInt32($Bytes, $o)

    # Un registro no puede medir menos que su cabecera. Y esta guarda es
    # ademas lo que impide que el recorrido de Get-RegistrosUsn se quede
    # dando vueltas para siempre: avanza lo que diga Longitud, asi que
    # Longitud tiene que ser siempre mayor que cero. Un cero es, en la
    # practica, el final de los datos: el buffer que devuelve el sistema es
    # mas grande que lo que ha escrito en el, y lo que sobra son ceros.
    if ($largo -lt 60) { return $null }

    # Y que quepa de verdad. Un registro declarado mas largo que lo que
    # queda de buffer es lo normal en la ultima vuelta -la llamada al
    # sistema corta por donde le cabe-, no una corrupcion: se para y ya.
    if (($o + $largo) -gt $Bytes.Length) { return $null }

    # La version NO es un detalle de documentacion. Un USN_RECORD_V3 tiene
    # los mismos campos hasta el 8 y a partir de ahi la referencia ocupa
    # 128 bits, asi que TODOS los desplazamientos de abajo apuntan a otra
    # cosa: leerlo como si fuera V2 da un nombre sacado de la mitad de un
    # identificador y una razon que es medio numero de archivo. No falla
    # ruidosamente; devuelve basura con pinta de dato. Se exige 2.0 exacto:
    # una 2.1 no existe hoy, y si existiera algun dia, nadie sabe aqui que
    # le habrian cambiado.
    if ([BitConverter]::ToUInt16($Bytes, $o + 4) -ne 2) { return $null }
    if ([BitConverter]::ToUInt16($Bytes, $o + 6) -ne 0) { return $null }

    $largoNombre  = [int][BitConverter]::ToUInt16($Bytes, $o + 56)
    $offsetNombre = [int][BitConverter]::ToUInt16($Bytes, $o + 58)

    # LAS COMPROBACIONES DEL NOMBRE VAN DENTRO DEL "SI HAY NOMBRE", Y ESO
    # NO ES UN DETALLE DE ESTILO. Fuera, como FileNameOffset nunca puede
    # ser menor que 60, cualquier registro que declarara menos de 60 bytes
    # caia aqui -en el nombre- antes de que se notara que la guarda de
    # longitud minima de arriba habia dejado de funcionar. O sea que la
    # guarda que impide el bucle infinito estaba TAPADA: se podia romper
    # entera y la suite seguia verde, pasando por el motivo equivocado.
    # Salio mutando, no escribiendo.
    #
    # Y ademas es lo correcto por si mismo: sin nombre, FileNameOffset no
    # se lee, asi que no hay nada que validar sobre el.
    $nombre = ''
    if ($largoNombre -gt 0) {
        # UTF-16 son dos bytes por caracter siempre. Un numero impar de
        # bytes no es un nombre a medias: es que estos bytes no son lo que
        # dicen ser.
        if (($largoNombre % 2) -ne 0) { return $null }

        # El nombre no puede empezar dentro de la cabecera fija. Un registro
        # que lo declarara en el 0 devolveria su propia cabecera convertida
        # a texto, y eso -un nombre compuesto de numeros de referencia-
        # pasaria por un nombre raro pero valido.
        if ($offsetNombre -lt 60) { return $null }

        # Ni salirse del registro. Se compara contra la longitud DECLARADA
        # y no contra el final del buffer aposta: un nombre que se sale de
        # su registro y entra en el siguiente se leeria "bien" -hay bytes
        # ahi- y daria un nombre con la cabecera del siguiente pegada.
        if (($offsetNombre + $largoNombre) -gt $largo) { return $null }

        # UTF-16LE, que es como NTFS guarda los nombres. Decodificarlo como
        # ASCII dejaria un byte cero entre cada dos letras y perderia las
        # enyes y las tildes, que es medio disco duro de un usuario espanyol.
        $nombre = [Text.Encoding]::Unicode.GetString($Bytes, $o + $offsetNombre, $largoNombre)
    }

    # FILETIME: ticks de 100 ns desde el 1 de enero de 1601, UTC. Un valor
    # negativo, o uno mas alla del anyo 9999, no es una fecha, y
    # FromFileTimeUtc lanza con los dos. Una marca imposible no invalida el
    # registro -el nombre y la razon siguen siendo buenos-, asi que se deja
    # a $null y se sigue: es el unico campo del que se puede prescindir sin
    # que el cambio deje de significar lo que significa.
    $ticks = [BitConverter]::ToInt64($Bytes, $o + 32)
    $marca = $null
    if ($ticks -ge 0) {
        try { $marca = [DateTime]::FromFileTimeUtc($ticks) } catch { $marca = $null }
    }

    $referencia      = [BitConverter]::ToUInt64($Bytes, $o + 8)
    $referenciaPadre = [BitConverter]::ToUInt64($Bytes, $o + 16)
    $atributos       = [BitConverter]::ToUInt32($Bytes, $o + 52)

    return [pscustomobject]@{
        Longitud              = [int]$largo
        Referencia            = $referencia
        ReferenciaPadre       = $referenciaPadre
        NumeroReferencia      = Get-ReferenciaMft -Bytes $Bytes -Desde ($o + 8)
        NumeroReferenciaPadre = Get-ReferenciaMft -Bytes $Bytes -Desde ($o + 16)
        Usn                   = [BitConverter]::ToInt64($Bytes, $o + 24)
        Marca                 = $marca
        Razon                 = [BitConverter]::ToUInt32($Bytes, $o + 40)
        Origen                = [BitConverter]::ToUInt32($Bytes, $o + 44)
        IdSeguridad           = [BitConverter]::ToUInt32($Bytes, $o + 48)
        Atributos             = $atributos
        Nombre                = $nombre
        # FILE_ATTRIBUTE_DIRECTORY. Se decide aqui y no en quien llame
        # porque el diario no distingue de otra forma entre "se ha borrado
        # un archivo de 4 GB" y "se ha borrado una carpeta", y son dos
        # cosas muy distintas para el indice de espacio.
        EsCarpeta             = ($atributos -band 0x10) -ne 0
    }
}

function Get-RegistrosUsn {
    <#
    .SYNOPSIS
        Recorre un buffer con varios registros seguidos y devuelve los que
        valen, en orden, como array. Calculo puro, nunca lanza.

    .PARAMETER Bytes
        El buffer tal cual: registros pegados, cada uno empezando donde
        termina el anterior segun su Longitud. Puede venir con ceros o con
        basura detras del ultimo, y puede ser nulo.

    .NOTES
        SE PARA EN EL PRIMERO QUE NO VALE, Y NO SALTA POR ENCIMA.

        Un $null de Get-RegistroUsn no se esquiva avanzando a ojo. No se
        sabe cuanto media ese registro -por eso se ha rechazado-, asi que
        buscar el siguiente seria adivinar donde empieza, y un "registro"
        encontrado adivinando es un cambio inventado. Los tres casos que
        paran el recorrido se tratan igual y son igual de normales:
        Longitud a cero -el sistema devuelve un buffer mas grande que lo
        que escribe, y lo que sobra son ceros-, un registro cortado -la
        llamada corta por donde le cabe- y basura. Lo leido antes de eso
        vale y se devuelve; lo de despues, no se puede afirmar.

        EL RETURN NO LLEVA COMA, Y ESO ES A PROPOSITO. Los registros salen
        por la tuberia de uno en uno, como los de Read-TablaMaestra, y quien
        llama los recoge con @( ), que es el idioma de este proyecto para
        no depender de si han venido cero, uno o mil: en 5.1 un objeto
        suelto no tiene .Count. Con la coma -que aqui se usa solo para los
        byte[], que no deben enumerarse- el array llegaria como UN objeto,
        y @(Get-RegistrosUsn ...).Count valdria siempre 1. Ver
        docs/RELEVO.md.

        EL TOPE DE VUELTAS NO ES DESCONFIANZA: ES LO QUE HACE VISIBLE UN
        FALLO. El bucle termina solo porque Get-RegistroUsn rechaza toda
        longitud menor que 60, asi que $pos crece al menos 60 por vuelta.
        Si un dia esa guarda se tocara, esto se convertiria en un cuelgue
        con el programa entero detras -y con un cuelgue no hay prueba que
        se ponga roja: se queda colgada-. Con el tope, ese mismo fallo sale
        como un resultado equivocado, que si se puede ver. En un buffer de
        N bytes no caben mas de N/60 registros, asi que el tope no recorta
        ningun caso legitimo.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [byte[]] $Bytes
    )

    $registros = [Collections.Generic.List[object]]::new()
    if ($null -eq $Bytes) { return $registros.ToArray() }

    $largoBuffer = $Bytes.Length
    $tope = [int][Math]::Floor($largoBuffer / 60)
    $pos = 0
    $vueltas = 0
    while (($pos + 60) -le $largoBuffer -and $vueltas -lt $tope) {
        $vueltas++
        $registro = Get-RegistroUsn -Bytes $Bytes -Desplazamiento $pos
        if ($null -eq $registro) { break }
        $registros.Add($registro)
        $pos += $registro.Longitud
    }

    return $registros.ToArray()
}

# =====================================================================
#  LA DECISION: se puede leer el diario de esta unidad, y si no, por que
# =====================================================================

function Test-PuedeLeerDiarioUsn {
    <#
    .SYNOPSIS
        Motivo por el que NO se puede leer el diario USN de una unidad, o
        cadena vacia si se puede. Decision pura.

    .DESCRIPTION
        Leer el diario exige abrir el volumen en crudo, que es EXACTAMENTE
        lo que exige leer la tabla maestra: NTFS, disco fijo o extraible, y
        permisos de administrador. Por eso las tres primeras comprobaciones
        no se repiten aqui: las decide Test-PuedeLeerTablaMaestra, en el
        mismo orden y con los mismos motivos. Es la unica llamada viva que
        le queda a esa funcion desde que [VEL-01] se midio y se descarto, y
        es una buena razon para que Mft.ps1 siga en el nucleo.

        La cuarta condicion es propia del diario: TIENE QUE ESTAR ACTIVO.
        Windows lo lleva encendido en el disco del sistema, pero en otros
        discos puede no existir, y un administrador lo puede apagar. Sin
        diario no hay cambios que leer, y entonces no queda otra que
        recorrer las carpetas.

        LA CONSECUENCIA QUE HAY QUE DECIR EN VOZ ALTA: el programa arranca
        SIN privilegios, asi que en el uso normal esta funcion contesta
        "hace falta administrador" y el camino rapido no se usa. [VEL-02]
        acelera el segundo analisis solo cuando se ejecuta elevado, que es
        cuando ya se ejecutan los modulos que lo piden. No es un fallo de
        diseño: es el precio de no pedir permisos que el usuario no ha
        dado. Pero conviene no venderlo como "el segundo analisis es
        instantaneo" a secas.

    .PARAMETER DiarioActivo
        Si la consulta del diario devolvio un identificador. $null vale
        "no se ha podido preguntar", y se trata como no activo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $SistemaArchivos,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $TipoUnidad,
        [Parameter(Mandatory)] [AllowNull()] [bool] $EsAdministrador,
        [Parameter(Mandatory)] [AllowNull()] [object] $DiarioActivo
    )

    $motivo = Test-PuedeLeerTablaMaestra -SistemaArchivos $SistemaArchivos `
                                          -TipoUnidad $TipoUnidad `
                                          -EsAdministrador $EsAdministrador
    if (-not [string]::IsNullOrWhiteSpace($motivo)) {
        # Los motivos de la tabla maestra hablan de "la tabla maestra".
        # Aqui se habla del diario, que es lo que el usuario va a ver.
        return $motivo.Replace('la tabla maestra', 'el diario de cambios').Replace('La tabla maestra', 'El diario de cambios')
    }

    if ($null -eq $DiarioActivo -or -not [bool]$DiarioActivo) {
        return 'Esta unidad no tiene activo el diario de cambios de NTFS, así que se recorren las carpetas.'
    }

    return ''
}

# =====================================================================
#  LA LECTURA: lo unico de este archivo que toca el disco.
#  NO VERIFICADO: solo se puede ejecutar en Windows.
# =====================================================================

$script:DiarioUsnInterop = $null

function Initialize-InteropDiarioUsn {
    <#
    .SYNOPSIS
        Compila una vez la llamada a DeviceIoControl. Devuelve $true si se
        puede usar; $false, y nunca lanza, si no.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne $script:DiarioUsnInterop) { return [bool]$script:DiarioUsnInterop }

    $esWindows = $IsWindows -or ($null -eq $IsWindows)
    if (-not $esWindows) { $script:DiarioUsnInterop = $false; return $false }

    try {
        if (-not ('Cachivache.DiarioUsn' -as [type])) {
            # Solo DeviceIoControl. El volumen se abre con FileStream, igual
            # que en Read-TablaMaestra, y se le pide su SafeFileHandle: asi
            # no hace falta CreateFile ni CloseHandle a mano, y el cierre
            # lo garantiza el Dispose del flujo.
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Cachivache {
    public static class DiarioUsn {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DeviceIoControl(
            SafeFileHandle hDevice, uint dwIoControlCode,
            IntPtr lpInBuffer, uint nInBufferSize,
            IntPtr lpOutBuffer, uint nOutBufferSize,
            out uint lpBytesReturned, IntPtr lpOverlapped);
    }
}
'@ -ErrorAction Stop
        }
        $script:DiarioUsnInterop = $true
    } catch {
        Write-Verbose ("No se ha podido preparar la lectura del diario USN: {0}" -f $_.Exception.Message)
        $script:DiarioUsnInterop = $false
    }
    return [bool]$script:DiarioUsnInterop
}

function Get-DatosDiarioUsn {
    <#
    .SYNOPSIS
        Consulta el diario USN de una unidad: su identificador y el rango
        de USN que conserva. NO VERIFICADO: solo se ejecuta en Windows.

    .DESCRIPTION
        ESTA FUNCION NO SE HA EJECUTADO NUNCA, por el mismo motivo que
        Read-TablaMaestra: donde se escribio no hay NTFS ni volumen que
        abrir. Las funciones puras de arriba estan probadas byte a byte;
        esta es una hipotesis escrita en PowerShell hasta que alguien la
        ejecute en un Windows real. Ver docs/VEL-02-MEDICION.md.

        NUNCA LANZA. Devuelve $null ante cualquier problema, y quien llama
        recorre las carpetas de siempre.

        Lo que devuelve es EXACTAMENTE lo que Test-IndiceUtilizable pide
        del disco: IdDiario y PrimerUsn, mas el UsnSiguiente que hay que
        guardar como corte del indice nuevo.

    .PARAMETER Unidad
        'C:' sin barra final.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Unidad)

    if (-not (Initialize-InteropDiarioUsn)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Unidad)) { return $null }
    $letra = $Unidad.Trim().TrimEnd([char]'\', [char]'/')
    if ($letra -notmatch '^[A-Za-z]:$') { return $null }

    # FSCTL_QUERY_USN_JOURNAL. USN_JOURNAL_DATA_V0 son siete enteros de 64
    # bits: UsnJournalID, FirstUsn, NextUsn, LowestValidUsn, MaxUsn,
    # MaximumSize, AllocationDelta. 56 bytes.
    $FSCTL_QUERY_USN_JOURNAL = [uint32]0x000900F4
    $flujo = $null
    $salida = [IntPtr]::Zero
    try {
        $flujo = [IO.FileStream]::new(('\\.\' + $letra), [IO.FileMode]::Open,
                                       [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $salida = [Runtime.InteropServices.Marshal]::AllocHGlobal(64)
        $devueltos = [uint32]0
        $ok = [Cachivache.DiarioUsn]::DeviceIoControl(
            $flujo.SafeFileHandle, $FSCTL_QUERY_USN_JOURNAL,
            [IntPtr]::Zero, [uint32]0, $salida, [uint32]64, [ref]$devueltos, [IntPtr]::Zero)
        if (-not $ok -or $devueltos -lt 56) {
            Write-Verbose ("El diario USN de {0} no responde (Win32 {1})." -f $letra,
                           [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            return $null
        }
        $bytes = [byte[]]::new(56)
        [Runtime.InteropServices.Marshal]::Copy($salida, $bytes, 0, 56)
        return [pscustomobject]@{
            Unidad         = $letra
            IdDiario       = [BitConverter]::ToUInt64($bytes, 0)
            PrimerUsn      = [BitConverter]::ToInt64($bytes, 8)
            UsnSiguiente   = [BitConverter]::ToInt64($bytes, 16)
            UsnMasBajo     = [BitConverter]::ToInt64($bytes, 24)
            UsnMaximo      = [BitConverter]::ToInt64($bytes, 32)
        }
    } catch {
        Write-Verbose ("No se ha podido consultar el diario USN de {0}: {1}" -f $letra, $_.Exception.Message)
        return $null
    } finally {
        if ($salida -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($salida) }
        if ($null -ne $flujo) { $flujo.Dispose() }
    }
}

function Read-DiarioUsn {
    <#
    .SYNOPSIS
        Lee los registros del diario USN desde un USN dado. NO VERIFICADO:
        solo se ejecuta en Windows.

    .DESCRIPTION
        La misma advertencia que Get-DatosDiarioUsn: escrita a ciegas,
        pendiente de ejecutarse en un Windows real. NUNCA LANZA; devuelve
        $null ante cualquier problema.

        Se pide con ReturnOnlyOnClose a 1: solo los registros de cierre,
        que son el estado final de cada archivo. El diario emite crear,
        extender y cerrar como tres registros, y para el indice solo
        importa el ultimo. Eso reduce el volumen varias veces, y
        ConvertTo-CambiosIndice colapsa lo que quede.

    .PARAMETER Desde
        USN a partir del cual leer: el UsnCorte que guardo el indice.

    .PARAMETER MaximoBytes
        Tope total a leer. Un diario grande son cientos de megabytes; si
        hay que leer tanto, ya no compensa (ver docs/VEL-02-MEDICION.md) y
        es mejor rendirse y recorrer las carpetas.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Unidad,
        [Parameter(Mandatory)] [AllowNull()] $IdDiario,
        [Parameter(Mandatory)] [AllowNull()] $Desde,
        [int] $MaximoBytes = 64MB
    )

    if (-not (Initialize-InteropDiarioUsn)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Unidad) -or $null -eq $IdDiario -or $null -eq $Desde) { return $null }
    $letra = $Unidad.Trim().TrimEnd([char]'\', [char]'/')
    if ($letra -notmatch '^[A-Za-z]:$') { return $null }

    $FSCTL_READ_USN_JOURNAL = [uint32]0x000900BB
    $tamanoBloque = 1MB
    $flujo = $null
    $entrada = [IntPtr]::Zero
    $salida  = [IntPtr]::Zero
    try {
        $flujo = [IO.FileStream]::new(('\\.\' + $letra), [IO.FileMode]::Open,
                                       [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $entrada = [Runtime.InteropServices.Marshal]::AllocHGlobal(40)
        $salida  = [Runtime.InteropServices.Marshal]::AllocHGlobal($tamanoBloque)

        $registros = [Collections.Generic.List[object]]::new()
        $usnActual = [int64]$Desde
        $leidoTotal = 0

        while ($leidoTotal -lt $MaximoBytes) {
            # READ_USN_JOURNAL_DATA_V0: StartUsn(8) ReasonMask(4)
            # ReturnOnlyOnClose(4) Timeout(8) BytesToWaitFor(8) UsnJournalID(8)
            $peticion = [byte[]]::new(40)
            [Array]::Copy([BitConverter]::GetBytes([int64]$usnActual),  0, $peticion,  0, 8)
            [Array]::Copy([BitConverter]::GetBytes([uint32]0xFFFFFFFF), 0, $peticion,  8, 4)
            [Array]::Copy([BitConverter]::GetBytes([uint32]1),          0, $peticion, 12, 4)
            # Timeout y BytesToWaitFor a cero: devolver lo que haya y no esperar.
            [Array]::Copy([BitConverter]::GetBytes([uint64]$IdDiario),  0, $peticion, 32, 8)
            [Runtime.InteropServices.Marshal]::Copy($peticion, 0, $entrada, 40)

            $devueltos = [uint32]0
            $ok = [Cachivache.DiarioUsn]::DeviceIoControl(
                $flujo.SafeFileHandle, $FSCTL_READ_USN_JOURNAL,
                $entrada, [uint32]40, $salida, [uint32]$tamanoBloque, [ref]$devueltos, [IntPtr]::Zero)
            if (-not $ok) {
                Write-Verbose ("La lectura del diario USN de {0} ha fallado (Win32 {1})." -f $letra,
                               [Runtime.InteropServices.Marshal]::GetLastWin32Error())
                return $null
            }
            # Los primeros 8 bytes son el USN por el que seguir. Si solo
            # vienen esos, no hay mas registros.
            if ($devueltos -le 8) { break }

            $bloque = [byte[]]::new([int]$devueltos)
            [Runtime.InteropServices.Marshal]::Copy($salida, $bloque, 0, [int]$devueltos)
            $siguiente = [BitConverter]::ToInt64($bloque, 0)

            $cuerpo = [byte[]]::new([int]$devueltos - 8)
            [Array]::Copy($bloque, 8, $cuerpo, 0, $cuerpo.Length)
            foreach ($r in @(Get-RegistrosUsn -Bytes $cuerpo)) { $registros.Add($r) }

            $leidoTotal += [int]$devueltos
            # Sin avance no hay progreso: se corta para no dar vueltas.
            if ($siguiente -le $usnActual) { break }
            $usnActual = $siguiente
        }

        if ($leidoTotal -ge $MaximoBytes) {
            Write-Verbose ("El diario de {0} es demasiado grande para compensar: se recorren las carpetas." -f $letra)
            return $null
        }

        return [pscustomobject]@{
            Registros    = $registros.ToArray()
            UsnSiguiente = $usnActual
            BytesLeidos  = $leidoTotal
        }
    } catch {
        Write-Verbose ("No se ha podido leer el diario USN de {0}: {1}" -f $letra, $_.Exception.Message)
        return $null
    } finally {
        if ($entrada -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($entrada) }
        if ($salida  -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($salida) }
        if ($null -ne $flujo) { $flujo.Dispose() }
    }
}
