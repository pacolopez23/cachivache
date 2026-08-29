<#
    Pruebas de regresion del COMPORTAMIENTO de módulos concretos:
    30-RestosProgramas, 35-Descargas, 50-Temporales y 40-CarpetasVacias.

    No confundir con Modules.Tests.ps1, que comprueba el CONTRATO que todo
    módulo debe cumplir (Id único, Orden único, perfiles válidos...). Aquí
    se fija que cada uno de estos cuatro decide lo que debe decidir: cada
    Describe nace de un fallo real que se corrigio, y esta ahi para que no
    vuelva. Al corregir un fallo nuevo en un módulo, su prueba va aquí.
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
}

Describe 'Modulo descargas: escala de riesgo (C-10)' {

    BeforeEach {
        $script:carpetaDescargas = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-desc-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaDescargas -Force | Out-Null

        $script:modulo = Get-ModuloLimpieza -Id 'descargas' -Raiz $script:Raiz
        $script:sync = New-EstadoSincronizado
        $script:configuracion = [pscustomobject]@{
            Descargas  = $script:carpetaDescargas
            DiasSinUso = 30
            MinimoMB   = 0
            Admin      = $true
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaDescargas -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'un instalador antiguo suelto es riesgo Bajo (antes: Medio, rama muerta)' {
        $archivo = Join-Path $script:carpetaDescargas 'instalador.exe'
        Set-Content -LiteralPath $archivo -Value ('x' * 100) -NoNewline
        (Get-Item -LiteralPath $archivo).LastWriteTime = (Get-Date).AddDays(-60)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 1
        $resultado.Candidatos[0].Riesgo | Should -Be 'Bajo'
    }

    It 'un comprimido antiguo sigue siendo riesgo Medio (puede contener cualquier cosa)' {
        $archivo = Join-Path $script:carpetaDescargas 'descarga.zip'
        Set-Content -LiteralPath $archivo -Value ('x' * 100) -NoNewline
        (Get-Item -LiteralPath $archivo).LastWriteTime = (Get-Date).AddDays(-60)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 1
        $resultado.Candidatos[0].Riesgo | Should -Be 'Medio'
    }

    It 'nunca premarca nada, sea cual sea el riesgo' {
        $archivo = Join-Path $script:carpetaDescargas 'instalador.exe'
        Set-Content -LiteralPath $archivo -Value ('x' * 100) -NoNewline
        (Get-Item -LiteralPath $archivo).LastWriteTime = (Get-Date).AddDays(-60)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos[0].Seleccionado | Should -BeFalse
    }
}

Describe 'Modulo temporales: no toca lo que puede estar en uso ahora mismo (C-15)' {

    BeforeEach {
        $script:carpetaZona = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-temp-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaZona -Force | Out-Null

        $script:modulo = Get-ModuloLimpieza -Id 'temporales' -Raiz $script:Raiz
        $script:sync = New-EstadoSincronizado
        $script:configuracion = [pscustomobject]@{
            ZonasUsuario = @($script:carpetaZona)
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaZona -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'NO propone un archivo de bloqueo de Office (~$) reciente' {
        $archivo = Join-Path $script:carpetaZona '~$documento.docx'
        Set-Content -LiteralPath $archivo -Value 'x' -NoNewline

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 0
    }

    It 'SI propone un archivo de bloqueo de Office (~$) con mas de 30 minutos' {
        $archivo = Join-Path $script:carpetaZona '~$documento.docx'
        Set-Content -LiteralPath $archivo -Value 'x' -NoNewline
        (Get-Item -LiteralPath $archivo -Force).LastWriteTime = (Get-Date).AddHours(-2)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 1
    }

    It 'NO propone una descarga a medias (.crdownload) reciente' {
        $archivo = Join-Path $script:carpetaZona 'pelicula.crdownload'
        Set-Content -LiteralPath $archivo -Value 'x' -NoNewline

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 0
    }

    It 'SI propone un .tmp antiguo' {
        $archivo = Join-Path $script:carpetaZona 'restos.tmp'
        Set-Content -LiteralPath $archivo -Value 'x' -NoNewline
        (Get-Item -LiteralPath $archivo -Force).LastWriteTime = (Get-Date).AddHours(-2)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 1
    }

    It 'ya no casa cualquier nombre con ".~" en cualquier posicion, solo la extension' {
        # Antes: '*.~*' casaba p.ej. "informe.~final.docx". Ahora solo
        # cuenta si la EXTENSIÓN empieza por ".~".
        $archivoNormal = Join-Path $script:carpetaZona 'informe.~final.docx'
        Set-Content -LiteralPath $archivoNormal -Value 'x' -NoNewline
        (Get-Item -LiteralPath $archivoNormal -Force).LastWriteTime = (Get-Date).AddDays(-1)

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 0
    }
}

Describe 'Modulo carpetas vacias: comprobacion no recursiva (R-05)' {

    BeforeEach {
        $script:carpetaZona = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-vacias-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaZona -Force | Out-Null

        $script:modulo = Get-ModuloLimpieza -Id 'vacias' -Raiz $script:Raiz
        $script:sync = New-EstadoSincronizado
        $script:configuracion = [pscustomobject]@{ ZonasUsuario = @($script:carpetaZona) }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaZona -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'SIGUE proponiendo una carpeta hoja realmente vacia' {
        $vacia = Join-Path $script:carpetaZona 'vacia'
        New-Item -ItemType Directory -Path $vacia -Force | Out-Null

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 1
        $resultado.Candidatos[0].Ruta | Should -Be $vacia
    }

    It 'NO propone una carpeta que tiene un archivo dentro' {
        $conArchivo = Join-Path $script:carpetaZona 'con-archivo'
        New-Item -ItemType Directory -Path $conArchivo -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $conArchivo 'algo.txt') -Value 'x' -NoNewline

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 0
    }

    It 'una cadena de carpetas vacias se propone UNA vez, por la mas alta (C-09)' {
        # Antes solo se detectaban las hojas, así que vaciar a\b\c exigia
        # ejecutar el programa tres veces. Ahora se propone 'padre' y punto:
        # borrarlo se lleva toda la cadena.
        $padre = Join-Path $script:carpetaZona 'padre'
        $hija  = Join-Path $padre 'hija'
        $nieta = Join-Path $hija 'nieta'
        New-Item -ItemType Directory -Path $nieta -Force | Out-Null

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $rutas = @($resultado.Candidatos | ForEach-Object { $_.Ruta })
        $rutas | Should -Contain $padre
        $rutas | Should -Not -Contain $hija -Because 'borrar el padre ya se la lleva'
        $rutas | Should -Not -Contain $nieta
        $rutas.Count | Should -Be 1
    }

    It 'un archivo en el fondo de la cadena salva a TODA la cadena' {
        # La comprobación es del subarbol entero, no del nivel: si hay un
        # solo archivo en el último nivel, ninguna carpeta de la cadena
        # puede proponerse.
        $padre = Join-Path $script:carpetaZona 'padre'
        $hija  = Join-Path $padre 'hija'
        New-Item -ItemType Directory -Path $hija -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $hija 'importante.txt') -Value 'x' -NoNewline

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $resultado.Candidatos.Count | Should -Be 0
    }

    It 'una rama con archivos no impide proponer la rama vecina que si esta vacia' {
        $conArchivo = Join-Path $script:carpetaZona 'ocupada'
        New-Item -ItemType Directory -Path $conArchivo -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $conArchivo 'algo.txt') -Value 'x' -NoNewline
        $vacia = Join-Path $script:carpetaZona 'libre'
        New-Item -ItemType Directory -Path (Join-Path $vacia 'dentro') -Force | Out-Null

        $resultado = Invoke-ModuloLimpieza -Modulo $script:modulo -Configuracion $script:configuracion -Sync $script:sync

        $rutas = @($resultado.Candidatos | ForEach-Object { $_.Ruta })
        $rutas | Should -Contain $vacia
        $rutas | Should -Not -Contain $conArchivo
    }
}

Describe 'Modulo restos de programas: no inventa entradas por valores binarios (C-16, en 90-Arranque comparte helper)' {

    It 'Get-EjecutableDeComando nunca revienta con valores no-string' {
        # Regresion mínima: el guard "$_.Value -isnot [string]" de
        # 90-Arranque.ps1 evita llamar aquí con un byte[]; esta prueba deja
        # constancia de que la función en si sigue siendo solo de texto.
        { Get-EjecutableDeComando ([string]([byte[]]@(1,0,0))) } | Should -Not -Throw
    }
}

Describe 'Get-TemaDeWindows' {

    <#
        Solo se consulta en el primer arranque. Lo que importa aquí es que
        NUNCA reviente: se ejecuta antes de que exista ninguna ventana, y
        una excepción suya dejaria el programa sin abrir. En un sistema sin
        registro -las pruebas corren en Linux- tiene que responder igual.
    #>

    It 'devuelve siempre claro u oscuro, nunca nada mas' {
        Get-TemaDeWindows | Should -BeIn @('claro', 'oscuro')
    }

    It 'no lanza aunque no exista el registro' {
        { Get-TemaDeWindows } | Should -Not -Throw
    }

    It 'responde oscuro cuando no se puede leer la clave' {
        Mock Get-ItemProperty { throw 'no existe' }
        Get-TemaDeWindows | Should -Be 'oscuro' -Because 'es lo que el programa venia haciendo siempre'
    }

    It 'traduce el valor del registro: <Valor> -> <Esperado>' -ForEach @(
        @{ Valor = 1; Esperado = 'claro'  }
        @{ Valor = 0; Esperado = 'oscuro' }
    ) {
        Mock Get-ItemProperty { [pscustomobject]@{ AppsUseLightTheme = $Valor } }
        Get-TemaDeWindows | Should -Be $Esperado
    }

    It 'el primer arranque hereda el tema del sistema' {
        # Sin archivo de preferencias, el tema NO es una constante: sale de
        # Windows. Con archivo, manda lo guardado.
        $carpeta = Join-Path ([IO.Path]::GetTempPath()) ('pref_' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        Mock Get-ItemProperty { [pscustomobject]@{ AppsUseLightTheme = 1 } }
        Mock Get-RutaPreferencias { Join-Path $carpeta 'preferencias.json' }
        try {
            (Import-Preferencias).Tema | Should -Be 'claro'
        } finally {
            Remove-Item -LiteralPath $carpeta -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Las preferencias del archivo se validan antes de usarse' {

    <#
        preferencias.json es texto plano en una carpeta escribible, y sus
        valores van directos a controles tipados de la ventana: un
        "MinimoMB": "diez" hacia [int] sobre esa cadena y el programa no
        llegaba a abrirse. Es el mismo tipo de fallo que tumbo el arranque
        desde historial.json, en otro archivo.

        Lo que no encaja vuelve a su valor por defecto. Perder una
        preferencia es una molestia; no abrir, un programa roto.
    #>

    BeforeEach {
        $script:CarpetaPref = Join-Path ([IO.Path]::GetTempPath()) ('pref_' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:CarpetaPref -Force | Out-Null
        Mock Get-RutaPreferencias { Join-Path $script:CarpetaPref 'preferencias.json' }
        Mock Get-TemaDeWindows { 'oscuro' }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:CarpetaPref -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'un tema inventado vuelve al valor por defecto' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "Tema": "fucsia" }'
        (Import-Preferencias).Tema | Should -Be 'oscuro'
    }

    It 'un perfil inventado vuelve al valor por defecto' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "Perfil": "destructor" }'
        (Import-Preferencias).Perfil | Should -Be 'equilibrado'
    }

    It 'un umbral que no es numero vuelve al valor por defecto' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "DiasSinUso": "ciento ochenta", "MinimoMB": [1,2] }'
        $p = Import-Preferencias
        $p.DiasSinUso | Should -Be 180
        $p.MinimoMB   | Should -Be 10
    }

    It 'un umbral fuera del rango del deslizador vuelve al valor por defecto' {
        # Si se aceptara, WPF lo recortaria al pintar y la preferencia
        # guardada dejaria de coincidir con lo que ve el usuario.
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "MinimoMB": 99999, "DiasSinUso": 2 }'
        $p = Import-Preferencias
        $p.MinimoMB   | Should -Be 10
        $p.DiasSinUso | Should -Be 180
    }

    It 'un umbral valido si se respeta' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "MinimoMB": 250, "DiasSinUso": 365 }'
        $p = Import-Preferencias
        $p.MinimoMB   | Should -Be 250
        $p.DiasSinUso | Should -Be 365
    }

    It 'una casilla que no es booleana vuelve al valor por defecto' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "IncluirMenores": "quiza", "Permanente": 1 }'
        $p = Import-Preferencias
        $p.IncluirMenores | Should -BeFalse
        # Un 1 no es $true: aceptar números donde se espera un booleano es
        # justo como se activa solo un borrado permanente.
        $p.Permanente     | Should -BeFalse
    }

    It 'una casilla booleana de verdad si se respeta' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "Permanente": true }'
        (Import-Preferencias).Permanente | Should -BeTrue
    }

    It 'las listas se limpian elemento a elemento' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "ModulosActivos": ["caches", 42, null, "", "vacias"] }'
        $lista = @((Import-Preferencias).ModulosActivos)
        $lista.Count | Should -Be 2
        $lista       | Should -Contain 'caches'
        $lista       | Should -Contain 'vacias'
    }

    It 'un valor suelto donde se espera una lista se envuelve' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "UnidadesExcluidas": "D:" }'
        $lista = @((Import-Preferencias).UnidadesExcluidas)
        $lista.Count | Should -Be 1
        $lista[0]    | Should -Be 'D:'
    }

    It 'un archivo entero ilegible no impide arrancar' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ esto no es json'
        $p = $null
        { $p = Import-Preferencias } | Should -Not -Throw
        (Import-Preferencias).Perfil | Should -Be 'equilibrado'
    }

    It 'lo bueno sobrevive aunque lo demas sea basura' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaPref 'preferencias.json') -Value '{ "Tema": "claro", "Perfil": "destructor", "MinimoMB": "x" }'
        $p = Import-Preferencias
        $p.Tema     | Should -Be 'claro'
        $p.Perfil   | Should -Be 'equilibrado'
        $p.MinimoMB | Should -Be 10
    }
}

Describe 'FAL-02: las carpetas vacias fuera de AppData no se premarcan' {

    <#
        Una carpeta vacia dentro de AppData es basura: ahi no organiza
        nadie a mano. Una carpeta vacia en el Escritorio o en Documentos
        puede ser justo lo contrario: algo que el usuario acaba de crear
        para ordenar, y que esta vacia porque todavia no ha metido nada.
        Venia premarcada, asi que desaparecia sola.
    #>

    BeforeAll {
        $script:padreVacias = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-vacias-' + [guid]::NewGuid())
        $script:zonaUsuario = Join-Path $script:padreVacias 'Escritorio'
        New-Item -ItemType Directory -Path (Join-Path $script:zonaUsuario 'Proyecto Nuevo') -Force | Out-Null

        $modulo = Get-ModuloLimpieza -Id 'vacias' -Raiz (Split-Path $PSScriptRoot -Parent)
        $resultado = Invoke-ModuloLimpieza -Modulo $modulo -Sync (New-EstadoSincronizado) `
                     -Configuracion ([pscustomobject]@{
                         ZonasUsuario = @($script:zonaUsuario)
                         DiasSinUso = 30; MinimoMB = 0; Admin = $true
                     })
        $script:CandidatosVacias = @($resultado.Candidatos)
    }

    AfterAll {
        Remove-Item -LiteralPath $script:padreVacias -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'propone la carpeta, porque esta vacia de verdad' {
        @($script:CandidatosVacias | Where-Object { $_.Ruta -like '*Proyecto Nuevo' }).Count |
            Should -Be 1
    }

    It 'pero NO la premarca: se creo hace un momento y esta fuera de AppData' {
        $c = $script:CandidatosVacias | Where-Object { $_.Ruta -like '*Proyecto Nuevo' }
        $c.Seleccionado | Should -BeFalse -Because 'puede ser una carpeta que el usuario acaba de crear para ordenar'
        $c.Aviso        | Should -Not -BeNullOrEmpty
    }
}

Describe 'FAL-08: vendor y target dejan de ser prueba suficiente' {

    <#
        En Go, vendor/ SE VERSIONA a proposito: es lo que permite compilar
        sin red. Borrarlo no es limpiar, es romper el proyecto. Y "target"
        es un nombre de carpeta corriente fuera de Rust y de Maven.
    #>

    BeforeAll {
        $script:padreProy = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-proy-' + [guid]::NewGuid())

        # Un "vendor" suelto, sin manifiesto de ningun ecosistema al lado.
        $sueltos = Join-Path $script:padreProy 'CarpetaCualquiera'
        New-Item -ItemType Directory -Path (Join-Path $sueltos 'vendor') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path (Join-Path $sueltos 'vendor') 'a.bin') -Value ('x' * 4096) -NoNewline

        $modulo = Get-ModuloLimpieza -Id 'proyectos' -Raiz (Split-Path $PSScriptRoot -Parent)
        $resultado = Invoke-ModuloLimpieza -Modulo $modulo -Sync (New-EstadoSincronizado) `
                     -Configuracion ([pscustomobject]@{
                         RaicesProyecto = @($script:padreProy)
                         DiasSinUso = 0; MinimoMB = 0; Admin = $true
                     })
        $script:RutasProy = @($resultado.Candidatos | ForEach-Object { $_.Ruta })
    }

    AfterAll {
        Remove-Item -LiteralPath $script:padreProy -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'no propone un "vendor" sin manifiesto de su ecosistema al lado' {
        @($script:RutasProy | Where-Object { $_ -like '*vendor' }).Count |
            Should -Be 0 -Because 'en Go vendor/ se versiona y es necesario para compilar sin red'
    }
}

Describe 'FAL-13: un informe de archivos grandes no pinta la lista de rojo' {

    It 'los archivos grandes son riesgo Medio, no Alto' {
        # El modulo no borra nada -SoloInforma-, asi que marcar en rojo un
        # video tuyo de 8 GB no informa de nada y contamina el resumen.
        $texto = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Modules') '60-ArchivosGrandes.ps1')
        $texto | Should -Match "Metodo 'Informativo' -Raices \`$zonas -Riesgo 'Medio'"
    }
}

Describe 'REN-31: el recorrido de carpetas vacias poda en vez de filtrar' {

    <#
        node_modules, .git, .svn y .hg no son candidatas Y ademas cuentan
        como contenido para su carpeta padre. Antes se enumeraban ENTERAS
        para descartarlas despues con una regex sobre la ruta; ahora no se
        entra en ellas. Lo que no puede cambiar es el veredicto: una
        carpeta que solo contiene un .git NO esta vacia.
    #>

    BeforeAll {
        $script:padreNv = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-poda-' + [guid]::NewGuid())
        $zona = Join-Path $script:padreNv 'Zona'

        # Vacia de verdad.
        New-Item -ItemType Directory -Path (Join-Path $zona 'VaciaDeVerdad') -Force | Out-Null

        # Solo contiene un .git: NO esta vacia.
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $zona 'ConGit') '.git') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path (Join-Path (Join-Path $zona 'ConGit') '.git') 'HEAD') `
                    -Value 'ref: refs/heads/main' -NoNewline

        # Cadena de vacias anidadas: se propone solo la mas alta.
        New-Item -ItemType Directory -Path (Join-Path (Join-Path (Join-Path $zona 'Cadena') 'b') 'c') -Force | Out-Null

        $modulo = Get-ModuloLimpieza -Id 'vacias' -Raiz (Split-Path $PSScriptRoot -Parent)
        $r = Invoke-ModuloLimpieza -Modulo $modulo -Sync (New-EstadoSincronizado) `
             -Configuracion ([pscustomobject]@{
                 ZonasUsuario = @($zona); DiasSinUso = 0; MinimoMB = 0; Admin = $true
             })
        $script:RutasNv = @($r.Candidatos | ForEach-Object { $_.Ruta })
    }

    AfterAll {
        Remove-Item -LiteralPath $script:padreNv -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'propone la carpeta que esta vacia de verdad' {
        @($script:RutasNv | Where-Object { $_ -like '*VaciaDeVerdad' }).Count | Should -Be 1
    }

    It 'NO propone la que solo contiene un .git' {
        @($script:RutasNv | Where-Object { $_ -like '*ConGit' }).Count |
            Should -Be 0 -Because 'una carpeta con un repositorio dentro no esta vacia'
    }

    It 'no propone el propio .git' {
        @($script:RutasNv | Where-Object { $_ -like '*.git*' }).Count | Should -Be 0
    }

    It 'de una cadena anidada propone solo la carpeta mas alta' {
        @($script:RutasNv | Where-Object { $_ -like '*Cadena*' }).Count | Should -Be 1
        @($script:RutasNv | Where-Object { $_ -like '*Cadena' }).Count  | Should -Be 1
    }
}
