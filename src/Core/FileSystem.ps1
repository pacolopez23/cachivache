<#
.SYNOPSIS
    Medición de tamaños, información de unidades y recorrido de carpetas.
#>

# =====================================================================
#  RUTAS LARGAS  ([COR-02])
# =====================================================================
#
# Windows arrastra un limite historico de 260 caracteres por ruta
# (MAX_PATH). Se puede saltar anteponiendo "\\?\", que le dice a la API
# que no interprete ni normalice nada y admita hasta 32.767 caracteres.
#
# POR QUE IMPORTA AQUI Y NO EN CUALQUIER PROGRAMA
#
# Este dominio es justo donde pasa: un node_modules anidado, una cache de
# Gradle o .next\cache\webpack desbordan el limite sin esfuerzo. Y el
# fallo no era un error: EnumerateFiles lanzaba, el catch lo contaba como
# "inaccesible" y el programa MEDIA DE MENOS y BORRABA DE MENOS, para
# despues informar de "quedan archivos en uso por algun programa abierto".
# Un mensaje falso sobre una carpeta que si se podia borrar.
#
# En PowerShell 5.1 -que es con lo que arranca Cachivache.exe- el
# proveedor de archivos de .NET Framework NO soporta rutas largas aunque
# el registro de Windows lo permita: ese soporte llego a .NET Core. Asi
# que el prefijo no es opcional, es la unica via.
#
# LA REGLA QUE NO SE PUEDE ROMPER
#
# El prefijo vive DENTRO de la llamada a la API y no sale de ahi. Nunca
# se guarda en un candidato, ni se compara, ni se registra, ni se
# ensenya. Si se colara en Ruta, la guardia compararia "\\?\C:\Windows"
# contra su lista negra "C:\Windows" y NO COINCIDIRIA: un prefijo para
# medir mejor se convertiria en un agujero para borrar el sistema. Hay un
# invariante que lo comprueba.

function ConvertTo-RutaLarga {
    <#
    .SYNOPSIS
        Antepone "\\?\" a una ruta de Windows para saltarse MAX_PATH.

    .DESCRIPTION
        CALCULO PURO: no toca el disco. Solo transforma texto, que es lo
        que permite probar aqui la parte que decide si una carpeta del
        usuario se mide entera o a medias.

        Lo que NO se toca, y cada caso tiene su motivo:

          - Lo que ya lleva el prefijo. Ponerlo dos veces lo invalida.
          - Rutas relativas. "\\?\" exige ruta absoluta: la API no
            resuelve nada, y con una relativa produciria una ruta que no
            existe en vez de un error, que es peor.
          - Rutas que no son de Windows (las pruebas corren en Linux) y
            cualquier cosa que no empiece por letra de unidad o por UNC:
            algunos candidatos usan Ruta para etiquetas como
            "docker system prune", que no son rutas de nada.

        Las de red van a "\\?\UNC\servidor\recurso", no a
        "\\?\\\servidor\recurso": es la forma que exige la API.

        Se normalizan las barras y se rechaza lo que lleve "." o ".." como
        segmento, porque con el prefijo la API NO normaliza: un ".." se
        quedaria tal cual y se buscaria una carpeta llamada "..".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $Ruta }
    if ($Ruta.StartsWith('\\?\') -or $Ruta.StartsWith('\\.\')) { return $Ruta }

    $normal = $Ruta.Replace('/', '\')

    # Un segmento "." o ".." con el prefijo se buscaria literalmente.
    foreach ($segmento in $normal.Split('\')) {
        if ($segmento -eq '.' -or $segmento -eq '..') { return $Ruta }
    }

    if ($normal -match '^[A-Za-z]:\\') { return '\\?\' + $normal }
    if ($normal.StartsWith('\\'))      { return '\\?\UNC\' + $normal.Substring(2) }

    return $Ruta
}

function ConvertFrom-RutaLarga {
    <#
    .SYNOPSIS
        Quita el prefijo "\\?\". Lo que sale de una API vuelve a ser una
        ruta normal antes de que la vea nadie.

    .DESCRIPTION
        Se aplica a TODO lo que sale hacia fuera: candidatos, registro,
        informes y mensajes. Un usuario no tiene por que saber que existe
        "\\?\", y la guardia no puede comparar contra rutas que lo lleven.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $Ruta }
    if ($Ruta.StartsWith('\\?\UNC\')) { return '\\' + $Ruta.Substring(8) }
    if ($Ruta.StartsWith('\\?\'))     { return $Ruta.Substring(4) }
    return $Ruta
}

function Test-RutaDemasiadoLarga {
    <#
    .SYNOPSIS
        ¿Esta ruta supera el limite historico de Windows?

    .DESCRIPTION
        260 es MAX_PATH contando el terminador nulo, asi que el limite
        util son 259 caracteres. Se compara sobre la ruta SIN prefijo:
        con el, cualquier ruta pareceria cuatro caracteres mas larga.

        Sirve para decidir si hace falta el prefijo y, sobre todo, para
        avisar en los sitios donde el prefijo no basta.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] [AllowEmptyString()] [string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $false }
    return ((ConvertFrom-RutaLarga -Ruta $Ruta).Length -ge 260)
}

# =====================================================================
#  ARCHIVOS QUE VIVEN EN LA NUBE  ([COR-03])
# =====================================================================
#
# OneDrive "Archivos a petición" deja en el disco un MARCADOR: la entrada
# de directorio existe, con su nombre y su tamaño logico, pero el
# contenido no esta. Se descarga sola la primera vez que alguien ABRE el
# archivo, y ese "alguien" puede ser este programa.
#
# QUE DISPARA UNA DESCARGA Y QUE NO
#
# Conviene ser exacto, porque el arreglo equivocado costaria rendimiento
# sin evitar nada:
#
#   NO la dispara   enumerar carpetas, ni leer Length, Attributes o
#                   LastWriteTime: todo eso sale de la entrada de
#                   directorio, sin abrir el archivo. O sea que MEDIR un
#                   arbol es seguro.
#   SI la dispara   abrir el archivo para leerlo. En este proyecto eso es
#                   Get-HuellaRapida y Get-FileHash, los dos del modulo de
#                   duplicados.
#
# Asi que el problema real esta acotado: comparar duplicados podia
# descargarse gigabytes de OneDrive sin avisar. En una conexion medida,
# eso es dinero del usuario.
#
# Y hay un segundo problema, de la familia de [VIS-03]: un marcador ocupa
# unos pocos kilobytes en el disco, no su tamaño logico. Proponer
# borrarlo y prometer que libera 4 GB seria mentir sobre el espacio, otra
# vez.

# Valores numericos y no [IO.FileAttributes]::RecallOnDataAccess a
# proposito: ese nombre no existe en el .NET Framework con el que corre
# PowerShell 5.1, que es justo donde arranca Cachivache.exe. Un nombre
# que no existe lanza en tiempo de ejecucion; un numero, no.
$script:AtributoOffline             = 0x1000     # FILE_ATTRIBUTE_OFFLINE
$script:AtributoRecallOnOpen        = 0x40000    # FILE_ATTRIBUTE_RECALL_ON_OPEN
$script:AtributoRecallOnDataAccess  = 0x400000   # FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS

function Test-EsMarcadorNube {
    <#
    .SYNOPSIS
        ¿Este archivo esta solo en la nube, sin contenido en el disco?

    .DESCRIPTION
        CALCULO PURO sobre los atributos, para poder probarlo sin tener
        OneDrive ni conexion.

        Se miran los TRES atributos porque los proveedores no coinciden:
        OneDrive marca los suyos con RecallOnDataAccess, mientras que otras
        soluciones de almacenamiento jerarquico usan Offline. Comprobar
        solo uno dejaria fuera a la mitad.

    .PARAMETER Atributos
        El valor de FileInfo.Attributes. Se acepta como entero para que la
        funcion no dependa de que un nombre de la enumeracion exista en la
        version de .NET que toque.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [int] $Atributos)

    $mascara = $script:AtributoOffline -bor
               $script:AtributoRecallOnOpen -bor
               $script:AtributoRecallOnDataAccess
    return (($Atributos -band $mascara) -ne 0)
}

function Test-ArchivoEnNube {
    <#
    .SYNOPSIS
        Lo mismo, pero preguntando por un FileInfo o por una ruta.

    .DESCRIPTION
        Envoltorio comodo para los sitios que ya tienen el objeto a mano.
        No abre el archivo: Attributes viene de la entrada de directorio,
        asi que preguntar esto NO dispara ninguna descarga. Seria
        contraproducente que la comprobacion causara justo lo que trata de
        evitar.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] $Archivo)

    if ($null -eq $Archivo) { return $false }
    try {
        $atributos = if ($Archivo -is [string]) {
            [int][IO.File]::GetAttributes((ConvertTo-RutaLarga -Ruta $Archivo))
        } else {
            [int]$Archivo.Attributes
        }
        return Test-EsMarcadorNube -Atributos $atributos
    } catch {
        # Si no se puede saber, se responde que NO es un marcador. Decir
        # que si haria que el programa se saltara archivos normales por un
        # fallo de lectura, y saltarse cosas en silencio es peor que
        # arriesgarse a una descarga que probablemente no ocurra.
        return $false
    }
}

function Get-CarpetaParaRecorrer {
    <#
    .SYNOPSIS
        El mismo DirectoryInfo, pero preparado para que la enumeracion no
        se tope con MAX_PATH.

    .DESCRIPTION
        Si el prefijo no se puede aplicar -ruta relativa, una etiqueta que
        no es una ruta, o un sistema que no es Windows- se devuelve la
        carpeta tal cual y el recorrido funciona como siempre. Degradar a
        lo de antes es aceptable; fallar al medir, no.
    #>
    [CmdletBinding()]
    [OutputType([IO.DirectoryInfo])]
    param([Parameter(Mandatory)] [IO.DirectoryInfo] $Carpeta)

    $larga = ConvertTo-RutaLarga -Ruta $Carpeta.FullName
    if ($larga -eq $Carpeta.FullName) { return $Carpeta }

    try   { return [IO.DirectoryInfo]::new($larga) }
    catch { return $Carpeta }
}

function Test-EsEnlace {
    <#
    .SYNOPSIS
        Detecta junctions y enlaces simbolicos.
    .DESCRIPTION
        Nunca se sigue ni se borra un punto de reanalisis: borrar el enlace
        podría arrastrar el destino real, que puede estar en cualquier sitio.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param($Elemento)

    if ($null -eq $Elemento) { return $false }
    return [bool]($Elemento.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Join-RutaNativa {
    <#
    .SYNOPSIS
        Une segmentos de ruta sin pasar por el proveedor de PowerShell.
    .DESCRIPTION
        Join-Path resuelve la unidad a traves del proveedor y lanza si la
        letra no existe como unidad real en el proceso -por ejemplo, al
        ejecutar las pruebas fuera de Windows-. Este proyecto ya se topo
        con eso dos veces: en Get-EjecutableDeComando y en la resolucion de
        Docker, y las dos se arreglaron concatenando texto a mano.

        Esta funcion es ese apano, escrito una vez. Usa el separador nativo
        del sistema en lugar de una barra invertida fija, de modo que el
        codigo que construye rutas a partir de carpetas descubiertas en
        disco -bibliotecas de Steam, carpetas de partidas- funciona igual
        en Windows, que es donde se usa de verdad, y bajo las pruebas.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Base, [Parameter(ValueFromRemainingArguments)] [string[]] $Segmentos)

    $separador = [IO.Path]::DirectorySeparatorChar
    $ruta = $Base.TrimEnd([char]'\', [char]'/')
    foreach ($segmento in @($Segmentos)) {
        if ([string]::IsNullOrWhiteSpace($segmento)) { continue }
        foreach ($trozo in ($segmento -split '[\\/]')) {
            if ([string]::IsNullOrWhiteSpace($trozo)) { continue }
            $ruta = $ruta + $separador + $trozo
        }
    }
    return $ruta
}

function Test-RutaExcluida {
    <#
    .SYNOPSIS
        Indica si una ruta la ha excluido el usuario a mano.

    .DESCRIPTION
        La lista de exclusiones es lo que convierte al programa en algo que
        se usa dos veces. Sin ella, el usuario desmarca hoy la carpeta de un
        proyecto vivo y manyana vuelve a salir; y a la tercera deja de leer
        la lista, que es justo cuando un limpiador se vuelve peligroso.

        Excluir una carpeta excluye TODO lo que cuelga de ella. Es lo que
        cualquiera espera al decir "esta carpeta no la toques": nadie quiere
        tener que enumerar tambien sus veinte subcarpetas.

        La comparacion se hace sobre la ruta normalizada -minusculas, sin
        barra final, con un solo tipo de separador- y exigiendo separador
        al comparar el prefijo. Sin esa exigencia, excluir "C:\\Datos"
        excluiria tambien "C:\\Datos Antiguos", que es otra carpeta.

        SE COMPRUEBA EN DOS SITIOS, y es deliberado: en el embudo del
        analisis, donde pasan todos los candidatos de todos los modulos, y
        OTRA VEZ dentro del motor de borrado. El borrado corre en otro
        runspace y puede pasar tiempo entre una cosa y la otra; una
        exclusion que solo se aplicara al analizar seria una promesa que
        el motor no tiene por que cumplir. Ver [CNF-01] en
        docs/HOJA-DE-RUTA.md.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string] $Ruta,
        [string[]] $Excluidas = @()
    )

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $false }

    $lista = @($Excluidas | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lista.Count -eq 0) { return $false }

    # Los DOS separadores se llevan a uno solo, y siempre al mismo, sin
    # preguntarle al sistema cual es el suyo.
    #
    # El primer intento normalizaba la barra normal al separador NATIVO, y
    # eso funciona en Windows -donde el nativo es la invertida- pero no
    # fuera: en Linux el nativo es la normal, asi que "C:\Trabajo" se
    # quedaba con sus barras invertidas, "c:/trabajo/x" con las suyas, y
    # dos formas de escribir la misma ruta no casaban. Lo cazo una prueba.
    # Comparar rutas no debe depender de donde se ejecute la comparacion.
    $normalizar = {
        param([string] $R)
        return $R.Replace('/', '\').TrimEnd([char]'\').ToLowerInvariant()
    }

    $candidata = & $normalizar $Ruta
    foreach ($excluida in $lista) {
        $base = & $normalizar $excluida
        if ([string]::IsNullOrEmpty($base)) { continue }

        if ($candidata.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }

        # El separador es obligatorio: sin el, "C:\Datos" excluiria tambien
        # "C:\Datos Antiguos", que es otra carpeta.
        if ($candidata.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-EsRutaDeVerdad {
    <#
    .SYNOPSIS
        Si un texto es una ruta absoluta y no una etiqueta.

    .DESCRIPTION
        Hace falta porque el campo Ruta de un candidato NO siempre lleva una
        ruta. Para el metodo Comando lleva la orden que se va a ejecutar
        -"docker system prune -a -f"- y para el metodo Papelera lleva una
        etiqueta. Informativo va en los dos casos: el modulo de archivos
        grandes pone rutas de verdad, y el de Windows Update, etiquetas.

        Por eso esto mira el VALOR y no el metodo. Decidirlo por metodo
        habria dejado fuera justo los candidatos informativos que si tienen
        ruta, que son la mayoria.

        Ver [ARQ-03].
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Texto
    )

    if ([string]::IsNullOrWhiteSpace($Texto)) { return $false }

    # La pregunta de fondo es si la cadena esta ANCLADA en algun sitio, no
    # si tiene pinta de Windows. Tres formas:
    #
    #   - Unidad con letra: "C:\..." o "C:/..."
    #   - Recurso de red:   "\\equipo\recurso"
    #   - Raiz POSIX:       "/tmp/..."
    #
    # La tercera no sobra aunque el programa solo corra en Windows. La
    # primera version de esto no la tenia, y la suite -que se ejecuta en
    # Linux- convirtio una ruta de verdad en "etiqueta": la exclusion del
    # usuario dejaba de aplicarse y el archivo se borraba. Lo cazo una
    # prueba de [CNF-01] que ya existia. Una regla que solo es correcta en
    # el sistema donde no se prueba es una regla sin probar.
    return $Texto -match '^[A-Za-z]:[\\/]' -or $Texto.StartsWith('\\') -or $Texto.StartsWith('/')
}

function Get-ClaveExclusion {
    <#
    .SYNOPSIS
        La clave estable con la que el usuario excluye un candidato.

    .DESCRIPTION
        [ARQ-03], y lo dejo escrito [CNF-01] al cerrarse: "la clave de
        exclusion no puede ser la ruta a secas".

        Hasta ahora se excluia comparando contra Ruta. Para lo que tiene
        ruta, bien. Para lo que no -un comando, la papelera-, esa
        comparacion es sobre una ETIQUETA tratada como si fuera una carpeta:
        se normaliza a minusculas, se le quitan barras finales y se le
        aplica una regla de prefijo pensada para jerarquias que ahi no
        existe. "Excluir siempre esto" sobre un comando guardaba un texto
        que no era una ruta dentro de una lista llamada RutasExcluidas.

        Ahora hay dos formas de clave, y se distinguen a la vista:

        - Con ruta de verdad: la clave ES la ruta. El comportamiento no
          cambia ni un byte para todo lo que hoy funciona.
        - Sin ruta: "modulo:<ModuloId>|<Nombre>". Lleva una barra vertical,
          que Windows no admite en una ruta, asi que una clave sintetica no
          puede confundirse jamas con una ruta ni casar con una exclusion
          de carpeta.

        Estable entre analisis: ModuloId y Nombre no dependen de la
        ejecucion. Si dependieran, excluir algo hoy no lo excluiria manyana,
        que es exactamente el fallo que la exclusion viene a arreglar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $ModuloId,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Nombre
    )

    if (Test-EsRutaDeVerdad -Texto $Ruta) { return $Ruta }

    return ('modulo:{0}|{1}' -f $ModuloId, $Nombre)
}

function Test-ClaveExcluida {
    <#
    .SYNOPSIS
        Si el usuario ha excluido este candidato.

    .DESCRIPTION
        Reparte segun la forma de la clave, y es el motivo de que exista:

        - Clave de ruta: se compara con Test-RutaExcluida, o sea por
          prefijo, porque excluir una carpeta excluye lo que cuelga de ella.
        - Clave sintetica: solo coincidencia EXACTA. Una etiqueta no tiene
          jerarquia, asi que comparar por prefijo ahi solo puede excluir de
          mas: "modulo:docker|prune" no contiene a nada.

        Ver [ARQ-03].
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Clave,
        [string[]] $Excluidas = @()
    )

    if ([string]::IsNullOrWhiteSpace($Clave)) { return $false }
    if (Test-EsRutaDeVerdad -Texto $Clave) {
        return (Test-RutaExcluida -Ruta $Clave -Excluidas $Excluidas)
    }

    foreach ($excluida in @($Excluidas)) {
        if ([string]::IsNullOrWhiteSpace($excluida)) { continue }
        if ($Clave.Equals($excluida.Trim(), [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-IdentidadArchivo {
    <#
    .SYNOPSIS
        Identidad del CONTENIDO de un archivo, o $null si no lo comparte
        con nadie.

    .DESCRIPTION
        Un enlace duro no es un acceso directo ni un punto de reanalisis:
        es otra entrada de directorio que apunta al MISMO contenido en
        disco. Dos rutas, un solo archivo, unos solos bytes.

        Y este programa los contaba DOS VECES. El recorrido salta los
        puntos de reanalisis -enlaces simbolicos y uniones- pero un enlace
        duro no lleva ese atributo, asi que pasaba por dos archivos
        distintos. No es teorico: WinSxS es casi todo enlaces duros, y la
        medicion de ese modulo lleva inflada desde siempre. WizTree no
        tiene el problema porque lee la tabla maestra, donde cada archivo
        aparece una vez.

        Dos caminos segun el sistema:

          * PowerShell fuera de Windows expone UnixStat, que trae
            HardlinkCount e Inode.
          * En Windows se mira LinkType, que rellena el proveedor de
            archivos, y la identidad se compone con el conjunto ORDENADO
            de todas las rutas que comparten el contenido: la propia y las
            que devuelve Target. Ese conjunto es identico se pregunte
            desde el enlace que se pregunte, que es justo lo que hace falta.

        RECIBE UNA RUTA, NO UN FileInfo, y eso NO es un descuido. Las dos
        propiedades de arriba las anyade el PROVEEDOR de PowerShell; los
        objetos que devuelve EnumerateFiles vienen de .NET en crudo y no
        las llevan. Preguntarselas a uno de esos devuelve siempre $null y
        la funcion no detecta nada -asi se descubrio, midiendo-. Hay que
        pedir el objeto decorado con Get-Item.

        Y AHI ESTA EL COSTE: un Get-Item por archivo. Por eso quien llama
        tiene que pedirlo expresamente y solo donde compensa. Sin leer la
        tabla maestra de NTFS no hay forma barata de saber cuantos enlaces
        tiene un archivo: es una de las razones de peso para hacer
        [VEL-01], donde este dato viene gratis.

        ANTE LA DUDA, $null. Si no se puede averiguar, el archivo se cuenta
        como se contaba antes. Equivocarse hacia "no lo comparte" mantiene
        el comportamiento actual; equivocarse al reves haria desaparecer
        bytes reales de la medicion.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Ruta)

    # Desde [COR-02] la medicion recorre con el prefijo de ruta larga, asi
    # que aqui llegan rutas con "\\?\" AUNQUE SEAN CORTAS: los hijos
    # heredan la forma del padre. El proveedor de PowerShell no entiende
    # ese prefijo, de modo que sin esta linea Get-Item fallaria siempre, el
    # catch devolveria $null -"no es un enlace duro"- y el conteo de
    # enlaces duros volveria a estar roto EN SILENCIO. Que es exactamente
    # el fallo de [VIS-03], que ya costo descubrir una vez.
    #
    # Solo se quita cuando la ruta cabe sin el: si de verdad es larga, el
    # prefijo es lo unico que permite abrirla.
    if (-not (Test-RutaDemasiadoLarga -Ruta $Ruta)) {
        $Ruta = ConvertFrom-RutaLarga -Ruta $Ruta
    }

    try {
        $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction Stop

        # --- Camino Unix (pruebas, macOS, Linux) ----------------------
        $unix = $item.PSObject.Properties['UnixStat']
        if ($null -ne $unix -and $null -ne $unix.Value) {
            if ([int]$unix.Value.HardlinkCount -le 1) { return $null }
            return 'unix:{0}:{1}' -f $unix.Value.DeviceId, $unix.Value.Inode
        }

        # --- Camino Windows -------------------------------------------
        $tipo = $item.PSObject.Properties['LinkType']
        if ($null -eq $tipo -or $tipo.Value -ne 'HardLink') { return $null }

        $rutas = [Collections.Generic.List[string]]::new()
        $rutas.Add($item.FullName)
        $destino = $item.PSObject.Properties['Target']
        if ($null -ne $destino -and $null -ne $destino.Value) {
            foreach ($otra in @($destino.Value)) {
                if (-not [string]::IsNullOrWhiteSpace($otra)) { $rutas.Add([string]$otra) }
            }
        }
        if ($rutas.Count -lt 2) { return $null }

        return 'win:' + (($rutas | Sort-Object -Unique) -join '|').ToLowerInvariant()
    } catch {
        return $null
    }
}

function Get-HuellaRapida {
    <#
    .SYNOPSIS
        Huella barata de un archivo: su tamaño mas los primeros y ultimos
        64 KB.
    .DESCRIPTION
        Sirve para DESCARTAR parejas antes de calcular el hash completo,
        nunca para afirmar que dos archivos son iguales. Dos archivos con
        huellas distintas son con seguridad distintos; dos con la misma
        huella todavia hay que compararlos entero.

        El motivo es el coste. El modulo de duplicados agrupa por tamaño y
        despues calcula SHA-256 del archivo ENTERO de cada miembro del
        grupo: con el perfil exhaustivo y un umbral de 3 MB, un grupo de
        dos videos de 4 GB obliga a leer 8 GB de disco para decidir si son
        el mismo. Leyendo 128 KB de cada uno se descartan casi todos los
        grupos sin tocar el resto del archivo.

        Los ultimos 64 KB importan tanto como los primeros: dos
        grabaciones de la misma camara, dos ISO de la misma familia o dos
        maquinas virtuales del mismo sistema comparten cabecera y se
        diferencian al final.

        Ver [REN-52] en docs/PLAN-ACCION.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Ruta)

    # Un marcador de OneDrive se DESCARGA en cuanto se abre. Esta es la
    # unica funcion del nucleo que abre archivos del usuario para leerlos,
    # asi que la comprobacion vive aqui y no solo en quien llama: el
    # siguiente que quiera una huella no tiene por que acordarse, y
    # olvidarlo le costaria datos al usuario sin que nada avisara.
    # Devolver cadena vacia es lo mismo que ya se hace cuando no se puede
    # abrir, asi que ningun llamante necesita cambiar. Ver [COR-03].
    if (Test-ArchivoEnNube -Archivo $Ruta) { return '' }

    $trozo = 64KB
    try {
        $flujo = [IO.File]::Open($Ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    } catch {
        return ''
    }

    try {
        $longitud = $flujo.Length
        $hash = [Security.Cryptography.SHA256]::Create()
        try {
            $bufer = New-Object byte[] $trozo

            $leidos = $flujo.Read($bufer, 0, [Math]::Min([int]$trozo, [int][Math]::Min($longitud, [long]$trozo)))
            if ($leidos -gt 0) { [void]$hash.TransformBlock($bufer, 0, $leidos, $bufer, 0) }

            if ($longitud -gt (2 * $trozo)) {
                [void]$flujo.Seek(-$trozo, [IO.SeekOrigin]::End)
                $leidos = $flujo.Read($bufer, 0, [int]$trozo)
                if ($leidos -gt 0) { [void]$hash.TransformBlock($bufer, 0, $leidos, $bufer, 0) }
            }

            [void]$hash.TransformFinalBlock((New-Object byte[] 0), 0, 0)
            return "$longitud-" + [BitConverter]::ToString($hash.Hash).Replace('-', '')
        } finally {
            $hash.Dispose()
        }
    } catch {
        return ''
    } finally {
        $flujo.Dispose()
    }
}

function Get-ResumenArbol {
    <#
    .SYNOPSIS
        Recorre una carpeta y devuelve bytes, número de archivos y la fecha
        de modificacion más reciente en UNA sola pasada.
    .DESCRIPTION
        Es el motor de Measure-Ruta y Measure-RutaDetalle, y el cambio de
        rendimiento más rentable del programa: Get-ChildItem -Recurse
        construye un objeto de PowerShell con su PSObject por cada archivo
        y lo pasa por la canalizacion, mientras que EnumerateFiles devuelve
        directamente lo que da FindNextFile. Sobre 7.200 archivos son
        179 ms frente a 4 ms para la enumeracion pura, y 183 ms frente a
        20 ms contando la suma. Measure-Ruta tiene 18 puntos de llamada.
        Ver docs/RENDIMIENTO.md (sección 1).

        Tres decisiones que no son de velocidad:

        1. Se recorre con una PILA propia y EnumerateDirectories en vez de
           usar AllDirectories, porque hace falta poder SALTAR los puntos
           de reanalisis. AllDirectories los sigue, y seguirlos significa
           contar dos veces el destino de una junction -o dar vueltas en
           un ciclo-. Measure-Ruta ya se negaba a seguir un enlace que le
           dieran como raiz; ahora la regla vale también dentro.

        2. Las propiedades Length y LastWriteTime de los FileInfo que
           devuelve la enumeracion vienen rellenas del propio
           WIN32_FIND_DATA, sin volver al disco. Por eso se pueden leer
           dentro del bucle sin coste y sin que puedan fallar por un
           archivo que desaparezca a mitad.

        3. La fecha más reciente se saca con un máximo sobre ticks. El
           código anterior ORDENABA el array entero para quedarse con el
           primero: 36 ms frente a 2,1 ms con 7.200 archivos.

        Sobre los errores: cada carpeta va en su propio try, así que un
        "acceso denegado" pierde esa carpeta y no el recorrido entero, que
        es lo que hacia Get-ChildItem -ErrorAction SilentlyContinue. Se
        devuelven contados en Inaccesibles por si alguna vez se quieren
        mostrar. NO se escriben en el flujo de error a propósito: con
        ErrorActionPreference = 'Stop' -que es lo que pone Cachivache.ps1 en
        modo consola- cualquier Write-Error aquí abortaria la medición.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [IO.DirectoryInfo] $Carpeta,
        # Patrones opcionales para que el MISMO recorrido responda ademas
        # "hay aqui dentro algo que el usuario querria conservar". Sin
        # esto, 30-RestosProgramas recorria cada carpeta sospechosa tres
        # veces: una para medirla, otra buscando subcarpetas valiosas y
        # otra contando documentos. Tres recorridos completos de disco
        # donde basta uno. Ver [REN-20] en docs/PLAN-ACCION.md.
        [string] $PatronCarpetaValiosa = '',
        [string] $PatronExtensionValiosa = '',
        # Cuenta una sola vez el contenido compartido por varios enlaces
        # duros. Va APAGADO por defecto, y es importante que siga asi:
        # cuesta un Get-Item por archivo (ver Get-IdentidadArchivo), o sea
        # que multiplica el coste del recorrido. Solo compensa donde los
        # enlaces duros son la norma y no la excepcion, que en Windows
        # significa las carpetas del sistema. En las del usuario son tan
        # raros que pagar por buscarlos seria tirar el tiempo.
        # Ver [VIS-03] en docs/HOJA-DE-RUTA.md.
        [switch] $ContarEnlacesDuros
    )

    $bytes        = 0.0
    $archivos     = 0
    $ticksUltimo  = 0L
    $inaccesibles = 0
    $valiosas     = [Collections.Generic.List[string]]::new()
    $documentos   = 0
    $buscaCarpetas   = -not [string]::IsNullOrEmpty($PatronCarpetaValiosa)
    $buscaExtensiones = -not [string]::IsNullOrEmpty($PatronExtensionValiosa)

    # Solo se crea el conjunto si de verdad se va a usar: un HashSet vacio
    # por cada carpeta medida seria pagar por nada en el caso normal.
    #
    # Y se asigna DENTRO del if, no con "$vistos = if (...) { ... }". La
    # segunda forma parece equivalente y no lo es: un if usado como
    # expresion manda su resultado por la canalizacion, y la canalizacion
    # ENUMERA las colecciones. Un HashSet recien creado esta vacio, asi que
    # enumerarlo no produce ni un elemento y $vistos acababa valiendo $null.
    # El conteo de enlaces duros no fallaba: no llegaba a ejecutarse nunca,
    # y en silencio. Se descubrio midiendo, porque el resultado seguia
    # dando el doble.
    $vistos      = $null
    if ($ContarEnlacesDuros) {
        $vistos = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    $compartidos = 0

    $pendientes = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()

    # El recorrido arranca desde la carpeta con el prefijo de ruta larga, y
    # se hace AQUI y no en los ocho sitios que llaman a esta funcion: una
    # regla que hay que recordar en ocho sitios se olvida en el noveno.
    #
    # No es que la carpeta que se mide sea larga -si lo fuera, quien la
    # busco ya habria fallado antes-, es que sus DESCENDIENTES pueden
    # serlo: un node_modules anidado desborda los 260 caracteres a cinco
    # niveles de una ruta corta. Como los hijos que devuelve la
    # enumeracion heredan la forma de su padre, basta con ponerlo en la
    # raiz para que todo el arbol quede cubierto.
    #
    # Sin esto, EnumerateFiles lanzaba PathTooLongException, el catch de
    # abajo lo sumaba a $inaccesibles y el tamaño salia de menos en
    # silencio. Ver [COR-02].
    $pendientes.Push((Get-CarpetaParaRecorrer -Carpeta $Carpeta))

    while ($pendientes.Count -gt 0) {
        $actual = $pendientes.Pop()

        # Dos try INDEPENDIENTES, uno por bucle, y no uno solo alrededor de
        # los dos. Con el try compartido, un "acceso denegado" al enumerar
        # los ARCHIVOS de una carpeta saltaba también su EnumerateDirectories,
        # así que las subcarpetas no se apilaban nunca y la rama entera del
        # arbol se perdia. El sintoma no era un error: era un tamaño más
        # pequeño de lo real, que podia dejar al candidato por debajo del
        # umbral y hacerlo desaparecer de la lista sin que nadie supiera por
        # que. Perder una carpeta no puede costar perder todo lo que cuelga
        # de ella. Ver [SEG-40] en docs/PLAN-ACCION.md.
        try {
            foreach ($archivo in $actual.EnumerateFiles()) {
                $ticks = $archivo.LastWriteTime.Ticks
                if ($ticks -gt $ticksUltimo) { $ticksUltimo = $ticks }

                # El archivo se CUENTA siempre; lo que puede no sumarse
                # son sus bytes, si ya los sumo otro enlace al mismo
                # contenido. Son dos entradas de directorio reales.
                $archivos++
                $sumar = $true
                if ($null -ne $vistos) {
                    $identidad = Get-IdentidadArchivo -Ruta $archivo.FullName
                    if ($null -ne $identidad -and -not $vistos.Add($identidad)) {
                        $sumar = $false
                        $compartidos++
                    }
                }
                if ($sumar) { $bytes += $archivo.Length }

                if ($buscaExtensiones -and $archivo.Extension -match $PatronExtensionValiosa) {
                    $documentos++
                }
            }
        } catch {
            $inaccesibles++
        }

        try {
            foreach ($sub in $actual.EnumerateDirectories()) {
                if ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }

                if ($buscaCarpetas -and $sub.Name -match $PatronCarpetaValiosa) {
                    $valiosas.Add($sub.Name)
                }
                $pendientes.Push($sub)
            }
        } catch {
            $inaccesibles++
        }
    }

    return [pscustomobject]@{
        Bytes        = $bytes
        Archivos     = $archivos
        Ultimo       = if ($ticksUltimo -gt 0) { [datetime]::new($ticksUltimo) } else { $null }
        Inaccesibles = $inaccesibles
        # Solo tienen contenido si se han pedido los patrones.
        CarpetasValiosas = @($valiosas)
        ArchivosValiosos = $documentos
        # Archivos cuyos bytes NO se han sumado porque ya los sumo otro
        # enlace duro al mismo contenido. Cero si no se pidio contarlos.
        Compartidos      = $compartidos
    }
}

# =====================================================================
#  EL RECORRIDO CON EL QUE LOS MODULOS ENCUENTRAN QUE PROPONER ([COR-08])
# =====================================================================
#
# [COR-02] arreglo MEDIR -el prefijo de Get-ResumenArbol- y BORRAR -
# System.IO con el mismo prefijo-. Lo que no arreglo fue ENCONTRAR.
#
# Los modulos recorrian con
#
#     Get-ChildItem -LiteralPath $zona -Recurse -File -Force -ErrorAction SilentlyContinue
#
# y en Windows PowerShell 5.1 eso SE PARA a los 260 caracteres. Bajo ese
# SilentlyContinue no dice absolutamente nada: no hay error, no hay aviso,
# simplemente el arbol termina antes de tiempo. O sea que el programa
# medía bien y borraba bien lo que llegaba a proponer, pero NO PROPONIA lo
# que hay al fondo de una ruta larga -un node_modules anidado, una cache
# de Gradle-. El fallo original de [COR-02] seguia vivo un paso antes.
#
# Esta funcion es el unico recorrido de los modulos, y esta escrita con
# las mismas cuatro reglas que Get-ResumenArbol, que es el modelo:
#
#   1. Pila propia y EnumerateDirectories en vez de AllDirectories,
#      porque hay que poder SALTAR los puntos de reanalisis.
#   2. EnumerateFiles en vez de Get-ChildItem -Recurse. Es lo que permite
#      aplicar el prefijo -el proveedor de PowerShell 5.1 no lo entiende-
#      y ademas ahorra el proveedor entero: la enumeracion pura son 4 ms
#      donde Get-ChildItem -Recurse gasta 179 sobre 7.200 archivos (ver
#      docs/RENDIMIENTO.md, seccion 1).
#
#      OJO CON ESE NUMERO: alli se comparaba SUMAR, que no construye nada.
#      Aqui hay que devolver un objeto por archivo, y eso cuesta unos 19
#      microsegundos, que es del mismo orden que lo que cuesta el objeto
#      de Get-ChildItem en 5.1. O sea que la ganancia grande esta en los
#      modulos que pasan -Filtro -45-AccesosRotos y 85-DockerWsl, donde
#      filtra Windows y no una canalizacion-, y en los demas lo que se
#      gana es correccion, no velocidad. Medido en PowerShell 7 sobre
#      Linux, que es donde se puede medir; en 5.1 esta sin comprobar.
#   3. El prefijo "\\?\" se pone UNA VEZ, en la raiz. Los hijos que
#      devuelve la enumeracion heredan la forma del padre, asi que basta
#      con eso para cubrir el arbol entero.
#   4. Cada carpeta va en su propio try: una carpeta sin permiso pierde
#      esa carpeta, no el recorrido.
#
# Y LA REGLA QUE NO SE PUEDE ROMPER, que aqui es mas dificil que en
# Get-ResumenArbol porque alli lo que salia eran numeros y aqui salen
# RUTAS: la ruta que devuelve este recorrido acaba en el campo Ruta de un
# candidato, y de ahi en la guardia, en la pantalla y en el informe. Si
# llevara el prefijo, la guardia compararia "\\?\C:\Windows" contra su
# lista negra "C:\Windows" y NO COINCIDIRIA. Un prefijo puesto para
# encontrar mejor se convertiria en un agujero para borrar el sistema.
#
# Por eso la ruta que sale NO se lee de FullName: se COMPONE con la ruta
# limpia del padre mas el nombre de la entrada, que es exactamente lo que
# hace .NET por dentro. Asi el prefijo no puede escaparse aunque alguien
# se olvide de quitarlo, porque nunca llega a estar en la cadena que sale.

function Get-ElementosDelArbol {
    <#
    .SYNOPSIS
        Recorre una carpeta entera -sin pararse en los 260 caracteres- y va
        devolviendo lo que encuentra, uno a uno.

    .DESCRIPTION
        Sustituye a Get-ChildItem -Recurse en los modulos. Ver el bloque de
        arriba para el porque; aqui esta el contrato.

        DEVUELVE OBJETOS PROPIOS, NO FileInfo, y es la unica diferencia
        visible. El motivo es la ruta: un FileInfo nacido de una
        enumeracion con prefijo lleva el prefijo METIDO en su FullName, y
        no hay forma de quitarselo sin construir otro objeto. Estos traen
        las mismas propiedades que usaban los modulos -FullName, Name,
        BaseName, Extension, Length, LastWriteTime, LastAccessTime,
        CreationTime, DirectoryName, Attributes- leidas del propio
        WIN32_FIND_DATA, o sea sin volver al disco, mas EsCarpeta. Con eso
        los ocho modulos siguieron funcionando sin tocar ni una linea de su
        logica.

        Y TamanoEnDisco, que es lo unico que NO sale del WIN32_FIND_DATA:
        vale $null salvo que se pida -MedirEnDisco y el archivo lleve la
        marca de compresion de NTFS. $null significa "no lo se", nunca
        "no ocupa nada"; quien decide que hacer con esa diferencia es
        Get-EspacioRecuperable. Ver [VIS-05].

        NO trae Directory (el DirectoryInfo del padre): construirlo cuesta
        un objeto por archivo y ningun llamante lo usa. Si alguna vez hace
        falta, DirectoryName lleva la misma ruta ya limpia.

        LOS PUNTOS DE REANALISIS NO SE SIGUEN, igual que en
        Get-ResumenArbol: seguir una union significa contar y proponer dos
        veces el destino, o dar vueltas en un ciclo. Por defecto tampoco se
        DEVUELVEN; -IncluirEnlaces los devuelve sin entrar en ellos, que es
        lo que necesita quien esta buscando precisamente enlaces.

        LOS OCULTOS Y LOS DE SISTEMA SI SE VEN. Es lo que hacia -Force, y
        no es un detalle: media docena de modulos viven de archivos con el
        atributo oculto -Thumbs.db, desktop.ini, los contenedores de la
        papelera-. EnumerateFiles no filtra por atributos, asi que sale
        gratis, pero hay una prueba que lo fija: si un dia dejaran de
        verse, esos modulos dejarian de encontrar cosas y NADA fallaria.

    .PARAMETER Ruta
        La carpeta por donde se empieza. Si no existe, no se devuelve nada
        y no se lanza: es lo mismo que hacia Get-ChildItem con
        -ErrorAction SilentlyContinue, y hay modulos que preguntan por
        carpetas que pueden no estar.

    .PARAMETER Que
        'Archivos' (por defecto), 'Carpetas' o 'Todo'.

    .PARAMETER Filtro
        Patron de nombre, el mismo que -Filter de Get-ChildItem: lo
        resuelve la propia API de Windows, que es muchisimo mas barato que
        traerse todo y descartar despues.

        SOLO SE APLICA A LOS ARCHIVOS, a proposito. Filtrar carpetas no
        seria filtrar lo que sale: seria decidir POR DONDE SE DESCIENDE, y
        entonces un patron cualquiera se llevaria por delante ramas
        enteras del arbol sin que nadie lo notara. Para no descender esta
        -NoDescender, que se llama asi justamente para que se vea.

    .PARAMETER NoDescender
        Bloque que recibe una carpeta y devuelve $true si NO hay que entrar
        en ella. Es la poda de 20-Proyectos: al encontrar un node_modules
        no hay nada que buscar dentro, y entrar ademas hacia que sus
        'dist' y 'build' se propusieran POR SEPARADO del node_modules que
        los contiene, o sea los mismos bytes contados dos veces.

    .PARAMETER Cancelado
        Bloque que devuelve $true cuando el usuario ha cancelado. Se mira
        una vez por carpeta. Sin el, cancelar no para la enumeracion, solo
        deja de mirar lo que va saliendo.

    .PARAMETER IncluirEnlaces
        Devuelve tambien los puntos de reanalisis. Nunca se entra en ellos,
        se pida o no.

    .PARAMETER MedirEnDisco
        Rellena TamanoEnDisco en los archivos que llevan la marca de
        compresion de NTFS. Ver [VIS-05] y el comentario de la propia rama.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        [ValidateSet('Archivos', 'Carpetas', 'Todo')] [string] $Que = 'Archivos',
        [string] $Filtro = '*',
        [AllowNull()] [scriptblock] $NoDescender,
        [AllowNull()] [scriptblock] $Cancelado,
        [switch] $IncluirEnlaces,
        # Averigua lo que OCUPA de verdad cada archivo comprimido con NTFS,
        # que no es lo que mide. Va APAGADO por defecto, igual que
        # -ContarEnlacesDuros en Get-ResumenArbol y por el mismo motivo:
        # cuesta una llamada al sistema por archivo medido, y quien solo
        # esta enumerando -buscar un .lnk roto, contar cuantos hay- no
        # tiene por que pagarla.
        #
        # Lo que hace barata la rama es el ORDEN: primero Test-EstaComprimido,
        # que es aritmetica sobre unos atributos que la enumeracion ya
        # trajo del WIN32_FIND_DATA, y solo si contesta que si se pregunta
        # al sistema. Los archivos comprimidos son la excepcion, asi que en
        # un arbol normal esto no llega a costar nada aunque se pida.
        # Ver [VIS-05] en docs/HOJA-DE-RUTA.md.
        [switch] $MedirEnDisco
    )

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return }

    # La barra final se quita ANTES de componer nada. Con ella, la primera
    # ruta compuesta saldria con dos separadores seguidos y dejaria de ser
    # igual, como texto, a la que devuelve Windows; y estas rutas se
    # comparan como texto en la guardia, en las exclusiones del usuario y
    # en el comprobador del banco.
    $raizLimpia = $Ruta.TrimEnd([char]'\', [char]'/')
    if ([string]::IsNullOrEmpty($raizLimpia)) { return }

    # El mismo prefijo que Get-CarpetaParaRecorrer pone para medir, pero
    # aplicado a la CADENA y no a un DirectoryInfo ya construido: asi
    # funciona tambien cuando la carpeta de partida ya es larga de por si,
    # que es el caso que el otro camino no puede cubrir porque el
    # constructor habria lanzado antes.
    $rutaApi = ConvertTo-RutaLarga -Ruta $raizLimpia

    try {
        $raiz = [IO.DirectoryInfo]::new($rutaApi)
        if (-not $raiz.Exists) { return }
    } catch {
        # Una etiqueta que no es una ruta ("docker system prune"), una
        # unidad que no existe, caracteres que Windows no admite. Devolver
        # vacio es lo que hacia Get-ChildItem -ErrorAction SilentlyContinue.
        Write-Verbose ("No se puede recorrer '{0}': {1}" -f $Ruta, $_.Exception.Message)
        return
    }

    $separador = [IO.Path]::DirectorySeparatorChar
    $emiteArchivos = ($Que -eq 'Archivos' -or $Que -eq 'Todo')
    $emiteCarpetas = ($Que -eq 'Carpetas' -or $Que -eq 'Todo')
    # El objeto de una carpeta se construye si hay que devolverlo O si hay
    # que preguntarle a la poda, que lo necesita para decidir.
    $armaCarpetas  = $emiteCarpetas -or ($null -ne $NoDescender)

    # Cada marco de la pila lleva DOS cosas: el DirectoryInfo con el que se
    # llama a la API -que puede llevar el prefijo- y la ruta LIMPIA con la
    # que se componen las que salen. Van juntas para que no puedan
    # separarse: una ruta limpia calculada aparte se olvidaria de
    # actualizar en el noveno sitio.
    $pendientes = [Collections.Generic.Stack[object[]]]::new()
    $pendientes.Push(@($raiz, $raizLimpia))

    while ($pendientes.Count -gt 0) {
        if ($null -ne $Cancelado -and (& $Cancelado)) { break }

        $marco  = $pendientes.Pop()
        $actual = [IO.DirectoryInfo]$marco[0]
        $base   = [string]$marco[1]

        # Dos try INDEPENDIENTES, uno por bucle, por lo mismo que en
        # Get-ResumenArbol: con un try compartido, un "acceso denegado" al
        # enumerar los ARCHIVOS se llevaba por delante el
        # EnumerateDirectories de la misma carpeta y la rama entera del
        # arbol se perdia sin un solo error. Ver [SEG-40].
        if ($emiteArchivos) {
            try {
                foreach ($archivo in $actual.EnumerateFiles($Filtro)) {
                    $nombre = $archivo.Name

                    # $null quiere decir "no lo se", y es lo que sale casi
                    # siempre: sin -MedirEnDisco no se pregunta nunca, y con
                    # el solo se pregunta por lo que ya dice estar
                    # comprimido. La medicion de verdad tampoco puede
                    # devolver cero por no saber -Get-TamanoEnDisco contesta
                    # $null-, asi que "no ocupa nada" y "no se ha podido
                    # medir" siguen siendo dos respuestas distintas hasta
                    # Get-EspacioRecuperable, que es quien decide.
                    $enDisco = $null
                    if ($MedirEnDisco -and (Test-EstaComprimido -Atributos ([int]$archivo.Attributes))) {
                        # Se le pasa la ruta LIMPIA, la misma que sale en
                        # FullName: Get-TamanoEnDisco pone el prefijo de
                        # ruta larga por su cuenta, y ponerselo aqui ademas
                        # seria duplicarlo.
                        $enDisco = Get-TamanoEnDisco -Ruta ($base + $separador + $nombre)
                    }

                    [pscustomobject]@{
                        FullName       = $base + $separador + $nombre
                        Name           = $nombre
                        BaseName       = [IO.Path]::GetFileNameWithoutExtension($nombre)
                        Extension      = $archivo.Extension
                        Length         = $archivo.Length
                        LastWriteTime  = $archivo.LastWriteTime
                        LastAccessTime = $archivo.LastAccessTime
                        CreationTime   = $archivo.CreationTime
                        DirectoryName  = $base
                        Attributes     = $archivo.Attributes
                        TamanoEnDisco  = $enDisco
                        EsCarpeta      = $false
                    }
                }
            } catch {
                # NO se escribe en el flujo de error, y es a proposito: en
                # modo consola Cachivache.ps1 pone ErrorActionPreference a
                # 'Stop', asi que un Write-Error aqui abortaria el analisis
                # entero por una sola carpeta sin permisos. Queda el rastro
                # en el flujo detallado, que no aborta nada.
                Write-Verbose ("No se han podido leer los archivos de '{0}': {1}" -f $base, $_.Exception.Message)
            }
        }

        try {
            foreach ($sub in $actual.EnumerateDirectories()) {
                $rutaSub = $base + $separador + $sub.Name
                $esEnlace = ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

                $carpeta = $null
                if ($armaCarpetas) {
                    $carpeta = [pscustomobject]@{
                        FullName       = $rutaSub
                        Name           = $sub.Name
                        BaseName       = $sub.Name
                        Extension      = $sub.Extension
                        Length         = 0.0
                        LastWriteTime  = $sub.LastWriteTime
                        LastAccessTime = $sub.LastAccessTime
                        CreationTime   = $sub.CreationTime
                        DirectoryName  = $base
                        Attributes     = $sub.Attributes
                        # Siempre $null en una carpeta, y la propiedad esta
                        # de todas formas: quien recorre con -Que Todo mira
                        # la misma propiedad en las dos clases de elemento,
                        # y una que unas veces existe y otras no obliga a
                        # preguntar por ella antes de leerla. Una carpeta
                        # comprimida no ocupa lo que ocupan sus archivos:
                        # GetCompressedFileSize contestaria por la ENTRADA
                        # de directorio, que no es la pregunta.
                        TamanoEnDisco  = $null
                        EsCarpeta      = $true
                    }
                }

                if ($emiteCarpetas -and ($IncluirEnlaces -or -not $esEnlace)) { $carpeta }

                # Un punto de reanalisis no se sigue JAMAS, se haya pedido
                # devolverlo o no. Seguirlo seria proponer dos veces lo que
                # hay al otro lado -que puede estar en cualquier sitio- o
                # dar vueltas en un ciclo.
                if ($esEnlace) { continue }
                if ($null -ne $NoDescender -and (& $NoDescender $carpeta)) { continue }

                $pendientes.Push(@($sub, $rutaSub))
            }
        } catch {
            Write-Verbose ("No se han podido leer las subcarpetas de '{0}': {1}" -f $base, $_.Exception.Message)
        }
    }
}

function Measure-Ruta {
    <#
    .SYNOPSIS
        Devuelve el tamaño en bytes de un archivo o de una carpeta completa.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return 0.0 }

    # La ruta se resuelve con Get-Item y no con [IO.Directory]::Exists, y
    # es deliberado: PowerShell entiende cosas que System.IO no -rutas
    # relativas a $PWD, que no es el directorio del proceso; separadores
    # que en un sistema no son separadores- y aquí llegan rutas de todo
    # tipo, incluidas etiquetas como "docker system prune" que algunos
    # candidatos usan de Ruta sin ser una ruta. Se cambia lo que costaba
    # -el RECORRIDO- y no lo que ya funcionaba.
    #
    # Además es una llamada al proveedor menos que antes: el Test-Path
    # previo sobraba, porque un Get-Item que no encuentra nada devuelve
    # $null y eso ya es la respuesta.
    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    if ($null -eq $item)     { return (Measure-RutaLarga -Ruta $Ruta) }
    if (Test-EsEnlace $item) { return 0.0 }
    if (-not $item.PSIsContainer) { return [double]$item.Length }

    return (Get-ResumenArbol -Carpeta $item).Bytes
}

function Measure-RutaLarga {
    <#
    .SYNOPSIS
        Lo que ocupa algo cuya ruta pasa de 260 caracteres, sin pasar por el
        proveedor de PowerShell.

    .DESCRIPTION
        Existe por [COR-08], y es la mitad que faltaba de [COR-02].

        Get-ResumenArbol ya median un arbol con descendientes largos, porque
        el prefijo se pone en la RAIZ y los hijos heredan su forma. Lo que
        no se podia medir era una raiz que YA es larga, y hasta ahora eso no
        pasaba nunca: los modulos no llegaban a encontrar nada tan hondo. Al
        arreglar el recorrido si llegan, y entonces Measure-Ruta devolvia
        cero -Get-Item lanza PathTooLongException y se traga el error-, el
        candidato quedaba por debajo del minimo y desaparecia de la lista.
        O sea: encontrarlo mejor habria servido para tirarlo un paso
        despues, otra vez en silencio.

        Solo se llama cuando Get-Item ha devuelto $null, asi que no cambia
        ni un caso de los que ya funcionaban: donde antes se devolvia cero,
        ahora se mira una vez mas con System.IO, que si admite el prefijo.

        Los puntos de reanalisis siguen midiendo cero, igual que arriba:
        seguir una union significa contar el destino, que puede estar en
        cualquier sitio.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([AllowNull()] [AllowEmptyString()] [string] $Ruta)

    if (-not (Test-RutaDemasiadoLarga -Ruta $Ruta)) { return 0.0 }

    $larga = ConvertTo-RutaLarga -Ruta $Ruta
    if ($larga -eq $Ruta) { return 0.0 }

    try {
        if ([IO.Directory]::Exists($larga)) {
            $carpeta = [IO.DirectoryInfo]::new($larga)
            if (Test-EsEnlace $carpeta) { return 0.0 }
            return (Get-ResumenArbol -Carpeta $carpeta).Bytes
        }
        if ([IO.File]::Exists($larga)) {
            $archivo = [IO.FileInfo]::new($larga)
            if (Test-EsEnlace $archivo) { return 0.0 }
            return [double]$archivo.Length
        }
    } catch {
        # No existe, no hay permiso, o la cadena no era una ruta. Cero es lo
        # que devolvia antes en todos esos casos.
        Write-Verbose ("No se ha podido medir la ruta larga '{0}': {1}" -f $Ruta, $_.Exception.Message)
    }
    return 0.0
}

function Measure-RutaDetalle {
    <#
    .SYNOPSIS
        Tamaño, número de archivos y fecha del último cambio de una carpeta.
    #>
    [CmdletBinding()]
    param([string] $Ruta)

    $resultado = [pscustomobject]@{
        Bytes    = 0.0
        Archivos = 0
        Ultimo   = [datetime]'1900-01-01'
    }
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $resultado }

    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $resultado }

    # Si le dan un archivo suelto, Get-ChildItem -Recurse -File devolvia el
    # propio archivo: un archivo, sus bytes y su fecha. Se conserva, y esta
    # comprobado contra la versión anterior; no es lo que parecia a simple
    # vista, que era caer en la rama de "carpeta vacía".
    if (-not $item.PSIsContainer) {
        $resultado.Bytes    = [double]$item.Length
        $resultado.Archivos = 1
        $resultado.Ultimo   = $item.LastWriteTime
        return $resultado
    }

    $resumen = Get-ResumenArbol -Carpeta $item
    $resultado.Bytes    = $resumen.Bytes
    $resultado.Archivos = $resumen.Archivos
    if ($null -ne $resumen.Ultimo) { $resultado.Ultimo = $resumen.Ultimo }
    else                           { $resultado.Ultimo = $item.LastWriteTime }
    return $resultado
}

function Get-UnidadesAnalizables {
    <#
    .SYNOPSIS
        Lista las unidades que el programa mira, con su espacio, su clase
        y si en ellas se puede borrar.

    .DESCRIPTION
        SE LLAMABA Get-UnidadesFijas Y EL NOMBRE PASO A MENTIR con
        [VIS-04]: ya no devuelve solo las fijas, tambien las extraibles.
        Renombrarla cuesta tocar cuatro sitios; dejarla llamandose "Fijas"
        cuesta que alguien, dentro de seis meses, de por hecho que lo que
        sale de aqui se puede borrar. En este programa esa suposicion se
        paga con archivos de alguien.

        Cada unidad viene con `Clase` y con `Borrable`. **Que aparezca en
        esta lista significa que se ANALIZA, no que se pueda borrar en
        ella**: una extraible entra en el mapa, en la vista de archivos y
        en el informe, y nunca produce un candidato borrable. La regla vive
        en Extraibles.ps1 y el corte esta en el embudo y en el motor.

        Lo de abajo se conserva porque explica por que esto usa DriveInfo.
    .DESCRIPTION
        Con System.IO.DriveInfo y no con Win32_LogicalDisk. Son el mismo
        dato -DriveType Fixed y DriveType=3 salen los dos de la misma
        GetDriveType de Win32- pero una consulta CIM cuesta decenas de
        milisegundos y puede tardar bastante más la primera vez, cuando hay
        que despertar el servicio WMI; DriveInfo son microsegundos.

        Esto se llamaba dos veces en el arranque -Config.ps1 y la cabecera
        del registro- y otra vez cada vez que se refresca el panel de
        Inicio o se cambia de tema. Ver docs/RENDIMIENTO.md (sección 8).

        Y hay un motivo que no es de velocidad: si el servicio WMI esta
        estropeado -pasa más de lo que parece-, la lista de discos se
        quedaba vacía y con ella el panel entero. DriveInfo no depende de
        ningún servicio.

        IsReady es imprescindible: en una unidad no formateada o sin medio,
        leer VolumeLabel o TotalSize lanza IOException.
    #>
    [CmdletBinding()]
    param()

    try   { $unidades = [IO.DriveInfo]::GetDrives() }
    catch { return }

    foreach ($unidad in $unidades) {
        # [VIS-04]. Antes aqui ponia "-ne Fixed", y por eso un disco
        # externo o una llave USB no se analizaban EN ABSOLUTO. Ahora la
        # decision no se toma aqui: se le pregunta a Extraibles.ps1, que
        # es donde vive la regla y donde esta probada.
        $clase = Get-ClaseDeUnidad -Tipo $unidad.DriveType
        if (-not (Test-UnidadAnalizable -Clase $clase).Analizable) { continue }
        if (-not $unidad.IsReady) { continue }

        try {
            $total = [double]$unidad.TotalSize
            # AvailableFreeSpace y no TotalFreeSpace: es el espacio que
            # puede usar ESTE usuario, con sus cuotas si las hay, que es
            # justo lo que devolvia Win32_LogicalDisk.FreeSpace.
            $libre = [double]$unidad.AvailableFreeSpace
            $etiqueta = $unidad.VolumeLabel
        } catch {
            continue
        }

        $usado = $total - $libre
        [pscustomobject]@{
            # Name viene como "C:\" y el resto del programa espera "C:":
            # hay sitios que hacen $unidad.Letra + '\'.
            Letra        = $unidad.Name.TrimEnd('\')
            Etiqueta     = if ([string]::IsNullOrWhiteSpace($etiqueta)) { 'Disco local' } else { $etiqueta }
            Total        = $total
            Libre        = $libre
            PorcentajeUsado = if ($total -gt 0) { [Math]::Round(100 * $usado / $total, 1) } else { 0 }
            # [VIS-04]. Los dos campos nuevos viajan pegados a la unidad
            # para que nadie tenga que volver a clasificarla: dos sitios
            # decidiendo la clase de un disco es como se acaba analizando
            # una llave USB y borrando en ella.
            Clase        = $clase
            Borrable     = (Test-PuedeProducirCandidatoBorrable -Clase $clase)
        }
    }
}

function Get-TipoDeUnidad {
    <#
    .SYNOPSIS
        El DriveType de la unidad a la que pertenece una ruta, o $null si
        no se puede saber.

    .DESCRIPTION
        Existe para [VIS-04]: el segundo corte de Get-MotivoNoSeBorra tiene
        la ruta delante y necesita saber en que clase de disco esta, sin
        depender de que la configuracion traiga la lista de unidades al
        dia. Un disco enchufado despues de arrancar no esta en esa lista.

        ANTE LA DUDA, $null, y quien llama lo traduce a "desconocida". Esa
        eleccion no es neutral y conviene entenderla: devolver $null hace
        que el corte NO se aplique, o sea que el candidato siga su camino y
        lo juzguen las demas comprobaciones -la guardia, la papelera, las
        exclusiones-, que es el comportamiento que habia antes de este
        punto. Inventarse una clase seria peor en las dos direcciones:
        decir "fija" sin saberlo abriria el borrado en un disco que quiza
        se desconecte, y decir "extraible" sin saberlo dejaria al usuario
        sin poder limpiar su propio disco duro.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta)

    $letra = Get-LetraUnidad -Ruta $Ruta
    if ([string]::IsNullOrWhiteSpace($letra)) { return $null }

    try {
        # DriveInfo y no una consulta CIM, por lo mismo que
        # Get-UnidadesAnalizables: microsegundos frente a decenas de
        # milisegundos, y sin depender del servicio WMI.
        return ([IO.DriveInfo]::new($letra + '\')).DriveType
    } catch {
        # Fuera de Windows, o con una letra que no corresponde a ninguna
        # unidad montada, esto lanza. No es un error del que informar: es
        # justo el caso de "no lo se".
        Write-Verbose "No se ha podido saber el tipo de la unidad '$letra': $($_.Exception.Message)"
        return $null
    }
}

function Get-PropiedadUnidad {
    <#
    .SYNOPSIS
        Lee una propiedad de tamaño de una unidad concreta ("C:").
    .DESCRIPTION
        Existia una función por propiedad, con el cuerpo copiado palabra
        por palabra salvo el nombre del campo. Se unifican aquí: cualquier
        arreglo de la consulta solo hay que hacerlo una vez. Ver
        docs/ESTRUCTURA.md (sección 5.4).

        Los nombres de propiedad siguen siendo los de Win32_LogicalDisk
        -FreeSpace y Size- porque son el contrato que ya usaban las cuatro
        llamadas de fuera; por debajo lo resuelve DriveInfo. El motivo del
        cambio esta en Get-UnidadesFijas: esto lo llama el resumen del pie
        cada vez que el usuario marca una casilla, y una consulta CIM ahi
        se nota.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [string] $Unidad,
        [ValidateSet('FreeSpace', 'Size')]
        [string] $Propiedad
    )

    if ([string]::IsNullOrWhiteSpace($Unidad)) { return 0.0 }
    try {
        $disco = [IO.DriveInfo]::new($Unidad)
        if (-not $disco.IsReady) { return 0.0 }
        if ($Propiedad -eq 'Size') { return [double]$disco.TotalSize }
        return [double]$disco.AvailableFreeSpace
    } catch {
        # Letra inexistente, unidad desconectada, cadena que no es una
        # unidad. Cero es lo que devolvia antes en todos esos casos.
        return 0.0
    }
}

function Get-LetraUnidad {
    <#
    .SYNOPSIS
        Letra de unidad de una ruta ("C:"), o cadena vacía si no la tiene.
    .DESCRIPTION
        Devuelve vacío para rutas de red (\\servidor\recurso), para rutas
        relativas y para las etiquetas que algunos candidatos usan como
        Ruta sin ser una ruta de verdad (el método 'Comando'). Quien
        consuma esto debe decidir que hacer con el caso vacío; aquí no se
        adivina.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return '' }
    if ($Ruta -match '^[\\/]{2}')            { return '' }   # \\servidor\...
    if ($Ruta -notmatch '^[A-Za-z]:')        { return '' }
    return $Ruta.Substring(0, 2).ToUpperInvariant()
}

function Test-UnidadSeleccionada {
    <#
    .SYNOPSIS
        Indica si una ruta esta en una unidad que el usuario quiere limpiar.
    .DESCRIPTION
        La lista de unidades elegidas vive en $Configuracion.UnidadesSeleccionadas.
        Se comprueba en ModuleRegistry.ps1, en el mismo sitio por el que pasan
        TODOS los candidatos de TODOS los módulos, para que ninguno pueda
        saltarselo.

        Contrato deliberado en los casos ambiguos: se responde SIEMPRE que
        si. Si la lista esta vacía o no existe (modo consola, configuración
        antigua, pruebas) no hay ninguna exclusión que aplicar; y si la ruta
        no tiene letra de unidad (una etiqueta como "docker system prune",
        un recurso de red) tampoco hay unidad que excluir. Equivocarse hacia
        "no" haría desaparecer candidatos legitimos sin que el usuario
        entendiera por que, y eso es peor que no filtrar.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string] $Ruta,
        $Configuracion
    )

    if ($null -eq $Configuracion) { return $true }
    $propiedad = $Configuracion.PSObject.Properties['UnidadesSeleccionadas']
    if ($null -eq $propiedad) { return $true }

    $elegidas = @($propiedad.Value | Where-Object { $_ })
    if ($elegidas.Count -eq 0) { return $true }

    $letra = Get-LetraUnidad $Ruta
    if ([string]::IsNullOrEmpty($letra)) { return $true }

    foreach ($u in $elegidas) {
        if ((Get-LetraUnidad $u) -eq $letra) { return $true }
    }
    return $false
}

function Get-EspacioLibre {
    <#
    .SYNOPSIS
        Espacio libre en bytes de una unidad concreta ("C:").
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([string] $Unidad)

    return (Get-PropiedadUnidad -Unidad $Unidad -Propiedad 'FreeSpace')
}

function Test-ProcesoAbierto {
    <#
    .SYNOPSIS
        Comprueba si alguno de los procesos indicados esta en ejecución.
    .DESCRIPTION
        Sirve para avisar de que hay que cerrar un programa antes de vaciar
        su cache, porque de lo contrario los archivos en uso se saltan.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string[]] $Nombres)

    # UNA consulta y un conjunto, no un Get-Process por nombre. Cada
    # Get-Process -Name enumera la tabla de procesos entera del sistema, y
    # 10-Caches llama a esta funcion con quince nombres de golpe: quince
    # barridos completos para responder una pregunta que necesita uno.
    # Ver [REN-55] en docs/PLAN-ACCION.md.
    if ($null -eq $Nombres -or @($Nombres).Count -eq 0) { return @() }

    $enMarcha = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($proceso in @(Get-Process -ErrorAction SilentlyContinue)) {
            [void]$enMarcha.Add($proceso.ProcessName)
        }
    } catch {
        # Sin lista de procesos no se puede afirmar que ninguno este
        # abierto. Se devuelve vacio, que es lo que hacia antes cuando
        # Get-Process fallaba: el aviso de "cierra el programa" desaparece,
        # pero nada se borra por eso.
        return @()
    }

    $abiertos = [Collections.Generic.List[string]]::new()
    foreach ($nombre in $Nombres) {
        if ($enMarcha.Contains($nombre)) { $abiertos.Add($nombre) }
    }
    return @($abiertos)
}

function Get-CarpetaConocida {
    <#
    .SYNOPSIS
        Resuelve una carpeta especial del usuario respetando redirecciones.
    .DESCRIPTION
        No se usa "$env:USERPROFILE\Documents" a pelo porque con OneDrive o
        con Windows en otro idioma la carpeta real esta en otro sitio.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('Desktop', 'Documents', 'Pictures', 'Music', 'Videos', 'Downloads')]
        [string] $Nombre
    )

    $ruta = $null
    switch ($Nombre) {
        'Desktop'   { $ruta = [Environment]::GetFolderPath('Desktop') }
        'Documents' { $ruta = [Environment]::GetFolderPath('MyDocuments') }
        'Pictures'  { $ruta = [Environment]::GetFolderPath('MyPictures') }
        'Music'     { $ruta = [Environment]::GetFolderPath('MyMusic') }
        'Videos'    { $ruta = [Environment]::GetFolderPath('MyVideos') }
        'Downloads' {
            # Descargas no tiene entrada en Environment.SpecialFolder.
            $guid  = '{374DE290-123F-4565-9164-39C4925E467B}'
            $clave = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
            $valor = (Get-ItemProperty -Path $clave -Name $guid -ErrorAction SilentlyContinue).$guid
            if ($valor) { $ruta = [Environment]::ExpandEnvironmentVariables($valor) }
            else        { $ruta = Join-Path $env:USERPROFILE 'Downloads' }
        }
    }

    if ([string]::IsNullOrWhiteSpace($ruta)) { return $null }
    return $ruta.TrimEnd('\')
}

function Select-RutasNoAnidadas {
    <#
    .SYNOPSIS
        Filtra una lista de carpetas dejando solo las que no cuelgan de
        ninguna otra de la misma lista.
    .DESCRIPTION
        Con OneDrive y Known Folder Move activado, Get-CarpetaConocida
        'Desktop' puede devolver "OneDrive\Escritorio", que cuelga de la
        propia carpeta "OneDrive" que también se ofrece como zona. Sin este
        filtro, un mismo archivo se indexa dos veces con el mismo FullName
        (una vez por cada zona), y eso es justo lo que permitia que el
        módulo de duplicados propusiera borrar el único ejemplar de un
        archivo creyendo que existia otra copia. Ver [C-02] en
        docs/OPTIMIZACIONES.md.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string[]] $Rutas)

    $aceptadas = [Collections.Generic.List[string]]::new()
    foreach ($ruta in @($Rutas | Sort-Object Length)) {
        $normalizada = $ruta.TrimEnd('\')
        $contenida = $false
        foreach ($padre in $aceptadas) {
            if ($normalizada.Equals($padre, [StringComparison]::OrdinalIgnoreCase) -or
                $normalizada.StartsWith($padre + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $contenida = $true
                break
            }
        }
        if (-not $contenida) { $aceptadas.Add($normalizada) }
    }
    return @($aceptadas)
}
