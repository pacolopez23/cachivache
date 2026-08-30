<#
.SYNOPSIS
    Comparar el analisis de ahora con el analisis anterior.

.DESCRIPTION
    El programa guarda historial e informes desde hace tiempo, pero al
    terminar un analisis no dice NADA de lo que habia la vez pasada. El
    resumen pone "812 elementos - 3,20 GB recuperables" y el usuario no
    tiene con que compararlo: no sabe si eso es mucho, poco, o lo mismo
    que ayer. El dato existe, esta en historial.json, y solo faltaba
    decirlo. Ver [CNF-06] en docs/HOJA-DE-RUTA.md.

    Lo dificil de este punto no es restar dos numeros: es NO MENTIR al
    restarlos. Hay tres formas de mentir aqui, y las tres estan cerradas:

    1. COMPARAR CON ALGO QUE NO ES UN ANALISIS. El historial mezcla
       analisis y limpiezas. Los "Elementos" de una limpieza son los que
       se borraron, no los que se encontraron, y sus "Bytes" son espacio
       liberado, no espacio recuperable. Decir "hace 4 dias eran 12
       elementos" cuando aquello fue una limpieza de 12 archivos es
       comparar dos magnitudes distintas y presentarlas como la misma.
       Solo valen las entradas de Tipo 'analisis'.

    2. USAR UN ANALISIS INCOMPLETO COMO SI FUERA COMPLETO. Desde [CNF-04]
       el historial guarda Incompleto y Motivo. Un analisis que se
       cancelo en el modulo 7 de 21 encontro menos porque se MIRO menos,
       no porque hubiera menos. Callarlo produce exactamente la frase que
       este proyecto lleva cerrando desde [CNF-04], [USO-09] y [USO-15]:
       el programa afirmando que habia menos cuando lo que paso es que
       miro menos. Aqui se compara igual -esconder el unico dato que hay
       es su propia forma de mentir- pero DICIENDOLO.

    3. COMPARAR CIFRAS QUE NO SON EQUIPARABLES. Un analisis con el perfil
       Exhaustivo encuentra muchisimo mas que uno Conservador, y uno con
       la mitad de los modulos marcados encuentra la mitad de las cosas.
       Las dos cifras son correctas y la resta no significa nada. Se
       ensenya el dato y se dice que no es equiparable, en vez de callarlo:
       quien acaba de analizar sabe que ya analizo antes, y un hueco donde
       deberia estar la comparacion se lee como que el programa no la sabe
       hacer, que es [USO-15] otra vez.

    Cuando NO hay con que comparar -el primer analisis de siempre- no se
    dice nada. No hay un "0 elementos antes" que inventarse: antes no
    habia una medicion de cero, es que no habia medicion.

    El tiempo transcurrido lo formatean Format-Antiguedad y
    Format-Duracion, que ya estaban en Format.ps1. Un segundo formateador
    de tiempos acabaria diciendo "hace 4 dias" donde el otro dice "ayer".
#>

function Get-ReferenciaAnterior {
    <#
    .SYNOPSIS
        La ultima entrada del historial que sirve como termino de
        comparacion para un analisis.

    .DESCRIPTION
        Solo las de Tipo 'analisis'. Una limpieza cuenta otra cosa (lo
        borrado, no lo encontrado) y una entrada de tipo desconocido
        -historial.json es texto plano en una carpeta escribible- no se
        sabe que cuenta.

        La comparacion es contra la ANTERIOR, no contra la mejor ni contra
        la ultima completa. Elegir cual de los analisis pasados se ensenya
        es elegir el numero que queda mejor, y ademas dejaria al usuario
        sin saber por que un dia se compara con el martes y otro con el
        jueves. Si la anterior no vale del todo, se dice; no se cambia por
        otra.

        Se toma la ULTIMA de la lista y no la de Fecha mayor: el historial
        se escribe anyadiendo al final, asi que el orden del archivo es el
        orden real de ejecucion, y la fecha es un campo de texto que puede
        faltar o venir corrupto. Ordenar por un campo que puede estar mal
        haria que un reloj desajustado cambiara con que se compara.

    .PARAMETER Historial
        Lo que devuelve Get-Historial. Puede ser $null, estar vacio, o
        traer entradas de cualquier forma: el archivo lo escribe el
        programa pero lo puede editar cualquiera.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Historial
    )

    if ($null -eq $Historial) { return $null }

    $referencia = $null
    foreach ($entrada in @($Historial)) {
        if ($null -eq $entrada) { continue }
        # [string] sobre el campo, no el campo pelado. Si Tipo llegara
        # siendo un array, "$entrada.Tipo -eq 'analisis'" devuelve el
        # subconjunto que coincide, que al no estar vacio es verdadero y
        # la entrada colaria. Es el mismo apanyo que Get-ResumenHistorial,
        # y esta ahi porque ya paso una vez.
        if ([string]$entrada.Tipo -ne 'analisis') { continue }
        $referencia = $entrada
    }

    return $referencia
}

function Get-FraseMotivoComparacion {
    <#
    .SYNOPSIS
        Como se dice, en castellano, cada motivo por el que dos analisis
        no son equiparables.

    .DESCRIPTION
        Aparte de Get-ComparacionAnalisis para que los codigos ('incompleto',
        'otro-perfil'...) se puedan probar sin pelearse con la redaccion, y
        para que la redaccion se pueda cambiar sin tocar la decision.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Motivo
    )

    switch ($Motivo) {
        'incompleto'    { return 'quedó incompleto' }
        'otro-perfil'   { return 'usó otro perfil' }
        'otros-modulos' { return 'miró otros módulos' }
        'no-consta'     { return 'no dejó anotado del todo con qué se hizo' }
        default         { return '' }
    }
}

function Get-ComparacionAnalisis {
    <#
    .SYNOPSIS
        Que anyadirle al resumen del analisis para decir como estaba esto
        la vez anterior.

    .DESCRIPTION
        Devuelve un objeto con ocho campos:

          HayReferencia  si hay un analisis anterior con el que comparar
          Caso           'sin-referencia' | 'comparable' | 'no-equiparable'
          Motivos        por que no es equiparable, en codigos
          Fecha          la del analisis anterior, o $null si no se pudo leer
          Elementos      los que encontro aquel analisis
          Bytes          los recuperables que encontro aquel analisis
          Texto          la frase entre parentesis, o cadena vacia
          Sufijo         lo mismo, pero con el espacio de separacion delante

        Sufijo existe para que la ventana sea UNA suma y no un if. Con
        Texto a secas, quien lo pega tiene que acordarse de anyadir el
        espacio solo cuando hay algo que anyadir, y ese if es una decision
        mas viviendo fuera de aqui: el dia que alguien lo escriba mal, el
        resumen acaba con un espacio colgando o con las dos frases pegadas.
        Con Sufijo, "$resumen += $comparacion.Sufijo" es correcto tambien
        el primer dia, cuando no hay nada con que comparar y la suma no
        anyade nada.

        NO calcula la diferencia ("312 mas que la vez pasada") a proposito.
        La hoja de ruta pide como minimo viable las cifras de antes, y una
        resta obliga a decidir que se dice cuando los elementos suben y los
        bytes bajan -pasa en cuanto cambia un umbral- sin tener con que
        explicarlo. Las dos cifras puestas al lado dicen lo mismo y no
        pueden equivocarse de signo.

    .PARAMETER Historial
        Lo que devuelve Get-Historial. Tiene que leerse ANTES de anotar la
        entrada del analisis que acaba de terminar; si no, la referencia
        seria el propio analisis y el programa se compararia consigo mismo.

    .PARAMETER Perfil
        El perfil del analisis de AHORA, para saber si las cifras son
        equiparables.

    .PARAMETER Modulos
        Los modulos REVISADOS en el analisis de ahora, los mismos que se
        van a anotar en el historial.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Historial,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Perfil,
        [Parameter(Mandatory)] [AllowNull()] $Modulos
    )

    $anterior = Get-ReferenciaAnterior -Historial $Historial

    if ($null -eq $anterior) {
        # Primer analisis de siempre, o un historial que solo tiene
        # limpiezas. No se dice nada: no hay un "0 elementos antes" que
        # ensenyar, porque antes no hubo una medicion de cero, es que no
        # hubo medicion.
        return [pscustomobject]@{
            HayReferencia = $false
            Caso          = 'sin-referencia'
            Motivos       = @()
            Fecha         = $null
            Elementos     = 0
            Bytes         = 0.0
            Texto         = ''
            Sufijo        = ''
        }
    }

    # ConvertTo-DoubleSeguro y no [int]/[double] pelados: estos campos
    # salen de un JSON que puede venir de una version anterior o editado a
    # mano, y una conversion que lanza aqui se lleva por delante el final
    # del analisis. Un numero que se queda a cero se ve; un programa que
    # revienta al terminar de analizar, no se arregla.
    $elementos = [int](ConvertTo-DoubleSeguro $anterior.Elementos)
    $bytes     = ConvertTo-DoubleSeguro $anterior.Bytes
    if ($elementos -lt 0) { $elementos = 0 }
    if ($bytes -lt 0)     { $bytes = 0.0 }

    $fecha = $null
    $leida = [datetime]::MinValue
    if ([datetime]::TryParse([string]$anterior.Fecha,
                             [Globalization.CultureInfo]::InvariantCulture,
                             [Globalization.DateTimeStyles]::RoundtripKind,
                             [ref] $leida)) {
        $fecha = $leida
    }

    # La fecha se usa para decir "hace 4 dias" solo si se puede decir sin
    # mentir. Una fecha en el futuro -reloj desajustado, archivo tocado a
    # mano- daria "hace menos de 1 s" delante de un analisis de la semana
    # que viene, y una fecha de 1900 es el hueco que deja un campo que
    # falta. En los dos casos se dice "el analisis anterior" y ya esta: no
    # saber cuando fue no impide decir cuanto habia.
    $ahora    = Get-Date
    $hayCuando = $false
    $cuando    = ''
    if ($null -ne $fecha -and $fecha -gt [datetime]'1900-01-02' -and $fecha -le $ahora) {
        $transcurrido = $ahora - $fecha
        # Por debajo del dia, Format-Antiguedad solo sabe decir "hoy", que
        # delante de una cifra se lee como si fuera de ahora mismo. Los dos
        # formateadores son los de Format.ps1: aqui no se escribe ni un
        # "hace {0} dias" nuevo, porque dos formateadores de tiempo acaban
        # discrepando y el usuario ve "ayer" en un sitio y "hace 1 dia" en
        # otro.
        $cuando = if ($transcurrido.TotalDays -lt 1) {
            'hace ' + (Format-Duracion $transcurrido)
        } else {
            Format-Antiguedad -Fecha $fecha
        }
        $hayCuando = -not [string]::IsNullOrWhiteSpace($cuando)
    }

    $motivos = [Collections.Generic.List[string]]::new()

    # 1. Incompleto. Va primero porque es un defecto de la medicion misma:
    #    aquella cifra no mide bien ni siquiera su propio perfil.
    $incompleto = [bool]$anterior.Incompleto
    if ($incompleto) { $motivos.Add('incompleto') }

    $noConsta = $false

    # 2. Perfil. Solo se declara distinto si se conocen los dos; si el
    #    anterior no lo anoto, lo que pasa es que no se sabe, y decir "uso
    #    otro perfil" seria inventarse una diferencia, que es la misma
    #    familia de mentira que dar por buena una igualdad.
    $perfilAntes = ([string]$anterior.Perfil).Trim()
    $perfilAhora = if ($null -ne $Perfil) { $Perfil.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($perfilAntes) -or [string]::IsNullOrWhiteSpace($perfilAhora)) {
        $noConsta = $true
    } elseif ($perfilAntes -ne $perfilAhora) {
        $motivos.Add('otro-perfil')
    }

    # 3. Modulos, como conjunto: ni el orden ni las repeticiones significan
    #    nada, y las mayusculas tampoco.
    #
    #    Solo se miran si el anterior NO quedo incompleto. Un analisis
    #    cancelado anota los modulos REVISADOS, que son menos por estar
    #    cancelado: contarlo aparte seria decir dos veces el mismo hecho
    #    -"quedo incompleto y miro otros modulos"- y el segundo trozo suena
    #    a que el usuario cambio algo, cuando no cambio nada.
    if (-not $incompleto) {
        $modulosAntes = @(@($anterior.Modulos) |
                          Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } |
                          ForEach-Object { $_.Trim().ToLowerInvariant() } |
                          Select-Object -Unique | Sort-Object)
        $modulosAhora = @(@($Modulos) |
                          Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } |
                          ForEach-Object { $_.Trim().ToLowerInvariant() } |
                          Select-Object -Unique | Sort-Object)

        if ($modulosAntes.Count -eq 0 -or $modulosAhora.Count -eq 0) {
            $noConsta = $true
        } elseif (($modulosAntes -join '|') -ne ($modulosAhora -join '|')) {
            $motivos.Add('otros-modulos')
        }
    }

    if ($noConsta) { $motivos.Add('no-consta') }

    $caso = if ($motivos.Count -gt 0) { 'no-equiparable' } else { 'comparable' }

    # "1 elemento", nunca "1 elementos". Es la misma regla que en
    # EstadoVacio.ps1 y en Format-ResumenSimulacion; el verbo va detras
    # porque "hace 4 dias era 1 elemento" tambien tiene que concordar.
    $cuantos = if ($elementos -eq 1) { '1 elemento' } else { '{0} elementos' -f $elementos }
    $verbo   = if ($elementos -eq 1) { 'era' } else { 'eran' }

    $encabezado = if ($hayCuando) { ('{0} {1}' -f $cuando, $verbo) } else { 'el análisis anterior tenía' }

    $cola = ''
    if ($motivos.Count -gt 0) {
        $frases = @($motivos | ForEach-Object { Get-FraseMotivoComparacion -Motivo $_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $cola = ', pero aquel análisis {0}: no son cifras equiparables' -f ($frases -join ' y ')
    }

    # Parentesis alrededor de la plantilla ANTES del -f. El -f se enlaza
    # mas fuerte que el +, asi que sin ellos solo se formatearia el ultimo
    # trozo y los {0} de los primeros llegarian literales a la pantalla.
    $texto = ('({0} {1} y {2}{3})' -f $encabezado, $cuantos, (Format-Tamano $bytes), $cola)

    return [pscustomobject]@{
        HayReferencia = $true
        Caso          = $caso
        Motivos       = $motivos.ToArray()
        Fecha         = $fecha
        Elementos     = $elementos
        Bytes         = $bytes
        Texto         = $texto
        Sufijo        = (' ' + $texto)
    }
}
