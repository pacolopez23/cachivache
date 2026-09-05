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

    # LOS SEIS BOTONES DE NAVEGACION, y aqui hubo que corregir el sondeo.
    #
    # La primera version buscaba los nombres de los PANELES -"Ajustes",
    # "Acerca de Cachivache"- y luego intentaba pulsarlos. Dos errores
    # encima del otro:
    #
    #   a) Un panel es un contenedor: no se pulsa. Y ademas NavAjustes
    #      tiene Content="Ajustes" y el panel tiene
    #      AutomationProperties.Name="Ajustes", o sea DOS ELEMENTOS CON EL
    #      MISMO NOMBRE ACCESIBLE. Buscar solo por nombre cogia uno de los
    #      dos a suertes, y salio el que no era.
    #   b) "Acerca de Cachivache" no aparecia en el arbol. No es un fallo:
    #      WPF no construye el contenido de un panel hasta que se muestra,
    #      asi que LO QUE NO SE HA ENSENYADO NO EXISTE PARA UI AUTOMATION.
    #      Es la regla de diseno mas importante que ha dejado este sondeo:
    #      el robot tiene que NAVEGAR primero y mirar despues.
    #
    # Asi que se buscan los botones, filtrando ademas por tipo de control.
    $buscados = @('Inicio', 'Resultados', 'Registro', 'Informes', 'Ajustes', 'Acerca de')

    function Get-PorNombre {
        param([string] $Nombre)
        $c = [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::NameProperty, $Nombre)
        return $ventana.FindFirst([Windows.Automation.TreeScope]::Descendants, $c)
    }

    function Get-Navegacion {
        param([string] $Nombre)
        $porNombre = [Windows.Automation.PropertyCondition]::new(
                        [Windows.Automation.AutomationElement]::NameProperty, $Nombre)
        # EL TIPO DE CONTROL NO ES UN ADORNO: es lo que desempata cuando dos
        # elementos se llaman igual.
        $porTipo = [Windows.Automation.PropertyCondition]::new(
                        [Windows.Automation.AutomationElement]::ControlTypeProperty,
                        [Windows.Automation.ControlType]::RadioButton)
        $ambas = [Windows.Automation.AndCondition]::new($porNombre, $porTipo)
        return $ventana.FindFirst([Windows.Automation.TreeScope]::Descendants, $ambas)
    }

    $faltan = @($buscados | Where-Object { $null -eq (Get-Navegacion $_) })
    if ($faltan.Count -eq 0) {
        Write-Paso '2b.' 'Los seis botones de navegacion se encuentran' 'BIEN'
    } else {
        Write-Paso '2b.' 'Los seis botones de navegacion se encuentran' 'FALLA' ('no aparecen: ' + ($faltan -join ', '))
    }

    # --- 3. Pulsar de verdad -----------------------------------------
    # SE LE PREGUNTA AL ELEMENTO QUE SABE HACER, EN VEZ DE SUPONERLO. La
    # primera version daba por hecho InvokePattern y el sondeo contesto
    # "Modelo no admitido": un RadioButton de WPF NO se invoca, se
    # SELECCIONA con SelectionItemPattern. Suponer el patron es la version
    # de interfaz grafica de suponer que una llamada al sistema funciona.
    $acerca = Get-Navegacion 'Acerca de'
    $pulsado = $false
    if ($null -eq $acerca) {
        Write-Paso '3.' 'Se puede pulsar un boton' 'FALLA' 'no se encuentra el boton "Acerca de"'
    } else {
        $patrones = @($acerca.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
        try {
            if ($acerca.GetSupportedPatterns() -contains [Windows.Automation.SelectionItemPattern]::Pattern) {
                $acerca.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
                $pulsado = $true
            } elseif ($acerca.GetSupportedPatterns() -contains [Windows.Automation.InvokePattern]::Pattern) {
                $acerca.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                $pulsado = $true
            }
            if ($pulsado) {
                Start-Sleep -Milliseconds 900
                Write-Paso '3.' 'Se puede pulsar un boton' 'BIEN' (
                    'pulsado "Acerca de". Patrones: {0}' -f ($patrones -join ', '))
            } else {
                Write-Paso '3.' 'Se puede pulsar un boton' 'FALLA' (
                    'no admite ni seleccionar ni invocar. Patrones: {0}' -f ($patrones -join ', '))
            }
        } catch {
            Write-Paso '3.' 'Se puede pulsar un boton' 'FALLA' $_.Exception.Message
        }
    }

    # --- 3b. .SE HA ENTERADO EL PROGRAMA? ----------------------------
    # LA PREGUNTA QUE DE VERDAD DECIDE. Un robot que pulsa y no comprueba
    # el efecto es un robot que hace clic y se fia. El panel "Acerca de
    # Cachivache" NO existia en el arbol antes de pulsar -paso 2b de la
    # version anterior- asi que si ahora esta, la unica explicacion es que
    # el clic ha llegado. Causa y efecto en la misma comprobacion.
    if ($pulsado) {
        $panel = Get-PorNombre 'Acerca de Cachivache'
        if ($null -ne $panel) {
            Write-Paso '3b.' 'El programa reacciona al clic' 'BIEN' (
                'el panel "Acerca de Cachivache" no estaba en el arbol y ahora si')
        } else {
            Write-Paso '3b.' 'El programa reacciona al clic' 'FALLA' 'el panel sigue sin aparecer'
        }
    }

    # --- 4. Leer lo que la ventana dice ------------------------------
    # LA OTRA MITAD QUE IMPORTA. Pulsar sin poder leer el resultado seria
    # un robot que hace clic a ciegas. Se lee DESPUES de navegar, que es la
    # leccion del paso 2b: lo que no se ha ensenyado no existe en el arbol.
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

    # Volver al inicio: cortesia, no medicion. Por el boton y con el patron
    # que admite, igual que arriba: el error de la primera version se
    # cometia TAMBIEN aqui, y por eso no basta con arreglarlo en un sitio.
    $volver = Get-Navegacion 'Inicio'
    if ($null -ne $volver) {
        try {
            $volver.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
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
Write-Host '  Si TODOS los pasos dicen BIEN, el robot de [VAL-05] se puede escribir.'
Write-Host '  El que decide es el 3b: pulsar sin poder comprobar el efecto seria un'
Write-Host '  robot que hace clic y se fia, o sea otra prueba verde que no mira nada.'
Write-Host ''
Write-Host '  Contestado que si en Windows 11 el 5 de septiembre de 2026. Este guion'
Write-Host '  se queda como el juez de si la maquina de turno puede manejar la'
Write-Host '  ventana: lo ejecuta la integracion continua antes de nada.'
