<#
.SYNOPSIS
    Ventana principal: carga del XAML, enlace de datos y orquestacion.

.DESCRIPTION
    El análisis y la eliminación se ejecutan en runspaces aparte para que la
    ventana no se congele. La comunicación es una tabla hash sincronizada
    que un DispatcherTimer consulta cinco veces por segundo (cada 200 ms);
    así todo lo que toca controles ocurre siempre en el hilo de la interfaz.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# Montaje del XAML por trozos. En su propio archivo para que las pruebas
# puedan cargarlo sin arrastrar los ensamblados de WPF de aquí arriba.
. (Join-Path $PSScriptRoot 'Xaml.ps1')

# Interoperabilidad con Win32 para que el maximizado respete la barra de
# tareas. Aparte porque no tiene que ver con la lógica de la ventana.
. (Join-Path $PSScriptRoot 'Maximizar.ps1')

# Que hace cada tecla. Aparte, y sin un solo tipo de WPF dentro, para que
# las pruebas puedan recorrer las combinaciones sin interfaz grafica.
. (Join-Path $PSScriptRoot 'Atajos.ps1')

# Que posicion y que seleccion se recuperan al reenganchar la tabla. Otra
# vez aparte y otra vez sin WPF dentro, por el mismo motivo. Ver [USO-10].
. (Join-Path $PSScriptRoot 'Posicion.ps1')

# =====================================================================
#  CARGA DE XAML
# =====================================================================
function Import-Xaml {
    <#
    .SYNOPSIS
        Carga un archivo XAML y devuelve el objeto que describe.
    .DESCRIPTION
        Se usa ReadAllText en vez de Get-Content para que la marca de orden
        de bytes no llegue al analizador, que la rechazaria.

        Si el documento trae marcas de panel, se resuelven antes de
        interpretar. Ver Expand-PanelesXaml.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Ruta)

    if (-not (Test-Path -LiteralPath $Ruta)) {
        throw "No se encuentra el archivo de interfaz: $Ruta"
    }
    $texto = [IO.File]::ReadAllText($Ruta)
    if ($texto -match '<!--#panel') {
        $texto = Expand-PanelesXaml -Texto $texto -Carpeta (Split-Path $Ruta -Parent)
    }
    try {
        return [Windows.Markup.XamlReader]::Parse($texto)
    } catch {
        throw "Error al interpretar $([IO.Path]::GetFileName($Ruta)): $($_.Exception.Message)"
    }
}

function Get-CarpetaInterfaz {
    [OutputType([string])]
    param()
    return $PSScriptRoot
}

# =====================================================================
#  COLORES DE ETIQUETA
# =====================================================================
function Get-GeometriaTema {
    <#
    .SYNOPSIS
        Icono del boton de tema: luna para el oscuro, sol para el claro.
    .DESCRIPTION
        El Path del XAML se dibuja con Fill y sin Stroke, así que la
        geometria tiene que estar hecha SOLO de figuras cerradas. El sol
        anterior dibujaba sus rayos como segmentos de línea sueltos
        ("M12,1 L12,4"), que no encierran area: al rellenar no se veia
        ninguno y el boton quedaba en un circulito suelto. Aquí los rayos
        son rectangulos cerrados, que si se rellenan.

        Las dos geometrias viven en esta única función porque antes estaban
        duplicadas en el arranque y en el cambio de tema, con el riesgo de
        corregir una y olvidar la otra.
    #>
    [CmdletBinding()]
    [OutputType([Windows.Media.Geometry])]
    param(
        [ValidateSet('claro', 'oscuro')]
        [string] $Tema
    )

    # Lienzo de 24x24 en ambos casos, para que Stretch="Uniform" los deje
    # del mismo tamaño optico.
    $trazado = if ($Tema -eq 'claro') {
        # Sol: disco central de radio 5 y ocho rayos rectangulares.
        'M12,7 A5,5 0 1,1 12,17 A5,5 0 1,1 12,7 Z ' +
        'M11.1,3 L12.9,3 L12.9,5.2 L11.1,5.2 Z ' +
        'M11.1,18.8 L12.9,18.8 L12.9,21 L11.1,21 Z ' +
        'M3,11.1 L5.2,11.1 L5.2,12.9 L3,12.9 Z ' +
        'M18.8,11.1 L21,11.1 L21,12.9 L18.8,12.9 Z ' +
        'M16.17,17.44 L17.73,19 L19,17.73 L17.44,16.17 Z ' +
        'M6.56,16.17 L5,17.73 L6.27,19 L7.83,17.44 Z ' +
        'M7.83,6.56 L6.27,5 L5,6.27 L6.56,7.83 Z ' +
        'M17.44,7.83 L19,6.27 L17.73,5 L16.17,6.56 Z'
    } else {
        # Luna: una sola figura cerrada, ya se veia bien.
        'M12,3 A9,9 0 1,0 21,12 A7,7 0 0,1 12,3 Z'
    }
    return [Windows.Media.Geometry]::Parse($trazado)
}

function Get-ColorRiesgo {
    <#
    .SYNOPSIS
        Traduce un nivel de riesgo a su color.
    .DESCRIPTION
        Devolvia DOS colores, fondo y texto, porque las etiquetas eran
        pildoras rellenas. Ahora son un punto y una palabra del mismo
        color, así que el fondo sobraba: seis valores menos que mantener
        coherentes con los dos temas, y una propiedad menos en cada una de
        las tres clases de Types.ps1.

        Los mismos valores que Éxito/Aviso/Peligro de los diccionarios de
        tema. Viajan como cadenas porque las clases de Types.ps1 no
        dependen de WPF; si se tocan allí, hay que tocarlos aquí.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Riesgo, [string] $Tema = 'oscuro')

    $oscuro = @{ 'Bajo' = '#4ADE80'; 'Medio' = '#FBBF24'; 'Alto' = '#FB7185' }
    $claro  = @{ 'Bajo' = '#15803D'; 'Medio' = '#B45309'; 'Alto' = '#DC2626' }
    $tabla = if ($Tema -eq 'claro') { $claro } else { $oscuro }
    if (-not $tabla.ContainsKey($Riesgo)) { $Riesgo = 'Bajo' }
    return $tabla[$Riesgo]
}

function Get-ColorAcentoTema {
    <#
    .SYNOPSIS
        Los cuatro colores de acento del tema en curso.

    .DESCRIPTION
        Existe porque había literales del TEMA OSCURO incrustados en tres
        sitios que no los recalculaban al cambiar de tema: las barras del
        panel de discos y las etiquetas LIMPIEZA/ANÁLISIS del historial.
        En tema claro quedaban colores chillones sobre fondo blanco, o
        verde oscuro sobre verde oscuro. Los mismos valores que ya usan
        Theme.Dark.xaml y Theme.Light.xaml, en un solo sitio.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Exito', 'Aviso', 'Peligro', 'Acento')] [string] $Cual,
        [string] $Tema = 'oscuro'
    )

    $oscuro = @{ Exito = '#4ADE80'; Aviso = '#FBBF24'; Peligro = '#FB7185'; Acento = '#2DD4BF' }
    $claro  = @{ Exito = '#15803D'; Aviso = '#B45309'; Peligro = '#DC2626'; Acento = '#0D9488' }
    $tabla = if ($Tema -eq 'claro') { $claro } else { $oscuro }
    return $tabla[$Cual]
}

# =====================================================================
#  VENTANA PRINCIPAL
# =====================================================================
function Show-VentanaPrincipal {
    <#
    .SYNOPSIS
        Construye y muestra la ventana. Devuelve cuando el usuario la cierra.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Configuracion,
        [Parameter(Mandatory)] $Modulos,
        [Parameter(Mandatory)] [hashtable] $Preferencias,
        [Parameter(Mandatory)] [string] $Raiz
    )

    Initialize-TiposInterfaz
    [void](Initialize-MotorBorrado)
    [void](Initialize-Registro -CarpetaDatos $Configuracion.CarpetaDatos)

    $carpetaUi = Get-CarpetaInterfaz

    # ---------- Aplicación y recursos -----------------------------------
    $app = [Windows.Application]::Current
    if ($null -eq $app) { $app = New-Object Windows.Application }
    $app.ShutdownMode = [Windows.ShutdownMode]::OnMainWindowClose

    $tema = if ($Preferencias.Tema -eq 'claro') { 'Theme.Light.xaml' } else { 'Theme.Dark.xaml' }
    $app.Resources.MergedDictionaries.Clear()
    $app.Resources.MergedDictionaries.Add((Import-Xaml (Join-Path $carpetaUi $tema)))
    $app.Resources.MergedDictionaries.Add((Import-Xaml (Join-Path $carpetaUi 'Styles.xaml')))

    $ventana = Import-Xaml (Join-Path $carpetaUi 'MainWindow.xaml')

    # El icono se asigna DESDE CÓDIGO y no con Icon="..." en el XAML: la
    # ventana se carga con XamlReader.Parse, sin ensamblado detras, así que
    # una ruta relativa o un URI de tipo pack no se resuelven contra nada.
    # Aquí si se sabe donde esta el proyecto.
    #
    # Si falla no pasa nada grave: la ventana sale con el icono generico de
    # Windows. Un icono no es motivo para no abrir el programa.
    try {
        $rutaIcono = Join-Path (Join-Path $Raiz 'assets') 'cachivache.ico'
        if (Test-Path -LiteralPath $rutaIcono) {
            $ventana.Icon = New-Object Windows.Media.Imaging.BitmapImage ([uri]$rutaIcono)
        }
    } catch {
        Write-Verbose "No se ha podido cargar el icono de la ventana: $($_.Exception.Message)"
    }

    # Sin esto, al maximizar la ventana ocupa la pantalla ENTERA y se mete
    # por debajo de la barra de tareas: al dibujar su propia barra de
    # titulo (WindowStyle="None"), Windows deja de calcularle los límites.
    Register-LimiteMaximizado -Ventana $ventana

    # ---------- Estado compartido ---------------------------------------
    $estado = [pscustomobject]@{
        Configuracion = $Configuracion
        Modulos       = $Modulos
        Preferencias  = $Preferencias
        Raiz          = $Raiz
        CarpetaUi     = $carpetaUi
        Tema          = if ($Preferencias.Tema -eq 'claro') { 'claro' } else { 'oscuro' }
        # ::new() y NO "New-Object System.Collections.Generic.List[object]".
        #
        # No es estilo: es un fallo real que rompio el informe HTML durante
        # semanas. Una lista de este tipo concreto creada con New-Object
        # produce un objeto que el operador @( ) NO PUEDE ENUMERAR: lanza
        # "Los tipos de argumentos no coinciden" (ArgumentException).
        #
        # Lo raro, y lo que lo hizo tan dificil de ver:
        #   - falla incluso con la lista VACIA;
        #   - falla solo con List[object]: List[string], HashSet, Dictionary
        #     y ObservableCollection creados igual van bien;
        #   - foreach, el pipe, .Count y .ToArray() funcionan. SOLO @( ).
        #
        # Como Export-InformeHtml empieza con "$lista = @($Candidatos)",
        # cada analisis terminaba con "No se ha podido generar el informe"
        # y nadie sabia por que. Las pruebas no lo cogian porque le pasaban
        # un ARRAY; la ventana le pasaba esta lista. Ver [COR-07] en
        # docs/HOJA-DE-RUTA.md.
        Candidatos    = [Collections.Generic.List[object]]::new()
        Items         = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.ItemVista]
        ModulosVista  = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.ModuloVista]
        PerfilesVista = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.PerfilVista]
        DiscosVista   = New-Object System.Collections.ObjectModel.ObservableCollection[Cachivache.DiscoVista]
        Cola          = @()
        # El ScrollViewer que de verdad desplaza la tabla de resultados,
        # una vez encontrado. Vive DENTRO de la plantilla del DataGrid, y
        # esa plantilla no esta aplicada hasta que la ventana se carga, de
        # modo que las primeras busquedas pueden no dar con el. Se guarda
        # aqui SOLO cuando aparece: cachear el "no esta" condenaria a
        # [USO-10] para toda la sesion.
        DesplazadorTabla = $null
        Indice        = 0
        Total         = 0
        Ocupado       = $false
        Fase          = 'reposo'
        Sync          = (New-EstadoSincronizado)
        Runspace      = $null
        PowerShell    = $null
        Handle        = $null
        LibreInicial  = 0.0
        # En que modo se lanzo el lote que esta corriendo ahora mismo. Se
        # fija al pulsar el boton y NO se vuelve a mirar la casilla: entre
        # el arranque y el final el usuario puede haberla tocado, y lo que
        # decide si esto se anota en el historial es como se ejecuto de
        # verdad, no como esta la interfaz al terminar. Tambien sobrevive a
        # que el trabajo se caiga a medias, que es cuando mas importa no
        # apuntar una limpieza que no ha ocurrido.
        SimulandoLote = $false
        # Lo que impide decir "Análisis terminado" cuando no lo está.
        # Cancelar en el módulo 7 de 21 producia exactamente el mismo texto
        # que recorrer los 21, y el usuario borraba creyendo haber visto
        # todo lo que hay. Ver [CNF-04] en docs/HOJA-DE-RUTA.md.
        AnalisisCancelado = $false
        ModulosFallidos   = [Collections.Generic.List[string]]::new()
        # El espacio libre se consulta por WMI, que tarda decenas de
        # milisegundos. Como el resumen del pie se recalcula en cada clic
        # de casilla, se cachea y solo se refresca cuando puede cambiar.
        LibreCache    = 0.0
        # Mientras esta a $true, marcar casillas no recalcula el resumen.
        # Lo usa el marcado en lote para no repetir el calculo N veces.
        SuprimirResumen = $false
        # Mientras esta a $true, mover los controles de Ajustes NO pasa el
        # perfil a Personalizado: es la propia aplicación la que los esta
        # poniendo al valor del perfil elegido.
        SincronizandoPerfil = $false
        # Cuantas líneas hay ahora mismo en el panel de Registro. Se lleva
        # la cuenta a mano en vez de preguntarselo al TextBox porque
        # contarlas obliga a partir todo el texto, y esto se consulta en
        # cada volcado; el recorte de verdad, que si parte el texto, solo
        # ocurre cuando este número se pasa del tope.
        LineasConsola = 0
        Cronometro    = $null
        Vista         = $null
        # Temporizador del cuadro de filtro. Filtrar no ocurre al pulsar
        # una tecla sino 250 ms después de la última, así que escribir una
        # palabra provoca una pasada por la tabla y no una por letra. Vive
        # aquí para que no se lo lleve el recolector de basura.
        TemporizadorFiltro = $null
        # Comprobación de versión nueva [DIS-05]. Viven aquí por lo mismo
        # que el temporizador del filtro: mientras la consulta esta en
        # marcha, el recolector de basura no puede llevarse ni el
        # temporizador que la sondea ni el trabajo que la ejecuta.
        #
        # TrabajoVersion es $null cuando no hay ninguna consulta en curso, y
        # es lo que impide que dos pulsaciones seguidas del boton abran dos.
        TemporizadorVersion = $null
        TrabajoVersion      = $null
    }

    # Una cabecera por arranque de la interfaz, con el ID de sesión que va
    # a llevar cada línea de este proceso. Ver [T-05] en
    # docs/OPTIMIZACIONES.md.
    Write-CabeceraSesion -Perfil $Preferencias.Perfil -Admin $Configuracion.Admin -Sync $estado.Sync

    # ---------- Acceso rápido a los controles ---------------------------
    $c = @{}
    foreach ($nombre in @(
        'TxtVersionBarra', 'InsigniaAdmin', 'PuntoAdmin', 'TxtInsigniaAdmin',
        'BtnTema', 'IconoTema', 'BtnMinimizar', 'BtnMaximizar', 'BtnCerrar',
        'NavInicio', 'NavResultados', 'NavRegistro', 'NavInformes', 'NavAjustes', 'NavAcerca',
        'ListaDiscos', 'TxtTotalHistorico',
        'PanelInicio', 'PanelResultados', 'PanelRegistro', 'PanelInformes', 'PanelAjustes', 'PanelAcerca',
        'ListaPerfiles', 'ListaModulos', 'BtnModulosTodos', 'BtnModulosNinguno',
        'TxtEstadoInicio', 'BarraInicio', 'BtnAnalizar', 'BtnCancelar',
        'TxtResumenAnalisis', 'CampoFiltro', 'FiltroRiesgo',
        'BtnMarcarTodo', 'BtnDesmarcarTodo', 'BtnSoloSeguros', 'BtnAbrirCarpeta', 'BtnVerContenido',
        'ChkOcultarHechos', 'BtnMostrarHechos',
        'MenuAbrirUbicacion', 'MenuCopiarRuta', 'MenuExcluirSiempre', 'MenuDesmarcarGrupo',
        'TablaResultados', 'TxtSeleccion', 'TxtProyeccion', 'BarraBorrado',
        'BtnExportar', 'BtnEliminar', 'BtnCancelarBorrado', 'ChkSimular', 'ChkAnonimizar', 'BtnAbrirPapelera',
        'EstadoVacio', 'TxtEstadoVacio', 'BtnQuitarFiltros',
        'AvisoIncompleto', 'TxtAvisoIncompleto',
        'AvisoSimulacion', 'TxtAvisoSimulacion',
        'Consola', 'BtnCopiarRegistro', 'BtnAbrirRegistro',
        'BtnExportarHtml', 'BtnExportarCsv', 'BtnExportarJson',
        'ListaInformesHtml', 'TxtSinInformesHtml',
        'ListaInformesCsv', 'TxtSinInformesCsv',
        'ListaInformesJson', 'TxtSinInformesJson',
        'ListaHistorial', 'TxtHistorialVacio',
        'SliderMinimoMB', 'TxtMinimoMB', 'SliderDias', 'TxtDiasSinUso',
        'ChkMenores', 'ChkPermanente', 'TxtEstadoAdmin', 'BtnReiniciarAdmin',
        'TxtResumenExclusiones', 'ListaExclusiones',
        'TxtCarpetaDatos', 'BtnAbrirDatos', 'BtnRestablecer',
        'TxtVersionAcerca', 'BtnRepositorio',
        'TxtActualizacion', 'BtnBuscarActualizacion', 'BtnIrAVersionNueva', 'BtnCopiarDiagnostico')) {
        $c[$nombre] = $ventana.FindName($nombre)
    }

    # =================================================================
    #  EL CUERPO DE LA VENTANA, POR PARTES
    # =================================================================
    # Cada uno de estos cuatro archivos es un trozo del cuerpo de ESTA
    # función, no una coleccion de funciones sueltas. Se dot-sourcean AQUÍ
    # DENTRO, en el ámbito de Show-VentanaPrincipal, de modo que ven $c,
    # $estado, $ventana y los cierres que definen entre ellos, exactamente
    # igual que si el texto estuviera pegado en este punto. Cargarlos desde
    # fuera de la función NO funcionaria: las definiciones moririan con el
    # ámbito del cargador.
    #
    # Sobre el orden: al cargarse, cada archivo se limita a DEFINIR sus
    # cierres; las referencias cruzadas entre ellos (por ejemplo, el
    # temporizador de Análisis llama a $terminarBorrado, que define
    # Eliminación) viven dentro de scriptblocks que no se evaluan hasta
    # mucho después, con los cuatro archivos ya cargados. Comprobado por
    # AST: en el momento de la carga ninguno usa nada que no exista ya.
    # Aun así se respeta el orden original de lectura, que es el que
    # cuenta la historia de arriba abajo.
    #
    # Ver docs/ESTRUCTURA.md (sección 3) para por que esta división es
    # segura y que se comprobo antes de hacerla.
    . (Join-Path $carpetaUi 'Window.Ayudantes.ps1')
    . (Join-Path $carpetaUi 'Window.Analisis.ps1')
    . (Join-Path $carpetaUi 'Window.Eliminacion.ps1')
    . (Join-Path $carpetaUi 'Window.Eventos.ps1')

    # =================================================================
    #  ESTADO INICIAL
    # =================================================================
    if ($estado.Tema -eq 'claro') {
        $c.IconoTema.Data = Get-GeometriaTema 'claro'
    }

    $c.TxtVersionBarra.Text  = 'v' + $script:VersionCachivache
    $c.TxtVersionAcerca.Text = 'Versión {0} - PowerShell {1} - {2}' -f `
                               $script:VersionCachivache, $PSVersionTable.PSVersion, $estado.Configuracion.Windows
    $c.TxtCarpetaDatos.Text  = $estado.Configuracion.CarpetaDatos

    # La insignia se ve siempre; lo que cambian son el texto y el color.
    # Ambar en modo estandar -hay módulos que no vas a poder usar- y verde
    # como administrador, que es cuando esta todo disponible. Antes el
    # color era ambar fijo, así que ir como administrador se anunciaba con
    # el color de un aviso.
    $c.InsigniaAdmin.Visibility = 'Visible'
    if ($estado.Configuracion.Admin) {
        $c.TxtInsigniaAdmin.Text = 'Administrador'
        $c.TxtEstadoAdmin.Text = 'El programa se esta ejecutando como administrador: todos los módulos están disponibles.'
        $c.BtnReiniciarAdmin.IsEnabled = $false
        $pincelInsignia = $app.Resources['Exito']
    } else {
        $c.TxtInsigniaAdmin.Text = 'Modo estandar'
        $c.TxtEstadoAdmin.Text = 'Modo estandar. Los módulos de registros del sistema y de Windows Update necesitan permisos de administrador.'
        $pincelInsignia = $app.Resources['Aviso']
    }
    $c.PuntoAdmin.Fill = $pincelInsignia
    $c.TxtInsigniaAdmin.Foreground = $pincelInsignia

    $c.SliderMinimoMB.Value    = [int]$estado.Preferencias.MinimoMB
    $c.SliderDias.Value        = [int]$estado.Preferencias.DiasSinUso
    $c.ChkMenores.IsChecked    = [bool]$estado.Preferencias.IncluirMenores
    $c.ChkPermanente.IsChecked = [bool]$estado.Preferencias.Permanente
    $c.TxtMinimoMB.Text        = '{0} MB' -f [int]$estado.Preferencias.MinimoMB
    $c.TxtDiasSinUso.Text      = '{0} dias' -f [int]$estado.Preferencias.DiasSinUso

    & $refrescarModulos
    $c.ListaModulos.ItemsSource   = $estado.ModulosVista
    $c.ListaPerfiles.ItemsSource  = $estado.PerfilesVista

    # La vista se pide y se configura ANTES de entregarle la coleccion al
    # DataGrid. Al revés (que es como estaba) el DataGrid ya se ha
    # enganchado a la vista y esta en mitad de su pasada de enlace (tiene
    # GroupStyle declarado en el XAML), así que añadir la agrupacion en
    # ese momento revienta con "no se puede cambiar el contenido o la
    # posición Current de CollectionView mientras Refresh se esta
    # aplazando" y la ventana no llega a abrirse.
    #
    # GetDefaultView devuelve SIEMPRE la misma instancia para la misma
    # coleccion, de modo que el DataGrid recibe justo después esta misma
    # vista, ya agrupada. La comprobación de Count evita duplicar la
    # agrupacion si alguna vez se vuelve a pasar por aquí (es el mismo
    # fallo que [C-12] corrigio en el cambio de tema).
    $estado.Vista = [Windows.Data.CollectionViewSource]::GetDefaultView($estado.Items)
    if ($estado.Vista.GroupDescriptions.Count -eq 0) {
        $estado.Vista.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Categoria'))
    }
    $c.TablaResultados.ItemsSource = $estado.Items

    # Estos tres rellenan paneles a partir de datos de disco -unidades,
    # historial, informes-. Nada de eso es imprescindible para que el
    # programa sirva, así que un problema leyendolos NO puede impedir que
    # la ventana se abra: el usuario se queda sin ese panel, no sin
    # programa. Paso exactamente eso, con un historial que se leia mal en
    # PowerShell 5.1 (ver la cabecera de Get-Historial).
    foreach ($paso in @(
        @{ Que = 'los discos';   Hacer = $refrescarDiscos },
        @{ Que = 'el historial'; Hacer = $refrescarHistorial },
        @{ Que = 'el resumen';   Hacer = $actualizarResumenSeleccion })) {
        try {
            & $paso.Hacer
        } catch {
            # Con Write-Registro y no con $escribir: $escribir vuelca a la
            # consola de la ventana, y en este punto puede ser justo lo que
            # ha fallado.
            Write-Registro -Nivel 'ERROR' -Mensaje (
                'No se ha podido preparar {0} al arrancar: {1}' -f $paso.Que, $_.Exception.Message)
        }
    }

    & $escribir ('Cachivache v{0} iniciado. Equipo: {1}. {2}' -f `
                 $script:VersionCachivache, $estado.Configuracion.Equipo,
                 $(if ($estado.Configuracion.Admin) { 'Modo administrador.' } else { 'Modo estandar.' }))

    # ---------- Arranque -------------------------------------------------
    # Un fallo dentro de un manejador de WPF (un enlace de datos que
    # escribe de vuelta, un evento que salta al materializar una lista...)
    # no ocurre en ninguna línea de este archivo: ocurre dentro de
    # $app.Run, mientras se dibuja. Sin este manejador, lo único que se ve
    # es "Excepción al llamar a X" sin ningún sitio al que ir a mirar.
    $app.Add_DispatcherUnhandledException({
        param($remitente, $argumentos)
        $ex = $argumentos.Exception
        Write-Host ''
        Write-Host '  Fallo dentro de la interfaz (no en el arranque lineal):' -ForegroundColor Red
        Write-Host "    $($ex.Message)"
        $interna = $ex.InnerException
        while ($interna) {
            Write-Host "    causado por: $($interna.Message)"
            $interna = $interna.InnerException
        }
        Write-Host ''
        Write-Host '  Pila de .NET:' -ForegroundColor Yellow
        Write-Host $ex.StackTrace
        Write-Host ''
        try {
            Write-Registro -Nivel 'ERROR' -Mensaje ("Fallo en la interfaz: {0}`n{1}" -f $ex.Message, $ex.StackTrace)
        } catch {
            Write-Verbose "Tampoco se ha podido anotar el fallo en el registro: $($_.Exception.Message)"
        }

        # Solo la PRIMERA vez de cada fallo distinto. Este manejador salta
        # dentro del bucle de WPF, y ahi los fallos no vienen de uno en uno:
        # vienen en cada tick del temporizador o en cada fila de una lista.
        # Un cuadro modal por cada uno enterraba la ventana bajo veinte
        # avisos identicos que habia que cerrar de uno en uno, mientras el
        # analisis que los generaba seguia corriendo detras y no habia forma
        # de llegar al boton de pararlo. Al registro van todos. Ver [USO-14].
        try {
            if (Test-DebeAvisarDelFallo -Firma (Get-FirmaDeFallo -Excepcion $ex)) {
                [void][Windows.MessageBox]::Show(
                    ("Ha fallado algo dentro de la ventana:`n`n{0}`n`nEl programa sigue abierto. Si esto se repite solo se anotara en el registro, para no llenarte la pantalla de avisos. El detalle completo esta ahi; si vuelve a pasar, adjuntalo al informar del fallo." -f $ex.Message),
                    'Ha fallado algo', 'OK', 'Warning')
            }
        } catch {
            Write-Verbose "No se ha podido avisar del fallo por pantalla: $($_.Exception.Message)"
        }

        # Sin esto, WPF vuelve a lanzar la excepción y el proceso MUERE. Y
        # al morir así no llega a correr el manejador de Closing, que es
        # quien para el runspace de trabajo y guarda las preferencias: se
        # perdian los ajustes y quedaba un runspace trabajando sobre el
        # disco sin nadie mirando. Cualquier fallo en cualquier manejador
        # -un Start-Process que no encuentra la carpeta, un disco lleno al
        # anotar el historial- se llevaba la aplicación entera por delante.
        # Se marca como atendido: ya se ha registrado y se ha avisado.
        $argumentos.Handled = $true
    })

    $app.MainWindow = $ventana
    [void]$app.Run($ventana)
}
