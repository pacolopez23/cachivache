<#
    Las decisiones del banco de pruebas. [VAL-02].

    Se prueba Banco-Decisiones.ps1, NO Banco-Pruebas.ps1: el segundo crea y
    borra archivos, asi que dot-sourcearlo desde aqui seria ejecutarlo. Esa
    separacion es justo lo que permite que esto exista.

    Y aqui hay un archivo entero para cuatro funciones pequenyas por un
    motivo: Test-DentroDeRaiz es lo unico que separa "-Quitar borra el
    banco" de "-Quitar borra la carpeta Documentos". Un fallo aqui no da un
    resultado raro: se lleva archivos del usuario.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path $script:Raiz 'tools') 'Banco-Decisiones.ps1')

    $script:Banco = 'C:\Users\quien\Documents\Banco-Cachivache'
}

Describe 'Test-DentroDeRaiz: lo que impide que el banco borre fuera de si mismo' {

    It 'la propia raiz esta dentro' {
        Test-DentroDeRaiz -Ruta $script:Banco -Raiz $script:Banco | Should -BeTrue
    }

    It 'algo debajo esta dentro' {
        Test-DentroDeRaiz -Ruta "$script:Banco\01-temporales\uno.bak" -Raiz $script:Banco | Should -BeTrue
    }

    It 'la carpeta de encima NO esta dentro' {
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\Documents' -Raiz $script:Banco | Should -BeFalse
    }

    It 'una carpeta hermana con el mismo principio NO esta dentro' {
        # El fallo clasico de comparar por prefijo. Aqui costaria la carpeta
        # entera de al lado.
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\Documents\Banco-Cachivache-2\algo.txt' `
                          -Raiz $script:Banco | Should -BeFalse
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\Documents\Banco-CachivacheViejo' `
                          -Raiz $script:Banco | Should -BeFalse
    }

    It 'otra unidad NO esta dentro' {
        Test-DentroDeRaiz -Ruta 'D:\Banco-Cachivache\algo.bak' -Raiz $script:Banco | Should -BeFalse
    }

    It 'las mayusculas no cambian el veredicto' {
        # En Windows las rutas no distinguen, y comparar con distincion
        # habria dado "esta fuera" a algo que si esta dentro: el guion
        # habria lanzado en mitad del borrado.
        Test-DentroDeRaiz -Ruta 'C:\USERS\QUIEN\DOCUMENTS\BANCO-CACHIVACHE\uno.bak' `
                          -Raiz $script:Banco | Should -BeTrue
    }

    It 'el prefijo de ruta larga no cambia el veredicto' {
        # El banco crea la ruta larga con \\?\. Sin normalizarlo, esas rutas
        # parecerian estar fuera de su propia raiz y -Quitar fallaria justo
        # en el cebo mas importante. Es la leccion de [COR-02].
        Test-DentroDeRaiz -Ruta "\\?\$script:Banco\02-ruta-larga\x.bak" -Raiz $script:Banco |
            Should -BeTrue
        Test-DentroDeRaiz -Ruta "$script:Banco\02-ruta-larga\x.bak" -Raiz "\\?\$script:Banco" |
            Should -BeTrue
    }

    It 'una barra final no cambia el veredicto' {
        Test-DentroDeRaiz -Ruta "$script:Banco\uno.bak" -Raiz "$script:Banco\" | Should -BeTrue
    }

    It 'con nulo o vacio dice que NO, y no lanza' {
        # El caso peligroso: si un nulo diera "si", el borrado seguiria.
        { Test-DentroDeRaiz -Ruta $null -Raiz $script:Banco } | Should -Not -Throw
        Test-DentroDeRaiz -Ruta $null -Raiz $script:Banco | Should -BeFalse
        Test-DentroDeRaiz -Ruta "$script:Banco\uno.bak" -Raiz $null | Should -BeFalse
        Test-DentroDeRaiz -Ruta '' -Raiz '' | Should -BeFalse
        Test-DentroDeRaiz -Ruta 'C:\lo-que-sea' -Raiz '   ' | Should -BeFalse
    }

    It 'una raiz que se queda en nada tras normalizar dice que NO' {
        # "\" recortado por los dos lados no es una raiz: es la unidad
        # entera. Si esto dijera "si", -Quitar borraria el disco.
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\algo' -Raiz '\' | Should -BeFalse
    }
}

Describe 'Get-MotivoNoQuitarBanco: los tres candados del borrado' {

    It 'con la raiz correcta y existiendo, no hay motivo' {
        Get-MotivoNoQuitarBanco -Raiz $script:Banco -Existe | Should -BeNullOrEmpty
    }

    It 'si la ruta no termina en el nombre del banco, se para' {
        # El caso que de verdad da miedo: el calculo se fue a Documentos.
        $motivo = Get-MotivoNoQuitarBanco -Raiz 'C:\Users\quien\Documents' -Existe
        $motivo | Should -Not -BeNullOrEmpty
        $motivo | Should -Match 'No se borra nada'
    }

    It 'si esta demasiado arriba, se para' -ForEach @(
        @{ Ruta = 'C:\' }, @{ Ruta = 'C:\Banco-Cachivache' }, @{ Ruta = '\' }
    ) {
        Get-MotivoNoQuitarBanco -Raiz $Ruta -Existe | Should -Not -BeNullOrEmpty
    }

    It 'si no existe, lo dice en vez de callarse' {
        Get-MotivoNoQuitarBanco -Raiz $script:Banco | Should -Match 'No hay ningun banco'
    }

    It 'con nulo o vacio se para, y no lanza' {
        { Get-MotivoNoQuitarBanco -Raiz $null -Existe } | Should -Not -Throw
        Get-MotivoNoQuitarBanco -Raiz $null -Existe | Should -Not -BeNullOrEmpty
        Get-MotivoNoQuitarBanco -Raiz '' -Existe    | Should -Not -BeNullOrEmpty
    }

    It 'el prefijo de ruta larga no despista al candado' {
        Get-MotivoNoQuitarBanco -Raiz "\\?\$script:Banco" -Existe | Should -BeNullOrEmpty
    }
}

Describe 'Get-MotivoNoMontarBanco: la red antes de crear nada' {

    It 'en una VM y con la carpeta libre, adelante' {
        Get-MotivoNoMontarBanco -PareceVirtual | Should -BeNullOrEmpty
    }

    It 'fuera de una VM se para y explica por que' {
        $motivo = Get-MotivoNoMontarBanco
        $motivo | Should -Match 'maquina virtual'
        $motivo | Should -Match 'AunqueNoSeaVirtual' -Because 'un "no" sin salida solo ensenya a buscar rodeos'
    }

    It 'fuera de una VM pero forzado, adelante' {
        Get-MotivoNoMontarBanco -Forzado | Should -BeNullOrEmpty
    }

    It 'con un banco ya montado se para' {
        Get-MotivoNoMontarBanco -PareceVirtual -RaizOcupada | Should -Match 'Quitalo primero'
    }

    It 'si no es una VM Y ademas hay banco, manda el motivo de la VM' {
        # El orden importa: el primer motivo que se da tiene que ser el que
        # el usuario necesita para decidir, y "esto no es una VM" es mas
        # grave que "ya hay una carpeta".
        Get-MotivoNoMontarBanco -RaizOcupada | Should -Match 'maquina virtual'
    }
}

Describe 'Test-PareceMaquinaVirtual' {

    It 'reconoce <Fabricante> / <Modelo>' -ForEach @(
        @{ Fabricante = 'innotek GmbH';          Modelo = 'VirtualBox' }
        @{ Fabricante = 'VMware, Inc.';          Modelo = 'VMware Virtual Platform' }
        @{ Fabricante = 'Microsoft Corporation'; Modelo = 'Virtual Machine' }
        @{ Fabricante = 'QEMU';                  Modelo = 'Standard PC' }
        @{ Fabricante = 'Parallels Software';    Modelo = 'Parallels Virtual Platform' }
    ) {
        Test-PareceMaquinaVirtual -Fabricante $Fabricante -Modelo $Modelo | Should -BeTrue
    }

    It 'un portatil normal no lo parece' {
        Test-PareceMaquinaVirtual -Fabricante 'LENOVO' -Modelo '20XW00ABSP' | Should -BeFalse
        Test-PareceMaquinaVirtual -Fabricante 'ASUSTeK COMPUTER INC.' -Modelo 'ROG Strix' | Should -BeFalse
    }

    It 'sin datos dice que NO' {
        # Si no se puede preguntar, no se puede afirmar. Y no poder afirmar
        # tiene que cerrar la red, no abrirla.
        Test-PareceMaquinaVirtual -Fabricante '' -Modelo ''     | Should -BeFalse
        Test-PareceMaquinaVirtual -Fabricante $null -Modelo $null | Should -BeFalse
    }

    It 'no lanza con nulos' {
        { Test-PareceMaquinaVirtual -Fabricante $null -Modelo $null } | Should -Not -Throw
    }
}
