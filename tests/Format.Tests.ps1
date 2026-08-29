<#
    Pruebas del formato de tamaños, tiempos y rutas para mostrar.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'Format-Tamano' {

    It 'formatea <Bytes> como algo que contiene "<Esperado>"' -ForEach @(
        @{ Bytes = 0;            Esperado = 'B' }
        @{ Bytes = 512;          Esperado = 'B' }
        @{ Bytes = 2048;         Esperado = 'KB' }
        @{ Bytes = 5242880;      Esperado = 'MB' }
        @{ Bytes = 3221225472;   Esperado = 'GB' }
        @{ Bytes = 2199023255552;Esperado = 'TB' }
    ) { Format-Tamano $Bytes | Should -BeLike "*$Esperado*" }

    It 'nunca devuelve un tamanyo negativo' {
        Format-Tamano -500 | Should -Be '0 B'
    }
}

Describe 'ConvertFrom-NumeroLocal (C-04)' {
    <#
        Antes de esta corrección, "-replace '.',''" trataba el punto
        siempre como separador de miles. En Windows en inglés,
        "vssadmin list shadowstorage" devuelve "15.5 GB" (punto decimal) y
        el programa lo convertia en 155 GB.
    #>

    It 'interpreta "15.5" (ingles, decimal) como 15.5, NO como 155' {
        ConvertFrom-NumeroLocal '15.5' | Should -Be 15.5
    }

    It 'interpreta "15,5" (espanyol, decimal) como 15.5' {
        ConvertFrom-NumeroLocal '15,5' | Should -Be 15.5
    }

    It 'interpreta "15,500" (ingles, miles) como 15500' {
        ConvertFrom-NumeroLocal '15,500' | Should -Be 15500
    }

    It 'interpreta "1.234.567" (espanyol, miles repetidos) como 1234567' {
        ConvertFrom-NumeroLocal '1.234.567' | Should -Be 1234567
    }

    It 'interpreta "1.234,56" (espanyol, miles y decimal) como 1234.56' {
        ConvertFrom-NumeroLocal '1.234,56' | Should -Be 1234.56
    }

    It 'interpreta "1,234.56" (ingles, miles y decimal) como 1234.56' {
        ConvertFrom-NumeroLocal '1,234.56' | Should -Be 1234.56
    }

    It 'interpreta un numero sin separadores' {
        ConvertFrom-NumeroLocal '155' | Should -Be 155
    }

    It 'devuelve 0 con texto vacio o no numerico' {
        ConvertFrom-NumeroLocal ''    | Should -Be 0
        ConvertFrom-NumeroLocal 'xyz' | Should -Be 0
    }
}

Describe 'ConvertTo-BytesConUnidad' {

    It 'convierte <Numero> <Unidad> a los bytes correctos' -ForEach @(
        @{ Numero = 15.5; Unidad = 'GB'; Esperado = 15.5 * 1GB }
        @{ Numero = 500;  Unidad = 'MB'; Esperado = 500 * 1MB }
        @{ Numero = 2;    Unidad = 'TB'; Esperado = 2 * 1TB }
        @{ Numero = 100;  Unidad = 'KB'; Esperado = 100 * 1KB }
    ) { ConvertTo-BytesConUnidad -Numero $Numero -Unidad $Unidad | Should -Be $Esperado }

    It 'no revienta con una unidad desconocida' {
        ConvertTo-BytesConUnidad -Numero 5 -Unidad 'PB' | Should -Be 0
    }
}

Describe 'Get-RutaCorta' {

    It 'sustituye el perfil del usuario por una virgulilla' {
        $env:USERPROFILE = 'C:\Users\prueba'
        Get-RutaCorta 'C:\Users\prueba\Documents\x' | Should -Be '~\Documents\x'
    }
}

Describe 'Get-RutaElidida' {

    It 'no toca las rutas que ya caben' {
        Get-RutaElidida 'C:\corta' 70 | Should -Be 'C:\corta'
    }

    It 'recorta por el centro las rutas largas' {
        $larga = 'C:\' + ('carpeta\' * 20) + 'archivo.txt'
        $resultado = Get-RutaElidida $larga 40
        $resultado.Length | Should -BeLessOrEqual 41
        $resultado | Should -BeLike '*...*'
    }
}

Describe 'Format-Antiguedad' {

    It 'describe fechas recientes y lejanas' {
        Format-Antiguedad (Get-Date)                  | Should -Be 'hoy'
        Format-Antiguedad (Get-Date).AddDays(-1)      | Should -Be 'ayer'
        Format-Antiguedad (Get-Date).AddDays(-10)     | Should -BeLike '*10 días*'
        Format-Antiguedad (Get-Date).AddDays(-400)    | Should -BeLike '*año*'
    }
}

Describe 'USO-07: la linea de progreso demuestra que el programa sigue vivo' {

    <#
        La barra avanza POR MODULO TERMINADO. El modulo de duplicados puede
        estar cinco minutos con la barra clavada en el 38% y sin un solo
        numero moviendose, y para el usuario eso no se distingue de un
        cuelgue. Lo razonable ante un programa colgado es matarlo, a mitad
        de una limpieza.

        El arreglo no es una barra mas fina: son dos datos que SE MUEVEN.
        Y esta en una funcion pura para poder comprobarlo, porque el
        temporizador de WPF no arranca en las pruebas.
    #>

    It 'dice que modulo va, por donde va y que esta haciendo' {
        $t = Format-ProgresoAnalisis -Modulo 'Duplicados' -Mensaje 'Comparando contenido' -Indice 8 -Total 21
        $t | Should -BeLike '*Duplicados*'
        $t | Should -BeLike '*8 de 21*'
        $t | Should -BeLike '*Comparando contenido*'
    }

    It 'el contador va PEGADO al modulo, no al mensaje' {
        # Los modulos traen su propia cuenta. Pegar la nuestra al mensaje
        # producia "grupo 3 de 47 (8 de 21)": dos contadores seguidos que
        # no hay quien lea. Se vio mirando la linea escrita, no al
        # pensarla.
        $t = Format-ProgresoAnalisis -Modulo 'Duplicados' -Indice 8 -Total 21 `
                -Mensaje 'Comparando contenido: grupo 3 de 47'
        $t | Should -BeLike 'Duplicados (8 de 21)*'
        $t | Should -Not -BeLike '*47 (8 de 21)*'
    }

    It 'no repite el nombre del modulo cuando el mensaje es el mismo' {
        # Al arrancar un modulo los dos valen lo mismo y quedaria
        # "Duplicados (8 de 21) - Duplicados".
        $t = Format-ProgresoAnalisis -Modulo 'Duplicados' -Mensaje 'Duplicados' -Indice 8 -Total 21
        @([regex]::Matches($t, 'Duplicados')).Count | Should -Be 1
    }

    It 'anyade el tiempo transcurrido, que avanza aunque el modulo no encuentre nada' {
        $t = Format-ProgresoAnalisis -Modulo 'Duplicados' -Indice 8 -Total 21 `
                -Transcurrido ([TimeSpan]::FromSeconds(134))
        $t | Should -BeLike '*2 min*'
    }

    It 'anyade los elementos encontrados' {
        $t = Format-ProgresoAnalisis -Modulo 'Buscando' -Indice 3 -Total 21 -Elementos 1203
        $t | Should -BeLike '*1203 elementos*'
    }

    It 'los dos juntos, que es el caso que importa' {
        # "Duplicados (8 de 21) - 2 min 14 s - 1203 elementos": pase lo que
        # pase, algo se mueve.
        $t = Format-ProgresoAnalisis -Modulo 'Duplicados' -Indice 8 -Total 21 `
                -Transcurrido ([TimeSpan]::FromSeconds(134)) -Elementos 1203
        $t | Should -BeLike '*Duplicados*'
        $t | Should -BeLike '*8 de 21*'
        $t | Should -BeLike '*min*'
        $t | Should -BeLike '*1203*'
    }

    It 'el tiempo no aparece durante el primer segundo' {
        # Cambia tan rapido que parpadea, y con un modulo corto no aporta.
        $t = Format-ProgresoAnalisis -Modulo 'Empezando' -Indice 1 -Total 21 `
                -Transcurrido ([TimeSpan]::FromMilliseconds(300))
        $t | Should -Not -BeLike '*s*·*'
    }

    It 'sin elementos no ensenya un cero desanimante' {
        $t = Format-ProgresoAnalisis -Modulo 'Buscando' -Indice 1 -Total 21 -Elementos 0
        $t | Should -Not -BeLike '*0 elementos*'
    }

    It 'singular y plural' {
        (Format-ProgresoAnalisis -Modulo 'x' -Elementos 1)  | Should -BeLike '*1 elemento*'
        (Format-ProgresoAnalisis -Modulo 'x' -Elementos 2)  | Should -BeLike '*2 elementos*'
    }

    It 'sin nada que decir no revienta ni deja separadores sueltos' {
        $t = Format-ProgresoAnalisis
        { Format-ProgresoAnalisis } | Should -Not -Throw
        $t | Should -Be 'Analizando'
    }
}
