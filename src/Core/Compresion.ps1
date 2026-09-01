<#
.SYNOPSIS
    Compresion NTFS: lo que un archivo ocupa de verdad en el disco.
#>

# =====================================================================
#  COMPRESION NTFS  ([VIS-05])
# =====================================================================
#
# NTFS sabe comprimir un archivo de forma transparente: se lee y se
# escribe igual que cualquier otro, pero en el disco ocupa menos. La
# entrada de directorio sigue diciendo el tamano LOGICO -lo que mide el
# archivo al leerlo-, que es lo que devuelve FileInfo.Length y lo unico
# que este programa ha mirado nunca.
#
# POR QUE ESO IMPORTA AQUI Y NO EN CUALQUIER PROGRAMA
#
# Cachivache no describe archivos: PROMETE ESPACIO. En una carpeta
# comprimida, borrar 100 MB logicos devuelve al disco los 30 MB que
# ocupaban de verdad. Prometer 100 es prometer de mas, y el usuario lo
# descubre despues de borrar, cuando ya no puede comprobar nada.
#
# Es la contabilidad falsa de [VIS-03] con los enlaces duros y la de
# [COR-03] con los marcadores de OneDrive otra vez, por un mecanismo
# distinto y en la misma direccion: el disco tiene menos de lo que la
# entrada de directorio dice.
#
# LAS DOS MITADES, Y POR QUE ESTAN SEPARADAS
#
# Test-EstaComprimido y Get-EspacioRecuperable son calculo puro y se
# prueban aqui, en Linux, sin NTFS. Get-TamanoEnDisco es la unica parte
# que toca el sistema operativo, y es la unica que puede fallar. Al
# partirlo asi, la DECISION -cuanto se promete- se puede probar entera
# aunque la medicion no exista.

# Valor numerico y no [IO.FileAttributes]::Compressed a proposito, por lo
# mismo que en Test-EsMarcadorNube: un nombre de enumeracion que no exista
# en la version de .NET que toque lanza en tiempo de ejecucion, y un
# numero no. Este si existe en .NET Framework, pero la regla vale para
# todos o no vale para ninguno.
$script:AtributoComprimido = 0x800    # FILE_ATTRIBUTE_COMPRESSED

function Test-EstaComprimido {
    <#
    .SYNOPSIS
        .Lleva este archivo la marca de comprimido de NTFS?

    .DESCRIPTION
        CALCULO PURO sobre los atributos, para poder probarlo sin NTFS y
        sin Windows.

        Los atributos son una mascara de bits: un archivo comprimido
        normal llega con Archive y Compressed puestos a la vez, y uno
        dentro de una carpeta del sistema con tres o cuatro mas. Por eso
        se pregunta por el BIT y no por la igualdad, que solo acertaria
        con el archivo que no tiene ningun otro atributo.

    .PARAMETER Atributos
        El valor de FileInfo.Attributes, como entero. Se acepta nulo
        porque un atributo que no se pudo leer llega asi, y responder que
        no es la respuesta segura: contar de mas un archivo que quiza esta
        comprimido solo cuesta una promesa mas pequena.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [AllowNull()] [int] $Atributos)

    return (($Atributos -band $script:AtributoComprimido) -ne 0)
}

function Get-TamanoEnDisco {
    <#
    .SYNOPSIS
        Cuantos bytes ocupa de verdad un archivo, o $null si no se sabe.

    .DESCRIPTION
        Es la unica parte de [VIS-05] que toca el sistema operativo.

        En Windows lo contesta GetCompressedFileSize de kernel32, que es
        la respuesta buena para las tres cosas que hacen que Length mienta
        -compresion NTFS, archivos dispersos y flujos alternativos-, y no
        abre el archivo, asi que no dispara ninguna descarga de OneDrive
        (ver [COR-03]).

        DEVOLVER $null Y NO CERO ES EL PUNTO ENTERO DE ESTA FUNCION.

        Cero significa "ocupa cero bytes", o sea "borrarlo no libera
        nada". Fuera de Windows, o si la llamada falla, lo cierto es que
        NO SE SABE, y las dos cosas no se parecen en nada: con cero, un
        analisis en un equipo donde la medicion falle prometeria cero para
        todo. $null deja que Get-EspacioRecuperable vuelva al tamano
        logico, que es el comportamiento de siempre.

        Y NO LANZA NUNCA. Se la va a llamar una vez por archivo dentro de
        un recorrido de cientos de miles: una excepcion aqui no es un
        archivo mal medido, es un analisis entero que se cae.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $null }

    # $IsWindows NO EXISTE en PowerShell 5.1: vale $null, y ahi "-not
    # $IsWindows" seria verdadero JUSTO EN WINDOWS. Ver docs/RELEVO.md.
    if (-not ($IsWindows -or ($null -eq $IsWindows))) { return $null }

    try {
        if (-not ('Cachivache.Kernel32' -as [type])) {
            Add-Type -Namespace 'Cachivache' -Name 'Kernel32' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint = "GetCompressedFileSizeW", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern uint GetCompressedFileSize(string lpFileName, out uint lpFileSizeHigh);
'@ -ErrorAction Stop
        }

        # El prefijo de ruta larga, por lo mismo que en [COR-02]: las rutas
        # que desbordan MAX_PATH son justo las de node_modules y las caches
        # anidadas, que es donde vive la basura que este programa busca.
        $rutaApi = ConvertTo-RutaLarga -Ruta $Ruta

        $alto = [uint32]0
        $bajo = [Cachivache.Kernel32]::GetCompressedFileSize($rutaApi, [ref] $alto)

        # INVALID_FILE_SIZE se escribe [uint32]::MaxValue y no 0xFFFFFFFF a
        # proposito: ese literal hexadecimal no vale lo mismo en las dos
        # versiones de PowerShell, y comparar contra el numero equivocado
        # daria por buena una medicion fallida.
        #
        # El segundo miembro no sobra: un archivo enorme puede ocupar
        # exactamente esa cifra en la parte baja y ser una medicion valida.
        # La API lo distingue con GetLastError, no con el valor.
        if ($bajo -eq [uint32]::MaxValue) {
            if ([Runtime.InteropServices.Marshal]::GetLastWin32Error() -ne 0) { return $null }
        }

        return [double](([uint64]$alto -shl 32) -bor [uint64]$bajo)
    } catch {
        # Un archivo bloqueado, una unidad que se ha ido o un sistema sin
        # esa API son "no lo se", nunca "cero".
        return $null
    }
}

function Get-EspacioRecuperable {
    <#
    .SYNOPSIS
        Cuantos bytes se pueden PROMETER por borrar esto. Calculo puro.

    .DESCRIPTION
        La decision central de [VIS-05], en una sola funcion para que la
        vista, el informe y el motor no puedan decir tres cifras distintas
        del mismo archivo.

        La regla, y su porque:

          - Si se sabe lo que ocupa en disco, SE PROMETE ESO. Es lo que el
            disco recupera de verdad al borrarlo, comprimido o no.
          - Si no se sabe -$null-, se promete el tamano logico, que es lo
            que el programa ha hecho siempre. No saber no puede empeorar
            el comportamiento anterior.

        Nunca sale un numero negativo, y un tamano en disco absurdo
        (negativo) se trata como cero antes que como una promesa: la
        unica invariante que da sentido a este punto es que lo prometido
        no pueda pasarse de lo que el disco tiene.

    .PARAMETER TamanoLogico
        Lo que mide el archivo al leerlo (FileInfo.Length).

    .PARAMETER TamanoEnDisco
        Lo que devuelve Get-TamanoEnDisco, con su $null incluido.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $TamanoLogico,
        [Parameter(Mandatory)] [AllowNull()] $TamanoEnDisco
    )

    $logico = ConvertTo-DoubleSeguro -Valor $TamanoLogico
    if ($logico -lt 0) { $logico = 0.0 }

    # La comparacion con $null va ANTES de convertir, y ese orden es la
    # funcion entera: ConvertTo-DoubleSeguro traduce $null a 0.0 -y hace
    # bien, para eso existe-, asi que convertir primero borraria la
    # diferencia entre "no se sabe" y "no ocupa nada". Lo primero devuelve
    # el tamano logico; lo segundo, cero.
    if ($null -eq $TamanoEnDisco) { return $logico }

    $disco = ConvertTo-DoubleSeguro -Valor $TamanoEnDisco
    if ($disco -lt 0) { $disco = 0.0 }
    return $disco
}

function Format-DetalleCompresion {
    <#
    .SYNOPSIS
        El texto que ve el usuario cuando algo esta comprimido con NTFS.

    .DESCRIPTION
        Se ensenyan LAS DOS cifras, que es el criterio de aceptacion de
        [VIS-05]: un archivo de 100 MB que ocupa 30 MB se cuenta como 30,
        y el usuario tiene que poder ver de donde sale ese 30. Ensenyar
        solo la cifra pequenya arreglaria la aritmetica y dejaria al
        usuario sin entender por que su carpeta de 100 MB libera 30.

        Cuando no se sabe lo que ocupa en disco se dice, en vez de
        callarlo: una cifra sin aviso se lee como una medicion.

    .PARAMETER Archivos
        Cuantos archivos comprimidos se estan resumiendo. Cero -el valor
        por defecto- habla de uno solo, sin contarlo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $TamanoLogico,
        [Parameter(Mandatory)] [AllowNull()] $TamanoEnDisco,
        [int] $Archivos = 0
    )

    $logico = ConvertTo-DoubleSeguro -Valor $TamanoLogico
    if ($logico -lt 0) { $logico = 0.0 }
    $textoLogico = Format-Tamano -Bytes $logico

    # Singular y plural de verdad. "1 elementos" es la marca de un
    # programa que no se ha releido, y aqui el numero es casi siempre 1.
    $etiqueta = if ($Archivos -le 0) {
        'Comprimido con NTFS'
    } elseif ($Archivos -eq 1) {
        '1 archivo comprimido con NTFS'
    } else {
        ('{0} archivos comprimidos con NTFS' -f $Archivos)
    }

    if ($null -eq $TamanoEnDisco) {
        # Los parentesis alrededor del -f no son decoracion: -f se enlaza
        # mas fuerte que +, y sin ellos el {0} sale literal en pantalla.
        # Ha mordido cuatro veces en este proyecto.
        return (('{0}: {1} de tamaño real. No se ha podido leer cuánto ocupa en disco, así que se cuenta entero.') -f
                $etiqueta, $textoLogico)
    }

    $disco = Get-EspacioRecuperable -TamanoLogico $logico -TamanoEnDisco $TamanoEnDisco
    $textoDisco = Format-Tamano -Bytes $disco

    if ($disco -ge $logico) {
        # Comprimido pero sin ganancia: pasa con lo que ya venia
        # comprimido -video, .zip- y con los archivos diminutos, que
        # ocupan un grupo entero. Decir "se liberan X, no X" seria ruido.
        return (('{0}: {1} de tamaño real que ocupan {2} en disco.') -f
                $etiqueta, $textoLogico, $textoDisco)
    }

    return (('{0}: {1} de tamaño real que ocupan {2} en disco. Se liberan {2}, no {1}.') -f
            $etiqueta, $textoLogico, $textoDisco)
}
