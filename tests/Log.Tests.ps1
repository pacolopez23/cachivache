<#
    Pruebas del registro de actividad: la cola concurrente que evita
    perder líneas durante el borrado, y el volcado de diagnóstico.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'Registro con cola concurrente (C-19)' {

    BeforeEach {
        # Cada prueba con su propia carpeta y su propio archivo de registro:
        # $script:RutaRegistro es estado de módulo compartido entre pruebas.
        $script:CarpetaRegistroPrueba = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:CarpetaRegistroPrueba -Force | Out-Null
        Initialize-Registro -CarpetaDatos $script:CarpetaRegistroPrueba | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:CarpetaRegistroPrueba -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'New-EstadoSincronizado incluye una ColaRegistro vacia' {
        $sync = New-EstadoSincronizado
        # -ActualValue en vez de tuberia: una ConcurrentQueue vacía es
        # enumerable y, si esta vacía, la tuberia no emite nada -- Should
        # nunca llegaria a evaluarse con el objeto de verdad.
        Should -ActualValue $sync.ColaRegistro -BeOfType [Collections.Concurrent.ConcurrentQueue[string]]
        $sync.ColaRegistro.IsEmpty | Should -BeTrue
    }

    It 'con -Sync, Write-Registro encola en vez de escribir al archivo' {
        $sync = New-EstadoSincronizado
        Write-Registro -Sync $sync -Nivel 'INFO' -Mensaje 'linea de prueba'

        $sync.ColaRegistro.IsEmpty | Should -BeFalse
        Get-Content -LiteralPath $script:RutaRegistro -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It 'sin -Sync, Write-Registro escribe al archivo al momento (modo consola)' {
        Write-Registro -Nivel 'INFO' -Mensaje 'linea directa'

        $contenido = Get-Content -LiteralPath $script:RutaRegistro
        $contenido | Should -Match 'linea directa'
    }

    It 'Invoke-VaciarColaRegistro vuelca las lineas encoladas, en orden, y vacia la cola' {
        $sync = New-EstadoSincronizado
        1..5 | ForEach-Object { Write-Registro -Sync $sync -Nivel 'BORRADO' -Mensaje "linea $_" }

        Invoke-VaciarColaRegistro -Sync $sync

        $sync.ColaRegistro.IsEmpty | Should -BeTrue
        $contenido = @(Get-Content -LiteralPath $script:RutaRegistro)
        $contenido.Count | Should -Be 5
        1..5 | ForEach-Object {
            $contenido[$_ - 1] | Should -Match "linea $_"
        }
    }

    It 'Invoke-VaciarColaRegistro no falla ni escribe nada con la cola vacia' {
        $sync = New-EstadoSincronizado
        { Invoke-VaciarColaRegistro -Sync $sync } | Should -Not -Throw
        Test-Path -LiteralPath $script:RutaRegistro | Should -BeFalse
    }

    It 'Invoke-VaciarColaRegistro ignora un $Sync que no es la tabla esperada' {
        { Invoke-VaciarColaRegistro -Sync ([pscustomobject]@{ Nada = $true }) } | Should -Not -Throw
        { Invoke-VaciarColaRegistro -Sync @{ SinColaRegistro = $true } } | Should -Not -Throw
    }

    It 'Write-CabeceraSesion encola una cabecera con el ID de sesion, version y perfil' {
        $sync = New-EstadoSincronizado
        Write-CabeceraSesion -Perfil 'equilibrado' -Admin $false -Sync $sync
        Invoke-VaciarColaRegistro -Sync $sync

        $contenido = Get-Content -LiteralPath $script:RutaRegistro -Raw
        $contenido | Should -Match ([regex]::Escape($script:IdSesion))
        $contenido | Should -Match 'equilibrado'
        $contenido | Should -Match 'Administrador: False'
    }

    It 'todas las lineas de una sesion llevan el mismo ID de sesion (T-05)' {
        $sync = New-EstadoSincronizado
        Write-CabeceraSesion -Perfil 'conservador' -Admin $true -Sync $sync
        Write-Registro -Sync $sync -Nivel 'BORRADO' -Mensaje 'algo borrado'
        Invoke-VaciarColaRegistro -Sync $sync

        $lineasNoVacias = @(Get-Content -LiteralPath $script:RutaRegistro | Where-Object { $_.Trim() })
        foreach ($linea in $lineasNoVacias) {
            $linea | Should -Match ([regex]::Escape("[$script:IdSesion]"))
        }
    }
}

Describe 'Lo que se ve en el panel es lo que hay en el archivo' {

    <#
        El panel de Registro pinta EXACTAMENTE lo que Invoke-VaciarColaRegistro
        devuelve, y esa misma función es la que escribe el archivo. Que
        devuelva justo lo que escribio es lo que sostiene la promesa del
        panel: "Copiar te da el mismo texto que hay en el archivo".

        Antes la ventana componia su propia versión corta de los mensajes
        por otro camino, y las líneas que escribia el runspace -una por
        elemento borrado, cada comando rechazado, los errores agrupados-
        solo llegaban al .log. El panel contaba bastante menos que el
        archivo sin que nada lo advirtiera.
    #>

    BeforeEach {
        $script:CarpetaLog = Join-Path ([IO.Path]::GetTempPath()) ('log_' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:CarpetaLog -Force | Out-Null
        Initialize-Registro -CarpetaDatos $script:CarpetaLog | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:CarpetaLog -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'devuelve exactamente las mismas lineas que acaba de escribir en el archivo' {
        $sync = New-EstadoSincronizado
        Write-Registro -Sync $sync -Nivel 'BORRADO'   -Mensaje 'C:\algo -> 10 MB'
        Write-Registro -Sync $sync -Nivel 'BLOQUEADO' -Mensaje 'comando rechazado'
        Write-Registro -Sync $sync -Nivel 'AVISO'     -Mensaje 'algo raro'

        $devueltas = @(Invoke-VaciarColaRegistro -Sync $sync)
        $enArchivo = @(Get-Content -LiteralPath $script:RutaRegistro)

        $devueltas.Count | Should -Be 3
        $enArchivo.Count | Should -Be 3
        for ($i = 0; $i -lt 3; $i++) {
            $devueltas[$i] | Should -BeExactly $enArchivo[$i] -Because 'la pantalla y el archivo no pueden divergir'
        }
    }

    It 'lo devuelto conserva el nivel, que en pantalla se perdia' {
        # El panel mostraba solo la hora y el texto: un AVISO y un INFO se
        # veian identicos y no había forma de escanear el registro buscando
        # problemas. Ahora la línea de pantalla es la del archivo, con su
        # nivel dentro.
        $sync = New-EstadoSincronizado
        Write-Registro -Sync $sync -Nivel 'BLOQUEADO' -Mensaje 'la guardia lo ha parado'

        $devueltas = @(Invoke-VaciarColaRegistro -Sync $sync)
        $devueltas[0] | Should -Match 'BLOQUEADO'
        $devueltas[0] | Should -Match 'la guardia lo ha parado'
    }

    It 'devuelve una lista vacia, y no $null, cuando no hay nada que volcar' {
        # La ventana hace @(...).Count sobre el resultado en cada pasada del
        # temporizador, cinco veces por segundo. Devolver $null funcionaria
        # por casualidad; devolver una lista vacía es lo que se promete.
        $sync = New-EstadoSincronizado
        @(Invoke-VaciarColaRegistro -Sync $sync).Count | Should -Be 0
        @(Invoke-VaciarColaRegistro -Sync ([pscustomobject]@{ Nada = $true })).Count | Should -Be 0
        @(Invoke-VaciarColaRegistro -Sync @{ SinColaRegistro = $true }).Count | Should -Be 0
    }

    It 'no devuelve dos veces la misma linea' {
        # Si devolviera lo mismo en dos pasadas seguidas, el panel repetiria
        # cada línea cinco veces por segundo mientras dura un análisis.
        $sync = New-EstadoSincronizado
        Write-Registro -Sync $sync -Mensaje 'una sola vez'

        @(Invoke-VaciarColaRegistro -Sync $sync).Count | Should -Be 1
        @(Invoke-VaciarColaRegistro -Sync $sync).Count | Should -Be 0
    }

    It 'devuelve las lineas aunque el archivo no se pueda escribir' {
        # Disco lleno o sin permisos: quedarse además sin ver nada en
        # pantalla convertiria un problema en dos.
        $sync = New-EstadoSincronizado
        Write-Registro -Sync $sync -Mensaje 'esto tiene que verse igual'

        $anterior = $script:RutaRegistro
        $script:RutaRegistro = Join-Path $script:CarpetaLog 'no/existe/este/camino.log'
        try {
            $devueltas = @(Invoke-VaciarColaRegistro -Sync $sync)
            $devueltas.Count | Should -Be 1
            $devueltas[0] | Should -Match 'esto tiene que verse igual'
        } finally {
            $script:RutaRegistro = $anterior
        }
    }
}

Describe 'Get-InformeDiagnostico (T-05)' {

    BeforeEach {
        $script:CarpetaRegistroPrueba = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:CarpetaRegistroPrueba -Force | Out-Null
        Initialize-Registro -CarpetaDatos $script:CarpetaRegistroPrueba | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:CarpetaRegistroPrueba -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'incluye version del programa, PowerShell y administrador' {
        $informe = Get-InformeDiagnostico -Admin $true -CarpetaDatos $script:CarpetaRegistroPrueba
        $informe | Should -Match ([regex]::Escape((Get-VersionCachivache)))
        $informe | Should -Match ([regex]::Escape([string]$PSVersionTable.PSVersion))
        $informe | Should -Match 'Administrador\s*:\s*True'
    }

    It 'no revienta sin registro previo para este mes' {
        { Get-InformeDiagnostico -CarpetaDatos $script:CarpetaRegistroPrueba } | Should -Not -Throw
        $informe = Get-InformeDiagnostico -CarpetaDatos $script:CarpetaRegistroPrueba
        $informe | Should -Match 'todavía no existe registro'
    }

    It 'con -LineasRegistro 0 no incluye el bloque del registro' {
        Write-Registro -Nivel 'INFO' -Mensaje 'linea que no deberia aparecer'
        $informe = Get-InformeDiagnostico -CarpetaDatos $script:CarpetaRegistroPrueba -LineasRegistro 0
        $informe | Should -Not -Match 'linea que no deberia aparecer'
    }

    It 'incluye las ultimas N lineas del registro cuando existen' {
        1..5 | ForEach-Object { Write-Registro -Nivel 'INFO' -Mensaje "linea numero $_" }
        $informe = Get-InformeDiagnostico -CarpetaDatos $script:CarpetaRegistroPrueba -LineasRegistro 3

        $informe | Should -Match 'linea numero 5'
        $informe | Should -Match 'linea numero 3'
        $informe | Should -Not -Match 'linea numero 1'
    }

    It 'Get-DescripcionSistema nunca lanza, con o sin CIM disponible' {
        { Get-DescripcionSistema } | Should -Not -Throw
        Get-DescripcionSistema | Should -Not -BeNullOrEmpty
    }
}

Describe 'El historial se lee igual en PowerShell 5.1 que en 7' {

    <#
        El fallo que tiro la ventana al arrancar, y que las pruebas no
        podian ver porque corren en PowerShell 7.

        ConvertFrom-Json NO enumera igual en las dos versiones: en 5.1 un
        array de JSON sale de la tuberia como UN objeto de tipo Object[];
        desde la 6 sale enumerado. Con "@($texto | ConvertFrom-Json)", en
        5.1 el resultado era una lista de un elemento que era, a su vez, la
        lista entera.

        Aquí no se puede cambiar de versión de PowerShell, así que se
        reproduce la FORMA que produce 5.1 -una lista que contiene una
        lista- y se exige que Get-Historial la devuelva plana igualmente.
        Es más robusto que probar la versión: el arreglo tiene que valer
        para cualquiera.
    #>

    BeforeEach {
        $script:CarpetaHist = Join-Path ([IO.Path]::GetTempPath()) ('hist_' + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:CarpetaHist -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:CarpetaHist -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'aplana una lista que contiene una lista, que es lo que devuelve 5.1' {
        # El JSON es identico en las dos versiones; lo que cambia es como lo
        # entrega ConvertFrom-Json. Se simula devolviendo el array envuelto.
        $entradas = @(
            [pscustomobject]@{ Fecha = '2026-08-19T10:00:00'; Tipo = 'limpieza'; Bytes = 100.0; Elementos = 3; Perfil = 'equilibrado' }
            [pscustomobject]@{ Fecha = '2026-08-19T11:00:00'; Tipo = 'analisis'; Bytes = 200.0; Elementos = 7; Perfil = 'equilibrado' }
        )
        Set-Content -LiteralPath (Join-Path $script:CarpetaHist 'historial.json') -Value ($entradas | ConvertTo-Json -Depth 5)
        Mock ConvertFrom-Json { , $entradas }   # la coma fuerza "un solo objeto que es un array"

        $leidas = @(Get-Historial -CarpetaDatos $script:CarpetaHist)
        $leidas.Count | Should -Be 2 -Because 'la lista tiene que llegar plana, no anidada'
        $leidas[0].Tipo | Should -Be 'limpieza'
        $leidas[1].Bytes | Should -Be 200.0
    }

    It 'Get-ResumenHistorial no revienta con el historial anidado de 5.1' {
        # Este era el síntoma: la entrada falsa pasaba el filtro y
        # [double]$entrada.Bytes -que era un array- lanzaba, tirando el
        # arranque de la ventana entera.
        $entradas = @(
            [pscustomobject]@{ Tipo = 'limpieza'; Bytes = 100.0 }
            [pscustomobject]@{ Tipo = 'limpieza'; Bytes = 250.0 }
        )
        Set-Content -LiteralPath (Join-Path $script:CarpetaHist 'historial.json') -Value ($entradas | ConvertTo-Json -Depth 5)
        Mock ConvertFrom-Json { , $entradas }

        { Get-ResumenHistorial -CarpetaDatos $script:CarpetaHist } | Should -Not -Throw
        $resumen = Get-ResumenHistorial -CarpetaDatos $script:CarpetaHist
        $resumen.Limpiezas    | Should -Be 2
        $resumen.BytesTotales | Should -Be 350.0
    }

    It 'con una sola entrada tambien funciona (el caso que NO fallaba)' {
        # ConvertTo-Json de un elemento escribe un objeto suelto, no un
        # array, y por eso el fallo no aparecio hasta la segunda ejecución.
        $una = [pscustomobject]@{ Tipo = 'limpieza'; Bytes = 42.0 }
        Set-Content -LiteralPath (Join-Path $script:CarpetaHist 'historial.json') -Value ($una | ConvertTo-Json -Depth 5)

        @(Get-Historial -CarpetaDatos $script:CarpetaHist).Count | Should -Be 1
        (Get-ResumenHistorial -CarpetaDatos $script:CarpetaHist).BytesTotales | Should -Be 42.0
    }

    It 'un historial editado a mano con basura no impide leer el resto' {
        $texto = @'
[
  { "Tipo": "limpieza", "Bytes": 100 },
  { "Tipo": "limpieza", "Bytes": [1, 2, 3] },
  { "Tipo": "limpieza", "Bytes": "no soy un numero" },
  { "Tipo": "limpieza" },
  { "Tipo": "limpieza", "Bytes": 50 }
]
'@
        Set-Content -LiteralPath (Join-Path $script:CarpetaHist 'historial.json') -Value $texto

        { Get-ResumenHistorial -CarpetaDatos $script:CarpetaHist } | Should -Not -Throw
        $resumen = Get-ResumenHistorial -CarpetaDatos $script:CarpetaHist
        $resumen.Limpiezas    | Should -Be 5
        $resumen.BytesTotales | Should -Be 150.0 -Because 'lo ilegible cuenta como cero, pero lo bueno se suma'
    }

    It 'un JSON roto del todo devuelve lista vacia en vez de lanzar' {
        Set-Content -LiteralPath (Join-Path $script:CarpetaHist 'historial.json') -Value '{ esto no es json'
        @(Get-Historial -CarpetaDatos $script:CarpetaHist).Count | Should -Be 0
        { Get-ResumenHistorial -CarpetaDatos $script:CarpetaHist } | Should -Not -Throw
    }
}

Describe 'ConvertTo-DoubleSeguro' {

    It 'convierte lo que es convertible: <Valor>' -ForEach @(
        @{ Valor = 5;        Esperado = 5.0 }
        @{ Valor = '12.5';   Esperado = 12.5 }
        @{ Valor = 0;        Esperado = 0.0 }
        @{ Valor = -3.5;     Esperado = -3.5 }
    ) {
        ConvertTo-DoubleSeguro $Valor | Should -Be $Esperado
    }

    It 'devuelve cero, sin lanzar, ante lo que no lo es' {
        ConvertTo-DoubleSeguro $null            | Should -Be 0.0
        ConvertTo-DoubleSeguro @(1, 2, 3)       | Should -Be 0.0
        ConvertTo-DoubleSeguro 'hola'           | Should -Be 0.0
        ConvertTo-DoubleSeguro ([pscustomobject]@{ a = 1 }) | Should -Be 0.0
        { ConvertTo-DoubleSeguro @() }          | Should -Not -Throw
    }

    It 'no intenta adivinar sumando ni tomando el primero de un array' {
        # Inventarse un dato es peor que devolver cero: cero se nota.
        ConvertTo-DoubleSeguro @(10, 20) | Should -Be 0.0
    }

    It 'un array de UN elemento tampoco es un numero' {
        # Comprobado aparte porque es el caso donde uno esperaria que
        # PowerShell "ayudase" desenvolviendo el único elemento. En
        # PowerShell 7 no lo hace: [double]@(5) lanza igual que
        # [double]@(1,2,3). Se fija por contrato para que la respuesta sea
        # la misma en cualquier versión, que es justo la leccion del fallo
        # que obligo a escribir esta función.
        ConvertTo-DoubleSeguro @(5) | Should -Be 0.0
    }
}

Describe 'COR-06: Get-DetalleExcepcion dice DONDE ha fallado' {

    <#
        Nacio de un fallo real: la ventana enseñaba "No se ha podido
        guardar el informe: Los tipos de argumentos no coinciden" y no
        habia por donde empezar a mirar. Ni el usuario podia actuar, ni
        quien recibiera la incidencia sabia que archivo abrir.

        SECURITY.md pide adjuntar el registro para reportar un fallo. Un
        registro lleno de mensajes sin sitio convierte cada incidencia en
        una conversacion de ida y vuelta antes de mirar una sola linea.
    #>

    BeforeAll {
        $script:Raiz = Split-Path $PSScriptRoot -Parent
        . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

        # Un error REAL nacido en un archivo real, para que InvocationInfo
        # traiga nombre de archivo y numero de linea de verdad. Fabricar un
        # ErrorRecord a mano no probaria nada: lo que se comprueba es que
        # la funcion sabe leer lo que PowerShell rellena solo.
        $script:Guion = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-err-' + [guid]::NewGuid() + '.ps1')
        Set-Content -LiteralPath $script:Guion -Encoding UTF8 -Value @(
            'function Invoke-QueFalla {'
            '    [CmdletBinding()] param()'
            '    throw [InvalidOperationException]::new("algo se ha torcido")'
            '}')
        . $script:Guion

        $script:Capturado = $null
        try { Invoke-QueFalla } catch { $script:Capturado = $_ }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Guion -Force -ErrorAction SilentlyContinue
    }

    It 'la prueba ha capturado un error de verdad: si no, no prueba nada' {
        $script:Capturado | Should -Not -BeNullOrEmpty
        $script:Capturado.InvocationInfo.ScriptName | Should -Not -BeNullOrEmpty
    }

    It 'conserva el mensaje original' {
        Get-DetalleExcepcion -ErrorRecord $script:Capturado | Should -BeLike '*algo se ha torcido*'
    }

    It 'dice el TIPO de excepcion' {
        # "Los tipos de argumentos no coinciden" es ArgumentException;
        # el mismo texto podria venir de otra cosa. El tipo acota.
        Get-DetalleExcepcion -ErrorRecord $script:Capturado | Should -BeLike '*InvalidOperationException*'
    }

    It 'dice el archivo y la linea' {
        $detalle = Get-DetalleExcepcion -ErrorRecord $script:Capturado
        $detalle | Should -BeLike ('*' + (Split-Path -Leaf $script:Guion) + ':*')
        $detalle | Should -Match ':\d+\]'
    }

    It 'solo anyade la pila cuando se pide' {
        # En un cuadro de dialogo la pila no la lee nadie y tapa el
        # mensaje; en el registro es lo unico que sirve.
        $corto = Get-DetalleExcepcion -ErrorRecord $script:Capturado
        $largo = Get-DetalleExcepcion -ErrorRecord $script:Capturado -ConPila

        $corto.Contains([Environment]::NewLine) | Should -BeFalse -Because 'sin -ConPila cabe en una linea'
        $largo.Length | Should -BeGreaterThan $corto.Length
        $largo | Should -BeLike '*Invoke-QueFalla*'
    }

    It 'no revienta con un error sin sitio ni con nulo' {
        # Los cierres de la ventana son scriptblocks creados al vuelo: su
        # InvocationInfo puede venir sin ScriptName. Un diagnostico que
        # falla al diagnosticar es peor que no tenerlo.
        $sinSitio = $null
        try { & { throw 'suelto' } } catch { $sinSitio = $_ }

        { Get-DetalleExcepcion -ErrorRecord $sinSitio } | Should -Not -Throw
        Get-DetalleExcepcion -ErrorRecord $sinSitio | Should -BeLike '*suelto*'
        Get-DetalleExcepcion -ErrorRecord $null     | Should -Be '(error desconocido)'
    }
}

Describe 'COR-06: guardar el informe y abrirlo son dos cosas distintas' {

    It 'un fallo al abrir el Explorador no puede decir que no se ha guardado' {
        # Estaban en el mismo try: si el informe se escribia bien pero
        # Start-Process fallaba, la ventana decia "No se ha podido guardar
        # el informe" con el archivo ya en el disco.
        # Se quitan los comentarios ANTES de buscar. La primera version de
        # esta prueba fallaba porque encontraba las dos cosas dentro del
        # comentario que explica el arreglo, no en el codigo. Es la tercera
        # vez que pasa en este proyecto: aqui se comentan mucho los
        # porques, asi que cualquier prueba que lea el codigo como texto
        # tiene que mirar solo el codigo.
        $lineas = Get-Content -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) 'src/UI/Window.Eventos.ps1')
        $texto = ($lineas | Where-Object { $_ -notmatch '^\s*#' }) -join [Environment]::NewLine

        $exportar = $texto.IndexOf('$exportar = {')
        $exportar | Should -BeGreaterThan -1

        # Dentro del cierre de exportar, Start-Process tiene que aparecer
        # DESPUES del catch que informa del guardado.
        $trozo   = $texto.Substring($exportar, 3000)
        $catch   = $trozo.IndexOf('No se ha podido guardar el informe')
        $abrir   = $trozo.IndexOf('Start-Process')

        $catch | Should -BeGreaterThan -1
        $abrir | Should -BeGreaterThan $catch -Because (
            'abrir el Explorador va en su propio try, despues del que guarda')
    }

    It 'los catch del informe usan Get-DetalleExcepcion, no el mensaje pelado' {
        $raiz = Split-Path $PSScriptRoot -Parent
        foreach ($archivo in @('src/UI/Window.Eventos.ps1',
                               'src/UI/Window.Analisis.ps1',
                               'src/UI/Window.Eliminacion.ps1')) {
            $texto = Get-Content -Raw -LiteralPath (Join-Path $raiz $archivo)
            if ($texto -match 'podido (guardar|generar) el informe') {
                $texto | Should -Match '(?s)podido (guardar|generar) el informe.{0,200}Get-DetalleExcepcion' -Because $archivo
            }
        }
    }
}
