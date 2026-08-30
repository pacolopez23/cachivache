<#
.SYNOPSIS
    Como se le ensenya al usuario su propia lista de "esto no se toca nunca".

.DESCRIPTION
    [CNF-01] prometia una tarjeta en Ajustes para ver y quitar exclusiones y
    nunca se hizo. Con [USO-06] se pudieron ANYADIR desde el menu contextual
    de la tabla, asi que hasta ahora la unica forma de quitar una era editar
    preferencias.json a mano: una puerta de un solo sentido abierta por el
    propio programa.

    LO QUE SE GUARDA YA NO SON SOLO RUTAS. Desde [ARQ-03] la lista mezcla dos
    formas de clave, y se distinguen a la vista:

      - La ruta, cuando el candidato tiene una de verdad.
      - "modulo:<Id>|<Nombre>" cuando no la tiene -un comando, la papelera-,
        con una barra vertical que Windows no admite en una ruta.

    Ensenyar "modulo:dockerwsl|Cache de Docker" tal cual es ensenyarle al
    usuario una cadena interna del programa y pedirle que la interprete. Pero
    la clave REAL no se puede perder: es la que hay que borrar de la lista y
    la unica que el motor de borrado compara. Por eso esta funcion devuelve
    las dos cosas por separado -lo que se lee y lo que se guarda- y quien
    pinta la tarjeta no recompone nada.

    LA DECISION VIVE AQUI, EN UNA FUNCION PURA, y no en un DataTrigger ni en
    un convertidor del XAML, por lo mismo que [USO-09] y [USO-04]: aqui no hay
    WPF con el que comprobar un mecanismo de XAML, y un mecanismo que no se
    puede verificar no tiene sitio en este repositorio. Esto se prueba entero.

    Ver [CNF-01], [USO-06] y [ARQ-03] en docs/HOJA-DE-RUTA.md.
#>

function Get-ExclusionVista {
    <#
    .SYNOPSIS
        Como se presenta UNA clave de la lista de exclusiones.

    .DESCRIPTION
        Devuelve cuatro campos:

          Clave    la cadena EXACTA que esta guardada. Es la que hay que
                   quitar de la lista y la que compara el motor.
          Titulo   lo que el usuario lee en grande.
          Detalle  que clase de exclusion es y hasta donde llega.
          Tipo     'carpeta', 'modulo' o 'texto' (para poder probarlo).

        Clave se devuelve TAL CUAL, sin normalizar, sin recortar y sin
        cambiar de mayusculas. Si se "limpiara" aqui, el boton de quitar
        pediria borrar una cadena que no esta en la lista y no quitaria nada:
        un boton que se pulsa y no hace nada es [USO-15] otra vez.

        Los tres casos:

        CARPETA. Se ensenya la ruta entera y no solo el ultimo tramo. Dos
        proyectos que se llamen "web" en carpetas distintas darian dos filas
        identicas, y la lista existe justo para poder decidir cual sobra.

        MODULO. Se ensenya el nombre que ya vio el usuario en la tabla y el
        detalle nombra el modulo. El Id es tecnico -"dockerwsl"- pero es lo
        unico que distingue dos elementos que se llamen igual en dos modulos,
        y es ademas la mitad de la clave que se esta guardando: esconderlo
        entero convertiria dos exclusiones distintas en dos filas iguales.

        TEXTO. Ni ruta ni clave sintetica. No lo produce el programa, asi que
        solo puede venir de una edicion a mano de preferencias.json o de la
        opcion -Excluir de la consola. Se ensenya tal cual y se dice que
        alcance tiene de verdad, que es el minimo: Test-ClaveExcluida compara
        una clave que no es ruta por igualdad exacta. Callarlo dejaria al
        usuario creyendo que "docker system prune" excluye algo.

    .PARAMETER Clave
        Una entrada de RutasExcluidas. Puede llegar nula o en blanco -el
        archivo lo edita gente- y entonces se devuelve $null, para que quien
        pinta la lista se la salte en vez de ensenyar una fila vacia que
        nadie sabria por que esta ahi.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Clave
    )

    if ([string]::IsNullOrWhiteSpace($Clave)) { return $null }

    if (Test-EsRutaDeVerdad -Texto $Clave) {
        return [pscustomobject]@{
            Clave   = $Clave
            Titulo  = $Clave
            Detalle = 'Ruta del disco. Si es una carpeta, queda fuera también todo lo que haya dentro.'
            Tipo    = 'carpeta'
        }
    }

    # La misma forma que compone Get-ClaveExclusion, leida al reves. El Id no
    # puede llevar barra vertical -por eso [^|]- y el nombre se queda con
    # todo lo que venga detras, incluidas mas barras si el nombre las trae.
    $partes = [regex]::Match($Clave, '^modulo:([^|]*)\|(.*)$')
    if ($partes.Success) {
        $modulo = $partes.Groups[1].Value
        $nombre = $partes.Groups[2].Value

        # Un titulo en blanco seria una fila que no se ve y que por tanto no
        # se puede quitar. Antes que eso, la clave tal cual: fea, pero
        # visible y pulsable.
        $titulo = if ([string]::IsNullOrWhiteSpace($nombre)) { $Clave } else { $nombre }
        $deQuien = if ([string]::IsNullOrWhiteSpace($modulo)) { '(sin nombre)' } else { $modulo }

        return [pscustomobject]@{
            Clave   = $Clave
            Titulo  = $titulo
            Detalle = ('Elemento del módulo «{0}»: no es una carpeta del disco, así que la exclusión vale solo para él.' -f $deQuien)
            Tipo    = 'modulo'
        }
    }

    return [pscustomobject]@{
        Clave   = $Clave
        Titulo  = $Clave
        Detalle = ('Escrito a mano: ni es una ruta ni tiene la forma de las claves que genera el programa, ' +
                   'así que solo excluye lo que se llame exactamente así.')
        Tipo    = 'texto'
    }
}

function Get-TextoListaExclusiones {
    <#
    .SYNOPSIS
        Que dice la tarjeta encima de la lista, incluida la lista vacia.

    .DESCRIPTION
        LA TARJETA VACIA TIENE QUE DECIR ALGO UTIL. Es la leccion de
        [USO-09]: un hueco en blanco donde deberia haber algo se lee como que
        el programa ha perdido los datos o como que la funcion no va. Y aqui
        el vacio es ademas el estado normal de cualquiera que abra Ajustes
        antes de haber excluido nada, o sea el primero que va a leer esto.

        Asi que el caso de cero no dice "no hay nada": dice donde esta la
        orden que llena esta lista, con su nombre exacto -"Excluir siempre
        esto"- para que se pueda buscar en el menu.

        Y los tres textos dicen que quitar de aqui NO BORRA NADA. De eso
        depende que el boton de quitar pueda no preguntar: lo que hace es
        volver a proponer algo, no destruirlo.

        Cero, uno y muchos van por separado para no escribir "1 elementos",
        que es un fallo que en este repositorio ya salio en las cabeceras de
        grupo y en el historial.

    .PARAMETER Cuantas
        Cuantas exclusiones hay. Un negativo se trata como cero: es lo unico
        que se puede decir con sentido, y desde luego mejor que ensenyar
        "Hay -1 elementos excluidos".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int] $Cuantas = 0)

    if ($Cuantas -le 0) {
        return ('Todavía no has excluido nada. Para excluir algo: en Resultados, pulsa con el botón derecho ' +
                'sobre su fila y elige «Excluir siempre esto». Aparecerá aquí, y aquí lo podrás quitar.')
    }

    if ($Cuantas -eq 1) {
        return ('Hay 1 elemento excluido. No se propone en ningún análisis y el motor de borrado lo rechaza ' +
                'aunque llegue a estar marcado. Quitarlo de la lista no borra nada: solo hace que vuelva a proponerse.')
    }

    # Parentesis alrededor de toda la concatenacion ANTES del -f: el -f se
    # enlaza mas fuerte que el +, asi que sin ellos solo se formatearia el
    # ultimo trozo y el {0} del primero llegaria literal a la pantalla. Ha
    # mordido cuatro veces en este repositorio.
    return (('Hay {0} elementos excluidos. No se proponen en ningún análisis y el motor de borrado los rechaza ' +
             'aunque lleguen a estar marcados. Quitar uno de la lista no borra nada: solo hace que vuelva a proponerse.') -f $Cuantas)
}
