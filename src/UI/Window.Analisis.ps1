<#
.SYNOPSIS
    Análisis: los guiones que corren en el runspace, el lanzador de trabajos y el temporizador que sondea el progreso.

.DESCRIPTION
    Aquí vive la concurrencia. Nada de lo que se ejecuta en el runspace puede tocar un control de WPF: solo escribe en la tabla sincronizada.

    ESTE ARCHIVO NO SE EJECUTA SOLO. Es un trozo del cuerpo de
    Show-VentanaPrincipal (Window.ps1), que lo dot-sourcea desde
    DENTRO de la función. Por eso el código de aquí usa $c, $estado,
    $ventana y los cierres de Window.Ayudantes.ps1 sin declararlos:
    los ve porque se carga en el ámbito de esa función, igual que si
    el texto estuviera pegado allí. Ver docs/ESTRUCTURA.md (sección 3).
#>

    # =================================================================
    #  ANÁLISIS
    # =================================================================
    $temporizador = New-Object Windows.Threading.DispatcherTimer
    $temporizador.Interval = [TimeSpan]::FromMilliseconds(200)

    # 'Continue' (el valor por defecto de PowerShell), no 'SilentlyContinue':
    # con SilentlyContinue los errores no terminantes de un módulo (acceso
    # denegado, ruta demasiado larga, disco desconectado...) desaparecian
    # sin dejar rastro en $ps.Streams.Error y la interfaz decia "nada que
    # limpiar" como si el equipo estuviera limpio. Con 'Continue' el módulo
    # sigue funcionando exactamente igual (no es un error terminante, no
    # para nada), pero limpiarTrabajo puede leerlos después y dejar
    # constancia en el registro. Ver [C-13] en docs/OPTIMIZACIONES.md.
    $codigoAnalisis = @'
$ErrorActionPreference = 'Continue'
try {
    # El nucleo y la guardia ya estan cargados: los pone $abrirRunspace una
    # sola vez por analisis, no una por modulo. Ver [INT-01].
    #
    # Se carga UNICAMENTE el archivo del modulo que toca. Buscarlo por
    # identificador obligaria a dot-sourcear los veintiuno en cada paso.
    $modulo = . $archivoModulo
    if ($null -ne $modulo) {
        $sync.Resultado = Invoke-ModuloLimpieza -Modulo $modulo -Configuracion $cfg -Sync $sync
    }
} catch {
    $sync.Error = $_.Exception.Message
}
$sync.Terminado = $true
'@

    $codigoBorrado = @'
$ErrorActionPreference = 'Continue'
try {
    # Nucleo y guardia ya cargados por $abrirRunspace. Ver [INT-01].
    [void](Initialize-MotorBorrado)

    # El MISMO bucle que usa la consola, que vive en Remove.ps1. Aqui
    # habia una copia escrita a mano dentro de esta cadena de texto, y ya
    # habia divergido: contaba como hecho todo lo que intentaba, y anotaba
    # PAPELERA para cosas que se borraban permanentemente. Ver [ARQ-01].
    # El verbo se resuelve AQUI, en una variable normal, y no dentro del
    # bloque de progreso: ese bloque lo invoca Invoke-LoteEliminacion desde
    # su propio ambito, y depender de que $simular se vea desde alli seria
    # confiar en el alcance dinamico para algo que se lee en pantalla.
    # Decir "Eliminando" mientras no se elimina nada es justo la mentira
    # que este modo existe para evitar.
    $verbo = if ($simular) { 'Midiendo' } else { 'Eliminando' }

    $resultado = Invoke-LoteEliminacion -Candidatos $lote -Permanente:$permanente -Simular:$simular `
                    -Configuracion $cfg -Sync $sync -Confirm:$false `
                    -AlProgresar {
                        param($candidato, $avance)
                        $sync.Mensaje   = '{0}: {1}' -f $verbo, $candidato.Nombre
                        $sync.Resultado = [pscustomobject]@{
                            Hechos = $avance.Hechos; Liberado = $avance.Liberado
                        }
                    }.GetNewClosure()
    $sync.Resultado = [pscustomobject]@{
        Hechos    = $resultado.Hechos
        Liberado  = $resultado.Liberado
        Simulados = $resultado.Simulados
        Bloqueados = $resultado.Bloqueados
        Simulado  = $resultado.Simulado
    }
} catch {
    $sync.Error = $_.Exception.Message
}
$sync.Terminado = $true
'@

    # El nucleo se carga UNA vez por runspace, no una vez por trabajo.
    # Bootstrap.ps1 dot-sourcea los diecinueve archivos de src/Core -mas de
    # cuatro mil lineas- y despues se llama a Initialize-Guardia. Hacerlo
    # por modulo significaba pagarlo VEINTIUNA veces en cada analisis.
    # Ver [INT-01] en docs/PLAN-ACCION.md.
    $codigoArranqueRunspace = @'
$ErrorActionPreference = 'Continue'
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Bootstrap.ps1')
Initialize-Guardia -Configuracion $cfg
'@

    $abrirRunspace = {
        # Si ya hay uno abierto y sano, se reutiliza.
        if ($estado.Runspace -and $estado.Runspace.RunspaceStateInfo.State -eq 'Opened') { return }

        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = 'STA'
        $runspace.ThreadOptions  = 'ReuseThread'
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable('sync', $estado.Sync)
        $runspace.SessionStateProxy.SetVariable('raiz', $estado.Raiz)
        $runspace.SessionStateProxy.SetVariable('cfg',  $estado.Configuracion)

        # El arranque se ejecuta de forma sincrona: cuando esta funcion
        # vuelve, el runspace ya tiene el nucleo cargado y la guardia lista.
        $arranque = [powershell]::Create()
        try {
            $arranque.Runspace = $runspace
            [void]$arranque.AddScript($codigoArranqueRunspace)
            [void]$arranque.Invoke()
        } finally {
            $arranque.Dispose()
        }

        $estado.Runspace = $runspace
    }

    $cerrarRunspace = {
        # El runspace vive lo que dura el ANALISIS entero, no un modulo.
        # Cerrarlo es cosa de terminarAnalisis, de la cancelacion y del
        # cierre de la ventana; limpiarTrabajo solo suelta el trabajo.
        try { if ($estado.Runspace) { $estado.Runspace.Close(); $estado.Runspace.Dispose() } }
        catch { Write-Verbose "Cierre del runspace: $($_.Exception.Message)" }
        $estado.Runspace = $null
    }

    $lanzarTrabajo = {
        param([string] $Codigo, [hashtable] $Variables)

        $estado.Sync.Terminado = $false
        $estado.Sync.Cancelar  = $false
        $estado.Sync.Error     = ''
        $estado.Sync.Resultado = $null
        $estado.Sync.Mensaje   = 'Empezando...'

        # TODO el montaje va dentro del try. Sin el, un fallo al abrir el
        # runspace o al lanzar -limite de hilos, falta de memoria, una
        # politica de ejecucion- dejaba el programa colgado PARA SIEMPRE:
        # no se llegaba a $temporizador.Start(), asi que nadie volvia a
        # mirar el estado, $estado.Ocupado se quedaba en $true, el boton
        # "Analizar" deshabilitado y "Cancelar" a la vista sin nada que
        # cancelar. La unica salida era cerrar la ventana. Y el runspace ya
        # abierto no lo cerraba nadie. Ver [INT-02].
        try {
            & $abrirRunspace

            foreach ($clave in $Variables.Keys) {
                $estado.Runspace.SessionStateProxy.SetVariable($clave, $Variables[$clave])
            }

            $ps = [powershell]::Create()
            $ps.Runspace = $estado.Runspace
            [void]$ps.AddScript($Codigo)

            $estado.PowerShell = $ps
            $estado.Handle     = $ps.BeginInvoke()
            $temporizador.Start()
        } catch {
            $mensaje = $_.Exception.Message
            & $escribir ('No se ha podido lanzar el trabajo: {0}' -f $mensaje) 'ERROR'

            & $limpiarTrabajo
            & $cerrarRunspace

            $estado.Sync.Terminado = $true
            $estado.Sync.Error     = $mensaje

            # Devolver la ventana a un estado usable es lo que separa un
            # error de un programa inservible.
            if ($estado.Fase -eq 'analisis') { & $terminarAnalisis }
            else                             { & $terminarBorrado }
        }
    }

    $limpiarTrabajo = {
        $temporizador.Stop()
        # Stop() corta el trabajo en curso. Sin el, cerrar la ventana en
        # mitad de un recorrido largo de disco dejaba la aplicación
        # congelada hasta que el módulo terminase por su cuenta, porque la
        # bandera de cancelación solo se consulta entre iteraciones.
        try { if ($estado.PowerShell) { $estado.PowerShell.Stop() } }
        catch { Write-Verbose "Stop del runspace: $($_.Exception.Message)" }

        # Al cancelar es normal que EndInvoke se queje: el trabajo no ha
        # llegado a terminar. Se anota y se sigue liberando recursos.
        try { if ($estado.PowerShell) { [void]$estado.PowerShell.EndInvoke($estado.Handle) } }
        catch { Write-Verbose "EndInvoke: $($_.Exception.Message)" }

        # Antes de soltar el runspace: si el módulo tuvo errores no
        # terminantes (acceso denegado, ruta demasiado larga, disco
        # desconectado...), antes desaparecian sin dejar rastro. Se
        # agrupan por categoría para no ahogar el registro con los
        # "acceso denegado" legitimos de cualquier recorrido de disco: lo
        # que interesa es "N rutas inaccesibles", no las N líneas sueltas.
        # Ver [C-13] en docs/OPTIMIZACIONES.md.
        try {
            if ($estado.PowerShell -and $estado.PowerShell.HadErrors) {
                $maximoGrupos = 5
                $grupos = @($estado.PowerShell.Streams.Error |
                    Group-Object { $_.CategoryInfo.Category } |
                    Sort-Object Count -Descending)

                foreach ($grupo in @($grupos | Select-Object -First $maximoGrupos)) {
                    Write-Registro -Sync $estado.Sync -Nivel 'AVISO' -Mensaje (
                        '{0}: {1} rutas ({2})' -f $grupo.Name, $grupo.Count,
                        $grupo.Group[0].Exception.Message)
                }
                if ($grupos.Count -gt $maximoGrupos) {
                    Write-Registro -Sync $estado.Sync -Nivel 'AVISO' -Mensaje (
                        '... y {0} categorias de error más durante el análisis.' -f
                        ($grupos.Count - $maximoGrupos))
                }
            }
        } catch {
            Write-Verbose "No se han podido volcar los errores del modulo: $($_.Exception.Message)"
        }

        try { if ($estado.PowerShell) { $estado.PowerShell.Dispose() } }
        catch { Write-Verbose "Dispose del trabajo: $($_.Exception.Message)" }

        # El RUNSPACE no se cierra aqui: lo comparten todos los modulos del
        # mismo analisis y lo cierra $cerrarRunspace al terminar, al
        # cancelar o al cerrar la ventana. Lo que se suelta aqui es el
        # trabajo, que si es de un solo modulo. Ver [INT-01].
        $estado.PowerShell = $null
        $estado.Handle     = $null
    }

    $siguienteModulo = {
        if ($estado.Indice -ge $estado.Cola.Count) {
            & $terminarAnalisis
            return
        }
        $modulo = $estado.Cola[$estado.Indice]
        # La misma funcion que usa el temporizador, para que el texto no
        # cambie de forma entre "acabo de empezar el modulo" y "el
        # temporizador ha hecho su primer tick". Ver [USO-07].
        $c.TxtEstadoInicio.Text = Format-ProgresoAnalisis `
            -Modulo $modulo.Nombre `
            -Indice ($estado.Indice + 1) -Total $estado.Total `
            -Transcurrido $estado.Cronometro.Elapsed -Elementos $estado.Items.Count
        & $lanzarTrabajo $codigoAnalisis @{ archivoModulo = $modulo.Archivo }
    }

    $terminarAnalisis = {
        $estado.Ocupado = $false
        $estado.Fase    = 'reposo'
        $estado.Cronometro.Stop()

        # Aqui muere el runspace compartido por todos los modulos.
        & $cerrarRunspace

        $c.BtnAnalizar.IsEnabled  = $true
        $c.BtnCancelar.Visibility = 'Collapsed'
        $c.BarraInicio.Value      = 100
        $c.BarraInicio.Visibility = 'Collapsed'

        $bytes = 0.0
        foreach ($item in $estado.Items) { $bytes += $item.Bytes }
        $borrables = @($estado.Items | Where-Object { $_.Borrable })
        $bytesBorrables = 0.0
        foreach ($item in $borrables) { $bytesBorrables += $item.Bytes }

        # ---- ¿Ha terminado de verdad? --------------------------------
        #
        # Un análisis puede acabar de tres maneras y antes las tres decian
        # lo mismo: "Análisis terminado". Cancelar en el módulo 7 de 21
        # producia el mismo texto que recorrer los 21, asi que el usuario
        # miraba una lista incompleta creyendo que ahi estaba todo lo que
        # el equipo tiene, y borraba con esa idea. Ver [CNF-04].
        $fallidos   = @($estado.ModulosFallidos)
        $incompleto = [bool]$estado.AnalisisCancelado -or $fallidos.Count -gt 0
        $revisados  = [Math]::Min($estado.Indice, $estado.Total)

        $c.TxtEstadoInicio.Text = $(if ($estado.AnalisisCancelado) {
            'Análisis detenido a los {0}. Se revisaron {1} de {2} módulos.' -f `
                (Format-Duracion $estado.Cronometro.Elapsed), $revisados, $estado.Total
        } else {
            'Análisis terminado en {0}. No se ha borrado nada.' -f (Format-Duracion $estado.Cronometro.Elapsed)
        })

        $encontrados = if ($estado.Items.Count -eq 1) { '1 elemento encontrado' }
                       else { '{0} elementos encontrados' -f $estado.Items.Count }
        # El criterio de premarcado, DONDE se ve la lista. Estaba en el
        # README, en ARQUITECTURA.md y en el panel "Acerca de": tres sitios
        # donde nadie mira mientras decide que borrar. Sin saber la regla,
        # el usuario o desconfia de todo o se fia de todo. Ver [CNF-05].
        $criterio = Get-ResumenPremarcado -Candidatos $estado.Candidatos
        $c.TxtResumenAnalisis.Text = '{0} - {1} recuperables - {2} solo informativos. Nada se ha borrado.{3}' -f `
            $encontrados, (Format-Tamano $bytesBorrables), ($estado.Items.Count - $borrables.Count),
            $(if ($criterio) { ' ' + $criterio } else { '' })

        # La franja se queda puesta mientras dure la lista, porque el aviso
        # tiene que seguir ahi cuando el usuario decida qué marcar, no solo
        # en el instante de terminar.
        if ($incompleto) {
            $avisos = @()
            if ($estado.AnalisisCancelado) {
                $avisos += ('Lo detuviste en el módulo {0} de {1}: no se ha mirado el resto.' -f $revisados, $estado.Total)
            }
            if ($fallidos.Count -gt 0) {
                $avisos += ('{0} no se {1} podido completar: {2}.' -f `
                            $(if ($fallidos.Count -eq 1) { '1 módulo' } else { '{0} módulos' -f $fallidos.Count }),
                            $(if ($fallidos.Count -eq 1) { 'ha' } else { 'han' }),
                            ($fallidos -join ', '))
            }
            $c.TxtAvisoIncompleto.Text = ('Esta lista está incompleta. {0} Puede haber basura que no aparece aquí; mira el Registro para el detalle.' -f ($avisos -join ' '))
            $c.AvisoIncompleto.Visibility = 'Visible'
        } else {
            $c.AvisoIncompleto.Visibility = 'Collapsed'
            $c.TxtAvisoIncompleto.Text    = ''
        }

        & $escribir ''
        if ($incompleto) {
            & $escribir ('ANALISIS INCOMPLETO: {0} elementos, {1} recuperables, en {2}. {3}' -f `
                         $estado.Items.Count, (Format-Tamano $bytesBorrables),
                         (Format-Duracion $estado.Cronometro.Elapsed),
                         $c.TxtAvisoIncompleto.Text) 'AVISO'
        } else {
            & $escribir ('ANALISIS TERMINADO: {0} elementos, {1} recuperables, en {2}.' -f `
                         $estado.Items.Count, (Format-Tamano $bytesBorrables), (Format-Duracion $estado.Cronometro.Elapsed))
        }

        # Informe automático del análisis. Se genera ANTES de anotar la
        # entrada del historial para poder guardar su ruta dentro: sin ella
        # una tarjeta del historial es un resumen que no lleva a ninguna
        # parte, y no habría forma de volver a ver que proponia aquel
        # análisis. La limpieza hacia esto desde siempre; el análisis no.
        #
        # Si falla, se anota igual sin informe: perder la traza de que el
        # análisis ocurrio sería peor que quedarse sin el archivo.
        $rutaInforme = ''
        if ($estado.Candidatos.Count -gt 0) {
            try {
                $rutaInforme = New-NombreInforme -Tipo 'analisis' -Extension 'html' `
                                                 -CarpetaDatos $estado.Configuracion.CarpetaDatos
                Export-InformeHtml -Candidatos $estado.Candidatos -Ruta $rutaInforme `
                                   -Configuracion $estado.Configuracion -Modulos $estado.Modulos -Confirm:$false
                & $escribir ('Informe guardado en: {0}' -f $rutaInforme)
            } catch {
                & $escribir ('No se ha podido generar el informe: {0}' -f
                             (Get-DetalleExcepcion -ErrorRecord $_ -ConPila)) 'AVISO'
                $rutaInforme = ''
            }
        }

        # -Bytes es lo RECUPERABLE, no el total. La consola anotaba una
        # cosa y la ventana otra, asi que el mismo analisis producia dos
        # cifras distintas en historial.json segun por donde se lanzara, y
        # las tarjetas del historial no cuadraban entre si. Los
        # informativos -archivos grandes, perfiles de otros usuarios- no
        # se pueden recuperar: sumarlos infla el numero. Ver [INT-12].
        # -Modulos son los REVISADOS, no los de la cola. Anotar los 21 de la
        # cola cuando solo se llegó a mirar 7 convertiria el historial en
        # otro sitio donde el programa dice haber hecho lo que no hizo.
        $revisadosIds = @($estado.Cola | Select-Object -First $revisados | ForEach-Object { $_.Id })

        # La comparacion con el analisis anterior, pegada al resumen.
        # [CNF-06].
        #
        # ANTES del Add-EntradaHistorial, y no despues: en cuanto se anota
        # esta ejecucion, "el analisis anterior" pasa a ser ESTE, y el
        # programa se compararia consigo mismo -siempre cero de diferencia,
        # siempre en verde, y siempre mintiendo-.
        #
        # Se suma un Sufijo y no se escribe un if: cuando no hay con que
        # comparar, Get-ComparacionAnalisis devuelve cadena vacia y aqui no
        # queda ni un espacio colgando. Quien decide que se dice -y si se
        # puede decir algo- es esa funcion, que va probada.
        $c.TxtResumenAnalisis.Text += (Get-ComparacionAnalisis `
                                          -Historial (Get-Historial -CarpetaDatos $estado.Configuracion.CarpetaDatos) `
                                          -Perfil $estado.Configuracion.Perfil `
                                          -Modulos $revisadosIds).Sufijo

        Add-EntradaHistorial -Tipo 'analisis' -Elementos $estado.Items.Count -Bytes $bytesBorrables `
                             -Perfil $estado.Configuracion.Perfil `
                             -Modulos $revisadosIds `
                             -Informe $rutaInforme `
                             -Incompleto:$incompleto `
                             -Motivo $(if ($incompleto) { $c.TxtAvisoIncompleto.Text } else { '' }) `
                             -CarpetaDatos $estado.Configuracion.CarpetaDatos -Confirm:$false
        & $refrescarHistorial
        & $actualizarResumenSeleccion

        # ---- Lo mas grande primero ([USO-03]) --------------------------
        #
        # Es lo primero que quiere ver cualquiera al abrir una lista de
        # ciento y pico elementos, y hasta ahora habia que buscarlo a ojo
        # porque las cabeceras no ordenaban.
        #
        # Se hace AQUI y no al crear la vista: al empezar el analisis la
        # lista esta vacia y el orden no significa nada, y durante el
        # recorrido las filas van entrando de una en una. Reordenar en cada
        # llegada seria trabajo tirado y la lista bailaria delante del
        # usuario mientras la mira.
        #
        # La agrupacion por categoria se mantiene: WPF mete cada fila en su
        # grupo, y el orden de los grupos pasa a ser el del elemento mas
        # grande de cada uno. Que es exactamente lo que uno espera.
        try {
            $estado.Vista.SortDescriptions.Clear()
            $estado.Vista.SortDescriptions.Add(
                (New-Object ComponentModel.SortDescription 'Bytes', ([ComponentModel.ListSortDirection]::Descending)))
        } catch {
            # Ordenar es una comodidad: si fallara, la lista sigue siendo
            # correcta y el usuario puede ordenar a mano. No vale la pena
            # que un adorno impida ver los resultados.
            Write-Verbose "No se ha podido ordenar la lista: $($_.Exception.Message)"
        }

        if ($estado.Items.Count -gt 0) {
            $c.NavResultados.IsChecked = $true
        }
    }

    $appendResult = {
        param($Resultado)
        if ($null -eq $Resultado) { return }
        $modulo = $estado.Modulos | Where-Object { $_.Id -eq $Resultado.ModuloId } | Select-Object -First 1
        $nombreModulo = if ($modulo) { $modulo.Nombre } else { $Resultado.ModuloId }

        if ($Resultado.Omitido) {
            & $escribir ("  {0}: omitido - {1}" -f $nombreModulo, $Resultado.Omitido) 'OMITIDO'
            return
        }
        if ($Resultado.Error) {
            & $escribir ("  {0}: ERROR - {1}" -f $nombreModulo, $Resultado.Error) 'ERROR'
            return
        }

        $candidatos = @($Resultado.Candidatos)
        if ($candidatos.Count -eq 0) {
            & $escribir ("  {0}: nada que limpiar." -f $nombreModulo)
            return
        }

        # Se desengancha la tabla mientras se añaden las filas: así el
        # DataGrid no reagrupa ni repinta una vez por cada fila, que es lo
        # que hacia que un módulo con dos mil resultados tardará minutos
        # en aparecer.
        #
        # Aquí había un $estado.Vista.DeferRefresh(), y era un error: ese
        # método sirve para agrupar cambios en las PROPIEDADES de la vista
        # (orden, agrupacion, filtro), no para añadir elementos. WPF
        # prohibe expresamente tocar la coleccion mientras hay un refresco
        # aplazado y lanza "no se puede cambiar o comprobar el contenido o
        # la posición Current de CollectionView mientras Refresh se esta
        # aplazando" en el primer Add. Es decir: el análisis reventaba
        # siempre, en cuanto un módulo devolvia el primer resultado.
        #
        # Desenganchar y volver a enganchar consigue el mismo ahorro y es
        # legal. La vista sobrevive: GetDefaultView devuelve siempre la
        # misma instancia para la misma coleccion, así que la agrupacion
        # por categoría y el filtro activo siguen puestos al reenganchar.
        $c.TablaResultados.ItemsSource = $null
        try {

            $suma = 0.0
            foreach ($candidato in $candidatos) {
                $suma += $candidato.Bytes
                $estado.Candidatos.Add($candidato)

                $item = New-Object Cachivache.ItemVista
                $item.Categoria = $candidato.Categoria
                $item.Nombre    = $candidato.Nombre
                $item.Ruta      = $candidato.Ruta
                $item.Info      = $candidato.Info
                $item.Efecto    = $candidato.Efecto
                $item.Aviso     = $candidato.Aviso
                $item.Metodo    = $candidato.Metodo
                $item.Comando   = $candidato.Comando
                $item.Riesgo    = $candidato.Riesgo
                $item.Bytes     = $candidato.Bytes
                $item.Tamano    = if ($candidato.Bytes -gt 0) { Format-Tamano $candidato.Bytes } else { '-' }
                $item.Borrable  = $candidato.Metodo -ne 'Informativo'
                $item.Origen    = $candidato
                $item.ColorRiesgo = Get-ColorRiesgo -Riesgo $candidato.Riesgo -Tema $estado.Tema
                $item.Seleccionado = $candidato.Seleccionado -and $item.Borrable
                # Por que el programa lo marco solo, o por que no. Sale de
                # Get-MotivoPremarcado, la MISMA funcion de la que sale la
                # decision: si fueran dos copias acabarian diciendo cosas
                # distintas. Ver [CNF-05].
                $item.MotivoMarcado = Get-MotivoPremarcado -Riesgo $candidato.Riesgo `
                                        -Aviso $candidato.Aviso -Metodo $candidato.Metodo
                # La clave de exclusion se COPIA, no se recalcula. La
                # decide Get-ClaveExclusion al nacer el candidato, y de
                # ella dependen dos cosas de la fila: a que se anyade
                # "Excluir siempre esto" y si "Copiar ruta" tiene algo que
                # copiar. Calcularla otra vez aqui seria un segundo sitio
                # decidiendo lo mismo, que es como se acaba excluyendo una
                # cosa y comparando otra. Ver [USO-06] y [ARQ-03].
                $item.ClaveExclusion = $candidato.ClaveExclusion

                $item.add_PropertyChanged($manejadorSeleccionGlobal)
                $estado.Items.Add($item)
            }

        } finally {
            $c.TablaResultados.ItemsSource = $estado.Items
        }

        & $escribir ("  {0}: {1} elementos, {2}." -f $nombreModulo, $candidatos.Count, (Format-Tamano $suma))
        if ($Resultado.Descartados -gt 0) {
            & $escribir ("     {0} descartados por la guardia de seguridad." -f $Resultado.Descartados) 'BLOQUEADO'
        }
    }

    $temporizador.Add_Tick({
        # Vaciar la cola es lo primero, pase lo que pase: el runspace de
        # análisis o borrado puede haber encolado líneas incluso en el
        # instante en que $estado.Ocupado se pone a $false, y esta es la
        # única pasada del temporizador que las va a recoger antes de
        # pararse. Ver [C-19] en docs/OPTIMIZACIONES.md.
        #
        # Aquí es donde el panel de Registro se entera de lo que hace el
        # runspace: una línea por elemento borrado, cada comando rechazado
        # por la lista blanca y los errores agrupados del análisis salen
        # todos por este camino.
        & $volcarRegistro

        if (-not $estado.Ocupado) { $temporizador.Stop(); return }

        $mensaje = $estado.Sync.Mensaje
        if ($estado.Fase -eq 'analisis') {
            # Esto corre cinco veces por segundo. El tiempo y el contador
            # de elementos son los dos datos que SE MUEVEN aunque el modulo
            # lleve minutos en la misma operacion: sin ellos, una busqueda
            # de duplicados larga era indistinguible de un cuelgue, y lo
            # razonable ante un programa colgado es matarlo. Ver [USO-07].
            $nombreModulo = if ($estado.Indice -lt $estado.Cola.Count) {
                [string]$estado.Cola[$estado.Indice].Nombre
            } else { '' }
            $c.TxtEstadoInicio.Text = Format-ProgresoAnalisis `
                -Modulo $nombreModulo -Mensaje $mensaje `
                -Indice ($estado.Indice + 1) -Total $estado.Total `
                -Transcurrido $estado.Cronometro.Elapsed -Elementos $estado.Items.Count
        } else {
            $c.TxtSeleccion.Text = $mensaje
            $avance = $estado.Sync.Resultado
            if ($null -ne $avance -and $estado.Total -gt 0) {
                $c.BarraBorrado.Value = 100 * $avance.Hechos / $estado.Total
            }
        }

        if (-not $estado.Sync.Terminado) { return }
        & $limpiarTrabajo

        if ($estado.Sync.Error) {
            & $escribir ('ERROR: {0}' -f $estado.Sync.Error) 'ERROR'

            # Se apunta QUE modulo ha fallado, no solo que ha habido un
            # error. Antes esto moria en el registro: la pestaña de
            # Resultados presentaba una lista a la que le faltaban modulos
            # enteros exactamente igual que una completa. Ver [CNF-04].
            if ($estado.Fase -eq 'analisis' -and $estado.Indice -lt $estado.Cola.Count) {
                $estado.ModulosFallidos.Add([string]$estado.Cola[$estado.Indice].Nombre)
            }
        }

        # Aqui vivia una rama "if ($estado.Sync.Cancelar)" ANTES de esta,
        # que era inalcanzable: los tres sitios que ponen Cancelar a $true
        # llaman acto seguido a $limpiarTrabajo, que para el temporizador,
        # asi que este tick no vuelve a ejecutarse. Ver [INT-09].
        if ($estado.Fase -eq 'analisis') {
            & $appendResult $estado.Sync.Resultado
            $estado.Indice++
            $c.BarraInicio.Value = 100 * $estado.Indice / [Math]::Max(1, $estado.Total)
            & $actualizarResumenSeleccion
            if ($estado.Sync.Cancelar) {
                $estado.AnalisisCancelado = $true
                & $escribir 'Análisis cancelado por el usuario.' 'AVISO'
                & $terminarAnalisis
            } else {
                & $siguienteModulo
            }
        } else {
            & $terminarBorrado
        }
    })

