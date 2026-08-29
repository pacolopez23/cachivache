<#
.SYNOPSIS
    Los manifiestos de winget y de Scoop de una version. Calculo puro, sin
    tocar el disco.

.DESCRIPTION
    Aparte de Publicar-Manifiestos.ps1 igual que Sumas.ps1 lo esta de
    Publicar-Sumas.ps1: este archivo se puede dot-sourcear sin que pase
    nada, el otro escribe archivos.

    POR QUE LOS MANIFIESTOS SE GENERAN Y NO SE ESCRIBEN A MANO
    ----------------------------------------------------------
    Un manifiesto de winget y uno de Scoop declaran las mismas dos cosas: la
    VERSION y el HASH del .zip. Los dos datos los produce ya el flujo de
    publicacion, y los dos cambian en cada version.

    Un manifiesto escrito a mano con el hash de la version anterior no falla
    en ningun sitio: pasa las pruebas, pasa el analizador, se lee
    perfectamente y se sube tal cual. Falla en casa de quien lo instala, con
    un mensaje que dice que el archivo descargado no coincide con lo que el
    manifiesto declaraba -o sea, con la pinta exacta de un paquete
    adulterado-. Es la misma familia de fallo silencioso que [DIS-02], y por
    eso aqui se resuelve igual: el dato sale UNA vez, del archivo real, y de
    ahi lo copia todo el mundo.

    Y no es solo el hash. En este paquete van pegados a la version CUATRO
    datos, no dos:

      - PackageVersion / version:  2.1.0        (sin la v)
      - la URL de descarga:        .../v2.1.0/Cachivache-v2.1.0.zip
      - la carpeta DENTRO del zip: Cachivache-v2.1.0
      - el hash del zip

    La carpeta interior es la mas facil de olvidar: Compress-Archive mete el
    contenido dentro de una carpeta con el nombre de la version, asi que
    NestedInstallerFiles/RelativeFilePath (winget) y extract_dir (Scoop)
    caducan tambien. Cuatro sitios que envejecen en silencio a la vez.

    EL CASO DEL HASH NO ES EL MISMO EN LOS DOS
    ------------------------------------------
    Ver la cabecera de Sumas.ps1, que ya lo cuenta para SHA256SUMS.txt.

      - winget compara sin distinguir mayusculas, y su propia herramienta
        (wingetcreate) escribe el SHA256 en MAYUSCULAS. Se emite en
        mayusculas para que lo que hay en el manifiesto sea identico,
        caracter a caracter, a lo que genera la herramienta oficial: si
        alguien regenera el manifiesto y le sale otra cosa, tiene que ser
        porque el paquete cambio, no por el formato.

      - Scoop lo escribe en MINUSCULAS, y sobre todo: el autoupdate de este
        manifiesto saca el hash de nuestro SHA256SUMS.txt, que Sumas.ps1
        escribe en minusculas a proposito. Si el manifiesto declarase
        mayusculas, la primera version publicada y todas las siguientes
        dirian el mismo hash de dos formas distintas, y cualquier
        comparacion literal entre ambas fallaria.

    Ver [DIS-03] y [DIS-04].
#>

# El hash lo valida Test-SumaSha256Valida, que ya existe y ya esta probada
# desde [DIS-02]. Se dot-sourcea aqui y no se da por supuesto que alguien lo
# haya hecho antes: un archivo que se puede dot-sourcear solo tiene que
# funcionar dot-sourceado solo.
. (Join-Path $PSScriptRoot 'Sumas.ps1')

function Get-IdentidadPaquete {
    <#
    .SYNOPSIS
        Los datos del paquete que no dependen de la version.

    .DESCRIPTION
        Existe para que el nombre del repositorio, el identificador y la
        licencia esten en UN sitio. Los escriben cuatro archivos distintos
        -tres YAML de winget y un JSON de Scoop-, y cuatro copias de una URL
        es como se llega a que tres apunten a un sitio y la cuarta a otro.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        # winget exige Editor.Paquete. Se usa el nombre del autor y no el
        # del usuario de GitHub porque es lo que winget ensenya al instalar.
        IdentificadorWinget = 'FranciscoLopez.Cachivache'
        IdentificadorScoop  = 'cachivache'
        Repositorio         = 'https://github.com/pacolopez23/cachivache'
        Editor              = 'Francisco López'
        UrlEditor           = 'https://github.com/pacolopez23'
        Licencia            = 'MIT'
        Idioma              = 'es-ES'
        Resumen             = 'Limpiador de disco para Windows que enseña qué va a borrar antes de borrarlo.'

        # 1.6.0 y no la ultima: es la version de esquema que soporta
        # NestedInstallerFiles -imprescindible aqui, porque el instalador es
        # un .zip con una carpeta dentro- y la acepta cualquier cliente de
        # winget desde 2023. Subir de version de esquema sin necesidad solo
        # sirve para dejar fuera a clientes viejos.
        VersionManifiesto   = '1.6.0'
    }
}

function Get-VersionDesdeEtiqueta {
    <#
    .SYNOPSIS
        La version sin la 'v' inicial, a partir de la etiqueta de git.

    .DESCRIPTION
        El flujo de publicacion se dispara con etiquetas 'v*' y usa la
        etiqueta ENTERA para el nombre del zip y para la URL de descarga.
        Pero winget y Scoop quieren la version SIN la v: 'v2.1.0' en
        PackageVersion sale en la lista de versiones instalables como
        "v2.1.0" y no ordena igual que las demas.

        Se es estricto a proposito: si la etiqueta no tiene forma de
        etiqueta, se para. Adivinar aqui produce una URL de descarga que
        devuelve 404, y un 404 no lo ve nadie hasta que alguien intenta
        instalar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    if ([string]::IsNullOrWhiteSpace($Etiqueta)) {
        throw 'No hay etiqueta de la que sacar la version.'
    }
    if ($Etiqueta -cnotmatch '^v\d+(\.\d+){1,3}$') {
        throw ("La etiqueta '$Etiqueta' no tiene la forma vX.Y.Z que publica este proyecto.")
    }

    return $Etiqueta.Substring(1)
}

function Get-NombrePaqueteZip {
    <#
    .SYNOPSIS
        Como se llama el .zip de una version.

    .DESCRIPTION
        ESTE ES EL DATO COMPARTIDO DEL PUNTO. El nombre lo decide
        .github/workflows/publicar.yml al armar el paquete ("Cachivache-
        $version.zip"), y lo tienen que repetir la URL de descarga de
        winget, la de Scoop y quien verifique las sumas. Cuatro sitios que
        deciden lo mismo: por eso se decide aqui, y hay una invariante que
        prohibe que el flujo y esta funcion se separen.

        Si alguien renombra el zip en el flujo, hoy no falla nada: se
        publica un paquete con un nombre y dos manifiestos que apuntan a
        otro.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    # Valida la etiqueta aunque no use el resultado: un nombre de zip
    # construido sobre una etiqueta inventada es una URL rota.
    [void](Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta)
    return ('Cachivache-{0}.zip' -f $Etiqueta)
}

function Get-CarpetaDentroDelZip {
    <#
    .SYNOPSIS
        La carpeta que hay DENTRO del .zip.

    .DESCRIPTION
        Compress-Archive -Path Cachivache-v2.1.0 no comprime el contenido de
        la carpeta: comprime la carpeta. Al descomprimir no aparece
        Cachivache.exe, aparece Cachivache-v2.1.0\Cachivache.exe.

        winget lo necesita en RelativeFilePath y Scoop en extract_dir, y los
        dos fallan de la forma mas confusa posible si se equivoca: winget
        instala y luego no encuentra el ejecutable, y Scoop deja al usuario
        una carpeta de mas en medio del acceso directo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    return [IO.Path]::GetFileNameWithoutExtension((Get-NombrePaqueteZip -Etiqueta $Etiqueta))
}

function Get-UrlDescarga {
    <#
    .SYNOPSIS
        La URL de un archivo adjunto a la version de GitHub.

    .DESCRIPTION
        La misma forma que usa GitHub para todo lo que adjunta
        action-gh-release. Sirve para el .zip y para SHA256SUMS.txt, que es
        de donde saca el hash el autoupdate de Scoop.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Archivo
    )

    if ([string]::IsNullOrWhiteSpace($Archivo)) {
        throw 'No se ha dicho de que archivo es la URL.'
    }
    [void](Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta)

    $identidad = Get-IdentidadPaquete
    return ('{0}/releases/download/{1}/{2}' -f $identidad.Repositorio, $Etiqueta, $Archivo)
}

function ConvertTo-EscalarYaml {
    <#
    .SYNOPSIS
        Un valor listo para poner detras de "clave:" en un YAML.

    .DESCRIPTION
        Existe por un fallo concreto y silencioso: en YAML, 2.1 NO es la
        cadena "2.1", es el numero 2.1. Una etiqueta v2.1 -que este proyecto
        admite- produciria "PackageVersion: 2.1", el validador de winget
        veria un numero donde su esquema pide una cadena, y el manifiesto se
        rechazaria en la revision con un error que no habla de versiones.
        Con tres partes (2.1.0) no pasa, y por eso no se nota nunca hasta
        que pasa.

        Lo mismo con true, false, yes, no, on, off, null y ~, que YAML
        convierte; y con los valores que llevan ': ' dentro, que parten la
        linea en dos claves.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Valor
    )

    if ([string]::IsNullOrEmpty($Valor)) { return "''" }

    $pareceNumero  = $Valor -match '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$'
    $pareceBooleano = $Valor -match '^(?i:true|false|yes|no|on|off|null|~)$'
    $indicador     = $Valor -match '^[\s>|&*!%@`#\-?:{}\[\],''"]'
    $parteClave    = $Valor.Contains(': ')
    $bordeConEspacio = $Valor -ne $Valor.Trim()

    if ($pareceNumero -or $pareceBooleano -or $indicador -or $parteClave -or $bordeConEspacio) {
        # Comillas simples: en YAML dentro de ellas no hay escapes salvo la
        # propia comilla, que se duplica. Con comillas dobles habria que
        # pensar en las barras invertidas, y aqui hay rutas de Windows.
        return ("'" + $Valor.Replace("'", "''") + "'")
    }

    return $Valor
}

function Format-ManifiestoWingetVersion {
    <#
    .SYNOPSIS
        El manifiesto 'version' de winget: el que dice que existe el paquete.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    $identidad = Get-IdentidadPaquete
    $version   = Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta

    return (@(
        ('# yaml-language-server: $schema=https://aka.ms/winget-manifest.version.{0}.schema.json' -f $identidad.VersionManifiesto)
        ''
        ('PackageIdentifier: {0}' -f (ConvertTo-EscalarYaml -Valor $identidad.IdentificadorWinget))
        ('PackageVersion: {0}'    -f (ConvertTo-EscalarYaml -Valor $version))
        ('DefaultLocale: {0}'     -f (ConvertTo-EscalarYaml -Valor $identidad.Idioma))
        'ManifestType: version'
        ('ManifestVersion: {0}'   -f (ConvertTo-EscalarYaml -Valor $identidad.VersionManifiesto))
    ) -join "`n") + "`n"
}

function Format-ManifiestoWingetInstalador {
    <#
    .SYNOPSIS
        El manifiesto 'installer' de winget: donde esta el .zip y que hay
        dentro.

    .DESCRIPTION
        Es el unico de los tres que lleva el hash, y el unico que puede
        quedarse obsoleto sin que se vea.

        InstallerType zip + NestedInstallerType portable es lo que hace que
        winget acepte un paquete SIN FIRMAR: no ejecuta ningun instalador,
        descomprime y crea un alias. Por eso [DIS-03] no depende de
        [DIS-01].

        Architecture: neutral, y no x64, porque es la verdad. El programa
        son guiones de PowerShell y un lanzador compilado sin /platform, o
        sea AnyCPU. Declarar x64 dejaria fuera a Windows en ARM64, donde
        esto funciona igual.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Hash
    )

    if (-not (Test-SumaSha256Valida -Suma $Hash)) {
        throw ("El hash del paquete no tiene forma de SHA-256: '$Hash'")
    }

    $identidad = Get-IdentidadPaquete
    $version   = Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta
    $zip       = Get-NombrePaqueteZip -Etiqueta $Etiqueta
    $carpeta   = Get-CarpetaDentroDelZip -Etiqueta $Etiqueta
    $url       = Get-UrlDescarga -Etiqueta $Etiqueta -Archivo $zip

    # Separador de Windows: la ruta es relativa DENTRO del zip y la resuelve
    # winget en Windows. Con barra normal tambien funciona, pero los
    # manifiestos del repositorio de winget la escriben asi y conviene
    # parecerse a lo que ya han revisado mil veces.
    $rutaInterior = '{0}\Cachivache.exe' -f $carpeta

    return (@(
        ('# yaml-language-server: $schema=https://aka.ms/winget-manifest.installer.{0}.schema.json' -f $identidad.VersionManifiesto)
        ''
        ('PackageIdentifier: {0}' -f (ConvertTo-EscalarYaml -Valor $identidad.IdentificadorWinget))
        ('PackageVersion: {0}'    -f (ConvertTo-EscalarYaml -Valor $version))
        'InstallerType: zip'
        'NestedInstallerType: portable'
        'NestedInstallerFiles:'
        ('  - RelativeFilePath: {0}' -f (ConvertTo-EscalarYaml -Valor $rutaInterior))
        ('    PortableCommandAlias: {0}' -f (ConvertTo-EscalarYaml -Valor $identidad.IdentificadorScoop))
        'Installers:'
        '  - Architecture: neutral'
        ('    InstallerUrl: {0}' -f (ConvertTo-EscalarYaml -Valor $url))
        # En MAYUSCULAS: es lo que escribe wingetcreate. Ver la cabecera.
        ('    InstallerSha256: {0}' -f $Hash.ToUpperInvariant())
        'ManifestType: installer'
        ('ManifestVersion: {0}' -f (ConvertTo-EscalarYaml -Valor $identidad.VersionManifiesto))
    ) -join "`n") + "`n"
}

function Format-ManifiestoWingetLocale {
    <#
    .SYNOPSIS
        El manifiesto 'defaultLocale' de winget: lo que lee una persona.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta
    )

    $identidad = Get-IdentidadPaquete
    $version   = Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta

    return (@(
        ('# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.{0}.schema.json' -f $identidad.VersionManifiesto)
        ''
        ('PackageIdentifier: {0}' -f (ConvertTo-EscalarYaml -Valor $identidad.IdentificadorWinget))
        ('PackageVersion: {0}'    -f (ConvertTo-EscalarYaml -Valor $version))
        ('PackageLocale: {0}'     -f (ConvertTo-EscalarYaml -Valor $identidad.Idioma))
        ('Publisher: {0}'         -f (ConvertTo-EscalarYaml -Valor $identidad.Editor))
        ('PublisherUrl: {0}'      -f (ConvertTo-EscalarYaml -Valor $identidad.UrlEditor))
        ('PublisherSupportUrl: {0}' -f (ConvertTo-EscalarYaml -Valor ($identidad.Repositorio + '/issues')))
        ('Author: {0}'            -f (ConvertTo-EscalarYaml -Valor $identidad.Editor))
        'PackageName: Cachivache'
        ('PackageUrl: {0}'        -f (ConvertTo-EscalarYaml -Valor $identidad.Repositorio))
        ('License: {0}'           -f (ConvertTo-EscalarYaml -Valor $identidad.Licencia))
        ('LicenseUrl: {0}'        -f (ConvertTo-EscalarYaml -Valor ($identidad.Repositorio + '/blob/main/LICENSE')))
        ('ShortDescription: {0}'  -f (ConvertTo-EscalarYaml -Valor $identidad.Resumen))
        ('Moniker: {0}'           -f (ConvertTo-EscalarYaml -Valor $identidad.IdentificadorScoop))
        'Tags:'
        '  - limpieza'
        '  - disco'
        '  - espacio'
        '  - powershell'
        '  - windows'
        ('ReleaseNotesUrl: {0}'   -f (ConvertTo-EscalarYaml -Valor ('{0}/releases/tag/{1}' -f $identidad.Repositorio, $Etiqueta)))
        'ManifestType: defaultLocale'
        ('ManifestVersion: {0}'   -f (ConvertTo-EscalarYaml -Valor $identidad.VersionManifiesto))
    ) -join "`n") + "`n"
}

function Format-ManifiestoScoop {
    <#
    .SYNOPSIS
        El manifiesto de Scoop: un solo .json.

    .DESCRIPTION
        Se arma con ConvertTo-Json y no a mano. Escribir JSON concatenando
        cadenas funciona hasta que un valor lleva una comilla o una barra
        invertida, y entonces produce un archivo que no parsea o -peor- que
        parsea con el valor cambiado.

        checkver + autoupdate estan a proposito aunque el manifiesto se
        regenere en cada publicacion: son para el DIA EN QUE ESTO SE OLVIDE.
        Si alguien mete el .json en un bucket y deja de regenerarlo, Scoop
        se actualiza solo mirando las versiones de GitHub, y saca el hash de
        nuestro SHA256SUMS.txt en vez de creerselo. Un manifiesto sin
        autoupdate es el que se queda anclado en la 2.0.0 para siempre.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Etiqueta,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Hash
    )

    if (-not (Test-SumaSha256Valida -Suma $Hash)) {
        throw ("El hash del paquete no tiene forma de SHA-256: '$Hash'")
    }

    $identidad = Get-IdentidadPaquete
    $version   = Get-VersionDesdeEtiqueta -Etiqueta $Etiqueta
    $zip       = Get-NombrePaqueteZip -Etiqueta $Etiqueta
    $carpeta   = Get-CarpetaDentroDelZip -Etiqueta $Etiqueta

    # Comillas SIMPLES en todo lo que lleva $version: son marcadores que
    # sustituye Scoop, no variables de PowerShell. Con comillas dobles
    # PowerShell las expandiria aqui -a cadena vacia- y el autoupdate
    # apuntaria a .../releases/download/v/Cachivache-.zip.
    $plantillaZip = 'Cachivache-v$version.zip'
    $urlAutoupdate = '{0}/releases/download/v$version/{1}' -f $identidad.Repositorio, $plantillaZip

    $manifiesto = [ordered] @{
        version     = $version
        description = $identidad.Resumen
        homepage    = $identidad.Repositorio
        license     = $identidad.Licencia
        url         = (Get-UrlDescarga -Etiqueta $Etiqueta -Archivo $zip)
        # En MINUSCULAS, y no es cosmetico: el autoupdate de aqui abajo saca
        # el hash de SHA256SUMS.txt, que va en minusculas. Ver la cabecera.
        hash        = $Hash.ToLowerInvariant()
        extract_dir = $carpeta

        # bin da el modo consola a quien vive en la terminal -que es el
        # publico de Scoop-, y el acceso directo abre la ventana. Son las
        # dos formas de arrancar el programa y las dos hacen falta: un shim
        # al .exe abriria una ventana desde la terminal sin decir nada.
        bin         = @(, @('Cachivache.ps1', 'cachivache'))
        shortcuts   = @(, @('Cachivache.exe', 'Cachivache'))

        checkver    = [ordered] @{ github = $identidad.Repositorio }
        autoupdate  = [ordered] @{
            url         = $urlAutoupdate
            extract_dir = 'Cachivache-v$version'
            # $baseurl es la URL de arriba sin el nombre del archivo, o sea
            # la carpeta de adjuntos de la version. Ahi es donde
            # action-gh-release deja SHA256SUMS.txt.
            hash        = [ordered] @{ url = '$baseurl/SHA256SUMS.txt' }
        }
    }

    $texto = $manifiesto | ConvertTo-Json -Depth 5

    # Saltos LF y salto final. ConvertTo-Json devuelve CRLF en Windows, y un
    # archivo que se genera en Windows y se revisa en un repositorio de
    # Scoop lleno de LF ensucia cada diferencia entera.
    return (($texto -replace "`r`n", "`n").TrimEnd("`n") + "`n")
}
