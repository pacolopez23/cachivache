<#
.SYNOPSIS
    Que programas externos puede lanzar este programa, y de donde salen.

.DESCRIPTION
    Aquí se responde a UNA sola pregunta, y es una pregunta de seguridad:
    dado un nombre, cual es el ejecutable que se va a lanzar de verdad -o
    ninguno-. No se lanza nada desde este archivo; solo se decide.

    Estaba repartida entre dos sitios que no se citaban entre si:
    Resolve-EjecutablePermitido vivia en Remove.ps1, entre las funciones
    que borran archivos, y Resolve-EjecutableDeSistema en Ejecutables.ps1,
    entre las que leen accesos directos y entradas de arranque. Quien
    auditara "que puede ejecutar esto" tenia que dar con las dos por su
    cuenta. Juntas se leen de una sentada, que es de lo que trata
    SECURITY.md. Ver docs/ESTRUCTURA.md (sección 4.5).

    SON DOS PUERTAS DISTINTAS, a propósito:

      Resolve-EjecutablePermitido   el motor de BORRADO. Lista blanca
                                    cerrada de tres nombres. Es lo único
                                    que puede lanzar Remove.ps1 al
                                    ejecutar el método 'Comando'.

      Resolve-EjecutableDeSistema   consultas de SOLO LECTURA durante el
                                    análisis. Sin lista de nombres, pero
                                    anclado a System32: lo único que puede
                                    salir de ahi es lo que Windows tiene
                                    instalado.

    Ninguna de las dos consulta jamas el PATH, porque el PATH puede
    contener carpetas donde el usuario -o cualquier cosa que corra como
    el- puede escribir.

    ESO ERA MENTIRA HASTA [SEG-30]. La frase de arriba llevaba escrita
    desde que existe el archivo, pero la rama de 'docker' -y la de 'npm',
    que ya no existe- resolvia con Get-Command, que es exactamente el PATH.
    Y el PATH de cualquier usuario de Windows incluye
    %LOCALAPPDATA%\Microsoft\WindowsApps, que el usuario puede escribir:
    dejar ahi un docker.exe bastaba para que el motor de borrado lo
    lanzara. Ahora la resolución esta anclada a las ubicaciones reales de
    instalación y, ademas, se rechaza cualquier ruta que resulte estar en
    una carpeta escribible por el usuario. Ver docs/PLAN-ACCION.md.
#>

# Lista blanca de ejecutables que el método 'Comando' tiene permitido
# lanzar, por nombre base (sin ruta ni extensión). Antes de esto,
# Invoke-EliminacionCandidato ejecutaba $Candidato.Comando ENTERO a traves
# de "cmd.exe /c", que interpreta '&', '|' y '%VAR%', y no comprobaba nada
# contra ninguna lista. Ahora Comando es solo texto para MOSTRAR: lo que
# se ejecuta de verdad es Ejecutable + Argumentos por separado, sin pasar
# nunca por un interprete de shell. Ver [C-03] en docs/OPTIMIZACIONES.md.
#
# npm ESTUVO aquí, por el método 'NpmClean'. Ya no, y con el se ha ido el
# propio método: ver [SEG-21] en docs/PLAN-ACCION.md. El resumen es que
# resolver 'npm' devuelve npm.cmd, un script por lotes, y ejecutar un .cmd
# pasa por cmd.exe SIEMPRE, con lo que la lista blanca de ejecutables
# reintroducia por la puerta de atras el interprete de shell que [C-03]
# habia quitado por la de delante. Como el propio código reconocia que
# "npm cache clean" no libera espacio -lo libera vaciar la carpeta, que es
# lo que se hace de todos modos-, la solución con menos superficie era
# quitarlo entero en vez de blindarlo.
#
# Lo que la ventana abre cuando el usuario lo pide -el Explorador, un
# informe, el navegador- no pasa por ninguna de estas dos funciones y
# tiene sus propias reglas. Todo junto, en SECURITY.md, sección "Lo que el
# programa nunca hace".
$script:EjecutablesPermitidos = @('dism', 'docker')

# Ubicaciones donde Docker Desktop se instala de verdad. Se prueban en
# orden y se coge la primera que exista. Ninguna es escribible por un
# usuario sin privilegios, que es justo lo que las hace utilizables aquí.
$script:RutasDocker = @(
    'Docker\Docker\resources\bin\docker.exe'
    'Docker\Docker\resources\docker.exe'
    'Docker\docker.exe'
)

function Resolve-EjecutablePermitido {
    <#
    .SYNOPSIS
        Resuelve un nombre de ejecutable a su ruta absoluta si esta en la
        lista blanca del método 'Comando', o $null si no.
    .DESCRIPTION
        La comparacion es por el NOMBRE BASE, sin ruta ni extensión, para
        que un candidato no pueda colarse declarando una ruta arbitraria
        que solo "contenga" un nombre permitido. DISM se resuelve siempre
        bajo System32 del propio equipo, nunca por PATH: mismo criterio
        que ya usa Get-EjecutableDeComando para no fiarse de rutas
        relativas.

        Docker se resuelve contra la lista de rutas de instalación reales,
        bajo Archivos de programa. Antes se resolvia con Get-Command, o
        sea por PATH, que es donde estaba el agujero. Ver [SEG-30].
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Ejecutable)

    if ([string]::IsNullOrWhiteSpace($Ejecutable)) { return $null }
    # [IO.Path]::GetFileNameWithoutExtension solo reconoce '\' como
    # separador en Windows: en otro sistema lo trataria como parte del
    # nombre y "C:\ruta\dism.exe" no se reduciria a "dism". Se normaliza a
    # mano antes para que la extraccion del nombre base no dependa del
    # sistema operativo en el que corra esto (incluidas las pruebas).
    $normalizado = $Ejecutable.Trim().Replace('\', '/')
    $nombre = [IO.Path]::GetFileNameWithoutExtension($normalizado).ToLowerInvariant()
    if ($script:EjecutablesPermitidos -notcontains $nombre) { return $null }

    switch ($nombre) {
        'dism' {
            return (Resolve-EjecutableDeSistema -Nombre 'Dism.exe')
        }
        'docker' {
            # Anclado a las carpetas de Archivos de programa, nunca por
            # PATH. Un usuario sin privilegios no puede escribir ahi, que
            # es la única propiedad que hace que fiarse de esta ruta sea
            # distinto de fiarse de cualquier otra. Ver [SEG-30].
            foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
                if ([string]::IsNullOrWhiteSpace($base)) { continue }
                foreach ($relativa in $script:RutasDocker) {
                    # Concatenacion de texto, no Join-Path: Join-Path
                    # resuelve la unidad a traves del proveedor de
                    # PowerShell y lanza si "C:" no existe como unidad real
                    # en el proceso -por ejemplo al correr las pruebas en
                    # Linux-. Mismo motivo que en Get-EjecutableDeComando.
                    $ruta = $base.TrimEnd('\') + '\' + $relativa
                    if (Test-Path -LiteralPath $ruta -PathType Leaf) { return $ruta }
                }
            }
            return $null
        }
    }
    return $null
}

function Get-RutaExplorador {
    <#
    .SYNOPSIS
        Ruta absoluta del Explorador de Windows.
    .DESCRIPTION
        El programa abre carpetas en cinco sitios distintos, y hasta ahora
        lo hacia con Start-Process explorer.exe, a pelo. Un nombre suelto lo
        resuelve Windows mirando primero la carpeta del propio programa y
        el directorio actual, y solo despues System32. Como el .zip se
        descomprime donde quiera el usuario -tipicamente Descargas, que
        esta llena de cosas ajenas-, dejar ahi un explorer.exe bastaba para
        que se ejecutara ese.

        explorer.exe vive en la raiz de Windows, no en System32, asi que no
        vale Resolve-EjecutableDeSistema.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { return $null }
    $ruta = Join-Path $env:SystemRoot 'explorer.exe'
    if (Test-Path -LiteralPath $ruta -PathType Leaf) { return $ruta }
    return $null
}

function Get-RutaPowerShell {
    <#
    .SYNOPSIS
        Ruta absoluta de Windows PowerShell 5.1.
    .DESCRIPTION
        Por el mismo motivo que Get-RutaExplorador, pero esto importa
        bastante mas: es lo que se lanza al reiniciar como administrador,
        o sea la UNICA linea del programa que ejecuta algo elevado. Un
        powershell.exe ajeno resuelto por orden de busqueda ahi no es una
        molestia, es una escalada de privilegios servida en bandeja.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { return $null }
    $ruta = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ruta -PathType Leaf) { return $ruta }
    return $null
}

function Resolve-EjecutableDeSistema {
    <#
    .SYNOPSIS
        Devuelve la ruta absoluta de una herramienta de Windows bajo
        System32, o $null si no esta.

    .DESCRIPTION
        Existe para que NINGÚN sitio del programa invoque un programa
        externo por su nombre suelto. Hacerlo lo resuelve a traves del
        PATH, y el PATH puede contener carpetas donde el usuario -o
        cualquier cosa que corra como el- puede escribir: basta con dejar
        ahi un 'vssadmin.exe' para que se ejecute el suyo en vez del de
        Windows. El módulo de archivos de sistema hacia justo eso, y además
        dentro de la rama que solo corre CON PRIVILEGIOS DE ADMINISTRADOR,
        que es el peor sitio posible para no saber que binario se lanza.

        No lleva lista blanca de nombres porque no la necesita: al anclar
        la ruta a System32 del propio equipo, lo único que se puede lanzar
        es lo que Windows tiene instalado ahi. La lista blanca de arriba
        responde a otra pregunta -que programas puede lanzar el motor de
        BORRADO- y sigue siendo la que manda allí.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Nombre)

    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { return $null }
    # Solo un nombre de archivo: nada de rutas ni de subir por el arbol.
    if ($Nombre -match '[\\/:]' -or $Nombre.Contains('..')) { return $null }

    $ruta = Join-Path (Join-Path $env:SystemRoot 'System32') $Nombre
    if (Test-Path -LiteralPath $ruta -PathType Leaf) { return $ruta }
    return $null
}
