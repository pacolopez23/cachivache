<#
    Pruebas de [COR-03]: archivos que viven en la nube.

    OneDrive "Archivos a peticion" deja un marcador en el disco: la
    entrada de directorio esta, el contenido no. Se descarga sola en
    cuanto alguien ABRE el archivo, y ese alguien puede ser este programa.

    La deteccion es aritmetica sobre los atributos, asi que se prueba
    aqui, sin OneDrive, sin conexion y sin arriesgar ni un megabyte del
    usuario.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Los valores que define Windows. Se repiten aqui a proposito: si
    # alguien cambia las constantes del nucleo por error, esta prueba lo
    # caza en vez de cambiar con ellas.
    $script:OFFLINE                = 0x1000
    $script:RECALL_ON_OPEN         = 0x40000
    $script:RECALL_ON_DATA_ACCESS  = 0x400000
    $script:ARCHIVE                = 0x20
    $script:READONLY               = 0x1
}

Describe 'Test-EsMarcadorNube' {

    It 'un archivo normal no lo es' {
        Test-EsMarcadorNube -Atributos $script:ARCHIVE | Should -BeFalse
    }

    It 'detecta el marcador de OneDrive (RecallOnDataAccess)' {
        # Es el que usa OneDrive para "solo en linea". Si solo se mirara
        # Offline, que es lo primero que uno busca, se dejaria fuera
        # justo al proveedor mas comun.
        Test-EsMarcadorNube -Atributos ($script:ARCHIVE -bor $script:RECALL_ON_DATA_ACCESS) | Should -BeTrue
    }

    It 'detecta tambien Offline y RecallOnOpen' {
        # Otras soluciones de almacenamiento jerarquico usan estos.
        Test-EsMarcadorNube -Atributos ($script:ARCHIVE -bor $script:OFFLINE)        | Should -BeTrue
        Test-EsMarcadorNube -Atributos ($script:ARCHIVE -bor $script:RECALL_ON_OPEN) | Should -BeTrue
    }

    It 'no confunde otros atributos con la nube' {
        # Un falso positivo aqui significa saltarse archivos normales, o
        # sea dejar de encontrar basura de verdad.
        Test-EsMarcadorNube -Atributos ($script:ARCHIVE -bor $script:READONLY) | Should -BeFalse
        Test-EsMarcadorNube -Atributos 0                                       | Should -BeFalse
    }
}

Describe 'Test-ArchivoEnNube' {

    BeforeAll {
        $script:Zona = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-nube-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Zona -Force | Out-Null
        $script:Normal = Join-Path $script:Zona 'normal.bin'
        [IO.File]::WriteAllBytes($script:Normal, (New-Object byte[] 2048))
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Zona -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'un archivo de verdad, que existe, no esta en la nube' {
        Test-ArchivoEnNube -Archivo (Get-Item -LiteralPath $script:Normal) | Should -BeFalse
        Test-ArchivoEnNube -Archivo $script:Normal                          | Should -BeFalse
    }

    It 'un nulo no revienta y responde que no' {
        { Test-ArchivoEnNube -Archivo $null } | Should -Not -Throw
        Test-ArchivoEnNube -Archivo $null     | Should -BeFalse
    }

    It 'una ruta que no existe responde que no, sin lanzar' {
        # Ante la duda se responde NO. Decir que si haria que el programa
        # se saltara archivos normales por un fallo de lectura, y saltarse
        # cosas en silencio es peor que arriesgar una descarga que
        # probablemente no ocurra.
        Test-ArchivoEnNube -Archivo (Join-Path $script:Zona 'no-existe.bin') | Should -BeFalse
    }

    It 'preguntarlo NO abre el archivo' {
        # Seria absurdo que la comprobacion causara justo la descarga que
        # trata de evitar. Se comprueba abriendo el archivo en exclusiva:
        # si Test-ArchivoEnNube intentara abrirlo, fallaria.
        $flujo = [IO.File]::Open($script:Normal, [IO.FileMode]::Open,
                                 [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            { Test-ArchivoEnNube -Archivo $script:Normal } | Should -Not -Throw
            Test-ArchivoEnNube -Archivo $script:Normal | Should -BeFalse
        } finally {
            $flujo.Dispose()
        }
    }
}

Describe 'COR-03: nada lee un archivo que este solo en la nube' {

    BeforeAll {
        $script:Fs   = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/Core/FileSystem.ps1')
        $script:Dup  = (Get-Content -LiteralPath (Join-Path $script:Raiz 'src/Modules/55-Duplicados.ps1') |
                        Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $script:Gran = (Get-Content -LiteralPath (Join-Path $script:Raiz 'src/Modules/60-ArchivosGrandes.ps1') |
                        Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'la huella rapida se protege sola, antes de abrir nada' {
        # Es la unica funcion del nucleo que abre archivos del usuario. La
        # comprobacion vive AHI para que el siguiente que quiera una huella
        # no tenga que acordarse.
        $i = $script:Fs.IndexOf('function Get-HuellaRapida')
        $abre = $script:Fs.IndexOf('[IO.File]::Open($Ruta', $i)
        $chequeo = $script:Fs.IndexOf('Test-ArchivoEnNube', $i)

        $chequeo | Should -BeGreaterThan -1
        $chequeo | Should -BeLessThan $abre -Because 'comprobar despues de abrir no evita la descarga'
    }

    It 'duplicados descarta los de la nube antes de compararlos' {
        $script:Dup | Should -Match 'Test-ArchivoEnNube'
    }

    It 'y cuenta cuantos ha dejado fuera, para poder decirlo' {
        # Saltarse archivos en silencio es la otra forma de mentir sobre lo
        # que se ha mirado: leerias "ningun duplicado" cuando lo cierto es
        # que no se ha comparado casi nada.
        $script:Dup | Should -Match '\$contador\.Nube\+\+'
        $script:Dup | Should -Match 'están solo en la nube'
    }

    It 'el aviso sale ANTES de rendirse por no encontrar duplicados' {
        $aviso = $script:Dup.IndexOf('están solo en la nube')
        $salida = $script:Dup.IndexOf('if ($gruposCandidatos.Count -eq 0) { return }')
        $aviso  | Should -BeGreaterThan -1
        $salida | Should -BeGreaterThan $aviso
    }

    It 'archivos grandes no promete espacio que no existe en el disco' {
        # Un marcador ocupa kilobytes: listarlo como "4 GB que puedes
        # liberar" es la contabilidad falsa de [VIS-03] otra vez.
        $script:Gran | Should -Match 'Test-ArchivoEnNube'
    }

    It 'el contador vive en una tabla, no en una variable suelta' {
        # Hoy "$n++" tambien funcionaria: Where-Object ejecuta su bloque en
        # el ambito de quien llama. Pero el dia que este bloque se mueva a
        # una funcion auxiliar -que si crea ambito- el contador se quedaria
        # en cero, el aviso no saldria nunca y no habria ni un error que lo
        # delatara. La tabla funciona en los dos casos.
        $script:Dup | Should -Match '\$contador = @\{ Nube = 0 \}'
    }

    It 'y de hecho el contador cuenta: no basta con que exista' {
        # Se reproduce el patron exacto del modulo. Una prueba que solo
        # mirara el texto del codigo daria por bueno un contador que nunca
        # se incrementa.
        $contador = @{ Nube = 0 }
        $pasan = @(1..10) | Where-Object {
            if ($_ % 3 -eq 0) { $contador.Nube++; return $false }
            $true
        }
        $contador.Nube | Should -Be 3
        @($pasan).Count | Should -Be 7
    }
}
