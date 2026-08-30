<#
.SYNOPSIS
    Guardia de seguridad: decide que rutas NO se pueden tocar jamas.

.DESCRIPTION
    Este es el archivo más importante del proyecto. Todo borrado pasa por
    aquí antes de ejecutarse, y vuelve a pasar justo antes de borrar
    (revalidación en vivo), porque entre el análisis y la eliminación el
    usuario puede haber movido cosas.

    El modelo es de LISTA BLANCA: una ruta solo es borrable si cuelga de
    una raiz explicitamente autorizada por el módulo que la propuso. Todo
    lo demás se rechaza por defecto.

    Test-RutaIntocable aplica cinco filtros encadenados; cualquiera veta:
      1. Forma de la ruta: demasiado corta, raiz de unidad, recurso de red
         o travesia con dos puntos.
      2. Lista negra de rutas exactas, más la comprobación de que la ruta
         no sea ANTECESORA de ninguna de ellas.
      3. Fragmentos prohibidos en cualquier punto (WinSxS, System32,
         claves criptograficas, credenciales...).
      4. La ruta ES una carpeta personal (último segmento), este donde
         este: D:\Documentos, E:\Fotos\Imágenes...
      5. Cualquier cosa bajo una carpeta de copias de seguridad.

    Encima de eso, Test-RutaSegura añade la lista blanca de raices del
    módulo, el veto de enlaces simbolicos y el veto por extensión personal:
    tres comprobaciones más, ocho en total para cualquier candidato. El
    README cuenta "siete filtros" porque agrupa de otra forma y además
    incluye Test-NombreSensible, que NO es universal: solo lo invocan por
    su cuenta los módulos de más riesgo (hoy, únicamente "restos"). Los dos
    números son ciertos según que se cuente; lo que no puede pasar es que
    ninguno de los dos sitios lo aclare. Ver [T-01] en
    docs/OPTIMIZACIONES.md.

    IMPORTANTE: el filtro 4 mira solo el ÚLTIMO segmento a propósito.
    Vetar cualquier ruta que contenga "\descargas\" o "\documentos\" en
    algún punto dejaria sin función a la mitad de los módulos, que tienen
    que mirar precisamente ahi dentro. Lo que protege ese contenido es la
    lista blanca de raices más el veto por extensión.
#>

# Profundidad mínima de una ruta para considerarla candidata: tiene que
# colgar de algo, no ser una carpeta de primer nivel de la unidad.
#
# Antes esto se medía en CARACTERES -menos de 15, fuera- y era una regla
# equivocada disfrazada de umbral: "D:\Juegos\Steam" son 14 caracteres y
# "E:\Games\Old", 12, así que las bibliotecas de juegos en discos
# secundarios -justo donde vive la basura que este programa busca- quedaban
# vetadas por ser cortas de escribir. Lo que de verdad se quería excluir no
# es lo corto, es lo poco profundo: "C:\tmp" sobra por estar colgando de la
# raiz, no por medir seis caracteres. Ver [SEG-16] en docs/PLAN-ACCION.md.
$script:SeparadoresMinimos = 2

function Initialize-Guardia {
    <#
    .SYNOPSIS
        Prepara las listas negras a partir de la configuración del equipo.
    .PARAMETER Configuracion
        Objeto devuelto por New-Configuracion.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Configuracion)

    # Se baja la bandera ANTES de tocar nada y se sube en la última
    # sentencia de la función. Mientras tanto la guardia se considera no
    # inicializada, que es el estado que lo bloquea todo. Ver [SEG-11].
    $script:GuardiaLista = $false

    $script:RutasIntocables = @(
        # --- Raiz y sistema operativo -----------------------------------
        $env:SystemDrive
        "$env:SystemDrive\"
        $env:SystemRoot
        "$env:SystemRoot\System32"
        "$env:SystemRoot\SysWOW64"
        "$env:SystemRoot\WinSxS"
        "$env:SystemRoot\Boot"
        "$env:SystemRoot\Fonts"
        "$env:SystemDrive\Windows"
        "$env:SystemDrive\Users"
        "$env:SystemDrive\Recovery"
        "$env:SystemDrive\System Volume Information"

        # --- Programas ---------------------------------------------------
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:ProgramData
        "$env:ProgramData\Package Cache"
        "$env:ProgramFiles\WindowsApps"
        "$env:ProgramData\Microsoft"
        "$env:ProgramData\USOShared"

        # --- Perfil del usuario ------------------------------------------
        $env:USERPROFILE
        $env:LOCALAPPDATA
        $env:APPDATA
        "$env:LOCALAPPDATA\Microsoft"
        "$env:APPDATA\Microsoft"
        "$env:LOCALAPPDATA\Packages"
        "$env:USERPROFILE\.ssh"
        "$env:USERPROFILE\OneDrive"

        # --- Carpetas personales resueltas en tiempo de ejecución ---------
        $Configuracion.Escritorio
        $Configuracion.Documentos
        $Configuracion.Descargas
        $Configuracion.Imagenes
        $Configuracion.Musica
        $Configuracion.Videos
        $Configuracion.CarpetaDatos
    ) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { ConvertTo-RutaNormalizada $_ } |
    Where-Object { $_ } |
    Select-Object -Unique

    # =================================================================
    # [I18N-02] ESTAS LISTAS NO SE TRADUCEN. NO SON TEXTO DE INTERFAZ.
    #
    # Lo que viene a partir de aqui son palabras en castellano y en ingles
    # -"documentos" y "documents", "respaldo" y "backup", "seguridad" y
    # "security"-, y por eso PARECEN cadenas de interfaz esperando a que
    # alguien las saque a un archivo de idioma. No lo son: son LOGICA DE
    # SEGURIDAD. Con ellas decide la guardia que no se puede borrar.
    #
    # Si una extraccion de textos se las lleva a un .resx, a un .psd1 de
    # idioma o a cualquier recurso, pasan dos cosas y ninguna se ve:
    #   - traducir la lista al idioma de turno BORRA la mitad castellana o
    #     la inglesa, y la guardia deja de reconocer justo las carpetas que
    #     protegia;
    #   - y no falla nada. No hay excepcion, no hay aviso: simplemente se
    #     propone para borrar algo que antes estaba vetado.
    #
    # Las dos mitades tienen que seguir estando LAS DOS, aqui dentro y
    # escritas literalmente. Ver [I18N-02] en docs/HOJA-DE-RUTA.md y la
    # invariante de tests/Guardia.Idioma.Tests.ps1, que lo exige archivo a
    # archivo: FragmentosProhibidos, NombresSensibles,
    # ExtensionesPersonales, NombresBasuraConocida, CarpetasEspejo,
    # RegexCarpetaPersonal y RegexCopiaSeguridad.
    #
    # (Lo que si es un problema abierto, y distinto, es que un Windows
    # aleman o frances tenga las carpetas con OTROS nombres: eso es
    # [I18N-03], y se arregla anyadiendo idiomas a estas listas, nunca
    # sustituyendo los que ya hay.)
    # =================================================================
    $script:FragmentosProhibidos = @(
        'windowsapps', 'package cache', 'winsxs', 'driverstore', 'catroot',
        '\system32\', '\syswow64\', '\config\systemprofile\', '\assembly\',
        'systemcertificates', '\microsoft\crypto\', '\microsoft\protect\',
        '\microsoft\vault\', '\microsoft\credentials\', '\windows defender',
        '\.ssh\', '\gnupg\', '\.gnupg\', '\.aws\', '\.kube\', '\.docker\config',
        '\system volume information', '\$recycle.bin\', '\recovery\'
    )

    $script:NombresSensibles = @(
        # Seguridad del equipo
        'defender', 'antivir', 'bitdefender', 'kaspersky', 'eset', 'avast', 'avg',
        'norton', 'mcafee', 'malwarebytes', 'sophos', 'trendmicro', 'firewall',
        'seguridad', 'security'
        # Identidad digital
        'certific', 'fnmt', 'pki', 'smartcard', 'dnie', 'autofirma', 'clave', 'token'
        # Gestores de contraseñas
        'keepass', 'bitwarden', 'lastpass', '1password', 'dashlane', 'password',
        'contrasen', 'authenticator'
        # Monederos y criptomonedas
        'wallet', 'ledger', 'trezor', 'metamask', 'exodus', 'electrum', 'bitcoin', 'crypto'
        # Sincronización en la nube
        'onedrive', 'dropbox', 'gdrive', 'googledrive', 'mega', 'icloud',
        'nextcloud', 'syncthing', 'resilio', 'sincroniz'
        # Copias de seguridad
        'backup', 'respaldo', 'veeam', 'acronis', 'macrium', 'restic', 'borg'
        # Comunicaciones y banca
        'thunderbird', 'outlook', 'mailstore', 'signal', 'whatsapp', 'telegram',
        'bank', 'banco', 'hacienda', 'aeat'
    )

    $script:ExtensionesPersonales = @(
        # Ofimatica
        '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.pdf', '.odt', '.ods',
        '.rtf', '.txt', '.md', '.csv'
        # Imagen y video
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tif', '.tiff', '.raw', '.heic',
        '.cr2', '.nef', '.arw', '.mp4', '.mov', '.avi', '.mkv', '.webm'
        # Audio
        '.mp3', '.wav', '.flac', '.ogg', '.m4a', '.aac'
        # Correo y comprimidos con datos
        '.pst', '.ost', '.eml', '.msg', '.mbox'
        # Partidas guardadas y proyectos creativos
        '.sav', '.save', '.world', '.blend', '.psd', '.ai', '.indd', '.dwg',
        '.prproj', '.aep', '.sketch', '.fig'
        # Bases de datos y llaves
        '.kdbx', '.db', '.sqlite', '.mdb', '.accdb', '.pem', '.key', '.pfx', '.p12'
    )

    # Archivos que llevan una extensión "personal" pero que en realidad son
    # basura conocida del sistema. Sin esta excepción, Thumbs.db quedaria
    # protegido para siempre por ser un .db.
    $script:NombresBasuraConocida = @(
        'thumbs.db', 'ehthumbs.db', 'ethumbs.db', '.ds_store',
        'iconcache.db', 'desktop.ini.bak'
    )

    # Nombres de carpeta que parecen vacías pero son enlaces heredados del
    # sistema. Borrarlas rompe cuadros de dialogo antiguos.
    $script:CarpetasEspejo = @(
        'misimagenes', 'mimusica', 'misvideos', 'misdocumentos', 'mypictures',
        'mymusic', 'myvideos', 'mydocuments', 'documentos', 'documents',
        'descargas', 'downloads', 'escritorio', 'desktop', 'favoritos', 'favorites',
        'contactos', 'contacts', 'vinculos', 'links', 'busquedas', 'searches',
        'partidasguardadas', 'savedgames', 'onedrive', 'applicationdata',
        'datosdeprograma', 'configuracionlocal', 'localsettings'
    )

    # --- Nombres sensibles: dos grupos, dos formas de comparar ---------
    #
    # Comparar todos por subcadena era demasiado laxo hacia el lado
    # "seguro", y ese lado tiene un precio que no se veia: cada acierto es
    # un 'continue' en 30-RestosProgramas, así que la carpeta no se examina
    # NUNCA y su basura es invisible para siempre. "eset" casaba dentro de
    # Presets y de Reset, "avg" dentro de savgame, "mega" dentro de Omega,
    # "clave" dentro de Autoclave y "token" dentro de SignalRToken.
    #
    # Las palabras LARGAS (6 o más) siguen comparandose por subcadena: son
    # inequivocas, y varias son raices a proposito -"certific", "contrasen",
    # "sincroniz"- que tienen que casar con sus derivados.
    #
    # Las CORTAS exigen empezar en un limite: principio del nombre o
    # detras de algo que no sea una letra. Así "ESET Security" y "MEGAsync"
    # siguen protegidos y "Presets" y "Omega" dejan de estarlo.
    # Equivocarse aquí hacia "no sensible" no borra nada: la carpeta solo
    # pasa a EXAMINARSE, y sigue teniendo delante la guardia entera.
    # Ver [SEG-12] en docs/PLAN-ACCION.md.
    $script:NombresSensiblesLargos = @($script:NombresSensibles | Where-Object { $_.Length -ge 6 })

    $cortas = @($script:NombresSensibles | Where-Object { $_.Length -lt 6 } |
                ForEach-Object { [regex]::Escape($_) })
    $script:NombresSensiblesCortos = if ($cortas.Count -gt 0) {
        [regex]::new('(^|[^a-z])(' + ($cortas -join '|') + ')',
                     [Text.RegularExpressions.RegexOptions]::Compiled)
    } else { $null }

    # --- Precalculo para la ruta caliente de la guardia ---------------
    #
    # Get-MotivoIntocable se llama por CADA candidato y, dentro de
    # Clear-ContenidoCarpeta, por cada archivo: sobre una cache de
    # 200.000 archivos son 200.000 pasadas. El plan de la version 2.0.0
    # midio 42 us por llamada, y casi todo se iba en dos bucles y en
    # regex interpretadas. Las tres cosas se pueden calcular UNA vez aqui.
    #
    # 1. "La ruta es antecesora de algo protegido" era un bucle sobre las
    #    ~30 rutas intocables con un StartsWith cada una. Es equivalente,
    #    exactamente, a preguntar si la ruta esta en el conjunto de TODOS
    #    los antepasados de las rutas protegidas, que se puede precalcular
    #    y consultar en O(1).
    $script:AntepasadosProtegidos = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($protegida in $script:RutasIntocables) {
        $trozos = $protegida.Split('\', [StringSplitOptions]::RemoveEmptyEntries)
        for ($i = 1; $i -lt $trozos.Count; $i++) {
            [void]$script:AntepasadosProtegidos.Add(($trozos[0..($i - 1)] -join '\'))
        }
    }

    # 2. Los fragmentos prohibidos eran 24 Contains por llamada. Una sola
    #    expresion compilada los cubre todos de una pasada.
    $script:RegexFragmentos = [regex]::new(
        '(' + (($script:FragmentosProhibidos | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')',
        [Text.RegularExpressions.RegexOptions]::Compiled -bor
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # 3. Las dos expresiones del filtro de carpetas personales y de copias
    #    de seguridad, tambien compiladas.
    $script:RegexCarpetaPersonal = [regex]::new(
        '^(documents?|documentos?|desktop|escritorio|downloads?|descargas?|pictures?|imagenes?|fotos|music|musica|videos?|onedrive)$',
        [Text.RegularExpressions.RegexOptions]::Compiled -bor
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $script:RegexCopiaSeguridad = [regex]::new(
        '(\\|^)(backups?|respaldos?|copias|copias de seguridad)\\',
        [Text.RegularExpressions.RegexOptions]::Compiled -bor
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    # Última sentencia: a partir de aquí la guardia esta completa. Si algo
    # de lo anterior lanza, la bandera se queda abajo y Test-GuardiaLista
    # lo bloquea todo, en vez de dar por buenas unas listas a medio cargar.
    $script:GuardiaLista = $true
}

function ConvertTo-RutaNormalizada {
    <#
    .SYNOPSIS
        Deja una ruta en minusculas, con barra invertida y sin barra final.
    .DESCRIPTION
        Todas las comparaciones de la guardia pasan por aquí. Unificar el
        separador evita que una ruta escrita con barra normal, que Windows
        acepta perfectamente, se salte los filtros por no coincidir con el
        patron esperado.

        Y se quita el prefijo "\\?\" de rutas largas por el mismo motivo,
        que es defensa en profundidad. Desde [COR-02] ese prefijo existe en
        el programa, aunque no deba salir nunca de las llamadas al sistema.
        Si algun dia se colara hasta aquí sin esta linea pasarian dos
        cosas, las dos malas:

          - "\\?\C:\Windows" NO coincidiria con la lista negra
            "C:\Windows", porque son cadenas distintas;
          - y en cambio SI casaria con el patron de recurso de red, que
            mira si la ruta empieza por dos barras.

        O sea que la guardia daria el veredicto correcto -bloquear- por el
        motivo equivocado, y para una ruta legitima daria el veredicto
        equivocado: "es un recurso de red" sobre una carpeta del propio
        disco. Un filtro que acierta por casualidad deja de acertar en
        cuanto cambia cualquier cosa alrededor.

        Se descubrio justamente asi: una prueba de [COR-02] pasaba, pero
        pasaba por este motivo y no por el que decia comprobar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return '' }
    $sinPrefijo = ConvertFrom-RutaLarga -Ruta $Ruta
    return $sinPrefijo.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
}

function Test-GuardiaLista {
    <#
    .SYNOPSIS
        Comprueba que Initialize-Guardia se ha ejecutado ENTERA en este
        ámbito.
    .DESCRIPTION
        Mira una bandera que Initialize-Guardia sube en su última
        sentencia, no la primera lista que asigna.

        La diferencia importa. Antes se comprobaba $script:RutasIntocables,
        que es lo PRIMERO que se rellena: si Initialize-Guardia fallaba a
        mitad -por ejemplo al resolver una carpeta conocida-, la guardia se
        declaraba lista con $script:ExtensionesPersonales todavia a $null.
        Y como "$null -contains $extension" es $false, el veto por
        extensión personal desaparecia sin que nada avisara: la guardia
        seguia respondiendo, pero ya no protegia los documentos del
        usuario. Un fallo parcial tiene que cerrar la puerta, no dejarla
        entornada. Ver [SEG-11] en docs/PLAN-ACCION.md.
    #>
    [OutputType([bool])]
    param()
    return $script:GuardiaLista -eq $true
}

function Get-MotivoIntocable {
    <#
    .SYNOPSIS
        Explica por que una ruta esta vetada sin condiciones, o cadena
        vacía si no lo esta bajo ninguno de estos filtros.
    .DESCRIPTION
        Única fuente de verdad de los filtros incondicionales de la
        guardia. Test-RutaIntocable es un envoltorio booleano de esta
        función, y Get-MotivoBloqueo la reutiliza en vez de reimplementar
        los mismos filtros por su cuenta.

        Antes esta lógica vivia duplicada en Test-RutaIntocable y en
        Get-MotivoBloqueo, y las dos copias se habían desincronizado:
        Get-MotivoBloqueo omitia tres de los filtros (la travesia con
        "..", el veto de carpeta personal por último segmento y el veto
        de copias de seguridad), así que para una ruta rechazada por
        cualquiera de esos tres el registro decia literalmente
        "Bloqueado por la guardia: Sin bloqueo." en la única función cuyo
        propósito es hacer auditable el programa sin leer el código.
        Unificarlas hace imposible que vuelvan a desincronizarse. Ver
        [C-08] en docs/OPTIMIZACIONES.md.

        Ante la duda siempre bloquea. Un falso positivo solo hace que se
        deje de limpiar algo; un falso negativo puede romper el equipo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Ruta)

    if (-not (Test-GuardiaLista)) {
        return 'La guardia no se ha inicializado en este ámbito: se bloquea todo por seguridad.'
    }
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return 'Ruta vacía.' }

    $r = ConvertTo-RutaNormalizada $Ruta

    # 1. Formas de ruta que nunca son un candidato válido.
    if ($r -match '^[a-z]:\\?$') { return 'Es la raiz de una unidad.' }
    if ($r -match '^\\\\')       { return 'Es un recurso de red.' }
    # Profundidad, no longitud: se exige que la ruta cuelgue de algo. Con
    # el umbral de caracteres anterior, "D:\Juegos\Steam" quedaba vetada
    # por medir 14. Ver [SEG-16].
    if (($r.Split('\', [StringSplitOptions]::RemoveEmptyEntries).Count - 1) -lt $script:SeparadoresMinimos) {
        return 'Ruta demasiado cerca de la raiz para ser un candidato.'
    }
    # Una travesia es un SEGMENTO que vale exactamente "..", no dos puntos
    # en cualquier sitio. Con Contains('..') quedaban vetadas para siempre
    # rutas legitimas como "proyecto v1..2" o "notas...txt", y encima el
    # mensaje les acusaba de algo que no hacian. La comprobación sigue
    # siendo igual de estricta para lo que importa: "\..\" en medio y "\.."
    # al final.
    if ($r.Contains('\..\') -or $r.EndsWith('\..') -or $r -eq '..' -or $r.StartsWith('..\')) {
        return 'Contiene una travesia de rutas (..).'
    }

    # 2. Coincidencia exacta con la lista negra.
    if ($script:RutasIntocables -contains $r) { return 'Esta en la lista de rutas protegidas.' }

    # 3. La ruta es ANTECESORA de algo intocable (borrarla se lo llevaria).
    #    Ordinal, no la sobrecarga de un solo argumento: esa compara con la
    #    cultura actual, que IGNORA ciertos caracteres (guion suave, ZWJ...).
    #    Con ella, "C:\a\b<guion suave>c\" empieza por "C:\a\bc\" y una ruta
    #    quedaba fuera de la comparacion sin estarlo de verdad. Es una
    #    comprobación de seguridad: tiene que comparar bytes, no idioma.
    # Consulta O(1) contra el conjunto de antepasados precalculado en
    # Initialize-Guardia, en vez de un StartsWith por cada ruta protegida.
    # Es la misma pregunta: "$protegida empieza por $r\" es cierto si y
    # solo si $r es uno de los antepasados de $protegida.
    if ($script:AntepasadosProtegidos.Contains($r)) {
        return 'Contiene una ruta protegida.'
    }

    # 4. Fragmentos prohibidos en cualquier punto de la ruta.
    $conBarra = $r + '\'
    $fragmento = $script:RegexFragmentos.Match($conBarra)
    if ($fragmento.Success) { return "Contiene un fragmento prohibido: $($fragmento.Value)" }

    # 5a. La ruta ES una carpeta personal, este donde este. Protege los
    #     casos que la lista negra no puede conocer: D:\Documentos,
    #     E:\Fotos de la boda\Imágenes, un Escritorio de otro perfil...
    #
    #     Se comprueba solo el ÚLTIMO segmento, no la ruta entera. Vetar
    #     cualquier ruta que contenga "\descargas\" en algún punto dejaria
    #     inservibles los módulos que tienen que mirar precisamente ahi
    #     dentro: instaladores viejos, temporales sueltos, accesos rotos.
    #     Lo que protege el contenido de esas carpetas no es este filtro,
    #     sino la lista blanca de raices de cada módulo y el veto por
    #     extensión de Test-ArchivoPersonal.
    #     Y se exceptua lo que cuelga de la carpeta de Windows: ahi dentro
    #     no vive nada del usuario, y el nombre puede coincidir por pura
    #     casualidad. Pasaba de verdad y era caro:
    #     C:\Windows\SoftwareDistribution\Download -la cache de Windows
    #     Update, "lo que más espacio recupera" según su propio módulo-
    #     termina en "Download", casaba con "downloads?" y quedaba vetada.
    #     El módulo hacia 'continue' sin registrar nada, así que el
    #     candidato no llegaba a existir y no aparecia ni un aviso: la
    #     función llevaba rota desde que existe este filtro.
    #
    #     La excepción es segura porque no relaja ninguno de los otros
    #     siete filtros: la lista negra del sistema, los fragmentos
    #     prohibidos y la lista blanca de raices del módulo siguen
    #     aplicandose igual a todo lo que hay bajo Windows.
    #     Y se comparan SIN tildes. ConvertTo-RutaNormalizada baja a
    #     minúsculas y unifica el separador, pero conserva los diacriticos,
    #     así que "D:\Imagenes" con tilde, "E:\Musica" con tilde y
    #     "F:\Videos" con tilde NO casaban con el patron y quedaban sin
    #     proteger: exactamente los tres ejemplos que este comentario
    #     presumia de cubrir, en un Windows en español, que es el idioma
    #     para el que esta escrito el programa. Se quitan las tildes solo
    #     del ÚLTIMO SEGMENTO y nunca de la ruta entera: los filtros 2, 3 y
    #     4 comparan texto contra rutas reales del sistema y dejarian de
    #     casar. Ver [SEG-10] en docs/PLAN-ACCION.md.
    $ultimoSegmento = $r.Substring($r.LastIndexOfAny([char[]]@('\', '/')) + 1)
    $segmentoSinTildes = (Remove-Tildes $ultimoSegmento).ToLowerInvariant()
    if ($script:RegexCarpetaPersonal.IsMatch($segmentoSinTildes)) {
        $raizWindows = ''
        if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
            $raizWindows = (ConvertTo-RutaNormalizada $env:SystemRoot).TrimEnd('\') + '\'
        }
        if ([string]::IsNullOrWhiteSpace($raizWindows) -or
            -not $r.StartsWith($raizWindows, [StringComparison]::OrdinalIgnoreCase)) {
            return "Es una carpeta personal por su nombre: $ultimoSegmento"
        }
    }

    # 5b. Carpetas de copia de seguridad en cualquier punto de la ruta.
    #     Aquí si se mira la ruta entera: una carpeta llamada "backup"
    #     contiene, por definición, lo que su dueño no quiere perder.
    if ($script:RegexCopiaSeguridad.IsMatch($conBarra)) {
        return 'Cuelga de una carpeta de copias de seguridad.'
    }

    return ''
}

function Test-RutaIntocable {
    <#
    .SYNOPSIS
        Devuelve $true si la ruta no se puede borrar bajo ningún concepto.
    .DESCRIPTION
        Envoltorio booleano de Get-MotivoIntocable. Ver esa función para
        el detalle de los filtros y el porque de la unificacion.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Ruta)

    return -not [string]::IsNullOrEmpty((Get-MotivoIntocable $Ruta))
}

function Test-NombreSensible {
    <#
    .SYNOPSIS
        Detecta nombres que sugieren datos críticos o irrecuperables.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Nombre)

    if (-not (Test-GuardiaLista)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Nombre)) { return $true }

    $n = (Remove-Tildes $Nombre).ToLowerInvariant()

    # Palabras largas: subcadena en cualquier posición. Son inequivocas y
    # varias son raices que deben casar con sus derivados.
    foreach ($palabra in $script:NombresSensiblesLargos) {
        if ($n.Contains($palabra)) { return $true }
    }

    # Palabras cortas: solo si empiezan en un limite. El detalle esta en
    # Initialize-Guardia, donde se construye la expresión. Ver [SEG-12].
    if ($null -ne $script:NombresSensiblesCortos -and $script:NombresSensiblesCortos.IsMatch($n)) {
        return $true
    }

    return $false
}

function Test-ArchivoPersonal {
    <#
    .SYNOPSIS
        Decide si un archivo parece trabajo del usuario y no basura.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Ruta)

    if (-not (Test-GuardiaLista)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $true }

    # Se parte a mano en lugar de usar [IO.Path]::GetFileName porque esa
    # función no reconoce la barra invertida cuando el código se analiza
    # desde un sistema que no es Windows (por ejemplo, en integración
    # continua o al ejecutar las pruebas en Linux).
    $corte     = $Ruta.LastIndexOfAny([char[]]@('\', '/'))
    $nombre    = if ($corte -ge 0) { $Ruta.Substring($corte + 1) } else { $Ruta }
    $extension = [IO.Path]::GetExtension($nombre).ToLowerInvariant()

    # Excepción explicita: basura conocida que casualmente lleva una
    # extensión de las protegidas.
    if ($script:NombresBasuraConocida -contains $nombre.ToLowerInvariant()) { return $false }

    # Lo mismo, pero por patron en vez de por nombre exacto: "~$nombre.ext"
    # es el archivo de control casi vacío que Word, Excel o PowerPoint
    # crean mientras el documento esta abierto. NO es el documento: el
    # contenido real sigue intacto en "nombre.ext", sin tocar. Sin esta
    # excepción, cualquier "~$factura.docx" quedaba protegido para
    # siempre por la extensión y el módulo de temporales no podia
    # proponer un solo archivo de bloqueo de Office real. El prefijo debe
    # ser EXACTO: un documento legitimo que empiece por "~" (p. ej.
    # "~ideas 2024.docx") sigue protegido con normalidad.
    if ($nombre.StartsWith('~$', [StringComparison]::Ordinal)) { return $false }

    if ($script:ExtensionesPersonales -contains $extension) { return $true }

    # Doble extensión: "Contrasenas.kdbx.bak" tiene extensión ".bak", así
    # que la comprobación anterior lo daba por basura y el módulo de
    # temporales lo proponia como "copia antigua". Lo mismo con
    # ".sqlite.bak", ".pst.bak", ".mdb.old" y ".docx.old": justo los
    # archivos que más duele perder, porque son la copia de seguridad de
    # algo importante. Si la extensión es de las que marcan "esto es un
    # descarte", se mira la que hay DEBAJO y se decide con esa.
    #
    # Un ".bak" cualquiera -"configuracion.bak", "salida.bak"- sigue siendo
    # proponible con normalidad: solo se protege el que esconde una
    # extensión personal. Ver [SEG-14] en docs/PLAN-ACCION.md.
    if ($extension -in @('.bak', '.old', '.tmp')) {
        $interior = [IO.Path]::GetExtension(
                        [IO.Path]::GetFileNameWithoutExtension($nombre)).ToLowerInvariant()
        if ($script:ExtensionesPersonales -contains $interior) { return $true }
    }

    # El patron tiene que CERRAR. Sin el grupo final era un prefijo suelto,
    # y un prefijo suelto protege de más: "image" bloqueaba imagecache.dat,
    # "document" bloqueaba documentdb.log y "cv" bloqueaba cualquier
    # cv*.tmp. Se admite separador, digito o final de nombre, para que
    # "Documento 3.tmp", "cv2024.tmp" y "foto_01.tmp" sigan protegidos.
    # Ver [SEG-13].
    if ($nombre -match '(?i)^(documento|document|foto|photo|imagen|image|backup|respaldo|copia|export|factura|contrato|curriculum|cv)([0-9 _\-.]|$)') {
        return $true
    }
    return $false
}

function Test-CarpetaEspejo {
    <#
    .SYNOPSIS
        Carpeta del sistema que parece vacía pero es un enlace heredado.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Nombre)

    if (-not (Test-GuardiaLista)) { return $true }
    return $script:CarpetasEspejo -contains (ConvertTo-Token $Nombre)
}

function Get-RaizQueContiene {
    <#
    .SYNOPSIS
        Devuelve la raiz autorizada de la que cuelga una ruta, o cadena
        vacia si no cuelga de ninguna.
    .DESCRIPTION
        La comparacion exige la barra final, de modo que la propia raiz
        nunca resulta borrable: solo lo que hay dentro de ella.

        Devuelve la raiz y no un si/no porque Test-CadenaSinEnlaces
        necesita saber DONDE parar de subir.

        Test-BajoRaiz es el envoltorio booleano de esta función. Ya no lo
        llama ningún sitio de produccion -todos necesitan la raiz, no el
        si/no- y se conserva a proposito porque es el contrato que fijan
        las pruebas de la guardia. Este comentario decia que "sigue
        existiendo para los sitios que solo quieren el booleano", y no hay
        tal sitio: en el archivo más importante del programa, un comentario
        que describe un uso inexistente es peor que no tener comentario.
        Ver [SEG-15] en docs/PLAN-ACCION.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]   $Ruta,
        [string[]] $Raices
    )

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return '' }
    if ($null -eq $Raices -or $Raices.Count -eq 0) { return '' }

    $r = ConvertTo-RutaNormalizada $Ruta
    foreach ($raiz in $Raices) {
        if ([string]::IsNullOrWhiteSpace($raiz)) { continue }
        $base = ConvertTo-RutaNormalizada $raiz
        # Ordinal por el mismo motivo que el filtro 3 de Get-MotivoIntocable:
        # esta comparacion decide si una ruta esta dentro de una raiz
        # autorizada, y con la cultura actual un carácter ignorable la
        # colaba dentro sin estarlo.
        if ($base -and $r.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { return $base }
    }
    return ''
}

function Test-BajoRaiz {
    <#
    .SYNOPSIS
        Comprueba que una ruta cuelga de alguna de las raices autorizadas.
    .DESCRIPTION
        OJO: esta comprobacion es SOLO DE TEXTO. Por si sola devuelve $true
        para una ruta con "..", y no sabe nada de enlaces. Nunca se llama
        suelta desde un modulo: se llama desde Test-RutaSegura, que antes
        ha pasado Test-RutaIntocable y despues comprueba la cadena de
        carpetas contra el disco.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]   $Ruta,
        [string[]] $Raices
    )

    return -not [string]::IsNullOrEmpty((Get-RaizQueContiene -Ruta $Ruta -Raices $Raices))
}

function Test-CadenaSinEnlaces {
    <#
    .SYNOPSIS
        Comprueba que ni una sola carpeta del camino entre la raiz
        autorizada y la ruta es un punto de reanalisis.

    .DESCRIPTION
        Este es el agujero que tapa esta funcion, y conviene entenderlo
        porque no es obvio:

        La lista blanca compara TEXTO. El sistema de archivos, en cambio,
        entiende de junctions y enlaces simbolicos, y Get-ChildItem -Recurse
        de Windows PowerShell 5.1 BAJA por ellos sin avisar. Asi que bastaba
        con que hubiera un enlace dentro de una zona autorizada para que
        todo lo que hay al otro lado pareciera estar dentro:

            mklink /J "%USERPROFILE%\Downloads\copia" "D:\Contabilidad"

        Eso no pide permisos de administrador. Lo puede crear el propio
        usuario, o cualquier programa que corra como el. A partir de ahi,
        "...\Downloads\copia\facturas\2025.xlsx" empieza por la raiz
        autorizada, y Test-RutaSegura decia que si. Peor todavia: la lista
        negra de fragmentos (\system32\, \.ssh\, \microsoft\crypto\)
        tambien compara texto, asi que un enlace la esquivaba igual.

        La comprobacion sube de la hoja hasta la raiz autorizada mirando
        los atributos REALES de cada carpeta. Si encuentra un reparse point
        por el camino, la ruta no esta donde dice estar y se rechaza.

        Coste: una llamada a Get-Item por nivel de profundidad. Frente a
        Measure-Ruta, que recorre el arbol entero, es ruido.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [Parameter(Mandatory)] [string] $Raiz
    )

    if ([string]::IsNullOrWhiteSpace($Raiz)) { return $false }
    $tope = ConvertTo-RutaNormalizada $Raiz

    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    # Si un tramo del camino no se puede leer, no se puede afirmar que sea
    # seguro. Se falla cerrado, como el resto de la guardia.
    if ($null -eq $item)     { return $false }
    if (Test-EsEnlace $item) { return $false }

    # Se sube con la propiedad Parent de .NET y NO partiendo la cadena con
    # Split-Path. Parece lo mismo y no lo es: partir texto se equivoca con
    # los nombres raros y obliga a adivinar cual es el separador, mientras
    # que Parent lo resuelve el propio sistema de archivos.
    $carpeta = if ($item.PSIsContainer) { $item } else { $item.Directory }

    # Tope de seguridad: ninguna ruta real tiene 260 niveles, y sin el un
    # enlace que apunte a un ancestro dejaria el bucle dando vueltas.
    for ($nivel = 0; $nivel -lt 260 -and $null -ne $carpeta; $nivel++) {
        if (Test-EsEnlace $carpeta) { return $false }
        if ((ConvertTo-RutaNormalizada $carpeta.FullName) -eq $tope) { return $true }
        $carpeta = $carpeta.Parent
    }
    # Se ha llegado a la raiz del disco sin encontrar la raiz autorizada:
    # la ruta no cuelga de donde decia colgar.
    return $false
}

function Test-RutaSegura {
    <#
    .SYNOPSIS
        Veredicto final: esta ruta se puede borrar con estas raices.
    .DESCRIPTION
        Es la única función que los módulos deben llamar. Combina la lista
        blanca de raices con todos los filtros de la lista negra y además
        consulta el estado real del disco (enlaces, tipo de elemento).

    .PARAMETER PermitirPersonales
        Levanta ÚNICAMENTE el veto por extensión personal. Existe para el
        módulo de duplicados, que es el único caso en el que borrar un
        archivo personal no pierde información: se ha comprobado por hash
        que existe otra copia identica y siempre se conserva la más
        antigua. Ningún otro módulo debe usar este parámetro.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]   $Ruta,
        [string[]] $Raices,
        [switch]   $PermitirPersonales
    )

    if (Test-RutaIntocable $Ruta) { return $false }

    $raizQueVale = Get-RaizQueContiene -Ruta $Ruta -Raices $Raices
    if ([string]::IsNullOrEmpty($raizQueVale)) { return $false }

    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    if ($null -eq $item)     { return $false }
    if (Test-EsEnlace $item) { return $false }

    # Y ahora lo que de verdad cierra la lista blanca: que NINGUNA carpeta
    # del camino sea un enlace. Sin esto, la pertenencia a una raiz es una
    # afirmacion sobre una cadena de texto, no sobre donde estan los bytes.
    # Ver Test-CadenaSinEnlaces.
    if (-not (Test-CadenaSinEnlaces -Ruta $Ruta -Raiz $raizQueVale)) { return $false }

    if (-not $PermitirPersonales -and
        -not $item.PSIsContainer -and
        (Test-ArchivoPersonal $item.FullName)) { return $false }
    return $true
}

function Get-MotivoBloqueo {
    <#
    .SYNOPSIS
        Explica en castellano por que la guardia ha rechazado una ruta.
    .DESCRIPTION
        Solo se usa para el registro y los informes: ayuda a auditar el
        comportamiento del programa sin tener que leer el código.

        Reutiliza Get-MotivoIntocable para los filtros incondicionales en
        vez de reimplementarlos: es la función equivalente a
        Test-RutaSegura, pero devolviendo el motivo en vez de un booleano.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]   $Ruta,
        [string[]] $Raices
    )

    $motivo = Get-MotivoIntocable $Ruta
    if ($motivo) { return $motivo }

    $raizQueVale = Get-RaizQueContiene -Ruta $Ruta -Raices $Raices
    if ([string]::IsNullOrEmpty($raizQueVale)) { return 'No cuelga de ninguna raiz autorizada por el módulo.' }

    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    if ($null -eq $item)     { return 'La ruta ya no existe.' }
    if (Test-EsEnlace $item) { return 'Es un enlace simbolico o junction.' }
    if (-not (Test-CadenaSinEnlaces -Ruta $Ruta -Raiz $raizQueVale)) {
        return 'Alguna carpeta del camino es un enlace: la ruta no esta donde parece.'
    }
    if (-not $item.PSIsContainer -and (Test-ArchivoPersonal $item.FullName)) {
        return 'Parece un archivo personal por su extensión o su nombre.'
    }
    return 'Sin bloqueo.'
}
