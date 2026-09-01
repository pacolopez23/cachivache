<#
.SYNOPSIS
    Registro de actividad: una línea por acción, para auditar que hizo el
    programa. Se rota por meses.

.DESCRIPTION
    El historial de ejecuciones (.json) NO vive aquí: esta en
    Historial.ps1. Son dos cosas distintas con vidas distintas y este
    archivo llego a mezclarlas. Ver docs/ESTRUCTURA.md (sección 5.1).
#>

$script:RutaRegistro = $null

# Cache de la descripcion del sistema operativo. Se declara aqui, junto al
# resto del estado del archivo, y no solo dentro de la funcion que la
# rellena: una variable que solo existe cuando alguien la escribe lanza
# bajo Set-StrictMode, que es lo que PSScriptAnalyzer recomienda activar.
# Ver [SEG-63] en docs/PLAN-ACCION.md.
$script:DescripcionSistema = $null

# Id corto de ESTA sesión de PowerShell (proceso principal o runspace de
# análisis/borrado, que son procesos logicos distintos aunque compartan
# archivo de registro). Va en cada línea para poder separar que escribio
# cada uno cuando dos ejecuciones concurren. Ver [T-05] en
# docs/OPTIMIZACIONES.md.
$script:IdSesion = -join ((1..6) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })

function Get-DescripcionSistema {
    <#
    .SYNOPSIS
        Caption de Win32_OperatingSystem, o '(desconocido)' si el host no
        tiene CIM/WMI (por ejemplo, al ejecutar las pruebas en Linux).
    .DESCRIPTION
        -ErrorAction SilentlyContinue no basta aquí: si el cmdlet Get-CimInstance
        ni siquiera existe en el host, el error es de resolución de comando,
        no de ejecución, y solo un try/catch lo detiene. Compartida por
        Write-CabeceraSesion, Get-InformeDiagnostico y la configuración
        para no repetir el try/catch tres veces.

        La respuesta se recuerda porque el nombre del sistema operativo no
        cambia mientras el programa esta abierto y la consulta CIM cuesta
        decenas de milisegundos: se preguntaba dos veces solo en el
        arranque. Ver docs/RENDIMIENTO.md (sección 8).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrEmpty($script:DescripcionSistema)) {
        return $script:DescripcionSistema
    }
    try {
        $script:DescripcionSistema = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
    } catch {
        $script:DescripcionSistema = '(desconocido)'
    }
    if ([string]::IsNullOrWhiteSpace($script:DescripcionSistema)) {
        $script:DescripcionSistema = '(desconocido)'
    }
    return $script:DescripcionSistema
}

function Initialize-Registro {
    <#
    .SYNOPSIS
        Abre el archivo de registro del mes en curso.
    #>
    [CmdletBinding()]
    param([string] $CarpetaDatos = (Get-CarpetaDatos))

    $carpeta = Join-Path $CarpetaDatos 'registros'
    if (-not (Test-Path -LiteralPath $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    }
    $script:RutaRegistro = Join-Path $carpeta ('cachivache-{0}.log' -f (Get-Date -Format 'yyyy-MM'))
    return $script:RutaRegistro
}

function Write-CabeceraSesion {
    <#
    .SYNOPSIS
        Anota al registro con que versión, entorno y permisos arranca esta
        sesión.
    .DESCRIPTION
        El registro es lo que se pide adjuntar en CONTRIBUTING.md y
        SECURITY.md para depurar un problema, pero antes no decia ni la
        versión del programa ni la de PowerShell ni si iba como
        administrador: el mantenedor recibia líneas sueltas sin saber que
        las había producido. Ver [T-05] en docs/OPTIMIZACIONES.md.
    #>
    [CmdletBinding()]
    param(
        [string] $Perfil       = '',
        [Nullable[bool]] $Admin = $null,
        $Sync = $null
    )

    $admin   = if ($null -ne $Admin) { $Admin } else { Test-EsAdministrador }
    $sistema = Get-DescripcionSistema
    Write-Registro -Sync $Sync -Nivel 'INFO' -Mensaje ('=' * 70)
    Write-Registro -Sync $Sync -Nivel 'INFO' -Mensaje (
        'Sesión {0}  -  Cachivache v{1}  -  PowerShell {2}  -  {3}' -f
        $script:IdSesion, (Get-VersionCachivache), $PSVersionTable.PSVersion, $sistema)
    # Sin el nombre del equipo. SECURITY.md pide adjuntar este registro
    # para reportar un fallo, asi que todo lo que se escriba aqui hay que
    # darlo por publicado. El nombre del equipo no ayudaba a diagnosticar
    # nada y en cambio identificaba a quien colabora.
    Write-Registro -Sync $Sync -Nivel 'INFO' -Mensaje (
        '  Administrador: {0}  -  Perfil: {1}' -f
        $admin, $(if ($Perfil) { $Perfil } else { '(sin especificar)' }))
}

function Get-InformeDiagnostico {
    <#
    .SYNOPSIS
        Vuelca el entorno completo, listo para pegar en una incidencia.
    .DESCRIPTION
        CONTRIBUTING.md pide versión de Windows y de PowerShell, perfil y
        módulos, y el fragmento pertinente del registro. Antes había que
        recopilarlo todo a mano de sitios distintos; -Diagnóstico lo junta
        en un único bloque de texto. Ver [T-05] en docs/OPTIMIZACIONES.md.

        No incluye rutas de archivos del usuario ni nada del contenido de
        sus discos: unidades, letras y espacio libre si, porque eso es lo
        que hace falta para reproducir un fallo de detección de espacio.
    .PARAMETER LineasRegistro
        Cuantas líneas finales del registro del mes en curso incluir. 0
        para omitirlo (por ejemplo, si el registro pudiera contener rutas
        que el usuario prefiera no pegar en una incidencia pública).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Nullable[bool]] $Admin = $null,
        [string] $CarpetaDatos  = (Get-CarpetaDatos),
        [int] $LineasRegistro   = 40
    )

    $admin = if ($null -ne $Admin) { $Admin } else { Test-EsAdministrador }
    $lineas = [Collections.Generic.List[string]]::new()

    $lineas.Add('=== Diagnostico de Cachivache ===')
    $lineas.Add('Versión del programa : {0}' -f (Get-VersionCachivache))
    # Ojo: dentro de los parentesis de .Add(...) la coma separa argumentos
    # del MÉTODO, no del operador -f. Sin el parentesis extra alrededor de
    # todo el -f, esto se parte en dos argumentos y revienta con un error
    # de formato en vez de uno de sobrecarga.
    $lineas.Add(('PowerShell           : {0}  ({1})' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition))
    $lineas.Add('Sistema operativo    : {0}' -f (Get-DescripcionSistema))
    $lineas.Add('Arquitectura         : {0}' -f $env:PROCESSOR_ARCHITECTURE)
    $lineas.Add('Administrador        : {0}' -f $admin)
    $lineas.Add('Estado de subprocesos: {0}' -f [Threading.Thread]::CurrentThread.GetApartmentState())
    try {
        $lineas.Add('Politica de ejecución: {0}' -f (Get-ExecutionPolicy))
    } catch {
        $lineas.Add('Política de ejecución: (no disponible)')
    }
    $lineas.Add('Carpeta de datos     : {0}' -f $CarpetaDatos)
    # Cachivache se salta MAX_PATH con el prefijo "\\?\" pase lo que pase
    # (ver [COR-02]), asi que esto no cambia lo que hace el programa. Se
    # anota porque explica el ENTORNO: en un equipo sin el soporte
    # activado, el Explorador de Windows tampoco puede abrir ni borrar esas
    # carpetas, y eso es justo lo que el usuario intentara hacer cuando lea
    # que ahi hay 3 GB de basura.
    try {
        $largo = Get-ItemProperty -ErrorAction SilentlyContinue `
                    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
        $lineas.Add('Rutas largas Windows : {0}' -f $(
            if ($null -eq $largo)                     { '(no se ha podido leer)' }
            elseif ([int]$largo.LongPathsEnabled -eq 1) { 'activadas' }
            else                                      { 'desactivadas (Cachivache las maneja igual)' }))
    } catch {
        $lineas.Add('Rutas largas Windows : (no se ha podido leer)')
    }
    $lineas.Add('')

    $lineas.Add('--- Unidades ---')
    try {
        foreach ($unidad in @(Get-UnidadesAnalizables)) {
            $lineas.Add(('  {0}  {1}  -  {2} libres de {3} ({4}% usado)' -f
                $unidad.Letra, $unidad.Etiqueta, (Format-Tamano $unidad.Libre),
                (Format-Tamano $unidad.Total), $unidad.PorcentajeUsado))
        }
    } catch {
        $lineas.Add('  (no se han podido enumerar: {0})' -f $_.Exception.Message)
    }
    $lineas.Add('')

    if ($LineasRegistro -gt 0) {
        $lineas.Add('--- Ultimas {0} lineas del registro de este mes ---' -f $LineasRegistro)
        $ruta = if ([string]::IsNullOrWhiteSpace($script:RutaRegistro)) {
            Join-Path (Join-Path $CarpetaDatos 'registros') ('cachivache-{0}.log' -f (Get-Date -Format 'yyyy-MM'))
        } else {
            $script:RutaRegistro
        }
        if (Test-Path -LiteralPath $ruta) {
            @(Get-Content -LiteralPath $ruta -Tail $LineasRegistro) | ForEach-Object { $lineas.Add("  $_") }
        } else {
            $lineas.Add('  (todavía no existe registro para este mes)')
        }
    }

    return ($lineas -join [Environment]::NewLine)
}

function Get-DetalleExcepcion {
    <#
    .SYNOPSIS
        Convierte un error atrapado en una linea que dice DONDE ha pasado.

    .DESCRIPTION
        Los manejadores de la interfaz mostraban solo
        $_.Exception.Message. Para media docena de errores eso basta
        -"acceso denegado"-, pero para el resto no: mensajes como "Los
        tipos de argumentos no coinciden" o "El indice estaba fuera de los
        limites" no dicen nada por si solos. Ni el usuario puede actuar, ni
        quien reciba la incidencia puede empezar a mirar.

        Y ese es el punto: SECURITY.md pide adjuntar el registro para
        reportar un fallo. Un registro lleno de mensajes sin sitio convierte
        cada incidencia en una conversacion de ida y vuelta antes de poder
        mirar una sola linea de codigo.

        Devuelve el mensaje, el tipo de excepcion y el archivo y la linea
        exactos. La pila completa va aparte, para el registro, porque en un
        cuadro de dialogo no la lee nadie.

    .PARAMETER ErrorRecord
        El ErrorRecord tal cual llega a un catch: $_.

    .PARAMETER ConPila
        Anyade la pila de llamadas. Para el archivo de registro, no para la
        pantalla.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # AllowNull, aunque sea obligatorio: esta funcion la llaman
        # manejadores de error, y un diagnostico que revienta al
        # diagnosticar tapa el fallo que venia a explicar. Sin esto, el
        # enlace de parametros rechazaba el nulo ANTES de llegar a la
        # guarda de abajo, que era pura decoracion.
        [Parameter(Mandatory)] [AllowNull()] $ErrorRecord,
        [switch] $ConPila
    )

    if ($null -eq $ErrorRecord) { return '(error desconocido)' }

    $mensaje = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    $tipo    = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.GetType().Name } else { 'Error' }

    # El sitio se saca de InvocationInfo, que es lo que sobrevive al catch.
    # ScriptName puede venir vacio cuando el error nace dentro de un
    # scriptblock creado al vuelo -los cierres de la ventana lo son-, y en
    # ese caso el numero de linea suelto enganiaria mas que ayudar.
    $sitio = ''
    if ($ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.ScriptName)) {
        $sitio = ' [{0}:{1}]' -f (Split-Path -Leaf $ErrorRecord.InvocationInfo.ScriptName),
                                 $ErrorRecord.InvocationInfo.ScriptLineNumber
    }

    $detalle = '{0} ({1}){2}' -f $mensaje, $tipo, $sitio

    if ($ConPila -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
        $pila = ($ErrorRecord.ScriptStackTrace -split "`r?`n" | ForEach-Object { '    ' + $_ }) -join [Environment]::NewLine
        $detalle = $detalle + [Environment]::NewLine + $pila
    }

    return $detalle
}

function Write-Registro {
    <#
    .SYNOPSIS
        Escribe una línea con marca de tiempo en el registro.
    .PARAMETER Nivel
        INFO | AVISO | ERROR | BORRADO | PAPELERA | BLOQUEADO | OMITIDO
    .PARAMETER Sync
        La tabla sincronizada de New-EstadoSincronizado, si la hay. Con
        ella, la línea se ENCOLA en $Sync.ColaRegistro en vez de
        escribirse al archivo directamente: el runspace de análisis o
        borrado y el hilo de la interfaz pueden llamar a esta función a la
        vez sin pisarse, porque ninguno de los dos toca el disco. El único
        que vacía la cola y escribe de verdad es
        Invoke-VaciarColaRegistro, desde el temporizador de la interfaz.
        Sin $Sync (modo consola, que es de un solo hilo) se escribe al
        momento, como antes. Ver [C-19] en docs/OPTIMIZACIONES.md.
    #>
    [CmdletBinding()]
    param(
        # Se admite la cadena vacía a propósito: la interfaz escribe líneas
        # en blanco para separar bloques del registro.
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Mensaje,
        [ValidateSet('INFO', 'AVISO', 'ERROR', 'BORRADO', 'PAPELERA', 'BLOQUEADO', 'OMITIDO', 'SIMULACION')]
        [string] $Nivel = 'INFO',
        $Sync = $null
    )

    $idParte = if ([string]::IsNullOrWhiteSpace($Mensaje)) { '' } else { "[$script:IdSesion] " }
    $linea = '{0}  [{1,-9}]  {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $idParte, $Mensaje

    $cola = $null
    if ($null -ne $Sync -and $Sync -is [Collections.IDictionary] -and $Sync.ContainsKey('ColaRegistro')) {
        $cola = $Sync['ColaRegistro']
    }
    if ($cola -is [Collections.Concurrent.ConcurrentQueue[string]]) {
        $cola.Enqueue($linea)
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:RutaRegistro)) { [void](Initialize-Registro) }
    try {
        Add-Content -LiteralPath $script:RutaRegistro -Value $linea -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Verbose "No se ha podido escribir en el registro: $($_.Exception.Message)"
    }
}

function Invoke-VaciarColaRegistro {
    <#
    .SYNOPSIS
        Escribe a disco, de una vez, todas las líneas que se hayan
        encolado desde la última llamada.
    .DESCRIPTION
        Pensada para llamarse desde el temporizador de la interfaz (cada
        200 ms) y una última vez al terminar un trabajo, para no perder
        las líneas finales escritas justo antes de que el temporizador se
        pare. Es el ÚNICO sitio del programa que escribe el registro
        mientras hay un runspace de análisis o borrado en marcha.

        DEVUELVE las líneas que acaba de escribir, para que la interfaz
        pueda mostrar en pantalla exactamente lo mismo que ha ido al
        archivo. Antes no devolvia nada y la ventana pintaba su propia
        versión reducida de los mensajes por otro camino, de modo que el
        panel de Registro y el .log contaban cosas distintas: las líneas
        que más importan para auditar -una por cada elemento borrado, cada
        comando rechazado por la lista blanca, los errores agrupados del
        análisis- las escribe el runspace y solo llegaban al archivo.

        Devolver la lista, en vez de que la ventana lea el archivo, evita
        volver a abrirlo cinco veces por segundo y evita el desfase de
        tener dos fuentes que se pueden desincronizar.
    .OUTPUTS
        [string[]] con las líneas escritas, o una lista vacía si no había
        nada encolado.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] $Sync)

    if ($Sync -isnot [Collections.IDictionary] -or -not $Sync.ContainsKey('ColaRegistro')) { return @() }
    $cola = $Sync['ColaRegistro']
    if ($cola -isnot [Collections.Concurrent.ConcurrentQueue[string]]) { return @() }
    if ($cola.IsEmpty) { return @() }

    $lineas = [Collections.Generic.List[string]]::new()
    $linea = $null
    while ($cola.TryDequeue([ref] $linea)) { $lineas.Add($linea) }
    if ($lineas.Count -eq 0) { return @() }

    if ([string]::IsNullOrWhiteSpace($script:RutaRegistro)) { [void](Initialize-Registro) }
    try {
        [IO.File]::AppendAllLines($script:RutaRegistro, $lineas, [Text.Encoding]::UTF8)
    } catch {
        Write-Verbose "No se ha podido vaciar la cola del registro: $($_.Exception.Message)"
    }

    # Se devuelven aunque la escritura haya fallado: que no se pueda tocar
    # el disco (permisos, disco lleno) no es motivo para dejar también al
    # usuario sin ver en pantalla lo que esta pasando.
    return $lineas.ToArray()
}

# ---------------------------------------------------------------------------
# Avisos repetidos
# ---------------------------------------------------------------------------
# Un fallo dentro de un manejador de WPF no ocurre una vez: ocurre en cada
# tick del temporizador -cinco veces por segundo- o en cada elemento de una
# lista. El manejador abria un cuadro de dialogo MODAL por cada uno, asi que
# el primer fallo enterraba la ventana bajo una pila de veinte avisos
# identicos que habia que cerrar de uno en uno, sin poder ni siquiera parar
# el analisis que los estaba generando.
#
# Un aviso repetido no informa mas que el primero: informa PEOR, porque tapa
# el programa. Al registro van todos -ahi si interesa saber cuantas veces
# paso-; a la pantalla, el primero de cada clase.

$script:FallosAvisados = @{}
$script:MaximoAvisosDeFallo = 3

function Reset-AvisosDeFallo {
    <#
    .SYNOPSIS
        Olvida que ya se aviso de algo. Para las pruebas y para cada sesion.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo vacía una tabla en memoria.')]
    [CmdletBinding()]
    param()
    $script:FallosAvisados = @{}
}

function Get-VecesQueFallo {
    <#
    .SYNOPSIS
        Cuantas veces se ha visto cada fallo. Para el resumen al cerrar.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return $script:FallosAvisados.Clone()
}

function Get-FirmaDeFallo {
    <#
    .SYNOPSIS
        Que dos apariciones del mismo fallo se reconozcan como el mismo.

    .DESCRIPTION
        El mensaje solo no vale como firma: dos fallos que no tienen nada
        que ver dicen los dos "Referencia a objeto no establecida". El tipo
        solo, tampoco. La firma es tipo + mensaje + la primera linea de la
        pila, que es donde ocurrio de verdad.

        Ante cualquier duda devuelve cadena vacia, y una firma vacia SIEMPRE
        avisa: callar un fallo por un defecto de esta funcion seria bastante
        peor que repetirlo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Excepcion
    )

    if ($null -eq $Excepcion) { return '' }

    $tipo = ''
    $mensaje = ''
    $donde = ''
    try { $tipo = $Excepcion.GetType().FullName } catch { $tipo = '' }
    try { $mensaje = [string]$Excepcion.Message } catch { $mensaje = '' }
    try {
        $pila = [string]$Excepcion.StackTrace
        if (-not [string]::IsNullOrWhiteSpace($pila)) {
            # La primera linea con contenido: el marco donde salto.
            foreach ($linea in ($pila -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($linea)) { $donde = $linea.Trim(); break }
            }
        }
    } catch { $donde = '' }

    $firma = ('{0}|{1}|{2}' -f $tipo, $mensaje, $donde).Trim('|')
    if ([string]::IsNullOrWhiteSpace($firma)) { return '' }
    return $firma
}

function Test-DebeAvisarDelFallo {
    <#
    .SYNOPSIS
        Decide si un fallo se ensenya por pantalla o solo se anota.

    .DESCRIPTION
        Se avisa la PRIMERA vez de cada fallo distinto, y como mucho de tres
        fallos distintos por sesion. A partir de ahi, al registro y nada
        mas: quien esta delante ya sabe que algo va mal, y lo que necesita
        entonces es poder usar el programa para cerrarlo con calma.

        Tres fallos distintos ya son un programa roto y no un incidente. El
        cuarto aviso no lo va a arreglar, y si puede tapar el boton de
        cerrar.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Firma
    )

    if ([string]::IsNullOrWhiteSpace($Firma)) { return $true }

    if ($script:FallosAvisados.ContainsKey($Firma)) {
        $script:FallosAvisados[$Firma] = $script:FallosAvisados[$Firma] + 1
        return $false
    }

    if ($script:FallosAvisados.Count -ge $script:MaximoAvisosDeFallo) {
        return $false
    }

    $script:FallosAvisados[$Firma] = 1
    return $true
}
