<#
.SYNOPSIS
    Eliminación: preparacion del lote, confirmación y cierre del borrado.

.DESCRIPTION
    El borrado real lo hace Invoke-EliminacionCandidato en el nucleo; esto solo decide que se manda y que se hace al terminar.

    ESTE ARCHIVO NO SE EJECUTA SOLO. Es un trozo del cuerpo de
    Show-VentanaPrincipal (Window.ps1), que lo dot-sourcea desde
    DENTRO de la función. Por eso el código de aquí usa $c, $estado,
    $ventana y los cierres de Window.Ayudantes.ps1 sin declararlos:
    los ve porque se carga en el ámbito de esa función, igual que si
    el texto estuviera pegado allí. Ver docs/ESTRUCTURA.md (sección 3).
#>

    # =================================================================
    #  ELIMINACIÓN
    # =================================================================
    $terminarBorrado = {
        $estado.Ocupado = $false
        $estado.Fase    = 'reposo'

        # El runspace se comparte durante toda la operacion y muere aqui.
        # Ver [INT-01] en docs/PLAN-ACCION.md.
        & $cerrarRunspace

        $resultado = $estado.Sync.Resultado
        $liberado  = if ($resultado) { [double]$resultado.Liberado } else { 0.0 }
        $hechos    = if ($resultado) { [int]$resultado.Hechos } else { 0 }

        # El modo sale de $estado, fijado al pulsar el boton, y NO de la
        # casilla ni del resultado: la casilla puede haber cambiado mientras
        # corria el lote, y el resultado no llega si el trabajo se cae a
        # medias. Justo entonces es cuando no se puede anotar en el
        # historial una limpieza que nunca ocurrio.
        # Ver [CNF-02] en docs/HOJA-DE-RUTA.md.
        $simulado  = [bool]$estado.SimulandoLote
        $simulados = if ($resultado -and $null -ne $resultado.Simulados) { [int]$resultado.Simulados } else { 0 }
        # Los que la simulacion dice que NO se borrarian. Callarlos seria
        # volver a prometer un espacio que no se va a liberar. Ver [CNF-02].
        $bloqueados = if ($resultado -and $null -ne $resultado.Bloqueados) { [int]$resultado.Bloqueados } else { 0 }

        # La bandera es imprescindible: $item.Seleccionado = $false dispara
        # PropertyChanged, y su manejador recalcula el resumen del pie, que
        # recorre TODOS los elementos y además materializa la vista
        # filtrada. Sin suprimirlo, cerrar una limpieza de cinco mil
        # elementos hacia cinco mil recalculos completos, cada uno sobre
        # cinco mil filas, dentro del hilo de la ventana: la aplicación se
        # quedaba en "No responde" varios minutos justo al terminar de
        # borrar, que es el peor momento posible para parecer colgada.
        # El resumen se recalcula una sola vez, más abajo. Es la misma
        # bandera que ya usaba el marcado en lote.
        $estado.SuprimirResumen = $true
        try {
            foreach ($item in $estado.Items) {
                if ($item.Origen.Hecho -or $item.Origen.Error) {
                    $item.Hecho = [bool]$item.Origen.Hecho
                    # Solo se desmarca lo que SE BORRO. Antes se desmarcaba
                    # todo, fallos incluidos: el pie pasaba a decir "nada
                    # marcado", la lista parecia despachada y lo que no se
                    # pudo borrar desaparecia de la vista del usuario sin
                    # haberse tocado. Dejarlo marcado permite arreglar la
                    # causa -cerrar el programa que lo tenia abierto, marcar
                    # borrado permanente- y volver a pulsar. Ver [USO-02].
                    if ($item.Origen.Hecho) { $item.Seleccionado = $false }
                    $item.Estado = if ($item.Origen.Error) { $item.Origen.Error } else { 'Eliminado' }
                    if ($item.Origen.Error) {
                        # Se encola y se vuelca UNA vez al salir del bucle,
                        # en vez de usar $escribir, que fuerza un volcado
                        # -escritura en disco más repintado del panel- por
                        # cada línea. Con muchos avisos eran cientos de
                        # escrituras sueltas.
                        Write-Registro -Sync $estado.Sync -Nivel 'AVISO' -Mensaje (
                            '  Aviso en {0}: {1}' -f $item.Nombre, $item.Origen.Error)
                    }
                }
            }
        } finally {
            $estado.SuprimirResumen = $false
            & $volcarRegistro
        }

        $c.BarraBorrado.Visibility       = 'Collapsed'
        $c.BtnCancelarBorrado.Visibility = 'Collapsed'
        $c.BtnEliminar.IsEnabled         = $true
        $c.BtnAnalizar.IsEnabled         = $true

        # ---- Simulacion: se cuenta lo que habria pasado y se para aqui ----
        #
        # Ni informe ni entrada en el historial. Un historial con limpiezas
        # que no ocurrieron y un informe titulado "limpieza" que enumera
        # archivos que siguen en el disco son exactamente la misma clase de
        # mentira que esta auditoria lleva corrigiendo desde el principio:
        # el programa afirmando haber hecho algo que no hizo.
        #
        # Tampoco se refresca el espacio en disco: no ha cambiado, y
        # enseñar la cifra invita a buscarle una diferencia que no existe.
        if ($simulado) {
            & $escribir ''
            & $escribir ('SIMULACION TERMINADA: se habrian eliminado {0} elementos y liberado {1}.' -f `
                         $simulados, (Format-Tamano $liberado)) 'SIMULACION'
            if ($bloqueados -gt 0) {
                & $escribir ('{0} {1} se habrian quedado sin borrar. Mira las lineas [BLOQUEADO] de arriba.' -f `
                             $bloqueados, $(if ($bloqueados -eq 1) { 'elemento' } else { 'elementos' })) 'BLOQUEADO'
            }
            & $escribir 'NO SE HA BORRADO NADA. Lo marcado sigue marcado: desmarca lo que quieras conservar,' 'SIMULACION'
            & $escribir 'quita "Solo simular" y vuelve a pulsar para hacerlo de verdad.' 'SIMULACION'

            # DESPUES de actualizar el resumen, no antes: esa llamada es
            # justo la que borra el cartel anterior. Al reves, la
            # simulación se tapaba a si misma.
            & $actualizarResumenSeleccion

            $resumen = Format-ResumenSimulacion `
                -Simulados $simulados -Liberado $liberado -Bloqueados $bloqueados

            # Si el cartel no esta, se DICE. Este bloque existe para que la
            # simulación deje de ser muda; que fallara en silencio seria el
            # mismo fallo otra vez, escondido un piso mas abajo. Y un
            # FindName que devuelve nulo no lanza al leerlo: se traga la
            # linea y sigue como si nada.
            if ($null -eq $c.AvisoSimulacion -or $null -eq $c.TxtAvisoSimulacion) {
                & $escribir (('AVISO INTERNO: no se encuentra el cartel de la simulación en la ventana. ' +
                              'El resultado solo se ve aquí: {0}') -f $resumen) 'ERROR'
            } else {
                $c.TxtAvisoSimulacion.Text    = $resumen
                $c.AvisoSimulacion.Visibility = 'Visible'
            }

            $estado.Vista.Refresh()
            return
        }

        # Una limpieza detenida a mitad no es una limpieza terminada. Se
        # anotaba en el historial igual que una completa, asi que semanas
        # despues -cuando el historial es lo unico que queda- decia que se
        # habian limpiado 400 elementos de los que solo se borraron 3.
        # Ver [CNF-04].
        $detenida = [bool]$estado.Sync.Cancelar
        $motivo   = if ($detenida) {
            'La detuviste a mitad: se eliminaron {0} de {1} elementos marcados.' -f $hechos, $estado.Total
        } else { '' }

        $libreAhora = Get-EspacioLibre $estado.Configuracion.Unidad
        & $escribir ''
        if ($detenida) {
            & $escribir ('LIMPIEZA DETENIDA: {0} de {1} elementos, {2} liberados. Lo ya borrado sigue borrado.' -f `
                         $hechos, $estado.Total, (Format-Tamano $liberado)) 'AVISO'
        } else {
            & $escribir ('LIMPIEZA TERMINADA: {0} elementos, {1} liberados.' -f $hechos, (Format-Tamano $liberado)) 'BORRADO'
        }
        & $escribir ('Espacio libre en {0}: {1} (antes {2}).' -f `
                     $estado.Configuracion.Unidad, (Format-Tamano $libreAhora), (Format-Tamano $estado.LibreInicial))

        # ---- Que se puede rescatar ([CNF-03]) --------------------------
        #
        # El programa manda a la papelera por defecto, pero nunca lo decia:
        # la red de seguridad existia y el usuario no se enteraba. Y hay
        # que ser EXACTO, porque prometer de mas aqui es peor que callarse:
        # vaciar la papelera, los comandos externos como DISM y las caches
        # con ForzarPermanente no se pueden deshacer, y decir lo contrario
        # haria que alguien contara con recuperar algo que ya no existe.
        $rescate = Get-ResumenRecuperable -Candidatos $estado.Candidatos `
                                          -Permanente:$estado.Configuracion.Permanente
        if ($rescate.Recuperables -gt 0) {
            & $escribir ('{0} {1} en la papelera de Windows: se {2} recuperar desde ahi mientras no la vacies.' -f `
                         $rescate.Recuperables,
                         $(if ($rescate.Recuperables -eq 1) { 'elemento esta' } else { 'elementos estan' }),
                         $(if ($rescate.Recuperables -eq 1) { 'puede' } else { 'pueden' }))
            $c.BtnAbrirPapelera.Visibility = 'Visible'
        }
        if ($rescate.Definitivos -gt 0) {
            & $escribir ('{0} {1} sin paso por la papelera: eso no tiene vuelta atras.' -f `
                         $rescate.Definitivos,
                         $(if ($rescate.Definitivos -eq 1) { 'elemento se ha borrado' } else { 'elementos se han borrado' })) 'AVISO'
        }

        # Informe automático de lo que se ha hecho. Va ANTES de anotar la
        # entrada del historial para poder guardar su ruta dentro y que la
        # tarjeta pueda ofrecer abrirlo. Si falla, la entrada se anota
        # igualmente sin informe.
        $rutaInforme = ''
        try {
            $rutaInforme = New-NombreInforme -Tipo 'limpieza' -Extension 'html' -CarpetaDatos $estado.Configuracion.CarpetaDatos
            Export-InformeHtml -Candidatos @($estado.Candidatos | Where-Object { $_.Hecho }) -Ruta $rutaInforme `
                               -Configuracion $estado.Configuracion -Tipo 'limpieza' -Modulos $estado.Modulos -Confirm:$false
            & $escribir ('Informe guardado en: {0}' -f $rutaInforme)
        } catch {
            & $escribir ('No se ha podido generar el informe: {0}' -f
                         (Get-DetalleExcepcion -ErrorRecord $_ -ConPila)) 'AVISO'
            $rutaInforme = ''
        }

        Add-EntradaHistorial -Tipo 'limpieza' -Elementos $hechos -Bytes $liberado `
                             -Perfil $estado.Configuracion.Perfil `
                             -LibreAntes $estado.LibreInicial -LibreDespues $libreAhora `
                             -Informe $rutaInforme `
                             -Incompleto:$detenida -Motivo $motivo `
                             -CarpetaDatos $estado.Configuracion.CarpetaDatos -Confirm:$false

        & $refrescarDiscos
        & $refrescarHistorial
        & $actualizarResumenSeleccion
        $estado.Vista.Refresh()
    }

