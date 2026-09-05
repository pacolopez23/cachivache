<#
    Invariantes estructurales del proyecto.

    Estas pruebas no comprueban que una función devuelva lo correcto:
    comprueban que el PROYECTO sigue estando construido como debe. Cada una
    protege una regla que hoy se cumple porque alguien se acuerda, y que un
    cambio distraido podría romper sin que ninguna otra prueba se enterase.

    Se apoyan en el arbol de sintaxis (AST) y en reflexion, no en buscar
    texto: un comentario que mencione "Remove-Item" no debe hacerlas fallar,
    y una llamada real escrita de otra forma no debe escaparse.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    function Get-AstDe {
        param([string] $Ruta)
        return [System.Management.Automation.Language.Parser]::ParseFile($Ruta, [ref]$null, [ref]$null)
    }

    # Todos los nombres de comando que aparecen invocados en un archivo.
    function Get-ComandosInvocados {
        param([string] $Ruta)
        $ast = Get-AstDe $Ruta
        return @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                 ForEach-Object { $_.GetCommandName() } |
                 Where-Object { $_ })
    }
}

Describe 'Ningun modulo de limpieza borra ni escribe por su cuenta (P-02)' {
    <#
        La garantía central del programa: los módulos PROPONEN, y el único
        que ejecuta es el motor de Remove.ps1, que revalida la guardia justo
        antes de tocar nada. Si un módulo llamara a Remove-Item directamente,
        se saltaria esa revalidación entera. Hoy ninguno lo hace; esta prueba
        existe para que siga siendo verdad.
    #>

    # OJO: esta lista va en un BeforeAll, no en el cuerpo del Describe. El
    # cuerpo del Describe se ejecuta en la fase de DESCUBRIMIENTO de Pester y
    # sus variables no existen luego al ejecutar las pruebas: la comparacion
    # se haría contra $null y el test pasaria siempre, dijera lo que dijera
    # el código. Se detecto justamente así, mutando un módulo a propósito
    # para comprobar que la prueba fallaba, y no fallaba.
    BeforeAll {
        $script:Destructivos = @(
            'Remove-Item', 'Remove-ItemProperty', 'Clear-RecycleBin', 'Clear-Content',
            'Set-Content', 'Add-Content', 'Out-File', 'New-Item', 'Move-Item',
            'Rename-Item', 'Set-ItemProperty', 'New-ItemProperty',
            'Set-Item', 'Copy-Item', 'Start-Process', 'Invoke-Expression',
            'Stop-Process', 'Stop-Service', 'Set-Service', 'Remove-Service'
        )
    }

    It 'el modulo <Nombre> no invoca ningun comando destructivo' -ForEach @(
        (Get-ChildItem (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Modules') -Filter '*.ps1' |
            ForEach-Object { @{ Nombre = $_.Name; Ruta = $_.FullName } })
    ) {
        $script:Destructivos | Should -Not -BeNullOrEmpty -Because 'sin la lista, esta prueba no comprobaria nada'
        $invocados = Get-ComandosInvocados $Ruta
        $prohibidos = @($invocados | Where-Object { $_ -in $script:Destructivos })
        $prohibidos | Should -BeNullOrEmpty -Because (
            "$Nombre debe limitarse a proponer candidatos. Borrar o escribir desde un modulo " +
            "se salta la revalidacion de la guardia que hace Invoke-EliminacionCandidato")
    }

    It 'dentro del nucleo, solo Remove.ps1 borra archivos' {
        $borradores = @('Remove-Item', 'Clear-RecycleBin')
        $carpeta = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Core'
        $culpables = @()
        foreach ($archivo in (Get-ChildItem $carpeta -Filter '*.ps1')) {
            if ($archivo.Name -eq 'Remove.ps1') { continue }
            $invocados = Get-ComandosInvocados $archivo.FullName
            if (@($invocados | Where-Object { $_ -in $borradores })) { $culpables += $archivo.Name }
        }
        $culpables | Should -BeNullOrEmpty -Because 'todo borrado debe pasar por el motor que revalida la guardia'
    }

    It 'ningun modulo lanza procesos externos: eso es exclusivo del metodo Comando' {
        # El método 'Comando' esta exento de la guardia de rutas, así que su
        # ejecución vive centralizada en Remove.ps1 y pasa por una lista
        # blanca de ejecutables. Un módulo que lanzara procesos por su cuenta
        # esquivaria esa lista. Ver [C-03].
        $carpeta = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Modules'
        $culpables = @()
        foreach ($archivo in (Get-ChildItem $carpeta -Filter '*.ps1')) {
            $invocados = Get-ComandosInvocados $archivo.FullName
            if (@($invocados | Where-Object { $_ -in @('Start-Process', 'Invoke-Expression', 'Invoke-Item') })) {
                $culpables += $archivo.Name
            }
        }
        $culpables | Should -BeNullOrEmpty
    }
}

Describe 'El candidato y la fila de la interfaz no pueden divergir' {
    <#
        Candidate.ps1 define el candidato; Types.ps1 define ItemVista, lo que
        ve el usuario. La correspondencia se copia a mano, campo a campo, en
        Window.Analisis.ps1. Cuando [C-03] anyadio el campo Comando hubo que
        acordarse de añadir también su línea allí, porque SECURITY.md exige
        que el comando externo se vea. Nada avisaba si se olvidaba.
    #>

    BeforeAll {
        . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') 'Types.ps1')
        Initialize-TiposInterfaz

        # Campos del candidato: el hashtable que devuelve New-Candidato.
        $astCandidato = Get-AstDe (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Candidate.ps1')
        $funcion = $astCandidato.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-Candidato'
        }, $true)[0]
        $tabla = $funcion.FindAll({
            param($n) $n -is [System.Management.Automation.Language.HashtableAst]
        }, $true)[0]
        $script:CamposCandidato = @($tabla.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text.Trim("'`"") })

        # Propiedades reales de ItemVista, por reflexion.
        $script:PropsItemVista = @([Cachivache.ItemVista].GetProperties() | ForEach-Object { $_.Name })

        # Asignaciones "$item.X = ..." que hace Window.Analisis.ps1.
        $astVista = Get-AstDe (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'UI') 'Window.Analisis.ps1')
        $script:Mapeadas = @($astVista.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                      $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] -and
                      $n.Left.Expression.Extent.Text -eq '$item'
        }, $true) | ForEach-Object { $_.Left.Member.Extent.Text })
    }

    It 'toda propiedad que existe en el candidato Y en ItemVista se copia de verdad' {
        # Propiedades que ItemVista calcula o gestiona por su cuenta y que
        # por tanto NO deben copiarse desde el candidato.
        $propias = @('ColorRiesgo', 'Tamano', 'Borrable', 'Origen',
                     'Seleccionado', 'Hecho', 'Estado', 'VisibilidadAviso', 'VisibilidadComando')

        $deberian = @($script:PropsItemVista |
                      Where-Object { $_ -in $script:CamposCandidato -and $_ -notin $propias })
        $olvidadas = @($deberian | Where-Object { $_ -notin $script:Mapeadas })

        $olvidadas | Should -BeNullOrEmpty -Because (
            'si una propiedad existe en ambos lados pero no se copia en Window.Analisis.ps1, ' +
            'la interfaz la mostrara siempre vacia sin que nada falle')
    }

    It 'no se copia al item ninguna propiedad que ItemVista no declare' {
        $fantasma = @($script:Mapeadas | Where-Object { $_ -notin $script:PropsItemVista })
        $fantasma | Should -BeNullOrEmpty -Because 'asignar una propiedad inexistente falla en tiempo de ejecucion'
    }
}

Describe 'El nucleo se carga entero y en orden' {

    It 'Bootstrap.ps1 nombra todos los archivos que hay en src/Core' {
        $carpeta = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Core'
        $enDisco = @(Get-ChildItem $carpeta -Filter '*.ps1' |
                     Where-Object { $_.Name -ne 'Bootstrap.ps1' } |
                     ForEach-Object { $_.Name })
        $texto = Get-Content (Join-Path $carpeta 'Bootstrap.ps1') -Raw
        $ausentes = @($enDisco | Where-Object { $texto -notmatch [regex]::Escape($_) })
        $ausentes | Should -BeNullOrEmpty -Because 'un archivo del nucleo que no se cargue deja funciones sin definir'
    }
}

Describe 'Los controles de la ventana y el XAML no pueden divergir' {

    <#
        Este es el fallo más traicionero de toda la interfaz. Window.ps1
        resuelve los controles por nombre con FindName y los guarda en $c.
        Si el código pide $c.BtnLoQueSea y ese nombre no esta en la lista, o
        esta en la lista pero no en el XAML, PowerShell no protesta: devuelve
        $null, y $null.Add_Click(...) revienta o, peor, la propiedad se asigna
        a la nada y el control simplemente no responde. Un boton muerto y
        ningún error. Estas tres pruebas convierten ese silencio en un fallo.
    #>

    BeforeAll {
        $script:CarpetaUI = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        # El documento MONTADO, no MainWindow.xaml a secas: desde que la
        # ventana se reparte en Panel.*.xaml, el armazon solo declara
        # diecisiete nombres y esta prueba se quedaria mirando una
        # diecisieteava parte de la ventana sin enterarse. Se monta igual
        # que en tiempo de ejecución.
        . (Join-Path $script:CarpetaUI 'Xaml.ps1')
        $script:XamlMontado = Expand-PanelesXaml -Carpeta $script:CarpetaUI `
                                  -Texto ([IO.File]::ReadAllText((Join-Path $script:CarpetaUI 'MainWindow.xaml')))

        $script:NombresXaml = @{}
        foreach ($m in [regex]::Matches($script:XamlMontado, 'x:Name="([^"]+)"')) {
            $script:NombresXaml[$m.Groups[1].Value] = $true
        }

        # La lista literal que Window.ps1 pasa por FindName, acotada al bloque
        # que la construye para no arrastrar cadenas de otras partes del archivo.
        $textoVentana = Get-Content (Join-Path $script:CarpetaUI 'Window.ps1') -Raw
        $bloque = [regex]::Match($textoVentana, '(?s)\$c = @\{\}.*?\$c\[\$nombre\] = \$ventana\.FindName')
        $script:NombresResueltos = @{}
        foreach ($m in [regex]::Matches($bloque.Value, "'([^']+)'")) {
            $script:NombresResueltos[$m.Groups[1].Value] = $true
        }

        # Lo que el código consulta de verdad, en cualquiera de los Window*.ps1.
        $script:NombresUsados = @{}
        foreach ($archivo in (Get-ChildItem $script:CarpetaUI -Filter 'Window*.ps1')) {
            $t = Get-Content $archivo.FullName -Raw
            foreach ($m in [regex]::Matches($t, "\`$c\.([A-Za-z_][A-Za-z0-9_]*)")) {
                $script:NombresUsados[$m.Groups[1].Value] = $archivo.Name
            }
            foreach ($m in [regex]::Matches($t, "\`$c\[\s*'([^']+)'\s*\]")) {
                $script:NombresUsados[$m.Groups[1].Value] = $archivo.Name
            }
        }
    }

    It 'la extraccion encuentra controles: si no, la prueba no esta probando nada' {
        $script:NombresXaml.Count      | Should -BeGreaterThan 30
        $script:NombresResueltos.Count | Should -BeGreaterThan 30
        $script:NombresUsados.Count    | Should -BeGreaterThan 30
    }

    It 'todo control que el codigo usa esta en la lista que Window.ps1 resuelve' {
        $huerfanos = @($script:NombresUsados.Keys |
                       Where-Object { -not $script:NombresResueltos.ContainsKey($_) } |
                       Sort-Object)
        $huerfanos | Should -BeNullOrEmpty -Because 'un nombre fuera de la lista deja $c.Nombre a $null y el control no responde'
    }

    It 'todo control que Window.ps1 resuelve existe en el XAML' {
        $inventados = @($script:NombresResueltos.Keys |
                        Where-Object { -not $script:NombresXaml.ContainsKey($_) } |
                        Sort-Object)
        $inventados | Should -BeNullOrEmpty -Because 'FindName de un nombre que no existe devuelve $null sin avisar'
    }
}

Describe 'Marcar en lote no puede alcanzar lo que el usuario no ve' {

    <#
        "Marcar todo" recorria $estado.Items, la coleccion COMPLETA, no la
        vista filtrada. Con un filtro puesto -por texto o por riesgo-
        marcaba también las filas escondidas, y el siguiente clic en
        "Eliminar lo marcado" las borraba: el usuario creia estar actuando
        sobre lo que tenia delante y actuaba sobre todo el análisis.

        En un programa que borra archivos, la distancia entre lo que se ve
        y lo que se toca tiene que ser cero. Esta prueba lee el cuerpo del
        cierre y exige que recorra la vista.
    #>

    BeforeAll {
        $ruta = Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI') 'Window.Eventos.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ruta, [ref]$null, [ref]$null)

        # La asignacion $marcarEnLote = { ... }, localizada por AST y no
        # por texto, para que un comentario que hable de Items no cuente.
        $asignacion = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$marcarEnLote'
        }, $true))

        $script:CuerpoLote = if ($asignacion.Count -gt 0) { $asignacion[0].Right.Extent.Text } else { '' }

        # Solo el código, sin comentarios: el cierre explica en sus
        # comentarios por que NO recorre Items, y esa explicación no debe
        # hacer fallar la prueba.
        $script:CodigoLote = (($script:CuerpoLote -split "`r?`n") |
                              Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'la prueba encuentra el cierre: si no, no esta comprobando nada' {
        $script:CuerpoLote | Should -Not -BeNullOrEmpty
        $script:CodigoLote | Should -Match 'Seleccionado' -Because 'es el cierre que marca las casillas'
    }

    It 'recorre la vista filtrada, no la coleccion completa' {
        $script:CodigoLote | Should -Match '\$estado\.Vista' -Because 'marcar tiene que actuar sobre lo que se esta viendo'
    }

    It 'no toca $estado.Items' {
        $script:CodigoLote | Should -Not -Match '\$estado\.Items' -Because 'recorrer Items alcanza filas que el filtro esconde'
    }
}

Describe 'La codificación de los archivos no puede volver a romperse' {

    <#
        Windows PowerShell 5.1 lee un .ps1 SIN BOM como ANSI, no como
        UTF-8. Una "ñ" en un archivo sin BOM llega al usuario convertida en
        basura, y por eso durante mucho tiempo el proyecto se escribió en
        ASCII puro: la interfaz decía "Cachees", "contrasenyas" y "tamanyo".

        La regla ahora es la contraria: todos los .ps1 y .xaml van en UTF-8
        CON BOM y el castellano se escribe bien. Estas pruebas existen
        porque el fallo es silencioso — nada peta, solo salen acentos rotos
        en pantalla — y porque cualquier editor mal configurado puede
        guardar un archivo sin BOM sin avisar a nadie.
    #>

    BeforeAll {
        $script:RaizProyecto = Split-Path $PSScriptRoot -Parent
        # -Include SE IGNORA con -LiteralPath en Windows PowerShell 5.1.
        #
        # En PowerShell 7 filtra; en 5.1 no, y devuelve el arbol ENTERO. La
        # prueba de abajo pasaba a exigir un BOM a .md, .yml, .gitignore y
        # al propio .bat, asi que fallaba con una lista de veinte archivos
        # que no tienen por que llevarlo. Y la de los .bat pasaba a recorrer
        # el repositorio entero buscando bytes altos: 23 segundos y otra
        # lista enorme.
        #
        # Se filtra por extension a mano, que da igual en las dos versiones.
        $script:ConBom = @(
            Get-ChildItem -LiteralPath $script:RaizProyecto -Recurse -File |
            Where-Object { $_.Extension -eq '.ps1' -or $_.Extension -eq '.xaml' } |
            Where-Object { $_.FullName -notmatch '\\\.git\\' }
        )
    }

    It 'la prueba encuentra archivos: si no, no comprueba nada' {
        $script:ConBom.Count | Should -BeGreaterThan 40
    }

    It 'todos los .ps1 y .xaml empiezan por el BOM de UTF-8' {
        $sinBom = @()
        foreach ($archivo in $script:ConBom) {
            $bytes = [IO.File]::ReadAllBytes($archivo.FullName)
            if ($bytes.Length -lt 3 -or
                $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
                $sinBom += $archivo.Name
            }
        }
        $sinBom | Should -BeNullOrEmpty -Because 'sin BOM, PowerShell 5.1 lee el archivo como ANSI y destroza los acentos'
    }

    It 'los .bat siguen siendo ASCII puro' {
        # La consola de Windows no usa UTF-8 por defecto: un acento en un
        # .bat sale como un símbolo raro en la ventana del usuario.
        $sucios = @()
        # Filtrado a mano por lo mismo: -Include no filtra en 5.1.
        $bats = @(Get-ChildItem -LiteralPath $script:RaizProyecto -Recurse -File |
                  Where-Object { $_.Extension -eq '.bat' })
        $bats.Count | Should -BeGreaterThan 0 -Because 'sin ningun .bat esta prueba no comprueba nada'
        foreach ($archivo in $bats) {
            $bytes = [IO.File]::ReadAllBytes($archivo.FullName)
            if ($bytes | Where-Object { $_ -gt 127 }) { $sucios += $archivo.Name }
        }
        $sucios | Should -BeNullOrEmpty
    }

    It 'un acento escrito en el codigo llega intacto al leerlo' {
        # La comprobacion de verdad: no que el byte este, sino que el texto
        # que sale es el que se escribio.
        $ruta = Join-Path (Join-Path (Join-Path $script:RaizProyecto 'src') 'Modules') '10-Caches.ps1'
        $texto = Get-Content -Raw -LiteralPath $ruta
        $texto | Should -Match 'contrase'
        $texto | Should -Match ([regex]::Escape('contraseñas'))
    }

    It 'la interfaz no vuelve a escribir la enye como "ny"' {
        <#
            Antes esto era una LISTA A MANO de cinco palabras
            -contrasenya, tamanyo, anyadir, pestanya, Cachees- y por eso
            solo cazaba lo que alguien ya habia encontrado. Se le escapo
            "elementos pequenyos", que llevaba meses saliendo en el
            registro de cualquiera que abriera el programa; lo vio el
            usuario, no la suite.

            Ahora se busca el PATRON: cualquier "ny" dentro de una palabra
            de una cadena de prosa. En espanyol ese digrafo no existe, asi
            que todo lo que aparezca ahi es un apanyo de cuando los
            archivos no llevaban marca de orden de bytes.

            Se mira solo la prosa entrecomillada, no los comentarios: ahi
            el ASCII puro es deliberado y no lo lee ningun usuario. Y de
            ahi que este propio comentario pueda escribir "espanyol" sin
            hacerse saltar a si mismo.
        #>
        $apanyos = @()
        foreach ($archivo in $script:ConBom) {
            if ($archivo.FullName -match 'tests') { continue }
            if ($archivo.Extension -ne '.ps1')    { continue }

            $n = 0
            $enBloque = $false
            foreach ($linea in (Get-Content -LiteralPath $archivo.FullName)) {
                $n++
                if ($linea -match '<#') { $enBloque = $true }
                if ($enBloque) {
                    if ($linea -match '#>') { $enBloque = $false }
                    continue
                }
                if ($linea -match '^\s*#') { continue }

                foreach ($m in [regex]::Matches($linea, "'([^'`n]+)'|`"([^`"`n]+)`"")) {
                    $texto = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                    if ($texto.Length -lt 14) { continue }
                    if (@($texto -split ' ' | Where-Object { $_ }).Count -lt 3) { continue }

                    foreach ($palabra in [regex]::Matches($texto, '[A-Za-z]*ny[A-Za-z]*')) {
                        $apanyos += ('{0}:{1}  {2}' -f $archivo.Name, $n, $palabra.Value)
                    }
                }
            }
        }
        $apanyos | Should -BeNullOrEmpty -Because 'ya no hace falta el apanyo: los archivos llevan BOM'
    }
}

Describe 'El cuadro de filtro no dispara el filtro en cada tecla' {

    <#
        Add_TextChanged enganchado directamente a $aplicarFiltro provocaba
        una pasada completa por la tabla POR CADA TECLA. Con 15.000 filas,
        escribir "chrome" son seis pasadas, y cada una invoca el predicado
        y el bloque del resumen una vez por fila: unas 180.000 invocaciones
        de scriptblock y cerca de tres segundos con la ventana bloqueada,
        durante los cuales se pierden teclas.

        Entre medias va un DispatcherTimer que se reinicia en cada
        pulsacion, así que se filtra 250 ms después de la última. Es de las
        cosas que es fácil "simplificar" sin querer al tocar el archivo, y
        el síntoma -la ventana va a tirones al escribir- no salta en
        ninguna prueba funcional. Ver docs/RENDIMIENTO.md (sección 9).
    #>

    BeforeAll {
        $carpetaUi = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'
        $script:Eventos   = Get-Content -Raw -LiteralPath (Join-Path $carpetaUi 'Window.Eventos.ps1')
        $script:Ayudantes = Get-Content -Raw -LiteralPath (Join-Path $carpetaUi 'Window.Ayudantes.ps1')

        # Sin comentarios: los de este mismo bloque hablan de $aplicarFiltro.
        $script:CodigoEventos = (($script:Eventos -split "`r?`n") |
                                 Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'la prueba encuentra el enganche: si no, no esta comprobando nada' {
        $script:CodigoEventos | Should -Match 'CampoFiltro\.Add_TextChanged'
    }

    It 'el cuadro de texto pide el filtro, no lo ejecuta' {
        $script:CodigoEventos | Should -Match 'CampoFiltro\.Add_TextChanged\(\{\s*&\s*\$solicitarFiltro'
    }

    It 'existe el temporizador que separa la tecla del filtrado' {
        $script:Ayudantes | Should -Match '\$solicitarFiltro\s*='
        $script:Ayudantes | Should -Match 'TemporizadorFiltro.*=.*DispatcherTimer'
    }

    It 'sin criterios se quita el filtro en vez de poner uno que diga que si a todo' {
        # De esto depende que el resumen del pie pueda preguntar "hay algún
        # filtro puesto?" y saltarse el segundo recorrido cuando no lo hay.
        $script:Ayudantes | Should -Match '\$estado\.Vista\.Filter = \$null'
    }
}

Describe 'Lo que el usuario elige a mano pasa el perfil a Personalizado' {

    <#
        El programa guarda ocho preferencias, pero al arrancar solo hace
        caso a los módulos elegidos y a los umbrales SI el perfil es
        'personalizado'. Es una decisión razonable -elegir "Equilibrado"
        tiene que significar algo-, pero convierte cada control que el
        usuario toca sin pasar a Personalizado en una eleccion que se
        guarda y luego se tira sin decir nada.

        La regla que lo sostiene: todo control cuyo valor se persiste
        llama a $pasarAPersonalizado. Esta prueba la fija por AST para los
        cuatro de Ajustes y para las casillas de módulo, que eran las que
        se quedaban fuera.
    #>

    BeforeAll {
        $carpeta = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        $script:CodigoUi = @{}
        foreach ($nombre in @('Window.Eventos.ps1', 'Window.Ayudantes.ps1')) {
            $script:CodigoUi[$nombre] = Get-Content (Join-Path $carpeta $nombre) -Raw
        }

        # Cuerpo de una asignacion de cierre, localizada por AST, sin sus
        # líneas de comentario (que hablan del problema y lo nombran).
        function Get-CuerpoCierre {
            param([string] $Texto, [string] $Nombre)
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Texto, [ref]$null, [ref]$null)
            $encontradas = @($ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -eq $Nombre
            }, $true))
            if ($encontradas.Count -eq 0) { return '' }
            return ((($encontradas[0].Right.Extent.Text -split "`r?`n") |
                     Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
        }
    }

    It 'existe el cierre que pasa a Personalizado' {
        $cuerpo = Get-CuerpoCierre $script:CodigoUi['Window.Eventos.ps1'] '$pasarAPersonalizado'
        $cuerpo | Should -Not -BeNullOrEmpty
        $cuerpo | Should -Match 'personalizado'
        $cuerpo | Should -Match 'SincronizandoPerfil' -Because 'sin la bandera, mover los controles al elegir perfil pasaria a Personalizado solo'
    }

    It 'las casillas de modulo pasan el perfil a Personalizado' {
        # Nadie escuchaba estas casillas: desmarcabas un módulo estando en
        # Equilibrado, se guardaba, y al reabrir el programa se descartaba
        # tu eleccion en silencio.
        $cuerpo = Get-CuerpoCierre $script:CodigoUi['Window.Ayudantes.ps1'] '$manejadorModuloGlobal'
        $cuerpo | Should -Not -BeNullOrEmpty -Because 'sin manejador, tocar un modulo no se entera nadie'
        $cuerpo | Should -Match 'pasarAPersonalizado'
    }

    It 'el manejador de modulos se engancha a cada tarjeta' {
        $script:CodigoUi['Window.Ayudantes.ps1'] |
            Should -Match 'add_PropertyChanged\(\$manejadorModuloGlobal\)' -Because 'definirlo sin engancharlo no sirve de nada'
    }

    It 'los dos sliders de Ajustes pasan el perfil a Personalizado' {
        $texto = $script:CodigoUi['Window.Eventos.ps1']
        foreach ($control in @('SliderMinimoMB', 'SliderDias')) {
            $bloque = [regex]::Match($texto, "(?s)\`$c\.$control\.Add_\w+\(\{.*?\n    \}\)")
            $bloque.Success | Should -BeTrue -Because "hay que encontrar el manejador de $control"
            $bloque.Value | Should -Match 'pasarAPersonalizado' -Because "$control se guarda en preferencias y solo se relee en Personalizado"
        }
    }

    It 'las dos casillas de Ajustes pasan el perfil a Personalizado' {
        foreach ($cierre in @('$sincronizarMenores', '$sincronizarPermanente')) {
            $cuerpo = Get-CuerpoCierre $script:CodigoUi['Window.Eventos.ps1'] $cierre
            $cuerpo | Should -Not -BeNullOrEmpty -Because "hay que encontrar el cierre $cierre"
            $cuerpo | Should -Match 'pasarAPersonalizado'
        }
    }

    It 'las casillas usan Checked y Unchecked, nunca Click' {
        # Click SOLO se levanta cuando el usuario pulsa. Asignar IsChecked
        # desde el código -que es lo que hacen elegir un perfil y
        # "Restablecer ajustes"- no lo dispara, así que $estado.Preferencias
        # se quedaba con el valor anterior y el borrado permanente llegaba a
        # rearmarse solo en el arranque siguiente.
        $texto = $script:CodigoUi['Window.Eventos.ps1']
        foreach ($casilla in @('ChkMenores', 'ChkPermanente')) {
            $texto | Should -Not -Match "\`$c\.$casilla\.Add_Click" -Because 'Add_Click no se entera de los cambios por codigo'
            $texto | Should -Match "\`$c\.$casilla\.Add_Checked"
            $texto | Should -Match "\`$c\.$casilla\.Add_Unchecked"
        }
    }
}

Describe 'Los dos temas y el XAML no pueden divergir' {

    <#
        Cambiar de tema en caliente es sustituir un diccionario por otro.
        Si una clave existe solo en uno, al pasar a ese tema el control que
        la usa se queda sin pincel: en el mejor caso invisible, en el peor
        con el color del tema anterior pegado. WPF no avisa de nada.

        Lo mismo con una clave que el XAML usa y ningún tema define: el
        DynamicResource se resuelve a nada, en silencio.
    #>

    BeforeAll {
        $script:CarpetaTemas = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        function Get-ClavesDeTema {
            param([string] $Archivo)
            $texto = Get-Content (Join-Path $script:CarpetaTemas $Archivo) -Raw
            return @([regex]::Matches($texto, 'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        }

        $script:ClavesOscuro = Get-ClavesDeTema 'Theme.Dark.xaml'
        $script:ClavesClaro  = Get-ClavesDeTema 'Theme.Light.xaml'

        # Todo lo que los XAML piden por DynamicResource.
        # Se incluyen los Panel.*.xaml: la mayoria de los colores se usan
        # ahi desde que la ventana se partio.
        $script:Pedidas = @{}
        $aRevisar = @('MainWindow.xaml', 'Styles.xaml', 'ConfirmDialog.xaml') +
                    @(Get-ChildItem $script:CarpetaTemas -Filter 'Panel.*.xaml' | ForEach-Object { $_.Name })
        foreach ($archivo in $aRevisar) {
            $texto = Get-Content (Join-Path $script:CarpetaTemas $archivo) -Raw
            foreach ($m in [regex]::Matches($texto, '\{DynamicResource\s+([A-Za-z0-9_]+)\s*\}')) {
                $script:Pedidas[$m.Groups[1].Value] = $archivo
            }
        }
    }

    It 'la extraccion encuentra claves: si no, la prueba no prueba nada' {
        $script:ClavesOscuro.Count | Should -BeGreaterThan 15
        $script:ClavesClaro.Count  | Should -BeGreaterThan 15
        $script:Pedidas.Count      | Should -BeGreaterThan 15
    }

    It 'los dos temas declaran exactamente las mismas claves' {
        $soloOscuro = @($script:ClavesOscuro | Where-Object { $script:ClavesClaro -notcontains $_ } | Sort-Object)
        $soloClaro  = @($script:ClavesClaro  | Where-Object { $script:ClavesOscuro -notcontains $_ } | Sort-Object)
        $soloOscuro | Should -BeNullOrEmpty -Because 'estas claves faltan en el tema claro'
        $soloClaro  | Should -BeNullOrEmpty -Because 'estas claves faltan en el tema oscuro'
    }

    It 'ningun XAML pide un color que los temas no definan' {
        # Se descartan las claves que define Styles.xaml (estilos y fuentes),
        # que no son del tema: aquí solo interesan los pinceles.
        $delEstilo = @([regex]::Matches((Get-Content (Join-Path $script:CarpetaTemas 'Styles.xaml') -Raw),
                                        'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $huerfanas = @($script:Pedidas.Keys |
                       Where-Object { $script:ClavesOscuro -notcontains $_ -and $delEstilo -notcontains $_ } |
                       Sort-Object)
        $huerfanas | Should -BeNullOrEmpty -Because 'un DynamicResource sin destino no pinta nada y no avisa'
    }

    It 'ningun color del tema se declara y luego no lo usa nadie' {
        $sinUsar = @($script:ClavesOscuro | Where-Object { -not $script:Pedidas.ContainsKey($_) } | Sort-Object)
        $sinUsar | Should -BeNullOrEmpty -Because 'un color que no usa nadie es peso muerto en los dos temas'
    }
}

Describe 'La escala tipografica no admite tamanyos sueltos' {

    <#
        Seis tamaños: 11 12 13 15 20 28. Es lo que hace que dos paneles
        distintos se lean como el mismo programa. Antes había nueve valores
        elegidos uno a uno según hiciera falta (11.5, 12.5, 13.5, 14, 16...)
        y bastaba con que alguien escribiera FontSize="14" en un sitio nuevo
        para que dejaran de rimar.
    #>

    BeforeAll {
        $script:Escala = @('11', '12', '13', '15', '20', '28')
        $script:CarpetaXaml = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'
    }

    It '<Archivo> solo usa tamanyos de la escala' -ForEach @(
        @{ Archivo = 'MainWindow.xaml' }
        @{ Archivo = 'Styles.xaml' }
        @{ Archivo = 'ConfirmDialog.xaml' }
        @{ Archivo = 'Panel.Inicio.xaml' }
        @{ Archivo = 'Panel.Resultados.xaml' }
        @{ Archivo = 'Panel.Registro.xaml' }
        @{ Archivo = 'Panel.Informes.xaml' }
        @{ Archivo = 'Panel.Ajustes.xaml' }
        @{ Archivo = 'Panel.Acerca.xaml' }
    ) {
        $texto = Get-Content (Join-Path $script:CarpetaXaml $Archivo) -Raw
        $usados = @([regex]::Matches($texto, 'FontSize="([0-9.]+)"') |
                    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $fuera = @($usados | Where-Object { $script:Escala -notcontains $_ })
        $fuera | Should -BeNullOrEmpty -Because "la escala es $($script:Escala -join ', ')"
    }
}

Describe 'La ventana partida en paneles monta el mismo documento de antes' {

    <#
        MainWindow.xaml tenia 783 líneas con los seis paneles dentro. Al
        partirlo, la única garantía que vale es la más fuerte posible: que
        el documento que WPF acaba interpretando sea IDENTICO al de antes.
        No "equivalente", no "parecido salvo espacios": identico.

        Se guarda una copia del original en tests/ y se compara con lo que
        monta Expand-PanelesXaml. Mientras esta prueba pase, partir el XAML
        no ha podido cambiar nada en tiempo de ejecución.

        Si algún día hay que cambiar la ventana a propósito, esta prueba
        fallara: entonces se revisa el cambio y se actualiza la copia. Ese
        es justo el momento en que uno quiere que algo le pare.
    #>

    BeforeAll {
        $script:CarpetaUi = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        # Xaml.ps1 no depende de WPF, así que se carga tal cual.
        . (Join-Path $script:CarpetaUi 'Xaml.ps1')
    }

    It 'el documento montado es identico al original, byte a byte' {
        # Oraculo de esta prueba: el documento tal y como era ANTES de
        # partirlo en Panel.*.xaml. Se renombro de
        # "datos-MainWindow-antes-de-partir.xaml": el nombre parecia un
        # resto de refactor olvidado e invitaba a borrarlo, cuando es lo
        # unico que garantiza que Expand-PanelesXaml reconstruye la ventana
        # byte a byte. Ver [REP-05] en docs/PLAN-ACCION.md.
        $original = [IO.File]::ReadAllText(
            (Join-Path (Join-Path $PSScriptRoot 'datos') 'MainWindow.montado.esperado.xaml'))
        $montado  = Expand-PanelesXaml -Texto ([IO.File]::ReadAllText((Join-Path $script:CarpetaUi 'MainWindow.xaml'))) `
                                       -Carpeta $script:CarpetaUi
        $montado | Should -BeExactly $original
    }

    It 'el documento montado sigue siendo XML valido' {
        $montado = Expand-PanelesXaml -Texto ([IO.File]::ReadAllText((Join-Path $script:CarpetaUi 'MainWindow.xaml'))) `
                                      -Carpeta $script:CarpetaUi
        { [xml]$montado } | Should -Not -Throw
    }

    It 'una marca que apunte a un panel inexistente falla al momento y lo dice' {
        # En silencio, el panel simplemente no estaria: una pestaña en
        # blanco y ningún error. Mejor no abrir.
        { Expand-PanelesXaml -Texto '<!--#panel Panel.QueNoExiste.xaml-->' -Carpeta $script:CarpetaUi } |
            Should -Throw -ExpectedMessage '*Panel.QueNoExiste.xaml*'
    }

    It 'cada Panel.*.xaml se usa y cada marca tiene su archivo' {
        $marcas = @([regex]::Matches(
            [IO.File]::ReadAllText((Join-Path $script:CarpetaUi 'MainWindow.xaml')),
            '<!--#panel\s+([^\s>]+?)\s*-->') | ForEach-Object { $_.Groups[1].Value })
        $archivos = @(Get-ChildItem $script:CarpetaUi -Filter 'Panel.*.xaml' | ForEach-Object { $_.Name })

        @($marcas   | Where-Object { $_ -notin $archivos }) | Should -BeNullOrEmpty -Because 'marca sin archivo'
        @($archivos | Where-Object { $_ -notin $marcas })   | Should -BeNullOrEmpty -Because 'archivo que no monta nadie'
    }

    It 'ningun panel declara xmlns por su cuenta' {
        # Un fragmento con su propio xmlns no se puede pegar dentro de otro
        # documento: sería XML invalido en cuanto se montara.
        foreach ($archivo in (Get-ChildItem $script:CarpetaUi -Filter 'Panel.*.xaml')) {
            # Sin los comentarios: la cabecera de cada panel explica
            # precisamente que no declara xmlns, y buscar la palabra suelta
            # hacia fallar la prueba por su propia documentación.
            $sinComentarios = [regex]::Replace([IO.File]::ReadAllText($archivo.FullName), '(?s)<!--.*?-->', '')
            $sinComentarios | Should -Not -Match 'xmlns\s*=' -Because "$($archivo.Name) es un trozo, no un documento"
        }
    }
}

Describe 'Fase 6: invariantes del hilo de analisis' {

    <#
        La interfaz no se puede arrancar desde las pruebas: WPF necesita una
        ventana de verdad. Lo que SI se puede comprobar, y es lo que se
        rompe en silencio, son las propiedades estructurales del codigo.
        Cada una de estas nace de un fallo concreto del plan de accion.
    #>

    BeforeAll {
        $script:RutaAnalisis = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/UI') 'Window.Analisis.ps1'
        $script:TextoAnalisis = Get-Content -Raw -LiteralPath $script:RutaAnalisis
    }

    Context 'INT-01: un solo runspace por operacion' {

        It 'el nucleo se carga en el arranque del runspace, no en cada trabajo' {
            $script:TextoAnalisis | Should -Match 'codigoArranqueRunspace'
            $script:TextoAnalisis | Should -Match '\$abrirRunspace'
        }

        It 'los guiones por modulo ya NO cargan Bootstrap' {
            # Cada Bootstrap son mas de cuatro mil lineas dot-sourceadas.
            # Hacerlo por modulo era pagarlo veintiuna veces por analisis.
            #
            # Se cuentan las INVOCACIONES, no las menciones: el comentario
            # que explica por que esto importa nombra el archivo, y contarlo
            # haria fallar la prueba por documentar bien el motivo.
            $cargas = @([regex]::Matches($script:TextoAnalisis, "(?m)^\s*\.\s+\(Join-Path[^\n]*Bootstrap\.ps1"))
            $cargas.Count | Should -Be 1 -Because 'solo el arranque del runspace lo carga'
        }

        It 'limpiarTrabajo NO cierra el runspace: lo comparten los modulos' {
            $ini = $script:TextoAnalisis.IndexOf('$limpiarTrabajo = {')
            $fin = $script:TextoAnalisis.IndexOf('$siguienteModulo = {')
            $cuerpo = $script:TextoAnalisis.Substring($ini, $fin - $ini)

            $cuerpo | Should -Not -Match 'Runspace\.Close\(\)' -Because (
                'cerrarlo por modulo es justo lo que obligaba a reabrirlo veintiuna veces')
        }

        It 'existe un cierre dedicado y lo llaman los tres finales' {
            $script:TextoAnalisis | Should -Match '\$cerrarRunspace = \{'

            # terminarAnalisis, terminarBorrado y el cierre de la ventana.
            $ui = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/UI'
            $llamantes = @(
                Get-ChildItem -LiteralPath $ui -Filter '*.ps1' |
                Where-Object { (Get-Content -Raw -LiteralPath $_.FullName) -match '& \$cerrarRunspace' }
            )
            $llamantes.Count | Should -BeGreaterOrEqual 3 -Because (
                'si alguno se olvida, el runspace queda abierto hasta cerrar el programa')
        }
    }

    Context 'INT-02: un fallo al lanzar no deja la ventana bloqueada' {

        It 'todo el montaje del trabajo va dentro de un try' {
            $ini = $script:TextoAnalisis.IndexOf('$lanzarTrabajo = {')
            $fin = $script:TextoAnalisis.IndexOf('$limpiarTrabajo = {')
            $cuerpo = $script:TextoAnalisis.Substring($ini, $fin - $ini)

            $cuerpo | Should -Match '(?s)try\s*\{.*BeginInvoke.*\}\s*catch' -Because (
                'sin esto, un fallo al abrir el runspace dejaba Ocupado en $true para siempre')
        }

        It 'el catch devuelve la ventana a un estado usable' {
            $ini = $script:TextoAnalisis.IndexOf('$lanzarTrabajo = {')
            $fin = $script:TextoAnalisis.IndexOf('$limpiarTrabajo = {')
            $cuerpo = $script:TextoAnalisis.Substring($ini, $fin - $ini)

            $cuerpo | Should -Match 'terminarAnalisis'
            $cuerpo | Should -Match 'terminarBorrado'
            $cuerpo | Should -Match 'cerrarRunspace' -Because 'el runspace abierto tambien hay que soltarlo'
        }
    }

    Context 'INT-03: el boton de tema no toca la configuracion durante un trabajo' {

        It 'refrescarDiscos solo se llama si no hay nada en marcha' {
            $texto = Get-Content -Raw -LiteralPath (
                Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/UI') 'Window.Ayudantes.ps1')

            # $refrescarDiscos escribe Configuracion.Unidades, y ese objeto
            # viaja POR REFERENCIA al runspace que esta analizando.
            $texto | Should -Match '(?s)if \(-not \$estado\.Ocupado\) \{\s*& \$refrescarDiscos'
        }
    }

    Context 'INT-04: cerrar en mitad de un borrado no pierde el historial' {

        It 'el manejador de cierre declara los parametros del evento' {
            $texto = Get-Content -Raw -LiteralPath (
                Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/UI') 'Window.Eventos.ps1')
            $texto | Should -Match '(?s)Add_Closing\(\{.*param\(\$remitente, \$argumentos\)' -Because (
                'sin parametros de evento es imposible cancelar el cierre')
        }

        It 'anota la limpieza interrumpida antes de soltar nada' {
            $texto = Get-Content -Raw -LiteralPath (
                Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/UI') 'Window.Eventos.ps1')
            $texto | Should -Match 'limpieza-interrumpida' -Because (
                'el programa habia borrado archivos de verdad y no quedaba constancia')
        }
    }
}

Describe 'Fase 6: la ventana y la consola cuentan lo mismo' {

    It 'las dos anotan en el historial los bytes RECUPERABLES' {
        # El mismo analisis producia dos cifras distintas en historial.json
        # segun se lanzara desde la ventana o desde la consola. Ver [INT-12].
        $raiz = Split-Path $PSScriptRoot -Parent
        $ventana = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/UI/Window.Analisis.ps1')
        $consola = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/Cli/Cli.ps1')

        $ventana | Should -Match "Add-EntradaHistorial -Tipo 'analisis' -Elementos \`$estado\.Items\.Count -Bytes \`$bytesBorrables"
        $consola | Should -Match "Add-EntradaHistorial -Tipo 'analisis' -Elementos \`$todos\.Count -Bytes \`$bytesTotales"
    }

    It 'la consola pasa -Sync al motor de borrado, como la ventana' {
        # La comprobacion sigue el CAMINO, no una linea concreta: desde
        # [ARQ-01] el bucle vive en Remove.ps1 y las dos interfaces lo
        # comparten, asi que -Sync hace dos saltos. Lo que importa es que
        # llegue: sin el se pierden las lineas de registro del momento que
        # mas importa auditar.
        $raiz = Split-Path $PSScriptRoot -Parent

        $consola = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/Cli/Cli.ps1')
        $consola | Should -Match '(?s)Invoke-LoteEliminacion.*-Sync \$sync'

        $ventana = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/UI/Window.Analisis.ps1')
        $ventana | Should -Match '(?s)Invoke-LoteEliminacion.*-Sync \$sync'

        $motor = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/Core/Remove.ps1')
        $motor | Should -Match '(?s)Invoke-EliminacionCandidato -Candidato \$candidato.*-Sync \$Sync'
    }

    It 'ARQ-01: el bucle de borrado existe UNA sola vez' {
        # Antes estaba en la consola y, otra vez, dentro de una cadena de
        # texto del runspace de la ventana. Ya habian divergido: la copia
        # de la ventana contaba como hecho todo lo que intentaba y anotaba
        # PAPELERA para cosas que se borraban permanentemente.
        $raiz = Split-Path $PSScriptRoot -Parent
        $copias = 0
        foreach ($archivo in @('src/Cli/Cli.ps1', 'src/UI/Window.Analisis.ps1')) {
            $texto = Get-Content -Raw -LiteralPath (Join-Path $raiz $archivo)
            $copias += @([regex]::Matches($texto, 'Invoke-EliminacionCandidato')).Count
        }
        $copias | Should -Be 0 -Because (
            'las dos interfaces tienen que llamar a Invoke-LoteEliminacion, no reimplementar el bucle')
    }
}

Describe 'CNF-04: un analisis incompleto no puede presentarse como completo' {

    <#
        Cancelar en el modulo 7 de 21 producia el MISMO texto que recorrer
        los 21: "Analisis terminado". El usuario miraba una lista a la que
        le faltaban catorce modulos creyendo que ahi estaba todo lo que su
        equipo tiene, y decidia que borrar con esa idea.

        Lo mismo con los modulos que fallan -constaba solo en el registro,
        que nadie abre- y con una limpieza detenida a mitad, que se anotaba
        en el historial igual que una completa.

        Es la misma familia que [COR-01] y [SEG-20]: el programa contando
        algo distinto de lo que hizo. Aqui no destruye datos, pero lleva a
        decidir sobre informacion falsa, que acaba en lo mismo.
    #>

    BeforeAll {
        $script:RaizCnf = Split-Path $PSScriptRoot -Parent
        $script:SinComentarios = {
            param([string] $Relativa)
            (Get-Content -LiteralPath (Join-Path $script:RaizCnf $Relativa) |
                Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        }
        $script:Analisis    = & $script:SinComentarios 'src/UI/Window.Analisis.ps1'
        $script:Eliminacion = & $script:SinComentarios 'src/UI/Window.Eliminacion.ps1'
        $script:Consola     = & $script:SinComentarios 'src/Cli/Cli.ps1'
    }

    It 'la ventana distingue terminado de detenido' {
        $script:Analisis | Should -Match 'Análisis detenido'
        $script:Analisis | Should -Match 'Análisis terminado'
    }

    It 'cancelar deja marca, no solo una linea en el registro' {
        $script:Analisis | Should -Match '\$estado\.AnalisisCancelado\s*=\s*\$true'
    }

    It 'se apunta QUE modulo ha fallado, no solo que hubo un error' {
        $script:Analisis | Should -Match '\$estado\.ModulosFallidos\.Add'
    }

    It 'la franja se enciende cuando falta algo y se apaga cuando no' {
        $script:Analisis | Should -Match "AvisoIncompleto\.Visibility\s*=\s*'Visible'"
        $script:Analisis | Should -Match "AvisoIncompleto\.Visibility\s*=\s*'Collapsed'"
    }

    It 'el historial recibe la verdad en los dos caminos' {
        # Si solo lo hiciera uno, tendriamos otra vez dos interfaces
        # contando cosas distintas: el error de [ARQ-01] y de [INT-12].
        $script:Analisis    | Should -Match 'Add-EntradaHistorial[\s\S]{0,600}-Incompleto'
        $script:Eliminacion | Should -Match 'Add-EntradaHistorial[\s\S]{0,600}-Incompleto'
        $script:Consola     | Should -Match 'Add-EntradaHistorial[\s\S]{0,600}-Incompleto'
    }

    It 'no se anotan como revisados los modulos que no se llegaron a mirar' {
        # Anotar los 21 de la cola cuando solo corrieron 7 convierte el
        # historial en otro sitio donde el programa miente.
        $script:Analisis | Should -Match 'Select-Object -First \$revisados'
        $script:Consola  | Should -Match 'notin \$idsFallidos'
    }

    It 'una limpieza detenida no se llama terminada' {
        $script:Eliminacion | Should -Match 'LIMPIEZA DETENIDA'
    }

    It 'la consola avisa igual que la ventana' {
        $script:Consola | Should -Match 'esta lista está incompleta'
    }

    It 'las banderas se reinician en cada analisis' {
        # Un aviso heredado del analisis anterior es la misma mentira con
        # el signo cambiado: asustar sobre una lista que si esta entera.
        $eventos = & $script:SinComentarios 'src/UI/Window.Eventos.ps1'
        $eventos | Should -Match '\$estado\.AnalisisCancelado\s*=\s*\$false'
        $eventos | Should -Match '\$estado\.ModulosFallidos\.Clear\(\)'
    }
}

Describe 'I18N-01: el texto que lee el usuario se escribe en espanol correcto' {

    <#
        Los informes salian con "Atencion", "version", "vacias", "Cache de
        miniaturas". Los archivos llevan marca de orden de bytes desde hace
        tiempo, asi que no habia ninguna razon tecnica para escribir asi:
        era inercia de cuando si la habia.

        Se comprueban SOLO las cadenas de prosa -catorce caracteres o mas y
        al menos dos espacios-, que es lo que acaba en la pantalla y en el
        informe. Los comentarios quedan fuera a proposito: son para quien
        lee el codigo, y mantenerlos en ASCII puro evita sustos de
        codificacion en las herramientas.

        La lista es de palabras INEQUIVOCAS. "solo", "esta", "mas", "de" y
        "si" cambian de significado con la tilde y solo se pueden decidir
        leyendo la frase, asi que no estan aqui: prohibirlas produciria
        avisos falsos y la gente aprenderia a ignorar la prueba.
    #>

    BeforeAll {
        $script:RaizI18n = Split-Path $PSScriptRoot -Parent
        $script:SinTilde = @(
            'atencion', 'version', 'analisis', 'informacion', 'aplicacion',
            'configuracion', 'eliminacion', 'ubicacion', 'deteccion', 'ejecucion',
            'proteccion', 'extension', 'opcion', 'accion', 'sesion', 'revision',
            'conexion', 'instalacion', 'compilacion',
            'numero', 'codigo', 'menu', 'maquina', 'limite', 'minimo', 'maximo',
            'ningun', 'algun', 'ademas', 'despues', 'segun', 'tambien', 'aqui',
            'util', 'facil', 'dias', 'vacia', 'vacias', 'estan',
            'ultimo', 'ultima', 'ultimos', 'cache', 'caches', 'musica', 'anyos'
        )
    }

    It 'la prueba encuentra prosa: si no, no comprueba nada' {
        $s = 'Se ha borrado la carpeta entera'
        ($s.Length -ge 14 -and $s.Split(' ').Count -ge 3) | Should -BeTrue
    }

    It 'ninguna cadena de prosa usa una palabra sin su tilde' {
        $patron = '\b(' + ($script:SinTilde -join '|') + ')\b'
        $culpables = @()

        foreach ($archivo in @(Get-ChildItem (Join-Path $script:RaizI18n 'src') -Filter '*.ps1' -Recurse)) {
            $n = 0
            $enBloque = $false
            foreach ($linea in (Get-Content -LiteralPath $archivo.FullName)) {
                $n++
                # Los comentarios de bloque <# ... #> tambien quedan fuera:
                # ahi dentro hay explicaciones que citan codigo, y una de
                # ellas -"$null -contains $extension" en Guard.ps1- hacia
                # saltar la prueba por una palabra que nadie lee en pantalla.
                if ($linea -match '<#') { $enBloque = $true }
                if ($enBloque) {
                    if ($linea -match '#>') { $enBloque = $false }
                    continue
                }
                if ($linea -match '^\s*#') { continue }

                foreach ($m in [regex]::Matches($linea, "'([^'`n]+)'|`"([^`"`n]+)`"")) {
                    $texto = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }

                    # Se quitan las interpolaciones ANTES de mirar. Dentro
                    # de "hace $dias dias" hay dos cosas distintas: una
                    # variable, que es codigo y se escribe sin tildes, y una
                    # palabra, que es prosa y lleva la suya. Sin esta linea
                    # la prueba pedia acentuar el nombre de la variable, que
                    # es exactamente el error que se cometio al corregir
                    # esto por primera vez.
                    $texto = $texto -replace '\$\([^)]*\)', ' ' -replace '\$[A-Za-z_][A-Za-z0-9_:.]*', ' '

                    if ($texto.Length -lt 14) { continue }
                    if (@($texto -split ' ' | Where-Object { $_ }).Count -lt 3) { continue }
                    if ($texto -cmatch $patron) {
                        $culpables += ('{0}:{1}  {2}' -f $archivo.Name, $n, $matches[0])
                    }
                }
            }
        }
        $culpables | Should -BeNullOrEmpty
    }

    It 'ninguna variable lleva tilde donde el resto del archivo no la lleva' {
        # Esto no es estilo: es la cicatriz de haber corregido las tildes
        # con un reemplazo automatico que entro DENTRO de cadenas
        # interpoladas y renombro variables. "hace $dias dias" se convirtio
        # en "hace $dias dias" con la variable acentuada, que no existia, y
        # el modulo de restos dejo de encontrar nada. Las pruebas lo
        # cazaron; esta comprobacion lo caza antes y dice por que.
        $culpables = @()
        foreach ($archivo in @(Get-ChildItem (Join-Path $script:RaizI18n 'src') -Filter '*.ps1' -Recurse)) {
            $texto  = Get-Content -Raw -LiteralPath $archivo.FullName
            $nombres = @([regex]::Matches($texto, '\$([A-Za-z_áéíóúñÁÉÍÓÚÑ][A-Za-z0-9_áéíóúñÁÉÍÓÚÑ]*)') |
                         ForEach-Object { $_.Groups[1].Value } |
                         Where-Object { $_ -cmatch '[áéíóúñÁÉÍÓÚÑ]' } | Select-Object -Unique)
            foreach ($nombre in $nombres) {
                $plano = $nombre -replace '[áÁ]', 'a' -replace '[éÉ]', 'e' -replace '[íÍ]', 'i' `
                                 -replace '[óÓ]', 'o' -replace '[úÚ]', 'u' -replace '[ñÑ]', 'n'
                if ($texto -cmatch ('\$' + [regex]::Escape($plano) + '\b')) {
                    $culpables += ('{0}: ${1} y ${2} conviven' -f $archivo.Name, $nombre, $plano)
                }
            }
        }
        $culpables | Should -BeNullOrEmpty -Because (
            'la misma variable escrita de dos formas significa que una de las dos no existe')
    }
}

Describe 'COR-07: ninguna lista generica se crea con New-Object' {

    <#
        Fallo real, encontrado ejecutando el programa en Windows despues de
        que la suite entera pasara en verde.

        "New-Object System.Collections.Generic.List[object]" devuelve un
        objeto que el operador @( ) no puede enumerar: lanza
        ArgumentException ("Los tipos de argumentos no coinciden"). Falla
        con la lista vacia, y falla SOLO con List[object]: la misma llamada
        con List[string], HashSet, Dictionary u ObservableCollection va
        bien. foreach, el pipe, .Count y .ToArray() tambien van bien; el
        unico que revienta es @( ).

        Como Export-InformeHtml empieza por "$lista = @($Candidatos)" y la
        ventana guardaba los candidatos en una lista de esas, TODOS los
        informes fallaban. Las pruebas no lo veian porque le pasaban un
        array: probaban un tipo que la aplicacion no usa.

        La regla se aplica a toda la familia Generic aunque hoy solo
        List[object] este roto. Distinguir cual de los tipos es seguro
        obliga a recordar una excepcion arbitraria, y ::new() no tiene
        ningun inconveniente.
    #>

    BeforeAll {
        $script:RaizProy = Split-Path $PSScriptRoot -Parent
        $script:Fuentes  = @(Get-ChildItem -Path (Join-Path $script:RaizProy 'src') -Filter '*.ps1' -Recurse) +
                           @(Get-ChildItem -Path $script:RaizProy -Filter 'Cachivache.ps1')
    }

    It 'la prueba encuentra archivos: si no, no comprueba nada' {
        @($script:Fuentes).Count | Should -BeGreaterThan 20
    }

    It 'ningun archivo usa New-Object con una coleccion generica' {
        $culpables = @()
        foreach ($archivo in $script:Fuentes) {
            $n = 0
            foreach ($linea in (Get-Content -LiteralPath $archivo.FullName)) {
                $n++
                if ($linea -match '^\s*#') { continue }
                if ($linea -match 'New-Object\s+[''"]?(System\.)?Collections\.Generic\.') {
                    $culpables += ('{0}:{1}' -f $archivo.Name, $n)
                }
            }
        }
        $culpables | Should -BeNullOrEmpty -Because (
            'hay que usar [Collections.Generic.X[...]]::new(); ver el comentario de Candidatos en Window.ps1')
    }

    It 'ningun Grid coloca cosas a la derecha sin declarar columnas' {
        # LA SEGUNDA VERSION DE ESTA PRUEBA, Y POR QUE HIZO FALTA.
        #
        # La primera exigia DOS GRUPOS HORIZONTALES en el mismo Grid, que
        # era el caso que se acababa de arreglar en la barra de
        # herramientas. Cazaba ese y ninguno mas.
        #
        # Media hora despues, la misma captura de pantalla enseñaba el
        # MISMO fallo en la barra de abajo: "32 elementos marcados" y la
        # casilla "Solo simular" superpuestas. Alli el grupo de la
        # izquierda era un StackPanel VERTICAL -sin atributo Orientation-,
        # asi que la prueba no lo miraba siquiera. Estaba escrita sobre el
        # ejemplo que tenia delante en vez de sobre la regla, que es
        # exactamente el error de la regla 8 del relevo cometido otra vez
        # y el mismo dia.
        #
        # LA REGLA DE VERDAD no habla de orientaciones: en un Grid sin
        # columnas todos los hijos ocupan LA MISMA CELDA. Poner uno con
        # HorizontalAlignment="Right" es fingir dos columnas con la
        # alineacion, y funciona exactamente hasta que el contenido crece:
        # entonces se pintan uno encima del otro, sin recortarse, sin
        # desplazarse y sin avisar.
        #
        # Con columnas declaradas la de Auto reserva su ancho ANTES de
        # repartir, y el solape deja de poder ocurrir. Nueve sitios en
        # cinco paneles seguian el patron; dos se solapaban ya.
        #
        # Aqui no hay WPF y no se puede medir un pixel. Se prohibe la
        # ESTRUCTURA, que es lo unico comprobable desde una prueba.
        $malos = @()
        foreach ($archivo in @(Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'src') `
                                             -Filter '*.xaml' -Recurse)) {
            $texto = [IO.File]::ReadAllText($archivo.FullName)
            # Grids HOJA: los que no contienen otro Grid dentro. Son donde
            # se colocan los controles de verdad.
            foreach ($m in [regex]::Matches($texto, '(?s)<Grid(?<attr>[^>]*)>(?<cuerpo>((?!<Grid[\s>]).)*?)</Grid>')) {
                $cuerpo = $m.Groups['cuerpo'].Value
                if ($cuerpo -notmatch 'HorizontalAlignment="Right"') { continue }
                if ($cuerpo -match '<Grid\.ColumnDefinitions>')      { continue }
                # Un solo hijo alineado a la derecha no se solapa con nada.
                $hijos = @([regex]::Matches($cuerpo,
                    '<(StackPanel|WrapPanel|DockPanel|Border|Button|TextBlock|CheckBox|ComboBox|Slider|ProgressBar|Image)[\s>]')).Count
                if ($hijos -lt 2) { continue }
                $linea = ($texto.Substring(0, $m.Index) -split "`n").Count
                $malos += ('{0}:{1}' -f $archivo.Name, $linea)
            }
        }
        $malos -join ', ' | Should -BeNullOrEmpty -Because (
            'sin columnas, todos los hijos comparten celda y se PINTAN ENCIMA cuando no caben')
    }

    It 'ningun Grid apila DOS grupos horizontales en la misma celda' {
        # EL FALLO QUE ENCONTRO ESTA PRUEBA, y lo encontro un ojo humano
        # antes que ella.
        #
        # La barra de herramientas de Panel.Resultados.xaml era un Grid SIN
        # columnas con dos hijos dentro: un grupo horizontal alineado a la
        # izquierda y otro alineado a la derecha. En un Grid sin columnas
        # los dos hijos ocupan LA MISMA CELDA, asi que en cuanto la suma de
        # sus anchos pasa del ancho disponible se pintan UNO ENCIMA DEL
        # OTRO. No se recortan, no se desplazan, no avisan: se superponen,
        # con los rotulos entremezclados e ilegibles.
        #
        # La casilla de [USO-13] anyadio unos 170 px al grupo izquierdo y
        # los cruzo. Se vio el 1 de septiembre de 2026, la primera vez que
        # alguien miro la ventana ejecutandose, y llevaba anotado como
        # SOSPECHA en docs/PRUEBA-MANUAL.md desde el 30 de agosto.
        #
        # Ninguna prueba de este proyecto puede medir un pixel: aqui no hay
        # WPF. Lo que si se puede es prohibir la ESTRUCTURA que lo hace
        # posible, que es lo que hace esta prueba. Un Grid con dos grupos
        # horizontales tiene que declarar columnas; con ellas, la de Auto
        # reserva su ancho antes de repartir y el solape deja de poder
        # ocurrir.
        $malos = @()
        foreach ($archivo in @(Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'src') `
                                             -Filter '*.xaml' -Recurse)) {
            $texto = [IO.File]::ReadAllText($archivo.FullName)
            # Un Grid, lo que hay dentro, y su cierre. Sin anidar: basta con
            # los que no contienen otro Grid dentro, que son las hojas donde
            # de verdad se colocan los controles.
            foreach ($m in [regex]::Matches($texto, '(?s)<Grid(?<attr>[^>]*)>(?<cuerpo>((?!<Grid[\s>]).)*?)</Grid>')) {
                $cuerpo = $m.Groups['cuerpo'].Value
                $grupos = @([regex]::Matches($cuerpo, '<(StackPanel|WrapPanel)[^>]*Orientation="Horizontal"'))
                if ($grupos.Count -lt 2) { continue }
                # Con columnas declaradas, o con cada grupo en su fila, el
                # solape no puede darse.
                if ($cuerpo -match '<Grid\.ColumnDefinitions>') { continue }
                if ($m.Groups['attr'].Value -match 'ColumnDefinitions') { continue }
                $malos += ('{0}: un Grid con {1} grupos horizontales y sin columnas' -f
                           $archivo.Name, $grupos.Count)
            }
        }
        $malos -join ' // ' | Should -BeNullOrEmpty -Because (
            'dos grupos horizontales en la misma celda se PINTAN ENCIMA cuando no caben')
    }

    It 'ningun archivo usa un acelerador de tipos que 5.1 no tiene' {
        # EL FALLO QUE ENCONTRO ESTA PRUEBA, y es el peor de su clase.
        #
        # src/Core/IndiceIncremental.ps1 comprobaba "$Valor -is [short]".
        # [short] es un acelerador que PowerShell NO trae hasta la version
        # 6: en Windows PowerShell 5.1 esa linea lanza "Unable to find type
        # [short]" y se lleva por delante la funcion entera. O sea que
        # [VEL-02] estaba MUERTO en la unica plataforma donde el programa
        # se ejecuta de verdad, mientras la suite de PowerShell 7 lo daba
        # por bueno.
        #
        # Por que se cuela: un nombre de tipo dentro de un -is solo se
        # resuelve al EJECUTAR esa linea. No falla al cargar el archivo, no
        # lo ve el analizador, y solo se nota si una prueba pasa por ahi
        # EN 5.1. Son 21 pruebas las que lo destaparon, y todas de golpe en
        # la integracion continua.
        #
        # Los tres nombres de abajo llegaron en PowerShell 6. Todos tienen
        # un equivalente que si existe en 5.1 y significa exactamente lo
        # mismo: [int16], [uint16] y [sbyte] por su nombre de .NET.
        $prohibidos = @{
            'short'  = '[int16]'
            'ushort' = '[uint16]'
            'bigint' = '[System.Numerics.BigInteger]'
        }
        $culpables = @()
        foreach ($archivo in $script:Fuentes) {
            $n = 0
            foreach ($linea in (Get-Content -LiteralPath $archivo.FullName)) {
                $n++
                if ($linea -match '^\s*#') { continue }
                foreach ($malo in $prohibidos.Keys) {
                    if ($linea -match ('\[\s*{0}\s*\]' -f $malo)) {
                        $culpables += ('{0}:{1} usa [{2}], hay que usar {3}' -f
                                       $archivo.Name, $n, $malo, $prohibidos[$malo])
                    }
                }
            }
        }
        $culpables -join ' // ' | Should -BeNullOrEmpty -Because (
            'esos aceleradores llegaron en PowerShell 6 y el programa corre en 5.1')
    }

    It 'ningun literal hexadecimal con el bit alto puesto se escribe sin la L' {
        # EL FALLO QUE ENCONTRO ESTA PRUEBA, y es hermano del de arriba.
        #
        # src/Core/DiarioUsn.ps1 escribia la mascara de razones del diario
        # USN asi: [uint32]0xFFFFFFFF. En PowerShell ese literal NO es un
        # UInt32 que vale 4.294.967.295: son ocho digitos, o sea 32 bits, y
        # el analizador lo lee como un Int32 QUE VALE -1. Convertir -1 a
        # UInt32 lanza. Y lanzaba dentro del try de Read-DiarioUsn, dos
        # lineas antes de la unica llamada al sistema de toda la funcion,
        # asi que el catch lo devolvia como $null y desde fuera se veia
        # exactamente igual que "Windows ha dicho que no".
        #
        # POR QUE NINGUNA DE LAS 2.454 PRUEBAS LO VIO: Read-DiarioUsn abre
        # \\.\C: en crudo. No se puede ejecutar en Linux, no se puede
        # ejecutar sin ser administrador, y la integracion continua no es
        # administrador. Las 107 pruebas de [VEL-02] cubren el calculo puro
        # que rodea a esa funcion y no podian decir nada de ella. Se
        # descubrio ejecutandolo a mano en la maquina del usuario, elevado.
        #
        # Y LO PEOR: la trampa ESTABA YA EXPLICADA, con estas mismas
        # palabras, en la cabecera de Get-RegistroUsn, 436 lineas mas
        # arriba EN EL MISMO ARCHIVO. Saber una cosa escrita no es lo mismo
        # que tenerla comprobada. Por eso esto es una invariante y no un
        # parrafo mas.
        #
        # LA REGLA, y esta si se puede barrer: un literal 0x de EXACTAMENTE
        # ocho digitos que empiece por 8-F tiene el bit de signo puesto y es
        # un Int32 negativo. Sirve para comparar con -band -que promociona a
        # Int64 y compara contra el numero equivocado- y LANZA al convertir
        # a cualquier tipo sin signo. La L lo convierte en Int64 y las dos
        # cosas pasan a funcionar. Los de dieciseis digitos que empiezan por
        # 8-F son Int64 negativos y la L no los salva, asi que se rechazan
        # siempre: hay que escribirlos en decimal o con ::MaxValue.
        #
        # Se pregunta "hay alguno mal?" barriendo src/, tools/ y la raiz, y
        # NO "los tres que conozco estan bien" (regla 8 de docs/RELEVO.md).
        function script:Get-SinComentariosHex {
            param([string] $Ruta)
            $t = [IO.File]::ReadAllText($Ruta)
            # Los bloques <# #> ANTES que las lineas de #. Al reves, el
            # primer paso se lleva la linea del "#>" y el bloque se queda
            # sin cerrar. Aqui importa de verdad: los comentarios de este
            # repositorio CITAN el literal sin L para explicar la trampa,
            # asi que leerlos pondria esta prueba roja por su propia
            # documentacion. Ya paso, y no una sola vez.
            $t = [regex]::Replace($t, '(?s)<#.*?#>', '')
            return (@($t -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
        }

        # EL DETECTOR, APARTE, PARA PODER APUNTARLO CONTRA SI MISMO. Ver la
        # guarda de cordura del final: si esto viviera pegado al bucle de
        # abajo, la unica forma de comprobar que detecta algo seria que el
        # repositorio contuviera un ejemplo, y eso es una dependencia que no
        # se controla.
        function script:Get-LiteralesPeligrosos {
            param([string] $Texto)
            $malos = @()
            $n = 0
            foreach ($linea in ($Texto -split "`n")) {
                $n++
                # Ocho digitos justos, el primero de 8 a F, y lo que venga
                # detras. El (?![0-9A-Fa-f]) impide que un literal de nueve
                # o mas digitos entre por aqui partido por la mitad.
                foreach ($m in [regex]::Matches($linea, '0x(?<d>[89A-Fa-f][0-9A-Fa-f]{7})(?![0-9A-Fa-f])(?<suf>[Ll]?)')) {
                    if ($m.Groups['suf'].Value) { continue }
                    # EL VALOR SE SACA POR LOS BYTES Y NO CON [int]. La
                    # primera version de esta linea decia
                    # [int][Convert]::ToUInt32(...), y eso LANZA con
                    # 4.294.967.295: "no se puede convertir al tipo Int32".
                    # O sea que la prueba cometia, al redactar su propio
                    # mensaje, exactamente el fallo que viene a cazar, y
                    # salia roja con un error de conversion en vez de con
                    # la lista de culpables. Salio mutando. Reinterpretar
                    # los cuatro bytes es lo que hace el analizador de
                    # PowerShell, asi que ademas es el numero de verdad.
                    $valor = [BitConverter]::ToInt32(
                                 [BitConverter]::GetBytes([Convert]::ToUInt32($m.Groups['d'].Value, 16)), 0)
                    $malos += ('linea {0}: 0x{1} sin la L (es un Int32 que vale {2})' -f
                               $n, $m.Groups['d'].Value, $valor)
                }
                foreach ($m in [regex]::Matches($linea, '0x(?<d>[89A-Fa-f][0-9A-Fa-f]{15})(?![0-9A-Fa-f])')) {
                    $malos += ('linea {0}: 0x{1}, que es un Int64 negativo y la L no lo arregla' -f
                               $n, $m.Groups['d'].Value)
                }
            }
            return $malos
        }

        # LA GUARDA DE CORDURA, Y ESTA ES LA SEGUNDA VERSION. La primera
        # exigia que el barrido encontrara al menos un literal BIEN escrito
        # -habia dos, en Mft.ps1 y en DiarioUsnCambios.ps1- razonando que si
        # no ve ni esos, no esta mirando el codigo.
        #
        # Era una guarda apoyada en algo que no se controla. El 5 de
        # septiembre de 2026 se borraron esos dos archivos al descartar
        # [VEL-01] y [VEL-02], y con ellos los dos unicos ejemplos: la
        # prueba se habria puesto roja acusando al barrido de estar ciego
        # cuando el barrido estaba perfecto.
        #
        # Ahora el detector se demuestra CONTRA SI MISMO, con texto
        # fabricado aqui. Eso no depende de lo que el repositorio contenga
        # hoy, y ademas comprueba las dos mitades: que ve lo malo y que NO
        # marca lo bueno. Una guarda que solo comprobara lo primero pasaria
        # con un detector que devolviera "todo es culpable".
        @(script:Get-LiteralesPeligrosos '$mascara = [uint32]0xFFFFFFFF').Count |
            Should -Be 1 -Because 'si no ve el literal sin L, el barrido no detecta nada'
        @(script:Get-LiteralesPeligrosos '$fin = 0x8000000000000001').Count |
            Should -Be 1 -Because 'los de dieciseis digitos que empiezan por 8-F tambien'
        @(script:Get-LiteralesPeligrosos "`$ok = 0xFFFFFFFFL
`$tambien = 0x7FFFFFFF
`$y = 0x00000010
`$nueve = 0xFFFFFFFFF").Count |
            Should -Be 0 -Because 'un detector que marca lo correcto no sirve de nada'

        $aBarrer = @($script:Fuentes) +
                   @(Get-ChildItem -Path (Join-Path $script:RaizProy 'tools') -Filter '*.ps1' -Recurse)
        @($aBarrer).Count | Should -BeGreaterThan 20 -Because 'sin archivos que barrer, esto no comprueba nada'

        $culpables = @()
        foreach ($archivo in $aBarrer) {
            foreach ($malo in @(script:Get-LiteralesPeligrosos (script:Get-SinComentariosHex $archivo.FullName))) {
                $culpables += ('{0} {1}' -f $archivo.Name, $malo)
            }
        }

        $culpables -join ' // ' | Should -BeNullOrEmpty -Because (
            'un 0x de ocho digitos que empieza por 8-F es un Int32 NEGATIVO: ' +
            'lanza al convertirlo a un tipo sin signo y compara mal con -band')
    }

    It 'la lista de candidatos de la ventana se puede enumerar con @( )' {
        # La comprobacion de verdad: se construye igual que Window.ps1 y se
        # enumera igual que Report.ps1. Si alguien vuelve a cambiarlo por
        # New-Object, esto falla aqui y no en el equipo del usuario.
        $lista = [Collections.Generic.List[object]]::new()
        $lista.Add([pscustomobject]@{ Bytes = 10 })
        $lista.Add([pscustomobject]@{ Bytes = 20 })

        { $null = @($lista) } | Should -Not -Throw
        @($lista).Count | Should -Be 2
    }
}

Describe 'CNF-02: simular no puede dejar rastro de una limpieza que no ocurrio' {

    <#
        La simulacion existe para que el usuario pueda mirar antes de
        borrar. Si al terminar apunta una entrada en el historial y guarda
        un informe titulado "limpieza", el programa acaba afirmando haber
        hecho algo que no hizo: exactamente la familia de fallo que toda
        esta auditoria lleva cerrando -Hecho puesto antes de consolidar
        errores, PAPELERA para borrados permanentes, enlaces duros contados
        como espacio recuperado-.

        Se comprueban los DOS caminos, porque el fallo original de este
        proyecto fue justo ese: la ventana y la consola divergiendo.
    #>

    BeforeAll {
        $script:Raiz = Split-Path $PSScriptRoot -Parent
        $script:Consola = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/Cli/Cli.ps1')
        $script:Cierre  = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Window.Eliminacion.ps1')
    }

    It 'la consola no anota historial cuando simula' {
        $script:Consola | Should -Match '(?s)if \(-not \$Simular\).*Add-EntradaHistorial'
    }

    It 'la ventana corta ANTES de anotar historial y de exportar el informe' {
        # No basta con que exista la condicion: tiene que estar por delante
        # de las dos llamadas. Se compara la POSICION en el texto, que es lo
        # unico que garantiza el orden real de ejecucion.
        $corte     = $script:Cierre.IndexOf('if ($simulado)')
        $historial = $script:Cierre.IndexOf('Add-EntradaHistorial')
        $informe   = $script:Cierre.IndexOf('Export-InformeHtml')

        $corte     | Should -BeGreaterThan -1 -Because 'tiene que haber una rama de simulacion'
        $historial | Should -BeGreaterThan $corte -Because 'el historial se anota despues del corte, nunca antes'
        $informe   | Should -BeGreaterThan $corte -Because 'el informe se exporta despues del corte, nunca antes'
    }

    It 'la ventana sale de la rama de simulacion sin seguir' {
        # Sin el return, la rama solo anyade texto y despues cae en el
        # camino normal: historial e informe incluidos.
        #
        # Se mira el TROZO entre el corte y la primera linea del camino
        # normal, en vez de una expresion regular con [^}]*: los mensajes
        # de dentro llevan marcadores de formato {0} y {1}, y esa llave de
        # cierre corta la busqueda antes de tiempo. La primera version de
        # esta prueba fallaba por eso, no por el codigo.
        $corte  = $script:Cierre.IndexOf('if ($simulado)')
        $normal = $script:Cierre.IndexOf('$libreAhora = Get-EspacioLibre')

        $corte  | Should -BeGreaterThan -1
        $normal | Should -BeGreaterThan $corte

        $rama = $script:Cierre.Substring($corte, $normal - $corte)
        $rama | Should -Match '(?m)^\s*return\s*$' -Because (
            'sin return, la rama solo anyade texto y luego borra igual')
    }

    It 'el modo del lote se congela al lanzarlo, no se relee de la casilla al final' {
        # Entre el arranque y el final el usuario puede desmarcar la
        # casilla. Si el cierre mirara el control, una simulacion acabaria
        # anotada como limpieza real.
        $script:Cierre | Should -Match '\$simulado\s*=\s*\[bool\]\$estado\.SimulandoLote'
        $script:Cierre | Should -Not -Match 'ChkSimular' -Because (
            'el cierre decide por el estado congelado, nunca por el control')
    }

    It 'simular no se guarda entre sesiones' {
        # Guardada en preferencias, se queda activada en silencio: vuelves
        # semanas despues, lees "se habrian eliminado", no ves el
        # condicional y te vas creyendo que has limpiado.
        $prefs = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/Core/Preferencias.ps1')
        $prefs | Should -Not -Match '(?m)^\s*Simular\s*=' -Because (
            'no es una preferencia, es una comprobacion previa a un acto concreto')
    }

    It 'la casilla de la ventana llega al motor de borrado' {
        # El camino completo: casilla -> estado -> runspace -> motor. Si se
        # corta en cualquier punto, la ventana ensenya "Solo simular" y
        # borra de verdad, que es el peor fallo imaginable aqui.
        $eventos  = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Window.Eventos.ps1')
        $analisis = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Window.Analisis.ps1')

        $eventos  | Should -Match '\$simular\s*=\s*\[bool\]\$c\.ChkSimular\.IsChecked'
        $eventos  | Should -Match '(?s)\$lanzarTrabajo \$codigoBorrado.*simular\s*=\s*\$simular'
        $analisis | Should -Match 'Invoke-LoteEliminacion.*-Simular:\$simular'
    }

    It 'el boton no puede decir "Eliminar" mientras simula' {
        $eventos = Get-Content -Raw -LiteralPath (Join-Path $script:Raiz 'src/UI/Window.Eventos.ps1')
        $eventos | Should -Match "BtnEliminar\.Content\s*=\s*'Simular limpieza'"
    }
}

Describe 'COR-04: las cuatro listas de metodos no pueden divergir' {

    <#
        La lista de metodos validos vive en CUATRO sitios: el comentario de
        cabecera de Candidate.ps1, su ValidateSet, el array $sinRuta de
        ModuleRegistry.ps1 y el switch de Remove.ps1.

        Y nada falla si olvidas uno. El switch cae en 'default', que BORRA
        POR RUTA: un metodo nuevo pensado para vaciar contenido o para
        informar acabaria borrando la carpeta entera. Es el fallo
        silencioso mas peligroso que le queda al contrato.

        Diez lineas de prueba para que no pueda pasar.
    #>

    BeforeAll {
        $script:CarpetaNucleo = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'Core'

        # 1. La fuente de verdad: el ValidateSet del parametro -Metodo.
        $astCandidato = Get-AstDe (Join-Path $script:CarpetaNucleo 'Candidate.ps1')
        $conjunto = $astCandidato.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AttributeAst] -and
                      $n.TypeName.Name -eq 'ValidateSet'
        }, $true) | Select-Object -First 1
        $script:MetodosValidos = @($conjunto.PositionalArguments |
                                   ForEach-Object { $_.Value })

        # 2. Las ramas del switch del motor de borrado.
        $astRemove = Get-AstDe (Join-Path $script:CarpetaNucleo 'Remove.ps1')
        $switch = $astRemove.FindAll({
            param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] -and
                      $n.Condition.Extent.Text -match 'Metodo'
        }, $true) | Select-Object -First 1
        $script:RamasSwitch = @($switch.Clauses | ForEach-Object { $_.Item1.Extent.Text.Trim("'`"") })

        # 3. Los metodos exentos de la guardia por no tener ruta real.
        $textoRegistro = Get-Content -Raw -LiteralPath (
            Join-Path $script:CarpetaNucleo 'ModuleRegistry.ps1')
        $script:SinRuta = @()
        if ($textoRegistro -match "\`$sinRuta\s*=\s*@\(([^)]*)\)") {
            $script:SinRuta = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim("'`"") } |
                                Where-Object { $_ })
        }

        # 4. El comentario de cabecera que los documenta.
        $textoCandidato = Get-Content -Raw -LiteralPath (
            Join-Path $script:CarpetaNucleo 'Candidate.ps1')
        $script:Documentados = @([regex]::Matches($textoCandidato, '(?m)^#\s{3}(\w+)\s+->') |
                                 ForEach-Object { $_.Groups[1].Value })
    }

    It 'la prueba encuentra las cuatro listas: si no, no comprueba nada' {
        $script:MetodosValidos.Count | Should -BeGreaterThan 4
        $script:RamasSwitch.Count    | Should -BeGreaterThan 0
        $script:SinRuta.Count        | Should -BeGreaterThan 0
        $script:Documentados.Count   | Should -BeGreaterThan 4
    }

    It 'todo metodo del ValidateSet esta documentado en la cabecera' {
        $sinDocumentar = @($script:MetodosValidos | Where-Object { $_ -notin $script:Documentados })
        $sinDocumentar | Should -BeNullOrEmpty -Because (
            'la cabecera de Candidate.ps1 es donde se explica que hace cada metodo')
    }

    It 'todo metodo documentado existe de verdad en el ValidateSet' {
        # El caso inverso: documentar un metodo que ya no existe manda a
        # quien lo lea a buscar codigo que no esta.
        $inventados = @($script:Documentados | Where-Object { $_ -notin $script:MetodosValidos })
        $inventados | Should -BeNullOrEmpty
    }

    It 'todo metodo o tiene rama propia en el motor, o esta exento de la guardia' {
        # 'Ruta' es el comportamiento por defecto y no necesita rama: es
        # justo lo que hace el 'default' del switch.
        $cubiertos = @($script:RamasSwitch) + @($script:SinRuta) + @('Ruta')
        $huerfanos = @($script:MetodosValidos | Where-Object { $_ -notin $cubiertos })

        $huerfanos | Should -BeNullOrEmpty -Because (
            'un metodo sin rama cae en el default del switch, que BORRA POR RUTA: ' +
            'un metodo pensado para informar acabaria borrando la carpeta')
    }

    It 'ninguna rama del switch invoca a un metodo que ya no existe' {
        $fantasmas = @($script:RamasSwitch | Where-Object { $_ -notin $script:MetodosValidos })
        $fantasmas | Should -BeNullOrEmpty -Because 'codigo inalcanzable que aparenta cubrir un caso'
    }

    It 'ningun metodo exento de la guardia se ha quedado sin existir' {
        $fantasmas = @($script:SinRuta | Where-Object { $_ -notin $script:MetodosValidos })
        $fantasmas | Should -BeNullOrEmpty
    }

    It 'CNF-03: todo metodo esta clasificado como recuperable o como irreversible' {
        <#
            La quinta lista. Se anyade a esta prueba y no a otra a
            proposito: el problema de [COR-04] es que una lista de metodos
            suelta acaba divergiendo, y crear una sexta sin meterla aqui
            seria repetir el error que esta prueba existe para impedir.

            Aqui lo que se promete es que algo se puede RESCATAR de la
            papelera. Si un metodo nuevo se quedara sin clasificar y el
            codigo lo diera por recuperable por descarte, el programa
            ofreceria recuperar algo que ya no existe. Prometer de menos
            molesta; prometer de mas rompe la confianza que este proyecto
            dice tener como pilar.
        #>
        $texto = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaNucleo 'Remove.ps1')

        $leerLista = {
            param([string] $Nombre)
            if ($texto -match ("\`$script:$Nombre\s*=\s*@\(([^)]*)\)")) {
                return @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim("'`"") } |
                         Where-Object { $_ })
            }
            return @()
        }

        $recuperables  = @(& $leerLista 'MetodosRecuperables')
        $irreversibles = @(& $leerLista 'MetodosIrreversibles')

        $recuperables.Count  | Should -BeGreaterThan 0 -Because 'si no se leen, la prueba no comprueba nada'
        $irreversibles.Count | Should -BeGreaterThan 0

        # 1. Juntas cubren TODOS los metodos validos.
        $clasificados = @($recuperables) + @($irreversibles)
        $sinClasificar = @($script:MetodosValidos | Where-Object { $_ -notin $clasificados })
        $sinClasificar | Should -BeNullOrEmpty -Because (
            'un metodo sin clasificar se daria por recuperable por descarte, y el programa ' +
            'ofreceria rescatar de la papelera algo que nunca fue a la papelera')

        # 2. Y no se solapan: un metodo no puede ser las dos cosas.
        $ambiguos = @($recuperables | Where-Object { $_ -in $irreversibles })
        $ambiguos | Should -BeNullOrEmpty

        # 3. Ninguna inventa metodos que no existen.
        $fantasmas = @($clasificados | Where-Object { $_ -notin $script:MetodosValidos })
        $fantasmas | Should -BeNullOrEmpty
    }
}

Describe 'CNF-05: el criterio se dice en los DOS caminos' {

    <#
        El criterio de premarcado estaba en el README, en ARQUITECTURA.md y
        en el panel "Acerca de": tres sitios donde nadie mira mientras
        decide que borrar. Y si solo lo dijera uno de los dos caminos,
        volveriamos al problema de [ARQ-01]: la ventana y la consola
        contando cosas distintas.
    #>

    BeforeAll {
        $script:RaizCnf5 = Split-Path $PSScriptRoot -Parent
        $script:SinCom = {
            param([string] $Rel)
            [regex]::Replace(
                ((Get-Content -LiteralPath (Join-Path $script:RaizCnf5 $Rel) |
                  Where-Object { $_ -notmatch '^\s*#' }) -join "`n"), '(?s)<#.*?#>', '')
        }
    }

    It 'la ventana lo ensenya en el resumen del analisis' {
        (& $script:SinCom 'src/UI/Window.Analisis.ps1') | Should -Match 'Get-ResumenPremarcado'
    }

    It 'la consola tambien' {
        (& $script:SinCom 'src/Cli/Cli.ps1') | Should -Match 'Get-ResumenPremarcado'
    }

    It 'y cada fila lleva su motivo' {
        (& $script:SinCom 'src/UI/Window.Analisis.ps1') | Should -Match 'MotivoMarcado = Get-MotivoPremarcado'
    }

    It 'la regla se decide en UN solo sitio' {
        # Si New-Candidato volviera a llevar la condicion escrita a mano,
        # la explicacion y la decision podrian divergir sin que nada falle.
        $candidato = & $script:SinCom 'src/Core/Candidate.ps1'
        $candidato | Should -Match '\$marcado = Test-DebeVenirMarcado'
        $candidato | Should -Not -Match "\`$marcado = \`$Riesgo -eq 'Bajo' -and"
    }
}

Describe 'La ventana no puede pedir un recurso que no existe' {

    <#
        Un {StaticResource} mal escrito NO falla al escribirlo ni al
        interpretar el XML: falla al ABRIR LA VENTANA, con una excepcion
        que se lleva el programa entero antes de que exista un sitio donde
        contarlo.

        Esta prueba nace de haberlo hecho: al anyadir el plegado de grupos
        de [USO-04] se referencio {StaticResource BoolAVisible} sin haberlo
        declarado. Se cazo por casualidad, mirando la salida. La casualidad
        no es un metodo.

        Es la comprobacion mas cercana a "la ventana abrira" que se puede
        hacer sin WPF, y protege TODO lo que se ha construido hoy: siete
        sitios de XAML tocados sin poder ejecutarlos.
    #>

    BeforeAll {
        $script:CarpetaXaml = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'
        $script:Xamls = @(Get-ChildItem $script:CarpetaXaml -Filter '*.xaml')

        # Las claves se declaran con x:Key, en cualquiera de los archivos:
        # los diccionarios de tema y el de estilos se mezclan al arrancar,
        # asi que una clave de Theme.Dark.xaml vale para MainWindow.xaml.
        $script:Claves = @{}
        foreach ($archivo in $script:Xamls) {
            $texto = Get-Content -Raw -LiteralPath $archivo.FullName
            foreach ($m in [regex]::Matches($texto, 'x:Key="([^"]+)"')) {
                $script:Claves[$m.Groups[1].Value] = $archivo.Name
            }
        }

        # Las referencias, sin los comentarios: dentro de un <!-- --> puede
        # haber ejemplos de codigo que no son referencias de verdad.
        $script:Referencias = @{}
        foreach ($archivo in $script:Xamls) {
            $texto = [regex]::Replace(
                (Get-Content -Raw -LiteralPath $archivo.FullName), '(?s)<!--.*?-->', '')
            foreach ($m in [regex]::Matches($texto, '\{(?:Static|Dynamic)Resource\s+([A-Za-z_][\w.]*)\s*\}')) {
                $clave = $m.Groups[1].Value
                if (-not $script:Referencias.ContainsKey($clave)) { $script:Referencias[$clave] = @() }
                $script:Referencias[$clave] += $archivo.Name
            }
        }
    }

    It 'la prueba encuentra recursos: si no, no comprueba nada' {
        $script:Claves.Count      | Should -BeGreaterThan 20
        $script:Referencias.Count | Should -BeGreaterThan 20
    }

    It 'toda referencia a un recurso tiene su clave declarada' {
        $huerfanas = @()
        foreach ($clave in $script:Referencias.Keys) {
            if (-not $script:Claves.ContainsKey($clave)) {
                $huerfanas += ('{0} (usado en {1})' -f $clave,
                               (($script:Referencias[$clave] | Select-Object -Unique) -join ', '))
            }
        }
        $huerfanas | Should -BeNullOrEmpty -Because (
            'un recurso que no existe no falla al escribirlo: se lleva la ventana entera al abrirla')
    }

    It 'los dos temas declaran las mismas claves que se usan como DynamicResource' {
        # Un color que solo exista en el tema oscuro deja la ventana a
        # medio pintar al cambiar al claro, sin ningun error.
        $oscuro = @{}
        $claro  = @{}
        foreach ($par in @(@('Theme.Dark.xaml', $oscuro), @('Theme.Light.xaml', $claro))) {
            $texto = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaXaml $par[0])
            foreach ($m in [regex]::Matches($texto, 'x:Key="([^"]+)"')) { $par[1][$m.Groups[1].Value] = $true }
        }
        @($oscuro.Keys | Where-Object { -not $claro.ContainsKey($_) })  | Should -BeNullOrEmpty
        @($claro.Keys  | Where-Object { -not $oscuro.ContainsKey($_) }) | Should -BeNullOrEmpty
    }
}

Describe 'El teclado tiene que poder salir del dialogo y no puede navegar sin querer' {
    <#
        Los tres arreglos de [A11Y-03] y [A11Y-05] son atributos de XAML.
        Un atributo de XAML no lo protege nadie: se borra en un refactor de
        formato y nada se queja, porque la ventana sigue abriendo. Lo que
        desaparece en silencio es la unica salida de teclado del dialogo que
        confirma un borrado.
    #>

    BeforeAll {
        $script:CarpetaUiTeclado = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        function Get-XamlSinComentarios {
            param([string]$Nombre)
            # Sin los comentarios: si no, la prueba se encuentra a si misma
            # escrita en la explicacion de al lado y pasa sin comprobar nada.
            [regex]::Replace(
                (Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUiTeclado $Nombre)),
                '(?s)<!--.*?-->', '')
        }

        $script:Dialogo = Get-XamlSinComentarios 'ConfirmDialog.xaml'
        $script:Ventana = Get-XamlSinComentarios 'MainWindow.xaml'
    }

    It 'la prueba mira archivos con contenido: si no, no comprueba nada' {
        $script:Dialogo.Length | Should -BeGreaterThan 1000
        $script:Ventana.Length | Should -BeGreaterThan 1000
    }

    It 'el boton de cancelar es el de Escape' {
        # Sin IsCancel, Escape solo funcionaba con el foco dentro del cuadro
        # de texto: si habias tabulado hasta un boton, no habia salida.
        $script:Dialogo | Should -Match 'x:Name="BtnNo"[^>]*IsCancel="True"' -Because (
            'un dialogo que bloquea la ventana tiene que poder cerrarse con el teclado desde cualquier foco')
    }

    It 'el boton de borrar NO es el de Enter' {
        # Lo contrario del anterior: IsDefault lanzaria el borrado con Enter
        # desde cualquier foco, en el unico dialogo que existe para frenar
        # un gesto automatico.
        $script:Dialogo | Should -Not -Match 'IsDefault="True"' -Because (
            'el dialogo existe para frenar un clic distraido; Enter global lo convertiria en un tramite')
    }

    It 'el dialogo no puede crecer hasta sacar los botones de la pantalla' {
        # SizeToContent="Height" + una lista que la escribe el usuario = un
        # dialogo tan alto como haga falta. Sin tope, los botones acaban por
        # debajo del borde inferior y no hay forma de confirmar ni cancelar.
        # La etiqueta <Window ...>, NO el archivo entero. La primera version
        # de esta prueba buscaba MaxHeight en todo el texto y encontraba el
        # del ScrollViewer de la lista de riesgo, que lleva ahi desde
        # [USO-08]: quitar el tope de la VENTANA no la hacia fallar. Se vio
        # borrandolo a proposito y comprobando que seguia pasando.
        $etiqueta = [regex]::Match($script:Dialogo, '(?s)<Window\b.*?>').Value
        $etiqueta | Should -Match 'SizeToContent="Height"' -Because 'si no crece sola, esta prueba mira otra cosa'
        $etiqueta | Should -Match 'MaxHeight="\d+"'

        $tope = [int][regex]::Match($etiqueta, 'MaxHeight="(\d+)"').Groups[1].Value
        $tope | Should -BeLessOrEqual 768 -Because 'el caso peor comun es un portatil de 768 px de alto'
    }

    It 'las flechas no cambian de panel en la barra lateral' {
        $script:Ventana | Should -Match 'KeyboardNavigation\.DirectionalNavigation="None"' -Because (
            'son RadioButton en grupo: en WPF la flecha mueve el foco Y marca, y marcar aqui cambia de panel')
    }

    It 'las seis entradas de navegacion son puntos de tabulacion' {
        # Si las flechas no navegan, Tab es la unica forma de recorrerlas.
        $radios = @([regex]::Matches($script:Ventana, '<RadioButton x:Name="Nav\w+"(?s).*?/>'))
        $radios.Count | Should -Be 6 -Because 'si no son seis, la prueba esta mirando otra cosa'

        foreach ($radio in $radios) {
            $radio.Value | Should -Match 'IsTabStop="True"' -Because (
                'sin flechas, una entrada que Tab no visita es una entrada inalcanzable con teclado')
        }
    }
}

Describe 'La etiqueta de riesgo no puede ser el texto mas pequenyo del programa' {
    <#
        [A11Y-07]. El riesgo es el dato que decide si alguien borra algo o
        no. Estaba a 11 px, el tamanyo mas pequenyo de toda la interfaz.

        Esta prueba no fija "12": fija la RELACION. Si manyana alguien baja
        la etiqueta por debajo de cualquier otro texto del programa, se
        entera aqui y no en una captura de pantalla.
    #>

    BeforeAll {
        $script:Estilos = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI') 'Styles.xaml')),
            '(?s)<!--.*?-->', '')

        # El bloque del estilo, no el archivo entero: buscar "FontSize" suelto
        # en Styles.xaml encontraria los veinte tamanyos de los demas estilos.
        function Get-BloqueEstilo {
            param([string]$Clave)
            $m = [regex]::Match($script:Estilos, ('(?s)<Style x:Key="{0}".*?</Style>' -f [regex]::Escape($Clave)))
            if (-not $m.Success) { throw ('no esta el estilo {0}' -f $Clave) }
            $m.Value
        }

        function Get-TamanyosDeLetra {
            # DOS formas de escribir un tamanyo, y hay que mirar las dos:
            #   <Setter Property="FontSize" Value="13"/>   (dentro de un Style)
            #   FontSize="13"                              (suelto en un elemento)
            # La primera version de esta prueba solo miraba la segunda y
            # encontraba dos tamanyos en todo el archivo: pasaba comparando
            # la etiqueta contra practicamente nada. La deteccion la salvo
            # la guarda de "si no hay tamanyos que comparar", que es justo
            # para lo que esta.
            @([regex]::Matches($script:Estilos, 'Property="FontSize"\s+Value="(\d+)"') |
              ForEach-Object { [int]$_.Groups[1].Value }) +
            @([regex]::Matches($script:Estilos, '(?<!Property=")\bFontSize\s*=\s*"(\d+)"') |
              ForEach-Object { [int]$_.Groups[1].Value })
        }
    }

    It 'la prueba encuentra los dos estilos: si no, no comprueba nada' {
        (Get-BloqueEstilo 'TextoEtiqueta').Length | Should -BeGreaterThan 100
        (Get-BloqueEstilo 'Punto').Length         | Should -BeGreaterThan 50
    }

    It 'ningun texto de la interfaz es mas pequenyo que la etiqueta de riesgo' {
        $etiqueta = [int][regex]::Match((Get-BloqueEstilo 'TextoEtiqueta'), 'Property="FontSize"\s+Value="(\d+)"').Groups[1].Value

        $todos = @(Get-TamanyosDeLetra)
        $todos.Count | Should -BeGreaterThan 5 -Because 'si no hay tamanyos que comparar, la prueba no compara nada'

        # Estrictamente mayor que el minimo, no igual a el. En Styles.xaml
        # el escalon de 11 lo ocupan "Seccion" y las cabeceras de columna:
        # rotulos de estructura que se leen una vez. Eso es correcto. Lo que
        # [A11Y-07] denunciaba es que el riesgo, que se lee en CADA fila y
        # decide si algo se borra, compartia el escalon de abajo con ellos.
        $etiqueta | Should -BeGreaterThan ($todos | Measure-Object -Minimum).Minimum -Because (
            'el dato de seguridad de cada fila no puede ser el texto mas pequenyo del programa')
        $etiqueta | Should -BeGreaterOrEqual 12
    }

    It 'el punto de color se ve al lado de su etiqueta' {
        $punto = [int][regex]::Match((Get-BloqueEstilo 'Punto'), 'Property="Width"\s+Value="(\d+)"').Groups[1].Value
        $punto | Should -BeGreaterOrEqual 9 -Because 'el punto ES el color del riesgo; a 7 px es una mota'

        # Redondo: si alto y ancho se separan, deja de ser un punto.
        $alto = [int][regex]::Match((Get-BloqueEstilo 'Punto'), 'Property="Height"\s+Value="(\d+)"').Groups[1].Value
        $alto | Should -Be $punto
    }

    It 'no se ha inventado un septimo tamanyo de letra' {
        # La hoja de ruta lo dice expresamente: la escala es lo que hace que
        # seis paneles se lean como un solo programa. Subir 11 a 12 usa un
        # escalon que ya existia; lo que no vale es anyadir uno nuevo.
        $escala = @(11, 12, 13, 15, 20, 28)
        $usados = @(Get-TamanyosDeLetra | Sort-Object -Unique)

        @($usados | Where-Object { $_ -notin $escala }) | Should -BeNullOrEmpty -Because (
            'la escala es 11/12/13/15/20/28 y el arreglo tenia que caber dentro')
    }
}

Describe 'Un disparador no puede apuntar a algo que no es un elemento' {
    <#
        [USO-14]. Esto tumbo el programa en Windows con las 928 pruebas en
        verde y el analizador limpio.

        Dentro de una plantilla habia <RotateTransform x:Name="Giro"/> y un
        <Setter TargetName="Giro" Property="Angle"/>. Una RotateTransform es
        un Freezable, no un FrameworkElement: no entra en el ambito de
        nombres de la plantilla, asi que TargetName no la encuentra nunca.

        Y lo que lo hacia dificil de ver: el contenido de una plantilla se
        analiza TARDE, cuando se aplica por primera vez. El XAML cargaba sin
        una queja, la ventana abria, la navegacion funcionaba... y al
        aparecer la primera cabecera de grupo saltaba "La inicializacion de
        System.Windows.Setter produjo una excepcion", una vez por cabecera.

        La forma correcta es apuntar al ELEMENTO -que si tiene nombre- y
        reemplazarle la transformacion entera.
    #>

    BeforeAll {
        $script:CarpetaXamlNombres = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        # Cosas que se escriben dentro de una plantilla y NO son elementos:
        # pintan, transforman o describen una forma, y viven fuera del
        # ambito de nombres. Ponerles nombre solo puede servir para
        # apuntarles, y apuntarles no funciona.
        $script:NoSonElementos = @(
            'RotateTransform', 'ScaleTransform', 'SkewTransform', 'TranslateTransform',
            'MatrixTransform', 'TransformGroup', 'RotateTransform3D',
            'SolidColorBrush', 'LinearGradientBrush', 'RadialGradientBrush', 'ImageBrush',
            'VisualBrush', 'DrawingBrush', 'GradientStop',
            'PathGeometry', 'StreamGeometry', 'RectangleGeometry', 'EllipseGeometry',
            'LineGeometry', 'GeometryGroup', 'CombinedGeometry',
            'DropShadowEffect', 'BlurEffect'
        )

        $script:NombradosPorArchivo = @{}
        foreach ($archivo in (Get-ChildItem $script:CarpetaXamlNombres -Filter '*.xaml')) {
            $texto = [regex]::Replace(
                (Get-Content -Raw -LiteralPath $archivo.FullName), '(?s)<!--.*?-->', '')
            $script:NombradosPorArchivo[$archivo.Name] = $texto
        }
    }

    It 'la prueba lee XAML de verdad: si no, no comprueba nada' {
        $script:NombradosPorArchivo.Count | Should -BeGreaterThan 5
        @($script:NombradosPorArchivo.Values | Where-Object { $_ -match 'x:Name=' }).Count |
            Should -BeGreaterThan 5
    }

    It 'nada que no sea un elemento lleva x:Name' {
        $malos = @()
        foreach ($nombre in $script:NombradosPorArchivo.Keys) {
            foreach ($m in [regex]::Matches($script:NombradosPorArchivo[$nombre], '<([A-Za-z][\w.]*)\s[^>]*x:Name="([^"]+)"')) {
                $etiqueta = $m.Groups[1].Value
                if ($etiqueta -in $script:NoSonElementos) {
                    $malos += ('{0} x:Name="{1}" en {2}' -f $etiqueta, $m.Groups[2].Value, $nombre)
                }
            }
        }
        $malos | Should -BeNullOrEmpty -Because (
            'no esta en el ambito de nombres de la plantilla: TargetName no lo encontrara y WPF lanzara al aplicar el disparador, no al cargar')
    }

    It 'todo TargetName apunta a un nombre que existe en el mismo archivo' {
        # Un TargetName que no resuelve tampoco falla al cargar: falla al
        # aplicarse, que es cuando ya hay alguien delante mirando.
        $huerfanos = @()
        foreach ($nombre in $script:NombradosPorArchivo.Keys) {
            $texto = $script:NombradosPorArchivo[$nombre]
            $declarados = @{}
            foreach ($m in [regex]::Matches($texto, 'x:Name="([^"]+)"')) { $declarados[$m.Groups[1].Value] = $true }

            foreach ($m in [regex]::Matches($texto, 'TargetName="([^"]+)"')) {
                $destino = $m.Groups[1].Value
                if (-not $declarados.ContainsKey($destino)) {
                    $huerfanos += ('{0} -> {1}' -f $nombre, $destino)
                }
            }
        }
        $huerfanos | Should -BeNullOrEmpty
    }
}

Describe 'El manejador de fallos de la ventana no puede volver a inundar la pantalla' {
    <#
        [USO-14]. El limite vive en Test-DebeAvisarDelFallo, pero quien
        tiene que llamarlo es el manejador de Window.ps1, y ahi es una linea
        dentro de un bloque de script: nada obliga a que siga estando.
        Quitarla no rompe ninguna prueba de las otras, porque la funcion
        seguiria existiendo y pasando las suyas.
    #>

    BeforeAll {
        $script:TextoVentana = [regex]::Replace(
            (Get-Content -Raw -LiteralPath (Join-Path (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI') 'Window.ps1')),
            '(?m)^\s*#.*$', '')
    }

    It 'la prueba lee el manejador: si no, no comprueba nada' {
        $script:TextoVentana | Should -Match 'Add_DispatcherUnhandledException'
    }

    It 'el aviso por pantalla pasa por el filtro de repetidos' {
        $script:TextoVentana | Should -Match 'Test-DebeAvisarDelFallo' -Because (
            'sin el, un fallo que se repite abre un cuadro modal por repeticion y entierra la ventana')
    }

    It 'el registro se escribe SIEMPRE, tenga o no tenga aviso' {
        # El filtro es para la pantalla, no para el registro: ahi si
        # interesa cada aparicion. Que Write-Registro quede dentro del if
        # seria cambiar "no te molesto mas" por "no te lo cuento".
        $manejador = [regex]::Match($script:TextoVentana,
            '(?s)Add_DispatcherUnhandledException\(\{.*?\$argumentos\.Handled = \$true').Value
        $manejador.Length | Should -BeGreaterThan 200 -Because 'si no, la prueba mira otra cosa'

        $posicionRegistro = $manejador.IndexOf('Write-Registro')
        $posicionFiltro   = $manejador.IndexOf('Test-DebeAvisarDelFallo')
        $posicionRegistro | Should -BeGreaterThan 0
        $posicionFiltro   | Should -BeGreaterThan $posicionRegistro -Because (
            'primero se anota y despues se decide si ademas se avisa')
    }
}

Describe 'El cartel de la simulación no puede quedarse mintiendo' {
    <#
        [USO-15]. El cartel dice "se habrian liberado 9,83 GB", y esa cifra
        es la de lo que estaba marcado CUANDO se simulo. En cuanto alguien
        marca o desmarca una fila deja de corresponder a nada.

        Un cartel viejo encima de una selección nueva es la misma familia de
        mentira que este proyecto lleva cerrando desde el principio, solo
        que mas educada. Por eso caduca en $actualizarResumenSeleccion, que
        es exactamente el sitio por el que pasa todo cambio de marcado.
    #>

    BeforeAll {
        $script:CarpetaUiSim = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        function Get-FuenteUi {
            param([string]$Nombre)
            [regex]::Replace(
                (Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUiSim $Nombre)),
                '(?m)^\s*#.*$', '')
        }

        $script:Ayudantes   = Get-FuenteUi 'Window.Ayudantes.ps1'
        $script:Eliminacion = Get-FuenteUi 'Window.Eliminacion.ps1'
    }

    It 'la prueba lee los dos archivos: si no, no comprueba nada' {
        $script:Ayudantes   | Should -Match 'actualizarResumenSeleccion'
        $script:Eliminacion | Should -Match 'terminarBorrado'
    }

    It 'la simulación deja el resultado en Resultados, no solo en el Registro' {
        $script:Eliminacion | Should -Match 'AvisoSimulacion' -Because (
            'el registro es otro panel: quien pulsa el boton no lo esta mirando')
        $script:Eliminacion | Should -Match 'Format-ResumenSimulacion'
    }

    It 'el cartel caduca al cambiar la selección' {
        $script:Ayudantes | Should -Match 'AvisoSimulacion' -Because (
            'sus cifras son las de lo que estaba marcado al simular')
    }

    It 'si el cartel no esta, se dice' {
        # Un FindName que devuelve nulo no lanza al LEERLO: se traga la
        # linea y el programa sigue tan tranquilo. Un bloque que existe
        # para que la simulación deje de ser muda no puede quedarse mudo el.
        $script:Eliminacion | Should -Match 'AVISO INTERNO' -Because (
            'fallar en silencio al avisar es el mismo fallo, escondido un piso mas abajo')
    }

    It 'la cabecera de grupo no depende de un disparador para decir el numero' {
        # Hubo un Style con DataTrigger para el singular: en Windows el
        # disparador se aplicaba y el valor por defecto no, asi que las
        # categorias de una fila decian "1 elemento" y las de doce se
        # quedaban en "12", sin palabra. Aqui no hay WPF con el que
        # averiguar por que, y por eso no vuelve.
        $cabecera = [regex]::Match(
            (Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUiSim 'Panel.Resultados.xaml')),
            '(?s)<ControlTemplate TargetType="GroupItem">.*?</ControlTemplate>').Value
        $cabecera.Length | Should -BeGreaterThan 500 -Because 'si no, la prueba mira otra cosa'

        $sinComentarios = [regex]::Replace($cabecera, '(?s)<!--.*?-->', '')
        $sinComentarios | Should -Not -Match '<Style TargetType="Run"' -Because (
            'no se deja en la cabecera un mecanismo que no se puede comprobar aqui')
    }

    It 'se pone DESPUES de actualizar el resumen, que es quien lo borra' {
        # Al reves, la simulación se tapaba a si misma: ponia el cartel y la
        # llamada siguiente lo quitaba. Habria quedado exactamente igual de
        # mudo que antes, y con codigo nuevo que parecia arreglarlo.
        $bloque = [regex]::Match($script:Eliminacion,
            '(?s)if \(\$simulado\).*?return').Value
        $bloque.Length | Should -BeGreaterThan 200 -Because 'si no, la prueba mira otra cosa'

        $posResumen = $bloque.IndexOf('actualizarResumenSeleccion')
        $posCartel  = $bloque.IndexOf('AvisoSimulacion')
        $posResumen | Should -BeGreaterThan 0
        $posCartel  | Should -BeGreaterThan $posResumen
    }
}

Describe 'A11Y-01: ningun control sin texto puede quedarse sin nombre accesible' {
    <#
        [A11Y-01]. Antes de esto no habia UNA sola AutomationProperties.Name
        en los ocho XAML del proyecto.

        Lo que eso significa en la practica: el nombre accesible de un Button
        sale de su Content, y los cuatro botones de la barra de titulo tienen
        por Content un dibujo -un Path, un Border-, asi que un lector de
        pantalla anunciaba los cuatro como "boton" y no habia forma de saber
        cual cerraba el programa. Igual la casilla de cada fila de la tabla:
        cientos de "casilla, sin marcar" sin decir de que, en la columna que
        decide lo que se borra.

        Por que hace falta una invariante y no basta con haberlo arreglado:
        este fallo es MUDO en las dos direcciones. Ni la ventana se queja, ni
        el analizador ve nada, ni ninguna otra prueba lo nota, ni el
        desarrollador -que ve la pantalla- lo percibe jamas. Es exactamente la
        familia de [USO-14]: algo que solo se manifiesta delante de un usuario
        concreto, en un equipo que aqui no hay.

        Dos reglas, y la segunda es la que de verdad muerde:

        1. Todo control interactivo SIN texto propio declara un nombre.
        2. Todo nombre que sea un enlace apunta a una propiedad que EXISTE.
           Un {Binding Titluo} mal escrito no lanza, no avisa y no rompe
           nada visible: WPF resuelve a vacio y el control se queda tan mudo
           como estaba, pero ahora con el atributo puesto y pareciendo
           arreglado. Es la peor version del fallo.
    #>

    BeforeAll {
        $script:CarpetaA11y = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'
        . (Join-Path $script:CarpetaA11y 'Xaml.ps1')

        # El documento MONTADO, por el mismo motivo que la prueba de nombres
        # de arriba: el armazon suelto solo trae los cuatro botones de la
        # barra de titulo y esta prueba se quedaria sin ver los seis paneles.
        $montado = Expand-PanelesXaml -Carpeta $script:CarpetaA11y `
                       -Texto ([IO.File]::ReadAllText((Join-Path $script:CarpetaA11y 'MainWindow.xaml')))

        $script:DocsA11y = @{
            'MainWindow (montado)' = [xml] $montado
            'ConfirmDialog.xaml'   = [xml] ([IO.File]::ReadAllText(
                                        (Join-Path $script:CarpetaA11y 'ConfirmDialog.xaml')))
        }

        # Controles con los que el usuario INTERACTUA. Un TextBlock o un Path
        # no entran: son contenido, y un lector de pantalla los lee como
        # texto. Lo que aqui importa es lo que se puede pulsar, marcar,
        # escribir o arrastrar, porque eso el lector lo anuncia por su
        # NOMBRE, y sin nombre lo anuncia por su tipo a secas.
        $script:Interactivos = @(
            'Button', 'RadioButton', 'CheckBox', 'TextBox', 'ComboBox',
            'ToggleButton', 'Slider', 'PasswordBox', 'RepeatButton'
        )

        # Todos los controles interactivos de los dos documentos, con lo que
        # hace falta para juzgarlos.
        $script:ControlesA11y = @()
        foreach ($doc in $script:DocsA11y.Keys) {
            foreach ($n in $script:DocsA11y[$doc].SelectNodes('//*')) {
                if ($script:Interactivos -notcontains $n.LocalName) { continue }

                $contenido = $n.GetAttribute('Content')
                # Un Content enlazado no es texto propio: puede venir vacio.
                $tieneTextoPropio = $contenido -and ($contenido -notmatch '^\s*\{')

                $script:ControlesA11y += [pscustomobject]@{
                    Documento = $doc
                    Etiqueta  = $n.LocalName
                    Nombre    = $(if ($n.GetAttribute('x:Name')) { $n.GetAttribute('x:Name') } else { '(anonimo)' })
                    Texto     = $tieneTextoPropio
                    Auto      = $n.GetAttribute('AutomationProperties.Name')
                }
            }
        }

        # Las propiedades que las clases de la ventana exponen de verdad.
        # Se sacan del codigo, no de una lista escrita a mano: una lista a
        # mano es justo lo que fallo en [VAL-01] con las cinco palabras del
        # registro.
        $texto = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaA11y 'Types.ps1')
        $script:PropiedadesVista = @{}
        foreach ($m in [regex]::Matches($texto, 'public\s+(?!class\b|abstract\b|event\b|override\b|virtual\b)[\w<>\[\],\s]*?([A-Za-z_]\w*)\s*(?:\r?\n\s*)?\{\s*get')) {
            $script:PropiedadesVista[$m.Groups[1].Value] = $true
        }
    }

    It 'la prueba lee controles de verdad: si no, no comprueba nada' {
        # Sin esta guarda, un cambio que rompiera el montaje o el XPath
        # dejaria la lista vacia y las dos pruebas de abajo pasarian
        # celebrando que no hay ni un control mal.
        $script:ControlesA11y.Count | Should -BeGreaterThan 30
        @($script:ControlesA11y | Where-Object { -not $_.Texto }).Count |
            Should -BeGreaterThan 10 -Because 'la ventana tiene botones de icono, casillas y campos sin rotulo propio'
        $script:PropiedadesVista.Count | Should -BeGreaterThan 20 -Because 'si no, se leyo mal Types.ps1'
    }

    It 'todo control sin texto propio declara AutomationProperties.Name' {
        $mudos = @($script:ControlesA11y |
            Where-Object { -not $_.Texto -and -not $_.Auto } |
            ForEach-Object { '{0}: {1} {2}' -f $_.Documento, $_.Etiqueta, $_.Nombre })

        $mudos | Should -BeNullOrEmpty -Because (
            'un lector de pantalla lo anunciaria solo por su tipo, y con varios iguales no hay forma de distinguirlos')
    }

    It 'ningun nombre accesible esta en blanco' {
        # AutomationProperties.Name="" pasa la prueba de arriba y no sirve
        # para nada. Es el atajo obvio para callar un fallo.
        $vacios = @($script:ControlesA11y |
            Where-Object { $null -ne $_.Auto -and $_.Auto -ne '' -and $_.Auto.Trim() -eq '' } |
            ForEach-Object { '{0}: {1}' -f $_.Documento, $_.Nombre })

        $vacios | Should -BeNullOrEmpty
    }

    It 'todo nombre enlazado apunta a una propiedad que existe' {
        # La regla de fondo: donde hay un rotulo visible enlazado, el nombre
        # accesible usa EL MISMO enlace, para que no puedan separarse. Eso
        # solo se sostiene si la propiedad existe; si no, el control queda
        # mudo igual que antes y encima parece arreglado.
        $rotos = @()
        foreach ($c in $script:ControlesA11y) {
            if (-not $c.Auto) { continue }
            $m = [regex]::Match($c.Auto, '^\{Binding\s+(?:Path=)?([A-Za-z_]\w*)')
            if (-not $m.Success) { continue }

            $propiedad = $m.Groups[1].Value
            if (-not $script:PropiedadesVista.ContainsKey($propiedad)) {
                $rotos += ('{0}: {1} -> {2}' -f $c.Documento, $c.Nombre, $propiedad)
            }
        }

        $rotos | Should -BeNullOrEmpty -Because (
            'WPF resuelve un enlace roto a vacio sin lanzar: el control se queda mudo y el atributo aparenta que no')
    }
}

Describe 'A11Y-06: cambiar de panel tiene que notarse sin mirar la pantalla' {
    <#
        [A11Y-06]. Cambiar de panel solo alternaba Visibility.

        Para quien ve la pantalla eso basta: el contenido cambia delante. Para
        un lector de pantalla no ocurria NADA, porque los lectores anuncian lo
        que tiene el FOCO, no lo que se ha vuelto visible. El foco se quedaba
        en el boton de la barra lateral: el usuario pulsaba "Resultados", oia
        "Resultados, boton de opcion, marcado", y ahi se acababa. Ninguna
        pista de que delante tenia ya una tabla con seiscientas filas.

        Y de paso se cierra un agujero mas viejo que estaba al lado. Los
        nombres de los seis paneles viven en CUATRO sitios -el x:Name del
        XAML, la lista que resuelve Window.ps1, el bucle de mostrarPanel y las
        seis lineas que los enganchan a la barra lateral- y nada comparaba las
        cuatro listas. Es la misma forma de [COR-04], con el mismo final
        silencioso: anyadir un septimo panel y olvidar el bucle no rompe nada
        visible, simplemente ese panel no se oculta nunca y se queda encima
        del que toca.
    #>

    BeforeAll {
        $script:CarpetaFoco = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'

        # 1. Los paneles segun el XAML.
        $script:PanelesXaml = @{}
        $script:TextoPanel  = @{}
        foreach ($archivo in (Get-ChildItem $script:CarpetaFoco -Filter 'Panel.*.xaml')) {
            $texto = Get-Content -Raw -LiteralPath $archivo.FullName
            $m = [regex]::Match($texto, 'x:Name="(Panel[A-Za-z]+)"')
            if ($m.Success) {
                $script:PanelesXaml[$m.Groups[1].Value] = $archivo.Name
                $script:TextoPanel[$m.Groups[1].Value]  = $texto
            }
        }

        # 2. Los paneles que Window.ps1 resuelve por FindName.
        $ventana = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaFoco 'Window.ps1')
        $script:PanelesResueltos = @{}
        foreach ($m in [regex]::Matches($ventana, "'(Panel[A-Za-z]+)'")) {
            $script:PanelesResueltos[$m.Groups[1].Value] = $true
        }

        # 3. Los paneles del bucle de mostrarPanel, acotado a su bloque para
        #    no arrastrar cadenas de otras partes del archivo.
        $ayudantes = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaFoco 'Window.Ayudantes.ps1')
        $script:BloqueMostrar = [regex]::Match($ayudantes, '(?s)\$mostrarPanel = \{.*?\r?\n    \}').Value
        $script:PanelesBucle = @{}
        foreach ($m in [regex]::Matches($script:BloqueMostrar, "'(Panel[A-Za-z]+)'")) {
            $script:PanelesBucle[$m.Groups[1].Value] = $true
        }

        # 4. Los paneles que la barra lateral sabe pedir.
        $eventos = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaFoco 'Window.Eventos.ps1')
        $script:PanelesNavegacion = @{}
        foreach ($m in [regex]::Matches($eventos, "mostrarPanel '(Panel[A-Za-z]+)'")) {
            $script:PanelesNavegacion[$m.Groups[1].Value] = $true
        }
    }

    It 'la prueba encuentra las cuatro listas: si no, no comprueba nada' {
        $script:PanelesXaml.Count       | Should -BeGreaterThan 4
        $script:PanelesResueltos.Count  | Should -Be $script:PanelesXaml.Count
        $script:PanelesBucle.Count      | Should -BeGreaterThan 4
        $script:PanelesNavegacion.Count | Should -BeGreaterThan 4
        $script:BloqueMostrar.Length    | Should -BeGreaterThan 200 -Because 'si no, se acoto mal el bloque de mostrarPanel'
    }

    It 'las cuatro listas de paneles dicen exactamente lo mismo' {
        # Un panel que este en el XAML y no en el bucle NO SE OCULTA NUNCA:
        # se queda pintado encima del panel al que se acaba de navegar.
        $enXaml = ($script:PanelesXaml.Keys | Sort-Object) -join ', '

        (($script:PanelesResueltos.Keys  | Sort-Object) -join ', ') | Should -Be $enXaml -Because 'Window.ps1 no resolveria el control y $c[...] seria $null'
        (($script:PanelesBucle.Keys      | Sort-Object) -join ', ') | Should -Be $enXaml -Because 'un panel fuera del bucle no se oculta nunca'
        (($script:PanelesNavegacion.Keys | Sort-Object) -join ', ') | Should -Be $enXaml -Because 'un panel sin entrada en la barra lateral es inalcanzable'
    }

    It 'el panel <Panel> es destino de foco pero no parada de tabulacion' -ForEach @(
        @{ Panel = 'PanelInicio' }, @{ Panel = 'PanelResultados' }, @{ Panel = 'PanelRegistro' }
        @{ Panel = 'PanelInformes' }, @{ Panel = 'PanelAjustes' }, @{ Panel = 'PanelAcerca' }
    ) {
        # Focus() sobre algo con Focusable="False" devuelve $false y no hace
        # nada: la llamada de mostrarPanel seguiria ahi, pareciendo que
        # funciona, y el lector de pantalla seguiria sin enterarse.
        $texto = $script:TextoPanel[$Panel]
        $texto | Should -Not -BeNullOrEmpty

        $declaracion = [regex]::Match($texto, ('(?s)<Grid x:Name="{0}".*?>' -f $Panel)).Value
        $declaracion | Should -Match 'Focusable="True"' -Because 'sin esto Focus() no hace nada y falla en silencio'
        $declaracion | Should -Match 'KeyboardNavigation.IsTabStop="False"' -Because 'si no, se anyade una parada de tabulacion por panel para quien ya ve la pantalla'
        $declaracion | Should -Match 'AutomationProperties.Name=' -Because 'sin nombre, el lector anuncia el foco como un contenedor sin mas'
    }

    It 'el nombre que anuncia el panel <Panel> es su titulo visible' -ForEach @(
        @{ Panel = 'PanelInicio' }, @{ Panel = 'PanelResultados' }, @{ Panel = 'PanelRegistro' }
        @{ Panel = 'PanelInformes' }, @{ Panel = 'PanelAjustes' }, @{ Panel = 'PanelAcerca' }
    ) {
        # Son dos copias del mismo rotulo a pocas lineas de distancia, y dos
        # copias acaban divergiendo: se cambia el titulo que se ve y el que
        # se oye se queda con el de antes. Quien no ve la pantalla oiria un
        # nombre que ya no existe en ningun sitio.
        $texto = $script:TextoPanel[$Panel]

        $accesible = [regex]::Match(
            [regex]::Match($texto, ('(?s)<Grid x:Name="{0}".*?>' -f $Panel)).Value,
            'AutomationProperties.Name="([^"]+)"').Groups[1].Value
        $visible = [regex]::Match($texto, 'Text="([^"]+)" Style="\{StaticResource Titulo\}"').Groups[1].Value

        $visible   | Should -Not -BeNullOrEmpty -Because 'si no, la prueba compara contra la nada'
        $accesible | Should -Be $visible
    }

    It 'el foco se pide DESPUES de poner la visibilidad' {
        # Al reves no falla: Focus() sobre un elemento Collapsed devuelve
        # $false, no lanza, y el panel se queda mostrado y mudo. Seria codigo
        # nuevo que parece arreglarlo y no arregla nada.
        $posVisibilidad = $script:BloqueMostrar.IndexOf('.Visibility =')
        $posFoco        = $script:BloqueMostrar.IndexOf('.Focus()')

        $posVisibilidad | Should -BeGreaterThan 0
        $posFoco        | Should -BeGreaterThan $posVisibilidad
    }

    It 'el resultado de Focus() no se cuela en la salida de la funcion' {
        # PowerShell devuelve TODO lo que no se consume. Un Focus() suelto
        # mete un booleano en la salida de mostrarPanel, y quien la llame
        # recogeria un $true o un $false que no ha pedido.
        $script:BloqueMostrar | Should -Match '\[void\]\s*\$c\[\$Cual\]\.Focus\(\)'
    }
}

Describe 'A11Y-04: los atajos no pueden separarse de lo que hacen los botones' {
    <#
        [A11Y-04]. No habia ni un atajo de teclado.

        Lo que se protege aqui no es que F5 analice -eso se prueba en
        Atajos.Tests.ps1, que recorre las combinaciones una a una-, sino las
        dos formas que tiene esto de pudrirse en silencio:

        1. El despachador copia lo que hace el boton en vez de pulsarlo.
           Entonces hay dos versiones de la misma accion, y el dia que se
           arregle una, la otra se queda con el fallo. Es [ARQ-01] con otra
           ropa: alli eran dos copias del bucle de borrado, aqui serian dos
           copias de cada manejador.

        2. Se reordena la barra lateral y Ctrl+3 deja de ser el tercero que
           se ve. No falla nada. El atajo sigue funcionando, sigue llevando a
           un panel, y esta mal.
    #>

    BeforeAll {
        $script:CarpetaAtajos = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src') 'UI'
        . (Join-Path $script:CarpetaAtajos 'Atajos.ps1')
        . (Join-Path $script:CarpetaAtajos 'Xaml.ps1')

        $script:MontadoAtajos = Expand-PanelesXaml -Carpeta $script:CarpetaAtajos `
                                    -Texto ([IO.File]::ReadAllText(
                                        (Join-Path $script:CarpetaAtajos 'MainWindow.xaml')))

        # El bloque del despachador, acotado para no arrastrar el resto del
        # archivo de eventos, que tiene manejadores de todo.
        $eventos = Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaAtajos 'Window.Eventos.ps1')
        $script:BloqueTeclado = [regex]::Match(
            $eventos, '(?s)\$ventana\.Add_PreviewKeyDown\(\{.*?\r?\n    \}\)').Value

        # Sin comentarios: si no, las pruebas de texto de abajo encuentran lo
        # que explican los propios comentarios. Ha pasado cinco veces en este
        # repositorio.
        $script:TecladoLimpio = [regex]::Replace($script:BloqueTeclado, '(?m)^\s*#.*$', '')
    }

    It 'la prueba lee el despachador de verdad: si no, no comprueba nada' {
        $script:BloqueTeclado.Length | Should -BeGreaterThan 400 -Because 'si no, se acoto mal el bloque de PreviewKeyDown'
        $script:TecladoLimpio | Should -Match 'Get-AtajoDeTecla'
        (Get-NavegacionPorNumero).Count | Should -Be 6
    }

    It 'Ctrl+1..6 sigue el orden en que se ven las entradas en la barra lateral' {
        # Un numero que no corresponde a la posicion no rompe nada: lleva a
        # un panel, sin error, y miente.
        $enPantalla = @([regex]::Matches($script:MontadoAtajos, 'RadioButton x:Name="(Nav[A-Za-z]+)"') |
                        ForEach-Object { $_.Groups[1].Value })

        $enPantalla.Count | Should -Be 6 -Because 'si no, la prueba no esta leyendo la barra lateral'
        ($enPantalla -join ', ') | Should -Be ((Get-NavegacionPorNumero) -join ', ')
    }

    It 'toda accion que devuelve la funcion la sabe atender el despachador' {
        # Una accion nueva sin rama cae en el "default", que trata lo que le
        # llegue como si fuera una entrada de la barra lateral: $c[$accion]
        # seria $null, y escribir una propiedad de $null si lanza. Un atajo
        # que revienta la ventana.
        $devueltas = @()
        foreach ($m in [regex]::Matches(
            (Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaAtajos 'Atajos.ps1')),
            "return '([A-Za-z]+)'")) {
            $devueltas += $m.Groups[1].Value
        }

        $devueltas.Count | Should -BeGreaterThan 2 -Because 'si no, la prueba mira otra cosa'

        $sinRama = @($devueltas | Where-Object {
            $_ -notmatch '^Nav' -and $script:TecladoLimpio -notmatch ("'{0}'" -f $_)
        })
        $sinRama | Should -BeNullOrEmpty -Because 'caeria en el default y se trataria como un panel inexistente'
    }

    It 'el despachador pulsa los botones, no repite lo que hacen' {
        # La regla entera de este punto. Si aqui apareciera un Remove, un
        # Where-Object sobre los items o un Show-Confirmacion, seria una
        # segunda version de una decision que ya vive en el manejador del
        # boton, y las dos versiones acabarian diciendo cosas distintas.
        $script:TecladoLimpio | Should -Match 'RaiseEvent'

        foreach ($prohibido in @(
            'Show-Confirmacion', 'Invoke-LoteEliminacion', 'Remove-Elemento',
            '\$estado\.Items', '\$estado\.Ocupado', 'Add-EntradaHistorial')) {
            $script:TecladoLimpio | Should -Not -Match $prohibido -Because (
                'esa decision ya vive en el manejador del boton: aqui seria una segunda copia')
        }
    }

    It 'la tecla se marca atendida DESPUES de saber que era un atajo' {
        # Al reves se come cada letra que el usuario escribe en el filtro, y
        # el cuadro de texto se queda mudo sin que falle nada.
        $posSalida  = $script:TecladoLimpio.IndexOf('if (-not $accion) { return }')
        $posAtendida = $script:TecladoLimpio.IndexOf('$e.Handled = $true')

        $posSalida   | Should -BeGreaterThan 0
        $posAtendida | Should -BeGreaterThan $posSalida
    }
}

Describe 'Nada que no sea codigo puede colarse en lo que se publica' {
    <#
        Encontrado al hacer el primer commit del repositorio, y por poco.

        Trabajando sobre una carpeta montada por FUSE, sobrescribir un
        archivo que otro proceso tiene abierto no lo borra: lo RENOMBRA a
        .fuse_hidden0000004300000004. Quedaron doce copias muertas de
        Atajos.ps1, Window.Eventos.ps1, Window.Ayudantes.ps1,
        Panel.Ajustes.xaml y Banco-Decisiones.ps1 dentro de src/ y tools/.
        Un cuarto de mega de codigo viejo.

        Y no las vio NADA. Pester solo lee *.Tests.ps1; el analizador y la
        prueba del BOM filtran *.ps1 y *.xaml; ninguna de las tres mira un
        archivo sin extension. Las 1206 pruebas estaban en verde con ellas
        dentro.

        Lo que lo convierte en un fallo de verdad y no en suciedad: el paso
        "Armar el paquete" de .github/workflows/publicar.yml hace
        Copy-Item -Recurse sobre src/ ENTERO. Se habrian publicado a los
        usuarios, dentro del .zip, versiones antiguas del codigo de la
        ventana. Nadie las ejecutaria -no las carga nadie-, pero un
        proyecto que presume de "puedes leer exactamente que hace antes de
        ejecutarlo" repartiendo copias fantasma de su propio codigo es lo
        contrario de lo que promete.

        La regla, entonces: en las carpetas que se publican solo hay
        extensiones conocidas. Todo lo demas sobra, sea lo que sea.
    #>

    BeforeAll {
        $script:RaizPublicable = Split-Path $PSScriptRoot -Parent

        # Lo que legitimamente vive en src/ y tools/. Es una lista corta a
        # proposito: ampliarla tiene que ser una decision, no un descuido.
        $script:ExtensionesPublicables = @('.ps1', '.psd1', '.psm1', '.xaml', '.bat', '.md')

        $script:CarpetasPublicables = @('src', 'tools', 'assets')

        $script:ArchivosPublicables = @()
        foreach ($carpeta in $script:CarpetasPublicables) {
            $ruta = Join-Path $script:RaizPublicable $carpeta
            if (-not (Test-Path -LiteralPath $ruta)) { continue }
            $script:ArchivosPublicables += @(Get-ChildItem -LiteralPath $ruta -Recurse -File -Force)
        }
    }

    It 'la prueba recorre las carpetas de verdad: si no, no comprueba nada' {
        # Sin esta guarda, un error en el recorrido deja la lista vacia y
        # las dos pruebas de abajo pasan celebrando que no hay nada mal.
        $script:ArchivosPublicables.Count | Should -BeGreaterThan 40
        @($script:ArchivosPublicables | Where-Object { $_.Extension -eq '.ps1' }).Count |
            Should -BeGreaterThan 20
    }

    It 'no hay ningun archivo oculto en lo que se publica' {
        # El caso exacto que se escapo. Ojo al detalle, porque la primera
        # version de esta prueba estaba mal escrita: buscaba archivos SIN
        # extension, y ".fuse_hidden0000004300000004" no es eso. Solo lleva
        # un punto, y va delante, asi que PowerShell le da BaseName vacio y
        # Extension ".fuse_hidden0000004300000004" entera. Los cazaba la
        # prueba de abajo, la de extensiones raras, no esta.
        #
        # Lo que de verdad los distingue es que el NOMBRE empieza por
        # punto: es la firma de los restos que dejan FUSE (.fuse_hidden*) y
        # NFS (.nfs*) cuando no pueden borrar un archivo abierto. En src/,
        # tools/ y assets/ no hay ningun motivo legitimo para un archivo
        # asi; los que si lo tienen -.gitignore, .editorconfig- viven en la
        # raiz, que no se recorre aqui.
        $ocultos = @($script:ArchivosPublicables |
            Where-Object { $_.Name.StartsWith('.') } |
            ForEach-Object { $_.FullName.Substring($script:RaizPublicable.Length + 1) })

        $ocultos | Should -BeNullOrEmpty -Because (
            'publicar.yml copia src/ entero al .zip, y esto se iria dentro sin que lo mire ninguna otra comprobacion')
    }

    It 'ninguna extension rara se cuela en lo que se publica' {
        $raros = @($script:ArchivosPublicables |
            Where-Object { $_.Extension -and $script:ExtensionesPublicables -notcontains $_.Extension.ToLowerInvariant() } |
            ForEach-Object { $_.FullName.Substring($script:RaizPublicable.Length + 1) })

        # assets/ lleva imagenes, y son legitimas: se nombran aparte en vez
        # de ensanchar la lista de arriba, para que anyadir un .dll o un
        # .exe a src/ siga siendo un fallo.
        $raros = @($raros | Where-Object { $_ -notmatch '^assets[\\/]' })

        $raros | Should -BeNullOrEmpty
    }
}

Describe 'Un flujo de trabajo invalido no llega ni a ejecutarse' {
    <#
        Encontrado en el primer push del repositorio, y es de la peor
        familia: la comprobacion rota.

        ci.yml tenia "shell: ${{ matrix.shell }}" en dos pasos. La clave
        "shell:" de un paso es de los POCOS sitios de un flujo donde el
        contexto "matrix" no esta disponible, asi que eso no da un shell
        equivocado: invalida el ARCHIVO ENTERO. GitHub no ejecuta nada y
        marca la ejecucion en rojo con "Invalid workflow file".

        Llevaba asi desde que se escribio. No se noto porque hasta hoy el
        proyecto no tenia repositorio, asi que no habia donde ejecutarlo: el
        unico archivo del proyecto que nadie habia verificado nunca era
        justamente el que existe para verificar todo lo demas.

        La regla, entonces: ninguna clave "shell:" lleva expresion. Cuando
        haga falta variar el shell por matriz, va en
        jobs.<id>.defaults.run.shell, que si admite el contexto.

        Esto NO sustituye a actionlint -que caza muchas mas cosas y con el
        que se arreglo esto-, pero actionlint no esta en el entorno de
        pruebas y esta regla concreta si se puede exigir aqui, que es donde
        se para antes de subir.
    #>

    BeforeAll {
        $script:CarpetaFlujos = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) '.github') 'workflows'

        $script:Flujos = @{}
        foreach ($archivo in (Get-ChildItem $script:CarpetaFlujos -Filter '*.yml' -ErrorAction SilentlyContinue)) {
            $script:Flujos[$archivo.Name] = Get-Content -Raw -LiteralPath $archivo.FullName
        }
    }

    It 'la prueba lee los flujos de verdad: si no, no comprueba nada' {
        $script:Flujos.Count | Should -BeGreaterThan 1
        @($script:Flujos.Values | Where-Object { $_ -match '(?m)^\s*runs-on:' }).Count |
            Should -BeGreaterThan 1
    }

    It 'ninguna clave shell de un PASO lleva una expresion' {
        # Se quitan primero los bloques defaults.run.shell, que son el sitio
        # donde la expresion SI vale. La primera version de esta prueba no
        # los quitaba y fallaba sobre el arreglo correcto: habria empujado a
        # deshacerlo para callarla, que es la peor forma de fallar que tiene
        # una prueba.
        $malos = @()
        foreach ($nombre in $script:Flujos.Keys) {
            $texto = [regex]::Replace($script:Flujos[$nombre],
                        '(?m)^\s*defaults:\s*\r?\n\s*run:\s*\r?\n\s*shell:.*$', '')

            foreach ($m in [regex]::Matches($texto, '(?m)^\s*shell:\s*(.+)$')) {
                if ($m.Groups[1].Value -match '\$\{\{') {
                    $malos += ('{0}: {1}' -f $nombre, $m.Groups[0].Value.Trim())
                }
            }
        }

        $malos | Should -BeNullOrEmpty -Because (
            'no da un shell equivocado: invalida el archivo entero y el flujo no llega a ejecutarse')
    }

    It 'el trabajo con matriz declara su shell donde SI se admite' {
        # La otra mitad de la regla. Sin esto, quitar la expresion del paso
        # y no ponerla en defaults deja el flujo valido y ejecutando las
        # pruebas de PowerShell 5.1 con pwsh: las dos ramas de la matriz
        # correrian lo mismo, en verde, sin comprobar 5.1 jamas.
        $ci = $script:Flujos['ci.yml']
        $ci | Should -Not -BeNullOrEmpty

        $ci | Should -Match '(?s)strategy:.*?matrix:.*?defaults:\s*\r?\n\s*run:\s*\r?\n\s*shell:\s*\$\{\{\s*matrix\.shell'
    }
}

Describe 'El historial no puede rechazar un tipo que el programa le manda' {
    <#
        Encontrado al integrar [CNF-06], y llevaba roto desde [CNF-04].

        El ValidateSet de Add-EntradaHistorial admitia 'analisis' y
        'limpieza'. La ventana lleva desde [CNF-04] llamando ademas con
        'limpieza-interrumpida'. El ValidateSet rechazaba la llamada, la
        excepcion caia en el catch de al lado -que solo hace Write-Verbose,
        y con razon: eso ocurre al cerrar la ventana, donde ya no hay a
        quien avisar- y NO SE ANOTABA NADA.

        O sea: la parte de [CNF-04] que promete "una limpieza detenida se
        anota como tal" no funcionaba por el camino de la ventana, que es el
        camino normal del programa. Y no lo veia nadie porque las dos
        listas -la que valida y la que llama- viven en archivos distintos y
        nada las comparaba.

        Es [COR-04] con otra pareja de listas, y la solucion es la misma:
        compararlas.
    #>

    BeforeAll {
        $script:RaizHist = Split-Path $PSScriptRoot -Parent
        $script:TextoHistorial = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Join-Path $script:RaizHist 'src') 'Core') 'Historial.ps1')

        # Lo que el ValidateSet admite.
        $m = [regex]::Match($script:TextoHistorial,
                "ValidateSet\(((?:\s*'[^']+'\s*,?)+)\)\]\s*\[string\]\s*\`$Tipo")
        $script:TiposAdmitidos = @()
        if ($m.Success) {
            foreach ($t in [regex]::Matches($m.Groups[1].Value, "'([^']+)'")) {
                $script:TiposAdmitidos += $t.Groups[1].Value
            }
        }

        # Lo que el programa manda de verdad, en TODO src. Sin comentarios:
        # un ejemplo escrito en una cabecera no es una llamada.
        $script:TiposUsados = @{}
        foreach ($archivo in (Get-ChildItem (Join-Path $script:RaizHist 'src') -Recurse -Filter '*.ps1')) {
            $texto = [regex]::Replace((Get-Content -Raw -LiteralPath $archivo.FullName), '(?m)^\s*#.*$', '')
            foreach ($u in [regex]::Matches($texto, "Add-EntradaHistorial\s+-Tipo\s+'([^']+)'")) {
                $script:TiposUsados[$u.Groups[1].Value] = $archivo.Name
            }
        }
    }

    It 'la prueba encuentra las dos listas: si no, no comprueba nada' {
        $script:TiposAdmitidos.Count | Should -BeGreaterThan 1 -Because 'si no, se leyo mal el ValidateSet'
        $script:TiposUsados.Count    | Should -BeGreaterThan 1 -Because 'si no, no se encontro ninguna llamada'
    }

    It 'todo tipo que el programa manda esta admitido' {
        $rechazados = @($script:TiposUsados.Keys |
            Where-Object { $script:TiposAdmitidos -notcontains $_ } |
            ForEach-Object { ('{0} (desde {1})' -f $_, $script:TiposUsados[$_]) })

        $rechazados | Should -BeNullOrEmpty -Because (
            'el ValidateSet lanza, el catch se lo traga y la entrada no se anota: el historial miente por omision')
    }
}

Describe 'El texto que lee el usuario concuerda en singular' {
    <#
        "hace 1 meses" y "hace mas de 1 anyos", en Format-Antiguedad.

        Es el mismo descuido que ya se corrigio en las cabeceras de grupo
        -"1 elementos", ver [USO-15]- y vuelve a aparecer donde nadie
        miraba: solo se ve durante un mes de cada anyo. Encontrado al
        integrar [CNF-06], que reutiliza esa funcion.

        No es una invariante general sobre plurales -eso seria un mecanismo
        que aqui no se puede verificar-: son los casos concretos, escritos.
    #>

    BeforeAll {
        $script:RaizPlural = Split-Path $PSScriptRoot -Parent
        . (Join-Path (Join-Path (Join-Path $script:RaizPlural 'src') 'Core') 'Bootstrap.ps1')
    }

    It 'un solo mes se dice en singular' {
        $texto = Format-Antiguedad -Fecha ((Get-Date).AddDays(-40))
        $texto | Should -Not -Match '\b1 meses\b'
        $texto | Should -Be 'hace un mes'
    }

    It 'y varios, en plural' {
        Format-Antiguedad -Fecha ((Get-Date).AddDays(-100)) | Should -Be 'hace 3 meses'
    }

    It 'un solo anyo se dice en singular' {
        # Este ya estaba bien de antes. La prueba se queda igual: es la que
        # destapo que, al arreglar el de los meses, se habia colado una
        # segunda rama identica -inalcanzable- justo encima.
        $texto = Format-Antiguedad -Fecha ((Get-Date).AddDays(-400))
        $texto | Should -Not -Match '\b1 años\b'
        $texto | Should -Be 'hace más de 1 año'
    }

    It 'los casos cortos siguen como estaban' {
        Format-Antiguedad -Fecha (Get-Date)                    | Should -Be 'hoy'
        Format-Antiguedad -Fecha ((Get-Date).AddDays(-1))      | Should -Be 'ayer'
        Format-Antiguedad -Fecha ((Get-Date).AddDays(-5))      | Should -Be 'hace 5 días'
    }

    It 'ningun tramo devuelve un numero pegado a un plural equivocado' {
        # Recorrido por todos los tramos, que es lo que habria cazado el
        # fallo sin tener que sospecharlo: ninguna respuesta puede empezar
        # por "1 " y seguir con una palabra en plural.
        foreach ($dias in @(0, 1, 2, 15, 29, 30, 45, 59, 60, 200, 364, 365, 400, 800)) {
            $texto = Format-Antiguedad -Fecha ((Get-Date).AddDays(-$dias))
            $texto | Should -Not -Match '\b1 (días|meses|años)\b' -Because "con $dias dias dice '$texto'"
        }
    }
}

Describe 'COR-08: el programa no puede volver a recorrer con Get-ChildItem -Recurse' {

    <#
        Es la invariante del punto. [COR-02] arreglo medir y borrar una ruta
        de mas de 260 caracteres; lo que no arreglo fue ENCONTRARLA, porque
        los modulos recorrian con

            Get-ChildItem -LiteralPath $zona -Recurse -File -Force -ErrorAction SilentlyContinue

        y en Windows PowerShell 5.1 eso se para en MAX_PATH y bajo ese
        SilentlyContinue no dice nada de nada. El sintoma no es un error:
        es que un candidato no aparece. Y en la otra direccion -el
        vocabulario de Registry.ps1, la busqueda de enlaces de Remove.ps1-
        el sintoma es peor todavia: se propone DE MAS.

        Por eso la regla se escribe aqui y NO SE DEJA NINGUNA EXCEPCION. Una
        invariante con excepciones sin motivo escrito es un colador, y el
        noveno modulo -el que todavia no existe- es exactamente para quien
        esta escrita: quien lo escriba copiara la linea del modulo de al
        lado, y la del modulo de al lado ya no puede ser la mala.

        ALCANCE: todo src/ mas Cachivache.ps1, o sea el programa que se
        entrega. Las pruebas quedan fuera a proposito -se ejecutan en el
        repositorio, sobre rutas cortas, y no proponen borrar nada-, y
        tools/Banco-Pruebas.ps1 ya tiene la suya en Banco.Tests.ps1 desde
        que -Quitar no podia desmontar el cebo de ruta larga.
    #>

    BeforeAll {
        $script:RaizRec = Split-Path $PSScriptRoot -Parent
        $script:FuentesRec = @(Get-ChildItem -Path (Join-Path $script:RaizRec 'src') -Filter '*.ps1' -Recurse) +
                             @(Get-ChildItem -Path $script:RaizRec -Filter 'Cachivache.ps1')
    }

    It 'la prueba encuentra los archivos: si no, no comprueba nada' {
        @($script:FuentesRec).Count | Should -BeGreaterThan 20
    }

    It 'ningun archivo del programa recorre con Get-ChildItem -Recurse' {
        $culpables = @()
        foreach ($archivo in $script:FuentesRec) {
            # Sin los comentarios: media docena de ellos explican justamente
            # por que ya NO se usa Get-ChildItem -Recurse, y contarlos haria
            # fallar la prueba por documentar bien el motivo. Ha pasado seis
            # veces en este proyecto, y aqui pasaria en tres archivos a la
            # vez.
            #
            # Los bloques <# ... #> se sustituyen por sus mismos saltos de
            # linea en vez de borrarse: asi el numero de linea del culpable
            # sigue siendo el de verdad, que es lo unico que sirve para ir a
            # arreglarlo.
            $texto = Get-Content -Raw -LiteralPath $archivo.FullName
            $sinBloques = [regex]::Replace($texto, '(?s)<#.*?#>', {
                param($coincidencia)
                return ("`n" * @([regex]::Matches($coincidencia.Value, "`n")).Count)
            })

            $n = 0
            foreach ($linea in ($sinBloques -split "`n")) {
                $n++
                if ($linea -match '^\s*#') { continue }
                if ($linea -match 'Get-ChildItem[^\r\n]*-Recurse') {
                    $culpables += ('{0}:{1}' -f $archivo.Name, $n)
                }
            }
        }
        $culpables | Should -BeNullOrEmpty -Because (
            'hay que usar Get-ElementosDelArbol: Get-ChildItem -Recurse se para a los 260 caracteres y no lo dice')
    }

    It 'los ocho modulos que se migraron llaman al recorrido compartido' -ForEach @(
        @{ Modulo = '20-Proyectos.ps1' }
        @{ Modulo = '25-Papelera.ps1' }
        @{ Modulo = '35-Descargas.ps1' }
        @{ Modulo = '45-AccesosRotos.ps1' }
        @{ Modulo = '50-Temporales.ps1' }
        @{ Modulo = '55-Duplicados.ps1' }
        @{ Modulo = '60-ArchivosGrandes.ps1' }
        @{ Modulo = '85-DockerWsl.ps1' }
    ) {
        # La otra mitad de la invariante. Sin esto, borrar el recorrido de
        # un modulo entero tambien pasaria la prueba de arriba: no habria
        # Get-ChildItem -Recurse porque no habria recorrido, y el modulo
        # dejaria de encontrar nada sin un solo error.
        $ruta = Join-Path (Join-Path (Join-Path $script:RaizRec 'src') 'Modules') $Modulo
        $codigo = @(Get-Content -LiteralPath $ruta | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $codigo | Should -Match 'Get-ElementosDelArbol'
    }

    It 'el recorrido compartido pone el prefijo de ruta larga' {
        # Lo que no se puede comprobar ejecutando: el limite de 260 es de
        # Windows y aqui las rutas largas funcionan solas, asi que quitar el
        # prefijo no haria fallar ni una prueba de comportamiento. Se fija
        # por texto, que es lo unico que queda, y lo comprueba de verdad la
        # CI del banco sobre un archivo a 546 caracteres de un Windows real.
        $texto = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Join-Path $script:RaizRec 'src') 'Core') 'FileSystem.ps1')
        $desde = $texto.IndexOf('function Get-ElementosDelArbol')
        $hasta = $texto.IndexOf('function Measure-Ruta')
        $desde | Should -BeGreaterThan 0
        $hasta | Should -BeGreaterThan $desde

        $cuerpo = @((($texto.Substring($desde, $hasta - $desde)) -split "`n") |
                    Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $cuerpo | Should -Match '\$rutaApi\s*=\s*ConvertTo-RutaLarga -Ruta \$raizLimpia'
        $cuerpo | Should -Match '\[IO\.DirectoryInfo\]::new\(\$rutaApi\)'
    }

    It 'y la ruta que devuelve se compone con la limpia, no se lee de FullName' {
        # La regla que no se puede romper. Un FileInfo nacido de una
        # enumeracion con prefijo lo lleva METIDO en su FullName, y esa
        # ruta acaba en el campo Ruta de un candidato: la guardia
        # compararia "\\?\C:\Windows" contra su lista negra "C:\Windows" y
        # no coincidiria. Un prefijo puesto para encontrar mejor seria un
        # agujero para borrar el sistema.
        $texto = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Join-Path $script:RaizRec 'src') 'Core') 'FileSystem.ps1')
        $desde = $texto.IndexOf('function Get-ElementosDelArbol')
        $hasta = $texto.IndexOf('function Measure-Ruta')
        $cuerpo = @((($texto.Substring($desde, $hasta - $desde)) -split "`n") |
                    Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        $cuerpo | Should -Match 'FullName\s*=\s*\$base \+ \$separador \+ \$nombre'
        $cuerpo | Should -Match '\$rutaSub\s*=\s*\$base \+ \$separador \+ \$sub\.Name'
        $cuerpo | Should -Not -Match 'FullName\s*=\s*\$archivo\.FullName'
        $cuerpo | Should -Not -Match 'FullName\s*=\s*\$sub\.FullName'
    }
}
