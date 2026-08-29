<#
.SYNOPSIS
    Cachivache - analiza y libera espacio en Windows sin romper nada.

.DESCRIPTION
    Punto de entrada único. Sin parámetros abre la ventana; con -Consola
    trabaja en la terminal. Todo el código real vive en src/.

    El programa NUNCA borra nada durante el análisis. Para eliminar hace
    falta una confirmación escrita en la ventana, o el modificador
    -Ejecutar en modo consola.

.PARAMETER Consola
    Trabaja en la terminal en lugar de abrir la ventana.

.PARAMETER Perfil
    conservador | equilibrado | agresivo | personalizado.

.PARAMETER Modulos
    Identificadores de módulo concretos. Sustituye a la selección del
    perfil. Usa -Listar para ver los disponibles.

.PARAMETER Ejecutar
    Solo en modo consola: elimina de verdad los elementos que el análisis
    haya marcado por su cuenta (riesgo bajo y sin avisos).

.PARAMETER Permanente
    Borra sin pasar por la papelera. Irreversible.

.PARAMETER Simular
    Con -Ejecutar, ensenya EXACTAMENTE que se borraria y cuanto espacio se
    liberaria, sin tocar un solo archivo. Es la forma de estrenar el
    programa en un equipo sin consecuencias.

        .\Cachivache.ps1 -Consola -Ejecutar -Simular
.PARAMETER Excluir
    Carpetas que no se deben tocar NUNCA, ni proponer. Se suman a las que
    ya tengas guardadas en tus preferencias. Excluir una carpeta excluye
    todo lo que cuelga de ella.

        .\Cachivache.ps1 -Consola -Excluir 'D:\Trabajo','C:\Proyectos\activo'
.PARAMETER Espacio
    Enseña DONDE se ha ido el espacio: el arbol de carpetas ordenado por
    tamano y los archivos mas grandes. Es un informe: no propone ni borra
    nada. Acepta rutas sueltas; sin ellas usa las carpetas del usuario.
.PARAMETER Profundidad
    Cuantos niveles de carpeta enseña -Espacio. Por defecto 2.
.PARAMETER Buscar
    Filtra los archivos de -Espacio por nombre. Admite comodines.
.PARAMETER InformeAnonimo
    Genera el informe sustituyendo tu carpeta de perfil, tu nombre de
    usuario y el nombre del equipo por marcadores genericos. Uselo si va a
    compartir el informe con alguien o adjuntarlo a una incidencia: sin
    esto, cada ruta del informe lleva su nombre de usuario de Windows.
.PARAMETER Informe
    Ruta del informe a generar. La extensión decide el formato:
    .html, .csv o .json.

.PARAMETER Listar
    Muestra los módulos disponibles y termina.

.PARAMETER Silencioso
    No escribe nada por pantalla. Útil en tareas programadas.

.PARAMETER Diagnostico
    Vuelca versión, entorno, unidades y el final del registro, listo para
    pegar en una incidencia, y termina sin analizar ni abrir la ventana.

.EXAMPLE
    .\Cachivache.ps1
    Abre la ventana.

.EXAMPLE
    .\Cachivache.ps1 -Consola -Perfil conservador -Informe .\informe.html
    Analiza sin borrar nada y guarda un informe.

.EXAMPLE
    .\Cachivache.ps1 -Consola -Módulos caches,navegadores -Ejecutar
    Vacía las cachés de aplicaciones y de navegadores.

.EXAMPLE
    .\Cachivache.ps1 -Diagnóstico
    Vuelca el entorno y el final del registro, listo para pegar en una
    incidencia.

.LINK
    https://github.com/pacolopez23/cachivache
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch] $Consola,

    [ValidateSet('conservador', 'equilibrado', 'agresivo', 'personalizado')]
    [string] $Perfil = '',

    [string[]] $Modulos = @(),

    [switch] $Ejecutar,
    [switch] $Permanente,
    [string] $Informe = '',
    [switch] $InformeAnonimo,
    [switch] $Simular,
    [string[]] $Excluir = @(),
    [switch] $Espacio,
    [int]    $Profundidad = 2,
    [string] $Buscar = '',
    [switch] $Listar,
    [switch] $Silencioso,
    [switch] $Diagnostico
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------
#  Comprobaciones previas
# ---------------------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error 'Cachivache necesita PowerShell 5.1 o superior.'
    exit 1
}
if ($env:OS -ne 'Windows_NT') {
    Write-Error 'Cachivache solo funciona en Windows.'
    exit 1
}

$Raiz = $PSScriptRoot

# ---------------------------------------------------------------------
#  Carga del nucleo
# ---------------------------------------------------------------------
try {
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'Core') 'Bootstrap.ps1')
} catch {
    Write-Error "No se ha podido cargar el nucleo del programa: $($_.Exception.Message)"
    exit 1
}

[void](Initialize-Registro)

# ---------------------------------------------------------------------
#  -Diagnóstico
# ---------------------------------------------------------------------
# Antes de contar módulos a propósito: tiene que funcionar incluso si
# src/Modules estuviera vacío o roto, que es justo el tipo de fallo que
# esto sirve para diagnosticar.
if ($Diagnostico) {
    Write-Host (Get-InformeDiagnostico)
    exit 0
}

$modulosDisponibles = @(Get-ModulosLimpieza -Raiz $Raiz)

if ($modulosDisponibles.Count -eq 0) {
    Write-Error 'No se ha encontrado ningun modulo de limpieza en src/Modules.'
    exit 1
}

# ---------------------------------------------------------------------
#  -Listar
# ---------------------------------------------------------------------
if ($Listar) {
    Write-Host ''
    Write-Host "  Cachivache v$script:VersionCachivache - modulos disponibles" -ForegroundColor Cyan
    Write-Host ''
    foreach ($modulo in $modulosDisponibles) {
        $etiquetas = @()
        if ($modulo.RequiereAdmin) { $etiquetas += 'admin' }
        if ($modulo.SoloInforma)   { $etiquetas += 'solo informa' }
        $sufijo = if ($etiquetas.Count -gt 0) { '  [' + ($etiquetas -join ', ') + ']' } else { '' }

        Write-Host ('  {0,-16}' -f $modulo.Id) -ForegroundColor Green -NoNewline
        Write-Host ('{0}{1}' -f $modulo.Nombre, $sufijo)
        Write-Host ('                  {0}' -f $modulo.Descripcion) -ForegroundColor DarkGray
        Write-Host ('                  riesgo {0} - perfiles: {1}' -f `
                    $modulo.Riesgo.ToLower(), ($modulo.Perfiles -join ', ')) -ForegroundColor DarkGray
        Write-Host ''
    }
    exit 0
}

# ---------------------------------------------------------------------
#  Configuración
# ---------------------------------------------------------------------
$preferencias = Import-Preferencias
if ([string]::IsNullOrWhiteSpace($Perfil)) { $Perfil = [string]$preferencias.Perfil }
if ([string]::IsNullOrWhiteSpace($Perfil)) { $Perfil = 'equilibrado' }

$configuracion = New-Configuracion -Perfil $Perfil
if ($Perfil -eq 'personalizado') {
    $configuracion.MinimoMB       = [int]$preferencias.MinimoMB
    $configuracion.DiasSinUso     = [int]$preferencias.DiasSinUso
    $configuracion.IncluirMenores = [bool]$preferencias.IncluirMenores
}
# Las exclusiones del usuario: las guardadas mas las que venga en la linea
# de comandos. Se SUMAN en vez de sustituirse: quien pasa -Excluir esta
# anyadiendo una carpeta para esta ejecucion, no renunciando a las que ya
# habia decidido proteger. Ver [CNF-01] en docs/HOJA-DE-RUTA.md.
$configuracion.RutasExcluidas = @(
    @($preferencias.RutasExcluidas) + @($Excluir) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique
)

if ($Permanente) { $configuracion.Permanente = $true }

Initialize-Guardia -Configuracion $configuracion

# Comprobación de cordura: si la guardia no estuviera activa, cualquier
# ruta sería borrable. Antes que arriesgarse, el programa no arranca.
if (-not (Test-RutaIntocable 'C:\Windows\System32')) {
    Write-Error 'La guardia de seguridad no se ha inicializado correctamente. El programa no va a continuar.'
    exit 1
}

# Identificadores de módulo invalidos: mejor avisar que analizar de menos.
if ($Modulos.Count -gt 0) {
    $conocidos = @($modulosDisponibles | ForEach-Object { $_.Id })
    $desconocidos = @($Modulos | Where-Object { $conocidos -notcontains $_ })
    if ($desconocidos.Count -gt 0) {
        Write-Error ("Modulos desconocidos: {0}. Usa -Listar para ver los disponibles." -f ($desconocidos -join ', '))
        exit 1
    }
}

# ---------------------------------------------------------------------
#  Modo espacio: donde se fue el disco
# ---------------------------------------------------------------------
# Va ANTES del modo consola porque no analiza ni borra: es una consulta.
# Comparte con el resto el nucleo ya cargado y la guardia inicializada.
if ($Espacio) {
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'Cli') 'Cli.ps1')
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'Cli') 'Espacio.ps1')

    Show-InformeEspacio -Rutas $Modulos -Profundidad $Profundidad -Buscar $Buscar `
                        -Anonimo:$InformeAnonimo -Informe $Informe -Configuracion $configuracion
    exit 0
}

# ---------------------------------------------------------------------
#  Modo consola
# ---------------------------------------------------------------------
if ($Consola) {
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'Cli') 'Cli.ps1')
    $codigo = Invoke-CachivacheCli -Configuracion $configuracion -Modulos $modulosDisponibles `
                                  -Ids $Modulos -Ejecutar:$Ejecutar -Informe $Informe `
                                  -InformeAnonimo:$InformeAnonimo -Simular:$Simular `
                                  -Silencioso:$Silencioso -Confirm:$false
    exit $codigo
}

# ---------------------------------------------------------------------
#  Modo ventana
# ---------------------------------------------------------------------
try {
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'UI') 'Types.ps1')
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'UI') 'Window.ps1')
    . (Join-Path (Join-Path (Join-Path $Raiz 'src') 'UI') 'Dialogs.ps1')
} catch {
    Write-Error "No se ha podido cargar la interfaz: $($_.Exception.Message)"
    exit 1
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Warning 'PowerShell no esta en modo STA. Abre el programa con Cachivache.bat o añade -STA.'
}

$preferencias.Perfil = $Perfil
try {
    Show-VentanaPrincipal -Configuracion $configuracion -Modulos $modulosDisponibles `
                          -Preferencias $preferencias -Raiz $Raiz
} catch {
    # Sin esto, un fallo dentro de la ventana llega a la consola como
    # "Excepción al llamar a X" sin decir en que archivo ni en que línea:
    # el mensaje apunta a esta llamada, que es solo el punto de entrada.
    # La pila de PowerShell y la excepción interna si lo dicen, y son
    # justo lo que hace falta para reportar el fallo. Ver [T-05] en
    # docs/OPTIMIZACIONES.md.
    Write-Host ''
    Write-Host '  La ventana ha fallado al arrancar.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Mensaje:' -ForegroundColor Yellow
    Write-Host "    $($_.Exception.Message)"
    $interna = $_.Exception.InnerException
    while ($interna) {
        Write-Host "    causado por: $($interna.Message)"
        $interna = $interna.InnerException
    }
    Write-Host ''
    Write-Host '  Donde (lo de arriba del todo es el sitio exacto):' -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace
    Write-Host ''
    try {
        Write-Registro -Nivel 'ERROR' -Mensaje "Fallo al abrir la ventana: $($_.Exception.Message)"
        Write-Registro -Nivel 'ERROR' -Mensaje $_.ScriptStackTrace
    } catch {
        Write-Verbose "Tampoco se ha podido anotar el fallo en el registro: $($_.Exception.Message)"
    }
    exit 1
}
exit 0
