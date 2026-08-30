<#
.SYNOPSIS
    Papelera de reciclaje.
.DESCRIPTION
    Se mide lo que ocupa en cada unidad fija. Vaciarla es irreversible, así
    que nunca viene marcado por defecto y se avisa de cuantos elementos hay.
#>

$BuscarPapelera = {
    param($Configuracion, $Sync)

    Set-Progreso $Sync 'Midiendo la papelera de reciclaje...'

    $totalBytes = 0.0
    $totalElementos = 0
    $detallePorUnidad = @()
    $letrasConContenido = @()

    # Solo las unidades que el usuario quiere analizar. El filtro central de
    # ModuleRegistry.ps1 no puede cubrir este caso: el candidato de la
    # papelera vive en la unidad del sistema, así que pasaria el filtro y
    # aun así habría medido (y vaciado) papeleras de discos desmarcados.
    # Aquí se mide lo mismo que después se vacía.
    $unidades = @($Configuracion.Unidades | Where-Object {
        Test-UnidadSeleccionada -Ruta ($_.Letra + '\') -Configuracion $Configuracion
    })

    foreach ($unidad in $unidades) {
        if (Test-Cancelacion $Sync) { break }
        $ruta = Join-Path ($unidad.Letra + '\') '$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $ruta)) { continue }

        $bytes = 0.0
        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        # Aqui pesa doble, porque lo que hay dentro de $Recycle.Bin son las
        # rutas ORIGINALES de lo que el usuario borro, con su profundidad
        # entera: si algo venia de un node_modules anidado, la copia de la
        # papelera es igual de larga.
        Get-ElementosDelArbol -Ruta $ruta |
            ForEach-Object {
                # Los archivos $I son metadatos del propio contenedor.
                if ($_.Name -notlike '$I*') { $bytes += [double]$_.Length }
            }
        if ($bytes -le 0) { continue }

        $totalBytes += $bytes
        $detallePorUnidad += ('{0} {1}' -f $unidad.Letra, (Format-Tamano $bytes))
        $letrasConContenido += $unidad.Letra
    }

    # El recuento de elementos se obtiene del shell, que si sabe agrupar los
    # archivos sueltos en los elementos originales que el usuario borro.
    try {
        $shell = New-Object -ComObject Shell.Application
        $papelera = $shell.NameSpace(0x0A)
        if ($papelera) { $totalElementos = @($papelera.Items()).Count }
    } catch {
        $totalElementos = 0
    }

    if ($totalBytes -lt 1MB) { return }

    $info = if ($totalElementos -gt 0) { "$totalElementos elementos" } else { 'contenido de la papelera' }
    if ($detallePorUnidad.Count -gt 1) { $info += ' - ' + ($detallePorUnidad -join ', ') }

    # La ruta del candidato tiene que estar en una unidad MARCADA, y no
    # siempre en la del sistema. El filtro central mira esta ruta: si el
    # usuario desmarcaba C: y dejaba D:, el candidato apuntaba igualmente a
    # C: y desaparecia entero, así que la papelera de D: no se ofrecia
    # aunque tuviera cuarenta gigas. Se usa la primera unidad marcada donde
    # de verdad hay algo que vaciar.
    $letraCandidato = if ($letrasConContenido.Count -gt 0) { $letrasConContenido[0] }
                      else { $Configuracion.Unidad }

    New-Candidato -ModuloId 'papelera' -Categoria 'Papelera de reciclaje' `
                  -Nombre 'Vaciar la papelera de reciclaje' `
                  -Ruta (Join-Path ($letraCandidato + '\') '$Recycle.Bin') `
                  -Bytes $totalBytes -Info $info `
                  -Efecto 'Libera el espacio de todo lo que ya habías borrado.' `
                  -Aviso 'Irreversible: después de esto no se puede restaurar nada de la papelera.' `
                  -Metodo 'Papelera' -Raices @() -Riesgo 'Medio' -Preseleccionado $false
}

New-ModuloLimpieza -Id 'papelera' -Orden 25 `
    -Nombre 'Papelera de reciclaje' `
    -Descripcion 'Lo que ya borraste sigue ocupando disco hasta que se vacía la papelera. Vaciarla es irreversible.' `
    -Riesgo 'Medio' `
    -Perfiles @('conservador', 'equilibrado', 'agresivo') `
    -Buscar $BuscarPapelera
