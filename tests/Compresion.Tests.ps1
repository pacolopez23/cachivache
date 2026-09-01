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

Describe 'VIS-05: el candidato lleva el tamanyo en disco, y es ANULABLE' {

    <#
        La mitad de nucleo de [VIS-05] estaba escrita y probada, y no la
        usaba nadie: en una carpeta comprimida el programa seguia
        prometiendo el tamanyo LOGICO. Esto es el enganche.

        Las dos ramas se ejercitan PASANDO EL TAMANYO A MANO, no llamando a
        Get-TamanoEnDisco: aqui no hay Windows, asi que la medicion real
        contesta $null siempre y la rama de "si lo se" no llegaria a
        ejecutarse nunca. Una prueba que solo puede recorrer un lado del if
        no comprueba el if.
    #>

    It 'criterio de aceptacion: 100 MB que ocupan 30 se proponen como 30' {
        # Literalmente lo que pide [VIS-05], ya sobre el candidato entero y
        # no sobre la funcion suelta.
        $c = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' `
                           -Ruta 'C:\zona\comprimida\archivo.bak' `
                           -Bytes $script:CIEN_MB -TamanoEnDisco $script:TREINTA_MB

        $c.Bytes         | Should -Be $script:TREINTA_MB
        $c.Bytes         | Should -Not -Be $script:CIEN_MB
        $c.TamanoEnDisco | Should -Be $script:TREINTA_MB
    }

    It 'sin decir nada, el candidato promete lo mismo que ha prometido siempre' {
        # El 99 % de los candidatos: ningun modulo pasa -TamanoEnDisco y el
        # comportamiento anterior no cambia ni un byte.
        $c = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' `
                           -Ruta 'C:\zona\normal\archivo.tmp' -Bytes $script:CIEN_MB

        $c.Bytes | Should -Be $script:CIEN_MB
    }

    It 'el campo nace a $null, NUNCA a cero' {
        # Esto es lo mas importante del enganche. Con 0 por defecto, todo
        # candidato del programa afirmaria ocupar cero bytes en disco, y
        # Get-EspacioRecuperable -que hace bien su trabajo- prometeria cero
        # para absolutamente todo. El programa diria que no hay nada que
        # ganar limpiando.
        $c = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\zona\normal\archivo.tmp' -Bytes 1MB

        ($null -eq $c.TamanoEnDisco) | Should -BeTrue -Because 'no preguntarlo es "no lo se", no "no ocupa nada"'
        ($c.TamanoEnDisco -eq 0)     | Should -BeFalse
        $c.Bytes                     | Should -Be 1MB
    }

    It 'un cero explicito SI es cero, y no se confunde con no saberlo' {
        # El otro lado de la misma distincion: un archivo que de verdad no
        # ocupa nada -disperso, o de cero bytes- no promete su tamanyo
        # logico.
        $sinSaber = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\z\a' -Bytes $script:CIEN_MB
        $enCero   = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\z\a' `
                                  -Bytes $script:CIEN_MB -TamanoEnDisco 0

        $sinSaber.Bytes | Should -Be $script:CIEN_MB
        $enCero.Bytes   | Should -Be 0
    }

    It 'el campo del contrato existe siempre, se pase o no' {
        # Una propiedad que unas veces esta y otras no obliga a preguntar
        # por ella antes de leerla, y en PowerShell leer la que no esta NO
        # lanza: el sintoma seria un $null que parece una medicion fallida.
        foreach ($c in @(
            (New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\z\a' -Bytes 1MB),
            (New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\z\a' -Bytes 1MB -TamanoEnDisco 4KB)
        )) {
            $c.PSObject.Properties['TamanoEnDisco'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'ni un nulo ni la basura revientan al construir el candidato' {
        # [AllowNull()] en lo que puede recibir nulo. Ha faltado tres veces
        # en este proyecto y las tres lo cazo esta prueba.
        { New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\z\a' `
                        -Bytes 1MB -TamanoEnDisco $null } | Should -Not -Throw
        { New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\z\a' `
                        -Bytes 1MB -TamanoEnDisco 'hola' } | Should -Not -Throw
    }

    It 'INVARIANTE: teniendo el tamanyo en disco, el candidato NUNCA promete el logico' {
        # LA INVARIANTE DEL PUNTO. Todo lo demas de [VIS-05] es informacion;
        # esto es la promesa. Si se rompe, el programa vuelve a ofrecer
        # espacio que el disco no tiene, y el usuario lo descubre DESPUES de
        # borrar, cuando ya no puede comprobar nada.
        #
        # Y se compara contra Get-EspacioRecuperable, no contra una tabla de
        # numeros escrita aqui: una tabla seria una segunda copia de la
        # regla, y dos copias de una regla acaban diciendo cosas distintas.
        # Asi, quien decide cuanto se promete sigue siendo esa funcion y
        # nadie mas.
        $logicos = @(0, 1, 4096, 1MB, 100MB, 3GB, 12345678)
        $discos  = @(0, 1, 4096, 512KB, 30MB, 100MB, 3GB)

        $revisados = 0
        foreach ($logico in $logicos) {
            foreach ($disco in $discos) {
                $c = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' `
                                   -Ruta 'C:\zona\comprimida\archivo.bak' `
                                   -Bytes $logico -TamanoEnDisco $disco

                $c.Bytes | Should -Be (Get-EspacioRecuperable -TamanoLogico $logico -TamanoEnDisco $disco) `
                    -Because ('el candidato tiene que prometer lo que decide Get-EspacioRecuperable, no una copia de la regla')
                $c.Bytes | Should -BeLessOrEqual $disco -Because (
                    ('con {0} logicos que ocupan {1} el candidato prometio {2}' -f $logico, $disco, $c.Bytes))

                # Y el caso que da nombre al punto: si el disco tiene menos,
                # el logico no puede salir por ninguna parte.
                if ($disco -lt $logico) { $c.Bytes | Should -Not -Be $logico }
                $revisados++
            }
        }
        # Guarda: sin esto, un bucle que no entrara ni una vez dejaria la
        # prueba en verde sin haber comprobado nada.
        $revisados | Should -Be ($logicos.Count * $discos.Count)
    }

    It 'INVARIANTE: New-Candidato no calcula la promesa por su cuenta' {
        # La otra mitad, y hace falta: la de arriba compara el resultado, y
        # una copia literal de la regla escrita dentro de New-Candidato
        # daria los mismos numeros y pasaria. Lo que no se puede volver a
        # tener es DOS sitios que decidan cuanto se promete, que es
        # exactamente de donde salio este fallo.
        $ruta  = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Candidate.ps1'
        $texto = [IO.File]::ReadAllText($ruta)

        # Fuera los bloques de ayuda ANTES que las lineas de comentario: al
        # reves, el primer paso se lleva la linea del #> y el bloque se
        # queda sin cerrar. Y aqui importa de verdad, porque el comentario
        # que explica este campo nombra las dos formas.
        $sinBloques = [regex]::Replace($texto, '(?s)<#.*?#>', '')
        $codigo = @(($sinBloques -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        # Guarda: si el corte se comiera la funcion entera, lo de abajo
        # pasaria por no encontrar nada.
        $codigo | Should -Match 'function New-Candidato'
        $codigo | Should -Match 'TamanoEnDisco'

        $codigo | Should -Match 'Bytes\s*=\s*Get-EspacioRecuperable -TamanoLogico \$Bytes -TamanoEnDisco \$TamanoEnDisco' `
            -Because 'quien decide cuanto se promete es Get-EspacioRecuperable, y el candidato tiene que pasar por ahi'
        $codigo | Should -Not -Match 'Bytes\s*=\s*\[double\]\$Bytes' `
            -Because 'prometer el tamanyo logico teniendo el de disco es el fallo que [VIS-05] arregla'
    }
}

Describe 'VIS-05: el recorrido compartido lee el atributo, y solo pregunta cuando toca' {

    <#
        [COR-08] dejo un solo recorrido para los modulos, y ahi ya llegan
        los atributos del archivo sin coste: vienen del WIN32_FIND_DATA que
        devuelve la propia enumeracion. Preguntar por el bit de compresion
        es gratis; preguntar cuanto ocupa cuesta una llamada al sistema por
        archivo, asi que solo se hace por lo que ya dice estar comprimido.

        Aqui no hay NTFS, o sea que ningun archivo de estas pruebas lleva
        la marca: lo que se puede comprobar de verdad es que la propiedad
        existe siempre, que sin pedirlo vale $null, y -por texto- que el
        orden de la rama es el que hace que no se pague.
    #>

    BeforeAll {
        $script:Zona08 = Join-Path ([IO.Path]::GetTempPath()) ('vis05-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Zona08 -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:Zona08 'suelto.tmp'), 'aaa')
        New-Item -ItemType Directory -Path (Join-Path $script:Zona08 'sub') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:Zona08 'sub/dentro.tmp'), 'bbbb')

        $script:RutaFs = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'FileSystem.ps1'
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Zona08 -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'todo lo que sale del recorrido trae la propiedad, archivos y carpetas' {
        $elementos = @(Get-ElementosDelArbol -Ruta $script:Zona08 -Que Todo)
        $elementos.Count | Should -BeGreaterThan 2

        foreach ($elemento in $elementos) {
            $elemento.PSObject.Properties['TamanoEnDisco'] | Should -Not -BeNullOrEmpty `
                -Because "a '$($elemento.Name)' le falta el campo"
        }
    }

    It 'sin pedirlo vale $null: no se paga y no se afirma nada' {
        foreach ($elemento in @(Get-ElementosDelArbol -Ruta $script:Zona08 -Que Todo)) {
            ($null -eq $elemento.TamanoEnDisco) | Should -BeTrue -Because (
                'sin -MedirEnDisco no se pregunta al sistema, y no preguntar es "no lo se"')
        }
    }

    It 'pedirlo no cambia lo que se encuentra ni revienta' {
        # Fuera de Windows Get-TamanoEnDisco contesta $null siempre, asi que
        # aqui lo comprobable es que la rama nueva no estorba al recorrido.
        $sin = @(Get-ElementosDelArbol -Ruta $script:Zona08 | ForEach-Object { $_.FullName }) | Sort-Object
        $con = @(Get-ElementosDelArbol -Ruta $script:Zona08 -MedirEnDisco | ForEach-Object { $_.FullName }) | Sort-Object

        @($sin).Count      | Should -BeGreaterThan 1
        ($con -join '|')   | Should -Be ($sin -join '|')
    }

    It 'INVARIANTE: se pregunta por el bit ANTES de preguntarle al sistema' {
        # El orden ES el rendimiento. Al reves -medir y despues mirar si
        # estaba comprimido- el recorrido pagaria una llamada al sistema
        # por cada uno de los cientos de miles de archivos de un disco, y
        # nada fallaria: solo tardaria muchisimo mas, que es la clase de
        # regresion que nadie atribuye a su causa.
        $texto = [IO.File]::ReadAllText($script:RutaFs)
        $desde = $texto.IndexOf('function Get-ElementosDelArbol')
        $hasta = $texto.IndexOf('function Measure-Ruta')
        $desde | Should -BeGreaterThan 0
        $hasta | Should -BeGreaterThan $desde

        $sinBloques = [regex]::Replace($texto.Substring($desde, $hasta - $desde), '(?s)<#.*?#>', '')
        $cuerpo = @(($sinBloques -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        $cuerpo | Should -Match '\$MedirEnDisco -and \(Test-EstaComprimido' -Because (
            'primero el bit, que es gratis; la llamada al sistema solo para lo que ya dice estar comprimido')
        $cuerpo | Should -Match 'Get-TamanoEnDisco -Ruta'
    }
}
