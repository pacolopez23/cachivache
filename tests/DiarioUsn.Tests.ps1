<#
    Pruebas del parseo del diario de cambios de NTFS. Ver [VEL-02].

    LO QUE HACE QUE ESTAS PRUEBAS VALGAN ALGO: los registros se construyen
    AQUI, byte a byte, con los desplazamientos escritos otra vez desde la
    documentacion del formato. Aqui no hay NTFS, no hay volumen y no hay
    FSCTL_READ_USN_JOURNAL que llamar, asi que la alternativa era no probar
    el parseo -o "probarlo" contra el mismo codigo que lo escribe-, y un
    parseador binario que nadie ha visto acertar sobre bytes conocidos no
    esta probado en ningun sentido util de la palabra.

    Cada valor de prueba es DISTINTO de sus vecinos y distinto de cero. Si
    todo valiera 0 o 1, un parseo corrido un byte -o un campo leido del
    desplazamiento del de al lado- daria el mismo resultado y la prueba
    pasaria. Con valores que no se repiten, correrse un byte cambia el
    numero y la prueba se pone roja, que es lo que tiene que pasar.

    Y cada rechazo lleva su GEMELO SANO: antes de comprobar que un registro
    con la version 3 se rechaza, se comprueba que el mismo registro con la
    version 2 se acepta. Sin eso, una funcion que devolviera $null siempre
    pasaria todas las pruebas de rechazo.

    Archivo ASCII puro, como el resto de la suite: la enye se compone por
    codigo de caracter, para que una prueba sobre codificacion no dependa
    de la codificacion de su propio archivo.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # DiarioUsn.ps1 lo carga Bootstrap.ps1: aqui no se vuelve a cargar, para que
    # estas pruebas midan como se carga el programa de verdad.

    # Los tres escriben un entero en el orden de Intel y NO ESCRIBEN NADA
    # si no cabe. Ese silencio es deliberado y solo vale aqui: varias
    # pruebas construyen registros hostiles a proposito y sin la guarda el
    # constructor reventaria antes de que la funcion que se esta probando
    # llegara a ver nada. Un fallo del arnes disfrazado de fallo del
    # programa.
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

    # Con signo aposta: asi se puede escribir un FILETIME negativo -que es
    # una de las cosas que hay que rechazar- sin que el arnes reviente al
    # convertirlo. Los bytes que salen son los mismos que darian sin signo.
    function Set-I64 {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param([byte[]] $Bytes, [int] $Desde, [long] $Valor)
        if ($Desde -lt 0 -or ($Desde + 8) -gt $Bytes.Length) { return }
        $t = [BitConverter]::GetBytes([long]$Valor)
        [Array]::Copy($t, 0, $Bytes, $Desde, 8)
    }

    function New-RegistroUsnDePrueba {
        <#
            Un registro USN_RECORD_V2 completo, con su relleno hasta
            multiplo de ocho, igual que lo escribe el sistema.

            Los valores por omision son un registro corriente con todos los
            campos DISTINTOS entre si. Los parametros que acaban en
            "Declarad" escriben SOLO el campo de la cabecera, sin cambiar
            lo que hay en el buffer: son los que permiten construir un
            registro que miente sobre si mismo.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone bytes en memoria para las pruebas.')]
        [CmdletBinding()]
        param(
            [string] $Nombre = 'archivo.txt',
            # Numero 7 con secuencia 5, y padre 5 con secuencia 3.
            [long] $Referencia      = 0x0005000000000007,
            [long] $ReferenciaPadre = 0x0003000000000005,
            [long] $Usn   = 123456789012,
            # 2024-03-15 10:30:00 UTC, calculado con ToFileTimeUtc y
            # escrito aqui como numero para que la prueba no dependa del
            # codigo que se esta probando.
            [long] $Marca = 133549722000000000,
            # USN_REASON_CLOSE | USN_REASON_DATA_EXTEND: con el bit alto
            # puesto, que es el que se lee mal si alguien convierte a int.
            [long] $Razon       = 0x80000002L,
            [long] $Origen      = 3,
            [long] $IdSeguridad = 77,
            [long] $Atributos   = 0x20,
            [int] $VersionMayor = 2,
            [int] $VersionMenor = 0,
            # Donde se escribe el nombre de verdad, y donde dice la
            # cabecera que esta. Normalmente coinciden y valen 60.
            [int] $PosicionNombre = 60,
            [int] $DesplazamientoNombreDeclarado = 60,
            # Bytes de mas al final, multiplo de ocho: el sistema no los
            # pone, pero el formato los permite y son la forma de comprobar
            # que se avanza lo que dice Longitud y no lo que suma a ojo.
            [int] $RellenoExtra = 0,
            # -1 significa "el de verdad".
            [int] $LongitudDeclarada = -1,
            [int] $LongitudNombreDeclarada = -1
        )

        $bytesNombre = [Text.Encoding]::Unicode.GetBytes($Nombre)
        $largo = $PosicionNombre + $bytesNombre.Length
        if (($largo % 8) -ne 0) { $largo += 8 - ($largo % 8) }
        $largo += $RellenoExtra

        $b = [byte[]]::new($largo)
        $longitud = if ($LongitudDeclarada -ge 0) { $LongitudDeclarada } else { $largo }
        $largoNombre = if ($LongitudNombreDeclarada -ge 0) { $LongitudNombreDeclarada } else { $bytesNombre.Length }

        Set-U32 -Bytes $b -Desde 0  -Valor $longitud
        Set-U16 -Bytes $b -Desde 4  -Valor $VersionMayor
        Set-U16 -Bytes $b -Desde 6  -Valor $VersionMenor
        Set-I64 -Bytes $b -Desde 8  -Valor $Referencia
        Set-I64 -Bytes $b -Desde 16 -Valor $ReferenciaPadre
        Set-I64 -Bytes $b -Desde 24 -Valor $Usn
        Set-I64 -Bytes $b -Desde 32 -Valor $Marca
        Set-U32 -Bytes $b -Desde 40 -Valor $Razon
        Set-U32 -Bytes $b -Desde 44 -Valor $Origen
        Set-U32 -Bytes $b -Desde 48 -Valor $IdSeguridad
        Set-U32 -Bytes $b -Desde 52 -Valor $Atributos
        Set-U16 -Bytes $b -Desde 56 -Valor $largoNombre
        Set-U16 -Bytes $b -Desde 58 -Valor $DesplazamientoNombreDeclarado
        if ($bytesNombre.Length -gt 0) {
            [Array]::Copy($bytesNombre, 0, $b, $PosicionNombre, $bytesNombre.Length)
        }
        # LA COMA NO SOBRA. Sin ella PowerShell desenvuelve el array al
        # devolverlo y quien lo recoge se queda con un Object[]; al pasarlo
        # luego a un parametro [byte[]] se CONVIERTE, o sea que la funcion
        # recibe una COPIA y la prueba de "no toca el buffer" quedaria
        # hueca. Ver tests/Mft.Tests.ps1.
        return ,$b
    }

    function Join-Bytes {
        <#
            Pega varios arrays de bytes seguidos, como vienen los registros
            en el buffer del sistema. La coma, por lo mismo de arriba.
        #>
        [CmdletBinding()]
        param([byte[][]] $Trozos)
        $total = 0
        foreach ($t in $Trozos) { $total += $t.Length }
        $r = [byte[]]::new($total)
        $pos = 0
        foreach ($t in $Trozos) {
            [Array]::Copy($t, 0, $r, $pos, $t.Length)
            $pos += $t.Length
        }
        return ,$r
    }

    # "anyo.txt" con la enye de verdad: a, U+00F1, o, punto, t, x, t.
    # Siete caracteres, catorce bytes en UTF-16, y 60 + 14 = 74, que NO es
    # multiplo de ocho: el registro mide 80 y lleva seis bytes de relleno.
    $script:NombreEnye = 'a' + [char]0xF1 + 'o.txt'
}

Describe 'Get-RegistroUsn: un registro corriente, campo a campo' {

    BeforeAll {
        $script:Corriente = New-RegistroUsnDePrueba -Nombre $script:NombreEnye
        $script:R = Get-RegistroUsn -Bytes $script:Corriente
    }

    It 'el arnes construye un byte[] de verdad, y del tamanyo esperado' {
        # Guarda del arnes: si esto no fuera byte[], la funcion recibiria
        # una copia y la prueba de "no modifica el buffer" no probaria nada.
        $script:Corriente -is [byte[]] | Should -BeTrue
        $script:Corriente.Length | Should -Be 80
    }

    It 'devuelve un objeto' {
        $script:R | Should -Not -BeNullOrEmpty
    }

    It 'Longitud es la del registro con su relleno, no 60 mas el nombre' {
        $script:R.Longitud | Should -Be 80
        $script:R.Longitud | Should -BeOfType [int]
    }

    It 'Referencia y ReferenciaPadre salen enteras, con su secuencia, como uint64' {
        $script:R.Referencia      | Should -Be ([uint64]1407374883553287)   # 0x0005000000000007
        $script:R.ReferenciaPadre | Should -Be ([uint64]844424930131973)    # 0x0003000000000005
        $script:R.Referencia      | Should -BeOfType [uint64]
        $script:R.ReferenciaPadre | Should -BeOfType [uint64]
    }

    It 'NumeroReferencia y NumeroReferenciaPadre son la referencia sin la secuencia' {
        $script:R.NumeroReferencia      | Should -Be 7
        $script:R.NumeroReferenciaPadre | Should -Be 5
        $script:R.NumeroReferencia      | Should -BeOfType [double]
    }

    It 'Usn es un entero de 64 bits con signo' {
        $script:R.Usn | Should -Be 123456789012
        $script:R.Usn | Should -BeOfType [long]
    }

    It 'Marca es la fecha del FILETIME, en UTC' {
        $script:R.Marca | Should -BeOfType [datetime]
        $script:R.Marca | Should -Be ([DateTime]::new(2024, 3, 15, 10, 30, 0, [DateTimeKind]::Utc))
        $script:R.Marca.Kind | Should -Be ([DateTimeKind]::Utc)
    }

    It 'Razon conserva el bit alto: es uint32, no int' {
        # 0x80000002. Escrito en decimal porque el literal hexadecimal es
        # un Int32 negativo y [uint32] no lo acepta: esa es justo la trampa.
        $script:R.Razon | Should -Be ([uint32]2147483650)
        $script:R.Razon | Should -BeOfType [uint32]
    }

    It 'Origen e IdSeguridad se leen de sus sitios' {
        $script:R.Origen      | Should -Be ([uint32]3)
        $script:R.IdSeguridad | Should -Be ([uint32]77)
    }

    It 'Atributos es la mascara tal cual' {
        $script:R.Atributos | Should -Be ([uint32]0x20)
        $script:R.Atributos | Should -BeOfType [uint32]
    }

    It 'un archivo corriente no es carpeta' {
        $script:R.EsCarpeta | Should -BeFalse
    }

    It 'el nombre llega con su enye: UTF-16, no ASCII' {
        $script:R.Nombre | Should -Be $script:NombreEnye
        $script:R.Nombre.Length | Should -Be 7
        [int][char]$script:R.Nombre[1] | Should -Be 0xF1
    }
}

Describe 'Get-RegistroUsn: carpetas, nombres vacios y desplazamiento' {

    It 'FILE_ATTRIBUTE_DIRECTORY hace carpeta' {
        (Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Nombre 'carpeta' -Atributos 0x10)).EsCarpeta |
            Should -BeTrue
    }

    It 'la carpeta se reconoce aunque lleve mas bits puestos' {
        (Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Atributos 0x2010)).EsCarpeta | Should -BeTrue
    }

    It 'los bits vecinos del 0x10 no hacen carpeta' {
        (Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Atributos 0x08)).EsCarpeta | Should -BeFalse
        (Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Atributos 0x2020)).EsCarpeta | Should -BeFalse
    }

    It 'un nombre vacio es un registro valido, y mide 64: la cabecera de 60 redondeada a ocho' {
        # La primera version de esta prueba esperaba 60. El arnes -que
        # rellena a multiplo de ocho igual que el sistema- devolvio 64 y
        # tenia razon: 60 no es multiplo de ocho, asi que en un volumen de
        # verdad ningun registro mide 60.
        $b = New-RegistroUsnDePrueba -Nombre ''
        $b.Length | Should -Be 64
        $r = Get-RegistroUsn -Bytes $b
        $r | Should -Not -BeNullOrEmpty
        $r.Nombre   | Should -Be ''
        $r.Longitud | Should -Be 64
        $r.Usn      | Should -Be 123456789012
    }

    It 'sin nombre, el desplazamiento del nombre no se mira' {
        # Sin nombre no hay nada que leer en ese desplazamiento, asi que
        # un valor raro ahi no dice nada sobre el registro.
        $b = New-RegistroUsnDePrueba -Nombre '' -DesplazamientoNombreDeclarado 0
        (Get-RegistroUsn -Bytes $b).Nombre | Should -Be ''
    }

    It 'el nombre se lee de donde dice DesplazamientoNombre, no siempre del 60' {
        $b = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -PosicionNombre 68 -DesplazamientoNombreDeclarado 68
        $b.Length | Should -Be 88
        $r = Get-RegistroUsn -Bytes $b
        $r.Nombre   | Should -Be $script:NombreEnye
        $r.Longitud | Should -Be 88
    }

    Context 'con el registro en mitad del buffer' {
        BeforeAll {
            # Dieciseis bytes de basura delante, y el registro despues.
            $basura = [byte[]]::new(16)
            for ($i = 0; $i -lt 16; $i++) { $basura[$i] = 0xFF }
            $script:Metido = Join-Bytes -Trozos @($basura, (New-RegistroUsnDePrueba -Nombre $script:NombreEnye))
        }

        It 'con el desplazamiento correcto se lee entero' {
            $r = Get-RegistroUsn -Bytes $script:Metido -Desplazamiento 16
            $r | Should -Not -BeNullOrEmpty
            $r.Nombre | Should -Be $script:NombreEnye
            $r.Usn    | Should -Be 123456789012
        }

        It 'un byte antes o un byte despues no es un registro' {
            Get-RegistroUsn -Bytes $script:Metido -Desplazamiento 15 | Should -BeNullOrEmpty
            Get-RegistroUsn -Bytes $script:Metido -Desplazamiento 17 | Should -BeNullOrEmpty
        }

        It 'sin desplazamiento se lee desde el principio, que aqui es basura' {
            Get-RegistroUsn -Bytes $script:Metido | Should -BeNullOrEmpty
        }

        It 'un desplazamiento negativo no lanza: devuelve $null' {
            { Get-RegistroUsn -Bytes $script:Metido -Desplazamiento -1 } | Should -Not -Throw
            Get-RegistroUsn -Bytes $script:Metido -Desplazamiento -1 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-RegistroUsn: lo que se rechaza, con su gemelo sano al lado' {

    It 'el gemelo sano se acepta: si no, nada de lo de abajo prueba nada' {
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Nombre $script:NombreEnye) | Should -Not -BeNullOrEmpty
    }

    It 'un buffer nulo no lanza: devuelve $null' {
        { Get-RegistroUsn -Bytes $null } | Should -Not -Throw
        Get-RegistroUsn -Bytes $null | Should -BeNullOrEmpty
    }

    It 'un buffer vacio devuelve $null' {
        Get-RegistroUsn -Bytes ([byte[]]::new(0)) | Should -BeNullOrEmpty
    }

    It 'un buffer mas corto que la cabecera devuelve $null sin lanzar' {
        $corto = [byte[]]::new(59)
        [Array]::Copy((New-RegistroUsnDePrueba -Nombre $script:NombreEnye), 0, $corto, 0, 59)
        { Get-RegistroUsn -Bytes $corto } | Should -Not -Throw
        Get-RegistroUsn -Bytes $corto | Should -BeNullOrEmpty
    }

    It 'una Longitud que se sale del buffer devuelve $null' {
        # El registro entero esta bien; solo dice medir 88 en un buffer de 80.
        $b = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -LongitudDeclarada 88
        $b.Length | Should -Be 80
        Get-RegistroUsn -Bytes $b | Should -BeNullOrEmpty
    }

    It 'un registro cortado -la cabecera entera pero no el resto- devuelve $null' {
        $entero = New-RegistroUsnDePrueba -Nombre $script:NombreEnye
        $cortado = [byte[]]::new(72)
        [Array]::Copy($entero, 0, $cortado, 0, 72)
        Get-RegistroUsn -Bytes $cortado | Should -BeNullOrEmpty
    }

    It 'una Longitud menor que la cabecera devuelve $null' {
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -LongitudDeclarada 59) | Should -BeNullOrEmpty
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -LongitudDeclarada 0)  | Should -BeNullOrEmpty
    }

    It 'y tambien cuando NADA MAS esta mal: version 2.0 y sin nombre' {
        # Los dos de arriba llevan nombre, y un nombre que empieza en el 60
        # "se sale" de un registro que dice medir 59: caen en la guarda del
        # nombre, y la de la longitud minima podia desaparecer entera sin
        # que se notara. Salio mutando. Estos dos no tienen nombre, asi que
        # la unica guarda que los puede parar es la de la longitud, que es
        # la que impide que el recorrido se quede dando vueltas.
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Nombre '' -LongitudDeclarada 59) | Should -BeNullOrEmpty
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Nombre '' -LongitudDeclarada 0)  | Should -BeNullOrEmpty
    }

    It 'una Longitud de 0xFFFFFFFF no lanza por desbordamiento' {
        $b = New-RegistroUsnDePrueba -LongitudDeclarada 0
        Set-U32 -Bytes $b -Desde 0 -Valor 4294967295
        { Get-RegistroUsn -Bytes $b } | Should -Not -Throw
        Get-RegistroUsn -Bytes $b | Should -BeNullOrEmpty
    }

    It 'la version 3.0 se rechaza: sus campos estan en otro sitio' {
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -VersionMayor 3) | Should -BeNullOrEmpty
    }

    It 'la version 2.1 tambien: se exige 2.0 exacto' {
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -VersionMenor 1) | Should -BeNullOrEmpty
    }

    It 'y la 1.0, y la 0.0' {
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -VersionMayor 1) | Should -BeNullOrEmpty
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -VersionMayor 0) | Should -BeNullOrEmpty
    }

    It 'un nombre con un numero impar de bytes devuelve $null' {
        $sano = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -LongitudNombreDeclarada 14
        Get-RegistroUsn -Bytes $sano | Should -Not -BeNullOrEmpty
        $impar = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -LongitudNombreDeclarada 13
        Get-RegistroUsn -Bytes $impar | Should -BeNullOrEmpty
    }

    It 'un nombre que se sale del registro devuelve $null, aunque haya buffer detras' {
        # Con 22 bytes de nombre, 60 + 22 = 82 > 80. Y detras del registro
        # hay otro entero, o sea que si se comparara contra el buffer en
        # vez de contra la Longitud, se leeria "bien".
        $malo = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -LongitudNombreDeclarada 22
        $dos = Join-Bytes -Trozos @($malo, (New-RegistroUsnDePrueba))
        Get-RegistroUsn -Bytes $dos | Should -BeNullOrEmpty
    }

    It 'un nombre que se queda justo en el borde del registro se acepta' {
        # 60 + 20 = 80: el nombre entra en el relleno. Es la frontera de la
        # comprobacion de arriba, y tiene que caer del lado del si.
        $b = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -LongitudNombreDeclarada 20
        Get-RegistroUsn -Bytes $b | Should -Not -BeNullOrEmpty
    }

    It 'un nombre que empieza dentro de la cabecera devuelve $null' {
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -DesplazamientoNombreDeclarado 59) | Should -BeNullOrEmpty
        Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -DesplazamientoNombreDeclarado 0)  | Should -BeNullOrEmpty
    }
}

Describe 'Get-RegistroUsn: la marca de tiempo' {

    It 'cero es el 1 de enero de 1601' {
        (Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Marca 0)).Marca |
            Should -Be ([DateTime]::new(1601, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))
    }

    It 'un segundo son diez millones de ticks' {
        (Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Marca 10000000)).Marca |
            Should -Be ([DateTime]::new(1601, 1, 1, 0, 0, 1, [DateTimeKind]::Utc))
    }

    It 'un FILETIME negativo no es una fecha: Marca queda a $null y el registro sigue valiendo' {
        $r = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Nombre $script:NombreEnye -Marca -1)
        $r | Should -Not -BeNullOrEmpty
        $r.Marca  | Should -BeNullOrEmpty
        $r.Nombre | Should -Be $script:NombreEnye
    }

    It 'un FILETIME mas alla del anyo 9999 tampoco lanza: Marca a $null' {
        $b = New-RegistroUsnDePrueba -Marca ([long]::MaxValue)
        { Get-RegistroUsn -Bytes $b } | Should -Not -Throw
        $r = Get-RegistroUsn -Bytes $b
        $r | Should -Not -BeNullOrEmpty
        $r.Marca | Should -BeNullOrEmpty
    }
}

Describe 'Get-RegistroUsn: el mascarado de la secuencia' {

    It 'la misma fila con secuencias distintas da el mismo NumeroReferencia' {
        $a = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Referencia 0x0001000000000007)
        $b = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Referencia 0x0005000000000007)
        $c = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Referencia 0x0000000000000007)
        $a.NumeroReferencia | Should -Be 7
        $b.NumeroReferencia | Should -Be 7
        $c.NumeroReferencia | Should -Be 7
    }

    It 'y con la secuencia mas alta posible, tambien' {
        # 0xFFFF en los dos bytes altos. Se escribe a mano porque el
        # literal 0xFFFF000000000007 no cabe en un long positivo.
        $bytes = New-RegistroUsnDePrueba -Referencia 7
        $bytes[14] = 0xFF; $bytes[15] = 0xFF
        $r = Get-RegistroUsn -Bytes $bytes
        $r.NumeroReferencia | Should -Be 7
        $r.Referencia | Should -Be ([uint64]::MaxValue - [uint64]0x0000FFFFFFFFFFF8)
    }

    It 'mientras que Referencia si distingue las secuencias' {
        $a = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Referencia 0x0001000000000007)
        $b = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Referencia 0x0005000000000007)
        $a.Referencia | Should -Not -Be $b.Referencia
    }

    It 'se conservan los 48 bits del numero, no solo los 32 bajos' {
        # 2^40 + 1, con secuencia 1.
        $r = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -Referencia 0x0001010000000001)
        $r.NumeroReferencia | Should -Be 1099511627777
    }

    It 'el padre se mascara igual que el hijo' {
        $r = Get-RegistroUsn -Bytes (New-RegistroUsnDePrueba -ReferenciaPadre 0x00FF000000001234)
        $r.NumeroReferenciaPadre | Should -Be 0x1234
        $r.ReferenciaPadre | Should -Be ([uint64]0x00FF000000001234)
    }
}

Describe 'Get-RegistroUsn no modifica el buffer que le pasan' {

    It 'los bytes son los mismos antes y despues, byte a byte' {
        $b = New-RegistroUsnDePrueba -Nombre $script:NombreEnye
        $antes = ($b.Clone() | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        $r = Get-RegistroUsn -Bytes $b
        $r.Nombre | Should -Be $script:NombreEnye
        $despues = ($b | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        $despues | Should -Be $antes
    }
}

Describe 'Get-RegistrosUsn: varios registros seguidos' {

    BeforeAll {
        # Tres registros con longitudes distintas: 72, 80 y 80. El primero
        # -"a.txt", diez bytes- deja 60 + 10 = 70, que se rellena a 72: si
        # el recorrido avanzara 70, el segundo se leeria dos bytes corrido.
        $script:R1 = New-RegistroUsnDePrueba -Nombre 'a.txt' -Usn 100 -Referencia 11
        $script:R2 = New-RegistroUsnDePrueba -Nombre $script:NombreEnye -Usn 200 -Referencia 12
        $script:R3 = New-RegistroUsnDePrueba -Nombre 'carpeta' -Usn 300 -Referencia 13 -Atributos 0x10
        $script:Tres = Join-Bytes -Trozos @($script:R1, $script:R2, $script:R3)
        $script:Leidos = @(Get-RegistrosUsn -Bytes $script:Tres)
    }

    It 'el arnes ha pegado lo que dice: si no, nada de lo de abajo prueba nada' {
        $script:R1.Length | Should -Be 72
        $script:R2.Length | Should -Be 80
        $script:R3.Length | Should -Be 80
        $script:Tres.Length | Should -Be 232
    }

    It 'devuelve los tres' {
        $script:Leidos.Count | Should -Be 3
    }

    It 'en orden y con sus nombres' {
        $script:Leidos[0].Nombre | Should -Be 'a.txt'
        $script:Leidos[1].Nombre | Should -Be $script:NombreEnye
        $script:Leidos[2].Nombre | Should -Be 'carpeta'
    }

    It 'cada uno con lo suyo: el relleno del primero no descoloca al segundo' {
        $script:Leidos[0].Longitud | Should -Be 72
        @($script:Leidos | ForEach-Object { $_.Usn })              | Should -Be @(100, 200, 300)
        @($script:Leidos | ForEach-Object { $_.NumeroReferencia }) | Should -Be @(11, 12, 13)
        $script:Leidos[2].EsCarpeta | Should -BeTrue
        $script:Leidos[1].EsCarpeta | Should -BeFalse
    }

    It 'avanza lo que dice Longitud, no 60 mas el nombre' {
        # El primero lleva ocho bytes de relleno de mas. Un recorrido que
        # sumara a ojo caeria en mitad de ese relleno y no veria el segundo.
        $ancho = New-RegistroUsnDePrueba -Nombre 'a.txt' -Usn 100 -RellenoExtra 8
        $ancho.Length | Should -Be 80
        $l = @(Get-RegistrosUsn -Bytes (Join-Bytes -Trozos @($ancho, $script:R2)))
        $l.Count | Should -Be 2
        $l[0].Longitud | Should -Be 80
        $l[1].Nombre   | Should -Be $script:NombreEnye
    }

    It 'con un solo registro, @( ) lo cuenta como uno: el idioma del proyecto funciona' {
        # En 5.1 un objeto suelto no tiene .Count, asi que quien llama
        # envuelve siempre en @( ). Esto comprueba que el resultado se
        # deja envolver: si el return llevara coma, @( ) contaria UNO
        # tambien con tres registros, y los de arriba lo habrian visto.
        $uno = @(Get-RegistrosUsn -Bytes $script:R2)
        $uno.Count | Should -Be 1
        $uno[0].Nombre | Should -Be $script:NombreEnye
    }

    It 'un buffer nulo, vacio o mas corto que una cabecera da cero registros sin lanzar' {
        { Get-RegistrosUsn -Bytes $null } | Should -Not -Throw
        @(Get-RegistrosUsn -Bytes $null).Count | Should -Be 0
        @(Get-RegistrosUsn -Bytes ([byte[]]::new(0))).Count | Should -Be 0
        @(Get-RegistrosUsn -Bytes ([byte[]]::new(30))).Count | Should -Be 0
    }

    It 'no modifica el buffer' {
        $b = Join-Bytes -Trozos @($script:R1, $script:R2)
        $antes = ($b.Clone() | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        @(Get-RegistrosUsn -Bytes $b).Count | Should -Be 2
        ($b | ForEach-Object { '{0:X2}' -f $_ }) -join '' | Should -Be $antes
    }
}

Describe 'Get-RegistrosUsn: donde se para' {

    BeforeAll {
        $script:B1 = New-RegistroUsnDePrueba -Nombre 'uno.txt'  -Usn 1
        $script:B2 = New-RegistroUsnDePrueba -Nombre 'dos.txt'  -Usn 2
        $script:B3 = New-RegistroUsnDePrueba -Nombre 'tres.txt' -Usn 3
        $script:Basura = [byte[]]::new(40)
        for ($i = 0; $i -lt 40; $i++) { $script:Basura[$i] = 0xFF }
    }

    It 'los tres se leen enteros: si no, lo de abajo no prueba que se pare' {
        @(Get-RegistrosUsn -Bytes (Join-Bytes -Trozos @($script:B1, $script:B2, $script:B3))).Count | Should -Be 3
    }

    It 'ceros detras de los buenos -Longitud 0- es el fin: se devuelven los buenos' {
        $l = @(Get-RegistrosUsn -Bytes (Join-Bytes -Trozos @($script:B1, $script:B2, $script:B3, [byte[]]::new(128))))
        $l.Count | Should -Be 3
        $l[2].Nombre | Should -Be 'tres.txt'
    }

    It 'basura detras de los buenos no se lleva por delante a los buenos' {
        $b = Join-Bytes -Trozos @($script:B1, $script:B2, $script:B3, $script:Basura)
        { Get-RegistrosUsn -Bytes $b } | Should -Not -Throw
        $l = @(Get-RegistrosUsn -Bytes $b)
        $l.Count | Should -Be 3
        @($l | ForEach-Object { $_.Usn }) | Should -Be @(1, 2, 3)
    }

    It 'el ultimo cortado a mitad se descarta y los de antes valen' {
        $entero = Join-Bytes -Trozos @($script:B1, $script:B2, $script:B3)
        $cortado = [byte[]]::new($entero.Length - 5)
        [Array]::Copy($entero, 0, $cortado, 0, $cortado.Length)
        $l = @(Get-RegistrosUsn -Bytes $cortado)
        $l.Count | Should -Be 2
        $l[1].Nombre | Should -Be 'dos.txt'
    }

    It 'se para en el primero que no vale y NO salta por encima de el' {
        # El del medio es version 3. Detras hay uno bueno, y no se llega a
        # el: sin saber cuanto mide el malo, buscar el siguiente seria
        # adivinar, y un registro adivinado es un cambio inventado.
        $malo = New-RegistroUsnDePrueba -Nombre 'dos.txt' -Usn 2 -VersionMayor 3
        $l = @(Get-RegistrosUsn -Bytes (Join-Bytes -Trozos @($script:B1, $malo, $script:B3)))
        $l.Count | Should -Be 1
        $l[0].Nombre | Should -Be 'uno.txt'
    }

    It 'una Longitud a cero en medio para el recorrido, y no lo cuelga' {
        $ceros = [byte[]]::new(80)
        $l = @(Get-RegistrosUsn -Bytes (Join-Bytes -Trozos @($script:B1, $ceros, $script:B3)))
        $l.Count | Should -Be 1
        $l[0].Usn | Should -Be 1
    }

    It 'un registro que dice medir cero, pero por lo demas valido, para el recorrido sin colgarlo' {
        # Los ceros de arriba tambien tienen la version a cero, asi que los
        # rechaza la guarda de la version y la de la longitud no hace falta
        # para pasar la prueba. Este solo lo puede parar la longitud. Si se
        # aceptara, $pos no avanzaria y el bucle repetiria el mismo registro
        # hasta el tope de vueltas: saldria el mismo varias veces en vez de
        # uno solo.
        $cero = New-RegistroUsnDePrueba -Nombre '' -LongitudDeclarada 0
        $l = @(Get-RegistrosUsn -Bytes (Join-Bytes -Trozos @($script:B1, $cero, $script:B3)))
        $l.Count | Should -Be 1
        $l[0].Usn | Should -Be 1
    }

    It 'un registro que declara mas de lo que queda se descarta sin lanzar' {
        $largo = New-RegistroUsnDePrueba -Nombre 'dos.txt' -Usn 2 -LongitudDeclarada 4000
        $b = Join-Bytes -Trozos @($script:B1, $largo)
        { Get-RegistrosUsn -Bytes $b } | Should -Not -Throw
        @(Get-RegistrosUsn -Bytes $b).Count | Should -Be 1
    }
}
