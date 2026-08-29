<#
.SYNOPSIS
    Restos de juegos y de sus plataformas: Steam, Epic, Battle.net, GOG,
    EA, Ubisoft y Riot.
.DESCRIPTION
    Antes de este módulo la cobertura de juegos del programa era una sola
    entrada: la cache web de Steam. Y los juegos son, con diferencia, lo
    que más espacio ocupa y lo que peor se desinstala: las plataformas
    dejan atras instalaciones que ellas mismas ya no ven, cachés de
    sombreadores por juego, descargas abortadas y contenido del taller de
    juegos que se fueron hace años.

    DOS CLASES DE CANDIDATO, y no se mezclan:

      Basura regenerable   Cachés, registros, descargas a medias, volcados.
                           La plataforma los vuelve a crear sola. Riesgo
                           bajo, se proponen marcados.

      Instalaciones huerfanas   Carpetas de juego que la plataforma ya no
                           reconoce. Aquí se recupera el espacio de verdad
                           -decenas de GB-, pero decidirlo mal duele, así
                           que nunca van marcadas.

    LO QUE NO SE TOCA JAMAS, por mucho que parezca basura:

      * "Ubisoft Game Launcher\savegames" son partidas guardadas.
      * "userdata\<id>\<appid>\remote" son partidas en la nube de Steam.
      * "Documents\My Games\<Juego>" y "Saved Games\<Juego>" son partidas.
        De estas carpetas solo se proponen sus subcarpetas de registro,
        volcados y cache; la carpeta del juego en si es informativa.

    Ver [DET-30] a [DET-37] en docs/PLAN-ACCION.md.
#>

$BuscarJuegos = {
    param($Configuracion, $Sync)

    $LA = $env:LOCALAPPDATA
    $RA = $env:APPDATA
    $PD = $env:ProgramData
    $UP = $env:USERPROFILE

    # ==================================================================
    # 1. Cachés y registros de las plataformas: basura pura
    # ==================================================================
    $plataformas = @(
        # --- Steam ------------------------------------------------------
        @{ N = 'Caché web de Steam';          R = "$LA\Steam\htmlcache";  M = 'Contenido'; Menor = $true;  E = 'Se regenera. Cierra Steam antes.' }

        # --- Epic Games -------------------------------------------------
        @{ N = 'Registros de Epic Games';     R = "$LA\EpicGamesLauncher\Saved\Logs";     M = 'Contenido'; Menor = $true;  E = 'Sin efecto. Cierra Epic antes.' }
        @{ N = 'Caché web de Epic Games';     R = "$LA\EpicGamesLauncher\Saved\webcache"; M = 'Contenido'; Menor = $true;  E = 'Se regenera. Cierra Epic antes.' }
        @{ N = 'Caché de datos derivados de Unreal'; R = "$LA\UnrealEngine\Common\DerivedDataCache"; M = 'Contenido'; Menor = $false; E = 'Se regenera al abrir el proyecto. La primera compilación tardará mucho más.' }

        # --- Battle.net / Blizzard --------------------------------------
        @{ N = 'Caché de Battle.net';         R = "$PD\Battle.net\Cache";  M = 'Contenido'; Menor = $false; E = 'Se regenera. Cierra Battle.net antes.' }
        @{ N = 'Caché local de Battle.net';   R = "$LA\Battle.net\Cache";  M = 'Contenido'; Menor = $true;  E = 'Se regenera.' }
        @{ N = 'Registros de Battle.net';     R = "$RA\Battle.net\Logs";   M = 'Contenido'; Menor = $true;  E = 'Sin efecto.' }
        @{ N = 'Caché de Blizzard';           R = "$PD\Blizzard Entertainment\Battle.net\Cache"; M = 'Contenido'; Menor = $false; E = 'Se regenera. Suele ser lo que más ocupa de Battle.net.' }

        # --- GOG Galaxy --------------------------------------------------
        @{ N = 'Caché web de GOG Galaxy';     R = "$PD\GOG.com\Galaxy\webcache"; M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Registros de GOG Galaxy';     R = "$PD\GOG.com\Galaxy\logs";     M = 'Contenido'; Menor = $true; E = 'Sin efecto.' }

        # --- EA / Origin --------------------------------------------------
        @{ N = 'Registros de EA Desktop';     R = "$LA\Electronic Arts\EA Desktop\Logs";  M = 'Contenido'; Menor = $true; E = 'Sin efecto.' }
        @{ N = 'Caché de EA Desktop';         R = "$LA\Electronic Arts\EA Desktop\caché"; M = 'Contenido'; Menor = $true; E = 'Se regenera.' }
        @{ N = 'Registros de Origin';         R = "$PD\Origin\Logs";                      M = 'Contenido'; Menor = $true; E = 'Sin efecto.' }

        # --- Ubisoft Connect ----------------------------------------------
        # OJO: la carpeta hermana "savegames" son PARTIDAS GUARDADAS y no
        # aparece en esta lista a proposito. No se anyade nunca.
        @{ N = 'Caché de Ubisoft Connect';    R = "$LA\Ubisoft Game Launcher\caché";  M = 'Contenido'; Menor = $true; E = 'Se regenera. No toca tus partidas guardadas.' }
        @{ N = 'Registros de Ubisoft Connect';R = "$LA\Ubisoft Game Launcher\logs";   M = 'Contenido'; Menor = $true; E = 'Sin efecto.' }

        # --- Riot Games -----------------------------------------------------
        @{ N = 'Registros de Riot Client';    R = "$LA\Riot Games\Riot Client\Logs";  M = 'Contenido'; Menor = $true; E = 'Sin efecto.' }
        @{ N = 'Datos de Riot Client';        R = "$LA\Riot Games\Riot Client\Data";  M = 'Contenido'; Menor = $true; E = 'Se regenera al abrir el cliente.' }
    )

    # Si no hay ni una zona -un perfil sin las variables de entorno
    # habituales, o las pruebas- no se llama siquiera: -Raices es
    # obligatorio y un array vacio no satisface el enlace de parametros,
    # asi que el modulo entero reventaria en vez de no encontrar nada.
    # Quedarse sin candidatos es un resultado; lanzar no lo es.
    $raicesPlataformas = @(@($LA, $RA, $PD) | Where-Object { $_ })

    if ($raicesPlataformas.Count -gt 0) {
        Invoke-BusquedaPorLista -ModuloId 'juegos' -Categoria 'Plataformas de juego' `
                                -Entradas $plataformas -Raices $raicesPlataformas -Sync $Sync `
                                -MinimoBytes 1MB -ForzarPermanente `
                                -IncluirMenores:$Configuracion.IncluirMenores
    }

    # ==================================================================
    # 2. Steam: biblioteca por biblioteca
    # ==================================================================
    foreach ($steamapps in (Get-BibliotecasSteam)) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Revisando la biblioteca de Steam en $(Get-RutaCorta $steamapps)..."

        $raices = @($steamapps)

        # --- 2a. Basura regenerable de la biblioteca --------------------
        $basura = @(
            @{ N = 'Descargas de Steam a medias'; R = (Join-RutaNativa $steamapps 'downloading');        M = 'Contenido'; Menor = $false; E = 'Descargas interrumpidas. Steam las vuelve a bajar si hacen falta.' }
            @{ N = 'Temporales de Steam';         R = (Join-RutaNativa $steamapps 'temp');               M = 'Contenido'; Menor = $true;  E = 'Sin efecto.' }
            @{ N = 'Descargas del taller';        R = (Join-RutaNativa $steamapps 'workshop' 'downloads'); M = 'Contenido'; Menor = $true;  E = 'Descargas de mods a medias. Se vuelven a bajar.' }
        )
        Invoke-BusquedaPorLista -ModuloId 'juegos' -Categoria 'Steam' `
                                -Entradas $basura -Raices $raices -Sync $Sync `
                                -MinimoBytes 1MB -ForzarPermanente `
                                -IncluirMenores:$Configuracion.IncluirMenores

        # --- 2b. Que juegos conoce Steam de verdad ----------------------
        # Un appmanifest_<appid>.acf por juego instalado. Su "installdir"
        # dice el nombre de la carpeta dentro de common. Lo que esta en
        # common sin manifiesto es una instalacion que Steam ya no ve: no
        # aparece en la biblioteca, no se puede jugar y no se actualiza.
        $instalados = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase)
        $appids = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase)

        foreach ($acf in @(Get-ChildItem -LiteralPath $steamapps -Filter 'appmanifest_*.acf' `
                                         -File -Force -ErrorAction SilentlyContinue)) {
            foreach ($dir in (Get-ValorVdf -Ruta $acf.FullName -Clave 'installdir')) {
                [void]$instalados.Add($dir)
            }
            if ($acf.Name -match 'appmanifest_(\d+)\.acf') { [void]$appids.Add($Matches[1]) }
        }

        # Sin un solo manifiesto no se puede afirmar nada: puede que Steam
        # no haya terminado de escribir, o que esta no sea una biblioteca
        # de verdad. Declarar huerfano TODO seria el peor falso positivo
        # que este programa puede cometer.
        if ($instalados.Count -eq 0) { continue }

        $common = Join-RutaNativa $steamapps 'common'
        if (Test-Path -LiteralPath $common) {
            foreach ($juego in @(Get-ChildItem -LiteralPath $common -Directory -Force -ErrorAction SilentlyContinue)) {
                if (Test-Cancelacion $Sync) { break }
                if ($instalados.Contains($juego.Name))  { continue }
                if (Test-EsEnlace $juego)               { continue }
                if (-not (Test-RutaSegura $juego.FullName $raices)) { continue }

                Set-Progreso $Sync "Midiendo: $($juego.Name)"
                $resumen = Get-ResumenArbol -Carpeta $juego
                if ($resumen.Bytes -lt ($Configuracion.MinimoMB * 1MB)) { continue }

                New-Candidato -ModuloId 'juegos' -Categoria 'Juegos que Steam ya no reconoce' `
                              -Nombre $juego.Name -Ruta $juego.FullName -Bytes $resumen.Bytes `
                              -Info "$($resumen.Archivos) archivos en la biblioteca $(Get-RutaElidida $steamapps 45)" `
                              -Efecto 'Steam no tiene manifiesto de este juego: no aparece en tu biblioteca, no se actualiza y no se puede jugar sin volver a instalarlo.' `
                              -Aviso 'Comprueba que no es un juego que instalaste a mano o copiaste de otro equipo.' `
                              -Metodo 'Ruta' -Raices $raices -Riesgo 'Medio'
            }
        }

        # --- 2c. Cache de sombreadores y taller de juegos que ya no estan
        foreach ($par in @(
            @{ Carpeta = (Join-RutaNativa $steamapps 'shadercache')
               Categoria = 'Steam'
               Riesgo = 'Bajo'
               Aviso = ''
               Efecto = 'Sombreadores precompilados de un juego que ya no está instalado. Se regeneran solos si lo reinstalas.' }
            @{ Carpeta = (Join-RutaNativa $steamapps 'workshop' 'content')
               Categoria = 'Steam'
               Riesgo = 'Medio'
               Aviso = 'Son mods descargados del taller de un juego que ya no está instalado.'
               Efecto = 'Contenido del taller de un juego desinstalado. Se vuelve a descargar si reinstalas el juego.' })) {

            if (-not (Test-Path -LiteralPath $par.Carpeta)) { continue }

            foreach ($carpeta in @(Get-ChildItem -LiteralPath $par.Carpeta -Directory -Force -ErrorAction SilentlyContinue)) {
                if (Test-Cancelacion $Sync) { break }
                # Solo las carpetas que son un identificador de aplicacion:
                # cualquier otra cosa aqui dentro no se sabe que es.
                if ($carpeta.Name -notmatch '^\d+$')     { continue }
                if ($appids.Contains($carpeta.Name))     { continue }
                if (Test-EsEnlace $carpeta)              { continue }
                if (-not (Test-RutaSegura $carpeta.FullName $raices)) { continue }

                $resumen = Get-ResumenArbol -Carpeta $carpeta
                if ($resumen.Bytes -lt ($Configuracion.MinimoMB * 1MB)) { continue }

                New-Candidato -ModuloId 'juegos' -Categoria $par.Categoria `
                              -Nombre "$(Split-Path $par.Carpeta -Leaf) del juego $($carpeta.Name)" `
                              -Ruta $carpeta.FullName -Bytes $resumen.Bytes `
                              -Info "$($resumen.Archivos) archivos - ningún juego instalado usa el identificador $($carpeta.Name)" `
                              -Efecto $par.Efecto -Aviso $par.Aviso `
                              -Metodo 'Ruta' -Raices $raices -Riesgo $par.Riesgo
            }
        }
    }

    # ==================================================================
    # 3. Partidas guardadas: SOLO informativo, y su basura interna
    # ==================================================================
    # La carpeta de un juego aqui dentro es la partida. No se propone
    # jamas para borrar: se informa de lo que ocupa y ya. Lo que si es
    # seguro proponer son sus subcarpetas de registro y volcados, que los
    # motores de juego recrean solos.
    # Join-RutaNativa y no Join-Path: estas dos rutas se construyen sobre
    # carpetas que se han descubierto en el equipo, y Join-Path resuelve la
    # unidad a traves del proveedor de PowerShell. Ver el comentario de
    # Join-RutaNativa en FileSystem.ps1.
    $zonasPartidas = @()
    $documentos = Get-CarpetaConocida -Nombre 'Documents'
    if ($documentos) { $zonasPartidas += (Join-RutaNativa $documentos 'My Games') }
    if ($UP)         { $zonasPartidas += (Join-RutaNativa $UP 'Saved Games') }

    $basuraDeJuego = @('Logs', 'Crashes', 'DerivedDataCache', 'ShaderCache', 'CrashReportClient')

    foreach ($zona in ($zonasPartidas | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
        if (Test-Cancelacion $Sync) { break }
        Set-Progreso $Sync "Revisando $(Get-RutaCorta $zona)..."

        foreach ($juego in @(Get-ChildItem -LiteralPath $zona -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Cancelacion $Sync) { break }
            if (Test-EsEnlace $juego) { continue }

            $resumen = Get-ResumenArbol -Carpeta $juego
            if ($resumen.Bytes -ge ($Configuracion.MinimoMB * 1MB)) {
                New-Candidato -ModuloId 'juegos' -Categoria 'Partidas guardadas' `
                              -Nombre $juego.Name -Ruta $juego.FullName -Bytes $resumen.Bytes `
                              -Info "$($resumen.Archivos) archivos en $(Get-RutaElidida $zona 45)" `
                              -Efecto 'Aquí viven tus partidas guardadas y la configuración del juego. El programa no propone borrarlo: solo te dice lo que ocupa.' `
                              -Metodo 'Informativo' -Riesgo 'Bajo'
            }

            # Dentro si: registros y cachés que el motor recrea.
            foreach ($nombre in $basuraDeJuego) {
                foreach ($encontrada in @(Get-ChildItem -LiteralPath $juego.FullName -Directory -Force `
                                                        -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                                          Where-Object { $_.Name -eq $nombre })) {
                    if (Test-EsEnlace $encontrada) { continue }
                    if (-not (Test-RutaSegura $encontrada.FullName @($zona))) { continue }

                    $bytes = Measure-Ruta $encontrada.FullName
                    if ($bytes -lt 1MB) { continue }

                    New-Candidato -ModuloId 'juegos' -Categoria 'Registros y caché de juegos' `
                                  -Nombre "$($juego.Name) - $($encontrada.Name)" `
                                  -Ruta $encontrada.FullName -Bytes $bytes `
                                  -Info 'se vacía el contenido, la carpeta se queda' `
                                  -Efecto 'Registros y datos temporales del motor del juego. Se regeneran solos y no afectan a tus partidas.' `
                                  -Metodo 'Contenido' -Raices @($zona) -Riesgo 'Bajo' -ForzarPermanente
                }
            }
        }
    }
}

New-ModuloLimpieza -Id 'juegos' -Orden 33 `
    -Nombre 'Juegos y plataformas de juego' `
    -Descripcion 'Cachés de Steam, Epic, Battle.net, GOG, EA, Ubisoft y Riot, juegos que Steam ya no reconoce y sombreadores de juegos desinstalados. Nunca toca partidas guardadas.' `
    -Riesgo 'Medio' `
    -Perfiles @('conservador', 'equilibrado', 'agresivo') `
    -Buscar $BuscarJuegos
