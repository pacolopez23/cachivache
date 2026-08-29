<#
    El contrato del candidato y la fila que ve el usuario ([COR-05]).

    Candidate.ps1 declara veinte campos; ItemVista, la clase de C# que WPF
    enlaza a cada fila, expone otros tantos; y la correspondencia entre las
    dos se copia A MANO, campo a campo, en Window.Analisis.ps1.

    Invariantes.Tests.ps1 ya vigila la INTERSECCION: lo que existe en los
    dos lados tiene que copiarse de verdad. Lo que nadie vigilaba es el
    escalon anterior, que es justo donde esta el fallo silencioso de
    [COR-05]: un campo NUEVO en el contrato que no tenga contraparte en
    ItemVista no aparece en esa interseccion, asi que ninguna prueba lo
    echa de menos. Nace invisible en la interfaz y nada falla.

    De ahi la forma de este archivo: en vez de comparar las dos listas y
    quedarse con lo comun, obliga a que CADA campo del contrato este en uno
    de dos sitios -en ItemVista, o en una lista de exclusiones con su
    motivo escrito-. Anyadir un campo y no decidir nada deja de ser una
    opcion.

    COMO SE LEE CADA LISTA, Y POR QUE ASI

      * El contrato, por AST: se busca la funcion New-Candidato y la tabla
        que devuelve. Un comentario que mencione un campo no cuenta.
      * El mapeo, por AST: asignaciones "$item.X = ..." en cualquiera de
        los src/UI/Window*.ps1. Se miran todos y no solo el archivo donde
        vive hoy el bucle, para que mover ese bucle de sitio no apague la
        prueba en silencio.
      * ItemVista, POR REFLEXION sobre el tipo ya compilado. Y aqui hay que
        ser explicito: ItemVista es codigo de C# dentro de una cadena de
        Types.ps1, asi que el AST de PowerShell la ve como UN literal de
        texto y no sabe nada de sus propiedades. Compilar la cadena y
        preguntarle al tipo resultante es mas fuerte que cualquier regex,
        porque responde el compilador. El precio es que la respuesta ya no
        viene del archivo, sino de la memoria; por eso hay ademas una
        prueba que extrae las propiedades del TEXTO de Types.ps1 y exige
        que coincidan con las del tipo compilado. Esa es la costura que
        ata la reflexion al archivo.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    $script:CarpetaUI = Join-Path (Join-Path $script:Raiz 'src') 'UI'

    . (Join-Path $script:CarpetaUI 'Types.ps1')
    Initialize-TiposInterfaz

    # --- El contrato, por AST -----------------------------------------
    $rutaCandidato = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Candidate.ps1'
    $astCandidato = [System.Management.Automation.Language.Parser]::ParseFile($rutaCandidato, [ref]$null, [ref]$null)
    $nueva = $astCandidato.FindAll({
        param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-Candidato'
    }, $true)[0]
    # La primera tabla que aparece dentro de la funcion es la que se
    # devuelve: es el objeto candidato entero.
    $tabla = $nueva.FindAll({
        param($n) $n -is [System.Management.Automation.Language.HashtableAst]
    }, $true)[0]
    $script:CamposCandidato = @($tabla.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text.Trim("'`"") })

    # --- ItemVista, por reflexion --------------------------------------
    $script:PropsVista = @([Cachivache.ItemVista].GetProperties() | ForEach-Object { $_.Name })
    # Las que tienen "set": las unicas que alguien puede rellenar desde
    # fuera. Las demas las calcula la propia clase a partir de estas.
    $script:PropsRellenables = @([Cachivache.ItemVista].GetProperties() |
                                 Where-Object { $_.CanWrite } | ForEach-Object { $_.Name })

    # --- ItemVista, tambien desde el TEXTO de Types.ps1 ----------------
    # Solo para atar la reflexion al archivo. Se acota al cuerpo de la
    # clase -de "class ItemVista" a la siguiente "public class"- para no
    # contar las propiedades de ModuloVista, DiscoVista y compania.
    $textoTipos = [IO.File]::ReadAllText((Join-Path $script:CarpetaUI 'Types.ps1'))
    $inicio = $textoTipos.IndexOf('public class ItemVista', [StringComparison]::Ordinal)
    $siguiente = if ($inicio -ge 0) {
        $textoTipos.IndexOf('public class ', $inicio + 20, [StringComparison]::Ordinal)
    } else { -1 }
    $script:CuerpoItemVista = if ($inicio -lt 0) { '' }
                              elseif ($siguiente -lt 0) { $textoTipos.Substring($inicio) }
                              else { $textoTipos.Substring($inicio, $siguiente - $inicio) }

    # Una propiedad de C# es "public <tipo> <Nombre> {"; un metodo lleva
    # parentesis antes de la llave y un campo privado no es public, asi
    # que ninguno de los dos entra por aqui.
    $script:PropsEnTexto = @([regex]::Matches(
        $script:CuerpoItemVista,
        'public\s+(?:abstract\s+|virtual\s+|override\s+|static\s+)?[A-Za-z_][\w<>\[\]\.]*\s+([A-Za-z_]\w*)\s*\{'
    ) | ForEach-Object { $_.Groups[1].Value })

    # --- El mapeo, por AST ---------------------------------------------
    # "$item.X = ..." en cualquier Window*.ps1. Se guarda tambien el
    # archivo, que es lo que hace util el mensaje cuando falla.
    $script:Mapeadas = @{}
    foreach ($archivo in (Get-ChildItem $script:CarpetaUI -Filter 'Window*.ps1')) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($archivo.FullName, [ref]$null, [ref]$null)
        foreach ($n in $ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                      $n.Left -is [System.Management.Automation.Language.MemberExpressionAst]
        }, $true)) {
            if ($n.Left.Expression.Extent.Text -eq '$item') {
                $script:Mapeadas[$n.Left.Member.Extent.Text] = $archivo.Name
            }
        }
    }

    # --- Lo que la fila lee del candidato SIN copiarlo ------------------
    # Window.Eliminacion.ps1 no copia el error del candidato a un campo
    # propio: lo lee de $item.Origen. Esa es una forma legitima de llegar a
    # la interfaz, y la prueba de las exclusiones la comprueba en vez de
    # fiarse del comentario.
    $script:LeidasDeOrigen = @{}
    foreach ($archivo in (Get-ChildItem $script:CarpetaUI -Filter '*.ps1')) {
        # Sin comentarios: en este repositorio los comentarios nombran
        # campos constantemente y harian pasar la prueba solos.
        $codigo = ((Get-Content $archivo.FullName) | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        foreach ($m in [regex]::Matches($codigo, '\.Origen\.([A-Za-z_]\w*)')) {
            $script:LeidasDeOrigen[$m.Groups[1].Value] = $archivo.Name
        }
    }
}

Describe 'Ningun campo del contrato puede nacer invisible en la interfaz (COR-05)' {

    BeforeAll {
        <#
            LOS CAMPOS QUE NO VAN A LA FILA, Y POR QUE.

            Esta lista no es una forma de callar la prueba: es la otra
            mitad de la invariante. Cada entrada dice por que ese campo no
            se ensenya, y hay una prueba mas abajo que exige que todas
            sigan existiendo en el contrato, para que la lista no se
            convierta en un colador que tape campos futuros por casualidad
            de nombre.
        #>
        $script:NoVanALaFila = [ordered]@{

            # Quien lo propone. La tabla agrupa por Categoria, no por
            # modulo, y el nombre del modulo ya se escribe en el panel de
            # Registro una vez por modulo -no una vez por fila-. Ponerlo
            # ademas en cada fila seria repetir la misma informacion en el
            # sitio donde menos cabe.
            ModuloId = 'lo dice el registro una vez por modulo; la tabla agrupa por categoria'

            # Pareja tecnica del metodo Comando. Ejecutable es el binario
            # SIN ruta ('dism') que Remove.ps1 resuelve contra su lista
            # blanca, y Argumentos es el array que se pasa a Start-Process
            # sin pasar por ningun shell. Lo que SECURITY.md exige
            # ensenyar es el comando LEGIBLE, y eso es el campo Comando,
            # que si se copia a la fila y ademas tiene su propia
            # visibilidad (VisibilidadComando). Ensenyar el array crudo
            # junto al texto legible seria una segunda version de lo mismo
            # que podria contradecirla.
            Ejecutable = 'detalle interno del metodo Comando; el usuario ve el campo Comando'
            Argumentos = 'detalle interno del metodo Comando; el usuario ve el campo Comando'

            # Lista blanca de carpetas de las que debe colgar la ruta. Es
            # un dato de la guardia de seguridad, no del elemento: le dice
            # a Test-RutaSegura donde se le permite estar a esa ruta. Al
            # usuario le importa la ruta, que si se ensenya.
            Raices = 'parametro de la guardia de rutas, no informacion del elemento'

            # Bandera que solo levanta el modulo de duplicados para que
            # Test-RutaSegura no vete una extension personal, porque
            # garantiza que existe otra copia identica. Es una excepcion
            # del motor, invisible por diseno: si se ensenyara, la fila
            # estaria explicando el funcionamiento de la guardia en vez de
            # que es el archivo.
            PermitirPersonales = 'excepcion interna de la guardia, solo la usa el modulo de duplicados'

            # Decision del motor de borrado: las caches genuinas se borran
            # sin pasar por la papelera aunque el usuario prefiera la
            # papelera, porque mandar cientos de miles de archivos alli es
            # lentisimo y no libera espacio. La fila no promete papelera ni
            # borrado permanente en ninguna columna, asi que no hay nada
            # que contradecir. Ver Remove.ps1 (Invoke-EliminacionCandidato).
            ForzarPermanente = 'decision del motor de borrado; la fila no habla de papelera en ninguna columna'

            # Resultado del borrado, no de la propuesta: vale 0 hasta que
            # se borra. Lo que la fila cuenta despues es Estado
            # ('Eliminado'), y el total liberado va al pie y al informe,
            # que es donde una suma significa algo. Una columna por fila
            # con "0 B" durante todo el analisis solo confundiria.
            BytesLiberados = 'se rellena al borrar; la fila cuenta el resultado en Estado y el total va al pie'

            # Este SI llega a la fila, pero no copiado: Window.Eliminacion
            # lo lee de $item.Origen.Error y lo vuelca en Estado, que
            # ademas decide el color a traves de EstadoEsFallo. Copiarlo a
            # un campo propio crearia dos sitios donde vive el mismo error,
            # que es exactamente el fallo que este archivo persigue.
            # La prueba 'los campos que llegan por Origen se leen de
            # verdad' comprueba que esto es cierto y no solo un comentario.
            Error = 'llega por $item.Origen y se vuelca en Estado; copiarlo seria una segunda copia del mismo dato'
        }

        # Subconjunto de la lista anterior cuyo motivo es "llega por
        # Origen". Se comprueba de verdad; ver la prueba correspondiente.
        $script:PorOrigen = @('Error')
    }

    It 'la prueba encuentra las tres listas: si no, no esta comprobando nada' {
        # Sin esta guarda, un cambio de formato que dejara cualquiera de
        # las listas vacia haria pasar todo lo de abajo celebrando que no
        # hay ningun campo sin mapear.
        $script:CamposCandidato.Count   | Should -BeGreaterThan 15 -Because 'el contrato tiene una veintena de campos'
        $script:PropsVista.Count        | Should -BeGreaterThan 15 -Because 'ItemVista expone una veintena de propiedades'
        $script:PropsRellenables.Count  | Should -BeGreaterThan 10 -Because 'la mayoria de ItemVista se rellena desde fuera'
        $script:Mapeadas.Count          | Should -BeGreaterThan 10 -Because 'el bucle que construye las filas copia campo a campo'
        $script:CamposCandidato         | Should -Contain 'Ruta'
        $script:PropsVista              | Should -Contain 'Ruta'
    }

    It 'todo campo del contrato o esta en ItemVista o esta excluido con su motivo' {
        # ESTA es la prueba de [COR-05]. La invariante que ya existia
        # compara lo que hay en los dos lados; un campo nuevo que no este
        # en ItemVista no aparece en esa comparacion y se cuela entero.
        $sinSalida = @($script:CamposCandidato |
                       Where-Object { $_ -notin $script:PropsVista -and -not $script:NoVanALaFila.Contains($_) })

        $sinSalida | Should -BeNullOrEmpty -Because (
            'un campo del contrato que no exista en ItemVista no se puede ensenyar de ninguna forma: ' +
            'nace invisible y nada falla. O se anyade la propiedad a ItemVista y se copia en el bucle ' +
            'que construye las filas, o se anyade a $script:NoVanALaFila DICIENDO POR QUE no se ve')
    }

    It 'la lista de exclusiones no nombra campos que ya no existen' {
        # Una exclusion que sobrevive al campo que excluia es una trampa
        # esperando: el dia que alguien anyada un campo con ese mismo
        # nombre, la prueba de arriba lo dara por decidido sin que nadie
        # lo haya decidido.
        $fantasmas = @($script:NoVanALaFila.Keys | Where-Object { $_ -notin $script:CamposCandidato })
        $fantasmas | Should -BeNullOrEmpty -Because 'una exclusion sin campo detras tapa por casualidad al siguiente que se llame igual'
    }

    It 'ninguna exclusion se queda sin motivo escrito' {
        $mudas = @($script:NoVanALaFila.Keys |
                   Where-Object { [string]::IsNullOrWhiteSpace($script:NoVanALaFila[$_]) })
        $mudas | Should -BeNullOrEmpty -Because 'una lista de excepciones sin motivo es una forma de desactivar la prueba'
    }

    It 'los campos excluidos por llegar en Origen se leen de verdad desde Origen' {
        # El motivo "llega por $item.Origen" es el unico de la lista que
        # afirma algo comprobable sobre el codigo. Se comprueba, para que
        # no pueda quedarse en un comentario que dejo de ser verdad.
        $nadie = @($script:PorOrigen | Where-Object { -not $script:LeidasDeOrigen.ContainsKey($_) })
        $nadie | Should -BeNullOrEmpty -Because (
            'si nadie lee $item.Origen.<campo>, ese campo no llega a la interfaz por ninguna via ' +
            'y su exclusion es falsa')
    }

    It 'toda propiedad rellenable de ItemVista la rellena alguien' {
        # El otro sentido del mismo fallo: una propiedad que la clase
        # declara y que nadie escribe sale siempre vacia en la fila. La
        # invariante de Invariantes.Tests.ps1 no la ve, porque alli las
        # propiedades que no son campos del candidato -Tamano,
        # ColorRiesgo, Borrable, Origen, MotivoMarcado- estan en su lista
        # de excepciones y quedan fuera de la comparacion.
        $vacias = @($script:PropsRellenables | Where-Object { -not $script:Mapeadas.ContainsKey($_) })
        $vacias | Should -BeNullOrEmpty -Because (
            'una propiedad de ItemVista que nadie asigna se ensenya vacia en todas las filas sin que nada falle')
    }

    It 'no se asigna al item ninguna propiedad que ItemVista no declare' {
        # Asignar una propiedad inexistente sobre un objeto de .NET lanza
        # en tiempo de ejecucion, y ese momento es dentro del bucle que
        # llena la tabla: el analisis entero se cae.
        $inventadas = @($script:Mapeadas.Keys | Where-Object { $_ -notin $script:PropsVista })
        $inventadas | Should -BeNullOrEmpty -Because 'asignar una propiedad que no existe revienta al construir la fila'
    }
}

Describe 'ItemVista: lo compilado es lo que pone en Types.ps1' {

    <#
        La costura de la que habla la cabecera. Todo lo de arriba pregunta
        por reflexion a un tipo YA COMPILADO, y un tipo compilado sigue en
        memoria aunque el archivo cambie: Initialize-TiposInterfaz se
        planta y no hace nada si el tipo ya existe. Estas dos pruebas
        vuelven a leer Types.ps1 del disco y exigen que diga lo mismo, para
        que la reflexion no pueda estar contestando por un ItemVista que ya
        no es el del repositorio.
    #>

    It 'la prueba encuentra la clase en el texto: si no, no comprueba nada' {
        $script:CuerpoItemVista | Should -Not -BeNullOrEmpty
        $script:PropsEnTexto.Count | Should -BeGreaterThan 15 -Because 'la clase declara una veintena de propiedades'
    }

    It 'las propiedades del texto y las del tipo compilado son las mismas' {
        $soloEnTexto  = @($script:PropsEnTexto | Where-Object { $_ -notin $script:PropsVista })
        $soloEnTipo   = @($script:PropsVista   | Where-Object { $_ -notin $script:PropsEnTexto })

        $soloEnTexto | Should -BeNullOrEmpty -Because 'lo que declara Types.ps1 tiene que existir en el tipo compilado'
        $soloEnTipo  | Should -BeNullOrEmpty -Because 'la reflexion estaria contestando por una version distinta del archivo'
    }
}

Describe 'Ninguna propiedad de ItemVista se queda sin quien la use' {

    <#
        La ultima pata del recorrido candidato -> ItemVista -> fila. Que
        una propiedad se rellene no significa que se vea: si nadie la
        enlaza en el XAML ni la consulta el codigo, el dato viaja hasta la
        fila y se queda ahi.

        No comprueba que se VEA -eso exige WPF, y aqui no hay WPF-, solo
        que exista alguien que la consuma. Hay tres consumidores validos, y
        los tres tienen que ser LECTURAS: rellenar una propiedad no es
        usarla, asi que la asignacion del bucle no cuenta.

          1. Un enlace del XAML montado. No vale que el nombre aparezca
             suelto en el documento -un texto visible puede decir "Estado"
             sin enlazar nada-: se extraen las expresiones {Binding ...} y
             los SortMemberPath, que es lo unico que consume un dato.
          2. Una lectura desde el codigo de src/UI.
          3. Otra propiedad de la propia clase, como TextoCompleto, que
             junta cinco textos y es lo unico que lee MotivoMarcado.

        Es una red floja a proposito, y conviene saber por donde cede: la
        lectura en codigo no distingue $item.Metodo de $candidato.Metodo,
        asi que un nombre compartido con el contrato puede darse por
        consumido sin serlo. Lo que si cae aqui es lo que importa: una
        propiedad nueva, con nombre propio, que se anyade y no se enlaza en
        ninguna parte.
    #>

    BeforeAll {
        . (Join-Path $script:CarpetaUI 'Xaml.ps1')
        # El documento MONTADO: el armazon solo, sin los Panel.*.xaml, no
        # contiene la tabla de resultados y esta prueba estaria mirando una
        # ventana que no incluye ni una sola fila.
        $script:XamlMontado = Expand-PanelesXaml -Carpeta $script:CarpetaUI `
            -Texto ([IO.File]::ReadAllText((Join-Path $script:CarpetaUI 'MainWindow.xaml')))
        # Sin los comentarios del XAML. Se quitan porque ya han mordido
        # aqui: OrdenRiesgo solo se enlaza en un SortMemberPath, y el
        # comentario de encima que lo explica bastaba para dar la prueba
        # por buena mirando la explicacion en vez del enlace.
        $sinComentarios = [regex]::Replace($script:XamlMontado, '(?s)<!--.*?-->', '')

        $script:Enlazadas = @{}
        foreach ($m in [regex]::Matches($sinComentarios, '\{Binding([^}]*)\}')) {
            # La expresion entera partida en palabras: asi entran igual
            # "{Binding Ruta}", "{Binding Path=Ruta}" y las que llevan
            # ademas Converter, Mode o StringFormat.
            foreach ($palabra in ($m.Groups[1].Value -split '[^A-Za-z0-9_]')) {
                if ($palabra) { $script:Enlazadas[$palabra] = $true }
            }
        }
        foreach ($m in [regex]::Matches($sinComentarios, 'SortMemberPath="([^"]+)"')) {
            $script:Enlazadas[$m.Groups[1].Value] = $true
        }

        $script:CodigoUI = ''
        foreach ($archivo in (Get-ChildItem $script:CarpetaUI -Filter '*.ps1')) {
            $script:CodigoUI += ((((Get-Content $archivo.FullName) |
                                   Where-Object { $_ -notmatch '^\s*#' }) -join "`n") + "`n")
        }
    }

    It 'la prueba encuentra enlaces y codigo: si no, no comprueba nada' {
        $script:Enlazadas.Count | Should -BeGreaterThan 20 -Because 'la ventana montada esta llena de enlaces de datos'
        $script:Enlazadas.ContainsKey('Seleccionado') | Should -BeTrue -Because 'la casilla de cada fila se enlaza a ella'
        $script:CodigoUI.Length | Should -BeGreaterThan 10000 -Because 'src/UI son varios miles de lineas'
    }

    It 'cada propiedad de ItemVista tiene quien la consuma' {
        $huerfanas = @($script:PropsVista | Where-Object {
            $nombre = [regex]::Escape($_)
            # (?!\s*=[^=]) descarta la asignacion y deja pasar la lectura,
            # incluida "-eq"; sin eso, rellenar una propiedad contaria como
            # usarla y la prueba no diria nada.
            $leidaEnCodigo = $script:CodigoUI -match ('\.' + $nombre + '\b(?!\s*=[^=])')
            # Mas de una aparicion en la clase = alguien mas que su propia
            # declaracion la nombra.
            $usadaEnLaClase = ([regex]::Matches($script:CuerpoItemVista, '\b' + $nombre + '\b')).Count -gt 1
            -not ($script:Enlazadas.ContainsKey($_) -or $leidaEnCodigo -or $usadaEnLaClase)
        })
        $huerfanas | Should -BeNullOrEmpty -Because (
            'una propiedad que nadie enlaza ni lee llega a la fila y no la ve nadie: ' +
            'el dato viaja entero y muere en la tabla')
    }
}
