<#
.SYNOPSIS
    Vista de archivos: la capa de consulta sobre el índice de disco.

.DESCRIPTION
    El índice (Indice.ps1) ya sabe QUÉ hay en el disco. Lo que faltaba era
    poder PREGUNTARLE: ordéname esto por tamaño, búscame *.tmp, dame los
    cincuenta primeros. Eso es lo que hace WizTree y lo que aquí no se
    podía hacer. Ver [VIS-02] en docs/HOJA-DE-RUTA.md.

    -------------------------------------------------------------------
    ESTO ES INFORMATIVO. NO PROPONE BORRAR NADA.

    Es la regla mas importante de este archivo y por eso esta la primera.
    Esta vista existe para ENSENYAR el disco, no para limpiarlo: un
    archivo enorme puede ser la copia de seguridad de la que depende
    todo. Cachivache solo propone borrar lo que un modulo ha reconocido
    como basura, con su motivo y su riesgo; aqui no hay ni motivo ni
    riesgo porque no hay juicio ninguno, solo tamanyos.

    De ahi que Get-VistaArchivos COPIE cada fila a un objeto con solo los
    campos de mostrar. Si devolviera las filas tal cual, cualquier cosa
    que el llamante hubiera colgado de ellas -Seleccionado, Riesgo,
    Metodo- viajaria hasta la tabla, y una fila con Seleccionado es una
    fila que la ventana sabe marcar. La unica forma de que eso no pase
    nunca es que la propiedad no exista. Hay una invariante.

    -------------------------------------------------------------------
    POR QUE NO SE USA -like

    Buscar con comodines parece un caso claro de -like, y no lo es:
    -like interpreta ademas [ y ] como clases de caracteres. Un usuario
    que busque "foto[1].jpg" -un nombre normalisimo, el que pone el
    navegador a la segunda descarga- pide sin saberlo "foto, y detras un
    1, y detras .jpg", asi que no encuentra su archivo y no tiene forma
    de entender por que. Ya mordio una vez en el cuadro de filtro de la
    tabla de resultados, donde se cambio -like por IndexOf ordinal; ver
    el comentario de src/UI/Window.Ayudantes.ps1 y docs/RENDIMIENTO.md.

    Aqui no vale IndexOf, porque aqui los comodines SI se quieren. Asi
    que el patron se traduce a expresion regular escapandolo TODO menos
    * y ?, que son los dos unicos caracteres con significado.
#>

function Get-OrdenesVistaArchivos {
    <#
    .SYNOPSIS
        Los criterios de orden que entiende la vista.
    .DESCRIPTION
        Existe para que la lista viva en UN solo sitio. Dos ValidateSet
        copiados a mano son dos listas que acaban divergiendo, y entonces
        el resumen describe un orden que la consulta no ha aplicado. Hay
        una invariante que compara los ValidateSet contra esto.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @('Tamano', 'Nombre')
}

function Test-CoincideComodin {
    <#
    .SYNOPSIS
        ¿Casa este nombre con este patrón de comodines?

    .DESCRIPTION
        * es "cualquier cosa" y ? es "un caracter cualquiera". TODO lo
        demas es literal, corchetes incluidos. Ver la cabecera.

    .PARAMETER Nombre
        Nombre de archivo. Nulo se trata como cadena vacia.
    .PARAMETER Patron
        Patron de busqueda. Vacio o solo espacios casa con todo: no
        buscar nada no es lo mismo que buscar la cadena vacia.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Nombre,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Patron
    )

    if ([string]::IsNullOrWhiteSpace($Patron)) { return $true }

    # Windows no deja que un nombre empiece ni acabe por espacio, asi que
    # recortarlos no puede perder ninguna coincidencia real; y en cambio
    # un espacio pegado al final de un patron pegado desde otro sitio
    # dejaria la busqueda a cero sin decir por que.
    $limpio = $Patron.Trim()
    if ($limpio.Length -eq 0) { return $true }

    $constructor = [Text.StringBuilder]::new()
    [void]$constructor.Append('^')

    $asteriscoAnterior = $false
    foreach ($caracter in $limpio.ToCharArray()) {
        if ($caracter -eq [char]'*') {
            # Varios asteriscos seguidos son un solo asterisco. No es
            # cosmetica: cada .* que se anyade multiplica el trabajo del
            # motor cuando el patron NO casa, y un usuario que aporree la
            # tecla no deberia poder colgar la ventana.
            if (-not $asteriscoAnterior) { [void]$constructor.Append('.*') }
            $asteriscoAnterior = $true
            continue
        }
        $asteriscoAnterior = $false

        if ($caracter -eq [char]'?') {
            [void]$constructor.Append('.')
            continue
        }

        # Regex.Escape sobre el caracter suelto: es lo que convierte [, ],
        # (, ., + y compania en texto literal, que es justo lo que -like no
        # hace con los corchetes.
        [void]$constructor.Append([regex]::Escape([string]$caracter))
    }

    [void]$constructor.Append('$')

    $opciones = ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                 [Text.RegularExpressions.RegexOptions]::CultureInvariant)

    # CultureInvariant y no la cultura del sistema: sin el, la I turca no
    # es la minuscula de i y una busqueda deja de encontrar archivos en un
    # Windows en turco. Es gratis y evita un fallo imposible de reproducir.
    $texto = $Nombre
    if ($null -eq $texto) { $texto = '' }

    return [regex]::IsMatch($texto, $constructor.ToString(), $opciones)
}

function Get-VistaArchivos {
    <#
    .SYNOPSIS
        Consulta sobre el índice: busca, ordena y recorta.

    .DESCRIPTION
        Devuelve filas para MOSTRAR, nunca candidatos. Ver la cabecera.

    .PARAMETER Indice
        Lo que devuelve New-IndiceDisco. Nulo devuelve lista vacia: la
        vista se pinta antes de que haya analisis.
    .PARAMETER Buscar
        Patron de nombre con comodines. Vacio no filtra.
    .PARAMETER Cuantos
        Cuantas filas devolver. Cero o menos devuelve ninguna.
    .PARAMETER Orden
        Tamano (de mayor a menor) o Nombre (alfabetico).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Indice,
        [AllowNull()] [AllowEmptyString()] [string] $Buscar = '',
        [int] $Cuantos = 50,
        [ValidateSet('Tamano', 'Nombre')] [string] $Orden = 'Tamano'
    )

    if ($null -eq $Indice) { return @() }
    if ($Cuantos -le 0) { return @() }

    $crudos = $Indice.Archivos
    if ($null -eq $crudos) { return @() }

    $coincidentes = [Collections.Generic.List[object]]::new()
    foreach ($fila in $crudos) {
        if ($null -eq $fila) { continue }
        if (Test-CoincideComodin -Nombre $fila.Nombre -Patron $Buscar) {
            $coincidentes.Add($fila)
        }
    }
    if ($coincidentes.Count -eq 0) { return @() }

    if ($Orden -eq 'Nombre') {
        # Desempate por tamanyo para que dos archivos con el mismo nombre
        # en carpetas distintas salgan siempre en el mismo orden. Sin el,
        # la lista baila entre pasadas y parece que el analisis cambia.
        $ordenados = @($coincidentes |
            Sort-Object -Property @{ Expression = { [string]$_.Nombre } },
                                  @{ Expression = { [double]$_.Bytes }; Descending = $true })
    } else {
        # Por BYTES, y con la conversion escrita a mano. Ordenar por el
        # texto ya formateado es un fallo que en este proyecto ya salio:
        # "9,52 GB" es alfabeticamente MENOR que "980 MB", asi que la
        # lista de los mayores empezaba por los medianos.
        $ordenados = @($coincidentes |
            Sort-Object -Property @{ Expression = { [double]$_.Bytes }; Descending = $true },
                                  @{ Expression = { [string]$_.Ruta } })
    }

    $recortados = @($ordenados | Select-Object -First $Cuantos)

    # La copia. Solo campos de mostrar: ni Seleccionado, ni Riesgo, ni
    # Metodo, ni ModuloId. Ver la cabecera y la invariante.
    $salida = [Collections.Generic.List[object]]::new()
    foreach ($fila in $recortados) {
        $salida.Add([pscustomobject]@{
            Ruta      = [string]$fila.Ruta
            Nombre    = [string]$fila.Nombre
            Carpeta   = [string]$fila.Carpeta
            Extension = [string]$fila.Extension
            Bytes     = [double]$fila.Bytes
            Ultimo    = $fila.Ultimo
        })
    }

    return @($salida)
}

function Get-ResumenVistaArchivos {
    <#
    .SYNOPSIS
        El texto honesto de lo que se está enseñando.

    .DESCRIPTION
        Tres situaciones que sin esto se ven como el mismo hueco, y la
        tercera es la peligrosa porque hace creer que el analisis fallo:

          (a) No hay ningun archivo por encima del umbral. El disco esta
              lleno de cosas pequenyas; el analisis fue bien.
          (b) Hay archivos, pero ninguno casa con la busqueda. El fallo
              esta en lo que se escribio, no en el analisis.
          (c) Hay mas de los que se ensenyan. Esta es la que enganya: el
              usuario ve cincuenta lineas y cree que eso es todo lo que
              hay, o -si buscaba algo concreto y no esta- que no existe.

        Cero, uno y muchos van por separado, para no escribir "1
        elementos" como ya paso en las cabeceras de grupo y en el
        historial.

    .PARAMETER Indice
        Lo que devuelve New-IndiceDisco. Nulo se cuenta como sin nada.
    .PARAMETER Buscar
        El mismo patron que se le paso a Get-VistaArchivos.
    .PARAMETER Cuantos
        Las mismas filas que se le pidieron a Get-VistaArchivos.
    .PARAMETER Orden
        El mismo orden. Decide si se puede decir "los mayores".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Indice,
        [AllowNull()] [AllowEmptyString()] [string] $Buscar = '',
        [int] $Cuantos = 50,
        [ValidateSet('Tamano', 'Nombre')] [string] $Orden = 'Tamano'
    )

    $crudos = $null
    if ($null -ne $Indice) { $crudos = $Indice.Archivos }

    $total = 0
    $coinciden = 0
    foreach ($fila in @($crudos)) {
        if ($null -eq $fila) { continue }
        $total++
        if (Test-CoincideComodin -Nombre $fila.Nombre -Patron $Buscar) { $coinciden++ }
    }

    # El umbral REAL con el que acabo el indice, que puede ser mayor que
    # el pedido si se alcanzo el tope de archivos. Decir el pedido seria
    # mentir sobre lo que se ha mirado.
    $umbral = 0.0
    if ($null -ne $Indice -and $null -ne $Indice.UmbralArchivo) {
        $umbral = [double]$Indice.UmbralArchivo
    }

    # --- (a) No hay nada por encima del umbral -----------------------
    if ($total -eq 0) {
        if ($umbral -gt 0) {
            return ('Ningún archivo llega a {0}: aquí el espacio está repartido en muchos archivos pequeños. ' +
                    'El análisis ha ido bien.') -f (Format-Tamano $umbral)
        }
        return 'Todavía no hay ningún archivo que enseñar: no se ha analizado nada.'
    }

    $desdeUmbral = ''
    if ($umbral -gt 0) { $desdeUmbral = ' de más de {0}' -f (Format-Tamano $umbral) }

    # --- (b) Hay archivos, pero ninguno casa con la busqueda ---------
    if ($coinciden -eq 0) {
        if ($total -eq 1) {
            return ('El único archivo{0} que hay no coincide con «{1}». Prueba con * al principio, ' +
                    'como en *{1}*.') -f $desdeUmbral, $Buscar
        }
        return ('Ninguno de los {0} archivos{1} coincide con «{2}». Prueba con * al principio, ' +
                'como en *{2}*.') -f $total, $desdeUmbral, $Buscar
    }

    # Cero o menos se cuenta como ninguna fila, igual que hace
    # Get-VistaArchivos. Si las dos no dijeran lo mismo, el resumen
    # describiria una lista que no es la que hay en pantalla.
    $mostrados = $coinciden
    if ($Cuantos -le 0) { $mostrados = 0 }
    if ($Cuantos -gt 0 -and $Cuantos -lt $coinciden) { $mostrados = $Cuantos }

    $mayores = 'mayores'
    if ($Orden -eq 'Nombre') { $mayores = 'primeros por orden alfabético' }

    # --- (c) Hay mas de los que se ensenyan --------------------------
    # Esta es la unica rama que nombra los dos numeros a la vez. Sin ella
    # la lista se lee como "esto es todo lo que hay", que es falso.
    if ($mostrados -lt $coinciden) {
        $restantes = $coinciden - $mostrados
        if ($mostrados -le 0) {
            return ('Hay {0} archivos{1} que coinciden, pero no se está mostrando ninguno.' -f
                    $coinciden, $desdeUmbral)
        }
        $cola = 'y quedan {0} más sin mostrar' -f $restantes
        if ($restantes -eq 1) { $cola = 'y queda 1 más sin mostrar' }
        return ('Se muestran los {0} {1} de {2} archivos{3} que coinciden, {4}. Es un informe: ' +
                'no se propone borrar nada.') -f $mostrados, $mayores, $coinciden, $desdeUmbral, $cola
    }

    # --- Caso normal: se ensenya todo lo que hay ---------------------
    if ($coinciden -eq 1) {
        return ('Se muestra el único archivo{0} que hay. Es un informe: no se propone borrar nada.' -f
                $desdeUmbral)
    }
    return ('Se muestran los {0} archivos{1} que hay, todos. Es un informe: no se propone borrar nada.' -f
            $coinciden, $desdeUmbral)
}
