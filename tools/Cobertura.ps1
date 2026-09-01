<#
.SYNOPSIS
    El suelo de cobertura y el veredicto sobre si se ha bajado de el.
    Calculo puro.

.DESCRIPTION
    Aparte de Probar.ps1 por el mismo motivo que Banco-Decisiones.ps1 vive
    aparte de Banco-Pruebas.ps1: esto se puede dot-sourcear sin
    consecuencias y por tanto se puede probar. Aqui no se mide nada ni se
    ejecuta ninguna prueba; entran porcentajes ya medidos y sale una lista
    de motivos.

    QUE ES UN SUELO Y QUE NO ES
    ---------------------------
    Es un trinquete: la cobertura solo puede subir. No es un objetivo ni
    una nota. Y sobre todo NO ES UNA MEDIDA DE CALIDAD: que una linea se
    haya ejecutado no dice que haga lo correcto. El fallo del ValidateSet
    del historial vivia en una linea perfectamente cubierta, y el de los
    informes que se anunciaban guardados sin escribirse tambien. Lo que de
    verdad protege este proyecto son las invariantes y la verificacion por
    mutacion; esto solo impide que un trozo entero del programa se quede
    sin ejecutar nunca, como le paso a src/Cli durante toda su vida.

    POR CARPETA Y NO SOLO EL TOTAL
    ------------------------------
    Un unico numero total se puede subir escribiendo pruebas faciles de la
    parte que ya estaba bien, mientras la parte dificil se pudre. Con un
    suelo por carpeta, cada trozo responde de si mismo.

    POR QUE src/UI ESTA AL 5 % Y SU SUELO ES 5
    ------------------------------------------
    Porque ahi no hay nada que ejecutar sin WPF: no hay ventana, ni
    DataGrid, ni lector de pantalla. Ese 95 % no lo cubre ninguna prueba
    que se pueda escribir aqui; lo cubren docs/PRUEBA-MANUAL.md, la
    integracion continua en Windows y el banco de la maquina virtual.
    Subir ese suelo exige otra maquina, no otra prueba.
#>

function Get-SueloCobertura {
    <#
    .SYNOPSIS
        El minimo exigible, en porcentaje, para el total y para cada
        carpeta de src.

    .DESCRIPTION
        Los numeros son los medidos el 31 de agosto de 2026, redondeados
        hacia abajo y con un punto de margen. El margen no es pereza: la
        cobertura de un mismo arbol varia un pelo entre PowerShell 5.1 y 7
        -hay ramas que solo existen en una version-, y un trinquete que
        salta por ese pelo se acaba desactivando, que es la peor forma de
        perderlo.

        Se expone con una funcion y no como variable suelta para que la
        pida igual quien mide y quien lo prueba.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # EL SUELO ES EL DEL PEOR SISTEMA, NO EL DEL QUE TENGAS DELANTE.
    #
    # Esto se aprendio a la primera: los numeros se fijaron midiendo en
    # Linux, y la integracion continua -que mide en Windows- tumbo el
    # trabajo por src/Modules. Y tenia razon en tumbarlo: hay modulos cuyo
    # codigo solo se ejecuta en uno de los dos sistemas, asi que la misma
    # suite cubre porcentajes distintos segun donde corra. Un suelo puesto
    # con la medida del sistema mas generoso no es un trinquete: es un
    # trabajo que falla los lunes.
    # ASI SE SUBEN, Y ASI SE SUBIERON EL 1 DE SEPTIEMBRE DE 2026.
    #
    # Ese dia se pago la deuda de pruebas entera: 23 funciones que no
    # nombraba ninguna prueba, 227 pruebas nuevas. En Linux el total paso
    # a 66,1 y Core a 88,6, y la tentacion era subir los suelos en ese
    # mismo momento.
    #
    # No se hizo hasta tener LAS DOS MEDIDAS, por el parrafo de aqui
    # arriba. Se subieron cuando la integracion continua publico la de
    # Windows, y con esta receta: el MENOR de los dos sistemas en cada
    # fila, menos un punto de margen. Windows resulto cubrir MAS que Linux
    # en las cuatro filas, asi que el que manda es Linux.
    #
    # Los comentarios llevan las dos medidas a proposito. Cuando vuelvan a
    # subir, se repite la receta: no se toca este archivo con una sola
    # medida delante.
    return @{
        'total'   = 65    # Linux 66,1   Windows 66,8
        'Core'    = 87    # Linux 88,6   Windows 89,4
        'Modules' = 64    # Linux 65,4   Windows 66,6
        'Cli'     = 88    # Linux 89,4   Windows 89,4 - estaba a 0 hasta el 31 de agosto de 2026
        'UI'      = 4     # Linux  5,1   Windows  5,1 - aqui no hay WPF; ver la cabecera
    }
}

function Test-CoberturaSuficiente {
    <#
    .SYNOPSIS
        Los motivos por los que la cobertura medida no vale. Vacio si vale.

    .PARAMETER Medido
        Tabla carpeta -> porcentaje, con una clave 'total'. Las claves
        distinguen mayusculas igual que los nombres de carpeta.

    .OUTPUTS
        Una lista de cadenas. Vacia significa que todo esta en orden, que
        es el unico caso en el que quien llama puede seguir.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [hashtable] $Medido
    )

    $suelo   = Get-SueloCobertura
    $motivos = [Collections.Generic.List[string]]::new()

    if ($null -eq $Medido -or $Medido.Count -eq 0) {
        # "No he medido nada" NO puede dar el mismo resultado que "todo
        # bien". Es el sintoma de que la medicion fallo, y sin esta linea
        # seria indistinguible de un exito.
        $motivos.Add('No hay ninguna medida de cobertura: la medicion no se ha llegado a hacer.')
        return $motivos.ToArray()
    }

    foreach ($clave in ($suelo.Keys | Sort-Object)) {
        if (-not $Medido.ContainsKey($clave)) {
            # Falta una carpeta que el suelo exige. Pasa si alguien la
            # renombra o la borra, y callarlo significaria dar por buena
            # una cobertura que ya no se esta midiendo.
            $motivos.Add(("Falta la cobertura de '{0}', que el suelo exige. .Se ha renombrado o borrado?" -f $clave))
            continue
        }
        $valor = [double] $Medido[$clave]
        if ($valor -lt [double] $suelo[$clave]) {
            $motivos.Add(('{0}: {1:N1}% y el suelo es {2}%. La cobertura solo puede subir.' -f `
                          $clave, $valor, $suelo[$clave]))
        }
    }

    foreach ($clave in ($Medido.Keys | Sort-Object)) {
        if (-not $suelo.ContainsKey($clave)) {
            # Una carpeta nueva sin suelo entraria en el proyecto sin que
            # nadie decidiera cuanto hay que probarla. Se exige la
            # decision, no un numero concreto.
            $motivos.Add(("'{0}' no tiene suelo. Añádelo a Get-SueloCobertura con el valor medido." -f $clave))
        }
    }

    return $motivos.ToArray()
}
