<#
.SYNOPSIS
    Cierres auxiliares de la ventana: escribir en consola, refrescar listas, filtrar y cambiar de tema.

.DESCRIPTION
    Los define ANTES que nadie porque el resto de trozos los usan.

    ESTE ARCHIVO NO SE EJECUTA SOLO. Es un trozo del cuerpo de
    Show-VentanaPrincipal (Window.ps1), que lo dot-sourcea desde
    DENTRO de la función. Por eso el código de aquí usa $c, $estado,
    $ventana y los cierres de Window.Ayudantes.ps1 sin declararlos:
    los ve porque se carga en el ámbito de esa función, igual que si
    el texto estuviera pegado allí. Ver docs/ESTRUCTURA.md (sección 3).
#>

    # =================================================================
    #  FUNCIONES AUXILIARES DE INTERFAZ
    # =================================================================
    # Cuantas líneas se conservan en pantalla, y cuanto se deja crecer
    # antes de recortar. El recorte cuesta reconstruir el texto entero, así
    # que se hace de tarde en tarde y se baja de golpe hasta el máximo, en
    # vez de una línea cada vez.
    #
    # Hace falta un tope porque el panel muestra ahora TODO lo que va al
    # archivo, y una limpieza escribe una línea por elemento borrado: con
    # doscientos mil archivos, meterlos todos en un TextBox congelaria la
    # ventana. El archivo del registro no se toca: allí siguen enteros.
    $maximoLineasConsola = 2000
    $margenLineasConsola = 1000

    # Único camino por el que algo aparece en el panel de Registro. Saca de
    # la cola lo que haya -lo escriba quien lo escriba, el hilo de la
    # ventana o el runspace de trabajo-, lo manda al archivo y pinta EN
    # PANTALLA LA MISMA LÍNEA, literal. Antes la ventana componia su propia
    # versión corta por otro lado, y el panel acababa contando bastante
    # menos que el .log.
    $volcarRegistro = {
        $lineas = @(Invoke-VaciarColaRegistro -Sync $estado.Sync)
        if ($lineas.Count -eq 0) { return }

        # Una sola llamada con todo el bloque: durante un borrado grande
        # cada pasada del temporizador trae cientos de líneas, y añadirlas
        # de una en una repinta el control cientos de veces.
        $c.Consola.AppendText(($lineas -join [Environment]::NewLine) + [Environment]::NewLine)
        $estado.LineasConsola += $lineas.Count

        if ($estado.LineasConsola -gt ($maximoLineasConsola + $margenLineasConsola)) {
            $conservadas = @($c.Consola.Text -split "`r?`n" | Select-Object -Last $maximoLineasConsola)
            $c.Consola.Text = '--- líneas anteriores recortadas; en el archivo del registro están todas ---' +
                              [Environment]::NewLine + ($conservadas -join [Environment]::NewLine)
            $estado.LineasConsola = $conservadas.Count + 1
        }

        $c.Consola.ScrollToEnd()
    }

    $escribir = {
        param([string] $Texto, [string] $Nivel = 'INFO')
        Write-Registro -Sync $estado.Sync -Mensaje $Texto -Nivel $Nivel
        # Se vuelca al momento y no se espera al temporizador: la mayoria
        # de estas líneas se escriben cuando no hay ningún trabajo en
        # marcha y el temporizador esta parado.
        & $volcarRegistro
    }

    # =================================================================
    #  [USO-10] La tabla no vuelve arriba cada vez que se reengancha
    # =================================================================
    # QUE DECIDE CADA UNO. Aquí no se decide nada: los tres cierres son
    # el brazo ejecutor. Que desplazamiento se aplica y si la selección se
    # restaura lo dice Get-PlanRestauracionTabla, en Posicion.ps1, que es
    # cálculo puro y va probado. Aquí solo se lee de WPF, se pregunta, y
    # se escribe en WPF.
    #
    # Nada de esto puede tumbar un análisis. Se ejecuta una vez por módulo
    # y lo único que hay en juego es dónde queda la barra de
    # desplazamiento; un fallo se anota y se sigue. Se anota de verdad,
    # con nivel AVISO en el registro, y no con un catch mudo: este
    # proyecto ya perdió el historial entero de las limpiezas
    # interrumpidas por un catch que se tragaba la excepción sin dejar
    # rastro (ver [CNF-04] y la nota de Add-EntradaHistorial).
    $desplazadorDeTabla = {
        # El ScrollViewer que desplaza el DataGrid vive DENTRO de su
        # plantilla, así que no se puede pedir por nombre desde fuera: se
        # baja por el árbol visual hasta encontrarlo. Se busca por TIPO y
        # no por el nombre "DG_ScrollViewer" que le pone la plantilla por
        # defecto de WPF, porque ese nombre es un detalle de esa plantilla
        # concreta y basta con que alguien redefina el ControlTemplate en
        # Styles.xaml para que deje de existir, en silencio.
        if ($null -ne $estado.DesplazadorTabla) { return $estado.DesplazadorTabla }

        # ::new() y no New-Object, que es la regla de [COR-07]: una
        # coleccion generica creada con New-Object da un objeto que @( ) no
        # sabe enumerar. Aquí no se enumera con @( ), pero la invariante no
        # distingue casos y hace bien: la excepción de hoy es la costumbre
        # de mañana. La cazó ella, no yo.
        $pila = [System.Collections.Generic.Stack[System.Windows.DependencyObject]]::new()
        $pila.Push($c.TablaResultados)
        while ($pila.Count -gt 0) {
            $nodo = $pila.Pop()
            if ($nodo -is [System.Windows.Controls.ScrollViewer]) {
                $estado.DesplazadorTabla = $nodo
                return $nodo
            }
            $cuantos = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($nodo)
            for ($i = 0; $i -lt $cuantos; $i++) {
                $pila.Push([System.Windows.Media.VisualTreeHelper]::GetChild($nodo, $i))
            }
        }
        return $null
    }

    # Se llama JUSTO ANTES de poner ItemsSource a $null. Devuelve siempre
    # un objeto, nunca $null: quien restaura no tiene que preguntar.
    $guardarPosicionTabla = {
        $desplazamiento = 0.0
        try {
            $sv = & $desplazadorDeTabla
            if ($null -ne $sv) { $desplazamiento = [double] $sv.VerticalOffset }
        } catch {
            Write-Registro -Sync $estado.Sync -Nivel 'AVISO' -Mensaje (
                'No se ha podido guardar la posición de la tabla: {0}' -f $_.Exception.Message)
        }
        return [pscustomobject]@{
            Desplazamiento = $desplazamiento
            Seleccion      = $c.TablaResultados.SelectedItem
        }
    }

    # Y este JUSTO DESPUES de volver a enganchar la colección.
    $restaurarPosicionTabla = {
        param($Guardado)

        if ($null -eq $Guardado) { return }

        try {
            $sv = & $desplazadorDeTabla

            # La medida hay que forzarla. Al reenganchar, WPF todavía no ha
            # vuelto a medir: ScrollableHeight sigue valiendo lo de la
            # lista ANTERIOR, y ScrollToVerticalOffset recorta contra ese
            # máximo viejo. Con un módulo que añade dos mil filas, eso deja
            # la tabla en el final de antes en vez de donde estaba el
            # usuario, que es un salto distinto pero salto igual.
            if ($null -ne $sv) { $c.TablaResultados.UpdateLayout() }

            $maximo = 0.0
            if ($null -ne $sv) { $maximo = [double] $sv.ScrollableHeight }

            $habia   = $null -ne $Guardado.Seleccion
            $visible = $false
            if ($habia) {
                # Si hay filtro puesto, se le pregunta A EL, invocando el
                # mismo predicado que decide qué filas se ven. Preguntarlo
                # de otra forma sería un segundo sitio decidiendo lo mismo.
                #
                # Con el predicado y no con Vista.Contains: Contains
                # recorre la vista entera para averiguar exactamente esto,
                # o sea otra pasada por quince mil filas por cada módulo
                # que termina, frente a una sola invocación.
                $filtro = $null
                if ($null -ne $estado.Vista) { $filtro = $estado.Vista.Filter }
                if ($null -eq $filtro) { $visible = $true }
                else { $visible = [bool] $filtro.Invoke($Guardado.Seleccion) }
            }

            $plan = Get-PlanRestauracionTabla -Guardado ([double] $Guardado.Desplazamiento) `
                                              -Maximo $maximo `
                                              -HabiaSeleccion:$habia -SeleccionVisible:$visible
            if (-not $plan.HayQueHacerAlgo) { return }

            if ($plan.RestaurarSeleccion) {
                # Selección sí, ScrollIntoView NO, y no es un olvido:
                # llevar la tabla hasta la fila marcada se pelearía con el
                # desplazamiento que se restaura tres líneas más abajo, y
                # ganaría el último que escribiera. El sitio del usuario es
                # donde está mirando, no donde dejó la marca. Hay una
                # invariante que prohíbe que aparezca aquí.
                $c.TablaResultados.SelectedItem = $Guardado.Seleccion
            }
            if ($plan.Desplazamiento -gt 0 -and $null -ne $sv) {
                $sv.ScrollToVerticalOffset($plan.Desplazamiento)
            }
        } catch {
            Write-Registro -Sync $estado.Sync -Nivel 'AVISO' -Mensaje (
                'No se ha podido restaurar la posición de la tabla: {0}' -f $_.Exception.Message)
        }
    }

    # Manejador único para las casillas de las unidades. Se define aquí, en
    # el ámbito de la función, y NO se le aplica GetNewClosure, por el mismo
    # motivo que al de las filas de resultados: esa llamada capturaria solo
    # el ámbito local del sitio donde se crea y dejaria a $null los cierres
    # que necesita.
    $manejadorUnidadGlobal = {
        param($remitente, $argumentos)
        if ($argumentos.PropertyName -ne 'Seleccionado') { return }
        & $actualizarUnidadesElegidas
    }

    # Cuando el usuario marca o desmarca la casilla de una unidad, se
    # recalcula la lista que consulta el nucleo. El filtro de verdad esta
    # en ModuleRegistry.ps1 (Test-UnidadSeleccionada), no aquí: esto solo
    # traslada la decisión del usuario a la configuración.
    $actualizarUnidadesElegidas = {
        $elegidas = @($estado.DiscosVista | Where-Object { $_.Seleccionado } | ForEach-Object { $_.Letra })
        $estado.Configuracion.UnidadesSeleccionadas = $elegidas
        $estado.Preferencias.UnidadesExcluidas =
            @($estado.DiscosVista | Where-Object { -not $_.Seleccionado } | ForEach-Object { $_.Letra })

        if ($elegidas.Count -eq 0) {
            & $escribir 'No queda ninguna unidad marcada: el análisis no encontrara nada.' 'AVISO'
        }
    }

    $refrescarDiscos = {
        $estado.Configuracion.Unidades = @(Get-UnidadesFijas)
        $estado.LibreCache = Get-EspacioLibre $estado.Configuracion.Unidad

        # Las carpetas que el usuario marco como intocables viajan de las
        # preferencias a la configuracion, que es lo que ven el embudo del
        # analisis y el motor de borrado. Ver [CNF-01].
        $estado.Configuracion.RutasExcluidas = @($estado.Preferencias.RutasExcluidas)

        # Las unidades que el usuario dejo desmarcadas la última vez. Se
        # guardan las EXCLUIDAS y no las incluidas a propósito: si mañana
        # aparece un disco nuevo, entra marcado por defecto en vez de quedar
        # fuera en silencio por no estar en una lista antigua.
        $excluidas = @($estado.Preferencias.UnidadesExcluidas)

        $c.ListaDiscos.ItemsSource = $null
        $lista = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.DiscoVista]
        foreach ($unidad in $estado.Configuracion.Unidades) {
            $vista = New-Object Cachivache.DiscoVista
            $vista.Letra      = $unidad.Letra
            $vista.Titulo     = '{0}  {1}' -f $unidad.Letra, $unidad.Etiqueta
            $vista.Detalle    = '{0} libres de {1}' -f (Format-Tamano $unidad.Libre), (Format-Tamano $unidad.Total)
            $vista.Porcentaje = '{0}%' -f $unidad.PorcentajeUsado
            $vista.AnchoUsado = [Math]::Round(160 * $unidad.PorcentajeUsado / 100, 0)
            # Rojo cuando queda poco sitio: se ve de un vistazo.
            $vista.ColorBarra = if ($unidad.PorcentajeUsado -ge 92) { Get-ColorAcentoTema 'Peligro' $estado.Tema }
                                elseif ($unidad.PorcentajeUsado -ge 80) { Get-ColorAcentoTema 'Aviso' $estado.Tema }
                                else { Get-ColorAcentoTema 'Acento' $estado.Tema }
            $vista.Seleccionado = ($excluidas -notcontains $unidad.Letra)
            $vista.add_PropertyChanged($manejadorUnidadGlobal)
            $lista.Add($vista)
        }
        $estado.DiscosVista = $lista
        $c.ListaDiscos.ItemsSource = $lista
        & $actualizarUnidadesElegidas
    }

    # =================================================================
    #  LO QUE EL USUARIO HA DICHO QUE NO SE TOQUE NUNCA [CNF-01]
    # =================================================================
    # La tarjeta de Ajustes que [CNF-01] daba por hecha en su banner y que
    # nunca se hizo. Desde [USO-06] se podian anyadir exclusiones desde el
    # menu contextual de la tabla pero no quitarlas, asi que el propio
    # dialogo de confirmacion tenia que avisar de que aquello solo se
    # deshacia editando preferencias.json a mano.
    #
    # La lista se rehace entera cada vez, como la de informes: son unas
    # pocas filas y se mira de tarde en tarde, asi que mantener viva una
    # coleccion sincronizada con las preferencias costaria mas de lo que
    # ahorra.
    #
    # COMO SE PRESENTA CADA CLAVE LO DECIDE Get-ExclusionVista, que es
    # calculo puro y esta probado. Aqui no se parte ninguna cadena ni se
    # busca ningun "modulo:": si esto compusiera su propio texto, habria dos
    # sitios interpretando la misma clave, que es como se llega a ensenyar
    # una cosa y borrar otra.
    $refrescarExclusiones = {
        $lista = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.ExclusionVista]
        foreach ($clave in @($estado.Preferencias.RutasExcluidas)) {
            $vista = Get-ExclusionVista -Clave ([string]$clave)
            # Nulo es "esto no se puede ensenyar" -una entrada en blanco de
            # un preferencias.json editado a mano-. Se salta en vez de
            # producir una fila vacia que nadie sabria por que esta ahi.
            if ($null -eq $vista) { continue }

            $fila = New-Object Cachivache.ExclusionVista
            $fila.Clave   = $vista.Clave
            $fila.Titulo  = $vista.Titulo
            $fila.Detalle = $vista.Detalle
            $fila.Tipo    = $vista.Tipo
            $lista.Add($fila)
        }

        $c.ListaExclusiones.ItemsSource = $lista
        # Se cuenta lo que de verdad se ve, no lo que hay en las
        # preferencias: si una entrada se ha saltado por venir en blanco, el
        # rotulo diria "hay 3" delante de dos filas.
        $c.TxtResumenExclusiones.Text = Get-TextoListaExclusiones -Cuantas $lista.Count
    }

    # Quitar una exclusion.
    #
    # NO PREGUNTA, Y ANYADIR SI PREGUNTA ([USO-06]). La asimetria no es un
    # descuido: sigue la direccion del danyo.
    #
    #   - Anyadir es una promesa de "nunca mas". A partir de ahi el elemento
    #     desaparece de TODOS los analisis, y lo que ya no se propone no se
    #     ve: una exclusion puesta por error es invisible justo despues de
    #     ponerla. Ademas el menu actua sobre la fila seleccionada, asi que
    #     la pregunta es tambien lo que convierte un "se abrio el menu sobre
    #     otra fila" en algo que se ve antes de que pase.
    #   - Quitar no destruye nada. Devuelve el elemento a estar PROPUESTO,
    #     que es de donde salio, y entre proponer y borrar siguen estando la
    #     casilla, el dialogo de confirmacion y la guardia del motor. El
    #     error se ve al momento -la fila desaparece de la tarjeta- y se
    #     deshace en dos clics desde Resultados.
    #
    # Y hay un motivo de fondo: una confirmacion que sale siempre se
    # aprende a despachar sin leerla, y entonces deja de proteger tambien
    # donde importa, que en este programa es el dialogo que borra. Preguntar
    # por todo es la forma barata de que no valga nada preguntar.
    $quitarExclusion = {
        param([string] $Clave)

        if ([string]::IsNullOrWhiteSpace($Clave)) { return }

        # Comparacion EXACTA y ordinal: la clave viene del Tag de la fila,
        # o sea que es la misma cadena que esta guardada, caracter por
        # caracter. Comparar sin distinguir mayusculas se llevaria por
        # delante otra entrada que solo se diferencie en eso, y el usuario
        # veria desaparecer una fila que no habia tocado.
        $antes  = @($estado.Preferencias.RutasExcluidas)
        $quedan = @($antes | Where-Object { -not [string]::Equals([string]$_, $Clave, [StringComparison]::Ordinal) })

        if ($quedan.Count -eq $antes.Count) {
            # No deberia ocurrir: la fila salio de esta misma lista. Si
            # ocurre, la tarjeta esta ensenyando algo que ya no existe y lo
            # util es volver a pintarla, no callarse.
            & $escribir ('Se ha pedido quitar una exclusión que ya no estaba en la lista: {0}' -f $Clave) 'AVISO'
            & $refrescarExclusiones
            return
        }

        # A las preferencias, que es donde vive la lista desde [CNF-01], y a
        # la configuracion, que es la copia que miran el embudo del analisis
        # y el motor de borrado. LAS DOS, porque solo se sincronizan al
        # refrescar los discos: sin la segunda linea el elemento seguiria
        # rechazado en la limpieza que el usuario esta a punto de lanzar, y
        # la tarjeta estaria diciendo que ya no lo esta. Es lo mismo que
        # hace "Excluir siempre esto" en el otro sentido.
        $estado.Preferencias.RutasExcluidas  = $quedan
        $estado.Configuracion.RutasExcluidas = @($estado.Preferencias.RutasExcluidas)

        # Se guarda al momento y no al cerrar la ventana, por lo mismo que
        # al anyadir: si "nunca mas" se escribe en disco en cuanto se
        # promete, lo contrario tambien tiene que escribirse en cuanto se
        # retira. Un cierre anormal que resucitara una exclusion que el
        # usuario acaba de quitar es la misma promesa rota del reves.
        & $guardarPreferencias
        & $refrescarExclusiones
        & $escribir ('Ya no está excluido: {0}. Volverá a proponerse en los próximos análisis.' -f $Clave)
    }

    # Las tres listas de informes ya generados. Se rehacen enteras cada vez
    # que se abre el panel: los archivos pueden haber cambiado por fuera
    # (el usuario borra uno, o llega otro de una ejecución por consola) y
    # mantener una lista viva sincronizada con el disco costaria un
    # FileSystemWatcher para algo que se mira una vez cada mucho.
    $refrescarInformes = {
        # Los controles se nombran uno a uno y no se componen a partir del
        # formato ($c["ListaInformes$sufijo"]): la prueba que ata los
        # nombres de la ventana al XAML lee referencias literales, así que
        # un nombre construido a mano se le escaparia y una errata volveria
        # a ser un panel vacío y silencioso.
        $destinos = @(
            @{ Formato = 'html'; Lista = $c.ListaInformesHtml; Vacio = $c.TxtSinInformesHtml }
            @{ Formato = 'csv';  Lista = $c.ListaInformesCsv;  Vacio = $c.TxtSinInformesCsv  }
            @{ Formato = 'json'; Lista = $c.ListaInformesJson; Vacio = $c.TxtSinInformesJson }
        )

        $ahora = [datetime]::Now
        foreach ($destino in $destinos) {
            $lista = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.InformeVista]
            foreach ($informe in @(Get-InformesGuardados -Formato $destino.Formato `
                                       -CarpetaDatos $estado.Configuracion.CarpetaDatos)) {
                $vista = New-Object Cachivache.InformeVista
                $vista.Nombre = $informe.Nombre
                $vista.Ruta   = $informe.Ruta
                $vista.Tamano = Format-Tamano $informe.Bytes

                $etiqueta = if ($informe.Tipo -eq 'limpieza') { 'Limpieza' }
                            elseif ($informe.Tipo -eq 'analisis') { 'Analisis' }
                            else { 'Informe' }
                $dias = [int]($ahora.Date - $informe.Fecha.Date).TotalDays
                $cuando = if ($dias -le 0) { 'hoy' }
                          elseif ($dias -eq 1) { 'ayer' }
                          else { "hace $dias días" }
                $vista.Detalle = '{0} - {1}, {2}' -f $etiqueta, $informe.Fecha.ToString('d \d\e MMMM \d\e yyyy, HH:mm'), $cuando

                $lista.Add($vista)
            }

            $destino.Lista.ItemsSource = $lista
            # El aviso de "todavía no hay ninguno" aparece SOLO cuando no
            # hay: las tres listas están siempre ahi y siempre se abren,
            # que era justo lo que faltaba.
            $destino.Vacio.Visibility = if ($lista.Count -eq 0) { 'Visible' } else { 'Collapsed' }
        }
    }

    $refrescarHistorial = {
        $entradas = @(Get-Historial -CarpetaDatos $estado.Configuracion.CarpetaDatos)
        $lista = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.HistorialVista]
        foreach ($entrada in ($entradas | Select-Object -Last 25)) {
            $vista = New-Object Cachivache.HistorialVista
            $esLimpieza = [string]$entrada.Tipo -eq 'limpieza'
            $vista.Tipo      = if ($esLimpieza) { 'LIMPIEZA' } else { 'ANALISIS' }
            # Los colores salen del tema en curso. Estaban incrustados con
            # los valores del tema oscuro, así que en tema claro las
            # etiquetas LIMPIEZA y ANÁLISIS quedaban verde oscuro sobre
            # verde casi negro, encima de una tarjeta blanca.
            # Verde para las limpiezas (reutiliza la etiqueta de riesgo
            # bajo, que ya tiene sus dos paletas) y azul para los análisis.
            $vista.ColorTipo = if ($esLimpieza) { Get-ColorAcentoTema 'Exito' $estado.Tema }
                               else { Get-ColorAcentoTema 'Acento' $estado.Tema }
            $fecha = try { [datetime]::Parse($entrada.Fecha) } catch { Get-Date }
            $vista.Titulo  = $fecha.ToString('dddd d \d\e MMMM, HH:mm')
            $cuantos = if ("$($entrada.Elementos)" -eq '1') { '1 elemento' } else { '{0} elementos' -f $entrada.Elementos }
            $vista.Detalle = '{0} - perfil {1}' -f $cuantos, $entrada.Perfil
            # ConvertTo-DoubleSeguro y no [double]: este dato sale de un
            # archivo de texto editable, y una conversión que lanza aquí
            # impide que la ventana llegue a abrirse. Ya paso una vez.
            $vista.Tamano  = Format-Tamano (ConvertTo-DoubleSeguro $entrada.Bytes)

            # El historial es un .json de texto plano en una carpeta donde
            # se puede escribir, así que su contenido no es de fiar: la
            # ruta pasa por la guardia ANTES de guardarse en la vista. Lo
            # que llegue a la interfaz ya esta validado, y lo que no pase
            # queda en cadena vacía, que la tarjeta muestra como "sin
            # informe" en vez de fingir que se puede pulsar.
            $informe = ''
            if ($entrada.PSObject.Properties['Informe'] -and $entrada.Informe) {
                $informe = [string](Resolve-InformeAbrible -Ruta $entrada.Informe `
                                                           -CarpetaDatos $estado.Configuracion.CarpetaDatos)
            }
            $vista.Informe = $informe

            $lista.Insert(0, $vista)
        }
        $c.ListaHistorial.ItemsSource = $lista
        $c.TxtHistorialVacio.Visibility = if ($lista.Count -eq 0) { 'Visible' } else { 'Collapsed' }
        & $refrescarInformes

        $resumen = Get-ResumenHistorial -CarpetaDatos $estado.Configuracion.CarpetaDatos
        if ($resumen.Limpiezas -gt 0) {
            # Singular cuando toca. "Recuperados 308 MB en 1 limpiezas" es
            # de las cosas que delatan que nadie ha leido la pantalla.
            $veces = if ($resumen.Limpiezas -eq 1) { '1 limpieza' } else { '{0} limpiezas' -f $resumen.Limpiezas }
            $c.TxtTotalHistorico.Text = 'Recuperados {0} en {1}.' -f (Format-Tamano $resumen.BytesTotales), $veces
        } else {
            $c.TxtTotalHistorico.Text = 'Sin limpiezas registradas todavía.'
        }
    }

    # Manejador único para las casillas de los módulos. Sin GetNewClosure,
    # por el mismo motivo que el de las filas de resultados.
    #
    # Existe porque antes NADIE escuchaba estas casillas: desmarcabas
    # "papelera" estando en Equilibrado, se guardaba tu eleccion en
    # preferencias.json, y al volver a abrir el programa $refrescarModulos
    # la descartaba sin decir nada, porque solo hace caso a ModulosActivos
    # cuando el perfil es 'personalizado'. Tu decisión aparentaba quedar
    # guardada y no lo estaba. Ahora tocar un módulo pasa el perfil a
    # Personalizado, igual que tocar un umbral en Ajustes.
    $manejadorModuloGlobal = {
        param($remitente, $argumentos)
        if ($argumentos.PropertyName -ne 'Seleccionado') { return }
        & $pasarAPersonalizado
    }

    $refrescarModulos = {
        $estado.ModulosVista.Clear()
        $perfil = $estado.Configuracion.Perfil
        foreach ($modulo in $estado.Modulos) {
            $vista = New-Object Cachivache.ModuloVista
            $vista.Id          = $modulo.Id
            $vista.Nombre      = $modulo.Nombre
            $vista.Descripcion = $modulo.Descripcion
            $vista.Riesgo      = $modulo.Riesgo
            $vista.ColorRiesgo = Get-ColorRiesgo -Riesgo $modulo.Riesgo -Tema $estado.Tema

            $notas = @()
            if ($modulo.SoloInforma) { $notas += 'Solo informa: este módulo nunca borra nada.' }
            if ($modulo.RequiereAdmin -and -not $estado.Configuracion.Admin) {
                $notas += 'Necesita permisos de administrador.'
            }
            $vista.Nota       = $notas -join ' '
            $vista.Disponible = -not ($modulo.RequiereAdmin -and -not $estado.Configuracion.Admin)
            $vista.Seleccionado = $vista.Disponible -and (Test-ModuloEnPerfil -Modulo $modulo -Perfil $perfil)

            if ($perfil -eq 'personalizado' -and @($estado.Preferencias.ModulosActivos).Count -gt 0) {
                $vista.Seleccionado = $vista.Disponible -and ($estado.Preferencias.ModulosActivos -contains $modulo.Id)
            }

            # El manejador se engancha Después de dejar puesto
            # Seleccionado, no antes: así rellenar la lista no se cuenta
            # como que el usuario ha tocado nada y no dispara el paso a
            # Personalizado. Es la misma idea que la bandera
            # SincronizandoPerfil de los controles de Ajustes, pero aquí
            # sale gratis porque los objetos son nuevos cada vez.
            $vista.add_PropertyChanged($manejadorModuloGlobal)
            $estado.ModulosVista.Add($vista)
        }
    }

    # Manejador único compartido por todas las filas de la tabla. Se
    # define aquí, en el ámbito de la función, y NO se le aplica
    # GetNewClosure: esa llamada capturaria solo el ámbito local del sitio
    # donde se creara y dejaria $actualizarResumenSeleccion a $null.
    $manejadorSeleccionGlobal = {
        param($remitente, $argumentos)
        if ($argumentos.PropertyName -ne 'Seleccionado') { return }
        $remitente.Origen.Seleccionado = $remitente.Seleccionado
        if ($estado.SuprimirResumen) { return }
        & $actualizarResumenSeleccion
    }

    # =================================================================
    #  ESTADOS VACIOS DE LA TABLA [USO-09]
    # =================================================================
    # Los tres controles del cartel se resuelven APARTE de $c, en su
    # propia tabla, y no es un descuido: $c lo construye Window.ps1 con una
    # lista literal que este punto no puede tocar. La invariante que impide
    # que $c y el XAML diverjan mira esa lista, asi que pedirle estos tres
    # controles a $c la haria fallar con razon: serian nombres usados que
    # nadie resuelve. (Esa invariante no quita los comentarios antes de
    # buscar, asi que salto contra la primera version de ESTE parrafo, que
    # escribia el acceso tal cual. Es la trampa que el relevo avisa que ha
    # mordido cinco veces.)
    #
    # Con tabla propia, la misma invariante se rehace para ella en
    # tests/EstadoVacio.Tests.ps1 -mismos tres extremos: lo que el XAML
    # declara, lo que se resuelve y lo que el codigo usa-, que es lo que de
    # verdad protege. Si algun dia esta lista se une a la de Window.ps1, la
    # de aqui desaparece y no se pierde nada.
    # Los tres controles del cartel se resuelven en la lista de $c de
    # Window.ps1, como todos los demas. Nacieron en una tabla propia aqui
    # -se escribieron con Window.ps1 ocupado- y eso era un segundo sitio
    # donde resolver controles: la invariante que impide que $c y el XAML
    # diverjan no cubria esa tabla, asi que habia que replicarla entera en
    # las pruebas. Dos mecanismos para lo mismo es como empiezan las
    # divergencias de este proyecto; ahora hay uno.
    #
    # FindName devuelve $null sin quejarse cuando el nombre no esta, y
    # leer $null.Text tampoco lanza: el cartel se quedaria mudo en
    # silencio, que es EL MISMO fallo que viene a arreglar este punto.
    # Se anota y se sigue: quedarse sin la explicacion de la tabla vacia
    # es malo, pero no abrir el programa por eso es peor.
    $faltanControlesVacio = @(@('EstadoVacio', 'TxtEstadoVacio', 'BtnQuitarFiltros', 'BtnMostrarHechos') |
                              Where-Object { $null -eq $c[$_] })
    if ($faltanControlesVacio.Count -gt 0) {
        Write-Registro -Sync $estado.Sync -Nivel 'ERROR' -Mensaje (
            'No se han encontrado en la ventana estos controles, y la tabla vacía no podrá explicarse: {0}' -f
            ($faltanControlesVacio -join ', '))
    }

    $actualizarEstadoVacio = {
        if ($faltanControlesVacio.Count -gt 0) { return }

        # En que punto va la sesion. $estado.Cronometro se crea al pulsar
        # "Analizar el equipo" y ya no vuelve a $null, asi que "sigue
        # siendo $null" es como sabe la ventana que TODAVIA no se ha
        # analizado nada en esta sesion. No hace falta una bandera nueva
        # para eso, pero si una invariante que ate las dos cosas: si
        # alguien deja de arrancar ese cronometro, el programa diria
        # "todavia no se ha analizado nada" con la lista llena.
        $fase = if ($estado.Ocupado -and $estado.Fase -eq 'analisis') { 'analizando' }
                elseif ($null -eq $estado.Cronometro)                 { 'sin-analizar' }
                else                                                  { 'terminado' }

        # IsEmpty, y NO @($estado.Vista).Count. Esto se recalcula en cada
        # clic de casilla, y contar la vista obliga a materializar hasta
        # quince mil filas en un array para averiguar si hay al menos una.
        # IsEmpty es parte de ICollectionView y responde sin recorrer nada.
        $hayVisibles = if ($null -ne $estado.Vista) { -not $estado.Vista.IsEmpty }
                       else { $estado.Items.Count -gt 0 }

        $veredicto = Get-EstadoVacio -Fase $fase -Total $estado.Items.Count -HayVisibles $hayVisibles `
                         -TextoFiltro $c.CampoFiltro.Text `
                         -RiesgoFiltro (Get-RiesgoDelFiltro -Indice $c.FiltroRiesgo.SelectedIndex) `
                         -OcultandoHechos ([bool]$c.ChkOcultarHechos.IsChecked)

        $c.TxtEstadoVacio.Text = $veredicto.Texto

        # El rotulo solo se escribe cuando el boton se va a ver. Asignarlo
        # siempre dejaria un boton con el Content vacio esperando en el
        # arbol, y un boton sin texto es lo que [A11Y-01] vino a quitar.
        if ($veredicto.OfrecerQuitarFiltro) {
            $c.BtnQuitarFiltros.Content    = $veredicto.TextoBoton
            $c.BtnQuitarFiltros.Visibility = 'Visible'
        } else {
            $c.BtnQuitarFiltros.Visibility = 'Collapsed'
        }

        # El segundo boton, por el mismo criterio: rotulo solo cuando se ve.
        # Los dos no pueden ofrecerse a la vez -Get-EstadoVacio lo garantiza
        # y hay prueba-, pero cada uno se apaga por su cuenta: si dependieran
        # uno del otro, un cambio en la funcion dejaria uno colgado visible.
        if ($veredicto.OfrecerMostrarHechos) {
            $c.BtnMostrarHechos.Content    = $veredicto.TextoBoton
            $c.BtnMostrarHechos.Visibility = 'Visible'
        } else {
            $c.BtnMostrarHechos.Visibility = 'Collapsed'
        }

        $c.EstadoVacio.Visibility = if ($veredicto.Vacio) { 'Visible' } else { 'Collapsed' }
    }

    $quitarFiltros = {
        # LOS DOS FILTROS, SIEMPRE.
        #
        # El panel tiene dos -el cuadro de texto y el desplegable de
        # riesgo- y quitar solo uno puede dejar la tabla igual de vacia.
        # Un boton que se pulsa y no cambia nada es indistinguible de uno
        # roto, que es el fallo de [USO-15] otra vez y justo el que este
        # cartel viene a evitar. El rotulo dice cuantos va a quitar, asi
        # que llevarse por delante un filtro que el usuario no habia
        # nombrado no es una sorpresa: estaba escrito en el boton.
        $c.FiltroRiesgo.SelectedIndex = 0
        $c.CampoFiltro.Text = ''

        # El desplegable filtra al momento; el cuadro de texto lo hace 250
        # ms despues de la ultima tecla. Sin este Stop, el temporizador que
        # acaba de armar la linea de arriba volveria a filtrar cuando ya no
        # hay nada que filtrar: una pasada entera por la tabla para nada.
        $estado.TemporizadorFiltro.Stop()
        & $aplicarFiltro

        # El foco vuelve al cuadro de filtro porque el boton que se acaba
        # de pulsar desaparece con el cartel, y dejar el foco sobre un
        # control que ya no esta deja al teclado en ninguna parte. Ver
        # [A11Y-06].
        [void] $c.CampoFiltro.Focus()
    }

    # =================================================================
    #  ABRIR LA UBICACION DE UNA FILA [USO-06]
    # =================================================================
    # Lo llaman TRES sitios: el boton de la barra de herramientas, la
    # entrada "Abrir ubicación" del menu contextual y el doble clic sobre
    # la fila. Un solo cierre y no tres copias, por lo mismo que [ARQ-01]:
    # tres copias divergen, y divergir aqui significa que el doble clic
    # abriria algo que el boton rechaza, o al reves. La comprobacion de
    # seguridad se escribe una vez.
    #
    # Las tres situaciones en las que este boton se quedaba callado -sin
    # fila elegida, con una ruta que ya no existe, y con un elemento que no
    # tiene ruta de verdad- dicen cada una lo suyo, porque las tres se
    # parecian demasiado a un boton roto.
    $abrirUbicacion = {
        param($Item)

        if ($null -eq $Item) {
            Show-Aviso -Mensaje 'Elige antes una fila de la lista: es su carpeta la que se abre.' -Tipo 'Information'
            return
        }

        # Se pregunta por TieneRutaReal y no por "el metodo es Comando".
        # Es la misma pregunta con mejor respuesta: la papelera tampoco
        # tiene ruta y NO es un comando, asi que antes caia en el Test-Path
        # de abajo y salia un "Ya no existe: Papelera de reciclaje" que no
        # es verdad -existe, simplemente no es una carpeta-. Ver [USO-06].
        if (-not $Item.TieneRutaReal) {
            Show-Aviso -Tipo 'Information' -Mensaje (& $describirSinRuta $Item 'ubicación que abrir')
            return
        }

        $ruta = $Item.Ruta
        if (-not (Test-Path -LiteralPath $ruta)) {
            Show-Aviso -Mensaje ("Ya no existe: {0}`n`nO se ha borrado o movido desde el análisis. Vuelve a analizar para tener la lista al día." -f $ruta) -Tipo 'Warning'
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
    }

    # Como se le explica al usuario que este elemento no tiene ruta.
    #
    # Lo necesitan las dos ordenes que solo tienen sentido sobre una ruta
    # -abrir la ubicación y copiar la ruta-, y tienen que decir LO MISMO:
    # si una lo llamara comando y la otra etiqueta, el usuario creeria que
    # son dos casos distintos. El final de la frase lo pone quien llama,
    # que es lo unico que cambia entre las dos.
    $describirSinRuta = {
        param($Item, [string] $QueNoHay)

        $que = if (-not [string]::IsNullOrWhiteSpace($Item.Comando)) {
            'es un comando del sistema ({0})' -f $Item.Comando
        } else {
            'es una etiqueta del programa, no una carpeta ni un archivo del disco'
        }
        return ('«{0}» {1}, así que no hay ninguna {2}.' -f $Item.Nombre, $que, $QueNoHay)
    }

    $actualizarResumenSeleccion = {
        if ($estado.SuprimirResumen) { return }

        # Que dice la tabla cuando no ensenya nada. Va aqui y no en cada
        # sitio que cambia la lista porque este cierre ya lo llaman los
        # cinco: el arranque, el final del analisis, cada modulo que
        # termina, cada cambio de filtro y cada casilla. Ver [USO-09].
        & $actualizarEstadoVacio

        # El resumen de la simulación caduca aqui. Sus cifras son las de lo
        # que estaba marcado CUANDO se simulo; en cuanto se marca o se
        # desmarca algo dejan de corresponder a nada. Un cartel que dice
        # "se habrian liberado 9,83 GB" encima de una selección que ya no
        # suma eso es la misma mentira de siempre, solo que mas educada.
        # Ver [USO-15]. Quien lo pone lo hace DESPUES de llamar aqui.
        if ($c.AvisoSimulacion.Visibility -ne 'Collapsed') {
            $c.AvisoSimulacion.Visibility = 'Collapsed'
            $c.TxtAvisoSimulacion.Text    = ''
        }

        # La barra de herramientas no tiene sentido con la tabla vacía:
        # antes seguia activa recien abierto el programa y sus botones no
        # hacian nada, que es indistinguible de que esten rotos.
        $hayResultados = $estado.Items.Count -gt 0
        $c.BtnMarcarTodo.IsEnabled    = $hayResultados
        $c.BtnDesmarcarTodo.IsEnabled = $hayResultados
        $c.BtnSoloSeguros.IsEnabled   = $hayResultados
        $c.BtnAbrirCarpeta.IsEnabled  = $hayResultados
        $c.BtnVerContenido.IsEnabled = $hayResultados
        $c.BtnExportar.IsEnabled      = $hayResultados

        # El total de marcados sale de Items, NO de la vista: es el número
        # que se va a borrar de verdad, lo esconda o no el filtro.
        #
        # Un solo foreach que cuenta y suma a la vez. Antes eran un
        # Where-Object -que invoca un scriptblock por fila- y después un
        # bucle sobre el resultado: dos pasadas y 15.000 invocaciones con
        # la tabla llena. Y esto se ejecuta en CADA clic de casilla, por el
        # UpdateSourceTrigger=PropertyChanged del enlace. Medido: 75-135 ms
        # por clic frente a 17 ms. Ver docs/RENDIMIENTO.md (sección 9).
        $cuentaMarcados = 0
        $bytes = 0.0
        foreach ($item in $estado.Items) {
            if ($item.Seleccionado -and -not $item.Hecho) {
                $cuentaMarcados++
                $bytes += $item.Bytes
            }
        }

        if ($cuentaMarcados -eq 0) {
            $c.TxtSeleccion.Text  = 'Nada marcado.'
            $c.TxtProyeccion.Text = if ($hayResultados) { 'Marca los elementos que quieras eliminar.' }
                                    else { 'Analiza el equipo para ver aquí lo que se puede recuperar.' }
            $c.BtnEliminar.IsEnabled = $false
            return
        }

        # Cuantos de esos marcados no están a la vista ahora mismo. Los
        # botones de marcado solo tocan lo visible, pero un filtro puesto
        # DESPUÉS puede esconder cosas ya marcadas, y el usuario tiene
        # derecho a saber que va a borrar algo que no esta mirando.
        #
        # Solo cuando hay un filtro puesto. Sin filtro la vista es la lista
        # entera, no puede haber nada escondido, y el segundo recorrido
        # -otras 15.000 iteraciones- no averigua nada: $ocultos sale 0
        # siempre. Es el caso del 90 % de los clics.
        $ocultos = 0
        if ($null -ne $estado.Vista -and $null -ne $estado.Vista.Filter) {
            $visiblesMarcados = 0
            foreach ($item in @($estado.Vista)) {
                if ($item.Seleccionado -and -not $item.Hecho) { $visiblesMarcados++ }
            }
            $ocultos = $cuentaMarcados - $visiblesMarcados
        }

        $libre = $estado.LibreCache
        $cuantos = if ($cuentaMarcados -eq 1) { '1 elemento marcado' } else { '{0} elementos marcados' -f $cuentaMarcados }
        $c.TxtSeleccion.Text = '{0} - se recuperarian {1}' -f $cuantos, (Format-Tamano $bytes)
        if ($ocultos -gt 0) {
            $c.TxtSeleccion.Text += ' ({0} que el filtro no esta mostrando)' -f $ocultos
        }
        $c.TxtProyeccion.Text = 'En {0} pasarias de {1} libres a {2} libres.' -f `
                                $estado.Configuracion.Unidad, (Format-Tamano $libre), (Format-Tamano ($libre + $bytes))
        $c.BtnEliminar.IsEnabled = -not $estado.Ocupado
    }

    $aplicarFiltro = {
        if ($null -eq $estado.Vista) { return }
        $texto  = $c.CampoFiltro.Text
        # La tabla de posiciones del desplegable vive en Get-RiesgoDelFiltro
        # y no aqui. La necesitan dos sitios -este filtro y el cartel que
        # explica la tabla vacia-, y dos copias de la misma tabla acaban
        # discrepando: bastaria con anyadir una posicion al ComboBox para
        # que el cartel ofreciera quitar un filtro que no ve. Ver [USO-09].
        $riesgo = Get-RiesgoDelFiltro -Indice $c.FiltroRiesgo.SelectedIndex

        # [USO-13]. NO entra en Test-HayFiltroPuesto, y no es un descuido:
        # esa funcion contesta "hay un filtro de BUSQUEDA puesto", y de esa
        # respuesta depende el rotulo del boton del cartel de tabla vacia
        # ("Quitar el filtro de texto"). Si la casilla contara como filtro,
        # ese boton prometeria quitar algo que no quita. Aqui se suma
        # aparte, que es lo unico que hace falta: que haya predicado.
        #
        # Si el control no estuviera en la ventana, esto da $false y la
        # tabla se comporta como siempre. Leer una propiedad de $null no
        # lanza en PowerShell.
        $ocultarHechos = [bool]$c.ChkOcultarHechos.IsChecked

        # Sin criterios no se instala un predicado que diga que si a todo:
        # se QUITA el filtro. Un predicado permisivo obliga igualmente a
        # WPF a invocarlo una vez por fila -y es un scriptblock de
        # PowerShell, no una función nativa-, mientras que Filter a $null
        # se salta el filtrado entero. Además deja "hay filtro puesto" como
        # una pregunta que se puede hacer, y de eso depende el segundo
        # recorrido del resumen del pie.
        #
        # La pregunta "hay algun filtro puesto" se hace con
        # Test-HayFiltroPuesto, la misma funcion que usa el cartel de la
        # tabla vacia. Si aqui un cuadro con tres espacios contara como
        # vacio y alli como filtro puesto -o al reves-, el cartel ofreceria
        # quitar un filtro que no existe y el boton no cambiaria nada.
        if (-not (Test-HayFiltroPuesto -TextoFiltro $texto -RiesgoFiltro $riesgo) -and -not $ocultarHechos) {
            if ($null -ne $estado.Vista.Filter) { $estado.Vista.Filter = $null }
            & $actualizarResumenSeleccion
            return
        }

        $estado.Vista.Filter = [Predicate[object]] {
            param($objeto)
            $item = [Cachivache.ItemVista]$objeto
            # [USO-13]: lo primero, y por Hecho.
            #
            # Hecho es la bandera que Window.Eliminacion.ps1 levanta SOLO
            # cuando el elemento se borro de verdad; un fallo se queda con
            # Hecho a $false y su texto en Estado. Preguntar por Hecho es
            # por tanto lo mismo que preguntar "esto salio bien", y es la
            # misma bandera de la que dependen el atenuado de la fila y el
            # desmarcado tras la limpieza: no puede discrepar con ellos.
            #
            # Un fallo NUNCA se esconde. Es lo unico de la lista que
            # todavia se puede arreglar y reintentar, y esconderlo seria
            # dar por limpiado algo que sigue en el disco. Ver [USO-02].
            if ($ocultarHechos -and $item.Hecho) { return $false }
            if ($riesgo -and $item.Riesgo -ne $riesgo) { return $false }
            if ([string]::IsNullOrWhiteSpace($texto)) { return $true }

            # IndexOf ordinal en vez de -like "*$texto*". Es más rápido
            # (10,8 us por fila frente a 15,9) y, sobre todo, arregla un
            # defecto: -like interpreta los comodines, así que un usuario
            # que escriba "*" o "?" o un "[" en el cuadro de busqueda
            # obtenia resultados absurdos o ninguno. Aquí el texto es
            # texto. Ver docs/RENDIMIENTO.md (sección 9).
            $comparacion = [StringComparison]::OrdinalIgnoreCase
            if ($item.Nombre -and $item.Nombre.IndexOf($texto, $comparacion) -ge 0) { return $true }
            if ($item.Ruta   -and $item.Ruta.IndexOf($texto, $comparacion)   -ge 0) { return $true }
            if ($item.Info   -and $item.Info.IndexOf($texto, $comparacion)   -ge 0) { return $true }
            return $false
        }.GetNewClosure()
        # Sin Refresh() aquí: asignar Filter ya provoca una pasada completa
        # de la vista. Llamarlo además hacia DOS recorridos por cada tecla
        # que se escribe en el cuadro de filtro, cada uno invocando el
        # predicado -un scriptblock de PowerShell- una vez por fila.
        #
        # Cambiar el filtro puede dejar marcados fuera de la vista, y el
        # pie es quien lo dice. Sin esta llamada el aviso solo se
        # actualizaria al tocar una casilla.
        & $actualizarResumenSeleccion
    }

    # Retardo del cuadro de texto. Escribir "chrome" con 15.000 filas
    # disparaba seis pasadas completas -una por tecla-, y cada pasada
    # invoca el predicado y el bloque del resumen una vez por fila:
    # 180.000 invocaciones de scriptblock, unos 2,9 s con el hilo de la
    # ventana bloqueado en seis tirones. Se pierden teclas.
    #
    # Con el temporizador se filtra 250 ms después de la ÚLTIMA tecla: seis
    # pasadas pasan a ser una. La cifra no es arbitraria; por debajo de
    # ~200 ms un mecanografo normal ya vuelve a disparar, y por encima de
    # ~350 ms se empieza a notar que la lista va por detras.
    #
    # No lleva GetNewClosure a propósito, por lo mismo que se explica en
    # $manejadorSeleccionGlobal: capturaria solo el ámbito local y dejaria
    # $aplicarFiltro a $null.
    $estado.TemporizadorFiltro = New-Object Windows.Threading.DispatcherTimer
    $estado.TemporizadorFiltro.Interval = [TimeSpan]::FromMilliseconds(250)
    $estado.TemporizadorFiltro.Add_Tick({
        $estado.TemporizadorFiltro.Stop()
        & $aplicarFiltro
    })

    $solicitarFiltro = {
        # Stop y Start: reiniciar la cuenta atras en cada tecla es lo que
        # hace que solo se filtre cuando el usuario para de escribir.
        $estado.TemporizadorFiltro.Stop()
        $estado.TemporizadorFiltro.Start()
    }

    $mostrarPanel = {
        param([string] $Cual)
        foreach ($nombre in @('PanelInicio', 'PanelResultados', 'PanelRegistro', 'PanelInformes', 'PanelAjustes', 'PanelAcerca')) {
            $c[$nombre].Visibility = if ($nombre -eq $Cual) { 'Visible' } else { 'Collapsed' }
        }

        # El foco va al panel que se acaba de mostrar, y no a un control
        # concreto de dentro. [A11Y-06].
        #
        # Antes esto solo alternaba la visibilidad. Para quien ve la pantalla
        # basta -el contenido cambia delante-, pero para un lector de pantalla
        # no ocurria NADA: el foco seguia en el boton de la barra lateral, y
        # los lectores anuncian lo que tiene el foco, no lo que se ha vuelto
        # visible. El usuario pulsaba "Resultados", oia "Resultados, boton de
        # opcion, marcado", y ahi se acababa: ninguna pista de que delante
        # tenia ahora una tabla con seiscientas filas.
        #
        # Al panel entero y no a su primer control por dos motivos. Uno: el
        # panel lleva por nombre su titulo visible, asi que el lector anuncia
        # "Resultados del analisis" -que es justo lo que hacia falta saber- y
        # Tab sigue desde ahi hacia dentro, en orden. Dos: el primer control
        # de Inicio es "Analizar el equipo", y dejar el foco encima de la
        # accion principal significa que un Espacio distraido lanza un
        # analisis que nadie pidio.
        #
        # DESPUES del bucle, no dentro: Focus() sobre un elemento Collapsed
        # devuelve $false y no hace nada. Si esto subiera arriba, el panel
        # todavia estaria oculto en el momento de pedir el foco y la funcion
        # entera se quedaria sin efecto, en silencio y sin fallar. Hay una
        # prueba que fija este orden.
        #
        # El valor de retorno se descarta: que Focus() devuelva $false no es
        # un fallo del que informar -pasa si la ventana aun no esta cargada-,
        # pero si se dejara pasar, ese $false se colaria en la salida de la
        # funcion y lo recogeria quien la llama.
        [void] $c[$Cual].Focus()
    }

    $aplicarTema = {
        param([string] $Nuevo)
        $estado.Tema = $Nuevo
        $estado.Preferencias.Tema = $Nuevo
        $archivo = if ($Nuevo -eq 'claro') { 'Theme.Light.xaml' } else { 'Theme.Dark.xaml' }
        $app.Resources.MergedDictionaries[0] = Import-Xaml (Join-Path $estado.CarpetaUi $archivo)

        # Los colores de las etiquetas viajan como cadenas, así que hay que
        # recalcularlos a mano al cambiar de tema.
        foreach ($vista in $estado.ModulosVista) {
            $vista.ColorRiesgo = Get-ColorRiesgo -Riesgo $vista.Riesgo -Tema $Nuevo
        }
        $c.ListaModulos.ItemsSource = $null
        $c.ListaModulos.ItemsSource = $estado.ModulosVista

        # Las filas de resultados llevan sus colores como cadenas y esas
        # propiedades no notifican cambios, así que hay que recalcularlas
        # y volver a enganchar la lista para que se repinte.
        foreach ($item in $estado.Items) {
            $item.ColorRiesgo = Get-ColorRiesgo -Riesgo $item.Riesgo -Tema $Nuevo
        }
        if ($estado.Items.Count -gt 0) {
            # Refresh() NO basta aquí. La tabla recicla sus contenedores
            # (VirtualizationMode="Recycling" en Styles.xaml): al rehacer
            # las filas, un contenedor reciclado puede recibir EL MISMO
            # objeto, con lo que asignar su DataContext no cuenta como
            # cambio y los enlaces a propiedades que no notifican -que es
            # el caso de ColorRiesgo- no se reevaluan. El
            # resultado eran chips con la paleta oscura sobre fondo claro.
            # Reasignar ItemsSource obliga a construir contenedores nuevos.
            #
            # Reasignar ItemsSource NO duplica el agrupado: lo que lo
            # duplicaba en [C-12] era volver a llamar a GetDefaultView y
            # añadir otra vez la agrupacion. La vista es la misma
            # instancia de siempre, con su filtro y su agrupado intactos.
            # Se reasigna la COLECCION, igual que en los otros tres sitios
            # que tocan esta propiedad: WPF resuelve su vista por defecto,
            # que es esta misma instancia con su filtro y su agrupado.
            #
            # Y el mismo par que en el análisis: reenganchar pierde el
            # sitio donde estaba el usuario. Cambiar de tema con la tabla
            # llena es un caso menos frecuente que el análisis, pero es
            # exactamente el mismo salto, así que se arregla con la misma
            # pieza y no con una copia. Ver [USO-10].
            $posicionTabla = & $guardarPosicionTabla
            $c.TablaResultados.ItemsSource = $null
            $c.TablaResultados.ItemsSource = $estado.Items
            $estado.Vista.Refresh()
            & $restaurarPosicionTabla $posicionTabla
        }

        # El icono alterna entre luna (tema oscuro) y sol (tema claro).
        $c.IconoTema.Data = Get-GeometriaTema $Nuevo

        # CARRERA DE DATOS: durante un analisis, NO se refrescan discos.
        #
        # $refrescarDiscos escribe $estado.Configuracion.Unidades y
        # .UnidadesSeleccionadas, y ese objeto se pasa POR REFERENCIA al
        # runspace que esta analizando en ese mismo momento. Cambiar el
        # tema con un analisis en marcha modificaba, desde el hilo de la
        # interfaz, la configuracion que el otro hilo estaba leyendo.
        #
        # El programa ya se blinda contra esto en Ajustes y en los
        # perfiles, con $ajusteBloqueadoPorTrabajo. Al boton de tema se le
        # olvido. Cambiar de color mientras se analiza es legitimo y sigue
        # funcionando: lo unico que se aplaza es volver a consultar los
        # discos, que no tiene nada que ver con el tema y solo estaba ahi
        # para repintar la barra de espacio. Ver [INT-03].
        if (-not $estado.Ocupado) {
            & $refrescarDiscos
            & $refrescarHistorial
        }
    }

