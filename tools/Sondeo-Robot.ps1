<#
.SYNOPSIS
    [VAL-05] · sondeo: .se puede manejar la ventana de Cachivache desde un
    guion? SOLO WINDOWS. No hace falta administrador.

.DESCRIPTION
    ESTO NO ES EL ROBOT. Es la pregunta que hay que contestar ANTES de
    escribir el robot.

    El hueco que [VAL-05] quiere tapar esta medido: src/Core al 89%,
    src/Cli al 89% y src/UI al 7,3% -1.814 instrucciones que no se ejecutan
    jamas-. Los cuatro fallos de interfaz del 4 de septiembre se veian a
    simple vista y ninguna de las 2.326 pruebas podia verlos, porque
    ninguna abre la ventana.

    La idea es usar UI Automation, que es la misma API que usan los
    lectores de pantalla. Y hay un motivo para pensar que puede salir: al
    cerrar [A11Y-01] se le puso AutomationProperties.Name a cada control,
    asi que la ventana ya se puede recorrer por nombres en vez de por
    pixeles. Sin quererlo, aquel trabajo dejo montada la infraestructura.

    PERO ESO ES UNA HIPOTESIS, y este proyecto lleva dos puntos muertos
    esta semana -[VEL-01] y [VEL-02]- por escribir cientos de lineas
    contra la documentacion antes de ejecutar una sola. Asi que primero se
    pregunta:

        1. .Arranca la ventana desde un guion y se la puede localizar?
        2. .Se le pueden enumerar los controles por su nombre accesible?
        3. .Se puede PULSAR uno y que el programa se entere?
        4. .Se puede LEER lo que la ventana dice despues?
        5. .Se cierra sola, sin dejar un proceso colgado?

    Si las cinco salen bien, el robot se puede escribir y merece la pena
    llevarlo a la integracion continua. Si alguna falla, se documenta y se
    descarta, que es un resultado igual de valido y mucho mas barato ahora
    que dentro de dos dias.

    -------------------------------------------------------------------
    QUE TOCA ESTE GUION: abre Cachivache, mira, pulsa DOS botones que no
    borran nada -cambiar de panel y volver- y lo cierra. NO pulsa
    Analizar, NO pulsa nada que elimine, y NO toca ningun archivo del
    usuario.

.PARAMETER Segundos
    Cuanto esperar a que la ventana aparezca.

.PARAMETER DejarAbierta
    No cerrar al terminar, para poder mirarla a mano.

.EXAMPLE
    # PowerShell normal (NO hace falta administrador), en la raiz del repo:
    .\tools\Sondeo-Robot.ps1
#>
[CmdletBinding()]
param(
    [int]    $Segundos = 40,
    [switch] $DejarAbierta
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent

function Write-Paso {
    param([string] $Numero, [string] $Texto, [string] $Estado = '', [string] $Detalle = '')
    $color = switch ($Estado) { 'BIEN' { 'Green' } 'FALLA' { 'Yellow' } default { 'Gray' } }
    Write-Host ('  {0,-3} {1,-46} {2}' -f $Numero, $Texto, $Estado) -ForegroundColor $color
    if ($Detalle) { Write-Host ('       {0}' -f $Detalle) -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host '=== [VAL-05] sondeo: se puede manejar la ventana? ====================' -ForegroundColor Cyan
Write-Host ("  PowerShell {0} · {1}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)
Write-Host ''

# --- 0. .Existe UI Automation en esta maquina? -----------------------
# Va primero porque si esto falla, no hay nada mas que preguntar. Las dos
# bibliotecas vienen con .NET Framework en cualquier Windows de escritorio,
# pero NO en las ediciones sin escritorio (Server Core, contenedores), que
# es justo lo que puede haber detras de un ejecutor de integracion continua.
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes  -ErrorAction Stop
    Write-Paso '0.' 'UI Automation esta disponible' 'BIEN'
} catch {
    Write-Paso '0.' 'UI Automation esta disponible' 'FALLA' $_.Exception.Message
    Write-Host ''
    Write-Host '  Sin esto no hay robot posible. [VAL-05] se descarta aqui mismo.' -ForegroundColor Yellow
    return
}

$proceso = $null
try {
    # --- 1. Arrancar la ventana --------------------------------------
    # Se lanza el guion de entrada, no el .exe: asi el sondeo funciona en
    # un clon recien bajado, sin compilar nada.
    $guion = Join-Path $raiz 'Cachivache.ps1'
    $proceso = Start-Process -FilePath 'powershell.exe' `
                             -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $guion + '"')) `
                             -PassThru
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $ventana = $null
    while ($reloj.Elapsed.TotalSeconds -lt $Segundos) {
        Start-Sleep -Milliseconds 400
        if ($proceso.HasExited) { break }
        # Por identificador de proceso y NO por titulo: si un dia el titulo
        # cambia, o hay otra ventana que se llame igual, buscar por texto
        # encontraria la ventana equivocada y todo lo de abajo mediria otro
        # programa.
        $cond = [Windows.Automation.PropertyCondition]::new(
                    [Windows.Automation.AutomationElement]::ProcessIdProperty, $proceso.Id)
        $ventana = [Windows.Automation.AutomationElement]::RootElement.FindFirst(
                    [Windows.Automation.TreeScope]::Children, $cond)
        if ($null -ne $ventana) { break }
    }
    $reloj.Stop()

    if ($null -eq $ventana) {
        $motivo = if ($proceso.HasExited) { ('el proceso ha terminado con codigo {0}' -f $proceso.ExitCode) }
                  else { ('no ha aparecido en {0:N1} s' -f $reloj.Elapsed.TotalSeconds) }
        Write-Paso '1.' 'La ventana arranca y se localiza' 'FALLA' $motivo
        return
    }
    Write-Paso '1.' 'La ventana arranca y se localiza' 'BIEN' (
        'titulo "{0}", en {1:N1} s' -f $ventana.Current.Name, $reloj.Elapsed.TotalSeconds)

    # --- 2. Enumerar controles por su nombre accesible ---------------
    # Esto es lo que [A11Y-01] hizo posible sin proponerselo.
    $todos = $ventana.FindAll([Windows.Automation.TreeScope]::Descendants,
                              [Windows.Automation.Condition]::TrueCondition)
    $conNombre = @()
    foreach ($e in $todos) {
        $n = $e.Current.Name
        if (-not [string]::IsNullOrWhiteSpace($n)) { $conNombre += $n }
    }
    Write-Paso '2.' 'Se enumeran los controles' 'BIEN' (
        '{0} elementos, {1} con nombre accesible' -f $todos.Count, $conNombre.Count)

    # Los que el robot necesitaria de verdad. Si alguno no aparece, el robot
    # tendria que buscarlo de otra forma y hay que saberlo AHORA.
    $buscados = @('Análisis del equipo', 'Resultados del análisis', 'Ajustes',
                  'Registro de la sesión', 'Informes e historial', 'Acerca de Cachivache')
    $faltan = @($buscados | Where-Object { $conNombre -notcontains $_ })
    if ($faltan.Count -eq 0) {
        Write-Paso '2b.' 'Los seis paneles se encuentran por nombre' 'BIEN'
    } else {
        Write-Paso '2b.' 'Los seis paneles se encuentran por nombre' 'FALLA' ('no aparecen: ' + ($faltan -join ', '))
    }

    # --- 3. Pulsar un boton ------------------------------------------
    # "Ajustes" y luego "Analisis del equipo": cambiar de panel y volver.
    # No borra nada, no analiza nada, y deja la ventana como estaba.
    function Get-PorNombre {
        param([string] $Nombre)
        $c = [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::NameProperty, $Nombre)
        return $ventana.FindFirst([Windows.Automation.TreeScope]::Descendants, $c)
    }

    $ajustes = Get-PorNombre 'Ajustes'
    if ($null -eq $ajustes) {
        Write-Paso '3.' 'Se puede pulsar un boton' 'FALLA' 'no se encuentra "Ajustes"'
    } else {
        try {
            $patron = $ajustes.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
            $patron.Invoke()
            Start-Sleep -Milliseconds 700
            Write-Paso '3.' 'Se puede pulsar un boton' 'BIEN' 'pulsado "Ajustes"'
        } catch {
            Write-Paso '3.' 'Se puede pulsar un boton' 'FALLA' $_.Exception.Message
        }
    }

    # --- 4. Leer lo que la ventana dice despues ----------------------
    # LA MITAD QUE DE VERDAD IMPORTA. Pulsar sin poder comprobar el efecto
    # no sirve de nada: seria un robot que hace clic y se fia.
    $textos = @()
    $despues = $ventana.FindAll([Windows.Automation.TreeScope]::Descendants,
                                [Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $despues) {
        if ($e.Current.ControlType.ProgrammaticName -match 'Text|Edit') {
            $n = $e.Current.Name
            if (-not [string]::IsNullOrWhiteSpace($n)) { $textos += $n }
        }
    }
    if ($textos.Count -gt 0) {
        $muestra = @($textos | Select-Object -First 4) -join ' / '
        Write-Paso '4.' 'Se lee lo que la ventana dice' 'BIEN' (
            '{0} textos. Muestra: {1}' -f $textos.Count, $muestra)
    } else {
        Write-Paso '4.' 'Se lee lo que la ventana dice' 'FALLA' 'no se ha podido leer ni un texto'
    }

    # Volver al panel de inicio: cortesia, no medicion. Si falla no cambia
    # el veredicto del sondeo -ya se ha contestado a las cinco preguntas- y
    # por eso el catch no lanza; pero se dice, porque un catch mudo es
    # exactamente lo que este proyecto persigue en el codigo de otros.
    $volver = Get-PorNombre 'Análisis del equipo'
    if ($null -ne $volver) {
        try {
            $volver.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
        } catch {
            Write-Verbose ('No se ha podido volver al panel de inicio: {0}' -f $_.Exception.Message)
        }
    }

} finally {
    # --- 5. Cerrar sin dejar nada colgado ----------------------------
    if ($null -ne $proceso -and -not $proceso.HasExited) {
        if ($DejarAbierta) {
            Write-Paso '5.' 'La ventana se cierra' '' ('se queda abierta a peticion, PID {0}' -f $proceso.Id)
        } else {
            try {
                $null = $proceso.CloseMainWindow()
                if (-not $proceso.WaitForExit(6000)) { $proceso.Kill() }
                Write-Paso '5.' 'La ventana se cierra' 'BIEN'
            } catch {
                Write-Paso '5.' 'La ventana se cierra' 'FALLA' $_.Exception.Message
            }
        }
    }
}

Write-Host ''
Write-Host '=== Copia esta salida entera en la conversacion ======================' -ForegroundColor Cyan
Write-Host '  Si los cinco pasos dicen BIEN, el robot de [VAL-05] se puede escribir'
Write-Host '  y llevar a la integracion continua. Si alguno falla, se documenta y se'
Write-Host '  descarta, como se hizo con [VEL-01] y [VEL-02].'
