<#
    Pruebas de la persistencia del indice en disco: [VEL-02].

    Lo que aqui se comprueba, y por que:

      1. QUE LA IDA Y VUELTA NO PIERDE NADA, y muy en concreto que no
         pierde LOS TOTALES POR CARPETA. Esa es la razon de que se guarden
         tres tablas y no una: volver a sumar las carpetas desde el millon
         de archivos cuesta 6 s, mas que el recorrido completo que se
         queria evitar. Ver docs/VEL-02-MEDICION.md.

      2. QUE NADA LANZA ANTE UN ARCHIVO QUE NO SIRVE. Truncado a la mitad,
         con bytes cambiados, de una version del formato del futuro, de
         cero bytes, lleno de basura, o que no esta. Los siete casos
         devuelven $null. La regla del proyecto es "ante la duda, no
         afirmar": quien llama recorre el disco de nuevo, que cuesta cinco
         segundos, y desde fuera solo se nota en que esta vez tardo lo de
         siempre.

      3. QUE LA ESCRITURA ES ATOMICA. Un apagon a mitad de escritura no
         puede dejar un archivo a medias que despues se lea como bueno.

      4. CUANTO TARDA DE VERDAD guardar y cargar 10.000 entradas, para
         dejar constancia de que la implementacion se parece a lo que se
         midio (0,02 s guardar y 0,01 s cargar en el banco).

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    $script:Nucleo = Join-Path (Join-Path $script:Raiz 'src') 'Core'
    . (Join-Path $script:Nucleo 'Bootstrap.ps1')

    # IndicePersistente.ps1 lo carga ya Bootstrap.ps1, asi que aqui NO se
    # vuelve a dot-sourcear: hacerlo funcionaria, pero estas pruebas
    # dejarian de medir como se carga el archivo en el programa de verdad.
    # La ruta se guarda solo para las invariantes que leen su texto.
    $script:RutaPersistente = Join-Path $script:Nucleo 'IndicePersistente.ps1'

    $script:Zona = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-idxdisco-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:Zona -Force | Out-Null

    function New-ArbolDeIndice {
        <#
        .SYNOPSIS
            Arbol pequenyo con proporciones conocidas, para que el indice
            que se guarda sea uno de verdad y no una imitacion.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo crea un arbol de prueba en una ruta temporal propia.')]
        [CmdletBinding()]
        param([Parameter(Mandatory)] [string] $Raiz)

        foreach ($c in @('grande/dentro', 'mediana', 'pequena')) {
            New-Item -ItemType Directory -Path (Join-Path $Raiz $c) -Force | Out-Null
        }
        [IO.File]::WriteAllBytes((Join-Path $Raiz 'grande/dentro/a.bin'), [byte[]]::new(8000000))
        [IO.File]::WriteAllBytes((Join-Path $Raiz 'grande/suelto.bin'),   [byte[]]::new(2000000))
        [IO.File]::WriteAllBytes((Join-Path $Raiz 'mediana/b.bin'),       [byte[]]::new(4000000))
        [IO.File]::WriteAllBytes((Join-Path $Raiz 'pequena/c.bin'),       [byte[]]::new(1500000))
        [IO.File]::WriteAllBytes((Join-Path $Raiz 'pequena/menudo.bin'),  [byte[]]::new(1000))
    }

    function New-IndiceSintetico {
        <#
        .SYNOPSIS
            Un indice con la forma EXACTA que devuelve New-IndiceDisco,
            del tamanyo que se pida. Para medir sin tocar el disco.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone un objeto en memoria.')]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [int] $Archivos,
            [Parameter(Mandatory)] [int] $Carpetas
        )

        $tablaCarpetas = [Collections.Generic.Dictionary[string, object]]::new(
                             [StringComparer]::OrdinalIgnoreCase)
        for ($i = 0; $i -lt $Carpetas; $i++) {
            # Division entera a mano: [int]($i / 20) REDONDEA, no trunca, y
            # eso deja archivos colgando de carpetas que no existen. Le
            # paso al banco de VEL-02 y se ve tarde.
            $ruta = 'C:\Sintetico\c{0}' -f $i
            $tablaCarpetas[$ruta] = [pscustomobject]@{
                Ruta     = $ruta
                Nombre   = 'c{0}' -f $i
                Nivel    = 1
                Bytes    = [double](1000 * ($i + 1))
                Propios  = [double](500 * ($i + 1))
                Archivos = $i
                Ultimo   = [datetime]'2026-09-01T10:00:00'
            }
        }

        $lista = [Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $Archivos; $i++) {
            $carpeta = 'C:\Sintetico\c{0}' -f ($i % [Math]::Max(1, $Carpetas))
            # Las dos cadenas se arman ANTES, en su variable. Dentro de un
            # .Add(...) la coma del -f la lee PowerShell como separador de
            # argumentos DEL METODO, no del formato, y el archivo no llega
            # ni a analizarse. Es una de las trampas de docs/RELEVO.md, y
            # ha mordido aqui mismo al escribir esta prueba.
            $nombre = 'archivo{0}.bin' -f $i
            $ruta = '{0}\{1}' -f $carpeta, $nombre
            $lista.Add([pscustomobject]@{
                Ruta      = $ruta
                Nombre    = $nombre
                Carpeta   = $carpeta
                Extension = '.bin'
                Bytes     = [double](1024 * $i)
                Ultimo    = [datetime]'2026-08-31T23:59:59'
            })
        }

        return [pscustomobject]@{
            Carpetas      = $tablaCarpetas
            Archivos      = $lista.ToArray()
            Raices        = @('C:\Sintetico')
            Bytes         = 123456789.0
            TotalArchivos = $Archivos
            Compartidos   = 3
            Inaccesibles  = 7
            UmbralArchivo = 1048576.0
        }
    }
}

Describe 'Get-SumaCuerpoIndice' {

    It 'la misma secuencia de bytes da siempre la misma suma' {
        $a = [byte[]] @(1, 2, 3, 4, 5)
        $b = [byte[]] @(1, 2, 3, 4, 5)
        (Get-SumaCuerpoIndice -Bytes $a) | Should -Be (Get-SumaCuerpoIndice -Bytes $b)
    }

    It 'un solo byte distinto cambia la suma' {
        $a = [byte[]] @(1, 2, 3, 4, 5)
        $b = [byte[]] @(1, 2, 3, 4, 6)
        (Get-SumaCuerpoIndice -Bytes $a) | Should -Not -Be (Get-SumaCuerpoIndice -Bytes $b)
    }

    It 'un cuerpo truncado no da la misma suma que el entero' {
        $entero = [byte[]] @(9, 8, 7, 6, 5, 4)
        $medio  = [byte[]] @(9, 8, 7)
        (Get-SumaCuerpoIndice -Bytes $entero) | Should -Not -Be (Get-SumaCuerpoIndice -Bytes $medio)
    }

    It 'un cuerpo nulo no lanza y vale lo mismo que uno vacio' {
        # Un indice sin entradas es un caso normal, no un error.
        { Get-SumaCuerpoIndice -Bytes $null } | Should -Not -Throw
        $vacio = Get-SumaCuerpoIndice -Bytes ([byte[]]::new(0))
        (Get-SumaCuerpoIndice -Bytes $null) | Should -Be $vacio
    }

    It 'la suma es hexadecimal en minusculas y siempre de la misma longitud' {
        $suma = Get-SumaCuerpoIndice -Bytes ([byte[]] @(1, 2, 3))
        $suma | Should -Match '^[0-9a-f]{64}$'
    }
}

Describe 'Ida y vuelta con un indice de verdad' {

    BeforeAll {
        $script:ZonaArbol = Join-Path $script:Zona 'arbol'
        New-Item -ItemType Directory -Path $script:ZonaArbol -Force | Out-Null
        New-ArbolDeIndice -Raiz $script:ZonaArbol

        $script:Original = New-IndiceDisco -Rutas @($script:ZonaArbol) -MinimoArchivoBytes 1MB

        $script:Refs = [Collections.Generic.Dictionary[uint64, string]]::new()
        $script:Refs[[uint64]5] = $script:ZonaArbol
        $script:Refs[[uint64]1152921504606846976] = (Join-Path $script:ZonaArbol 'grande')

        $script:Escrito = [datetime]'2026-09-01T08:30:15'
        $script:RutaIndice = Join-Path $script:Zona 'indice.cachidx'
        $script:Guardado = Save-IndiceDisco -Indice $script:Original -Ruta $script:RutaIndice `
                             -SerieVolumen 'AABB-1234' -IdDiario '18446744073709551615' `
                             -UsnCorte 987654321 -Referencias $script:Refs -Escrito $script:Escrito

        $script:Leido = Read-IndiceDisco -Ruta $script:RutaIndice
        $script:Cabecera = Get-CabeceraIndice -Ruta $script:RutaIndice
    }

    It 'la prueba parte de un indice con contenido: si no, no comprueba nada' {
        $script:Guardado | Should -BeTrue
        @($script:Original.Carpetas.Values).Count | Should -BeGreaterThan 3
        @($script:Original.Archivos).Count | Should -BeGreaterThan 2
    }

    It 'se ha escrito el archivo y no ha quedado ningun temporal en medio' {
        Test-Path -LiteralPath $script:RutaIndice | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:Zona -Filter '*.tmp').Count | Should -Be 0
    }

    It 'la cabecera trae los siete campos acordados, ni uno mas ni uno menos' {
        # Los nombres son un contrato con quien valida la cabecera. Si aqui
        # se anyade o se quita uno, los dos lados dejan de hablar el mismo
        # idioma sin que nada lo diga.
        $campos = @($script:Cabecera.PSObject.Properties.Name) -join ','
        $campos | Should -Be 'Version,SerieVolumen,IdDiario,UsnCorte,Entradas,Suma,Escrito'
    }

    It 'la cabecera dice lo que se le paso al guardar' {
        $script:Cabecera.Version      | Should -Be 1
        $script:Cabecera.SerieVolumen | Should -Be 'AABB-1234'
        $script:Cabecera.IdDiario     | Should -Be '18446744073709551615'
        $script:Cabecera.UsnCorte     | Should -Be 987654321
        $script:Cabecera.Entradas     | Should -Be @($script:Original.Archivos).Count
        $script:Cabecera.Escrito      | Should -Be $script:Escrito
        $script:Cabecera.Suma         | Should -Match '^[0-9a-f]{64}$'
    }

    It 'la cabecera se lee sin cargar el cuerpo, y coincide con la del indice leido' {
        $script:Leido.Cabecera.Suma | Should -Be $script:Cabecera.Suma
    }

    It 'Read-CabeceraIndiceFlujo deja el flujo justo al principio del cuerpo' {
        # Es el trozo que comparten los dos caminos -quedarse en la
        # cabecera o seguir hasta el final-, y lo que garantiza que los dos
        # entiendan lo mismo por "cabecera valida". Si dejara el flujo un
        # byte descolocado, la suma del cuerpo no cuadraria nunca y el
        # indice no se cargaria jamas, con las siete comprobaciones en
        # verde.
        $flujo = [IO.File]::Open($script:RutaIndice, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                                 [IO.FileShare]::ReadWrite)
        $lector = [IO.BinaryReader]::new($flujo, [Text.UTF8Encoding]::new($false))
        try {
            $cab = Read-CabeceraIndiceFlujo -Lector $lector
            $cab | Should -Not -BeNullOrEmpty
            $cab.Suma | Should -Be $script:Cabecera.Suma

            # Los ocho bytes de la longitud del cuerpo ya estan leidos: se
            # retrocede sobre ellos porque la suma los cubre tambien.
            $flujo.Position | Should -BeGreaterThan 8
            $flujo.Position = $flujo.Position - 8
            $cuerpo = $lector.ReadBytes([int]($flujo.Length - $flujo.Position))
            (Get-SumaCuerpoIndice -Bytes $cuerpo) | Should -Be $script:Cabecera.Suma
        } finally {
            $lector.Dispose()
            $flujo.Dispose()
        }
    }

    It 'los totales generales sobreviven a la ida y vuelta' {
        $script:Leido.Bytes         | Should -Be $script:Original.Bytes
        $script:Leido.TotalArchivos | Should -Be $script:Original.TotalArchivos
        $script:Leido.Compartidos   | Should -Be $script:Original.Compartidos
        $script:Leido.Inaccesibles  | Should -Be $script:Original.Inaccesibles
        $script:Leido.UmbralArchivo | Should -Be $script:Original.UmbralArchivo
        (@($script:Leido.Raices) -join '|') | Should -Be (@($script:Original.Raices) -join '|')
    }

    It 'los totales POR CARPETA sobreviven, campo a campo' {
        # La razon de existir de la segunda tabla. Si esto se pierde, al
        # cargar hay que volver a sumar el millon de archivos: 6 s, mas
        # que recorrer el disco entero.
        @($script:Leido.Carpetas.Keys).Count | Should -Be @($script:Original.Carpetas.Keys).Count
        $revisadas = 0
        foreach ($c in $script:Original.Carpetas.Values) {
            $script:Leido.Carpetas.ContainsKey($c.Ruta) | Should -BeTrue
            $v = $script:Leido.Carpetas[$c.Ruta]
            $v.Nombre   | Should -Be $c.Nombre
            $v.Nivel    | Should -Be $c.Nivel
            $v.Bytes    | Should -Be $c.Bytes
            $v.Propios  | Should -Be $c.Propios
            $v.Archivos | Should -Be $c.Archivos
            $v.Ultimo   | Should -Be $c.Ultimo
            $revisadas++
        }
        $revisadas | Should -BeGreaterThan 3 -Because 'sin carpetas esto no comprueba nada'
    }

    It 'la lista de archivos sobrevive entera, campo a campo y en el mismo orden' {
        $originales = @($script:Original.Archivos)
        $leidos = @($script:Leido.Archivos)
        $leidos.Count | Should -Be $originales.Count
        for ($i = 0; $i -lt $originales.Count; $i++) {
            $leidos[$i].Ruta      | Should -Be $originales[$i].Ruta
            $leidos[$i].Nombre    | Should -Be $originales[$i].Nombre
            $leidos[$i].Carpeta   | Should -Be $originales[$i].Carpeta
            $leidos[$i].Extension | Should -Be $originales[$i].Extension
            $leidos[$i].Bytes     | Should -Be $originales[$i].Bytes
            $leidos[$i].Ultimo    | Should -Be $originales[$i].Ultimo
        }
    }

    It 'la tabla de referencia de carpeta a ruta sobrevive, incluidos los numeros grandes' {
        # Las referencias de NTFS son de 64 bits SIN signo. Guardadas como
        # con signo, esta clave saldria negativa y no se encontraria nunca.
        @($script:Leido.Referencias.Keys).Count | Should -Be 2
        $script:Leido.Referencias[[uint64]5] | Should -Be $script:ZonaArbol
        $script:Leido.Referencias[[uint64]1152921504606846976] |
            Should -Be (Join-Path $script:ZonaArbol 'grande')
    }

    It 'lo leido se puede volver a guardar y a leer sin perder nada' {
        $segunda = Join-Path $script:Zona 'indice-2.cachidx'
        (Save-IndiceDisco -Indice $script:Leido -Ruta $segunda -Escrito $script:Escrito) |
            Should -BeTrue
        $otra = Read-IndiceDisco -Ruta $segunda
        $otra | Should -Not -BeNullOrEmpty
        $otra.Bytes | Should -Be $script:Original.Bytes
        @($otra.Archivos).Count | Should -Be @($script:Original.Archivos).Count
        @($otra.Carpetas.Keys).Count | Should -Be @($script:Original.Carpetas.Keys).Count
    }

    It 'las entradas se leen a DICCIONARIO y no a pscustomobject' {
        # Esto no es un detalle de implementacion: leer un millon de
        # entradas a objetos de PowerShell cuesta 12,38 s contra 1,04 s.
        # Doce veces. Medido en docs/VEL-02-MEDICION.md.
        @($script:Leido.Archivos).Count | Should -BeGreaterThan 0
        $script:Leido.Archivos[0] -is [Collections.IDictionary] | Should -BeTrue
        @($script:Leido.Carpetas.Values)[0] -is [Collections.IDictionary] | Should -BeTrue
    }

    It 'una entrada leida se deja usar igual que la que produce el recorrido' {
        # La promesa es "que quien lo consuma no note de donde vino": se
        # accede por propiedad, se ordena y se filtra igual.
        #
        # OJO CON EL ORDEN, que es donde la promesa tiene UN limite y hay
        # que decirlo. Las entradas leidas son diccionarios, y en Windows
        # PowerShell 5.1 un "Sort-Object Bytes" a secas sobre diccionarios
        # NO ORDENA: devuelve la lista tal cual, sin quejarse. Esta prueba
        # se escribio asi y pasaba en Linux mientras en 5.1 comparaba el
        # primer elemento contra el mayor.
        #
        # Se ordena con una expresion, que es como lo hace el programa de
        # verdad (Get-VistaArchivos, src/Core/VistaArchivos.ps1). No es
        # casualidad ni suerte: es la unica forma que funciona en las dos
        # versiones, y por eso hay una invariante mas abajo que lo exige.
        $porBytes = { [double]$_.Bytes }
        $mayor = @($script:Leido.Archivos | Sort-Object $porBytes -Descending)[0]
        $mayorOriginal = @($script:Original.Archivos | Sort-Object $porBytes -Descending)[0]
        $mayor.Bytes | Should -Be $mayorOriginal.Bytes
        @($script:Leido.Carpetas.Values | Where-Object { $_.Bytes -gt 0 }).Count |
            Should -BeGreaterThan 0
        # Y una propiedad que no existe se lee como $null, sin lanzar,
        # igual que en un pscustomobject.
        { $null -eq $script:Leido.Archivos[0].NoExiste } | Should -Not -Throw
    }
}

Describe 'Un indice vacio' {

    BeforeAll {
        $script:Vacio = [pscustomobject]@{
            Carpetas      = [Collections.Generic.Dictionary[string, object]]::new()
            Archivos      = @()
            Raices        = @()
            Bytes         = 0.0
            TotalArchivos = 0
            Compartidos   = 0
            Inaccesibles  = 0
            UmbralArchivo = 1048576.0
        }
        $script:RutaVacio = Join-Path $script:Zona 'vacio.cachidx'
        $script:GuardadoVacio = Save-IndiceDisco -Indice $script:Vacio -Ruta $script:RutaVacio
        $script:LeidoVacio = Read-IndiceDisco -Ruta $script:RutaVacio
    }

    It 'se guarda sin protestar' {
        $script:GuardadoVacio | Should -BeTrue
    }

    It 'se lee, y lo que sale esta vacio pero NO es $null' {
        # Un indice de cero entradas es una respuesta valida -un disco que
        # no tenia nada-, y hay que poder distinguirla de "no se pudo
        # leer". Si esto devolviera $null, quien llama recorreria el disco
        # cada vez sin motivo.
        $script:LeidoVacio | Should -Not -BeNullOrEmpty
        @($script:LeidoVacio.Archivos).Count | Should -Be 0
        @($script:LeidoVacio.Carpetas.Keys).Count | Should -Be 0
        @($script:LeidoVacio.Referencias.Keys).Count | Should -Be 0
    }

    It 'su cabecera dice que trae cero entradas' {
        (Get-CabeceraIndice -Ruta $script:RutaVacio).Entradas | Should -Be 0
    }
}

Describe 'Ante la duda, no afirmar: nada lanza y todo devuelve $null' {

    BeforeAll {
        # Se construye AQUI y no en el cuerpo del Describe: lo que se
        # asigna alli se evalua en el DESCUBRIMIENTO de Pester y llega
        # vacio a los It. Ha mordido tres veces en este proyecto.
        $script:Sano = Join-Path $script:Zona 'sano.cachidx'
        $indice = New-IndiceSintetico -Archivos 50 -Carpetas 5
        [void](Save-IndiceDisco -Indice $indice -Ruta $script:Sano -SerieVolumen 'CCDD-5678')
        $bytes = [IO.File]::ReadAllBytes($script:Sano)

        $script:Malos = @{}

        # Truncado a la mitad: la cabecera sobrevive, el cuerpo no.
        $script:Malos['truncado'] = Join-Path $script:Zona 'truncado.cachidx'
        $mitad = [byte[]]::new([int]($bytes.Length / 2))
        [Array]::Copy($bytes, $mitad, $mitad.Length)
        [IO.File]::WriteAllBytes($script:Malos['truncado'], $mitad)

        # Un byte cambiado dentro del cuerpo: la longitud sigue cuadrando,
        # asi que solo lo caza la suma de comprobacion.
        $script:Malos['alterado'] = Join-Path $script:Zona 'alterado.cachidx'
        $tocado = [byte[]]$bytes.Clone()
        $donde = $tocado.Length - 10
        $tocado[$donde] = [byte](($tocado[$donde] + 1) % 256)
        [IO.File]::WriteAllBytes($script:Malos['alterado'], $tocado)

        # Version del formato del futuro: los cuatro bytes que van detras
        # de la firma.
        $script:Malos['futuro'] = Join-Path $script:Zona 'futuro.cachidx'
        $futuro = [byte[]]$bytes.Clone()
        $futuro[8] = 99
        [IO.File]::WriteAllBytes($script:Malos['futuro'], $futuro)

        $script:Malos['cero'] = Join-Path $script:Zona 'cero.cachidx'
        [IO.File]::WriteAllBytes($script:Malos['cero'], [byte[]]::new(0))

        $script:Malos['basura'] = Join-Path $script:Zona 'basura.cachidx'
        [IO.File]::WriteAllBytes($script:Malos['basura'],
            [Text.Encoding]::UTF8.GetBytes('esto no es un indice, es un texto cualquiera'))

        # Basura que SI empieza por la firma correcta: descarta que lo
        # unico que se mire sean los ocho primeros bytes.
        $script:Malos['firmado'] = Join-Path $script:Zona 'firmado.cachidx'
        $firmado = [byte[]]::new(200)
        [Array]::Copy($bytes, $firmado, 12)
        [IO.File]::WriteAllBytes($script:Malos['firmado'], $firmado)

        # El numero de entradas de la CABECERA cambiado. Este caso no lo
        # cubre la suma de comprobacion -que solo cubre el cuerpo-, asi que
        # lo unico que lo caza es que Read-IndiceDisco compare lo que la
        # cabecera anuncia con lo que ha leido de verdad.
        #
        # El sitio se calcula, no se cuenta a ojo: ocho de firma, cuatro de
        # version, la serie y el diario con su longitud en int32 delante, y
        # ocho del USN de corte. La serie de este archivo es 'CCDD-5678' y
        # el diario esta vacio.
        $script:Malos['entradas'] = Join-Path $script:Zona 'entradas.cachidx'
        $mentiroso = [byte[]]$bytes.Clone()
        $donde = 8 + 4 + (4 + ([Text.Encoding]::UTF8.GetBytes('CCDD-5678')).Length) + (4 + 0) + 8
        [Array]::Copy([BitConverter]::GetBytes([int]4242), 0, $mentiroso, $donde, 4)
        [IO.File]::WriteAllBytes($script:Malos['entradas'], $mentiroso)

        # Un archivo por lo demas PERFECTO al que solo se le ha cambiado el
        # primer byte de la firma. Sin este caso, quitar la comprobacion de
        # la firma no haria fallar ninguna prueba: los demas archivos que
        # no son de aqui se caen igualmente por la version o por la
        # longitud. Lo mostro la verificacion por mutacion.
        $script:Malos['firma'] = Join-Path $script:Zona 'firma.cachidx'
        $otraFirma = [byte[]]$bytes.Clone()
        $otraFirma[0] = [byte](($otraFirma[0] + 1) % 256)
        [IO.File]::WriteAllBytes($script:Malos['firma'], $otraFirma)

        $script:Malos['inexistente'] = Join-Path $script:Zona 'no-esta-aqui.cachidx'
        $script:Malos['carpeta'] = $script:Zona
    }

    It 'el archivo sano si se lee: si no, estas pruebas no comprobarian nada' {
        (Read-IndiceDisco -Ruta $script:Sano) | Should -Not -BeNullOrEmpty
        (Get-CabeceraIndice -Ruta $script:Sano).SerieVolumen | Should -Be 'CCDD-5678'
    }

    It 'Read-IndiceDisco no lanza y devuelve $null con un archivo <Caso>' -ForEach @(
        @{ Caso = 'truncado' }
        @{ Caso = 'alterado' }
        @{ Caso = 'futuro' }
        @{ Caso = 'cero' }
        @{ Caso = 'basura' }
        @{ Caso = 'firmado' }
        @{ Caso = 'firma' }
        @{ Caso = 'entradas' }
        @{ Caso = 'inexistente' }
        @{ Caso = 'carpeta' }
    ) {
        $ruta = $script:Malos[$Caso]
        $ruta | Should -Not -BeNullOrEmpty -Because 'sin ruta el caso no se estaria probando'
        { Read-IndiceDisco -Ruta $ruta } | Should -Not -Throw
        (Read-IndiceDisco -Ruta $ruta) | Should -BeNullOrEmpty
    }

    It 'Get-CabeceraIndice no lanza y devuelve $null con un archivo <Caso>' -ForEach @(
        @{ Caso = 'truncado' }
        @{ Caso = 'futuro' }
        @{ Caso = 'cero' }
        @{ Caso = 'basura' }
        @{ Caso = 'firmado' }
        @{ Caso = 'firma' }
        @{ Caso = 'inexistente' }
        @{ Caso = 'carpeta' }
    ) {
        # 'alterado' NO esta en esta lista, y es a proposito: la cabecera
        # de ese archivo esta intacta y su longitud cuadra, asi que
        # Get-CabeceraIndice la devuelve. Detectar un byte cambiado en el
        # cuerpo obligaria a leer el cuerpo, que es justo lo que esta
        # funcion existe para no hacer. Lo caza Read-IndiceDisco, que es
        # el unico que llega a afirmar algo sobre el contenido.
        $ruta = $script:Malos[$Caso]
        $ruta | Should -Not -BeNullOrEmpty -Because 'sin ruta el caso no se estaria probando'
        { Get-CabeceraIndice -Ruta $ruta } | Should -Not -Throw
        (Get-CabeceraIndice -Ruta $ruta) | Should -BeNullOrEmpty
    }

    It 'con las entradas cambiadas la cabecera si se lee: es el cuerpo el que no cuadra' {
        # Guarda de la prueba de arriba: si este archivo estuviera roto por
        # cualquier otro motivo, el caso 'entradas' pasaria mirando otra
        # cosa y no comprobaria lo que dice comprobar.
        $cab = Get-CabeceraIndice -Ruta $script:Malos['entradas']
        $cab | Should -Not -BeNullOrEmpty
        $cab.Entradas | Should -Be 4242
    }

    It 'un cuerpo alterado deja la cabecera legible, pero el indice no se lee' {
        (Get-CabeceraIndice -Ruta $script:Malos['alterado']) | Should -Not -BeNullOrEmpty
        (Read-IndiceDisco -Ruta $script:Malos['alterado']) | Should -BeNullOrEmpty
    }

    It 'una ruta vacia o nula no lanza' {
        { Read-IndiceDisco -Ruta '' } | Should -Not -Throw
        { Get-CabeceraIndice -Ruta '' } | Should -Not -Throw
        { Read-IndiceDisco -Ruta $null } | Should -Not -Throw
        { Get-CabeceraIndice -Ruta $null } | Should -Not -Throw
        (Read-IndiceDisco -Ruta $null) | Should -BeNullOrEmpty
        (Get-CabeceraIndice -Ruta $null) | Should -BeNullOrEmpty
    }

    It 'guardar en una carpeta que no existe devuelve $false y no lanza' {
        $destino = Join-Path (Join-Path $script:Zona 'no-existe') 'x.cachidx'
        $indice = New-IndiceSintetico -Archivos 3 -Carpetas 2
        { Save-IndiceDisco -Indice $indice -Ruta $destino } | Should -Not -Throw
        (Save-IndiceDisco -Indice $indice -Ruta $destino) | Should -BeFalse
    }

    It 'guardar un indice nulo, o sin ruta, devuelve $false y no lanza' {
        { Save-IndiceDisco -Indice $null -Ruta (Join-Path $script:Zona 'nada.cachidx') } |
            Should -Not -Throw
        (Save-IndiceDisco -Indice $null -Ruta (Join-Path $script:Zona 'nada.cachidx')) |
            Should -BeFalse
        (Save-IndiceDisco -Indice (New-IndiceSintetico -Archivos 1 -Carpetas 1) -Ruta '') |
            Should -BeFalse
    }

    It 'una cadena de la cabecera que declara mas de lo que hay se para en seco' {
        # Read-CadenaIndice lanza a proposito, y quien llama lo convierte
        # en $null. Sin esa comprobacion, un archivo con basura podria
        # pedir que se reserve sitio para dos mil millones de caracteres.
        $memoria = [IO.MemoryStream]::new([byte[]] @(0xFF, 0xFF, 0xFF, 0x7F, 1, 2, 3), $false)
        $lector = [IO.BinaryReader]::new($memoria, [Text.UTF8Encoding]::new($false))
        try {
            { Read-CadenaIndice -Lector $lector } | Should -Throw
        } finally {
            $lector.Dispose()
        }
    }

    It 'una cadena escrita por Write-CadenaIndice se lee tal cual, acentos incluidos' {
        # El acento se arma con su codigo y no se escribe aqui: este
        # archivo de pruebas es ASCII puro, como el resto de la suite. Lo
        # que se comprueba es que una ruta con enye sobrevive al UTF-8 del
        # formato, que es lo normal en C:\Users\...
        $conEnye = 'C:\Documentos\A' + [char]0xF1 + 'o ' + [char]0xE9 + 'poca'
        $memoria = [IO.MemoryStream]::new()
        $escritor = [IO.BinaryWriter]::new($memoria, [Text.UTF8Encoding]::new($false))
        Write-CadenaIndice -Escritor $escritor -Texto $conEnye
        Write-CadenaIndice -Escritor $escritor -Texto ''
        $escritor.Flush()
        $lector = [IO.BinaryReader]::new([IO.MemoryStream]::new($memoria.ToArray(), $false),
                                         [Text.UTF8Encoding]::new($false))
        try {
            (Read-CadenaIndice -Lector $lector) | Should -Be $conEnye
            (Read-CadenaIndice -Lector $lector) | Should -Be ''
        } finally {
            $lector.Dispose()
            $escritor.Dispose()
        }
    }
}

Describe 'La escritura tiene que ser atomica' {

    BeforeAll {
        # Se quitan los comentarios ANTES de buscar, y los bloques <# #>
        # ANTES que las lineas que empiezan por #. Al reves, el primer paso
        # se lleva la linea del #>, el bloque se queda sin cierre y
        # sobrevive documentacion entera. Las pruebas que buscan texto han
        # encontrado los propios comentarios siete veces en este proyecto.
        $texto = [IO.File]::ReadAllText($script:RutaPersistente)
        $sinBloques = [regex]::Replace($texto, '(?s)<#.*?#>', '')
        $script:Codigo = (($sinBloques -split "`n" |
                           Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
    }

    It 'queda codigo despues de quitar los comentarios: si no, esto no comprueba nada' {
        $script:Codigo | Should -Match 'function Save-IndiceDisco'
        $script:Codigo | Should -Match 'function Read-IndiceDisco'
    }

    It 'se escribe a un temporal y se reemplaza con una sola operacion' {
        # Igual que Add-EntradaHistorial, y por el mismo motivo: si el
        # equipo se apaga a mitad de escritura, el archivo queda truncado.
        # Un indice truncado que se leyera como bueno es exactamente la
        # forma de mentir que este archivo existe para evitar.
        $script:Codigo | Should -Match ([regex]::Escape('$temporal = "$Ruta.$PID.tmp"'))
        $script:Codigo | Should -Match ([regex]::Escape('[IO.File]::Open($temporal'))
        $script:Codigo | Should -Match 'Move-Item[^\n]*-Destination \$Ruta -Force'
    }

    It 'el archivo de destino no se abre nunca para escribir directamente' {
        $abrirDestino = [regex]::Escape('[IO.File]::Open($Ruta, [IO.FileMode]::Create')
        $script:Codigo | Should -Not -Match $abrirDestino
        $script:Codigo | Should -Not -Match ([regex]::Escape('Set-Content -LiteralPath $Ruta'))
    }

    It 'aqui no se borra nada: dentro del nucleo eso es cosa de Remove.ps1' {
        $script:Codigo | Should -Not -Match 'Remove-Item'
    }

    It 'de aqui no sale nada que se parezca a un candidato' {
        # La decision de disenyo que manda sobre todas: el indice guardado
        # sirve para PINTAR EL MAPA, nunca para DECIDIR QUE SE BORRA.
        $script:Codigo | Should -Not -Match 'Candidat'
        $script:Codigo | Should -Not -Match 'New-Candidato'
    }
}

Describe 'Cuanto tarda de verdad' {

    BeforeAll {
        $script:Grande = New-IndiceSintetico -Archivos 10000 -Carpetas 500
        $script:RutaGrande = Join-Path $script:Zona 'diez-mil.cachidx'
        $script:TGuardar = (Measure-Command {
            $script:OkGrande = Save-IndiceDisco -Indice $script:Grande -Ruta $script:RutaGrande
        }).TotalSeconds
        $script:TCargar = (Measure-Command {
            $script:LeidoGrande = Read-IndiceDisco -Ruta $script:RutaGrande
        }).TotalSeconds
        $script:TCabecera = (Measure-Command {
            $script:CabGrande = Get-CabeceraIndice -Ruta $script:RutaGrande
        }).TotalSeconds
    }

    It 'guardar y cargar 10.000 entradas da exactamente lo mismo' {
        $script:OkGrande | Should -BeTrue
        $script:LeidoGrande | Should -Not -BeNullOrEmpty
        @($script:LeidoGrande.Archivos).Count | Should -Be 10000
        @($script:LeidoGrande.Carpetas.Keys).Count | Should -Be 500
        $script:LeidoGrande.Archivos[9999].Bytes | Should -Be $script:Grande.Archivos[9999].Bytes
        $script:LeidoGrande.Archivos[9999].Ruta  | Should -Be $script:Grande.Archivos[9999].Ruta
    }

    It 'y deja constancia de lo que tarda' {
        $tamano = (Get-Item -LiteralPath $script:RutaGrande).Length
        # Los parentesis alrededor de la suma NO son decorativos: -f se
        # enlaza mas fuerte que +, asi que sin ellos solo se formatea el
        # ultimo trozo y el primero sale con los {0} literales en pantalla.
        # Paso aqui mismo la primera vez que se ejecuto esto.
        $linea = ('    [VEL-02] 10.000 entradas + 500 carpetas: guardar {0:N2} s, ' +
                  'cargar {1:N2} s, solo cabecera {2:N4} s, {3:N0} bytes en disco') -f
                 $script:TGuardar, $script:TCargar, $script:TCabecera, $tamano
        Write-Host $linea

        # Sin tope estricto -esto corre en una maquina compartida y el
        # banco ya midio los numeros de verdad-, pero si un suelo grosero:
        # si alguna vez se cuela una llamada a funcion por entrada dentro
        # de los bucles, esto se va a decenas de segundos. Son 10 us por
        # llamada; a un millon de entradas, diez segundos.
        $script:TGuardar | Should -BeLessThan 30
        $script:TCargar  | Should -BeLessThan 30
    }

    It 'leer solo la cabecera es MUCHO mas barato que cargar el indice' {
        # Es la razon de que Get-CabeceraIndice exista: poder decidir si el
        # indice sirve ANTES de pagar la carga.
        $script:CabGrande | Should -Not -BeNullOrEmpty
        $script:TCabecera | Should -BeLessThan $script:TCargar
    }
}

Describe 'Lo que se lee del indice se ordena con una EXPRESION, nunca por nombre de propiedad' {

    # LA INVARIANTE QUE NACE DE UN FALLO DE PLATAFORMA.
    #
    # Read-IndiceDisco devuelve diccionarios y no pscustomobject, y eso es
    # deliberado: leer un millon de entradas a objetos de PowerShell cuesta
    # doce veces mas (docs/VEL-02-MEDICION.md). El precio de esa decision
    # es este:
    #
    #     $indice.Archivos | Sort-Object Bytes -Descending
    #
    # En PowerShell 7 eso ordena. En Windows PowerShell 5.1 NO ORDENA, y
    # no protesta: devuelve la lista en el orden en que estaba. Un "los
    # archivos mas grandes primero" que en realidad ensenya los primeros
    # que se leyeron, sin un solo error por ningun lado.
    #
    # Get-VistaArchivos ya lo hacia bien -ordena con { [double]$_.Bytes }-,
    # pero lo hacia bien sin que nadie lo hubiera exigido. Esta prueba lo
    # convierte en una regla, porque el sintoma de romperla es una lista
    # ordenada al azar y ni una linea en el registro.

    BeforeAll {
        $script:RaizInv = Split-Path $PSScriptRoot -Parent
        $script:Consumidores = @('VistaArchivos.ps1', 'IndiceIncremental.ps1', 'Indice.ps1', 'Mapa.ps1')
    }

    It 'los archivos que consumen el indice se han leido de verdad' {
        foreach ($nombre in $script:Consumidores) {
            $ruta = Join-Path (Join-Path (Join-Path $script:RaizInv 'src') 'Core') $nombre
            Test-Path -LiteralPath $ruta | Should -BeTrue -Because "$nombre tiene que existir"
        }
    }

    It 'ninguno ordena con un nombre de propiedad pelado' {
        $culpables = @()
        foreach ($nombre in $script:Consumidores) {
            $ruta = Join-Path (Join-Path (Join-Path $script:RaizInv 'src') 'Core') $nombre
            $n = 0
            foreach ($linea in (Get-Content -LiteralPath $ruta)) {
                $n++
                if ($linea -match '^\s*#') { continue }
                if ($linea -notmatch 'Sort-Object') { continue }
                # Vale la forma con expresion -llave { } o tabla hash con
                # Expression-; no vale "Sort-Object Bytes" ni
                # "Sort-Object -Property Bytes".
                if ($linea -match 'Sort-Object[^\{@]*$' -or
                    $linea -match 'Sort-Object\s+(-Property\s+)?[A-Za-z]') {
                    if ($linea -notmatch '\{' -and $linea -notmatch 'Expression') {
                        $culpables += ('{0}:{1}  {2}' -f $nombre, $n, $linea.Trim())
                    }
                }
            }
        }
        $culpables -join ' // ' | Should -BeNullOrEmpty -Because (
            'sobre diccionarios, en PowerShell 5.1 eso NO ordena y no avisa')
    }
}
