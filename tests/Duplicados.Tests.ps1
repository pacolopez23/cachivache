<#
    Pruebas del módulo de duplicados, centradas en [C-02] de
    docs/OPTIMIZACIONES.md: con zonas de usuario solapadas (el caso real es
    OneDrive con Known Folder Move activado, que hace que "OneDrive" y
    "OneDrive\Escritorio" convivan como zonas), un mismo archivo se podia
    indexar dos veces y el módulo acababa proponiendo borrar el único
    ejemplar de un archivo creyendo que existia una copia.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio   = ''
        Documentos   = ''
        Descargas    = ''
        Imagenes     = ''
        Musica       = ''
        Videos       = ''
        CarpetaDatos = ''
    })

    $script:ModuloDuplicados = Get-ModuloLimpieza -Id 'duplicados' -Raiz $script:Raiz
    $script:ModuloDuplicados | Should -Not -BeNullOrEmpty
}

Describe 'Modulo duplicados: zonas solapadas (C-02)' {

    BeforeEach {
        # Fuera de la carpeta temporal: en Windows cuelga de AppData y el
        # modulo de duplicados descarta \AppData\ a proposito, asi que los
        # cebos eran invisibles. La explicacion larga esta en el Describe
        # de los enlaces duros, mas abajo.
        $script:carpetaPrueba = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'pruebas') `
                                          ('tmp-dup-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaPrueba -Force | Out-Null

        $script:sync = New-EstadoSincronizado
        $script:configuracionBase = [pscustomobject]@{
            MinimoDuplicadoMB = 0
            ZonasUsuario      = @()
            Admin             = $true
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaPrueba -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'NO propone borrar un archivo consigo mismo cuando dos zonas se anidan' {
        # Simula OneDrive con Known Folder Move: "OneDrive" y
        # "OneDrive\Escritorio" son ambas zonas de usuario, y la segunda
        # cuelga de la primera.
        $oneDrive           = Join-Path $script:carpetaPrueba 'OneDrive'
        $oneDriveEscritorio = Join-Path $oneDrive 'Escritorio'
        New-Item -ItemType Directory -Path $oneDriveEscritorio -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $oneDriveEscritorio 'foto.jpg') -Value ('x' * 500) -NoNewline

        $configuracion = $script:configuracionBase
        $configuracion.ZonasUsuario = @($oneDrive, $oneDriveEscritorio)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:ModuloDuplicados -Configuracion $configuracion -Sync $script:sync

        $resultado.Error | Should -BeNullOrEmpty
        $resultado.Candidatos.Count | Should -Be 0 -Because 'el archivo se ha visto dos veces por culpa del anidamiento, pero es el mismo archivo'
    }

    It 'SIGUE detectando duplicados reales entre dos zonas independientes (no anidadas)' {
        $zonaA = Join-Path $script:carpetaPrueba 'ZonaA'
        $zonaB = Join-Path $script:carpetaPrueba 'ZonaB'
        New-Item -ItemType Directory -Path $zonaA -Force | Out-Null
        New-Item -ItemType Directory -Path $zonaB -Force | Out-Null

        # Mismo contenido, mismo tamaño, dos archivos DISTINTOS de verdad.
        Set-Content -LiteralPath (Join-Path $zonaA 'original.jpg') -Value ('y' * 500) -NoNewline
        Start-Sleep -Milliseconds 50
        Set-Content -LiteralPath (Join-Path $zonaB 'copia.jpg') -Value ('y' * 500) -NoNewline

        $configuracion = $script:configuracionBase
        $configuracion.ZonasUsuario = @($zonaA, $zonaB)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:ModuloDuplicados -Configuracion $configuracion -Sync $script:sync

        $resultado.Error | Should -BeNullOrEmpty
        $resultado.Candidatos.Count | Should -Be 1 -Because 'son dos archivos distintos con el mismo contenido: uno es un duplicado real'
        $resultado.Candidatos[0].Ruta | Should -Be (Join-Path $zonaB 'copia.jpg') -Because 'se conserva el mas antiguo (original.jpg) y se propone el mas nuevo'
    }
}

Describe 'Select-RutasNoAnidadas (C-02 / C-07)' {

    It 'descarta una ruta que cuelga de otra de la lista' {
        $resultado = Select-RutasNoAnidadas @('C:\Users\x\OneDrive', 'C:\Users\x\OneDrive\Escritorio')
        @($resultado) | Should -Be @('C:\Users\x\OneDrive')
    }

    It 'conserva rutas independientes' {
        $resultado = @(Select-RutasNoAnidadas @('C:\Users\x\Documentos', 'C:\Users\x\Descargas'))
        $resultado.Count | Should -Be 2
    }

    It 'no confunde un prefijo textual con un ancestro real' {
        # "OneDrive2" NO cuelga de "OneDrive": no comparte separador de ruta.
        $resultado = @(Select-RutasNoAnidadas @('C:\Users\x\OneDrive', 'C:\Users\x\OneDrive2'))
        $resultado.Count | Should -Be 2
    }

    It 'envuelta en @() por quien la llama, una sola ruta superviviente sigue siendo un array de un elemento' {
        # Recuerda al propio bug que corrige [C-07]: sin el @() en la
        # llamada, PowerShell "desenvuelve" un array de un elemento al
        # elemento suelto. Select-RutasNoAnidadas no puede arreglar eso por
        # su cuenta: es responsabilidad de quien la llama, tal como hace
        # Config.ps1 al asignar ZonasUsuario y RaicesProyecto.
        $resultado = @(Select-RutasNoAnidadas @('C:\Users\x\Unica'))
        $resultado.Count | Should -Be 1
        $resultado[0] | Should -Be 'C:\Users\x\Unica'
    }
}

Describe 'VIS-03: dos enlaces duros no son dos copias' {

    <#
        Tienen el mismo tamano y el mismo hash -son el mismo contenido-,
        asi que llegaban al modulo como si fueran dos copias. Proponer
        borrar uno es doblemente falso: no libera ni un byte, porque el
        contenido sigue vivo mientras quede otro enlace, y ademas el
        programa lo apuntaba como espacio recuperado.
    #>

    BeforeAll {
        # LOS CEBOS NO PUEDEN VIVIR EN LA CARPETA TEMPORAL DE WINDOWS.
        #
        # En Windows, [IO.Path]::GetTempPath() devuelve
        # C:\Users\<quien>\AppData\Local\Temp, o sea DENTRO de AppData. Y el
        # modulo de duplicados descarta a proposito todo lo que cuelgue de
        # \AppData\, porque son datos de aplicacion y no trabajo del
        # usuario. Resultado: el modulo no veia ni uno de los cebos,
        # devolvia cero candidatos, y las pruebas comprobaban el vacio.
        #
        # En Linux la ruta es /tmp y no hay AppData, asi que pasaban aqui y
        # solo fallaban en la integracion continua. Es exactamente el mismo
        # fallo que [VAL-03] encontro en el banco -cebos invisibles para el
        # programa-, con otro disfraz: alli era la guardia por el nombre,
        # aqui es el filtro por la ruta.
        #
        # La carpeta va bajo pruebas\, que esta en .gitignore y no cuelga de
        # AppData en ningun sistema.
        $script:raizPruebas = Join-Path (Split-Path $PSScriptRoot -Parent) 'pruebas'
        $script:zonaDup = Join-Path $script:raizPruebas ('tmp-dup-hl-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:zonaDup -Force | Out-Null

        # Dos enlaces al MISMO contenido.
        $uno = Join-Path $script:zonaDup 'documento.bin'
        [IO.File]::WriteAllBytes($uno, (New-Object byte[] 200000))
        $script:enlaceDup = Join-Path $script:zonaDup 'mismo-documento.bin'

        # Y dos copias DE VERDAD, con contenido identico pero archivos
        # distintos: estas si tienen que proponerse.
        $copiaA = Join-Path $script:zonaDup 'copia-a.bin'
        $copiaB = Join-Path $script:zonaDup 'copia-b.bin'
        $contenido = New-Object byte[] 300000
        for ($i = 0; $i -lt 500; $i++) { $contenido[$i] = 42 }
        [IO.File]::WriteAllBytes($copiaA, $contenido)
        [IO.File]::WriteAllBytes($copiaB, $contenido)

        $script:HayEnlaces = $false
        try {
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                & cmd /c mklink /H "`"$script:enlaceDup`"" "`"$uno`"" 2>&1 | Out-Null
            } else {
                & ln $uno $script:enlaceDup 2>&1 | Out-Null
            }
            $script:HayEnlaces = (Test-Path -LiteralPath $script:enlaceDup) -and
                                 ($null -ne (Get-IdentidadArchivo -Ruta $uno))
        } catch { $script:HayEnlaces = $false }

        Initialize-Guardia -Configuracion ([pscustomobject]@{
            Escritorio = ''; Documentos = ''; Descargas = ''
            Imagenes   = ''; Musica     = ''; Videos     = ''; CarpetaDatos = ''
        })

        $modulo = Get-ModuloLimpieza -Id 'duplicados' -Raiz (Split-Path $PSScriptRoot -Parent)
        $r = Invoke-ModuloLimpieza -Modulo $modulo -Sync (New-EstadoSincronizado) `
             -Configuracion ([pscustomobject]@{
                 ZonasUsuario = @($script:zonaDup)
                 MinimoDuplicadoMB = 0; MinimoMB = 0; DiasSinUso = 0; Admin = $true
                 Documentos = ''; Imagenes = ''; Musica = ''; Videos = ''; Descargas = ''
             })
        $script:RutasDup = @($r.Candidatos | ForEach-Object { $_.Ruta })
    }

    AfterAll {
        Remove-Item -LiteralPath $script:zonaDup -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'NO propone borrar un enlace duro' {
        if (-not $script:HayEnlaces) { Set-ItResult -Skipped -Because 'el sistema no admite enlaces duros'; return }
        $script:RutasDup | Should -Not -Contain $script:enlaceDup -Because (
            'borrar un enlace duro no libera un solo byte, y el programa lo apuntaria como espacio recuperado')
    }

    It 'pero SI sigue proponiendo las copias de verdad' {
        # Sin esta, un modulo que no propusiera nada pasaria la prueba
        # anterior con nota.
        @($script:RutasDup | Where-Object { $_ -like '*copia-*' }).Count |
            Should -Be 1 -Because 'dos archivos identicos e independientes si son un duplicado'
    }
}
