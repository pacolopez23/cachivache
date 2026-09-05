<#
.SYNOPSIS
    Configuración del EQUIPO: se descubre en cada arranque, no se guarda.

.DESCRIPTION
    Unidades, carpetas conocidas del usuario, permisos de administrador y
    los umbrales que aplica el perfil elegido.

    Las preferencias persistentes del usuario NO viven aquí: están en
    Preferencias.ps1. Ver docs/ESTRUCTURA.md (sección 5.2).
#>

function Test-EsAdministrador {
    <#
    .SYNOPSIS
        Indica si el proceso actual tiene permisos de administrador.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identidad)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-CarpetaDatos {
    <#
    .SYNOPSIS
        Carpeta donde el programa guarda registros, informes e historial.
    .DESCRIPTION
        Se usa LOCALAPPDATA y no la carpeta del propio programa para que el
        repositorio se pueda clonar en solo lectura y para no ensuciar el
        arbol de trabajo con datos generados.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    # TERCERA RED, y hizo falta. Las dos de arriba son variables de
    # entorno, y hay entornos donde no existe NINGUNA de las dos: PowerShell
    # sobre Linux no define TEMP, y un servicio de Windows puede correr sin
    # LOCALAPPDATA. Sin esto, esta funcion devolvia $null y quien la usaba
    # reventaba con "Cannot bind argument to parameter 'Path'" -en cascada,
    # una vez por cada Join-Path de aqui abajo-. GetTempPath() no es una
    # variable: la resuelve .NET y siempre contesta algo.
    if ([string]::IsNullOrWhiteSpace($base)) { $base = [IO.Path]::GetTempPath() }
    $carpeta = Join-Path $base 'Cachivache'

    foreach ($sub in @('', 'informes', 'registros')) {
        $ruta = if ($sub) { Join-Path $carpeta $sub } else { $carpeta }
        if (-not (Test-Path -LiteralPath $ruta)) {
            New-Item -ItemType Directory -Path $ruta -Force | Out-Null
        }
    }
    return $carpeta
}


function New-Configuracion {
    <#
    .SYNOPSIS
        Descubre las carpetas del equipo y compone el objeto de configuración.
    .DESCRIPTION
        El resultado se pasa a todos los módulos y a la guardia. Nunca
        contiene rutas escritas a mano: todo se resuelve en tiempo de
        ejecución para que el programa funcione en cualquier equipo y con
        Windows en cualquier idioma.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Lee el entorno y devuelve un objeto: no modifica nada.')]
    [CmdletBinding()]
    param(
        [string] $Perfil = 'equilibrado'
    )

    $carpetaDatos = Get-CarpetaDatos

    $configuracion = [pscustomobject]@{
        # --- Carpetas del usuario ---------------------------------------
        Escritorio   = Get-CarpetaConocida 'Desktop'
        Documentos   = Get-CarpetaConocida 'Documents'
        Descargas    = Get-CarpetaConocida 'Downloads'
        Imagenes     = Get-CarpetaConocida 'Pictures'
        Musica       = Get-CarpetaConocida 'Music'
        Videos       = Get-CarpetaConocida 'Videos'
        CarpetaDatos = $carpetaDatos

        # --- Entorno -----------------------------------------------------
        Unidad       = $env:SystemDrive
        Admin        = Test-EsAdministrador
        Equipo       = $env:COMPUTERNAME
        # La misma función que usa la cabecera del registro, y no una
        # consulta CIM aparte: Win32_OperatingSystem se preguntaba DOS
        # veces en cada arranque para leer el mismo campo. Get-DescripcionSistema
        # recuerda la respuesta, así que la segunda es gratis.
        Windows      = Get-DescripcionSistema

        # --- Umbrales (los sobreescribe el perfil) -----------------------
        Perfil          = $Perfil
        DiasSinUso      = 180
        MinimoMB        = 10
        IncluirMenores  = $false
        Permanente      = $false
        # Simular NO se guarda en las preferencias a proposito: ver la nota
        # en Preferencias.ps1. Vive aqui solo para el rato que dura una
        # sesion. Ver [CNF-02] en docs/HOJA-DE-RUTA.md.
        Simular         = $false
        MinimoDuplicadoMB     = 5
        MinimoGrandeMB        = 250

        # --- Rellenados justo después ------------------------------------
        ZonasUsuario    = @()
        RaicesProyecto  = @()
        Unidades        = @()
        # Letras de las unidades que el usuario quiere analizar. Vacío
        # significa "todas": ver Test-UnidadSeleccionada.
        UnidadesSeleccionadas = @()
        # Carpetas que el usuario ha marcado como intocables. Viene de las
        # preferencias; la configuracion solo la transporta hasta los dos
        # sitios que la comprueban. Ver [CNF-01].
        RutasExcluidas        = @()
    }

    # OJO: el @() de fuera es el que importa. El de dentro solo agrupa el
    # literal de partida; si el pipeline (Where-Object | Select-Object
    # -Unique | Select-RutasNoAnidadas) sobrevive con una sola ruta, sin el
    # @() exterior la asignacion produce un string escalar en vez de un
    # array de un elemento. Ver [C-07] en docs/OPTIMIZACIONES.md: eso
    # rompia en silencio a cualquiera que hiciera
    # "$Configuracion.ZonasUsuario + @(...)", como el módulo de accesos
    # directos rotos.
    $configuracion.ZonasUsuario = @(Select-RutasNoAnidadas (@(
        $configuracion.Escritorio, $configuracion.Documentos, $configuracion.Descargas,
        $configuracion.Imagenes, $configuracion.Musica, $configuracion.Videos,
        (Join-Path $env:USERPROFILE 'OneDrive')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique))

    $configuracion.RaicesProyecto = @(@(
        $configuracion.Escritorio, $configuracion.Documentos,
        (Join-Path $env:USERPROFILE 'source'),
        (Join-Path $env:USERPROFILE 'repos'),
        (Join-Path $env:USERPROFILE 'dev'),
        (Join-Path $env:USERPROFILE 'Proyectos'),
        (Join-Path $env:USERPROFILE 'Projects')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

    $configuracion.Unidades = @(Get-UnidadesAnalizables)
    # Por defecto se analizan todas las unidades detectadas. La interfaz
    # deja desmarcar las que no se quieran tocar, y ModuleRegistry.ps1
    # descarta los candidatos que caigan fuera de esta lista. Ver
    # Test-UnidadSeleccionada.
    $configuracion.UnidadesSeleccionadas = @($configuracion.Unidades | ForEach-Object { $_.Letra })

    return (Set-PerfilConfiguracion -Configuracion $configuracion -Perfil $Perfil)
}

