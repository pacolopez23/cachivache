<#
.SYNOPSIS
    Genera Cachivache.exe, el lanzador sin consola.

.DESCRIPTION
    El .bat funciona, pero deja una ventana de consola abierta detras del
    programa durante toda la sesión: PowerShell se ejecuta DENTRO de ella y
    la consola no puede cerrarse sin matar el proceso.

    Este script produce un ejecutable de unos 45 KB -de los cuales el
    icono incrustado se lleva la mayor parte- cuyo único trabajo es
    arrancar PowerShell con la ventana oculta y salir. No lleva lógica del
    programa: si alguna vez se pierde, se vuelve a generar desde aquí en
    dos segundos.

    Se compila con csc.exe, el compilador de C# que viene DENTRO de
    Windows como parte de .NET Framework. No hace falta instalar nada, ni
    Visual Studio, ni el SDK.

    POR QUE EL .EXE NO ESTA EN EL REPOSITORIO
    -----------------------------------------
    Por dos motivos, y el primero es de fondo. El proyecto presume de que
    "puedes leer exactamente que hace antes de ejecutarlo": un binario
    dentro del repositorio es justo lo contrario, porque nadie puede
    auditarlo leyendo el código. Y el segundo es práctico: un ejecutable
    pequeño y sin firmar que lanza PowerShell tiene exactamente la forma
    de un cuentagotas de malware, y los antivirus lo tratan como tal con
    frecuencia. Descargado de la página de versiones, al menos hay rastro
    de que lo construyo la integración continua a partir de este código.

    En la práctica: el CI lo compila y lo adjunta a cada versión
    publicada. Quien clone el repositorio ejecuta este script una vez, o
    usa el .bat.

.EXAMPLE
    .\tools\Compilar-Lanzador.ps1
    Deja Cachivache.exe en la raiz del proyecto.

.EXAMPLE
    .\tools\Compilar-Lanzador.ps1 -Destino C:\temp\Cachivache.exe
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Destino = ''
)

$ErrorActionPreference = 'Stop'

$raiz = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($Destino)) {
    $Destino = Join-Path $raiz 'Cachivache.exe'
}

# ---------------------------------------------------------------------
#  El lanzador
# ---------------------------------------------------------------------
# Deliberadamente corto: cuanto menos haga, menos hay que auditar. Resuelve
# su propia carpeta, comprueba que el .ps1 esta al lado y arranca
# PowerShell con la ventana oculta.
#
# -STA es imprescindible: WPF no arranca en un hilo MTA, que es el que
# usaria PowerShell por defecto al invocarse así.
$fuente = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

static class Lanzador
{
    [STAThread]
    static int Main(string[] argumentos)
    {
        string carpeta = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string guion   = Path.Combine(carpeta, "Cachivache.ps1");

        if (!File.Exists(guion))
        {
            MessageBox.Show(
                "No se encuentra Cachivache.ps1 junto a este ejecutable.\n\n" +
                "El lanzador tiene que estar en la misma carpeta que el programa.",
                "Cachivache", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // Cada argumento va entre comillas: sin esto, uno con espacios
        // llegaba partido en dos al otro lado.
        string extra = "";
        foreach (string a in argumentos) { extra += " \"" + a + "\""; }

        // RUTA COMPLETA, no "powershell.exe" a secas. Con
        // UseShellExecute=false, CreateProcess busca PRIMERO en la carpeta
        // del ejecutable que llama, y este .exe se descomprime donde el
        // usuario quiera: normalmente Descargas, que esta llena de cosas
        // que ha bajado de internet. Un powershell.exe ajeno ahi se
        // ejecutaria en lugar del de Windows.
        string psExe = Path.Combine(Environment.SystemDirectory,
                                    @"WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(psExe))
        {
            MessageBox.Show(
                "No se encuentra Windows PowerShell en:\n" + psExe,
                "Cachivache", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        ProcessStartInfo inicio = new ProcessStartInfo();
        inicio.FileName = psExe;
        inicio.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + guion + "\"" + extra;
        inicio.WorkingDirectory = carpeta;
        inicio.UseShellExecute = false;
        inicio.CreateNoWindow = true;

        try
        {
            Process proceso = Process.Start(inicio);
            proceso.WaitForExit();
            return proceso.ExitCode;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "No se ha podido iniciar PowerShell.\n\n" + ex.Message,
                "Cachivache", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
'@

# ---------------------------------------------------------------------
#  Compilación
# ---------------------------------------------------------------------
# Este bloque dice en voz alta todo lo que hace. No es verborrea: cuando
# esto falla, falla en el equipo de otra persona y sin registro, así que
# la salida de pantalla ES el diagnóstico.
Write-Host ''
Write-Host '  Compilando el lanzador...' -ForegroundColor Cyan
Write-Host ''
Write-Host ('    PowerShell : {0} ({1})' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
Write-Host ('    Destino    : {0}' -f $Destino)

# --- 1. Localizar csc.exe --------------------------------------------
# Se buscan las dos arquitecturas y CUALQUIER versión 4.x, en vez de dar
# por hecho el número de compilación 30319. Es el mismo compilador, y una
# ruta fija es una forma tonta de fallar.
$candidatos = @()
foreach ($marco in @('Framework64', 'Framework')) {
    $carpeta = Join-Path $env:SystemRoot "Microsoft.NET\$marco"
    if (-not (Test-Path -LiteralPath $carpeta)) { continue }
    $candidatos += @(Get-ChildItem -LiteralPath $carpeta -Directory -Filter 'v4.*' -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending |
                     ForEach-Object { Join-Path $_.FullName 'csc.exe' } |
                     Where-Object { Test-Path -LiteralPath $_ })
}

if ($candidatos.Count -eq 0) {
    Write-Host ''
    Write-Host '  No se encuentra el compilador de C# de .NET Framework.' -ForegroundColor Red
    Write-Host ('  Se ha buscado csc.exe en {0}\Microsoft.NET\Framework[64]\v4.*' -f $env:SystemRoot)
    Write-Host ''
    Write-Host '  Viene de serie con Windows 10 y 11. Si de verdad no esta, el .bat'
    Write-Host '  hace exactamente lo mismo dejando la consola a la vista:'
    Write-Host '      .\Cachivache.bat'
    exit 1
}

$csc = $candidatos[0]
Write-Host ('    csc.exe    : {0}' -f $csc)

# --- 1b. El icono ------------------------------------------------------
# Sin esto el lanzador sale con el icono generico de aplicación de .NET,
# que es de las cosas que más delatan a un proyecto casero. Es opcional a
# propósito: si alguien borra assets/, el .exe se sigue compilando.
$icono = Join-Path (Join-Path $raiz 'assets') 'cachivache.ico'
$argumentosIcono = @()
if (Test-Path -LiteralPath $icono) {
    $argumentosIcono = @("/win32icon:$icono")
    Write-Host ('    Icono      : {0}' -f $icono)
} else {
    Write-Host '    Icono      : (no esta assets\cachivache.ico; se compila sin el)'
}

# --- 2. Compilar ------------------------------------------------------
$archivoFuente = Join-Path ([IO.Path]::GetTempPath()) ('Lanzador_' + [Guid]::NewGuid() + '.cs')
Set-Content -LiteralPath $archivoFuente -Value $fuente -Encoding UTF8

$salida  = @()
$codigo  = -1
try {
    if (-not $PSCmdlet.ShouldProcess($Destino, 'Compilar el lanzador')) { return }

    # OJO con este bloque: el script corre con ErrorActionPreference =
    # 'Stop', y con esa preferencia CUALQUIER línea que un programa
    # externo escriba en la salida de error se convierte en un error
    # TERMINANTE al redirigirla con 2>&1. csc escribe ahi sus avisos, así
    # que un aviso inofensivo abortaba el script entero y no se llegaba
    # nunca a mirar el código de salida. Se baja la preferencia solo
    # durante la llamada.
    $preferenciaAnterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    # /target:winexe es lo que hace que NO se cree consola: un ejecutable
    # de subsistema Windows, no de consola. Es toda la diferencia entre
    # este .exe y el .bat.
    $salida = @(& $csc /nologo /target:winexe /optimize+ `
                       /reference:System.dll /reference:System.Windows.Forms.dll `
                       @argumentosIcono `
                       "/out:$Destino" $archivoFuente 2>&1 |
                ForEach-Object { $_.ToString() })
    $codigo = $LASTEXITCODE

    $ErrorActionPreference = $preferenciaAnterior
} finally {
    Remove-Item -LiteralPath $archivoFuente -Force -ErrorAction SilentlyContinue
}

Write-Host ('    Codigo     : {0}' -f $codigo)

if ($codigo -ne 0) {
    Write-Host ''
    Write-Host '  La compilacion ha fallado. Esto es lo que ha dicho csc:' -ForegroundColor Red
    if ($salida.Count -eq 0) { Write-Host '    (no ha dicho nada)' }
    $salida | ForEach-Object { Write-Host "    $_" }
    exit 1
}

# --- 3. Comprobar que el archivo existe de verdad ---------------------
# csc puede terminar con código 0 y no dejar nada: el caso típico es un
# antivirus que borra el .exe recien creado en cuanto lo ve. Es un
# ejecutable pequeño, sin firmar y que arranca PowerShell, o sea que
# tiene la forma exacta de un cuentagotas de malware. Comprobarlo aquí
# ahorra el "compila bien pero no aparece" que no lleva a ninguna parte.
if (-not (Test-Path -LiteralPath $Destino)) {
    Write-Host ''
    Write-Host '  csc ha terminado sin errores PERO el archivo no esta.' -ForegroundColor Red
    Write-Host '  Casi siempre es el antivirus, que lo ha puesto en cuarentena nada'
    Write-Host '  más crearse. Mira el historial de protección de Windows Defender.'
    Write-Host ''
    Write-Host '  Mientras tanto, el .bat hace lo mismo dejando la consola a la vista:'
    Write-Host '      .\Cachivache.bat'
    exit 1
}

# --- 4. Comprobar que es lo que decimos que es ------------------------
# El subsistema esta en la cabecera PE: 2 = ventana, 3 = consola. Si
# saliera 3, el .exe abriria su propia consola negra, que es justo lo que
# este archivo existe para evitar. Lo comprueba también la integración
# continua; comprobarlo aquí es lo que hace que el usuario se entere.
$bytes      = [IO.File]::ReadAllBytes($Destino)
$inicioPE   = [BitConverter]::ToInt32($bytes, 0x3C)
$subsistema = [BitConverter]::ToUInt16($bytes, $inicioPE + 0x5C)

if ($subsistema -ne 2) {
    Write-Host ''
    Write-Host ('  El ejecutable ha salido de CONSOLA (subsistema {0}, se esperaba 2).' -f $subsistema) -ForegroundColor Red
    Write-Host '  Así seguiria apareciendo la ventana negra. No lo uses; avisa del fallo.'
    exit 1
}

$sizeBytes = (Get-Item -LiteralPath $Destino).Length
Write-Host ('    Subsistema : {0} (ventana)' -f $subsistema)
Write-Host ''
Write-Host ('  Listo: {0} ({1:N0} bytes)' -f $Destino, $sizeBytes) -ForegroundColor Green
Write-Host '  Doble clic y el programa se abre sin ninguna consola detras.'
Write-Host ''
