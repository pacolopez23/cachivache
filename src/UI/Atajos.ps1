<#
.SYNOPSIS
    Que hace cada combinacion de teclas de la ventana. Calculo puro.

.DESCRIPTION
    Vive aparte de Window.Eventos.ps1 por el mismo motivo que Xaml.ps1 vive
    aparte de Window.ps1: aqui no se toca WPF. Entran tres datos -la tecla,
    si estaba pulsado Control y si el foco esta en un cuadro de texto- y sale
    el NOMBRE de una accion o nada. Ni un tipo de System.Windows, ni un
    control, ni un manejador. Asi las pruebas pueden recorrer las
    combinaciones enteras en un sistema donde no hay interfaz grafica, que es
    justo donde no se pueden probar los atajos de verdad.

    La regla de reparto: aqui se DECIDE, y quien llama EJECUTA. Y lo que
    ejecuta no es una copia de lo que hace el boton: levanta el evento Click
    del boton. Un atajo que repitiera el cuerpo del manejador seria una
    segunda copia de la misma decision, y este proyecto ya sabe como acaban
    las segundas copias. Ver [ARQ-01] y [A11Y-04].
#>

# Los seis paneles, en el orden en que se ven en la barra lateral.
#
# El orden es el atajo: Ctrl+1 es la primera entrada, Ctrl+6 la ultima. Si
# alguien reordena la barra lateral y no toca esta lista, Ctrl+3 lleva a un
# panel distinto del tercero que se ve, y no falla nada: simplemente pasa a
# mentir. Hay una invariante que compara las dos listas.
$script:NavegacionPorNumero = @(
    'NavInicio'      # Ctrl+1
    'NavResultados'  # Ctrl+2
    'NavRegistro'    # Ctrl+3
    'NavInformes'    # Ctrl+4
    'NavAjustes'     # Ctrl+5
    'NavAcerca'      # Ctrl+6
)

function Get-NavegacionPorNumero {
    <#
    .SYNOPSIS
        Los nombres de las seis entradas de la barra lateral, en su orden.

    .DESCRIPTION
        Se expone con una funcion y no como variable suelta porque una
        variable de script no sobrevive al dot-sourcing con la misma
        comodidad, y porque asi la invariante puede pedirla igual que la
        pide la ventana.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return $script:NavegacionPorNumero
}

function Get-AtajoDeTecla {
    <#
    .SYNOPSIS
        Que accion corresponde a una tecla, o nada si esa tecla no es atajo.

    .PARAMETER Tecla
        El nombre de la tecla tal y como lo da WPF: 'F5', 'Escape', 'A',
        'D1'..'D6' para los numeros de arriba y 'NumPad1'..'NumPad6' para
        los del teclado numerico. Se admiten los dos porque para el usuario
        son la misma tecla, y descubrir que el atajo "no funciona" segun
        donde pulses el 3 es exactamente la clase de detalle que hace que
        alguien deje de usar los atajos.

    .PARAMETER Control
        Si estaba pulsado Control.

    .PARAMETER EnCuadroDeTexto
        Si el foco esta dentro de un cuadro de texto. Solo cambia una cosa,
        y por eso es un dato y no cuatro condiciones repartidas: Ctrl+A ya
        significa "selecciona todo el texto" dentro de un cuadro, y el
        registro de la sesion ES un cuadro de texto, asi que robarle Ctrl+A
        dejaria al usuario sin forma de seleccionar el registro para
        copiarlo. Los demas atajos no chocan con nada que un cuadro de texto
        haga por su cuenta.

    .OUTPUTS
        El nombre de la accion, o $null si la tecla no es ningun atajo. Lo
        segundo es el caso normal: por aqui pasa cada tecla que se pulsa en
        la ventana, incluida cada letra que se escribe en el filtro.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # AllowNull y AllowEmptyString: por aqui pasa todo lo que teclee el
        # usuario, y una tecla sin nombre no es un error de programacion del
        # que haya que avisar, es una tecla que no es atajo. Sin esto,
        # Mandatory rechaza el nulo con una excepcion en mitad de un
        # manejador de teclado, que es el peor sitio para lanzar.
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Tecla,
        [switch] $Control,
        [switch] $EnCuadroDeTexto
    )

    if ([string]::IsNullOrWhiteSpace($Tecla)) { return $null }

    if (-not $Control) {
        # F5 y Escape van sin modificador, y tampoco chocan con nada que
        # haga un cuadro de texto, asi que valen escribiendo.
        switch ($Tecla) {
            'F5'     { return 'Analizar' }
            'Escape' { return 'Cancelar' }
        }
        return $null
    }

    switch ($Tecla) {
        'F' { return 'Filtrar' }
        'A' {
            # El unico choque real de toda la lista.
            if ($EnCuadroDeTexto) { return $null }
            return 'MarcarTodo'
        }
    }

    # Ctrl+1..6, con los numeros de arriba o los del teclado numerico.
    $m = [regex]::Match($Tecla, '^(?:D|NumPad)([1-6])$')
    if ($m.Success) {
        return $script:NavegacionPorNumero[[int]$m.Groups[1].Value - 1]
    }

    return $null
}
