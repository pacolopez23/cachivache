<#
    Pruebas de [USO-02]: un fallo de borrado no puede pintarse en verde ni
    quedarse invisible.

    Aqui NO se prueba XAML -no arranca en las pruebas-, sino las dos
    propiedades de las que ahora depende lo que se ve. Esa es justo la
    razon de haberlas movido de un disparador de XAML a la clase: un
    Trigger no se puede comprobar en ninguna parte, y una propiedad si.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') 'Types.ps1')
    Initialize-TiposInterfaz
}

Describe 'USO-02: el estado de una fila dice la verdad' {

    It 'antes de borrar no hay nada que ensenyar' {
        $item = [Cachivache.ItemVista]::new()
        $item.VisibilidadEstado | Should -Be 'Collapsed'
        $item.EstadoEsFallo     | Should -BeFalse
    }

    It 'un borrado correcto se ve, y NO como fallo' {
        $item = [Cachivache.ItemVista]::new()
        $item.Hecho  = $true
        $item.Estado = 'Eliminado'

        $item.VisibilidadEstado | Should -Be 'Visible'
        $item.EstadoEsFallo     | Should -BeFalse -Because 'se borro: va en verde'
    }

    It 'un FALLO se ve, que era el fallo de verdad' {
        # Antes la visibilidad dependia de Hecho, asi que esto quedaba
        # Collapsed: el elemento no se habia borrado y la fila no decia
        # absolutamente nada. El usuario daba por limpiado algo que seguia
        # en su disco.
        $item = [Cachivache.ItemVista]::new()
        $item.Hecho  = $false
        $item.Estado = 'Excluido por ti: C:\Proyectos'

        $item.VisibilidadEstado | Should -Be 'Visible'
        $item.EstadoEsFallo     | Should -BeTrue -Because 'no se borro: va en rojo'
    }

    It 'las dos propiedades se recalculan al cambiar Estado' {
        # WPF no adivina que una propiedad derivada ha cambiado: sin el
        # aviso, la fila se quedaria con el color y la visibilidad de
        # antes aunque el texto cambiara.
        $item = [Cachivache.ItemVista]::new()
        $item.VisibilidadEstado | Should -Be 'Collapsed'
        $item.Estado = 'No se ha podido borrar'
        $item.VisibilidadEstado | Should -Be 'Visible'
        $item.EstadoEsFallo     | Should -BeTrue
    }

    It 'y al cambiar Hecho' {
        $item = [Cachivache.ItemVista]::new()
        $item.Estado = 'Eliminado'
        $item.EstadoEsFallo | Should -BeTrue -Because 'todavia no consta como hecho'
        $item.Hecho = $true
        $item.EstadoEsFallo | Should -BeFalse
    }

    It 'avisa por PropertyChanged de las derivadas, no solo de la que se toca' {
        # Sin esto la clase seria correcta y la ventana seguiria mintiendo:
        # el valor bueno estaria ahi y nadie lo habria repintado.
        $item = [Cachivache.ItemVista]::new()
        $avisadas = [Collections.Generic.List[string]]::new()
        $item.add_PropertyChanged({ param($o, $e) $avisadas.Add($e.PropertyName) })

        $item.Estado = 'algo'
        $avisadas | Should -Contain 'Estado'
        $avisadas | Should -Contain 'VisibilidadEstado'
        $avisadas | Should -Contain 'EstadoEsFallo'

        $avisadas.Clear()
        $item.Hecho = $true
        $avisadas | Should -Contain 'Hecho'
        $avisadas | Should -Contain 'EstadoEsFallo'
    }
}

Describe 'USO-02: la vista no puede volver a esconder los fallos' {

    BeforeAll {
        $script:Xaml = Get-Content -Raw -LiteralPath (
            Join-Path $script:Raiz 'src/UI/Panel.Resultados.xaml')
        $script:Cierre = (Get-Content -LiteralPath (
            Join-Path $script:Raiz 'src/UI/Window.Eliminacion.ps1') |
            Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'la visibilidad del estado NO depende de Hecho' {
        $script:Xaml | Should -Match 'Visibility="\{Binding VisibilidadEstado\}"'
    }

    It 'el color deja de ser verde fijo' {
        $script:Xaml | Should -Match 'DataTrigger Binding="\{Binding EstadoEsFallo\}" Value="True"'
        $script:Xaml | Should -Match 'Value="\{DynamicResource Peligro\}"'
    }

    It 'solo se desmarca lo que SE BORRO' {
        # Desmarcarlo todo hacia que el pie dijera "nada marcado" y que lo
        # no borrado desapareciera de la vista sin haberse tocado.
        $script:Cierre | Should -Match 'if \(\$item\.Origen\.Hecho\) \{ \$item\.Seleccionado = \$false \}'
    }

    It 'una fila fallida no se atenua como las hechas' {
        # La opacidad reducida marca "esto ya esta resuelto". Aplicarla a
        # un fallo lo enterraria justo cuando mas hay que mirarlo.
        $script:Xaml | Should -Match '(?s)DataTrigger Binding="\{Binding Hecho\}" Value="True">\s*<Setter Property="Opacity"'
    }
}

Describe 'USO-01: el texto completo de la columna que sostiene la decision' {

    It 'junta los cuatro textos en el orden en que se leen' {
        $item = [Cachivache.ItemVista]::new()
        $item.Aviso   = 'contiene una carpeta projects'
        $item.Efecto  = 'No coincide con ningun programa instalado.'
        $item.Comando = 'docker system prune -a -f'
        $item.Estado  = 'No se ha podido borrar'

        $t = $item.TextoCompleto
        $t | Should -BeLike '*projects*'
        $t | Should -BeLike '*No coincide*'
        $t | Should -BeLike '*docker system prune -a -f*'
        $t | Should -BeLike '*No se ha podido borrar*'
        $t.IndexOf('projects')  | Should -BeLessThan $t.IndexOf('No coincide')
    }

    It 'omite lo que no hay, sin dejar huecos ni separadores sueltos' {
        $item = [Cachivache.ItemVista]::new()
        $item.Efecto = 'Solo esto.'
        $item.TextoCompleto | Should -Be 'Solo esto.'
    }

    It 'un elemento sin nada devuelve cadena vacia, no un salto de linea' {
        [Cachivache.ItemVista]::new().TextoCompleto | Should -Be ''
    }

    It 'el comando entra COMPLETO: es lo que SECURITY.md exige ensenyar' {
        $largo = 'dism /online /cleanup-image /startcomponentcleanup /resetbase'
        $item = [Cachivache.ItemVista]::new()
        $item.Comando = $largo
        $item.TextoCompleto | Should -BeLike "*$largo*"
    }

    It 'se recalcula al cambiar Estado' {
        $item = [Cachivache.ItemVista]::new()
        $avisadas = [Collections.Generic.List[string]]::new()
        $item.add_PropertyChanged({ param($o, $e) $avisadas.Add($e.PropertyName) })
        $item.Estado = 'algo'
        $avisadas | Should -Contain 'TextoCompleto'
    }
}

Describe 'USO-01: la altura de fila deja de recortar' {

    It 'el estilo usa altura MINIMA, no exacta' {
        # RowHeight fija la altura exacta y cortaba la columna sobre la que
        # el usuario decide. Sin puntos suspensivos y sin aviso.
        $estilos = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Styles.xaml')),
            '(?s)<!--.*?-->', '')
        $estilos | Should -Match 'Property="MinRowHeight"'
        $estilos | Should -Not -Match 'Property="RowHeight"'
    }

    It 'la celda lleva el texto completo en la ayuda emergente' {
        $xaml = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Panel.Resultados.xaml')),
            '(?s)<!--.*?-->', '')
        $xaml | Should -Match 'Binding TextoCompleto'
    }
}

Describe 'USO-03: ordenar la tabla produce un orden con sentido' {

    <#
        Las cabeceras PARECIAN pulsables y no hacian nada: una
        DataGridTemplateColumn no le dice a WPF por que campo ordenar.

        Pero declarar el campo a lo bruto habria sido peor que no ordenar,
        porque produce ordenes absurdos que parecen funcionar. Los dos
        casos estan aqui.
    #>

    It 'el riesgo se ordena por gravedad, no por alfabeto' {
        # Ordenar por la cadena daria Alto, Bajo, Medio: el orden del
        # diccionario, que no significa nada para quien mira la lista.
        $alto  = [Cachivache.ItemVista]::new(); $alto.Riesgo  = 'Alto'
        $medio = [Cachivache.ItemVista]::new(); $medio.Riesgo = 'Medio'
        $bajo  = [Cachivache.ItemVista]::new(); $bajo.Riesgo  = 'Bajo'

        $alto.OrdenRiesgo  | Should -BeLessThan $medio.OrdenRiesgo
        $medio.OrdenRiesgo | Should -BeLessThan $bajo.OrdenRiesgo
    }

    It 'un riesgo desconocido va al final, no al principio' {
        # Si cayera arriba, una fila con un valor raro encabezaria la lista
        # de "lo que hay que mirar" sin merecerlo.
        $raro = [Cachivache.ItemVista]::new(); $raro.Riesgo = 'Loquesea'
        $alto = [Cachivache.ItemVista]::new(); $alto.Riesgo = 'Alto'
        $raro.OrdenRiesgo | Should -BeGreaterThan $alto.OrdenRiesgo
    }

    It 'ordenados de verdad, salen en el orden que espera el usuario' {
        $filas = @('Bajo', 'Alto', 'Medio', 'Bajo') | ForEach-Object {
            $i = [Cachivache.ItemVista]::new(); $i.Riesgo = $_; $i
        }
        $orden = @($filas | Sort-Object OrdenRiesgo | ForEach-Object { $_.Riesgo })
        $orden[0] | Should -Be 'Alto'
        $orden[1] | Should -Be 'Medio'
    }

    It 'el tamano se ordena por Bytes, no por el texto formateado' {
        # "9,52 GB" es alfabeticamente menor que "980 MB", asi que ordenar
        # por el texto pondria 980 MB por encima de 9,52 GB.
        $gb = [Cachivache.ItemVista]::new(); $gb.Bytes = 9.52GB; $gb.Tamano = '9,52 GB'
        $mb = [Cachivache.ItemVista]::new(); $mb.Bytes = 980MB;  $mb.Tamano = '980,0 MB'

        # Lo que haria mal:
        @(@($gb, $mb) | Sort-Object Tamano -Descending)[0].Tamano | Should -Be '980,0 MB'
        # Lo que hace la tabla:
        @(@($gb, $mb) | Sort-Object Bytes  -Descending)[0].Tamano | Should -Be '9,52 GB'
    }
}

Describe 'USO-03: las cinco columnas declaran por que ordenan' {

    BeforeAll {
        $script:XamlOrden = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Panel.Resultados.xaml')),
            '(?s)<!--.*?-->', '')
    }

    It 'ninguna columna se queda sin SortMemberPath' {
        # Una cabecera que parece pulsable y no hace nada es peor que una
        # que no lo parece.
        # El espacio despues del nombre es imprescindible: sin el, el
        # patron caza tambien <DataGridTemplateColumn.CellTemplate> y salen
        # diez en vez de cinco. Lo dijo la propia guarda de abajo.
        $columnas = @([regex]::Matches($script:XamlOrden, '<DataGridTemplateColumn\s[^>]*>'))
        $columnas.Count | Should -Be 5 -Because 'si no son cinco, la prueba mira otra cosa'

        $sinOrden = @($columnas | Where-Object { $_.Value -notmatch 'SortMemberPath' })
        $sinOrden | Should -BeNullOrEmpty
    }

    It 'el tamano ordena por Bytes y el riesgo por OrdenRiesgo' {
        # Con la enye: es texto que lee el usuario, y en mayusculas el
        # espanyol tambien las lleva. Ver [I18N-01].
        $script:XamlOrden | Should -Match 'Header="TAMAÑO"[^>]*SortMemberPath="Bytes"'
        $script:XamlOrden | Should -Match 'Header="RIESGO"[^>]*SortMemberPath="OrdenRiesgo"'
    }

    It 'la lista sale ordenada de mayor a menor al terminar el analisis' {
        $analisis = (Get-Content -LiteralPath (Join-Path $script:Raiz 'src/UI/Window.Analisis.ps1') |
                     Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $analisis | Should -Match "SortDescription 'Bytes'"
        $analisis | Should -Match 'ListSortDirection\]::Descending'
    }
}

Describe 'USO-04: plegar grupos y marcar categorias enteras' {

    BeforeAll {
        $script:XamlG = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Panel.Resultados.xaml')),
            '(?s)<!--.*?-->', '')
        $script:EventosG = [regex]::Replace(
            ((Get-Content -LiteralPath (Join-Path $script:Raiz 'src/UI/Window.Eventos.ps1') |
              Where-Object { $_ -notmatch '^\s*#' }) -join "`n"), '(?s)<#.*?#>', '')
        $script:EstilosG = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Styles.xaml')),
            '(?s)<!--.*?-->', '')
    }

    It 'la cabecera de grupo se puede plegar' {
        $script:XamlG | Should -Match 'ToggleButton x:Name="BtnPlegarGrupo"'
        $script:XamlG | Should -Match 'ElementName=BtnPlegarGrupo'
    }

    It 'los grupos nacen desplegados' {
        # Nacer plegados escondería los resultados recién encontrados, que
        # es justo lo contrario de lo que el usuario acaba de pedir.
        $script:XamlG | Should -Match 'BtnPlegarGrupo"[\s\S]{0,120}IsChecked="True"'
    }

    It 'el conversor que usa el plegado esta declarado' {
        # Un StaticResource que no existe no falla al escribirlo: falla al
        # abrir la ventana, y con la ventana entera.
        $script:EstilosG | Should -Match '<BooleanToVisibilityConverter x:Key="BoolAVisible"/>'
    }

    It 'el ItemsPresenter sigue colgando directamente del Grid' {
        # La virtualizacion depende de esa estructura exacta: meter un
        # Expander u otro contenedor entre medias le da altura infinita a
        # las filas y la lista deja de virtualizar, que con miles de
        # elementos es la diferencia entre usable y colgado.
        $script:XamlG | Should -Match '<ItemsPresenter Grid.Row="1"'
        $script:XamlG | Should -Not -Match '<Expander'
    }

    It 'los dos botones de grupo llevan la categoria en Tag' {
        # Se extrae el ELEMENTO entero y se mira dentro, en vez de permitir
        # "hasta N caracteres". Es la segunda vez hoy que un tope de
        # caracteres en una expresion regular hace fallar una prueba por el
        # tamanyo de un comentario en lugar de por el comportamiento; la
        # primera fue en Papelera.Tests.ps1 y ya escribi alli por que estaba
        # mal. Escribirlo no basta: hay que dejar de hacerlo.
        foreach ($nombre in @('BtnMarcarGrupo', 'BtnQuitarGrupo')) {
            $i = $script:XamlG.IndexOf('<Button x:Name="' + $nombre + '"')
            $i | Should -BeGreaterThan -1 -Because "tiene que existir $nombre"

            $fin = $script:XamlG.IndexOf('/>', $i)
            $fin | Should -BeGreaterThan $i
            $elemento = $script:XamlG.Substring($i, $fin - $i)

            $elemento | Should -BeLike '*Tag="{Binding Name}"*' -Because (
                "$nombre necesita la categoria para saber a quien marcar")
        }
    }

    It 'el manejador distingue por NOMBRE, no por el texto del boton' {
        # Mirar el Content ataria el comportamiento a la etiqueta: cambiar
        # "Marcar" por "Marcar todo" dejaria de marcar sin dar un error.
        $script:EventosG | Should -Match "\`$boton\.Name -eq 'BtnMarcarGrupo'"
        $script:EventosG | Should -Not -Match "\`$boton\.Content -eq"
    }

    It 'el evento se engancha en la TABLA, no en cada boton' {
        # Las cabeceras nacen y mueren con el desplazamiento: no hay ningun
        # boton al que engancharse de forma duradera.
        $script:EventosG | Should -Match 'TablaResultados\.AddHandler'
        $script:EventosG | Should -Match 'ButtonBase\]::ClickEvent'
    }

    It 'marcar respeta lo que no se puede borrar' {
        # Un elemento informativo no se marca ni aunque se pida en bloque.
        $script:EventosG | Should -Match '\$marcar -and -not \$item\.Borrable'
    }

    It 'el marcado en bloque suprime el recalculo del resumen' {
        # Sin esto, marcar doscientas filas dispara doscientos recalculos
        # completos y la ventana se queda en "No responde". Es el mismo
        # fallo que ya obligo a poner esta bandera en el marcado global.
        $i = $script:EventosG.IndexOf('TablaResultados.AddHandler')
        $trozo = $script:EventosG.Substring($i, 1400)
        $trozo | Should -Match '\$estado\.SuprimirResumen = \$true'
        $trozo | Should -Match '\$estado\.SuprimirResumen = \$false'
        $trozo | Should -Match 'actualizarResumenSeleccion'
    }
}
