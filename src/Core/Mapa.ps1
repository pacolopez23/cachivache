<#
.SYNOPSIS
    Disposición del mapa de árbol: convierte tamaños en rectángulos.

.DESCRIPTION
    Cálculo puro. No dibuja nada, no sabe qué es WPF y no toca el disco:
    recibe una lista de elementos con un tamaño y un rectángulo, y
    devuelve dónde va cada uno. Eso es lo que permite PROBARLO, que en un
    proyecto donde la interfaz no se puede ejecutar en las pruebas no es
    un detalle menor.

    -------------------------------------------------------------------
    POR QUE "CUADRADO" Y NO A TIRAS

    La forma ingenua de repartir un rectángulo es cortarlo en tiras: una
    franja por elemento, todas del mismo ancho. Es fácil de escribir y
    produce rectángulos larguísimos y finísimos, imposibles de comparar
    con la vista y de pulsar con el ratón.

    El algoritmo cuadrado -"squarified treemap", de Bruls, Huizing y van
    Wijk- va metiendo elementos en una fila mientras la PROPORCION del
    peor rectángulo de esa fila mejore, y la cierra en cuanto empeora. El
    resultado son rectángulos cercanos al cuadrado, que es lo que hace el
    mapa legible.

    La proporción de un rectángulo es el lado largo dividido entre el
    corto: 1 es un cuadrado perfecto, y cuanto más alto peor.

    -------------------------------------------------------------------
    LO QUE NO HACE

    No decide colores ni textos: eso es de quien dibuja. Devuelve
    geometría y el elemento original, y ya. Así el mismo cálculo sirve
    para WPF, para un SVG en un informe o para una prueba.
#>

function New-Rectangulo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria.')]
    [CmdletBinding()]
    param([double] $X, [double] $Y, [double] $Ancho, [double] $Alto)

    return [pscustomobject]@{ X = $X; Y = $Y; Ancho = $Ancho; Alto = $Alto }
}

function Get-ProporcionPeor {
    <#
    .SYNOPSIS
        Proporción del peor rectángulo de una fila.
    .DESCRIPTION
        Es la función que decide cuándo cerrar una fila. Recibe los
        tamaños de la fila, su suma y el lado corto disponible.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [double[]] $Tamanos,
        [double]   $Suma,
        [double]   $Lado
    )

    if ($Tamanos.Count -eq 0 -or $Suma -le 0 -or $Lado -le 0) { return [double]::MaxValue }

    $minimo = [double]::MaxValue
    $maximo = 0.0
    foreach ($t in $Tamanos) {
        if ($t -lt $minimo) { $minimo = $t }
        if ($t -gt $maximo) { $maximo = $t }
    }
    if ($minimo -le 0) { return [double]::MaxValue }

    # Formula del articulo original: max( l^2*max/s^2 , s^2/(l^2*min) ).
    $ladoCuadrado = $Lado * $Lado
    $sumaCuadrado = $Suma * $Suma
    return [Math]::Max(($ladoCuadrado * $maximo) / $sumaCuadrado,
                       $sumaCuadrado / ($ladoCuadrado * $minimo))
}

function Get-DisposicionMapa {
    <#
    .SYNOPSIS
        Reparte un rectángulo entre una lista de elementos, en proporción
        a su tamaño.

    .PARAMETER Elementos
        Objetos con una propiedad de tamaño. Se devuelven tal cual dentro
        del resultado, para que quien dibuje tenga el original a mano.
    .PARAMETER Ancho
    .PARAMETER Alto
        Tamaño del área a repartir, en las unidades que sean.
    .PARAMETER Propiedad
        Nombre de la propiedad que lleva el tamaño.
    .PARAMETER MinimoLado
        Los rectángulos más finos que esto no se devuelven. Un elemento
        que no se puede ni ver ni pulsar no ayuda a nadie, y dibujarlo
        cuesta igual.

    .NOTES
        Los elementos se ordenan de mayor a menor, que es lo que el
        algoritmo necesita para producir rectángulos cuadrados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Elementos,
        [Parameter(Mandatory)] [double] $Ancho,
        [Parameter(Mandatory)] [double] $Alto,
        [string] $Propiedad  = 'Bytes',
        [double] $MinimoLado = 3
    )

    $resultado = [Collections.Generic.List[object]]::new()
    if ($Ancho -le 0 -or $Alto -le 0) { return @($resultado) }

    $lista = @(@($Elementos) |
               Where-Object { $null -ne $_ -and [double]$_.$Propiedad -gt 0 } |
               Sort-Object -Property $Propiedad -Descending)
    if ($lista.Count -eq 0) { return @($resultado) }

    $total = 0.0
    foreach ($e in $lista) { $total += [double]$e.$Propiedad }
    if ($total -le 0) { return @($resultado) }

    # Se trabaja en AREA: cada elemento recibe una porcion del area total
    # proporcional a su tamaño. Asi el reparto no depende de la escala.
    $areaTotal = $Ancho * $Alto
    $escala    = $areaTotal / $total

    $x = 0.0; $y = 0.0
    $anchoLibre = $Ancho; $altoLibre = $Alto

    $indice = 0
    while ($indice -lt $lista.Count -and $anchoLibre -gt 0 -and $altoLibre -gt 0) {

        # El lado corto manda: las filas se colocan a lo largo del lado
        # largo para que salgan lo mas cuadradas posible.
        $lado = [Math]::Min($anchoLibre, $altoLibre)

        $fila      = [Collections.Generic.List[object]]::new()
        $areasFila = [Collections.Generic.List[double]]::new()
        $sumaFila  = 0.0

        while ($indice -lt $lista.Count) {
            $area = [double]$lista[$indice].$Propiedad * $escala
            if ($area -le 0) { $indice++; continue }

            if ($fila.Count -eq 0) {
                $fila.Add($lista[$indice]); $areasFila.Add($area)
                $sumaFila += $area; $indice++
                continue
            }

            # Se prueba a añadir: si el peor rectangulo empeora, la fila
            # se cierra sin este elemento.
            $actual = Get-ProporcionPeor -Tamanos $areasFila.ToArray() -Suma $sumaFila -Lado $lado
            $conNuevo = [Collections.Generic.List[double]]::new($areasFila)
            $conNuevo.Add($area)
            $siguiente = Get-ProporcionPeor -Tamanos $conNuevo.ToArray() -Suma ($sumaFila + $area) -Lado $lado

            if ($siguiente -gt $actual) { break }

            $fila.Add($lista[$indice]); $areasFila.Add($area)
            $sumaFila += $area; $indice++
        }

        if ($fila.Count -eq 0) { break }

        # La fila ocupa una banda de grosor "suma / lado".
        $grosor = $sumaFila / $lado
        $avance = 0.0

        for ($i = 0; $i -lt $fila.Count; $i++) {
            $trozo = $areasFila[$i] / $grosor

            if ($anchoLibre -ge $altoLibre) {
                # Banda vertical a la izquierda del area libre.
                $rect = New-Rectangulo -X $x -Y ($y + $avance) -Ancho $grosor -Alto $trozo
            } else {
                # Banda horizontal en la parte de arriba.
                $rect = New-Rectangulo -X ($x + $avance) -Y $y -Ancho $trozo -Alto $grosor
            }
            $avance += $trozo

            if ($rect.Ancho -ge $MinimoLado -and $rect.Alto -ge $MinimoLado) {
                $resultado.Add([pscustomobject]@{
                    Elemento = $fila[$i]
                    X        = $rect.X
                    Y        = $rect.Y
                    Ancho    = $rect.Ancho
                    Alto     = $rect.Alto
                })
            }
        }

        # Se recorta el area libre por donde acaba de colocarse la banda.
        if ($anchoLibre -ge $altoLibre) {
            $x          += $grosor
            $anchoLibre -= $grosor
        } else {
            $y          += $grosor
            $altoLibre  -= $grosor
        }
    }

    return @($resultado)
}
