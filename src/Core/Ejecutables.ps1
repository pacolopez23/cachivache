<#
.SYNOPSIS
    Resolución y comprobación de ejecutables, entradas de arranque y
    accesos directos.

.DESCRIPTION
    Todo lo de este archivo es de SOLO LECTURA. El programa no escribe
    jamas en el registro.

    Solo Get-EstadoArranque toca el registro de verdad; las otras tres son
    parseo de texto, comprobación de rutas y COM sobre un .lnk. Vivian en
    Registry.ps1 junto al vocabulario de programas instalados, pero son
    dos grupos con consumidores completamente distintos: este lo usan
    90-Arranque y 45-AccesosRotos; aquel, solo 30-RestosProgramas. Ver
    docs/ESTRUCTURA.md (sección 5.3).
#>

function Get-EjecutableDeComando {
    <#
    .SYNOPSIS
        Extrae la ruta del ejecutable de una línea de comandos.

    .DESCRIPTION
        Tres estrategias, en este orden:
          1. Ruta entre comillas -> se toma tal cual.
          2. Todo hasta el primer ".exe" de forma no avida, lo que permite
             rutas con espacios sin comillas ("C:\Program Files\...").
          3. Sin extensión: se corta en el primer argumento con - o /.
        Siempre se expanden las variables de entorno.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Comando)

    if ([string]::IsNullOrWhiteSpace($Comando)) { return '' }
    $c = $Comando.Trim()

    # Sintaxis NT que usan los servicios y controladores: "\??\C:\..." es
    # el prefijo del subsistema de objetos de NT (no es una ruta Win32
    # válida) y "\SystemRoot\..." es una raiz simbolica hacia %SystemRoot%.
    # Sin normalizarlas, Test-EjecutableExiste no las encuentra nunca y se
    # generaban falsos "servicio roto". Ver [C-16] en docs/OPTIMIZACIONES.md.
    if ($c.StartsWith('\??\', [StringComparison]::Ordinal)) {
        $c = $c.Substring(4)
    } elseif ($c.StartsWith('\SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) {
        # Concatenacion de texto, no Join-Path: Join-Path intenta resolver
        # la unidad a traves del proveedor de PowerShell, lo que falla si
        # "C:" no existe como unidad real en el proceso que evalua esto
        # (por ejemplo, en las pruebas de esta suite corriendo en Linux).
        $c = $env:SystemRoot.TrimEnd('\') + '\' + $c.Substring(12)
    }

    if ($c -match '^"([^"]+)"') {
        return [Environment]::ExpandEnvironmentVariables($Matches[1])
    }
    if ($c -match '^(.+?\.exe)') {
        return [Environment]::ExpandEnvironmentVariables($Matches[1])
    }
    $recortado = ($c -split '\s+[-/]')[0]
    return [Environment]::ExpandEnvironmentVariables($recortado.Trim())
}

function Test-EjecutableExiste {
    <#
    .SYNOPSIS
        Comprueba de tres maneras si un ejecutable existe de verdad.
    .DESCRIPTION
        Muchos servicios se registran sin la extensión .exe y otros se
        resuelven por PATH. Declarar algo "roto" sin comprobar las tres
        cosas produce falsos positivos peligrosos.

        La busqueda por PATH se limita a -CommandType Application, es decir,
        a programas de verdad. Sin ese filtro, Get-Command también resuelve
        alias, funciones y cmdlets de PowerShell, de modo que una entrada de
        arranque llamada "where", "set", "sc" o "start" se daba por existente
        solo porque coincide con un alias de la consola, y una entrada rota
        de verdad pasaba desapercibida. Ver [C-17] en docs/OPTIMIZACIONES.md.

        Ante la duda se responde SIEMPRE que existe: quien consume esto es
        el módulo de arranque, y equivocarse hacia "roto" sería acusar de
        rota una entrada legitima.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Ejecutable)

    # -PathType Leaf: sin el, Test-Path responde $true tambien para una
    # CARPETA, así que una entrada de arranque que apunta a un directorio
    # -porque el programa se desinstalo y dejo la carpeta, o porque la
    # entrada esta mal escrita- se daba por sana y nunca se señalaba.
    # Ver [SEG-60] en docs/PLAN-ACCION.md.
    if ([string]::IsNullOrWhiteSpace($Ejecutable)) { return $true }
    if (Test-Path -LiteralPath $Ejecutable -PathType Leaf -ErrorAction SilentlyContinue)       { return $true }
    if (Test-Path -LiteralPath "$Ejecutable.exe" -PathType Leaf -ErrorAction SilentlyContinue) { return $true }

    # Solo tiene sentido buscar por PATH si lo que nos han dado es un nombre
    # suelto. Una ruta que ya trae carpeta y no existe en disco esta rota, y
    # preguntarle al PATH por ella solo puede dar un falso positivo.
    if ($Ejecutable -notmatch '[\\/]') {
        if (Get-Command $Ejecutable -CommandType Application -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

function Get-EstadoArranque {
    <#
    .SYNOPSIS
        Lee si una entrada de arranque esta activada según el Administrador
        de tareas.
    .DESCRIPTION
        Windows guarda el estado en StartupApproved como un byte[]: el bit 0
        del primer byte a cero significa activado.
    #>
    [CmdletBinding()]
    param()

    $resultado = @{}
    $claves = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    )

    foreach ($clave in $claves) {
        $valores = Get-ItemProperty -Path $clave -ErrorAction SilentlyContinue
        if ($null -eq $valores) { continue }
        $valores.PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' -and $_.Value -is [byte[]] } |
            ForEach-Object {
                $bytes = [byte[]]$_.Value
                if ($bytes.Length -gt 0) {
                    $resultado[$_.Name] = (($bytes[0] -band 1) -eq 0)
                }
            }
    }
    return $resultado
}

function Get-DestinoAccesoDirecto {
    <#
    .SYNOPSIS
        Resuelve el destino de un archivo .lnk.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        $Shell = $null
    )

    try {
        if ($null -eq $Shell) { $Shell = New-Object -ComObject WScript.Shell }
        return $Shell.CreateShortcut($Ruta).TargetPath
    } catch {
        return ''
    }
}
