<#
.SYNOPSIS
    Preferencias del usuario, persistidas entre sesiones.

.DESCRIPTION
    Un único archivo JSON en la carpeta de datos con lo que el usuario
    dejo elegido la última vez: tema, perfil, umbrales y módulos activos.

    Separado de Config.ps1 a propósito: aquello describe el EQUIPO y se
    recalcula en cada arranque (unidades, carpetas conocidas, si somos
    administrador); esto describe al USUARIO, sobrevive al reinicio y lo
    puede haber editado a mano. Ver docs/ESTRUCTURA.md (sección 5.2).

    Aviso: los valores que se leen de aquí NO están validados por tipo ni
    por rango; ver [A-05] en docs/OPTIMIZACIONES.md.
#>

function Get-RutaPreferencias {
    [OutputType([string])]
    param()
    return (Join-Path (Get-CarpetaDatos) 'preferencias.json')
}

function Get-TemaDeWindows {
    <#
    .SYNOPSIS
        El tema que Windows tiene elegido para las aplicaciones: 'claro' u
        'oscuro'. Devuelve 'oscuro' si no se puede averiguar.

    .DESCRIPTION
        Solo se consulta en el PRIMER arranque, para no abrir el programa
        con un tema que choca con todo lo demás de la pantalla. En cuanto
        el usuario toca el boton de tema, manda su eleccion y esto no
        vuelve a mirarse: la preferencia explicita de una persona pesa más
        que la del sistema.

        AppsUseLightTheme es la clave que gobierna el tema de las
        aplicaciones; existe también SystemUsesLightTheme, que es la de la
        barra de tareas y el menu inicio, y no es la que toca. 0 = oscuro,
        1 = claro. Si no existe (Windows anteriores a la 1809) o no se
        puede leer, se responde 'oscuro', que es lo que este programa venia
        haciendo desde siempre.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $clave = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $valor = (Get-ItemProperty -Path $clave -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
        if ([int]$valor -eq 1) { return 'claro' }
        return 'oscuro'
    } catch {
        return 'oscuro'
    }
}

function Import-Preferencias {
    <#
    .SYNOPSIS
        Lee las preferencias guardadas de la sesión anterior.
    .DESCRIPTION
        En el primer arranque no hay archivo, y entonces el tema se hereda
        del que Windows tenga puesto. A partir de ahi manda lo que el
        usuario haya elegido con el boton, que si se guarda.
    #>
    [CmdletBinding()]
    param()

    $ruta = Get-RutaPreferencias
    $valoresPorDefecto = @{
        Tema            = (Get-TemaDeWindows)
        Perfil          = 'equilibrado'
        DiasSinUso      = 180
        MinimoMB        = 10
        IncluirMenores  = $false
        Permanente      = $false
        ModulosActivos  = @()
        # Letras de unidad que el usuario dejo DESMARCADAS. Se guardan las
        # excluidas y no las incluidas a propósito: si aparece un disco
        # nuevo, entra marcado por defecto en vez de quedar fuera en
        # silencio por no figurar en una lista antigua.
        UnidadesExcluidas = @()
        # Carpetas que el usuario ha dicho que NO se toquen nunca.
        #
        # Es la funcion que mas se echa en falta en un limpiador: si el
        # programa propone la carpeta de un proyecto vivo, la desmarcas hoy
        # y vuelve a aparecer manyana. Aqui, al reves que con las unidades,
        # se guarda lo EXCLUIDO explicitamente: son decisiones del usuario
        # sobre rutas concretas, no una lista que pueda quedarse obsoleta
        # porque aparezca algo nuevo. Ver [CNF-01] en docs/HOJA-DE-RUTA.md.
        RutasExcluidas    = @()

        # AQUI NO VA "Simular", Y ES A PROPOSITO.
        #
        # Parece que deberia: es una casilla mas de la ventana, y las
        # casillas se recuerdan. Pero simular no es una preferencia, es una
        # COMPROBACION previa a un acto concreto. Guardada, pasa esto: la
        # activas hoy para mirar, cierras, vuelves dentro de tres semanas,
        # le das a eliminar, lees "se habrian eliminado 4.000 elementos" sin
        # fijarte en el condicional y te vas convencido de que has limpiado
        # el disco. No has limpiado nada.
        #
        # Es exactamente el fallo que ya tuvimos con el borrado permanente,
        # que se rearmaba solo entre sesiones (ver la nota en
        # Window.Eventos.ps1), solo que con el signo cambiado: aquel
        # destruia de mas, este miente sobre lo hecho. Los dos son la misma
        # familia de error -el programa no hace lo que el usuario cree- y
        # esa familia es la que lleva toda la auditoria intentando cerrar.
        #
        # Asi que la casilla nace apagada en cada arranque. Marcarla cuesta
        # un clic; descubrir que llevabas un mes sin limpiar, un disco lleno.
    }

    if (-not (Test-Path -LiteralPath $ruta)) { return $valoresPorDefecto }

    # Cada preferencia con su forma esperada y sus límites. Antes se
    # aceptaba lo que hubiera en el archivo tal cual, y este archivo es
    # texto plano que el usuario puede editar. Con un "MinimoMB": "diez"
    # dentro, el arranque hacia [int] sobre esa cadena y la ventana no
    # llegaba a abrirse; con un número fuera del rango del deslizador, WPF
    # lo recortaba y la preferencia guardada dejaba de coincidir con lo que
    # se veia. Es el aviso [A-05] de docs/OPTIMIZACIONES.md, y el mismo
    # tipo de fallo que tumbo el arranque desde historial.json.
    #
    # Lo que no encaja se sustituye por su valor por defecto, en silencio
    # pero anotado: perder una preferencia es una molestia, no abrir es un
    # programa roto.
    $reglas = @{
        Tema              = @{ Tipo = 'opcion'; Opciones = @('claro', 'oscuro') }
        Perfil            = @{ Tipo = 'opcion'; Opciones = @('conservador', 'equilibrado', 'agresivo', 'personalizado') }
        # Los rangos son los mismos que declaran los deslizadores en
        # MainWindow.xaml: si divergen, el control recorta el valor y la
        # preferencia deja de reflejar lo que ve el usuario.
        DiasSinUso        = @{ Tipo = 'entero'; Minimo = 30; Maximo = 730 }
        MinimoMB          = @{ Tipo = 'entero'; Minimo = 1;  Maximo = 500 }
        IncluirMenores    = @{ Tipo = 'bool' }
        Permanente        = @{ Tipo = 'bool' }
        ModulosActivos    = @{ Tipo = 'textos' }
        UnidadesExcluidas = @{ Tipo = 'textos' }
        RutasExcluidas    = @{ Tipo = 'textos' }
    }

    try {
        $guardado = Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($clave in @($valoresPorDefecto.Keys)) {
            $propiedad = $guardado.PSObject.Properties[$clave]
            if ($null -eq $propiedad) { continue }

            $bruto = $propiedad.Value
            $regla = $reglas[$clave]
            $valido = $true

            switch ($regla.Tipo) {
                'opcion' {
                    $texto = [string]$bruto
                    if ($regla.Opciones -contains $texto) { $valoresPorDefecto[$clave] = $texto }
                    else { $valido = $false }
                }
                'entero' {
                    $numero = ConvertTo-DoubleSeguro $bruto
                    # Un 0 puede ser el valor de verdad o el resultado de no
                    # poder convertir, así que se comprueba también el rango:
                    # ningún umbral admite el cero.
                    if ($numero -ge $regla.Minimo -and $numero -le $regla.Maximo) {
                        $valoresPorDefecto[$clave] = [int]$numero
                    } else { $valido = $false }
                }
                'bool' {
                    if ($bruto -is [bool]) { $valoresPorDefecto[$clave] = [bool]$bruto }
                    else { $valido = $false }
                }
                'textos' {
                    # Se filtra elemento a elemento: una lista con un objeto
                    # dentro llegaria hasta un -contains y se compararia con
                    # cualquier cosa.
                    $valoresPorDefecto[$clave] = @(@($bruto) |
                        Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } |
                        ForEach-Object { [string]$_ })
                }
            }

            if (-not $valido) {
                Write-Verbose ("La preferencia '{0}' del archivo no es valida; se usa el valor por defecto." -f $clave)
            }
        }
    } catch {
        Write-Verbose "No se han podido leer las preferencias: $($_.Exception.Message)"
    }
    return $valoresPorDefecto
}

function Export-Preferencias {
    <#
    .SYNOPSIS
        Guarda las preferencias para la próxima sesión.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $Preferencias)

    $ruta = Get-RutaPreferencias
    if (-not $PSCmdlet.ShouldProcess($ruta, 'Guardar preferencias')) { return }
    try {
        $Preferencias | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $ruta -Encoding UTF8
    } catch {
        Write-Verbose "No se han podido guardar las preferencias: $($_.Exception.Message)"
    }
}
