<#
    Pruebas de [VIS-05]: compresion NTFS.

    Un archivo comprimido por NTFS mide una cosa al leerlo y ocupa otra en
    el disco. Cachivache no lo miraba, asi que en una carpeta comprimida
    PROMETIA LIBERAR MAS ESPACIO DEL QUE IBA A LIBERAR: la misma familia
    que [VIS-03] con los enlaces duros, en la otra direccion.

    La decision -cuanto se promete- es aritmetica pura, asi que se prueba
    aqui entera, sin NTFS y sin Windows. La medicion real (kernel32) es lo
    unico que depende del sistema, y de ella se comprueba lo que se puede
    comprobar en cualquier parte: que no lanza nunca y que cuando no sabe
    dice $null y no cero.

    Archivo ASCII puro salvo las cadenas de cara al usuario, que llevan sus
    tildes y sus enyes por [I18N-01].
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')


    # Los valores que define Windows, repetidos aqui a proposito: si
    # alguien cambia la constante del nucleo por error, esta prueba lo caza
    # en vez de cambiar con ella.
    $script:COMPRESSED   = 0x800
    $script:ARCHIVE      = 0x20
    $script:READONLY     = 0x1
    $script:HIDDEN       = 0x2
    $script:OFFLINE      = 0x1000
    $script:RECALL_DATA  = 0x400000

    # El criterio de aceptacion de la hoja de ruta, en bytes.
    $script:CIEN_MB      = 100MB
    $script:TREINTA_MB   = 30MB

    $script:EsWindows = ($IsWindows -or ($null -eq $IsWindows))
}

Describe 'Test-EstaComprimido' {

    It 'un archivo normal no lo esta' {
        Test-EstaComprimido -Atributos $script:ARCHIVE | Should -BeFalse
    }

    It 'reconoce la marca de NTFS' {
        Test-EstaComprimido -Atributos $script:COMPRESSED | Should -BeTrue
    }

    It 'con varios atributos a la vez sigue viendo el bit' {
        # Este es el caso REAL: un archivo comprimido llega con Archive
        # puesto, y dentro de una carpeta del sistema con tres o cuatro
        # mas. Preguntar por igualdad en vez de por el bit solo acertaria
        # con el archivo que no tiene ningun otro atributo, o sea con
        # ninguno.
        $todos = $script:ARCHIVE -bor $script:READONLY -bor $script:HIDDEN -bor $script:COMPRESSED
        Test-EstaComprimido -Atributos $todos | Should -BeTrue
    }

    It 'no confunde la compresion con los atributos de la nube' {
        # Un falso positivo aqui prometeria de menos sobre archivos que no
        # estan comprimidos, y ademas taparia el aviso de [COR-03], que
        # habla de otra cosa.
        $nube = $script:ARCHIVE -bor $script:OFFLINE -bor $script:RECALL_DATA -bor $script:READONLY
        Test-EstaComprimido -Atributos $nube | Should -BeFalse
    }

    It 'cero no esta comprimido' {
        Test-EstaComprimido -Atributos 0 | Should -BeFalse
    }

    It 'un valor negativo no revienta y contesta por el bit' {
        # Attributes es un entero con signo: una mascara con el bit alto
        # puesto llega negativa. Que "-1" sea "todos los bits" no es una
        # curiosidad, es lo que decide la respuesta.
        { Test-EstaComprimido -Atributos -1 }    | Should -Not -Throw
        Test-EstaComprimido -Atributos -1        | Should -BeTrue
        # -2049 es justo el complemento de 0x800: todos los bits menos ese.
        Test-EstaComprimido -Atributos -2049     | Should -BeFalse
    }

    It 'un nulo no revienta y responde que no' {
        # Un atributo que no se pudo leer llega asi. Responder que no es
        # la respuesta segura: contar de mas un archivo que quiza estaba
        # comprimido solo produce una promesa mas pequenya.
        { Test-EstaComprimido -Atributos $null } | Should -Not -Throw
        Test-EstaComprimido -Atributos $null     | Should -BeFalse
    }
}

Describe 'Get-TamanoEnDisco' {

    BeforeAll {
        $script:Zona = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-compresion-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Zona -Force | Out-Null
        $script:Archivo = Join-Path $script:Zona 'datos.bin'
        [IO.File]::WriteAllBytes($script:Archivo, (New-Object byte[] 8192))
        $script:NoExiste = Join-Path $script:Zona 'no-existe.bin'
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Zona -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'no lanza con nada de lo que le puede llegar' {
        # Se la llama una vez por archivo dentro de un recorrido de cientos
        # de miles: una excepcion aqui no es un archivo mal medido, es un
        # analisis entero que se cae.
        { Get-TamanoEnDisco -Ruta $null }               | Should -Not -Throw
        { Get-TamanoEnDisco -Ruta '' }                  | Should -Not -Throw
        { Get-TamanoEnDisco -Ruta '   ' }               | Should -Not -Throw
        { Get-TamanoEnDisco -Ruta $script:NoExiste }    | Should -Not -Throw
        { Get-TamanoEnDisco -Ruta $script:Archivo }     | Should -Not -Throw
        { Get-TamanoEnDisco -Ruta 'docker system prune' } | Should -Not -Throw
    }

    It 'una ruta vacia o nula es "no lo se", que se dice $null' {
        ($null -eq (Get-TamanoEnDisco -Ruta $null)) | Should -BeTrue
        ($null -eq (Get-TamanoEnDisco -Ruta ''))    | Should -BeTrue
    }

    It 'lo que no se sabe se dice $null, nunca cero' {
        # LA DISTINCION ES EL PUNTO ENTERO. Cero significa "borrarlo no
        # libera nada"; con cero, un equipo donde la medicion falle
        # prometeria cero para todo y el programa diria que no hay nada
        # que ganar. $null deja que Get-EspacioRecuperable vuelva al
        # tamanyo logico, que es el comportamiento de siempre.
        $r = Get-TamanoEnDisco -Ruta $script:NoExiste
        ($null -eq $r) | Should -BeTrue -Because 'un archivo que no esta no ocupa "cero", es que no se sabe'
        ($r -eq 0)     | Should -BeFalse
    }

    It 'mide de verdad donde hay API, y contesta $null donde no la hay' {
        # La suite corre en Linux y tambien en Windows (integracion
        # continua), asi que la prueba se ramifica en vez de quedarse
        # hueca en una de las dos.
        $r = Get-TamanoEnDisco -Ruta $script:Archivo
        if ($script:EsWindows) {
            ($null -eq $r) | Should -BeFalse -Because 'en Windows GetCompressedFileSize contesta'
            $r | Should -BeGreaterOrEqual 0
        } else {
            ($null -eq $r) | Should -BeTrue -Because 'fuera de Windows no hay NTFS que preguntar'
        }
    }

    It 'preguntarlo NO abre el archivo' {
        # Seria absurdo que medir disparase la descarga que [COR-03]
        # evita. Se comprueba abriendolo en exclusiva: si la funcion
        # intentara abrirlo, esto fallaria.
        $flujo = [IO.File]::Open($script:Archivo, [IO.FileMode]::Open,
                                 [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            { Get-TamanoEnDisco -Ruta $script:Archivo } | Should -Not -Throw
        } finally {
            $flujo.Dispose()
        }
    }
}

Describe 'Get-EspacioRecuperable' {

    It 'criterio de aceptacion: 100 MB que ocupan 30 MB se prometen como 30' {
        # Literalmente lo que pide [VIS-05] en la hoja de ruta.
        Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB |
            Should -Be $script:TREINTA_MB
        Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB |
            Should -Not -Be $script:CIEN_MB
    }

    It 'un archivo sin comprimir promete lo mismo que antes' {
        # El caso normal, que es el 99 % de los archivos: logico y disco
        # coinciden y no cambia nada de lo que el programa ya hacia.
        Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:CIEN_MB |
            Should -Be $script:CIEN_MB
    }

    It 'cuando no se sabe lo que ocupa, se promete el tamanyo logico' {
        # No saber no puede empeorar el comportamiento anterior: si la
        # medicion no existe, se hace lo de siempre.
        Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco $null |
            Should -Be $script:CIEN_MB
    }

    It '"no lo se" y "cero" no son lo mismo' {
        # Si $null se tratara como 0 -que es lo que hace cualquier
        # conversion descuidada-, el programa dejaria de prometer espacio
        # en cuanto la medicion fallara. Y si 0 se tratara como $null,
        # prometeria 100 MB por un archivo que no ocupa nada.
        $sinSaber = Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco $null
        $enCero   = Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco 0
        $sinSaber | Should -Be $script:CIEN_MB
        $enCero   | Should -Be 0
        $sinSaber | Should -Not -Be $enCero
    }

    It 'con todo a cero promete cero' {
        Get-EspacioRecuperable -TamanoLogico 0 -TamanoEnDisco 0 | Should -Be 0
    }

    It 'los numeros negativos no producen promesas negativas' {
        # Un tamanyo negativo es un dato roto, no una promesa: se trata
        # como cero, que es el lado seguro.
        Get-EspacioRecuperable -TamanoLogico -5 -TamanoEnDisco -5   | Should -Be 0
        Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco -5 | Should -Be 0
        Get-EspacioRecuperable -TamanoLogico -5 -TamanoEnDisco $null | Should -Be 0
    }

    It 'ni los nulos ni la basura revientan' {
        { Get-EspacioRecuperable -TamanoLogico $null -TamanoEnDisco $null } | Should -Not -Throw
        Get-EspacioRecuperable -TamanoLogico $null -TamanoEnDisco $null     | Should -Be 0
        { Get-EspacioRecuperable -TamanoLogico 'hola' -TamanoEnDisco @(1, 2) } | Should -Not -Throw
        Get-EspacioRecuperable -TamanoLogico $script:CIEN_MB -TamanoEnDisco 'hola' | Should -Be 0
    }

    It 'INVARIANTE: si se sabe lo que ocupa, nunca se promete mas que eso' {
        # Esta es la invariante que da sentido al punto entero. Todo lo
        # demas de [VIS-05] -leer el atributo, ensenyar dos cifras- es
        # informacion; esto es la promesa. Si se rompe, el programa vuelve
        # a ofrecer espacio que el disco no tiene.
        $logicos = @(0, 1, 4096, 1MB, 100MB, 3GB, 12345678)
        $discos  = @(0, 1, 4096, 512KB, 30MB, 100MB, 3GB)

        $revisados = 0
        foreach ($logico in $logicos) {
            foreach ($disco in $discos) {
                $prometido = Get-EspacioRecuperable -TamanoLogico $logico -TamanoEnDisco $disco
                $prometido | Should -BeLessOrEqual $disco -Because (
                    ('con {0} logicos que ocupan {1} se prometio {2}' -f $logico, $disco, $prometido))
                $prometido | Should -BeGreaterOrEqual 0
                $revisados++
            }
        }
        # Guarda: sin esto, un bucle que no entrara ni una vez dejaria la
        # prueba en verde sin haber comprobado nada.
        $revisados | Should -Be ($logicos.Count * $discos.Count)
    }
}

Describe 'Format-DetalleCompresion' {

    It 'criterio de aceptacion: se ensenyan LAS DOS cifras' {
        # 100 MB que ocupan 30 MB. Ensenyar solo la cifra pequenya
        # arreglaria la aritmetica y dejaria al usuario sin entender por
        # que su carpeta de 100 MB libera 30.
        $texto = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB
        $texto | Should -BeLike ('*' + (Format-Tamano -Bytes $script:CIEN_MB) + '*')
        $texto | Should -BeLike ('*' + (Format-Tamano -Bytes $script:TREINTA_MB) + '*')
    }

    It 'y lo que promete liberar es 30, no 100' {
        $texto = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB
        $texto | Should -Match ('liberan\s+' + [regex]::Escape((Format-Tamano -Bytes $script:TREINTA_MB)))
        $texto | Should -Not -Match ('liberan\s+' + [regex]::Escape((Format-Tamano -Bytes $script:CIEN_MB)))
    }

    It 'INVARIANTE: la cifra del texto es la que decide Get-EspacioRecuperable' {
        # El texto y la decision no pueden divergir: si el mensaje dijera
        # una cifra y el motor sumara otra, el usuario leeria una promesa
        # que el programa no se ha hecho a si mismo.
        $casos = @(
            @{ Logico = 100MB; Disco = 30MB }
            @{ Logico = 4GB;   Disco = 1GB }
            @{ Logico = 8192;  Disco = 4096 }
        )
        foreach ($caso in $casos) {
            $texto     = Format-DetalleCompresion -TamanoLogico $caso.Logico -TamanoEnDisco $caso.Disco
            $prometido = Format-Tamano -Bytes (Get-EspacioRecuperable -TamanoLogico $caso.Logico -TamanoEnDisco $caso.Disco)
            $texto | Should -Match ('liberan\s+' + [regex]::Escape($prometido))
        }
        $casos.Count | Should -Be 3
    }

    It 'cuando no se sabe lo que ocupa en disco, se dice' {
        # Una cifra sin aviso se lee como una medicion. Si no se ha podido
        # medir, callarlo es afirmar algo que no se sabe.
        $texto = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $null
        $texto | Should -BeLike ('*' + (Format-Tamano -Bytes $script:CIEN_MB) + '*')
        $texto | Should -Match 'disco'
        $texto | Should -Not -Match 'liberan'
    }

    It 'un archivo comprimido que no gana nada no dice "se liberan X, no X"' {
        # Pasa con lo que ya venia comprimido -video, .zip- y con los
        # archivos diminutos, que ocupan un grupo entero del disco.
        $texto = Format-DetalleCompresion -TamanoLogico 1KB -TamanoEnDisco 4KB
        $texto | Should -Not -Match 'liberan'
        $texto | Should -BeLike ('*' + (Format-Tamano -Bytes 4KB) + '*')
    }

    It 'nunca dice "1 elementos"' {
        # Singular y plural de verdad. El numero es casi siempre 1, asi
        # que el descuido saldria en pantalla el primer dia.
        $uno    = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB -Archivos 1
        $varios = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB -Archivos 4

        $uno    | Should -BeLike '*1 archivo comprimido*'
        $uno    | Should -Not -BeLike '*1 archivos*'
        $varios | Should -BeLike '*4 archivos comprimidos*'
        $varios | Should -Not -BeLike '*4 archivo comprimidos*'
    }

    It 'sin contador habla de uno solo, sin inventarse un numero' {
        $texto = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB
        $texto | Should -BeLike 'Comprimido con NTFS*'
        $texto | Should -Not -Match '^\d'
    }

    It 'el texto de cara al usuario lleva tildes y enyes' {
        # [I18N-01]: la prosa que se ensenya va en castellano correcto.
        $conocido    = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB
        $desconocido = Format-DetalleCompresion -TamanoLogico $script:CIEN_MB -TamanoEnDisco $null

        $conocido    | Should -Match 'tamaño'
        $desconocido | Should -Match 'cuánto'
        $desconocido | Should -Match 'así'
    }

    It 'ni los nulos ni la basura revientan' {
        { Format-DetalleCompresion -TamanoLogico $null -TamanoEnDisco $null }     | Should -Not -Throw
        { Format-DetalleCompresion -TamanoLogico 'hola' -TamanoEnDisco 'adios' }  | Should -Not -Throw
        { Format-DetalleCompresion -TamanoLogico -1 -TamanoEnDisco -1 }           | Should -Not -Throw
        Format-DetalleCompresion -TamanoLogico $null -TamanoEnDisco $null | Should -Not -BeNullOrEmpty
    }
}
