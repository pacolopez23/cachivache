<#
    [VEL-02]: LAS DOS MITADES, JUNTAS.

    IndicePersistente.ps1 guarda y lee. IndiceIncremental.ps1 decide si lo
    leido se puede creer y le aplica los cambios. Las dos estan probadas
    por separado -55 y 82 pruebas- y las dos pasaban en verde el dia que
    NO ENCAJABAN.

    Se escribieron en paralelo. Coincidieron en la cabecera, que estaba
    acordada, y discreparon en dos cosas que nadie habia acordado:

      1. Read-IndiceDisco devolvia Archivos como ARRAY -para parecerse a
         New-IndiceDisco- y Update-IndiceConCambios necesita buscar rutas
         sueltas, o sea un diccionario. Se resolvio con -ComoDiccionario.
      2. Y ya con las dos usando diccionario, seguian discrepando en QUE
         guarda dentro: uno "ruta -> entrada" y otro "ruta -> bytes". El
         sintoma era que se descartaban TODAS las bajas.

    Ninguna de las dos cosas la podia ver una prueba de una sola mitad, y
    por eso este archivo existe: recorre el camino ENTERO, que es el unico
    sitio donde una costura se ve.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('costura-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Taller -Force)

    # Tres archivos de 2 MB: por encima del umbral del indice, y con un
    # total redondo para que las cuentas se lean de un vistazo.
    foreach ($n in 1..3) {
        [IO.File]::WriteAllBytes((Join-Path $script:Taller "a$n.bin"), [byte[]]::new(2MB))
    }
    $script:Origen = New-IndiceDisco -Rutas @($script:Taller) -MinimoArchivoBytes 1MB
    $script:Fichero = Join-Path $script:Taller 'indice.bin'
}

AfterAll {
    if ($script:Taller -and (Test-Path -LiteralPath $script:Taller)) {
        Remove-Item -LiteralPath $script:Taller -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'VEL-02: el camino entero, de guardar a aplicar cambios' {

    It 'el indice de partida tiene lo que se espera' {
        # Guarda: si el recorrido no encontrara nada, todo lo de abajo
        # comprobaria el vacio y pasaria.
        $script:Origen.Bytes | Should -Be (6MB)
        @($script:Origen.Archivos).Count | Should -Be 3
    }

    It 'se guarda y la cabecera se puede leer sin cargar el cuerpo' {
        Save-IndiceDisco -Indice $script:Origen -Ruta $script:Fichero `
                         -SerieVolumen 'AAAA-BBBB' -IdDiario '123' -UsnCorte 500 | Should -BeTrue

        $cab = Get-CabeceraIndice -Ruta $script:Fichero
        $cab               | Should -Not -BeNullOrEmpty
        $cab.Entradas      | Should -Be 3
        $cab.SerieVolumen  | Should -Be 'AAAA-BBBB'
    }

    It 'y esa cabecera la acepta quien decide si el indice se puede creer' {
        # Este es el apreton de manos entre las dos mitades: los siete
        # campos con los mismos nombres. Si una de las dos los cambiara,
        # aqui se ve; en sus pruebas por separado, no.
        $cab = Get-CabeceraIndice -Ruta $script:Fichero
        $v = Test-IndiceUtilizable -Cabecera $cab -VersionEsperada $cab.Version `
                                   -SerieVolumen 'AAAA-BBBB' -IdDiario '123' `
                                   -PrimerUsn 1 -Ahora (Get-Date)
        $v.Utilizable | Should -BeTrue -Because $v.Motivo
    }

    It 'un indice de OTRO disco se rechaza, aunque el archivo este perfecto' {
        # El caso que de verdad da miedo: una llave USB que hereda la letra
        # de otra. El archivo esta intacto y la suma cuadra; lo unico que
        # no cuadra es el disco.
        $cab = Get-CabeceraIndice -Ruta $script:Fichero
        $v = Test-IndiceUtilizable -Cabecera $cab -VersionEsperada $cab.Version `
                                   -SerieVolumen 'CCCC-DDDD' -IdDiario '123' `
                                   -PrimerUsn 1 -Ahora (Get-Date)
        $v.Utilizable | Should -BeFalse
        $v.Codigo     | Should -Be 'VolumenDistinto'
    }

    It 'lo leido vale exactamente lo mismo que lo guardado' {
        $leido = Read-IndiceDisco -Ruta $script:Fichero
        $leido.Bytes         | Should -Be $script:Origen.Bytes
        $leido.TotalArchivos | Should -Be $script:Origen.TotalArchivos
        @($leido.Archivos).Count | Should -Be 3
    }

    It 'y una BAJA baja el total: la mentira que este punto viene a impedir' {
        # LA PRUEBA QUE SOSTIENE EL PUNTO ENTERO. Si la propagacion se
        # olvidara de restar, el mapa ensenyaria para siempre un espacio
        # que ya no existe, el usuario iria a buscarlo, no lo encontraria,
        # y a partir de ahi no se fiaria de nada de lo que ve.
        #
        # -ComoDiccionario NO sobra: sin el, Archivos llega como array,
        # Update-IndiceConCambios no puede buscar una ruta suelta y
        # descarta TODAS las bajas -avisando, eso si-. Es la costura que
        # este archivo existe para vigilar.
        $leido = Read-IndiceDisco -Ruta $script:Fichero -ComoDiccionario
        $r = Update-IndiceConCambios -Indice $leido -Cambios @(
                 @{ Tipo = 'Baja'; Ruta = (Join-Path $script:Taller 'a1.bin') })

        $r.Confiable   | Should -BeTrue -Because $r.Motivo
        $r.Bajas       | Should -Be 1
        $r.Descartados | Should -Be 0
        $r.Indice.Bytes | Should -Be (4MB) -Because 'eran tres archivos de 2 MB y queda uno menos'
    }

    It 'un "no me fio" NUNCA viene sin motivo' {
        # Devolvia Motivo = '' incluso con Confiable a $false, asi que
        # quien llamara no podia saber si se habian caido tres cambios,
        # si el indice ya venia descuadrado, o si el programa se habia
        # roto. Un rechazo mudo es indistinguible de un fallo.
        $leido = Read-IndiceDisco -Ruta $script:Fichero -ComoDiccionario
        $r = Update-IndiceConCambios -Indice $leido -Cambios @(
                 @{ Tipo = 'inventado'; Ruta = 'C:\lo que sea' })

        $r.Confiable | Should -BeFalse
        $r.Motivo    | Should -Not -BeNullOrEmpty
        $r.Motivo    | Should -Match 'recorrer el disco entero'
    }

    It 'y con la forma de array avisa en vez de aplicar cambios a medias' {
        # Que las dos formas no encajen es un error de quien llama, no del
        # usuario. Lo importante es que se note: aplicar la mitad de los
        # cambios dejaria el indice peor que antes.
        $leido = Read-IndiceDisco -Ruta $script:Fichero
        $r = Update-IndiceConCambios -Indice $leido -Cambios @(
                 @{ Tipo = 'Baja'; Ruta = (Join-Path $script:Taller 'a1.bin') })
        $r.Confiable | Should -BeFalse
        $r.Motivo    | Should -Not -BeNullOrEmpty
    }
}
