<#
.SYNOPSIS
    Decisiones puras de geometria de la ventana: que desplazamiento y que
    seleccion se recuperan al reenganchar la tabla ([USO-10]), y hasta
    donde puede crecer un dialogo sin salirse de la pantalla ([A11Y-02]).

.DESCRIPTION
    Vive aparte por el mismo motivo que Atajos.ps1 vive aparte de
    Window.Eventos.ps1: aqui no se toca WPF. Entran dos numeros y dos
    banderas, y sale un plan. Ni un tipo de System.Windows, ni un control,
    ni un manejador. Asi las pruebas pueden recorrer los casos raros -el
    desplazamiento guardado que ya no cabe, el desplazador que todavia no
    ha medido nada y contesta NaN- en un sistema donde no hay interfaz
    grafica, que es justo donde esto no se puede probar de verdad.

    La regla de reparto es la de siempre: aqui se DECIDE, y quien llama
    EJECUTA. Ver [ARQ-01] y [A11Y-04].

    POR QUE HACE FALTA
    ------------------
    La tabla de resultados se DESENGANCHA y se vuelve a enganchar
    -ItemsSource a $null y otra vez a la coleccion- en dos sitios, y los
    dos tienen su motivo escrito donde estan:

      1. Al terminar cada modulo del analisis (Window.Analisis.ps1), para
         que el DataGrid no reagrupe y repinte una vez por cada fila.
      2. Al cambiar de tema (Window.Ayudantes.ps1), porque los colores
         viajan como cadenas que no notifican cambios y los contenedores
         reciclados no vuelven a evaluar sus enlaces.

    Las dos cosas son correctas. Las dos tienen el mismo efecto
    secundario: WPF regenera la lista desde cero, asi que el
    desplazamiento vuelve arriba y la seleccion se pierde. Con veinte
    filas no se nota; con quince mil y un analisis de dos minutos, cada
    modulo que termina te devuelve al principio mientras estas leyendo la
    fila doscientos. Ver [USO-10].

    LO QUE ESTE ARCHIVO NO HACE, Y ES DELIBERADO
    --------------------------------------------
    No decide llevar la tabla hasta la fila seleccionada. Restaurar la
    seleccion y ademas desplazarse hasta ella son dos cosas distintas, y
    la segunda se pelea con la primera: si alguien marco una fila y luego
    se fue a leer mil filas mas abajo, su sitio es donde esta mirando, no
    donde dejo la marca. Hay una invariante que prohibe que aparezca un
    ScrollIntoView en el camino de restauracion.
#>

function Get-DesplazamientoRestaurado {
    <#
    .SYNOPSIS
        A que altura volver, dado lo que habia antes y lo que cabe ahora.

    .DESCRIPTION
        Es un recorte, y el recorte es el punto entero de la funcion: el
        desplazamiento guardado se midio contra una lista que ya no
        existe. Normalmente la lista nueva es mas larga -acaba de
        terminar un modulo- y el valor cabe entero; pero si mientras
        tanto se puso un filtro que esconde la mitad, el guardado apunta
        a un sitio que ya no hay.

    .PARAMETER Guardado
        Lo que valia el desplazamiento vertical antes de desenganchar.

    .PARAMETER Maximo
        Lo que se puede desplazar ahora mismo. Cero significa que la
        lista entera cabe en pantalla y no hay nada que restaurar.

    .OUTPUTS
        El desplazamiento a aplicar. Cero significa "arriba del todo", que
        es exactamente lo que pasaria sin esta funcion: el caso de no
        hacer nada y el de no saber dan el mismo resultado a proposito.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [double] $Guardado,
        [Parameter(Mandatory)] [double] $Maximo
    )

    # NaN e infinito no son casos de laboratorio: un desplazador al que
    # todavia no le ha llegado una pasada de medida contesta cosas asi, y
    # por aqui se pasa una vez por modulo desde el primero, cuando la
    # ventana puede llevar abierta medio segundo.
    #
    # Y hay que sacarlos por arriba, antes que ninguna comparacion, porque
    # NaN las envenena todas: "NaN -gt 0" y "NaN -le 0" son las DOS falsas,
    # de modo que sin esta guarda el valor se colaria por en medio de los
    # dos "if" siguientes y llegaria intacto a ScrollToVerticalOffset.
    foreach ($n in @($Guardado, $Maximo)) {
        if ([double]::IsNaN($n) -or [double]::IsInfinity($n)) { return 0.0 }
    }

    # Un guardado negativo no deberia existir, pero si existiera y se
    # devolviera tal cual, WPF lo recortaria a cero por su cuenta y en
    # silencio. Se recorta aqui para que lo que decide sea esta funcion,
    # que es la que se puede probar.
    if ($Guardado -le 0 -or $Maximo -le 0) { return 0.0 }
    if ($Guardado -ge $Maximo) { return [double] $Maximo }
    return [double] $Guardado
}

function Get-PlanRestauracionTabla {
    <#
    .SYNOPSIS
        Que hay que restaurar tras reenganchar la tabla: las dos cosas,
        una, o ninguna.

    .DESCRIPTION
        Devuelve siempre un plan, nunca nada. "No hay nada que hacer" es
        una respuesta del plan (HayQueHacerAlgo a $false) y no un $null
        que quien llama tenga que comprobar antes de mirar dentro.

    .PARAMETER Guardado
        El desplazamiento vertical de antes de desenganchar.

    .PARAMETER Maximo
        Lo que se puede desplazar ahora, ya con las filas nuevas dentro.

    .PARAMETER HabiaSeleccion
        Si habia una fila seleccionada cuando se guardo.

    .PARAMETER SeleccionVisible
        Si esa fila SIGUE pasando el filtro que hay puesto ahora mismo.
        Va aparte de HabiaSeleccion porque son dos preguntas distintas y
        la segunda solo tiene sentido si la primera es que si.

        Restaurar una seleccion que el filtro esconde deja al DataGrid con
        algo marcado que nadie ve, y a "Abrir la ubicacion", al menu
        contextual y a la tecla Intro actuando sobre una fila invisible:
        el usuario pediria abrir una carpeta y se le abriria otra. Por eso
        una seleccion escondida NO se restaura, y no restaurarla es
        justamente dejarla a nada, que es lo que ya hizo el reenganche.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [double] $Guardado,
        [Parameter(Mandatory)] [double] $Maximo,
        [switch] $HabiaSeleccion,
        [switch] $SeleccionVisible
    )

    $desplazamiento = Get-DesplazamientoRestaurado -Guardado $Guardado -Maximo $Maximo
    $restaurarSeleccion = [bool] ($HabiaSeleccion -and $SeleccionVisible)

    return [pscustomobject] @{
        Desplazamiento     = $desplazamiento
        RestaurarSeleccion = $restaurarSeleccion
        # Para que quien llama pueda no tocar nada en el caso normal, que
        # es el de alguien que no esta mirando la tabla mientras se
        # analiza: sin desplazamiento y sin seleccion, restaurar es
        # escribir los mismos valores que ya hay.
        HayQueHacerAlgo    = ($desplazamiento -gt 0) -or $restaurarSeleccion
    }
}

function Get-AlturaMaximaDialogo {
    <#
    .SYNOPSIS
        Hasta donde puede crecer un dialogo sin salirse de la pantalla.
        Calculo puro: entra el alto util del escritorio, sale un maximo.

    .DESCRIPTION
        EL AGUJERO QUE TAPA, y es un agujero DENTRO de un arreglo anterior.

        [A11Y-03] arreglo que el dialogo de confirmacion creciera hasta
        dejar sus botones fuera de la pantalla, y lo hizo poniendo
        MaxHeight="760" en el XAML. El comentario que acompanya ese numero
        dice: "es la altura util de un portatil de 768 px, que es el caso
        peor comun".

        Y ahi esta el fallo. En un portatil de 1366x768 AL 150% -que es
        justo la maquina de la que habla [A11Y-02]- la pantalla no mide
        768 puntos: mide 512. WPF trabaja en puntos independientes del
        dispositivo, no en pixeles. Asi que 760 es mas alto que la
        pantalla entera y el tope no topa nada: el arreglo de [A11Y-03] no
        funciona precisamente en la maquina que [A11Y-02] describe.

        El comentario del XAML tenia razon en una cosa: el XAML no sabe
        cuanta pantalla hay. Pero PowerShell si -SystemParameters.WorkArea
        ya viene en puntos y ya descuenta la barra de tareas-, asi que la
        respuesta no era elegir mejor el numero fijo, era no fijarlo.

        El margen no es adorno: WorkArea descuenta la barra de tareas pero
        no los bordes de la ventana ni la sombra, y un dialogo que llega
        justo al borde parece cortado aunque quepa.

    .PARAMETER AltoAreaUtil
        Alto del area de trabajo del escritorio, en puntos. Lo da
        [System.Windows.SystemParameters]::WorkArea.Height.

    .PARAMETER Margen
        Lo que se deja libre arriba y abajo entre los dos.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [double] $AltoAreaUtil,
        [double] $Margen = 48
    )

    # Ante un dato imposible se devuelve el minimo util y NO se lanza: esto
    # se llama justo antes de enseñar el dialogo que frena un borrado, y
    # que ese dialogo no aparezca es peor que cualquier tamanyo raro.
    if ([double]::IsNaN($AltoAreaUtil) -or [double]::IsInfinity($AltoAreaUtil) -or
        $AltoAreaUtil -le 0) {
        return 320.0
    }

    $alto = $AltoAreaUtil - $Margen

    # Suelo: por debajo de esto el dialogo no puede enseñar ni el resumen
    # ni los botones, y mas vale que se salga un poco a que sea inutil.
    if ($alto -lt 320) { return 320.0 }

    # Techo: en un monitor de 4K un dialogo de 2000 puntos de alto es
    # ilegible. Lo que crece dentro es una lista que ya se desplaza sola.
    if ($alto -gt 760) { return 760.0 }

    return [double] $alto
}
