<#
    El modo consola, que estaba al 0 % de cobertura.

    POR QUE IMPORTA ESTE ARCHIVO. src/Cli/Cli.ps1 son 330 lineas de
    PowerShell corriente -ni una de WPF- que se podian haber ejecutado
    desde una prueba desde el primer dia, y nadie lo hizo nunca. No es el
    camino secundario: es el que la documentacion recomienda para la
    primera ejecucion sin riesgo, y el que usa una tarea programada.
    Encima orquesta el analisis, el informe, el historial y el borrado, o
    sea que un fallo aqui no da un resultado raro: borra o deja de borrar.

    COMO SE PRUEBA ALGO QUE SOLO ESCRIBE EN PANTALLA. Write-Host va al
    flujo de informacion, asi que "6>&1" lo captura. Todo lo que sale de
    Invoke-CachivacheCli se recoge asi y se lee como texto.

    QUE NO SE TOCA. Nada real: los modulos son de mentira y emiten lo que
    se les deje preparado, la carpeta de datos es temporal y se borra al
    final, y el unico borrado de verdad ocurre sobre un archivo que crea
    esta misma prueba dentro de esa carpeta temporal.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent

    # SE CARGA COMO LO CARGA EL PROGRAMA, Y ESO NO ES UN DETALLE.
    #
    # Aqui hubo un modulo. Al escribir estas pruebas, la que borra de verdad
    # fallaba con "El termino Invoke-VaciarColaRegistro no se reconoce", y se
    # dio por hecho que era una rareza de Pester: se rodeo importando el
    # nucleo como MODULO, que hace globales las funciones y hace desaparecer
    # el error.
    #
    # Era un fallo del programa. La integracion continua lo demostro dias
    # despues, con el modo consola muriendo AL BORRAR en una limpieza real:
    # el cierre de avance llevaba .GetNewClosure(), y desde un cierre no se
    # ven las funciones del nucleo porque Cachivache.ps1 lo dot-sourcea en
    # ambito de script y no en global.
    #
    # La leccion, que vale para cualquier prueba de este proyecto: cuando el
    # arnes de pruebas necesita un apanyo que el programa no tiene, el apanyo
    # NO es la solucion, es el sintoma. Se dot-sourcea igual que
    # Cachivache.ps1 para que lo que falle aqui sea lo que falla alli.
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Cli')  'Cli.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Cli')  'Espacio.ps1')

    # Carpeta de datos propia: el historial, el registro y los informes
    # van aqui y no a la carpeta de verdad del usuario que ejecute esto.
    $script:Datos = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-cli-' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Datos -Force)
    [void](Initialize-Registro -CarpetaDatos $script:Datos)

    # Guardia con carpetas personales vacias, igual que en Embudo.Tests:
    # asi el veredicto depende solo de la ruta del caso y no de donde se
    # esten ejecutando las pruebas.
    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio = ''; Documentos = ''; Descargas = ''
        Imagenes   = ''; Musica     = ''; Videos     = ''; CarpetaDatos = ''
    })

    function script:New-ConfiguracionDePrueba {
        param([switch] $Admin, [string] $Perfil = 'equilibrado')
        return [pscustomobject]@{
            Equipo                = 'EQUIPO-PRUEBA'
            Perfil                = $Perfil
            Admin                 = [bool]$Admin
            Unidad                = 'C:'
            CarpetaDatos          = $script:Datos
            UnidadesSeleccionadas = @('C:')
            RutasExcluidas        = @()
            Permanente            = $false
            ZonasUsuario          = @()
        }
    }

    # Los modulos de mentira emiten lo que haya en estas variables. De
    # ambito de script y no cierres, por el mismo motivo que en
    # Embudo.Tests: un cierre se ejecuta en un modulo dinamico donde no se
    # ven las funciones del nucleo.
    $script:EmisionA = @()
    $script:EmisionB = @()
    $script:ReventarB = $false

    $script:ModuloA = New-ModuloLimpieza -Id 'uno' -Orden 1 `
        -Nombre 'Modulo uno' -Descripcion 'Emite lo de EmisionA.' `
        -Buscar { param($Configuracion, $Sync) foreach ($c in $script:EmisionA) { $c } }

    $script:ModuloB = New-ModuloLimpieza -Id 'dos' -Orden 2 `
        -Nombre 'Modulo dos' -Descripcion 'Emite lo de EmisionB, o revienta.' `
        -Buscar {
            param($Configuracion, $Sync)
            if ($script:ReventarB) { throw 'el modulo dos ha reventado a proposito' }
            foreach ($c in $script:EmisionB) { $c }
        }

    $script:ModuloAdmin = New-ModuloLimpieza -Id 'tres' -Orden 3 `
        -Nombre 'Modulo de administrador' -Descripcion 'No deberia correr sin permisos.' `
        -RequiereAdmin -Buscar { param($Configuracion, $Sync) $script:EmisionA }

    # Informativo: exento de la guardia, en la unidad elegida, fuera de lo
    # excluido. Pasa el embudo entero sin depender del sistema operativo.
    function script:New-CandidatoInformativo {
        param([string] $Nombre = 'informativo', [double] $Bytes = 100)
        return New-Candidato -ModuloId 'uno' -Categoria 'Pruebas' -Nombre $Nombre `
                             -Ruta ('C:\normal\' + $Nombre) -Bytes $Bytes `
                             -Metodo 'Informativo' -Raices @()
    }

    # Borrable y premarcado: riesgo bajo y sin aviso, que es lo que
    # Test-DebeVenirMarcado exige. La ruta es real y esta dentro de la
    # carpeta temporal, para que el unico borrado de verdad del archivo
    # ocurra donde no importa.
    function script:New-CandidatoBorrable {
        param([string] $Nombre, [double] $Bytes = 1024)
        $ruta = Join-Path $script:Datos $Nombre
        return New-Candidato -ModuloId 'uno' -Categoria 'Pruebas' -Nombre $Nombre `
                             -Ruta $ruta -Bytes $Bytes -Metodo 'Ruta' -Riesgo 'Bajo' `
                             -Raices @($script:Datos)
    }

    function script:Invoke-Cli {
        param([hashtable] $Argumentos = @{})
        if (-not $Argumentos.ContainsKey('Configuracion')) {
            $Argumentos['Configuracion'] = script:New-ConfiguracionDePrueba
        }
        if (-not $Argumentos.ContainsKey('Modulos')) {
            $Argumentos['Modulos'] = @($script:ModuloA, $script:ModuloB)
        }
        $Argumentos['Confirm'] = $false
        # El $null absorbe el codigo de retorno. Sin el, el 0 o el 1 que
        # devuelve la funcion se cuela en la salida capturada y una prueba
        # que exige silencio absoluto encuentra un "0".
        $salida = & { $null = Invoke-CachivacheCli @Argumentos } 6>&1
        return ($salida | ForEach-Object { [string]$_ }) -join "`n"
    }

    # La ULTIMA entrada del historial, que es la que acaba de escribirse.
    # Add-EntradaHistorial anyade al final, asi que [0] es la mas antigua:
    # pedir [0] daba la entrada de otra prueba y el fallo aparecia donde
    # no estaba la causa.
    function script:Get-UltimaEntradaHistorial {
        param([string] $Tipo = '')
        $todas = @(Get-Historial -CarpetaDatos $script:Datos)
        if ($Tipo) { $todas = @($todas | Where-Object { $_.Tipo -eq $Tipo }) }
        if ($todas.Count -eq 0) { return $null }
        return $todas[-1]
    }
}

AfterAll {
    if ($script:Datos -and (Test-Path -LiteralPath $script:Datos)) {
        Remove-Item -LiteralPath $script:Datos -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Write-Linea: el unico sitio por el que sale texto' {

    It 'el estilo <Estilo> escribe el texto tal cual' -ForEach @(
        @{ Estilo = 'normal' }, @{ Estilo = 'titulo' }, @{ Estilo = 'ok' }
        @{ Estilo = 'aviso'  }, @{ Estilo = 'error'  }, @{ Estilo = 'tenue' }
    ) {
        $salida = (& { Write-Linea 'hola que tal' $Estilo } 6>&1 | ForEach-Object { [string]$_ }) -join ''
        $salida | Should -Be 'hola que tal'
    }

    It 'un estilo que no existe se rechaza en vez de pintarse de cualquier color' {
        # El ValidateSet no es decoracion: sin el, un estilo mal escrito
        # saldria por el "default" y la linea perderia su color sin que
        # nadie se enterara. Un aviso que se pinta como texto normal es
        # justo el fallo de [USO-02], pero en consola.
        { Write-Linea 'x' 'chillon' } | Should -Throw
    }

    It 'la cabecera subraya con el mismo ancho que el titulo' {
        $lineas = @(& { Write-Cabecera 'Analisis' } 6>&1 | ForEach-Object { [string]$_ })
        $subrayado = @($lineas | Where-Object { $_ -match '^\s*-+$' })
        $subrayado.Count | Should -Be 1
        $subrayado[0].Trim().Length | Should -Be 'Analisis'.Length
    }
}

Describe 'Invoke-CachivacheCli: el analisis' {
    # Cada prueba empieza con los modulos de mentira en silencio. Sin esto,
    # lo que emite una prueba se cuela en la siguiente y el fallo aparece
    # en un sitio que no tiene nada que ver.
    BeforeEach {
        $script:EmisionA  = @()
        $script:EmisionB  = @()
        $script:ReventarB = $false
    }


    It 'sin ningun modulo que ejecutar devuelve 1 y lo dice' {
        # Devolver 0 aqui seria decirle a una tarea programada que todo
        # fue bien cuando no se ha mirado nada.
        $cfg = script:New-ConfiguracionDePrueba
        $salida = script:Invoke-Cli @{ Configuracion = $cfg; Modulos = @(); Ids = @() }
        $salida | Should -Match 'No hay ningún módulo'
        Invoke-CachivacheCli -Configuracion $cfg -Modulos @() -Silencioso -Confirm:$false |
            Should -Be 1
    }

    It 'sin -Ejecutar avisa de que no ha borrado nada' {
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $salida = script:Invoke-Cli
        $salida | Should -Match 'solo un análisis'
        $salida | Should -Match '-Ejecutar'
    }

    It 'las dos primeras cifras del resumen hablan de lo mismo' {
        # [INT-14]: "Elementos encontrados" contaba TODO y "Recuperable
        # total" solo los borrables, asi que salian dos numeros que no
        # cuadraban en el mismo bloque y nadie sabia por que.
        $script:EmisionA = @(
            (script:New-CandidatoInformativo -Nombre 'info-1' -Bytes 10)
            (script:New-CandidatoInformativo -Nombre 'info-2' -Bytes 20)
        )
        # El archivo tiene que existir de verdad: una de las cuatro reglas
        # del embudo es "Candidato existente", asi que un borrable
        # inventado se cae antes de llegar al resumen y la cuenta saldria
        # 2 en vez de 3. Costo una prueba que fallaba culpando al resumen.
        [IO.File]::WriteAllText((Join-Path $script:Datos 'borrable-1'), 'x' * 500)
        $script:EmisionB = @(script:New-CandidatoBorrable -Nombre 'borrable-1' -Bytes 500)
        $salida = script:Invoke-Cli

        $salida | Should -Match 'Elementos encontrados : 3 \(1 recuperables, 2 solo informativos\)'
    }

    It 'un modulo que revienta sale en el aviso de lista incompleta' {
        # [CNF-04]. La ventana lo ensenya en una franja; si la consola se
        # lo callara tendriamos otra vez dos caminos contando cosas
        # distintas, que es el fallo de [ARQ-01].
        $script:EmisionA  = @(script:New-CandidatoInformativo)
        $script:ReventarB = $true
        $salida = script:Invoke-Cli

        $salida | Should -Match 'ATENCIÓN: esta lista está incompleta'
        $salida | Should -Match 'Modulo dos'
        $salida | Should -Match '1 módulo no se ha podido completar'
    }

    It 'el modulo que fallo NO se anota en el historial como revisado' {
        # Anotarlo convierte el historial en otro sitio donde el programa
        # dice haber mirado lo que no miro.
        $script:EmisionA  = @(script:New-CandidatoInformativo)
        $script:ReventarB = $true
        [void](script:Invoke-Cli)

        $ultima = script:Get-UltimaEntradaHistorial -Tipo 'analisis'
        $ultima.Incompleto | Should -BeTrue
        $ultima.Modulos    | Should -Contain 'uno'
        $ultima.Modulos    | Should -Not -Contain 'dos'
        $ultima.Motivo     | Should -Match 'Modulo dos'
    }

    It 'con todo bien, el historial no dice que sea incompleto' {
        $script:EmisionA = @(script:New-CandidatoInformativo)
        [void](script:Invoke-Cli)
        $ultima = script:Get-UltimaEntradaHistorial -Tipo 'analisis'
        $ultima.Incompleto | Should -BeFalse
        $ultima.Modulos    | Should -Contain 'dos'
    }

    It '-Ids elige modulos por nombre y se salta el perfil' {
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $script:EmisionB = @(script:New-CandidatoInformativo -Nombre 'de-b')
        $salida = script:Invoke-Cli @{ Ids = @('uno') }
        $salida | Should -Match 'Modulo uno'
        $salida | Should -Not -Match 'Modulo dos'
    }

    It 'un modulo que necesita administrador no corre sin permisos' {
        $cfg = script:New-ConfiguracionDePrueba   # Admin a $false
        $salida = script:Invoke-Cli @{
            Configuracion = $cfg
            Modulos       = @($script:ModuloA, $script:ModuloAdmin)
            Ids           = @('uno', 'tres')
        }
        $salida | Should -Not -Match 'Modulo de administrador'
    }

    It '-Silencioso no escribe absolutamente nada' {
        # Una tarea programada que escupe cuarenta lineas por consola cada
        # noche es una tarea que alguien acaba quitando.
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $salida = script:Invoke-Cli @{ Silencioso = $true }
        $salida | Should -BeNullOrEmpty
    }

    It 'nunca deja un hueco de formato sin rellenar' {
        # La trampa que ha mordido cuatro veces en este proyecto: "-f" se
        # enlaza mas fuerte que "+", asi que 'texto {0}' + 'mas' -f $x deja
        # el {0} literal en pantalla. Aqui se mira la salida ENTERA, con
        # modulos que dan resultado, uno que revienta y un informe.
        $script:EmisionA  = @(
            (script:New-CandidatoInformativo -Nombre 'info' -Bytes 4096)
            (script:New-CandidatoBorrable -Nombre 'hueco-1' -Bytes 2048)
        )
        $script:ReventarB = $true
        $salida = script:Invoke-Cli @{ Informe = (Join-Path $script:Datos 'huecos.html') }

        $salida | Should -Not -Match '\{\d+[,:][^}]*\}'
        $salida | Should -Not -Match '\{\d+\}'
    }
}

Describe 'Invoke-CachivacheCli: el informe' {
    # Cada prueba empieza con los modulos de mentira en silencio. Sin esto,
    # lo que emite una prueba se cuela en la siguiente y el fallo aparece
    # en un sitio que no tiene nada que ver.
    BeforeEach {
        $script:EmisionA  = @()
        $script:EmisionB  = @()
        $script:ReventarB = $false
    }


    It 'la extension <Extension> produce un archivo' -ForEach @(
        @{ Extension = 'html' }, @{ Extension = 'csv' }, @{ Extension = 'json' }
    ) {
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $ruta = Join-Path $script:Datos ('informe-' + $Extension + '.' + $Extension)
        $salida = script:Invoke-Cli @{ Informe = $ruta }

        Test-Path -LiteralPath $ruta | Should -BeTrue
        $salida | Should -Match 'Informe guardado'
    }

    It 'sin extension se guarda como html, y se dice el nombre de verdad' {
        # Decir "guardado en informe" y dejar "informe.html" en el disco es
        # una ruta que el usuario no encuentra.
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $ruta = Join-Path $script:Datos 'sin-extension'
        $salida = script:Invoke-Cli @{ Informe = $ruta }

        Test-Path -LiteralPath ($ruta + '.html') | Should -BeTrue
        $salida | Should -Match 'sin-extension\.html'
    }

    It 'si el informe no se puede guardar, se dice y el analisis sigue' {
        # Un informe es lo ultimo que puede tumbar un analisis que ya se
        # ha hecho.
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $carpetaQueNoExiste = Join-Path (Join-Path $script:Datos 'no-existe') 'tampoco'
        $salida = script:Invoke-Cli @{ Informe = (Join-Path $carpetaQueNoExiste 'x.html') }

        $salida | Should -Match 'No se ha podido guardar el informe'
        $salida | Should -Match 'Elementos encontrados'
    }
}

Describe 'Invoke-CachivacheCli: eliminar y simular' {
    # Cada prueba empieza con los modulos de mentira en silencio. Sin esto,
    # lo que emite una prueba se cuela en la siguiente y el fallo aparece
    # en un sitio que no tiene nada que ver.
    BeforeEach {
        $script:EmisionA  = @()
        $script:EmisionB  = @()
        $script:ReventarB = $false
    }


    It 'con -Ejecutar y nada marcado no borra ni promete nada' {
        # Solo informativos: no hay nada que se marque solo.
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $salida = script:Invoke-Cli @{ Ejecutar = $true }
        $salida | Should -Match 'No hay nada marcado'
    }

    It '-Simular habla en condicional y grita que no ha borrado nada' {
        # [CNF-02]. Un resumen que diga "eliminados" cuando no se ha
        # eliminado nada es peor que no dar resumen.
        $archivo = Join-Path $script:Datos 'simulado.tmp'
        [IO.File]::WriteAllText($archivo, 'x' * 500)
        $script:EmisionA = @(script:New-CandidatoBorrable -Nombre 'simulado.tmp' -Bytes 500)

        $salida = script:Invoke-Cli @{ Ejecutar = $true; Simular = $true }

        $salida | Should -Match 'Se habrian eliminado'
        $salida | Should -Match 'NO SE HA BORRADO NADA'
        $salida | Should -Not -Match 'Elementos eliminados'
        Test-Path -LiteralPath $archivo | Should -BeTrue -Because 'simular no borra'
    }

    It 'una simulacion NO se anota en el historial' {
        # Un historial con limpiezas que no ocurrieron es justo el tipo de
        # mentira que esta auditoria lleva corrigiendo. Ver [SEG-20].
        $archivo = Join-Path $script:Datos 'no-historial.tmp'
        [IO.File]::WriteAllText($archivo, 'x' * 300)
        $script:EmisionA = @(script:New-CandidatoBorrable -Nombre 'no-historial.tmp' -Bytes 300)

        [void](script:Invoke-Cli @{ Ejecutar = $true; Simular = $true })

        $limpiezas = @(Get-Historial -CarpetaDatos $script:Datos | Where-Object { $_.Tipo -eq 'limpieza' })
        $limpiezas.Count | Should -Be 0
    }

    It 'con -Ejecutar de verdad borra, lo dice, y lo anota' {
        # El unico borrado real de todo el archivo, sobre un archivo que
        # crea esta misma prueba dentro de la carpeta temporal.
        $archivo = Join-Path $script:Datos 'a-borrar.tmp'
        [IO.File]::WriteAllText($archivo, 'x' * 700)
        $script:EmisionA = @(script:New-CandidatoBorrable -Nombre 'a-borrar.tmp' -Bytes 700)

        # Permanente: aqui se borra de verdad, y la papelera de Windows
        # va por Microsoft.VisualBasic.FileIO, que no existe donde se
        # ejecutan estas pruebas. Lo que se comprueba es el camino del
        # modo consola -que marca, que borra, que lo cuenta y que lo
        # anota-, no la papelera, que tiene sus propias pruebas y su
        # apartado en el banco.
        $cfg = script:New-ConfiguracionDePrueba
        $cfg.Permanente = $true
        $salida = script:Invoke-Cli @{ Ejecutar = $true; Configuracion = $cfg }

        Test-Path -LiteralPath $archivo | Should -BeFalse
        $salida | Should -Match 'Elementos eliminados : 1'
        $salida | Should -Not -Match 'Se habrian eliminado'

        $limpiezas = @(Get-Historial -CarpetaDatos $script:Datos | Where-Object { $_.Tipo -eq 'limpieza' })
        $limpiezas.Count | Should -BeGreaterOrEqual 1
    }
}

Describe 'invariante: un informe que no se puede escribir NO se anuncia como guardado' {
    BeforeEach {
        $script:EmisionA  = @()
        $script:EmisionB  = @()
        $script:ReventarB = $false
    }


    It 'NINGUNA escritura a disco de src/ se hace sin -ErrorAction Stop' {
        # EL FALLO QUE ENCONTRO ESTA PRUEBA, y merece leerse entero.
        #
        # Set-Content y Export-Csv sobre una carpeta que no existe dan un
        # error NO TERMINANTE: la funcion sigue, termina como si nada y no
        # lanza. Los cuatro sitios que exportan van dentro de un try/catch
        # de quien llama, asi que el catch NO SE DISPARABA NUNCA: la
        # consola escribia "Informe guardado en ..." sobre un archivo
        # inexistente, y ademas anotaba esa ruta en el historial, con lo
        # que la ventana ofrecia despues una tarjeta para abrir un informe
        # que no se escribio jamas.
        #
        # Es la misma familia que [COR-01]: el programa afirmando haber
        # hecho algo que no hizo. Se ata por texto porque lo que falla es
        # una AUSENCIA, y una ausencia no lanza nada que se pueda capturar.
        #
        # POR QUE ESTA PRUEBA MIRA AHORA TODO src/ Y NO DOS ARCHIVOS.
        #
        # Nacio nombrando Report.ps1 y ReportEspacio.ps1 y exigiendo
        # exactamente cuatro escrituras. Con eso protegia los cuatro
        # exportadores que la motivaron... y a nadie mas. El dia que se
        # fue a probar Export-Preferencias aparecio un QUINTO sitio con
        # el mismo fallo exacto -las preferencias se perdian en silencio
        # al cerrar la ventana- y un SEXTO en Historial.ps1, donde un
        # temporal truncado se instalaba encima del historial bueno.
        # Los dos llevaban ahi desde siempre, delante de una invariante
        # verde.
        #
        # La leccion, que esta en docs/RELEVO.md: una invariante que
        # enumera los sitios donde ya sabemos que hubo un fallo no es una
        # invariante, es una lista de fallos pasados. La pregunta correcta
        # no era "hacen bien estos cuatro?" sino "hay alguno mal?".
        $cmdlets = 'Set-Content|Export-Csv|Out-File|Add-Content|Export-Clixml'
        $carpeta = Join-Path $script:Raiz 'src'
        $escrituras = @()
        foreach ($archivo in @(Get-ChildItem -LiteralPath $carpeta -Recurse -Force |
                               Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.ps1' })) {
            $n = 0
            foreach ($linea in @([IO.File]::ReadAllText($archivo.FullName) -split "`r?`n")) {
                $n++
                if ($linea -match '^\s*#')       { continue }
                if ($linea -notmatch $cmdlets)   { continue }
                # Solo cuentan las que escriben a un archivo. Un
                # Set-Content sin destino no existe, pero un Out-File
                # dentro de una cadena de texto de ayuda si.
                if ($linea -notmatch '-(LiteralPath|Path|FilePath)\s') { continue }
                $escrituras += [pscustomobject]@{
                    Donde = '{0}:{1}' -f $archivo.Name, $n
                    Linea = $linea.Trim()
                }
            }
        }

        # Guarda: si no encuentro escrituras, esta prueba no esta
        # comprobando nada y tiene que decirlo. Son seis a dia de hoy;
        # el suelo esta en cinco para que anyadir una no obligue a tocar
        # la prueba, pero quitar media docena si.
        @($escrituras).Count | Should -BeGreaterOrEqual 5 -Because (
            'si el barrido no encuentra las escrituras conocidas es que el barrido esta roto')

        $sinParar = @($escrituras | Where-Object { $_.Linea -notmatch '-ErrorAction\s+Stop' })
        (($sinParar | ForEach-Object { $_.Donde }) -join ', ') | Should -BeNullOrEmpty -Because (
            'sin -ErrorAction Stop el fallo es no terminante, el catch de quien llama ' +
            'no se entera y el programa anuncia como guardado algo que no existe')
    }

    It 'y el modo consola dice la verdad cuando el informe no se puede escribir' {
        # La otra mitad de la invariante, ejecutando de verdad: no basta
        # con que el exportador lance, hace falta que la consola lo diga y
        # que NO diga a la vez que lo guardo.
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $imposible = Join-Path (Join-Path $script:Datos 'no-existe') 'x.html'
        $salida = script:Invoke-Cli @{ Informe = $imposible }

        $salida | Should -Match 'No se ha podido guardar el informe'
        $salida | Should -Not -Match 'Informe guardado'
        Test-Path -LiteralPath $imposible | Should -BeFalse
    }

    It 'y no anota en el historial la ruta de un informe que no existe' {
        $script:EmisionA = @(script:New-CandidatoInformativo)
        $imposible = Join-Path (Join-Path $script:Datos 'tampoco-existe') 'y.html'
        [void](script:Invoke-Cli @{ Informe = $imposible })

        $ultima = script:Get-UltimaEntradaHistorial -Tipo 'analisis'
        $ultima.Informe | Should -BeNullOrEmpty
    }
}

Describe 'Show-InformeEspacio: el modo "donde se fue el espacio"' {

    BeforeAll {
        # Una carpeta con archivos DE VERDAD, todos por encima del umbral
        # de 1 MB que usa Show-InformeEspacio, y con nombres elegidos para
        # que el orden por tamanyo y el orden por nombre NO coincidan:
        # asi una prueba del orden alfabetico no puede pasar por casualidad.
        #
        # Y con "foto[1].jpg" al lado de "foto1.jpg", que son las dos
        # mitades del defecto de -like: buscando el primero, -like encuentra
        # el segundo -que no es lo que se pidio- y no encuentra el primero
        # -que si lo es-.
        $script:CarpetaVista = Join-Path $script:Datos 'vista'
        [void](New-Item -ItemType Directory -Path $script:CarpetaVista -Force)
        foreach ($par in @(
            @{ Nombre = 'copia.iso';   Bytes = 4MB   }
            @{ Nombre = 'video.mkv';   Bytes = 3MB   }
            @{ Nombre = 'basura.tmp';  Bytes = 2560KB }
            @{ Nombre = 'otro.tmp';    Bytes = 2MB   }
            @{ Nombre = 'tercero.tmp'; Bytes = 1536KB }
            @{ Nombre = 'foto[1].jpg'; Bytes = 1280KB }
            @{ Nombre = 'foto1.jpg';   Bytes = 1200KB }
        )) {
            # WriteAllBytes y no New-Item: la ruta lleva corchetes, y
            # cualquier cosa que los lea como comodin no crearia el archivo.
            [IO.File]::WriteAllBytes((Join-Path $script:CarpetaVista $par.Nombre),
                                     [byte[]]::new([int]$par.Bytes))
        }
        $script:CuantosVista = 7

        function script:Get-SalidaEspacio {
            <#
            .SYNOPSIS
                La salida de Show-InformeEspacio sobre la carpeta de arriba,
                como un solo texto.
            .DESCRIPTION
                Write-Host va al flujo de informacion, asi que 6>&1 lo
                captura. Los argumentos se pasan en una tabla y no por un
                cierre: un cierre se ejecuta en un modulo dinamico donde no
                se ven las funciones del nucleo. Ver la cabecera.
            #>
            param([hashtable] $Argumentos = @{})
            $Argumentos['Rutas'] = @($script:CarpetaVista)
            if (-not $Argumentos.ContainsKey('Profundidad')) { $Argumentos['Profundidad'] = 1 }
            $salida = & { Show-InformeEspacio @Argumentos } 6>&1
            return ($salida | ForEach-Object { [string]$_ }) -join "`n"
        }
    }

    It 'la barra se llena en proporcion, y nunca se sale del ancho' {
        (Write-BarraProporcion -Parte 0   -Total 100 -Ancho 10) | Should -Not -Match ([string][char]0x2588)
        (Write-BarraProporcion -Parte 100 -Total 100 -Ancho 10) | Should -Be ([string][char]0x2588 * 10)
        (Write-BarraProporcion -Parte 50  -Total 100 -Ancho 10).Length | Should -Be 10
        # Una parte mayor que el total no puede desbordar la linea.
        (Write-BarraProporcion -Parte 500 -Total 100 -Ancho 10) | Should -Be ([string][char]0x2588 * 10)
        (Write-BarraProporcion -Parte -5  -Total 100 -Ancho 10).Length | Should -Be 10
    }

    It 'con total cero devuelve espacios y no divide por cero' {
        $barra = Write-BarraProporcion -Parte 5 -Total 0 -Ancho 8
        $barra | Should -Be (''.PadRight(8))
    }

    It 'sin ninguna carpeta que mirar lo dice en vez de callarse' {
        $salida = (& { Show-InformeEspacio -Rutas @() } 6>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $salida | Should -Match 'No hay ninguna carpeta que analizar'
    }

    It 'una ruta que no existe no cuenta como carpeta' {
        $salida = (& { Show-InformeEspacio -Rutas @('C:\esto\no\existe\seguro') } 6>&1 |
                   ForEach-Object { [string]$_ }) -join "`n"
        $salida | Should -Match 'No hay ninguna carpeta que analizar'
    }

    It 'mide una carpeta de verdad y no propone borrar nada' {
        $carpeta = Join-Path $script:Datos 'espacio'
        [void](New-Item -ItemType Directory -Path $carpeta -Force)
        [IO.File]::WriteAllBytes((Join-Path $carpeta 'grande.bin'), [byte[]]::new(2MB))

        $salida = (& { Show-InformeEspacio -Rutas @($carpeta) -Profundidad 1 -Archivos 5 } 6>&1 |
                   ForEach-Object { [string]$_ }) -join "`n"

        $salida | Should -Match 'Donde se fue el espacio'
        $salida | Should -Match 'grande\.bin'
        $salida | Should -Match 'no se ha propuesto ni borrado nada'
        $salida | Should -Not -Match '\{\d+\}'
    }

    It 'un filtro que no encuentra nada NO se ve igual que un disco vacio' {
        # Tres situaciones que se veian como el mismo hueco, y la tercera
        # es la que hace creer que el analisis fallo.
        $salida = script:Get-SalidaEspacio @{ Buscar = 'no-existe-*' }
        $salida | Should -Match ('Ninguno de los {0} archivos' -f $script:CuantosVista)
        $salida | Should -Match '«no-existe-\*»'
        $salida | Should -Not -Match 'Ningún archivo llega a'
    }

    It 'el resumen se escribe SIEMPRE, tambien cuando la lista trae filas' {
        # ESTA ES LA PRUEBA DEL PUNTO. Antes el resumen solo salia con la
        # lista vacia: con filas, el usuario veia una lista que se acababa
        # y no habia forma de distinguir "esto es todo lo que hay" de
        # "esto es lo que cabe". Son cosas distintas y se veian iguales.
        $salida = script:Get-SalidaEspacio @{ Archivos = 2 }
        $salida | Should -Match ('Se muestran los 2 mayores de {0} archivos' -f $script:CuantosVista)
        $salida | Should -Match 'quedan 5 más sin mostrar'
        $salida | Should -Match 'no se propone borrar nada'
    }

    It 'y sale tambien cuando hay filtro Y hay mas de los que caben' {
        # El hueco exacto que faltaba. Con un filtro puesto, la lista
        # recortada es lo mas enganyoso que ensenya el programa: el usuario
        # busca algo, no lo ve entre las que caben, y concluye que el
        # analisis se dejo cosas. El resumen tiene que nombrar los DOS
        # numeros -las que se ensenyan y las que coinciden- para que eso no
        # se pueda pensar.
        $salida = script:Get-SalidaEspacio @{ Buscar = '*.tmp'; Archivos = 2 }
        $salida | Should -Match 'Filtrando por: \*\.tmp'
        $salida | Should -Match 'Se muestran los 2 mayores de 3 archivos'
        $salida | Should -Match 'queda 1 más sin mostrar'
        # Y en singular: "quedan 1" es el fallo de plural que ya salio en
        # las cabeceras de grupo y en el historial.
        $salida | Should -Not -Match 'quedan 1 '
    }

    It 'cuando caben todos lo dice, y no promete que haya mas' {
        $salida = script:Get-SalidaEspacio @{ Archivos = 50 }
        $salida | Should -Match ('Se muestran los {0} archivos' -f $script:CuantosVista)
        $salida | Should -Match 'todos'
        $salida | Should -Not -Match 'sin mostrar'
    }

    It 'buscar un nombre con corchetes encuentra ESE archivo y no el otro' {
        # El defecto real que arregla este punto. Antes se filtraba con
        # -like, que lee [1] como "un caracter que sea 1".
        $salida = script:Get-SalidaEspacio @{ Buscar = 'foto[1].jpg'; Archivos = 50 }
        $salida | Should -Match ([regex]::Escape('foto[1].jpg'))
        $salida | Should -Not -Match 'foto1\.jpg'

        # La guarda que demuestra que el defecto existe de verdad: si algun
        # dia -like dejara de comportarse asi, las dos lineas de arriba
        # dejarian de estar comprobando nada y esto lo diria.
        ('foto1.jpg'   -like 'foto[1].jpg') | Should -BeTrue  -Because 'es la mitad que sobraba'
        ('foto[1].jpg' -like 'foto[1].jpg') | Should -BeFalse -Because 'es la mitad que faltaba'
    }

    It '-Orden Nombre cambia el orden de verdad, y el resumen lo cuenta' {
        # Se comparan POSICIONES dentro del texto y no la primera linea:
        # asi la prueba no depende de cuantas lineas de carpetas salgan
        # antes. basura.tmp es el primero por nombre y copia.iso el primero
        # por tamanyo, asi que el par se invierte entre los dos ordenes y
        # ninguna de las dos mitades puede pasar por casualidad.
        $porNombre = script:Get-SalidaEspacio @{ Orden = 'Nombre'; Archivos = 3 }
        $porTamano = script:Get-SalidaEspacio @{ Orden = 'Tamano'; Archivos = 3 }

        # Guarda: si alguno no apareciera, los IndexOf valdrian -1 y la
        # comparacion pasaria sin mirar nada.
        foreach ($texto in @($porNombre, $porTamano)) {
            $texto | Should -Match 'basura\.tmp'
            $texto | Should -Match 'copia\.iso'
        }

        $porNombre.IndexOf('basura.tmp') | Should -BeLessThan $porNombre.IndexOf('copia.iso')
        $porTamano.IndexOf('copia.iso')  | Should -BeLessThan $porTamano.IndexOf('basura.tmp')

        # Y ni el resumen ni la cabecera pueden llamar "mayores" a una
        # lista alfabetica: seria el programa contando algo que no hizo.
        $porNombre | Should -Match 'los 3 primeros por orden alfabético'
        $porNombre | Should -Match 'Archivos por nombre'
        $porNombre | Should -Not -Match 'mayores'
        $porTamano | Should -Match 'los 3 mayores'
        $porTamano | Should -Match 'Archivos mayores'
    }

    It 'rechaza un orden que no existe en vez de ordenar de cualquier manera' {
        { Show-InformeEspacio -Rutas @($script:CarpetaVista) -Orden 'Inventado' } | Should -Throw
    }

    It 'invariante: el modo consola NO vuelve a filtrar ni a resumir por su cuenta' {
        # El patron central del proyecto: dos sitios que deciden lo mismo
        # acaban diciendo cosas distintas. Aqui ya paso -un -like propio y
        # un resumen a medias- y esto es lo que impide que vuelva.
        #
        # Los bloques <# #> se quitan ANTES que las lineas que empiezan por
        # #: al reves, el primer paso se lleva la linea del #>, el bloque se
        # queda sin cierre y sobrevive documentacion mientras desaparece
        # codigo. Y esta prueba busca "-like", que sale escrito en los
        # comentarios de este mismo archivo fuente.
        $ruta   = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Cli') 'Espacio.ps1'
        $codigo = [regex]::Replace([IO.File]::ReadAllText($ruta), '(?s)<#.*?#>', '')
        $codigo = [regex]::Replace($codigo, '(?m)^\s*#.*$', '')

        # Guarda: si el despiece se comiera el archivo entero, esto pasaria
        # sin mirar nada.
        $codigo | Should -Match 'function Show-InformeEspacio'
        $codigo | Should -Match 'Get-VistaArchivos'
        $codigo | Should -Match 'Get-ResumenVistaArchivos'
        $codigo | Should -Not -Match '\-like'
    }
}
