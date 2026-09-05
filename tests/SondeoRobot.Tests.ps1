<#
    [VAL-05] · lo que se puede comprobar del sondeo SIN Windows.

    El sondeo abre la ventana de verdad, asi que aqui no se ejecuta: no hay
    WPF donde esto corre. Pero hay tres cosas suyas que si se pueden atar,
    y las tres tapan una forma distinta de que el sondeo -y despues el
    robot- se estropee sin que nadie se entere:

      1. Que los nombres que busca EXISTAN en el XAML. Un robot que busca
         "Ajustes" despues de que alguien renombre el panel no falla: no
         encuentra el control y se queda esperando. Un robot ciego que
         informa de que todo va bien es peor que ningun robot.
      2. Que NO pulse nada peligroso. Es un sondeo; abre la ventana del
         usuario y podria borrar de verdad.
      3. Que cierre el proceso que abre. En la integracion continua, un
         proceso colgado deja el trabajo esperando hasta que Windows lo
         mata por tiempo, y eso se lee como "la prueba tarda mucho" en vez
         de como "el robot no cierra".
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    $script:RutaSondeo = Join-Path (Join-Path $script:Raiz 'tools') 'Sondeo-Robot.ps1'

    function script:Get-CodigoSondeo {
        # Los bloques <# #> ANTES que las lineas de #, por lo de siempre.
        # Y aqui hace falta de verdad: la cabecera del sondeo NOMBRA los
        # botones que promete no pulsar, asi que leer los comentarios haria
        # que la prueba de abajo se pusiera roja por su propia promesa. Es
        # el mismo tropiezo de Lotes.Tests.ps1, ya anotado dos veces.
        $t = [IO.File]::ReadAllText($script:RutaSondeo)
        $t = [regex]::Replace($t, '(?s)<#.*?#>', '')
        return (@($t -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
    }

    $script:Codigo = script:Get-CodigoSondeo
    $script:Xaml = (@(Get-ChildItem -Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') -Filter '*.xaml') |
                    ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
}

Describe 'VAL-05: el sondeo de la ventana' {

    It 'existe y es sintacticamente valido' {
        Test-Path -LiteralPath $script:RutaSondeo | Should -BeTrue
        $errores = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:RutaSondeo, [ref]$null, [ref]$errores)
        @($errores).Count | Should -Be 0
    }

    It 'SIGUE HACIENDO LAS CINCO PREGUNTAS QUE PROMETE' {
        # ESTA PRUEBA FALTABA, Y SE NOTO POR LAS MALAS. Al corregir el
        # sondeo tras su primera ejecucion, una sustitucion de texto se
        # llevo por delante el paso 4 entero -"se lee lo que la ventana
        # dice"- y con el la funcion Get-PorNombre que usa el 3b. El sondeo
        # siguiente salio con cuatro pasos en verde, sin el 4, y con un
        # "Get-PorNombre no se reconoce" al final.
        #
        # Las nueve invariantes de este archivo pasaron tan contentas:
        # todas miraban DETALLES del sondeo -que no pulse nada peligroso,
        # que cierre el proceso, que no suponga el patron- y ninguna miraba
        # si el sondeo seguia siendo un sondeo. Es el fallo del que habla
        # la regla 8 del relevo, en su otra cara: no basta con vigilar que
        # cada pieza este bien puesta si nadie cuenta las piezas.
        #
        # SE COMPARA EL CONJUNTO ENTERO, no se comprueba uno por uno. La
        # primera version recorria la lista preguntando ".esta el 4?", y
        # eso deja pasar un paso INVENTADO: al renumerar una rama a '3c.'
        # el sondeo anunciaba un paso que no promete y la prueba seguia
        # verde, porque el '3b.' original seguia en la otra rama. Salio
        # mutando. Comparar los dos conjuntos contesta las dos preguntas a
        # la vez -.falta alguno? .sobra alguno?- que es la forma que pide
        # la regla 8 del relevo.
        $prometidos = @('0.', '1.', '2.', '2b.', '3.', '3b.', '4.', '5.')
        $anunciados = @([regex]::Matches($script:Codigo, "Write-Paso\s+'([^']+)'") |
                        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

        @($anunciados).Count | Should -BeGreaterThan 4 -Because 'si no encuentra pasos, no esta mirando el codigo'
        ($anunciados -join ' ') | Should -Be (($prometidos | Sort-Object -Unique) -join ' ') -Because (
            'el sondeo tiene que anunciar exactamente los pasos que promete su cabecera: ni uno menos ni uno mas')
    }

    It 'no llama a ninguna funcion suya que no exista' {
        # La otra mitad del mismo accidente: Get-PorNombre se seguia
        # usando despues de que la sustitucion borrara su definicion. En
        # PowerShell eso no se ve hasta que esa linea se EJECUTA, y esa
        # linea solo se ejecuta con una ventana delante.
        $errores = $null
        $arbol = [System.Management.Automation.Language.Parser]::ParseFile(
                    $script:RutaSondeo, [ref]$null, [ref]$errores)

        $definidas = @($arbol.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object { $_.Name })

        # Solo se miran los nombres con la pinta de este archivo -Verbo-Algo
        # definido aqui-, para no perseguir cmdlets del sistema.
        $llamadas = @($arbol.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } |
            Where-Object { $_ -and ($_ -match '^(Get|Write)-(Paso|PorNombre|Navegacion)$') } |
            Sort-Object -Unique)

        @($llamadas).Count | Should -BeGreaterThan 2 -Because 'si no encuentra llamadas, no esta mirando el arbol'
        $huerfanas = @($llamadas | Where-Object { $definidas -notcontains $_ })
        $huerfanas -join ', ' | Should -BeNullOrEmpty -Because (
            'una funcion que no existe no se nota hasta que se ejecuta esa linea, y aqui hace falta una ventana para eso')
    }

    It 'TODO BOTON DE NAVEGACION QUE BUSCA EXISTE EN EL XAML' {
        # LA INVARIANTE. Se sacan del codigo los nombres de $buscados y se
        # exige que cada uno sea el Content de un RadioButton de navegacion.
        # El dia que alguien renombre un boton, esto se pone rojo AQUI -en
        # dos segundos, en Linux- en vez de dentro de un robot que se queda
        # esperando un control que ya no se llama asi.
        #
        # SE MIRA Content Y NO AutomationProperties.Name, y esa correccion
        # salio de ejecutar el sondeo: la primera version buscaba los
        # nombres de los PANELES y luego intentaba pulsarlos. Un panel es un
        # contenedor y no se pulsa. En WPF, un control de contenido sin
        # AutomationProperties.Name anuncia su Content, y eso es lo que ve
        # un lector de pantalla y lo que ve el robot.
        $m = [regex]::Match($script:Codigo, '(?s)\$buscados\s*=\s*@\((?<lista>.*?)\)')
        $m.Success | Should -BeTrue -Because 'sin la lista no hay nada que comprobar, y esta prueba estaria pasando por no mirar'

        $nombres = @([regex]::Matches($m.Groups['lista'].Value, "'([^']+)'") |
                     ForEach-Object { $_.Groups[1].Value })
        $nombres.Count | Should -Be 6 -Because 'son los seis paneles que tiene la ventana'

        $principal = [IO.File]::ReadAllText(
            (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') 'MainWindow.xaml'))
        $huerfanos = @($nombres | Where-Object {
            $principal -notmatch ('(?s)<RadioButton[^>]*?Content="' + [regex]::Escape($_) + '"')
        })
        $huerfanos -join ', ' | Should -BeNullOrEmpty -Because (
            'un robot que busca un boton que ya no se llama asi no falla: se queda ciego')
    }

    It 'el panel que usa para comprobar el efecto del clic tambien existe' {
        # El sondeo pulsa "Acerca de" y luego busca el panel "Acerca de
        # Cachivache" para demostrar que el clic ha llegado. Si ese nombre
        # cambiara, el sondeo diria que el programa no reacciona cuando en
        # realidad reacciona perfectamente: un falso negativo, que en una
        # herramienta de diagnostico es el peor resultado posible.
        $script:Codigo | Should -Match ([regex]::Escape("Get-PorNombre 'Acerca de Cachivache'"))
        $script:Xaml   | Should -Match ([regex]::Escape('AutomationProperties.Name="Acerca de Cachivache"'))
    }

    It 'no supone el patron de automatizacion: le pregunta al elemento' {
        # El fallo que devolvio la primera ejecucion: "Modelo no admitido".
        # Un RadioButton de WPF no se INVOCA, se SELECCIONA. Suponer el
        # patron es la version de interfaz grafica de suponer que una
        # llamada al sistema funciona, que es como murio [VEL-02].
        $script:Codigo | Should -Match 'GetSupportedPatterns'
        $script:Codigo | Should -Match 'SelectionItemPattern'
    }

    It 'desempata por tipo de control, porque hay nombres repetidos' {
        # NavAjustes tiene Content="Ajustes" y el panel de ajustes tiene
        # AutomationProperties.Name="Ajustes": dos elementos distintos con
        # el MISMO nombre accesible. Buscar solo por nombre coge uno de los
        # dos a suertes. Se comprueba aqui que la ambiguedad sigue estando
        # -si un dia desapareciera, esta prueba avisaria de que el filtro
        # por tipo ya no hace falta- y que el codigo la desempata.
        $script:Codigo | Should -Match 'ControlTypeProperty'
        $script:Codigo | Should -Match 'AndCondition'

        $principal = [IO.File]::ReadAllText(
            (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') 'MainWindow.xaml'))
        $principal | Should -Match ([regex]::Escape('Content="Ajustes"'))
        $script:Xaml | Should -Match ([regex]::Escape('AutomationProperties.Name="Ajustes"'))
    }

    It 'NO PULSA NADA QUE BORRE, y eso no es una promesa del comentario' {
        # El sondeo abre la ventana del USUARIO, con sus discos de verdad.
        # Se comprueba sobre el codigo, no sobre la cabecera que lo promete.
        foreach ($peligroso in 'BtnEliminar', 'BtnAnalizar', 'Eliminar lo marcado', 'Analizar') {
            $script:Codigo | Should -Not -Match ([regex]::Escape($peligroso)) -Because (
                "el sondeo solo mira y cambia de panel; '$peligroso' no pinta nada aqui")
        }
    }

    It 'busca la ventana por identificador de proceso y no por titulo' {
        # Por titulo encontraria cualquier ventana que se llame igual -otra
        # copia del programa, un explorador abierto en una carpeta con ese
        # nombre- y todo lo demas mediria otro programa.
        $script:Codigo | Should -Match 'ProcessIdProperty'
    }

    It 'cierra lo que abre, y con red por si no se cierra solo' {
        $script:Codigo | Should -Match 'CloseMainWindow'
        $script:Codigo | Should -Match '\.Kill\(\)' -Because (
            'una ventana que no responde dejaria el proceso colgado en el ejecutor de la CI')
        $script:Codigo | Should -Match 'finally' -Because (
            'si el sondeo lanza a mitad, el proceso hay que cerrarlo igual')
    }

    It 'comprueba que UI Automation existe ANTES de arrancar nada' {
        # Si las bibliotecas no estan -Server Core, un contenedor- no tiene
        # sentido abrir una ventana para descubrirlo. Y ese es justamente el
        # caso que puede darse en un ejecutor de integracion continua.
        # CON UN LIMITE DE PALABRA, Y NO CON IndexOf. La primera version
        # buscaba la subcadena, asi que escribir "UIAutomationCliente" -con
        # una letra de mas, o sea un ensamblado que no existe- la seguia
        # satisfaciendo: la prueba pasaba mirando un prefijo. Salio mutando.
        $mUia = [regex]::Match($script:Codigo, 'UIAutomationClient(?![A-Za-z])')
        $mUia.Success | Should -BeTrue -Because 'el nombre del ensamblado tiene que estar entero'

        $mArranque = [regex]::Match($script:Codigo, 'Start-Process')
        $mArranque.Success | Should -BeTrue
        $mArranque.Index | Should -BeGreaterThan $mUia.Index -Because (
            'preguntar primero lo barato es el orden que hace util un sondeo')
    }
}
