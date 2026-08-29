<#
    Configuracion de PSScriptAnalyzer.

    Las reglas excluidas lo estan por un motivo concreto, no por comodidad.
    Si alguna deja de tener sentido, lo suyo es quitarla de aqui y arreglar
    el codigo.
#>
@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # El programa esta escrito en castellano. En castellano el plural es
        # gramaticalmente correcto: Get-UnidadesFijas devuelve varias
        # unidades. La regla asume convenciones del ingles.
        'PSUseSingularNouns'

        # Todos los modulos reciben ($Configuracion, $Sync) porque ese es el
        # contrato del registro de modulos. Que un modulo concreto no use
        # uno de los dos no es un error: es uniformidad.
        'PSReviewUnusedParameter'

        # El modo consola es una interfaz de usuario: Write-Host es la
        # herramienta correcta para escribir con color en la terminal.
        'PSAvoidUsingWriteHost'

        # Los cuatro archivos src/UI/Window.*.ps1 no son scripts sueltos:
        # son trozos del cuerpo de Show-VentanaPrincipal, que los
        # dot-sourcea desde dentro de si misma para que compartan su
        # ambito. Un cierre que se define en Window.Ayudantes.ps1 se
        # consume en Window.Eventos.ps1, y el analizador, que mira cada
        # archivo por separado, no puede verlo: los da por "asignados y
        # nunca usados". Ver docs/ESTRUCTURA.md (seccion 3).
        'PSUseDeclaredVarsMoreThanAssignments'
    )

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
    }
}
