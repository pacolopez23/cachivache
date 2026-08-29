<#
    Pruebas del motor de borrado (Remove.ps1). Empieza por el método
    'Comando': es el único camino de ejecución de código del programa y,
    hasta [C-03], no tenia ni una sola prueba dedicada. Ver
    docs/OPTIMIZACIONES.md (P-01).
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

    # Write-Registro sin -Sync escribe al momento y, si nadie ha llamado
    # antes a Initialize-Registro, usa Get-CarpetaDatos por defecto, que
    # depende de %LOCALAPPDATA%/%TEMP%. En este sandbox ninguna de las dos
    # esta definida, así que se fija una carpeta de prueba explicita.
    $script:CarpetaRegistroPruebas = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:CarpetaRegistroPruebas -Force | Out-Null
    Initialize-Registro -CarpetaDatos $script:CarpetaRegistroPruebas | Out-Null
}

Describe "Invoke-EliminacionCandidato con Metodo 'Comando' (C-03)" {

    It 'un ejecutable fuera de la lista blanca NUNCA llega a Start-Process' {
        Mock Start-Process {}
        Mock Resolve-EjecutablePermitido { $null }

        $candidato = New-Candidato -ModuloId 'prueba' -Categoria 'Prueba' -Nombre 'Prueba' `
            -Ruta 'algo que no es una ruta' -Metodo 'Comando' `
            -Ejecutable 'powershell' -Argumentos @('-Command', 'Write-Host hola')

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        Should -Invoke Start-Process -Times 0 -Exactly
        $candidato.Error | Should -Match 'no permitido'
    }

    It 'la ruta "ya no existe" ya NO bloquea Comando: antes impedia ejecutar el comando de Docker (bug encontrado en C-03)' {
        # Antes de esta corrección, el candidato de "docker system prune"
        # usaba una Ruta que no es una ruta real ("docker system prune"),
        # y el chequeo generico "Test-Path $Candidato.Ruta" de más arriba
        # bloqueaba SIEMPRE ese candidato con "La ruta ya no existe": el
        # comando de Docker nunca llegaba a ejecutarse. Esta prueba fija
        # que 'Comando' esta exento de ese chequeo.
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Resolve-EjecutablePermitido { 'C:\Program Files\Docker\docker.exe' }

        $candidato = New-Candidato -ModuloId 'dockerwsl' -Categoria 'WSL y Docker' -Nombre 'Prueba' `
            -Ruta 'docker system prune' -Metodo 'Comando' `
            -Ejecutable 'docker' -Argumentos @('system', 'prune', '-a', '-f')

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        Should -Invoke Start-Process -Times 1 -Exactly
        $candidato.Error | Should -BeNullOrEmpty
    }

    It 'pasa los argumentos como ARRAY a Start-Process, nunca como una cadena unica de shell' {
        # -ArgumentList con un array: cada elemento llega como argumento
        # nativo del proceso. Si en vez de eso se uniera todo en una sola
        # cadena habría que fiarse otra vez de que nadie meta '&', '|' o
        # '%VAR%' en un argumento.
        $script:argumentosRecibidos = $null
        Mock Start-Process {
            $script:argumentosRecibidos = $ArgumentList
            [pscustomobject]@{ ExitCode = 0 }
        }
        Mock Resolve-EjecutablePermitido { 'C:\Windows\System32\Dism.exe' }

        $candidato = New-Candidato -ModuloId 'componentes' -Categoria 'Prueba' -Nombre 'Prueba' `
            -Ruta (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())) -Metodo 'Comando' `
            -Ejecutable 'dism' -Argumentos @('/Online', '/Cleanup-Image', '/StartComponentCleanup')

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        $script:argumentosRecibidos | Should -Be @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
    }

    It 'un codigo de salida distinto de cero se refleja en Candidato.Error' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 87 } }
        Mock Resolve-EjecutablePermitido { 'C:\Program Files\Docker\docker.exe' }

        $candidato = New-Candidato -ModuloId 'dockerwsl' -Categoria 'Prueba' -Nombre 'Prueba' `
            -Ruta 'docker system prune' -Metodo 'Comando' `
            -Ejecutable 'docker' -Argumentos @('system', 'prune', '-a', '-f')

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        $candidato.Error | Should -Match '87'
    }

    It 'registra el comando y el codigo de salida con -Sync, en vez de perderse en Write-Verbose' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Resolve-EjecutablePermitido { 'C:\Program Files\Docker\docker.exe' }

        $sync = New-EstadoSincronizado
        $candidato = New-Candidato -ModuloId 'dockerwsl' -Categoria 'Prueba' -Nombre 'Prueba' `
            -Ruta 'docker system prune' -Metodo 'Comando' `
            -Ejecutable 'docker' -Argumentos @('system', 'prune', '-a', '-f')

        Invoke-EliminacionCandidato -Candidato $candidato -Sync $sync -Confirm:$false | Out-Null

        $sync.ColaRegistro.IsEmpty | Should -BeFalse
        $lineas = @()
        $linea = $null
        while ($sync.ColaRegistro.TryDequeue([ref] $linea)) { $lineas += $linea }
        ($lineas -join "`n") | Should -Match 'docker'
        ($lineas -join "`n") | Should -Match 'código de salida 0'
    }
}

# ---------------------------------------------------------------------
#  Movidos desde Core.Tests.ps1: prueban Remove.ps1, no el nucleo en
#  general. Ver docs/ESTRUCTURA.md (sección 12).
# ---------------------------------------------------------------------

Describe 'Remove-Elemento respeta -Permanente (C-01)' {
    <#
        Antes de esta corrección, Clear-ContenidoCarpeta llamaba a
        Remove-Item -Force en sus hojas sin mirar -Permanente en absoluto:
        todo se borraba de forma permanente aunque el usuario tuviera
        marcada la papelera. Estas pruebas fijan el contrato para que no
        pueda volver a pasar sin que la suite lo note.
    #>

    It 'con -Permanente borra con Remove-Item' {
        Mock Remove-Item {}
        Remove-Elemento -Ruta 'C:\ruta\de\prueba\hoja.txt' -EsCarpeta $false -Permanente -Confirm:$false | Out-Null
        Should -Invoke Remove-Item -Times 1 -Exactly
    }

    It 'SIN -Permanente NUNCA llama a Remove-Item: debe ir por la papelera' {
        Mock Remove-Item {}
        # En este sandbox no hay shell de Windows, así que la llamada a la
        # papelera fallara y Remove-Elemento devolvera $false. Lo que nos
        # interesa comprobar es que jamas se intenta un borrado permanente.
        Remove-Elemento -Ruta 'C:\ruta\de\prueba\hoja.txt' -EsCarpeta $false -Confirm:$false | Out-Null
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}

Describe 'Clear-ContenidoCarpeta respeta -Permanente en las hojas (C-01)' {

    BeforeEach {
        $script:carpetaPrueba = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-test-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaPrueba -Force | Out-Null
        # Extensión deliberadamente NO personal (".txt" esta en la lista de
        # ExtensionesPersonales de la guardia y Clear-ContenidoCarpeta la
        # respeta siempre, así que un ".txt" de prueba no se borraria nunca
        # y la prueba no probaria lo que queremos probar).
        Set-Content -LiteralPath (Join-Path $script:carpetaPrueba 'hoja.cache') -Value 'contenido'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaPrueba -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'con -Permanente borra el archivo de verdad y conserva la carpeta' {
        Clear-ContenidoCarpeta -Ruta $script:carpetaPrueba -Permanente -Confirm:$false

        Test-Path -LiteralPath (Join-Path $script:carpetaPrueba 'hoja.cache') | Should -BeFalse
        Test-Path -LiteralPath $script:carpetaPrueba                          | Should -BeTrue
    }

    It 'SIN -Permanente no llama a Remove-Item sobre la hoja' {
        Mock Remove-Item {}
        Clear-ContenidoCarpeta -Ruta $script:carpetaPrueba -Confirm:$false
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}

Describe 'Invoke-EliminacionCandidato: la espera solo aplica a metodos que vacian contenido (R-01)' {
    <#
        Antes: Start-Sleep -Milliseconds 200 se ejecutaba SIEMPRE, incluso
        para el método 'Ruta', donde el archivo o la carpeta ya no existen
        y esperar no aporta nada. Con 500 elementos eran 100 s de espera
        pura. Ahora solo espera (50 ms) para los métodos que vacian
        contenido, que son los únicos donde el contenedor sigue vivo.
    #>

    BeforeEach {
        Mock Test-RutaSegura { $true }
        Mock Measure-Ruta { 0 }
        Mock Clear-ContenidoCarpeta {}
        Mock Remove-RutaSegura { $true }
        Mock Start-Sleep {}

        $script:carpetaR01 = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-r01-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaR01 -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaR01 -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'NO espera para el metodo Ruta: la carpeta ya no existe' {
        $candidato = New-Candidato -ModuloId 'x' -Categoria 'c' -Nombre 'n' -Ruta $script:carpetaR01 -Metodo 'Ruta'
        $candidato.Raices = @($script:carpetaR01)

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'SI espera 50 ms para el metodo Contenido: el contenedor sigue vivo' {
        $candidato = New-Candidato -ModuloId 'x' -Categoria 'c' -Nombre 'n' -Ruta $script:carpetaR01 -Metodo 'Contenido'
        $candidato.Raices = @($script:carpetaR01)

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 50 }
    }
}

Describe 'Invoke-EliminacionCandidato: ForzarPermanente solo lo activan los modulos de cache (C-01)' {

    BeforeEach {
        Mock Test-RutaSegura { $true }
        Mock Measure-Ruta { 0 }
        Mock Clear-ContenidoCarpeta {}

        # Test-Path real necesita que la ruta exista de verdad: se crea una
        # carpeta temporal en vez de usar una ruta de Windows inventada,
        # porque estas pruebas también corren en Linux dentro de la CI.
        $script:carpetaCandidato = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-test-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:carpetaCandidato -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:carpetaCandidato -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'un candidato de cache (ForzarPermanente) borra permanente aunque el usuario no lo pida' {
        $candidato = New-Candidato -ModuloId 'caches' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:carpetaCandidato -Metodo 'Contenido' -ForzarPermanente
        $candidato.Raices = @($script:carpetaCandidato)

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        Should -Invoke Clear-ContenidoCarpeta -Times 1 -Exactly -ParameterFilter { $Permanente -eq $true }
    }

    It 'un candidato normal respeta la preferencia del usuario (sin -Permanente, va a la papelera)' {
        $candidato = New-Candidato -ModuloId 'otro' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:carpetaCandidato -Metodo 'Contenido'
        $candidato.Raices = @($script:carpetaCandidato)

        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        Should -Invoke Clear-ContenidoCarpeta -Times 1 -Exactly -ParameterFilter { $Permanente -eq $false }
    }

    It 'un candidato normal SI respeta -Permanente cuando el usuario lo pide' {
        $candidato = New-Candidato -ModuloId 'otro' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:carpetaCandidato -Metodo 'Contenido'
        $candidato.Raices = @($script:carpetaCandidato)

        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        Should -Invoke Clear-ContenidoCarpeta -Times 1 -Exactly -ParameterFilter { $Permanente -eq $true }
    }
}

Describe 'Medicion honesta del espacio liberado (C-18, C-06)' {
    <#
        Dos fallos que se tapaban entre ellos:
        - [C-18] $antes salia del tamaño estimado en el análisis, que puede
          tener horas, en vez de medirse justo antes de borrar.
        - [C-06] el candidato de Firefox declara Ruta = la carpeta de
          perfiles entera pero Bytes = solo los cache2, así que al restar
          salia negativo (se forzaba a 0) y además se avisaba de que
          "quedaban" 600 MB que en realidad son marcadores y cookies.
    #>

    BeforeEach {
        # La raiz autorizada es la carpeta PADRE: la guardia nunca considera
        # borrable la propia raiz, solo lo que cuelga de ella. Es el mismo
        # patron que usan los módulos reales.
        $script:raiz = Join-Path ([IO.Path]::GetTempPath()) ('c06-' + [guid]::NewGuid())
        $script:base = Join-Path $script:raiz 'objetivo'
        New-Item -ItemType Directory -Path $script:base -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:raiz -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'mide justo antes de borrar y no se cree el tamanyo del analisis' {
        # El candidato declara 1 byte, pero en disco hay bastante más: si se
        # midiera de verdad, lo liberado debe reflejar lo que había AHORA.
        $archivo = Join-Path $script:base 'grande.cache'
        Set-Content -LiteralPath $archivo -Value ('x' * 5000)

        $candidato = New-Candidato -ModuloId 'p' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:base -Bytes 1 -Metodo 'Contenido'
        $candidato.Raices = @($script:raiz)

        $liberado = Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false

        $liberado | Should -BeGreaterThan 1000 -Because 'debe informar de lo que habia en disco, no del 1 byte estimado'
    }

    It 'un metodo parcial no avisa de que "queda algo": deja cosas atras a proposito' {
        # Se simula la forma del candidato de Firefox: la ruta contiene mucho
        # más de lo que el método va a tocar.
        $cache = Join-Path $script:base 'cache2'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cache 'datos.cache') -Value ('x' * 3000)
        # Esto NO se toca y pesa más de 1 MB: antes disparaba el aviso falso.
        Set-Content -LiteralPath (Join-Path $script:base 'marcadores.sqlite') -Value ('y' * 1200000)

        $candidato = New-Candidato -ModuloId 'caches' -Categoria 'c' -Nombre 'Cache de Firefox' `
                                   -Ruta $script:base -Metodo 'FirefoxCache'
        $candidato.Raices = @($script:raiz)

        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        $candidato.Error | Should -BeNullOrEmpty -Because 'los marcadores que quedan no son un fallo, son lo que se queria conservar'
    }

    It 'un metodo que SI debe vaciarlo todo sigue avisando si queda algo' {
        # La contrapartida: no se ha desactivado el aviso en general.
        $sub = Join-Path $script:base 'sub'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sub 'documento.txt') -Value ('z' * 1200000)

        $candidato = New-Candidato -ModuloId 'p' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:base -Metodo 'Contenido'
        $candidato.Raices = @($script:raiz)

        # .txt es extensión personal: la guardia lo salta, así que queda ahi
        # y el aviso debe aparecer.
        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        $candidato.Error | Should -Match 'Quedan'
    }
}

Describe "El metodo CarpetaVacia revalida que sigue vacia antes de borrar (C-09)" {
    <#
        Este método borra un ARBOL entero de una vez. Entre el análisis y el
        borrado pueden pasar minutos, y en ese hueco un programa puede dejar
        un archivo dentro. La guardia válida la ruta, pero no sabe nada de si
        esta vacía: sin esta comprobación, el borrado recursivo se llevaria
        por delante un archivo que nadie propuso borrar.
    #>

    BeforeEach {
        $script:raizCv = Join-Path ([IO.Path]::GetTempPath()) ('cv-' + [guid]::NewGuid())
        $script:arbol  = Join-Path $script:raizCv 'padre'
        New-Item -ItemType Directory -Path (Join-Path $script:arbol 'hija') -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:raizCv -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'borra el arbol entero cuando de verdad sigue vacio' {
        $candidato = New-Candidato -ModuloId 'vacias' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:arbol -Metodo 'CarpetaVacia'
        $candidato.Raices = @($script:raizCv)

        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        Test-Path -LiteralPath $script:arbol | Should -BeFalse
        $candidato.Error | Should -BeNullOrEmpty
    }

    It 'NO borra nada si ha aparecido un archivo desde el analisis' {
        # Simula la carrera: el candidato se creo cuando estaba vacío, pero
        # ahora hay un archivo en el nivel de abajo.
        $candidato = New-Candidato -ModuloId 'vacias' -Categoria 'c' -Nombre 'n' `
                                   -Ruta $script:arbol -Metodo 'CarpetaVacia'
        $candidato.Raices = @($script:raizCv)

        $intruso = Join-Path (Join-Path $script:arbol 'hija') 'aparecido.dat'
        Set-Content -LiteralPath $intruso -Value 'no me borres'

        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        Test-Path -LiteralPath $intruso     | Should -BeTrue  -Because 'nadie propuso borrar este archivo'
        Test-Path -LiteralPath $script:arbol | Should -BeTrue
        $candidato.Error | Should -Match 'Ya no está vacía'
    }
}

Describe 'SEG-20: "Hecho" no puede afirmar que se borro algo que fallo' {

    <#
        El peor fallo del programa: Hecho se calculaba ANTES de consolidar
        $script:UltimoError, donde aterrizan los fallos reales de borrado.
        Un Remove-Item denegado dejaba Hecho a $true con Error relleno, y a
        partir de ahi mentian los tres sitios que leen ese campo: el
        contador de la CLI, la columna "Eliminado" del CSV y los bytes del
        historial. Un programa cuya razon de ser es dejar constancia de lo
        que borro no puede equivocarse justo en eso.
    #>

    BeforeAll {
        # Todo cuelga de un mismo padre y se limpia en el AfterAll, no en
        # un AfterEach. Los mocks de un It siguen vivos durante SU
        # desmontaje, asi que un AfterEach que llame a Remove-Item choca
        # con el mock que esta prueba necesita instalar. El AfterAll del
        # Describe si queda fuera de su alcance.
        $script:padre = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-hecho-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:padre -Force | Out-Null
    }

    AfterAll {
        Remove-Item -LiteralPath $script:padre -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:carpeta = Join-Path $script:padre ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:carpeta -Force | Out-Null
        $script:archivo = Join-Path $script:carpeta 'basura.tmp'
        Set-Content -LiteralPath $script:archivo -Value ('x' * 4096) -NoNewline
    }

    It 'un borrado que falla NO se marca como hecho' {
        # Sin -ParameterFilter: el mock aplica a todo lo que ocurra dentro
        # de este It, que es solo el borrado que se esta probando. La
        # limpieza vive en el AfterAll del Describe, fuera de su alcance.
        Mock Remove-Item { throw 'Acceso denegado' }

        $candidato = New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'basura' `
                                   -Ruta $script:archivo -Bytes 4096 -Metodo 'Ruta' `
                                   -Raices @($script:carpeta)
        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        $candidato.Error | Should -Not -BeNullOrEmpty -Because 'el fallo se registra'
        $candidato.Hecho | Should -BeFalse -Because 'no se ha borrado nada, por mucho que el motor lo intentara'
    }

    It 'un borrado que funciona sigue marcandose como hecho' {
        $candidato = New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'basura' `
                                   -Ruta $script:archivo -Bytes 4096 -Metodo 'Ruta' `
                                   -Raices @($script:carpeta)
        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        $candidato.Error | Should -BeNullOrEmpty
        $candidato.Hecho | Should -BeTrue
    }

    It 'una rama que declina actuar tampoco se marca como hecha' {
        # 'Comando' con un ejecutable fuera de la lista blanca: la rama
        # rellena Error y no ejecuta nada.
        $candidato = New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'comando' `
                                   -Ruta 'algo que no es una ruta' -Metodo 'Comando' `
                                   -Ejecutable 'formatear' -Argumentos @('todo')
        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        $candidato.Error | Should -Match 'no permitido'
        $candidato.Hecho | Should -BeFalse
    }

    It 'un resultado PARCIAL si cuenta como hecho: se ejecuto y libero espacio' {
        # Distinguir "no se ha ejecutado" de "se ejecuto y quedan archivos
        # en uso" es justo lo que evita corregir el fallo hacia el otro
        # lado. Aqui el borrado corre y deja la carpeta vacia, asi que no
        # hay aviso de "quedan"; lo que se comprueba es que el camino
        # normal de 'Contenido' sigue marcandose hecho.
        $candidato = New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'carpeta' `
                                   -Ruta $script:carpeta -Bytes 4096 -Metodo 'Contenido' `
                                   -Raices @((Split-Path $script:carpeta -Parent))
        Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false | Out-Null

        $candidato.Hecho | Should -BeTrue
    }
}

Describe 'SEG-21: el metodo NpmClean ya no existe' {

    It 'New-Candidato rechaza el metodo' {
        { New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'n' -Ruta 'C:\x\y' -Metodo 'NpmClean' } |
            Should -Throw -Because 'se elimino con su rama del motor: resolvia npm.cmd y eso pasa por cmd.exe'
    }

    It 'ningun modulo declara ya el metodo' {
        # Solo el USO real, no las menciones en comentarios: el motivo por
        # el que se quito esta explicado en Remove.ps1 y en Comandos.ps1, y
        # esa explicacion tiene que poder seguir escrita.
        $carpeta = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $usos = @(
            Get-ChildItem -LiteralPath $carpeta -Recurse -Filter '*.ps1' |
            Where-Object {
                (Get-Content -LiteralPath $_.FullName -Raw) -match "M\s*=\s*'NpmClean'"
            }
        )
        $usos.Count | Should -Be 0
    }

    It 'la cache de npm se sigue proponiendo' {
        $modulo = Get-ModuloLimpieza -Id 'caches' -Raiz (Split-Path $PSScriptRoot -Parent)
        $modulo | Should -Not -BeNullOrEmpty
        $texto = Get-Content -LiteralPath $modulo.Archivo -Raw
        $texto | Should -Match 'npm-cache' -Because 'quitar el metodo no quita la entrada'
    }
}

Describe 'FAL-15: dentro de una cache declarada si se borran los .db' {

    <#
        El veto por extension personal protege documentos, y fuera de una
        cache es imprescindible. Dentro hacia que el programa mintiera:
        una cache de navegador o de aplicacion es casi toda SQLite -o sea
        archivos .db, que estan en la lista de extensiones personales-,
        asi que se anunciaban 600 MB, se saltaba casi todo, y luego se
        culpaba a "archivos en uso por algun programa abierto".
    #>

    BeforeAll {
        $script:padreCache = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-cache-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:padreCache -Force | Out-Null
    }

    AfterAll {
        Remove-Item -LiteralPath $script:padreCache -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:cache = Join-Path $script:padreCache ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:cache -Force | Out-Null
        foreach ($nombre in @('indice.db', 'notas.txt', 'datos.bin')) {
            Set-Content -LiteralPath (Join-Path $script:cache $nombre) -Value ('x' * 2048) -NoNewline
        }
    }

    It 'con -EsCache vacia tambien los .db y .txt' {
        Clear-ContenidoCarpeta -Ruta $script:cache -Permanente -EsCache -Confirm:$false

        @(Get-ChildItem -LiteralPath $script:cache -File).Count |
            Should -Be 0 -Because 'una cache declarada se vacia entera: por eso se ofrece'
    }

    It 'sin -EsCache el veto por extension personal sigue mandando' {
        Clear-ContenidoCarpeta -Ruta $script:cache -Permanente -Confirm:$false

        $quedan = @(Get-ChildItem -LiteralPath $script:cache -File | ForEach-Object { $_.Name })
        $quedan | Should -Contain 'indice.db'
        $quedan | Should -Contain 'notas.txt'
        $quedan | Should -Not -Contain 'datos.bin' -Because 'lo que no es personal si se borra'
    }

    It 'el metodo Contenido solo levanta el veto en candidatos de cache genuina' {
        # ForzarPermanente es lo que marca "esto es cache que el programa
        # regenera", y es el mismo hecho que autoriza levantar el veto.
        $candidato = New-Candidato -ModuloId 'caches' -Categoria 'Cachés' -Nombre 'cache' `
                                   -Ruta $script:cache -Bytes 6144 -Metodo 'Contenido' `
                                   -Raices @($script:padreCache) -ForzarPermanente
        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        @(Get-ChildItem -LiteralPath $script:cache -File).Count | Should -Be 0
    }

    It 'un candidato Contenido que NO es cache conserva la proteccion' {
        $candidato = New-Candidato -ModuloId 'otro' -Categoria 'Otro' -Nombre 'carpeta' `
                                   -Ruta $script:cache -Bytes 6144 -Metodo 'Contenido' `
                                   -Raices @($script:padreCache)
        Invoke-EliminacionCandidato -Candidato $candidato -Confirm:$false | Out-Null

        @(Get-ChildItem -LiteralPath $script:cache -File | ForEach-Object { $_.Name }) |
            Should -Contain 'indice.db'
    }
}

Describe 'CNF-01: las carpetas que el usuario excluye no se tocan' {

    <#
        Es la funcion que mas se echa en falta en un limpiador: sin ella,
        el usuario desmarca hoy la carpeta de un proyecto vivo y manyana
        vuelve a salir. A la tercera deja de leer la lista, que es justo
        cuando un limpiador se vuelve peligroso.

        Se comprueba en DOS sitios y aqui se prueban los dos: el embudo
        del analisis y, otra vez, el motor de borrado. El borrado corre en
        otro runspace y puede pasar tiempo entre una cosa y la otra.
    #>

    Context 'Test-RutaExcluida' {

        It 'una carpeta excluida se reconoce' {
            Test-RutaExcluida -Ruta 'C:\Trabajo' -Excluidas @('C:\Trabajo') | Should -BeTrue
        }

        It 'excluir una carpeta excluye todo lo que cuelga de ella' {
            Test-RutaExcluida -Ruta 'C:\Trabajo\proyecto\node_modules' -Excluidas @('C:\Trabajo') |
                Should -BeTrue -Because 'nadie quiere enumerar tambien las veinte subcarpetas'
        }

        It 'NO excluye una carpeta que solo empieza igual' {
            # Sin exigir separador, excluir "C:\Datos" excluiria tambien
            # "C:\Datos Antiguos", que es otra carpeta distinta.
            Test-RutaExcluida -Ruta 'C:\Datos Antiguos\x' -Excluidas @('C:\Datos') | Should -BeFalse
        }

        It 'no distingue mayusculas ni el tipo de barra' {
            Test-RutaExcluida -Ruta 'c:/trabajo/x' -Excluidas @('C:\Trabajo') | Should -BeTrue
        }

        It 'con la lista vacia no excluye nada' {
            Test-RutaExcluida -Ruta 'C:\lo-que-sea' -Excluidas @()    | Should -BeFalse
            Test-RutaExcluida -Ruta 'C:\lo-que-sea' -Excluidas $null  | Should -BeFalse
        }

        It 'ignora las entradas vacias de la lista' {
            # Una linea en blanco en el archivo de preferencias no puede
            # convertirse en "excluir todo".
            Test-RutaExcluida -Ruta 'C:\lo-que-sea' -Excluidas @('', '   ') | Should -BeFalse
        }
    }

    Context 'El motor de borrado lo revalida' {

        BeforeAll {
            $script:padreExcl = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-excl-' + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:padreExcl -Force | Out-Null
        }

        AfterAll {
            Remove-Item -LiteralPath $script:padreExcl -Recurse -Force -ErrorAction SilentlyContinue
        }

        BeforeEach {
            $script:protegida = Join-Path $script:padreExcl ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $script:protegida -Force | Out-Null
            $script:archivoExcl = Join-Path $script:protegida 'basura.tmp'
            Set-Content -LiteralPath $script:archivoExcl -Value ('x' * 4096) -NoNewline
        }

        It 'un candidato dentro de una carpeta excluida NO se borra' {
            $candidato = New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'basura' `
                            -Ruta $script:archivoExcl -Bytes 4096 -Metodo 'Ruta' `
                            -Raices @($script:padreExcl)

            Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false `
                -Configuracion ([pscustomobject]@{ RutasExcluidas = @($script:protegida) }) | Out-Null

            Test-Path -LiteralPath $script:archivoExcl | Should -BeTrue -Because 'el usuario dijo que no se tocara'
            $candidato.Hecho | Should -BeFalse
            $candidato.Error | Should -Match 'Excluido por ti'
        }

        It 'sin la exclusion, el mismo candidato SI se borra' {
            # Sin esta, un motor que no borrara nada pasaria la anterior.
            $candidato = New-Candidato -ModuloId 'x' -Categoria 'x' -Nombre 'basura' `
                            -Ruta $script:archivoExcl -Bytes 4096 -Metodo 'Ruta' `
                            -Raices @($script:padreExcl)

            Invoke-EliminacionCandidato -Candidato $candidato -Permanente -Confirm:$false `
                -Configuracion ([pscustomobject]@{ RutasExcluidas = @() }) | Out-Null

            Test-Path -LiteralPath $script:archivoExcl | Should -BeFalse
            $candidato.Hecho | Should -BeTrue
        }
    }
}

Describe 'CNF-02: modo simulacion' {

    <#
        Un limpiador que solo se puede probar borrando no se prueba: se
        estrena. La simulacion es lo que convierte la primera ejecucion en
        un equipo real en algo sin consecuencias.

        Y todo lo que produce va en condicional, sin excepcion: nada de
        "eliminados" cuando no se ha eliminado nada, y nada de anotar en el
        historial una limpieza que no ocurrio.
    #>

    BeforeAll {
        $script:padreSim = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-sim-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:padreSim -Force | Out-Null
    }

    AfterAll {
        Remove-Item -LiteralPath $script:padreSim -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:zonaSim = Join-Path $script:padreSim ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:zonaSim -Force | Out-Null

        $script:candidatosSim = @()
        foreach ($n in 1..3) {
            $ruta = Join-Path $script:zonaSim "basura$n.tmp"
            Set-Content -LiteralPath $ruta -Value ('x' * 100000) -NoNewline
            $script:candidatosSim += New-Candidato -ModuloId 'x' -Categoria 'x' `
                -Nombre "basura$n.tmp" -Ruta $ruta -Bytes 100000 `
                -Metodo 'Ruta' -Raices @($script:zonaSim)
        }
    }

    It 'no borra ni un solo archivo' {
        Invoke-LoteEliminacion -Candidatos $script:candidatosSim -Permanente -Simular -Confirm:$false | Out-Null
        @(Get-ChildItem -LiteralPath $script:zonaSim -File).Count |
            Should -Be 3 -Because 'simular es mirar, no tocar'
    }

    It 'cuenta lo que se HABRIA liberado' {
        $r = Invoke-LoteEliminacion -Candidatos $script:candidatosSim -Permanente -Simular -Confirm:$false
        $r.Simulados | Should -Be 3
        $r.Liberado  | Should -Be 300000
        $r.Simulado  | Should -BeTrue
    }

    It 'NO marca nada como hecho' {
        $r = Invoke-LoteEliminacion -Candidatos $script:candidatosSim -Permanente -Simular -Confirm:$false
        $r.Hechos | Should -Be 0 -Because 'no se ha hecho nada'
        foreach ($c in $script:candidatosSim) {
            $c.Hecho          | Should -BeFalse
            $c.BytesLiberados | Should -Be 0 -Because 'no se ha liberado nada todavia'
        }
    }

    It 'sin -Simular si borra: la prueba anterior no pasa por no hacer nada' {
        $r = Invoke-LoteEliminacion -Candidatos $script:candidatosSim -Permanente -Confirm:$false
        $r.Hechos    | Should -Be 3
        $r.Simulados | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:zonaSim -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'deja constancia en el registro, y en condicional' {
        $sync = New-EstadoSincronizado
        Invoke-LoteEliminacion -Candidatos $script:candidatosSim -Permanente -Simular `
                               -Sync $sync -Confirm:$false | Out-Null

        $lineas = @()
        $linea = $null
        while ($sync.ColaRegistro.TryDequeue([ref] $linea)) { $lineas += $linea }
        $texto = $lineas -join "`n"

        $texto | Should -Match 'SIMULACION'
        $texto | Should -Match 'Se borraria'
        $texto | Should -Not -Match '\[BORRADO\]' -Because 'no se ha borrado nada'
    }

    It 'la simulacion no anota nada en el historial' {
        # Un historial con limpiezas que no ocurrieron es justo el tipo de
        # mentira que este programa lleva toda la auditoria corrigiendo.
        $cli = Get-Content -Raw -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Cli/Cli.ps1')
        $cli | Should -Match '(?s)if \(-not \$Simular\) \{\s*Add-EntradaHistorial'
    }
}
