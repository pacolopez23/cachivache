<#
.SYNOPSIS
    Decide si un indice guardado se puede creer, y le aplica los cambios.

.DESCRIPTION
    LA DECISION DE DISENYO QUE MANDA SOBRE TODAS LAS DEMAS, Y VA LA PRIMERA
    PORQUE TODO LO DE ABAJO SE LEE A SU LUZ:

        El indice guardado sirve para PINTAR EL MAPA, nunca para DECIDIR
        QUE SE BORRA.

    Cachivache borra desde lo que acaba de ver con sus propios ojos en esta
    ejecucion. Si el indice se equivoca, el peor caso es un rectangulo mal
    dibujado; nunca un archivo borrado por error. Por eso aqui no hay ni
    una funcion que devuelva algo que se parezca a un candidato, y hay una
    prueba que lo prohibe. Esa separacion tiene que estar desde el primer
    dia: anyadirla despues de que algo dependa del indice no se hace.

    -------------------------------------------------------------------
    POR QUE ESTE ARCHIVO EXISTE

    docs/VEL-02-MEDICION.md midio que guardar el indice y actualizarlo con
    el diario de cambios de NTFS compensa por un margen amplio. Pero el
    apartado que decide el punto no tiene un numero por respuesta:

        UN INDICE QUE MIENTE ES PEOR QUE NO TENER INDICE.

    Si el archivo guardado dice que hay 40 GB en una carpeta que ya no
    existe, el programa ensenya espacio que no esta, el usuario va a
    buscarlo, no lo encuentra, y a partir de ahi no se fia de nada de lo
    que ve. El producto de Cachivache no es la velocidad: es que lo que
    dice sea verdad.

    De ahi las dos mitades de este archivo:

      * Test-IndiceUtilizable   - .se puede creer lo que hay guardado?
      * Update-IndiceConCambios - aplicarle lo que ha cambiado sin que los
        totales por carpeta se queden desfasados.

    -------------------------------------------------------------------
    LA REGLA DE ORO DE LA VALIDACION

    Ante cualquier duda -un campo que falta, un nulo, una fecha absurda-,
    la respuesta es NO SE PUEDE USAR. Equivocarse hacia "recorro de nuevo"
    cuesta cinco segundos; al reves cuesta ensenyar espacio que no existe.

    Y todo "no" lleva SIEMPRE un motivo legible: un rechazo mudo es
    indistinguible de un fallo del programa. El motivo va al registro, no
    a la cara del usuario -desde fuera lo unico que se nota es que esta
    vez tardo lo de siempre-, pero tiene que existir para poder mirarlo.

    -------------------------------------------------------------------
    LA CABECERA DEL INDICE

    Estos son los campos, con estos nombres exactos, porque quien ESCRIBE
    el indice y quien decide si CREERLO tienen que hablar el mismo idioma:

        Version       (int)      version del formato
        SerieVolumen  (string)   numero de serie del volumen
        IdDiario      (string)   identificador del diario USN
        UsnCorte      (long)     USN hasta donde se leyo
        Entradas      (int)      cuantas entradas trae el cuerpo
        Suma          (string)   suma de comprobacion del cuerpo
        Escrito       (datetime) cuando se escribio

    -------------------------------------------------------------------
    LA FORMA DEL INDICE EN MEMORIA que espera Update-IndiceConCambios

    La medicion es tajante: el indice cargado NO se compone como objetos.
    Un millon de pscustomobject cuesta 12,4 s frente a 1,0 s del mismo
    archivo leido a un diccionario. Asi que:

        Indice.Archivos - IDictionary  ruta -> bytes (numero)
        Indice.Carpetas - IDictionary  ruta -> entrada de New-EntradaCarpeta
                                       (Ruta, Nombre, Nivel, Bytes, Propios,
                                        Archivos, Ultimo)

    Ojo con la diferencia entre las dos columnas de bytes de una carpeta,
    porque la propagacion de aqui vive de ella:

        Propios - bytes de los archivos que estan DIRECTAMENTE ahi.
        Bytes   - bytes de todo lo que cuelga, a cualquier profundidad.
                  Es lo que dibuja el mapa, y es lo que miente si nadie lo
                  resta cuando algo desaparece.

    Esa es la razon de que la medicion obligue a guardar TAMBIEN la tabla
    de carpetas: volver a sumarla recorriendo el millon de archivos cuesta
    6 s, mas que recorrer el disco entero, y se come el ahorro completo.
    Por el mismo motivo aqui no hay ni un recorrido de la tabla de
    archivos: todo lo que se toca es proporcional a los cambios.
#>

function Get-CaducidadIndice {
    <#
    .SYNOPSIS
        Cuantos dias se da por fresco un indice guardado.

    .DESCRIPTION
        Es una funcion y no un numero suelto a proposito: lo pide igual
        quien decide -Test-IndiceUtilizable- y quien lo prueba. Un numero
        copiado en dos sitios es un numero que acabara siendo dos numeros
        distintos, que es el patron central del proyecto.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    # SIETE DIAS. El porque, que es lo unico que hace defendible un numero
    # elegido a ojo:
    #
    #   1. HAY UNA FORMA DE MENTIRA QUE NINGUNA CABECERA DETECTA: los
    #      cambios hechos con el diario apagado. Si alguien lo desactiva,
    #      si el disco se monta desde otro sistema en un arranque dual, o
    #      si se toca desde un contenedor, los cambios ocurren y el diario
    #      no se entera. El identificador sigue coincidiendo y el corte
    #      sigue siendo valido: el indice miente Y TODO CUADRA. Contra eso
    #      la caducidad es la unica red barata que queda, y cuanto mas
    #      corta, menos ventana.
    #
    #   2. UN INDICE VIEJO APENAS AHORRA. El punto de equilibrio medido
    #      esta en unos 125.000 registros del diario, del orden de 30.000
    #      archivos tocados. Un equipo normal se acerca a esa cifra en
    #      dias, no en semanas: pasado ese punto el camino incremental ya
    #      no gana, o sea que caducar un indice de mas de una semana no
    #      renuncia a casi nada.
    #
    #   3. Y EL PROPIO DIARIO CADUCA SOLO. Con el tamanyo por omision de
    #      Windows caben ~300.000 registros, asi que en una semana lo
    #      normal es que ya haya dado la vuelta y el indice se rechace por
    #      eso antes de llegar aqui. La caducidad no es la red principal:
    #      es la que sigue puesta cuando el diario es grande.
    #
    # Y no se elige un dia porque tampoco hay que pasarse: un indice que
    # caduca cada mananya no llega a usarse nunca, y entonces el punto
    # entero sobra.
    return 7
}

function ConvertTo-NumeroIndice {
    <#
    .SYNOPSIS
        El valor como numero entero, o $null si no se puede creer.

    .DESCRIPTION
        La cabecera y el cuerpo llegan de un archivo, asi que sus campos
        pueden ser cualquier cosa: una cadena, un nulo, texto con
        espacios, o basura. Aqui se convierte SIN lanzar y devolviendo
        $null cuando no hay conversion honesta, para que quien llama pueda
        tratar "no se sabe" igual que trata "no cuadra": rechazando.

        Se parsea con cultura invariante y no con un cast de PowerShell
        porque el cast REDONDEA: [long]'3,7' o [long]3.7 dan 4 en vez de
        fallar, y un USN de corte redondeado no es el USN que se guardo.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $Valor,
        [ValidateSet('int', 'long')] [string] $Tipo = 'long'
    )

    if ($null -eq $Valor) { return $null }
    # Un booleano convierte a 1 o a 0 sin protestar, y eso seria inventarse
    # una version o un numero de entradas a partir de un campo que no es un
    # numero.
    if ($Valor -is [bool]) { return $null }

    $largo = $null

    if ($Valor -is [int] -or $Valor -is [long] -or $Valor -is [short] -or
        $Valor -is [byte] -or $Valor -is [uint32] -or $Valor -is [uint64]) {
        $largo = [long]$Valor
    } elseif ($Valor -is [double] -or $Valor -is [single] -or $Valor -is [decimal]) {
        # El tamanyo de un archivo se guarda como double porque asi lo
        # devuelve el recorrido, pero sigue siendo un entero. Uno con
        # decimales no es un tamanyo: es otra cosa mal leida.
        $doble = [double]$Valor
        if ([double]::IsNaN($doble) -or [double]::IsInfinity($doble)) { return $null }
        if ([Math]::Floor($doble) -ne $doble) { return $null }
        if ($doble -gt 9.2E+18 -or $doble -lt -9.2E+18) { return $null }
        $largo = [long]$doble
    } else {
        $texto = ([string]$Valor).Trim()
        if ($texto.Length -eq 0) { return $null }
        try {
            $largo = [long]::Parse($texto, [Globalization.CultureInfo]::InvariantCulture)
        } catch {
            return $null
        }
    }

    if ($Tipo -eq 'int') {
        if ($largo -gt [int]::MaxValue -or $largo -lt [int]::MinValue) { return $null }
        return [int]$largo
    }
    return $largo
}

function Test-IndiceUtilizable {
    <#
    .SYNOPSIS
        .Se puede creer el indice guardado? Y si no, POR QUE no.

    .DESCRIPTION
        Calculo puro: no toca el disco ni el reloj. Recibe la cabecera
        guardada y los datos del disco de HOY, y devuelve un veredicto con
        tres campos:

            Utilizable - .se puede usar?
            Codigo     - motivo en ASCII, estable, para el registro y para
                         las pruebas. Es el que distingue un rechazo de
                         otro: una prueba que solo comprueba "se rechaza"
                         pasa por el motivo equivocado, y eso ya ha pasado
                         en este proyecto.
            Motivo     - la misma respuesta en castellano, legible.

        CADA COMPROBACION CIERRA UNA FORMA DISTINTA DE MENTIR, y son las
        que enumera docs/VEL-02-MEDICION.md:

          Version del formato   lo escribio otra version del programa, con
                                otra estructura.
          Numero de serie       es OTRO DISCO que ha heredado la misma
                                letra: un USB, una unidad remontada.
          Identificador diario  el diario se borro y se creo de nuevo
                                -chkdsk, una restauracion, alguien lo
                                desactivo-: la historia anterior ya no
                                existe.
          USN de corte          comparado con el primer USN disponible
                                ahora dice si el diario HA DADO LA VUELTA
                                y se ha comido el tramo que hacia falta.
          Entradas y suma       el cuerpo esta truncado o alterado; el
                                caso tipico es un apagon a mitad de
                                escritura.
          Caducidad             la unica red contra los cambios hechos con
                                el diario apagado. Ver Get-CaducidadIndice.

        EL ORDEN de las comprobaciones no es casual, y va de lo mas
        fundamental a lo mas fino: primero si hay cabecera, luego si hay
        con que contrastarla, luego si es coherente consigo misma, luego
        la identidad del disco y del diario, luego el cuerpo, y al final
        la edad. Asi el motivo que sale es el mas explicativo de los que
        aplican, y no el primero con el que se tropieza.

    .PARAMETER Cabecera
        La cabecera leida del indice guardado. Objeto o tabla hash con los
        siete campos.
    .PARAMETER VersionEsperada
        Version del formato que entiende el programa de hoy.
    .PARAMETER SerieVolumen
        Numero de serie del volumen tal y como lo dice el disco AHORA.
    .PARAMETER IdDiario
        Identificador del diario USN de AHORA.
    .PARAMETER PrimerUsn
        Primer USN que el diario todavia conserva. Por debajo de eso, la
        historia ya se ha perdido.
    .PARAMETER Ahora
        La fecha actual. Se pasa desde fuera para que esta funcion sea
        pura y la caducidad se pueda probar sin esperar una semana.
    .PARAMETER EntradasLeidas
        Cuantas entradas trae de verdad el cuerpo que se ha leido. Opcional:
        solo lo sabe quien ya ha leido el cuerpo. Si no se pasa, esa
        comprobacion NO se hace, y entonces la tiene que hacer el lector.
    .PARAMETER SumaCalculada
        La suma de comprobacion calculada sobre el cuerpo leido. Igual que
        la anterior.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $Cabecera,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $VersionEsperada,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $SerieVolumen,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $IdDiario,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $PrimerUsn,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $Ahora,
        [AllowNull()] [AllowEmptyString()] $EntradasLeidas = $null,
        [AllowNull()] [AllowEmptyString()] $SumaCalculada  = $null
    )

    # --- 1. .Hay cabecera? -------------------------------------------
    if ($null -eq $Cabecera) {
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'CabeceraAusente'
            Motivo     = 'No hay cabecera que comprobar, así que el índice no se puede creer.'
        }
    }

    # --- 2. .Hay con que contrastarla? -------------------------------
    # Va antes que la propia cabecera porque sin los datos de hoy no se
    # puede contrastar NADA, y un indice que no se ha podido contrastar es
    # igual de peligroso que uno que no cuadra.
    $versionHoy = ConvertTo-NumeroIndice -Valor $VersionEsperada -Tipo 'int'
    $serieHoy   = if ($null -eq $SerieVolumen) { '' } else { ([string]$SerieVolumen).Trim() }
    $diarioHoy  = if ($null -eq $IdDiario)     { '' } else { ([string]$IdDiario).Trim() }
    $primerUsn  = ConvertTo-NumeroIndice -Valor $PrimerUsn -Tipo 'long'

    $ahoraFecha = $null
    if ($Ahora -is [datetime]) {
        $ahoraFecha = $Ahora
    } elseif ($null -ne $Ahora -and ([string]$Ahora).Trim().Length -gt 0) {
        try { $ahoraFecha = [datetime]$Ahora } catch { $ahoraFecha = $null }
    }

    if ($null -eq $versionHoy -or $serieHoy.Length -eq 0 -or $diarioHoy.Length -eq 0 -or
        $null -eq $primerUsn  -or $primerUsn -lt 0 -or $null -eq $ahoraFecha) {
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'DatosDelDiscoNoValidos'
            Motivo     = 'No se puede contrastar la cabecera con el disco de hoy: faltan datos del volumen.'
        }
    }

    # --- 3. .Esta entera la cabecera? --------------------------------
    # Leer una propiedad que no existe devuelve $null sin lanzar, tanto en
    # un pscustomobject como en una tabla hash, asi que "falta" y "es
    # nulo" son el mismo caso y se contestan igual: no se usa.
    foreach ($campo in @('Version', 'SerieVolumen', 'IdDiario', 'UsnCorte', 'Entradas', 'Suma', 'Escrito')) {
        $valor = $Cabecera.$campo
        $vacio = ($null -eq $valor)
        if (-not $vacio -and $valor -is [string]) { $vacio = ($valor.Trim().Length -eq 0) }
        if ($vacio) {
            $texto = 'A la cabecera del índice le falta el campo {0}.' -f $campo
            return [pscustomobject]@{
                Utilizable = $false
                Codigo     = 'CampoAusente'
                Motivo     = $texto
            }
        }
    }

    # --- 4. .Son creibles los valores que trae? ----------------------
    $version  = ConvertTo-NumeroIndice -Valor $Cabecera.Version  -Tipo 'int'
    $usnCorte = ConvertTo-NumeroIndice -Valor $Cabecera.UsnCorte -Tipo 'long'
    $entradas = ConvertTo-NumeroIndice -Valor $Cabecera.Entradas -Tipo 'int'

    $escrito = $null
    if ($Cabecera.Escrito -is [datetime]) {
        $escrito = $Cabecera.Escrito
    } else {
        try { $escrito = [datetime]$Cabecera.Escrito } catch { $escrito = $null }
    }

    $imposible = ''
    if     ($null -eq $version)  { $imposible = 'Version' }
    elseif ($null -eq $usnCorte) { $imposible = 'UsnCorte' }
    elseif ($usnCorte -lt 0)     { $imposible = 'UsnCorte' }
    elseif ($null -eq $entradas) { $imposible = 'Entradas' }
    elseif ($entradas -lt 0)     { $imposible = 'Entradas' }
    elseif ($null -eq $escrito)  { $imposible = 'Escrito' }
    # Una fecha anterior al anyo 2000 es un campo que nunca llego a
    # escribirse: DateTime.MinValue y el cero de casi cualquier formato
    # caen ahi.
    elseif ($escrito -lt ([datetime]'2000-01-01')) { $imposible = 'Escrito' }
    # Y una fecha en el futuro es un archivo tocado o un reloj movido. El
    # margen de un minuto no es simetria: sin el, un ajuste de reloj de
    # tres segundos tiraria un indice perfectamente bueno cada vez.
    elseif ($escrito -gt $ahoraFecha.AddMinutes(1)) { $imposible = 'Escrito' }

    if ($imposible.Length -gt 0) {
        $texto = 'El campo {0} de la cabecera no trae un valor creíble.' -f $imposible
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'ValorImposible'
            Motivo     = $texto
        }
    }

    # --- 5. .Lo escribio esta version del programa? ------------------
    if ($version -ne $versionHoy) {
        # El texto se arma en una variable y no dentro del @{}: -f se
        # enlaza mas fuerte que + y la coma de dos argumentos dentro de
        # una llamada se lee como separador. Las dos trampas ya han
        # mordido en este repositorio.
        $texto = 'El índice lo escribió otra versión del programa: trae el formato {0} y aquí se lee el {1}.' -f
                 $version, $versionHoy
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'VersionDistinta'
            Motivo     = $texto
        }
    }

    # --- 6. .Es el mismo disco? --------------------------------------
    # Sin distinguir mayusculas porque el numero de serie se escribe en
    # hexadecimal y quien lo lea puede darlo en cualquiera de las dos
    # cajas.
    if (-not [string]::Equals(([string]$Cabecera.SerieVolumen).Trim(), $serieHoy,
                              [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'VolumenDistinto'
            Motivo     = 'El número de serie del volumen no coincide: es otro disco que ha heredado la misma letra.'
        }
    }

    # --- 7. .Es el mismo diario? -------------------------------------
    if (-not [string]::Equals(([string]$Cabecera.IdDiario).Trim(), $diarioHoy,
                              [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'DiarioDistinto'
            Motivo     = 'El diario de cambios se creó de nuevo, así que la historia anterior ya no existe.'
        }
    }

    # --- 8. .Sigue estando el tramo que hace falta? ------------------
    # Es -lt y no -le a proposito: si el corte guardado coincide con el
    # primer USN que queda, no se ha perdido nada. Lo que se pierde es lo
    # que quedo POR DEBAJO del primero disponible.
    if ($usnCorte -lt $primerUsn) {
        $texto = ('El diario ha dado la vuelta y se ha comido el tramo que hacía falta: ' +
                  'el corte guardado es {0} y ahora el diario empieza en {1}.') -f $usnCorte, $primerUsn
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'DiarioDioLaVuelta'
            Motivo     = $texto
        }
    }

    # --- 9. .Cuadra el cuerpo con lo que promete la cabecera? --------
    if ($null -ne $EntradasLeidas) {
        $leidas = ConvertTo-NumeroIndice -Valor $EntradasLeidas -Tipo 'int'
        if ($null -eq $leidas -or $leidas -ne $entradas) {
            $texto = ('El cuerpo del índice está truncado o alterado: ' +
                      'la cabecera promete {0} entradas y se han leído {1}.') -f $entradas, $EntradasLeidas
            return [pscustomobject]@{
                Utilizable = $false
                Codigo     = 'CuerpoNoCuadra'
                Motivo     = $texto
            }
        }
    }

    if ($null -ne $SumaCalculada -and ([string]$SumaCalculada).Trim().Length -gt 0) {
        if (-not [string]::Equals(([string]$Cabecera.Suma).Trim(), ([string]$SumaCalculada).Trim(),
                                  [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Utilizable = $false
                Codigo     = 'CuerpoNoCuadra'
                Motivo     = 'El cuerpo del índice está truncado o alterado: la suma de comprobación no coincide.'
            }
        }
    }

    # --- 10. .Es lo bastante reciente? -------------------------------
    $dias = ($ahoraFecha - $escrito).TotalDays
    $tope = Get-CaducidadIndice
    if ($dias -gt $tope) {
        $texto = 'El índice se escribió hace {0:N0} días y solo se dan por buenos los de menos de {1}.' -f
                 $dias, $tope
        return [pscustomobject]@{
            Utilizable = $false
            Codigo     = 'Caducado'
            Motivo     = $texto
        }
    }

    return [pscustomobject]@{
        Utilizable = $true
        Codigo     = 'Utilizable'
        Motivo     = ''
    }
}

function Resolve-CarpetaIndice {
    <#
    .SYNOPSIS
        La entrada de una carpeta dentro del indice, creandola si hace
        falta y se puede colocar bien.

    .DESCRIPTION
        Un alta puede caer en una carpeta que el indice todavia no conoce:
        se creo despues del ultimo recorrido. Inventarse la entrada a
        ciegas seria peor que no tenerla -el Nivel decide como se
        propaga-, asi que solo se crea cuando se puede colgar de un
        antepasado que SI esta en el indice, y entonces se crea la cadena
        entera con sus niveles correctos.

        Si no hay ningun antepasado conocido se devuelve $null y quien
        llama descarta el cambio. Es la regla de siempre: antes no saber
        que inventarse un sitio.

    .PARAMETER Crear
        Sin este conmutador la funcion solo busca. Para una baja no hay
        que crear nada: si la carpeta no esta, no hay total que corregir.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Carpetas,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $Ruta,
        [switch] $Crear
    )

    if ($null -eq $Carpetas -or -not ($Carpetas -is [Collections.IDictionary])) { return $null }
    if ($null -eq $Ruta) { return $null }

    # ContainsKey y no Contains: lo tienen las dos formas que puede tomar
    # esta tabla -Hashtable y Dictionary[string, object]-, mientras que
    # Contains en el diccionario generico es una implementacion explicita
    # de interfaz y no siempre se ve desde PowerShell.
    $clave = [string]$Ruta
    if ($clave.Trim().Length -eq 0) { return $null }
    if ($Carpetas.ContainsKey($clave)) { return $Carpetas[$clave] }

    # La raiz de una unidad se guarda como "C:\", con su barra, mientras
    # que cualquier otra carpeta se guarda sin ella. Por eso se prueban
    # las dos formas antes de dar la carpeta por desconocida.
    $sinBarra = $clave.TrimEnd([char]'\', [char]'/')
    if ($sinBarra.Length -gt 0 -and $sinBarra -ne $clave -and $Carpetas.ContainsKey($sinBarra)) {
        return $Carpetas[$sinBarra]
    }
    if ($sinBarra.Length -eq 0) { return $null }

    if (-not $Crear) { return $null }

    # Se sube hasta encontrar un antepasado conocido, apuntando por el
    # camino las carpetas que faltan. La guarda de 512 vueltas no es
    # paranoia gratuita: Split-Path sobre una ruta rara puede devolver lo
    # mismo que recibio, y un bucle infinito en el arranque del programa
    # es mucho peor que un indice desechado.
    $faltan = [Collections.Generic.List[string]]::new()
    $actual = $sinBarra
    $conocida = $null
    $guarda = 0

    while ($guarda -lt 512) {
        $guarda++
        $padre = [string](Split-Path $actual -Parent)
        if ([string]::IsNullOrWhiteSpace($padre) -or $padre -eq $actual) { break }
        if ($Carpetas.ContainsKey($padre)) { $conocida = $Carpetas[$padre]; break }
        $sinBarraPadre = $padre.TrimEnd([char]'\', [char]'/')
        if ($sinBarraPadre.Length -gt 0 -and $Carpetas.ContainsKey($sinBarraPadre)) {
            $conocida = $Carpetas[$sinBarraPadre]
            break
        }
        $faltan.Add($padre)
        $actual = $padre
    }

    if ($null -eq $conocida) { return $null }

    # De la mas alta a la mas honda, para que cada una pueda mirar el
    # Nivel de su padre, que para entonces ya existe.
    $nivel = [int]$conocida.Nivel
    for ($i = $faltan.Count - 1; $i -ge 0; $i--) {
        $nivel++
        $Carpetas[$faltan[$i]] = New-EntradaCarpeta -Ruta $faltan[$i] -Nivel $nivel
    }
    $nivel++
    $Carpetas[$sinBarra] = New-EntradaCarpeta -Ruta $sinBarra -Nivel $nivel
    return $Carpetas[$sinBarra]
}

function Update-CadenaCarpetas {
    <#
    .SYNOPSIS
        Sube una diferencia por la cadena de carpetas hasta la raiz.

    .DESCRIPTION
        ESTA ES LA FUNCION QUE IMPIDE LA MENTIRA. El total de una carpeta
        -Bytes- incluye todo lo que cuelga de ella, asi que cuando un
        archivo cambia de tamanyo o desaparece no basta con tocar su
        carpeta: hay que subir la diferencia por todos sus antepasados. Si
        la propagacion se olvida de restar, el mapa ensenya para siempre
        un espacio que ya no existe.

        Se hace de forma incremental -un salto por nivel- y no volviendo a
        sumar el indice entero, porque la medicion dejo el numero claro:
        propagar recorriendo el millon de archivos cuesta 6 s, mas que
        recorrer el disco entero.

        Devuelve cuantos totales han tenido que recortarse a cero.

    .NOTES
        UN ANTEPASADO QUE NO ESTE EN EL INDICE NO CORTA LA CADENA: se pasa
        de largo y se sigue subiendo. La verdad es que el total del abuelo
        SI contiene ese archivo, asi que pararse ahi seria dejar de restar
        justo donde mas se nota.

        Ultimo solo sube, nunca baja. Una baja no puede saber cual es la
        fecha mayor que queda sin volver a mirar la carpeta, asi que se
        deja como esta: es una fecha, no espacio, y el mapa no miente por
        ella.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo cambia numeros de un diccionario en memoria.')]
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Carpetas,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] $Ruta,
        [double] $DeltaBytes    = 0.0,
        [int]    $DeltaArchivos = 0,
        [AllowNull()] $Ultimo   = $null
    )

    $recortes = 0
    if ($null -eq $Carpetas -or -not ($Carpetas -is [Collections.IDictionary])) { return $recortes }
    if ($null -eq $Ruta) { return $recortes }

    $actual = [string]$Ruta
    $guarda = 0

    while ($guarda -lt 512 -and -not [string]::IsNullOrWhiteSpace($actual)) {
        $guarda++

        $clave = $null
        if ($Carpetas.ContainsKey($actual)) {
            $clave = $actual
        } else {
            $sinBarra = $actual.TrimEnd([char]'\', [char]'/')
            if ($sinBarra.Length -gt 0 -and $Carpetas.ContainsKey($sinBarra)) { $clave = $sinBarra }
        }

        if ($null -ne $clave) {
            $entrada = $Carpetas[$clave]
            $entrada.Bytes    = [double]$entrada.Bytes + $DeltaBytes
            $entrada.Archivos = [int]$entrada.Archivos + $DeltaArchivos

            # Un total negativo es imposible en el mundo real, asi que si
            # sale es que el indice ya venia descuadrado. Se recorta a
            # cero -ensenyar un tamanyo negativo seria una mentira peor- y
            # se CUENTA, para que quien llama pueda decidir recorrer de
            # nuevo en vez de fiarse. Recortar en silencio seria tapar el
            # sintoma justo en el archivo escrito para no tapar ninguno.
            if ($entrada.Bytes -lt 0)    { $entrada.Bytes = 0.0; $recortes++ }
            if ($entrada.Archivos -lt 0) { $entrada.Archivos = 0; $recortes++ }

            if ($null -ne $Ultimo -and $Ultimo -is [datetime] -and $Ultimo -gt $entrada.Ultimo) {
                $entrada.Ultimo = $Ultimo
            }
        }

        $padre = [string](Split-Path $actual -Parent)
        if ($padre -eq $actual) { break }
        $actual = $padre
    }

    return $recortes
}

function Update-IndiceConCambios {
    <#
    .SYNOPSIS
        Aplica altas, bajas y cambios de tamanyo al indice en memoria, y
        vuelve a propagar los totales por carpeta.

    .DESCRIPTION
        Calculo puro en el sentido que importa aqui: no toca el disco, no
        lee el reloj, no mira ninguna variable global y con las mismas
        entradas da siempre lo mismo. Lo que SI hace es modificar en el
        sitio el indice que recibe, porque copiar un diccionario de un
        millon de entradas por cada tanda costaria mas que recorrer el
        disco, que es justo lo que este camino existe para evitar.

        NO LANZA NUNCA. Ni con una lista vacia, ni con nulos dentro, ni con
        un cambio sobre una carpeta que ya no esta, ni con una baja de algo
        que no existia. Un arranque no puede morir porque el diario traiga
        algo raro: como mucho se descarta el indice y se recorre.

        CADA CAMBIO SE APLICA ENTERO O NO SE APLICA. Primero se resuelve
        todo lo que hace falta -la carpeta, el tamanyo anterior- y solo
        entonces se toca nada. Quitar el archivo de la tabla y no poder
        corregir su carpeta dejaria el indice diciendo que ese espacio
        sigue ahi, que es exactamente la mentira que esto viene a impedir.

        LA FORMA DE UN CAMBIO:

            Tipo    'Alta' | 'Baja' | 'Cambio'   (sin distinguir mayusculas)
            Ruta    ruta completa del archivo
            Bytes   tamanyo de AHORA (alta y cambio; la baja lo ignora)
            Carpeta opcional; si no viene, se deduce de la ruta
            Ultimo  opcional, fecha de la ultima escritura

        LO QUE DEVUELVE, y por que no es solo el indice:

            Indice      el mismo objeto que entro, ya actualizado
            Aplicados   cambios que han entrado
            Altas / Bajas / Modificados
            Ignorados   cambios con los que no habia nada que hacer: la
                        baja de un archivo que el indice no tenia es el
                        caso normal, no un fallo
            Descartados cambios que HABRIA que haber aplicado y no se ha
                        podido
            Recortes    totales que hubo que subir a cero porque salian
                        negativos, o sea, indice descuadrado de antes
            Confiable   $false si se descarto algo o si hubo recortes. Un
                        indice al que se le han caido cambios puede estar
                        mintiendo, y quien llama tiene una salida barata:
                        recorrer el disco entero.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo cambia estructuras en memoria; no toca el disco.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Indice,
        [Parameter(Mandatory)] [AllowNull()] $Cambios
    )

    $aplicados = 0; $altas = 0; $bajas = 0; $modificados = 0
    $ignorados = 0; $descartados = 0; $recortes = 0
    $netoBytes = 0.0; $netoArchivos = 0

    # @($null) NO es una lista vacia: es una lista con un nulo dentro. Sin
    # esta linea, "no ha cambiado nada" se contaria como un cambio perdido
    # y el indice quedaria marcado como no fiable por nada.
    $lista = @()
    if ($null -ne $Cambios) { $lista = @($Cambios) }

    $carpetas = $null
    $archivos = $null
    if ($null -ne $Indice) {
        if ($Indice.Carpetas -is [Collections.IDictionary]) { $carpetas = $Indice.Carpetas }
        if ($Indice.Archivos -is [Collections.IDictionary]) { $archivos = $Indice.Archivos }
    }

    # Sin las dos tablas no se puede aplicar nada SIN MENTIR, asi que no se
    # aplica nada. La medicion lo deja escrito: se guardan las dos tablas,
    # y la de archivos como diccionario ruta -> bytes, nunca como lista de
    # objetos.
    if ($null -eq $carpetas -or $null -eq $archivos) {
        return [pscustomobject]@{
            Indice      = $Indice
            Aplicados   = 0
            Altas       = 0
            Bajas       = 0
            Modificados = 0
            Ignorados   = 0
            Descartados = @($lista | Where-Object { $null -ne $_ }).Count
            Recortes    = 0
            Confiable   = $false
            Motivo      = 'El índice no trae las dos tablas que hacen falta, la de archivos y la de carpetas.'
        }
    }

    foreach ($cambio in $lista) {
        if ($null -eq $cambio) { $descartados++; continue }

        $tipo = ''
        if ($null -ne $cambio.Tipo) { $tipo = ([string]$cambio.Tipo).Trim() }
        $ruta = ''
        if ($null -ne $cambio.Ruta) { $ruta = ([string]$cambio.Ruta).Trim() }

        if ($ruta.Length -eq 0) { $descartados++; continue }
        if ($tipo -notin @('Alta', 'Baja', 'Cambio')) { $descartados++; continue }

        $carpetaRuta = ''
        if ($null -ne $cambio.Carpeta) { $carpetaRuta = ([string]$cambio.Carpeta).Trim() }
        if ($carpetaRuta.Length -eq 0) { $carpetaRuta = [string](Split-Path $ruta -Parent) }
        if ([string]::IsNullOrWhiteSpace($carpetaRuta)) { $descartados++; continue }

        $ultimo = $null
        if ($cambio.Ultimo -is [datetime]) { $ultimo = $cambio.Ultimo }

        # LA TABLA DE ARCHIVOS GUARDA ENTRADAS, NO NUMEROS SUELTOS.
        #
        # Esta funcion se escribio esperando "ruta -> bytes", y quien la
        # alimenta -Read-IndiceDisco -ComoDiccionario- da "ruta -> entrada",
        # con Ruta, Nombre, Carpeta, Extension, Bytes y Ultimo dentro. Las
        # dos mitades se escribieron en paralelo y coincidieron en usar un
        # diccionario pero no en que meter dentro; lo canto la primera vez
        # que se probo el camino entero, con TODAS las bajas descartadas.
        #
        # Se queda la entrada, y no el numero, porque es la forma que
        # permite VOLVER A GUARDAR el indice despues de actualizarlo, que
        # es el sentido de que el indice sea persistente. Con solo el
        # tamanyo habria que ir a buscar el resto a otro sitio.
        #
        # Se admite tambien el numero suelto: cuesta una linea y hace que
        # esta funcion se pueda probar sin montar un indice entero.
        $tenia = $archivos.ContainsKey($ruta)
        $anterior = 0.0
        if ($tenia) {
            $valor = $archivos[$ruta]
            if ($null -ne $valor -and $valor -isnot [ValueType] -and $valor -isnot [string]) {
                $valor = $valor.Bytes
            }
            $bruto = ConvertTo-NumeroIndice -Valor $valor -Tipo 'long'
            if ($null -eq $bruto) { $descartados++; continue }
            $anterior = [double]$bruto
        }

        if ($tipo -eq 'Baja') {
            # Una baja de algo que el indice no tenia no es un fallo: el
            # archivo pudo crearse y borrarse entre dos pasadas. No hay
            # nada que restar y no hay nada de lo que desconfiar.
            if (-not $tenia) { $ignorados++; continue }

            $entrada = Resolve-CarpetaIndice -Carpetas $carpetas -Ruta $carpetaRuta
            if ($null -eq $entrada) { $descartados++; continue }

            $null = $archivos.Remove($ruta)
            $entrada.Propios = [double]$entrada.Propios - $anterior
            if ($entrada.Propios -lt 0) { $entrada.Propios = 0.0; $recortes++ }
            $recortes += Update-CadenaCarpetas -Carpetas $carpetas -Ruta $entrada.Ruta `
                             -DeltaBytes (-$anterior) -DeltaArchivos (-1)
            $netoBytes -= $anterior
            $netoArchivos--
            $bajas++
            $aplicados++
            continue
        }

        # Alta y Cambio comparten todo salvo la cuenta de archivos, asi que
        # comparten codigo: la diferencia de verdad no es que la orden diga
        # "alta" o "cambio", sino si el indice ya conocia el archivo. Un
        # alta de algo que ya estaba es un cambio de tamanyo, y un cambio
        # sobre algo que faltaba es un alta; hacerles caso a las etiquetas
        # en vez de mirar lo que hay descuadraria los totales.
        $nuevo = ConvertTo-NumeroIndice -Valor $cambio.Bytes -Tipo 'long'
        if ($null -eq $nuevo -or $nuevo -lt 0) { $descartados++; continue }

        $entrada = Resolve-CarpetaIndice -Carpetas $carpetas -Ruta $carpetaRuta -Crear
        if ($null -eq $entrada) { $descartados++; continue }

        $delta = [double]$nuevo - $anterior
        # Se conserva la forma que ya tenia la tabla: si guardaba
        # entradas, se actualiza el campo Bytes de la entrada; si guardaba
        # numeros, se guarda el numero. Cambiar la forma a mitad de un
        # recorrido dejaria una tabla con las dos, que es peor que
        # cualquiera de las dos.
        if ($tenia -and $null -ne $archivos[$ruta] -and
            $archivos[$ruta] -isnot [ValueType] -and $archivos[$ruta] -isnot [string]) {
            $archivos[$ruta].Bytes = [double]$nuevo
        } else {
            $archivos[$ruta] = [double]$nuevo
        }
        $entrada.Propios = [double]$entrada.Propios + $delta
        if ($entrada.Propios -lt 0) { $entrada.Propios = 0.0; $recortes++ }

        $cuenta = 0
        if (-not $tenia) { $cuenta = 1 }
        $recortes += Update-CadenaCarpetas -Carpetas $carpetas -Ruta $entrada.Ruta `
                         -DeltaBytes $delta -DeltaArchivos $cuenta -Ultimo $ultimo

        $netoBytes += $delta
        $netoArchivos += $cuenta
        if ($tenia) { $modificados++ } else { $altas++ }
        $aplicados++
    }

    # Los totales de cabecera del indice, si los trae. Se mueven por la
    # DIFERENCIA y no volviendo a sumar la tabla de archivos: sumar el
    # millon de entradas es la operacion de 6 s que la medicion prohibe.
    #
    # Y se comprueba que la propiedad EXISTE antes de escribirla, porque
    # leer un $null.Propiedad no lanza pero escribirla si, y este objeto
    # puede venir de un formato anterior que no la tuviera.
    if ($null -ne $Indice -and $null -ne $Indice.PSObject) {
        if ($null -ne $Indice.PSObject.Properties['Bytes']) {
            $total = [double]$Indice.Bytes + $netoBytes
            if ($total -lt 0) { $total = 0.0; $recortes++ }
            $Indice.Bytes = $total
        }
        if ($null -ne $Indice.PSObject.Properties['TotalArchivos']) {
            $cuentaTotal = [int]$Indice.TotalArchivos + $netoArchivos
            if ($cuentaTotal -lt 0) { $cuentaTotal = 0; $recortes++ }
            $Indice.TotalArchivos = $cuentaTotal
        }
    }

    # UN "NO" SIN MOTIVO ES INDISTINGUIBLE DE UN FALLO DEL PROGRAMA.
    #
    # Esta funcion devolvia Motivo = '' SIEMPRE, tambien cuando Confiable
    # salia $false. O sea que quien llamara veia "no te fies" y no tenia
    # forma de saber si era porque se cayeron tres cambios, porque el
    # indice ya venia descuadrado, o porque el programa se habia roto. Lo
    # canto la primera vez que se probaron las dos mitades juntas: el
    # camino entero contestaba "confiable=False, motivo=" y ahi se acababa
    # la investigacion.
    #
    # La cabecera de esta misma funcion ya decia que quien llama tiene una
    # salida barata -recorrer el disco entero-, y para elegirla hace falta
    # saber por que.
    $confiable = ($descartados -eq 0 -and $recortes -eq 0)
    $porque = ''
    if (-not $confiable) {
        $partes = [Collections.Generic.List[string]]::new()
        if ($descartados -gt 0) {
            $partes.Add(('{0} {1} no se {2} podido aplicar' -f $descartados,
                         $(if ($descartados -eq 1) { 'cambio' } else { 'cambios' }),
                         $(if ($descartados -eq 1) { 'ha' } else { 'han' })))
        }
        if ($recortes -gt 0) {
            $partes.Add(('{0} {1} de carpeta {2} en negativo, asi que el índice ya venía descuadrado' -f
                         $recortes,
                         $(if ($recortes -eq 1) { 'total' } else { 'totales' }),
                         $(if ($recortes -eq 1) { 'salía' } else { 'salían' })))
        }
        $porque = 'El índice actualizado no es de fiar: ' + ($partes -join ', ') +
                  '. Conviene recorrer el disco entero.'
    }

    return [pscustomobject]@{
        Indice      = $Indice
        Aplicados   = $aplicados
        Altas       = $altas
        Bajas       = $bajas
        Modificados = $modificados
        Ignorados   = $ignorados
        Descartados = $descartados
        Recortes    = $recortes
        Confiable   = $confiable
        Motivo      = $porque
    }
}
