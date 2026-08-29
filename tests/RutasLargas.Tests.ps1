<#
    Pruebas de [COR-02]: rutas de mas de 260 caracteres.

    Windows arrastra MAX_PATH desde hace decadas. En este dominio se
    desborda con facilidad -node_modules anidados, cache de Gradle,
    .next\cache\webpack- y el sintoma no era un error: EnumerateFiles
    lanzaba, el catch lo contaba como "inaccesible", el programa media de
    menos y borraba de menos, y luego informaba de "archivos en uso por
    algun programa abierto". Un mensaje falso sobre carpetas que si se
    podian borrar.

    Todo lo que decide si una carpeta se mide entera es transformacion de
    texto, asi que se prueba aqui, en Linux, sin depender de un equipo con
    rutas largas de verdad.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'ConvertTo-RutaLarga' {

    It 'antepone el prefijo a una ruta con letra de unidad' {
        ConvertTo-RutaLarga -Ruta 'C:\Users\x\proyecto' | Should -Be '\\?\C:\Users\x\proyecto'
    }

    It 'una ruta de red va a la forma UNC, no a barras dobles' {
        # "\\?\\\servidor\..." no es valido: la API exige "\\?\UNC\".
        ConvertTo-RutaLarga -Ruta '\\servidor\comun\cosa' | Should -Be '\\?\UNC\servidor\comun\cosa'
    }

    It 'no lo pone dos veces' {
        $ya = '\\?\C:\Windows'
        ConvertTo-RutaLarga -Ruta $ya | Should -Be $ya
    }

    It 'respeta los dispositivos \\.\ ' {
        ConvertTo-RutaLarga -Ruta '\\.\PhysicalDrive0' | Should -Be '\\.\PhysicalDrive0'
    }

    It 'normaliza las barras, porque con el prefijo la API ya no lo hace' {
        ConvertTo-RutaLarga -Ruta 'C:/Users/x' | Should -Be '\\?\C:\Users\x'
    }

    It 'no toca una ruta relativa' {
        # Con el prefijo la API no resuelve nada: una relativa produciria
        # una ruta inexistente en vez de un error, que es peor.
        ConvertTo-RutaLarga -Ruta 'carpeta\sub' | Should -Be 'carpeta\sub'
    }

    It 'no toca una ruta con . o .. como segmento' {
        # Se buscarian literalmente carpetas llamadas "." y "..".
        ConvertTo-RutaLarga -Ruta 'C:\Users\..\Windows' | Should -Be 'C:\Users\..\Windows'
        ConvertTo-RutaLarga -Ruta 'C:\Users\.\x'        | Should -Be 'C:\Users\.\x'
    }

    It 'no toca lo que no es una ruta de Windows' {
        # Algunos candidatos usan Ruta para etiquetas.
        ConvertTo-RutaLarga -Ruta 'docker system prune' | Should -Be 'docker system prune'
        ConvertTo-RutaLarga -Ruta '/tmp/x'              | Should -Be '/tmp/x'
    }

    It 'aguanta el vacio y el nulo' {
        { ConvertTo-RutaLarga -Ruta '' }    | Should -Not -Throw
        { ConvertTo-RutaLarga -Ruta $null } | Should -Not -Throw
    }
}

Describe 'ConvertFrom-RutaLarga: lo que sale vuelve a ser normal' {

    It 'quita el prefijo de una unidad' {
        ConvertFrom-RutaLarga -Ruta '\\?\C:\Users\x' | Should -Be 'C:\Users\x'
    }

    It 'devuelve la forma UNC original' {
        ConvertFrom-RutaLarga -Ruta '\\?\UNC\servidor\comun' | Should -Be '\\servidor\comun'
    }

    It 'no toca lo que no lo lleva' {
        ConvertFrom-RutaLarga -Ruta 'C:\Users\x' | Should -Be 'C:\Users\x'
    }

    It 'ida y vuelta devuelve exactamente lo mismo' {
        # Es la propiedad de la que depende que el prefijo no se escape:
        # si la vuelta no fuera exacta, la guardia compararia contra una
        # ruta distinta de la que el usuario ve.
        foreach ($r in @('C:\Users\x\y', '\\servidor\comun\z', 'C:\Windows')) {
            ConvertFrom-RutaLarga -Ruta (ConvertTo-RutaLarga -Ruta $r) | Should -Be $r
        }
    }
}

Describe 'Test-RutaDemasiadoLarga' {

    It 'una ruta normal no lo es' {
        Test-RutaDemasiadoLarga -Ruta 'C:\Users\x\proyecto' | Should -BeFalse
    }

    It 'a partir de 260 caracteres si' {
        $larga = 'C:\' + ('a' * 300)
        Test-RutaDemasiadoLarga -Ruta $larga | Should -BeTrue
    }

    It 'mide SIN el prefijo: si no, toda ruta pareceria 4 caracteres mas larga' {
        $justa = 'C:\' + ('a' * 250)   # 253 caracteres, cabe
        Test-RutaDemasiadoLarga -Ruta $justa | Should -BeFalse
        Test-RutaDemasiadoLarga -Ruta (ConvertTo-RutaLarga -Ruta $justa) | Should -BeFalse
    }

    It 'el limite esta en 260, contando el terminador' {
        Test-RutaDemasiadoLarga -Ruta ('C:\' + ('a' * 256)) | Should -BeFalse  # 259
        Test-RutaDemasiadoLarga -Ruta ('C:\' + ('a' * 257)) | Should -BeTrue   # 260
    }
}

Describe 'COR-02: el prefijo no puede escaparse de las llamadas al sistema' {

    <#
        La regla que no se puede romper. Si "\\?\" se colara en la Ruta de
        un candidato, la guardia compararia "\\?\C:\Windows" contra su
        lista negra "C:\Windows" y NO COINCIDIRIA: un prefijo puesto para
        medir mejor se convertiria en un agujero para borrar el sistema.
    #>

    BeforeAll {
        # El mismo entorno simulado de Guard.Tests.ps1: las pruebas corren
        # en Linux, donde no hay unidad C: ni variables de Windows, y
        # New-Configuracion no puede descubrir nada.
        $env:SystemRoot    = 'C:\Windows'
        $env:ProgramFiles  = 'C:\Program Files'
        $env:ProgramData   = 'C:\ProgramData'
        $env:USERPROFILE   = 'C:\Users\prueba'
        $env:LOCALAPPDATA  = 'C:\Users\prueba\AppData\Local'

        Initialize-Guardia -Configuracion ([pscustomobject]@{
            Escritorio   = 'C:\Users\prueba\Desktop'
            Documentos   = 'C:\Users\prueba\Documents'
            Descargas    = 'C:\Users\prueba\Downloads'
            Imagenes     = 'C:\Users\prueba\Pictures'
            Musica       = 'C:\Users\prueba\Music'
            Videos       = 'C:\Users\prueba\Videos'
            CarpetaDatos = 'C:\Users\prueba\AppData\Local\Cachivache'
        })
    }

    It 'la guardia da el MISMO veredicto lleve o no el prefijo' {
        # Se exige el mismo motivo, no solo que rechace. La primera version
        # de esta prueba solo comprobaba "rechaza", y pasaba... porque la
        # guardia veia las dos barras iniciales de "\\?\" y respondia "es
        # un recurso de red". Veredicto correcto, motivo falso: en cuanto
        # la ruta fuera legitima, esa misma casualidad la habria bloqueado
        # diciendo que una carpeta del disco esta en la red.
        foreach ($ruta in @('C:\Windows',
                            'C:\Windows\System32',
                            'C:\Users\prueba\AppData\Local\Temp\basura')) {
            $sin = Get-MotivoIntocable -Ruta $ruta
            $con = Get-MotivoIntocable -Ruta (ConvertTo-RutaLarga -Ruta $ruta)
            $con | Should -Be $sin -Because "el prefijo no puede cambiar el juicio sobre $ruta"
        }
    }

    It 'y con el prefijo no confunde el disco local con un recurso de red' {
        # El sintoma concreto que tenia: cualquier ruta prefijada quedaba
        # vetada como si estuviera en un servidor.
        $motivo = Get-MotivoIntocable -Ruta '\\?\C:\Users\prueba\AppData\Local\Temp\basura'
        $motivo | Should -Not -BeLike '*recurso de red*'
    }

    It 'una ruta de red DE VERDAD sigue detectandose, con prefijo y sin el' {
        # Al quitar el prefijo no se puede perder la deteccion legitima:
        # "\\?\UNC\servidor\..." vuelve a ser "\\servidor\...".
        Get-MotivoIntocable -Ruta '\\servidor\comun\x'       | Should -BeLike '*recurso de red*'
        Get-MotivoIntocable -Ruta '\\?\UNC\servidor\comun\x' | Should -BeLike '*recurso de red*'
    }

    It 'New-Candidato no recibe rutas con prefijo desde los modulos' {
        # Se comprueba el CODIGO: ningun modulo puede pasar el resultado de
        # ConvertTo-RutaLarga como -Ruta.
        $culpables = @()
        foreach ($archivo in @(Get-ChildItem (Join-Path $script:Raiz 'src/Modules') -Filter '*.ps1')) {
            $texto = Get-Content -Raw -LiteralPath $archivo.FullName
            if ($texto -match '-Ruta\s+[^\r\n]*ConvertTo-RutaLarga') {
                $culpables += $archivo.Name
            }
            if ($texto -match "New-Candidato[\s\S]{0,400}'\\\\\?\\\\") {
                $culpables += $archivo.Name
            }
        }
        $culpables | Should -BeNullOrEmpty
    }

    It 'el recorrido usa el prefijo, y lo hace en UN solo sitio' {
        # Una regla que hay que recordar en ocho sitios se olvida en el
        # noveno. Get-ResumenArbol lo aplica por todos.
        $fs = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/Core/FileSystem.ps1')
        $fs | Should -Match 'Get-CarpetaParaRecorrer -Carpeta \$Carpeta'

        $usos = @([regex]::Matches($fs, 'Get-CarpetaParaRecorrer')).Count
        $usos | Should -BeLessOrEqual 3 -Because 'definicion, llamada y a lo sumo una mencion'
    }
}

Describe 'COR-02: el borrado distingue las dos APIs' {

    BeforeAll {
        $script:Motor = (Get-Content -LiteralPath (Join-Path $script:Raiz 'src/Core/Remove.ps1') |
                         Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'una ruta larga que va a la papelera se rechaza, no se borra a la brava' {
        # VisualBasic.FileIO no admite el prefijo. Resolverlo borrando
        # permanentemente destruiria justo lo que el usuario pidio poder
        # recuperar: la misma regla que [COR-01].
        $script:Motor | Should -Match '\$esLarga -and -not \$Permanente'
        $script:Motor | Should -Match 'Marca el borrado permanente'
    }

    It 'el borrado permanente de una ruta larga usa System.IO, no el proveedor' {
        $script:Motor | Should -Match '\[IO\.Directory\]::Delete\(\$larga, \$true\)'
        $script:Motor | Should -Match '\[IO\.File\]::Delete\(\$larga\)'
    }

    It 'las rutas normales siguen usando Remove-Item' {
        # No se cambia lo que ya funcionaba: Remove-Item entiende de
        # proveedores y de rutas relativas.
        $script:Motor | Should -Match 'Remove-Item -LiteralPath \$Ruta -Recurse -Force'
    }
}

Describe 'COR-02: medir sigue funcionando igual en lo de siempre' {

    <#
        El prefijo se aplica a TODO recorrido, no solo a los largos. Si
        rompiera el caso normal, el programa dejaria de medir bien en el
        99% de las carpetas para arreglar el 1%.
    #>

    BeforeAll {
        $script:Zona = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-largo-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:Zona 'sub') -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $script:Zona 'a.bin'), (New-Object byte[] 4096))
        [IO.File]::WriteAllBytes((Join-Path (Join-Path $script:Zona 'sub') 'b.bin'), (New-Object byte[] 2048))
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Zona -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'mide el arbol entero, subcarpetas incluidas' {
        Measure-Ruta $script:Zona | Should -Be 6144
    }

    It 'no cuenta nada como inaccesible' {
        # Si el prefijo rompiera la enumeracion, el sintoma seria este
        # contador subiendo y el tamaño bajando, en silencio.
        $r = Get-ResumenArbol -Carpeta ([IO.DirectoryInfo]::new($script:Zona))
        $r.Inaccesibles | Should -Be 0
        $r.Archivos     | Should -Be 2
    }
}
