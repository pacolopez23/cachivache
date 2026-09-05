<#
    Reutilizar el indice guardado en "cachivache espacio", sin mentir.

    LA PREGUNTA QUE SE PRUEBA no es "va mas rapido" -eso aqui no se puede
    medir- sino: .PUEDE ESTE CAMINO ENSENYAR DATOS VIEJOS SIN DECIRLO? Sin
    diario de cambios, un indice reutilizado dice lo que HABIA cuando se
    guardo. Eso es aceptable y util; presentarlo como lo que hay AHORA no
    lo es. Casi todas las pruebas de abajo empujan hacia ahi.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Cli') 'Cli.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Cli') 'Espacio.ps1')
}

Describe 'La huella del volumen' {

    It 'cambia cuando cambia cualquiera de las tres cosas que la componen' {
        $base = Get-HuellaVolumen -Formato 'NTFS' -Bytes 500107862016 -Creacion ([datetime]'2024-03-11T09:12:44Z')
        (Get-HuellaVolumen -Formato 'exFAT' -Bytes 500107862016 -Creacion ([datetime]'2024-03-11T09:12:44Z')) | Should -Not -Be $base
        (Get-HuellaVolumen -Formato 'NTFS'  -Bytes 250000000000 -Creacion ([datetime]'2024-03-11T09:12:44Z')) | Should -Not -Be $base
        (Get-HuellaVolumen -Formato 'NTFS'  -Bytes 500107862016 -Creacion ([datetime]'2025-01-02T00:00:00Z')) | Should -Not -Be $base
    }

    It 'NO SE COME LOS ARGUMENTOS, que es el fallo que tuvo' {
        # La primera version empezaba con "$bytes = 0.0" y luego leia
        # "$Bytes". En PowerShell los nombres de variable NO distinguen
        # mayusculas: son LA MISMA, asi que la primera linea borraba el
        # argumento antes de usarlo y salia una huella con 0 y sin fecha.
        # No lanzaba, el analizador no decia nada, y el resultado tenia la
        # misma pinta que un disco al que no se le ha podido preguntar.
        $h = Get-HuellaVolumen -Formato 'NTFS' -Bytes 500107862016 -Creacion ([datetime]'2024-03-11T09:12:44Z')
        $h | Should -Match '500107862016' -Because 'el tamanyo tiene que llegar entero a la huella'
        $h | Should -Match '2024'         -Because 'la fecha tambien'
        $h | Should -Not -Match 'sin-fecha'
    }

    It 'la fecha no depende del idioma del sistema' {
        # Con la cultura del sistema, la misma fecha se escribiria distinto
        # en un Windows en espanyol y en uno en ingles, y la huella dejaria
        # de coincidir consigo misma al cambiar el idioma.
        $antes = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::new('es-ES')
            $a = Get-HuellaVolumen -Formato 'NTFS' -Bytes 1000 -Creacion ([datetime]'2024-03-11T09:12:44Z')
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::new('en-US')
            $b = Get-HuellaVolumen -Formato 'NTFS' -Bytes 1000 -Creacion ([datetime]'2024-03-11T09:12:44Z')
            $a | Should -Be $b
        } finally {
            [Threading.Thread]::CurrentThread.CurrentCulture = $antes
        }
    }

    It 'no lanza con nada dentro' {
        { Get-HuellaVolumen } | Should -Not -Throw
        { Get-HuellaVolumen -Formato $null -Bytes $null -Creacion $null } | Should -Not -Throw
        { Get-HuellaVolumen -Bytes 'no soy un numero' } | Should -Not -Throw
        { Get-HuellaVolumenDeZonas -Zonas $null } | Should -Not -Throw
        { Get-HuellaVolumenDeZonas -Zonas @('Z:\no\existe') } | Should -Not -Throw
    }
}

Describe 'El nombre del archivo de indice' {

    It 'UN INDICE VALE PARA LAS CARPETAS QUE MIDIO Y PARA NINGUNA OTRA' {
        # Es lo que impide que analizar "Descargas y Documentos" encuentre
        # el indice de "Descargas" y ensenye su total como si fuera el de
        # los dos. El formato del archivo no guarda que carpetas midio, asi
        # que lo resuelve el nombre.
        $uno = Get-NombreIndiceEspacio -Zonas @('C:\Users\x\Downloads')
        $dos = Get-NombreIndiceEspacio -Zonas @('C:\Users\x\Downloads', 'C:\Users\x\Documents')
        $uno | Should -Not -Be $dos
    }

    It 'el orden y las mayusculas no cuentan: en Windows es la misma carpeta' {
        $a = Get-NombreIndiceEspacio -Zonas @('C:\Users\x\Downloads', 'C:\Users\x\Documents')
        $b = Get-NombreIndiceEspacio -Zonas @('c:\users\X\DOCUMENTS\', 'C:\Users\x\Downloads')
        $a | Should -Be $b -Because 'si no, el indice se perderia cada vez que las zonas vinieran en otro orden'
    }

    It 'sin zonas no hay nombre, y no se inventa uno' {
        Get-NombreIndiceEspacio -Zonas @()          | Should -BeNullOrEmpty
        Get-NombreIndiceEspacio -Zonas $null        | Should -BeNullOrEmpty
        Get-NombreIndiceEspacio -Zonas @('', '  ')  | Should -BeNullOrEmpty
    }

    It 'es un nombre de archivo valido en Windows' {
        $n = Get-NombreIndiceEspacio -Zonas @('C:\Users\x\Downloads')
        $n | Should -Match '^espacio-[0-9a-f]{16}\.idx$'
        @([IO.Path]::GetInvalidFileNameChars() | Where-Object { $n.Contains($_) }).Count | Should -Be 0
    }
}

Describe 'El aviso de que los datos son de antes' {

    It 'SIEMPRE dice que no se ha mirado el disco, y como forzarlo' {
        # Las dos mitades del aviso. La segunda nombra una opcion, y una
        # opcion nombrada en un aviso tiene que existir: lo comprueba la
        # prueba de mas abajo.
        $a = Get-AvisoIndiceReutilizado -Escrito ([datetime]'2026-09-05T10:00:00') -Ahora ([datetime]'2026-09-05T10:06:30')
        $a | Should -Match 'no se ha vuelto a mirar el disco'
        $a | Should -Match '-Recorrer'
        $a | Should -Match '6 min'
    }

    It 'con fechas imposibles avisa igual, solo que sin la antiguedad' {
        # Callar seria presentar datos viejos como nuevos, que es justo lo
        # que esta funcion existe para impedir. Un reloj raro no es motivo
        # para dejar de avisar.
        foreach ($caso in @(
            @{ E = $null; A = ([datetime]'2026-09-05') }
            @{ E = ([datetime]'2026-09-05'); A = $null }
            @{ E = ([datetime]'2026-09-05T12:00:00'); A = ([datetime]'2026-09-05T10:00:00') }
        )) {
            $a = Get-AvisoIndiceReutilizado -Escrito $caso.E -Ahora $caso.A
            $a | Should -Match 'no se ha vuelto a mirar el disco'
            $a | Should -Match '-Recorrer'
        }
    }

    It 'la opcion que nombra el aviso existe de verdad en los dos sitios' {
        # Un aviso que dice "usa -Recorrer" y una linea de comandos que no
        # tiene -Recorrer es peor que no avisar. Se comprueba en el comando
        # y en el guion de entrada, que son dos declaraciones distintas.
        (Get-Command Show-InformeEspacio).Parameters.Keys | Should -Contain 'Recorrer'
        $entrada = [IO.File]::ReadAllText((Join-Path $script:Raiz 'Cachivache.ps1'))
        $entrada | Should -Match '\[switch\]\s*\$Recorrer'
        $entrada | Should -Match '-Recorrer:\$Recorrer' -Because 'declararlo y no pasarlo lo dejaria sin efecto'
    }
}

Describe 'La marca de "sin diario"' {

    It 'quien guarda y quien comprueba dicen lo mismo' {
        # Si estos dos dejaran de coincidir, el indice se rechazaria
        # siempre y nadie sabria por que: el programa no fallaria, solo
        # dejaria de ir rapido. Por eso es una funcion y no un literal.
        Get-MarcaSinDiario | Should -Be (Get-MarcaSinDiario)
        Get-MarcaSinDiario | Should -Not -BeNullOrEmpty -Because 'Test-IndiceUtilizable rechaza un identificador vacio'
    }

    It 'un indice guardado sin diario lo rechazaria un programa CON diario' {
        # No es un apanyo para colarse por la comprobacion: es lo correcto.
        # El dia que alguien retome el camino del diario, los indices de
        # hoy traeran 'sin-diario' donde se espera un identificador de
        # verdad, y Test-IndiceUtilizable los tirara SOLO.
        $cabecera = [pscustomobject]@{
            Version = (Get-VersionFormatoIndice); SerieVolumen = 'H'; IdDiario = (Get-MarcaSinDiario)
            UsnCorte = 0; Entradas = 3; Suma = 'x'; Escrito = (Get-Date)
        }
        $v = Test-IndiceUtilizable -Cabecera $cabecera -VersionEsperada (Get-VersionFormatoIndice) `
                                   -SerieVolumen 'H' -IdDiario '133164517833123661' -PrimerUsn 100 -Ahora (Get-Date)
        $v.Utilizable | Should -BeFalse
    }
}

Describe 'De punta a punta: `espacio` reutiliza el indice, y lo dice' {

    BeforeAll {
        # SE FIJA LOCALAPPDATA, Y ESTO SALIO DE UN FALLO DE VERDAD. Estas
        # pruebas pasaban sueltas y fallaban dentro de la suite: otro
        # archivo deja la variable apuntando a una ruta estilo Windows
        # -"C:\Users\..."- que en Linux no existe, y entonces
        # Get-CarpetaDatos devuelve algo inservible, el comando se salta el
        # indice en silencio (que es lo correcto: es una optimizacion) y
        # aqui no aparece el aviso que se esperaba.
        #
        # O sea que la red de seguridad funcionaba y la prueba dependia del
        # entorno que le dejara OTRO archivo. Una prueba que pasa sola y
        # falla acompanyada no es una prueba: es una moneda al aire.
        $script:AppDataAntes = $env:LOCALAPPDATA
        $script:AppData = Join-Path ([IO.Path]::GetTempPath()) ('appdata-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:AppData -Force)
        $env:LOCALAPPDATA = $script:AppData

        $script:Taller = Join-Path ([IO.Path]::GetTempPath()) ('esp-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:Taller -Force)
        foreach ($n in 1..3) {
            [IO.File]::WriteAllBytes((Join-Path $script:Taller "f$n.bin"), [byte[]]::new(2MB))
        }
        function script:Corre {
            param([switch] $Recorrer)
            return ((Show-InformeEspacio -Rutas @($script:Taller) -Profundidad 1 -Archivos 2 `
                                         -Recorrer:$Recorrer 6>&1 | Out-String))
        }
    }

    AfterAll {
        # Se devuelve la variable como estaba, por lo mismo que se fijo: el
        # archivo siguiente no tiene por que heredar lo que este toco.
        $env:LOCALAPPDATA = $script:AppDataAntes
        foreach ($carpeta in @($script:Taller, $script:AppData)) {
            if ($carpeta -and (Test-Path -LiteralPath $carpeta)) {
                Remove-Item -LiteralPath $carpeta -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'la primera vez recorre y no avisa de nada' {
        $s = script:Corre
        $s | Should -Match '6\.0 MB'
        $s | Should -Not -Match 'índice guardado' -Because 'la primera vez no hay indice, y decirlo seria ruido'
    }

    It 'la segunda reutiliza Y LO DICE' {
        $s = script:Corre
        $s | Should -Match '6\.0 MB'
        $s | Should -Match 'índice guardado'
        $s | Should -Match '-Recorrer'
    }

    It 'SI EL DISCO CAMBIA, ENSENYA LO VIEJO — PERO DICIENDO QUE ES VIEJO' {
        # Este es EL caso incomodo, y por eso se prueba en vez de esconderlo.
        # Sin diario no hay forma de enterarse del archivo nuevo. El
        # programa no puede evitar ensenyar 6 MB donde ya hay 11; lo que si
        # puede -y tiene que- es no presentarlos como recien medidos.
        [IO.File]::WriteAllBytes((Join-Path $script:Taller 'f4.bin'), [byte[]]::new(5MB))
        $s = script:Corre
        $s | Should -Match '6\.0 MB'
        $s | Should -Match 'no se ha vuelto a mirar el disco'
    }

    It '-Recorrer vuelve a mirar de verdad, y deja el indice al dia' {
        $s = script:Corre -Recorrer
        $s | Should -Match '11\.0 MB'
        $s | Should -Not -Match 'índice guardado'

        # Y lo recorrido se guarda: la siguiente ya ensenya lo nuevo.
        $t = script:Corre
        $t | Should -Match '11\.0 MB'
        $t | Should -Match 'índice guardado'
    }

    It 'REUTILIZAR NO REJUVENECE EL INDICE, o la caducidad no caducaria nunca' {
        # SALIO MUTANDO, y es la forma mas silenciosa de mentir que tiene
        # este camino. Si al reutilizar se volviera a guardar, el archivo
        # llevaria fecha de HOY con datos de ANTES. Y como la unica red que
        # queda sin diario es la caducidad de siete dias, un indice que se
        # consulta a diario no caducaria JAMAS: cada consulta le renovaria
        # el plazo mientras se aleja un poco mas de lo que hay en el disco.
        #
        # Solo se guarda lo que se ha recorrido de verdad.
        $ruta = Join-Path (Join-Path (Get-CarpetaDatos) 'indices') (Get-NombreIndiceEspacio -Zonas @($script:Taller))
        Test-Path -LiteralPath $ruta | Should -BeTrue -Because 'sin archivo esta prueba no comprueba nada'

        $antes = (Get-CabeceraIndice -Ruta $ruta).Escrito
        Start-Sleep -Milliseconds 1100
        $s = script:Corre
        $s | Should -Match 'índice guardado' -Because 'esta pasada tiene que ser de las que reutilizan'

        $despues = (Get-CabeceraIndice -Ruta $ruta).Escrito
        $despues | Should -Be $antes -Because 'reutilizar no es medir, y la fecha dice cuando se midio'
    }

    It 'no deja rastro en las carpetas que analiza' {
        # El indice vive en los datos de la aplicacion. Escribirlo dentro
        # de la carpeta medida la ensuciaria y ademas se contaria a si
        # mismo en el siguiente analisis.
        @(Get-ChildItem -LiteralPath $script:Taller -Filter '*.idx' -Recurse).Count |
            Should -Be 0 -Because 'un informe no escribe en lo que informa'
    }
}
