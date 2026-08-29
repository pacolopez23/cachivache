<#
.SYNOPSIS
    Calcula las sumas SHA-256 de los archivos de una version y escribe
    SHA256SUMS.txt.

.DESCRIPTION
    Lo ejecuta .github/workflows/publicar.yml despues de armar el paquete y
    ANTES de adjuntarlo. El orden no es casual: hay que medir exactamente los
    bytes que se van a subir.

    POR QUE NO VALE MEDIR EL ARTEFACTO DE LA INTEGRACION CONTINUA
    ------------------------------------------------------------
    actions/upload-artifact mete lo que le des DENTRO DE OTRO ZIP. Lo que se
    descarga de la pestanya de artefactos no es el paquete: es un zip que
    contiene el paquete, y su suma no coincide con nada de aqui. Quien
    compare eso concluira que el paquete esta adulterado, y no lo esta. Las
    sumas que se publican son las de los archivos adjuntos a la VERSION.

    Ver [DIS-02]. Es prerrequisito de winget ([DIS-03]) y de Scoop ([DIS-04]),
    que declaran el hash en su manifiesto.

.PARAMETER Archivos
    Los archivos que se van a publicar.

.PARAMETER Destino
    Donde escribir el archivo de sumas. Por defecto, SHA256SUMS.txt en la
    carpeta actual.

.EXAMPLE
    ./tools/Publicar-Sumas.ps1 -Archivos Cachivache-v2.1.0.zip, Cachivache.exe
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string[]] $Archivos,

    [string] $Destino = 'SHA256SUMS.txt'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Sumas.ps1')

$entradas = foreach ($ruta in $Archivos) {
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) {
        throw "No esta el archivo que hay que firmar: $ruta"
    }

    $hash = (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash

    # Publicar una suma mal es PEOR que no publicarla: quien la comprueba y
    # no le cuadra concluye que el paquete esta adulterado. Si el hash no
    # tiene forma de hash, se para la publicacion entera.
    if (-not (Test-SumaSha256Valida -Suma $hash)) {
        throw "El hash de $ruta no tiene forma de SHA-256: '$hash'"
    }

    @{ Nombre = (Split-Path -Leaf $ruta); Hash = $hash }
}

$contenido = Format-SumasSha256 -Entradas @($entradas)

if ($PSCmdlet.ShouldProcess($Destino, 'Escribir las sumas SHA-256')) {
    # UTF8Encoding($false): SIN BOM. Este proyecto exige BOM en todo .ps1 y
    # .xaml, y aqui es justo al reves: un BOM hace que la PRIMERA linea no
    # valide con sha256sum -c, y solo la primera. Un fallo que parece que
    # funciona. Ver la cabecera de Sumas.ps1.
    #
    # Y WriteAllText con "`n" ya dentro del texto, no Out-File: Out-File
    # traduciria los saltos a CRLF en Windows y el \r sobrante se colaria en
    # el nombre del archivo.
    [IO.File]::WriteAllText($Destino, $contenido, [Text.UTF8Encoding]::new($false))
}

Write-Host ''
Write-Host 'SHA-256 de esta version:' -ForegroundColor Cyan
Write-Host ($contenido.TrimEnd())
Write-Host ''

# La tabla se devuelve para que el flujo de publicacion la meta en el cuerpo
# de la version: ahi queda escrita donde no llega quien pudiera cambiar el
# paquete y su archivo de sumas a la vez.
return (Format-TablaSumas -Entradas @($entradas))
