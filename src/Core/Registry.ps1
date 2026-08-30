<#
.SYNOPSIS
    Vocabulario de programas instalados, leido del registro de Windows.

.DESCRIPTION
    Todo lo de este archivo es de SOLO LECTURA. El programa no escribe
    jamas en el registro.

    Sirve a un único consumidor: 30-RestosProgramas, que necesita saber
    que nombres reconoce el equipo para no proponer como huerfana una
    carpeta de un programa que si esta instalado.

    La resolución de ejecutables y accesos directos NO vive aquí: esta en
    Ejecutables.ps1. Ver docs/ESTRUCTURA.md (sección 5.3).

    -------------------------------------------------------------------
    POR QUE HAY DOS VOCABULARIOS Y NO UNO

    Este archivo decide, en la practica, cuanta basura encuentra el
    programa. Y durante mucho tiempo la respuesta fue "casi ninguna".

    Todos los nombres iban a un mismo conjunto y se comparaban por
    subcadena en las dos direcciones, con un minimo de cuatro caracteres:

        $conocido.Contains($token) -or $token.Contains($conocido)

    El problema no es la comparacion, es lo que hay dentro del conjunto.
    Junto a nombres utiles -"Adobe Acrobat DC", "Ubisoft Game Launcher"-
    entraban nombres de SERVICIO ("themes", "power", "spooler"), de
    PROCESO ("node", "code") y de todos los accesos directos del menu
    Inicio ("games", "manual", "leeme"). En un equipo real son entre 2.000
    y 6.000 tokens, y muchos son palabras genericas cortas.

    Con la comparacion por subcadena, cualquier carpeta que contuviera una
    de esas palabras quedaba declarada "conocida" y no se miraba NUNCA.
    "EA Games" contiene "games". "Warframe Launcher" contiene "launcher".
    "PowerDVD Cache" contiene "power". Los restos de juegos, que es lo que
    mas espacio ocupa y lo que el usuario mas quiere encontrar, eran
    justo los que mas facil casaban.

    La correccion no es endurecer la comparacion a secas -eso convertiria
    falsos negativos en falsos positivos-, sino distinguir de donde sale
    cada nombre:

      FUERTES  Evidencia de que un programa concreto esta instalado:
               DisplayName de la lista de desinstalacion, nombre de la
               carpeta de InstallLocation y de Archivos de programa.
               Valen para coincidencia exacta Y para prefijo.

      DEBILES  Indicios genericos: nombres de servicio, de proceso, de
               paquete de la Store, de acceso directo, de entrada de
               arranque y de editor. Valen SOLO para coincidencia exacta.
               Que exista un servicio llamado "power" no dice
               absolutamente nada sobre una carpeta llamada "PowerDVD".

    Ver [DET-10] en docs/PLAN-ACCION.md.
#>

# Longitud minima de un token para que signifique algo. Por debajo de
# esto se responde "conocido" para no proponer carpetas cuyo nombre no
# distingue nada. Estaba en 4 y dejaba fuera del examen a "obs", "vlc" o
# "nvda", que son nombres de carpeta reales. Ver [DET-11].
$script:LongitudMinimaToken = 3

# Para que dos tokens se consideren el mismo programa por prefijo hacen
# falta las dos cosas: longitud suficiente y que el trozo compartido sea
# la mayor parte del nombre mas largo. Con 0.7, "Adobe Acrobat" casa con
# "Adobe Acrobat DC" (12/14) pero "Discord" no casa con "Discord Canary"
# (7/13), que es una aplicacion distinta y puede ser un resto de verdad.
$script:LongitudMinimaPrefijo = 6
$script:RatioMinimoPrefijo    = 0.7

function New-VocabularioInstalado {
    <#
    .SYNOPSIS
        Contenedor vacio de los dos conjuntos de nombres.
    .DESCRIPTION
        El indice por prefijo agrupa los tokens FUERTES por sus tres
        primeras letras. Sin el, comprobar el prefijo obligaria a recorrer
        el conjunto entero por cada carpeta, que es exactamente el bucle
        O(n*m) que se esta eliminando. Si un token es prefijo de otro y los
        dos superan la longitud minima, comparten por fuerza las tres
        primeras letras: agrupar por ahi es exacto, no una aproximacion.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria: no toca el sistema.')]
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Fuertes       = [Collections.Generic.HashSet[string]]::new()
        Debiles       = [Collections.Generic.HashSet[string]]::new()
        IndicePrefijo = [Collections.Generic.Dictionary[string, Collections.Generic.List[string]]]::new()
    }
}

function Add-TokenVocabulario {
    <#
    .SYNOPSIS
        Anade un nombre al vocabulario, como fuerte o como debil.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo modifica una estructura en memoria.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Vocabulario,
        [string] $Texto,
        [switch] $Fuerte
    )

    if ([string]::IsNullOrWhiteSpace($Texto)) { return }

    # Se guardan las dos formas: con version y sin ella. Asi "Python 3.9"
    # reconoce una carpeta llamada "Python" y al reves. Ver [DET-01].
    # El texto se normaliza UNA vez y la variante se deriva del token, no
    # del texto: normalizar es lo caro de las dos operaciones.
    $base = ConvertTo-Token $Texto
    foreach ($token in @($base, (Remove-SufijoVersion $base))) {
        if ($token.Length -lt $script:LongitudMinimaToken) { continue }

        if ($Fuerte) {
            [void]$Vocabulario.Fuertes.Add($token)

            if ($token.Length -ge $script:LongitudMinimaPrefijo) {
                $clave = $token.Substring(0, 3)
                if (-not $Vocabulario.IndicePrefijo.ContainsKey($clave)) {
                    $Vocabulario.IndicePrefijo[$clave] = [Collections.Generic.List[string]]::new()
                }
                if (-not $Vocabulario.IndicePrefijo[$clave].Contains($token)) {
                    $Vocabulario.IndicePrefijo[$clave].Add($token)
                }
            }
        } else {
            [void]$Vocabulario.Debiles.Add($token)
        }
    }
}

function Get-TokensProgramasInstalados {
    <#
    .SYNOPSIS
        Vocabulario de todo lo que hay instalado o en marcha en el equipo.

    .DESCRIPTION
        Se recolectan nombres desde ocho fuentes. Cada una entra como
        FUERTE o como DEBIL segun cuanta evidencia aporte de que un
        programa concreto sigue instalado; la cabecera del archivo explica
        por que esa distincion es la que decide si el programa encuentra
        basura o no.

        CADA FUENTE VA EN SU PROPIO TRY, y es deliberado. Son ocho fuentes
        OPCIONALES: ninguna es imprescindible y varias pueden no existir en
        un equipo concreto. Get-AppxPackage no esta en Windows Server Core
        ni en una instalacion sin el modulo Appx; Get-Service tampoco
        existe fuera de Windows. Un comando que NO EXISTE lanza
        CommandNotFoundException, que -ErrorAction SilentlyContinue no
        atrapa, asi que sin estos try la fuente menos importante de las
        ocho tumbaba el vocabulario entero y con el, el modulo de restos.

        Perder una fuente significa reconocer menos programas, o sea
        proponer de mas. Perderlas todas significa no proponer nada. La
        primera se degrada; la segunda se rompe.
    #>
    [CmdletBinding()]
    param($Sync = $null)

    $vocabulario = New-VocabularioInstalado

    # Ejecuta una fuente y anota el fallo sin propagarlo.
    $recolectar = {
        param([string] $Nombre, [scriptblock] $Accion)
        try { & $Accion } catch {
            Write-Verbose "No se ha podido leer la fuente '$Nombre': $($_.Exception.Message)"
        }
    }

    # 1. Programas desinstalables (32 y 64 bits, por máquina y por usuario)
    #
    #    Faltaba la clave WOW6432Node de HKCU: los programas de 32 bits
    #    instalados por el usuario -que son muchos: casi todo lo que se
    #    instala sin pedir permisos de administrador- no aportaban ni un
    #    token, asi que sus carpetas se proponian como huerfanas. Un falso
    #    positivo servido desde la propia lista de "lo que hay instalado".
    #    Ver [DET-12].
    Set-Progreso $Sync 'Leyendo la lista de programas instalados...'
    & $recolectar 'programas instalados' {
        $clavesDesinstalacion = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($clave in $clavesDesinstalacion) {
            Get-ItemProperty -Path $clave -ErrorAction SilentlyContinue | ForEach-Object {
                # DisplayName es la evidencia mas directa que existe de que
                # algo esta instalado: es lo que el usuario ve en
                # "Aplicaciones instaladas".
                Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.DisplayName -Fuerte
                if ($_.InstallLocation) {
                    Add-TokenVocabulario -Vocabulario $vocabulario `
                                         -Texto (Split-Path $_.InstallLocation -Leaf) -Fuerte
                }
                # El editor NO: que Ubisoft tenga algo instalado no dice
                # nada sobre una carpeta suelta llamada "Ubisoft Old".
                Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Publisher
            }
        }
    }

    # 2. Carpetas de Archivos de programa
    Set-Progreso $Sync 'Revisando Archivos de programa...'
    & $recolectar 'Archivos de programa' {
        foreach ($carpeta in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $carpeta) { continue }
            Get-ChildItem -LiteralPath $carpeta -Directory -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Name -Fuerte }
        }
    }

    # 3. Procesos en ejecución
    & $recolectar 'procesos en ejecución' {
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.ProcessName
            # $_.Company obliga a leer el FileVersionInfo del ejecutable,
            # que es una lectura de disco por proceso y lanza en los
            # procesos protegidos del sistema. Ver [SEG-70].
            try {
                if ($_.Company) { Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Company }
            } catch {
                Write-Verbose "Sin editor para el proceso $($_.ProcessName)."
            }
        }
    }

    # 4. Aplicaciones de la Store
    Set-Progreso $Sync 'Revisando aplicaciones de la Store...'
    & $recolectar 'aplicaciones de la Store' {
        Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object {
            Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Name -Fuerte
            Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Publisher
        }
    }

    # 5. Accesos directos del menu Inicio
    & $recolectar 'menu Inicio' {
        foreach ($menu in @(
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu'))) {
            # Get-ElementosDelArbol y no Get-ChildItem -Recurse, y aqui el
            # motivo de [COR-08] va AL REVES que en los modulos: este
            # vocabulario es la lista de "cosas que estan instaladas", y lo
            # consulta Test-TokenConocido para decidir si una carpeta
            # sobrante es de algo conocido. Un acceso directo que no se
            # llegue a leer no hace que se proponga de menos: hace que una
            # carpeta legitima parezca desconocida y SE PROPONGA PARA
            # BORRAR. Pararse a los 260 caracteres aqui era el error caro.
            Get-ElementosDelArbol -Ruta $menu -Filtro '*.lnk' |
                ForEach-Object { Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.BaseName }
        }
    }

    # 6. Servicios
    & $recolectar 'servicios' {
        Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
            Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.DisplayName
            Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Name
        }
    }

    # 7. Entradas de arranque
    & $recolectar 'entradas de arranque' {
        foreach ($clave in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
            $valores = Get-ItemProperty -Path $clave -ErrorAction SilentlyContinue
            if ($null -eq $valores) { continue }
            $valores.PSObject.Properties |
                Where-Object { $_.Name -notlike 'PS*' } |
                ForEach-Object { Add-TokenVocabulario -Vocabulario $vocabulario -Texto $_.Name }
        }
    }

    return $vocabulario
}

function Test-TokenConocido {
    <#
    .SYNOPSIS
        Comprueba si un nombre de carpeta corresponde a algo instalado.

    .DESCRIPTION
        Tres reglas, en orden de coste creciente:

          1. Token demasiado corto -> conocido. Ante la duda, no se
             propone: un nombre de dos letras no distingue nada.
          2. Coincidencia EXACTA contra cualquiera de los dos conjuntos.
             Es una consulta a un HashSet, O(1).
          3. Coincidencia por PREFIJO contra los tokens fuertes, en las
             dos direcciones y exigiendo que el trozo compartido sea al
             menos el 70% del nombre mas largo. Solo se comparan los
             tokens que empiezan por las mismas tres letras, gracias al
             indice: son unos pocos, no los miles del conjunto entero.

        La version anterior recorria el conjunto completo por cada carpeta
        haciendo dos Contains: entre 2.000 y 6.000 tokens por cada una de
        las 300 a 800 carpetas de las tres zonas, es decir millones de
        comparaciones de cadena en PowerShell interpretado. Era, a la vez,
        la razon de que el modulo no encontrara nada y de que tardara.
        Ver [DET-10] y [REN-10].
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Nombre,
        [Parameter(Mandatory)] $Vocabulario
    )

    $token = ConvertTo-Token $Nombre
    if ($token.Length -lt $script:LongitudMinimaToken) { return $true }

    # Se deriva del token ya calculado, no del nombre: esta funcion se
    # llama una vez por carpeta y normalizar dos veces el mismo texto era
    # duplicar la parte cara de la consulta.
    $variantes = @($token)
    $sinVersion = Remove-SufijoVersion $token
    if ($sinVersion -ne $token -and $sinVersion.Length -ge $script:LongitudMinimaToken) {
        $variantes += $sinVersion
    }

    # --- Regla 2: coincidencia exacta ---------------------------------
    foreach ($variante in $variantes) {
        if ($Vocabulario.Fuertes.Contains($variante)) { return $true }
        if ($Vocabulario.Debiles.Contains($variante)) { return $true }
    }

    # --- Regla 3: prefijo, solo contra tokens fuertes -----------------
    foreach ($variante in $variantes) {
        if ($variante.Length -lt $script:LongitudMinimaPrefijo) { continue }

        $clave = $variante.Substring(0, 3)
        if (-not $Vocabulario.IndicePrefijo.ContainsKey($clave)) { continue }

        foreach ($conocido in $Vocabulario.IndicePrefijo[$clave]) {
            $largo = if ($variante.Length -ge $conocido.Length) { $variante } else { $conocido }
            $corto = if ($variante.Length -ge $conocido.Length) { $conocido } else { $variante }

            if (-not $largo.StartsWith($corto, [StringComparison]::Ordinal)) { continue }
            if (($corto.Length / $largo.Length) -ge $script:RatioMinimoPrefijo) { return $true }
        }
    }

    return $false
}
