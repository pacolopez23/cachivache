<#
.SYNOPSIS
    Ejecuta TODO lo que se puede comprobar sin abrir la ventana, de una
    sola pasada, y deja el informe en un archivo.

.DESCRIPTION
    Hasta ahora esto era un bloque de PowerShell que habia que pegar a
    mano desde docs/RELEVO.md. Un ritual copiado a mano es exactamente el
    tipo de cosa que se rompe en silencio: basta con que alguien olvide la
    segunda mitad para que el analizador deje de mirarse durante semanas y
    nadie se entere.

    QUE HACE, EN ORDEN Y CON MOTIVO:

      1. La suite de Pester entera.
      2. PSScriptAnalyzer con la configuracion del proyecto.
      3. El suelo de cobertura (tools/Cobertura.ps1), salvo con -Rapido.
      4. Escribe el informe en pruebas/ y dice donde.

    El orden importa: si las pruebas fallan, lo demas se ejecuta igual
    -interesa el cuadro completo, no el primer sintoma- pero el veredicto
    final es uno solo, y el codigo de salida tambien: 0 si todo esta bien,
    1 si algo no lo esta. Asi esto sirve tal cual en la integracion
    continua y en un gancho de git.

    LO QUE ESTE GUION NO HACE, Y ES DELIBERADO
    ------------------------------------------
    NO regenera el oraculo del XAML. Hay una prueba que compara el XAML
    montado byte a byte con tests/datos/MainWindow.montado.esperado.xaml, y
    un guion que lo regenerara antes de comparar haria que esa prueba
    pasara SIEMPRE: estaria comparando el archivo consigo mismo. Cuando esa
    prueba falla, aqui se imprime el comando para regenerarlo y se deja la
    decision en manos de quien mira.

    Y NO ejecuta la interfaz. No hay WPF en ningun sitio donde esto se
    pueda automatizar; src/UI se queda al 5 % y su parte la cubren
    docs/PRUEBA-MANUAL.md, la integracion continua en Windows y el banco de
    docs/BANCO-PRUEBAS.md. Este guion lo dice al final para que nadie
    confunda "todo verde" con "probado".

.PARAMETER Ruta
    Que probar. Por defecto la carpeta tests entera; se le puede dar un
    archivo suelto mientras se trabaja en un punto.

.PARAMETER Rapido
    Sin cobertura. La medicion multiplica por tres o cuatro lo que tarda
    la suite, asi que mientras se itera sobre un punto no compensa.

.PARAMETER SinRegistro
    No escribe el informe en disco. Para cuando esto se llama desde otro
    guion que ya se encarga de guardar la salida.

.EXAMPLE
    .\tools\Probar.ps1
    Todo, con cobertura, e informe en pruebas\.

.EXAMPLE
    .\tools\Probar.ps1 -Rapido
    Suite y analizador, sin medir cobertura.

.EXAMPLE
    .\tools\Probar.ps1 -Ruta tests\Cli.Tests.ps1 -Rapido
    Solo un archivo, mientras se trabaja en el.
#>
[CmdletBinding()]
param(
    [string] $Ruta = 'tests',
    [switch] $Rapido,
    [switch] $SinRegistro
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Cobertura.ps1')

# Todo lo que se escriba pasa por aqui: sale por pantalla Y se guarda. Dos
# caminos distintos para lo mismo acabarian contando cosas distintas, que
# es el error de [ARQ-01] aplicado a un guion de pruebas.
$lineas = [Collections.Generic.List[string]]::new()
function Write-Informe {
    param([string] $Texto = '', [string] $Color = '')
    $lineas.Add($Texto)
    if ($Color) { Write-Host $Texto -ForegroundColor $Color } else { Write-Host $Texto }
}

function Test-ModuloDisponible {
    param([string] $Nombre, [string] $VersionMinima = '0.0')
    $m = @(Get-Module -ListAvailable -Name $Nombre |
           Where-Object { $_.Version -ge [version]$VersionMinima })
    return $m.Count -gt 0
}

$faltan = @()
if (-not (Test-ModuloDisponible -Nombre 'Pester' -VersionMinima '5.0')) { $faltan += 'Pester (5.0 o mas)' }
if (-not (Test-ModuloDisponible -Nombre 'PSScriptAnalyzer'))            { $faltan += 'PSScriptAnalyzer' }
if ($faltan.Count -gt 0) {
    Write-Host ''
    Write-Host ('  Falta por instalar: {0}' -f ($faltan -join ', ')) -ForegroundColor Red
    Write-Host '  Instalalos con:' -ForegroundColor DarkGray
    Write-Host '    Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck'
    Write-Host '    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force'
    Write-Host ''
    exit 1
}

Push-Location $raiz
try {
    Import-Module Pester -MinimumVersion 5.0
    Import-Module PSScriptAnalyzer

    $arranque = Get-Date
    Write-Informe ''
    Write-Informe ('  Cachivache - pasada completa   {0}' -f $arranque.ToString('yyyy-MM-dd HH:mm:ss')) 'Cyan'
    Write-Informe ('  PowerShell {0} sobre {1}' -f $PSVersionTable.PSVersion,
                   $(if ($IsLinux) { 'Linux' } elseif ($IsMacOS) { 'macOS' } else { 'Windows' })) 'DarkGray'
    Write-Informe ''

    # ---------------------------------------------------------------
    #  1. La suite
    # ---------------------------------------------------------------
    $conf = New-PesterConfiguration
    $conf.Run.Path         = $Ruta
    $conf.Run.PassThru     = $true
    $conf.Output.Verbosity = 'None'
    if (-not $Rapido) {
        $conf.CodeCoverage.Enabled = $true
        $conf.CodeCoverage.Path    = @('src')
    }

    # 6>&1 y 3>&1: varias pruebas ejercitan de verdad codigo que escribe
    # con Write-Host y Write-Warning. Sin recogerlo, esa salida se mezcla
    # con el informe y lo vuelve ilegible.
    $resultado = Invoke-Pester -Configuration $conf 6>$null 3>$null

    # CERO PRUEBAS NO ES UN EXITO. Es el sintoma de una ruta mal escrita, y
    # sin esta guarda se ve exactamente igual que una suite impecable:
    # "TODO EN VERDE" con los contadores vacios. Paso la primera vez que se
    # ejecuto este guion, apuntando a un archivo que aun no existia.
    if ($null -eq $resultado -or $resultado.TotalCount -eq 0) {
        Write-Informe ''
        Write-Informe ("  NO SE HA EJECUTADO NI UNA PRUEBA con -Ruta '{0}'." -f $Ruta) 'Red'
        Write-Informe '  Cero pruebas no es una suite en verde: es una ruta que no existe.' 'Red'
        Write-Host ''
        exit 1
    }

    # UN ARCHIVO QUE NO LLEGA A CARGARSE NO CUENTA COMO PRUEBA FALLIDA.
    #
    # Si un .Tests.ps1 revienta en el descubrimiento -un error de sintaxis,
    # un BeforeAll que lanza, un dot-source a un archivo que no existe-,
    # Pester lo apunta como CONTENEDOR roto y FailedCount sigue a cero. O
    # sea: la suite entera de ese archivo desaparece y esto imprimia "TODO
    # EN VERDE" con los contadores de los demas. Es el mismo error de
    # siempre —"no he medido nada" pareciendose a "todo bien"— y aparecio
    # justo aqui, en el guion escrito para no fiarse.
    $contenedoresRotos = [int] $resultado.FailedContainersCount
    if ($contenedoresRotos -gt 0) {
        Write-Informe ''
        Write-Informe ('  {0} archivo(s) de pruebas NO SE HAN PODIDO EJECUTAR.' -f $contenedoresRotos) 'Red'
        foreach ($c in $resultado.Containers) {
            if (-not $c.Passed) {
                Write-Informe ('    x {0}' -f $c.Item) 'Red'
                foreach ($e in @($c.ErrorRecord)) {
                    if ($e) { Write-Informe ('        {0}' -f $e.Exception.Message) 'DarkGray' }
                }
            }
        }
    }

    $fallaronPruebas = $resultado.FailedCount -gt 0 -or $contenedoresRotos -gt 0
    Write-Informe ('  PRUEBAS      {0} en total, {1} bien, {2} mal' -f `
                   $resultado.TotalCount, $resultado.PassedCount, $resultado.FailedCount) `
                  $(if ($fallaronPruebas) { 'Red' } else { 'Green' })

    if ($fallaronPruebas) {
        Write-Informe ''
        foreach ($f in $resultado.Failed) {
            Write-Informe ('    x {0}' -f $f.ExpandedPath) 'Red'
            $mensaje = @(($f.ErrorRecord.Exception.Message -split "`r?`n") | Select-Object -First 4)
            foreach ($m in $mensaje) { Write-Informe ('        {0}' -f $m) 'DarkGray' }
        }

        # El aviso del oraculo. Va aqui y no siempre: puesto en cada
        # pasada seria ruido, y un consejo que sale siempre no se lee.
        $sonaOraculo = @($resultado.Failed | Where-Object {
            $_.ExpandedPath -match 'oraculo|montad|xaml' }).Count -gt 0
        if ($sonaOraculo) {
            Write-Informe ''
            Write-Informe '  Parece el oraculo del XAML. Si el cambio en src/UI/*.xaml es intencionado, regeneralo:' 'Yellow'
            Write-Informe '    . ./src/UI/Xaml.ps1'
            Write-Informe '    $ui = Join-Path (Get-Location) "src/UI"'
            Write-Informe '    $m = Expand-PanelesXaml -Texto ([IO.File]::ReadAllText((Join-Path $ui "MainWindow.xaml"))) -Carpeta $ui'
            Write-Informe '    [IO.File]::WriteAllText("tests/datos/MainWindow.montado.esperado.xaml", $m, [Text.UTF8Encoding]::new($true))'
            Write-Informe '  Este guion NO lo regenera solo: comparar un archivo consigo mismo pasa siempre.' 'DarkGray'
        }
    }

    # ---------------------------------------------------------------
    #  2. El analizador
    # ---------------------------------------------------------------
    $avisos = @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
    $fallaronAvisos = $avisos.Count -gt 0
    Write-Informe ('  ANALIZADOR   {0} avisos' -f $avisos.Count) `
                  $(if ($fallaronAvisos) { 'Red' } else { 'Green' })
    foreach ($a in $avisos) {
        Write-Informe ('    x {0}:{1}  {2}' -f (Split-Path $a.ScriptName -Leaf), $a.Line, $a.RuleName) 'Red'
    }

    # ---------------------------------------------------------------
    #  3. La cobertura y su suelo
    # ---------------------------------------------------------------
    $fallaronSuelos = $false
    if ($Rapido) {
        Write-Informe '  COBERTURA    sin medir (-Rapido)' 'DarkGray'
    } else {
        $medido = @{}
        $porCarpeta = @{}
        foreach ($x in $resultado.CodeCoverage.CommandsMissed) {
            $k = Split-Path (Split-Path $x.File -Parent) -Leaf
            if (-not $porCarpeta.ContainsKey($k)) { $porCarpeta[$k] = @{ Mal = 0; Bien = 0 } }
            $porCarpeta[$k].Mal++
        }
        foreach ($x in $resultado.CodeCoverage.CommandsExecuted) {
            $k = Split-Path (Split-Path $x.File -Parent) -Leaf
            if (-not $porCarpeta.ContainsKey($k)) { $porCarpeta[$k] = @{ Mal = 0; Bien = 0 } }
            $porCarpeta[$k].Bien++
        }
        foreach ($k in $porCarpeta.Keys) {
            $total = $porCarpeta[$k].Bien + $porCarpeta[$k].Mal
            if ($total -gt 0) { $medido[$k] = 100.0 * $porCarpeta[$k].Bien / $total }
        }
        $medido['total'] = [double] $resultado.CodeCoverage.CoveragePercent

        Write-Informe ('  COBERTURA    {0:N1}% del programa se ha llegado a ejecutar' -f $medido['total'])
        foreach ($k in ($medido.Keys | Where-Object { $_ -ne 'total' } | Sort-Object)) {
            $sinEjecutar = if ($porCarpeta.ContainsKey($k)) { $porCarpeta[$k].Mal } else { 0 }
            Write-Informe ('      src/{0,-10} {1,6:N1}%   {2} instrucciones sin ejecutar' -f `
                           $k, $medido[$k], $sinEjecutar) 'DarkGray'
        }

        $motivos = @(Test-CoberturaSuficiente -Medido $medido)
        $fallaronSuelos = $motivos.Count -gt 0
        if ($fallaronSuelos) {
            Write-Informe ''
            foreach ($m in $motivos) { Write-Informe ('    x SUELO  {0}' -f $m) 'Red' }
        }
    }

    # ---------------------------------------------------------------
    #  4. Veredicto
    # ---------------------------------------------------------------
    $todoBien = -not ($fallaronPruebas -or $fallaronAvisos -or $fallaronSuelos)
    Write-Informe ''
    Write-Informe ('  {0}   ({1:N0} s)' -f `
                   $(if ($todoBien) { 'TODO EN VERDE' } else { 'HAY ALGO QUE MIRAR' }),
                   ((Get-Date) - $arranque).TotalSeconds) `
                  $(if ($todoBien) { 'Green' } else { 'Red' })

    # Esta linea sale SIEMPRE, y sobre todo cuando todo esta en verde. Es
    # lo unico que impide leer "todo en verde" como "el programa esta
    # probado": la mitad de la interfaz no la ha ejecutado nadie aqui.
    Write-Informe ''
    Write-Informe '  Esto NO cubre la ventana: no hay WPF donde esto se ejecuta. Para eso estan' 'DarkGray'
    Write-Informe '  docs/PRUEBA-MANUAL.md, la pestaña Actions y docs/BANCO-PRUEBAS.md.' 'DarkGray'

    # ---------------------------------------------------------------
    #  El informe en disco
    # ---------------------------------------------------------------
    if (-not $SinRegistro) {
        $carpeta = Join-Path $raiz 'pruebas'
        if (-not (Test-Path -LiteralPath $carpeta)) {
            [void](New-Item -ItemType Directory -Path $carpeta -Force)
        }
        $archivo = Join-Path $carpeta ('{0}-{1}.txt' -f `
                    $arranque.ToString('yyyy-MM-dd-HHmmss'),
                    $(if ($todoBien) { 'verde' } else { 'rojo' }))
        [IO.File]::WriteAllLines($archivo, $lineas)

        # Un archivo con nombre fijo, ademas del fechado: asi se puede
        # tener abierto siempre el mismo y recargarlo, sin buscar cual es
        # el ultimo.
        [IO.File]::WriteAllLines((Join-Path $carpeta 'ultima-pasada.txt'), $lineas)

        # Solo se conservan las veinte ultimas. Un historial infinito de
        # informes de pruebas no lo lee nadie y acaba pesando mas que el
        # programa.
        $viejas = @(Get-ChildItem -LiteralPath $carpeta -Filter '*-*.txt' -File |
                    Sort-Object Name -Descending | Select-Object -Skip 20)
        foreach ($v in $viejas) { Remove-Item -LiteralPath $v.FullName -Force -ErrorAction SilentlyContinue }

        Write-Host ''
        Write-Host ('  Informe: {0}' -f $archivo) -ForegroundColor DarkGray
    }
    Write-Host ''

    if (-not $todoBien) { exit 1 }
    exit 0
} finally {
    Pop-Location
}
