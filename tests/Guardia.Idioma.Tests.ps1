<#
    I18N-02: las listas de palabras de la guardia NO son texto de interfaz.

    POR QUE EXISTE ESTE ARCHIVO

    La hoja de ruta lo deja escrito como aviso critico y pide "un test que
    lo verifique". Este es.

    Test-CarpetaEspejo, Test-ArchivoPersonal y la lista de nombres
    sensibles comparan contra listas de palabras en castellano y en ingles:
    "documentos" y "documents", "respaldo" y "backup", "seguridad" y
    "security". Vistas desde fuera son indistinguibles de las cadenas que
    se sacan a un archivo de idioma cuando se traduce un programa. Y son
    otra cosa: son la logica que decide QUE NO SE PUEDE BORRAR.

    El dia que alguien haga la traduccion, el riesgo no es que el programa
    hable raro. Es este:

      - Una extraccion de textos se lleva las listas a un .psd1 de idioma o
        a cualquier recurso. La guardia pasa a depender de un archivo que
        se elige por cultura del sistema.
      - Al traducirlo, "documentos" se convierte en "Dokumente" y desaparece
        la mitad castellana, o la inglesa, o las dos.
      - Y NO FALLA NADA. Ni excepcion, ni aviso, ni linea en el registro.
        La guardia sigue respondiendo; lo unico que cambia es que empieza a
        dar por buenas rutas que antes vetaba. En un programa que borra
        archivos, ese es el peor fallo posible: el que solo se nota cuando
        ya no esta el archivo.

    QUE EXIGE ESTA INVARIANTE, Y POR QUE ESO Y NO OTRA COSA

    Dos patas, porque una sola no sirve de nada:

      1. ESTRUCTURA - las listas se quedan donde estan. Escritas como texto
         literal dentro de src/Core/Guard.ps1, sin que ninguna variable ni
         ninguna llamada intervenga en su valor, y sin que Guard.ps1 lea
         texto de ningun archivo, recurso o cultura. Y ningun otro archivo
         de src puede tocarlas: si se pudieran reasignar desde fuera,
         daria igual donde se hayan escrito.

      2. CONTENIDO - las dos mitades siguen ahi. Comprobar solo la
         estructura seria una prueba tranquilizadora e inutil: la lista
         puede seguir siendo un array literal en Guard.ps1 y tener dentro
         las palabras traducidas. Por eso la segunda pata pregunta a las
         funciones publicas, no a los arrays, y exige el par completo:
         "Documentos" Y "Documents", "respaldo" Y "backup". Traducir en vez
         de anyadir hace caer la mitad que se haya perdido, con nombre y
         apellidos.

    Se pregunta a las funciones y no a las listas a proposito: asi tambien
    cae si las listas se quedan intactas pero la funcion pasa a consultar
    otra cosa.

    Lo que esta invariante NO promete: que la guardia funcione en un
    Windows aleman o frances. Eso es I18N-03, sigue abierto, y se arregla
    ANYADIENDO idiomas a estas listas. Nunca sustituyendo los que hay.
#>

BeforeAll {
    $script:Raiz     = Split-Path $PSScriptRoot -Parent
    $script:CarpetaSrc  = Join-Path $script:Raiz 'src'
    $script:RutaGuardia = Join-Path (Join-Path $script:CarpetaSrc 'Core') 'Guard.ps1'

    . (Join-Path (Join-Path $script:CarpetaSrc 'Core') 'Bootstrap.ps1')

    # Carpetas personales vacias: asi ningun veredicto de esta prueba
    # depende de donde se ejecute, solo de las listas.
    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio = ''; Documentos = ''; Descargas = ''
        Imagenes   = ''; Musica     = ''; Videos     = ''; CarpetaDatos = ''
    })

    # Las listas protegidas. Estan aqui por su nombre y no descubiertas
    # automaticamente a proposito: la lista de lo que hay que proteger es
    # una decision, no un efecto secundario de como este escrito el
    # archivo hoy.
    $script:ListasDeSeguridad = @(
        'FragmentosProhibidos'    # \system32\, \microsoft\crypto\, \.ssh\...
        'NombresSensibles'        # seguridad/security, respaldo/backup, banco/bank
        'ExtensionesPersonales'   # .docx, .kdbx, .pst...
        'NombresBasuraConocida'   # thumbs.db, .ds_store
        'CarpetasEspejo'          # documentos/documents, descargas/downloads
        'RegexCarpetaPersonal'    # el patron bilingue de carpeta personal
        'RegexCopiaSeguridad'     # backup/respaldo/copias
    )

    $script:AstGuardia = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:RutaGuardia, [ref]$null, [ref]$null)

    function Get-AsignacionDe {
        <#
            La asignacion "$script:<Nombre> = ..." de Guard.ps1. Se busca
            en el AST y no con una expresion regular porque un comentario
            que mencione la lista no debe contar como asignacion: es la
            trampa que ya ha mordido cinco veces en este repositorio.
        #>
        param([string] $Nombre)
        return @($script:AstGuardia.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.Left.VariablePath.UserPath -eq ('script:' + $Nombre)
        }, $true))
    }

    function Get-NodosDe {
        param($Nodo, [type] $Tipo)
        return @($Nodo.FindAll({ param($n) $n -is $Tipo }, $true))
    }

    function Get-ArchivosSrc {
        return @(Get-ChildItem -LiteralPath $script:CarpetaSrc -Recurse -Filter '*.ps1' -File)
    }
}

Describe 'I18N-02 (1 de 2): las listas de la guardia se quedan donde estan' {

    It 'la prueba encuentra las <Cuantas> listas: si no, no esta comprobando nada' -ForEach @(
        @{ Cuantas = 7 }
    ) {
        # Guarda obligatoria. Si un cambio de nombre dejara a esta prueba
        # buscando algo que ya no existe, pasaria en verde sin mirar nada.
        $script:ListasDeSeguridad.Count | Should -Be $Cuantas

        foreach ($nombre in $script:ListasDeSeguridad) {
            @(Get-AsignacionDe -Nombre $nombre).Count | Should -Be 1 -Because (
                "no hay ninguna asignacion de `$script:$nombre en Guard.ps1: o se ha movido, o se ha renombrado")
        }
    }

    It 'la lista <Lista> es texto literal escrito en Guard.ps1' -ForEach @(
        @{ Lista = 'FragmentosProhibidos' }
        @{ Lista = 'NombresSensibles' }
        @{ Lista = 'ExtensionesPersonales' }
        @{ Lista = 'NombresBasuraConocida' }
        @{ Lista = 'CarpetasEspejo' }
        @{ Lista = 'RegexCarpetaPersonal' }
        @{ Lista = 'RegexCopiaSeguridad' }
    ) {
        $asignacion = @(Get-AsignacionDe -Nombre $Lista)
        $asignacion.Count | Should -Be 1

        $derecha = $asignacion[0].Right

        # Ni una llamada a comando en el valor. Esto es lo que prohibe
        # Import-LocalizedData, Get-Content, ConvertFrom-Json y cualquier
        # otra forma de traer las palabras de fuera.
        $comandos = Get-NodosDe -Nodo $derecha -Tipo ([System.Management.Automation.Language.CommandAst])
        @($comandos | ForEach-Object { $_.GetCommandName() }) | Should -BeNullOrEmpty -Because (
            "el valor de $Lista tiene que estar escrito aqui, no venir de ningun sitio")

        # Ni una variable. Esto es lo que prohibe la version sutil del
        # mismo fallo: la lista sigue en Guard.ps1, pero armada a partir de
        # un $textos.Carpetas que alguien rellena en otro lado.
        $variables = Get-NodosDe -Nodo $derecha -Tipo ([System.Management.Automation.Language.VariableExpressionAst])
        @($variables | ForEach-Object { $_.VariablePath.UserPath }) | Should -BeNullOrEmpty -Because (
            "$Lista no puede depender de ninguna variable: seria una lista construida a partir de un recurso")
    }

    It 'las listas de palabras tienen contenido de verdad, no dos ejemplos' {
        # Otra guarda: una lista vaciada seguiria siendo "texto literal".
        $minimos = @{
            FragmentosProhibidos  = 10
            NombresSensibles      = 30
            ExtensionesPersonales = 30
            NombresBasuraConocida = 4
            CarpetasEspejo        = 15
        }
        foreach ($nombre in $minimos.Keys) {
            $derecha  = (Get-AsignacionDe -Nombre $nombre)[0].Right
            $palabras = Get-NodosDe -Nodo $derecha -Tipo (
                [System.Management.Automation.Language.StringConstantExpressionAst])
            $palabras.Count | Should -BeGreaterOrEqual $minimos[$nombre] -Because (
                "$nombre se ha quedado en $($palabras.Count) palabras: la guardia protege menos que ayer")
        }
    }

    It 'Guard.ps1 no lee texto de ningun archivo de idioma, recurso ni cultura' {
        # El archivo mas importante del programa no puede depender de nada
        # que se elija en tiempo de ejecucion segun el idioma del equipo.
        $prohibidos = @(
            'Import-LocalizedData', 'Import-PowerShellDataFile', 'Get-Content',
            'ConvertFrom-Json', 'ConvertFrom-StringData', 'Import-Csv', 'Import-Clixml',
            'Import-Module', 'Invoke-WebRequest', 'Invoke-RestMethod',
            'Get-Culture', 'Get-UICulture'
        )
        $prohibidos.Count | Should -BeGreaterThan 5 -Because 'sin la lista, esto no comprueba nada'

        $invocados = @(Get-NodosDe -Nodo $script:AstGuardia `
                                   -Tipo ([System.Management.Automation.Language.CommandAst]) |
                       ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $invocados.Count | Should -BeGreaterThan 0 -Because 'si no se ve ni un comando, el AST no se ha leido'

        @($invocados | Where-Object { $_ -in $prohibidos }) | Should -BeNullOrEmpty -Because (
            'traer texto de fuera es el primer paso para que las listas dejen de estar aqui')

        # Lo mismo por la puerta de .NET, que no es un comando y se
        # escaparia de la comprobacion de arriba.
        $lecturas = @(Get-NodosDe -Nodo $script:AstGuardia `
                                  -Tipo ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
                      Where-Object { $_.Member.Value -match '^(ReadAllText|ReadAllLines|ReadAllBytes|ReadLines|OpenText|OpenRead)$' })
        $lecturas | Should -BeNullOrEmpty -Because 'Guard.ps1 no abre archivos: decide sobre rutas'

        # Y ninguna decision puede mirar la cultura del sistema.
        $culturas = @(Get-NodosDe -Nodo $script:AstGuardia `
                                  -Tipo ([System.Management.Automation.Language.VariableExpressionAst]) |
                      Where-Object { $_.VariablePath.UserPath -in @('PSUICulture', 'PSCulture') })
        $culturas | Should -BeNullOrEmpty -Because (
            'la guardia tiene que dar el mismo veredicto en un Windows en cualquier idioma')
    }

    It 'ningun otro archivo de src puede reasignar las listas de la guardia' {
        # Sin esto, el resto de la pata estructural no valdria: daria igual
        # que las listas esten escritas en Guard.ps1 si un archivo de
        # idioma pudiera sobrescribirlas al arrancar.
        $archivos = Get-ArchivosSrc
        $archivos.Count | Should -BeGreaterThan 20 -Because 'si no se recorren archivos, esto no comprueba nada'

        $culpables = @()
        foreach ($archivo in $archivos) {
            if ($archivo.FullName -eq $script:RutaGuardia) { continue }
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $archivo.FullName, [ref]$null, [ref]$null)

            $tocan = @(Get-NodosDe -Nodo $ast -Tipo (
                          [System.Management.Automation.Language.VariableExpressionAst]) |
                       Where-Object { $_.VariablePath.UserPath -in
                                      @($script:ListasDeSeguridad | ForEach-Object { 'script:' + $_ }) })

            # Y por la via indirecta, que no es una asignacion sino un
            # comando: Set-Variable -Name 'CarpetasEspejo' -Scope Script.
            $porNombre = @(Get-NodosDe -Nodo $ast -Tipo (
                              [System.Management.Automation.Language.CommandAst]) |
                           Where-Object { $_.GetCommandName() -in @('Set-Variable', 'New-Variable') } |
                           Where-Object {
                               $texto = $_.Extent.Text
                               @($script:ListasDeSeguridad | Where-Object { $texto -match $_ }).Count -gt 0
                           })

            if ($tocan.Count -gt 0 -or $porNombre.Count -gt 0) { $culpables += $archivo.Name }
        }

        $culpables | Should -BeNullOrEmpty -Because (
            'las listas de la guardia solo se escriben en Guard.ps1: quien las pueda cambiar desde fuera, manda')
    }

    It 'el aviso para quien traduzca sigue escrito donde lo va a ver' {
        # La invariante vive en tests/, y quien haga la extraccion de
        # textos va a estar leyendo Guard.ps1. El aviso tiene que estar
        # alli, y este es el unico sitio desde el que se puede exigir.
        $texto = Get-Content -Raw -LiteralPath $script:RutaGuardia
        $marcas = @([regex]::Matches($texto, '(?m)^\s*#.*\[I18N-02\]'))
        $marcas.Count | Should -BeGreaterOrEqual 1 -Because (
            'sin la marca [I18N-02] en Guard.ps1, quien extraiga los textos no tiene forma de saberlo')

        $texto | Should -Match 'NO SE TRADUCEN'
    }
}

Describe 'I18N-02 (2 de 2): las dos mitades de cada lista bilingue siguen ahi' {
    <#
        Esta es la pata que de verdad se entera de una traduccion. Se
        pregunta a las funciones publicas, no a los arrays: asi tambien cae
        si la lista se queda intacta pero la funcion pasa a consultar otro
        sitio.

        Cada caso exige el PAR completo. Traducir es sustituir, y sustituir
        deja siempre una de las dos mitades por el camino.
    #>

    It 'Test-CarpetaEspejo reconoce "<Es>" y "<En>"' -ForEach @(
        @{ Es = 'Documentos';        En = 'Documents' }
        @{ Es = 'Descargas';         En = 'Downloads' }
        @{ Es = 'Escritorio';        En = 'Desktop' }
        @{ Es = 'Favoritos';         En = 'Favorites' }
        @{ Es = 'MisImagenes';       En = 'MyPictures' }
        @{ Es = 'MiMusica';          En = 'MyMusic' }
        @{ Es = 'MisVideos';         En = 'MyVideos' }
        @{ Es = 'MisDocumentos';     En = 'MyDocuments' }
        @{ Es = 'Vinculos';          En = 'Links' }
        @{ Es = 'Busquedas';         En = 'Searches' }
        @{ Es = 'PartidasGuardadas'; En = 'SavedGames' }
        @{ Es = 'Contactos';         En = 'Contacts' }
    ) {
        Test-CarpetaEspejo $Es | Should -BeTrue -Because (
            "'$Es' es la mitad castellana: si cae, alguien ha traducido la lista en vez de anyadir a ella")
        Test-CarpetaEspejo $En | Should -BeTrue -Because (
            "'$En' es la mitad inglesa: si cae, alguien ha traducido la lista en vez de anyadir a ella")
    }

    It 'Test-CarpetaEspejo sigue diciendo que no a lo que no es una carpeta espejo' {
        # Sin esto, una lista que dijera "si" a todo pasaria los doce casos
        # de arriba sin proteger nada.
        Test-CarpetaEspejo 'node_modules'   | Should -BeFalse
        Test-CarpetaEspejo 'cache temporal' | Should -BeFalse
    }

    It 'Test-NombreSensible reconoce "<Es>" y "<En>"' -ForEach @(
        @{ Es = 'Seguridad del equipo'; En = 'Security Center' }
        @{ Es = 'Banco Santander';      En = 'Bank of America' }
        @{ Es = 'Respaldo 2024';        En = 'Backup 2024' }
        @{ Es = 'Contrasenas';          En = 'Passwords' }
        @{ Es = 'Sincronizacion';       En = 'Syncthing' }
        @{ Es = 'Certificados FNMT';    En = 'Certificates' }
    ) {
        Test-NombreSensible $Es | Should -BeTrue -Because "'$Es' es la mitad castellana de la lista"
        Test-NombreSensible $En | Should -BeTrue -Because "'$En' es la mitad inglesa de la lista"
    }

    It 'Test-NombreSensible sigue dejando pasar lo que no es sensible' {
        # Cada acierto de esta funcion es un 'continue' en 30-RestosProgramas:
        # una lista que dijera "si" a todo dejaria de examinar el disco
        # entero, y las doce parejas de arriba pasarian igual. Ver [SEG-12].
        Test-NombreSensible 'node_modules' | Should -BeFalse
        Test-NombreSensible 'Presets'      | Should -BeFalse
    }

    It 'Test-ArchivoPersonal protege "<Es>" y "<En>"' -ForEach @(
        @{ Es = 'Documento 3.tmp'; En = 'Document 3.tmp' }
        @{ Es = 'Foto1.tmp';       En = 'Photo1.tmp' }
        @{ Es = 'Imagen1.tmp';     En = 'Image1.tmp' }
        @{ Es = 'Respaldo1.tmp';   En = 'Backup1.tmp' }
    ) {
        # Extension .tmp a proposito: no esta en ExtensionesPersonales, asi
        # que el unico motivo por el que puede quedar protegido es el
        # patron bilingue de nombres. El veredicto viene de donde se cree.
        Test-ArchivoPersonal ('C:\trabajo\cosas\' + $Es) | Should -BeTrue -Because (
            "'$Es' es la mitad castellana del patron de nombres personales")
        Test-ArchivoPersonal ('C:\trabajo\cosas\' + $En) | Should -BeTrue -Because (
            "'$En' es la mitad inglesa del patron de nombres personales")
    }

    It 'Test-ArchivoPersonal sigue dejando proponer basura de verdad' {
        Test-ArchivoPersonal 'C:\trabajo\cosas\salida.tmp'  | Should -BeFalse
        Test-ArchivoPersonal 'C:\trabajo\cosas\imagecache.dat' | Should -BeFalse
    }

    It 'la guardia veta la carpeta personal "<Es>" y "<En>", y por el mismo motivo' -ForEach @(
        @{ Es = 'Documentos'; En = 'Documents' }
        @{ Es = 'Escritorio'; En = 'Desktop' }
        @{ Es = 'Descargas';  En = 'Downloads' }
        @{ Es = 'Imagenes';   En = 'Pictures' }
        @{ Es = 'Musica';     En = 'Music' }
    ) {
        # Rutas de tres niveles a proposito: con "D:\Documentos" la guardia
        # tambien bloquea, pero por estar demasiado cerca de la raiz, y la
        # prueba pasaria sin haber mirado la lista de palabras. Se exige el
        # MISMO VEREDICTO, no solo que se rechace.
        (Get-MotivoIntocable ('D:\trabajo\' + $Es)) | Should -Match 'carpeta personal' -Because (
            "'$Es' es la mitad castellana del patron de carpetas personales")
        (Get-MotivoIntocable ('D:\trabajo\' + $En)) | Should -Match 'carpeta personal' -Because (
            "'$En' es la mitad inglesa del patron de carpetas personales")
    }

    It 'y lo mismo con las tildes del castellano, que no son decorativas' {
        # ConvertTo-RutaNormalizada conserva los diacriticos, asi que sin
        # el paso por Remove-Tildes estas dos quedarian sin proteger en un
        # Windows en espanyol, que es el idioma para el que esta escrito el
        # programa. Ver [SEG-10].
        (Get-MotivoIntocable 'D:\trabajo\Imágenes') | Should -Match 'carpeta personal'
        (Get-MotivoIntocable 'D:\trabajo\Música')   | Should -Match 'carpeta personal'
    }

    It 'la guardia veta las copias de seguridad se llamen "<Nombre>"' -ForEach @(
        @{ Nombre = 'backup' }
        @{ Nombre = 'backups' }
        @{ Nombre = 'respaldo' }
        @{ Nombre = 'respaldos' }
        @{ Nombre = 'copias' }
    ) {
        (Get-MotivoIntocable ('D:\trabajo\' + $Nombre + '\lote')) |
            Should -Match 'copias de seguridad' -Because (
                "'$Nombre' esta en el patron bilingue de copias: una carpeta asi contiene lo que su duenyo no quiere perder")
    }

    It 'y no veta una carpeta cualquiera: si vetara todo, los casos de arriba no dirian nada' {
        (Get-MotivoIntocable 'D:\trabajo\cache\lote') | Should -BeNullOrEmpty
    }
}
