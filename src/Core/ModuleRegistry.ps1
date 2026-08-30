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

function Get-ReglasFiltroCandidato {
    <#
    .SYNOPSIS
        Las reglas que el embudo aplica a TODOS los candidatos de TODOS los
        módulos: nombre, coste y predicado.

    .DESCRIPTION
        Antes estos filtros estaban cableados a mano dentro de
        Invoke-ModuloLimpieza, uno detras de otro. Funcionaba, pero cada
        filtro nuevo habia que enchufarlo en el sitio correcto y nada
        obligaba a que se aplicaran todos: olvidar uno no da ningun error,
        propone DE MAS, que en este programa es el fallo caro. Ver [ARQ-02].

        Ahora son datos: una lista que el embudo recorre entera. Anyadir la
        cuarta regla es anyadir un elemento, y la prueba regla a regla de
        tests/Embudo.Tests.ps1 exige que toda regla de esta lista tenga un
        caso que demuestre que se aplica de verdad.

        CONTRATO DE UNA REGLA
        - Nombre: para las pruebas y para leer la lista. Unico.
        - Coste: 0 = ni mira el candidato, 1 = solo texto en memoria,
          2 = consulta el disco. Ver el porque del orden mas abajo.
        - Predicado: bloque de filtro al estilo de Where-Object. Recibe el
          candidato en $_, el contexto de New-ContextoEmbudo como unico
          parametro, y devuelve $true para CONSERVARLO. Se aplica siempre
          igual, desde el embudo y desde las pruebas:

              @($candidatos) | Where-Object { & $regla.Predicado $contexto }

        POR QUE UN CONTEXTO Y NO UN CIERRE. La primera version armaba los
        predicados con .GetNewClosure(), que parece justo lo que hace falta:
        el predicado se lleva dentro la configuracion. Y no vale: un cierre
        se ejecuta en el ambito de un modulo dinamico nuevo, donde NO se ven
        las funciones del nucleo, que se cargan dot-sourceando Bootstrap.ps1
        en el ambito de quien llama y no son globales. El sintoma fue
        "Test-UnidadSeleccionada no se reconoce" en seis pruebas: la regla
        no filtraba de menos, es que reventaba. Con un parametro corriente
        no hay ambito nuevo y no hay nada que resolver.

        UNA REGLA SOLO PUEDE QUITAR CANDIDATOS, NUNCA ANYADIRLOS. Son
        restricciones sobre lo que ya se propuso, no permisos.

        EL ORDEN. Para el RESULTADO no importa: los predicados son puros y
        no dependen unos de otros, asi que lo que sobrevive es la
        interseccion, que es la misma se apliquen en el orden que se
        apliquen. Hay una prueba que lo comprueba aplicandolas al reves.
        Para el COSTE si importa, y por eso van de barata a cara: la
        guardia es la unica que toca el disco -un Get-Item por candidato
        mas uno por nivel de carpeta, dentro de Test-CadenaSinEnlaces-, y
        preguntarle al disco por un candidato que la lista de exclusiones
        ya iba a tirar es trabajo tirado. Antes iba primera, que era el
        orden peor. Una prueba exige que los Coste no decrezcan.

        Que la guardia vaya la ULTIMA no la debilita ni un poco: para
        sobrevivir hay que pasarlas todas, y ninguna de las otras dos puede
        dar por bueno lo que la guardia rechaza. Lo que decide es la
        conjuncion, no la posicion.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $reglas = [Collections.Generic.List[object]]::new()

    # Regla 0. Defensa en profundidad: quien recoge los candidatos ya
    # descarta los nulos, pero un $null que llegara hasta aqui haria que
    # las demas reglas decidieran sobre propiedades vacias. Leer
    # $null.Ruta no lanza en PowerShell, asi que el sintoma seria un
    # candidato fantasma, no un error.
    $reglas.Add([pscustomobject]@{
        Nombre    = 'Candidato existente'
        Coste     = 0
        Predicado = { param($Contexto) $null -ne $_ }
    })

    # Regla 1. Las unidades que el usuario ha desmarcado.
    $reglas.Add([pscustomobject]@{
        Nombre    = 'Unidad seleccionada'
        Coste     = 1
        Predicado = {
            param($Contexto)
            Test-UnidadSeleccionada -Ruta $_.Ruta -Configuracion $Contexto.Configuracion
        }
    })

    # Regla 2. Las carpetas que el usuario ha excluido a mano. Ver [CNF-01].
    # Por ClaveExclusion y no por Ruta: lo que no tiene ruta real se
    # compara exacto, no por prefijo de carpeta. Ver [ARQ-03].
    $reglas.Add([pscustomobject]@{
        Nombre    = 'Exclusiones del usuario'
        Coste     = 1
        Predicado = {
            param($Contexto)
            if ($Contexto.Excluidas.Count -eq 0) { return $true }
            return -not (Test-ClaveExcluida -Clave $_.ClaveExclusion -Excluidas $Contexto.Excluidas)
        }
    })

    # Regla 3. La guardia: ningun candidato que borre archivos se libra de
    # ella. Es la unica que consulta el disco, de ahi el Coste 2 y de ahi
    # que vaya la ultima.
    $reglas.Add([pscustomobject]@{
        Nombre    = 'Guardia de rutas'
        Coste     = 2
        Predicado = {
            param($Contexto)
            if ($Contexto.SinRuta -contains $_.Metodo) { return $true }
            return (Test-RutaSegura -Ruta $_.Ruta -Raices $_.Raices `
                                    -PermitirPersonales:$_.PermitirPersonales)
        }
    })

    return @($reglas)
}

function New-ContextoEmbudo {
    <#
    .SYNOPSIS
        Lo que las reglas del embudo necesitan saber, calculado una sola vez
        por modulo en vez de una vez por candidato.

    .DESCRIPTION
        Calculo puro: no toca el disco ni el registro, solo lee la
        configuracion. Existe por dos motivos, y los dos importan:

        - RENDIMIENTO. Un predicado corre una vez por candidato, y sobre una
          cache de 200.000 archivos eso son 200.000 veces. Leer
          RutasExcluidas ahi dentro seria rehacer 200.000 veces un trabajo
          cuyo resultado no cambia.
        - PODER PROBAR UNA REGLA SUELTA. Una regla no depende de que exista
          una variable con el nombre correcto en el ambito de quien la
          invoca: recibe esto y ya esta.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo construye un objeto en memoria: no cambia el estado de nada.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # AllowNull porque el modo consola y varias pruebas llaman al
        # embudo sin configuracion, y las reglas tienen que saber
        # responder a eso sin reventar.
        [Parameter(Mandatory)] [AllowNull()] $Configuracion
    )

    # Los métodos que no tocan el sistema de archivos directamente
    # (informativos, papelera y comandos oficiales de Windows) se validan
    # por otras vias y no tienen una ruta convencional que comprobar.
    $sinRuta = @('Informativo', 'Papelera', 'Comando')

    $excluidas = @()
    if ($null -ne $Configuracion -and $Configuracion.PSObject.Properties['RutasExcluidas']) {
        $excluidas = @($Configuracion.RutasExcluidas)
    }

    return [pscustomobject]@{
        Configuracion = $Configuracion
        Excluidas     = $excluidas
        SinRuta       = $sinRuta
    }
}

function Invoke-ModuloLimpieza {
    <#
    .SYNOPSIS
        Ejecuta la busqueda de un módulo y devuelve sus candidatos.
    .DESCRIPTION
        Aisla los fallos: si un módulo revienta, se informa del error pero
        el resto del análisis continua. Además pasa los resultados por
        TODAS las reglas de Get-ReglasFiltroCandidato, por si un módulo se
        olvidara de comprobarlas.
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

    # EL EMBUDO. Este es el único sitio por el que pasan todos los
    # candidatos de todos los módulos: por eso los filtros viven aquí y no
    # módulo a módulo. Así ninguno puede olvidarse de respetarlos y un
    # módulo nuevo los hereda sin escribir una línea.
    #
    # Se recorre la lista ENTERA, sin elegir: la lista es el contrato. Si
    # esto dejara de aplicar una regla no habria ningun error, se
    # propondria de mas, que es justo el fallo que no se ve. Ver [ARQ-02] y
    # las pruebas regla a regla de tests/Embudo.Tests.ps1.
    $contexto = New-ContextoEmbudo -Configuracion $Configuracion
    $validos  = @($candidatos)
    foreach ($regla in (Get-ReglasFiltroCandidato)) {
        $validos = @($validos | Where-Object { & $regla.Predicado $contexto })
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
