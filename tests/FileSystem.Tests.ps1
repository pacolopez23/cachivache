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

        # SE BORRA CON System.IO Y NO CON Remove-Item.
        #
        # En Windows PowerShell 5.1, Remove-Item sobre un enlace simbolico A
        # UNA CARPETA revienta con NullReferenceException -y ni siquiera
        # -ErrorAction SilentlyContinue lo tapa, porque no es un error
        # terminable sino una excepcion del proveedor-. La prueba fallaba en
        # el finally, o sea DESPUES de haber comprobado lo que venia a
        # comprobar, y el mensaje no hablaba de enlaces.
        #
        # Directory::Delete con $false borra el ENLACE y nunca su destino,
        # que ademas es exactamente lo que este bloque quiere demostrar.
        try {
            Measure-Ruta $enlace | Should -Be 0
        } finally {
            try {
                [IO.Directory]::Delete($enlace, $false)
            } catch {
                # No se calla del todo: un enlace que no se deja borrar deja
                # basura en la carpeta temporal, y conviene poder verlo.
                Write-Verbose "No se ha podido quitar el enlace de prueba: $($_.Exception.Message)"
            }
        }
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

    It 'Get-UnidadesAnalizables devuelve la forma que espera el resto del programa' {
        foreach ($unidad in @(Get-UnidadesAnalizables)) {
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

        # El corte termina en Get-ElementosDelArbol y no en Measure-Ruta: el
        # recorrido de [COR-08] se escribio JUSTO DEBAJO, asi que el corte
        # de antes se lo tragaba y esta prueba pasaba a contar los try de
        # dos funciones. Una prueba estructural que mide un trozo mas grande
        # del que cree deja de comprobar lo que dice.
        $cuerpo = $texto.Substring($texto.IndexOf('function Get-ResumenArbol'),
                                   $texto.IndexOf('function Get-ElementosDelArbol') - $texto.IndexOf('function Get-ResumenArbol'))

        @([regex]::Matches($cuerpo, '(?m)^\s*try\s*\{')).Count |
            Should -Be 2 -Because 'un try por enumeracion: si comparten uno, perder los archivos pierde las subcarpetas'
    }

    It 'el recorrido compartido tambien lleva un try por enumeracion' {
        # La misma propiedad en Get-ElementosDelArbol, que es el recorrido
        # por el que pasan los ocho modulos desde [COR-08]. Alli el sintoma
        # seria peor que una suma corta: una carpeta sin permiso al enumerar
        # sus ARCHIVOS dejaria de proponer todo lo que cuelga de ella.
        $ruta = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Core/FileSystem.ps1'
        $texto = Get-Content -LiteralPath $ruta -Raw

        $desde = $texto.IndexOf('function Get-ElementosDelArbol')
        $hasta = $texto.IndexOf('function Measure-Ruta')
        $desde | Should -BeGreaterThan 0
        $hasta | Should -BeGreaterThan $desde

        $cuerpo = $texto.Substring($desde, $hasta - $desde)
        @([regex]::Matches($cuerpo, '(?m)^\s*try\s*\{')).Count |
            Should -Be 3 -Because 'uno para abrir la raiz y uno por cada enumeracion, archivos y subcarpetas'
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

        # DOS PREGUNTAS, NO UNA. Antes esto era una sola bandera que juntaba
        # ".el sistema de archivos admite enlaces duros?" con ".sabe verlos
        # el programa?", y al fallar no habia forma de saber cual de las dos
        # habia dicho que no. Costo una ronda entera de integracion continua.
        $script:enlace = Join-Path $script:carpetaEnlaces 'enlace.bin'
        $script:EnlaceCreado = $false
        $script:HayEnlaces   = $false
        try {
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                & cmd /c mklink /H "`"$script:enlace`"" "`"$script:original`"" 2>&1 | Out-Null
            } else {
                & ln $script:original $script:enlace 2>&1 | Out-Null
            }
            $script:EnlaceCreado = Test-Path -LiteralPath $script:enlace
            $script:HayEnlaces   = $script:EnlaceCreado -and
                                   ($null -ne (Get-IdentidadArchivo -Ruta $script:original))
        } catch {
            $script:EnlaceCreado = $false
            $script:HayEnlaces   = $false
        }

        # PowerShell 5.1 no define $PSEdition como 'Core'.
        $script:EsPwsh7 = $PSVersionTable.PSVersion.Major -ge 6
    }

    AfterAll {
        Remove-Item -LiteralPath $script:carpetaEnlaces -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'el sistema de archivos admite enlaces duros' {
        $script:EnlaceCreado | Should -BeTrue -Because 'sin enlace creado no hay nada que medir'
    }

    It 'y el programa sabe verlos, salvo la degradacion conocida de PowerShell 7' {
        <#
            AQUI HAY UN HUECO DE VERDAD, Y NO SE TAPA: SE ESCRIBE.

            Get-IdentidadArchivo, en Windows, se apoya en LinkType y Target
            de Get-Item. En Windows PowerShell 5.1 -que es donde arranca
            Cachivache.exe- eso funciona. En PowerShell 7, Target dejo de
            rellenarse para enlaces duros (solo devuelve destino de enlaces
            SIMBOLICOS), asi que la funcion contesta $null y [VIS-03] se
            degrada EN SILENCIO: los enlaces duros vuelven a contarse dos
            veces, sin un solo error.

            Por que esta prueba no se limita a saltarse en 7: porque un
            Skipped permanente es una forma de dejar de mirar. Lo que se
            exige aqui es que la degradacion sea EXACTAMENTE la conocida.
            Si algun dia apareciera tambien en 5.1 -o sea, en la version en
            la que el programa corre de verdad-, esto se pone en rojo, que
            es justo cuando hay que enterarse.

            El arreglo de verdad esta anotado como [COR-09] en la hoja de
            ruta: leer el numero de serie del volumen y el indice del
            archivo, que es el mismo dato que traeria gratis [VEL-01].
        #>
        if ($script:HayEnlaces) { return }

        $script:EsPwsh7 | Should -BeTrue -Because (
            'en PowerShell 5.1 los enlaces duros SI se detectan. Que no se detecten ahi ' +
            'significa que VIS-03 esta roto en la version con la que corre el programa')
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

Describe 'COR-08: Get-ElementosDelArbol, el recorrido que usan los modulos' {

    <#
        [COR-02] arreglo MEDIR y BORRAR una ruta de mas de 260 caracteres.
        Lo que no arreglo fue ENCONTRARLA: los modulos recorrian con
        Get-ChildItem -Recurse, que en Windows PowerShell 5.1 se para ahi
        mismo y bajo -ErrorAction SilentlyContinue no dice nada. El
        programa media bien y borraba bien lo que llegaba a proponer, pero
        no proponia lo que hay al fondo de un node_modules anidado.

        Estas pruebas fijan las cuatro cosas que no se pueden romper,
        porque romper cualquiera de ellas NO da un error: da un programa
        que propone de menos -y se queda callado- o, peor, de mas.

        AVISO SOBRE EL LIMITE DE 260: es de Windows. Aqui se pueden crear y
        recorrer rutas mucho mas largas sin prefijo ninguno, asi que lo que
        estas pruebas comprueban es que el recorrido AGUANTA un arbol
        hondo de verdad y que la ruta que devuelve sale limpia. Que el
        prefijo se ponga es una invariante de texto, y la prueba de verdad
        la hace la CI del banco en un Windows real.
    #>

    BeforeEach {
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ('cor08-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Base -Force | Out-Null

        # Un archivo arriba, otro en una subcarpeta, uno oculto y uno con
        # otra extension, para poder probar el filtro sin inventar nada.
        [IO.File]::WriteAllText((Join-Path $script:Base 'arriba.tmp'), 'aaa')
        [IO.File]::WriteAllText((Join-Path $script:Base 'otro.lnk'), 'bb')
        New-Item -ItemType Directory -Path (Join-Path $script:Base 'sub') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:Base 'sub/dentro.tmp'), 'cccc')
        [IO.File]::WriteAllText((Join-Path $script:Base 'sub/.oculto'), 'ddddd')

        # Una rama de verdad de mas de 260 caracteres, con carpetas reales
        # y no con una cadena larga: es la unica forma de probar que el
        # recorrido baja hasta el fondo.
        $script:Hondo = $script:Base
        1..12 | ForEach-Object {
            $script:Hondo = Join-Path $script:Hondo ('carpeta-anidada-con-nombre-largo-numero-{0:00}' -f $_)
        }
        New-Item -ItemType Directory -Path $script:Hondo -Force | Out-Null
        $script:ArchivoHondo = Join-Path $script:Hondo 'volcado-antiguo.dmp'
        [IO.File]::WriteAllText($script:ArchivoHondo, 'x' * 28)
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'el arbol de prueba es hondo de verdad: si no, esta prueba no comprueba nada' {
        # La guarda. Sin ella, un Join-Path que se quedara corto convertiria
        # todo lo de abajo en "recorrer una carpeta normal", que es
        # justamente lo que ya funcionaba antes.
        $script:ArchivoHondo.Length | Should -BeGreaterThan 260
    }

    It 'encuentra lo mismo que Get-ChildItem -Recurse -File -Force' {
        $mio  = @(Get-ElementosDelArbol -Ruta $script:Base | ForEach-Object { $_.FullName }) | Sort-Object
        $suyo = @(Get-ChildItem -LiteralPath $script:Base -Recurse -File -Force -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.FullName }) | Sort-Object

        @($suyo).Count | Should -BeGreaterThan 3
        ($mio -join '|') | Should -Be ($suyo -join '|')
    }

    It 'llega al archivo del fondo de la rama larga' {
        @(Get-ElementosDelArbol -Ruta $script:Base | Where-Object { $_.FullName -eq $script:ArchivoHondo }).Count |
            Should -Be 1
    }

    It 'ninguna ruta que sale lleva el prefijo de ruta larga' {
        # La regla que no se puede romper: esta ruta acaba en el campo Ruta
        # de un candidato y de ahi en la guardia. Con el prefijo, la guardia
        # compararia "\\?\C:\Windows" contra su lista negra "C:\Windows" y
        # NO coincidiria: un prefijo para encontrar mejor se convertiria en
        # un agujero para borrar el sistema.
        foreach ($elemento in @(Get-ElementosDelArbol -Ruta $script:Base -Que Todo)) {
            $elemento.FullName    | Should -Not -Match '\\\\\?\\'
            $elemento.DirectoryName | Should -Not -Match '\\\\\?\\'
        }
    }

    It 've los archivos ocultos, que es lo que hacia -Force' {
        # Sin esto no falla nada: media docena de modulos viven de archivos
        # ocultos -Thumbs.db, desktop.ini, los contenedores de la papelera-
        # y simplemente dejarian de encontrar cosas.
        $sinForce = @(Get-ChildItem -LiteralPath (Join-Path $script:Base 'sub') -File -ErrorAction SilentlyContinue).Count
        $conForce = @(Get-ChildItem -LiteralPath (Join-Path $script:Base 'sub') -File -Force -ErrorAction SilentlyContinue).Count
        if ($sinForce -eq $conForce) {
            Set-ItResult -Skipped -Because 'aqui no hay archivos ocultos que distingan una cosa de la otra'
            return
        }
        @(Get-ElementosDelArbol -Ruta $script:Base | Where-Object { $_.Name -eq '.oculto' }).Count | Should -Be 1
    }

    It 'trae las propiedades con las que deciden los modulos' {
        $archivo = @(Get-ElementosDelArbol -Ruta $script:Base | Where-Object { $_.Name -eq 'arriba.tmp' })[0]

        # Una a una, porque cada una la usa algun modulo: si alguna se
        # cayera, ese modulo empezaria a comparar contra $null y a decidir
        # que no, sin un solo error.
        $archivo.FullName      | Should -Be (Join-Path $script:Base 'arriba.tmp')
        $archivo.Name          | Should -Be 'arriba.tmp'
        $archivo.BaseName      | Should -Be 'arriba'
        $archivo.Extension     | Should -Be '.tmp'
        $archivo.Length        | Should -Be 3
        $archivo.DirectoryName | Should -Be $script:Base
        $archivo.EsCarpeta     | Should -BeFalse
        $archivo.LastWriteTime | Should -BeOfType [datetime]
        $archivo.LastAccessTime| Should -BeOfType [datetime]
        $archivo.CreationTime  | Should -BeOfType [datetime]
        [int]$archivo.Attributes | Should -BeGreaterThan 0
    }

    It 'el filtro lo resuelve la API y no cambia por donde se desciende' {
        $conFiltro = @(Get-ElementosDelArbol -Ruta $script:Base -Filtro '*.tmp' | ForEach-Object { $_.Name })
        $conFiltro | Should -Contain 'arriba.tmp'
        $conFiltro | Should -Contain 'dentro.tmp'
        $conFiltro | Should -Not -Contain 'otro.lnk'

        # Y el filtro NO poda: el .dmp del fondo esta detras de doce
        # carpetas que no casan con ningun patron de archivo.
        @(Get-ElementosDelArbol -Ruta $script:Base -Filtro '*.dmp').Count | Should -Be 1
    }

    It 'la barra final de la carpeta de partida no ensucia lo que sale' {
        # Con ella, la primera ruta compuesta saldria con dos separadores
        # seguidos y dejaria de ser igual, COMO TEXTO, a la que devuelve
        # Windows. Y estas rutas se comparan como texto en la guardia, en
        # las exclusiones y en el comprobador del banco.
        $conBarra = @(Get-ElementosDelArbol -Ruta ($script:Base + [IO.Path]::DirectorySeparatorChar) |
                      ForEach-Object { $_.FullName }) | Sort-Object
        $sinBarra = @(Get-ElementosDelArbol -Ruta $script:Base | ForEach-Object { $_.FullName }) | Sort-Object
        ($conBarra -join '|') | Should -Be ($sinBarra -join '|')
    }

    It 'lo que no existe, lo vacio y lo que ni siquiera es una ruta no lanzan' -ForEach @(
        @{ Caso = 'no existe';     Ruta = '/zzz-no-existe-zzz/tampoco' }
        @{ Caso = 'cadena vacia';  Ruta = '' }
        @{ Caso = 'solo espacios'; Ruta = '   ' }
        # El metodo Comando usa la orden como Ruta.
        @{ Caso = 'una etiqueta';  Ruta = 'docker system prune' }
    ) {
        { $null = @(Get-ElementosDelArbol -Ruta $Ruta) } | Should -Not -Throw
        @(Get-ElementosDelArbol -Ruta $Ruta).Count | Should -Be 0
    }

    It 'con Ruta a $null no lanza' {
        # [AllowNull()] en un Mandatory que puede recibir nulo. Ha faltado
        # tres veces en este proyecto y las tres lo cazo esta prueba.
        { $null = @(Get-ElementosDelArbol -Ruta $null) } | Should -Not -Throw
    }

    It 'Que Carpetas devuelve carpetas y no archivos' {
        $carpetas = @(Get-ElementosDelArbol -Ruta $script:Base -Que Carpetas)
        @($carpetas | Where-Object { -not $_.EsCarpeta }).Count | Should -Be 0
        @($carpetas | Where-Object { $_.Name -eq 'sub' }).Count | Should -Be 1
        # Las doce de la rama honda tambien.
        @($carpetas).Count | Should -BeGreaterThan 12
    }

    It 'Que Todo devuelve las dos cosas' {
        $todo = @(Get-ElementosDelArbol -Ruta $script:Base -Que Todo)
        @($todo | Where-Object { $_.EsCarpeta }).Count       | Should -BeGreaterThan 0
        @($todo | Where-Object { -not $_.EsCarpeta }).Count  | Should -BeGreaterThan 0
    }

    It 'NoDescender poda la rama entera, no solo la carpeta' {
        $poda = { param($C) return ($C.Name -eq 'carpeta-anidada-con-nombre-largo-numero-01') }
        $rutas = @(Get-ElementosDelArbol -Ruta $script:Base -NoDescender $poda | ForEach-Object { $_.FullName })

        $rutas | Should -Not -Contain $script:ArchivoHondo
        $rutas | Should -Contain (Join-Path $script:Base 'arriba.tmp')
    }

    It 'Cancelado para el recorrido' {
        $veces = @{ N = 0 }
        # Se cancela a la segunda carpeta: lo que importa es que PARE, no
        # cuanto devuelve antes de parar.
        $cancela = { $veces.N++; return ($veces.N -gt 2) }
        $antes = @(Get-ElementosDelArbol -Ruta $script:Base).Count
        $antes | Should -BeGreaterThan 3
        @(Get-ElementosDelArbol -Ruta $script:Base -Cancelado $cancela).Count | Should -BeLessThan $antes
    }
}

Describe 'COR-08: los enlaces no se siguen, ni al recorrer ni al proponer' {

    BeforeAll {
        $script:BaseEnl = Join-Path ([IO.Path]::GetTempPath()) ('cor08e-' + [guid]::NewGuid())
        $script:Destino = Join-Path $script:BaseEnl 'destino'
        New-Item -ItemType Directory -Path $script:Destino -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:Destino 'tesoro.tmp'), 'x' * 10)

        $script:HayEnlace = $false
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $script:BaseEnl 'atajo') `
                     -Target $script:Destino -ErrorAction Stop | Out-Null
            $script:HayEnlace = $true
        } catch {
            Write-Verbose "Sin enlaces simbolicos en este sistema: $($_.Exception.Message)"
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:BaseEnl -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'un punto de reanalisis no se sigue: el contenido sale una sola vez' {
        if (-not $script:HayEnlace) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces simbolicos'; return }
        # Si se siguiera, tesoro.tmp saldria dos veces -por su carpeta y por
        # el atajo- y se propondria dos veces para borrar el mismo archivo.
        @(Get-ElementosDelArbol -Ruta $script:BaseEnl | Where-Object { $_.Name -eq 'tesoro.tmp' }).Count |
            Should -Be 1
    }

    It 'por defecto el enlace ni siquiera se devuelve' {
        if (-not $script:HayEnlace) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces simbolicos'; return }
        @(Get-ElementosDelArbol -Ruta $script:BaseEnl -Que Carpetas | Where-Object { $_.Name -eq 'atajo' }).Count |
            Should -Be 0
    }

    It 'con -IncluirEnlaces se devuelve, pero sigue sin entrarse' {
        if (-not $script:HayEnlace) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces simbolicos'; return }
        # Lo necesita Remove-RutaSegura, que busca precisamente enlaces
        # dentro de una carpeta antes de borrarla recursivamente.
        @(Get-ElementosDelArbol -Ruta $script:BaseEnl -Que Carpetas -IncluirEnlaces |
          Where-Object { $_.Name -eq 'atajo' }).Count | Should -Be 1
        @(Get-ElementosDelArbol -Ruta $script:BaseEnl -Que Todo -IncluirEnlaces |
          Where-Object { $_.Name -eq 'tesoro.tmp' }).Count | Should -Be 1
    }
}

Describe 'COR-08: una carpeta sin permiso no puede abortar el recorrido' {

    BeforeAll {
        $script:BasePerm = Join-Path ([IO.Path]::GetTempPath()) ('cor08p-' + [guid]::NewGuid())
        $script:Cerrada  = Join-Path $script:BasePerm 'cerrada'
        New-Item -ItemType Directory -Path $script:Cerrada -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:Cerrada 'dentro.tmp'), 'x')
        [IO.File]::WriteAllText((Join-Path $script:BasePerm 'hermano.tmp'), 'yy')

        # chmod no existe en Windows y ahi esto no cierra nada: por eso
        # abajo hay una guarda que se salta la prueba si la carpeta sigue
        # leyendose. Sin la guarda, en Windows pasaria sin comprobar nada.
        $script:Cerro = $false
        try {
            & chmod 000 $script:Cerrada 2>$null
            $script:Cerro = -not (Test-Path -LiteralPath (Join-Path $script:Cerrada 'dentro.tmp') `
                                            -ErrorAction SilentlyContinue)
        } catch {
            Write-Verbose "No se ha podido cerrar la carpeta: $($_.Exception.Message)"
        }
    }

    AfterAll {
        & chmod 755 $script:Cerrada 2>$null
        Remove-Item -LiteralPath $script:BasePerm -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'se pierde esa carpeta y no el recorrido entero' {
        if (-not $script:Cerro) { Set-ItResult -Skipped -Because 'aqui no se puede cerrar una carpeta'; return }

        { $script:Salida = @(Get-ElementosDelArbol -Ruta $script:BasePerm) } | Should -Not -Throw
        $rutas = @($script:Salida | ForEach-Object { $_.Name })

        $rutas | Should -Contain 'hermano.tmp' -Because 'lo que si se puede leer se sigue devolviendo'
        $rutas | Should -Not -Contain 'dentro.tmp'
    }

    It 'con ErrorActionPreference en Stop -que es lo que pone el modo consola- sigue sin abortar' {
        if (-not $script:Cerro) { Set-ItResult -Skipped -Because 'aqui no se puede cerrar una carpeta'; return }

        # Es la prueba del comentario de Get-ResumenArbol, y aqui vale
        # igual: Cachivache.ps1 pone ErrorActionPreference a 'Stop' en modo
        # consola, asi que si el catch de una carpeta sin permisos se
        # cambiara por un Write-Error -o desapareciera-, una sola carpeta
        # ilegible tumbaria el analisis entero.
        #
        # NO se comprueba con -ErrorVariable: PowerShell apunta en $Error
        # las excepciones de metodo aunque las cace un try, asi que esa
        # cuenta sale distinta de cero incluso estando todo bien. Lo que
        # importa no es que $Error quede limpio, es que no se aborte.
        $previo = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            { $script:Duro = @(Get-ElementosDelArbol -Ruta $script:BasePerm) } | Should -Not -Throw
        } finally {
            $ErrorActionPreference = $previo
        }
        @($script:Duro | ForEach-Object { $_.Name }) | Should -Contain 'hermano.tmp'
    }
}

Describe 'COR-08: Measure-RutaLarga, la mitad que faltaba de la medicion' {

    <#
        Al arreglar el recorrido, los modulos empezaron a encontrar cosas
        cuya RUTA ya es larga de por si. Get-Item no las resuelve en
        PowerShell 5.1, Measure-Ruta devolvia cero y el candidato caia por
        debajo del minimo: encontrarlo mejor solo servia para tirarlo un
        paso despues, otra vez en silencio.

        El camino de System.IO con prefijo NO se puede ejecutar aqui: el
        limite es de Windows y ConvertTo-RutaLarga deja las rutas de este
        sistema como estan, a proposito. Lo que si se puede fijar es que la
        funcion no se meta donde no la llaman ni lance con nada raro.
    #>

    It 'una ruta que no es larga devuelve cero sin mirar el disco' {
        Measure-RutaLarga -Ruta '/tmp' | Should -Be 0.0
    }

    It 'con nulo, vacio y una etiqueta no lanza' -ForEach @(
        @{ Caso = 'nulo';     Ruta = $null }
        @{ Caso = 'vacio';    Ruta = '' }
        @{ Caso = 'etiqueta'; Ruta = 'docker system prune' }
    ) {
        { Measure-RutaLarga -Ruta $Ruta } | Should -Not -Throw
        Measure-RutaLarga -Ruta $Ruta | Should -Be 0.0
    }

    It 'Measure-Ruta solo cae en ella cuando Get-Item no ha resuelto nada' {
        # Comprobacion estructural, porque el camino de verdad solo existe
        # en Windows: lo que se fija es que la llamada esta EN la rama del
        # $null y no antes, que es lo que garantiza que no cambia ni un
        # caso de los que ya funcionaban.
        $texto = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core') 'FileSystem.ps1')
        $codigo = @(($texto -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $codigo | Should -Match '\$null -eq \$item\s*\)\s*\{ return \(Measure-RutaLarga -Ruta \$Ruta\) \}'
    }
}
