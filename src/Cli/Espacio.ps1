<#
.SYNOPSIS
    Modo "¿dónde se fue el espacio?" en consola: el árbol de carpetas por
    tamaño y la lista de archivos mayores.

.DESCRIPTION
    Es la mitad que le faltaba al programa. Cachivache sabía encontrar
    basura; no sabía enseñar el disco, que es justo lo que hacen WizTree y
    WinDirStat y por lo que mucha gente tiene dos programas instalados.

    Aquí sale en consola. La misma información alimentará el mapa de árbol
    de la ventana: el índice y la geometría ya están en el núcleo
    (`Indice.ps1` y `Mapa.ps1`), y son cálculo puro y probado. Lo que falta
    para la ventana es el dibujado.

    NO BORRA NADA, ni lo propone. Es un informe.
#>

function Write-BarraProporcion {
    <#
    .SYNOPSIS
        Barra de texto proporcional a una fracción.
    .DESCRIPTION
        El equivalente en consola de un rectángulo del mapa: se ve de un
        vistazo qué se lleva el espacio, sin leer los números.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([double] $Parte, [double] $Total, [int] $Ancho = 24)

    if ($Total -le 0) { return ''.PadRight($Ancho) }
    $llenos = [int][Math]::Round($Ancho * ($Parte / $Total))
    if ($llenos -lt 0)      { $llenos = 0 }
    if ($llenos -gt $Ancho) { $llenos = $Ancho }

    # Caracteres de bloque de la tabla de dibujo: se ven igual en la
    # consola clasica y en la nueva.
    return ([string][char]0x2588 * $llenos) + ([string][char]0x2591 * ($Ancho - $llenos))
}

function Show-InformeEspacio {
    <#
    .SYNOPSIS
        Vuelca el índice de espacio: carpetas por tamaño y archivos
        mayores.

    .PARAMETER Rutas
        Carpetas por las que empezar. Si no se dan, las zonas del usuario.
    .PARAMETER Profundidad
        Cuántos niveles de carpeta mostrar.
    .PARAMETER Archivos
        Cuántos archivos mayores listar.
    .PARAMETER Buscar
        Filtra los archivos por nombre. Admite comodines.
    .PARAMETER Anonimo
        Sustituye perfil, usuario y equipo por marcadores, para poder
        pegar la salida en una incidencia.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Rutas        = @(),
        [int]      $Profundidad  = 2,
        [int]      $Archivos     = 15,
        [string]   $Buscar       = '',
        [switch]   $ContarEnlacesDuros,
        [switch]   $Anonimo,
        # Si se da, ademas del volcado en consola se escribe un informe
        # HTML con el mapa de arbol dibujado.
        [string]   $Informe = '',
        $Configuracion = $null
    )

    $zonas = @($Rutas | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($zonas.Count -eq 0 -and $null -ne $Configuracion) {
        $zonas = @($Configuracion.ZonasUsuario | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    }
    if ($zonas.Count -eq 0) {
        Write-Linea '  No hay ninguna carpeta que analizar.' 'aviso'
        return
    }

    $mostrar = {
        param([string] $Texto)
        if ($Anonimo) { return ConvertTo-RutaAnonima $Texto }
        return $Texto
    }

    Write-Cabecera 'Donde se fue el espacio'
    foreach ($z in $zonas) { Write-Linea ('  Analizando: {0}' -f (& $mostrar $z)) }
    Write-Linea ''

    $cronometro = [Diagnostics.Stopwatch]::StartNew()
    $indice = New-IndiceDisco -Rutas $zonas -MinimoArchivoBytes 1MB `
                              -ContarEnlacesDuros:$ContarEnlacesDuros
    $cronometro.Stop()

    if ($indice.Bytes -le 0) {
        Write-Linea '  No se ha podido medir nada. Comprueba los permisos.' 'aviso'
        return
    }

    # ---------------- Carpetas ----------------
    Write-Cabecera 'Carpetas por tamaño'

    $pilaVisita = [Collections.Generic.Stack[object]]::new()
    foreach ($z in ($zonas | Sort-Object { -$indice.Carpetas[$_].Bytes })) {
        if ($indice.Carpetas.ContainsKey($z)) {
            $pilaVisita.Push([pscustomobject]@{ Ruta = $z; Nivel = 0; Total = $indice.Carpetas[$z].Bytes })
        }
    }

    while ($pilaVisita.Count -gt 0) {
        $nodo = $pilaVisita.Pop()
        $entrada = $indice.Carpetas[$nodo.Ruta]
        if ($null -eq $entrada) { continue }

        $sangria = '  ' + ('   ' * $nodo.Nivel)
        $nombre  = if ($nodo.Nivel -eq 0) { & $mostrar $nodo.Ruta } else { $entrada.Nombre }

        Write-Linea ('{0}{1} {2,10}  {3}' -f $sangria,
                     (Write-BarraProporcion -Parte $entrada.Bytes -Total $indice.Bytes),
                     (Format-Tamano $entrada.Bytes),
                     (Get-RutaElidida $nombre 46))

        if ($nodo.Nivel -ge $Profundidad) { continue }

        # Se apilan del reves para que salgan de mayor a menor.
        $hijas = @(Get-HijasDirectas -Indice $indice -Ruta $nodo.Ruta |
                   Where-Object { $_.Bytes -ge ($indice.Bytes * 0.01) })
        for ($i = $hijas.Count - 1; $i -ge 0; $i--) {
            if (-not $indice.Carpetas.ContainsKey($hijas[$i].Ruta)) { continue }
            $pilaVisita.Push([pscustomobject]@{
                Ruta = $hijas[$i].Ruta; Nivel = $nodo.Nivel + 1; Total = $hijas[$i].Bytes
            })
        }
    }

    Write-Linea ''
    Write-Linea '  Solo se muestran las carpetas que pasan del 1% del total.'

    # ---------------- Archivos ----------------
    Write-Cabecera 'Archivos mayores'

    $sinFiltrar = @($indice.Archivos)
    $lista      = $sinFiltrar
    if (-not [string]::IsNullOrWhiteSpace($Buscar)) {
        $lista = @($lista | Where-Object { $_.Nombre -like $Buscar })
        Write-Linea ('  Filtrando por: {0}' -f $Buscar)
        Write-Linea ''
    }

    if ($lista.Count -eq 0) {
        # Tres situaciones distintas que se veian como el mismo hueco. La
        # tercera es la peligrosa: el usuario cree que el analisis fallo.
        if ($sinFiltrar.Count -eq 0) {
            Write-Linea ('  Ningún archivo llega a {0}: aquí el espacio esta repartido en archivos pequeños.' -f
                         (Format-Tamano $indice.UmbralArchivo))
        } else {
            Write-Linea ('  Ninguno de los {0} archivos grandes coincide con "{1}".' -f
                         $sinFiltrar.Count, $Buscar) 'aviso'
        }
    } else {
        foreach ($a in ($lista | Select-Object -First $Archivos)) {
            Write-Linea ('  {0,10}  {1}' -f (Format-Tamano $a.Bytes),
                         (Get-RutaElidida (& $mostrar $a.Ruta) 60))
        }
        if ($lista.Count -gt $Archivos) {
            Write-Linea ''
            Write-Linea ('  ... y {0} archivos más de más de {1}.' -f
                         ($lista.Count - $Archivos), (Format-Tamano $indice.UmbralArchivo))
        }
    }

    # ---------------- Resumen ----------------
    Write-Cabecera 'Resumen'
    Write-Linea ('  Espacio medido    : {0}' -f (Format-Tamano $indice.Bytes))
    Write-Linea ('  Archivos          : {0:N0}' -f $indice.TotalArchivos)
    Write-Linea ('  Carpetas          : {0:N0}' -f $indice.Carpetas.Count)
    Write-Linea ('  Tiempo            : {0}' -f (Format-Duracion $cronometro.Elapsed))

    if ($indice.Compartidos -gt 0) {
        Write-Linea ('  Enlaces duros     : {0:N0} archivos comparten contenido y se han contado una sola vez' -f
                     $indice.Compartidos)
    }
    if ($indice.Inaccesibles -gt 0) {
        Write-Linea ('  Sin permiso       : {0:N0} carpetas no se han podido leer' -f $indice.Inaccesibles) 'aviso'
    }

    # ---------------- Informe con mapa ----------------
    if (-not [string]::IsNullOrWhiteSpace($Informe)) {
        try {
            Export-InformeEspacio -Indice $indice -Ruta $Informe -Anonimo:$Anonimo -Confirm:$false
            Write-Linea ''
            Write-Linea ('  Mapa del disco guardado en: {0}' -f $Informe) 'ok'
        } catch {
            Write-Linea ('  No se ha podido guardar el informe: {0}' -f $_.Exception.Message) 'error'
        }
    }

    Write-Linea ''
    Write-Linea '  Esto es un informe: no se ha propuesto ni borrado nada.'
}
