<#
    Atajos de teclado. [A11Y-04].

    Get-AtajoDeTecla es calculo puro y no toca WPF, asi que se puede recorrer
    combinacion por combinacion aqui, donde no hay interfaz grafica. Esa es
    justamente la razon de que la decision viva en su propio archivo: la
    parte que se puede probar se prueba, y lo que queda sin verificar hasta
    que alguien lo ejecute en Windows es solo el cableado.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') 'Atajos.ps1')
}

Describe 'Get-AtajoDeTecla' {

    Context 'Las teclas sueltas' {
        It 'F5 analiza' {
            Get-AtajoDeTecla -Tecla 'F5' | Should -Be 'Analizar'
        }

        It 'Escape cancela' {
            Get-AtajoDeTecla -Tecla 'Escape' | Should -Be 'Cancelar'
        }

        It 'F5 y Escape siguen valiendo escribiendo en un cuadro de texto' {
            # No chocan con nada que haga un cuadro de texto, y quien esta
            # escribiendo en el filtro es justo quien mas necesita poder
            # parar un analisis sin buscar el raton.
            Get-AtajoDeTecla -Tecla 'F5'     -EnCuadroDeTexto | Should -Be 'Analizar'
            Get-AtajoDeTecla -Tecla 'Escape' -EnCuadroDeTexto | Should -Be 'Cancelar'
        }

        It 'una letra cualquiera no es atajo' {
            Get-AtajoDeTecla -Tecla 'K' | Should -BeNullOrEmpty
        }

        It 'F5 con Control NO analiza' {
            # El atajo es F5, no "F5 con lo que sea": en un navegador
            # Ctrl+F5 significa otra cosa, y aceptar de mas es como acabas
            # disparando acciones que nadie pidio.
            Get-AtajoDeTecla -Tecla 'F5' -Control | Should -BeNullOrEmpty
        }
    }

    Context 'Con Control' {
        It 'Ctrl+F lleva al filtro' {
            Get-AtajoDeTecla -Tecla 'F' -Control | Should -Be 'Filtrar'
        }

        It 'Ctrl+A marca todo' {
            Get-AtajoDeTecla -Tecla 'A' -Control | Should -Be 'MarcarTodo'
        }

        It 'la F y la A sin Control no son atajo' {
            # Si lo fueran, escribir "familia" en el filtro marcaria la lista
            # entera a la primera letra.
            Get-AtajoDeTecla -Tecla 'F' | Should -BeNullOrEmpty
            Get-AtajoDeTecla -Tecla 'A' | Should -BeNullOrEmpty
        }
    }

    Context 'El unico choque: Ctrl+A dentro de un cuadro de texto' {
        It 'Ctrl+A en un cuadro de texto NO marca todo' {
            # Ahi Ctrl+A ya significa "selecciona todo el texto". El registro
            # de la sesion es un cuadro de texto: robarle Ctrl+A dejaria al
            # usuario sin forma de seleccionarlo para copiarlo.
            Get-AtajoDeTecla -Tecla 'A' -Control -EnCuadroDeTexto | Should -BeNullOrEmpty
        }

        It 'los demas atajos con Control siguen valiendo en un cuadro de texto' {
            Get-AtajoDeTecla -Tecla 'F'  -Control -EnCuadroDeTexto | Should -Be 'Filtrar'
            Get-AtajoDeTecla -Tecla 'D2' -Control -EnCuadroDeTexto | Should -Be 'NavResultados'
        }
    }

    Context 'Ctrl+1..6, los seis paneles' {
        It 'Ctrl+<Tecla> lleva a <Esperado>' -ForEach @(
            @{ Tecla = 'D1'; Esperado = 'NavInicio' }
            @{ Tecla = 'D2'; Esperado = 'NavResultados' }
            @{ Tecla = 'D3'; Esperado = 'NavRegistro' }
            @{ Tecla = 'D4'; Esperado = 'NavInformes' }
            @{ Tecla = 'D5'; Esperado = 'NavAjustes' }
            @{ Tecla = 'D6'; Esperado = 'NavAcerca' }
        ) {
            Get-AtajoDeTecla -Tecla $Tecla -Control | Should -Be $Esperado
        }

        It 'el teclado numerico hace lo mismo que la fila de arriba' {
            # Para el usuario es la misma tecla. Descubrir que el atajo "no
            # funciona" segun donde pulses el 3 es de las cosas que hacen que
            # alguien deje de usar los atajos.
            foreach ($n in 1..6) {
                $arriba  = Get-AtajoDeTecla -Tecla ('D{0}' -f $n)      -Control
                $numerico = Get-AtajoDeTecla -Tecla ('NumPad{0}' -f $n) -Control
                $numerico | Should -Be $arriba
            }
        }

        It 'no hay Ctrl+7 ni Ctrl+0: no hay septimo panel' {
            Get-AtajoDeTecla -Tecla 'D7' -Control | Should -BeNullOrEmpty
            Get-AtajoDeTecla -Tecla 'D0' -Control | Should -BeNullOrEmpty
        }

        It 'los numeros SIN Control no son atajo' {
            Get-AtajoDeTecla -Tecla 'D3' | Should -BeNullOrEmpty
        }
    }

    Context 'No revienta con lo que le llegue' {
        # Por esta funcion pasa CADA tecla que se pulsa en la ventana, y va
        # dentro de un manejador de teclado: el peor sitio posible para
        # lanzar una excepcion. Ver la nota de [AllowNull] en el relevo.
        It 'con nulo devuelve nada, no lanza' {
            { Get-AtajoDeTecla -Tecla $null } | Should -Not -Throw
            Get-AtajoDeTecla -Tecla $null | Should -BeNullOrEmpty
        }

        It 'con cadena vacia o espacios devuelve nada, no lanza' {
            { Get-AtajoDeTecla -Tecla '' } | Should -Not -Throw
            Get-AtajoDeTecla -Tecla ''   | Should -BeNullOrEmpty
            Get-AtajoDeTecla -Tecla '   ' | Should -BeNullOrEmpty
        }

        It 'con un nombre de tecla que no existe devuelve nada' {
            Get-AtajoDeTecla -Tecla 'TeclaQueNoExiste' -Control | Should -BeNullOrEmpty
        }
    }
}
