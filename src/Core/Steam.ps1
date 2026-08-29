<#
.SYNOPSIS
    Lectura de los metadatos que Steam deja en disco.

.DESCRIPTION
    Todo lo de este archivo es de SOLO LECTURA, igual que Registry.ps1: no
    se escribe jamas en la configuracion de Steam.

    Vive en el nucleo y no dentro de 33-Juegos.ps1 por un motivo tecnico
    que conviene no olvidar: los modulos se cargan con dot-sourcing DENTRO
    de Get-ModulosLimpieza, asi que una funcion declarada en el archivo de
    un modulo desaparece en cuanto esa funcion termina. Un modulo puede
    declarar su bloque Buscar y sus datos, pero no funciones auxiliares.

    Y hay un motivo que no es tecnico: esto responde a "que tiene el equipo
    instalado segun Steam", que es la misma pregunta que responde
    Registry.ps1 para los programas de Windows. Son lectores del estado del
    equipo, no proponentes de limpieza. Ver docs/ESTRUCTURA.md.
#>

function Get-ValorVdf {
    <#
    .SYNOPSIS
        Extrae los valores de una clave de un archivo VDF de Valve.
    .DESCRIPTION
        El formato VDF es "clave" <espacios> "valor", una pareja por
        linea, con bloques anidados entre llaves. No hace falta un
        analizador completo para lo unico que se necesita aqui -leer
        "path" e "installdir"-, y escribir uno seria mucho codigo nuevo
        para ganar nada.

        Las barras invertidas vienen escapadas en el archivo ("D:\\Juegos")
        y se desescapan al leerlas.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [Parameter(Mandatory)] [string] $Clave
    )

    if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return @() }
    try   { $texto = [IO.File]::ReadAllText($Ruta) }
    catch { return @() }

    $patron = '"' + [regex]::Escape($Clave) + '"\s+"([^"]*)"'
    return @([regex]::Matches($texto, $patron, 'IgnoreCase') |
             ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } |
             Where-Object { $_ })
}

function Get-BibliotecasSteam {
    <#
    .SYNOPSIS
        Carpetas "steamapps" de todas las bibliotecas de Steam del equipo.
    .DESCRIPTION
        Steam permite repartir los juegos por varios discos, y la lista
        vive en libraryfolders.vdf. Mirar solo la carpeta de instalacion
        dejaria fuera justo las bibliotecas grandes, que es donde la gente
        pone los juegos precisamente por tamaño.

        Se exige que la carpeta steamapps EXISTA antes de devolverla: una
        biblioteca en un disco externo desconectado sigue apareciendo en el
        archivo, y proponer nada de ahi seria proponer sobre un disco que
        no esta.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $raices = [Collections.Generic.List[string]]::new()

    # 1. Donde esta instalado Steam.
    $instalacion = $null
    $clave = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue
    if ($clave -and $clave.SteamPath) { $instalacion = $clave.SteamPath -replace '/', '\' }

    if ([string]::IsNullOrWhiteSpace($instalacion)) {
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if ([string]::IsNullOrWhiteSpace($base)) { continue }
            $candidata = Join-RutaNativa $base 'Steam'
            if (Test-Path -LiteralPath $candidata) { $instalacion = $candidata; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($instalacion)) { return @() }

    $principal = Join-RutaNativa $instalacion 'steamapps'
    if (Test-Path -LiteralPath $principal) { $raices.Add($principal) }

    # 2. Bibliotecas declaradas en el VDF, en sus dos ubicaciones historicas.
    foreach ($vdf in @((Join-RutaNativa $instalacion 'steamapps' 'libraryfolders.vdf'),
                       (Join-RutaNativa $instalacion 'config' 'libraryfolders.vdf'))) {
        foreach ($ruta in (Get-ValorVdf -Ruta $vdf -Clave 'path')) {
            $steamapps = Join-RutaNativa $ruta 'steamapps'
            if ((Test-Path -LiteralPath $steamapps) -and ($raices -notcontains $steamapps)) {
                $raices.Add($steamapps)
            }
        }
    }

    return @($raices)
}
