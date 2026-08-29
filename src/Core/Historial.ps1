<#
.SYNOPSIS
    Historial persistente de ejecuciones.

.DESCRIPTION
    Una entrada por ejecución completa, en JSON, para poder dibujar la
    evolucion del espacio recuperado y responder a "cuando limpie esto por
    última vez". Se conservan las cien últimas.

    No confundir con el registro de actividad (Log.ps1), que es una línea
    por acción y sirve para auditar. Son dos cosas distintas con vidas
    distintas: el registro se rota por meses y crece durante la ejecución;
    el historial se lee y se reescribe entero de una vez, al terminar.
    Vivian en el mismo archivo por motivos historicos. Ver
    docs/ESTRUCTURA.md (sección 5.1).
#>

function Get-RutaHistorial {
    [OutputType([string])]
    param([string] $CarpetaDatos = (Get-CarpetaDatos))
    return (Join-Path $CarpetaDatos 'historial.json')
}

function Get-Historial {
    <#
    .SYNOPSIS
        Lee el historial de ejecuciones anteriores. Siempre devuelve una
        lista PLANA de entradas, nunca una lista que contenga una lista.

    .DESCRIPTION
        Aquí vivio un fallo que solo se manifestaba en Windows PowerShell
        5.1 -es decir, en el único sitio donde el programa se ejecuta de
        verdad- y que las pruebas, que corren en PowerShell 7, no podian
        ver:

        ConvertFrom-Json NO enumera igual en las dos versiones. En 5.1, un
        array de JSON sale de la tuberia como UN SOLO objeto de tipo
        Object[]; desde PowerShell 6 sale enumerado, un objeto por
        entrada. Con "@($contenido | ConvertFrom-Json)", en 5.1 el
        resultado era una lista de UN elemento que era, a su vez, la lista
        entera de entradas.

        Y ese envoltorio no reventaba donde se creaba, sino tres funciones
        más alla: Get-ResumenHistorial filtraba con
        "Where-Object { $_.Tipo -eq 'limpieza' }", y sobre un Object[] eso
        devuelve el array de TODOS los Tipo, que al compararse no esta
        vacío y por tanto es verdadero. La entrada falsa pasaba el filtro,
        y al llegar a "[double]$entrada.Bytes" -que ahora era otro array-
        la conversión fallaba y se llevaba por delante el arranque de la
        ventana.

        Curiosidad útil: con cero o una entrada NO fallaba, porque
        ConvertTo-Json de un solo elemento escribe un objeto suelto y no
        un array. Aparecio al guardar la segunda ejecución.

        Se aplana a mano en vez de confiar en la versión: es barato y no
        depende de en que PowerShell se ejecute.
    #>
    [CmdletBinding()]
    param([string] $CarpetaDatos = (Get-CarpetaDatos))

    $ruta = Get-RutaHistorial -CarpetaDatos $CarpetaDatos
    if (-not (Test-Path -LiteralPath $ruta)) { return @() }
    try {
        $contenido = Get-Content -LiteralPath $ruta -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($contenido)) { return @() }

        $datos = ConvertFrom-Json -InputObject $contenido
        $entradas = [Collections.Generic.List[object]]::new()
        foreach ($elemento in @($datos)) {
            if ($null -eq $elemento) { continue }
            # Una cadena también es enumerable, y no queremos partirla en
            # caracteres. PSCustomObject no lo es, así que las entradas de
            # verdad caen siempre en el else.
            if ($elemento -is [System.Collections.IEnumerable] -and $elemento -isnot [string]) {
                foreach ($sub in $elemento) { if ($null -ne $sub) { $entradas.Add($sub) } }
            } else {
                $entradas.Add($elemento)
            }
        }
        return $entradas.ToArray()
    } catch {
        return @()
    }
}

function Add-EntradaHistorial {
    <#
    .SYNOPSIS
        Añade una ejecución al historial (se conservan las 100 últimas).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateSet('analisis', 'limpieza')] [string] $Tipo,
        [Parameter(Mandatory)] [int]    $Elementos,
        [Parameter(Mandatory)] [double] $Bytes,
        [string] $Perfil        = 'equilibrado',
        [string[]] $Modulos     = @(),
        [double] $LibreAntes    = 0,
        [double] $LibreDespues  = 0,
        # Ruta del informe que documenta ESTA ejecución, si se genero uno.
        # Se guarda para que el historial pueda ofrecer abrirlo: sin esto,
        # una entrada es un resumen que no lleva a ninguna parte. Se guarda
        # tal cual llega; quien la use tiene que pasarla antes por
        # Resolve-InformeAbrible, porque este .json es texto plano en una
        # carpeta escribible y su contenido no es de fiar.
        [string] $Informe       = '',
        # Esta ejecución no llegó al final: se canceló, o falló algún
        # módulo, o se detuvo el borrado a mitad. Sin esto, una limpieza
        # parada en el elemento 3 de 400 quedaba anotada exactamente igual
        # que una completa, y el historial -que es lo único que queda
        # semanas después- decia que se había hecho algo que no se hizo.
        # Ver [CNF-04] en docs/HOJA-DE-RUTA.md.
        [switch] $Incompleto,
        # Por qué quedó incompleta, en una frase, para que la tarjeta del
        # historial pueda decirlo en vez de limitarse a marcarlo.
        [string] $Motivo        = '',
        [string] $CarpetaDatos  = (Get-CarpetaDatos)
    )

    $ruta = Get-RutaHistorial -CarpetaDatos $CarpetaDatos
    if (-not $PSCmdlet.ShouldProcess($ruta, 'Añadir entrada al historial')) { return }

    $entrada = [pscustomobject]@{
        Fecha        = (Get-Date).ToString('o')
        Tipo         = $Tipo
        Perfil       = $Perfil
        Modulos      = @($Modulos)
        Elementos    = $Elementos
        Bytes        = $Bytes
        LibreAntes   = $LibreAntes
        LibreDespues = $LibreDespues
        Informe      = $Informe
        Incompleto   = [bool]$Incompleto
        Motivo       = $Motivo
    }

    $historial = @(Get-Historial -CarpetaDatos $CarpetaDatos) + @($entrada)
    if ($historial.Count -gt 100) {
        $historial = @($historial | Select-Object -Last 100)
    }

    # Escritura atomica: primero a un archivo temporal al lado, y despues
    # un reemplazo de una sola operacion. Antes se escribia directamente
    # sobre historial.json, lo que abre dos agujeros que ya se han visto:
    #
    #   1. Si el proceso muere -o el equipo se apaga- mientras Set-Content
    #      esta a medias, el historial queda TRUNCADO. Es un JSON invalido,
    #      asi que Get-Historial devuelve vacio y se pierde el registro
    #      entero, no la ultima entrada.
    #   2. La ventana y la consola pueden estar guardando a la vez. El
    #      ciclo leer-modificar-escribir no es atomico, asi que la segunda
    #      pisa lo que acaba de anotar la primera.
    #
    # Move con -Force sobre el destino es lo mas cercano a un reemplazo
    # atomico que hay disponible en las dos versiones de PowerShell que el
    # programa soporta. Ver [SEG-62] en docs/PLAN-ACCION.md.
    #
    # El temporal lleva el PID en el nombre por dos motivos: dos procesos
    # no se pisan el archivo intermedio, y si un reemplazo falla a mitad el
    # resto que queda es SIEMPRE el mismo nombre, que la siguiente escritura
    # de este proceso sobrescribe y se lleva. Por eso no hace falta
    # borrarlo aqui, y es preferible que no lo haga: dentro de src/Core
    # solo Remove.ps1 borra archivos, y esa invariante -que las pruebas
    # comprueban- vale mucho mas que un .tmp huerfano en el caso raro.
    $temporal = "$ruta.$PID.tmp"
    try {
        $historial | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporal -Encoding UTF8
        Move-Item -LiteralPath $temporal -Destination $ruta -Force -ErrorAction Stop
    } catch {
        Write-Verbose "No se ha podido guardar el historial: $($_.Exception.Message)"
    }
}

function Get-ResumenHistorial {
    <#
    .SYNOPSIS
        Totales acumulados para mostrar en la interfaz.
    #>
    [CmdletBinding()]
    param([string] $CarpetaDatos = (Get-CarpetaDatos))

    $historial = @(Get-Historial -CarpetaDatos $CarpetaDatos)
    # -eq sobre una cadena, no sobre lo que traiga el JSON: si Tipo llegara
    # siendo un array, "$_.Tipo -eq 'limpieza'" devuelve el subconjunto que
    # coincide, que al no estar vacío es verdadero, y la entrada colaria.
    $limpiezas = @($historial | Where-Object { [string]$_.Tipo -eq 'limpieza' })

    $totalBytes = 0.0
    foreach ($entrada in $limpiezas) { $totalBytes += ConvertTo-DoubleSeguro $entrada.Bytes }

    return [pscustomobject]@{
        Limpiezas    = $limpiezas.Count
        BytesTotales = $totalBytes
    }
}
