<#
    Los manifiestos de winget y de Scoop. [DIS-03] y [DIS-04].

    Los dos declaran cuatro datos que cambian en cada version: la version sin
    la v, la URL de descarga, la carpeta que hay DENTRO del zip y el SHA-256.
    Escritos a mano, los cuatro envejecen sin que falle nada: el manifiesto
    se lee perfectamente, pasa el analizador y se sube tal cual. El fallo
    aparece en el equipo de quien instala, y lo que su gestor le dice es que
    el archivo descargado no coincide con lo declarado -o sea, que el
    paquete esta adulterado-.

    De ahi que los manifiestos se generen. Y de ahi que lo que se prueba aqui
    no sea solo el formato, sino sobre todo las TRES COSTURAS por las que
    esto se puede separar en silencio:

      1. El nombre del zip lo decide publicar.yml y lo repiten las dos URL.
      2. La direccion del repositorio la decide src/Core/Version.ps1.
      3. El hash va en MAYUSCULAS en winget y en MINUSCULAS en Scoop, y en
         los dos sitios tiene que ser el mismo hash.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path $script:Raiz 'tools') 'Manifiestos.ps1')

    # Un SHA-256 de verdad y en mayusculas, que es como lo devuelve
    # Get-FileHash. Probar el trato de mayusculas con una cadena que ya
    # estuviera en minusculas no probaria nada.
    $script:Hash = 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
    $script:Etiqueta = 'v2.1.0'

    $script:Identidad  = Get-IdentidadPaquete
    $script:WVersion   = Format-ManifiestoWingetVersion   -Etiqueta $script:Etiqueta
    $script:WInstalador = Format-ManifiestoWingetInstalador -Etiqueta $script:Etiqueta -Hash $script:Hash
    $script:WLocale    = Format-ManifiestoWingetLocale    -Etiqueta $script:Etiqueta
    $script:Scoop      = Format-ManifiestoScoop           -Etiqueta $script:Etiqueta -Hash $script:Hash

    # El flujo de publicacion, sin comentarios. Las pruebas que buscan texto
    # encuentran los propios comentarios, y aqui hay un comentario por cada
    # cosa que se comprueba: encontrarian todas sin que el flujo hiciera
    # ninguna.
    $script:Flujo = (Get-Content -LiteralPath (Join-Path $script:Raiz '.github/workflows/publicar.yml') |
        Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
}

Describe 'Get-VersionDesdeEtiqueta: la version que ponen los manifiestos' {

    It 'quita la v inicial' {
        # winget y Scoop ordenan versiones. 'v2.1.0' no es un numero de
        # version para ninguno de los dos: sale en la lista como texto y no
        # ordena con las demas.
        Get-VersionDesdeEtiqueta -Etiqueta 'v2.1.0' | Should -BeExactly '2.1.0'
        Get-VersionDesdeEtiqueta -Etiqueta 'v10.0.3.1' | Should -BeExactly '10.0.3.1'
    }

    It 'rechaza <Que>' -ForEach @(
        @{ Que = 'una version sin v';      Etiqueta = '2.1.0' }
        @{ Que = 'una rama';               Etiqueta = 'main' }
        @{ Que = 'el dev del disparo a mano'; Etiqueta = 'dev' }
        @{ Que = 'una v con letras';       Etiqueta = 'v2.1.0-beta' }
        @{ Que = 'solo la v';              Etiqueta = 'v' }
        @{ Que = 'un solo numero';         Etiqueta = 'v2' }
        @{ Que = 'una cadena vacia';       Etiqueta = '' }
    ) {
        # Adivinar aqui produce una URL de descarga que devuelve 404, y un
        # 404 no lo ve nadie hasta que alguien intenta instalar.
        { Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta } | Should -Throw
    }

    It 'con nulo lanza, y lo dice' {
        { Get-VersionDesdeEtiqueta -Etiqueta $null } | Should -Throw -ExpectedMessage '*etiqueta*'
    }

    It 'una V mayuscula no cuela' {
        # -cnotmatch a proposito: las etiquetas de este proyecto son v*, en
        # minuscula, y GitHub distingue. Una URL con V mayuscula es un 404.
        { Get-VersionDesdeEtiqueta -Etiqueta 'V2.1.0' } | Should -Throw
    }
}

Describe 'El nombre del zip y la carpeta de dentro' {

    It 'el zip lleva la etiqueta entera, con la v' {
        Get-NombrePaqueteZip -Etiqueta 'v2.1.0' | Should -BeExactly 'Cachivache-v2.1.0.zip'
    }

    It 'la carpeta de dentro del zip es el mismo nombre sin la extension' {
        # Compress-Archive -Path Cachivache-v2.1.0 comprime LA CARPETA, no
        # su contenido: al descomprimir no aparece Cachivache.exe, aparece
        # Cachivache-v2.1.0\Cachivache.exe. Es el dato que mas facil se
        # olvida, y lleva la version dentro.
        Get-CarpetaDentroDelZip -Etiqueta 'v2.1.0' | Should -BeExactly 'Cachivache-v2.1.0'
    }

    It 'una etiqueta invalida no llega a producir un nombre' {
        { Get-NombrePaqueteZip -Etiqueta 'dev' }     | Should -Throw
        { Get-CarpetaDentroDelZip -Etiqueta 'dev' }  | Should -Throw
    }

    It 'la URL de descarga es la de los adjuntos de la version' {
        Get-UrlDescarga -Etiqueta 'v2.1.0' -Archivo 'SHA256SUMS.txt' |
            Should -BeExactly ($script:Identidad.Repositorio + '/releases/download/v2.1.0/SHA256SUMS.txt')
    }

    It 'una URL sin archivo se rechaza' {
        { Get-UrlDescarga -Etiqueta 'v2.1.0' -Archivo '' }   | Should -Throw
        { Get-UrlDescarga -Etiqueta 'v2.1.0' -Archivo $null } | Should -Throw
    }
}

Describe 'ConvertTo-EscalarYaml: en YAML, 2.1 no es una cadena' {

    It 'deja en paz lo que no necesita comillas' {
        ConvertTo-EscalarYaml -Valor '2.1.0'    | Should -BeExactly '2.1.0'
        ConvertTo-EscalarYaml -Valor 'es-ES'    | Should -BeExactly 'es-ES'
        ConvertTo-EscalarYaml -Valor 'Cachivache-v2.1.0\Cachivache.exe' |
            Should -BeExactly 'Cachivache-v2.1.0\Cachivache.exe'
    }

    It 'entrecomilla <Que>, que YAML convertiria' -ForEach @(
        @{ Que = 'una version de dos partes'; Valor = '2.1' }
        @{ Que = 'un entero';                 Valor = '3' }
        @{ Que = 'algo con forma de si';      Valor = 'yes' }
        @{ Que = 'algo con forma de no';      Valor = 'no' }
        @{ Que = 'un nulo de YAML';           Valor = '~' }
        @{ Que = 'algo que empieza por guion'; Valor = '- raro' }
        @{ Que = 'algo con dos puntos y espacio'; Valor = 'clave: valor' }
    ) {
        (ConvertTo-EscalarYaml -Valor $Valor).StartsWith("'") | Should -BeTrue
        (ConvertTo-EscalarYaml -Valor $Valor).EndsWith("'")   | Should -BeTrue
    }

    It 'duplica las comillas simples de dentro' {
        # Una comilla al principio SI obliga a entrecomillar -es un
        # indicador de YAML-, y entonces hay que duplicarla. Una comilla en
        # medio no obliga a nada, y por eso el caso de prueba empieza por
        # ella: es el unico que ejerce las dos mitades a la vez.
        ConvertTo-EscalarYaml -Valor "'ojo'" | Should -BeExactly "'''ojo'''"
    }

    It 'una cadena vacia sale como cadena vacia, no como nada' {
        # "clave:" a secas es null en YAML, no "". El esquema de winget pide
        # cadena y lo rechazaria.
        ConvertTo-EscalarYaml -Valor '' | Should -BeExactly "''"
        ConvertTo-EscalarYaml -Valor $null | Should -BeExactly "''"
    }

    It 'la version de dos partes llega entrecomillada al manifiesto' {
        # La prueba de arriba comprueba la funcion; esta comprueba que se
        # usa. Este proyecto admite etiquetas de dos partes, asi que v2.1
        # produciria "PackageVersion: 2.1", que en YAML es el numero 2.1 y
        # no la cadena "2.1". El validador de winget lo rechaza con un error
        # que no habla de versiones.
        Format-ManifiestoWingetVersion -Etiqueta 'v2.1' | Should -Match "PackageVersion: '2\.1'"
    }
}

Describe 'winget: los tres manifiestos' {

    It 'las pruebas leen tres manifiestos de verdad: si no, no comprueban nada' {
        foreach ($texto in @($script:WVersion, $script:WInstalador, $script:WLocale)) {
            $texto.Length | Should -BeGreaterThan 150
            $texto | Should -Match 'PackageIdentifier:'
        }
        # Los tres tienen que ser distintos: si Format-... devolviera lo
        # mismo tres veces, todo lo de abajo seguiria pasando.
        (@($script:WVersion, $script:WInstalador, $script:WLocale) | Select-Object -Unique).Count |
            Should -Be 3
    }

    It 'cada uno declara su ManifestType, y son los tres que winget espera' {
        $script:WVersion    | Should -Match '(?m)^ManifestType: version$'
        $script:WInstalador | Should -Match '(?m)^ManifestType: installer$'
        $script:WLocale     | Should -Match '(?m)^ManifestType: defaultLocale$'
    }

    It 'los tres hablan del mismo paquete y de la misma version' {
        # Un manifiesto multi-archivo con un PackageIdentifier distinto en
        # uno de los tres no es un paquete: son tres paquetes rotos.
        foreach ($texto in @($script:WVersion, $script:WInstalador, $script:WLocale)) {
            $texto | Should -Match ('(?m)^PackageIdentifier: ' + [regex]::Escape($script:Identidad.IdentificadorWinget) + '$')
            $texto | Should -Match '(?m)^PackageVersion: 2\.1\.0$'
        }
    }

    It 'el identificador tiene la forma Editor.Paquete que exige winget' {
        $script:Identidad.IdentificadorWinget | Should -Match '^[^.\s]{1,32}(\.[^.\s]{1,32}){1,7}$'
    }

    It 'el DefaultLocale del manifiesto de version es el PackageLocale del otro' {
        # Si no coinciden, winget no encuentra la descripcion por defecto.
        $script:WVersion | Should -Match ('(?m)^DefaultLocale: ' + [regex]::Escape($script:Identidad.Idioma) + '$')
        $script:WLocale  | Should -Match ('(?m)^PackageLocale: ' + [regex]::Escape($script:Identidad.Idioma) + '$')
    }

    It 'el instalador es un zip portable con archivo anidado' {
        # Es lo que hace que winget acepte un paquete SIN FIRMAR: no ejecuta
        # ningun instalador, descomprime y crea un alias. Por eso [DIS-03]
        # no depende de [DIS-01].
        $script:WInstalador | Should -Match '(?m)^InstallerType: zip$'
        $script:WInstalador | Should -Match '(?m)^NestedInstallerType: portable$'
        $script:WInstalador | Should -Match '(?m)^NestedInstallerFiles:$'
    }

    It 'la ruta del ejecutable dentro del zip lleva la carpeta de la version' {
        # Sin la carpeta, winget instala y luego no encuentra el
        # ejecutable, que es el fallo mas confuso de los cuatro.
        $script:WInstalador | Should -Match 'RelativeFilePath: Cachivache-v2\.1\.0\\Cachivache\.exe'
    }

    It 'la URL del instalador apunta al zip de esta version' {
        $esperada = Get-UrlDescarga -Etiqueta $script:Etiqueta -Archivo (Get-NombrePaqueteZip -Etiqueta $script:Etiqueta)
        $script:WInstalador | Should -Match ('(?m)^\s+InstallerUrl: ' + [regex]::Escape($esperada) + '$')
    }

    It 'el SHA-256 va en MAYUSCULAS' {
        # winget compara sin distinguir, pero wingetcreate escribe en
        # mayusculas. Si alguien regenera el manifiesto y le sale otra
        # cosa, tiene que ser porque el paquete cambio y no por el formato.
        $script:WInstalador | Should -MatchExactly ('InstallerSha256: ' + $script:Hash.ToUpperInvariant())
        $script:WInstalador | Should -Not -MatchExactly ('InstallerSha256: ' + $script:Hash.ToLowerInvariant())
    }

    It 'un hash que no tiene forma de hash no llega a producir manifiesto' {
        # Declarar una suma mal es peor que no declararla: quien instala
        # concluye que el paquete esta adulterado.
        { Format-ManifiestoWingetInstalador -Etiqueta $script:Etiqueta -Hash 'e3b0c442' } | Should -Throw
        { Format-ManifiestoWingetInstalador -Etiqueta $script:Etiqueta -Hash '' }         | Should -Throw
        { Format-ManifiestoWingetInstalador -Etiqueta $script:Etiqueta -Hash $null }      | Should -Throw
    }

    It 'el manifiesto de idioma lleva lo que winget exige para publicar' {
        foreach ($clave in @('Publisher', 'PackageName', 'License', 'ShortDescription')) {
            $script:WLocale | Should -Match ('(?m)^' + $clave + ': \S')
        }
    }

    It 'la licencia que declara es la del repositorio' {
        # LICENSE es MIT. Declarar otra cosa en la tienda de paquetes de
        # Microsoft no es un descuido de formato.
        $licencia = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'LICENSE')
        $licencia | Should -Match 'MIT License'
        $script:Identidad.Licencia | Should -BeExactly 'MIT'
    }

    It 'los tres terminan en salto de linea y ninguno lleva retornos de carro' {
        foreach ($texto in @($script:WVersion, $script:WInstalador, $script:WLocale)) {
            $texto | Should -Not -Match "`r"
            $texto.EndsWith("`n") | Should -BeTrue
        }
    }
}

Describe 'Scoop: el .json' {

    BeforeAll {
        $script:ScoopObjeto = $script:Scoop | ConvertFrom-Json
    }

    It 'la prueba lee un JSON de verdad: si no, no comprueba nada' {
        { $script:Scoop | ConvertFrom-Json } | Should -Not -Throw
        $script:ScoopObjeto.version | Should -Not -BeNullOrEmpty
    }

    It 'la version va sin la v' {
        $script:ScoopObjeto.version | Should -BeExactly '2.1.0'
    }

    It 'el hash va en MINUSCULAS' {
        # No es cosmetico. El autoupdate de aqui abajo saca el hash de
        # SHA256SUMS.txt, que Sumas.ps1 escribe en minusculas a proposito.
        # Si el manifiesto declarase mayusculas, el mismo hash estaria
        # escrito de dos formas y cualquier comparacion literal fallaria.
        $script:ScoopObjeto.hash | Should -BeExactly $script:Hash.ToLowerInvariant()
    }

    It 'la url apunta al zip de esta version' {
        $script:ScoopObjeto.url | Should -BeExactly (
            Get-UrlDescarga -Etiqueta $script:Etiqueta -Archivo (Get-NombrePaqueteZip -Etiqueta $script:Etiqueta))
    }

    It 'extract_dir es la carpeta que hay dentro del zip' {
        # Sin esto, Scoop deja una carpeta de mas en medio y el acceso
        # directo apunta a un archivo que no existe.
        $script:ScoopObjeto.extract_dir | Should -BeExactly (Get-CarpetaDentroDelZip -Etiqueta $script:Etiqueta)
    }

    It 'da un shim de consola y un acceso directo de ventana' {
        # Son las dos formas de arrancar el programa y las dos hacen falta:
        # un shim al .exe abriria una ventana desde la terminal sin decir
        # nada, y solo el acceso directo dejaria fuera al publico de Scoop,
        # que vive en la terminal.
        $script:ScoopObjeto.bin[0][0]       | Should -BeExactly 'Cachivache.ps1'
        $script:ScoopObjeto.bin[0][1]       | Should -BeExactly 'cachivache'
        $script:ScoopObjeto.shortcuts[0][0] | Should -BeExactly 'Cachivache.exe'
    }

    It 'lleva checkver y autoupdate' {
        # Son para el dia en que esto se olvide: si alguien mete el .json en
        # un bucket y deja de regenerarlo, Scoop se actualiza solo. Un
        # manifiesto sin autoupdate es el que se queda anclado para siempre.
        $script:ScoopObjeto.checkver.github | Should -BeExactly $script:Identidad.Repositorio
        $script:ScoopObjeto.autoupdate.url  | Should -Not -BeNullOrEmpty
    }

    It 'el autoupdate deja los marcadores de Scoop sin expandir' {
        # $version y $baseurl los sustituye Scoop. Con comillas dobles
        # PowerShell los habria expandido AQUI, a cadena vacia, y el
        # autoupdate apuntaria a .../download/v/Cachivache-.zip. Se leeria
        # perfectamente y no descargaria nada.
        $script:ScoopObjeto.autoupdate.url         | Should -BeLike '*/v$version/Cachivache-v$version.zip'
        # Con la v, porque la carpeta de dentro del zip lleva la etiqueta
        # entera y $version es la version sin ella.
        $script:ScoopObjeto.autoupdate.extract_dir | Should -BeExactly 'Cachivache-v$version'
        $script:ScoopObjeto.autoupdate.hash.url    | Should -BeExactly '$baseurl/SHA256SUMS.txt'
    }

    It 'el autoupdate saca el hash del archivo que publica el flujo' {
        # $baseurl es la carpeta de adjuntos de la version, que es donde
        # action-gh-release deja SHA256SUMS.txt. Si el flujo dejara de
        # adjuntarlo, el autoupdate se quedaria sin hash.
        $script:Flujo | Should -Match 'SHA256SUMS\.txt'
        $script:ScoopObjeto.autoupdate.hash.url | Should -BeLike '*SHA256SUMS.txt'
    }

    It 'un hash que no tiene forma de hash no llega a producir manifiesto' {
        { Format-ManifiestoScoop -Etiqueta $script:Etiqueta -Hash 'e3b0c442' } | Should -Throw
        { Format-ManifiestoScoop -Etiqueta $script:Etiqueta -Hash $null }      | Should -Throw
    }

    It 'saltos LF, salto final, y ningun retorno de carro' {
        # ConvertTo-Json devuelve CRLF en Windows. Estos archivos acaban en
        # un repositorio de Scoop donde cada diferencia se revisa a mano.
        $script:Scoop | Should -Not -Match "`r"
        $script:Scoop.EndsWith("`n") | Should -BeTrue
    }
}

Describe 'Los dos manifiestos dicen lo mismo' {
    <#
        Son dos representaciones del mismo paquete, y asi es exactamente
        como empiezan las divergencias: uno se actualiza y el otro no, y
        entonces winget instala una version y Scoop otra.
    #>

    It 'la misma version' {
        $scoop = $script:Scoop | ConvertFrom-Json
        $script:WInstalador | Should -Match ('(?m)^PackageVersion: ' + [regex]::Escape($scoop.version) + '$')
    }

    It 'el mismo hash, cada uno en su caso' {
        $scoop = $script:Scoop | ConvertFrom-Json
        # Que sean el mismo hash escrito distinto, y no dos hashes.
        $script:WInstalador | Should -MatchExactly ('InstallerSha256: ' + $scoop.hash.ToUpperInvariant())
        $scoop.hash | Should -MatchExactly '^[0-9a-f]{64}$'
    }

    It 'la misma URL de descarga' {
        $scoop = $script:Scoop | ConvertFrom-Json
        $script:WInstalador | Should -Match ('InstallerUrl: ' + [regex]::Escape($scoop.url))
    }
}

Describe 'La costura con el flujo de publicacion' {
    <#
        El nombre del zip lo decide publicar.yml y lo repiten las dos URL.
        Si alguien lo renombra alli, hoy no falla nada: se publica un
        paquete con un nombre y dos manifiestos que apuntan a otro. El 404
        no lo ve nadie hasta que alguien intenta instalar.
    #>

    It 'la prueba lee el flujo de verdad: si no, no comprueba nada' {
        $script:Flujo.Length | Should -BeGreaterThan 1000
        $script:Flujo | Should -Match 'Compress-Archive'
        $script:Flujo | Should -Match 'action-gh-release'
    }

    It 'el zip que arma el flujo se llama como dice Get-NombrePaqueteZip' {
        $carpeta = [regex]::Match($script:Flujo, '\$carpeta\s*=\s*"([^"]+)"')
        $carpeta.Success | Should -BeTrue -Because 'sin encontrar el nombre, esta prueba no compara nada'

        # El flujo escribe "Cachivache-$version"; aqui se sustituye $version
        # por una etiqueta y se compara con lo que dicen los manifiestos.
        $delFlujo = $carpeta.Groups[1].Value.Replace('$version', 'v2.1.0')
        ($delFlujo + '.zip') | Should -BeExactly (Get-NombrePaqueteZip -Etiqueta 'v2.1.0')
        $delFlujo            | Should -BeExactly (Get-CarpetaDentroDelZip -Etiqueta 'v2.1.0')
    }

    It 'y el zip se arma a partir de esa misma carpeta' {
        # La otra mitad: que "$carpeta.zip" siga siendo el nombre del
        # archivo. Comprobar solo la variable dejaria pasar un
        # -DestinationPath distinto.
        $script:Flujo | Should -Match 'Compress-Archive -Path \$carpeta -DestinationPath "\$carpeta\.zip"'
    }

    It 'los manifiestos se generan DESPUES de armar el paquete' {
        # Antes serian los de un zip que todavia no existe, o los del de la
        # ejecucion anterior.
        $posPaquete = $script:Flujo.IndexOf('Compress-Archive')
        $posManifiestos = $script:Flujo.IndexOf('Publicar-Manifiestos.ps1')

        $posPaquete     | Should -BeGreaterThan 0
        $posManifiestos | Should -BeGreaterThan $posPaquete
    }

    It 'y ANTES de adjuntar nada' {
        $posManifiestos = $script:Flujo.IndexOf('Publicar-Manifiestos.ps1')
        $posAdjuntar    = $script:Flujo.IndexOf('action-gh-release')

        $posAdjuntar | Should -BeGreaterThan $posManifiestos
    }

    It 'el flujo comprueba lo que ha escrito antes de subirlo' {
        # Generar los manifiestos y no comprobarlos deja un paso verde que
        # sube un archivo que nadie ha mirado. Es la leccion de [DIS-02]: la
        # comprobacion no vale nada si recorre el mismo camino que lo que
        # comprueba, asi que el flujo vuelve a calcular el hash del zip y lo
        # compara con lo ESCRITO en los archivos.
        $script:Flujo | Should -Match 'ConvertFrom-Json'
        $script:Flujo | Should -Match 'Get-FileHash'
        $script:Flujo | Should -Match '-cne'
    }

    It 'el flujo adjunta los cuatro manifiestos a la version' {
        # Generarlos y no subirlos deja el punto entero sin efecto: los
        # archivos se quedan en el agente y se borran con el.
        #
        # Se mira SOLO el bloque files: del paso que publica, y no el flujo
        # entero. La primera version de esta prueba buscaba los nombres en
        # todo el texto y NO CAZO la mutacion que los quitaba de files:,
        # porque el paso que los comprueba los vuelve a nombrar. O sea:
        # pasaba con el bloque files: apuntando a otra cosa.
        $bloque = [regex]::Match($script:Flujo, '(?s)files: \|(.*?)\n\s*body: \|')
        $bloque.Success | Should -BeTrue -Because 'sin el bloque files:, esta prueba no comprueba nada'
        $adjuntos = $bloque.Groups[1].Value

        $identidad = Get-IdentidadPaquete
        foreach ($archivo in @(
            'packaging/{0}.json'                  -f $identidad.IdentificadorScoop
            'packaging/winget/{0}.yaml'           -f $identidad.IdentificadorWinget
            'packaging/winget/{0}.installer.yaml' -f $identidad.IdentificadorWinget
            ('packaging/winget/{0}.locale.{1}.yaml' -f $identidad.IdentificadorWinget, $identidad.Idioma)
        )) {
            $adjuntos | Should -Match ('(?m)^\s*' + [regex]::Escape($archivo) + '\s*$')
        }
    }

    It 'los manifiestos solo se generan cuando hay etiqueta' {
        # El disparo a mano usa la version "dev", que no es una etiqueta:
        # Get-VersionDesdeEtiqueta lanzaria y tumbaria una ejecucion que
        # existe justamente para probar el empaquetado sin publicar.
        $pos = $script:Flujo.IndexOf('Generar los manifiestos')
        $pos | Should -BeGreaterThan 0
        $script:Flujo.Substring($pos, 200) | Should -Match "startsWith\(github\.ref, 'refs/tags/'\)"
    }
}

Describe 'La costura con la version del programa' {

    It 'el repositorio que declaran los manifiestos es el de src/Core/Version.ps1' {
        # Version.ps1 ya tiene la direccion del repositorio y la usa el
        # programa. Dos copias de una URL es como se llega a que una apunte
        # a un sitio y la otra a otro, y quien instala por winget acabaria
        # en un repositorio que no es este.
        $texto = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/Core/Version.ps1')
        $url = [regex]::Match($texto, "RepositorioUrl\s*=\s*'([^']+)'")
        $url.Success | Should -BeTrue -Because 'sin encontrar la URL, esta prueba no compara nada'

        (Get-IdentidadPaquete).Repositorio | Should -BeExactly $url.Groups[1].Value
    }

    It 'todas las URL de los manifiestos cuelgan de ese repositorio' {
        $repo = (Get-IdentidadPaquete).Repositorio
        $urls = [regex]::Matches(
            ($script:WVersion + $script:WInstalador + $script:WLocale + $script:Scoop),
            'https://github\.com/[^\s",]+')

        $urls.Count | Should -BeGreaterThan 5 -Because 'si no hay URL, esta prueba no comprueba nada'
        foreach ($u in $urls) {
            # UrlEditor es el usuario, del que cuelga el repositorio.
            $u.Value | Should -BeLike ((Get-IdentidadPaquete).UrlEditor + '*')
        }
        $repo | Should -BeLike ((Get-IdentidadPaquete).UrlEditor + '/*')
    }
}

Describe 'Publicar-Manifiestos.ps1: de punta a punta' {
    <#
        Lo que las pruebas de formato no pueden ver: Format-... devuelve
        cadenas impecables y es QUIEN LAS ESCRIBE el que puede estropearlas.
        Con BOM, un YAML lo rechazan los validadores de winget-pkgs y un
        JSON lo lee mal ConvertFrom-Json en PowerShell 5.1.
    #>

    BeforeAll {
        $script:Temporal = Join-Path ([IO.Path]::GetTempPath()) ("paquetes-" + [Guid]::NewGuid().ToString('N'))
        $script:Interior = Join-Path $script:Temporal 'Cachivache-v9.9.9'
        New-Item -ItemType Directory -Path $script:Interior -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Interior 'Cachivache.ps1') -Value 'exit 0'

        $script:Zip = Join-Path $script:Temporal 'Cachivache-v9.9.9.zip'
        Compress-Archive -Path $script:Interior -DestinationPath $script:Zip

        $script:Salida = Join-Path $script:Temporal 'packaging'
        & (Join-Path (Join-Path $script:Raiz 'tools') 'Publicar-Manifiestos.ps1') `
            -Etiqueta 'v9.9.9' -Paquete $script:Zip -Destino $script:Salida | Out-Null

        $script:Escritos = @(Get-ChildItem -LiteralPath $script:Salida -Recurse -File)

        # Sin comentarios. El guion lleva un comentario que dice "y
        # WriteAllText, no Out-File" justo encima de la linea que lo cumple:
        # una prueba que buscara "Out-File" en el texto entero lo
        # encontraria ahi y fallaria con el codigo bien.
        $script:Guion = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (
                Join-Path (Join-Path $script:Raiz 'tools') 'Publicar-Manifiestos.ps1')),
            '(?s)<#.*?#>', '')
        $script:Guion = (($script:Guion -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Temporal -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'escribe los cuatro archivos' {
        $script:Escritos.Count | Should -Be 4
        @($script:Escritos.Name) | Should -Contain 'cachivache.json'
    }

    It 'ninguno lleva BOM' {
        # Este proyecto EXIGE BOM en todo .ps1 y .xaml, con su propia
        # invariante. Aqui es justo al reves, y quien venga detras vera el
        # $false de Publicar-Manifiestos.ps1 y pensara que es un descuido.
        foreach ($archivo in $script:Escritos) {
            $bytes = [IO.File]::ReadAllBytes($archivo.FullName)
            $bytes.Length | Should -BeGreaterThan 3
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
                Should -BeFalse -Because "$($archivo.Name) no puede empezar por el BOM de UTF-8"
        }
    }

    It 'ninguno lleva retornos de carro' {
        foreach ($archivo in $script:Escritos) {
            [IO.File]::ReadAllText($archivo.FullName) | Should -Not -Match "`r"
        }
    }

    It 'el hash escrito es el del zip de verdad, no uno de antes' {
        # El motivo entero del punto. Se recalcula aqui, por otro camino.
        $real = (Get-FileHash -LiteralPath $script:Zip -Algorithm SHA256).Hash

        $scoop = Get-Content -Raw -LiteralPath (Join-Path $script:Salida 'cachivache.json') | ConvertFrom-Json
        $scoop.hash | Should -BeExactly $real.ToLowerInvariant()

        $instalador = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path $script:Salida 'winget') 'FranciscoLopez.Cachivache.installer.yaml')
        $instalador | Should -MatchExactly ('InstallerSha256: ' + $real.ToUpperInvariant())
    }

    It 'los nombres de archivo son los que adjunta el flujo' {
        # Si el guion escribe un nombre y el flujo sube otro, la version
        # sale sin manifiesto y el paso queda verde.
        foreach ($archivo in $script:Escritos) {
            $script:Flujo | Should -Match ([regex]::Escape($archivo.Name))
        }
    }

    It 'un zip que no se llama como toca para la publicacion' {
        # El nombre del zip y el de los manifiestos tienen que ser el mismo
        # dato. Si dejan de serlo, se publicarian dos URL que devuelven 404.
        $otro = Join-Path $script:Temporal 'Cachivache.zip'
        Copy-Item -LiteralPath $script:Zip -Destination $otro
        {
            & (Join-Path (Join-Path $script:Raiz 'tools') 'Publicar-Manifiestos.ps1') `
                -Etiqueta 'v9.9.9' -Paquete $otro -Destino $script:Salida
        } | Should -Throw -ExpectedMessage '*404*'
    }

    It 'un paquete que no existe para la publicacion' {
        {
            & (Join-Path (Join-Path $script:Raiz 'tools') 'Publicar-Manifiestos.ps1') `
                -Etiqueta 'v9.9.9' -Paquete (Join-Path $script:Temporal 'no-existe.zip') -Destino $script:Salida
        } | Should -Throw
    }

    It 'el guion no acepta un hash por parametro' {
        # Un -Hash permitiria pasarle el de la version anterior copiado a
        # mano, que es exactamente el fallo que este punto cierra.
        $script:Guion.Length | Should -BeGreaterThan 500 -Because 'sin guion, esta prueba no comprueba nada'
        $script:Guion | Should -Not -Match '(?m)^\s*\[string\]\s*\$Hash'
        $script:Guion | Should -Match 'Get-FileHash'
    }

    It 'escribe con WriteAllText y sin BOM, no con Out-File' {
        # Con BOM, un YAML lo rechazan los validadores de winget-pkgs y un
        # JSON lo lee mal ConvertFrom-Json en PowerShell 5.1. Out-File, en
        # Windows, traduciria los saltos a CRLF.
        $script:Guion | Should -Match '\[Text\.UTF8Encoding\]::new\(\$false\)'
        $script:Guion | Should -Not -Match 'Out-File'
    }
}

Describe 'El README cuenta las dos formas nuevas de instalar' {

    BeforeAll {
        $script:Lectura = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'README.md')
    }

    It 'la prueba lee el README de verdad: si no, no comprueba nada' {
        $script:Lectura.Length | Should -BeGreaterThan 5000
        $script:Lectura | Should -Match '## Empezar'
    }

    It 'nombra winget y Scoop' {
        # Un canal de distribucion que nadie sabe que existe no distribuye
        # nada.
        $script:Lectura | Should -Match 'winget'
        $script:Lectura | Should -Match 'Scoop'
    }

    It 'y no promete que ya este en el repositorio de winget' {
        # Todavia no se ha enviado a microsoft/winget-pkgs. Un README que
        # diga "winget install Cachivache" manda al usuario a un comando que
        # falla.
        $script:Lectura | Should -Match 'packaging/README\.md|packaging\\README\.md'
    }
}

Describe 'Lo que se le entrega al usuario: cada cosa, con su motivo' {

    # EL FALLO QUE ENCONTRO ESTA PRUEBA, ensayando el empaquetado en local
    # antes de etiquetar la primera version.
    #
    # publicar.yml copiaba 'tools' al paquete, justo debajo de un
    # comentario que decia "ni pruebas, ni herramientas de desarrollo".
    # Iban dentro los cinco bancos, Mutar.ps1 y el ejecutor de pruebas.
    # Ninguno hace falta para ejecutar el programa, y dos son peligrosos
    # en manos de quien se baja un limpiador de disco: Banco-Pruebas.ps1
    # crea y borra arboles enteros -su cabecera dice "EJECUTAR SOLO EN UNA
    # MAQUINA VIRTUAL CON INSTANTANEA"- y Mutar.ps1 reescribe archivos
    # fuente a proposito.
    #
    # LA FORMA DE LA PRUEBA IMPORTA, y viene de la regla 8 del relevo. No
    # se prohibe 'tools' por su nombre: eso seria escribir la lista de los
    # fallos que ya conocemos. Se exige que CADA elemento del paquete este
    # declarado aqui con su motivo, asi que meter uno nuevo obliga a
    # justificarlo, y meter uno que sobra se ve al no encontrarle motivo.

    BeforeAll {
        $script:RaizPaq = Split-Path $PSScriptRoot -Parent
        $script:Publicar = [IO.File]::ReadAllText(
            (Join-Path (Join-Path (Join-Path $script:RaizPaq '.github') 'workflows') 'publicar.yml'))

        # Lo que se entrega, y por que. Si anyades algo al flujo, anyadelo
        # aqui con su motivo o la prueba se pone roja.
        $script:MotivoDeCadaCosa = @{
            'src'             = 'el programa entero: sin esto no hay nada que ejecutar'
            'assets'          = 'los iconos que carga la ventana al abrirse'
            'Cachivache.ps1'  = 'el punto de entrada, en modo ventana y en modo consola'
            'Cachivache.bat'  = 'el arranque para quien no quiera usar el .exe'
            'Cachivache.exe'  = 'el lanzador sin consola negra detras; lo compila el paso anterior'
            'README.md'       = 'que es esto y como se usa'
            'LICENSE'         = 'la licencia; distribuir sin ella no es legal'
            'SECURITY.md'     = 'que hace el programa con tus archivos, que es lo que el proyecto promete que se puede leer'
        }
    }

    It 'la prueba encuentra la lista de verdad: si no, no comprueba nada' {
        $script:Publicar | Should -Match "foreach \(\`$elemento in @\("
    }

    It 'todo lo que se empaqueta esta declarado con su motivo' {
        $m = [regex]::Match($script:Publicar, "(?s)foreach \(\`$elemento in @\((?<lista>.*?)\)\) \{")
        $m.Success | Should -BeTrue
        $entregado = @([regex]::Matches($m.Groups['lista'].Value, "'(?<e>[^']+)'") |
                       ForEach-Object { $_.Groups['e'].Value })
        @($entregado).Count | Should -BeGreaterThan 4 -Because 'si la lista sale vacia, esto no mira nada'

        $sinMotivo = @($entregado | Where-Object { -not $script:MotivoDeCadaCosa.ContainsKey($_) })
        ($sinMotivo -join ', ') | Should -BeNullOrEmpty -Because (
            'lo que se le entrega a un usuario se justifica una por una, o acaba viajando algo que nadie decidio mandar')

        # Y al reves: un motivo escrito para algo que ya no se entrega es
        # una lista que ha dejado de describir la realidad.
        $sinEntregar = @($script:MotivoDeCadaCosa.Keys | Where-Object { $entregado -notcontains $_ })
        ($sinEntregar -join ', ') | Should -BeNullOrEmpty
    }

    It 'no viaja NADA que cree, borre o reescriba archivos por su cuenta' {
        # La comprobacion de verdad: se mira lo que hay DENTRO de cada
        # carpeta entregada, no su nombre. Una carpeta puede llamarse
        # inofensiva y traer dentro un banco de pruebas.
        $m = [regex]::Match($script:Publicar, "(?s)foreach \(\`$elemento in @\((?<lista>.*?)\)\) \{")
        $entregado = @([regex]::Matches($m.Groups['lista'].Value, "'(?<e>[^']+)'") |
                       ForEach-Object { $_.Groups['e'].Value })

        $peligrosos = @()
        foreach ($e in $entregado) {
            $ruta = Join-Path $script:RaizPaq $e
            if (-not (Test-Path -LiteralPath $ruta)) { continue }
            if (-not (Get-Item -LiteralPath $ruta).PSIsContainer) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $ruta -Recurse -File)) {
                if ($f.Name -match '\.Tests\.ps1$' -or $f.Name -match '^(Banco-|Mutar|Probar|Cobertura)') {
                    $peligrosos += ('{0} trae {1}' -f $e, $f.Name)
                }
            }
        }
        ($peligrosos -join ' // ') | Should -BeNullOrEmpty -Because (
            'quien se baja un limpiador no debe recibir bancos de pruebas ni el mutador')
    }

    It 'y tampoco viajan las pruebas ni la configuracion del repositorio' {
        $m = [regex]::Match($script:Publicar, "(?s)foreach \(\`$elemento in @\((?<lista>.*?)\)\) \{")
        $entregado = @([regex]::Matches($m.Groups['lista'].Value, "'(?<e>[^']+)'") |
                       ForEach-Object { $_.Groups['e'].Value })
        foreach ($prohibido in @('tests', '.github', 'pruebas', 'docs')) {
            $entregado | Should -Not -Contain $prohibido
        }
    }
}
