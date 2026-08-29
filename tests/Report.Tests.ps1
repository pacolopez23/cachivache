<#
    Pruebas de los informes. Este archivo no tenia ninguna: el generador de
    informes se probaba solo abriendo el HTML a ojo.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    function Get-CandidatosDePrueba {
        return @(
            New-Candidato -ModuloId 'caches' -Categoria 'Cachees' -Nombre 'Cache de prueba' `
                          -Ruta 'C:\ruta\cache' -Bytes 1048576 -Efecto 'Se regenera.' -Riesgo 'Bajo'
            New-Candidato -ModuloId 'vacias' -Categoria 'Carpetas vacias' -Nombre 'Carpeta <b>con html</b>' `
                          -Ruta 'C:\ruta\vacia' -Bytes 2097152 -Efecto 'Ordena.' -Riesgo 'Medio' -Aviso 'Revisala'
        )
    }

    $script:Configuracion = [pscustomobject]@{ Equipo = 'EQUIPO'; Windows = 'Windows 11'; Perfil = 'equilibrado' }
}

Describe 'Measure-TotalBytes' {

    It 'suma los bytes de varios candidatos' {
        Measure-TotalBytes (Get-CandidatosDePrueba) | Should -Be 3145728
    }

    It 'suma la propiedad que se le pida' {
        $c = Get-CandidatosDePrueba
        $c[0].BytesLiberados = 500
        $c[1].BytesLiberados = 700
        Measure-TotalBytes $c 'BytesLiberados' | Should -Be 1200
    }

    It 'devuelve cero con una lista vacia y no revienta' {
        Measure-TotalBytes @() | Should -Be 0
        Measure-TotalBytes $null | Should -Be 0
    }

    It 'acepta un candidato suelto, no solo una lista' {
        $uno = (Get-CandidatosDePrueba)[0]
        Measure-TotalBytes $uno | Should -Be 1048576
    }
}

Describe 'ConvertTo-HtmlSeguro' {

    It 'escapa los caracteres que romperian el HTML' {
        $escapado = ConvertTo-HtmlSeguro '<script>alert("x")</script>'
        $escapado | Should -Not -Match '<script>'
        $escapado | Should -Match '&lt;'
    }

    It 'no se atraganta con una cadena vacia' {
        { ConvertTo-HtmlSeguro '' } | Should -Not -Throw
    }
}

Describe 'El CSV no puede convertirse en un vector de ejecución' {

    <#
        Excel evalúa como fórmula cualquier celda que empiece por =, +, -,
        @ o un tabulador, y las comillas del CSV no lo impiden. Como el
        nombre de un archivo lo elige quien lo creó, un informe abierto en
        Excel era una forma de ejecutar algo en el equipo de quien lo abre.
    #>

    It 'neutraliza "<Entrada>"' -ForEach @(
        @{ Entrada = "=cmd|'/c calc'!A1"; Esperado = "'=cmd|'/c calc'!A1" }
        @{ Entrada = '+1+1';              Esperado = "'+1+1" }
        @{ Entrada = '-2+3';              Esperado = "'-2+3" }
        @{ Entrada = '@SUM(A1)';          Esperado = "'@SUM(A1)" }
    ) {
        ConvertTo-CsvSeguro $Entrada | Should -Be $Esperado
    }

    It 'no toca el texto normal, que es el 99,9 % de los casos' -ForEach @(
        @{ Texto = 'C:\Users\prueba\Downloads\instalador.exe' }
        @{ Texto = 'Caché de Firefox' }
        @{ Texto = '' }
    ) {
        ConvertTo-CsvSeguro $Texto | Should -Be $Texto
    }

    It 'un nombre de archivo con fórmula sale neutralizado del informe entero' {
        $malicioso = "=HYPERLINK(`"http://x`",`"pincha`")"
        $candidato = New-Candidato -ModuloId 'temporales' -Categoria 'Temporales' `
                                   -Nombre $malicioso -Ruta 'C:\x\y\z\temporal.tmp' `
                                   -Bytes 1024 -Metodo 'Ruta' -Riesgo 'Bajo'
        $destino = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString() + '.csv')
        try {
            Export-InformeCsv -Candidatos @($candidato) -Ruta $destino -Confirm:$false
            $texto = Get-Content -Raw -LiteralPath $destino
            $texto | Should -Match ([regex]::Escape("'=HYPERLINK"))
        } finally {
            Remove-Item -LiteralPath $destino -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Export-InformeHtml' {

    BeforeEach {
        $script:destino = Join-Path ([IO.Path]::GetTempPath()) ((New-Guid).ToString() + '.html')
    }

    AfterEach {
        Remove-Item -LiteralPath $script:destino -Force -ErrorAction SilentlyContinue
    }

    It 'genera un archivo autocontenido, con su CSS dentro' {
        Export-InformeHtml -Candidatos (Get-CandidatosDePrueba) -Configuracion $script:Configuracion `
                           -Ruta $script:destino -Tipo 'analisis' -Confirm:$false

        Test-Path -LiteralPath $script:destino | Should -BeTrue
        $html = Get-Content -LiteralPath $script:destino -Raw
        $html | Should -Match '<style>'
        $html | Should -Match '</style>'
        $html | Should -Match '</html>'
        # Sin dependencias externas: se tiene que poder abrir sin conexion.
        $html | Should -Not -Match '<link[^>]+href="http'
        $html | Should -Not -Match '<script[^>]+src="http'
    }

    It 'escapa el contenido que viene del disco del usuario' {
        # Un nombre de archivo con HTML dentro no debe poder inyectar nada
        # en el informe.
        Export-InformeHtml -Candidatos (Get-CandidatosDePrueba) -Configuracion $script:Configuracion `
                           -Ruta $script:destino -Tipo 'analisis' -Confirm:$false

        $html = Get-Content -LiteralPath $script:destino -Raw
        $html | Should -Match '&lt;b&gt;con html&lt;/b&gt;'
        $html | Should -Not -Match 'Carpeta <b>con html</b>'
    }

    It 'informa del total sumado de todos los candidatos' {
        Export-InformeHtml -Candidatos (Get-CandidatosDePrueba) -Configuracion $script:Configuracion `
                           -Ruta $script:destino -Tipo 'analisis' -Confirm:$false

        $html = Get-Content -LiteralPath $script:destino -Raw
        $html | Should -Match ([regex]::Escape((Format-Tamano 3145728)))
    }

    It 'no escribe nada con -WhatIf' {
        Export-InformeHtml -Candidatos (Get-CandidatosDePrueba) -Configuracion $script:Configuracion `
                           -Ruta $script:destino -Tipo 'analisis' -WhatIf
        Test-Path -LiteralPath $script:destino | Should -BeFalse
    }
}

Describe 'Export-InformeCsv y Export-InformeJson' {

    BeforeEach {
        $script:destino = Join-Path ([IO.Path]::GetTempPath()) ((New-Guid).ToString())
    }

    AfterEach {
        Remove-Item -LiteralPath $script:destino -Force -ErrorAction SilentlyContinue
    }

    It 'el CSV sale con una fila por candidato' {
        Export-InformeCsv -Candidatos (Get-CandidatosDePrueba) -Ruta $script:destino -Confirm:$false
        $filas = @(Import-Csv -LiteralPath $script:destino)
        $filas.Count | Should -Be 2
    }

    It 'el JSON es JSON valido y sus totales cuadran con los candidatos' {
        Export-InformeJson -Candidatos (Get-CandidatosDePrueba) -Configuracion $script:Configuracion `
                           -Ruta $script:destino -Confirm:$false
        $datos = Get-Content -LiteralPath $script:destino -Raw | ConvertFrom-Json

        $datos            | Should -Not -BeNullOrEmpty
        $datos.Elementos  | Should -Be 2       # recuento, no la lista
        $datos.Total      | Should -Be 3145728
        @($datos.Candidatos).Count | Should -Be 2
        $datos.Candidatos[0].Nombre | Should -Be 'Cache de prueba'
    }

    It 'ninguno de los dos escribe con -WhatIf' {
        Export-InformeCsv -Candidatos (Get-CandidatosDePrueba) -Ruta $script:destino -WhatIf
        Test-Path -LiteralPath $script:destino | Should -BeFalse
    }
}

Describe 'Get-InformesGuardados: la lista de informes ya generados' {

    BeforeAll {
        $script:Datos = Join-Path ([IO.Path]::GetTempPath()) ('inf_' + [guid]::NewGuid())
        $script:Carpeta = Join-Path $script:Datos 'informes'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Carpeta) {
            Get-ChildItem -LiteralPath $script:Carpeta -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Datos -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'devuelve una lista vacia si la carpeta no existe todavia, sin fallar' {
        # Es el caso del primer arranque. El panel tiene que poder abrirse
        # y decir que no hay nada, en vez de reventar o quedarse en blanco.
        $sinNada = Join-Path ([IO.Path]::GetTempPath()) ('nada_' + [guid]::NewGuid())
        @(Get-InformesGuardados -CarpetaDatos $sinNada).Count | Should -Be 0
        @(Get-InformesGuardados -CarpetaDatos $sinNada -Formato html).Count | Should -Be 0
    }

    It 'devuelve una lista vacia si la carpeta existe pero esta vacia' {
        New-Item -ItemType Directory -Path $script:Carpeta -Force | Out-Null
        @(Get-InformesGuardados -CarpetaDatos $script:Datos).Count | Should -Be 0
    }

    It 'separa por formato y no cuenta archivos que no son informes' {
        New-Item -ItemType Directory -Path $script:Carpeta -Force | Out-Null
        Set-Content (Join-Path $script:Carpeta 'analisis_2026-08-19_143005.html') 'x'
        Set-Content (Join-Path $script:Carpeta 'limpieza_2026-08-18_090000.html') 'x'
        Set-Content (Join-Path $script:Carpeta 'analisis_2026-08-17_100000.csv')  'x'
        Set-Content (Join-Path $script:Carpeta 'analisis_2026-08-16_100000.json') 'x'
        Set-Content (Join-Path $script:Carpeta 'apuntes.txt')                     'x'
        Set-Content (Join-Path $script:Carpeta 'registro.log')                    'x'

        @(Get-InformesGuardados -CarpetaDatos $script:Datos).Count               | Should -Be 4
        @(Get-InformesGuardados -CarpetaDatos $script:Datos -Formato html).Count | Should -Be 2
        @(Get-InformesGuardados -CarpetaDatos $script:Datos -Formato csv).Count  | Should -Be 1
        @(Get-InformesGuardados -CarpetaDatos $script:Datos -Formato json).Count | Should -Be 1
    }

    It 'ordena del mas reciente al mas antiguo' {
        New-Item -ItemType Directory -Path $script:Carpeta -Force | Out-Null
        Set-Content (Join-Path $script:Carpeta 'analisis_2026-01-01_000000.html') 'x'
        Set-Content (Join-Path $script:Carpeta 'analisis_2026-08-19_143005.html') 'x'
        Set-Content (Join-Path $script:Carpeta 'analisis_2026-05-05_120000.html') 'x'

        $orden = @(Get-InformesGuardados -CarpetaDatos $script:Datos -Formato html | ForEach-Object { $_.Nombre })
        $orden[0] | Should -Be 'analisis_2026-08-19_143005.html'
        $orden[2] | Should -Be 'analisis_2026-01-01_000000.html'
    }

    It 'saca el tipo y la fecha exacta del nombre que escribe New-NombreInforme' {
        New-Item -ItemType Directory -Path $script:Carpeta -Force | Out-Null
        Set-Content (Join-Path $script:Carpeta 'limpieza_2026-08-19_143005.html') 'x'

        $informe = @(Get-InformesGuardados -CarpetaDatos $script:Datos)[0]
        $informe.Tipo               | Should -Be 'limpieza'
        $informe.Fecha.Year         | Should -Be 2026
        $informe.Fecha.Month        | Should -Be 8
        $informe.Fecha.Day          | Should -Be 19
        $informe.Fecha.Hour         | Should -Be 14
        $informe.Fecha.Minute       | Should -Be 30
        $informe.Fecha.Second       | Should -Be 5
    }

    It 'un informe renombrado a mano sigue apareciendo, con la fecha del archivo' {
        # Renombrar un archivo no debe hacerlo desaparecer de la lista ni
        # dejarlo sin fecha: la carpeta es del usuario.
        New-Item -ItemType Directory -Path $script:Carpeta -Force | Out-Null
        $ruta = Join-Path $script:Carpeta 'el informe bueno.html'
        Set-Content $ruta 'x'

        $informe = @(Get-InformesGuardados -CarpetaDatos $script:Datos)[0]
        $informe.Nombre | Should -Be 'el informe bueno.html'
        $informe.Tipo   | Should -Be 'informe'
        $informe.Fecha  | Should -Not -BeNullOrEmpty
    }

    It 'lo que genera New-NombreInforme lo reconoce Get-InformesGuardados' {
        # Las dos funciones tienen que hablar el mismo idioma. Si alguien
        # cambia el formato del nombre en una y no en la otra, la lista
        # deja de saber la fecha y el tipo de los informes nuevos.
        $ruta = New-NombreInforme -Tipo 'analisis' -Extension 'html' -CarpetaDatos $script:Datos
        Set-Content -LiteralPath $ruta -Value 'x'

        $informe = @(Get-InformesGuardados -CarpetaDatos $script:Datos)[0]
        $informe.Tipo | Should -Be 'analisis'
        [math]::Abs(([datetime]::Now - $informe.Fecha).TotalMinutes) | Should -BeLessThan 5
    }
}

Describe 'Resolve-InformeAbrible: la guardia de lo que se abre' {

    <#
        Esta es la única puerta por la que el programa abre un archivo con
        el programa predeterminado del sistema. La ruta no siempre la ha
        escrito el programa: las entradas del historial viven en un .json
        de texto plano en una carpeta escribible, así que hay que tratarlas
        como entrada hostil. Cada prueba de aquí describe algo que NO se
        debe abrir nunca.
    #>

    BeforeAll {
        $script:DatosG = Join-Path ([IO.Path]::GetTempPath()) ('grd_' + [guid]::NewGuid())
        $script:CarpetaG = Join-Path $script:DatosG 'informes'
        New-Item -ItemType Directory -Path $script:CarpetaG -Force | Out-Null

        $script:Legitimo = Join-Path $script:CarpetaG 'analisis_2026-08-19_143005.html'
        Set-Content -LiteralPath $script:Legitimo -Value '<html></html>'

        # Un vecino con nombre parecido, para el fallo clasico de comparar
        # prefijos sin separador: "...\informesFalsa" empieza por
        # "...\informes".
        $script:Vecina = Join-Path $script:DatosG 'informesFalsa'
        New-Item -ItemType Directory -Path $script:Vecina -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Vecina 'colado.html') -Value 'x'

        Set-Content -LiteralPath (Join-Path $script:DatosG 'fuera.html') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:CarpetaG 'script.ps1') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:CarpetaG 'programa.exe') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:CarpetaG 'acceso.lnk') -Value 'x'
    }

    AfterAll {
        Remove-Item -LiteralPath $script:DatosG -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'abre un informe legitimo de la carpeta de informes' {
        Resolve-InformeAbrible -Ruta $script:Legitimo -CarpetaDatos $script:DatosG |
            Should -Not -BeNullOrEmpty -Because 'si no abriera esto, la funcionalidad entera sobraria'
    }

    It 'acepta los tres formatos de informe y ningun otro' {
        foreach ($ext in @('html', 'csv', 'json')) {
            $ruta = Join-Path $script:CarpetaG "analisis_2026-08-19_143005.$ext"
            Set-Content -LiteralPath $ruta -Value 'x'
            Resolve-InformeAbrible -Ruta $ruta -CarpetaDatos $script:DatosG |
                Should -Not -BeNullOrEmpty -Because ".$ext es un formato de informe"
        }
    }

    It 'no abre un <Que> aunque este dentro de la carpeta de informes' -ForEach @(
        @{ Que = 'script de PowerShell'; Archivo = 'script.ps1' }
        @{ Que = 'ejecutable';           Archivo = 'programa.exe' }
        @{ Que = 'acceso directo';       Archivo = 'acceso.lnk' }
    ) {
        Resolve-InformeAbrible -Ruta (Join-Path $script:CarpetaG $Archivo) -CarpetaDatos $script:DatosG |
            Should -BeNullOrEmpty -Because 'abrirlo con el programa predeterminado seria ejecutarlo'
    }

    It 'no se sale de la carpeta con .. aunque la extension sea buena' {
        $escapada = Join-Path $script:CarpetaG (Join-Path '..' 'fuera.html')
        Resolve-InformeAbrible -Ruta $escapada -CarpetaDatos $script:DatosG | Should -BeNullOrEmpty
    }

    It 'no acepta una carpeta vecina cuyo nombre empieza igual' {
        Resolve-InformeAbrible -Ruta (Join-Path $script:Vecina 'colado.html') -CarpetaDatos $script:DatosG |
            Should -BeNullOrEmpty -Because 'informesFalsa empieza por informes, pero no esta dentro'
    }

    It 'no acepta rutas absolutas de cualquier otro sitio del disco' {
        Resolve-InformeAbrible -Ruta (Join-Path $script:DatosG 'fuera.html') -CarpetaDatos $script:DatosG |
            Should -BeNullOrEmpty
    }

    It 'no acepta un archivo que ya no existe' {
        Resolve-InformeAbrible -Ruta (Join-Path $script:CarpetaG 'borrado.html') -CarpetaDatos $script:DatosG |
            Should -BeNullOrEmpty -Because 'entre pintar la lista y el clic pueden pasar horas'
    }

    It 'no acepta la propia carpeta ni nada sin extension' {
        Resolve-InformeAbrible -Ruta $script:CarpetaG -CarpetaDatos $script:DatosG | Should -BeNullOrEmpty
        Resolve-InformeAbrible -Ruta (Join-Path $script:CarpetaG 'sinextension') -CarpetaDatos $script:DatosG |
            Should -BeNullOrEmpty
    }

    It 'no acepta nada vacio ni nulo' {
        Resolve-InformeAbrible -Ruta ''    -CarpetaDatos $script:DatosG | Should -BeNullOrEmpty
        Resolve-InformeAbrible -Ruta '   ' -CarpetaDatos $script:DatosG | Should -BeNullOrEmpty
        Resolve-InformeAbrible -Ruta $null -CarpetaDatos $script:DatosG | Should -BeNullOrEmpty
    }

    It 'no acepta un enlace que finge ser un informe y apunta fuera' {
        # El único ataque que sobrevive a las otras comprobaciones: la
        # extensión es buena, la ruta esta dentro de la carpeta, el archivo
        # existe... y sin embargo lo que se abriria esta en otro sitio. Por
        # eso se mira también el atributo de reanalisis.
        $enlace = Join-Path $script:CarpetaG 'parece_un_informe.html'
        $destino = Join-Path $script:DatosG 'fuera.html'
        $creado = $false
        try {
            New-Item -ItemType SymbolicLink -Path $enlace -Target $destino -ErrorAction Stop | Out-Null
            $creado = $true
        } catch {
            # Windows sin modo desarrollador exige privilegios para crear
            # enlaces. Si no se puede crear, no hay nada que comprobar.
            Set-ItResult -Skipped -Because 'este sistema no deja crear enlaces simbolicos'
        }
        if ($creado) {
            Resolve-InformeAbrible -Ruta $enlace -CarpetaDatos $script:DatosG |
                Should -BeNullOrEmpty -Because 'la ruta esta dentro, pero lo que abre no'
        }
    }
}

Describe 'Anonimizacion de informes' {

    <#
        SECURITY.md pide adjuntar el informe y el registro para reportar un
        fallo. Sin esto, colaborar con el proyecto obligaba a publicar el
        nombre de usuario de Windows -que aparece en CADA ruta de CADA
        fila- y el nombre del equipo. Nadie deberia tener que elegir entre
        reportar un fallo y su privacidad.
    #>

    BeforeAll {
        $script:EntornoPrevio = @{
            UP = $env:USERPROFILE; UN = $env:USERNAME; CN = $env:COMPUTERNAME
        }
        $env:USERPROFILE  = 'C:\Users\paco'
        $env:USERNAME     = 'paco'
        $env:COMPUTERNAME = 'PC-PACO'
    }

    AfterAll {
        $env:USERPROFILE  = $script:EntornoPrevio.UP
        $env:USERNAME     = $script:EntornoPrevio.UN
        $env:COMPUTERNAME = $script:EntornoPrevio.CN
    }

    Context 'ConvertTo-RutaAnonima' {

        It 'sustituye el perfil entero' {
            ConvertTo-RutaAnonima 'C:\Users\paco\Documents\x.txt' |
                Should -Be '<perfil>\Documents\x.txt'
        }

        It 'sustituye el usuario aunque aparezca DOS veces en la misma ruta' {
            # De mas especifico a mas general: si se sustituyera el nombre
            # suelto primero, el perfil ya no casaria y quedaria a medias.
            ConvertTo-RutaAnonima 'C:\Users\paco\AppData\Local\paco\notas.txt' |
                Should -Be '<perfil>\AppData\Local\<usuario>\notas.txt'
        }

        It 'sustituye el nombre del equipo' {
            ConvertTo-RutaAnonima 'Copiado desde PC-PACO' | Should -Be 'Copiado desde <equipo>'
        }

        It 'NO mutila palabras que contienen el nombre de usuario' {
            # Si el usuario se llama "ana", una carpeta "Semana" no puede
            # quedar como "Sem<usuario>". El nombre solo se sustituye
            # cuando es un SEGMENTO de ruta completo.
            ConvertTo-RutaAnonima 'D:\Semana Santa\pacotes\foto.jpg' |
                Should -Be 'D:\Semana Santa\pacotes\foto.jpg'
        }

        It 'no lanza con texto vacio ni nulo' {
            { ConvertTo-RutaAnonima '' }    | Should -Not -Throw
            { ConvertTo-RutaAnonima $null } | Should -Not -Throw
        }
    }

    Context 'Los exportadores lo aplican' {

        BeforeAll {
            $script:candidatoPrueba = New-Candidato -ModuloId 'x' -Categoria 'Prueba' `
                -Nombre 'archivo.tmp' -Ruta 'C:\Users\paco\AppData\Local\basura\archivo.tmp' `
                -Bytes 100 -Info 'en C:\Users\paco\AppData' -Metodo 'Informativo'
        }

        It 'el CSV anonimo no contiene el nombre de usuario' {
            $ruta = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.csv')
            try {
                Export-InformeCsv -Candidatos @($script:candidatoPrueba) -Ruta $ruta -Anonimo -Confirm:$false
                $texto = Get-Content -Raw -LiteralPath $ruta
                $texto | Should -Not -Match 'paco'
                $texto | Should -Match '<perfil>'
            } finally { Remove-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue }
        }

        It 'el CSV normal SI las conserva: es tu informe de tu equipo' {
            # Anonimizar por defecto haria el informe inutil para su uso
            # principal, que es que su dueño decida que borra.
            $ruta = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.csv')
            try {
                Export-InformeCsv -Candidatos @($script:candidatoPrueba) -Ruta $ruta -Confirm:$false
                (Get-Content -Raw -LiteralPath $ruta) | Should -Match 'paco'
            } finally { Remove-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue }
        }

        It 'el JSON anonimo tampoco, y NUNCA guarda el nombre del equipo' {
            $ruta = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.json')
            try {
                Export-InformeJson -Candidatos @($script:candidatoPrueba) -Ruta $ruta -Anonimo -Confirm:$false
                $texto = Get-Content -Raw -LiteralPath $ruta
                $texto | Should -Not -Match 'paco'
                $texto | Should -Not -Match 'PC-PACO'
            } finally { Remove-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue }
        }

        It 'el JSON normal tampoco guarda el nombre del equipo' {
            # Ese dato no lo usaba nadie y viajaba en cada archivo
            # compartido. Un dato que no se usa y que identifica, sobra.
            $ruta = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.json')
            try {
                Export-InformeJson -Candidatos @($script:candidatoPrueba) -Ruta $ruta -Confirm:$false
                (Get-Content -Raw -LiteralPath $ruta) | Should -Not -Match 'PC-PACO'
            } finally { Remove-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'COR-07: los informes se generan con la coleccion que usa la aplicacion' {

    <#
        Esta suite probaba los informes pasandoles un ARRAY. La ventana y
        la consola les pasan una List[object]. Durante semanas, todos los
        informes fallaron en el equipo del usuario -"Los tipos de
        argumentos no coinciden"- mientras aqui salia todo verde: se estaba
        probando un tipo que el programa no usa en ningun sitio.

        La leccion, que vale para toda la suite: si una funcion recibe una
        coleccion, hay que probarla con la coleccion REAL, no con la mas
        comoda de escribir en la prueba.
    #>

    BeforeAll {
        $script:RaizCol = Split-Path $PSScriptRoot -Parent
        . (Join-Path (Join-Path (Join-Path $script:RaizCol 'src') 'Core') 'Bootstrap.ps1')

        # Construida EXACTAMENTE como la construyen Window.ps1 y Cli.ps1.
        $script:Coleccion = [Collections.Generic.List[object]]::new()
        foreach ($i in 1..4) {
            $script:Coleccion.Add((New-Candidato -ModuloId 'm1' -Categoria 'Cat' `
                -Nombre "Elemento $i" -Ruta ('C:\Prueba\e{0}' -f $i) -Bytes ($i * 1048576)))
        }

        $script:Config = [pscustomobject]@{
            Equipo = ''; Windows = 'Windows 11'; Perfil = 'equilibrado'
            Unidades = @([pscustomobject]@{ Letra = 'C:'; Libre = 1073741824 })
        }
        $script:Carpeta = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-col-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Carpeta -Force | Out-Null
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Carpeta -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'la coleccion de prueba es del mismo tipo que la de la aplicacion' {
        # Si esto deja de ser cierto, el resto del Describe no prueba nada.
        $script:Coleccion.GetType().Name | Should -Be 'List`1'
        $script:Coleccion.Count | Should -Be 4
    }

    It 'Export-InformeHtml acepta la coleccion sin reventar' {
        $ruta = Join-Path $script:Carpeta 'informe.html'
        { Export-InformeHtml -Candidatos $script:Coleccion -Ruta $ruta `
                             -Configuracion $script:Config -Modulos @() -Confirm:$false } | Should -Not -Throw
        Test-Path -LiteralPath $ruta | Should -BeTrue
    }

    It 'el informe contiene los cuatro elementos, no una lista vacia' {
        # Que no lance no basta: una enumeracion silenciosamente vacia
        # produciria un informe valido y mentiroso.
        $ruta = Join-Path $script:Carpeta 'informe2.html'
        Export-InformeHtml -Candidatos $script:Coleccion -Ruta $ruta `
                           -Configuracion $script:Config -Modulos @() -Confirm:$false
        $html = Get-Content -Raw -LiteralPath $ruta
        foreach ($i in 1..4) { $html | Should -BeLike ('*Elemento {0}*' -f $i) }
    }

    It 'Export-InformeCsv y Export-InformeJson tambien' {
        $csv  = Join-Path $script:Carpeta 'i.csv'
        $json = Join-Path $script:Carpeta 'i.json'
        { Export-InformeCsv  -Candidatos $script:Coleccion -Ruta $csv  -Confirm:$false } | Should -Not -Throw
        { Export-InformeJson -Candidatos $script:Coleccion -Ruta $json -Configuracion $script:Config -Confirm:$false } | Should -Not -Throw
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 4
    }

    It 'Measure-TotalBytes suma bien sobre la coleccion' {
        # 1+2+3+4 MB
        Measure-TotalBytes $script:Coleccion 'Bytes' | Should -Be (10 * 1048576)
    }
}
