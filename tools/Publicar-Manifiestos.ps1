<#
.SYNOPSIS
    Escribe los manifiestos de winget y de Scoop de una version, con el hash
    del paquete que se acaba de armar.

.DESCRIPTION
    Lo ejecuta .github/workflows/publicar.yml despues de calcular las sumas
    y ANTES de adjuntar nada, por el mismo motivo que Publicar-Sumas.ps1:
    hay que declarar exactamente los bytes que se van a subir.

    EL HASH NO SE PASA POR PARAMETRO A PROPOSITO
    --------------------------------------------
    Se calcula aqui, del archivo real. Un parametro -Hash permitiria pasarle
    el de la version anterior copiado a mano, que es justo el fallo que
    [DIS-03] y [DIS-04] vienen a cerrar: un manifiesto con un hash viejo no
    falla en ningun sitio hasta que alguien intenta instalar, y entonces su
    gestor de paquetes le dice que el archivo descargado no coincide con lo
    declarado. O sea, le dice que el paquete esta adulterado.

    Y SE COMPRUEBA QUE EL ZIP SE LLAMA COMO TIENE QUE LLAMARSE
    ---------------------------------------------------------
    El nombre del .zip lo decide el flujo de publicacion y lo repiten las
    URL de los dos manifiestos. Si alguna vez dejan de coincidir, los
    manifiestos apuntan a una descarga que devuelve 404 y aqui no falla
    nada. Por eso se compara el nombre del archivo que se recibe con el que
    dice Get-NombrePaqueteZip, y si no cuadra se para la publicacion.

    Ver [DIS-03] y [DIS-04].

.PARAMETER Etiqueta
    La etiqueta de git de esta version, con la v: v2.1.0.

.PARAMETER Paquete
    El .zip que se va a adjuntar a la version. Se le calcula el hash.

.PARAMETER Destino
    Carpeta donde escribir los manifiestos. Por defecto packaging/.

.EXAMPLE
    ./tools/Publicar-Manifiestos.ps1 -Etiqueta v2.1.0 -Paquete Cachivache-v2.1.0.zip
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $Etiqueta,

    [Parameter(Mandatory)]
    [string] $Paquete,

    [string] $Destino = 'packaging'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Manifiestos.ps1')

if (-not (Test-Path -LiteralPath $Paquete -PathType Leaf)) {
    throw "No esta el paquete del que hay que declarar el hash: $Paquete"
}

$nombre   = Split-Path -Leaf $Paquete
$esperado = Get-NombrePaqueteZip -Etiqueta $Etiqueta
if ($nombre -cne $esperado) {
    throw ("El paquete se llama '$nombre' y los manifiestos van a declarar '$esperado'. " +
           'Uno de los dos esta mal, y publicarlo asi deja dos URL que devuelven 404.')
}

$hash = (Get-FileHash -LiteralPath $Paquete -Algorithm SHA256).Hash
if (-not (Test-SumaSha256Valida -Suma $hash)) {
    throw "El hash de $Paquete no tiene forma de SHA-256: '$hash'"
}

$identidad   = Get-IdentidadPaquete
$carpetaWinget = Join-Path $Destino 'winget'

$archivos = @(
    @{
        Ruta  = (Join-Path $carpetaWinget ('{0}.yaml' -f $identidad.IdentificadorWinget))
        Texto = (Format-ManifiestoWingetVersion -Etiqueta $Etiqueta)
    }
    @{
        Ruta  = (Join-Path $carpetaWinget ('{0}.installer.yaml' -f $identidad.IdentificadorWinget))
        Texto = (Format-ManifiestoWingetInstalador -Etiqueta $Etiqueta -Hash $hash)
    }
    @{
        Ruta  = (Join-Path $carpetaWinget ('{0}.locale.{1}.yaml' -f $identidad.IdentificadorWinget, $identidad.Idioma))
        Texto = (Format-ManifiestoWingetLocale -Etiqueta $Etiqueta)
    }
    @{
        Ruta  = (Join-Path $Destino ('{0}.json' -f $identidad.IdentificadorScoop))
        Texto = (Format-ManifiestoScoop -Etiqueta $Etiqueta -Hash $hash)
    }
)

if ($PSCmdlet.ShouldProcess($Destino, 'Escribir los manifiestos de winget y de Scoop')) {
    foreach ($carpeta in @($Destino, $carpetaWinget)) {
        if (-not (Test-Path -LiteralPath $carpeta -PathType Container)) {
            New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        }
    }

    foreach ($archivo in $archivos) {
        # UTF8Encoding($false): SIN BOM, igual que SHA256SUMS.txt y por el
        # mismo motivo que alli. Este proyecto exige BOM en todo .ps1 y
        # .xaml, con su propia invariante, y quien venga detras vera aqui un
        # $false y pensara que es un descuido: no lo es. Un YAML o un JSON
        # con BOM lo rechazan los validadores de winget-pkgs y lo lee mal
        # ConvertFrom-Json en PowerShell 5.1.
        #
        # Y WriteAllText, no Out-File: Out-File traduciria los saltos a CRLF
        # en Windows, y estos archivos acaban en repositorios donde cada
        # diferencia se revisa a mano.
        [IO.File]::WriteAllText($archivo.Ruta, $archivo.Texto, [Text.UTF8Encoding]::new($false))
        Write-Host ("  escrito  {0}" -f $archivo.Ruta)
    }
}

Write-Host ''
Write-Host ('Manifiestos de {0} listos, declarando el SHA-256 de {1}:' -f $Etiqueta, $nombre) -ForegroundColor Cyan
Write-Host ('  {0}' -f $hash.ToLowerInvariant())
Write-Host ''
