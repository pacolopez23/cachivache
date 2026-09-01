<#
    LAS CUATRO QUE NADIE NOMBRABA.

    Test-Cancelacion y Set-Progreso son las dos funciones mas llamadas del
    programa: no hay un solo modulo de limpieza que no las use. Y hasta
    hoy ninguna prueba las nombraba, porque se ejercitaban SIEMPRE por
    debajo -a traves de Invoke-ModuloLimpieza- y nunca por su contrato.

    Ese contrato es deliberadamente tolerante con $Sync nulo: en modo
    consola no hay ninguna tabla que sincronizar, y las dos se llaman
    igual para que el modulo no tenga que preguntar en que modo esta. Esa
    tolerancia no la protegia nadie. El dia que alguien pusiera un
    [Parameter(Mandatory)] o quitara el "if ($null -eq $Sync)", el modo
    consola entero se caeria y la suite seguiria en verde, porque todas
    las pruebas que las tocaban le pasaban una tabla de verdad.

    Invoke-BusquedaPorLista y Get-ReferenciaAnterior estaban en el mismo
    sitio: tests/BusquedaPorLista.Tests.ps1 y tests/Comparacion.Tests.ps1
    las recorren enteras, pero desde arriba -por los tres modulos de lista
    y por Get-ComparacionAnalisis- y sin nombrarlas. Una prueba que llega
    a la funcion por otro camino comprueba el camino, no la funcion: el
    dia que el llamante deje de llamarla, esas pruebas siguen pasando y la
    funcion se queda sin nadie que la mire. Aqui se atacan de frente y por
    sus limites, que es donde se rompen las cosas: lista vacia, sin
    coincidencias, historial vacio, entradas malformadas.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # --- Un disco de mentira para Invoke-BusquedaPorLista --------------
    #
    # Se monta una sola vez porque no se escribe en el durante las
    # pruebas: cada It solo lo lee. Las variables de entorno apuntan aqui
    # para que la guardia construya sus listas contra este arbol y no
    # contra el equipo real, y se restauran en el AfterAll: Initialize-
    # Guardia es estado global del proceso y las demas pruebas de la
    # suite corren en el mismo runspace.
    $script:Obra   = Join-Path ([IO.Path]::GetTempPath()) ('progbus-' + [guid]::NewGuid().ToString('N'))
    $script:Dentro = Join-Path $script:Obra 'dentro'
    [void](New-Item -ItemType Directory -Path $script:Dentro -Force)

    $script:EntornoOriginal = @{
        SystemRoot   = $env:SystemRoot
        ProgramData  = $env:ProgramData
        LOCALAPPDATA = $env:LOCALAPPDATA
        APPDATA      = $env:APPDATA
        USERPROFILE  = $env:USERPROFILE
        SystemDrive  = $env:SystemDrive
    }

    $env:SystemRoot   = Join-Path $script:Obra 'Windows'
    $env:ProgramData  = Join-Path $script:Obra 'ProgramData'
    $env:USERPROFILE  = Join-Path $script:Obra 'Usuario'
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'Local'
    $env:APPDATA      = Join-Path $env:USERPROFILE 'Roaming'
    $env:SystemDrive  = $script:Obra

    $script:ConfiguracionGuardia = [pscustomobject]@{
        Escritorio = ''; Documentos = ''; Descargas = ''
        Imagenes   = ''; Musica     = ''; Videos     = ''
        CarpetaDatos = ''
    }
    Initialize-Guardia -Configuracion $script:ConfiguracionGuardia

    function script:New-CarpetaConPeso {
        param([string] $Ruta, [int] $Megas = 3)
        [void](New-Item -ItemType Directory -Path $Ruta -Force)
        $relleno = [byte[]]::new(1MB)
        for ($i = 0; $i -lt $Megas; $i++) {
            [IO.File]::WriteAllBytes((Join-Path $Ruta "relleno$i.bin"), $relleno)
        }
        return $Ruta
    }

    # Por encima del umbral de 1 MB que traen por defecto los modulos.
    $script:Grande = script:New-CarpetaConPeso (Join-Path $script:Dentro 'grande')
    $script:Otra   = script:New-CarpetaConPeso (Join-Path $script:Dentro 'otra')
    $script:Menor  = script:New-CarpetaConPeso (Join-Path $script:Dentro 'menor')
    # Existe y pesa, pero NO cuelga de ninguna raiz autorizada.
    $script:Fuera  = script:New-CarpetaConPeso (Join-Path $script:Obra 'fuera')
    # Existe pero no llega al umbral.
    $script:Peque  = Join-Path $script:Dentro 'peque'
    [void](New-Item -ItemType Directory -Path $script:Peque -Force)
    [IO.File]::WriteAllBytes((Join-Path $script:Peque 'migaja.bin'), [byte[]]::new(1024))
    # No existe, y no se crea nunca.
    $script:NoExiste = Join-Path $script:Dentro 'esto-no-esta'

    # Lo que todos los modulos de lista pasan igual, para que cada It
    # ensenye solo lo que esta probando.
    $script:Comunes = @{
        ModuloId  = 'pruebas'
        Categoria = 'Cachés'
        Raices    = @($script:Dentro)
    }

    # Una entrada de historial como las que escribe Add-EntradaHistorial.
    # Se construye a mano y no con el escritor real porque lo que se prueba
    # aqui es como se lee un archivo que puede haber editado cualquiera.
    function script:New-Apunte {
        param(
            [string] $Tipo = 'analisis',
            [string] $Id   = 'x',
            [double] $DiasAtras = 1
        )
        [pscustomobject]@{
            Marca     = $Id
            Tipo      = $Tipo
            Fecha     = (Get-Date).AddDays(-$DiasAtras).ToString('o')
            Perfil    = 'equilibrado'
            Modulos   = @('caches')
            Elementos = 890
            Bytes     = 3435973836.8
        }
    }
}

AfterAll {
    foreach ($clave in @($script:EntornoOriginal.Keys)) {
        Set-Item -Path ("Env:$clave") -Value $script:EntornoOriginal[$clave] -ErrorAction SilentlyContinue
    }
    # La guardia se vuelve a construir con el entorno de verdad: sus listas
    # son estado del proceso y detras de este archivo corren mas pruebas.
    Initialize-Guardia -Configuracion $script:ConfiguracionGuardia

    if ($script:Obra -and (Test-Path -LiteralPath $script:Obra)) {
        Remove-Item -LiteralPath $script:Obra -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =====================================================================
#  Test-Cancelacion
# =====================================================================

Describe 'Test-Cancelacion: el interruptor que consultan todos los modulos' {

    It 'con $Sync nulo dice que NO se cancela, y de eso vive el modo consola' {
        # La linea que sostiene el modo consola entero. Sin tabla que
        # sincronizar, la respuesta tiene que ser "sigue", nunca un fallo
        # ni un "para": los 18 modulos preguntan esto en cada vuelta de su
        # bucle y ninguno comprueba antes en que modo esta el programa.
        Test-Cancelacion $null | Should -BeFalse
    }

    It 'y con $Sync nulo NO lanza, ni siquiera llamandola mil veces seguidas' {
        # Un modulo la llama una vez por elemento. Si el contrato se
        # volviera intolerante con el nulo, el modo consola no fallaria en
        # el arranque: fallaria a mitad del analisis del usuario.
        {
            foreach ($i in 1..1000) { [void](Test-Cancelacion $null) }
        } | Should -Not -Throw
    }

    It 'con Cancelar a $true dice que si' {
        $sync = [hashtable]::Synchronized(@{ Cancelar = $true })
        Test-Cancelacion $sync | Should -BeTrue
    }

    It 'con Cancelar a $false dice que no' {
        $sync = [hashtable]::Synchronized(@{ Cancelar = $false })
        Test-Cancelacion $sync | Should -BeFalse
    }

    It 'devuelve un [bool] de verdad, no lo que hubiera en la propiedad' {
        # La tabla es un hashtable compartido entre dos hilos y cualquiera
        # puede escribir en el lo que quiera. Si la funcion devolviera el
        # campo pelado, quien llama recibiria una cadena, y "if (cadena)"
        # es verdadero para cualquier texto no vacio: el bucle pararia sin
        # que nadie hubiera pedido parar. Las dos aserciones hacen falta,
        # porque el valor tambien es cierto sin la conversion.
        $sync = [hashtable]::Synchronized(@{ Cancelar = 'no' })
        $r = Test-Cancelacion $sync
        $r | Should -BeOfType [bool]
        $r | Should -BeTrue -Because 'una cadena no vacia convertida a bool es verdadera'

        $sync.Cancelar = ''
        $r2 = Test-Cancelacion $sync
        $r2 | Should -BeOfType [bool]
        $r2 | Should -BeFalse
    }

    It 'con $Sync nulo tambien devuelve un [bool], no un nulo disfrazado' {
        (Test-Cancelacion $null) | Should -BeOfType [bool]
    }

    It 'una tabla sin la clave Cancelar no cancela' {
        # Una tabla a medio construir -o de una version anterior del
        # programa- no puede significar "aborta": el analisis se quedaria
        # sin hacer y el usuario no veria ni un error.
        $sync = [hashtable]::Synchronized(@{ Mensaje = 'hola' })
        $r = Test-Cancelacion $sync
        $r | Should -BeOfType [bool]
        $r | Should -BeFalse
    }

    It 'sobre la tabla que el programa usa de verdad' {
        # New-EstadoSincronizado es lo que se pasa en el programa. Si su
        # forma cambiara -otro nombre de campo, por ejemplo- esta prueba
        # se pone roja y las de arriba, que arman la tabla a mano, no.
        $sync = New-EstadoSincronizado
        Test-Cancelacion $sync | Should -BeFalse -Because 'un estado recien creado no viene cancelado'

        $sync.Cancelar = $true
        Test-Cancelacion $sync | Should -BeTrue
    }
}

# =====================================================================
#  Set-Progreso
# =====================================================================

Describe 'Set-Progreso: el mensaje tiene que ACABAR en la tabla' {

    It 'el mensaje llega a la tabla, que es lo unico que hace esta funcion' {
        # Que no lance no prueba nada: una funcion vacia tampoco lanza.
        # Lo que hay que comprobar es que la interfaz puede leer despues
        # lo que el hilo de trabajo acaba de escribir.
        $sync = [hashtable]::Synchronized(@{ Mensaje = '' })
        Set-Progreso $sync 'Midiendo: Temporales del usuario'
        $sync.Mensaje | Should -Be 'Midiendo: Temporales del usuario'
    }

    It 'sobre la tabla que el programa usa de verdad' {
        $sync = New-EstadoSincronizado
        Set-Progreso $sync 'Analizando cachés'
        $sync.Mensaje | Should -Be 'Analizando cachés'
    }

    It 'el mensaje nuevo pisa al anterior' {
        # Es un marcador de "en que voy", no un registro. Si se acumulara,
        # la barra de progreso ensenyaria el primer modulo para siempre.
        $sync = New-EstadoSincronizado
        Set-Progreso $sync 'primero'
        Set-Progreso $sync 'segundo'
        $sync.Mensaje | Should -Be 'segundo'
    }

    It 'una cadena vacia BORRA el mensaje, no lo deja como estaba' {
        # Es como se apaga el texto al terminar. Si un mensaje vacio se
        # ignorara, la ventana se quedaria diciendo "Midiendo: ..." con el
        # analisis ya acabado.
        $sync = New-EstadoSincronizado
        Set-Progreso $sync 'Midiendo algo'
        Set-Progreso $sync ''
        $sync.Mensaje | Should -Be ''
    }

    It 'no toca ningun otro campo de la tabla' {
        # La tabla la comparten dos hilos. Reemplazarla, o escribir de
        # paso en Cancelar o en Terminado, seria pisar lo que el otro hilo
        # acaba de decir.
        $sync = New-EstadoSincronizado
        $sync.Cancelar  = $true
        $sync.Terminado = $false
        $cola = $sync.ColaRegistro

        Set-Progreso $sync 'Midiendo'

        $sync.Cancelar  | Should -BeTrue
        $sync.Terminado | Should -BeFalse
        [object]::ReferenceEquals($cola, $sync.ColaRegistro) |
            Should -BeTrue -Because 'la cola de registro la comparten los dos hilos: no se puede sustituir'
    }

    It 'con $Sync nulo NO lanza: es el modo consola' {
        # El mismo contrato tolerante que Test-Cancelacion, y por el mismo
        # motivo: los modulos llaman a las dos sin preguntar si hay tabla.
        { Set-Progreso $null 'Midiendo algo' } | Should -Not -Throw
    }

    It 'y con $Sync nulo aguanta mil llamadas, como en un analisis de verdad' {
        {
            foreach ($i in 1..1000) { Set-Progreso $null ("Midiendo: elemento $i") }
        } | Should -Not -Throw
    }

    It 'con $Sync nulo tampoco lanza sin mensaje' {
        { Set-Progreso $null } | Should -Not -Throw
    }

    It 'no devuelve NADA por la tuberia, ni con tabla ni sin ella' {
        # Invoke-BusquedaPorLista la llama DENTRO del bucle que emite
        # candidatos. Si devolviera algo, ese algo se colaria en la lista
        # de candidatos del modulo y acabaria en la tabla del usuario como
        # una fila que nadie ha propuesto.
        $sync = New-EstadoSincronizado
        @(Set-Progreso $sync 'Midiendo').Count | Should -Be 0
        @(Set-Progreso $null 'Midiendo').Count | Should -Be 0
    }
}

Describe 'Las dos juntas: un bucle de modulo sin tabla que sincronizar' {

    It 'un recorrido entero en modo consola no lanza ni se cree cancelado' {
        # Asi las llama un modulo: preguntar, trabajar, anunciar. Con
        # $Sync a $null las dos tienen que comportarse como si nadie
        # hubiera pedido nada, vuelta tras vuelta.
        # El bucle va suelto y no dentro de un Should -Not -Throw: asi, si
        # alguna de las dos dejara de aguantar el nulo, el It se pone rojo
        # con la excepcion de verdad delante en vez de con un "esperaba que
        # no lanzara". Y el contador va en $script: porque un scriptblock
        # corre en su propio ambito: incrementarlo dentro dejaria fuera un
        # cero y la prueba compararia contra su propia variable intacta.
        $script:VueltasConsola = 0
        foreach ($i in 1..200) {
            if (Test-Cancelacion $null) { break }
            Set-Progreso $null ("Midiendo: elemento $i")
            $script:VueltasConsola++
        }
        $script:VueltasConsola | Should -Be 200 -Because 'sin tabla, nadie ha cancelado nada'
    }
}

# =====================================================================
#  Invoke-BusquedaPorLista
# =====================================================================

Describe 'Invoke-BusquedaPorLista: el caso feliz y su forma' {

    It 'el arbol de mentira esta montado: si no, todo lo de abajo mira el vacio' {
        # La guarda que pide RELEVO.md. Sin ella, un fallo al montar las
        # carpetas convertiria media docena de "no propone nada" en
        # pruebas que pasan sin comprobar nada.
        Test-Path -LiteralPath $script:Grande | Should -BeTrue
        Test-Path -LiteralPath $script:Fuera  | Should -BeTrue
        (Measure-Ruta $script:Grande) | Should -BeGreaterThan 1MB
        (Measure-Ruta $script:Peque)  | Should -BeLessThan 1MB
    }

    It 'una entrada que existe y pesa sale como candidato, campo a campo' {
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                   @{ N = 'Temporales del usuario'; R = $script:Grande; E = 'se recrean solos' }))

        @($r).Count      | Should -Be 1
        $r[0].Nombre     | Should -Be 'Temporales del usuario'
        $r[0].Ruta       | Should -Be $script:Grande
        $r[0].Efecto     | Should -Be 'se recrean solos'
        $r[0].ModuloId   | Should -Be 'pruebas'
        $r[0].Categoria  | Should -Be 'Cachés'
        $r[0].Metodo     | Should -Be 'Contenido' -Because 'sin M, el metodo por defecto es Contenido'
        $r[0].Riesgo     | Should -Be 'Bajo'
        $r[0].Aviso      | Should -Be ''
        $r[0].Bytes      | Should -BeGreaterThan 1MB
        $r[0].Seleccionado | Should -BeTrue -Because 'riesgo bajo y sin aviso: la regla de New-Candidato lo marca'
        $r[0].ForzarPermanente | Should -BeFalse
        @($r[0].Raices)  | Should -Be @($script:Dentro)
    }

    It 'el Info por defecto se usa tal cual, y -Info lo sustituye' {
        $porDefecto = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                            @{ N = 'A'; R = $script:Grande; E = 'e' }))
        $porDefecto[0].Info | Should -Be 'se vacía el contenido, la carpeta se queda'

        $propio = @(Invoke-BusquedaPorLista @script:Comunes -Info 'se borra entera' -Entradas @(
                        @{ N = 'A'; R = $script:Grande; E = 'e' }))
        $propio[0].Info | Should -Be 'se borra entera'
    }

    It 'M y A de la entrada mandan sobre los valores por defecto' {
        # El aviso no es decoracion: New-Candidato NUNCA marca lo que lleva
        # aviso. Si esta funcion se comiera el campo A, la entrada saldria
        # marcada y el usuario borraria sin leer el motivo.
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                   @{ N = 'Base de datos'; R = $script:Grande; E = 'e'
                      M = 'Ruta'; A = 'se borra el historial de actualizaciones' }))

        @($r).Count  | Should -Be 1
        $r[0].Metodo | Should -Be 'Ruta'
        $r[0].Aviso  | Should -Be 'se borra el historial de actualizaciones'
        $r[0].Seleccionado | Should -BeFalse -Because 'lo que lleva aviso no se marca nunca solo'
    }

    It '-ForzarPermanente llega hasta el candidato' {
        # Solo lo usan las caches genuinas. Si se perdiera por el camino,
        # cientos de miles de archivos de cache irian a la papelera y no se
        # liberaria ni un byte hasta vaciarla.
        $con = @(Invoke-BusquedaPorLista @script:Comunes -ForzarPermanente -Entradas @(
                     @{ N = 'A'; R = $script:Grande; E = 'e' }))
        $sin = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                     @{ N = 'A'; R = $script:Grande; E = 'e' }))

        $con[0].ForzarPermanente | Should -BeTrue
        $sin[0].ForzarPermanente | Should -BeFalse
    }

    It 'NotaExtra recibe LA ENTRADA como parametro y su texto se pega al Info' {
        # Se pasa como parametro y no confiando en $_, porque un $_ que
        # atraviesa un & no es un mecanismo: depende de la version de
        # PowerShell. Si llegara vacio, el Info saldria sin el corchete.
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Info 'base' -Entradas @(
                   @{ N = 'Caché de npm'; R = $script:Grande; E = 'e' }) `
               -NotaExtra { param($entrada) ' [' + $entrada.N + ']' })

        $r[0].Info | Should -Be 'base [Caché de npm]'
    }

    It 'sin NotaExtra el Info sale sin cola' {
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Info 'base' -Entradas @(
                   @{ N = 'A'; R = $script:Grande; E = 'e' }))
        $r[0].Info | Should -Be 'base'
    }

    It 'varias entradas salen todas, y en el orden de la lista' {
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                   @{ N = 'Primera'; R = $script:Grande; E = 'e' },
                   @{ N = 'Segunda'; R = $script:Otra;   E = 'e' }))

        @($r).Count  | Should -Be 2
        $r[0].Nombre | Should -Be 'Primera'
        $r[1].Nombre | Should -Be 'Segunda'
    }
}

Describe 'Invoke-BusquedaPorLista: los limites, que es donde se rompe' {

    It 'una lista vacia no propone nada ni lanza' {
        { [void](Invoke-BusquedaPorLista @script:Comunes -Entradas @()) } | Should -Not -Throw
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas @()).Count | Should -Be 0
    }

    It 'sin ninguna coincidencia: lo que no existe en disco no se propone' {
        # El caso normal en un equipo cualquiera: la mayoria de las rutas
        # de la lista no estan. Proponer una ruta inexistente le prometeria
        # al usuario un espacio que no va a recuperar.
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
              @{ N = 'Fantasma'; R = $script:NoExiste; E = 'e' })).Count | Should -Be 0
    }

    It 'ni una sola de una lista entera de rutas que no existen' {
        $entradas = @(1..5 | ForEach-Object {
            @{ N = "Fantasma $_"; R = (Join-Path $script:Dentro "no-esta-$_"); E = 'e' }
        })
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas $entradas).Count | Should -Be 0
    }

    It 'lo que no llega al umbral no se propone' {
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
              @{ N = 'Migaja'; R = $script:Peque; E = 'e' })).Count | Should -Be 0
    }

    It 'y el umbral es el que pide cada modulo, no uno unico' {
        # windowsupdate usa 10 MB donde caches y logs usan 1. Es justo el
        # detalle que un refactor unifica sin darse cuenta.
        @(Invoke-BusquedaPorLista @script:Comunes -MinimoBytes 10MB -Entradas @(
              @{ N = 'Grande'; R = $script:Grande; E = 'e' })).Count |
            Should -Be 0 -Because 'la carpeta pesa 3 MB y el umbral pedido es 10'

        @(Invoke-BusquedaPorLista @script:Comunes -MinimoBytes 1MB -Entradas @(
              @{ N = 'Grande'; R = $script:Grande; E = 'e' })).Count | Should -Be 1
    }

    It 'una ruta que no cuelga de las raices la veta la guardia' {
        # Existe y pesa de sobra: lo unico que le pasa es que esta fuera de
        # la lista blanca del modulo.
        Test-Path -LiteralPath $script:Fuera | Should -BeTrue
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
              @{ N = 'Fuera'; R = $script:Fuera; E = 'e' })).Count | Should -Be 0
    }

    It 'y la veta ANTES de medirla: no llega a anunciar que la esta midiendo' {
        # El orden esta puesto a proposito -ver RENDIMIENTO.md, seccion 7-:
        # medir cuesta segundos y preguntarle a la guardia cuesta un
        # milisegundo. Si alguien invirtiera las dos lineas el resultado
        # seria el mismo y el analisis tardaria de mas, sin que nada
        # avisara. El mensaje de progreso es la unica huella que deja.
        $sync = New-EstadoSincronizado
        [void](Invoke-BusquedaPorLista @script:Comunes -Sync $sync -Entradas @(
                   @{ N = 'Fuera'; R = $script:Fuera; E = 'e' }))
        $sync.Mensaje | Should -Be '' -Because 'una ruta vetada no se llega a medir'
    }

    It 'las entradas Menor solo salen con -IncluirMenores' {
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
              @{ N = 'Menor'; R = $script:Menor; E = 'e'; Menor = $true })).Count |
            Should -Be 0

        @(Invoke-BusquedaPorLista @script:Comunes -IncluirMenores -Entradas @(
              @{ N = 'Menor'; R = $script:Menor; E = 'e'; Menor = $true })).Count |
            Should -Be 1
    }

    It '-IncluirMenores no cambia nada para las que no son menores' {
        foreach ($incluir in @($true, $false)) {
            $r = @(Invoke-BusquedaPorLista @script:Comunes -IncluirMenores:$incluir -Entradas @(
                       @{ N = 'Normal'; R = $script:Grande; E = 'e' }))
            @($r).Count | Should -Be 1 -Because "con -IncluirMenores:$incluir una entrada normal sale igual"
        }
    }

    It 'una entrada malformada no tumba el recorrido: la siguiente sigue saliendo' {
        # historial.json no, pero una lista mal escrita por un modulo nuevo
        # si es posible. Lo que no puede pasar es que una entrada rota se
        # lleve por delante las quince que van detras, ni que salga un
        # candidato sin ruta que el motor intentaria borrar.
        #
        # ESTA PRUEBA ESTABA VERDE Y MENTIA, y hay que leer por que.
        #
        # Nacio con -ErrorAction SilentlyContinue, porque en PowerShell 7
        # una ruta nula hace que Test-Path escriba un error NO terminante
        # y siga. En Windows PowerShell 5.1 el mismo -LiteralPath nulo lo
        # rechaza el ENLAZADOR DE PARAMETROS, que lanza y aborta el bucle
        # entero: la entrada buena no llegaba a mirarse. O sea que la
        # funcion hacia exactamente lo que esta prueba prometia que no
        # hacia, en la unica plataforma donde el programa se ejecuta.
        #
        # Ahora hay una guarda explicita en Candidate.ps1 y el -ErrorAction
        # sobra. Se quita A PROPOSITO: sin el, esta prueba exige ademas
        # que no se escriba ningun error, que es lo que de verdad
        # distingue "lo saltamos bien" de "lo tapamos".
        #
        # AVISO PARA QUIEN VERIFIQUE POR MUTACION: quitar esa guarda NO
        # pone nada en rojo si mutas en Linux o en PowerShell 7, porque
        # ahi el fallo no existe. Esta prueba solo demuestra el arreglo en
        # el trabajo "Pruebas (PowerShell 5.1)" de la integracion continua.
        # No es un hueco de la prueba: es que el fallo era de plataforma.
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                   @{ N = 'Sin ruta'; E = 'e' },
                   @{ N = 'Buena'; R = $script:Grande; E = 'e' }))

        @($r).Count  | Should -Be 1
        $r[0].Nombre | Should -Be 'Buena'
    }

    It 'una entrada con la ruta en blanco tampoco' {
        # La cadena vacia y los espacios van por la misma guarda que el
        # nulo: Test-Path con "" tambien lanza en 5.1.
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                   @{ N = 'Vacia'; R = ''; E = 'e' },
                   @{ N = 'Espacios'; R = '   '; E = 'e' },
                   @{ N = 'Buena'; R = $script:Grande; E = 'e' }))

        @($r).Count  | Should -Be 1
        $r[0].Nombre | Should -Be 'Buena'
    }

    It 'una entrada nula tampoco lo tumba' {
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
                   $null,
                   @{ N = 'Buena'; R = $script:Grande; E = 'e' }))

        @($r).Count  | Should -Be 1
        $r[0].Nombre | Should -Be 'Buena'
    }

    It 'una entrada suelta, sin envolver en lista, se recorre igual' {
        # Un modulo cuya lista se quede en una sola entrada la pasa suelta,
        # no envuelta: en 5.1 una coleccion de uno se desenvuelve sola. Lo
        # que se fija aqui es que ese caso proponga su candidato igual.
        #
        # (El @($Entradas) del codigo NO es lo que lo salva: quitarlo deja
        # esta prueba en verde, porque un foreach sobre un hashtable ya
        # recorre el hashtable entero y no sus claves. Se comprobo mutando.
        # Lo que se protege es el COMPORTAMIENTO, no esa linea.)
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Entradas @{ N = 'Sola'; R = $script:Grande; E = 'e' })
        @($r).Count  | Should -Be 1
        $r[0].Nombre | Should -Be 'Sola'
    }
}

Describe 'Invoke-BusquedaPorLista: progreso y cancelacion, sus dos vecinas' {

    It 'anuncia por Set-Progreso lo que esta midiendo, con el nombre de la entrada' {
        $sync = New-EstadoSincronizado
        [void](Invoke-BusquedaPorLista @script:Comunes -Sync $sync -Entradas @(
                   @{ N = 'Caché de npm'; R = $script:Grande; E = 'e' }))
        $sync.Mensaje | Should -Be 'Midiendo: Caché de npm'
    }

    It 'con $Sync nulo propone lo mismo: es como lo llama el modo consola' {
        # LA PRUEBA QUE JUSTIFICA EL CONTRATO TOLERANTE. Esta funcion llama
        # a Test-Cancelacion y a Set-Progreso en cada vuelta sin mirar si
        # hay tabla. Si alguna de las dos dejara de aguantar el nulo, el
        # modo consola dejaria de encontrar nada y se veria aqui.
        $conTabla = @(Invoke-BusquedaPorLista @script:Comunes -Sync (New-EstadoSincronizado) -Entradas @(
                          @{ N = 'A'; R = $script:Grande; E = 'e' }))
        $sinTabla = @(Invoke-BusquedaPorLista @script:Comunes -Sync $null -Entradas @(
                          @{ N = 'A'; R = $script:Grande; E = 'e' }))

        @($sinTabla).Count | Should -Be 1
        @($sinTabla).Count | Should -Be @($conTabla).Count
        $sinTabla[0].Ruta  | Should -Be $conTabla[0].Ruta
    }

    It 'sin -Sync tampoco: el parametro es opcional y su valor por defecto es nulo' {
        @(Invoke-BusquedaPorLista @script:Comunes -Entradas @(
              @{ N = 'A'; R = $script:Grande; E = 'e' })).Count | Should -Be 1
    }

    It 'cancelado de antemano no propone ni el primero' {
        $sync = New-EstadoSincronizado
        $sync.Cancelar = $true
        @(Invoke-BusquedaPorLista @script:Comunes -Sync $sync -Entradas @(
              @{ N = 'A'; R = $script:Grande; E = 'e' },
              @{ N = 'B'; R = $script:Otra;   E = 'e' })).Count | Should -Be 0
    }

    It 'cancelar a mitad corta ahi: sale lo ya propuesto y nada mas' {
        # Se pregunta en CADA vuelta, no una vez al entrar. Si se
        # preguntara solo al principio, pulsar "Cancelar" no haria nada
        # hasta terminar la lista entera, que es justo lo que el usuario
        # esta intentando evitar.
        $script:SyncCorte = New-EstadoSincronizado
        $r = @(Invoke-BusquedaPorLista @script:Comunes -Sync $script:SyncCorte -Entradas @(
                   @{ N = 'Primera'; R = $script:Grande; E = 'e' },
                   @{ N = 'Segunda'; R = $script:Otra;   E = 'e' }) `
               -NotaExtra { param($entrada) $script:SyncCorte.Cancelar = $true; '' })

        @($r).Count  | Should -Be 1
        $r[0].Nombre | Should -Be 'Primera'
    }
}

# =====================================================================
#  Get-ReferenciaAnterior
# =====================================================================

Describe 'Get-ReferenciaAnterior: con que se compara un analisis' {

    It 'un historial nulo no da referencia' {
        # Es el primer arranque del programa, y tambien el caso de un
        # historial.json ilegible. Devolver algo aqui seria inventarse un
        # "antes habia" que nunca se midio.
        Get-ReferenciaAnterior -Historial $null | Should -BeNullOrEmpty
    }

    It 'un historial vacio tampoco' {
        Get-ReferenciaAnterior -Historial @() | Should -BeNullOrEmpty
    }

    It 'y ninguno de los dos lanza' {
        { [void](Get-ReferenciaAnterior -Historial $null) } | Should -Not -Throw
        { [void](Get-ReferenciaAnterior -Historial @()) }   | Should -Not -Throw
    }

    It 'un analisis si sirve de referencia, y se devuelve tal cual' {
        # Se devuelve LA ENTRADA, no una copia ni un resumen: quien llama
        # lee de ella Elementos, Bytes, Fecha, Perfil, Modulos e
        # Incompleto. Un objeto nuevo se dejaria campos por el camino.
        $apunte = script:New-Apunte -Id 'unico'
        $r = Get-ReferenciaAnterior -Historial @($apunte)

        $r | Should -Not -BeNullOrEmpty
        $r.Marca     | Should -Be 'unico'
        $r.Elementos | Should -Be 890
        [object]::ReferenceEquals($apunte, $r) | Should -BeTrue
    }
}

Describe 'Get-ReferenciaAnterior: lo que NO vale como termino de comparacion' {

    It 'una limpieza no vale, aunque sea el ultimo apunte' {
        # Los "Elementos" de una limpieza son los que se BORRARON y sus
        # "Bytes" el espacio liberado. Compararlos con lo encontrado en un
        # analisis es restar dos magnitudes distintas y ensenyarlas como
        # si fueran la misma.
        Get-ReferenciaAnterior -Historial @(script:New-Apunte -Tipo 'limpieza' -Id 'L1') |
            Should -BeNullOrEmpty
    }

    It 'un historial de puras limpiezas no da referencia' {
        $h = @(
            script:New-Apunte -Tipo 'limpieza' -Id 'L1' -DiasAtras 5
            script:New-Apunte -Tipo 'limpieza' -Id 'L2' -DiasAtras 2
        )
        Get-ReferenciaAnterior -Historial $h | Should -BeNullOrEmpty
    }

    It 'un tipo que no se conoce tampoco vale' {
        # historial.json es texto plano en una carpeta escribible: puede
        # traer un tipo de una version futura, o inventado. Lo que no se
        # sabe que cuenta no se compara.
        Get-ReferenciaAnterior -Historial @(script:New-Apunte -Tipo 'limpieza-interrumpida' -Id 'R1') |
            Should -BeNullOrEmpty
    }

    It 'una entrada sin Tipo no cuela' {
        Get-ReferenciaAnterior -Historial @([pscustomobject]@{ Marca = 'S1'; Elementos = 3 }) |
            Should -BeNullOrEmpty
    }

    It 'un Tipo que llega como LISTA no cuela, ni siquiera si todo dentro es analisis' {
        # Aqui esta el motivo de que el codigo escriba [string]$entrada.Tipo
        # y no el campo pelado. Con @('analisis','analisis'), la
        # comparacion sin convertir devuelve una lista vacia -o sea, falso-
        # y la entrada colaria: bastaria escribir "Tipo": ["analisis",
        # "analisis"] en el archivo para que se compare con cualquier cosa.
        # Con la conversion, el campo vale "analisis analisis" y se
        # descarta. Es la unica forma de esta prueba que se pone roja si
        # alguien quita el [string].
        Get-ReferenciaAnterior -Historial @([pscustomobject]@{ Tipo = @('analisis', 'analisis'); Marca = 'AR' }) |
            Should -BeNullOrEmpty

        Get-ReferenciaAnterior -Historial @([pscustomobject]@{ Tipo = @('analisis', 'limpieza'); Marca = 'AR2' }) |
            Should -BeNullOrEmpty
    }

    It 'basura suelta en la lista no cuela ni lanza' {
        # El archivo lo puede editar cualquiera: puede traer cadenas,
        # numeros o nulos donde deberia haber objetos.
        { [void](Get-ReferenciaAnterior -Historial @('basura', 42, $null)) } | Should -Not -Throw
        Get-ReferenciaAnterior -Historial @('basura', 42, $null) | Should -BeNullOrEmpty
    }

    It 'un historial de puros nulos no da referencia' {
        Get-ReferenciaAnterior -Historial @($null, $null) | Should -BeNullOrEmpty
    }
}

Describe 'Get-ReferenciaAnterior: cual de todos los analisis' {

    It 'el ULTIMO analisis, saltandose las limpiezas que vengan detras' {
        # Se compara con el anterior, no con el ultimo apunte. Una limpieza
        # posterior no borra el analisis que si servia.
        $h = @(
            script:New-Apunte -Tipo 'analisis' -Id 'A1' -DiasAtras 9
            script:New-Apunte -Tipo 'analisis' -Id 'A2' -DiasAtras 5
            script:New-Apunte -Tipo 'limpieza' -Id 'L1' -DiasAtras 1
        )
        (Get-ReferenciaAnterior -Historial $h).Marca | Should -Be 'A2'
    }

    It 'las entradas nulas de en medio se saltan sin perder la buena' {
        $h = @($null, (script:New-Apunte -Id 'A1'), $null)
        (Get-ReferenciaAnterior -Historial $h).Marca | Should -Be 'A1'
    }

    It 'el ULTIMO del archivo, no el de Fecha mayor' {
        # El historial se escribe anyadiendo al final, asi que el orden del
        # archivo ES el orden de ejecucion. La fecha es un campo de texto
        # que puede faltar o venir corrupto: ordenar por ella dejaria que
        # un reloj desajustado cambiara con que se compara el usuario.
        $h = @(
            script:New-Apunte -Id 'la-de-fecha-mas-nueva' -DiasAtras 0
            script:New-Apunte -Id 'la-ultima-del-archivo' -DiasAtras 400
        )
        (Get-ReferenciaAnterior -Historial $h).Marca |
            Should -Be 'la-ultima-del-archivo' -Because 'manda el orden del archivo, no la fecha'
    }

    It 'una fecha ausente o ilegible no impide elegir referencia' {
        # No saber cuando fue no impide decir cuanto habia. Si esto
        # devolviera nulo, un historial con una fecha rota dejaria al
        # usuario sin comparacion para siempre.
        $h = @(
            [pscustomobject]@{ Tipo = 'analisis'; Marca = 'sin-fecha'; Elementos = 12 }
            [pscustomobject]@{ Tipo = 'analisis'; Marca = 'fecha-rota'; Fecha = 'ni-fecha-ni-nada'; Elementos = 7 }
        )
        (Get-ReferenciaAnterior -Historial $h).Marca | Should -Be 'fecha-rota'
    }

    It 'un historial que no es lista sino una entrada suelta tambien vale' {
        # Get-Historial devuelve un objeto SUELTO cuando el archivo tiene
        # un unico apunte: en 5.1 una coleccion de uno se desenvuelve, y
        # eso ya no es una lista. El primer analisis que un usuario repite
        # pasa exactamente por aqui.
        (Get-ReferenciaAnterior -Historial (script:New-Apunte -Id 'sola')).Marca | Should -Be 'sola'
    }

    It 'devuelve UNA entrada, no una lista de todas las que valian' {
        # Quien llama hace $anterior.Elementos. Si se devolvieran las tres,
        # ese campo seria una lista de tres numeros y la frase del resumen
        # saldria con los tres pegados.
        $h = @(
            script:New-Apunte -Id 'A1' -DiasAtras 9
            script:New-Apunte -Id 'A2' -DiasAtras 5
            script:New-Apunte -Id 'A3' -DiasAtras 1
        )
        @(Get-ReferenciaAnterior -Historial $h).Count | Should -Be 1
    }
}
