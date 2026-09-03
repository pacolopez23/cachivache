<#
.SYNOPSIS
    Como se recorre una lista larga de filas sin dejar la ventana colgada.
    Calculo puro.

.DESCRIPTION
    Vive aparte por el mismo motivo que Atajos.ps1 y Posicion.ps1: aqui no
    se toca WPF. Entra un numero de filas y sale un plan. Ni un tipo de
    System.Windows, ni un control, ni un manejador. La regla de reparto es
    la de siempre: aqui se DECIDE, y quien llama EJECUTA.

    POR QUE HACE FALTA · [VEL-03]
    -----------------------------
    "Marcar todo", "Desmarcar todo" y "Solo lo seguro" recorren la vista
    entera de un tiron, en el hilo de la interfaz, poniendo Seleccionado en
    cada fila. Cada una de esas asignaciones dispara PropertyChanged, y WPF
    tiene que atenderlo. Con 119 filas no se nota nada. Con 5.000 -un disco
    con muchos duplicados, o un perfil exhaustivo- la ventana se queda
    congelada varios segundos: no repinta, no responde al raton, y Windows
    puede llegar a ofrecer cerrarla. El usuario no ve un programa
    trabajando: ve un programa roto.

    LO QUE NO SE ARREGLA TROCEANDO, Y HAY QUE SABERLO
    -------------------------------------------------
    Trocear hace que la ventana RESPONDA mientras marca, y eso tiene un
    filo: si responde, tambien acepta clics. Mientras se marcan 5.000
    filas, el boton de eliminar sigue ahi. Por eso el plan no es solo
    "cuantos trozos": quien ejecuta tiene que apagar los botones que
    pueden hacer danyo mientras dura, y volver a encenderlos al final.
    Congelada, la ventana estaba protegida por accidente; respondiendo, hay
    que protegerla a proposito.

    POR QUE UN UMBRAL Y NO TROCEAR SIEMPRE
    --------------------------------------
    Dejar respirar a la ventana entre trozos cuesta tiempo: es una vuelta
    al despachador por trozo. Con pocas filas, eso hace MAS LENTO lo que
    hoy es instantaneo, y ademas mete un parpadeo donde no habia ninguno.
    Por debajo del umbral se hace de una sola vez, exactamente como se
    hacia antes: el caso normal no cambia en nada.
#>

function Get-PlanMarcadoEnLote {
    <#
    .SYNOPSIS
        Como trocear el marcado de N filas, o si no hay que trocearlo.

    .PARAMETER Total
        Cuantas filas hay que recorrer.

    .PARAMETER Umbral
        A partir de cuantas filas se trocea. Por debajo se hace de una vez.

    .PARAMETER Tamano
        Cuantas filas por trozo cuando se trocea.

    .NOTES
        LA PROPIEDAD QUE IMPORTA, y la que prueba la invariante: los trozos
        tienen que cubrir EXACTAMENTE las Total filas. Ni una de menos -una
        fila sin marcar que el usuario cree marcada es justo la clase de
        mentira que este programa no se puede permitir- ni una de mas.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Total,
        [int] $Umbral = 2000,
        [int] $Tamano = 500
    )

    # Ante cualquier cosa que no sea un numero utilizable se contesta "no
    # hay nada que hacer". Esto se llama desde un manejador de clic: que
    # lance ahi deja la ventana con el manejador reventado y sin decir
    # nada, que es peor que no marcar.
    $n = 0
    if ($null -ne $Total) {
        try { $n = [int]$Total } catch { $n = 0 }
    }
    if ($n -le 0) {
        return [pscustomobject]@{
            Total = 0; PorTrozos = $false; Tamano = 0; Trozos = 0; Umbral = $Umbral
        }
    }

    # Un umbral o un tamanyo imposibles no pueden dejar el plan en un
    # bucle infinito ni en cero trozos: se caen a los valores de siempre.
    if ($Umbral -lt 1) { $Umbral = 2000 }
    if ($Tamano -lt 1) { $Tamano = 500 }

    if ($n -le $Umbral) {
        # De una sola vez, como toda la vida. Se devuelve igualmente un
        # plan completo -un trozo del tamanyo justo- para que quien llama
        # no tenga que escribir dos caminos distintos.
        return [pscustomobject]@{
            Total = $n; PorTrozos = $false; Tamano = $n; Trozos = 1; Umbral = $Umbral
        }
    }

    $trozos = [int][Math]::Ceiling($n / [double]$Tamano)
    return [pscustomobject]@{
        Total = $n; PorTrozos = $true; Tamano = $Tamano; Trozos = $trozos; Umbral = $Umbral
    }
}

function Get-RangosDeLote {
    <#
    .SYNOPSIS
        Los tramos concretos de un plan: desde donde y cuantas filas.

    .DESCRIPTION
        Existe para que la comprobacion de "cubren exactamente Total" se
        pueda hacer sobre los tramos DE VERDAD y no sobre la aritmetica
        que uno cree que hizo. El ultimo tramo casi nunca mide lo mismo
        que los demas, y ese es el sitio exacto donde se pierde una fila.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)] [AllowNull()] $Plan)

    if ($null -eq $Plan -or [int]$Plan.Total -le 0) { return @() }

    $tramos = [Collections.Generic.List[object]]::new()
    $desde = 0
    while ($desde -lt [int]$Plan.Total) {
        $cuantas = [Math]::Min([int]$Plan.Tamano, [int]$Plan.Total - $desde)
        $tramos.Add([pscustomobject]@{ Desde = $desde; Cuantas = $cuantas })
        $desde += $cuantas
    }
    return $tramos.ToArray()
}
