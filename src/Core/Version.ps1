<#
.SYNOPSIS
    Versión del programa, y el aviso de que hay una nueva. Único sitio donde
    se toca la versión al publicar.

.DESCRIPTION
    Aquí viven dos cosas muy distintas y conviene no confundirlas:

    1. El CALCULO PURO de si una etiqueta publicada es más nueva que la
       instalada. No toca nada de fuera y se prueba entero.
    2. La CONSULTA A LA RED, que es una sola función, aislada a propósito,
       que nunca lanza y que devuelve cadena vacía cuando no puede saberlo.

    Sobre la red: el programa NO se conecta por su cuenta. Ni al arrancar,
    ni al abrir un panel, ni con un temporizador de fondo. La consulta
    ocurre únicamente cuando el usuario pulsa el botón de Acerca de. Ver
    [DIS-05] en docs/HOJA-DE-RUTA.md y la nota del README.
#>

$script:VersionCachivache = '2.0.0'
$script:RepositorioUrl   = 'https://github.com/pacolopez23/cachivache'

function Get-VersionCachivache {
    [OutputType([string])]
    param()
    return $script:VersionCachivache
}

function ConvertTo-PartesVersion {
    <#
    .SYNOPSIS
        Una etiqueta de versión convertida a sus tres números, o $null si no
        se entiende.

    .DESCRIPTION
        Esta es la pieza donde esta todo el riesgo del punto. Si se
        equivoca, el programa o no avisa nunca o avisa siempre, y las dos
        cosas son igual de inutiles.

        Lo que hace, y por que:

        - Quita la 'v' de delante. La etiqueta de la publicacion es
          "v2.1.0" y la version instalada es "2.1.0": comparar las dos tal
          cual dice que son distintas SIEMPRE, y el programa avisaria de una
          version nueva en cada pulsacion.
        - Devuelve NUMEROS, no texto. Alfabeticamente "2.10.0" es MENOR que
          "2.9.0" porque el caracter '1' va antes que el '9'. Con una
          comparacion de cadenas, el dia que se publique la 2.10.0 nadie se
          entera. Es el fallo clasico de esto y es silencioso.
        - Admite etiquetas de una, dos y tres partes, y las completa con
          ceros: "2.1" y "2.1.0" son la misma version.
        - Cualquier otra cosa devuelve $null, y quien llama entiende $null
          como "no lo se". Deliberadamente estricto: una etiqueta que no se
          entiende no puede producir un aviso, porque un aviso falso empuja
          al usuario a descargar algo que no existe. Eso deja fuera las
          preversiones ("2.1.0-beta") a proposito: de una beta no se avisa.
        - Como maximo nueve digitos por parte, que es lo que cabe en un
          entero de 32 bits. Sin ese limite, una etiqueta absurda revienta
          la conversion en vez de devolver $null.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    if ([string]::IsNullOrWhiteSpace($Etiqueta)) { return $null }

    $texto = $Etiqueta.Trim()
    if ($texto -match '^[vV]') { $texto = $texto.Substring(1).Trim() }

    if ($texto -notmatch '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$') { return $null }

    $partes = @(0, 0, 0)
    $indice = 0
    foreach ($trozo in $texto.Split('.')) {
        $partes[$indice] = [int]$trozo
        $indice++
    }

    # La coma de delante es obligatoria: sin ella PowerShell desenrolla el
    # array al devolverlo y quien llama recibe tres enteros sueltos.
    return ,[int[]]$partes
}

function Format-VersionNormalizada {
    <#
    .SYNOPSIS
        La etiqueta escrita siempre igual: "v2.1" -> "2.1.0". Cadena vacía
        si no se entiende.

    .DESCRIPTION
        Existe por dos motivos. Uno de presentacion: el usuario no tiene por
        que ver una vez "2.1" y otra "v2.1.0" segun de donde salga el dato.

        Y otro de seguridad, que es el que de verdad importa: la etiqueta
        publicada VIENE DE LA RED. Todo lo que se ensenya en la ventana pasa
        antes por aqui, asi que lo que se pinta son los numeros que se han
        entendido, nunca el texto tal cual llego. Si la respuesta trae
        cualquier otra cosa, esto devuelve vacio y el panel dice que no ha
        podido comprobarlo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    $partes = ConvertTo-PartesVersion -Etiqueta $Etiqueta
    if ($null -eq $partes) { return '' }
    return ($partes -join '.')
}

function Compare-VersionCachivache {
    <#
    .SYNOPSIS
        1 si Izquierda es más nueva, -1 si es más vieja, 0 si son la misma.
        $null si alguna de las dos no se entiende.

    .DESCRIPTION
        Se compara parte a parte y de izquierda a derecha, que es como se
        ordenan las versiones: el mayor primero manda, y solo se mira el
        siguiente numero cuando hay empate.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[int]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Izquierda,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Derecha
    )

    $unas = ConvertTo-PartesVersion -Etiqueta $Izquierda
    $otras = ConvertTo-PartesVersion -Etiqueta $Derecha
    if ($null -eq $unas -or $null -eq $otras) { return $null }

    for ($i = 0; $i -lt 3; $i++) {
        if ($unas[$i] -gt $otras[$i]) { return 1 }
        if ($unas[$i] -lt $otras[$i]) { return -1 }
    }
    return 0
}

function Test-HayVersionNueva {
    <#
    .SYNOPSIS
        Si la publicada es más nueva que la instalada. Falso ante la duda.

    .DESCRIPTION
        Ante cualquier duda -una etiqueta rara, una respuesta vacia, una
        version instalada que no se entiende- responde $false. Callarse
        cuando no se sabe es lo correcto aqui: el coste de no avisar es que
        el usuario actualiza mas tarde, y el de avisar de mas es que deja
        de creerse los avisos.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Instalada,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Publicada
    )

    $comparacion = Compare-VersionCachivache -Izquierda $Publicada -Derecha $Instalada
    if ($null -eq $comparacion) { return $false }
    return ($comparacion -gt 0)
}

function Get-AvisoActualizacion {
    <#
    .SYNOPSIS
        Que tiene que decir el panel Acerca de: el texto y si hay que
        ofrecer la descarga.

    .DESCRIPTION
        La DECISION entera vive aqui, en una funcion pura, y no repartida
        entre el manejador del boton y el XAML. Es la regla 2 del relevo, y
        aqui ademas hace falta porque la ventana no se puede ejecutar en el
        entorno donde se escribe esto: si la decision estuviera en un
        disparador del XAML, no habria forma de comprobarla.

        Los tres estados son excluyentes y ninguno miente:
        no se ha podido saber, hay una version nueva, o estas al dia.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Instalada,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Publicada
    )

    $laInstalada = Format-VersionNormalizada -Etiqueta $Instalada
    $laPublicada = Format-VersionNormalizada -Etiqueta $Publicada

    if ($laInstalada -eq '' -or $laPublicada -eq '') {
        return [pscustomobject]@{
            Hay     = $false
            Version = ''
            Texto   = 'No se ha podido comprobar si hay una versión nueva. Vuelve a intentarlo más tarde o mira la página del proyecto.'
        }
    }

    if (Test-HayVersionNueva -Instalada $Instalada -Publicada $Publicada) {
        return [pscustomobject]@{
            Hay     = $true
            Version = $laPublicada
            Texto   = ('Hay una versión nueva: la {0}. La tuya es la {1}.' -f $laPublicada, $laInstalada)
        }
    }

    return [pscustomobject]@{
        Hay     = $false
        Version = $laPublicada
        Texto   = ('Estás al día: no hay publicada ninguna versión más nueva que la {0}.' -f $laInstalada)
    }
}

function Get-UrlUltimaVersion {
    <#
    .SYNOPSIS
        La página de la última publicación, que es la que se abre en el
        navegador.

    .DESCRIPTION
        Se avisa y se abre la pagina; el programa NO se actualiza a si
        mismo. El .zip se descomprime donde el usuario quiera, asi que
        sustituir los archivos "en su sitio" significa adivinar cual es ese
        sitio, y ademas hacerlo mientras el propio programa se esta
        ejecutando desde ahi. Ver [DIS-05].
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Repositorio = $script:RepositorioUrl)

    if ([string]::IsNullOrWhiteSpace($Repositorio)) { return '' }
    return ($Repositorio.Trim().TrimEnd('/') + '/releases/latest')
}

function Get-UrlApiUltimaVersion {
    <#
    .SYNOPSIS
        La dirección a consultar para saber cual es la última publicación.

    .DESCRIPTION
        Se DERIVA de la direccion del repositorio, que ya estaba en este
        archivo, en vez de escribirse aparte. Dos direcciones que hay que
        cambiar a la vez son dos direcciones que acaban apuntando a sitios
        distintos, y el sintoma seria que el aviso deja de funcionar sin
        que nadie se entere.

        Si la direccion del repositorio no tiene la forma esperada se
        devuelve cadena vacia, y entonces no se consulta nada.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Repositorio = $script:RepositorioUrl)

    if ([string]::IsNullOrWhiteSpace($Repositorio)) { return '' }

    $base = $Repositorio.Trim().TrimEnd('/')
    if ($base.EndsWith('.git')) { $base = $base.Substring(0, $base.Length - 4) }

    $coincidencia = [regex]::Match($base, '^https://github\.com/([^/]+)/([^/]+)$')
    if (-not $coincidencia.Success) { return '' }

    return ('https://api.github.com/repos/{0}/{1}/releases/latest' -f
            $coincidencia.Groups[1].Value, $coincidencia.Groups[2].Value)
}

function Get-UltimaVersionPublicada {
    <#
    .SYNOPSIS
        La etiqueta de la última publicación, o cadena vacía si no se ha
        podido averiguar. NUNCA lanza.

    .DESCRIPTION
        Este es el UNICO sitio del programa que abre una conexion, y se
        llama solo cuando el usuario pulsa el boton de Acerca de.

        Tres decisiones, y las tres tienen el mismo motivo: no saber si hay
        una version nueva no es un problema del usuario.

        1. NUNCA LANZA. Sin red, con un proxy que corta, con la API
           limitando por peticiones o con una respuesta que no es la
           esperada, se devuelve cadena vacia y el panel dice que no ha
           podido comprobarlo. Un cuadro de error por esto seria ruido.
        2. TIEMPO DE ESPERA CORTO. Sin el, una red que acepta la conexion y
           luego no contesta deja esto esperando el plazo por defecto.
        3. NO ESCRIBE EN EL REGISTRO. Se usa Write-Verbose porque esta
           funcion se ejecuta en un runspace aparte que solo tiene cargado
           este archivo; llamar alli a Write-Registro seria llamar a algo
           que no existe.

        Dos detalles que no son opcionales y que fallan en silencio:

        - La cabecera User-Agent. La API de GitHub responde 403 sin ella, y
          el sintoma seria "nunca hay version nueva".
        - TLS 1.2. PowerShell 5.1 hereda de .NET Framework una lista de
          protocolos que en equipos sin actualizar no lo incluye, y GitHub
          no acepta nada por debajo. Se anyade al valor que ya hubiera en
          vez de sustituirlo, porque es un ajuste de todo el proceso.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Url = (Get-UrlApiUltimaVersion),
        [int] $TiempoEspera = 6
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "No se ha podido pedir TLS 1.2: $($_.Exception.Message)"
    }

    try {
        $cabeceras = @{
            'User-Agent' = 'Cachivache'
            'Accept'     = 'application/vnd.github+json'
        }
        $respuesta = Invoke-RestMethod -Uri $Url -Method Get -Headers $cabeceras `
                                       -TimeoutSec $TiempoEspera -ErrorAction Stop
        if ($null -eq $respuesta) { return '' }
        return [string]$respuesta.tag_name
    } catch {
        Write-Verbose "No se ha podido consultar la última versión: $($_.Exception.Message)"
        return ''
    }
}
