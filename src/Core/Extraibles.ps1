<#
.SYNOPSIS
    Que se puede hacer con cada tipo de unidad: analizarla, y borrar en
    ella. Calculo puro.

.DESCRIPTION
    [VIS-04]. Hoy Get-UnidadesFijas filtra por DriveType Fixed, asi que un
    disco externo o una llave USB NO SE ANALIZAN EN ABSOLUTO. WizTree los
    recorre sin mas, y es la unica funcion suya que la hoja de ruta no
    contemplaba de ninguna forma.

    LA DECISION DE FONDO, QUE ES LO UNICO QUE DECIDE ESTE ARCHIVO:
    analizar si, borrar no.

    Una unidad extraible se puede desconectar en mitad de una operacion, y
    eso convierte cualquier borrado en un error a medias sobre un disco que
    ya no esta: media carpeta borrada, un informe que promete espacio que
    no se ha liberado, y nada que se pueda deshacer. Medir y dibujar no
    tienen ese problema: si el disco desaparece durante el analisis, se
    pierde el analisis y ya. Y medir es justo lo que hace falta para
    competir con WizTree, que no borra.

    Asi que la regla es: una unidad extraible entra en el mapa, en la vista
    de archivos y en el informe, y NUNCA produce un candidato borrable.

    POR QUE ESTO VIVE EN UNA FUNCION Y NO EN UN "if" DENTRO DEL EMBUDO.
    Es el patron central del proyecto: cuando dos sitios tienen que decidir
    lo mismo -aqui son al menos tres: quien lista las unidades, quien filtra
    los candidatos y quien escribe el informe- se saca a una sola funcion
    que se pueda probar, y se protege con una invariante que prohiba que
    vuelvan a divergir. Un "if ($tipo -eq 'Fixed')" repetido en tres sitios
    es un borrado en una llave USB esperando a que alguien toque uno solo
    de los tres.

    ANTE LO DESCONOCIDO, LA RESPUESTA SEGURA: no analizable y no borrable.
    Equivocarse hacia "no se puede borrar" cuesta una funcion, y se nota
    enseguida porque el usuario la echa de menos. Equivocarse al reves
    cuesta los archivos de alguien, y no se nota hasta que ya no estan.

    LO QUE QUEDA FUERA, CON SU MOTIVO:

      - UNIDADES DE RED. Son el disco de otro ordenador, con la latencia y
        los permisos de otro, y un recorrido completo puede tardar horas o
        molestar a alguien. La guardia las veta hoy y con razon; levantar
        ese veto es un punto propio, no un detalle de este.
      - MOVILES Y CAMARAS POR USB. Cachivache es un programa PARA PC, y
        ademas esos aparatos no son unidades con letra: van por MTP y
        exigen la API del Shell, que es otro mundo entero. Fuera por
        alcance, no por dificultad.
#>

function Get-ClaseDeUnidad {
    <#
    .SYNOPSIS
        Traduce el tipo de unidad que da el sistema a una de las cinco
        clases del programa: fija, extraible, red, optica o desconocida.

    .DESCRIPTION
        ACEPTA LAS DOS FORMAS DE ENTRADA A PROPOSITO, y ese es el motivo de
        que exista esta funcion en vez de una comparacion suelta. El
        programa pregunta por el tipo de unidad de dos maneras distintas
        segun el sitio:

          - [IO.DriveInfo]::GetDrives(), que da un [System.IO.DriveType] y
            se imprime como "Fixed", "Removable", "Network", "CDRom".
            Es lo que usa Get-UnidadesFijas, y por velocidad: una consulta
            CIM cuesta decenas de milisegundos y DriveInfo microsegundos.
          - Win32_LogicalDisk / Get-CimInstance, que da un NUMERO.

        Si esta funcion aceptara solo una de las dos, el dia que un sitio
        cambiara de fuente -o alguien pasara el resultado de Get-Volume,
        que dice "CD-ROM" con guion- la respuesta pasaria a ser
        "desconocida" EN SILENCIO. Y "desconocida" no revienta: solo hace
        que una unidad entera deje de analizarse sin que nadie se entere.
        Es el fallo de [VIS-03] otra vez: degradarse callando.

        Los dos numeros son EL MISMO DATO, no una coincidencia: DriveType
        Fixed y DriveType=3 salen los dos de la GetDriveType de Win32, y
        por eso la tabla numerica vale para las dos fuentes.

        DISCO RAM (6) Y "SIN RAIZ" (1) CAEN EN "DESCONOCIDA", que aqui es
        lo mismo que decir "no se toca". Un disco RAM desaparece al
        reiniciar y una unidad sin raiz no tiene medio dentro: ninguno de
        los dos es un disco fijo, y prometer que se puede borrar en ellos
        no aporta nada que compense el riesgo.

    .PARAMETER Tipo
        El tipo tal y como lo da el sistema: el numero de DriveType, el
        nombre de System.IO.DriveType, o el propio valor de la enumeracion.
        Puede llegar nulo, y entonces la respuesta es "desconocida".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Tipo
    )

    if ($null -eq $Tipo) { return 'desconocida' }

    # [string] sobre el valor de la enumeracion da su nombre y sobre un
    # entero da sus digitos, asi que las tres formas de entrada -numero,
    # nombre y enumeracion- llegan aqui como texto y se deciden abajo.
    $texto = ([string]$Tipo).Trim()
    if ([string]::IsNullOrEmpty($texto)) { return 'desconocida' }

    $numero = 0
    if ([int]::TryParse($texto, [ref]$numero)) {
        switch ($numero) {
            2 { return 'extraible' }
            3 { return 'fija' }
            4 { return 'red' }
            5 { return 'optica' }
            default { return 'desconocida' }
        }
    }

    # ToLowerInvariant y no ToLower: la cultura del sistema no debe poder
    # cambiar el veredicto sobre si en un disco se borra o no.
    switch ($texto.ToLowerInvariant()) {
        'removable' { return 'extraible' }
        'fixed'     { return 'fija' }
        'network'   { return 'red' }
        # Las dos grafias: DriveType dice "CDRom" y Get-Volume "CD-ROM".
        'cdrom'     { return 'optica' }
        'cd-rom'    { return 'optica' }
        default     { return 'desconocida' }
    }
}

function Test-UnidadAnalizable {
    <#
    .SYNOPSIS
        Si el programa debe recorrer una unidad de esta clase, y cuando no,
        por que no.

    .DESCRIPTION
        DEVUELVE UN OBJETO Y NO UN BOOLEANO, y no es capricho. Un "no" que
        no dice por que acaba en una unidad que no aparece en la lista sin
        ninguna explicacion, y eso es indistinguible de un fallo del
        programa: el usuario ve que su disco D: no esta y no puede saber si
        es que se ha decidido no mirarlo o es que algo se ha roto. La misma
        funcion decide y explica, como en [CNF-05].

        Extraible SI, y esa es la novedad de [VIS-04]: analizarla no tiene
        el riesgo que tiene borrar en ella.

        Optica no porque su contenido no se puede limpiar -recorrerla seria
        gastar minutos para acabar sin poder ofrecer nada- y red no por lo
        que explica la cabecera de este archivo.

    .PARAMETER Clase
        Una de las clases que devuelve Get-ClaseDeUnidad. Cualquier otra
        cosa -nula, vacia, un tipo del sistema sin traducir- se trata como
        desconocida, que es la respuesta prudente.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Clase
    )

    # Sin comprobacion de nulo y no es un descuido: el tipo [string] del
    # parametro convierte un nulo en cadena vacia antes de entrar aqui, y
    # la cadena vacia ya cae en el "default", que es la respuesta prudente.
    $normalizada = $Clase.Trim().ToLowerInvariant()

    switch ($normalizada) {
        'fija' {
            return [pscustomobject]@{ Analizable = $true; Clase = 'fija'; Motivo = '' }
        }
        'extraible' {
            return [pscustomobject]@{ Analizable = $true; Clase = 'extraible'; Motivo = '' }
        }
        'red' {
            return [pscustomobject]@{
                Analizable = $false
                Clase      = 'red'
                Motivo     = ('Es una unidad de red, o sea el disco de otro equipo. Cachivache no la ' +
                              'recorre: un análisis completo por la red puede tardar horas y molestar ' +
                              'a quien la comparte.')
            }
        }
        'optica' {
            return [pscustomobject]@{
                Analizable = $false
                Clase      = 'optica'
                Motivo     = ('Es una unidad óptica. Lo que hay grabado en ella no se puede quitar, ' +
                              'así que recorrerla no serviría para liberar ni un byte.')
            }
        }
        default {
            return [pscustomobject]@{
                Analizable = $false
                Clase      = 'desconocida'
                Motivo     = ('No se ha podido saber de qué tipo de unidad es, y ante la duda ' +
                              'Cachivache no la toca.')
            }
        }
    }
}

function Test-PuedeProducirCandidatoBorrable {
    <#
    .SYNOPSIS
        Si en una unidad de esta clase se puede proponer algo para borrar.
        SOLO las fijas.

    .DESCRIPTION
        ESTA FUNCION SOSTIENE [VIS-04] ENTERO. Todo lo demas de este
        archivo se puede equivocar y lo peor que pasa es que una unidad no
        salga en el mapa; si esta se equivoca, el programa propone borrar
        en un disco que puede desaparecer a mitad de la operacion.

        Por eso esta escrita como una lista blanca de UN solo elemento y no
        como una lista negra: "todo menos red y optica" da por bueno
        cualquier tipo nuevo que aparezca -y aparecen: los discos RAM y los
        espacios de almacenamiento ya existen-, mientras que "solo fija"
        deja fuera lo que no se ha decidido todavia. La invariante de
        tests/Extraibles.Tests.ps1 recorre las clases que el codigo
        devuelve, asi que una clase nueva sin decidir entra automaticamente
        en la comprobacion.

        Y por eso NO acepta el tipo del sistema, solo la clase: si
        aceptara las dos cosas, un "Fixed" mal escrito o un numero de una
        fuente distinta podria colarse por la rama equivocada. Quien la
        llame pasa antes por Get-ClaseDeUnidad, que es donde se traduce.

    .PARAMETER Clase
        Una de las clases que devuelve Get-ClaseDeUnidad.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Clase
    )

    # El tipo [string] del parametro ya ha convertido un nulo en cadena
    # vacia, que no es 'fija' y por tanto no borra nada.
    return ($Clase.Trim().ToLowerInvariant() -eq 'fija')
}

function Get-MotivoNoBorrableEnUnidad {
    <#
    .SYNOPSIS
        Lo que lee el usuario cuando algo sale en el informe y no se puede
        borrar por la unidad en la que esta. Cadena vacia si si se puede.

    .DESCRIPTION
        Es la otra mitad de Test-PuedeProducirCandidatoBorrable: la misma
        decision, dicha en castellano. Van juntas a proposito y hay una
        invariante que lo exige -si no se puede borrar, hay texto; si se
        puede, no lo hay-, porque el fallo natural de esta pareja es que
        alguien anyada una clase, la deje sin borrado y se olvide del
        texto: entonces el usuario ve una fila que no puede marcar y NADA
        que le diga por que. Un control que no responde y no se explica es
        indistinguible de uno roto; ese es el fallo de [USO-15].

        El texto dice las dos cosas -que se ha medido y que no se va a
        borrar- porque medir sin borrar es la funcion, no una limitacion
        que haya que disimular: es exactamente lo que hace WizTree.

    .PARAMETER Clase
        Una de las clases que devuelve Get-ClaseDeUnidad.
    .PARAMETER Letra
        La unidad concreta ("D:"), si se sabe. Nombrarla importa cuando hay
        varias conectadas: "esta unidad" obliga al usuario a adivinar cual
        de las tres es.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Clase,
        [AllowNull()] [AllowEmptyString()] [string] $Letra = ''
    )

    if (Test-PuedeProducirCandidatoBorrable -Clase $Clase) { return '' }

    $sujeto = if ([string]::IsNullOrWhiteSpace($Letra)) {
        'esta unidad'
    } else {
        'la unidad {0}' -f $Letra.Trim()
    }

    $normalizada = $Clase.Trim().ToLowerInvariant()

    # Los parentesis alrededor de la concatenacion son imprescindibles: el
    # -f se enlaza mas fuerte que el +, asi que sin ellos solo se formatea
    # el ultimo trozo y el {0} del primero llega literal a la pantalla. Ha
    # mordido cuatro veces en este repositorio.
    switch ($normalizada) {
        'extraible' {
            return (('Se ha medido, pero no se borra nada en {0}: es una unidad extraíble y se puede ' +
                     'desconectar en mitad del borrado, que quedaría a medias sobre un disco que ya ' +
                     'no está. Sale en el mapa y en el informe; para vaciarla, hazlo tú.') -f $sujeto)
        }
        'red' {
            return (('Se ha medido, pero no se borra nada en {0}: es una unidad de red, o sea el disco ' +
                     'de otro equipo, y ahí Cachivache no borra nada.') -f $sujeto)
        }
        'optica' {
            return (('No se borra nada en {0}: es una unidad óptica y lo que hay grabado en ella no se ' +
                     'puede quitar desde aquí.') -f $sujeto)
        }
        default {
            return (('No se borra nada en {0}: no se ha podido saber de qué tipo de unidad es, y ante ' +
                     'la duda Cachivache no borra.') -f $sujeto)
        }
    }
}
