<#
    [USO-10]. La tabla de resultados no puede devolverte al principio cada
    vez que termina un modulo.

    Aqui no arranca WPF, asi que ni hay ScrollViewer ni hay DataGrid ni se
    puede desplazar nada. Lo que si se puede hacer es lo que este proyecto
    lleva haciendo desde [USO-04]: sacar la decision del sitio donde no se
    puede mirar y meterla en una funcion pura, y despues atar por texto que
    la ventana no vuelva a decidirlo por su cuenta.

    Lo que se protege:

      1. El recorte del desplazamiento guardado, incluidos los dos valores
         que un desplazador sin medir contesta de verdad -NaN e infinito- y
         que envenenan cualquier comparacion que los reciba.
      2. Que una seleccion escondida por el filtro NO se restaura. Si se
         restaurara, "Abrir la ubicacion" y el menu contextual actuarian
         sobre una fila que nadie ve.
      3. Que el plan no lleva una segunda copia del recorte.
      4. Que NINGUN sitio puede desenganchar la tabla sin guardar y
         restaurar el sitio. Es la invariante que importa: el fallo
         original no fue escribir mal el reenganche, fue que reenganchar
         tenia un efecto secundario que nadie habia anotado, y un cuarto
         sitio lo repetiria igual.
      5. Que restaurar la seleccion no arrastra la tabla hasta ella.

    Toda prueba de texto lleva su guarda previa, y el codigo se lee sin
    comentarios: las pruebas de texto encuentran los comentarios del propio
    arreglo, que en este repositorio ha pasado seis veces. Aqui pasaria
    seguro: el comentario que explica por que NO hay un ScrollIntoView
    contiene la palabra ScrollIntoView.
#>

BeforeAll {
    $script:Raiz      = Split-Path $PSScriptRoot -Parent
    $script:CarpetaUi = Join-Path (Join-Path $script:Raiz 'src') 'UI'

    . (Join-Path $script:CarpetaUi 'Posicion.ps1')

    # ORDEN: primero los bloques <# #>, DESPUES las lineas que empiezan
    # por #. Al reves -que es como esta en otros archivos de pruebas- el
    # primer paso se lleva por delante la linea del "#>", el bloque se
    # queda sin cierre, y el segundo paso encuentra el "#>" del bloque
    # SIGUIENTE: el resultado es que un trozo de documentacion sobrevive
    # entero y otro trozo de codigo de verdad desaparece.
    #
    # No es teorico: esta prueba fallo asi. La cabecera de Posicion.ps1
    # dice "ni un tipo de System.Windows", y la invariante que busca
    # System.Windows en el codigo lo encontro en esa frase.
    function script:Get-CodigoSinComentarios {
        param([string] $Ruta)
        $texto  = [regex]::Replace([IO.File]::ReadAllText($Ruta), '(?s)<#.*?#>', '')
        $lineas = @($texto -split "`r?`n" |
                    Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*///' })
        return $lineas -join "`n"
    }

    $script:ArchivosUi = @(Get-ChildItem -LiteralPath $script:CarpetaUi -Filter '*.ps1' -File)
}

Describe 'Get-DesplazamientoRestaurado: el recorte' {

    It 'devuelve lo guardado cuando todavia cabe' {
        Get-DesplazamientoRestaurado -Guardado 120 -Maximo 900 | Should -Be 120
    }

    It 'recorta al maximo cuando ya no cabe' {
        # Pasa de verdad: se guarda con la lista larga y se restaura con un
        # filtro puesto que esconde la mitad.
        Get-DesplazamientoRestaurado -Guardado 900 -Maximo 120 | Should -Be 120
    }

    It 'justo en el maximo devuelve el maximo' {
        Get-DesplazamientoRestaurado -Guardado 300 -Maximo 300 | Should -Be 300
    }

    It 'sin nada que desplazar devuelve cero' {
        # La lista entera cabe en pantalla: no hay barra.
        Get-DesplazamientoRestaurado -Guardado 120 -Maximo 0 | Should -Be 0
    }

    It 'un guardado de <Guardado> devuelve cero' -ForEach @(
        @{ Guardado = 0.0 }, @{ Guardado = -1.0 }, @{ Guardado = -900.0 }
    ) {
        Get-DesplazamientoRestaurado -Guardado $Guardado -Maximo 900 | Should -Be 0
    }

    It 'NaN en el guardado devuelve cero' {
        # El caso que obliga a que la guarda vaya la PRIMERA: NaN hace
        # falsas las dos comparaciones, la de mayor y la de menor, asi que
        # sin ella se cuela por en medio de los dos "if" y sale intacto.
        Get-DesplazamientoRestaurado -Guardado ([double]::NaN) -Maximo 900 | Should -Be 0
    }

    It 'NaN en el maximo devuelve cero' {
        Get-DesplazamientoRestaurado -Guardado 120 -Maximo ([double]::NaN) | Should -Be 0
    }

    It 'infinito en cualquiera de los dos devuelve cero' {
        Get-DesplazamientoRestaurado -Guardado ([double]::PositiveInfinity) -Maximo 900 | Should -Be 0
        Get-DesplazamientoRestaurado -Guardado 120 -Maximo ([double]::PositiveInfinity) | Should -Be 0
        Get-DesplazamientoRestaurado -Guardado ([double]::NegativeInfinity) -Maximo 900 | Should -Be 0
    }

    It 'nunca devuelve NaN ni infinito, pase lo que pase' {
        $raros = @(0.0, -1.0, 120.0, 900.0, [double]::NaN,
                   [double]::PositiveInfinity, [double]::NegativeInfinity)
        foreach ($g in $raros) {
            foreach ($m in $raros) {
                $r = Get-DesplazamientoRestaurado -Guardado $g -Maximo $m
                [double]::IsNaN($r)      | Should -BeFalse -Because "con Guardado=$g y Maximo=$m"
                [double]::IsInfinity($r) | Should -BeFalse -Because "con Guardado=$g y Maximo=$m"
                $r | Should -BeGreaterOrEqual 0 -Because "con Guardado=$g y Maximo=$m"
            }
        }
    }
}

Describe 'Get-PlanRestauracionTabla: que se restaura y que no' {

    It 'sin desplazamiento y sin seleccion no hay nada que hacer' {
        # El caso normal, y el que mas veces se da: alguien lanza el
        # analisis y se va a hacer otra cosa. Restaurar seria escribir los
        # mismos valores que ya hay.
        $plan = Get-PlanRestauracionTabla -Guardado 0 -Maximo 900
        $plan.HayQueHacerAlgo    | Should -BeFalse
        $plan.RestaurarSeleccion | Should -BeFalse
        $plan.Desplazamiento     | Should -Be 0
    }

    It 'con desplazamiento hay algo que hacer aunque no haya seleccion' {
        $plan = Get-PlanRestauracionTabla -Guardado 120 -Maximo 900
        $plan.HayQueHacerAlgo | Should -BeTrue
        $plan.Desplazamiento  | Should -Be 120
    }

    It 'una seleccion que sigue a la vista se restaura' {
        $plan = Get-PlanRestauracionTabla -Guardado 0 -Maximo 900 -HabiaSeleccion -SeleccionVisible
        $plan.RestaurarSeleccion | Should -BeTrue
        $plan.HayQueHacerAlgo    | Should -BeTrue
    }

    It 'una seleccion que el filtro esconde NO se restaura' {
        # Restaurarla dejaria al DataGrid con una fila marcada que nadie
        # ve, y a "Abrir la ubicacion" abriendo una carpeta que el usuario
        # no ha senyalado.
        $plan = Get-PlanRestauracionTabla -Guardado 0 -Maximo 900 -HabiaSeleccion
        $plan.RestaurarSeleccion | Should -BeFalse
        $plan.HayQueHacerAlgo    | Should -BeFalse
    }

    It 'una seleccion escondida no impide restaurar el desplazamiento' {
        # Son dos cosas independientes, y la mas visible de las dos es el
        # desplazamiento.
        $plan = Get-PlanRestauracionTabla -Guardado 120 -Maximo 900 -HabiaSeleccion
        $plan.RestaurarSeleccion | Should -BeFalse
        $plan.Desplazamiento     | Should -Be 120
        $plan.HayQueHacerAlgo    | Should -BeTrue
    }

    It 'sin seleccion, que el filtro la dejara pasar no inventa una' {
        # Combinacion que no deberia darse; si se diera, no puede acabar
        # marcando una fila que nadie habia marcado.
        $plan = Get-PlanRestauracionTabla -Guardado 0 -Maximo 900 -SeleccionVisible
        $plan.RestaurarSeleccion | Should -BeFalse
        $plan.HayQueHacerAlgo    | Should -BeFalse
    }

    It 'el desplazamiento del plan sale de Get-DesplazamientoRestaurado, no de una copia' -ForEach @(
        @{ G = 0.0 ;  M = 0.0   }
        @{ G = 120.0; M = 900.0 }
        @{ G = 900.0; M = 120.0 }
        @{ G = -5.0 ; M = 900.0 }
        @{ G = 300.0; M = 300.0 }
    ) {
        # Tautologica mientras el plan llame a la funcion, que es
        # exactamente lo que esta prueba defiende: el dia que alguien
        # meta el recorte a mano aqui dentro, habra dos sitios recortando
        # y esta prueba se entera antes que el usuario.
        (Get-PlanRestauracionTabla -Guardado $G -Maximo $M).Desplazamiento |
            Should -Be (Get-DesplazamientoRestaurado -Guardado $G -Maximo $M)
    }

    It 'con los valores raros del desplazador no lanza y no hay nada que hacer' {
        { Get-PlanRestauracionTabla -Guardado ([double]::NaN) -Maximo 900 } | Should -Not -Throw
        (Get-PlanRestauracionTabla -Guardado ([double]::NaN) -Maximo 900).HayQueHacerAlgo |
            Should -BeFalse
    }
}

Describe 'Posicion.ps1 no toca WPF' {

    It 'define las dos funciones que la ventana necesita' {
        # Guarda de la prueba de abajo: si el archivo no fuera el que
        # creo que es, buscar tipos de WPF dentro no comprobaria nada.
        $texto = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Posicion.ps1')
        $texto | Should -Match 'function Get-DesplazamientoRestaurado'
        $texto | Should -Match 'function Get-PlanRestauracionTabla'
    }

    It 'no menciona ni un tipo de System.Windows' {
        # Es lo unico que permite que todo lo de arriba se pueda ejecutar
        # en un sistema sin interfaz grafica. En cuanto entre un tipo de
        # WPF, este archivo deja de cargarse en las pruebas y las
        # decisiones vuelven a estar donde no se pueden mirar.
        $texto = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Posicion.ps1')
        $texto | Should -Not -Match 'System\.Windows'
        $texto | Should -Not -Match '\[Windows\.'
    }

    It 'la ventana lo carga' {
        $ventana = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.ps1')
        $ventana | Should -Match "Posicion\.ps1"
    }
}

Describe 'invariante: desenganchar la tabla obliga a guardar y restaurar el sitio' {

    It 'hay al menos dos sitios que desenganchan, si no esta prueba no mira nada' {
        $total = 0
        foreach ($archivo in $script:ArchivosUi) {
            $texto = script:Get-CodigoSinComentarios $archivo.FullName
            $total += ([regex]::Matches($texto,
                'TablaResultados\.ItemsSource\s*=\s*\$null')).Count
        }
        $total | Should -BeGreaterOrEqual 2 -Because 'el analisis y el cambio de tema desenganchan los dos'
    }

    It 'cada archivo que desengancha guarda y restaura las mismas veces' {
        $informe = @()
        foreach ($archivo in $script:ArchivosUi) {
            $texto = script:Get-CodigoSinComentarios $archivo.FullName
            $desengancha = ([regex]::Matches($texto,
                'TablaResultados\.ItemsSource\s*=\s*\$null')).Count
            if ($desengancha -eq 0) { continue }

            # Las LLAMADAS, no las definiciones: los tres cierres se
            # definen en Window.Ayudantes.ps1 y ahi el nombre aparece
            # tambien a la izquierda de un igual.
            $guarda   = ([regex]::Matches($texto, '&\s*\$guardarPosicionTabla')).Count
            $restaura = ([regex]::Matches($texto, '&\s*\$restaurarPosicionTabla')).Count

            if ($guarda -ne $desengancha -or $restaura -ne $desengancha) {
                $informe += ('{0}: desengancha {1}, guarda {2}, restaura {3}' -f `
                             $archivo.Name, $desengancha, $guarda, $restaura)
            }
        }
        $informe -join '; ' | Should -BeNullOrEmpty -Because (
            'reenganchar la tabla borra el desplazamiento y la seleccion, ' +
            'asi que quien desengancha tiene que guardarlos antes y devolverlos despues')
    }

    It 'restaurar la posicion no arrastra la tabla hasta la fila seleccionada' {
        # ScrollIntoView se pelearia con el desplazamiento que se acaba de
        # restaurar, y ganaria el ultimo en escribir. Es una decision, no
        # un olvido, y por eso esta atada. El comentario que lo explica
        # dice la palabra, por eso se lee el archivo sin comentarios.
        $ayudantes = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Ayudantes.ps1')
        $ayudantes | Should -Match '\$restaurarPosicionTabla\s*=' -Because 'guarda: el cierre tiene que estar aqui'
        $ayudantes | Should -Not -Match 'ScrollIntoView'
    }

    It 'el estado de la ventana tiene donde guardar el desplazador' {
        $ventana = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.ps1')
        $ventana | Should -Match 'DesplazadorTabla\s*=\s*\$null'
    }
}

Describe 'Get-AlturaMaximaDialogo: el dialogo no puede salirse de la pantalla' {

    # [A11Y-02]. El MaxHeight="760" que puso [A11Y-03] esta en PIXELES de un
    # portatil sin escalar. En ese mismo portatil al 150% la pantalla mide
    # 512 PUNTOS, que es en lo que trabaja WPF, asi que el tope quedaba por
    # encima del escritorio entero y no topaba nada.

    It 'en el caso que motivo el punto -1366x768 al 150%- cabe de sobra' {
        # 768 px / 1,5 = 512 puntos de alto.
        $alto = Get-AlturaMaximaDialogo -AltoAreaUtil 512
        $alto | Should -BeLessThan 512
        $alto | Should -BeGreaterOrEqual 320
    }

    It 'y en esa pantalla NO devuelve los 760 de antes' {
        Get-AlturaMaximaDialogo -AltoAreaUtil 512 | Should -Not -Be 760 -Because (
            'es mas alto que la pantalla entera: era el fallo')
    }

    It 'deja margen: nunca devuelve el area util entera' {
        foreach ($util in @(512, 700, 900, 1040)) {
            Get-AlturaMaximaDialogo -AltoAreaUtil $util | Should -BeLessThan $util
        }
    }

    It 'en una pantalla grande se queda en 760, que ya es legible' {
        Get-AlturaMaximaDialogo -AltoAreaUtil 1400 | Should -Be 760
    }

    It 'en una pantalla absurdamente pequenya devuelve un suelo utilizable' {
        # Mas vale que se salga un poco a que no quepan ni los botones.
        Get-AlturaMaximaDialogo -AltoAreaUtil 200 | Should -Be 320
    }

    It 'con datos imposibles NO lanza: este dialogo es el que frena un borrado' {
        foreach ($malo in @(0, -100, [double]::NaN, [double]::PositiveInfinity)) {
            { Get-AlturaMaximaDialogo -AltoAreaUtil $malo } | Should -Not -Throw
            Get-AlturaMaximaDialogo -AltoAreaUtil $malo | Should -BeGreaterOrEqual 320
        }
    }

    It 'siempre devuelve un numero utilizable, sea cual sea la pantalla' {
        foreach ($util in @(100, 320, 512, 600, 768, 900, 1080, 1440, 2160)) {
            $alto = Get-AlturaMaximaDialogo -AltoAreaUtil $util
            $alto | Should -BeGreaterOrEqual 320
            $alto | Should -BeLessOrEqual 760
        }
    }
}

Describe 'A11Y-02: la ventana cabe en la pantalla mas pequenya que se soporta' {

    BeforeAll {
        $script:RaizA11y2 = Split-Path $PSScriptRoot -Parent
        $script:XamlVentana = [IO.File]::ReadAllText(
            (Join-Path (Join-Path (Join-Path $script:RaizA11y2 'src') 'UI') 'MainWindow.xaml'))

        # El caso peor que el proyecto dice soportar: un portatil corriente
        # de 1366x768 con el escalado de Windows al 150%. WPF trabaja en
        # puntos, asi que son 910x512.
        $script:AnchoMinimoPantalla = 1366 / 1.5
        $script:AltoMinimoPantalla  = 768 / 1.5
        # La barra de tareas de Windows 11, en puntos.
        $script:BarraTareas = 48
    }

    It 'la prueba encuentra el minimo declarado: si no, no comprueba nada' {
        $script:XamlVentana | Should -Match 'MinWidth="\d+"'
        $script:XamlVentana | Should -Match 'MinHeight="\d+"'
    }

    It 'el minimo declarado CABE en 1366x768 al 150%' {
        $ancho = [double][regex]::Match($script:XamlVentana, 'MinWidth="(\d+)"').Groups[1].Value
        $alto  = [double][regex]::Match($script:XamlVentana, 'MinHeight="(\d+)"').Groups[1].Value

        $ancho | Should -BeLessOrEqual $script:AnchoMinimoPantalla -Because (
            'si el minimo es mayor que la pantalla, la ventana no puede encogerse y se sale')
        $alto  | Should -BeLessOrEqual ($script:AltoMinimoPantalla - $script:BarraTareas) -Because (
            'tiene que caber ADEMAS de la barra de tareas, o el boton de eliminar queda debajo')
    }

    It 'pero sigue siendo un tamanyo con el que se puede trabajar' {
        # El otro lado: bajar el minimo a 200x200 tambien "cabria" y seria
        # inutil. Esto impide arreglar el punto haciendolo absurdo.
        $ancho = [double][regex]::Match($script:XamlVentana, 'MinWidth="(\d+)"').Groups[1].Value
        $alto  = [double][regex]::Match($script:XamlVentana, 'MinHeight="(\d+)"').Groups[1].Value
        $ancho | Should -BeGreaterOrEqual 800
        $alto  | Should -BeGreaterOrEqual 440
    }

    It 'y el dialogo de confirmacion se ajusta a la pantalla, no a un numero fijo' {
        $ps = [IO.File]::ReadAllText(
            (Join-Path (Join-Path (Join-Path $script:RaizA11y2 'src') 'UI') 'Dialogs.ps1'))
        $codigo = ($ps -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $codigo | Should -Match 'Get-AlturaMaximaDialogo'
        $codigo | Should -Match 'WorkArea'
        $codigo | Should -Match 'MaxHeight'
    }
}
