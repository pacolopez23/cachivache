<#
    El arnes de mutacion. [VAL-02].

    Probar la herramienta que se usa para probar suena a vuelta de tuerca, y
    no lo es: esta se rompio DOS VECES en una sola sesion, siempre igual. El
    sustituidor no encontraba el texto, no decia nada, y la suite pasaba. El
    paso que existe para no fiarse de que una prueba pasa, dio por buena una
    prueba porque pasaba. La segunda vez fueron cuatro mutaciones seguidas.

    Lo que se protege aqui es una sola idea: NO MUTAR NADA TIENE QUE SER
    RUIDOSO, porque el sintoma de no mutar nada es identico al de una prueba
    impecable.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path $script:Raiz 'tools') 'Mutar.ps1')
}

Describe 'Get-TextoMutado' {

    It 'sustituye cuando el texto aparece una vez' {
        Get-TextoMutado -Texto 'uno dos tres' -Buscar 'dos' -Poner 'DOS' | Should -Be 'uno DOS tres'
    }

    It 'LANZA si el texto no aparece' {
        # El fallo entero que motiva este archivo.
        { Get-TextoMutado -Texto 'uno dos tres' -Buscar 'cuatro' -Poner 'x' } |
            Should -Throw -ExpectedMessage '*no se ha mutado nada*'
    }

    It 'LANZA si el texto aparece mas de una vez' {
        # Mutar "la primera" es mutar un sitio que no se ha elegido: la
        # prueba que falle despues no dice lo que uno cree.
        { Get-TextoMutado -Texto 'dos y dos' -Buscar 'dos' -Poner 'x' } |
            Should -Throw -ExpectedMessage '*Aparece 2 veces*'
    }

    It 'admite BORRAR: poner cadena vacia es una mutacion valida' {
        # Quitar una linea entera -".que prueba se entera si suprimo esta
        # comprobacion?"- es de las mutaciones mas utiles que hay. La
        # primera version la rechazaba por ser cadena vacia, y dos
        # mutaciones de [ARQ-03] no llegaron a ejecutarse.
        Get-TextoMutado -Texto 'uno dos tres' -Buscar ' dos' -Poner '' | Should -Be 'uno tres'
    }

    It 'LANZA si la mutacion no cambia nada' {
        { Get-TextoMutado -Texto 'uno dos' -Buscar 'dos' -Poner 'dos' } |
            Should -Throw -ExpectedMessage '*no cambia nada*'
    }

    It 'compara literalmente, no como expresion regular' {
        # Lo que se muta es codigo lleno de $, [, ] y (. Si esto tratara el
        # texto como expresion regular, cada mutacion habria que escaparla a
        # mano, y ahi es donde se falla.
        $codigo = 'if ($hojas.Count -lt 3) { return $null }'
        Get-TextoMutado -Texto $codigo -Buscar '$hojas.Count -lt 3' -Poner '$false' |
            Should -Be 'if ($false) { return $null }'
    }

    It 'no se le escapa una diferencia de mayusculas' {
        # Ordinal, no OrdinalIgnoreCase: en PowerShell $Cual y $cual son la
        # misma variable, pero en una prueba de texto sobre el codigo la
        # diferencia importa, y "casi lo encuentra" es no encontrarlo.
        { Get-TextoMutado -Texto 'return $Cual' -Buscar 'return $cual' -Poner 'x' } |
            Should -Throw -ExpectedMessage '*no se ha mutado nada*'
    }

    It 'con nulos o vacios LANZA, no devuelve el texto tal cual' {
        # Devolver el original seria exactamente el fallo original: una
        # mutacion que no muta y no se queja.
        { Get-TextoMutado -Texto $null -Buscar 'x' -Poner 'y' }  | Should -Throw
        { Get-TextoMutado -Texto 'algo' -Buscar $null -Poner 'y' } | Should -Throw
        { Get-TextoMutado -Texto 'algo' -Buscar '' -Poner 'y' }    | Should -Throw
    }
}

Describe 'Invoke-Mutacion' {

    BeforeEach {
        $script:Archivo = Join-Path ([IO.Path]::GetTempPath()) ("mutar-{0}.ps1" -f [guid]::NewGuid())
        [IO.File]::WriteAllText($script:Archivo, "uno`ndos`ntres`n", [Text.UTF8Encoding]::new($true))
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Archivo) { Remove-Item -LiteralPath $script:Archivo -Force }
    }

    It 'el archivo esta mutado DENTRO del bloque' {
        # La caja es una tabla hash a proposito, no una variable suelta. El
        # bloque se ejecuta en otro ambito, asi que asignar una variable
        # dentro no se ve fuera -las dos primeras versiones de esta prueba
        # fallaron asi, una con $script: y otra con GetNewClosure-. Una tabla
        # hash es una referencia: lo que se le mete dentro sigue ahi.
        $caja = @{}
        $ruta = $script:Archivo

        Invoke-Mutacion -Ruta $ruta -Buscar 'dos' -Poner 'DOS' -Prueba {
            $caja.Texto = [IO.File]::ReadAllText($ruta)
        }.GetNewClosure()

        # Contenido exacto, no un comodin: -BeLike NO distingue mayusculas,
        # asi que "no contiene 'dos'" pasaba con "DOS" dentro y no comprobaba
        # nada.
        $caja.Texto | Should -Be "uno`nDOS`ntres`n"
    }

    It 'y restaurado despues' {
        Invoke-Mutacion -Ruta $script:Archivo -Buscar 'dos' -Poner 'DOS' -Prueba { }
        [IO.File]::ReadAllText($script:Archivo) | Should -Be "uno`ndos`ntres`n"
    }

    It 'restaurado tambien si el bloque LANZA' {
        # Sin el finally, una prueba que revienta deja el repositorio mutado,
        # que es peor que no haber mutado: a partir de ahi todo lo que se
        # ejecute mide otra cosa.
        { Invoke-Mutacion -Ruta $script:Archivo -Buscar 'dos' -Poner 'DOS' -Prueba { throw 'ay' } } |
            Should -Throw
        [IO.File]::ReadAllText($script:Archivo) | Should -Be "uno`ndos`ntres`n"
    }

    It 'el BOM sobrevive a la mutacion' {
        # Si la mutacion se comiera el BOM, fallaria la invariante de
        # codificacion y la prueba fallaria por un motivo que NO es el que se
        # esta comprobando. Justo lo que esto viene a evitar.
        Invoke-Mutacion -Ruta $script:Archivo -Buscar 'dos' -Poner 'DOS' -Prueba {
            $b = [IO.File]::ReadAllBytes($script:Archivo)
            $b[0] | Should -Be 239
        }
        [IO.File]::ReadAllBytes($script:Archivo)[0] | Should -Be 239
    }

    It 'no toca el archivo si la mutacion no vale' {
        # Se valida ANTES de escribir: un texto que no aparece no puede
        # dejar el archivo a medias.
        { Invoke-Mutacion -Ruta $script:Archivo -Buscar 'cuatro' -Poner 'x' -Prueba { } } |
            Should -Throw -ExpectedMessage '*no se ha mutado nada*'
        [IO.File]::ReadAllText($script:Archivo) | Should -Be "uno`ndos`ntres`n"
    }

    It 'lanza si el archivo no existe' {
        { Invoke-Mutacion -Ruta 'C:\no\existe.ps1' -Buscar 'a' -Poner 'b' -Prueba { } } | Should -Throw
    }
}
