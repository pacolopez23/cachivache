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
    # Ajustes rehace la lista de exclusiones al abrirse, igual que Informes
    # rehace el historial: la lista puede haber cambiado desde la ultima vez
    # -al excluir algo desde la tabla, o por fuera editando preferencias.json-
    # y una tarjeta que ensenya lo de hace media hora es peor que no tenerla.
    $c.NavAjustes.Add_Checked({    & $refrescarExclusiones; & $mostrarPanel 'PanelAjustes' })
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

    # El cuerpo de esto vive en $abrirUbicacion (Window.Ayudantes.ps1), y no
    # aqui, porque lo comparten tres entradas: este boton, la del menu
    # contextual y el doble clic. Ver [USO-06].
    $c.BtnAbrirCarpeta.Add_Click({ & $abrirUbicacion $c.TablaResultados.SelectedItem })

    # ---- Doble clic sobre una fila ([USO-06]) ----
    #
    # Abrir la ubicación es lo que espera cualquiera al hacer doble clic en
    # una lista de archivos, y hasta ahora obligaba a subir a la barra de
    # herramientas. No abre el archivo: lo ensenya en su carpeta. Abrirlo
    # seria ejecutar algo que el programa ha propuesto BORRAR, y esa no es
    # una sorpresa que deba dar un doble clic.
    #
    # Sin fila no hace nada y se calla: el doble clic tambien cae sobre la
    # cabecera -donde ya ordena la columna- y sobre el hueco de debajo de la
    # ultima fila, y un aviso ahi seria un cuadro de dialogo por accidente.
    # Es la diferencia con el boton, que si tiene que explicarse cuando se
    # pulsa sin haber elegido nada.
    $c.TablaResultados.Add_MouseDoubleClick({
        $item = $c.TablaResultados.SelectedItem
        if ($null -eq $item) { return }
        & $abrirUbicacion $item
    })

    # ---- Ocultar lo ya eliminado ([USO-13]) ----
    #
    # Add_Checked y Add_Unchecked, no Add_Click: es la misma trampa que
    # documenta la casilla de borrado permanente mas abajo. Click solo se
    # levanta cuando pulsa el usuario, asi que si algun dia el codigo mueve
    # esta casilla, la tabla se quedaria filtrada de una forma y la casilla
    # diciendo otra.
    $sincronizarOcultarHechos = { & $aplicarFiltro }
    $c.ChkOcultarHechos.Add_Checked($sincronizarOcultarHechos)
    $c.ChkOcultarHechos.Add_Unchecked($sincronizarOcultarHechos)

    # El boton del cartel no reaplica el filtro por su cuenta: solo desmarca
    # la casilla, y el Add_Unchecked de arriba hace el resto. Si hiciera las
    # dos cosas habria dos caminos para destapar lo eliminado, y el dia que
    # cambie uno el otro se queda con el comportamiento viejo. Ver [USO-13].
    $c.BtnMostrarHechos.Add_Click({ $c.ChkOcultarHechos.IsChecked = $false })

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
        # La casilla de Resultados, que es la MISMA capacidad que
        # -InformeAnonimo en la consola: las dos acaban en el parametro
        # -Anonimo de las tres funciones de Report.ps1. La ventana no
        # anonimiza por su cuenta, y hay una invariante que lo prohibe:
        # dos anonimizadores distintos es lo mismo que dos bucles de
        # borrado distintos, y ya sabemos como acabo aquello. Ver [USO-12],
        # [CNF-02] y [ARQ-01].
        $anonimo = [bool]$c.ChkAnonimizar.IsChecked

        $ruta = $null
        try {
            $ruta = New-NombreInforme -Tipo 'analisis' -Extension $Formato -CarpetaDatos $estado.Configuracion.CarpetaDatos
            switch ($Formato) {
                'html' { Export-InformeHtml -Candidatos $estado.Candidatos -Ruta $ruta -Configuracion $estado.Configuracion -Modulos $estado.Modulos -Anonimo:$anonimo -Confirm:$false }
                'csv'  { Export-InformeCsv  -Candidatos $estado.Candidatos -Ruta $ruta -Anonimo:$anonimo -Confirm:$false }
                'json' { Export-InformeJson -Candidatos $estado.Candidatos -Ruta $ruta -Configuracion $estado.Configuracion -Anonimo:$anonimo -Confirm:$false }
            }
            # Se DICE que se ha anonimizado. Un informe anonimo y otro sin
            # anonimizar se llaman igual y se ven casi igual, asi que sin
            # esta linea la unica forma de saber cual es cual es abrirlo y
            # buscar tu propio nombre de usuario dentro. Es la leccion de
            # [USO-15]: hacer el trabajo y no decirlo es indistinguible de
            # no hacerlo.
            $comoSeGuardo = if ($anonimo) { ' (con las rutas anonimizadas)' } else { '' }
            & $escribir (('Informe guardado: {0}{1}' -f $ruta, $comoSeGuardo))
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

            & $marcarCategoria $categoria $marcar
        })

    # Marcar o desmarcar una categoria entera. Lo llaman los dos botones de
    # la cabecera de grupo y la orden "Desmarcar el grupo" del menu
    # contextual ([USO-06]); un solo cierre, por lo mismo que [ARQ-01].
    #
    # Se define DESPUES del manejador de arriba, que ya lo usa, y no pasa
    # nada: ese manejador no se evalua hasta que alguien pulsa un boton, con
    # el archivo entero cargado desde hace rato. Es lo mismo que hacen los
    # cuatro trozos de la ventana entre si, y esta explicado en Window.ps1.
    $marcarCategoria = {
        param([string] $Categoria, [bool] $Marcar)

        # La misma bandera que usa el marcado global: sin ella, cambiar
        # doscientas casillas dispara doscientos recalculos completos del
        # resumen del pie, cada uno recorriendo la lista entera. Es el
        # fallo que dejaba la ventana en "No responde".
        $estado.SuprimirResumen = $true
        try {
            foreach ($item in $estado.Items) {
                if ($item.Categoria -ne $Categoria) { continue }
                # Marcar respeta lo que NO se puede borrar; quitar vale
                # para todo, porque desmarcar nunca hace danyo.
                if ($Marcar -and -not $item.Borrable) { continue }
                $item.Seleccionado = $Marcar
            }
        } finally {
            $estado.SuprimirResumen = $false
        }
        & $actualizarResumenSeleccion
    }

    # =================================================================
    #  MENU CONTEXTUAL DE LA TABLA [USO-06]
    # =================================================================
    # Las cuatro ordenes trabajan sobre la fila SELECCIONADA, la misma que
    # usan los botones de la barra de herramientas. El menu cuelga de la
    # tabla entera, asi que tambien se abre sobre la cabecera y sobre el
    # hueco de debajo de la ultima fila, donde no hay ninguna elegida: las
    # cuatro lo comprueban y lo dicen, en vez de no hacer nada.
    #
    # Y se comprueba que el XAML los trajo. FindName devuelve $null sin
    # quejarse cuando el nombre no esta, y $null.Add_Click() SI lanza: se
    # perderia la ventana entera por un menu contextual. Se anota y se
    # sigue, igual que con los controles del cartel de tabla vacia
    # ([USO-09]): quedarse sin menu es malo, no abrir el programa es peor.
    $faltanMenuFila = @(@('MenuAbrirUbicacion', 'MenuCopiarRuta',
                          'MenuExcluirSiempre', 'MenuDesmarcarGrupo') |
                        Where-Object { $null -eq $c[$_] })
    if ($faltanMenuFila.Count -gt 0) {
        Write-Registro -Sync $estado.Sync -Nivel 'ERROR' -Mensaje (
            'No se han encontrado estas entradas del menú contextual de la tabla, y no van a responder: {0}' -f
            ($faltanMenuFila -join ', '))
    } else {

        $c.MenuAbrirUbicacion.Add_Click({ & $abrirUbicacion $c.TablaResultados.SelectedItem })

        # ---- Copiar ruta ----
        #
        # SIN RUTA DE VERDAD NO SE COPIA NADA, y esa es la decision.
        #
        # Copiar la etiqueta -"Papelera de reciclaje", "docker system
        # prune"- dejaria en el portapapeles algo que parece una ruta y no
        # lo es. El portapapeles no dice de donde salio lo que lleva
        # dentro: el usuario se entera al pegarlo, en otro programa, sin
        # ninguna pista de por que no funciona. Y el comando, que es lo
        # unico util que habria ahi, ya se ve entero en la propia fila
        # porque SECURITY.md lo exige.
        #
        # Callarse tampoco vale: se dice que no hay ruta y por que. Un
        # menu que se pulsa y no hace nada es indistinguible de uno roto,
        # que es [USO-15] otra vez.
        $c.MenuCopiarRuta.Add_Click({
            $item = $c.TablaResultados.SelectedItem
            if ($null -eq $item) {
                Show-Aviso -Mensaje 'Elige antes una fila de la lista: es su ruta la que se copia.' -Tipo 'Information'
                return
            }

            if (-not $item.TieneRutaReal) {
                Show-Aviso -Tipo 'Information' -Mensaje (
                    (& $describirSinRuta $item 'ruta que copiar') +
                    [Environment]::NewLine + [Environment]::NewLine +
                    'No se ha copiado nada: dejar ahí una etiqueta que parece una ruta solo se descubre al pegarla, en otro sitio y sin ninguna pista de qué ha pasado.')
                return
            }

            try {
                [Windows.Clipboard]::SetText($item.Ruta)
                # Sin cuadro de dialogo al copiar bien: copiar es una
                # accion frecuente y de riesgo cero, y quien la pide va a
                # pegar acto seguido, que es donde lo comprueba. Al
                # registro si, que es lo que se adjunta a una incidencia.
                & $escribir ('Ruta copiada al portapapeles: {0}' -f $item.Ruta)
            } catch {
                Show-Aviso -Mensaje 'Otro programa está bloqueando el portapapeles. Vuelve a intentarlo.' -Tipo 'Warning'
            }
        })

        # ---- Excluir siempre esto ----
        #
        # Se guarda $item.ClaveExclusion TAL CUAL. NO se recompone aqui la
        # clave a partir de la ruta: la decide Get-ClaveExclusion al nacer
        # el candidato y viaja pegada a la fila desde [ARQ-03]. Dos sitios
        # calculando la misma clave es como se llega a excluir una cosa y
        # comparar otra, y el sitio donde se compara es el motor de
        # borrado.
        #
        # Se PREGUNTA antes, y se sigue preguntando ahora que la tarjeta de
        # Ajustes ya existe y esto se puede deshacer. El motivo ya no es que
        # sea una puerta de un solo sentido -no lo es-, sino que lo que se
        # promete es "nunca mas": a partir de aqui el elemento desaparece de
        # todos los analisis, y lo que deja de proponerse no se ve, asi que
        # una exclusion puesta por error es invisible justo despues de
        # ponerla. Ademas el menu actua sobre la fila SELECCIONADA, y
        # nombrarla en la pregunta es lo que convierte un posible "se abrio
        # el menu sobre otra fila" en algo que el usuario ve antes de que
        # pase.
        #
        # Quitar, en cambio, NO pregunta: devuelve el elemento a estar
        # propuesto, que es de donde salio, y el error se ve al momento. La
        # explicacion larga esta junto a $quitarExclusion.
        $c.MenuExcluirSiempre.Add_Click({
            $item = $c.TablaResultados.SelectedItem
            if ($null -eq $item) {
                Show-Aviso -Mensaje 'Elige antes una fila de la lista: es ese elemento el que se excluye.' -Tipo 'Information'
                return
            }

            $clave = [string]$item.ClaveExclusion
            if ([string]::IsNullOrWhiteSpace($clave)) {
                Show-Aviso -Tipo 'Warning' -Mensaje (
                    'Esta fila no trae la clave con la que se guardan las exclusiones, así que excluirla no serviría de nada: no habría nada con lo que comparar. Vuelve a analizar y prueba otra vez.')
                return
            }

            # La MISMA funcion que usan el embudo del analisis y el motor
            # de borrado. Si aqui se comprobara de otra forma, el programa
            # podria decir "ya estaba excluido" sobre algo que luego borra.
            $excluidas = @($estado.Preferencias.RutasExcluidas)
            if (Test-ClaveExcluida -Clave $clave -Excluidas $excluidas) {
                Show-Aviso -Tipo 'Information' -Mensaje (
                    '«{0}» ya está cubierto por tu lista de cosas que no se tocan nunca. No hace falta volver a excluirlo.' -f $item.Nombre)
                return
            }

            # Parentesis alrededor de toda la concatenacion antes del -f:
            # el -f se enlaza mas fuerte que el +, y sin ellos solo se
            # formatea el ultimo trozo y los {0} de los demas llegan
            # literales a la pantalla. Ha mordido cuatro veces.
            $pregunta = ('Vas a excluir «{0}» para siempre.' + [Environment]::NewLine + [Environment]::NewLine +
                         'Se guarda esta clave: {1}' + [Environment]::NewLine + [Environment]::NewLine +
                         'Si es una carpeta, queda fuera también todo lo que haya dentro. No volverá a proponerse en ningún análisis, y el motor de borrado lo rechazará aunque llegue a estar marcado.' +
                         [Environment]::NewLine + [Environment]::NewLine +
                         'Podrás quitarlo cuando quieras en Ajustes, en la tarjeta «Lo que no se toca nunca».' +
                         [Environment]::NewLine + [Environment]::NewLine +
                         '¿Lo excluyes?') -f $item.Nombre, $clave

            if ([Windows.MessageBox]::Show($pregunta, 'Excluir siempre', 'YesNo', 'Question') -ne 'Yes') { return }

            # A las preferencias, que es donde vive la lista desde
            # [CNF-01], y a la configuracion, que es la copia que miran el
            # embudo del analisis y el motor de borrado. Las dos, porque
            # solo se sincronizan al refrescar los discos y eso no vuelve a
            # ocurrir hasta que se cambia de tema o se restablece: sin la
            # segunda linea, la exclusion no valdria para la limpieza que
            # el usuario esta a punto de lanzar.
            $estado.Preferencias.RutasExcluidas = @(@($excluidas) + $clave |
                                                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                                                    Select-Object -Unique)
            $estado.Configuracion.RutasExcluidas = @($estado.Preferencias.RutasExcluidas)

            # Se guarda al momento y no al cerrar la ventana. Lo que esto
            # promete es "nunca mas", y un cierre anormal que se llevara la
            # exclusion por delante seria justo la promesa incumplida que
            # [CNF-01] vino a arreglar. Es lo que ya hace "Restablecer".
            & $guardarPreferencias

            # Y la tarjeta de Ajustes se rehace ya. Tambien se rehace al
            # abrir ese panel, asi que esto es de mas por hoy; se pone igual
            # porque la tarjeta acaba de prometer en el dialogo que el
            # elemento se puede quitar desde alli, y esa promesa no puede
            # depender de que el unico camino hasta el panel siga pasando por
            # el boton de navegacion.
            & $refrescarExclusiones

            # Y se desmarca al momento lo que la exclusion cubre, con la
            # MISMA funcion que decide en el motor. Sin esto, la fila
            # seguiria marcada y la siguiente limpieza intentaria borrarla
            # para que el motor la rechazara con un error en rojo: el
            # programa discutiendo consigo mismo delante del usuario.
            $ahora = @($estado.Preferencias.RutasExcluidas)
            $desmarcados = 0
            $estado.SuprimirResumen = $true
            try {
                foreach ($fila in $estado.Items) {
                    if (-not $fila.Seleccionado) { continue }
                    if (-not (Test-ClaveExcluida -Clave $fila.ClaveExclusion -Excluidas $ahora)) { continue }
                    $fila.Seleccionado = $false
                    $desmarcados++
                }
            } finally {
                $estado.SuprimirResumen = $false
            }
            & $actualizarResumenSeleccion

            $cola = if ($desmarcados -eq 0) {
                'En la lista de ahora no quedaba nada marcado que la exclusión cubra.'
            } elseif ($desmarcados -eq 1) {
                'Se ha desmarcado 1 elemento que la exclusión cubre.'
            } else {
                'Se han desmarcado {0} elementos que la exclusión cubre.' -f $desmarcados
            }

            & $escribir ('Excluido para siempre: {0}. {1}' -f $clave, $cola)
            Show-Aviso -Tipo 'Information' -Mensaje (
                ('«{0}» ya no se propondrá en ningún análisis.' +
                 [Environment]::NewLine + [Environment]::NewLine + '{1}') -f $item.Nombre, $cola)
        })

        # ---- Desmarcar el grupo ----
        # Mismo cierre que el boton "Quitar" de la cabecera de grupo: aqui
        # solo se dice sobre que categoria, que es la de la fila elegida.
        $c.MenuDesmarcarGrupo.Add_Click({
            $item = $c.TablaResultados.SelectedItem
            if ($null -eq $item) {
                Show-Aviso -Mensaje 'Elige antes una fila de la lista: se desmarca la categoría a la que pertenece.' -Tipo 'Information'
                return
            }
            & $marcarCategoria $item.Categoria $false
        })
    }

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

    # ---- Quitar una exclusion ([CNF-01]) ----
    #
    # El boton "Quitar" vive DENTRO de la plantilla de cada fila, asi que no
    # tiene nombre en el ambito de la ventana y $ventana.FindName no lo
    # encuentra: las filas las crea y las destruye la lista cada vez que se
    # rehace. Por eso el evento se engancha en la LISTA y se mira quien lo
    # disparo, exactamente igual que los dos botones de la cabecera de grupo
    # de la tabla ([USO-04]).
    $c.ListaExclusiones.AddHandler(
        [Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [Windows.RoutedEventHandler]{
            param($remitente, $argumentos)

            $boton = $argumentos.OriginalSource -as [Windows.Controls.Button]
            if ($null -eq $boton) { return }

            # Por NOMBRE, no por el texto del boton. Mirar el Content ataria
            # el comportamiento al rotulo: cambiar "Quitar" por "Quitar de la
            # lista" dejaria de quitar sin dar ningun error.
            if ($boton.Name -ne 'BtnQuitarExclusion') { return }

            # La CLAVE, que viaja en el Tag, y no el titulo que se lee en la
            # fila: para un comando o para la papelera el titulo es el nombre
            # legible y la clave es la cadena sintetica de [ARQ-03]. Quitar
            # por el titulo no encontraria nada que quitar.
            & $quitarExclusion ([string]$boton.Tag)
        })

    $c.BtnAbrirDatos.Add_Click({
        try { Start-Process -FilePath (Get-RutaExplorador) -ArgumentList "`"$($estado.Configuracion.CarpetaDatos)`"" }
        catch { Show-Aviso -Mensaje "No se ha podido abrir la carpeta de datos:`n$($_.Exception.Message)" -Tipo 'Warning' }
    })

    $c.BtnRestablecer.Add_Click({
        if ($estado.Ocupado) {
            Show-Aviso -Mensaje 'Hay un análisis o una limpieza en marcha. Espera a que termine o cancelalo antes de restablecer los ajustes.' -Tipo 'Information'
            return
        }

        # Se nombra lo que NO se toca, y desde [CNF-01] eso incluye la lista
        # de exclusiones: ahora se ve en una tarjeta de este mismo panel, dos
        # dedos por encima de este boton, asi que quien lo pulse tiene motivo
        # para temer que se la lleve por delante. Un "restablecer" que borra
        # en silencio decisiones de "no toques esto nunca" seria la perdida
        # muda que este proyecto lleva cerrando.
        $respuesta = [Windows.MessageBox]::Show(
            ('Se van a restablecer los umbrales, el perfil, los módulos marcados y la ' +
             'selección de discos. El tema, el historial y lo que hayas excluido no se tocan.' + [Environment]::NewLine +
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

    # ---- Acerca de: hay una version nueva ([DIS-05]) ----
    #
    # La consulta se hace en un RUNSPACE APARTE, no aqui. Una llamada de red
    # sincrona en el manejador del boton congela la ventana entera mientras
    # dura: el usuario no puede ni moverla ni cerrarla, y Windows acaba
    # pintandola en blanco con "no responde" en el titulo. Con una red que
    # acepta la conexion y luego no contesta, eso son los seis segundos del
    # tiempo de espera con la ventana muerta.
    #
    # El runspace carga UNICAMENTE Version.ps1, no el nucleo entero: es lo
    # que necesita Get-UltimaVersionPublicada y es un archivo que no toca
    # disco ni guardia.
    $codigoVersion = @'
$ErrorActionPreference = 'Stop'
. $archivoVersion
Get-UltimaVersionPublicada -TiempoEspera 6
'@

    # Lo que se ve en el panel. La decision de QUE decir no esta aqui:
    # esta en Get-AvisoActualizacion, que es pura y esta probada. Aqui solo
    # se pintan sus dos salidas. Ver [DIS-05].
    $pintarAvisoVersion = {
        param([AllowNull()] [string] $Publicada)

        $aviso = Get-AvisoActualizacion -Instalada $script:VersionCachivache -Publicada $Publicada
        $c.TxtActualizacion.Text = $aviso.Texto
        $c.BtnIrAVersionNueva.Visibility = if ($aviso.Hay) { 'Visible' } else { 'Collapsed' }
        $c.BtnBuscarActualizacion.IsEnabled = $true
    }

    # Suelta el trabajo pase lo que pase. Se llama desde el sondeo y desde
    # el cierre de la ventana: si se cierra en mitad de una consulta, el
    # hilo de fondo seguiria vivo esperando a la red y el proceso tardaria
    # en morir despues de que la ventana ya no este.
    $soltarComprobacionVersion = {
        if ($estado.TemporizadorVersion) { $estado.TemporizadorVersion.Stop() }

        $trabajo = $estado.TrabajoVersion
        # Se pone a $null ANTES de soltar nada: si Dispose lanza, el estado
        # ya dice que no hay consulta en marcha y el boton vuelve a servir.
        $estado.TrabajoVersion = $null
        if (-not $trabajo) { return }

        try { $trabajo.Ps.Stop() }        catch { Write-Verbose "Al parar la consulta de versión: $($_.Exception.Message)" }
        try { $trabajo.Ps.Dispose() }     catch { Write-Verbose "Al soltar la consulta de versión: $($_.Exception.Message)" }
        try { $trabajo.Runspace.Dispose() } catch { Write-Verbose "Al soltar el runspace de versión: $($_.Exception.Message)" }
    }

    # El sondeo, igual que el del analisis: un DispatcherTimer que mira si
    # ya ha terminado. Es la unica forma de volver al hilo de la interfaz
    # sin bloquearlo.
    $revisarComprobacionVersion = {
        $trabajo = $estado.TrabajoVersion
        if (-not $trabajo) {
            if ($estado.TemporizadorVersion) { $estado.TemporizadorVersion.Stop() }
            return
        }
        if (-not $trabajo.Handle.IsCompleted) { return }

        # Cadena vacia si algo ha ido mal, que es lo que
        # Get-AvisoActualizacion entiende como "no se ha podido saber".
        $publicada = ''
        try {
            $salida = $trabajo.Ps.EndInvoke($trabajo.Handle)
            if ($salida -and $salida.Count -gt 0) { $publicada = [string]$salida[$salida.Count - 1] }
        } catch {
            Write-Verbose "La consulta de versión no ha devuelto nada: $($_.Exception.Message)"
        }

        & $soltarComprobacionVersion
        & $pintarAvisoVersion $publicada
    }

    $estado.TemporizadorVersion = New-Object Windows.Threading.DispatcherTimer
    $estado.TemporizadorVersion.Interval = [TimeSpan]::FromMilliseconds(200)
    $estado.TemporizadorVersion.Add_Tick($revisarComprobacionVersion)

    $c.BtnBuscarActualizacion.Add_Click({
        # Dos pulsaciones seguidas abririan dos runspaces y el segundo
        # pisaria al primero en $estado, dejando el primero sin soltar.
        if ($estado.TrabajoVersion) { return }

        $c.BtnBuscarActualizacion.IsEnabled = $false
        $c.BtnIrAVersionNueva.Visibility = 'Collapsed'
        $c.TxtActualizacion.Text = 'Comprobando en GitHub cuál es la última versión publicada...'

        try {
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.Open()
            $runspace.SessionStateProxy.SetVariable('archivoVersion',
                (Join-Path (Join-Path (Join-Path $estado.Raiz 'src') 'Core') 'Version.ps1'))

            $consulta = [powershell]::Create()
            $consulta.Runspace = $runspace
            [void]$consulta.AddScript($codigoVersion)

            $estado.TrabajoVersion = @{
                Ps       = $consulta
                Runspace = $runspace
                Handle   = $consulta.BeginInvoke()
            }
            $estado.TemporizadorVersion.Start()
        } catch {
            # Ni siquiera se ha podido lanzar la consulta. Para el usuario
            # es exactamente lo mismo que si hubiera fallado la red, y se le
            # dice lo mismo: sin cuadro de error.
            Write-Verbose "No se ha podido lanzar la consulta de versión: $($_.Exception.Message)"
            $estado.TrabajoVersion = $null
            & $pintarAvisoVersion ''
        }
    })

    $c.BtnIrAVersionNueva.Add_Click({
        # Se abre la pagina y ya. El programa no se actualiza a si mismo:
        # el .zip se descomprime donde el usuario quiera. Ver [DIS-05].
        $url = Get-UrlUltimaVersion
        try { Start-Process $url }
        catch { Show-Aviso -Mensaje "No se ha podido abrir el navegador. La dirección es: $url" }
    })

    # ---- Acerca de: copiar el diagnostico ([USO-12]) ----
    #
    # LA MISMA funcion que .\Cachivache.ps1 -Diagnostico, no una version
    # para la ventana. Si aqui se armara el texto a mano, los dos caminos
    # divergirian a la primera vez que se anyada un dato al diagnostico, y
    # entonces una incidencia traeria mas informacion que otra segun por
    # donde se hubiera copiado. Hay una invariante que lo prohibe.
    $c.BtnCopiarDiagnostico.Add_Click({
        try {
            $diagnostico = Get-InformeDiagnostico -Admin $estado.Configuracion.Admin `
                                                  -CarpetaDatos $estado.Configuracion.CarpetaDatos
            [Windows.Clipboard]::SetText($diagnostico)
            & $escribir 'Diagnóstico copiado al portapapeles.'
            # Se confirma. Copiar al portapapeles no se ve, y desde este
            # panel no se ve tampoco el registro: sin esto, pulsar el boton
            # y que no ocurra nada es indistinguible de que este roto. Ver
            # [USO-15].
            Show-Aviso -Tipo 'Information' -Titulo 'Diagnóstico copiado' -Mensaje (
                'El diagnóstico está en el portapapeles. Pégalo en la incidencia con Control+V.')
        } catch {
            Show-Aviso -Tipo 'Warning' -Mensaje (
                "No se ha podido copiar el diagnóstico:`n{0}" -f (Get-DetalleExcepcion -ErrorRecord $_))
        }
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
        # Y la consulta de version, por el mismo motivo y por uno mas: si se
        # cierra la ventana con una consulta en marcha, el hilo de fondo
        # sigue esperando a la red y el proceso tarda en morir despues de
        # que la ventana ya no este en pantalla. Ver [DIS-05].
        & $soltarComprobacionVersion
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

