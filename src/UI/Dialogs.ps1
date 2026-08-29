<#
.SYNOPSIS
    Dialogos modales de la interfaz.
#>

function Get-LineasConfirmacion {
    <#
    .SYNOPSIS
        Las lineas que se ensenyan en el dialogo antes de borrar.

    .DESCRIPTION
        Esta aparte de Show-Confirmacion, y no es capricho: aqui se decide
        QUE VE el usuario justo antes de destruir algo, y eso tiene que
        poder probarse. Show-Confirmacion abre una ventana de WPF, que no
        arranca en las pruebas; esto es texto entrando y texto saliendo.

        -------------------------------------------------------------------
        DOS REGLAS, Y LA PRIMERA MANDA SOBRE LA SEGUNDA

        1. TODO comando externo se ensenya. Sin excepcion.

           SECURITY.md exige que un comando externo sea "siempre visible y
           siempre con confirmacion". Antes se cogian los cinco elementos
           mas grandes y ya: si el unico candidato que lanza
           "docker system prune -a -f" no estaba entre esos cinco -y con
           218 elementos marcados lo normal es que no lo este-, el usuario
           confirmaba la ejecucion de un comando que nunca vio.

           Por eso los que llevan comando van PRIMERO y ninguno se corta.

        2. Del resto se ensenyan los mas gordos, hasta un tope.

           Y si sobran, se DICE cuantos quedan. Antes ponia "218 requieren
           tu criterio" y se listaban cinco, sin una palabra sobre los
           otros 213: parecia la lista entera.

    .PARAMETER Maximo
        Cuantos elementos SIN comando se listan como mucho. Los que llevan
        comando no cuentan para este tope: ver la regla 1.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Arriesgados,
        [int] $Maximo = 25
    )

    $todos = @($Arriesgados)
    if ($todos.Count -eq 0) { return @() }

    $describir = {
        param($Elemento)
        $motivo = if ([string]::IsNullOrWhiteSpace($Elemento.Aviso)) {
            "riesgo $([string]$Elemento.Riesgo)".ToLower()
        } else { $Elemento.Aviso }
        $linea = '- {0} ({1}) - {2}' -f $Elemento.Nombre, $Elemento.Tamano, $motivo
        if (-not [string]::IsNullOrWhiteSpace($Elemento.Comando)) {
            $linea += "`n     Ejecuta: $($Elemento.Comando)"
        }
        return $linea
    }

    $conComando = @($todos | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Comando) })
    $sinComando = @($todos | Where-Object { [string]::IsNullOrWhiteSpace($_.Comando) } |
                    Sort-Object Bytes -Descending)

    $lineas = [Collections.Generic.List[string]]::new()
    foreach ($elemento in $conComando) { $lineas.Add((& $describir $elemento)) }

    $mostrados = @($sinComando | Select-Object -First $Maximo)
    foreach ($elemento in $mostrados) { $lineas.Add((& $describir $elemento)) }

    $ocultos = $sinComando.Count - $mostrados.Count
    if ($ocultos -gt 0) {
        $lineas.Add(('  ... y {0} {1} más que no caben aquí. Están todos marcados en la lista de resultados.' -f
                     $ocultos, $(if ($ocultos -eq 1) { 'elemento' } else { 'elementos' })))
    }

    return $lineas.ToArray()
}

function Show-Confirmacion {
    <#
    .SYNOPSIS
        Pide confirmación escrita antes de eliminar.

    .DESCRIPTION
        Obliga a teclear una palabra exacta. Si en el lote hay elementos de
        riesgo medio o alto, la palabra cambia y se listan los casos que
        hacen falta para decidir con la información delante: qué se lista
        exactamente lo decide Get-LineasConfirmacion, que está aparte
        justamente para poder probarlo.

    .OUTPUTS
        [bool] $true si el usuario ha confirmado.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] $Propietario,
        [Parameter(Mandatory)] [string] $CarpetaUi,
        [Parameter(Mandatory)] [int]    $Elementos,
        [Parameter(Mandatory)] [double] $Bytes,
        [bool] $Permanente = $false,
        $Arriesgados = @()
    )

    $dialogo = Import-Xaml (Join-Path $CarpetaUi 'ConfirmDialog.xaml')
    $dialogo.Owner = $Propietario

    $lista = @($Arriesgados)
    $palabra = if ($lista.Count -gt 0 -or $Permanente) { 'ELIMINAR' } else { 'SI' }

    $txtSubtitulo = $dialogo.FindName('TxtSubtitulo')
    $txtElementos = $dialogo.FindName('TxtElementos')
    $txtEspacio   = $dialogo.FindName('TxtEspacio')
    $txtDestino   = $dialogo.FindName('TxtDestino')
    $marcoRiesgo  = $dialogo.FindName('MarcoRiesgo')
    $txtRiesgo    = $dialogo.FindName('TxtRiesgo')
    $listaRiesgo  = $dialogo.FindName('ListaRiesgo')
    $txtInstruccion = $dialogo.FindName('TxtInstruccion')
    $campo        = $dialogo.FindName('CampoConfirmacion')
    $txtError     = $dialogo.FindName('TxtError')
    $btnSi        = $dialogo.FindName('BtnSi')
    $btnNo        = $dialogo.FindName('BtnNo')

    $txtSubtitulo.Text = 'Esta acción no la puede deshacer el programa.'
    $txtElementos.Text = '{0}' -f $Elementos
    $txtEspacio.Text   = Format-Tamano $Bytes
    $txtDestino.Text   = if ($Permanente) { 'Borrado permanente' } else { 'Papelera de reciclaje' }
    $txtInstruccion.Text = "Para continuar, escribe $palabra tal cual:"

    if ($lista.Count -gt 0) {
        $marcoRiesgo.Visibility = 'Visible'
        $txtRiesgo.Text = '{0} de los elementos marcados requieren tu criterio:' -f $lista.Count
        $listaRiesgo.ItemsSource = @(Get-LineasConfirmacion -Arriesgados $lista)
    }

    $validar = {
        $coincide = $campo.Text.Trim() -ceq $palabra
        $btnSi.IsEnabled = $coincide
        $txtError.Visibility = if ($campo.Text.Length -gt 0 -and -not $coincide) { 'Visible' } else { 'Collapsed' }
    }.GetNewClosure()

    $campo.Add_TextChanged($validar)
    # Enter solo desde el cuadro de texto, y solo si la palabra ya coincide.
    # Escape NO se maneja aqui: lo hace IsCancel="True" en el boton Cancelar,
    # que funciona con el foco donde sea. Ver [A11Y-03].
    $campo.Add_KeyDown({
        param($remitente, $argumentos)
        if ($argumentos.Key -eq 'Enter' -and $btnSi.IsEnabled) { $dialogo.DialogResult = $true }
    }.GetNewClosure())

    $btnSi.Add_Click({ $dialogo.DialogResult = $true }.GetNewClosure())
    $btnNo.Add_Click({ $dialogo.DialogResult = $false }.GetNewClosure())
    $dialogo.Add_ContentRendered({ $campo.Focus() }.GetNewClosure())

    return [bool]$dialogo.ShowDialog()
}

function Show-Aviso {
    <#
    .SYNOPSIS
        Mensaje breve con el estilo del sistema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Mensaje,
        [string] $Titulo = 'Cachivache',
        [ValidateSet('Information', 'Warning', 'Error')] [string] $Tipo = 'Information'
    )
    [void][Windows.MessageBox]::Show($Mensaje, $Titulo, 'OK', $Tipo)
}
