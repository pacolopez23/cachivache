<#
.SYNOPSIS
    Informe HTML del espacio en disco, con mapa de árbol dibujado en SVG.

.DESCRIPTION
    Es la mitad visual de lo que hacen WizTree y WinDirStat, dentro de un
    archivo que se puede archivar, enviar por correo o abrir sin conexión.

    -------------------------------------------------------------------
    POR QUE EL INFORME Y NO LA VENTANA, DE MOMENTO

    El cálculo del mapa ya está hecho y probado (`Mapa.ps1`): reparte un
    rectángulo entre elementos en proporción a su tamaño, y lo hace con
    el algoritmo cuadrado para que los rectángulos se puedan comparar con
    la vista y pulsar con el ratón.

    Dibujarlo tiene dos destinos posibles, y este se eligió primero a
    propósito:

      * En WPF no se puede COMPROBAR. La interfaz no arranca en las
        pruebas, así que un mapa dibujado ahí sería código que nadie ha
        visto funcionar.
      * En SVG sí. El resultado es texto: se puede verificar que los
        rectángulos están donde deben, que suman el área, y que el
        documento es válido.

    Cuando el mapa se lleve a la ventana, el cálculo y los colores ya
    estarán probados aquí. Ver [VIS-01] en docs/HOJA-DE-RUTA.md.

    -------------------------------------------------------------------
    EL COLOR DICE ALGO

    En WizTree el color distingue tipos de archivo. Aquí distingue **qué
    parte de ese espacio es recuperable**, que es lo que ninguno de los
    dos programas puede decir: WizTree no sabe qué es basura y los
    limpiadores no dibujan el disco.

    Una carpeta con candidatos de limpieza se pinta en el color de su
    riesgo; una carpeta sin nada que limpiar, en gris. De un vistazo se
    ve dónde está el espacio Y cuánto de él sobra.
#>

function Get-ColorMapa {
    <#
    .SYNOPSIS
        Color de un rectángulo del mapa según lo que se pueda recuperar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Riesgo = '')

    switch ($Riesgo) {
        'Bajo'  { return '#3dd68c' }   # recuperable sin pensarlo
        'Medio' { return '#f5a524' }   # recuperable con criterio
        'Alto'  { return '#ff5d5d' }   # mirar antes de tocar
        default { return '#3f4756' }   # nada que limpiar aquí
    }
}

function Get-MapaSvg {
    <#
    .SYNOPSIS
        Dibuja un nivel del índice como un mapa de árbol en SVG.

    .PARAMETER Indice
        Resultado de New-IndiceDisco.
    .PARAMETER Ruta
        Carpeta cuyo contenido se dibuja.
    .PARAMETER RiesgoPorCarpeta
        Tabla opcional ruta -> riesgo. Lo que convierte el mapa en algo
        que ningún analizador de disco puede enseñar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Indice,
        [Parameter(Mandatory)] [string] $Ruta,
        [int] $Ancho = 900,
        [int] $Alto  = 480,
        $RiesgoPorCarpeta = @{}
    )

    $hijas = @(Get-HijasDirectas -Indice $Indice -Ruta $Ruta)
    if ($hijas.Count -eq 0) { return '' }

    $rectangulos = @(Get-DisposicionMapa -Elementos $hijas -Ancho $Ancho -Alto $Alto -MinimoLado 4)

    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine(('<svg viewBox="0 0 {0} {1}" width="100%" xmlns="http://www.w3.org/2000/svg" class="mapa">' -f $Ancho, $Alto))

    foreach ($r in $rectangulos) {
        $elemento = $r.Elemento
        $riesgo = ''
        if ($null -ne $RiesgoPorCarpeta -and $RiesgoPorCarpeta.ContainsKey($elemento.Ruta)) {
            $riesgo = [string]$RiesgoPorCarpeta[$elemento.Ruta]
        }
        $color = Get-ColorMapa -Riesgo $riesgo

        $titulo = '{0} - {1}' -f $elemento.Nombre, (Format-Tamano $elemento.Bytes)
        if ($riesgo) { $titulo += ' - ' + $riesgo }

        [void]$sb.AppendLine(('  <g><title>{0}</title><rect x="{1:F1}" y="{2:F1}" width="{3:F1}" height="{4:F1}" fill="{5}" stroke="#0f1115" stroke-width="1"/>' -f
                              (ConvertTo-HtmlSeguro $titulo), $r.X, $r.Y, $r.Ancho, $r.Alto, $color))

        # El texto solo cabe si el rectángulo da de sí. Un nombre recortado
        # a dos letras no informa y ensucia el dibujo.
        if ($r.Ancho -ge 70 -and $r.Alto -ge 26) {
            $nombre = $elemento.Nombre
            if ($nombre.Length -gt [int]($r.Ancho / 7)) {
                $nombre = $nombre.Substring(0, [Math]::Max(3, [int]($r.Ancho / 7) - 1)) + [char]0x2026
            }
            [void]$sb.AppendLine(('    <text x="{0:F1}" y="{1:F1}" font-size="11" fill="#0f1115" font-family="Segoe UI,sans-serif">{2}</text>' -f
                                  ($r.X + 5), ($r.Y + 15), (ConvertTo-HtmlSeguro $nombre)))
            if ($r.Alto -ge 40) {
                [void]$sb.AppendLine(('    <text x="{0:F1}" y="{1:F1}" font-size="10" fill="#0f1115" opacity="0.75" font-family="Segoe UI,sans-serif">{2}</text>' -f
                                      ($r.X + 5), ($r.Y + 29), (Format-Tamano $elemento.Bytes)))
            }
        }
        [void]$sb.AppendLine('  </g>')
    }

    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

function Export-InformeEspacio {
    <#
    .SYNOPSIS
        Informe HTML de dónde se fue el espacio, con mapa de árbol.

    .PARAMETER Indice
        Resultado de New-IndiceDisco.
    .PARAMETER Candidatos
        Candidatos de un análisis, opcionales. Si vienen, el mapa colorea
        las carpetas por el riesgo de lo que se puede limpiar dentro.
    .PARAMETER Anonimo
        Sustituye perfil, usuario y equipo por marcadores.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Indice,
        [Parameter(Mandatory)] [string] $Ruta,
        $Candidatos = @(),
        [switch] $Anonimo
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Exportar informe de espacio')) { return }

    $texto = {
        param([string] $T)
        if ($Anonimo) { return ConvertTo-RutaAnonima $T }
        return $T
    }

    # --- Riesgo por carpeta, a partir de los candidatos ---------------
    # Se queda el riesgo MAS ALTO de lo que hay dentro: si en una carpeta
    # hay algo que conviene mirar, el mapa tiene que decirlo aunque el
    # resto sea inofensivo.
    $orden = @{ 'Bajo' = 1; 'Medio' = 2; 'Alto' = 3 }
    $riesgoPorCarpeta = @{}
    foreach ($c in @($Candidatos)) {
        if ($null -eq $c -or [string]::IsNullOrWhiteSpace($c.Ruta)) { continue }
        $carpeta = $c.Ruta
        while (-not [string]::IsNullOrWhiteSpace($carpeta)) {
            if ($Indice.Carpetas.ContainsKey($carpeta)) {
                $actual = if ($riesgoPorCarpeta.ContainsKey($carpeta)) { $riesgoPorCarpeta[$carpeta] } else { '' }
                $nuevoOrden  = if ($orden.ContainsKey($c.Riesgo)) { $orden[$c.Riesgo] } else { 0 }
                $actualOrden = if ($orden.ContainsKey($actual))   { $orden[$actual] }   else { 0 }
                if ($nuevoOrden -gt $actualOrden) { $riesgoPorCarpeta[$carpeta] = $c.Riesgo }
            }
            $padre = Split-Path $carpeta -Parent
            if ($padre -eq $carpeta) { break }
            $carpeta = $padre
        }
    }

    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<title>Cachivache - donde se fue el espacio</title>')
    [void]$sb.AppendLine((Get-InformeEstiloCss))
    [void]$sb.AppendLine('<style>.mapa{border-radius:8px;margin:12px 0}.mapa g:hover rect{opacity:.82;cursor:default}')
    [void]$sb.AppendLine('.leyenda{display:flex;gap:18px;flex-wrap:wrap;margin:8px 0 20px}')
    [void]$sb.AppendLine('.leyenda span{display:flex;align-items:center;gap:6px;font-size:13px}')
    [void]$sb.AppendLine('.punto{width:12px;height:12px;border-radius:3px;display:inline-block}</style>')
    [void]$sb.AppendLine('</head><body><div class="envoltorio">')

    [void]$sb.AppendLine('<h1>Dónde se fue el espacio</h1>')
    [void]$sb.AppendLine(('<p class="tenue">Generado el {0} · {1} en {2:N0} archivos y {3:N0} carpetas</p>' -f
                          (Get-Date).ToString('yyyy-MM-dd HH:mm'), (Format-Tamano $Indice.Bytes),
                          $Indice.TotalArchivos, $Indice.Carpetas.Count))

    if ($Indice.Compartidos -gt 0) {
        [void]$sb.AppendLine(('<p class="tenue">{0:N0} archivos comparten contenido con otros (enlaces duros) y se han contado una sola vez.</p>' -f
                              $Indice.Compartidos))
    }

    # --- Leyenda ------------------------------------------------------
    [void]$sb.AppendLine('<div class="leyenda">')
    foreach ($par in @(
        @{ C = (Get-ColorMapa -Riesgo 'Bajo');  T = 'Se puede limpiar' }
        @{ C = (Get-ColorMapa -Riesgo 'Medio'); T = 'Se puede limpiar, con criterio' }
        @{ C = (Get-ColorMapa -Riesgo 'Alto');  T = 'Míralo antes de tocarlo' }
        @{ C = (Get-ColorMapa);                 T = 'Nada que limpiar aquí' })) {
        [void]$sb.AppendLine(('<span><i class="punto" style="background:{0}"></i>{1}</span>' -f $par.C, $par.T))
    }
    [void]$sb.AppendLine('</div>')

    # --- Un mapa por raíz ---------------------------------------------
    foreach ($raiz in @($Indice.Raices)) {
        if (-not $Indice.Carpetas.ContainsKey($raiz)) { continue }
        $svg = Get-MapaSvg -Indice $Indice -Ruta $raiz -RiesgoPorCarpeta $riesgoPorCarpeta
        if ([string]::IsNullOrWhiteSpace($svg)) { continue }

        [void]$sb.AppendLine(('<h2>{0}</h2>' -f (ConvertTo-HtmlSeguro (& $texto $raiz))))
        [void]$sb.AppendLine($svg)
    }

    # --- Archivos mayores ---------------------------------------------
    [void]$sb.AppendLine('<h2>Archivos mayores</h2>')
    [void]$sb.AppendLine('<table><thead><tr><th>Tamaño</th><th>Archivo</th></tr></thead><tbody>')
    foreach ($a in @($Indice.Archivos | Select-Object -First 40)) {
        [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td></tr>' -f
                              (Format-Tamano $a.Bytes), (ConvertTo-HtmlSeguro (& $texto $a.Ruta))))
    }
    [void]$sb.AppendLine('</tbody></table>')

    [void]$sb.AppendLine('<p class="tenue">Este informe no propone ni borra nada: solo mide.</p>')
    [void]$sb.AppendLine('</div></body></html>')

    Set-Content -LiteralPath $Ruta -Value $sb.ToString() -Encoding UTF8
}
