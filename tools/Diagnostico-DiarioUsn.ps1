<#
.SYNOPSIS
    Por que falla FSCTL_READ_USN_JOURNAL en esta maquina. Solo lee.

.DESCRIPTION
    SOLO WINDOWS, Y COMO ADMINISTRADOR.

    El banco [VEL-02] dejo un resultado a medias: la CONSULTA del diario
    responde y devuelve datos con sentido, pero la LECTURA falla en 80 ms.
    Read-DiarioUsn se traga el codigo de error de Windows en un
    Write-Verbose, asi que desde fuera solo se ve "no se ha podido".

    Este guion pregunta lo unico que hace falta saber: QUE numero devuelve
    Windows, y si cambia al mover una sola cosa de la peticion. Prueba seis
    variantes, cada una aislando UNA hipotesis, e imprime el codigo Win32 y
    su mensaje. No cambia nada del programa ni del disco: abre el volumen en
    solo lectura y pregunta.

    Existe porque adivinar por que falla una llamada al sistema, cambiando
    cosas a ciegas y volviendo a pedirle al usuario que lo ejecute, es
    justo lo que este proyecto no hace. Se mide una vez y se corrige con el
    dato delante.

.PARAMETER Unidad
    La letra, sin barra: 'C:'.

.EXAMPLE
    # PowerShell COMO ADMINISTRADOR, en la raiz del repositorio:
    .\tools\Diagnostico-DiarioUsn.ps1 -Unidad C:
#>
[CmdletBinding()]
param(
    [string] $Unidad = 'C:',
    # Cuantos bytes de cada respuesta se parsean. Ver el comentario largo
    # de Invoke-Variante: con el megabyte entero esto tardaba media hora
    # por variante en PowerShell 5.1.
    [int] $MaxBytesParseo = 64KB
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Bootstrap.ps1')

$letra = $Unidad.Trim().TrimEnd('\', '/')

function Write-Titulo([string] $Texto) {
    Write-Host ''
    Write-Host ('=== ' + $Texto + ' ' + ('=' * [Math]::Max(0, 66 - $Texto.Length))) -ForegroundColor Cyan
}

if (-not (Test-EsAdministrador)) {
    Write-Host '  Hace falta administrador. Abre PowerShell como administrador.' -ForegroundColor Yellow
    return
}
if (-not (Initialize-InteropDiarioUsn)) {
    Write-Host '  No se ha podido preparar DeviceIoControl.' -ForegroundColor Yellow
    return
}

# =====================================================================
#  1. La consulta, ENTERA. El banco solo enseñaba tres campos.
# =====================================================================
# LowestValidUsn es el que puede explicarlo todo: si es mayor que FirstUsn,
# empezar a leer en FirstUsn pide registros que NTFS ya ha tirado, y eso
# es un error concreto (1181) y no un fallo de la implementacion.

Write-Titulo '1 · La consulta al completo'

$FSCTL_QUERY = [uint32]0x000900F4
$FSCTL_READ  = [uint32]0x000900BB

$flujo = [IO.FileStream]::new(('\\.\' + $letra), [IO.FileMode]::Open,
                              [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$bufQ = [Runtime.InteropServices.Marshal]::AllocHGlobal(128)
try {
    $dev = [uint32]0
    $ok = [Cachivache.DiarioUsn]::DeviceIoControl($flujo.SafeFileHandle, $FSCTL_QUERY,
              [IntPtr]::Zero, [uint32]0, $bufQ, [uint32]128, [ref]$dev, [IntPtr]::Zero)
    if (-not $ok) {
        Write-Host ('  la consulta falla: Win32 {0}' -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Yellow
        return
    }
    $q = [byte[]]::new([int]$dev)
    [Runtime.InteropServices.Marshal]::Copy($bufQ, $q, 0, [int]$dev)
} finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($bufQ)
}

# El tamaño devuelto dice la version de la estructura, y por tanto que
# versiones de REGISTRO admite este volumen: 56 = V0, 60 = V1, 80 = V2.
# Si es V1 o V2, el sistema publica MinSupportedMajorVersion y
# MaxSupportedMajorVersion, y ahi se ve si USN_RECORD_V2 sigue admitido.
$idDiario   = [BitConverter]::ToUInt64($q, 0)
$primerUsn  = [BitConverter]::ToInt64($q, 8)
$usnSig     = [BitConverter]::ToInt64($q, 16)
$usnBajo    = [BitConverter]::ToInt64($q, 24)
$usnMaximo  = [BitConverter]::ToInt64($q, 32)

Write-Host ('  bytes devueltos   {0}   ({1})' -f $dev,
    $(switch ([int]$dev) { 56 {'USN_JOURNAL_DATA_V0'} 60 {'V1'} 80 {'V2'} default {'tamanyo inesperado'} }))
Write-Host ('  IdDiario          {0}' -f $idDiario)
Write-Host ('  FirstUsn          {0:N0}' -f $primerUsn)
Write-Host ('  NextUsn           {0:N0}' -f $usnSig)
Write-Host ('  LowestValidUsn    {0:N0}' -f $usnBajo)
Write-Host ('  MaxUsn            {0:N0}' -f $usnMaximo)
if ($dev -ge 60) {
    Write-Host ('  MinMajorVersion   {0}' -f [BitConverter]::ToUInt16($q, 56))
    Write-Host ('  MaxMajorVersion   {0}' -f [BitConverter]::ToUInt16($q, 58)) -ForegroundColor White
    Write-Host '  (si MaxMajorVersion es 2, USN_RECORD_V2 vale; si es 3 o 4, hay que mirarlo)'
}
if ($usnBajo -gt $primerUsn) {
    Write-Host '  OJO: LowestValidUsn > FirstUsn. Empezar en FirstUsn pide registros ya tirados.' -ForegroundColor Yellow
}

# =====================================================================
#  2. Las seis variantes
# =====================================================================
# Cada una mueve UNA cosa respecto de lo que hace Read-DiarioUsn hoy, para
# que el codigo que devuelva señale a una causa y no a varias a la vez.

function Invoke-Variante {
    param(
        [string] $Nombre,
        [int64]  $Inicio,
        [uint32] $SoloAlCerrar,
        [int]    $TamBuffer,
        [switch] $EntradaV1
    )

    # READ_USN_JOURNAL_DATA_V0 son 40 bytes; la V1 anyade dos WORD con el
    # rango de versiones de registro que se acepta, y son 48. En Windows
    # modernos la V1 es la forma de decir "dame USN_RECORD_V2", que es
    # exactamente lo que Get-RegistroUsn sabe leer.
    $tam = if ($EntradaV1) { 48 } else { 40 }
    $p = [byte[]]::new($tam)
    [Array]::Copy([BitConverter]::GetBytes([int64]$Inicio),      0, $p,  0, 8)
    # [uint32]::MaxValue y no 0xFFFFFFFF: ese literal es un Int32 que vale
    # -1 y el cast LANZA. Es el fallo que este mismo guion vino a buscar, y
    # que tambien tenia copiado.
    [Array]::Copy([BitConverter]::GetBytes([uint32]::MaxValue),  0, $p,  8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$SoloAlCerrar), 0, $p, 12, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$idDiario),   0, $p, 32, 8)
    if ($EntradaV1) {
        [Array]::Copy([BitConverter]::GetBytes([uint16]2), 0, $p, 40, 2)  # MinMajorVersion
        [Array]::Copy([BitConverter]::GetBytes([uint16]2), 0, $p, 42, 2)  # MaxMajorVersion
    }

    $ent = [Runtime.InteropServices.Marshal]::AllocHGlobal($tam)
    $sal = [Runtime.InteropServices.Marshal]::AllocHGlobal($TamBuffer)
    try {
        [Runtime.InteropServices.Marshal]::Copy($p, 0, $ent, $tam)
        $d = [uint32]0
        $ok = [Cachivache.DiarioUsn]::DeviceIoControl($flujo.SafeFileHandle, $FSCTL_READ,
                  $ent, [uint32]$tam, $sal, [uint32]$TamBuffer, [ref]$d, [IntPtr]::Zero)
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if (-not $ok) {
            $msg = try { ([ComponentModel.Win32Exception]$err).Message } catch { '' }
            Write-Host ('  {0,-34} FALLA   Win32 {1}  {2}' -f $Nombre, $err, $msg) -ForegroundColor Yellow
            return
        }

        # Bien. Cuantos registros se entienden de lo que ha venido?
        #
        # SOLO SE PARSEA UN TROZO, Y ESTO SE APRENDIO POR LAS MALAS. La
        # primera version parseaba el megabyte entero de cada variante. En
        # Windows PowerShell 5.1 eso tardo MEDIA HORA por variante -el
        # usuario se fue a dormir a mitad-, cuando en pwsh 7 sobre Linux el
        # mismo trabajo son 1,6 segundos. Una herramienta de diagnostico que
        # tarda mas que el problema que diagnostica no es una herramienta.
        #
        # Con 64 KB sobra para lo que se vino a saber -si el formato se
        # entiende y de que version son los registros- y ademas se MIDE la
        # velocidad, que resulto ser el dato decisivo de todo [VEL-02].
        $bloque = [byte[]]::new([int]$d)
        [Runtime.InteropServices.Marshal]::Copy($sal, $bloque, 0, [int]$d)
        $regs = @()
        $ritmo = ''
        if ($d -gt 8) {
            $aParsear = [Math]::Min([int]$d - 8, $MaxBytesParseo)
            $cuerpo = [byte[]]::new($aParsear)
            [Array]::Copy($bloque, 8, $cuerpo, 0, $aParsear)
            $cr = [Diagnostics.Stopwatch]::StartNew()
            $regs = @(Get-RegistrosUsn -Bytes $cuerpo)
            $cr.Stop()
            $seg = $cr.Elapsed.TotalSeconds
            if ($seg -gt 0 -and $regs.Count -gt 0) {
                $porSeg = $regs.Count / $seg
                # La extrapolacion es la frase que decide si [VEL-02] vive:
                # cuanto costaria parsear TODO lo que el diario conserva,
                # comparado con los 42 s que tarda recorrer el disco entero.
                $bytesReg = $aParsear / $regs.Count
                $totalReg = ($usnSig - $primerUsn) / $bytesReg
                $ritmo = ('  [{0:N0} reg/s -> el diario entero serian {1:N0} reg = {2:N0} s]' -f
                          $porSeg, $totalReg, ($totalReg / $porSeg))
            }
        }
        # La version que trae el PRIMER registro es el dato que decide si
        # Get-RegistroUsn puede leerlos: exige 2.0 exacto y devuelve $null
        # ante cualquier otra, en silencio, que es como se ve "cero
        # registros" con la llamada en verde.
        $ver = ''
        if ($d -gt 12) { $ver = ' · primer registro v{0}.{1}' -f [BitConverter]::ToUInt16($bloque, 12), [BitConverter]::ToUInt16($bloque, 14) }
        Write-Host ('  {0,-34} BIEN    {1:N0} bytes, {2:N0} registros entendidos{3}' -f $Nombre, $d, $regs.Count, $ver) -ForegroundColor Green
        if ($regs.Count -gt 0) {
            Write-Host ('      ejemplo: {0}' -f $regs[0].Nombre) -ForegroundColor DarkGray
        }
        if ($ritmo) { Write-Host $ritmo -ForegroundColor White }
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($ent)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($sal)
    }
}

Write-Titulo '2 · Seis variantes de la peticion'

try {
    # A: lo que hace hoy Read-DiarioUsn. Es la linea base.
    Invoke-Variante -Nombre 'A · como ahora (FirstUsn, cerrar)' -Inicio $primerUsn -SoloAlCerrar 1 -TamBuffer 1MB

    # B: desde cero. Documentado como "todo lo que haya"; descarta que el
    #    problema sea el USN de partida.
    Invoke-Variante -Nombre 'B · desde 0' -Inicio 0 -SoloAlCerrar 1 -TamBuffer 1MB

    # C: sin ReturnOnlyOnClose. Descarta que el filtro sea lo que molesta.
    Invoke-Variante -Nombre 'C · desde 0, sin filtro de cierre' -Inicio 0 -SoloAlCerrar 0 -TamBuffer 1MB

    # D: desde LowestValidUsn. Si A falla con 1181 y esta va, la causa era
    #    empezar en un tramo ya reciclado.
    Invoke-Variante -Nombre 'D · desde LowestValidUsn' -Inicio $usnBajo -SoloAlCerrar 1 -TamBuffer 1MB

    # E: buffer de 64 KB. METHOD_NEITHER pasa el puntero tal cual al
    #    sistema de archivos, y hay versiones que se quejan de un buffer
    #    grande de golpe.
    Invoke-Variante -Nombre 'E · desde 0, buffer 64 KB' -Inicio 0 -SoloAlCerrar 1 -TamBuffer 64KB

    # F: peticion V1 pidiendo registros version 2. Si las cinco de arriba
    #    fallan y esta va, el volumen exige la estructura nueva.
    Invoke-Variante -Nombre 'F · peticion V1, registros v2' -Inicio 0 -SoloAlCerrar 1 -TamBuffer 1MB -EntradaV1
} finally {
    $flujo.Dispose()
}

Write-Titulo 'Copia esta salida entera en la conversacion'
