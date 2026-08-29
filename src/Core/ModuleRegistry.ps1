<#
.SYNOPSIS
    Descubrimiento y ejecución de los módulos de limpieza.

.DESCRIPTION
    Cada archivo de src/Modules termina devolviendo un objeto creado con
    New-ModuloLimpieza. Para añadir una categoría nueva basta con dejar
    caer un archivo en esa carpeta: no hay ninguna lista que mantener.
#>

function Get-RaizProyecto {
    <#
    .SYNOPSIS
        Carpeta raiz del repositorio, calculada desde este archivo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
}

function Get-ModulosLimpieza {
    <#
    .SYNOPSIS
        Carga y devuelve todos los módulos de limpieza, ordenados.
    #>
    [CmdletBinding()]
    param([string] $Raiz = (Get-RaizProyecto))

    $carpeta = Join-Path (Join-Path $Raiz 'src') 'Modules'
    if (-not (Test-Path -LiteralPath $carpeta)) { return @() }

    $modulos = [Collections.Generic.List[object]]::new()
    foreach ($archivo in (Get-ChildItem -LiteralPath $carpeta -Filter '*.ps1' -File | Sort-Object Name)) {
        try {
            # Se coge el ÚLTIMO objeto que parezca un módulo, en vez de dar
            # por hecho que el archivo produce uno solo. Si un módulo deja
            # escapar cualquier salida -un Write-Output olvidado, una
            # llamada cuyo valor no se descarta-, "$modulo = . $archivo"
            # devuelve un ARRAY, .PSObject.Properties['Buscar'] da $null y
            # el módulo entero se descartaba con un Write-Warning que en
            # modo ventana no ve nadie. Ver [SEG-51].
            $modulo = @(. $archivo.FullName) |
                      Where-Object { $null -ne $_ -and $_.PSObject.Properties['Buscar'] } |
                      Select-Object -Last 1

            if ($null -ne $modulo -and $modulo.PSObject.Properties['Buscar']) {
                # Guardar el archivo permite que el hilo de análisis cargue
                # solo este módulo en vez de recorrer la carpeta entera.
                $modulo | Add-Member -NotePropertyName 'Archivo' `
                                     -NotePropertyValue $archivo.FullName -Force
                $modulos.Add($modulo)
            } else {
                Write-Warning "El archivo $($archivo.Name) no devuelve un modulo valido."
            }
        } catch {
            Write-Warning "No se ha podido cargar $($archivo.Name): $($_.Exception.Message)"
        }
    }
    return @($modulos | Sort-Object Orden)
}

function Get-ModuloLimpieza {
    <#
    .SYNOPSIS
        Devuelve un único módulo por su identificador.
    .DESCRIPTION
        Comodidad para las pruebas, que necesitan un módulo suelto sin
        montar toda la cola de análisis.

        Ojo con lo que NO hace: no carga solo ese archivo, sino los
        dieciocho, y después filtra. Por eso el hilo de análisis no la usa
        y prefiere dot-sourcear directamente el archivo del módulo que le
        toca (ver Window.Analisis.ps1). Para un puñado de llamadas en las
        pruebas da igual; en el bucle del análisis sería un derroche.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [string] $Raiz = (Get-RaizProyecto)
    )
    return (Get-ModulosLimpieza -Raiz $Raiz | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Invoke-ModuloLimpieza {
    <#
    .SYNOPSIS
        Ejecuta la busqueda de un módulo y devuelve sus candidatos.
    .DESCRIPTION
        Aisla los fallos: si un módulo revienta, se informa del error pero
        el resto del análisis continua. Además filtra los resultados que no
        pasen la guardia, por si un módulo se olvidara de comprobarlo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Modulo,
        [Parameter(Mandatory)] $Configuracion,
        $Sync = $null
    )

    # Las dos ramas de salida de esta función devuelven EXACTAMENTE los
    # mismos campos. Antes no: la de omitido no traia Descartados, y quien
    # la consumiera sin comprobarlo leia $null. Funcionaba de milagro,
    # porque el llamante hacia continue antes de mirarlo.
    if ($Modulo.RequiereAdmin -and -not $Configuracion.Admin) {
        return [pscustomobject]@{
            ModuloId    = $Modulo.Id
            Candidatos  = @()
            Error       = ''
            Omitido     = 'Necesita permisos de administrador.'
            Descartados = 0
        }
    }

    # Se acumula candidato a candidato en vez de asignar el resultado
    # entero. Con "$candidatos = @(& $Modulo.Buscar ...)", un módulo que
    # reventaba a mitad tiraba TAMBIÉN lo que ya había emitido: la
    # asignación no llega a completarse. Justo el caso peor -un módulo que
    # falla al llegar a una carpeta concreta despues de haber encontrado
    # cosas de verdad- perdia todo el trabajo en silencio.
    #
    # Y se guarda la traza, no solo el mensaje: "Acceso denegado" sin saber
    # en que linea del módulo es un aviso que no se puede investigar.
    # Ver [SEG-50] en docs/PLAN-ACCION.md.
    $recogidos = [Collections.Generic.List[object]]::new()
    $error1    = ''

    try {
        & $Modulo.Buscar $Configuracion $Sync | ForEach-Object {
            if ($null -ne $_) { $recogidos.Add($_) }
        }
    } catch {
        $error1 = $_.Exception.Message
        if ($_.ScriptStackTrace) {
            $error1 += " (en $($_.ScriptStackTrace -split "`n" | Select-Object -First 1))"
        }
    }

    $candidatos = @($recogidos)

    # Red de seguridad: ningún candidato que borre archivos escapa a la
    # guardia. Los métodos que no tocan el sistema de archivos directamente
    # (informativos, papelera y comandos oficiales de Windows) se validan
    # por otras vias y no tienen una ruta convencional que comprobar.
    $sinRuta = @('Informativo', 'Papelera', 'Comando')
    $validos = @($candidatos | Where-Object {
        $null -ne $_ -and (
            $sinRuta -contains $_.Metodo -or
            (Test-RutaSegura -Ruta $_.Ruta -Raices $_.Raices `
                             -PermitirPersonales:$_.PermitirPersonales)
        )
    })

    # Segundo filtro: las unidades que el usuario haya excluido. Se aplica
    # AQUÍ, en el único sitio por el que pasan todos los candidatos de todos
    # los módulos, y no módulo a módulo: así ninguno puede olvidarse de
    # respetarlo, del mismo modo que ninguno puede saltarse la guardia.
    #
    # Solo puede QUITAR candidatos, nunca añadirlos: es una restriccion
    # adicional sobre lo que ya aprobo la guardia, no un permiso.
    $validos = @($validos | Where-Object { Test-UnidadSeleccionada -Ruta $_.Ruta -Configuracion $Configuracion })

    # Tercer filtro: las carpetas que el usuario ha excluido a mano.
    #
    # Va AQUI y no en cada modulo, por el mismo motivo que los otros dos:
    # es el unico sitio por el que pasan todos los candidatos de todos los
    # modulos, asi que ninguno puede olvidarse de respetarlo, y un modulo
    # nuevo lo hereda sin escribir una linea. Ver [CNF-01].
    $excluidas = @()
    if ($null -ne $Configuracion -and $Configuracion.PSObject.Properties['RutasExcluidas']) {
        $excluidas = @($Configuracion.RutasExcluidas)
    }
    if ($excluidas.Count -gt 0) {
        $validos = @($validos | Where-Object {
            -not (Test-RutaExcluida -Ruta $_.Ruta -Excluidas $excluidas)
        })
    }

    return [pscustomobject]@{
        ModuloId    = $Modulo.Id
        Candidatos  = @($validos | Sort-Object Bytes -Descending)
        Error       = $error1
        Omitido     = ''
        Descartados = $candidatos.Count - $validos.Count
    }
}

function New-EstadoSincronizado {
    <#
    .SYNOPSIS
        Crea la tabla compartida entre la interfaz y el hilo de análisis.
    .DESCRIPTION
        ColaRegistro es una ConcurrentQueue: el hilo de la interfaz y el
        runspace de análisis/borrado pueden escribir en el registro a la
        vez sin coordinarse entre ellos, porque ninguno de los dos toca el
        archivo directamente. Encolan líneas de texto ya formateadas; el
        ÚNICO que las escribe a disco es el temporizador de la interfaz,
        con Invoke-VaciarColaRegistro. Ver [C-19] en
        docs/OPTIMIZACIONES.md: antes los dos escribian el mismo archivo
        con Add-Content sin ninguna sincronización, lo que producia una
        violacion de uso compartido y perdia líneas de auditoria justo
        durante el borrado, que es el momento que más importa.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Crea una tabla hash en memoria.')]
    [CmdletBinding()]
    param()
    return [hashtable]::Synchronized(@{
        Mensaje      = ''
        Terminado    = $true
        Cancelar     = $false
        Resultado    = $null
        Error        = ''
        ColaRegistro = [Collections.Concurrent.ConcurrentQueue[string]]::new()
    })
}
