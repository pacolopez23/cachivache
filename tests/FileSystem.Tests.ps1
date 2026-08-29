<#
    Red de seguridad para el cambio de rendimiento más invasivo del
    proyecto: Measure-Ruta y Measure-RutaDetalle han pasado de
    Get-ChildItem -Recurse a una enumeracion de .NET con pila propia.

    Estas pruebas no comprueban que el resultado sea "correcto" en
    abstracto: fijan EL RESULTADO QUE YA DABA el código anterior, campo a
    campo, más la única diferencia que se ha introducido a propósito -no
    seguir los puntos de reanalisis- que va marcada como tal.

    Se ejecutan sobre arboles de mentira en una carpeta temporal, así que
    no tocan el equipo real y valen igual en Linux.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # La implementación ANTERIOR, copiada palabra por palabra. Es el patron
    # de una prueba de caracterizacion: no se compara con lo que uno cree
    # que hacia el código viejo, se compara con el código viejo.
    function Measure-RutaComoAntes {
        param([string] $Ruta)
        if ([string]::IsNullOrWhiteSpace($Ruta))  { return 0.0 }
        if (-not (Test-Path -LiteralPath $Ruta))  { return 0.0 }
        $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
        if ($null -eq $item)      { return 0.0 }
        if (Test-EsEnlace $item)  { return 0.0 }
        if (-not $item.PSIsContainer) { return [double]$item.Length }
        $suma = (Get-ChildItem -LiteralPath $Ruta -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
        if ($null -eq $suma) { return 0.0 }
        return [double]$suma
    }

    function Measure-RutaDetalleComoAntes {
        param([string] $Ruta)
        $resultado = [pscustomobject]@{ Bytes = 0.0; Archivos = 0; Ultimo = [datetime]'1900-01-01' }
        if (-not (Test-Path -LiteralPath $Ruta)) { return $resultado }
        $archivos = @(Get-ChildItem -LiteralPath $Ruta -Recurse -Force -File -ErrorAction SilentlyContinue)
        if ($archivos.Count -eq 0) {
            $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
            if ($item) { $resultado.Ultimo = $item.LastWriteTime }
            return $resultado
        }
        $medida = $archivos | Measure-Object -Property Length -Sum
        $resultado.Bytes    = [double]$medida.Sum
        $resultado.Archivos = [int]$medida.Count
        $resultado.Ultimo   = ($archivos | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        return $resultado
    }

    function Initialize-ArbolDePrueba {
        param([string] $Base)
        # Tres niveles, archivos en todos ellos y fechas repartidas para
        # que "el último" no sea trivialmente el último que se escribio.
        $fecha = [datetime]'2021-03-04 10:00:00'
        foreach ($rama in @('', 'uno', 'uno/hondo', 'dos')) {
            $carpeta = if ($rama) { Join-Path $Base $rama } else { $Base }
            New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
            foreach ($n in 1..3) {
                $archivo = Join-Path $carpeta "a$n.bin"
                [IO.File]::WriteAllBytes($archivo, [byte[]]::new(100 * $n))
                [IO.File]::SetLastWriteTime($archivo, $fecha)
                $fecha = $fecha.AddHours(7)
            }
        }
        # Una carpeta sin ningún archivo, que es un caso aparte en las dos
        # funciones.
        New-Item -ItemType Directory -Path (Join-Path $Base 'sin-nada') -Force | Out-Null
    }
}

Describe 'Measure-Ruta da lo mismo que antes del cambio a .NET' {

    BeforeEach {
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ('fs_' + [Guid]::NewGuid())
        Initialize-ArbolDePrueba $script:Base
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'suma un arbol entero igual que Get-ChildItem -Recurse' {
        $antes = Measure-RutaComoAntes $script:Base
        $antes | Should -BeGreaterThan 0
        Measure-Ruta $script:Base | Should -Be $antes
    }

    It 'una subcarpeta cualquiera tambien coincide' {
        $sub = Join-Path $script:Base 'uno'
        Measure-Ruta $sub | Should -Be (Measure-RutaComoAntes $sub)
    }

    It 'un archivo suelto devuelve su tamanyo' {
        $archivo = Join-Path $script:Base 'a1.bin'
        Measure-Ruta $archivo | Should -Be 100
    }

    It 'una carpeta vacia devuelve cero' {
        Measure-Ruta (Join-Path $script:Base 'sin-nada') | Should -Be 0
    }

    It 'lo que no existe, lo vacio y lo que ni siquiera es una ruta devuelven cero' -ForEach @(
        @{ Caso = 'no existe';       Ruta = 'zzz-no-existe-zzz' }
        @{ Caso = 'cadena vacia';    Ruta = '' }
        @{ Caso = 'solo espacios';   Ruta = '   ' }
        # El método Comando usa la orden como Ruta: no es una ruta y no
        # puede hacer saltar nada.
        @{ Caso = 'una orden';       Ruta = 'docker system prune' }
    ) {
        Measure-Ruta $Ruta | Should -Be 0
    }
}

Describe 'Measure-RutaDetalle da lo mismo que antes del cambio a .NET' {

    BeforeEach {
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ('fs_' + [Guid]::NewGuid())
        Initialize-ArbolDePrueba $script:Base
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'coinciden los tres campos sobre un arbol con subcarpetas' {
        $antes  = Measure-RutaDetalleComoAntes $script:Base
        $ahora  = Measure-RutaDetalle $script:Base

        $antes.Archivos | Should -Be 12
        $ahora.Bytes    | Should -Be $antes.Bytes
        $ahora.Archivos | Should -Be $antes.Archivos
        $ahora.Ultimo   | Should -Be $antes.Ultimo
    }

    It 'la fecha es la del archivo mas reciente, no la del ultimo que se recorre' {
        # El código anterior ORDENABA el array entero para sacar este dato;
        # ahora es un máximo sobre ticks. Tiene que dar lo mismo aunque el
        # archivo más nuevo este en mitad del recorrido.
        $tarde = Join-Path $script:Base 'uno/hondo/a2.bin'
        [IO.File]::SetLastWriteTime($tarde, [datetime]'2030-12-31 23:00:00')

        (Measure-RutaDetalle $script:Base).Ultimo | Should -Be ([datetime]'2030-12-31 23:00:00')
    }

    It 'una carpeta sin archivos devuelve cero y SU PROPIA fecha' {
        $vacia  = Join-Path $script:Base 'sin-nada'
        $antes  = Measure-RutaDetalleComoAntes $vacia
        $ahora  = Measure-RutaDetalle $vacia

        $ahora.Bytes    | Should -Be 0
        $ahora.Archivos | Should -Be 0
        $ahora.Ultimo   | Should -Be $antes.Ultimo
        $ahora.Ultimo   | Should -Not -Be ([datetime]'1900-01-01')
    }

    It 'un archivo suelto cuenta como un archivo, no como carpeta vacia' {
        $archivo = Join-Path $script:Base 'a3.bin'
        $antes   = Measure-RutaDetalleComoAntes $archivo
        $ahora   = Measure-RutaDetalle $archivo

        $ahora.Bytes    | Should -Be $antes.Bytes
        $ahora.Archivos | Should -Be $antes.Archivos
        $ahora.Ultimo   | Should -Be $antes.Ultimo
    }

    It 'lo que no existe devuelve el objeto vacio con la fecha centinela' {
        $r = Measure-RutaDetalle (Join-Path $script:Base 'zzz')
        $r.Bytes    | Should -Be 0
        $r.Archivos | Should -Be 0
        $r.Ultimo   | Should -Be ([datetime]'1900-01-01')
    }
}

Describe 'El recorrido no atraviesa puntos de reanalisis' {

    BeforeEach {
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ('fs_' + [Guid]::NewGuid())
        Initialize-ArbolDePrueba $script:Base
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'un enlace dado como raiz devuelve cero' {
        $enlace = Join-Path ([IO.Path]::GetTempPath()) ('fs_enlace_' + [Guid]::NewGuid())
        $creado = New-Item -ItemType SymbolicLink -Path $enlace -Target $script:Base -ErrorAction SilentlyContinue
        # Sin permiso para crear enlaces no hay nada que comprobar aquí.
        if (-not $creado) { return }

        try   { Measure-Ruta $enlace | Should -Be 0 }
        finally { Remove-Item -LiteralPath $enlace -Force -ErrorAction SilentlyContinue }
    }

    It 'un enlace DENTRO del arbol no se sigue: su destino no se cuenta dos veces' {
        # Esta es la única diferencia deliberada con el código anterior.
        # Get-ChildItem -Recurse de PowerShell 5.1 SI entra en las junctions,
        # así que un enlace a una carpeta hermana hacia que sus bytes se
        # contaran dos veces, y un enlace a un ancestro daba vueltas.
        $solo   = Measure-Ruta $script:Base
        $enlace = Join-Path $script:Base 'atajo'
        $creado = New-Item -ItemType SymbolicLink -Path $enlace -Target (Join-Path $script:Base 'uno') -ErrorAction SilentlyContinue
        if (-not $creado) { return }

        Measure-Ruta $script:Base | Should -Be $solo
    }
}

Describe 'Las unidades y el nombre del sistema no se preguntan dos veces' {

    It 'Get-UnidadesFijas devuelve la forma que espera el resto del programa' {
        foreach ($unidad in @(Get-UnidadesFijas)) {
            $unidad.Letra    | Should -Not -BeNullOrEmpty
            # Hay sitios que hacen $unidad.Letra + '\': no puede venir ya
            # con separador al final. OJO: esta comprobación concreta solo
            # muerde en Windows. En Linux, DriveInfo.Name devuelve rutas de
            # montaje ("/", "/boot") y el TrimEnd no tiene nada que quitar,
            # así que aquí pasaria igual aunque estuviera mal.
            $unidad.Letra    | Should -Not -Match '\\$'
            $unidad.Etiqueta | Should -Not -BeNullOrEmpty
            $unidad.Total    | Should -BeOfType [double]
            $unidad.Libre    | Should -BeOfType [double]
        }
    }

    It 'Get-PropiedadUnidad devuelve cero ante una unidad que no existe' {
        Get-PropiedadUnidad -Unidad 'ZZ:' -Propiedad 'FreeSpace' | Should -Be 0
        Get-PropiedadUnidad -Unidad ''    -Propiedad 'Size'      | Should -Be 0
    }

    It 'Get-DescripcionSistema siempre responde algo y responde lo mismo' {
        $primera = Get-DescripcionSistema
        $primera | Should -Not -BeNullOrEmpty
        Get-DescripcionSistema | Should -Be $primera
    }
}

Describe 'SEG-40: una carpeta inaccesible no se lleva por delante lo que cuelga de ella' {

    <#
        Get-ResumenArbol envolvia el bucle de archivos y el de subcarpetas
        en un SOLO try. Una excepcion al enumerar los archivos saltaba
        tambien EnumerateDirectories, asi que las subcarpetas no se
        apilaban y toda la rama desaparecia de la suma. El sintoma no era
        un error visible: era un tamano mas pequeno de lo real, capaz de
        dejar al candidato por debajo del umbral y hacerlo desaparecer.
    #>

    BeforeEach {
        $script:raizArbol = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-arbol-' + [guid]::NewGuid())
        $script:hija = Join-Path $script:raizArbol 'subcarpeta'
        New-Item -ItemType Directory -Path $script:hija -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:raizArbol 'raiz.dat') -Value ('x' * 1000) -NoNewline
        Set-Content -LiteralPath (Join-Path $script:hija 'hija.dat')      -Value ('x' * 5000) -NoNewline
    }

    AfterEach {
        Remove-Item -LiteralPath $script:raizArbol -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'suma el arbol entero cuando todo es accesible' {
        $resumen = Get-ResumenArbol -Carpeta (Get-Item -LiteralPath $script:raizArbol)
        $resumen.Bytes    | Should -Be 6000
        $resumen.Archivos | Should -Be 2
    }

    It 'los dos recorridos son independientes: cada uno tiene su propio try' {
        # Comprobacion estructural. Simular un acceso denegado real de
        # forma portable no es posible aqui -en Linux el usuario de las
        # pruebas suele poder leerlo todo-, asi que se fija la propiedad
        # que garantiza el comportamiento: dos bloques try separados
        # dentro del bucle, uno por enumeracion.
        $ruta = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Core/FileSystem.ps1'
        $texto = Get-Content -LiteralPath $ruta -Raw

        $cuerpo = $texto.Substring($texto.IndexOf('function Get-ResumenArbol'),
                                   $texto.IndexOf('function Measure-Ruta') - $texto.IndexOf('function Get-ResumenArbol'))

        @([regex]::Matches($cuerpo, '(?m)^\s*try\s*\{')).Count |
            Should -Be 2 -Because 'un try por enumeracion: si comparten uno, perder los archivos pierde las subcarpetas'
    }
}

Describe 'REN-52: Get-HuellaRapida como prefiltro de duplicados' {

    <#
        Su contrato es asimetrico y conviene no olvidarlo: huellas
        distintas garantizan archivos distintos; huellas iguales NO
        garantizan nada y obligan al hash completo. Sirve para descartar,
        no para afirmar.
    #>

    BeforeAll {
        $script:carpetaHuella = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-huella-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaHuella -Force | Out-Null

        function New-ArchivoDePrueba {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Solo crea un archivo de prueba en una ruta temporal propia.')]
            [CmdletBinding()]
            param([string] $Nombre, [byte[]] $Contenido)

            $ruta = Join-Path $script:carpetaHuella $Nombre
            [IO.File]::WriteAllBytes($ruta, $Contenido)
            return $ruta
        }

        # Tres archivos grandes que comparten cabecera y se diferencian
        # solo al final: el caso real de dos grabaciones de la misma camara
        # o dos imagenes del mismo sistema.
        $cabecera = New-Object byte[] (200KB)
        for ($i = 0; $i -lt $cabecera.Length; $i++) { $cabecera[$i] = 7 }

        $a = $cabecera.Clone(); $a[$a.Length - 1] = 1
        $b = $cabecera.Clone(); $b[$b.Length - 1] = 2
        $c = $cabecera.Clone(); $c[$c.Length - 1] = 1

        $script:rutaA = New-ArchivoDePrueba -Nombre 'a.bin' -Contenido $a
        $script:rutaB = New-ArchivoDePrueba -Nombre 'b.bin' -Contenido $b
        $script:rutaC = New-ArchivoDePrueba -Nombre 'c.bin' -Contenido $c
    }

    AfterAll {
        Remove-Item -LiteralPath $script:carpetaHuella -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'dos archivos identicos tienen la misma huella' {
        Get-HuellaRapida -Ruta $script:rutaA | Should -Be (Get-HuellaRapida -Ruta $script:rutaC)
    }

    It 'distingue archivos que solo se diferencian al FINAL' {
        # Sin leer los ultimos 64 KB estos dos serian indistinguibles, y el
        # prefiltro no descartaria nada en el caso que mas importa.
        Get-HuellaRapida -Ruta $script:rutaA |
            Should -Not -Be (Get-HuellaRapida -Ruta $script:rutaB)
    }

    It 'el tamaño forma parte de la huella' {
        $corto = Join-Path $script:carpetaHuella 'corto.bin'
        [IO.File]::WriteAllBytes($corto, (New-Object byte[] 10))
        $largo = Join-Path $script:carpetaHuella 'largo.bin'
        [IO.File]::WriteAllBytes($largo, (New-Object byte[] 20))

        Get-HuellaRapida -Ruta $corto | Should -Not -Be (Get-HuellaRapida -Ruta $largo)
    }

    It 'funciona con archivos mas pequenos que el trozo que lee' {
        $mini = Join-Path $script:carpetaHuella 'mini.bin'
        [IO.File]::WriteAllBytes($mini, [byte[]]@(1, 2, 3))
        Get-HuellaRapida -Ruta $mini | Should -Not -BeNullOrEmpty
    }

    It 'devuelve vacio sin lanzar si el archivo no existe' {
        { Get-HuellaRapida -Ruta (Join-Path $script:carpetaHuella 'no-existe.bin') } | Should -Not -Throw
        Get-HuellaRapida -Ruta (Join-Path $script:carpetaHuella 'no-existe.bin') | Should -BeNullOrEmpty
    }

    It 'coincide consigo misma en dos lecturas seguidas' {
        Get-HuellaRapida -Ruta $script:rutaA | Should -Be (Get-HuellaRapida -Ruta $script:rutaA)
    }
}

Describe 'VIS-03: los enlaces duros se cuentan una sola vez' {

    <#
        Un enlace duro no es un acceso directo ni un punto de reanalisis:
        es otra entrada de directorio apuntando al MISMO contenido. Dos
        rutas, unos solos bytes en disco.

        El recorrido los contaba dos veces, y el modulo de duplicados los
        veia como dos copias -mismo tamano, mismo hash- y proponia borrar
        una, cuando borrar un enlace duro no libera nada.

        Estas pruebas usan enlaces duros DE VERDAD. Si el sistema de
        archivos no los admite, se saltan en vez de dar un falso verde.
    #>

    BeforeAll {
        $script:carpetaEnlaces = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-enlaces-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaEnlaces -Force | Out-Null

        $script:original = Join-Path $script:carpetaEnlaces 'original.bin'
        [IO.File]::WriteAllBytes($script:original, (New-Object byte[] 100000))

        $script:suelto = Join-Path $script:carpetaEnlaces 'suelto.bin'
        [IO.File]::WriteAllBytes($script:suelto, (New-Object byte[] 50000))

        # Se crea el enlace duro con la herramienta del sistema y se
        # comprueba que ha funcionado: en un sistema de archivos que no los
        # admita, las pruebas se saltan.
        $script:enlace = Join-Path $script:carpetaEnlaces 'enlace.bin'
        $script:HayEnlaces = $false
        try {
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                & cmd /c mklink /H "`"$script:enlace`"" "`"$script:original`"" 2>&1 | Out-Null
            } else {
                & ln $script:original $script:enlace 2>&1 | Out-Null
            }
            $script:HayEnlaces = (Test-Path -LiteralPath $script:enlace) -and
                                 ($null -ne (Get-IdentidadArchivo -Ruta $script:original))
        } catch {
            $script:HayEnlaces = $false
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:carpetaEnlaces -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'el sistema de archivos admite enlaces duros' {
        # Si esta falla, las siguientes se saltan: mejor decirlo que fingir.
        $script:HayEnlaces | Should -BeTrue -Because 'sin enlaces duros reales estas pruebas no prueban nada'
    }

    It 'un archivo con un solo enlace no tiene identidad compartida' {
        Get-IdentidadArchivo -Ruta $script:suelto |
            Should -BeNullOrEmpty -Because 'devolver $null en el caso normal es lo que lo hace barato'
    }

    It 'los dos enlaces al mismo contenido comparten identidad' {
        if (-not $script:HayEnlaces) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces duros'; return }
        Get-IdentidadArchivo -Ruta $script:original |
            Should -Be (Get-IdentidadArchivo -Ruta $script:enlace)
    }

    It 'sin el modificador se siguen contando dos veces: el comportamiento de siempre' {
        if (-not $script:HayEnlaces) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces duros'; return }
        $resumen = Get-ResumenArbol -Carpeta (Get-Item -LiteralPath $script:carpetaEnlaces)
        $resumen.Bytes | Should -Be 250000
    }

    It 'con el modificador se cuenta el contenido una sola vez' {
        if (-not $script:HayEnlaces) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces duros'; return }
        $resumen = Get-ResumenArbol -Carpeta (Get-Item -LiteralPath $script:carpetaEnlaces) -ContarEnlacesDuros

        $resumen.Bytes       | Should -Be 150000 -Because 'los 100 KB compartidos se suman una vez, no dos'
        $resumen.Archivos    | Should -Be 3      -Because 'las entradas de directorio si son tres'
        $resumen.Compartidos | Should -Be 1
    }

    It 'el conjunto se crea de verdad: un if como expresion lo habria dejado en $null' {
        # Regresion de una trampa concreta de PowerShell: "$x = if (...) {
        # [HashSet]::new() }" manda el resultado por la canalizacion, que
        # ENUMERA las colecciones, y un conjunto vacio enumerado no produce
        # nada. La comprobacion de enlaces no fallaba: no se ejecutaba, y
        # en silencio.
        #
        # Se miran solo las lineas de CODIGO: el comentario que explica la
        # trampa cita la forma incorrecta, y contarla haria fallar la
        # prueba por documentar bien el motivo.
        $lineas = Get-Content -LiteralPath (
            Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core') 'FileSystem.ps1')
        $codigo = @($lineas | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        $codigo | Should -Not -Match '\$vistos\s*=\s*if\s*\('
        $codigo | Should -Match '\$vistos\s*=\s*\$null'
    }
}
