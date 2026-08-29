<#
.SYNOPSIS
    Comunicación de progreso y cancelación entre el hilo de trabajo y la
    interfaz.

.DESCRIPTION
    Las dos funciones más usadas del programa: TODOS los módulos de
    limpieza las llaman, sin excepción. No tocan el disco ni miden nada;
    solo leen y escriben la tabla sincronizada que comparten el runspace
    de análisis y el hilo de la ventana.

    Vivian en FileSystem.ps1, cuyo docblock habla de "medición de tamaños
    y recorrido de carpetas" y no las mencionaba: estaban escondidas bajo
    una etiqueta que no las describia. Ver docs/ESTRUCTURA.md (sección 5.4).

    El contrato es deliberadamente tolerante con $Sync nulo: en modo
    consola no hay ninguna tabla que sincronizar y las dos funciones se
    llaman igual, sin que el módulo tenga que preguntar en que modo esta.
#>

function Test-Cancelacion {
    <#
    .SYNOPSIS
        Indica si la interfaz ha pedido abortar el análisis en curso.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param($Sync)

    if ($null -eq $Sync) { return $false }
    return [bool]$Sync.Cancelar
}

function Set-Progreso {
    <#
    .SYNOPSIS
        Pública el mensaje que la interfaz muestra bajo la barra de progreso.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Escribe un mensaje en una tabla en memoria para la interfaz.')]
    [CmdletBinding()]
    param(
        $Sync,
        [string] $Mensaje
    )
    if ($null -ne $Sync) { $Sync.Mensaje = $Mensaje }
}
