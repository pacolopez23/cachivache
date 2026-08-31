<#
.SYNOPSIS
    Generación de informes en HTML, CSV y JSON.
#>

function Measure-TotalBytes {
    <#
    .SYNOPSIS
        Suma una propiedad de bytes de una lista de candidatos.
    .DESCRIPTION
        Existia tres veces en este mismo archivo, escrita de tres formas
        distintas: dos bucles foreach a mano y un Measure-Object. Una sola
        versión evita que se arreglen dos y se olvide la tercera.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        $Candidatos,
        [ValidateSet('Bytes', 'BytesLiberados')]
        [string] $Propiedad = 'Bytes'
    )

    $suma = 0.0
    foreach ($c in @($Candidatos)) { $suma += [double]$c.$Propiedad }
    return $suma
}

function ConvertTo-CsvSeguro {
    <#
    .SYNOPSIS
        Neutraliza un texto para que Excel no lo interprete como fórmula.

    .DESCRIPTION
        Excel evalúa como fórmula cualquier celda que empiece por =, +, -,
        @ o un tabulador, y las comillas de Export-Csv no lo impiden: son
        del formato CSV, no de Excel. Así que un archivo llamado

            =cmd|'/c calc'!A1.tmp

        se ejecuta al abrir el informe. Y esa entrada no es teórica: el
        nombre lo pone quien creó el archivo, y el módulo de arranque lee
        además nombres de servicio y valores del registro, que un programa
        malicioso ya instalado elige a su gusto.

        El apóstrofo delante es la convención de Excel para "esto es texto,
        no lo interpretes". Se ve en la barra de fórmulas pero no en la
        celda, así que el informe se sigue leyendo igual.

        El informe HTML no necesita esto: ahí cada campo pasa por
        ConvertTo-HtmlSeguro.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Texto)

    if ([string]::IsNullOrEmpty($Texto)) { return $Texto }

    # Se mira el primer caracter NO BLANCO. Excel ignora los espacios de
    # delante al decidir si una celda es una formula, asi que " =HYPERLINK(...)"
    # se evalua igual que "=HYPERLINK(...)" pero se colaba por este filtro,
    # que miraba $Texto[0] a secas. Ver [SEG-64] en docs/PLAN-ACCION.md.
    $recortado = $Texto.TrimStart()
    if ([string]::IsNullOrEmpty($recortado)) { return $Texto }
    if ($recortado[0] -in @('=', '+', '-', '@', "`t", "`r")) { return "'" + $Texto }
    return $Texto
}

function Export-InformeCsv {
    <#
    .SYNOPSIS
        Vuelca los candidatos a un CSV listo para abrir en Excel.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Candidatos,
        [Parameter(Mandatory)] [string] $Ruta,
        # Sustituye el perfil, el nombre de usuario y el del equipo por
        # marcadores. Para compartir el informe con alguien. Ver
        # ConvertTo-RutaAnonima en Format.ps1.
        [switch] $Anonimo
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Exportar CSV')) { return }

    # Se compone el tratamiento de texto una sola vez: si es anonimo, se
    # anonimiza ANTES de neutralizar la formula de Excel, para que el
    # apostrofo protector no acabe en medio de la ruta.
    $limpiar = if ($Anonimo) {
        { param($t) ConvertTo-CsvSeguro (ConvertTo-RutaAnonima $t) }
    } else {
        { param($t) ConvertTo-CsvSeguro $t }
    }
    # Todo campo cuyo contenido venga del disco o del registro pasa por
    # ConvertTo-CsvSeguro. Los que no: Modulo, Riesgo y Metodo salen de un
    # ValidateSet, y los numéricos y booleanos los genera el programa.
    @($Candidatos) |
        Select-Object @{ n = 'Modulo';        e = { $_.ModuloId } },
                      @{ n = 'Categoria';     e = { & $limpiar $_.Categoria } },
                      @{ n = 'Nombre';        e = { & $limpiar $_.Nombre } },
                      @{ n = 'Ruta';          e = { & $limpiar $_.Ruta } },
                      @{ n = 'Bytes';         e = { [long]$_.Bytes } },
                      @{ n = 'Tamano';        e = { Format-Tamano $_.Bytes } },
                      Riesgo, Metodo,
                      @{ n = 'Info';          e = { & $limpiar $_.Info } },
                      @{ n = 'Efecto';        e = { & $limpiar $_.Efecto } },
                      @{ n = 'Aviso';         e = { & $limpiar $_.Aviso } },
                      @{ n = 'Seleccionado';  e = { $_.Seleccionado } },
                      @{ n = 'Eliminado';     e = { $_.Hecho } },
                      @{ n = 'Liberado';      e = { Format-Tamano $_.BytesLiberados } },
                      @{ n = 'Error';         e = { & $limpiar $_.Error } } |
        Export-Csv -LiteralPath $Ruta -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
}

function Export-InformeJson {
    <#
    .SYNOPSIS
        Vuelca el análisis completo a JSON, para integrarlo con otras cosas.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Candidatos,
        [Parameter(Mandatory)] [string] $Ruta,
        $Configuracion = $null,
        [switch] $Anonimo
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Exportar JSON')) { return }

    $total = Measure-TotalBytes $Candidatos

    # El nombre del equipo YA NO se guarda. No servia para nada -quien lee
    # el informe suele ser su propio dueño- y en cambio viajaba en cada
    # archivo que alguien adjuntara a una incidencia. Un dato que no se
    # usa y que identifica es un dato que sobra.
    $documento = [pscustomobject]@{
        Generado   = (Get-Date).ToString('o')
        Version    = $script:VersionCachivache
        Perfil     = if ($Configuracion) { $Configuracion.Perfil } else { '' }
        Total      = $total
        Elementos  = @($Candidatos).Count
        Candidatos = @($Candidatos | Select-Object ModuloId, Categoria, Nombre, Bytes,
                                                   Riesgo, Metodo, Seleccionado, Hecho,
                                                   BytesLiberados,
            @{ n = 'Ruta';   e = { if ($Anonimo) { ConvertTo-RutaAnonima $_.Ruta }   else { $_.Ruta } } },
            @{ n = 'Info';   e = { if ($Anonimo) { ConvertTo-RutaAnonima $_.Info }   else { $_.Info } } },
            @{ n = 'Efecto'; e = { if ($Anonimo) { ConvertTo-RutaAnonima $_.Efecto } else { $_.Efecto } } },
            @{ n = 'Aviso';  e = { if ($Anonimo) { ConvertTo-RutaAnonima $_.Aviso }  else { $_.Aviso } } },
            @{ n = 'Error';  e = { if ($Anonimo) { ConvertTo-RutaAnonima $_.Error }  else { $_.Error } } })
    }
    $documento | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Ruta -Encoding UTF8 -ErrorAction Stop
}

function ConvertTo-HtmlSeguro {
    [OutputType([string])]
    param([string] $Texto)
    if ([string]::IsNullOrEmpty($Texto)) { return '' }
    return [Net.WebUtility]::HtmlEncode($Texto)
}

function Get-InformeEstiloCss {
    <#
    .SYNOPSIS
        Hoja de estilos del informe HTML.
    .DESCRIPTION
        Vive aparte del código que compone el informe a propósito: son dos
        cosas que se tocan por motivos distintos (cambiar el aspecto no es
        lo mismo que cambiar que datos se muestran) y tenerlas juntas hacia
        que Export-InformeHtml pareciera mucho más complicada de lo que es.

        El informe es un único archivo autocontenido, sin dependencias
        externas: se puede adjuntar en un correo o abrir sin conexion.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @'
<style>
:root{--bg:#0f1115;--surface:#161a21;--surface2:#1d222b;--border:#262c37;
--text:#e6eaf2;--muted:#8a93a6;--accent:#4c8dff;--ok:#3dd68c;--warn:#f5a524;--danger:#ff5d5d}
*{box-sizing:border-box}
body{margin:0;padding:32px;background:var(--bg);color:var(--text);
font-family:"Segoe UI Variable Text","Segoe UI",system-ui,sans-serif;font-size:14px;line-height:1.55}
.wrap{max-width:1180px;margin:0 auto}
h1{font-size:28px;font-weight:600;margin:0 0 4px}
h2{font-size:17px;font-weight:600;margin:36px 0 12px;display:flex;align-items:center;gap:10px}
.sub{color:var(--muted);margin:0 0 28px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px;margin-bottom:32px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:18px}
.card .k{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.06em}
.card .v{font-size:26px;font-weight:600;margin-top:6px}
.card.acc .v{color:var(--accent)} .card.ok .v{color:var(--ok)}
/* table-layout:fixed y anchos explicitos.
   Sin esto el navegador reparte el ancho segun el contenido, y como la
   ruta se podia partir por cualquier letra (word-break:break-all) la
   consideraba infinitamente estrechable: le daba cuatro caracteres y
   dejaba las rutas en una tira vertical ilegible. Con anchos fijos, cada
   columna tiene lo suyo pase lo que pase con el contenido. */
table{width:100%;table-layout:fixed;border-collapse:collapse;background:var(--surface);
border:1px solid var(--border);border-radius:12px;overflow:hidden}
col.c-elem{width:26%} col.c-ruta{width:34%} col.c-tam{width:10%}
col.c-riesgo{width:9%} col.c-efecto{width:21%}
th{background:var(--surface2);text-align:left;padding:11px 14px;font-weight:600;
font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
td{padding:11px 14px;border-top:1px solid var(--border);vertical-align:top;
overflow-wrap:anywhere}
tr:hover td{background:rgba(255,255,255,.02)}
/* overflow-wrap:anywhere en vez de word-break:break-all: parte solo
   cuando de verdad no cabe, en lugar de cortar cada linea a mitad de
   palabra aunque quedara sitio. */
.path{font-family:"Cascadia Mono",Consolas,monospace;font-size:12px;color:var(--muted);
overflow-wrap:anywhere}
.num{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
.chip{display:inline-block;padding:2px 9px;border-radius:999px;font-size:11px;font-weight:600}
.chip.bajo{background:rgba(61,214,140,.14);color:var(--ok)}
.chip.medio{background:rgba(245,165,36,.14);color:var(--warn)}
.chip.alto{background:rgba(255,93,93,.14);color:var(--danger)}
.aviso{color:var(--danger);font-size:12px;display:block;margin-top:4px}
.count{color:var(--muted);font-weight:400;font-size:13px}
footer{margin-top:48px;color:var(--muted);font-size:12px;border-top:1px solid var(--border);padding-top:18px}
@media print{body{background:#fff;color:#111}.card,table{border-color:#ddd;background:#fff}}
</style>
'@
}

function Export-InformeHtml {
    <#
    .SYNOPSIS
        Genera un informe HTML autocontenido, sin dependencias externas.
    .DESCRIPTION
        Un único archivo con estilos incrustados que se puede archivar,
        enviar por correo o abrir sin conexion. Agrupa por módulo y marca
        con color los elementos que llevan aviso.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Candidatos,
        [Parameter(Mandatory)] [string] $Ruta,
        [Parameter(Mandatory)] $Configuracion,
        [ValidateSet('analisis', 'limpieza')] [string] $Tipo = 'analisis',
        $Modulos = @(),
        [switch] $Anonimo
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Exportar informe HTML')) { return }

    $lista         = @($Candidatos)
    $totalBytes    = Measure-TotalBytes $lista 'Bytes'
    $totalLiberado = Measure-TotalBytes $lista 'BytesLiberados'

    $nombresModulo = @{}
    foreach ($m in @($Modulos)) { $nombresModulo[$m.Id] = $m.Nombre }

    $titulo = if ($Tipo -eq 'limpieza') { 'Informe de limpieza' } else { 'Informe de análisis' }

    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="es"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>$titulo - Cachivache</title>")
    [void]$sb.AppendLine((Get-InformeEstiloCss))
    [void]$sb.AppendLine('</head><body><div class="wrap">')

    [void]$sb.AppendLine("<h1>$titulo</h1>")
    [void]$sb.AppendLine(('<p class="sub">{0} &middot; {1} &middot; perfil {2} &middot; {3}</p>' -f
        (ConvertTo-HtmlSeguro $Configuracion.Equipo),
        (ConvertTo-HtmlSeguro $Configuracion.Windows),
        (ConvertTo-HtmlSeguro $Configuracion.Perfil),
        (Get-Date -Format 'dd/MM/yyyy HH:mm')))

    [void]$sb.AppendLine('<div class="cards">')
    [void]$sb.AppendLine(('<div class="card"><div class="k">Elementos</div><div class="v">{0}</div></div>' -f $lista.Count))
    [void]$sb.AppendLine(('<div class="card acc"><div class="k">Espacio detectado</div><div class="v">{0}</div></div>' -f (Format-Tamano $totalBytes)))
    if ($Tipo -eq 'limpieza') {
        [void]$sb.AppendLine(('<div class="card ok"><div class="k">Espacio liberado</div><div class="v">{0}</div></div>' -f (Format-Tamano $totalLiberado)))
    }
    foreach ($unidad in @($Configuracion.Unidades)) {
        [void]$sb.AppendLine(('<div class="card"><div class="k">Libre en {0}</div><div class="v">{1}</div></div>' -f
            (ConvertTo-HtmlSeguro $unidad.Letra), (Format-Tamano $unidad.Libre)))
    }
    [void]$sb.AppendLine('</div>')

    foreach ($grupo in ($lista | Group-Object ModuloId | Sort-Object { -(Measure-TotalBytes $_.Group) })) {
        $nombre = if ($nombresModulo.ContainsKey($grupo.Name)) { $nombresModulo[$grupo.Name] } else { $grupo.Name }
        $suma   = Measure-TotalBytes $grupo.Group
        [void]$sb.AppendLine(('<h2>{0} <span class="count">{1} elementos &middot; {2}</span></h2>' -f
            (ConvertTo-HtmlSeguro $nombre), $grupo.Count, (Format-Tamano $suma)))
        [void]$sb.AppendLine('<table><colgroup><col class="c-elem"><col class="c-ruta"><col class="c-tam"><col class="c-riesgo"><col class="c-efecto"></colgroup>')
        [void]$sb.AppendLine('<thead><tr><th>Elemento</th><th>Ruta</th><th class="num">Tamaño</th><th>Riesgo</th><th>Efecto</th></tr></thead><tbody>')

        foreach ($c in ($grupo.Group | Sort-Object Bytes -Descending)) {
            $aviso = ''
            if (-not [string]::IsNullOrWhiteSpace($c.Aviso)) {
                $aviso = '<span class="aviso">Atención: ' + (ConvertTo-HtmlSeguro $c.Aviso) + '</span>'
            }
            $tam = if ($c.Bytes -gt 0) { Format-Tamano $c.Bytes } else { '&mdash;' }
            [void]$sb.AppendLine(('<tr><td><strong>{0}</strong><br><span class="count">{1}</span>{2}</td><td class="path">{3}</td><td class="num">{4}</td><td><span class="chip {5}">{6}</span></td><td>{7}</td></tr>' -f
                (ConvertTo-HtmlSeguro $c.Nombre),
                (ConvertTo-HtmlSeguro $c.Info),
                $aviso,
                (ConvertTo-HtmlSeguro $(if ($Anonimo) { ConvertTo-RutaAnonima $c.Ruta } else { $c.Ruta })),
                $tam,
                $c.Riesgo.ToLowerInvariant(),
                (ConvertTo-HtmlSeguro $c.Riesgo),
                (ConvertTo-HtmlSeguro $c.Efecto)))
        }
        [void]$sb.AppendLine('</tbody></table>')
    }

    if ($lista.Count -eq 0) {
        [void]$sb.AppendLine('<p class="sub">No se ha encontrado nada que limpiar con estos umbrales.</p>')
    }

    [void]$sb.AppendLine(('<footer>Generado por Cachivache v{0}. Este informe describe lo que el programa PROPONE; no implica que se haya borrado nada salvo que se indique lo contrario.</footer>' -f $script:VersionCachivache))
    [void]$sb.AppendLine('</div></body></html>')

    # -ErrorAction Stop, y no es adorno. Set-Content sobre una carpeta que
    # no existe -o sin permiso de escritura- da un error NO TERMINANTE: la
    # funcion sigue, termina como si nada y NO lanza. Los cuatro sitios
    # que exportan estan envueltos en un try/catch de quien llama, asi que
    # el catch no se disparaba nunca y la consola escribia "Informe
    # guardado en ..." sobre un archivo que no existe. Peor: la ruta se
    # anotaba en el historial, de modo que la ventana ofrecia despues una
    # tarjeta para abrir un informe que nunca se escribio.
    #
    # O sea, la misma familia que [COR-01]: el programa diciendo que hizo
    # algo que no hizo. Lo encontro la primera prueba que se escribio para
    # el modo consola; hay una invariante que exige el -ErrorAction Stop en
    # los cuatro exportadores.
    Set-Content -LiteralPath $Ruta -Value $sb.ToString() -Encoding UTF8 -ErrorAction Stop
}

function New-NombreInforme {
    <#
    .SYNOPSIS
        Compone una ruta de informe con marca de tiempo.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Compone una ruta; la carpeta se crea con New-Item, que ya avisa.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Tipo,
        [Parameter(Mandatory)] [string] $Extension,
        [string] $CarpetaDatos = (Get-CarpetaDatos)
    )

    $carpeta = Join-Path $CarpetaDatos 'informes'
    if (-not (Test-Path -LiteralPath $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    }
    $marca = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    return (Join-Path $carpeta "$Tipo`_$marca.$Extension")
}

function Get-CarpetaInformes {
    <#
    .SYNOPSIS
        Carpeta donde viven los informes generados.
    .DESCRIPTION
        Un único sitio que diga donde están. Antes solo lo sabia
        New-NombreInforme, escondido en la mitad de su cuerpo, así que
        cualquiera que quisiera LEER informes tenia que repetir el
        Join-Path y confiar en que no cambiara.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $CarpetaDatos = (Get-CarpetaDatos))

    return (Join-Path $CarpetaDatos 'informes')
}

function Get-InformesGuardados {
    <#
    .SYNOPSIS
        Enumera los informes ya generados, del más reciente al más antiguo.

    .DESCRIPTION
        Devuelve objetos con lo que la interfaz necesita para pintar una
        lista: nombre, tipo, formato, fecha y tamaño. La fecha sale del
        NOMBRE del archivo cuando encaja con el patron que escribe
        New-NombreInforme, y si no, de la fecha de escritura del propio
        archivo: renombrar un informe a mano no debe hacer que desaparezca
        de la lista ni que se muestre sin fecha.

        Nunca falla: si la carpeta no existe todavía -porque el programa
        acaba de instalarse y no se ha exportado nada- devuelve una lista
        vacía. El panel que la consume tiene que poder abrirse igual y
        decir que no hay nada, en vez de quedarse en blanco.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('html', 'csv', 'json')]
        [string] $Formato = '',
        [string] $CarpetaDatos = (Get-CarpetaDatos)
    )

    $carpeta = Get-CarpetaInformes -CarpetaDatos $CarpetaDatos
    if (-not (Test-Path -LiteralPath $carpeta)) { return @() }

    $extensiones = if ($Formato) { @($Formato) } else { @('html', 'csv', 'json') }
    $encontrados = @()

    foreach ($archivo in @(Get-ChildItem -LiteralPath $carpeta -File -ErrorAction SilentlyContinue)) {
        $ext = $archivo.Extension.TrimStart('.').ToLowerInvariant()
        if ($extensiones -notcontains $ext) { continue }

        # analisis_2026-08-19_143005.html -> tipo 'análisis', fecha exacta.
        $tipo  = 'informe'
        $fecha = $archivo.LastWriteTime
        if ($archivo.BaseName -match '^(?<tipo>[a-z]+)_(?<f>\d{4}-\d{2}-\d{2})_(?<h>\d{2})(?<m>\d{2})(?<s>\d{2})$') {
            $tipo = $Matches['tipo']
            # ParseExact con InvariantCulture: el formato lo escribimos
            # nosotros, no depende del idioma del equipo.
            $texto = '{0} {1}:{2}:{3}' -f $Matches['f'], $Matches['h'], $Matches['m'], $Matches['s']
            try {
                $fecha = [datetime]::ParseExact($texto, 'yyyy-MM-dd HH:mm:ss',
                                                [Globalization.CultureInfo]::InvariantCulture)
            } catch {
                $fecha = $archivo.LastWriteTime
            }
        }

        $encontrados += [pscustomobject]@{
            Nombre  = $archivo.Name
            Ruta    = $archivo.FullName
            Formato = $ext
            Tipo    = $tipo
            Fecha   = $fecha
            Bytes   = [double]$archivo.Length
        }
    }

    return @($encontrados | Sort-Object -Property Fecha -Descending)
}

function Resolve-InformeAbrible {
    <#
    .SYNOPSIS
        Devuelve la ruta de un informe que se puede abrir, o $null.

    .DESCRIPTION
        Esta función es una GUARDIA, no una comodidad. La interfaz abre
        informes con el programa predeterminado del sistema, y la ruta que
        abre no siempre la ha escrito el programa: las entradas del
        historial viven en un .json de texto plano dentro de una carpeta
        donde el usuario -o cualquier cosa que corra como el- puede
        escribir. Una entrada manipulada podría apuntar a un .lnk, un .ps1
        o un ejecutable en cualquier sitio del disco, y abrirlo con el
        programa predeterminado sería ejecutarlo.

        Por eso se comprueban cuatro cosas, y se exigen las cuatro:
          1. La extensión es html, csv o json. Nada más se abre jamas.
          2. La ruta, ya resuelta a absoluta y canonica, cuelga de la
             carpeta de informes. Se compara sobre la ruta canonica
             precisamente para que '..\..\Windows\System32\x.html' no
             cuele: al canonizarla deja de estar dentro y se rechaza.
          3. Es un archivo que existe.
          4. No es un enlace ni un punto de reanalisis, que apuntarian
             fuera de la carpeta manteniendo la apariencia de estar dentro.

        Ante cualquier duda devuelve $null: no abrir un informe legitimo es
        una molestia; abrir lo que no toca, un problema de seguridad.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Ruta,
        [string] $CarpetaDatos = (Get-CarpetaDatos)
    )

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $null }

    $extension = [IO.Path]::GetExtension($Ruta)
    if ([string]::IsNullOrWhiteSpace($extension)) { return $null }
    if (@('.html', '.csv', '.json') -notcontains $extension.ToLowerInvariant()) { return $null }

    $carpeta = Get-CarpetaInformes -CarpetaDatos $CarpetaDatos

    try {
        $completa  = [IO.Path]::GetFullPath($Ruta)
        $baseLimpia = [IO.Path]::GetFullPath($carpeta).TrimEnd([IO.Path]::DirectorySeparatorChar)
    } catch {
        return $null
    }

    # El separador final es imprescindible: sin el, "C:\...\informesFalsa"
    # empezaria por "C:\...\informes" y pasaria la comprobación.
    $prefijo = $baseLimpia + [IO.Path]::DirectorySeparatorChar
    if (-not $completa.StartsWith($prefijo, [StringComparison]::OrdinalIgnoreCase)) { return $null }

    $elemento = Get-Item -LiteralPath $completa -Force -ErrorAction SilentlyContinue
    if ($null -eq $elemento) { return $null }
    if ($elemento.PSIsContainer) { return $null }
    if (($elemento.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }

    return $completa
}
