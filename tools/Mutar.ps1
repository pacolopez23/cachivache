<#
.SYNOPSIS
    Rompe el codigo a proposito, para comprobar que una prueba falla por el
    motivo correcto. Herramienta de desarrollo.

.DESCRIPTION
    La regla 3 del relevo dice que toda invariante se verifica por mutacion:
    se rompe el codigo, se comprueba que la prueba falla, y se restaura. Una
    invariante que no se ha visto fallar no sirve para nada.

    Este archivo existe porque ESE PASO SE ROMPIO DOS VECES EN UNA SOLA
    SESION, y las dos de la misma forma: el sustituidor no encontro el texto
    que buscaba, no dijo nada, y la suite paso. O sea, el paso que existe
    para no fiarse de que una prueba pasa, dio por buena una prueba porque
    pasaba. La segunda vez fueron cuatro mutaciones seguidas.

    De ahi las dos reglas de aqui, y las dos son la misma idea:

    1. Si el texto a mutar NO APARECE, se lanza. No mutar nada tiene que ser
       ruidoso, porque el sintoma de no mutar nada es identico al de una
       prueba impecable.
    2. Si aparece MAS DE UNA VEZ, tambien se lanza. Mutar "la primera" es
       mutar un sitio que no se ha elegido, y entonces no se sabe que se
       esta probando.

    Ver [VAL-02] y la regla 3 de docs/RELEVO.md.

.EXAMPLE
    . ./tools/Mutar.ps1
    Invoke-Mutacion -Ruta ./src/UI/Atajos.ps1 -Buscar "return 'Filtrar'" -Poner "return 'Otra'" -Prueba {
        # ... aqui se ejecuta la suite y se comprueba que falla
    }
#>

function Get-TextoMutado {
    <#
    .SYNOPSIS
        El texto con la sustitucion hecha. Calculo puro.

    .DESCRIPTION
        Aparte de la parte que toca el disco para poder probarlo sin tocar
        ningun archivo. Es la funcion que decide si la mutacion es valida.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Texto,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Buscar,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Poner
    )

    if ([string]::IsNullOrEmpty($Texto))  { throw 'No hay texto que mutar.' }
    if ([string]::IsNullOrEmpty($Buscar)) { throw 'No se ha dicho que buscar.' }
    if ($Buscar -ceq $Poner) { throw 'La mutacion no cambia nada: buscar y poner son iguales.' }

    # Comparacion literal, no expresion regular: lo que se muta es codigo
    # lleno de $, [, ] y (, y escaparlo a mano es justo como se falla.
    $veces = 0
    $desde = 0
    while ($true) {
        $i = $Texto.IndexOf($Buscar, $desde, [StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $veces++
        $desde = $i + $Buscar.Length
    }

    if ($veces -eq 0) {
        throw ("No aparece, asi que no se ha mutado nada: '{0}'" -f $Buscar)
    }
    if ($veces -gt 1) {
        throw ("Aparece {0} veces: '{1}'. Alarga el texto hasta que sea unico." -f $veces, $Buscar)
    }

    return $Texto.Replace($Buscar, $Poner)
}

function Invoke-Mutacion {
    <#
    .SYNOPSIS
        Muta un archivo, ejecuta lo que se le diga, y lo restaura pase lo
        que pase.

    .PARAMETER Prueba
        Bloque a ejecutar con el codigo roto. Lo normal es lanzar Pester y
        MIRAR QUE FALLA, y que falle por el motivo correcto.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [Parameter(Mandatory)] [string] $Buscar,
        [Parameter(Mandatory)] [string] $Poner,
        [Parameter(Mandatory)] [scriptblock] $Prueba
    )

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) {
        throw "No esta el archivo que hay que mutar: $Ruta"
    }

    $original = [IO.File]::ReadAllText($Ruta)
    # Get-TextoMutado lanza ANTES de tocar el disco si la mutacion no vale.
    $mutado = Get-TextoMutado -Texto $original -Buscar $Buscar -Poner $Poner

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Mutar temporalmente')) { return }

    # El BOM se conserva: sin el, la mutacion romperia la invariante de
    # codificacion y la prueba fallaria por un motivo que no es el que se
    # esta comprobando. Que es exactamente lo que esto viene a evitar.
    $conBom = $original.Length -gt 0 -and
              [IO.File]::ReadAllBytes($Ruta)[0] -eq 239
    $codificacion = [Text.UTF8Encoding]::new($conBom)

    try {
        [IO.File]::WriteAllText($Ruta, $mutado, $codificacion)
        & $Prueba
    } finally {
        # finally y no al final del try: si el bloque de prueba lanza, el
        # archivo tiene que quedar restaurado igual. Dejar el repositorio
        # mutado seria peor que no haber mutado.
        [IO.File]::WriteAllText($Ruta, $original, $codificacion)
    }
}
