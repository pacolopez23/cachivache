<#
.SYNOPSIS
    Cuanta HISTORIA guarda el diario de cambios de NTFS en esta maquina.
    Solo consulta; no lee ni parsea ni un registro.

.DESCRIPTION
    SOLO WINDOWS, Y COMO ADMINISTRADOR.

    LA PREGUNTA QUE DECIDE [VEL-02], Y QUE NO SE HABIA HECHO.

    Toda la idea de [VEL-02] es: "el segundo analisis no recorre el disco,
    solo mira que ha cambiado desde el anterior". Eso da por supuesto que
    el diario recuerda lo que paso desde el analisis anterior. Y el diario
    NTFS es un buffer circular de tamanyo fijo: cuando se llena, tira lo
    viejo por delante. Si en esta maquina solo caben diez minutos de
    historia, el atajo no existe para nadie que analice dos veces el mismo
    dia, por rapido que fuera leerlo.

    Se sospecho al comparar dos ejecuciones sueltas del diagnostico: entre
    una y otra el diario habia generado unos 148 MB y seguia conservando
    solo 37. Pero no se sabia cuanto tiempo habia pasado entre ellas, asi
    que no era una medicion: era una corazonada. Esto la convierte en un
    numero, con reloj.

    COMO LO MIDE. Consulta el diario cada pocos segundos y apunta dos
    cosas: cuanto CRECE por delante (NextUsn, o sea cuanta actividad hay en
    el equipo) y cuanto se TIRA por detras (FirstUsn). Con esas dos
    velocidades sale la respuesta:

        ventana de historia = lo que conserva / lo que genera por minuto

    -------------------------------------------------------------------
    QUE TOCA: NADA. Abre el volumen en solo lectura y pregunta. Se puede
    dejar corriendo mientras se trabaja; de hecho es MEJOR, porque asi mide
    el uso real del equipo y no el de un equipo parado.

.PARAMETER Minutos
    Cuanto tiempo observar. Diez dan una cifra decente; con dos ya se ve la
    tendencia si hay prisa.

.PARAMETER CadaSegundos
    Cada cuanto se pregunta.

.EXAMPLE
    # PowerShell COMO ADMINISTRADOR, en la raiz del repositorio.
    # Dejalo corriendo y sigue usando el ordenador con normalidad.
    .\tools\Banco-VEL02-Retencion.ps1 -Unidad C: -Minutos 10
#>
[CmdletBinding()]
param(
    [string] $Unidad = 'C:',
    [int] $Minutos = 10,
    [int] $CadaSegundos = 30
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Bootstrap.ps1')

$letra = $Unidad.Trim().TrimEnd('\', '/')

if (-not (Test-EsAdministrador)) {
    Write-Host '  Hace falta administrador.' -ForegroundColor Yellow
    return
}

$primero = Get-DatosDiarioUsn -Unidad $letra
if ($null -eq $primero) {
    Write-Host ('  El diario de {0} no responde.' -f $letra) -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host ('=== Retencion del diario de {0} · observando {1} minutos ===' -f $letra, $Minutos) -ForegroundColor Cyan
Write-Host '  Sigue usando el ordenador con normalidad: la cifra vale para el uso real.'
Write-Host ''
# Alineacion a la derecha es {1,16}, NO {1,>16}: el mayor-que no existe en
# el formato de .NET y hace que -f lance "la cadena de entrada no tiene el
# formato correcto". Reventaba en la cabecera, o sea antes de la primera
# medicion, en la unica linea del archivo que no se habia ejecutado nunca.
Write-Host ('  {0,-9} {1,16} {2,16} {3,14}' -f 'reloj', 'generado (MB)', 'tirado (MB)', 'conserva (MB)')

$arranque   = Get-Date
$usnInicial = $primero.UsnSiguiente
$priInicial = $primero.PrimerUsn
$fin        = $arranque.AddMinutes($Minutos)
$ultimo     = $primero

while ((Get-Date) -lt $fin) {
    Start-Sleep -Seconds $CadaSegundos
    $ahora = Get-DatosDiarioUsn -Unidad $letra
    if ($null -eq $ahora) { continue }

    # SI CAMBIA EL IDENTIFICADOR, TODO LO ANTERIOR NO VALE. Windows puede
    # borrar y recrear el diario; entonces los USN empiezan de cero y
    # restar da un numero sin sentido. Es ademas la razon por la que el
    # indice guarda el IdDiario junto al USN de corte.
    if ($ahora.IdDiario -ne $primero.IdDiario) {
        Write-Host '  El diario se ha recreado durante la medicion. Vuelve a empezar.' -ForegroundColor Yellow
        return
    }

    $transcurrido = ((Get-Date) - $arranque)
    Write-Host ('  {0,-9} {1,16:N1} {2,16:N1} {3,12:N1}' -f
        $transcurrido.ToString('mm\:ss'),
        (($ahora.UsnSiguiente - $usnInicial) / 1MB),
        (($ahora.PrimerUsn - $priInicial) / 1MB),
        (($ahora.UsnSiguiente - $ahora.PrimerUsn) / 1MB))
    $ultimo = $ahora
}

# -------------------------------------------------------------------
$minutosReales = ((Get-Date) - $arranque).TotalMinutes
$generado = ($ultimo.UsnSiguiente - $usnInicial) / 1MB
$conserva = ($ultimo.UsnSiguiente - $ultimo.PrimerUsn) / 1MB
$porMinuto = if ($minutosReales -gt 0) { $generado / $minutosReales } else { 0 }

Write-Host ''
Write-Host '=== La cifra ==========================================================' -ForegroundColor Cyan
Write-Host ('  observado          {0:N1} minutos' -f $minutosReales)
Write-Host ('  el diario genera   {0:N1} MB por minuto' -f $porMinuto)
Write-Host ('  y conserva         {0:N1} MB' -f $conserva)

if ($porMinuto -le 0) {
    Write-Host ''
    Write-Host '  No se ha generado nada: el equipo estaba parado. Repitelo mientras lo usas.' -ForegroundColor Yellow
    return
}

$ventana = $conserva / $porMinuto
Write-Host ''
Write-Host ('  VENTANA DE HISTORIA: {0:N0} minutos' -f $ventana) -ForegroundColor White
Write-Host ''
Write-Host '  Es el tiempo maximo que puede pasar entre dos analisis para que el'
Write-Host '  segundo pueda usar el diario en vez de recorrer el disco. Si son'
Write-Host '  minutos, [VEL-02] no sirve para nadie y hay que cerrarlo como se'
Write-Host '  cerro [VEL-01]: medido y descartado. Si son horas o dias, entonces'
Write-Host '  la conversacion pasa a ser la velocidad de parseo, que es el otro'
Write-Host '  problema. Ver docs/VEL-02-MEDICION.md.'
