<#
.SYNOPSIS
    Que decir cuando la tabla de resultados no ensenya ninguna fila.

.DESCRIPTION
    La tabla vacia ensenyaba EL MISMO rectangulo en blanco en tres
    situaciones que no se parecen en nada: recien abierto el programa,
    analizado sin encontrar basura, y un filtro que no deja pasar ni una
    fila.

    La tercera es la peligrosa. El usuario ha analizado, ha visto seiscientas
    filas, escribe "chrome" en el cuadro de filtro, se equivoca de palabra y
    la tabla se queda en blanco. Lo que ve es indistinguible de un analisis
    que ha fallado, y lo razonable ante un programa que ha perdido los
    resultados es volver a analizar -otros cinco minutos- o cerrarlo. El dato
    que le falta no es un dato nuevo: el programa lo sabe. Solo no lo dice.

    La decision vive AQUI, en una funcion pura, y no en un DataTrigger del
    XAML, por lo mismo que se explica en la cabecera de grupo de
    Panel.Resultados.xaml: en [USO-04] un Style con DataTrigger se comporto
    de forma incoherente en Windows -el disparador se aplicaba y el valor
    por defecto no-, no se pudo averiguar por que, y aqui no hay WPF con el
    que comprobarlo. Un mecanismo que no se puede verificar no tiene sitio
    en el codigo. Esto si se puede probar entero, y la ventana se limita a
    asignar el texto que salga.

    Es la misma familia que [CNF-04] y [USO-15]: decir la verdad sobre lo
    que ha pasado. Ver [USO-09] en docs/HOJA-DE-RUTA.md.
#>

function Get-RiesgoDelFiltro {
    <#
    .SYNOPSIS
        A que nivel de riesgo corresponde cada posicion del desplegable.

    .DESCRIPTION
        Existe para que el filtro y el cartel de "no pasa nada" no puedan
        discrepar sobre si hay un filtro de riesgo puesto. Estaba escrito
        dentro del cierre que filtra, y en cuanto un segundo sitio necesito
        la misma respuesta pasaba a ser dos copias de la misma tabla; dos
        copias de una tabla acaban diciendo cosas distintas, y aqui eso se
        traduce en un boton "Quitar los filtros" que no quita el filtro que
        estorba.

        El indice es la posicion literal del ComboBox de Panel.Resultados.xaml:
        0 "Todos los riesgos", 1 bajo, 2 medio, 3 alto. Cualquier otra cosa
        -incluido el -1 de "no hay nada seleccionado"- es "todos", que es la
        respuesta que no esconde filas.

    .PARAMETER Indice
        SelectedIndex del desplegable de riesgo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int] $Indice = 0)

    switch ($Indice) {
        1 { return 'Bajo' }
        2 { return 'Medio' }
        3 { return 'Alto' }
        default { return '' }
    }
}

function Test-HayFiltroPuesto {
    <#
    .SYNOPSIS
        Hay algun filtro que pueda estar escondiendo filas.

    .DESCRIPTION
        La regla de "no hay filtro" tiene que ser LA MISMA que usa el cierre
        que instala el predicado en la vista. Si alli un cuadro con tres
        espacios cuenta como vacio -y cuenta, por IsNullOrWhiteSpace- y aqui
        contara como filtro puesto, el cartel ofreceria quitar un filtro que
        no existe y el boton no cambiaria nada al pulsarlo. Un boton que no
        hace nada es indistinguible de uno roto: es el fallo de [USO-15]
        otra vez.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $TextoFiltro,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $RiesgoFiltro
    )

    if (-not [string]::IsNullOrWhiteSpace($TextoFiltro))  { return $true }
    if (-not [string]::IsNullOrWhiteSpace($RiesgoFiltro)) { return $true }
    return $false
}

function Get-TextoQuitarFiltros {
    <#
    .SYNOPSIS
        Como se rotula el boton que quita los filtros.

    .DESCRIPTION
        El panel tiene DOS filtros: el cuadro de texto y el desplegable de
        riesgo. El boton los quita LOS DOS siempre -quitar solo uno puede
        dejar la tabla igual de vacia, y entonces el boton parece roto, que
        es justo lo que este punto viene a arreglar-, asi que el rotulo
        tiene que decir cuantos va a quitar.

        Decirlo importa porque quitar un filtro que el usuario NO se estaba
        quejando de tener tambien es una sorpresa: si solo molesta el texto
        y el boton dice "Quitar los dos filtros", el usuario sabe de
        antemano que su "Solo riesgo alto" tambien se va. Nombrar la accion
        completa cuesta tres palabras.

        Cuando solo hay uno puesto, quitar los dos y quitar ese uno son la
        misma cosa, asi que el rotulo nombra el que hay.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $TextoFiltro,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $RiesgoFiltro
    )

    $hayTexto  = -not [string]::IsNullOrWhiteSpace($TextoFiltro)
    $hayRiesgo = -not [string]::IsNullOrWhiteSpace($RiesgoFiltro)

    if ($hayTexto -and $hayRiesgo) { return 'Quitar los dos filtros' }
    if ($hayTexto)                 { return 'Quitar el filtro de texto' }
    if ($hayRiesgo)                { return 'Quitar el filtro de riesgo' }
    return 'Quitar los filtros'
}

function Get-EstadoVacio {
    <#
    .SYNOPSIS
        Que hay que decir cuando la tabla no ensenya ni una fila, y si hay
        que ofrecer quitar el filtro.

    .DESCRIPTION
        Devuelve un objeto con cinco campos:

          Vacio               si hay que ensenyar el cartel
          Caso                cual de las situaciones es (para poder probarlo)
          Texto               lo que lee el usuario
          OfrecerQuitarFiltro si procede el boton
          TextoBoton          como se rotula ese boton

        EL ORDEN DE LAS PREGUNTAS NO ES CAPRICHOSO. Se mira primero si hay
        algo a la vista, luego si la coleccion completa trae algo, y solo al
        final en que punto va el analisis. Al reves -preguntando primero por
        la fase- un analisis en marcha sobre una lista ya llena y filtrada
        diria "la lista se ira llenando sola" delante de setecientas filas
        escondidas por el filtro, que es exactamente la mentira que este
        punto viene a quitar.

        Que "Total mayor que cero y nada a la vista" signifique "hay un
        filtro" es una deduccion, no un dato, asi que se comprueba: si
        resulta que no hay ningun filtro puesto, se dice lo poco que se
        sabe con certeza y NO se ofrece un boton que no arreglaria nada.
        Esa rama no deberia ocurrir nunca; existe porque prometer una
        solucion falsa es peor que admitir que no se sabe.

    .PARAMETER Fase
        'terminado' cuando ya ha acabado un analisis en esta sesion,
        'analizando' mientras corre, cualquier otra cosa -incluido el
        vacio- significa que todavia no se ha analizado nada. El caso por
        defecto es el prudente: nunca afirma que hubo un analisis.
    .PARAMETER Total
        Elementos en la coleccion completa, los esconda o no el filtro.
    .PARAMETER HayVisibles
        Si la vista ensenya al menos una fila. Es un booleano y no una
        cuenta a proposito: la ventana lo resuelve con ICollectionView.IsEmpty,
        que no recorre nada, y esto se recalcula en cada clic de casilla.
    .PARAMETER TextoFiltro
        Lo que hay escrito en el cuadro de filtro. Puede llegar nulo.
    .PARAMETER RiesgoFiltro
        El nivel elegido en el desplegable, vacio si estan todos.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Fase,
        [Parameter(Mandatory)] [AllowNull()] [int] $Total,
        [Parameter(Mandatory)] [AllowNull()] [bool] $HayVisibles,
        [AllowNull()] [AllowEmptyString()] [string] $TextoFiltro  = '',
        [AllowNull()] [AllowEmptyString()] [string] $RiesgoFiltro = ''
    )

    if ($Total -lt 0) { $Total = 0 }

    if ($HayVisibles) {
        return [pscustomobject]@{
            Vacio               = $false
            Caso                = 'con-datos'
            Texto               = ''
            OfrecerQuitarFiltro = $false
            TextoBoton          = ''
        }
    }

    if ($Total -gt 0) {
        $cuantos = if ($Total -eq 1) { '1 elemento' } else { '{0} elementos' -f $Total }

        if (Test-HayFiltroPuesto -TextoFiltro $TextoFiltro -RiesgoFiltro $RiesgoFiltro) {
            # Parentesis alrededor de la concatenacion ANTES del -f: el -f se
            # enlaza mas fuerte que el +, asi que sin ellos solo se formatea
            # el ultimo trozo y el {0} del primero llega literal a la
            # pantalla. Ha mordido cuatro veces en este repositorio.
            $texto = ('El análisis encontró {0}, pero el filtro que tienes puesto no deja pasar ninguno. ' +
                      'La lista no está vacía: está filtrada.') -f $cuantos
            return [pscustomobject]@{
                Vacio               = $true
                Caso                = 'filtrado'
                Texto               = $texto
                OfrecerQuitarFiltro = $true
                TextoBoton          = (Get-TextoQuitarFiltros -TextoFiltro $TextoFiltro -RiesgoFiltro $RiesgoFiltro)
            }
        }

        return [pscustomobject]@{
            Vacio               = $true
            Caso                = 'oculto'
            Texto               = ('Ninguno de los {0} que encontró el análisis se está viendo en la tabla.' -f $cuantos)
            OfrecerQuitarFiltro = $false
            TextoBoton          = ''
        }
    }

    if ($Fase -eq 'analizando') {
        return [pscustomobject]@{
            Vacio               = $true
            Caso                = 'analizando'
            Texto               = 'Analizando: la lista se irá llenando sola. Todavía no ha aparecido nada.'
            OfrecerQuitarFiltro = $false
            TextoBoton          = ''
        }
    }

    if ($Fase -ne 'terminado') {
        return [pscustomobject]@{
            Vacio               = $true
            Caso                = 'sin-analizar'
            Texto               = 'Todavía no se ha analizado nada. Ve a Inicio, pulsa "Analizar el equipo" y lo que se encuentre aparecerá aquí.'
            OfrecerQuitarFiltro = $false
            TextoBoton          = ''
        }
    }

    # Analizado y sin una sola fila. Esto NO es un fallo y no se puede
    # escribir como si lo fuera: significa que no hay basura que borrar, que
    # es la mejor noticia que este programa puede dar. Se nombra ademas de
    # que depende el resultado -los modulos y los ajustes de ESTE analisis-
    # porque prometer "tu equipo esta limpio" seria pasarse: con otro perfil
    # el mismo equipo puede tener gigas.
    return [pscustomobject]@{
        Vacio               = $true
        Caso                = 'sin-resultados'
        Texto               = ('El análisis ha terminado y no ha encontrado nada que borrar. ' +
                               'No es un fallo, es una buena noticia: no hay basura que limpiar ' +
                               'con los módulos y los ajustes que has usado.')
        OfrecerQuitarFiltro = $false
        TextoBoton          = ''
    }
}
