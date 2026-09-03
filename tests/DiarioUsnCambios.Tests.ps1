<#
    [VEL-02]: DE LA LLUVIA DE REGISTROS USN A LA LISTA LIMPIA DE CAMBIOS.

    src/Core/DiarioUsnCambios.ps1 es calculo puro: recibe registros del
    diario y devuelve lo que Update-IndiceConCambios sabe aplicar. Las dos
    cosas que solo sabe Windows -traducir una referencia a ruta y medir un
    archivo- se inyectan, y aqui son un diccionario y un contador.

    Cada prueba de abajo cubre UNA regla, y esta escrita para ponerse roja
    si esa regla se quita. Las que de verdad importan:

      - N registros del mismo archivo = UN cambio (colapsar por archivo).
      - El orden por Usn manda aunque los registros lleguen desordenados.
      - Crear y luego borrar = NADA. Borrar y crear = Alta. Cambiar y
        borrar = Baja.
      - Renombrar = Baja(ruta vieja) + Alta(ruta nueva), con las rutas
        resueltas por separado.
      - La ruta que no se resuelve se descarta, se cuenta, y no lanza.
      - El archivo que ya no esta pasa a Baja.
      - MedirBytes se llama SOLO para altas y cambios.
      - Nada lanza con nulos por todas partes.

    Y una prueba de costura al final: lo que sale de aqui entra tal cual en
    Update-IndiceConCambios de verdad. Dos mitades en verde que discrepan
    en lo que nadie acordo ya costaron una sesion en este mismo punto.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
    # DiarioUsnCambios.ps1 lo carga Bootstrap.ps1: aqui no se vuelve a cargar, para que
    # estas pruebas midan como se carga el programa de verdad.

    # Las razones, con nombre, para que las pruebas se lean como el diario.
    # Con el sufijo L: 0x80000000 sin el es un Int32 negativo.
    $script:R = @{
        Overwrite = 0x00000001L
        Extend    = 0x00000002L
        Truncate  = 0x00000004L
        Create    = 0x00000100L
        Delete    = 0x00000200L
        OldName   = 0x00001000L
        NewName   = 0x00002000L
        BasicInfo = 0x00008000L
        Close     = 0x80000000L
    }

    function script:New-RegistroUsn {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [uint64] $Ref,
            [Parameter(Mandatory)] [uint64] $Padre,
            [Parameter(Mandatory)] [int64]  $Usn,
            [Parameter(Mandatory)] [int64]  $Razon,
            [Parameter(Mandatory)] [string] $Nombre,
            [switch] $Carpeta
        )
        return [pscustomobject]@{
            NumeroReferencia      = $Ref
            NumeroReferenciaPadre = $Padre
            Usn                   = $Usn
            Razon                 = [uint32]$Razon
            EsCarpeta             = [bool]$Carpeta
            Nombre                = $Nombre
        }
    }

    # El resolutor de mentira: un diccionario "padre|nombre" -> ruta. Lo
    # que no este, no se sabe, que es exactamente lo que hace el de
    # verdad con una referencia que ya no existe.
    $script:Carpetas = @{ 1 = 'C:\datos'; 2 = 'C:\otra' }
    $script:Resolver = {
        param($Padre, $Nombre)
        $carpeta = $script:Carpetas[[int]$Padre]
        if ($null -eq $carpeta) { return $null }
        # A mano y no con Join-Path: en Linux, Join-Path rechaza una unidad
        # "C:" que aqui no existe, y estas rutas son de Windows a proposito.
        return ($carpeta + '\' + $Nombre)
    }

    # El medidor de mentira: un diccionario ruta -> bytes. Lo que no este,
    # "no esta en el disco". Y apunta CADA llamada, que es lo que permite
    # comprobar que solo se mide lo que hay que medir.
    $script:Tamanyos = @{}
    $script:Medidas = [Collections.Generic.List[string]]::new()
    $script:Medir = {
        param($Ruta)
        $script:Medidas.Add([string]$Ruta)
        if ($script:Tamanyos.ContainsKey($Ruta)) { return [double]$script:Tamanyos[$Ruta] }
        return $null
    }

    function script:Invoke-Conversion {
        param([object[]] $Registros)
        return ConvertTo-CambiosIndice -Registros $Registros `
                                       -ResolverRuta $script:Resolver `
                                       -MedirBytes $script:Medir
    }
}

Describe 'Get-CambioDesdeRazonUsn: una razon, un veredicto' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'una carpeta nunca interesa, ni creada ni borrada' {
        Get-CambioDesdeRazonUsn -Razon $script:R.Create -EsCarpeta | Should -Be ''
        Get-CambioDesdeRazonUsn -Razon $script:R.Delete -EsCarpeta | Should -Be ''
        Get-CambioDesdeRazonUsn -Razon ($script:R.Extend -bor $script:R.Close) -EsCarpeta | Should -Be ''
    }

    It 'borrar es Baja, y el nombre viejo de un renombrado tambien' {
        Get-CambioDesdeRazonUsn -Razon $script:R.Delete  | Should -Be 'Baja'
        Get-CambioDesdeRazonUsn -Razon $script:R.OldName | Should -Be 'Baja'
    }

    It 'la baja manda sobre todo lo demas del mismo registro' {
        # La mascara se acumula mientras el archivo esta abierto: creado,
        # escrito, borrado y cerrado en un solo registro. Lo que describe
        # donde acaba el archivo es el borrado.
        $todo = $script:R.Create -bor $script:R.Extend -bor $script:R.Delete -bor $script:R.Close
        Get-CambioDesdeRazonUsn -Razon $todo | Should -Be 'Baja'
        Get-CambioDesdeRazonUsn -Razon ($script:R.Delete -bor $script:R.NewName) | Should -Be 'Baja'
        Get-CambioDesdeRazonUsn -Razon ($script:R.OldName -bor $script:R.Extend) | Should -Be 'Baja'
    }

    It 'crear es Alta, y el nombre nuevo de un renombrado tambien' {
        Get-CambioDesdeRazonUsn -Razon $script:R.Create  | Should -Be 'Alta'
        Get-CambioDesdeRazonUsn -Razon $script:R.NewName | Should -Be 'Alta'
        Get-CambioDesdeRazonUsn -Razon ($script:R.Create -bor $script:R.Extend -bor $script:R.Close) | Should -Be 'Alta'
    }

    It 'si un registro trae el nombre viejo y el nuevo, el nombre que lleva es el nuevo: Alta' {
        # El diario los emite por separado; si un lector los juntara, dar
        # de baja la ruta nueva quitaria del indice la unica que existe.
        Get-CambioDesdeRazonUsn -Razon ($script:R.OldName -bor $script:R.NewName) | Should -Be 'Alta'
    }

    It 'escribir, crecer o encoger es Cambio' {
        Get-CambioDesdeRazonUsn -Razon $script:R.Overwrite | Should -Be 'Cambio'
        Get-CambioDesdeRazonUsn -Razon $script:R.Extend    | Should -Be 'Cambio'
        Get-CambioDesdeRazonUsn -Razon $script:R.Truncate  | Should -Be 'Cambio'
        Get-CambioDesdeRazonUsn -Razon ($script:R.Extend -bor $script:R.Close) | Should -Be 'Cambio'
    }

    It 'lo que no mueve el tamanyo no interesa: atributos, cierre a secas, cero, bits desconocidos' {
        Get-CambioDesdeRazonUsn -Razon $script:R.BasicInfo | Should -Be ''
        Get-CambioDesdeRazonUsn -Razon $script:R.Close     | Should -Be ''
        Get-CambioDesdeRazonUsn -Razon 0                   | Should -Be ''
        Get-CambioDesdeRazonUsn -Razon 0x00400000L         | Should -Be ''
        Get-CambioDesdeRazonUsn -Razon $null               | Should -Be ''
    }

    It 'un bit desconocido al lado de uno conocido no tapa al conocido' {
        Get-CambioDesdeRazonUsn -Razon (0x00400000L -bor $script:R.Extend) | Should -Be 'Cambio'
        Get-CambioDesdeRazonUsn -Razon (0x00400000L -bor $script:R.Delete) | Should -Be 'Baja'
    }
}

Describe 'ConvertTo-CambiosIndice: colapsar por archivo' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'crear + extender + cerrar del mismo archivo = UNA alta, medida UNA vez' {
        $script:Tamanyos['C:\datos\nuevo.bin'] = 700.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'nuevo.bin')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon ($script:R.Create -bor $script:R.Extend) -Nombre 'nuevo.bin')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.Create -bor $script:R.Extend) -Nombre 'nuevo.bin')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 4 -Razon ($script:R.Create -bor $script:R.Extend -bor $script:R.Close) -Nombre 'nuevo.bin')
        )
        @($r.Cambios).Count       | Should -Be 1
        $r.Cambios[0].Tipo        | Should -Be 'Alta'
        $r.Cambios[0].Ruta        | Should -Be 'C:\datos\nuevo.bin'
        $r.Cambios[0].Bytes       | Should -Be 700.0
        @($script:Medidas).Count  | Should -Be 1
        $r.Descartados            | Should -Be 0
    }

    It 'veinte escrituras sobre el mismo archivo = UN cambio con el tamanyo de ahora' {
        $script:Tamanyos['C:\datos\log.txt'] = 5000.0
        $regs = foreach ($n in 1..20) {
            New-RegistroUsn -Ref 20 -Padre 1 -Usn $n -Razon $script:R.Extend -Nombre 'log.txt'
        }
        $r = Invoke-Conversion @($regs)
        @($r.Cambios).Count      | Should -Be 1
        $r.Cambios[0].Tipo       | Should -Be 'Cambio'
        $r.Cambios[0].Bytes      | Should -Be 5000.0
        @($script:Medidas).Count | Should -Be 1
    }

    It 'archivos distintos NO se colapsan entre si' {
        $script:Tamanyos['C:\datos\a.txt'] = 1.0
        $script:Tamanyos['C:\datos\b.txt'] = 2.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 1 -Padre 1 -Usn 1 -Razon $script:R.Extend -Nombre 'a.txt')
            (New-RegistroUsn -Ref 2 -Padre 1 -Usn 2 -Razon $script:R.Extend -Nombre 'b.txt')
        )
        @($r.Cambios).Count | Should -Be 2
        @($r.Cambios | ForEach-Object { $_.Ruta }) | Should -Be @('C:\datos\a.txt', 'C:\datos\b.txt')
    }
}

Describe 'ConvertTo-CambiosIndice: el orden manda' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'crear y luego borrar en la misma tanda = NADA, ni alta ni baja' {
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'fugaz.tmp')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon ($script:R.Create -bor $script:R.Extend) -Nombre 'fugaz.tmp')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.Create -bor $script:R.Extend -bor $script:R.Delete -bor $script:R.Close) -Nombre 'fugaz.tmp')
        )
        @($r.Cambios).Count      | Should -Be 0
        $r.Descartados           | Should -Be 0
        @($script:Medidas).Count | Should -Be 0
    }

    It 'borrar y luego crear con el mismo nombre = UNA alta con el tamanyo nuevo' {
        $script:Tamanyos['C:\datos\config.ini'] = 999.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'config.ini')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon $script:R.Create -Nombre 'config.ini')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.Create -bor $script:R.Extend -bor $script:R.Close) -Nombre 'config.ini')
        )
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Tipo  | Should -Be 'Alta'
        $r.Cambios[0].Ruta  | Should -Be 'C:\datos\config.ini'
        $r.Cambios[0].Bytes | Should -Be 999.0
    }

    It 'borrar uno y crear OTRO con el mismo nombre = Baja y luego Alta, en ese orden' {
        # Dos referencias distintas: son dos archivos. Al indice le llega
        # primero la baja del viejo y despues el alta del nuevo; al reves,
        # la baja se llevaria por delante el alta.
        $script:Tamanyos['C:\datos\config.ini'] = 999.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 11 -Padre 1 -Usn 2 -Razon $script:R.Create -Nombre 'config.ini')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'config.ini')
        )
        @($r.Cambios).Count | Should -Be 2
        @($r.Cambios | ForEach-Object { $_.Tipo }) | Should -Be @('Baja', 'Alta')
    }

    It 'cambiar y luego borrar = Baja, y no se mide nada' {
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Extend -Nombre 'viejo.dat')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon ($script:R.Extend -bor $script:R.Delete -bor $script:R.Close) -Nombre 'viejo.dat')
        )
        @($r.Cambios).Count      | Should -Be 1
        $r.Cambios[0].Tipo       | Should -Be 'Baja'
        $r.Cambios[0].Ruta       | Should -Be 'C:\datos\viejo.dat'
        @($script:Medidas).Count | Should -Be 0
    }

    It 'el orden es el del Usn, no el de llegada: "borrar, crear" desordenado sigue siendo "crear, borrar"' {
        # Los mismos tres registros que "crear y luego borrar", entregados
        # al reves. Sin ordenar por Usn se leeria "borrar y luego crear" y
        # saldria un alta de un archivo que no existe.
        $script:Tamanyos['C:\datos\fugaz.tmp'] = 1.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'fugaz.tmp')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon $script:R.Extend -Nombre 'fugaz.tmp')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'fugaz.tmp')
        )
        @($r.Cambios).Count | Should -Be 0
    }

    It 'un Usn que llega como texto ordena como numero: el 100 va despues del 99' {
        $registros = @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 100 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'x.tmp')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 99  -Razon $script:R.Create -Nombre 'x.tmp')
        )
        foreach ($reg in $registros) { $reg.Usn = [string]$reg.Usn }
        $r = Invoke-Conversion $registros
        @($r.Cambios).Count | Should -Be 0
    }
}

Describe 'ConvertTo-CambiosIndice: renombrar' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'renombrar = Baja(ruta vieja) + Alta(ruta nueva), el unico caso con dos cambios por archivo' {
        $script:Tamanyos['C:\datos\despues.txt'] = 300.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.OldName -Nombre 'antes.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon $script:R.NewName -Nombre 'despues.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.NewName -bor $script:R.Close) -Nombre 'despues.txt')
        )
        @($r.Cambios).Count | Should -Be 2
        $r.Cambios[0].Tipo  | Should -Be 'Baja'
        $r.Cambios[0].Ruta  | Should -Be 'C:\datos\antes.txt'
        $r.Cambios[1].Tipo  | Should -Be 'Alta'
        $r.Cambios[1].Ruta  | Should -Be 'C:\datos\despues.txt'
        $r.Cambios[1].Bytes | Should -Be 300.0
        # Solo se mide la ruta nueva: la vieja ya no existe.
        @($script:Medidas)  | Should -Be @('C:\datos\despues.txt')
    }

    It 'mover de carpeta es renombrar: cada ruta se resuelve con SU padre' {
        $script:Tamanyos['C:\otra\mismo.txt'] = 50.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.OldName -Nombre 'mismo.txt')
            (New-RegistroUsn -Ref 10 -Padre 2 -Usn 2 -Razon ($script:R.NewName -bor $script:R.Close) -Nombre 'mismo.txt')
        )
        @($r.Cambios | ForEach-Object { $_.Tipo + ' ' + $_.Ruta }) |
            Should -Be @('Baja C:\datos\mismo.txt', 'Alta C:\otra\mismo.txt')
    }

    It 'un archivo nacido en la tanda y renombrado = solo el alta con el nombre nuevo' {
        # El indice nunca tuvo el nombre viejo: no hay nada que dar de baja.
        $script:Tamanyos['C:\datos\final.txt'] = 10.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'provisional.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon $script:R.OldName -Nombre 'provisional.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.NewName -bor $script:R.Close) -Nombre 'final.txt')
        )
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Tipo  | Should -Be 'Alta'
        $r.Cambios[0].Ruta  | Should -Be 'C:\datos\final.txt'
    }

    It 'renombrar A -> B -> A deja Baja(B) y Alta(A), no dos bajas de A' {
        $script:Tamanyos['C:\datos\a.txt'] = 10.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.OldName -Nombre 'a.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon $script:R.NewName -Nombre 'b.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon $script:R.OldName -Nombre 'b.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 4 -Razon ($script:R.NewName -bor $script:R.Close) -Nombre 'a.txt')
        )
        @($r.Cambios | ForEach-Object { $_.Tipo + ' ' + $_.Ruta }) |
            Should -Be @('Baja C:\datos\b.txt', 'Alta C:\datos\a.txt')
    }

    It 'renombrar y luego borrar = solo Baja de la ruta vieja: la nueva nunca llego al indice' {
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.OldName -Nombre 'antes.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 2 -Razon $script:R.NewName -Nombre 'despues.txt')
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 3 -Razon ($script:R.NewName -bor $script:R.Delete -bor $script:R.Close) -Nombre 'despues.txt')
        )
        # La ruta nueva se da de baja tambien: es inofensivo (Update la
        # ignora si no la tenia) y es lo que dice el diario. Lo que NO
        # puede pasar es que se pierda la baja de la ruta vieja.
        @($r.Cambios | ForEach-Object { $_.Tipo }) | Should -Not -Contain 'Alta'
        @($r.Cambios | Where-Object { $_.Ruta -eq 'C:\datos\antes.txt' -and $_.Tipo -eq 'Baja' }).Count | Should -Be 1
        @($script:Medidas).Count | Should -Be 0
    }
}

Describe 'ConvertTo-CambiosIndice: lo que se descarta se cuenta y no lanza' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'una ruta que el resolutor no sabe se descarta y se cuenta, con motivo legible' {
        $script:Tamanyos['C:\datos\bien.txt'] = 1.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1  -Usn 1 -Razon $script:R.Create -Nombre 'bien.txt')
            (New-RegistroUsn -Ref 11 -Padre 99 -Usn 2 -Razon $script:R.Create -Nombre 'huerfano.txt')
        )
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Ruta  | Should -Be 'C:\datos\bien.txt'
        $r.Descartados      | Should -Be 1
        $r.MotivoDescartes  | Should -Match 'descartado'
        $r.MotivoDescartes  | Should -Match 'recorrer el disco'
        # Y sin ruta no se llama al medidor: no hay nada que medir.
        @($script:Medidas)  | Should -Be @('C:\datos\bien.txt')
    }

    It 'la baja de una ruta que no se resuelve tambien se cuenta' {
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 99 -Usn 1 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'ido.txt')
        )
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 1
    }

    It 'sin descartes, el motivo esta vacio: un "no me fio" sin motivo es un fallo' {
        $script:Tamanyos['C:\datos\bien.txt'] = 1.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'bien.txt')
        )
        $r.Descartados     | Should -Be 0
        $r.MotivoDescartes | Should -Be ''
    }

    It 'un resolutor que revienta no tumba la conversion: se cuenta' {
        $roto = { param($Padre, $Nombre) throw 'la API no esta' }
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'x.txt')
        ) -ResolverRuta $roto -MedirBytes $script:Medir
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 1
    }

    It 'un medidor que revienta no convierte el alta en baja: se descarta y se cuenta' {
        # Reventar no es "el archivo no esta": es "no se sabe". Y no saber
        # nunca se traduce en quitar bytes del indice.
        $roto = { param($Ruta) throw 'acceso denegado' }
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'x.txt')
        ) -ResolverRuta $script:Resolver -MedirBytes $roto
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 1
    }
}

Describe 'ConvertTo-CambiosIndice: el archivo que se fue entre el diario y nosotros' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'un alta cuya ruta ya no existe pasa a Baja' {
        # Nada en $script:Tamanyos: el medidor dice "no esta".
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon ($script:R.Create -bor $script:R.Close) -Nombre 'efimero.txt')
        )
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Tipo  | Should -Be 'Baja'
        $r.Cambios[0].Ruta  | Should -Be 'C:\datos\efimero.txt'
        $r.Descartados      | Should -Be 0
    }

    It 'un cambio cuya ruta ya no existe pasa a Baja' {
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon ($script:R.Extend -bor $script:R.Close) -Nombre 'efimero.txt')
        )
        $r.Cambios[0].Tipo | Should -Be 'Baja'
    }

    It 'un tamanyo negativo o que no es un numero se descarta, no se aplica' {
        $raro = { param($Ruta) if ($Ruta -like '*neg*') { return -5.0 } else { return 'muchos' } }
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'neg.txt')
            (New-RegistroUsn -Ref 11 -Padre 1 -Usn 2 -Razon $script:R.Create -Nombre 'texto.txt')
        ) -ResolverRuta $script:Resolver -MedirBytes $raro
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 2
    }
}

Describe 'ConvertTo-CambiosIndice: a quien se mide y a quien no' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'MedirBytes se llama SOLO para altas y cambios, nunca para bajas ni para lo que no interesa' {
        $script:Tamanyos['C:\datos\alta.txt']   = 1.0
        $script:Tamanyos['C:\datos\cambio.txt'] = 2.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 1 -Padre 1 -Usn 1 -Razon $script:R.Create    -Nombre 'alta.txt')
            (New-RegistroUsn -Ref 2 -Padre 1 -Usn 2 -Razon $script:R.Extend    -Nombre 'cambio.txt')
            (New-RegistroUsn -Ref 3 -Padre 1 -Usn 3 -Razon $script:R.Delete    -Nombre 'baja.txt')
            (New-RegistroUsn -Ref 4 -Padre 1 -Usn 4 -Razon $script:R.BasicInfo -Nombre 'fechas.txt')
            (New-RegistroUsn -Ref 5 -Padre 1 -Usn 5 -Razon $script:R.Close     -Nombre 'cerrado.txt')
        )
        @($r.Cambios).Count | Should -Be 3
        @($script:Medidas | Sort-Object) | Should -Be @('C:\datos\alta.txt', 'C:\datos\cambio.txt')
    }

    It 'las carpetas se ignoran aunque se creen o se borren; sus archivos de dentro, no' {
        # Al borrar una carpeta el diario emite un DELETE por cada archivo
        # de dentro: por eso ignorar la carpeta no pierde nada.
        # La carpeta ya existia (no trae CREATE): si no se ignorara, su
        # borrado saldria como una baja mas y su escritura pediria medirla.
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 50 -Padre 1  -Usn 1 -Razon $script:R.Extend -Nombre 'sub' -Carpeta)
            (New-RegistroUsn -Ref 51 -Padre 1  -Usn 2 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'dentro.txt')
            (New-RegistroUsn -Ref 50 -Padre 1  -Usn 3 -Razon ($script:R.Delete -bor $script:R.Close) -Nombre 'sub' -Carpeta)
            (New-RegistroUsn -Ref 52 -Padre 1  -Usn 4 -Razon $script:R.Create -Nombre 'viva' -Carpeta)
        )
        @($r.Cambios).Count      | Should -Be 1
        $r.Cambios[0].Tipo       | Should -Be 'Baja'
        $r.Cambios[0].Ruta       | Should -Be 'C:\datos\dentro.txt'
        $r.Descartados           | Should -Be 0
        @($script:Medidas).Count | Should -Be 0
    }

    It 'un bit de razon desconocido no rompe nada: se ignora si va solo y se respeta lo que le acompanya' {
        $script:Tamanyos['C:\datos\raro.txt'] = 7.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 1 -Padre 1 -Usn 1 -Razon 0x00400000L -Nombre 'solo.txt')
            (New-RegistroUsn -Ref 2 -Padre 1 -Usn 2 -Razon (0x00400000L -bor $script:R.Extend) -Nombre 'raro.txt')
        )
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Tipo  | Should -Be 'Cambio'
        $r.Cambios[0].Ruta  | Should -Be 'C:\datos\raro.txt'
    }

    It 'la razon con el bit alto leida con signo (CLOSE como negativo) sigue valiendo' {
        # 0x80000002 leido como Int32 es -2147483646: CLOSE | EXTEND. Un
        # lector que pase la razon por un [int] la entregaria asi, y
        # rechazarla tiraria justo los registros de cierre.
        $script:Tamanyos['C:\datos\x.txt'] = 3.0
        $reg = New-RegistroUsn -Ref 1 -Padre 1 -Usn 1 -Razon $script:R.Extend -Nombre 'x.txt'
        $reg.Razon = [int]-2147483646
        $r = Invoke-Conversion @($reg)
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Tipo  | Should -Be 'Cambio'
    }
}

Describe 'ConvertTo-CambiosIndice: nulos por todas partes' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    It 'con Registros nulo devuelve una lista vacia y no lanza' {
        $r = ConvertTo-CambiosIndice -Registros $null -ResolverRuta $script:Resolver -MedirBytes $script:Medir
        $r                  | Should -Not -BeNullOrEmpty
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 0
        $r.MotivoDescartes  | Should -Be ''
    }

    It 'con Registros vacio, igual' {
        $r = ConvertTo-CambiosIndice -Registros @() -ResolverRuta $script:Resolver -MedirBytes $script:Medir
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 0
    }

    It 'un nulo dentro de la lista se cuenta y los demas siguen' {
        $script:Tamanyos['C:\datos\bien.txt'] = 1.0
        $r = Invoke-Conversion @(
            $null
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'bien.txt')
        )
        @($r.Cambios).Count | Should -Be 1
        $r.Descartados      | Should -Be 1
    }

    It 'un registro con los campos a nulo se cuenta y no lanza' {
        $vacio = [pscustomobject]@{
            NumeroReferencia = $null; NumeroReferenciaPadre = $null; Usn = $null
            Razon = $null; EsCarpeta = $null; Nombre = $null
        }
        $sinRazon = New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'x.txt'
        $sinRazon.Razon = $null
        $r = Invoke-Conversion @($vacio, $sinRazon)
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 1   # el vacio; el otro simplemente no interesa
    }

    It 'sin resolutor, todo cambio se descarta y se cuenta: nunca se inventa una ruta' {
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'x.txt')
        ) -ResolverRuta $null -MedirBytes $script:Medir
        @($r.Cambios).Count      | Should -Be 0
        $r.Descartados           | Should -Be 1
        @($script:Medidas).Count | Should -Be 0
    }

    It 'sin medidor, las altas y cambios se descartan y se cuentan; las bajas salen igual' {
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'x.txt')
            (New-RegistroUsn -Ref 11 -Padre 1 -Usn 2 -Razon $script:R.Delete -Nombre 'y.txt')
        ) -ResolverRuta $script:Resolver -MedirBytes $null
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Tipo  | Should -Be 'Baja'
        $r.Descartados      | Should -Be 1
        $r.MotivoDescartes  | Should -Match 'medir'
    }

    It 'un resolutor que devuelve vacio o espacios cuenta como "no lo se"' {
        $enBlanco = { param($Padre, $Nombre) return '   ' }
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'x.txt')
        ) -ResolverRuta $enBlanco -MedirBytes $script:Medir
        @($r.Cambios).Count | Should -Be 0
        $r.Descartados      | Should -Be 1
    }
}

Describe 'ConvertTo-CambiosIndice: la forma de la salida es la que Update-IndiceConCambios espera' {

    BeforeEach { $script:Tamanyos.Clear(); $script:Medidas.Clear() }

    BeforeAll {
        # Un indice minimo de verdad, montado con las mismas piezas que
        # usa el programa. Un archivo que existe (viejo.txt, 1000 bytes)
        # para poder darlo de baja, y una carpeta conocida para colgar
        # el alta.
        #
        # Con rutas NATIVAS de la maquina donde corre la prueba y no con
        # 'C:\datos': Update-IndiceConCambios deduce la carpeta con
        # Split-Path, y en Linux eso devuelve 'C:/datos', que no casa con
        # la clave del indice. En Windows casaria; aqui la prueba diria
        # que la costura esta rota cuando lo roto seria el separador.
        $script:CarpetaNativa = Join-Path ([IO.Path]::GetTempPath()) 'cachivache-usn-costura'
        $script:ViejoNativo   = Join-Path $script:CarpetaNativa 'viejo.txt'
        $script:NuevoNativo   = Join-Path $script:CarpetaNativa 'nuevo.txt'
        $script:ResolverNativo = {
            param($Padre, $Nombre)
            return (Join-Path $script:CarpetaNativa $Nombre)
        }

        $carpetas = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        $archivos = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        $carpetas[$script:CarpetaNativa] = New-EntradaCarpeta -Ruta $script:CarpetaNativa -Nivel 0
        $carpetas[$script:CarpetaNativa].Propios  = 1000.0
        $carpetas[$script:CarpetaNativa].Bytes    = 1000.0
        $carpetas[$script:CarpetaNativa].Archivos = 1
        $archivos[$script:ViejoNativo] = 1000.0
        $script:Indice = [pscustomobject]@{
            Carpetas = $carpetas; Archivos = $archivos; Bytes = 1000.0; TotalArchivos = 1
        }
    }

    It 'cada cambio lleva exactamente Tipo, Ruta y Bytes, y Bytes es un numero' {
        $script:Tamanyos['C:\datos\nuevo.txt'] = 250.0
        $r = Invoke-Conversion @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'nuevo.txt')
            (New-RegistroUsn -Ref 11 -Padre 1 -Usn 2 -Razon $script:R.Delete -Nombre 'viejo.txt')
        )
        @($r.Cambios).Count | Should -Be 2
        foreach ($cambio in $r.Cambios) {
            @($cambio.PSObject.Properties.Name | Sort-Object) | Should -Be @('Bytes', 'Ruta', 'Tipo')
            $cambio.Tipo  | Should -BeIn @('Alta', 'Baja', 'Cambio')
            $cambio.Bytes | Should -BeOfType [double]
        }
    }

    It 'lo que sale de aqui lo aplica Update-IndiceConCambios sin descartar nada' {
        # La costura de verdad: la baja de viejo.txt (que el indice tenia)
        # y el alta de nuevo.txt (en una carpeta que conoce). Si el nombre
        # de un campo o el vocabulario de Tipo cambiara en un lado y no en
        # el otro, aqui saldria descartado y Confiable=False.
        $script:Tamanyos[$script:NuevoNativo] = 250.0
        $r = ConvertTo-CambiosIndice -Registros @(
            (New-RegistroUsn -Ref 10 -Padre 1 -Usn 1 -Razon $script:R.Create -Nombre 'nuevo.txt')
            (New-RegistroUsn -Ref 11 -Padre 1 -Usn 2 -Razon $script:R.Delete -Nombre 'viejo.txt')
        ) -ResolverRuta $script:ResolverNativo -MedirBytes $script:Medir
        @($r.Cambios).Count | Should -Be 2

        $aplicado = Update-IndiceConCambios -Indice $script:Indice -Cambios $r.Cambios
        $aplicado.Confiable   | Should -BeTrue -Because $aplicado.Motivo
        $aplicado.Descartados | Should -Be 0
        $aplicado.Altas       | Should -Be 1
        $aplicado.Bajas       | Should -Be 1
        $script:Indice.Bytes         | Should -Be 250.0
        $script:Indice.TotalArchivos | Should -Be 1
        $script:Indice.Archivos.ContainsKey($script:ViejoNativo) | Should -BeFalse
        $script:Indice.Archivos[$script:NuevoNativo] | Should -Be 250.0
    }
}
