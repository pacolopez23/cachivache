<#
.SYNOPSIS
    Conexion de los eventos de la ventana: un manejador por control.

.DESCRIPTION
    Es código de pegamento a propósito: cada manejador debería limitarse a llamar a un cierre de Window.Ayudantes.ps1 o a lanzar un trabajo.

    ESTE ARCHIVO NO SE EJECUTA SOLO. Es un trozo del cuerpo de
    Show-VentanaPrincipal (Window.ps1), que lo dot-sourcea desde
    DENTRO de la función. Por eso el código de aquí usa $c, $estado,
    $ventana y los cierres de Window.Ayudantes.ps1 sin declararlos:
    los ve porque se carga en el ámbito de esa función, igual que si
    el texto estuviera pegado allí. Ver docs/ESTRUCTURA.md (sección 3).
#>

    # =================================================================
    #  EVENTOS
    # =================================================================

    # Guardar preferencias en un solo sitio: lo usan el cierre de la
    # ventana, el boton de restablecer y el reinicio como administrador.
    $guardarPreferencias = {
        $estado.Preferencias.ModulosActivos =
            @($estado.ModulosVista | Where-Object { $_.Seleccionado } | ForEach-Object { $_.Id })
        Export-Preferencias -Preferencias $estado.Preferencias -Confirm:$false
    }

    # ---- Barra de titulo ----
    $c.BtnMinimizar.Add_Click({ $ventana.WindowState = 'Minimized' })
    $c.BtnMaximizar.Add_Click({
        $ventana.WindowState = if ($ventana.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
    })
    $c.BtnCerrar.Add_Click({ $ventana.Close() })
    $c.BtnTema.Add_Click({
        & $aplicarTema $(if ($estado.Tema -eq 'oscuro') { 'claro' } else { 'oscuro' })
    })

    # ---- Navegación ----
    $c.NavInicio.Add_Checked({     & $mostrarPanel 'PanelInicio' })
    $c.NavResultados.Add_Checked({ & $mostrarPanel 'PanelResultados' })
    $c.NavRegistro.Add_Checked({   & $mostrarPanel 'PanelRegistro' })
    $c.NavInformes.Add_Checked({   & $refrescarHistorial; & $mostrarPanel 'PanelInformes' })
    $c.NavAjustes.Add_Checked({    & $mostrarPanel 'PanelAjustes' })
    $c.NavAcerca.Add_Checked({     & $mostrarPanel 'PanelAcerca' })

    # ---- Teclado ----
    #
    # [A11Y-04]. No habia ni un atajo: todo se hacia con el raton o
    # tabulando hasta el control.
    #
    # QUE tecla hace QUE lo decide Get-AtajoDeTecla, en Atajos.ps1, que es
    # calculo puro y va probado combinacion por combinacion. Aqui solo se
    # ejecuta, y ejecutar significa LEVANTAR EL CLIC DEL BOTON, no repetir
    # lo que el boton hace. Si este despachador copiase el cuerpo de los
    # manejadores, cada arreglo futuro habria que hacerlo dos veces y una de
    # las dos copias se olvidaria: es literalmente [ARQ-01] otra vez. Asi,
    # el atajo no PUEDE hacer algo distinto del boton, porque hace el boton.
    #
    # Efecto util de eso: los botones ya saben cuando no toca. BtnAnalizar
    # esta deshabilitado mientras se analiza y BtnEliminar mientras no hay
    # nada marcado, y un control deshabilitado no atiende el evento. El
    # atajo hereda gratis todas esas guardas.
    #
    # PreviewKeyDown y no KeyDown: hace falta ver la tecla ANTES que el
    # control que tiene el foco, porque si no una tabla o un cuadro de texto
    # pueden consumirla antes de llegar aqui. El precio de mirar primero es
    # que hay que apartarse a mano de lo que el cuadro de texto necesita, y
    # de eso se encarga EnCuadroDeTexto.
    $ventana.Add_PreviewKeyDown({
        param($origen, $e)

        $control = ([System.Windows.Input.Keyboard]::Modifiers -band
                    [System.Windows.Input.ModifierKeys]::Control) -eq
                   [System.Windows.Input.ModifierKeys]::Control

        $foco = [System.Windows.Input.Keyboard]::FocusedElement
        $enTexto = $foco -is [System.Windows.Controls.TextBox]

        $accion = Get-AtajoDeTecla -Tecla ([string]$e.Key) -Control:$control -EnCuadroDeTexto:$enTexto
        if (-not $accion) { return }

        # Solo se marca como atendida si de verdad era un atajo. Marcarlo
        # antes de saberlo se comeria cada letra que el usuario escribe.
        $e.Handled = $true

        $clic = { param($boton) $boton.RaiseEvent(
                    [System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }

        switch ($accion) {
            'Analizar'   { & $clic $c.BtnAnalizar }
            'MarcarTodo' { & $clic $c.BtnMarcarTodo }

            'Filtrar' {
                # Llevar a Resultados y no solo enfocar el cuadro: buscar es
                # lo que se hace en la tabla, y desde Ajustes un Ctrl+F que
                # pusiera el foco en un cuadro invisible no haria nada
                # visible y pareceria roto.
                $c.NavResultados.IsChecked = $true
                [void] $c.CampoFiltro.Focus()
            }

            'Cancelar' {
                # Cual de los dos, segun cual se pueda pulsar ahora mismo.
                # Se mira lo que el usuario podria hacer con el raton en
                # este instante, en vez de deducirlo de una bandera interna:
                # asi el atajo y el raton no pueden discrepar.
                if ($c.BtnCancelar.Visibility -eq 'Visible' -and $c.BtnCancelar.IsEnabled) {
                    & $clic $c.BtnCancelar
                } elseif ($c.BtnCancelarBorrado.Visibility -eq 'Visible' -and $c.BtnCancelarBorrado.IsEnabled) {
                    & $clic $c.BtnCancelarBorrado
                }
            }

            default {
                # Lo que queda son las seis entradas de la barra lateral.
                # Marcarlas dispara su Checked, que ya muestra el panel y le
                # da el foco: el atajo se anuncia solo. Ver [A11Y-06].
                $c[$accion].IsChecked = $true
            }
        }
    })

    # ---- Módulos ----
    $c.BtnModulosTodos.Add_Click({
        foreach ($vista in $estado.ModulosVista) { if ($vista.Disponible) { $vista.Seleccionado = $true } }
    })
    $c.BtnModulosNinguno.Add_Click({
        foreach ($vista in $estado.ModulosVista) { $vista.Seleccionado = $false }
    })

    # ---- Analizar ----
    $c.BtnAnalizar.Add_Click({
        if ($estado.Ocupado) { return }

        $seleccionados = @($estado.ModulosVista | Where-Object { $_.Seleccionado })
        if ($seleccionados.Count -eq 0) {
            [Windows.MessageBox]::Show('Marca al menos un módulo para analizar.', 'Nada que analizar',
                'OK', 'Information') | Out-Null
            return
        }

        # Sin ninguna unidad marcada el filtro central descarta todos los
        # candidatos, así que el análisis recorreria el disco entero
        # durante minutos para terminar con la lista vacía. Mejor decirlo
        # antes: el aviso del registro solo se ve si el usuario esta
        # mirando esa pestaña.
        if (@($estado.DiscosVista | Where-Object { $_.Seleccionado }).Count -eq 0) {
            [Windows.MessageBox]::Show(
                'No hay ninguna unidad marcada en el panel de la izquierda, así que el análisis no encontraria nada. Marca al menos una.',
                'Ninguna unidad marcada', 'OK', 'Information') | Out-Null
            return
        }

        $estado.Items.Clear()
        $estado.Candidatos.Clear()
        $c.TxtResumenAnalisis.Text = 'Analizando...'
        # El registro NO se vacía al empezar un análisis. Se llama "de la
        # sesión" y antes se borraba entero en cada ejecución, así que al
        # analizar por segunda vez desaparecia lo que había pasado en la
        # primera: precisamente lo que uno quiere comparar. El tope de
        # líneas de $volcarRegistro es lo que impide que crezca sin fin.

        # Los ajustes de la pestaña se aplican siempre. Coherente con el
        # texto del panel: tocarlos pasa el perfil a Personalizado, así que
        # lo que se ve en los controles es SIEMPRE lo que se va a usar.
        $estado.Configuracion.MinimoMB       = [int]$c.SliderMinimoMB.Value
        $estado.Configuracion.DiasSinUso     = [int]$c.SliderDias.Value
        $estado.Configuracion.IncluirMenores = [bool]$c.ChkMenores.IsChecked
        $estado.Configuracion.Permanente     = [bool]$c.ChkPermanente.IsChecked

        $ids = @($seleccionados | ForEach-Object { $_.Id })
        $estado.Cola   = @($estado.Modulos | Where-Object { $ids -contains $_.Id } | Sort-Object Orden)
        $estado.Indice = 0
        $estado.Total  = $estado.Cola.Count
        $estado.Ocupado = $true
        $estado.Fase    = 'analisis'
        $estado.LibreInicial = Get-EspacioLibre $estado.Configuracion.Unidad
        $estado.Cronometro = [Diagnostics.Stopwatch]::StartNew()

        # A cero en CADA análisis. Un aviso de "incompleto" heredado del
        # anterior seria la misma mentira con el signo cambiado: asustar
        # sobre una lista que esta vez si esta entera. Ver [CNF-04].
        $estado.AnalisisCancelado = $false
        $estado.ModulosFallidos.Clear()
        $c.AvisoIncompleto.Visibility = 'Collapsed'
        $c.TxtAvisoIncompleto.Text    = ''

        # El cartel de la tabla vacia, al momento. La lista se acaba de
        # vaciar, asi que sin esta llamada se quedaria un "el análisis
        # encontró 812 elementos" del anterior colgado sobre una tabla que
        # ya no tiene ninguno, hasta que terminara el primer módulo. Ver
        # [USO-09].
        & $actualizarEstadoVacio

        $c.BtnAnalizar.IsEnabled  = $false
        # El boton de eliminar se apaga AQUÍ y no cuando termine el primer
        # módulo, que puede tardar minutos: hasta ahora se quedaba activo
        # con la cuenta del análisis anterior, y al pulsarlo su manejador
        # salia por "if Ocupado return" sin decir nada. Un boton encendido
        # que no hace nada es indistinguible de uno roto.
        $c.BtnEliminar.IsEnabled  = $false
        $c.TxtSeleccion.Text      = 'Nada marcado.'
        $c.TxtProyeccion.Text     = 'Analizando: la lista se irá llenando sola.'
        $c.BtnCancelar.Visibility = 'Visible'
        # Se reactiva por si venia deshabilitado de haber cancelado antes.
        $c.BtnCancelar.IsEnabled  = $true
        $c.BarraInicio.Visibility = 'Visible'
        $c.BarraInicio.Value = 0

        & $escribir ('ANALISIS - perfil {0}, {1} modulos. No se va a borrar nada.' -f `
                     $estado.Configuracion.Perfil, $estado.Total)
        & $escribir ('Umbrales: mínimo {0} MB, {1} días sin usar, elementos pequeños: {2}.' -f `
                     $estado.Configuracion.MinimoMB, $estado.Configuracion.DiasSinUso,
                     $(if ($estado.Configuracion.IncluirMenores) { 'si' } else { 'no' }))
        & $siguienteModulo
    })

    $c.BtnCancelar.Add_Click({
        if (-not $estado.Ocupado) { return }

        # Levantar la bandera NO basta, y esa era la razón de que el boton
        # pareciera no hacer nada: los módulos solo la consultan entre
        # iteraciones, así que uno que este midiendo una carpeta enorme no
        # vuelve a mirarla hasta que termina, y eso pueden ser minutos.
        # Hay que parar el runspace de verdad, que es justo lo que ya hacia
        # limpiarTrabajo al cerrar la ventana.
        #
        # Ojo: al parar el runspace, la línea "$sync.Terminado = $true" del
        # final del guion puede no llegar a ejecutarse nunca, así que el
        # temporizador no se enteraria de que ha acabado. Por eso aquí se
        # cierra el análisis a mano en vez de esperar al siguiente tick.
        $estado.Sync.Cancelar    = $true
        $c.BtnCancelar.IsEnabled = $false
        $c.TxtEstadoInicio.Text  = 'Cancelando el análisis...'

        & $limpiarTrabajo
        & $escribir 'Análisis cancelado por el usuario.' 'AVISO'
        & $terminarAnalisis
    })

    $c.BtnCancelarBorrado.Add_Click({
        if (-not $estado.Ocupado) { return }

        # Lo ya borrado se queda borrado; simplemente no se sigue. Mismo
        # motivo que en el boton de cancelar el análisis: la bandera sola
        # no corta un borrado que este dentro de una operación larga.
        $estado.Sync.Cancelar           = $true
        $c.BtnCancelarBorrado.IsEnabled = $false
        $c.TxtSeleccion.Text            = 'Deteniendo la eliminación...'

        & $limpiarTrabajo
        & $escribir 'Eliminación detenida por el usuario.' 'AVISO'
        & $terminarBorrado
    })

    # ---- Filtros y selección ----
    # El cuadro de texto pide el filtro y el temporizador decide cuando:
    # escribir "chrome" son seis teclas y una sola pasada por la tabla, no
    # seis. La lista de riesgo va directa porque elegir en un desplegable
    # no se encadena como se encadenan las pulsaciones.
    $c.CampoFiltro.Add_TextChanged({ & $solicitarFiltro })
    $c.FiltroRiesgo.Add_SelectionChanged({ & $aplicarFiltro })

    # El boton del cartel de tabla vacia. No se engancha por $c sino por
    # la lista de $c de Window.ps1, como todos los demas controles;
    # alli esta explicado por que, y tests/EstadoVacio.Tests.ps1 le pone la
    # misma invariante que $c tiene. Ver [USO-09].
    if ($null -ne $c.BtnQuitarFiltros) {
        $c.BtnQuitarFiltros.Add_Click({ & $quitarFiltros })
    }

    # Marcar en lote suprime el recalculo del resumen mientras dura la
    # operación y lo hace una sola vez al final. Sin esto, marcar cinco mil
    # filas recalcularia el resumen cinco mil veces y congelaria la ventana.
    #
    # No se desengancha el manejador porque remove_PropertyChanged no
    # sirve con un scriptblock: PowerShell construye un delegado nuevo en
    # cada conversión, así que nunca coincidiria con el que se enganycho.
    #
    # Se recorre LA VISTA, no $estado.Items. Es la diferencia entre marcar
    # lo que el usuario esta viendo y marcar todo el análisis: con un
    # filtro puesto ("chrome", o "solo riesgo bajo"), recorrer Items
    # marcaba también las filas ocultas, y el siguiente clic en "Eliminar
    # lo marcado" las borraba. El usuario creia estar actuando sobre una
    # docena de elementos y actuaba sobre miles que no había visto nunca.
    # En un programa que borra archivos eso no es un detalle.
    #
    # Sin filtro, la vista contiene exactamente lo mismo que Items, así que
    # el caso normal no cambia en nada.
    $marcarEnLote = {
        param([scriptblock] $Criterio)
        if ($null -eq $estado.Vista) { return }
        $estado.SuprimirResumen = $true
        try {
            # Se materializa con @() antes de tocar nada: modificar los
            # elementos mientras se enumera una CollectionView con filtro
            # es pedirle problemas al enumerador.
            foreach ($item in @($estado.Vista)) { $item.Seleccionado = [bool](& $Criterio $item) }
        } finally {
            $estado.SuprimirResumen = $false
        }
        & $actualizarResumenSeleccion
    }

    $c.BtnMarcarTodo.Add_Click({
        & $marcarEnLote { param($i) $i.Borrable -and -not $i.Hecho }
    })
    $c.BtnDesmarcarTodo.Add_Click({
        & $marcarEnLote { param($i) $false }
    })
    $c.BtnSoloSeguros.Add_Click({
        & $marcarEnLote {
            param($i)
            $i.Borrable -and -not $i.Hecho -and $i.Riesgo -eq 'Bajo' -and
            [string]::IsNullOrWhiteSpace($i.Aviso)
        }
    })

    # Antes este boton se quedaba callado en tres situaciones distintas
    # -sin fila elegida, con una ruta que ya no existe, y con el método
    # 'Comando', que no tiene ruta de verdad sino una etiqueta-, y las tres
    # se parecian mucho a un boton roto. Ahora cada una dice lo suyo.
    # ---- Ver que hay dentro ([USO-05]) ----
    $c.BtnVerContenido.Add_Click({
        $item = $c.TablaResultados.SelectedItem
        if ($null -eq $item) {
            Show-Aviso -Mensaje 'Elige antes una fila de la lista: es su contenido el que se mira.' -Tipo 'Information'
            return
        }
        if ($item.Metodo -eq 'Comando') {
            Show-Aviso -Tipo 'Information' -Mensaje (
                "Este elemento no es una carpeta: es un comando del sistema ({0}), asi que no hay nada dentro que mirar." -f $item.Comando)
            return
        }

        # El recorrido puede tardar unos segundos en una cache con cien mil
        # archivos, y durante ese rato la ventana no responde. Se avisa con
        # el cursor, que es lo que todo el mundo entiende, en vez de dejar
        # que parezca colgada: la misma idea que [USO-07], en pequenyo.
        #
        # No se manda al runspace a proposito: ese runspace lo comparte el
        # analisis, vive y muere con el, y meter aqui un trabajo ajeno
        # significaria pelearse por el con [INT-01]. Para una espera de
        # segundos, el cursor es la respuesta proporcionada.
        $ventana.Cursor = [Windows.Input.Cursors]::Wait
        try {
            $detalle = Get-DetalleCarpeta -Ruta $item.Ruta
            $texto   = Format-DetalleCarpeta -Detalle $detalle -Ruta $item.Ruta
        } catch {
            & $escribir ('No se ha podido mirar dentro de {0}: {1}' -f
                         $item.Ruta, (Get-DetalleExcepcion -ErrorRecord $_ -ConPila)) 'AVISO'
            $texto = 'No se ha podido mirar dentro: ' + (Get-DetalleExcepcion -ErrorRecord $_)
        } finally {
            $ventana.Cursor = $null
        }

        Show-Aviso -Titulo ('Contenido de {0}' -f $item.Nombre) -Mensaje $texto -Tipo 'Information'
    })

    $c.BtnAbrirCarpeta.Add_Click({
        $item = $c.TablaResultados.SelectedItem
        if ($null -eq $item) {
            Show-Aviso -Mensaje 'Elige antes una fila de la lista: es su carpeta la que se abre.' -Tipo 'Information'
            return
        }
        if ($item.Metodo -eq 'Comando') {
            Show-Aviso -Mensaje ("Este elemento no es un archivo ni una carpeta: es un comando del sistema ({0}), así que no hay ninguna ubicación que abrir." -f $item.Comando) -Tipo 'Information'
            return
        }

        $ruta = $item.Ruta
        if ([string]::IsNullOrWhiteSpace($ruta) -or -not (Test-Path -LiteralPath $ruta)) {
            Show-Aviso -Mensaje ("Ya no existe: {0}`n`nO se ha borrado o movido desde el análisis. Vuelve a analizar para tener la lista al dia." -f $ruta) -Tipo 'Warning'
            return
        }

        try {
            if ((Get-Item -LiteralPath $ruta -Force).PSIsContainer) {
                Start-Process -FilePath (Get-RutaExplorador) -ArgumentList "`"$ruta`""
            } else {
                Start-Process -FilePath (Get-RutaExplorador) -ArgumentList "/select,`"$ruta`""
            }
        } catch {
            Show-Aviso -Mensaje ("No se ha podido abrir la ubicación:`n{0}" -f $_.Exception.Message) -Tipo 'Warning'
        }
    })

    # ---- Eliminar ----
    $c.BtnEliminar.Add_Click({
        if ($estado.Ocupado) { return }
        $marcados = @($estado.Items | Where-Object { $_.Seleccionado -and $_.Borrable -and -not $_.Hecho })
        if ($marcados.Count -eq 0) { return }

        $bytes = 0.0
        foreach ($item in $marcados) { $bytes += $item.Bytes }
        # Un comando externo entra SIEMPRE en la lista de riesgo, tenga el
        # riesgo o el aviso que tenga: SECURITY.md exige que sea "siempre
        # visible... y siempre con confirmación". Ver [C-03] en
        # docs/OPTIMIZACIONES.md.
        $arriesgados = @($marcados | Where-Object {
            $_.Riesgo -ne 'Bajo' -or -not [string]::IsNullOrWhiteSpace($_.Aviso) -or $_.Metodo -eq 'Comando'
        })

        $simular = [bool]$c.ChkSimular.IsChecked
        $estado.Configuracion.Simular = $simular

        # Simular no pide confirmación: no hay nada que confirmar. El
        # diálogo existe para que nadie borre cuatro mil cosas sin querer,
        # y aquí no se borra ninguna. Preguntar igualmente enseñaría al
        # usuario a decir "Sí" sin leer, que es la forma más segura de
        # arruinar la única defensa que queda cuando SÍ se borra de verdad.
        if (-not $simular) {
            $confirmado = Show-Confirmacion -Propietario $ventana -CarpetaUi $estado.CarpetaUi `
                                            -Elementos $marcados.Count -Bytes $bytes `
                                            -Permanente $estado.Configuracion.Permanente `
                                            -Arriesgados $arriesgados
            if (-not $confirmado) {
                & $escribir 'Eliminación cancelada en la confirmación.' 'AVISO'
                return
            }
        }

        $lote = @($marcados | ForEach-Object { $_.Origen })
        $estado.Ocupado       = $true
        $estado.Fase          = 'borrado'
        $estado.SimulandoLote = $simular
        $estado.Total   = $lote.Count
        $estado.LibreInicial = Get-EspacioLibre $estado.Configuracion.Unidad

        $c.BtnEliminar.IsEnabled   = $false
        $c.BtnAnalizar.IsEnabled   = $false
        # De la limpieza anterior. Ofrecer "abrir la papelera" cuando la
        # limpieza en curso todavia no ha mandado nada alli seria hablar de
        # otra cosa. Ver [CNF-03].
        $c.BtnAbrirPapelera.Visibility = 'Collapsed'
        $c.BarraBorrado.Visibility = 'Visible'
        $c.BarraBorrado.Value      = 0
        # También se puede parar a mitad de una eliminación: lo ya borrado
        # se queda borrado, pero no se sigue con el resto.
        $c.BtnCancelarBorrado.Visibility = 'Visible'
        # Se reactiva por si venia deshabilitado de haber parado antes.
        $c.BtnCancelarBorrado.IsEnabled  = $true

        & $escribir ''
        if ($simular) {
            & $escribir ('SIMULANDO {0} elementos ({1}). No se va a borrar nada.' -f `
                         $lote.Count, (Format-Tamano $bytes)) 'SIMULACION'
        } else {
            & $escribir ('ELIMINANDO {0} elementos ({1}). Destino: {2}.' -f `
                         $lote.Count, (Format-Tamano $bytes),
                         $(if ($estado.Configuracion.Permanente) { 'borrado permanente' } else { 'papelera de reciclaje' })) 'BORRADO'
        }

        & $lanzarTrabajo $codigoBorrado @{
            lote       = $lote
            permanente = $estado.Configuracion.Permanente
            simular    = $simular
        }
    })

    # ---- Simular ----
    # El boton rojo tiene que decir lo que va a hacer. Con la casilla
    # marcada, "Eliminar lo marcado" es falso, y el estilo de peligro
    # -rojo, el color de "esto no tiene vuelta atras"- tambien lo es.
    $sincronizarSimular = {
        if ([bool]$c.ChkSimular.IsChecked) {
            $c.BtnEliminar.Content = 'Simular limpieza'
            $c.BtnEliminar.Style   = $ventana.FindResource('BotonSecundario')
        } else {
            $c.BtnEliminar.Content = 'Eliminar lo marcado'
            $c.BtnEliminar.Style   = $ventana.FindResource('BotonPeligro')
        }
    }
    $c.ChkSimular.Add_Checked($sincronizarSimular)
    $c.ChkSimular.Add_Unchecked($sincronizarSimular)

    # ---- Registro ----
    $c.BtnCopiarRegistro.Add_Click({
        try { [Windows.Clipboard]::SetText($c.Consola.Text) }
        catch { Show-Aviso -Mensaje 'Otro programa esta bloqueando el portapapeles.' -Tipo 'Warning' }
    })
    $c.BtnAbrirRegistro.Add_Click({
        # Con try/catch como el resto: si la carpeta todavía no existe o el
        # Explorador falla, la excepción escapaba del manejador. Antes eso
        # mataba la ventana entera; ahora la atrapa el manejador global,
        # pero no hay motivo para llegar hasta ahi por abrir una carpeta.
        try { Start-Process -FilePath (Get-RutaExplorador) -ArgumentList "`"$(Join-Path $estado.Configuracion.CarpetaDatos 'registros')`"" }
        catch { Show-Aviso -Mensaje "No se ha podido abrir la carpeta del registro:`n$($_.Exception.Message)" -Tipo 'Warning' }
    })

    # ---- Informes ----
    $exportar = {
        param([string] $Formato)
        if ($estado.Candidatos.Count -eq 0) {
            [Windows.MessageBox]::Show('Analiza el equipo primero: todavía no hay nada que exportar.',
                'Sin datos', 'OK', 'Information') | Out-Null
            return
        }
        # DOS try separados a proposito.
        #
        # Antes eran uno solo, con Start-Process dentro. Si el informe se
        # guardaba bien pero fallaba al abrir el Explorador, el programa
        # decia "No se ha podido guardar el informe" con el archivo ya
        # escrito en el disco. Es la misma familia de mentira que el resto
        # de la auditoria: el programa contando algo distinto de lo que
        # paso. Ver [COR-06] en docs/HOJA-DE-RUTA.md.
        $ruta = $null
        try {
            $ruta = New-NombreInforme -Tipo 'analisis' -Extension $Formato -CarpetaDatos $estado.Configuracion.CarpetaDatos
            switch ($Formato) {
                'html' { Export-InformeHtml -Candidatos $estado.Candidatos -Ruta $ruta -Configuracion $estado.Configuracion -Modulos $estado.Modulos -Confirm:$false }
                'csv'  { Export-InformeCsv  -Candidatos $estado.Candidatos -Ruta $ruta -Confirm:$false }
                'json' { Export-InformeJson -Candidatos $estado.Candidatos -Ruta $ruta -Configuracion $estado.Configuracion -Confirm:$false }
            }
            & $escribir ('Informe guardado: {0}' -f $ruta)
        } catch {
            # Al registro, con pila: es lo que se adjunta en una incidencia.
            # A la pantalla, con archivo y linea pero sin pila, que en un
            # cuadro de dialogo no la lee nadie.
            & $escribir ('No se ha podido guardar el informe: {0}' -f (Get-DetalleExcepcion -ErrorRecord $_ -ConPila)) 'ERROR'
            Show-Aviso -Tipo 'Error' -Titulo 'Error' -Mensaje (
                "No se ha podido guardar el informe:`n{0}`n`nEl detalle completo está en el registro (pestaña Registro)." -f
                (Get-DetalleExcepcion -ErrorRecord $_))
            return
        }

        try {
            Start-Process -FilePath (Get-RutaExplorador) -ArgumentList "/select,`"$ruta`""
        } catch {
            # El informe SI esta guardado. Se dice donde, y ya.
            & $escribir ('El informe esta guardado, pero no se ha podido abrir el Explorador: {0}' -f
                         (Get-DetalleExcepcion -ErrorRecord $_)) 'AVISO'
        }
    }
    $c.BtnExportarHtml.Add_Click({ & $exportar 'html' })
    $c.BtnExportarCsv.Add_Click({  & $exportar 'csv' })
    $c.BtnExportarJson.Add_Click({ & $exportar 'json' })
    $c.BtnExportar.Add_Click({     & $exportar 'html' })

    # ---- Marcar y quitar una categoria entera ([USO-04]) ----
    #
    # Los dos botones viven DENTRO de la plantilla de la cabecera de grupo,
    # asi que no tienen nombre y $ventana.FindName no los encuentra: las
    # cabeceras las crea y las destruye el panel virtualizado segun te
    # desplazas. Por eso el evento se engancha en la TABLA y se mira quien
    # lo disparo. Es la forma estandar de tratar con controles que nacen y
    # mueren dentro de una plantilla.
    $c.TablaResultados.AddHandler(
        [Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [Windows.RoutedEventHandler]{
            param($remitente, $argumentos)

            $boton = $argumentos.OriginalSource -as [Windows.Controls.Button]
            if ($null -eq $boton) { return }

            $categoria = [string]$boton.Tag
            if ([string]::IsNullOrWhiteSpace($categoria)) { return }

            # Por NOMBRE, no por el texto del boton. Mirar el Content
            # ataria el comportamiento a la etiqueta: cambiar "Marcar" por
            # "Marcar todo" dejaria de marcar sin dar ningun error.
            if ($boton.Name -eq 'BtnMarcarGrupo')      { $marcar = $true }
            elseif ($boton.Name -eq 'BtnQuitarGrupo')  { $marcar = $false }
            else { return }

            # La misma bandera que usa el marcado global: sin ella, cambiar
            # doscientas casillas dispara doscientos recalculos completos
            # del resumen del pie, cada uno recorriendo la lista entera.
            # Es el fallo que dejaba la ventana en "No responde".
            $estado.SuprimirResumen = $true
            try {
                foreach ($item in $estado.Items) {
                    if ($item.Categoria -ne $categoria) { continue }
                    # Marcar respeta lo que NO se puede borrar; quitar vale
                    # para todo, porque desmarcar nunca hace danyo.
                    if ($marcar -and -not $item.Borrable) { continue }
                    $item.Seleccionado = $marcar
                }
            } finally {
                $estado.SuprimirResumen = $false
            }
            & $actualizarResumenSeleccion
        })

    # ---- Abrir la papelera ([CNF-03]) ----
    #
    # Es el paso honesto y barato hacia el deshacer: el programa ya manda
    # a la papelera, asi que lo unico que faltaba era llevar al usuario
    # hasta ella. Un boton de "deshacer" de verdad -restaurar solo lo de
    # esta limpieza, en su sitio- exige IFileOperation por COM y no se
    # puede escribir a ciegas; ver la nota de [CNF-03] en la hoja de ruta.
    #
    # shell:RecycleBinFolder es el nombre que entiende el Explorador, no
    # una ruta: no se puede validar con Test-Path ni pasa por la guardia,
    # y no hace falta, porque aqui no se borra nada.
    $c.BtnAbrirPapelera.Add_Click({
        try {
            Start-Process -FilePath (Get-RutaExplorador) -ArgumentList 'shell:RecycleBinFolder'
        } catch {
            Show-Aviso -Tipo 'Warning' -Mensaje (
                "No se ha podido abrir la papelera:`n{0}" -f (Get-DetalleExcepcion -ErrorRecord $_))
        }
    })

    # ---- Abrir un informe ----
    # Único punto del programa que abre un archivo con el programa
    # predeterminado del sistema, y por tanto el único sitio donde hay que
    # mirar para saber que puede llegar a lanzarse. La ruta se vuelve a
    # validar aquí aunque ya viniera validada al construir la lista: entre
    # que se pinto la lista y este clic pueden haber pasado horas, y en ese
    # rato el archivo ha podido cambiar, desaparecer o ser sustituido por
    # un enlace a otro sitio.
    $abrirInforme = {
        param([string] $Ruta)
        $valida = Resolve-InformeAbrible -Ruta $Ruta -CarpetaDatos $estado.Configuracion.CarpetaDatos
        if ($null -eq $valida) {
            [Windows.MessageBox]::Show(
                "Este informe ya no se puede abrir.`n`nO se ha borrado o movido, o no esta donde el programa guarda los informes. Solo se abren archivos .html, .csv y .json de esa carpeta.",
                'Informe no disponible', 'OK', 'Warning') | Out-Null
            & $refrescarHistorial
            return
        }
        try {
            Start-Process -FilePath $valida
        } catch {
            [Windows.MessageBox]::Show("No se ha podido abrir el informe:`n$($_.Exception.Message)",
                'Error', 'OK', 'Error') | Out-Null
        }
    }

    # Se usa ListBox con SelectionChanged, no un boton dentro de la
    # plantilla: así el manejador es un evento normal de un control con
    # nombre, igual que el resto de la ventana. La selección se deshace
    # justo después para que la fila no quede marcada y se pueda volver a
    # pulsar la misma; al ponerla a -1 el evento vuelve a entrar, pero
    # entonces SelectedItem ya es $null y se sale por la primera línea.
    $abrirSeleccionInforme = {
        param($Lista)
        $seleccion = $Lista.SelectedItem
        if ($null -eq $seleccion) { return }
        $Lista.SelectedIndex = -1
        & $abrirInforme $seleccion.Ruta
    }

    $c.ListaInformesHtml.Add_SelectionChanged({ & $abrirSeleccionInforme $c.ListaInformesHtml })
    $c.ListaInformesCsv.Add_SelectionChanged({  & $abrirSeleccionInforme $c.ListaInformesCsv  })
    $c.ListaInformesJson.Add_SelectionChanged({ & $abrirSeleccionInforme $c.ListaInformesJson })

    $c.ListaHistorial.Add_SelectionChanged({
        $entrada = $c.ListaHistorial.SelectedItem
        if ($null -eq $entrada) { return }
        $c.ListaHistorial.SelectedIndex = -1
        # Las ejecuciones anteriores a esta versión, y aquellas cuyo
        # informe se genero mal o se ha borrado, no tienen nada que abrir.
        # Se dice, en vez de no hacer nada.
        if ([string]::IsNullOrEmpty($entrada.Informe)) {
            [Windows.MessageBox]::Show(
                "Esta ejecución no tiene ningún informe guardado.`n`nDesde ahora, cada análisis y cada limpieza generan el suyo automáticamente; las ejecuciones anteriores a este cambio solo dejaron el resumen que ves en la tarjeta.",
                'Sin informe', 'OK', 'Information') | Out-Null
            return
        }
        & $abrirInforme $entrada.Informe
    })

    # ---- Ajustes ----
    # Tocar cualquier umbral pasa el perfil a Personalizado. Sin esto, la
    # interfaz decia "estos valores se aplican al perfil Personalizado"
    # mientras el código los aplicaba SIEMPRE: podias tener marcado
    # "Equilibrado" y estar analizando con umbrales que no son los suyos,
    # sin ninguna pista de que ya no estabas en ese perfil.
    $pasarAPersonalizado = {
        # No cuando somos nosotros quienes movemos los controles al elegir
        # un perfil: eso lo convertiria en Personalizado al instante.
        if ($estado.SincronizandoPerfil) { return }
        $vista = @($estado.PerfilesVista | Where-Object { $_.Id -eq 'personalizado' })[0]
        if ($null -ne $vista -and -not $vista.Activo) { $vista.Activo = $true }
    }

    # El objeto de configuración que lee el runspace de trabajo ES EL MISMO
    # que hay aquí, no una copia: se le pasa por referencia al lanzarlo. Y
    # nada impedia llegar a Ajustes o a las tarjetas de perfil con un
    # análisis en marcha, porque la navegación no se bloquea. Cambiar de
    # perfil a mitad de la cola reescribia los umbrales entre módulo y
    # módulo: la primera mitad del análisis usaba unos y la segunda otros,
    # y el informe y el historial declaraban un solo perfil. Además son
    # escrituras sobre un objeto que otro hilo esta leyendo.
    #
    # Se deshace el cambio en el control además de ignorarlo, para que lo
    # que se ve siga siendo lo que se esta usando.
    $ajusteBloqueadoPorTrabajo = {
        # Si la bandera ya esta puesta, quien mueve los controles somos
        # nosotros y no hay nada que bloquear. Sin esta línea habría
        # recursion infinita: deshacer el cambio vuelve a disparar los
        # manejadores, que vuelven a entrar aquí.
        if ($estado.SincronizandoPerfil) { return $false }
        if (-not $estado.Ocupado) { return $false }
        $estado.SincronizandoPerfil = $true
        try {
            $c.SliderMinimoMB.Value    = $estado.Configuracion.MinimoMB
            $c.SliderDias.Value        = $estado.Configuracion.DiasSinUso
            $c.ChkMenores.IsChecked    = $estado.Configuracion.IncluirMenores
            $c.ChkPermanente.IsChecked = $estado.Configuracion.Permanente
        } finally {
            $estado.SincronizandoPerfil = $false
        }
        Show-Aviso -Mensaje 'Hay un análisis o una limpieza en marcha. Los ajustes se aplican al empezar, así que cambiarlos ahora dejaria el trabajo a medias con dos configuraciones distintas. Espera a que termine o cancelalo.' -Tipo 'Information'
        return $true
    }

    $c.SliderMinimoMB.Add_ValueChanged({
        if (& $ajusteBloqueadoPorTrabajo) { return }
        $c.TxtMinimoMB.Text = '{0} MB' -f [int]$c.SliderMinimoMB.Value
        $estado.Preferencias.MinimoMB = [int]$c.SliderMinimoMB.Value
        & $pasarAPersonalizado
    })
    $c.SliderDias.Add_ValueChanged({
        if (& $ajusteBloqueadoPorTrabajo) { return }
        $c.TxtDiasSinUso.Text = '{0} dias' -f [int]$c.SliderDias.Value
        $estado.Preferencias.DiasSinUso = [int]$c.SliderDias.Value
        & $pasarAPersonalizado
    })
    # Add_Checked + Add_Unchecked, no Add_Click. Click SOLO se levanta
    # cuando el usuario pulsa: asignar IsChecked desde el código -que es lo
    # que hacen elegir un perfil y "Restablecer ajustes"- no lo dispara
    # nunca. Consecuencia real y peligrosa: marcabas "borrado permanente" a
    # mano, luego elegias Conservador, la casilla se desmarcaba en pantalla
    # y $estado.Preferencias.Permanente se quedaba en $true; en el arranque
    # siguiente la casilla volvia a aparecer MARCADA, en contra de la
    # última decisión del usuario. El borrado permanente se rearmaba solo.
    # Los sliders no tenian el problema porque ValueChanged si se levanta
    # por código, y por eso el fallo pasaba desapercibido.
    $sincronizarMenores = {
        if (& $ajusteBloqueadoPorTrabajo) { return }
        $estado.Preferencias.IncluirMenores = [bool]$c.ChkMenores.IsChecked
        & $pasarAPersonalizado
    }
    $c.ChkMenores.Add_Checked($sincronizarMenores)
    $c.ChkMenores.Add_Unchecked($sincronizarMenores)

    $sincronizarPermanente = {
        if (& $ajusteBloqueadoPorTrabajo) { return }
        $estado.Preferencias.Permanente = [bool]$c.ChkPermanente.IsChecked
        & $pasarAPersonalizado
    }
    $c.ChkPermanente.Add_Checked($sincronizarPermanente)
    $c.ChkPermanente.Add_Unchecked($sincronizarPermanente)

    $c.BtnAbrirDatos.Add_Click({
        try { Start-Process -FilePath (Get-RutaExplorador) -ArgumentList "`"$($estado.Configuracion.CarpetaDatos)`"" }
        catch { Show-Aviso -Mensaje "No se ha podido abrir la carpeta de datos:`n$($_.Exception.Message)" -Tipo 'Warning' }
    })

    $c.BtnRestablecer.Add_Click({
        if ($estado.Ocupado) {
            Show-Aviso -Mensaje 'Hay un análisis o una limpieza en marcha. Espera a que termine o cancelalo antes de restablecer los ajustes.' -Tipo 'Information'
            return
        }

        $respuesta = [Windows.MessageBox]::Show(
            ('Se van a restablecer los umbrales, el perfil, los módulos marcados y la ' +
             'selección de discos. El tema y el historial no se tocan.' + [Environment]::NewLine +
             [Environment]::NewLine + 'Continuar?'),
            'Restablecer ajustes', 'YesNo', 'Question')
        if ($respuesta -ne 'Yes') { return }

        # Volver al perfil por defecto también devuelve los umbrales a sus
        # valores, así que se hace primero y después se refresca todo.
        $vista = @($estado.PerfilesVista | Where-Object { $_.Id -eq 'equilibrado' })[0]
        if ($null -ne $vista) { $vista.Activo = $true }

        $estado.SincronizandoPerfil = $true
        try {
            $c.SliderMinimoMB.Value    = $estado.Configuracion.MinimoMB
            $c.SliderDias.Value        = $estado.Configuracion.DiasSinUso
            $c.ChkMenores.IsChecked    = $estado.Configuracion.IncluirMenores
            $c.ChkPermanente.IsChecked = $estado.Configuracion.Permanente
        } finally {
            $estado.SincronizandoPerfil = $false
        }

        # Todos los discos vuelven a entrar en el análisis.
        $estado.Preferencias.UnidadesExcluidas = @()
        foreach ($disco in $estado.DiscosVista) { $disco.Seleccionado = $true }

        & $refrescarModulos

        # Se guarda al momento: antes solo se escribia al cerrar la ventana,
        # así que un restablecimiento se perdia si el programa no se cerraba
        # con normalidad.
        & $guardarPreferencias
        & $escribir 'Ajustes restablecidos: perfil Equilibrado, umbrales por defecto, todos los discos.'
    })

    $c.BtnReiniciarAdmin.Add_Click({
        $entrada = Join-Path $estado.Raiz 'Cachivache.ps1'
        try {
            # Guardar ANTES de lanzar la copia elevada. Al revés había una
            # carrera: la instancia nueva lee preferencias.json al arrancar
            # y podia hacerlo antes de que esta lo escribiera al cerrarse,
            # con lo que el usuario perdia los ajustes que acababa de tocar
            # justo al pasar a modo administrador.
            & $guardarPreferencias

            Start-Process -FilePath (Get-RutaPowerShell) -Verb RunAs -ArgumentList @(
                '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$entrada`""
            )
            $ventana.Close()
        } catch {
            [Windows.MessageBox]::Show('No se ha podido reiniciar con permisos de administrador.',
                'Permisos', 'OK', 'Warning') | Out-Null
        }
    })

    $c.BtnRepositorio.Add_Click({
        try { Start-Process $script:RepositorioUrl }
        catch { Show-Aviso -Mensaje "No se ha podido abrir el navegador. La direccion es: $script:RepositorioUrl" }
    })

    # ---- Perfiles ----
    foreach ($perfil in (Get-PerfilesLimpieza)) {
        $vista = New-Object Cachivache.PerfilVista
        $vista.Id      = $perfil.Id
        $vista.Nombre  = $perfil.Nombre
        $vista.Resumen = $perfil.Resumen
        $vista.Activo  = ($perfil.Id -eq $estado.Configuracion.Perfil)
        $vista.add_PropertyChanged({
            param($remitente, $argumentos)
            if ($argumentos.PropertyName -ne 'Activo' -or -not $remitente.Activo) { return }

            # Set-PerfilConfiguracion MUTA el objeto de configuración, que
            # es el mismo que esta leyendo el runspace de trabajo. Cambiar
            # de perfil a mitad de un análisis reescribia los umbrales
            # entre módulo y módulo. Se ignora y se deja la tarjeta como
            # estaba.
            if ($estado.Ocupado) {
                $estado.SincronizandoPerfil = $true
                try {
                    foreach ($otro in $estado.PerfilesVista) {
                        $otro.Activo = ($otro.Id -eq $estado.Configuracion.Perfil)
                    }
                } finally {
                    $estado.SincronizandoPerfil = $false
                }
                Show-Aviso -Mensaje 'Hay un análisis o una limpieza en marcha. El perfil se aplica al empezar, así que cambiarlo ahora dejaria el trabajo a medias con dos configuraciones distintas. Espera a que termine o cancelalo.' -Tipo 'Information'
                return
            }

            $estado.Configuracion = Set-PerfilConfiguracion -Configuracion $estado.Configuracion -Perfil $remitente.Id
            $estado.Preferencias.Perfil = $remitente.Id
            if ($remitente.Id -ne 'personalizado') {
                # La bandera evita que mover estos controles por nuestra
                # cuenta dispare el paso a Personalizado.
                $estado.SincronizandoPerfil = $true
                try {
                    $c.SliderMinimoMB.Value    = $estado.Configuracion.MinimoMB
                    $c.SliderDias.Value        = $estado.Configuracion.DiasSinUso
                    $c.ChkMenores.IsChecked    = $estado.Configuracion.IncluirMenores
                    # Faltaba: quedaba marcado el borrado permanente de antes
                    # aunque el perfil elegido diga que no.
                    $c.ChkPermanente.IsChecked = $estado.Configuracion.Permanente
                } finally {
                    $estado.SincronizandoPerfil = $false
                }
                # Solo un perfil con nombre reescribe que módulos entran:
                # es lo que significa elegirlo. Pasar a Personalizado, en
                # cambio, se conserva lo que hay marcado en pantalla -y es
                # imprescindible que sea así, porque a Personalizado se
                # llega precisamente al tocar una casilla de módulo:
                # refrescar aquí borraria el clic que acaba de traernos.
                & $refrescarModulos
            }
        }.GetNewClosure())
        $estado.PerfilesVista.Add($vista)
    }

    # ---- Guardado de preferencias al cerrar ----
    $ventana.Add_Closing({
        # Los parametros del evento se declaran aunque hoy no se usen: sin
        # ellos es IMPOSIBLE cancelar el cierre, y ese es el unico gancho
        # que hay para reaccionar a que el usuario cierre la ventana en
        # mitad de algo. Ver [INT-04] en docs/PLAN-ACCION.md.
        param($remitente, $argumentos)

        $estabaBorrando = $estado.Ocupado -and $estado.Fase -eq 'borrado'

        $estado.Sync.Cancelar = $true
        & $limpiarTrabajo
        # Si quedaba una cuenta atras del filtro en marcha, se corta: un
        # tick después del cierre iria a tocar controles de una ventana que
        # ya no existe.
        if ($estado.TemporizadorFiltro) { $estado.TemporizadorFiltro.Stop() }
        # Última pasada por si el runspace encolo algo entre el último tick
        # del temporizador (que ya se ha parado) y este cierre. Se llama a
        # Invoke-VaciarColaRegistro y no a $volcarRegistro porque lo que
        # importa aquí es que las líneas lleguen al ARCHIVO: la ventana se
        # esta cerrando y ya no hay a quien mostrarselas.
        [void](Invoke-VaciarColaRegistro -Sync $estado.Sync)

        # Si se cierra la ventana EN MITAD DE UN BORRADO, $terminarBorrado
        # no llega a ejecutarse nunca, y con el se perdia la entrada del
        # historial: el programa habia borrado archivos de verdad y no
        # quedaba constancia de ello en ningun sitio salvo el .log. Para un
        # programa cuya razon de ser es dejar rastro de lo que borra, eso
        # es lo peor que puede pasarle a un cierre.
        #
        # Se anota lo que se sepa, marcado como interrumpido, y se hace
        # ANTES de soltar el runspace para no perder la ultima cifra que
        # dejo escrita. Ver [INT-04].
        if ($estabaBorrando) {
            try {
                $parcial  = $estado.Sync.Resultado
                $liberado = if ($parcial) { [double]$parcial.Liberado } else { 0.0 }
                $hechos   = if ($parcial) { [int]$parcial.Hechos } else { 0 }

                Add-EntradaHistorial -Tipo 'limpieza-interrumpida' `
                                     -Perfil $estado.Configuracion.Perfil `
                                     -Modulos @($estado.Modulos | ForEach-Object { $_.Id }) `
                                     -Elementos $hechos -Bytes $liberado `
                                     -CarpetaDatos $estado.Configuracion.CarpetaDatos | Out-Null
            } catch {
                Write-Verbose "No se ha podido anotar la limpieza interrumpida: $($_.Exception.Message)"
            }
        }

        & $cerrarRunspace
        & $guardarPreferencias
    })

