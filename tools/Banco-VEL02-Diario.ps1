<#
.SYNOPSIS
    Banco de [VEL-02], segunda mitad: ¿se puede leer el diario de cambios
    de NTFS desde PowerShell, cuánto tarda, y qué sale de él?

.DESCRIPTION
    SOLO SE PUEDE EJECUTAR EN WINDOWS, Y COMO ADMINISTRADOR. Abrir un
    volumen en crudo (\\.\C:) sin elevación falla con acceso denegado, y
    ese es el primer dato que este banco confirma o desmiente.

    Este guion no cambia nada del programa. Mide, en este orden, las cuatro
    cosas que la implementación da por supuestas y que NADIE HA VISTO
    FUNCIONAR:

      1. CONSULTAR el diario (Get-DatosDiarioUsn): ¿responde? ¿cuál es su
         identificador y qué rango de USN conserva?

      2. LEER el diario (Read-DiarioUsn) desde un punto reciente: ¿cuántos
         registros llegan, cuánto tarda, cuántos bytes son?

      3. PARSEAR lo leído (Get-RegistrosUsn): ¿cuántos registros se
         entienden y cuántos se tiran? Un 0 % de rechazos es sospechoso
         de que no se lee nada; un 50 % dice que el layout está mal.

      4. CLASIFICAR (Get-CambioDesdeRazonUsn): de lo leído, cuántas altas,
         bajas y cambios, y CUÁNTAS CARPETAS PADRE DISTINTAS aparecen.
         Ese último número es el que decide el diseño de lo que falta:
         resolver la referencia de una carpeta a su ruta. Ver el documento.

    Lo que NO mide, porque no existe todavía: la resolución de referencia
    a ruta. Sin ella, ConvertTo-CambiosIndice descarta todo. Está escrito
    en docs/VEL-02-MEDICION.md como la pieza pendiente.

    -------------------------------------------------------------------
    QUÉ TOCA ESTE GUION: NADA. Solo lee. No crea archivos, no escribe en
    el diario, no modifica el índice. Se puede ejecutar sobre el disco del
    sistema sin ningún riesgo.

.PARAMETER Unidad
    La letra, sin barra: 'C:'.

.PARAMETER MinutosAtras
    Desde cuándo leer. El diario no lleva fechas en la consulta, así que se
    lee todo lo que conserva y se filtra por la marca de cada registro.
    Con 60 minutos en un equipo en uso salen unos miles de registros.

.EXAMPLE
    # Desde un PowerShell COMO ADMINISTRADOR, en la raíz del repositorio:
    .\tools\Banco-VEL02-Diario.ps1 -Unidad C:
#>
[CmdletBinding()]
param(
    [string] $Unidad = 'C:',
    [int] $MinutosAtras = 60
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Bootstrap.ps1')

function Write-Titulo([string] $Texto) {
    Write-Host ''
    Write-Host ('=== ' + $Texto + ' ' + ('=' * [Math]::Max(0, 66 - $Texto.Length))) -ForegroundColor Cyan
}
function Format-Seg([double] $s) { '{0:N3} s' -f $s }

Write-Titulo 'VEL-02 · el diario de cambios de NTFS'
$letra = $Unidad.Trim().TrimEnd('\', '/')
$esAdmin = Test-EsAdministrador
$info = try { [IO.DriveInfo]::new($letra + '\') } catch { $null }
$formato = if ($info) { $info.DriveFormat } else { '' }
$tipo    = if ($info) { [string]$info.DriveType } else { '' }
Write-Host ("  unidad {0}   formato {1}   tipo {2}   administrador {3}" -f $letra, $formato, $tipo, $esAdmin)

# ---- 1. consultar -----------------------------------------------------
Write-Titulo '1 · Consultar el diario'
$cron = [Diagnostics.Stopwatch]::StartNew()
$datos = Get-DatosDiarioUsn -Unidad $letra
$cron.Stop()
$motivo = Test-PuedeLeerDiarioUsn -SistemaArchivos $formato -TipoUnidad $tipo -EsAdministrador $esAdmin -DiarioActivo ($null -ne $datos)
if ($null -eq $datos) {
    Write-Host ("  NO RESPONDE ({0})." -f (Format-Seg $cron.Elapsed.TotalSeconds)) -ForegroundColor Yellow
    Write-Host ("  Motivo que daría el programa: {0}" -f $motivo) -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Si eres administrador y sale esto, el fallo está en Get-DatosDiarioUsn y hay que mirarlo con -Verbose:' -ForegroundColor Yellow
    Write-Host '    $VerbosePreference = ''Continue''; Get-DatosDiarioUsn -Unidad C:' -ForegroundColor DarkGray
    return
}
Write-Host ("  responde en {0}" -f (Format-Seg $cron.Elapsed.TotalSeconds)) -ForegroundColor Green
Write-Host ("  IdDiario     {0}" -f $datos.IdDiario)
Write-Host ("  PrimerUsn    {0:N0}" -f $datos.PrimerUsn)
Write-Host ("  UsnSiguiente {0:N0}" -f $datos.UsnSiguiente)
Write-Host ("  conserva     {0:N0} bytes de diario" -f ($datos.UsnSiguiente - $datos.PrimerUsn))
if ($motivo) { Write-Host ("  OJO, el programa diría que no: {0}" -f $motivo) -ForegroundColor Yellow }

# ---- 2. leer ----------------------------------------------------------
Write-Titulo '2 · Leer el diario entero que conserva'
$cron = [Diagnostics.Stopwatch]::StartNew()
$lectura = Read-DiarioUsn -Unidad $letra -IdDiario $datos.IdDiario -Desde $datos.PrimerUsn -MaximoBytes 256MB
$cron.Stop()
if ($null -eq $lectura) {
    Write-Host ("  NO SE HA PODIDO LEER ({0}). Con -Verbose sale el código Win32." -f (Format-Seg $cron.Elapsed.TotalSeconds)) -ForegroundColor Yellow
    return
}
$registros = @($lectura.Registros)
Write-Host ("  {0:N0} registros en {1}   ({2:N1} MB leídos, {3:N0} registros/s)" -f
    $registros.Count, (Format-Seg $cron.Elapsed.TotalSeconds), ($lectura.BytesLeidos / 1MB),
    ($(if ($cron.Elapsed.TotalSeconds -gt 0) { $registros.Count / $cron.Elapsed.TotalSeconds } else { 0 }))) -ForegroundColor Green

# ---- 3. calidad del parseo --------------------------------------------
Write-Titulo '3 · Lo que se entiende de lo leído'
$conMarca = @($registros | Where-Object { $null -ne $_.Marca })
$carpetas = @($registros | Where-Object { $_.EsCarpeta })
$sinNombre = @($registros | Where-Object { [string]::IsNullOrEmpty($_.Nombre) })
Write-Host ("  con fecha legible  {0:N0} / {1:N0}" -f $conMarca.Count, $registros.Count)
Write-Host ("  carpetas           {0:N0}" -f $carpetas.Count)
Write-Host ("  sin nombre         {0:N0}   (debería ser ~0; si no, el nombre se lee mal)" -f $sinNombre.Count)
if ($conMarca.Count -gt 0) {
    $primero = ($conMarca | Sort-Object { $_.Marca } | Select-Object -First 1).Marca
    $ultimo  = ($conMarca | Sort-Object { $_.Marca } | Select-Object -Last 1).Marca
    Write-Host ("  abarca de {0:u} a {1:u}" -f $primero, $ultimo)
}
Write-Host '  cinco registros al azar, para verlos con los ojos:'
$registros | Get-Random -Count ([Math]::Min(5, $registros.Count)) | ForEach-Object {
    Write-Host ("    {0:u}  razón 0x{1:X8}  {2}{3}" -f $_.Marca, $_.Razon, $(if ($_.EsCarpeta) { '[carpeta] ' } else { '' }), $_.Nombre) -ForegroundColor DarkGray
}

# ---- 4. clasificar ----------------------------------------------------
Write-Titulo ("4 · Qué sale de los últimos {0} minutos" -f $MinutosAtras)
$desde = [DateTime]::UtcNow.AddMinutes(-$MinutosAtras)
$recientes = @($registros | Where-Object { $null -ne $_.Marca -and $_.Marca -ge $desde })
$cuenta = @{ Alta = 0; Baja = 0; Cambio = 0; Nada = 0 }
foreach ($r in $recientes) {
    $t = Get-CambioDesdeRazonUsn -Razon $r.Razon -EsCarpeta:$r.EsCarpeta
    if ($t) { $cuenta[$t]++ } else { $cuenta['Nada']++ }
}
$padres = @($recientes | Where-Object { -not $_.EsCarpeta } | ForEach-Object { $_.NumeroReferenciaPadre } | Sort-Object -Unique)
$archivosDistintos = @($recientes | Where-Object { -not $_.EsCarpeta } | ForEach-Object { $_.NumeroReferencia } | Sort-Object -Unique)
Write-Host ("  registros          {0:N0}" -f $recientes.Count)
Write-Host ("  archivos distintos {0:N0}" -f $archivosDistintos.Count)
Write-Host ("  altas {0:N0}   bajas {1:N0}   cambios {2:N0}   sin interés {3:N0}" -f $cuenta.Alta, $cuenta.Baja, $cuenta.Cambio, $cuenta.Nada)
Write-Host ''
Write-Host ("  CARPETAS PADRE DISTINTAS: {0:N0}" -f $padres.Count) -ForegroundColor White
Write-Host '  Ese es el número que falta resolver a ruta para que esto sirva. Si son'
Write-Host '  cientos, una llamada al sistema por carpeta es barata y el diseño es'
Write-Host '  "resolver al vuelo". Si son decenas de miles, hay que guardar la'
Write-Host '  referencia de cada carpeta en el índice al recorrer. Ver docs/VEL-02-MEDICION.md.'

Write-Titulo 'Copia esta salida entera en la conversación'
