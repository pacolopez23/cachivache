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

    return @{
        'total'   = 59    # medido 60,6
        'Core'    = 84    # medido 85,0
        'Modules' = 63    # medido 64,7
        'Cli'     = 86    # medido 87,5 - estaba a 0 hasta el 31 de agosto de 2026
        'UI'      = 4     # medido  5,1 - aqui no hay WPF; ver la cabecera
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
