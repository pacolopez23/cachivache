<#
    [VEL-04], EL CAMINO ENTERO, CON ARCHIVOS DE VERDAD.

    CambiosLimpieza.ps1 convierte el resultado de una limpieza en bajas.
    IndiceIncremental.ps1 las aplica al indice. Las dos estan probadas por
    separado, y eso -regla 4 del relevo- no basta: dos mitades pueden estar
    las dos en verde y no encajar, porque coinciden en lo acordado y
    discrepan en lo que nadie acordo. Ya paso con [VEL-02], donde las dos
    partes se pasaban tablas de forma distinta con 137 pruebas en verde.

    EL ORACULO ES UN ANALISIS COMPLETO DE VERDAD. No se comprueba que el
    indice tenga los numeros que uno espera a mano -eso es volver a
    escribir el algoritmo en la prueba y darle la razon-, sino que el
    indice actualizado por el atajo diga EXACTAMENTE LO MISMO que decir
    New-IndiceDisco otra vez sobre la carpeta ya limpiada. Que es,
    literalmente, la promesa de [VEL-04]: ahorrarse ese recorrido sin
    mentir.

    Y se borra de verdad, con Remove-Item, dentro de una carpeta propia del
    temporal del sistema. Sin archivos reales esto no probaria la parte que
    importa: que las rutas que el indice guarda y las que el motor de
    borrado maneja son la misma cosa escrita igual.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('vel04-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Taller -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $script:Taller 'cache') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $script:Taller 'cache\honda') -Force)
    # LA TRAMPA DEL PREFIJO, PERO EN EL DISCO: "cache-vieja" empieza por
    # "cache". Si la pertenencia se decidiera con un StartsWith sin barra,
    # limpiar "cache" se llevaria del indice un archivo que sigue aqui.
    [void](New-Item -ItemType Directory -Path (Join-Path $script:Taller 'cache-vieja') -Force)

    function script:Escribe([string] $Relativa, [int] $Mb) {
        [IO.File]::WriteAllBytes((Join-Path $script:Taller $Relativa), [byte[]]::new($Mb * 1MB))
    }
    script:Escribe 'cache\c1.bin'        2
    script:Escribe 'cache\c2.bin'        2
    script:Escribe 'cache\honda\c3.bin'  2
    script:Escribe 'cache-vieja\v1.bin'  2
    script:Escribe 'suelto.bin'          2
    script:Escribe 'otro.bin'            2

    # POR EL CAMINO REAL: guardar y volver a leer. New-IndiceDisco devuelve
    # la forma de ARRAY y Update-IndiceConCambios exige la de DICCIONARIO,
    # que es la que sale del archivo. En el programa el indice que se
    # actualiza SIEMPRE viene de disco, y saltarse ese paso aqui probaria
    # una tuberia que no existe.
    $origen = New-IndiceDisco -Rutas @($script:Taller) -MinimoArchivoBytes 1MB
    # EL INDICE SE GUARDA FUERA DE LA CARPETA QUE SE ANALIZA, y la primera
    # version no lo hacia. El fallo que salio de ahi merece quedar escrito
    # porque es una trampa del propio indice, no de esta prueba:
    #
    #   TotalArchivos cuenta TODOS los archivos vistos; Archivos solo
    #   guarda los que superan MinimoArchivoBytes.
    #
    # El indice guardado ocupa 540 bytes, o sea que entraba en el primer
    # contador y no en el segundo. Al comparar contra un analisis completo,
    # el recorrido veia 3 archivos y el atajo 2, y la diferencia era el
    # propio archivo de la prueba. Guardarlo fuera es ademas lo que hace el
    # programa: el indice vive en los datos de la aplicacion, no en el
    # disco que se esta midiendo.
    $script:Fichero = Join-Path ([IO.Path]::GetTempPath()) ('vel04-indice-' + [guid]::NewGuid().ToString('N') + '.bin')
    [void](Save-IndiceDisco -Indice $origen -Ruta $script:Fichero -SerieVolumen 'TEST-0002' -IdDiario '0' -UsnCorte 0)
    $script:Indice = Read-IndiceDisco -Ruta $script:Fichero -ComoDiccionario
}

AfterAll {
    if ($script:Taller -and (Test-Path -LiteralPath $script:Taller)) {
        Remove-Item -LiteralPath $script:Taller -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:Fichero -and (Test-Path -LiteralPath $script:Fichero)) {
        Remove-Item -LiteralPath $script:Fichero -Force -ErrorAction SilentlyContinue
    }
}

Describe 'VEL-04: de la limpieza al indice actualizado' {

    It 'el indice de partida tiene lo que se espera: si no, nada de esto mide nada' {
        [int]$script:Indice.TotalArchivos | Should -Be 6
        [double]$script:Indice.Bytes      | Should -Be 12MB
    }

    It 'LA COSTURA: se limpia de verdad y el indice acaba diciendo lo mismo que un analisis completo' {
        $cache  = Join-Path $script:Taller 'cache'
        $suelto = Join-Path $script:Taller 'suelto.bin'

        # 1. El programa limpia. De verdad: esto borra archivos del disco.
        Remove-Item -LiteralPath (Join-Path $cache 'c1.bin') -Force
        Remove-Item -LiteralPath (Join-Path $cache 'c2.bin') -Force
        Remove-Item -LiteralPath (Join-Path $cache 'honda\c3.bin') -Force
        Remove-Item -LiteralPath $suelto -Force

        # 2. Lo que Remove.ps1 dejaria en los candidatos. Con un tercero
        #    incierto -vaciar la papelera- que en el uso real aparece casi
        #    siempre, y que NO tiene que estropear las bajas de los otros.
        $candidatos = @(
            [pscustomobject]@{ Ruta = $cache;  Metodo = 'Contenido'; Hecho = $true; Error = '' }
            [pscustomobject]@{ Ruta = $suelto; Metodo = 'Ruta';      Hecho = $true; Error = '' }
            [pscustomobject]@{ Ruta = 'Papelera de reciclaje'; Metodo = 'Papelera'; Hecho = $true; Error = '' }
        )

        # 3. El cable de [VEL-04].
        $resultado = Get-CambiosDeLimpieza -Candidatos $candidatos -RutasIndice @($script:Indice.Archivos.Keys)
        $resultado.Ciertos   | Should -Be 2
        $resultado.Inciertos | Should -Be 1
        @($resultado.Cambios).Count | Should -Be 4

        # 4. Se aplican.
        $aplicado = Update-IndiceConCambios -Indice $script:Indice -Cambios $resultado.Cambios
        $aplicado.Bajas     | Should -Be 4
        $aplicado.Confiable | Should -BeTrue

        # 5. EL ORACULO: lo que diria recorrer el disco otra vez.
        $completo = New-IndiceDisco -Rutas @($script:Taller) -MinimoArchivoBytes 1MB

        [int]$aplicado.Indice.TotalArchivos | Should -Be ([int]$completo.TotalArchivos)
        [double]$aplicado.Indice.Bytes      | Should -Be ([double]$completo.Bytes)
        [int]$aplicado.Indice.TotalArchivos | Should -Be 2
        [double]$aplicado.Indice.Bytes      | Should -Be 4MB
    }

    It 'y las rutas concretas tambien coinciden, no solo los totales' {
        # Dos indices pueden sumar lo mismo y hablar de archivos distintos.
        # Aqui esta la trampa del prefijo: cache-vieja\v1.bin sigue en el
        # disco y tiene que seguir en el indice.
        $completo = New-IndiceDisco -Rutas @($script:Taller) -MinimoArchivoBytes 1MB
        $delAtajo     = @($script:Indice.Archivos.Keys | Sort-Object)
        $delRecorrido = @($completo.Archivos | ForEach-Object { $_.Ruta } | Sort-Object)

        ($delAtajo -join ' | ') | Should -Be ($delRecorrido -join ' | ')
        $delAtajo | Should -Contain (Join-Path $script:Taller 'cache-vieja\v1.bin')
    }

    It 'lo que no se pudo borrar del todo se queda en el indice' {
        # Segunda limpieza sobre lo que queda, con el resultado PARCIAL que
        # de verdad devuelve Remove.ps1: Hecho a $true y Error relleno con
        # "quedan archivos en uso". El archivo NO se ha borrado del disco, y
        # el indice tiene que seguir contandolo. Si esta prueba se pusiera
        # verde con el archivo fuera del indice, el programa estaria
        # diciendole al usuario que su disco esta mas limpio de lo que esta.
        $vieja = Join-Path $script:Taller 'cache-vieja'
        $antes = [double]$script:Indice.Bytes

        $r = Get-CambiosDeLimpieza -RutasIndice @($script:Indice.Archivos.Keys) -Candidatos @(
            [pscustomobject]@{
                Ruta = $vieja; Metodo = 'Contenido'; Hecho = $true
                Error = 'Quedan 2 MB: archivos en uso por algún programa abierto.'
            }
        )
        @($r.Cambios).Count | Should -Be 0

        $aplicado = Update-IndiceConCambios -Indice $script:Indice -Cambios $r.Cambios
        [double]$aplicado.Indice.Bytes | Should -Be $antes
        Test-Path -LiteralPath (Join-Path $vieja 'v1.bin') | Should -BeTrue -Because 'el archivo sigue en el disco: por eso sigue en el indice'
    }
}
