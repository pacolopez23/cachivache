<#
    [VEL-02], LA MITAD DE WINDOWS, JUNTA.

    DiarioUsn.ps1 convierte bytes en registros. DiarioUsnCambios.ps1
    convierte registros en cambios. IndiceIncremental.ps1 aplica cambios
    a un indice. Las tres estan probadas por separado -64, 43 y 82
    pruebas- y las dos primeras SE ESCRIBIERON EN PARALELO, con el
    contrato de en medio dictado por escrito. Es exactamente la situacion
    de la regla 4 del relevo, y por eso este archivo existe: una costura
    solo se ve recorriendo el camino entero.

    Lo unico que NO recorre es la lectura del volumen -Get-DatosDiarioUsn
    y Read-DiarioUsn-, porque aqui no hay NTFS. Los bytes que entran se
    fabrican a mano con el layout del sistema. Esa frontera esta escrita
    en docs/VEL-02-MEDICION.md, y la cruza tools/Banco-VEL02-Diario.ps1
    en un Windows de verdad.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # ---- un registro del diario, byte a byte -------------------------
    function script:New-BytesUsn {
        param(
            [Parameter(Mandatory)] [string] $Nombre,
            [Parameter(Mandatory)] [long]   $Referencia,
            [Parameter(Mandatory)] [long]   $ReferenciaPadre,
            [Parameter(Mandatory)] [long]   $Usn,
            [Parameter(Mandatory)] [long]   $Razon,
            [long] $Atributos = 0x20
        )
        $nombreBytes = [Text.Encoding]::Unicode.GetBytes($Nombre)
        $largo = 60 + $nombreBytes.Length
        if (($largo % 8) -ne 0) { $largo += 8 - ($largo % 8) }
        $b = [byte[]]::new($largo)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$largo),           0, $b,  0, 4)
        [Array]::Copy([BitConverter]::GetBytes([uint16]2),                0, $b,  4, 2)
        [Array]::Copy([BitConverter]::GetBytes([uint16]0),                0, $b,  6, 2)
        [Array]::Copy([BitConverter]::GetBytes([int64]$Referencia),       0, $b,  8, 8)
        [Array]::Copy([BitConverter]::GetBytes([int64]$ReferenciaPadre),  0, $b, 16, 8)
        [Array]::Copy([BitConverter]::GetBytes([int64]$Usn),              0, $b, 24, 8)
        [Array]::Copy([BitConverter]::GetBytes([int64]133549722000000000),0, $b, 32, 8)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$Razon),           0, $b, 40, 4)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$Atributos),       0, $b, 52, 4)
        [Array]::Copy([BitConverter]::GetBytes([uint16]$nombreBytes.Length), 0, $b, 56, 2)
        [Array]::Copy([BitConverter]::GetBytes([uint16]60),               0, $b, 58, 2)
        [Array]::Copy($nombreBytes, 0, $b, 60, $nombreBytes.Length)
        return $b
    }

    function script:Join-BytesUsn {
        param([byte[][]] $Trozos)
        $total = 0; foreach ($t in $Trozos) { $total += $t.Length }
        $b = [byte[]]::new($total); $pos = 0
        foreach ($t in $Trozos) { [Array]::Copy($t, 0, $b, $pos, $t.Length); $pos += $t.Length }
        return $b
    }

    # Razones, con nombre.
    $script:R_OVERWRITE = 0x00000001L
    $script:R_EXTEND    = 0x00000002L
    $script:R_CREATE    = 0x00000100L
    $script:R_DELETE    = 0x00000200L
    $script:R_OLD_NAME  = 0x00001000L
    $script:R_NEW_NAME  = 0x00002000L
    $script:R_CLOSE     = 0x80000000L

    # ---- un disco de mentira con un indice de verdad ------------------
    $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('usn-costura-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Taller -Force)
    foreach ($n in 1..3) {
        [IO.File]::WriteAllBytes((Join-Path $script:Taller "a$n.bin"), [byte[]]::new(2MB))
    }
    # POR EL CAMINO REAL: se guarda y se vuelve a leer. New-IndiceDisco
    # devuelve la forma de ARRAY, y Update-IndiceConCambios exige la de
    # DICCIONARIO, que es la que sale de leer el archivo. Esa es la costura
    # que se encontro el 1 de septiembre (tests/IndiceCostura.Tests.ps1), y
    # en el programa el indice que se actualiza SIEMPRE viene de disco.
    $origen = New-IndiceDisco -Rutas @($script:Taller) -MinimoArchivoBytes 1MB
    $script:Fichero = Join-Path $script:Taller 'indice.bin'
    [void](Save-IndiceDisco -Indice $origen -Ruta $script:Fichero -SerieVolumen 'TEST-0001' -IdDiario '42' -UsnCorte 900)
    $script:Indice = Read-IndiceDisco -Ruta $script:Fichero -ComoDiccionario

    # La referencia del padre -> la carpeta del taller. En Windows esto lo
    # resolveria el sistema; aqui es un diccionario con una entrada.
    $script:RefCarpeta = 0x0003000000000005
    $script:Resolver = {
        param($refPadre, $nombre)
        if ([double]$refPadre -eq [double](0x0000000000000005)) { return (Join-Path $script:Taller $nombre) }
        return $null
    }
    $script:Medir = {
        param($ruta)
        if (Test-Path -LiteralPath $ruta) { return [double](Get-Item -LiteralPath $ruta).Length }
        return $null
    }
}

AfterAll {
    if ($script:Taller -and (Test-Path -LiteralPath $script:Taller)) {
        Remove-Item -LiteralPath $script:Taller -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'VEL-02: de los bytes del diario al indice actualizado' {

    It 'el indice de partida tiene lo que se espera: si no, nada de esto mide nada' {
        [double]$script:Indice.Bytes | Should -Be 6MB
        [int]$script:Indice.TotalArchivos | Should -Be 3
    }

    It 'LA COSTURA: una baja, un alta y un cambio, y el total cuadra al byte' {
        # Lo que pasa en el disco entre un analisis y el siguiente.
        Remove-Item -LiteralPath (Join-Path $script:Taller 'a2.bin') -Force
        [IO.File]::WriteAllBytes((Join-Path $script:Taller 'a4.bin'), [byte[]]::new(3MB))
        [IO.File]::WriteAllBytes((Join-Path $script:Taller 'a1.bin'), [byte[]]::new(4MB))

        # Lo que el diario diria de eso. Solo registros de cierre, que es
        # como los pide Read-DiarioUsn (ReturnOnlyOnClose).
        $bytes = script:Join-BytesUsn @(
            (script:New-BytesUsn -Nombre 'a2.bin' -Referencia 0x0001000000000102 -ReferenciaPadre $script:RefCarpeta -Usn 1000 -Razon ($script:R_DELETE -bor $script:R_CLOSE)),
            (script:New-BytesUsn -Nombre 'a4.bin' -Referencia 0x0001000000000104 -ReferenciaPadre $script:RefCarpeta -Usn 1100 -Razon ($script:R_CREATE -bor $script:R_EXTEND -bor $script:R_CLOSE)),
            (script:New-BytesUsn -Nombre 'a1.bin' -Referencia 0x0001000000000101 -ReferenciaPadre $script:RefCarpeta -Usn 1200 -Razon ($script:R_EXTEND -bor $script:R_CLOSE))
        )

        # 1. bytes -> registros
        $registros = @(Get-RegistrosUsn -Bytes $bytes)
        $registros.Count | Should -Be 3 -Because 'los tres registros tienen que parsearse; si no, la costura falla antes de empezar'

        # 2. registros -> cambios
        $conversion = ConvertTo-CambiosIndice -Registros $registros -ResolverRuta $script:Resolver -MedirBytes $script:Medir
        $conversion.Descartados | Should -Be 0 -Because $conversion.MotivoDescartes
        $cambios = @($conversion.Cambios)
        $cambios.Count | Should -Be 3
        @($cambios | Where-Object { $_.Tipo -eq 'Baja' }).Count   | Should -Be 1
        @($cambios | Where-Object { $_.Tipo -eq 'Alta' }).Count   | Should -Be 1
        @($cambios | Where-Object { $_.Tipo -eq 'Cambio' }).Count | Should -Be 1

        # 3. cambios -> indice
        $resultado = Update-IndiceConCambios -Indice $script:Indice -Cambios $cambios
        $resultado.Confiable | Should -BeTrue -Because $resultado.Motivo

        # 6 - 2 (baja) + 3 (alta) + 2 (a1 de 2 a 4) = 9 MB. Al byte.
        [double]$script:Indice.Bytes | Should -Be 9MB
        [int]$script:Indice.TotalArchivos | Should -Be 3
    }

    It 'un renombrado atraviesa la costura como baja + alta, y el total no cambia' {
        $antes = [double]$script:Indice.Bytes
        Rename-Item -LiteralPath (Join-Path $script:Taller 'a4.bin') -NewName 'a5.bin'

        $bytes = script:Join-BytesUsn @(
            (script:New-BytesUsn -Nombre 'a4.bin' -Referencia 0x0001000000000104 -ReferenciaPadre $script:RefCarpeta -Usn 2000 -Razon ($script:R_OLD_NAME -bor $script:R_CLOSE)),
            (script:New-BytesUsn -Nombre 'a5.bin' -Referencia 0x0001000000000104 -ReferenciaPadre $script:RefCarpeta -Usn 2001 -Razon ($script:R_NEW_NAME -bor $script:R_CLOSE))
        )
        $conversion = ConvertTo-CambiosIndice -Registros @(Get-RegistrosUsn -Bytes $bytes) -ResolverRuta $script:Resolver -MedirBytes $script:Medir
        $cambios = @($conversion.Cambios)
        @($cambios | Where-Object { $_.Tipo -eq 'Baja' -and $_.Ruta -like '*a4.bin' }).Count | Should -Be 1
        @($cambios | Where-Object { $_.Tipo -eq 'Alta' -and $_.Ruta -like '*a5.bin' }).Count | Should -Be 1

        $resultado = Update-IndiceConCambios -Indice $script:Indice -Cambios $cambios
        $resultado.Confiable | Should -BeTrue -Because $resultado.Motivo
        [double]$script:Indice.Bytes | Should -Be $antes -Because 'renombrar no cambia lo que ocupa'
        [int]$script:Indice.TotalArchivos | Should -Be 3
    }

    It 'una carpeta en el diario no produce ningun cambio, y no rompe la costura' {
        $antes = [double]$script:Indice.Bytes
        $bytes = script:New-BytesUsn -Nombre 'nueva' -Referencia 0x0001000000000200 -ReferenciaPadre $script:RefCarpeta -Usn 3000 -Razon ($script:R_CREATE -bor $script:R_CLOSE) -Atributos 0x10
        $conversion = ConvertTo-CambiosIndice -Registros @(Get-RegistrosUsn -Bytes $bytes) -ResolverRuta $script:Resolver -MedirBytes $script:Medir
        @($conversion.Cambios).Count | Should -Be 0
        [double]$script:Indice.Bytes | Should -Be $antes
    }

    It 'una referencia de padre que nadie sabe resolver se cuenta, y el indice no se toca' {
        $antes = [double]$script:Indice.Bytes
        $bytes = script:New-BytesUsn -Nombre 'perdido.bin' -Referencia 0x0001000000000300 -ReferenciaPadre 0x0009000000000099 -Usn 4000 -Razon ($script:R_CREATE -bor $script:R_CLOSE)
        $conversion = ConvertTo-CambiosIndice -Registros @(Get-RegistrosUsn -Bytes $bytes) -ResolverRuta $script:Resolver -MedirBytes $script:Medir
        $conversion.Descartados | Should -Be 1
        $conversion.MotivoDescartes | Should -Not -BeNullOrEmpty
        @($conversion.Cambios).Count | Should -Be 0
        [double]$script:Indice.Bytes | Should -Be $antes
    }

    It 'basura al final del buffer no se lleva por delante los registros buenos' {
        $bueno = script:New-BytesUsn -Nombre 'a1.bin' -Referencia 0x0001000000000101 -ReferenciaPadre $script:RefCarpeta -Usn 5000 -Razon ($script:R_OVERWRITE -bor $script:R_CLOSE)
        $basura = [byte[]]::new(24); for ($i = 0; $i -lt 24; $i++) { $basura[$i] = 0xEE }
        $registros = @(Get-RegistrosUsn -Bytes (script:Join-BytesUsn @($bueno, $basura)))
        $registros.Count | Should -Be 1
    }
}

Describe 'VEL-02: la decision de si se puede leer el diario' {

    It 'con NTFS, disco fijo, administrador y diario activo, se puede' {
        Test-PuedeLeerDiarioUsn -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $true -DiarioActivo $true |
            Should -BeNullOrEmpty
    }

    It 'sin administrador NO se puede, y lo dice: es el caso NORMAL del programa' {
        $m = Test-PuedeLeerDiarioUsn -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $false -DiarioActivo $true
        $m | Should -Match 'administrador'
    }

    It 'con el diario apagado no se puede, y es el motivo propio de esta funcion' {
        $m = Test-PuedeLeerDiarioUsn -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $true -DiarioActivo $false
        $m | Should -Match 'diario'
        $m | Should -Not -Match 'administrador'
    }

    It 'sin saber si el diario esta activo, se trata como apagado' {
        Test-PuedeLeerDiarioUsn -SistemaArchivos 'NTFS' -TipoUnidad 'Fixed' -EsAdministrador $true -DiarioActivo $null |
            Should -Not -BeNullOrEmpty
    }

    It 'los tres motivos de la tabla maestra llegan hablando del diario, no de la tabla maestra' {
        foreach ($caso in @(
            @{ SistemaArchivos = 'FAT32'; TipoUnidad = 'Fixed';   Es = $true  },
            @{ SistemaArchivos = 'NTFS';  TipoUnidad = 'Network'; Es = $true  },
            @{ SistemaArchivos = 'NTFS';  TipoUnidad = 'CDRom';   Es = $true  }
        )) {
            $m = Test-PuedeLeerDiarioUsn -SistemaArchivos $caso.SistemaArchivos -TipoUnidad $caso.TipoUnidad -EsAdministrador $caso.Es -DiarioActivo $true
            $m | Should -Not -BeNullOrEmpty
            $m | Should -Not -Match 'tabla maestra' -Because 'el usuario no sabe que es la tabla maestra; sabe que es el diario de cambios'
        }
    }

    It 'el orden es el de la tabla maestra: primero lo que el usuario no puede cambiar' {
        # Una unidad de red sin administrador: el motivo tiene que ser la
        # red, no "reinicia como administrador", que no arreglaria nada.
        $m = Test-PuedeLeerDiarioUsn -SistemaArchivos 'NTFS' -TipoUnidad 'Network' -EsAdministrador $false -DiarioActivo $true
        $m | Should -Match 'red'
        $m | Should -Not -Match 'administrador'
    }

    It 'con nulos por todas partes no lanza y dice que no' {
        { Test-PuedeLeerDiarioUsn -SistemaArchivos $null -TipoUnidad $null -EsAdministrador $false -DiarioActivo $null } | Should -Not -Throw
        Test-PuedeLeerDiarioUsn -SistemaArchivos $null -TipoUnidad $null -EsAdministrador $false -DiarioActivo $null | Should -Not -BeNullOrEmpty
    }
}

Describe 'VEL-02: lo que toca el disco no puede tirar el analisis' {

    It 'fuera de Windows, o sin volumen, las dos lecturas devuelven $null y no lanzan' {
        { Get-DatosDiarioUsn -Unidad 'C:' } | Should -Not -Throw
        { Read-DiarioUsn -Unidad 'C:' -IdDiario 1 -Desde 0 } | Should -Not -Throw
        # Aqui no hay Windows, asi que es $null seguro. En Windows sin
        # administrador tambien lo seria, y ese es el contrato.
        $esWindows = $IsWindows -or ($null -eq $IsWindows)
        if (-not $esWindows) {
            Get-DatosDiarioUsn -Unidad 'C:' | Should -BeNullOrEmpty
            Read-DiarioUsn -Unidad 'C:' -IdDiario 1 -Desde 0 | Should -BeNullOrEmpty
        }
    }

    It 'preparar la llamada al sistema no lanza, y fuera de Windows dice que no' {
        { Initialize-InteropDiarioUsn } | Should -Not -Throw
        $esWindows = $IsWindows -or ($null -eq $IsWindows)
        if (-not $esWindows) {
            Initialize-InteropDiarioUsn | Should -BeFalse
        }
        # Y la segunda vez contesta lo mismo sin volver a compilar nada:
        # Add-Type dos veces con el mismo tipo lanza, y esto se llama en
        # cada analisis.
        (Initialize-InteropDiarioUsn) | Should -Be (Initialize-InteropDiarioUsn)
    }

    It 'con una unidad que no es una letra no intenta abrir nada' {
        foreach ($mala in @('', $null, 'C', 'C:\Users', '\\servidor\x', '..')) {
            Get-DatosDiarioUsn -Unidad $mala | Should -BeNullOrEmpty
            Read-DiarioUsn -Unidad $mala -IdDiario 1 -Desde 0 | Should -BeNullOrEmpty
        }
    }

    It 'con el identificador o el corte a nulo no lee: no sabria desde donde' {
        Read-DiarioUsn -Unidad 'C:' -IdDiario $null -Desde 0 | Should -BeNullOrEmpty
        Read-DiarioUsn -Unidad 'C:' -IdDiario 1 -Desde $null | Should -BeNullOrEmpty
    }
}
