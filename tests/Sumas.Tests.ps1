<#
    El formato de las sumas SHA-256 que se publican. [DIS-02].

    Un archivo de sumas no es un texto informativo: lo leen otras
    herramientas. `sha256sum -c`, winget y Scoop esperan una forma exacta, y
    los cuatro descuidos que la rompen -mayusculas, un solo espacio, saltos
    CRLF y el BOM- NO SE VEN mirando el archivo. Se ven aqui.

    El peor de los cuatro es el BOM, y merece la pena decir por que: hace que
    falle solo la PRIMERA linea. Un archivo con dos entradas validaria la
    segunda y no la primera, que es exactamente la pinta de un paquete
    adulterado.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path $script:Raiz 'tools') 'Sumas.ps1')

    # Dos hashes de verdad, para no probar el formato con cadenas cortas que
    # esconderian un recorte.
    $script:Uno = 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
    $script:Dos = '9F86D081884C7D659A2FEAA0C55AD015A3BF4F1B2B0B822CD15D6C15B0F00A08'

    $script:Entradas = @(
        @{ Nombre = 'Cachivache-v2.1.0.zip'; Hash = $script:Uno }
        @{ Nombre = 'Cachivache.exe';        Hash = $script:Dos }
    )
}

Describe 'Format-SumasSha256: la forma que espera sha256sum' {

    BeforeAll {
        $script:Texto  = Format-SumasSha256 -Entradas $script:Entradas
        $script:Lineas = $script:Texto.TrimEnd("`n") -split "`n"
    }

    It 'la prueba genera algo: si no, no comprueba nada' {
        $script:Texto.Length | Should -BeGreaterThan 100
        $script:Lineas.Count | Should -Be 2
    }

    It 'una linea por archivo, con su nombre' {
        $script:Lineas[0] | Should -BeLike '*Cachivache-v2.1.0.zip'
        $script:Lineas[1] | Should -BeLike '*Cachivache.exe'
    }

    It 'el hash va en minusculas' {
        # Get-FileHash lo devuelve en MAYUSCULAS y sha256sum escribe en
        # minusculas. A ojo da igual; con una herramienta, no.
        #
        # Se mira SOLO los 64 primeros caracteres de cada linea. La primera
        # version de esta prueba buscaba mayusculas en el texto entero y
        # fallaba por la C de "Cachivache": habria obligado a poner el
        # nombre del archivo en minusculas para callarla, que es justo lo
        # que no queremos.
        foreach ($linea in $script:Lineas) {
            $linea.Substring(0, 64) | Should -MatchExactly '^[0-9a-f]{64}$'
        }
        $script:Lineas[0] | Should -BeLike ($script:Uno.ToLowerInvariant() + '*')
    }

    It 'el separador son DOS espacios exactos' {
        foreach ($linea in $script:Lineas) {
            $linea | Should -Match '^[0-9a-f]{64}  \S'
            # Ni uno ni tres: se comprueba el numero exacto, porque "hay al
            # menos dos" pasaria con tres.
            ($linea -replace '^[0-9a-f]{64}( +).*$', '$1').Length | Should -Be 2
        }
    }

    It 'no hay retornos de carro' {
        # Un \r sobrante se cuela DENTRO del nombre del archivo y entonces no
        # casa ninguna linea.
        $script:Texto | Should -Not -Match "`r"
    }

    It 'termina en salto de linea' {
        $script:Texto.EndsWith("`n") | Should -BeTrue -Because 'sha256sum se queja de una ultima linea sin terminar'
    }

    It 'sin entradas devuelve texto vacio, no lanza' {
        { Format-SumasSha256 -Entradas @() } | Should -Not -Throw
        Format-SumasSha256 -Entradas @()   | Should -BeNullOrEmpty
        Format-SumasSha256 -Entradas $null | Should -BeNullOrEmpty
    }

    It 'un nombre con ruta se rechaza' {
        # Quien verifica lo hace desde la carpeta de la descarga: una ruta
        # del agente de integracion continua ahi no existe, y la linea no
        # casaria nunca.
        { Format-SumasSha256 -Entradas @(@{ Nombre = 'D:\a\salida\Cachivache.exe'; Hash = $script:Uno }) } |
            Should -Throw -ExpectedMessage '*lleva ruta*'
    }

    It 'una entrada sin hash o sin nombre se rechaza' {
        { Format-SumasSha256 -Entradas @(@{ Nombre = 'x.zip'; Hash = '' }) } | Should -Throw
        { Format-SumasSha256 -Entradas @(@{ Nombre = '';      Hash = $script:Uno }) } | Should -Throw
    }
}

Describe 'Format-TablaSumas: las mismas sumas en el cuerpo de la version' {

    BeforeAll {
        $script:Tabla = Format-TablaSumas -Entradas $script:Entradas
    }

    It 'es una tabla de Markdown con cabecera' {
        $script:Tabla | Should -Match '\|\s*Archivo\s*\|'
        $script:Tabla | Should -Match '\|---\|---\|'
    }

    It 'lleva los dos archivos y sus dos sumas' {
        $script:Tabla | Should -BeLike '*Cachivache-v2.1.0.zip*'
        $script:Tabla | Should -BeLike '*Cachivache.exe*'
        $script:Tabla | Should -BeLike ('*' + $script:Uno.ToLowerInvariant() + '*')
        $script:Tabla | Should -BeLike ('*' + $script:Dos.ToLowerInvariant() + '*')
    }

    It 'dice lo mismo que el archivo de sumas' {
        # Son dos representaciones del mismo dato en dos sitios distintos, y
        # eso es exactamente como empiezan las divergencias. Si alguna vez
        # dicen cosas distintas, quien compare a ojo y quien compare con la
        # herramienta llegaran a conclusiones opuestas.
        $texto = Format-SumasSha256 -Entradas $script:Entradas
        foreach ($e in $script:Entradas) {
            $suma = ([string]$e.Hash).ToLowerInvariant()
            $texto        | Should -BeLike ('*' + $suma + '*')
            $script:Tabla | Should -BeLike ('*' + $suma + '*')
        }
    }

    It 'sin entradas devuelve vacio, no lanza' {
        { Format-TablaSumas -Entradas $null } | Should -Not -Throw
        Format-TablaSumas -Entradas @() | Should -BeNullOrEmpty
    }
}

Describe 'Test-SumaSha256Valida' {

    It 'acepta un SHA-256 de verdad' {
        Test-SumaSha256Valida -Suma $script:Uno | Should -BeTrue
        Test-SumaSha256Valida -Suma $script:Uno.ToLowerInvariant() | Should -BeTrue
    }

    It 'rechaza <Que>' -ForEach @(
        @{ Que = 'uno corto';        Suma = 'e3b0c442' }
        @{ Que = 'uno largo';        Suma = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a' }
        @{ Que = 'algo no hex';      Suma = 'z3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' }
        @{ Que = 'con un espacio';   Suma = 'e3b0c442 8fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' }
        @{ Que = 'una cadena vacia'; Suma = '' }
    ) {
        Test-SumaSha256Valida -Suma $Suma | Should -BeFalse
    }

    It 'con nulo dice que no, y no lanza' {
        # Publicar una suma mal es peor que no publicarla: quien la comprueba
        # y no le cuadra concluye que el paquete esta adulterado.
        { Test-SumaSha256Valida -Suma $null } | Should -Not -Throw
        Test-SumaSha256Valida -Suma $null | Should -BeFalse
    }
}

Describe 'DIS-02: el flujo de publicacion firma lo que sube' {
    <#
        Las tres formas que tiene esto de quedarse a medias sin que falle
        nada: que se calculen las sumas y no se adjunten, que se calculen
        ANTES de armar el paquete -y entonces son de otra cosa-, y que
        nadie las verifique nunca hasta que lo haga un usuario.
    #>

    BeforeAll {
        $script:Flujo = Get-Content -Raw -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) '.github/workflows/publicar.yml')
    }

    It 'la prueba lee el flujo de verdad: si no, no comprueba nada' {
        $script:Flujo.Length | Should -BeGreaterThan 1000
        $script:Flujo | Should -Match 'action-gh-release'
    }

    It 'las sumas se calculan y ademas se adjuntan a la version' {
        # Calcularlas y no subirlas deja un paso verde que no publica nada.
        $script:Flujo | Should -Match 'Publicar-Sumas\.ps1'
        $script:Flujo | Should -Match 'SHA256SUMS\.txt'
    }

    It 'se calculan DESPUES de armar el paquete' {
        # Antes serian las sumas de un zip que todavia no existe, o del de la
        # ejecucion anterior.
        $posPaquete = $script:Flujo.IndexOf('Compress-Archive')
        $posSumas   = $script:Flujo.IndexOf('Publicar-Sumas.ps1')

        $posPaquete | Should -BeGreaterThan 0
        $posSumas   | Should -BeGreaterThan $posPaquete
    }

    It 'y ANTES de adjuntar nada' {
        $posSumas    = $script:Flujo.IndexOf('Publicar-Sumas.ps1')
        $posAdjuntar = $script:Flujo.IndexOf('action-gh-release')

        $posAdjuntar | Should -BeGreaterThan $posSumas
    }

    It 'el archivo de sumas se escribe SIN BOM y sin traducir los saltos' {
        # Lo unico de todo esto que las pruebas de formato no pueden ver:
        # Format-SumasSha256 devuelve una cadena impecable y es QUIEN LA
        # ESCRIBE el que puede estropearla.
        #
        # Dos formas, las dos silenciosas:
        #   - UTF8Encoding($true) pone BOM, y el BOM hace que falle solo la
        #     PRIMERA linea. Un archivo de dos entradas validaria la segunda
        #     y no la primera: la pinta exacta de un paquete adulterado.
        #   - Out-File traduce los saltos a CRLF en Windows, y el \r sobrante
        #     se cuela dentro del nombre del archivo.
        #
        # Y hay una trampa anyadida: este proyecto EXIGE BOM en todo .ps1 y
        # .xaml, con su propia invariante. Quien venga detras y vea aqui un
        # $false pensara que es un descuido y lo "arreglara".
        $guion = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools') 'Publicar-Sumas.ps1')

        $guion | Should -Match '\[Text\.UTF8Encoding\]::new\(\$false\)' -Because 'con BOM falla la primera linea, y solo la primera'
        $guion | Should -Not -Match 'Out-File\s+.*Destino' -Because 'Out-File traduce los saltos a CRLF'
    }

    It 'el propio flujo verifica las sumas con la herramienta de verdad' {
        # Un archivo con BOM, con CRLF o con un solo espacio se LEE bien y no
        # valida. Si nadie ejecuta sha256sum -c en la publicacion, el primero
        # en descubrirlo es un usuario, y lo que concluye es que el paquete
        # esta adulterado.
        $script:Flujo | Should -Match 'sha256sum -c'
    }

    It 'y lo verifica con --strict' {
        # Comprobado a mano contra la herramienta: sin --strict, un archivo
        # de sumas con BOM da "WARNING: 1 line is improperly formatted",
        # verifica el resto y SALE CON CODIGO 0. El paso quedaria verde
        # habiendo publicado un .zip cuya suma no ha comprobado nadie.
        #
        # Es la trampa entera de este punto: la comprobacion que se anyade
        # para que no pase algo, pasando por alto justo ese algo.
        $script:Flujo | Should -Match 'sha256sum -c --strict'
    }
}
