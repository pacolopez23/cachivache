<#
    Pruebas de la guardia de seguridad.

    Son las pruebas más importantes del proyecto: cada una describe una
    ruta que el programa NO debe borrar bajo ningún concepto. Si alguna
    falla, no se pública.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent

    # Entorno reproducible: las pruebas no dependen del equipo que las corre.
    $env:SystemDrive   = 'C:'
    $env:SystemRoot    = 'C:\Windows'
    $env:ProgramFiles  = 'C:\Program Files'
    ${env:ProgramFiles(x86)} = 'C:\Program Files (x86)'
    $env:ProgramData   = 'C:\ProgramData'
    $env:USERPROFILE   = 'C:\Users\prueba'
    $env:LOCALAPPDATA  = 'C:\Users\prueba\AppData\Local'
    $env:APPDATA       = 'C:\Users\prueba\AppData\Roaming'

    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    $script:Configuracion = [pscustomobject]@{
        Escritorio   = 'C:\Users\prueba\Desktop'
        Documentos   = 'C:\Users\prueba\Documents'
        Descargas    = 'C:\Users\prueba\Downloads'
        Imagenes     = 'C:\Users\prueba\Pictures'
        Musica       = 'C:\Users\prueba\Music'
        Videos       = 'C:\Users\prueba\Videos'
        CarpetaDatos = 'C:\Users\prueba\AppData\Local\Cachivache'
    }
    Initialize-Guardia -Configuracion $script:Configuracion
}

Describe 'Un enlace dentro de una raiz autorizada no saca el borrado fuera de ella' {

    <#
        El agujero que esto cierra:

        La lista blanca compara TEXTO ("esta ruta empieza por esta raiz"),
        pero el sistema de archivos entiende de junctions, y Get-ChildItem
        -Recurse de PowerShell 5.1 baja por ellas. Bastaba con esto, que no
        pide permisos de administrador:

            mklink /J "%USERPROFILE%\Downloads\copia" "D:\Contabilidad"

        para que D:\Contabilidad entrara en la zona borrable de seis
        modulos. Y como la lista negra de fragmentos (\system32\, \.ssh\)
        tambien compara texto, el enlace la esquivaba igual.

        Estas pruebas montan exactamente ese escenario. Si alguien vuelve a
        dejar la pertenencia en una comparacion de cadenas, caen.
    #>

    BeforeAll {
        Initialize-Guardia -Configuracion ([pscustomobject]@{
            Escritorio = ''; Documentos = ''; Descargas = ''
            Imagenes   = ''; Musica     = ''; Videos    = ''
            CarpetaDatos = ''
        })
    }

    BeforeEach {
        $script:Zona   = Join-Path ([IO.Path]::GetTempPath()) ('guardia_zona_'   + [Guid]::NewGuid())
        $script:Fuera  = Join-Path ([IO.Path]::GetTempPath()) ('guardia_fuera_'  + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Zona  -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Fuera 'privado') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Fuera 'privado\datos.tmp') -Value 'contabilidad'

        # El enlace, dentro de la zona autorizada, apuntando fuera.
        $script:Enlace = Join-Path $script:Zona 'copia'
        $script:HayEnlace = $null -ne (New-Item -ItemType SymbolicLink -Path $script:Enlace `
                                                -Target $script:Fuera -ErrorAction SilentlyContinue)
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Enlace -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Zona   -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Fuera  -Force -Recurse -ErrorAction SilentlyContinue
    }

    It 'lo que hay al otro lado del enlace NO se considera seguro' {
        if (-not $script:HayEnlace) { Set-ItResult -Skipped -Because 'no se pueden crear enlaces aqui'; return }

        $victima = Join-Path $script:Enlace 'privado\datos.tmp'
        Test-Path -LiteralPath $victima | Should -BeTrue -Because 'el enlace resuelve: el escenario es real'

        Test-RutaSegura $victima @($script:Zona) | Should -BeFalse
    }

    It 'y lo dice con todas las letras, no en silencio' {
        if (-not $script:HayEnlace) { Set-ItResult -Skipped -Because 'no se pueden crear enlaces aqui'; return }

        $victima = Join-Path $script:Enlace 'privado\datos.tmp'
        Get-MotivoBloqueo $victima @($script:Zona) | Should -Match 'enlace'
    }

    It 'la carpeta intermedia del enlace tampoco es segura' {
        if (-not $script:HayEnlace) { Set-ItResult -Skipped -Because 'no se pueden crear enlaces aqui'; return }

        Test-RutaSegura (Join-Path $script:Enlace 'privado') @($script:Zona) | Should -BeFalse
    }

    It 'un archivo normal de la misma zona SIGUE siendo borrable' {
        # Sin esto, la prueba anterior pasaria tambien con una guardia que
        # dijera que no a todo, que es la forma tonta de aprobar un examen
        # de seguridad.
        $normal = Join-Path $script:Zona 'temporal.tmp'
        Set-Content -LiteralPath $normal -Value 'basura'

        Test-RutaSegura $normal @($script:Zona) | Should -BeTrue
    }
}

Describe 'Test-RutaIntocable' {

    It 'bloquea la raiz de la unidad: <Ruta>' -ForEach @(
        @{ Ruta = 'C:' }
        @{ Ruta = 'C:\' }
        @{ Ruta = 'D:\' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea carpetas criticas del sistema: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\Windows' }
        @{ Ruta = 'C:\Windows\System32' }
        @{ Ruta = 'C:\Windows\System32\drivers' }
        @{ Ruta = 'C:\Windows\WinSxS' }
        @{ Ruta = 'C:\Windows\WinSxS\amd64_algo' }
        @{ Ruta = 'C:\Program Files' }
        @{ Ruta = 'C:\Program Files (x86)' }
        @{ Ruta = 'C:\ProgramData' }
        @{ Ruta = 'C:\ProgramData\Package Cache\algo' }
        @{ Ruta = 'C:\Program Files\WindowsApps' }
        @{ Ruta = 'C:\Users' }
        @{ Ruta = 'C:\System Volume Information' }
        @{ Ruta = 'C:\Recovery\algo' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea las carpetas personales en si mismas: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\Users\prueba' }
        @{ Ruta = 'C:\Users\prueba\Documents' }
        @{ Ruta = 'C:\Users\prueba\Desktop' }
        @{ Ruta = 'C:\Users\prueba\Downloads' }
        @{ Ruta = 'C:\Users\prueba\Pictures' }
        @{ Ruta = 'C:\Users\prueba\OneDrive' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea carpetas personales que no estan en el perfil: <Ruta>' -ForEach @(
        @{ Ruta = 'D:\Datos\Documentos' }
        @{ Ruta = 'E:\Fotos de la boda\Imagenes' }
        @{ Ruta = 'D:\Otro perfil\Escritorio' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea cualquier cosa bajo una carpeta de copias: <Ruta>' -ForEach @(
        @{ Ruta = 'D:\copias\backup\lo que sea' }
        @{ Ruta = 'C:\Users\prueba\Documents\Backup\enero' }
        @{ Ruta = 'D:\Respaldos\2024\enero' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'NO bloquea el contenido de las carpetas personales: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\Downloads\instalador.exe' }
        @{ Ruta = 'C:\Users\prueba\Documents\proyecto\node_modules' }
        @{ Ruta = 'C:\Users\prueba\Desktop\proyecto\dist' }
        @{ Ruta = 'C:\Users\prueba\Pictures\vacaciones' }
    ) {
        # Vetar todo lo que hay DENTRO de Descargas o Documentos dejaria
        # sin función a media docena de módulos. Lo que protege ese
        # contenido es la lista blanca de raices de cada módulo más el
        # veto por extensión, no un veto general por la ruta.
        Test-RutaIntocable $Ruta | Should -BeFalse
    }

    It 'bloquea las raices de AppData: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\AppData\Local' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\Microsoft' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming\Microsoft' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\Packages' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea material criptografico y de identidad: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\.ssh\id_rsa' }
        @{ Ruta = 'C:\Users\prueba\.gnupg\claves' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming\Microsoft\Crypto\RSA' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming\Microsoft\Protect\S-1-5' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\Microsoft\Vault\algo' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea recursos de red y travesias de ruta: <Ruta>' -ForEach @(
        @{ Ruta = '\\servidor\recurso\carpeta' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\..\..\..\Windows' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea rutas vacias, nulas o demasiado cortas: <Ruta>' -ForEach @(
        @{ Ruta = '' }
        @{ Ruta = $null }
        @{ Ruta = 'C:\tmp' }
        @{ Ruta = '   ' }
    ) { Test-RutaIntocable $Ruta | Should -BeTrue }

    It 'bloquea una ruta que CONTIENE una carpeta protegida' {
        # Borrar C:\Users se llevaria por delante el perfil entero.
        Test-RutaIntocable 'C:\Users' | Should -BeTrue
    }

    It 'permite cachees legitimas: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\AppData\Local\npm-cache' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\Temp' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming\discord\Cache' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\pip\Cache' }
    ) { Test-RutaIntocable $Ruta | Should -BeFalse }
}

Describe 'Get-MotivoIntocable / Test-RutaIntocable: equivalencia (C-08)' {
    <#
        Get-MotivoIntocable es ahora la ÚNICA fuente de verdad de los
        filtros incondicionales; Test-RutaIntocable es solo su envoltorio
        booleano. Este corpus reutiliza todas las rutas de los bloques de
        arriba (bloqueadas y permitidas) para comprobar que los dos nunca
        pueden discrepar: si algún día alguien reintroduce una copia
        separada de esta lógica, esta prueba lo detecta.
    #>

    It 'Test-RutaIntocable "<Ruta>" coincide siempre con [bool](Get-MotivoIntocable)' -ForEach @(
        @{ Ruta = 'C:' }
        @{ Ruta = 'C:\' }
        @{ Ruta = 'D:\' }
        @{ Ruta = 'C:\Windows' }
        @{ Ruta = 'C:\Windows\System32\drivers' }
        @{ Ruta = 'C:\Program Files' }
        @{ Ruta = 'C:\ProgramData\Package Cache\algo' }
        @{ Ruta = 'C:\Users' }
        @{ Ruta = 'C:\System Volume Information' }
        @{ Ruta = 'C:\Users\prueba' }
        @{ Ruta = 'C:\Users\prueba\Documents' }
        @{ Ruta = 'C:\Users\prueba\OneDrive' }
        @{ Ruta = 'D:\Datos\Documentos' }
        @{ Ruta = 'E:\Fotos de la boda\Imagenes' }
        @{ Ruta = 'D:\copias\backup\lo que sea' }
        @{ Ruta = 'C:\Users\prueba\Documents\Backup\enero' }
        @{ Ruta = 'C:\Users\prueba\Downloads\instalador.exe' }
        @{ Ruta = 'C:\Users\prueba\Documents\proyecto\node_modules' }
        @{ Ruta = 'C:\Users\prueba\Pictures\vacaciones' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\Packages' }
        @{ Ruta = 'C:\Users\prueba\.ssh\id_rsa' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming\Microsoft\Crypto\RSA' }
        @{ Ruta = '\\servidor\recurso\carpeta' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\..\..\..\Windows' }
        @{ Ruta = '' }
        @{ Ruta = $null }
        @{ Ruta = 'C:\tmp' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\npm-cache' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\Temp' }
        @{ Ruta = 'C:\Users\prueba\AppData\Roaming\discord\Cache' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\pip\Cache' }
    ) {
        $booleano = Test-RutaIntocable $Ruta
        $motivo   = Get-MotivoIntocable $Ruta
        $booleano | Should -Be (-not [string]::IsNullOrEmpty($motivo)) -Because "el motivo fue '$motivo'"
    }
}

Describe 'Get-MotivoBloqueo: ya no dice "Sin bloqueo" sobre una ruta bloqueada (C-08)' {
    <#
        Antes de la corrección, Get-MotivoBloqueo reimplementaba los
        filtros de Test-RutaIntocable por su cuenta y se había
        desincronizado: omitia la travesia con "..", el veto de carpeta
        personal por último segmento y el veto de copias de seguridad.
        Para una ruta rechazada por cualquiera de esos tres, el registro
        decia literalmente "Sin bloqueo." sobre una ruta que SI estaba
        bloqueada.
    #>

    It 'informa de la travesia de rutas, no "Sin bloqueo"' {
        $motivo = Get-MotivoBloqueo 'C:\Users\prueba\AppData\Local\..\..\..\Windows' @('C:\Users\prueba\AppData\Local')
        $motivo | Should -Not -Be 'Sin bloqueo.'
        $motivo | Should -BeLike '*travesia*'
    }

    It 'informa del veto de carpeta personal por ultimo segmento, no "Sin bloqueo"' {
        $motivo = Get-MotivoBloqueo 'D:\Datos\Documentos' @('D:\Datos')
        $motivo | Should -Not -Be 'Sin bloqueo.'
        $motivo | Should -BeLike '*personal*'
    }

    It 'informa del veto de carpetas de copia de seguridad, no "Sin bloqueo"' {
        $motivo = Get-MotivoBloqueo 'D:\copias\backup\lo que sea' @('D:\copias')
        $motivo | Should -Not -Be 'Sin bloqueo.'
        $motivo | Should -BeLike '*copias de seguridad*'
    }

    It 'sigue devolviendo "Sin bloqueo." para una ruta realmente permitida' {
        # Tiene que existir de verdad: Get-MotivoBloqueo, igual que
        # Test-RutaSegura, consulta el disco (tipo de elemento, enlaces).
        $carpeta = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-motivo-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        try {
            $archivo = Join-Path $carpeta 'instalador.exe'
            Set-Content -LiteralPath $archivo -Value 'x' -NoNewline

            $motivo = Get-MotivoBloqueo $archivo @($carpeta)
            $motivo | Should -Be 'Sin bloqueo.'
        } finally {
            Remove-Item -LiteralPath $carpeta -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'bloquea todo con un motivo explicito si la guardia no esta inicializada' {
        $sesion = [powershell]::Create()
        [void]$sesion.AddScript(@'
param($raiz)
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Format.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'FileSystem.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Guard.ps1')
Get-MotivoBloqueo 'C:\cualquier\cosa' @('C:\cualquier')
'@).AddArgument($script:Raiz)
        $resultado = $sesion.Invoke()
        $sesion.Dispose()

        $resultado[0] | Should -Not -Be 'Sin bloqueo.'
        $resultado[0] | Should -BeLike '*no se ha inicializado*'
    }
}

Describe 'Test-BajoRaiz' {

    It 'no considera borrable la propia raiz autorizada' {
        Test-BajoRaiz 'C:\Users\prueba\AppData\Local' @('C:\Users\prueba\AppData\Local') | Should -BeFalse
    }

    It 'acepta lo que cuelga de la raiz' {
        Test-BajoRaiz 'C:\Users\prueba\AppData\Local\npm-cache' @('C:\Users\prueba\AppData\Local') | Should -BeTrue
    }

    It 'rechaza lo que esta fuera de todas las raices' {
        Test-BajoRaiz 'C:\Otra\Cosa\Larga' @('C:\Users\prueba\AppData\Local') | Should -BeFalse
    }

    It 'no se deja enganyar por un prefijo parecido' {
        # AppData\LocalLow empieza igual que AppData\Local pero es otra carpeta.
        Test-BajoRaiz 'C:\Users\prueba\AppData\LocalLow\algo' @('C:\Users\prueba\AppData\Local') | Should -BeFalse
    }

    It 'rechaza cuando no hay ninguna raiz declarada' {
        Test-BajoRaiz 'C:\Users\prueba\AppData\Local\npm-cache' @() | Should -BeFalse
    }
}

Describe 'Test-NombreSensible' {

    It 'detecta datos criticos por el nombre: <Nombre>' -ForEach @(
        @{ Nombre = 'KeePass' }
        @{ Nombre = 'Bitwarden' }
        @{ Nombre = '1Password' }
        @{ Nombre = 'MiBackup2023' }
        @{ Nombre = 'Dropbox' }
        @{ Nombre = 'Kaspersky' }
        @{ Nombre = 'MetaMask' }
        @{ Nombre = 'Certificados' }
        @{ Nombre = 'Contrasenyas' }
        @{ Nombre = 'Thunderbird' }
    ) { Test-NombreSensible $Nombre | Should -BeTrue }

    It 'no marca nombres corrientes: <Nombre>' -ForEach @(
        @{ Nombre = 'AcmeLauncher' }
        @{ Nombre = 'ToolboxApp' }
        @{ Nombre = 'RenderCache' }
    ) { Test-NombreSensible $Nombre | Should -BeFalse }
}

Describe 'Test-ArchivoPersonal' {

    It 'protege el trabajo del usuario: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\x\tesis.docx' }
        @{ Ruta = 'C:\x\cuentas.xlsx' }
        @{ Ruta = 'C:\x\foto.jpg' }
        @{ Ruta = 'C:\x\video.mp4' }
        @{ Ruta = 'C:\x\claves.kdbx' }
        @{ Ruta = 'C:\x\correo.pst' }
        @{ Ruta = 'C:\x\partida.sav' }
        @{ Ruta = 'C:\x\factura-enero.pdf' }
        @{ Ruta = 'C:\x\certificado.pfx' }
    ) { Test-ArchivoPersonal $Ruta | Should -BeTrue }

    It 'no protege basura evidente: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\x\algo.tmp' }
        @{ Ruta = 'C:\x\cache.dat' }
        @{ Ruta = 'C:\x\Thumbs.db' }
    ) { Test-ArchivoPersonal $Ruta | Should -BeFalse }

    It 'no protege un archivo de bloqueo de Office pese a su extension personal: <Ruta>' -ForEach @(
        @{ Ruta = 'C:\x\~$tesis.docx' }
        @{ Ruta = 'C:\x\~$cuentas.xlsx' }
        @{ Ruta = 'C:\x\~$presentacion.pptx' }
    ) {
        # "~$nombre.ext" es el archivo de control casi vacío que crea Word
        # o Excel mientras el documento esta abierto: NO es el documento
        # real (ese sigue intacto en "nombre.ext"), así que no debería
        # quedar protegido solo por heredar la extensión. Sin esto, el
        # módulo de temporales nunca podia proponer un solo archivo de
        # bloqueo de Office de verdad: la guardia lo descartaba en
        # silencio. Ver [C-15] en docs/OPTIMIZACIONES.md.
        Test-ArchivoPersonal $Ruta | Should -BeFalse
    }

    It 'SI protege un documento cuyo nombre real empieza por algo parecido a "~$"' {
        # El prefijo tiene que ser EXACTO ("~$"), no solo "empezar por
        # virgulilla": un documento legitimo llamado "~ideas 2024.docx" no
        # es un archivo de bloqueo de Office y debe seguir protegido.
        Test-ArchivoPersonal 'C:\x\~ideas 2024.docx' | Should -BeTrue
    }
}

Describe 'Test-CarpetaEspejo' {

    It 'reconoce las carpetas espejo del sistema: <Nombre>' -ForEach @(
        @{ Nombre = 'Mis imagenes' }
        @{ Nombre = 'My Pictures' }
        @{ Nombre = 'Partidas guardadas' }
        @{ Nombre = 'Vinculos' }
        @{ Nombre = 'Favoritos' }
    ) { Test-CarpetaEspejo $Nombre | Should -BeTrue }

    It 'no marca una carpeta normal' {
        Test-CarpetaEspejo 'Capturas de pantalla' | Should -BeFalse
    }
}

Describe 'Test-RutaSegura sobre archivos reales' {

    BeforeAll {
        # Se trabaja sobre archivos de verdad porque Test-RutaSegura
        # consulta el disco: tipo de elemento y puntos de reanalisis.
        $script:Temporal = Join-Path ([IO.Path]::GetTempPath()) ("cachivache-pruebas-" + [Guid]::NewGuid())
        $script:Descargas = Join-Path $script:Temporal 'Downloads'
        New-Item -ItemType Directory -Path $script:Descargas -Force | Out-Null

        'x' | Set-Content -LiteralPath (Join-Path $script:Descargas 'instalador.exe')
        'x' | Set-Content -LiteralPath (Join-Path $script:Descargas 'tesis.docx')
        'x' | Set-Content -LiteralPath (Join-Path $script:Descargas 'basura.tmp')

        Initialize-Guardia -Configuracion $script:Configuracion
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Temporal -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'permite un instalador dentro de una raiz autorizada' {
        Test-RutaSegura -Ruta (Join-Path $script:Descargas 'instalador.exe') `
                        -Raices @($script:Descargas) | Should -BeTrue
    }

    It 'veta un documento personal aunque este en una raiz autorizada' {
        Test-RutaSegura -Ruta (Join-Path $script:Descargas 'tesis.docx') `
                        -Raices @($script:Descargas) | Should -BeFalse
    }

    It 'veta cualquier cosa fuera de las raices declaradas' {
        Test-RutaSegura -Ruta (Join-Path $script:Descargas 'basura.tmp') `
                        -Raices @('C:\Otro\Sitio\Distinto') | Should -BeFalse
    }

    It 'levanta el veto por extension solo con PermitirPersonales' {
        # Es la excepción del módulo de duplicados: existe otra copia
        # identica comprobada por hash, así que no se pierde información.
        $documento = Join-Path $script:Descargas 'tesis.docx'
        Test-RutaSegura -Ruta $documento -Raices @($script:Descargas)                      | Should -BeFalse
        Test-RutaSegura -Ruta $documento -Raices @($script:Descargas) -PermitirPersonales | Should -BeTrue
    }

    It 'PermitirPersonales NO levanta ningun otro filtro' {
        Test-RutaSegura -Ruta 'C:\Windows\System32\algo.dll' -Raices @('C:\Windows') `
                        -PermitirPersonales | Should -BeFalse
    }
}

Describe 'Guardia sin inicializar' {

    It 'bloquea absolutamente todo si no se ha llamado a Initialize-Guardia' {
        # Hace falta un runspace nuevo de verdad: dentro del mismo proceso
        # las listas ya estarian cargadas y la prueba no probaria nada.
        $sesion = [powershell]::Create()
        [void]$sesion.AddScript(@'
param($raiz)
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Format.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'FileSystem.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Guard.ps1')
[pscustomobject]@{
    Lista       = Test-GuardiaLista
    Intocable   = Test-RutaIntocable 'C:\Users\prueba\AppData\Local\npm-cache'
    Segura      = Test-RutaSegura 'C:\Users\prueba\AppData\Local\npm-cache' @('C:\Users\prueba\AppData\Local')
    Sensible    = Test-NombreSensible 'CualquierCosa'
    Personal    = Test-ArchivoPersonal 'C:\x\basura.tmp'
}
'@).AddArgument($script:Raiz)

        $resultado = $sesion.Invoke() | Select-Object -First 1
        $sesion.Dispose()

        $resultado.Lista     | Should -BeFalse
        $resultado.Intocable | Should -BeTrue
        $resultado.Segura    | Should -BeFalse
        $resultado.Sensible  | Should -BeTrue
        $resultado.Personal  | Should -BeTrue
    }
}

Describe 'El filtro de carpetas personales no puede vetar carpetas de Windows' {

    <#
        C:\Windows\SoftwareDistribution\Download -la cache de Windows
        Update, que es lo que más espacio recupera de todo el programa-
        termina en "Download" y casaba con el patron de carpetas
        personales. El módulo hacia 'continue' sin registrar nada, así que
        el candidato ni se creaba: la función llevaba rota desde que existe
        el filtro y nadie podia enterarse mirando la interfaz.
    #>

    BeforeAll {
        $script:SysRootOriginal = $env:SystemRoot
        if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { $env:SystemRoot = 'C:\Windows' }
        Initialize-Guardia -Configuracion ([pscustomobject]@{ Usuario = 'prueba' }) | Out-Null
    }

    AfterAll {
        $env:SystemRoot = $script:SysRootOriginal
    }

    It 'deja pasar <Ruta>, que esta bajo Windows' -ForEach @(
        @{ Ruta = 'C:\Windows\SoftwareDistribution\Download' }
        @{ Ruta = 'C:\Windows\Temp\Downloads' }
    ) {
        Get-MotivoIntocable -Ruta $Ruta |
            Should -Not -Match 'carpeta personal' -Because 'bajo Windows no vive nada del usuario'
    }

    It 'sigue vetando <Ruta>, que si es del usuario' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\Downloads' }
        @{ Ruta = 'C:\Users\prueba\Documentos' }
        @{ Ruta = 'D:\Fotos de la boda\Imagenes' }
        @{ Ruta = 'E:\copia\Escritorio' }
    ) {
        Get-MotivoIntocable -Ruta $Ruta |
            Should -Not -BeNullOrEmpty -Because 'una carpeta personal fuera de Windows sigue siendo intocable'
    }
}

Describe 'Las comprobaciones de prefijo de la guardia comparan caracteres, no idioma' {

    It 'un caracter ignorable no cuela una ruta dentro de una raiz autorizada' {
        # La sobrecarga StartsWith(string) compara con la cultura actual, que
        # IGNORA caracteres como el guion suave. Con ella,
        # "C:\raiz<guion suave>falsa\x" empezaba por "C:\raizfalsa\" y
        # Test-BajoRaiz devolvia $true para una ruta que no esta dentro.
        $blando = [char]0x00AD
        $fuera  = "C:\raiz${blando}falsa\algo\archivo.tmp"
        Test-BajoRaiz -Ruta $fuera -Raices @('C:\raizfalsa') |
            Should -BeFalse -Because 'la comparacion tiene que ser ordinal'
    }

    It 'una raiz de verdad sigue reconociendose' {
        Test-BajoRaiz -Ruta 'C:\raiz\algo\archivo.tmp' -Raices @('C:\raiz') | Should -BeTrue
    }
}

Describe 'Los dos puntos solo son travesia cuando son un segmento entero' {

    It 'acepta <Ruta>, que solo tiene dos puntos en el nombre' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\AppData\Local\proyecto v1..2\cache' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\algo\notas...tmp' }
    ) {
        Get-MotivoIntocable -Ruta $Ruta |
            Should -Not -Match 'travesia' -Because 'dos puntos dentro de un nombre no suben de carpeta'
    }

    It 'sigue rechazando <Ruta>, que si sube de carpeta' -ForEach @(
        @{ Ruta = 'C:\Users\prueba\AppData\..\..\..\Windows\System32' }
        @{ Ruta = 'C:\Users\prueba\AppData\Local\..' }
    ) {
        Get-MotivoIntocable -Ruta $Ruta | Should -Match 'travesia'
    }
}

Describe 'Fase 1: agujeros de la guardia corregidos' {

    <#
        Un Describe por hallazgo del plan de accion. Cada prueba de aqui
        FALLABA contra el codigo anterior: son la demostracion de que el
        arreglo hace algo, no un adorno.

        Este archivo es ASCII puro, asi que los caracteres acentuados se
        construyen por codigo. Es justo lo que hacia falta para destapar
        SEG-10: el fallo solo aparece con tildes de verdad.
    #>

    Context 'SEG-10: carpetas personales con tilde' {

        BeforeAll {
            $script:Acentuadas = @(
                @{ Ruta = 'D:\Im' + [char]0x00E1 + 'genes';        Que = 'Imagenes con tilde' }
                @{ Ruta = 'D:\M' + [char]0x00FA + 'sica';          Que = 'Musica con tilde' }
                @{ Ruta = 'D:\V' + [char]0x00ED + 'deos';          Que = 'Videos con tilde' }
                @{ Ruta = 'E:\Copias\Fotos\Im' + [char]0x00E1 + 'genes'; Que = 'Imagenes anidada' }
            )
        }

        It 'protege una carpeta personal aunque lleve tilde' {
            foreach ($caso in $script:Acentuadas) {
                Test-RutaIntocable $caso.Ruta |
                    Should -BeTrue -Because "$($caso.Que) es una carpeta personal y antes quedaba sin proteger"
            }
        }

        It 'sigue protegiendo las mismas carpetas escritas sin tilde' -ForEach @(
            @{ Ruta = 'D:\Imagenes' }
            @{ Ruta = 'D:\Musica' }
            @{ Ruta = 'D:\Videos' }
            @{ Ruta = 'D:\Documentos' }
        ) { Test-RutaIntocable $Ruta | Should -BeTrue }

        It 'no protege de mas: una carpeta que solo EMPIEZA por el nombre sigue siendo candidata' {
            $ruta = 'C:\Users\prueba\AppData\Local\Imagenes de sistema\cache'
            Test-RutaIntocable $ruta |
                Should -BeFalse -Because 'el filtro mira el ultimo segmento completo, no un prefijo'
        }
    }

    Context 'SEG-12: nombres sensibles anclados' {

        It 'deja de vetar "<Nombre>", que no tiene nada de sensible' -ForEach @(
            @{ Nombre = 'Presets';        Porque = 'contiene "eset" pero no es ESET' }
            @{ Nombre = 'Reset Tool';     Porque = 'contiene "eset" en medio de una palabra' }
            @{ Nombre = 'Omega Launcher'; Porque = 'contiene "mega" dentro de Omega' }
            @{ Nombre = 'Autoclave';      Porque = 'contiene "clave" dentro de otra palabra' }
            @{ Nombre = 'RefreshToken Cache'; Porque = 'contiene "token" pegado a otra palabra' }
        ) { Test-NombreSensible $Nombre | Should -BeFalse -Because $Porque }

        It 'sigue vetando "<Nombre>", que si lo es' -ForEach @(
            @{ Nombre = 'ESET Security' }
            @{ Nombre = 'MEGAsync' }
            @{ Nombre = 'Clave PIN' }
            @{ Nombre = 'AVG Antivirus' }
            @{ Nombre = 'Bitdefender' }
            @{ Nombre = 'KeePass' }
            @{ Nombre = 'Certificados FNMT' }
            @{ Nombre = 'Mi Backup' }
        ) { Test-NombreSensible $Nombre | Should -BeTrue }
    }

    Context 'SEG-13: el patron de nombre personal cierra' {

        It 'deja de proteger "<Nombre>", que solo comparte prefijo' -ForEach @(
            @{ Nombre = 'C:\Users\prueba\AppData\Local\app\imagecache.dat' }
            @{ Nombre = 'C:\Users\prueba\AppData\Local\app\documentdb.log' }
            @{ Nombre = 'C:\Users\prueba\AppData\Local\app\cvsdriver.tmp' }
        ) { Test-ArchivoPersonal $Nombre | Should -BeFalse }

        It 'sigue protegiendo "<Nombre>"' -ForEach @(
            @{ Nombre = 'C:\Users\prueba\Documents\Documento 3.tmp' }
            @{ Nombre = 'C:\Users\prueba\Documents\cv2024.tmp' }
            @{ Nombre = 'C:\Users\prueba\Documents\foto_01.tmp' }
            @{ Nombre = 'C:\Users\prueba\Documents\factura.tmp' }
        ) { Test-ArchivoPersonal $Nombre | Should -BeTrue }
    }

    Context 'SEG-14: doble extension' {

        It 'protege "<Nombre>", que esconde una extension personal bajo .bak o .old' -ForEach @(
            @{ Nombre = 'C:\Users\prueba\Documents\Contrasenas.kdbx.bak' }
            @{ Nombre = 'C:\Users\prueba\Documents\correo.pst.bak' }
            @{ Nombre = 'C:\Users\prueba\Documents\datos.sqlite.bak' }
            @{ Nombre = 'C:\Users\prueba\Documents\memoria.docx.old' }
            @{ Nombre = 'C:\Users\prueba\Pictures\boda.jpg.tmp' }
        ) {
            Test-ArchivoPersonal $Nombre |
                Should -BeTrue -Because 'la copia de seguridad de algo importante es tan importante como el original'
        }

        It 'no protege de mas: un .bak sin extension personal debajo sigue siendo candidato' -ForEach @(
            @{ Nombre = 'C:\Users\prueba\AppData\Local\app\configuracion.bak' }
            @{ Nombre = 'C:\Users\prueba\AppData\Local\app\salida.old' }
            @{ Nombre = 'C:\Users\prueba\AppData\Local\app\registro.log.bak' }
        ) { Test-ArchivoPersonal $Nombre | Should -BeFalse }

        It 'la excepcion de basura conocida sigue mandando sobre todo lo demas' {
            Test-ArchivoPersonal 'C:\Users\prueba\Documents\desktop.ini.bak' | Should -BeFalse
        }
    }

    Context 'SEG-16: profundidad en vez de longitud' {

        It 'acepta "<Ruta>", que antes se vetaba solo por ser corta de escribir' -ForEach @(
            @{ Ruta = 'D:\Juegos\Steam' }
            @{ Ruta = 'E:\Games\Old' }
            @{ Ruta = 'F:\a\b' }
        ) {
            Test-RutaIntocable $Ruta |
                Should -BeFalse -Because 'cuelga de algo: no es una carpeta de primer nivel de la unidad'
        }

        It 'sigue rechazando "<Ruta>", que cuelga de la raiz' -ForEach @(
            @{ Ruta = 'C:\tmp' }
            @{ Ruta = 'D:\Juegos' }
            @{ Ruta = 'C:\' }
        ) { Test-RutaIntocable $Ruta | Should -BeTrue }
    }
}

Describe 'SEG-11: un Initialize-Guardia a medias no deja la guardia entornada' {

    It 'si la inicializacion falla a mitad, la guardia bloquea todo' {
        # Runspace nuevo: dentro de este proceso las listas ya estan
        # cargadas y la prueba no probaria nada. Se hace fallar a
        # Initialize-Guardia despues de la PRIMERA lista, que es justo el
        # estado en el que antes se daba por lista.
        $sesion = [powershell]::Create()
        [void]$sesion.AddScript(@'
param($raiz)
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Format.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Texto.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'FileSystem.ps1')
. (Join-Path (Join-Path (Join-Path $raiz 'src') 'Core') 'Guard.ps1')

# Configuracion que revienta al leer la tercera carpeta personal: simula
# un fallo a mitad de la inicializacion.
$configuracion = [pscustomobject]@{ Escritorio = 'C:\x'; Documentos = 'C:\y' }
try { Initialize-Guardia -Configuracion $configuracion } catch { }

# Se fuerza el estado exacto del fallo antiguo: primera lista puesta,
# resto sin poner.
$script:GuardiaLista = $false

[pscustomobject]@{
    Lista    = Test-GuardiaLista
    Personal = Test-ArchivoPersonal 'C:\Users\prueba\Documents\memoria.docx'
    Sensible = Test-NombreSensible 'CualquierCosa'
}
'@).AddArgument($script:Raiz)

        $resultado = $sesion.Invoke() | Select-Object -First 1
        $sesion.Dispose()

        $resultado.Lista    | Should -BeFalse
        $resultado.Personal | Should -BeTrue -Because 'sin guardia completa, todo archivo se considera personal'
        $resultado.Sensible | Should -BeTrue -Because 'sin guardia completa, todo nombre se considera sensible'
    }
}
