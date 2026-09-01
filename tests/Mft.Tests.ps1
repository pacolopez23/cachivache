<#
    Pruebas de la lectura de la tabla maestra de NTFS. Ver [VEL-01].

    LO QUE HACE QUE ESTAS PRUEBAS VALGAN ALGO: el sector de arranque y los
    registros se construyen AQUI, byte a byte. No hay ningun NTFS en el
    entorno donde se ejecuta la suite, asi que la alternativa era no probar
    el parseo -o "probarlo" contra el mismo codigo que lo escribe-, y un
    parseador binario que nadie ha visto acertar sobre bytes conocidos no
    esta probado en ningun sentido util de la palabra.

    Construir los bytes a mano tiene ademas un efecto que no se esperaba:
    obliga a escribir el formato dos veces, una para leerlo y otra para
    escribirlo, y las dos veces mirando la documentacion. Los dos errores
    que se encontraron al escribir esto -el desplazamiento del tamanyo real
    en $FILE_NAME y el numero de entradas de la tabla de correcciones-
    salieron justo de que las dos mitades no cuadraban.

    Lo que NO se prueba aqui es Read-TablaMaestra de verdad: abre un
    volumen en crudo y eso no existe fuera de Windows. Solo se comprueba lo
    unico que se puede comprobar desde aqui, que es que no lanza y que
    devuelve $null.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Los tres escriben un entero en el orden de Intel y NO ESCRIBEN NADA
    # si no cabe. Ese silencio es deliberado y solo vale aqui: varias
    # pruebas construyen registros hostiles a proposito -un primer
    # atributo declarado en el byte 1020- y sin la guarda el constructor
    # reventaba antes de que la funcion que se esta probando llegara a
    # ver nada. Un fallo del arnes disfrazado de fallo del programa.
    function Set-U16 {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param([byte[]] $Bytes, [int] $Desde, [int] $Valor)
        if ($Desde -lt 0 -or ($Desde + 2) -gt $Bytes.Length) { return }
        $t = [BitConverter]::GetBytes([uint16]$Valor)
        [Array]::Copy($t, 0, $Bytes, $Desde, 2)
    }

    function Set-U32 {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param([byte[]] $Bytes, [int] $Desde, [long] $Valor)
        if ($Desde -lt 0 -or ($Desde + 4) -gt $Bytes.Length) { return }
        $t = [BitConverter]::GetBytes([uint32]$Valor)
        [Array]::Copy($t, 0, $Bytes, $Desde, 4)
    }

    function Set-U64 {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param([byte[]] $Bytes, [int] $Desde, [long] $Valor)
        if ($Desde -lt 0 -or ($Desde + 8) -gt $Bytes.Length) { return }
        $t = [BitConverter]::GetBytes([uint64]$Valor)
        [Array]::Copy($t, 0, $Bytes, $Desde, 8)
    }

    function New-SectorArranque {
        <#
            Un sector de arranque NTFS de 512 bytes. Los desplazamientos
            son los del formato; los valores por defecto son los de un
            disco corriente: sectores de 512, clusters de 4 KB, registros
            de MFT de 1 KB.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param(
            [string] $Firma = 'NTFS    ',
            [int] $BytesPorSector = 512,
            [int] $SectoresPorCluster = 8,
            [int] $ByteRegistro = 0xF6,
            [long] $ClusterMft = 786432,
            [long] $TotalSectores = 500000000
        )

        $s = [byte[]]::new(512)
        $s[0] = 0xEB; $s[1] = 0x52; $s[2] = 0x90
        $letras = [Text.Encoding]::ASCII.GetBytes($Firma)
        [Array]::Copy($letras, 0, $s, 3, [Math]::Min(8, $letras.Length))

        Set-U16 -Bytes $s -Desde 0x0B -Valor $BytesPorSector
        $s[0x0D] = [byte]$SectoresPorCluster
        $s[0x15] = 0xF8
        Set-U64 -Bytes $s -Desde 0x28 -Valor $TotalSectores
        Set-U64 -Bytes $s -Desde 0x30 -Valor $ClusterMft
        Set-U64 -Bytes $s -Desde 0x38 -Valor 2
        # Byte con signo: 0xF6 es -10, o sea 2^10 = 1024 bytes por registro.
        $s[0x40] = [byte]$ByteRegistro
        $s[0x44] = 1
        $s[0x1FE] = 0x55; $s[0x1FF] = 0xAA
        # LA COMA NO SOBRA. Sin ella PowerShell desenvuelve el array al
        # devolverlo y quien lo recoge se queda con un Object[] de bytes;
        # al pasarlo luego a un parametro [byte[]] se CONVIERTE, o sea que
        # la funcion recibe una COPIA. Eso dejaba hueca la prueba de que
        # Get-RegistroMft no toca los bytes del llamante: pasara lo que
        # pasara dentro, el array de aqui no se enteraba. La mutacion que
        # quitaba la copia defensiva no la cazaba nadie.
        return ,$s
    }

    function Add-AtributoNombre {
        <#
            Escribe un atributo $FILE_NAME (0x30) residente en $Desde y
            devuelve cuanto ocupa. La cabecera residente son 24 bytes y el
            contenido empieza con 0x42 bytes fijos antes del nombre.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param(
            [byte[]] $Bytes,
            [int] $Desde,
            [string] $Nombre,
            [long] $Padre = 5,
            [int] $EspacioNombres = 1,
            [long] $BytesReserva = 0
        )

        $nombreBytes = [Text.Encoding]::Unicode.GetBytes($Nombre)
        $contenido = 0x42 + $nombreBytes.Length
        $largo = 24 + $contenido
        if (($largo % 8) -ne 0) { $largo += 8 - ($largo % 8) }
        # Por lo mismo que las guardas de Set-U16: si el atributo no cabe,
        # el registro hostil se queda sin el y la prueba sigue siendo sobre
        # la funcion, no sobre el constructor.
        if ($Desde -lt 0 -or ($Desde + $largo) -gt $Bytes.Length) { return $largo }

        Set-U32 -Bytes $Bytes -Desde $Desde -Valor 0x30
        Set-U32 -Bytes $Bytes -Desde ($Desde + 4) -Valor $largo
        $Bytes[$Desde + 8] = 0
        $Bytes[$Desde + 9] = 0
        Set-U32 -Bytes $Bytes -Desde ($Desde + 0x10) -Valor $contenido
        Set-U16 -Bytes $Bytes -Desde ($Desde + 0x14) -Valor 24

        $v = $Desde + 24
        # La referencia del padre son 6 bytes de numero y 2 de secuencia.
        # La secuencia se pone a proposito distinta de cero: si el codigo
        # se olvidara de quitarla, el padre saldria astronomico.
        Set-U32 -Bytes $Bytes -Desde $v -Valor ($Padre -band 0xFFFFFFFF)
        Set-U16 -Bytes $Bytes -Desde ($v + 4) -Valor 0
        Set-U16 -Bytes $Bytes -Desde ($v + 6) -Valor 7
        Set-U64 -Bytes $Bytes -Desde ($v + 0x30) -Valor $BytesReserva
        $Bytes[$v + 0x40] = [byte]($nombreBytes.Length / 2)
        $Bytes[$v + 0x41] = [byte]$EspacioNombres
        [Array]::Copy($nombreBytes, 0, $Bytes, $v + 0x42, $nombreBytes.Length)

        return $largo
    }

    function Add-AtributoDatos {
        <#
            Un atributo $DATA (0x80). Residente si -Residente; si no, no
            residente con su tamanyo reservado y su tamanyo real, que es lo
            que tiene cualquier archivo que pase de unos cientos de bytes.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param(
            [byte[]] $Bytes,
            [int] $Desde,
            [long] $TamanoReal,
            [long] $TamanoReserva = 0,
            [switch] $Residente,
            [string] $NombreFlujo = ''
        )

        if ($Desde -lt 0 -or ($Desde + 72) -gt $Bytes.Length) { return 72 }
        Set-U32 -Bytes $Bytes -Desde $Desde -Valor 0x80
        $Bytes[$Desde + 9] = [byte]$NombreFlujo.Length
        Set-U16 -Bytes $Bytes -Desde ($Desde + 0x0A) -Valor 64

        if ($Residente) {
            $largo = 32
            $Bytes[$Desde + 8] = 0
            Set-U32 -Bytes $Bytes -Desde ($Desde + 4) -Valor $largo
            Set-U32 -Bytes $Bytes -Desde ($Desde + 0x10) -Valor $TamanoReal
            Set-U16 -Bytes $Bytes -Desde ($Desde + 0x14) -Valor 24
            return $largo
        }

        $largo = 72
        $Bytes[$Desde + 8] = 1
        Set-U32 -Bytes $Bytes -Desde ($Desde + 4) -Valor $largo
        Set-U16 -Bytes $Bytes -Desde ($Desde + 0x20) -Valor 64
        if ($TamanoReserva -le 0) { $TamanoReserva = $TamanoReal }
        Set-U64 -Bytes $Bytes -Desde ($Desde + 0x28) -Valor $TamanoReserva
        Set-U64 -Bytes $Bytes -Desde ($Desde + 0x30) -Valor $TamanoReal
        Set-U64 -Bytes $Bytes -Desde ($Desde + 0x38) -Valor $TamanoReal
        return $largo
    }

    function Set-Correcciones {
        <#
            Aplica las correcciones de secuencia igual que hace NTFS al
            escribir: guarda en la tabla los dos ultimos bytes de cada
            sector y los sustituye por la marca.

            Sin esto los registros de aqui no serian registros de NTFS, y la
            prueba del nombre que cruza el byte 510 no probaria nada.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param([byte[]] $Bytes, [int] $BytesPorSector = 512, [int] $Marca = 1)

        $desplazamiento = [BitConverter]::ToUInt16($Bytes, 0x04)
        $sectores = $Bytes.Length / $BytesPorSector
        Set-U16 -Bytes $Bytes -Desde $desplazamiento -Valor $Marca
        for ($s = 0; $s -lt $sectores; $s++) {
            $fin = (($s + 1) * $BytesPorSector) - 2
            $destino = $desplazamiento + 2 + ($s * 2)
            $Bytes[$destino]     = $Bytes[$fin]
            $Bytes[$destino + 1] = $Bytes[$fin + 1]
            $Bytes[$fin]     = $Bytes[$desplazamiento]
            $Bytes[$fin + 1] = $Bytes[$desplazamiento + 1]
        }
    }

    function New-RegistroMft {
        <#
            Un registro completo de 1 KB, con su cabecera, su tabla de
            correcciones, sus atributos y su marca de fin.

            -RellenoAntes empuja los atributos con un $STANDARD_INFORMATION
            de mentira, y existe para poder colocar el nombre justo encima
            del byte 510, que es donde NTFS pisa los datos.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param(
            [string] $Nombre = 'archivo.txt',
            [long] $Padre = 5,
            [long] $Tamano = 4096,
            [switch] $EsCarpeta,
            [switch] $Borrado,
            [switch] $DatosResidentes,
            [switch] $SinDatos,
            [long] $Reserva = 0,
            [int] $EspacioNombres = 1,
            [long] $BytesReserva = 0,
            [int] $RellenoAntes = 0,
            [int] $PrimerAtributo = 0x38,
            [int] $EntradasUsa = 3,
            [int] $Largo = 1024
        )

        $r = [byte[]]::new($Largo)
        $r[0] = 0x46; $r[1] = 0x49; $r[2] = 0x4C; $r[3] = 0x45   # "FILE"
        Set-U16 -Bytes $r -Desde 0x04 -Valor 0x30
        Set-U16 -Bytes $r -Desde 0x06 -Valor $EntradasUsa
        Set-U16 -Bytes $r -Desde 0x10 -Valor 1
        Set-U16 -Bytes $r -Desde 0x12 -Valor 1
        Set-U16 -Bytes $r -Desde 0x14 -Valor $PrimerAtributo

        $banderas = 0
        if (-not $Borrado)  { $banderas = $banderas -bor 0x0001 }
        if ($EsCarpeta)     { $banderas = $banderas -bor 0x0002 }
        Set-U16 -Bytes $r -Desde 0x16 -Valor $banderas
        Set-U32 -Bytes $r -Desde 0x1C -Valor $Largo

        $p = $PrimerAtributo
        if ($RellenoAntes -gt 0) {
            Set-U32 -Bytes $r -Desde $p -Valor 0x10
            Set-U32 -Bytes $r -Desde ($p + 4) -Valor $RellenoAntes
            Set-U16 -Bytes $r -Desde ($p + 0x14) -Valor 24
            $p += $RellenoAntes
        }

        $p += Add-AtributoNombre -Bytes $r -Desde $p -Nombre $Nombre -Padre $Padre `
                                 -EspacioNombres $EspacioNombres -BytesReserva $BytesReserva

        if (-not $SinDatos -and -not $EsCarpeta) {
            $p += Add-AtributoDatos -Bytes $r -Desde $p -TamanoReal $Tamano `
                                    -TamanoReserva $Reserva -Residente:$DatosResidentes
        }

        Set-U32 -Bytes $r -Desde $p -Valor 4294967295
        Set-U32 -Bytes $r -Desde 0x18 -Valor ($p + 8)
        Set-Correcciones -Bytes $r
        # La coma, por lo mismo que en New-SectorArranque.
        return ,$r
    }

}

Describe 'Cuando se puede leer la tabla maestra, y por que no' {

    It 'en un disco fijo NTFS con permisos, se puede' {
        Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' `
            -EsAdministrador $true | Should -Be ''
    }

    It 'y en un disco extraible formateado en NTFS, tambien' {
        # No es un caso raro: un disco USB de 2 TB viene en NTFS casi
        # siempre. Solo las llaves pequenyas vienen en exFAT o FAT32.
        Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'Removable' `
            -EsAdministrador $true | Should -Be ''
    }

    # LA LISTA DE -ForEach VA AQUI, EN EL CUERPO DEL DESCRIBE, Y NO EN UN
    # BeforeAll. Es el reverso exacto de la regla del relevo -"si un It lo
    # lee, se construye en un BeforeAll"-, y por eso conviene tenerlo
    # escrito: -ForEach no lo lee el It, lo lee el DESCUBRIMIENTO de
    # Pester, que es cuando se decide cuantas pruebas hay. Desde un
    # BeforeAll llega vacia y las nueve pruebas no llegan a existir.
    #
    # Aqui salto: Pester 6 rechaza un -ForEach vacio. En Pester 5 no
    # saltaba, y el sintoma habria sido el de siempre: la suite en verde
    # con nueve pruebas menos. El comando corto que solo mira PassedCount y
    # FailedCount tampoco lo ve, porque el contenedor entero falla sin
    # sumar ni un fallo.
    It 'todo "no" viene con su motivo escrito: <Sf> en <Tipo>' -ForEach @(
        @{ Sf = 'FAT32'; Tipo = 'Fixed';     Admin = $true }
        @{ Sf = 'exFAT'; Tipo = 'Removable'; Admin = $true }
        @{ Sf = 'NTFS';  Tipo = 'Network';   Admin = $true }
        @{ Sf = 'NTFS';  Tipo = 'CDRom';     Admin = $true }
        @{ Sf = 'NTFS';  Tipo = 'Ram';       Admin = $true }
        @{ Sf = 'NTFS';  Tipo = 'Unknown';   Admin = $true }
        @{ Sf = 'NTFS';  Tipo = 'Fixed';     Admin = $false }
        @{ Sf = '';      Tipo = 'Fixed';     Admin = $true }
        @{ Sf = 'NTFS';  Tipo = '';          Admin = $true }
    ) {
        # La invariante de esta funcion. Un booleano dejaria al llamante
        # inventandose la explicacion, y las cuatro razones por las que
        # esto no se puede hacer son muy distintas entre si.
        $motivo = Test-PuedeLeerTablaMaestra -SistemaArchivos $Sf -TipoUnidad $Tipo `
                    -EsAdministrador $Admin
        $motivo | Should -Not -BeNullOrEmpty
        $motivo.Length | Should -BeGreaterThan 20 -Because 'un motivo tiene que explicar algo'
    }

    It 'el motivo dice CUAL es el obstaculo, no solo que lo hay' {
        # Comprobar el mismo veredicto y no solo que se rechaza: una
        # version anterior rechazaba la unidad de red por el sistema de
        # archivos, que es cierto pero no es la razon.
        (Test-PuedeLeerTablaMaestra -SistemaArchivos 'FAT32' -TipoUnidad 'Fixed' -EsAdministrador $true) |
            Should -Match 'FAT32'
        (Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'Network' -EsAdministrador $true) |
            Should -Match 'red'
        (Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'CDRom' -EsAdministrador $true) |
            Should -Match 'CDRom'
        (Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $false) |
            Should -Match 'administrador'
    }

    It 'no propone hacerse administrador cuando eso no arreglaria nada' {
        # El orden de las comprobaciones ES la prueba. A quien analiza una
        # unidad de red o una llave en exFAT no se le puede decir "reinicia
        # como administrador": lo haria, y seguiria sin funcionar.
        foreach ($caso in @(
            @{ Sf = 'NTFS';  Tipo = 'Network' },
            @{ Sf = 'exFAT'; Tipo = 'Removable' },
            @{ Sf = 'NTFS';  Tipo = 'CDRom' })) {
            $motivo = Test-PuedeLeerTablaMaestra -SistemaArchivos $caso.Sf `
                        -TipoUnidad $caso.Tipo -EsAdministrador $false
            $motivo | Should -Not -Match 'administrador' -Because (
                'el obstaculo que el usuario no puede quitar se nombra antes')
        }
    }

    It 'con nulos no revienta, y dice que no' {
        { Test-PuedeLeerTablaMaestra -SistemaArchivos $null -TipoUnidad $null -EsAdministrador $false } |
            Should -Not -Throw
        Test-PuedeLeerTablaMaestra -SistemaArchivos $null -TipoUnidad $null -EsAdministrador $false |
            Should -Not -BeNullOrEmpty
        Test-PuedeLeerTablaMaestra -SistemaArchivos '   ' -TipoUnidad '   ' -EsAdministrador $true |
            Should -Not -BeNullOrEmpty
    }

    It 'no consulta nada: la misma entrada da siempre la misma respuesta' {
        # Es lo que la hace probable aqui, donde no hay ni una unidad NTFS.
        $a = Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $true
        $b = Test-PuedeLeerTablaMaestra -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $true
        $a | Should -Be $b
    }
}

Describe 'El sector de arranque de NTFS' {

    It 'saca los cuatro numeros de un sector corriente' {
        $d = Get-DatosArranqueNtfs -Bytes (New-SectorArranque)
        $d                      | Should -Not -BeNullOrEmpty
        $d.BytesPorSector       | Should -Be 512
        $d.SectoresPorCluster   | Should -Be 8
        $d.BytesPorCluster      | Should -Be 4096
        $d.BytesPorRegistro     | Should -Be 1024
        $d.ClusterMft           | Should -Be 786432
        $d.TotalSectores        | Should -Be 500000000
    }

    It 'entiende el tamanyo de registro escrito en clusters' {
        # El byte de 0x40 tiene dos significados segun su signo. Positivo
        # son CLUSTERS por registro; negativo son BYTES. Copiar mal esa
        # asimetria da registros de un gigabyte.
        $d = Get-DatosArranqueNtfs -Bytes (New-SectorArranque -ByteRegistro 1)
        $d.BytesPorRegistro | Should -Be 4096
    }

    It 'entiende los clusters grandes, que se escriben como negativos' {
        # 0xF9 leido con signo es -7, o sea 2^7 = 128 sectores por cluster.
        # Leerlo sin signo daria 249, y todas las posiciones del disco
        # saldrian mal a partir de ahi.
        $d = Get-DatosArranqueNtfs -Bytes (New-SectorArranque -SectoresPorCluster 0xF9)
        $d.SectoresPorCluster | Should -Be 128
        $d.BytesPorCluster    | Should -Be 65536
    }

    It 'un sector que no es NTFS devuelve $null, no numeros' {
        # El punto entero de la funcion. Estos bytes tambien "se pueden
        # leer": dan un cluster de MFT en algun sitio del disco, y el
        # llamante buscaria alli.
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -Firma 'MSDOS5.0') | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -Firma 'NTFS_XYZ') | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -Firma 'ntfs    ') | Should -BeNullOrEmpty
    }

    It 'un sector corto no se interpreta a medias' {
        Get-DatosArranqueNtfs -Bytes ([byte[]]::new(256)) | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes ([byte[]]::new(0))   | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque)[0..99] | Should -BeNullOrEmpty
    }

    It 'los numeros imposibles se rechazan uno a uno' {
        # Cada uno de estos ha aparecido de verdad al leer basura: se
        # comprueban por separado para que el fallo diga cual fue.
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -BytesPorSector 0)     | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -BytesPorSector 3000)  | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -BytesPorSector 40000) | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -SectoresPorCluster 0) | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -ByteRegistro 0)       | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -ByteRegistro 0xC0)    | Should -BeNullOrEmpty
        Get-DatosArranqueNtfs -Bytes (New-SectorArranque -ClusterMft 0)         | Should -BeNullOrEmpty
    }

    It 'con nulos no revienta' {
        { Get-DatosArranqueNtfs -Bytes $null } | Should -Not -Throw
        Get-DatosArranqueNtfs -Bytes $null | Should -BeNullOrEmpty
        { Get-DatosArranqueNtfs -Bytes @() } | Should -Not -Throw
    }

    It 'Get-ReferenciaMft se queda con el numero y tira la secuencia' {
        # Se prueba aparte de Get-RegistroMft porque es la funcion que
        # decide si un archivo encuentra a su carpeta. Con la secuencia
        # dentro, "la carpeta 5" pasa a ser un numero de quince cifras y el
        # archivo queda colgando de la nada.
        $b = [byte[]]::new(16)
        Set-U32 -Bytes $b -Desde 0 -Valor 4711
        Set-U16 -Bytes $b -Desde 4 -Valor 0
        Set-U16 -Bytes $b -Desde 6 -Valor 65535
        Get-ReferenciaMft -Bytes $b -Desde 0 | Should -Be 4711

        # Y un numero de registro que de verdad pasa de 32 bits: los seis
        # bytes son seis, no cuatro.
        Set-U32 -Bytes $b -Desde 8 -Valor 0
        Set-U16 -Bytes $b -Desde 12 -Valor 1
        Get-ReferenciaMft -Bytes $b -Desde 8 | Should -Be 4294967296
    }

    It 'Get-ReferenciaMft fuera de rango devuelve cero en vez de lanzar' {
        $b = [byte[]]::new(16)
        { Get-ReferenciaMft -Bytes $b -Desde 14 }   | Should -Not -Throw
        Get-ReferenciaMft -Bytes $b     -Desde 14   | Should -Be 0
        Get-ReferenciaMft -Bytes $b     -Desde -1   | Should -Be 0
        Get-ReferenciaMft -Bytes $null  -Desde 0    | Should -Be 0
    }

    It 'Get-EnteroLargoLe lee 64 bits sin desbordar ni lanzar' {
        $b = [byte[]]::new(16)
        Set-U64 -Bytes $b -Desde 0 -Valor 4294967296
        Get-EnteroLargoLe -Bytes $b -Desde 0 | Should -Be 4294967296
        Set-U64 -Bytes $b -Desde 8 -Valor 1099511627775
        Get-EnteroLargoLe -Bytes $b -Desde 8 | Should -Be 1099511627775
        # Fuera de rango devuelve cero en vez de lanzar: estos bytes vienen
        # de un disco y el llamante esta en mitad de un bucle de un millon.
        Get-EnteroLargoLe -Bytes $b -Desde 12   | Should -Be 0
        Get-EnteroLargoLe -Bytes $b -Desde -4   | Should -Be 0
        Get-EnteroLargoLe -Bytes $null -Desde 0 | Should -Be 0
    }
}

Describe 'Un registro de la tabla maestra' {

    It 'saca las cinco cosas de un archivo corriente' {
        $r = Get-RegistroMft -Bytes (New-RegistroMft -Nombre 'informe.pdf' -Padre 1234 -Tamano 8192)
        $r                  | Should -Not -BeNullOrEmpty
        $r.Nombre           | Should -Be 'informe.pdf'
        $r.ReferenciaPadre  | Should -Be 1234
        $r.EsCarpeta        | Should -BeFalse
        $r.EnUso            | Should -BeTrue
        $r.Bytes            | Should -Be 8192
    }

    It 'quita el numero de secuencia de la referencia del padre' {
        # Los 16 bits altos de una referencia son de secuencia. Dejarlos
        # dentro convierte "la carpeta 5" en un numero de quince cifras que
        # no casa con ningun padre, y el archivo queda colgando de la nada.
        # El constructor pone la secuencia a 7 justo para esto.
        $r = Get-RegistroMft -Bytes (New-RegistroMft -Padre 5)
        $r.ReferenciaPadre | Should -Be 5
    }

    It 'una carpeta se reconoce, y no aporta bytes' {
        # -BytesReserva 4096 no es adorno: una carpeta SI lleva un tamanyo
        # escrito en su $FILE_NAME -el de su indice-, y sin ponerlo aqui el
        # cero salia solo y la prueba pasaba aunque el codigo no vaciara
        # nada. Sumar ese indice contaria dos veces lo que ya cuentan los
        # hijos.
        $r = Get-RegistroMft -Bytes (New-RegistroMft -Nombre 'Documentos' -EsCarpeta -BytesReserva 4096)
        $r.EsCarpeta | Should -BeTrue
        $r.Nombre    | Should -Be 'Documentos'
        $r.Bytes     | Should -Be 0 -Because 'lo que cuelga de la carpeta ya lo cuentan sus hijos'
    }

    It 'un registro borrado se marca como tal en vez de desaparecer' {
        # NTFS no limpia el registro al borrar: solo apaga un bit. El
        # nombre y el tamanyo siguen ahi, y contarlos seria ensenyar
        # espacio que no existe. Quien decide que hacer es el llamante,
        # pero tiene que poder saberlo.
        $r = Get-RegistroMft -Bytes (New-RegistroMft -Nombre 'viejo.tmp' -Borrado)
        $r        | Should -Not -BeNullOrEmpty
        $r.EnUso  | Should -BeFalse
        $r.Nombre | Should -Be 'viejo.tmp'
    }

    It 'de un archivo grande sale el tamanyo REAL, no el reservado' {
        # Un archivo no residente reserva clusters enteros. Sumar lo
        # reservado inflaria el total del disco, que es justo el numero que
        # este camino existe para dar bien.
        #
        # LOS DOS NUMEROS TIENEN QUE SER DISTINTOS. Antes el constructor
        # ponia el reservado igual que el real, y entonces leer uno u otro
        # daba lo mismo: la prueba pasaba con las dos versiones del codigo.
        # Salio al mutar, no al escribirla.
        $r = Get-RegistroMft -Bytes (New-RegistroMft -Tamano 5000 -Reserva 8192)
        $r.Bytes | Should -Be 5000
        $r.Bytes | Should -Not -Be 8192
    }

    It 'de un archivo pequenyo, que vive dentro del registro, tambien' {
        $r = Get-RegistroMft -Bytes (New-RegistroMft -Tamano 300 -DatosResidentes)
        $r.Bytes | Should -Be 300
    }

    It 'un flujo alterno no se suma al tamanyo del archivo' {
        <#
            Un archivo descargado de internet lleva un segundo $DATA con
            nombre -"Zone.Identifier"- de unas decenas de bytes. Son bytes
            de verdad en el disco, pero NO son el tamanyo del archivo: si
            se suman, o peor, si se coge el ultimo que aparece, un archivo
            de 5 KB pasa a pesar 26 bytes en la vista de archivos.

            El alterno va DESPUES del principal a proposito: puesto antes,
            quedarse con el ultimo daria la respuesta correcta por
            casualidad y la prueba no diria nada.
        #>
        $r = [byte[]]::new(1024)
        $r[0] = 0x46; $r[1] = 0x49; $r[2] = 0x4C; $r[3] = 0x45
        Set-U16 -Bytes $r -Desde 0x04 -Valor 0x30
        Set-U16 -Bytes $r -Desde 0x06 -Valor 3
        Set-U16 -Bytes $r -Desde 0x14 -Valor 0x38
        Set-U16 -Bytes $r -Desde 0x16 -Valor 1
        $p = 0x38
        $p += Add-AtributoNombre -Bytes $r -Desde $p -Nombre 'descarga.zip'
        $p += Add-AtributoDatos  -Bytes $r -Desde $p -TamanoReal 5000
        $p += Add-AtributoDatos  -Bytes $r -Desde $p -TamanoReal 26 -NombreFlujo 'Zone.Identifier'
        Set-U32 -Bytes $r -Desde $p -Valor 4294967295
        Set-Correcciones -Bytes $r

        (Get-RegistroMft -Bytes $r).Bytes | Should -Be 5000
    }

    It 'sin $DATA cae al tamanyo que guarda el nombre' {
        $r = Get-RegistroMft -Bytes (New-RegistroMft -SinDatos -BytesReserva 777)
        $r.Bytes | Should -Be 777
    }

    Context 'cuando el archivo tiene varios nombres' {

        It 'se queda con el nombre de Windows y no con el de MS-DOS' {
            # Un archivo con nombre largo tiene DOS atributos $FILE_NAME.
            # Coger el primero que aparezca ensenyaria "PROGRA~1" en el
            # mapa del disco, que no es un nombre que nadie reconozca.
            $r = [byte[]]::new(1024)
            $r[0] = 0x46; $r[1] = 0x49; $r[2] = 0x4C; $r[3] = 0x45
            Set-U16 -Bytes $r -Desde 0x04 -Valor 0x30
            Set-U16 -Bytes $r -Desde 0x06 -Valor 3
            Set-U16 -Bytes $r -Desde 0x14 -Valor 0x38
            Set-U16 -Bytes $r -Desde 0x16 -Valor 1
            $p = 0x38
            # El corto va PRIMERO: si el codigo se quedara con el primero,
            # esta prueba pasaria por accidente al reves.
            $p += Add-AtributoNombre -Bytes $r -Desde $p -Nombre 'PROGRA~1' -EspacioNombres 2
            $p += Add-AtributoNombre -Bytes $r -Desde $p -Nombre 'Program Files' -EspacioNombres 1
            $p += Add-AtributoDatos -Bytes $r -Desde $p -TamanoReal 1024
            Set-U32 -Bytes $r -Desde $p -Valor 4294967295
            Set-Correcciones -Bytes $r

            (Get-RegistroMft -Bytes $r).Nombre | Should -Be 'Program Files'
        }

        It 'y con el corto se queda solo si no hay otro' {
            $r = Get-RegistroMft -Bytes (New-RegistroMft -Nombre 'CORTO~1.TXT' -EspacioNombres 2)
            $r.Nombre | Should -Be 'CORTO~1.TXT'
        }
    }

    Context 'las correcciones de secuencia' {

        It 'un nombre que cruza el final del sector se lee entero' {
            <#
                LA PRUEBA MAS IMPORTANTE DE ESTE ARCHIVO. NTFS pisa los dos
                ultimos bytes de cada sector con una marca. Sin deshacerlo,
                un nombre colocado encima del byte 510 sale con dos bytes
                cambiados -o sea, con una letra distinta- y el fallo
                aparece en un archivo de cada tantos, nunca en el que
                estabas mirando.

                El relleno coloca el atributo en 408, o sea el nombre en
                498: con diez letras cruza justo el 510.
            #>
            $bytes = New-RegistroMft -Nombre 'cruzando1.log' -RellenoAntes 352

            # Guarda: si la marca no estuviera puesta, esta prueba no
            # estaria comprobando nada y pasaria igual.
            $marca = [BitConverter]::ToUInt16($bytes, 0x30)
            [BitConverter]::ToUInt16($bytes, 510) | Should -Be $marca -Because (
                'el registro sintetico tiene que llevar la marca donde la pone NTFS')

            (Get-RegistroMft -Bytes $bytes).Nombre | Should -Be 'cruzando1.log'
        }

        It 'un registro roto a medias se tira en vez de leerse mal' {
            # Si los dos ultimos bytes de un sector no llevan la marca, NTFS
            # mismo considera que la escritura se quedo a medias. Devolver
            # un nombre de ahi seria inventarselo.
            $bytes = New-RegistroMft -Nombre 'aguas.dat'
            $bytes[1022] = 0x99
            $bytes[1023] = 0x99
            Get-RegistroMft -Bytes $bytes | Should -BeNullOrEmpty
        }

        It 'una tabla de correcciones imposible tambien' {
            Get-RegistroMft -Bytes (New-RegistroMft -EntradasUsa 0)    | Should -BeNullOrEmpty
            Get-RegistroMft -Bytes (New-RegistroMft -EntradasUsa 1)    | Should -BeNullOrEmpty
            Get-RegistroMft -Bytes (New-RegistroMft -EntradasUsa 9000) | Should -BeNullOrEmpty
        }
    }

    Context 'lo que no es un registro' {

        It 'unos bytes que no empiezan por FILE devuelven $null' {
            # "BAAD" lo escribe el propio NTFS en un registro que detecto
            # corrupto, y los huecos de la tabla son ceros. Los dos son
            # normales: la MFT esta llena de sitios donde no hay nada.
            $malo = New-RegistroMft
            $malo[0] = 0x42; $malo[1] = 0x41; $malo[2] = 0x41; $malo[3] = 0x44
            Get-RegistroMft -Bytes $malo | Should -BeNullOrEmpty
            Get-RegistroMft -Bytes ([byte[]]::new(1024)) | Should -BeNullOrEmpty
        }

        It 'un buffer corto no se lee a medias' {
            Get-RegistroMft -Bytes ([byte[]]::new(10)) | Should -BeNullOrEmpty
            Get-RegistroMft -Bytes ([byte[]]::new(0))  | Should -BeNullOrEmpty
            Get-RegistroMft -Bytes (New-RegistroMft)[0..40] | Should -BeNullOrEmpty
        }

        It 'con nulos no revienta' {
            { Get-RegistroMft -Bytes $null } | Should -Not -Throw
            Get-RegistroMft -Bytes $null | Should -BeNullOrEmpty
        }

        It 'un desplazamiento de atributo fuera del registro no lanza' {
            # Estos bytes vienen de un disco que puede estar danyado. Una
            # excepcion de indice a 300.000 registros de haber empezado se
            # llevaria por delante el analisis entero.
            { Get-RegistroMft -Bytes (New-RegistroMft -PrimerAtributo 5000) } | Should -Not -Throw
            { Get-RegistroMft -Bytes (New-RegistroMft -PrimerAtributo 1020) } | Should -Not -Throw
            { Get-RegistroMft -Bytes (New-RegistroMft -PrimerAtributo 0) }    | Should -Not -Throw
        }

        It 'un atributo que mide cero tira el registro entero' {
            # Un atributo de longitud cero no avanza: el bucle se quedaria
            # releyendo el mismo sitio. Devolver lo leido hasta ahi seria
            # peor que no devolver nada, porque pasaria por un archivo de
            # verdad con un tamanyo inventado.
            $bytes = New-RegistroMft
            Set-U32 -Bytes $bytes -Desde 0x3C -Valor 0
            Set-Correcciones -Bytes $bytes
            $reloj = [Diagnostics.Stopwatch]::StartNew()
            { Get-RegistroMft -Bytes $bytes } | Should -Not -Throw
            $reloj.Stop()
            Get-RegistroMft -Bytes $bytes | Should -BeNullOrEmpty
            $reloj.ElapsedMilliseconds | Should -BeLessThan 2000
        }

        It 'y un atributo que se sale del registro, tambien' {
            # Se comprueba APARTE del de longitud cero aunque acaben igual:
            # con las dos condiciones en un mismo if no se podia romper una
            # sola, y entonces no se sabia si la prueba tapaba las dos.
            $bytes = New-RegistroMft
            Set-U32 -Bytes $bytes -Desde 0x3C -Valor 99999
            Set-Correcciones -Bytes $bytes
            { Get-RegistroMft -Bytes $bytes } | Should -Not -Throw
            Get-RegistroMft -Bytes $bytes | Should -BeNullOrEmpty
        }
    }

    It 'no toca los bytes que le pasan' {
        # Las correcciones se deshacen ESCRIBIENDO en el array, y en el
        # lector de verdad ese array es un trozo de un buffer grande que se
        # reutiliza. Pisarlo corromperia los registros siguientes.
        $bytes = New-RegistroMft -Nombre 'intacto.txt'
        $copia = $bytes.Clone()
        [void](Get-RegistroMft -Bytes $bytes)
        [Convert]::ToBase64String($bytes) | Should -Be ([Convert]::ToBase64String($copia))
    }

    It 'un nombre con enye sale entero, porque NTFS lo guarda en UTF-16' {
        # Escrito por codigo de caracter para que este archivo siga siendo
        # ASCII puro y no dependa de su propia codificacion para probar
        # una codificacion.
        $nombre = 'Ma' + [char]0x00F1 + 'ana.txt'
        (Get-RegistroMft -Bytes (New-RegistroMft -Nombre $nombre)).Nombre | Should -Be $nombre
    }
}

Describe 'La lectura del volumen, que no se ha podido verificar' {

    <#
        Read-TablaMaestra abre \\.\C: en crudo. Aqui no hay Windows, no hay
        NTFS y no hay volumen, asi que estas dos pruebas NO dicen que la
        funcion lea bien: dicen lo unico que se puede decir desde aqui, que
        es que ante lo imposible devuelve $null y no lanza. Ver el
        comentario de la funcion y docs/VEL-01-MEDICION.md.
    #>

    It 'ante una unidad que no vale devuelve $null y no lanza' {
        foreach ($mala in @('', '   ', 'no es una unidad', 'CC:', '\\servidor\recurso', $null)) {
            { Read-TablaMaestra -Unidad $mala } | Should -Not -Throw
            Read-TablaMaestra -Unidad $mala | Should -BeNullOrEmpty
        }
    }

    It 'fuera de Windows no lo intenta siquiera' {
        # $IsWindows NO EXISTE en PowerShell 5.1: vale $null, y "-not
        # $IsWindows" seria verdadero justo en Windows. Por eso la funcion
        # pregunta por las dos cosas.
        if ($IsWindows -eq $false) {
            { Read-TablaMaestra -Unidad 'C:' } | Should -Not -Throw
            Read-TablaMaestra -Unidad 'C:' | Should -BeNullOrEmpty
        } else {
            Set-ItResult -Skipped -Because 'esto solo se puede comprobar fuera de Windows'
        }
    }
}
