<#
    Pruebas de [USO-09]: la tabla vacia tiene que decir CUAL de los tres
    vacios es.

    Antes ensenyaba el mismo rectangulo en blanco recien abierto el
    programa, despues de un analisis sin resultados y con un filtro que no
    deja pasar nada. El tercero es el que hace danyo: quien acaba de ver
    seiscientas filas y se equivoca al escribir en el cuadro de filtro ve
    exactamente lo mismo que veria si el analisis hubiera fallado, y lo
    razonable ante eso es volver a analizar -otros cinco minutos- o cerrar
    el programa.

    Se prueba la funcion pura entera y, sobre el texto de los archivos, las
    invariantes que impiden que la ventana vuelva a callarse.
#>

BeforeAll {
    $script:Raiz      = Split-Path $PSScriptRoot -Parent
    $script:CarpetaUi = Join-Path (Join-Path $script:Raiz 'src') 'UI'
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Codigo sin comentarios. Las pruebas que buscan texto encuentran los
    # comentarios del propio arreglo -ha pasado cinco veces en este
    # repositorio- y entonces pasan sin mirar nada.
    function script:Get-CodigoSinComentarios {
        param([string] $Ruta)
        $lineas = [IO.File]::ReadAllText($Ruta) -split "`r?`n"
        $fuera  = $false
        $limpio = foreach ($linea in $lineas) {
            if ($linea -match '<#')  { $fuera = $true }
            if ($fuera) {
                if ($linea -match '#>') { $fuera = $false }
                continue
            }
            if ($linea -match '^\s*#') { continue }
            $linea
        }
        ($limpio -join "`n")
    }

    $script:Ayudantes = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Ayudantes.ps1')
    $script:Eventos   = script:Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Eventos.ps1')

    # El XAML sin sus comentarios <!-- -->, por lo mismo.
    $script:PanelXaml = [regex]::Replace(
        [IO.File]::ReadAllText((Join-Path $script:CarpetaUi 'Panel.Resultados.xaml')),
        '(?s)<!--.*?-->', '')
}

Describe 'USO-09: Get-EstadoVacio distingue los tres vacios' {

    It 'devuelve los cinco campos que la ventana necesita' {
        # Guarda: si el objeto cambiara de forma, las pruebas de abajo
        # compararian $null contra $null y pasarian todas.
        $r = Get-EstadoVacio -Fase 'terminado' -Total 0 -HayVisibles $false
        foreach ($campo in @('Vacio', 'Caso', 'Texto', 'OfrecerQuitarFiltro', 'TextoBoton')) {
            $r.PSObject.Properties.Name | Should -Contain $campo
        }
    }

    It 'con filas a la vista no ensenya ningun cartel' {
        $r = Get-EstadoVacio -Fase 'terminado' -Total 900 -HayVisibles $true -TextoFiltro 'chrome'
        $r.Vacio | Should -BeFalse
        $r.Caso  | Should -Be 'con-datos'
        $r.Texto | Should -BeNullOrEmpty
        $r.OfrecerQuitarFiltro | Should -BeFalse
    }

    It 'recien abierto dice que todavia no se ha analizado' {
        $r = Get-EstadoVacio -Fase 'sin-analizar' -Total 0 -HayVisibles $false
        $r.Vacio | Should -BeTrue
        $r.Caso  | Should -Be 'sin-analizar'
        $r.Texto | Should -BeLike '*Todavía no se ha analizado nada*'
        $r.OfrecerQuitarFiltro | Should -BeFalse
    }

    It 'mientras analiza no dice que no hay nada, dice que se esta llenando' {
        $r = Get-EstadoVacio -Fase 'analizando' -Total 0 -HayVisibles $false
        $r.Caso  | Should -Be 'analizando'
        $r.Texto | Should -BeLike '*se irá llenando*'
    }

    It 'analizado y sin resultados NO suena a fallo' {
        # Es la decision de fondo de este caso: cero resultados no es un
        # error, es que no hay basura. Escribirlo como un fallo manda al
        # usuario a buscar un problema que no existe.
        $r = Get-EstadoVacio -Fase 'terminado' -Total 0 -HayVisibles $false
        $r.Caso  | Should -Be 'sin-resultados'
        $r.Texto | Should -BeLike '*buena noticia*'
        $r.Texto | Should -Not -Match '(?i)(error|no se ha podido|ha fallado|problema)'
    }

    It 'analizado y sin resultados dice de que depende el resultado' {
        # "Tu equipo esta limpio" seria pasarse: con otro perfil el mismo
        # equipo puede tener gigas. Lo que se sabe es que no hay nada CON
        # ESTOS modulos y ESTOS ajustes.
        $r = Get-EstadoVacio -Fase 'terminado' -Total 0 -HayVisibles $false
        $r.Texto | Should -BeLike '*módulos*'
        $r.Texto | Should -BeLike '*ajustes*'
    }

    It 'con filtro que no deja pasar nada dice que la lista esta filtrada, no vacia' {
        $r = Get-EstadoVacio -Fase 'terminado' -Total 812 -HayVisibles $false -TextoFiltro 'chromme'
        $r.Vacio | Should -BeTrue
        $r.Caso  | Should -Be 'filtrado'
        $r.Texto | Should -BeLike '*812 elementos*'
        $r.Texto | Should -BeLike '*filtrada*'
        $r.OfrecerQuitarFiltro | Should -BeTrue
    }

    It 'el caso del filtro nombra CUANTOS elementos hay detras' {
        # Es el dato que convierte "el programa ha perdido los resultados"
        # en "los resultados estan ahi": sin el numero, el cartel es una
        # excusa.
        (Get-EstadoVacio -Fase 'terminado' -Total 1 -HayVisibles $false -RiesgoFiltro 'Alto').Texto |
            Should -BeLike '*1 elemento,*'
        (Get-EstadoVacio -Fase 'terminado' -Total 2 -HayVisibles $false -RiesgoFiltro 'Alto').Texto |
            Should -BeLike '*2 elementos,*'
    }

    It 'un filtro de solo espacios no cuenta como filtro' {
        # El cierre que filtra usa IsNullOrWhiteSpace, asi que tres
        # espacios no esconden nada. Ofrecer quitarlos seria un boton que
        # no cambia nada al pulsarlo.
        $r = Get-EstadoVacio -Fase 'terminado' -Total 5 -HayVisibles $false -TextoFiltro '   '
        $r.Caso | Should -Be 'oculto'
        $r.OfrecerQuitarFiltro | Should -BeFalse
    }

    It 'analizando con la lista llena y filtrada habla del filtro, no del analisis' {
        # El orden de las preguntas. Al reves, un analisis en marcha sobre
        # una lista ya llena diria "se ira llenando sola" delante de
        # setecientas filas escondidas por el filtro.
        $r = Get-EstadoVacio -Fase 'analizando' -Total 700 -HayVisibles $false -TextoFiltro 'zzz'
        $r.Caso | Should -Be 'filtrado'
    }

    It 'una fase desconocida nunca afirma que hubo un analisis' {
        foreach ($fase in @('', 'reposo', 'borrado', 'lo-que-sea')) {
            (Get-EstadoVacio -Fase $fase -Total 0 -HayVisibles $false).Caso |
                Should -Be 'sin-analizar' -Because "la fase '$fase' no dice que se haya analizado"
        }
    }

    It 'no revienta con nulos ni con un total negativo' {
        { Get-EstadoVacio -Fase $null -Total 0 -HayVisibles $false -TextoFiltro $null -RiesgoFiltro $null } |
            Should -Not -Throw
        { Get-EstadoVacio -Fase 'terminado' -Total -5 -HayVisibles $false } | Should -Not -Throw
        (Get-EstadoVacio -Fase 'terminado' -Total -5 -HayVisibles $false).Caso | Should -Be 'sin-resultados'
    }
}

Describe 'USO-09: el boton dice cuantos filtros va a quitar' {

    It 'con <Texto> y <Riesgo> el rotulo es <Esperado>' -ForEach @(
        @{ Texto = 'chrome'; Riesgo = 'Alto'; Esperado = 'Quitar los dos filtros' }
        @{ Texto = 'chrome'; Riesgo = '';     Esperado = 'Quitar el filtro de texto' }
        @{ Texto = '';       Riesgo = 'Bajo'; Esperado = 'Quitar el filtro de riesgo' }
    ) {
        $r = Get-EstadoVacio -Fase 'terminado' -Total 40 -HayVisibles $false `
                 -TextoFiltro $Texto -RiesgoFiltro $Riesgo
        $r.TextoBoton | Should -Be $Esperado
    }

    It 'nombrar los dos es lo que impide que el boton parezca roto' {
        # Si dijera "Quitar el filtro" y solo quitara uno, la tabla podria
        # seguir vacia despues de pulsarlo. Un boton que no cambia nada es
        # indistinguible de uno roto: es [USO-15] otra vez.
        (Get-TextoQuitarFiltros -TextoFiltro 'x' -RiesgoFiltro 'Alto') | Should -Be 'Quitar los dos filtros'
    }

    It 'no revienta con nulos' {
        { Get-TextoQuitarFiltros -TextoFiltro $null -RiesgoFiltro $null } | Should -Not -Throw
    }
}

Describe 'USO-09: la tabla de riesgos del desplegable vive en un solo sitio' {

    It 'el indice <Indice> es "<Esperado>"' -ForEach @(
        @{ Indice = 0;  Esperado = '' }
        @{ Indice = 1;  Esperado = 'Bajo' }
        @{ Indice = 2;  Esperado = 'Medio' }
        @{ Indice = 3;  Esperado = 'Alto' }
        @{ Indice = -1; Esperado = '' }
        @{ Indice = 9;  Esperado = '' }
    ) { Get-RiesgoDelFiltro -Indice $Indice | Should -Be $Esperado }

    It 'las cuatro posiciones son las del ComboBox del panel' {
        # Si alguien anyade una opcion al desplegable y no la anyade a la
        # funcion, el filtro deja de filtrar por ella EN SILENCIO.
        $opciones = @([regex]::Matches($script:PanelXaml,
                      '<ComboBoxItem Content="([^"]+)"')) | ForEach-Object { $_.Groups[1].Value }
        $opciones.Count | Should -Be 4 -Because 'la funcion mapea exactamente cuatro posiciones'
        $opciones[0] | Should -BeLike '*Todos*'
    }

    It 'Test-HayFiltroPuesto usa la misma regla que el cierre que filtra' {
        Test-HayFiltroPuesto -TextoFiltro ''    -RiesgoFiltro ''     | Should -BeFalse
        Test-HayFiltroPuesto -TextoFiltro '   ' -RiesgoFiltro ''     | Should -BeFalse
        Test-HayFiltroPuesto -TextoFiltro $null -RiesgoFiltro $null  | Should -BeFalse
        Test-HayFiltroPuesto -TextoFiltro 'a'   -RiesgoFiltro ''     | Should -BeTrue
        Test-HayFiltroPuesto -TextoFiltro ''    -RiesgoFiltro 'Alto' | Should -BeTrue
    }
}

Describe 'USO-09: la decision no vive en el XAML' {

    <#
        La regla que dejo [USO-04]: aqui no hay WPF, asi que un mecanismo
        de XAML que no se puede ejecutar no se puede verificar, y no tiene
        sitio en el codigo. Alli un Style con DataTrigger aplico el
        disparador y NO el valor por defecto, en Windows, y nadie averiguo
        por que.
    #>

    BeforeAll {
        $script:BloqueCartel = [regex]::Match($script:PanelXaml,
            '(?s)<Border x:Name="EstadoVacio".*?</Border>').Value
    }

    It 'el cartel esta en el panel: si no, esta prueba no mira nada' {
        $script:BloqueCartel | Should -Not -BeNullOrEmpty
        $script:BloqueCartel | Should -Match 'x:Name="TxtEstadoVacio"'
        $script:BloqueCartel | Should -Match 'x:Name="BtnQuitarFiltros"'
    }

    It 'nace plegado: el cartel de tabla vacia sobre la tabla llena seria peor que nada' {
        $script:BloqueCartel | Should -Match '<Border x:Name="EstadoVacio"[^>]*Visibility="Collapsed"'
    }

    It 'ni un disparador ni un conversor deciden que se ve' {
        $script:BloqueCartel | Should -Not -Match 'DataTrigger'
        $script:BloqueCartel | Should -Not -Match '<Style'
        $script:BloqueCartel | Should -Not -Match 'Converter='
    }

    It 'el texto y la visibilidad se asignan desde PowerShell' {
        $script:Ayudantes | Should -Match '\$c\.TxtEstadoVacio\.Text\s*='
        $script:Ayudantes | Should -Match '\$c\.EstadoVacio\.Visibility\s*='
        $script:Ayudantes | Should -Match '\$c\.BtnQuitarFiltros\.Visibility\s*='
    }

    It 'el boton tiene rotulo propio, asi que no queda mudo' {
        # [A11Y-01]: un Button sin Content de texto se anuncia como "boton"
        # a secas. El Content de aqui es el caso general; el codigo lo
        # reescribe con cuantos filtros va a quitar.
        $script:BloqueCartel | Should -Match 'Content="Quitar los filtros"'
    }
}

Describe 'USO-09: la ventana llama a la funcion y no vuelve a decidir por su cuenta' {

    It 'los archivos tienen contenido: si no, nada de esto comprueba nada' {
        $script:Ayudantes.Length | Should -BeGreaterThan 4000
        $script:Eventos.Length   | Should -BeGreaterThan 4000
    }

    It 'el cartel sale de Get-EstadoVacio, no de un if de la ventana' {
        $script:Ayudantes | Should -Match 'Get-EstadoVacio\s+-Fase'
    }

    It 'el filtro y el cartel preguntan lo mismo a la misma funcion' {
        # Sin esto vuelven a ser dos copias de la tabla de riesgos, y basta
        # con anyadir una opcion al desplegable para que discrepen.
        $script:Ayudantes | Should -Match 'Get-RiesgoDelFiltro -Indice'
        $script:Ayudantes | Should -Match 'Test-HayFiltroPuesto -TextoFiltro'
        $script:Ayudantes | Should -Not -Match "1 \{ 'Bajo' \}"
    }

    It 'el resumen del pie arrastra el cartel, que es lo que lo mantiene al dia' {
        $script:Ayudantes | Should -Match '(?s)\$actualizarResumenSeleccion = \{.{0,400}& \$actualizarEstadoVacio'
    }

    It 'empezar un analisis refresca el cartel al momento' {
        # Sin esto, un "encontro 812 elementos" del analisis anterior se
        # queda colgado sobre la lista recien vaciada hasta que termine el
        # primer modulo, que puede tardar minutos.
        $script:Eventos | Should -Match '(?s)\$estado\.Items\.Clear\(\).*?& \$actualizarEstadoVacio'
    }

    It 'el boton del cartel esta enganchado' {
        $script:Eventos | Should -Match '\$c\.BtnQuitarFiltros\.Add_Click'
    }

    It 'el boton quita LOS DOS filtros' {
        # Si quitara solo uno, la tabla podria seguir vacia y el boton
        # pareceria roto. Es la razon de que el rotulo diga "los dos".
        $quitar = [regex]::Match($script:Ayudantes, '(?s)\$quitarFiltros = \{.*?\n    \}').Value
        $quitar | Should -Not -BeNullOrEmpty
        $quitar | Should -Match '\$c\.CampoFiltro\.Text\s*='
        $quitar | Should -Match '\$c\.FiltroRiesgo\.SelectedIndex\s*=\s*0'
    }

    It 'el cronometro se arranca al analizar, que es como se sabe que ya se analizo' {
        # De esto depende que "recien abierto" no se confunda con
        # "analizado y sin resultados": si nadie arranca el cronometro, el
        # programa diria "todavia no se ha analizado nada" con la lista
        # llena delante.
        $script:Eventos   | Should -Match '\$estado\.Cronometro = \[Diagnostics\.Stopwatch\]::StartNew\(\)'
        $script:Ayudantes | Should -Match '\$null -eq \$estado\.Cronometro'
    }

    It 'saber si hay algo a la vista no recorre la tabla entera' {
        # Esto se recalcula en CADA clic de casilla. Materializar quince
        # mil filas en un array para saber si hay al menos una es lo que
        # convirtio el resumen del pie en 135 ms por clic.
        $script:Ayudantes | Should -Match '\$estado\.Vista\.IsEmpty'
    }
}

Describe 'USO-09: los textos que ve el usuario estan bien escritos' {

    BeforeAll {
        $script:Textos = @(
            (Get-EstadoVacio -Fase 'sin-analizar' -Total 0 -HayVisibles $false).Texto
            (Get-EstadoVacio -Fase 'analizando'   -Total 0 -HayVisibles $false).Texto
            (Get-EstadoVacio -Fase 'terminado'    -Total 0 -HayVisibles $false).Texto
            (Get-EstadoVacio -Fase 'terminado' -Total 9 -HayVisibles $false -TextoFiltro 'x').Texto
        )
    }

    It 'hay cuatro textos distintos: si no, esta prueba no compara nada' {
        @($script:Textos | Select-Object -Unique).Count | Should -Be 4
        foreach ($t in $script:Textos) { $t.Length | Should -BeGreaterThan 40 }
    }

    It 'ninguno usa una palabra sin su tilde' {
        $sinTilde = @('analisis', 'aqui', 'vacia', 'estan', 'ningun', 'despues', 'ultima', 'modulos')
        $patron = '\b(' + ($sinTilde -join '|') + ')\b'
        foreach ($t in $script:Textos) { $t | Should -Not -CMatch $patron }
    }

    It 'ninguno dice "1 elementos"' {
        (Get-EstadoVacio -Fase 'terminado' -Total 1 -HayVisibles $false -TextoFiltro 'x').Texto |
            Should -Not -Match '1 elementos'
    }
}
