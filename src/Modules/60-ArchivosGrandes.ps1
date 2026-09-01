<#
.SYNOPSIS
    Archivos muy grandes que llevan mucho tiempo sin abrirse.
.DESCRIPTION
    Módulo INFORMATIVO: nunca borra nada. Su trabajo es enseñar donde se
    esta yendo el disco para que la decisión la tome una persona. Windows
    puede tener desactivado el seguimiento de último acceso, así que se usa
    la fecha más reciente entre acceso y modificacion.
#>

$BuscarArchivosGrandes = {
    param($Configuracion, $Sync)

    $zonas = @($Configuracion.ZonasUsuario)
    if ($zonas.Count -eq 0) { return }

    $minimo = [double]$Configuracion.MinimoGrandeMB * 1MB
    $limite = (Get-Date).AddDays(-$Configuracion.DiasSinUso)

    foreach ($zona in $zonas) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Buscando archivos grandes en $(Get-RutaCorta $zona)..."

        # Get-ElementosDelArbol y no Get-ChildItem -Recurse: ver [COR-08].
        # -MedirEnDisco: [VIS-05]. Solo pregunta el tamano en disco de lo
        # que lleva el bit de comprimido, asi que en el caso normal no
        # cuesta ni una llamada al sistema. Sin esto, en una carpeta
        # comprimida el modulo promete liberar el tamano LOGICO y libera
        # bastante menos.
        Get-ElementosDelArbol -Ruta $zona -MedirEnDisco |
        Where-Object {
            # Un archivo que solo esta en la nube ocupa unos kilobytes aqui,
            # no su tamaño logico. Listarlo como "4 GB que puedes liberar"
            # seria mentir sobre el espacio: borrarlo no devuelve nada, y
            # ademas te quita el archivo de OneDrive. Es la misma
            # contabilidad falsa que los enlaces duros de [VIS-03].
            # Ver [COR-03].
            -not (Test-ArchivoEnNube -Archivo $_) -and
            $_.Length -ge $minimo -and
            $_.FullName -notmatch '\\node_modules\\|\\\.git\\|\\\$Recycle|hiberfil|pagefile|swapfile' -and
            -not (Test-EsEnlace $_)
        } |
        ForEach-Object {
            if (Test-Cancelacion $Sync) { return }

            $ultimoUso = $_.LastAccessTime
            if ($_.LastWriteTime -gt $ultimoUso) { $ultimoUso = $_.LastWriteTime }
            if ($ultimoUso -gt $limite) { return }

            New-Candidato -ModuloId 'grandes' -Categoria 'Archivos grandes sin usar' `
                          -Nombre $_.Name -Ruta $_.FullName -Bytes $_.Length `
                          -TamanoEnDisco $_.TamanoEnDisco `
                          -Info "$(Get-RutaElidida $_.DirectoryName 55) - sin abrir desde $($ultimoUso.ToString('yyyy-MM-dd')) ($(Format-Antiguedad $ultimoUso))" `
                          -Efecto 'Solo informativo: este módulo no borra nada. Decide tú si lo mueves a un disco externo o lo eliminas a mano.' `
                          -Metodo 'Informativo' -Raices $zonas -Riesgo 'Medio' -Preseleccionado $false
        }
    }
}

New-ModuloLimpieza -Id 'grandes' -Orden 60 `
    -Nombre 'Archivos grandes sin usar' `
    -Descripcion 'Informe de los archivos que más ocupan y llevan más tiempo sin abrirse. Este módulo nunca borra nada.' `
    -Riesgo 'Alto' -SoloInforma `
    -Perfiles @('agresivo') `
    -Buscar $BuscarArchivosGrandes
