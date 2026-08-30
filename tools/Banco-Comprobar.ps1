<#
.SYNOPSIS
    Juzga una pasada del banco de pruebas. Es lo que ejecuta el trabajo
    "banco" de la integracion continua, y no borra nada por su cuenta.

.DESCRIPTION
    [VAL-03]. El banco existia para ejecutarse a mano en una maquina
    virtual, y por eso lo que decidia si una comprobacion habia salido bien
    era una casilla de docs/BANCO-PRUEBAS.md marcada por una persona. Un
    agente de GitHub tambien es una maquina virtual efimera, con Windows de
    verdad, NTFS de verdad y borrado de verdad: casi todo lo que no exige
    mirar una ventana se puede decidir solo.

    Este guion es ese "decidir solo". No monta nada -eso es
    Banco-Pruebas.ps1- y no borra el banco: recibe una fase, mira lo que
    tenga que mirar, escribe lo que ha visto y termina con codigo 1 si algo
    no cuadra.

    DONDE ESTA LA DECISION
    ----------------------
    Las cuentas viven en Banco-Decisiones.ps1, que es calculo puro y va
    probado en Linux: el catalogo de cebos, si una ruta cae dentro del
    banco, si cae en el perfil de otro usuario, y cuantos cebos de cada
    familia ha encontrado el analisis. Aqui solo se leen archivos, se
    llama al nucleo del programa y se imprime. La razon es la de siempre:
    esto se ejecuta en Windows y la suite corre en Linux, asi que todo lo
    que se pueda decidir sin Windows tiene que estar donde se pueda probar.

    QUE ES SENYAL Y QUE ES RUIDO
    ----------------------------
    Un agente de GitHub trae puesto lo suyo -o no lo trae: no tiene Steam,
    ni Docker, ni navegadores con cache-, asi que "un modulo no ha
    encontrado nada" no significa nada. Todas las comprobaciones de aqui
    son sobre lo que ha creado el banco, o sobre respuestas de la guardia a
    preguntas cuya respuesta correcta no depende del agente. Un modulo
    vacio no falla; un cebo que no aparece, si.

    Y toda comprobacion lleva su guarda: si no encuentra lo que necesita
    para comprobar algo, lo dice y falla, en vez de pasar sin haber mirado.

.PARAMETER Fase
    Que se comprueba. Ver el bloque de cada una mas abajo.

.PARAMETER Informe
    El .json que genero el analisis. Fases 'analisis' y 'simulacion'.

.PARAMETER ArchivosDeSobra
    Los mismos que se le pasaron a Banco-Pruebas.ps1. Si no coinciden, la
    fase 'analisis' buscaria cebos que nadie monto.

.PARAMETER Salida
    Donde escribir el inventario. Fase 'inventario'.

.PARAMETER Antes
.PARAMETER Despues
    Los dos inventarios que se comparan. Fase 'limpieza'.

.EXAMPLE
    .\tools\Banco-Comprobar.ps1 -Fase montaje -ArchivosDeSobra 300
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('montaje', 'analisis', 'windows', 'dosanalisis',
                 'inventario', 'simulacion', 'limpieza')]
    [string] $Fase,

    [string] $Informe = '',
    [ValidateRange(0, 50000)]
    [int]    $ArchivosDeSobra = 300,
    [string] $Salida = '',
    [string] $Antes = '',
    [string] $Despues = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$RaizProyecto = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Banco-Decisiones.ps1')

# El nucleo se dot-sourcea AQUI, en el ambito del guion, y no dentro de una
# funcion. Lo dice la cabecera de Bootstrap.ps1 y cuesta una sesion
# aprenderlo: una funcion que dot-sourcea carga las definiciones en SU
# ambito y se las lleva al terminar. Ademas hace falta que sea este ambito
# en concreto, porque las variables $script: del nucleo -sobre todo
# $script:UltimoError, que es donde Remove.ps1 deja el motivo de que algo no
# se haya borrado- viven en el ambito donde se cargo el archivo, y este
# guion tiene que poder leerlas.
. (Join-Path (Join-Path (Join-Path $RaizProyecto 'src') 'Core') 'Bootstrap.ps1')

# ---------------------------------------------------------------------
#  Como se dice lo que se ha visto
# ---------------------------------------------------------------------

$script:Fallos = [Collections.Generic.List[string]]::new()

function Write-Veredicto {
    <#
    .SYNOPSIS
        Una linea por comprobacion, con lo que se ha mirado.

    .DESCRIPTION
        El detalle se imprime SIEMPRE, tambien cuando la comprobacion pasa.
        Un registro que solo habla cuando falla obliga a adivinar que
        estaba mirando el dia que empiece a fallar, y estos pasos se leen
        meses despues.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Que,
        [Parameter(Mandatory)] [bool]   $Bien,
        [string] $Detalle = ''
    )

    if ($Bien) {
        Write-Host ('  OK     {0}' -f $Que) -ForegroundColor Green
    } else {
        Write-Host ('  FALLA  {0}' -f $Que) -ForegroundColor Red
        Write-Host ("::error::{0}: {1}" -f $Que, $Detalle)
        $script:Fallos.Add($Que)
    }
    if ($Detalle) { Write-Host ('         {0}' -f $Detalle) -ForegroundColor DarkGray }
}

function Write-Aviso {
    <#
    .SYNOPSIS
        Algo que hay que saber y que NO es un fallo del programa.

    .DESCRIPTION
        Para lo que el agente no puede comprobar (un modulo que se omitio
        por permisos) y para lo que se sabe que no se cumple y esta
        explicado en el catalogo. Sale como aviso de GitHub, o sea visible
        en la pestanya, sin ponerlo todo en rojo. Un trabajo que se pone en
        rojo por algo que no tiene arreglo se aprende a ignorar, y entonces
        deja de proteger tambien donde importa.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Texto)

    Write-Host ('  AVISO  {0}' -f $Texto) -ForegroundColor Yellow
    Write-Host ("::warning::{0}" -f $Texto)
}

function Get-RaizDelBanco {
    <#
    .SYNOPSIS
        La carpeta del banco en ESTE equipo.
    .DESCRIPTION
        Misma cuenta que hace Banco-Pruebas.ps1, con la misma funcion pura,
        para que el comprobador no pueda estar mirando otra carpeta.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $documentos = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $raiz = Get-RutaRaizBanco -Documentos $documentos
    if ([string]::IsNullOrWhiteSpace($raiz)) {
        throw 'No se ha podido encontrar la carpeta Documentos de este usuario.'
    }
    return [IO.Path]::GetFullPath($raiz)
}

function Get-ArchivosDeVerdad {
    <#
    .SYNOPSIS
        Todos los archivos que cuelgan de una carpeta, incluidos los que
        estan a mas de 260 caracteres.

    .DESCRIPTION
        Pila propia y DirectoryInfo con el prefijo "\\?\", por el mismo
        motivo que Get-ResumenArbol: Get-ChildItem -Recurse de Windows
        PowerShell 5.1 se para en MAX_PATH sin decir nada. Y aqui pararse
        en silencio seria peor que en ningun otro sitio: este inventario es
        lo que despues decide si la limpieza toco algo que no debia, asi
        que un archivo que no se llegue a inventariar es un archivo que
        puede desaparecer sin que nadie lo cuente.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string] $Carpeta)

    $encontrados = [Collections.Generic.List[string]]::new()
    if (-not [IO.Directory]::Exists('\\?\' + $Carpeta)) { return @() }

    $pendientes = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pendientes.Push([IO.DirectoryInfo]::new('\\?\' + $Carpeta))

    while ($pendientes.Count -gt 0) {
        $actual = $pendientes.Pop()
        try {
            foreach ($archivo in $actual.EnumerateFiles()) {
                $ruta = $archivo.FullName
                if ($ruta.StartsWith('\\?\')) { $ruta = $ruta.Substring(4) }
                $encontrados.Add($ruta)
            }
        } catch {
            Write-Host ('         (no se ha podido leer {0}: {1})' -f $actual.FullName, $_.Exception.Message)
        }
        try {
            foreach ($sub in $actual.EnumerateDirectories()) {
                # Los puntos de reanalisis no se siguen: al otro lado esta
                # otra carpeta y el inventario contaria cosas de fuera.
                if ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $pendientes.Push($sub)
            }
        } catch {
            Write-Host ('         (no se han podido listar las subcarpetas de {0})' -f $actual.FullName)
        }
    }
    return @($encontrados)
}

function Initialize-Comprobador {
    <#
    .SYNOPSIS
        Descubre el equipo y deja la guardia lista, como haria el programa.
    .DESCRIPTION
        Devuelve la configuracion para que las fases la usen. El nucleo ya
        esta cargado: se dot-sourcea arriba, en el ambito del guion.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param()

    # Lo mismo, y en el mismo orden, que hace Cachivache.ps1 al arrancar.
    # Initialize-Registro va primero por lo mismo que alli: cualquier
    # Write-Registro que salga del nucleo antes de eso no tiene archivo
    # donde escribir y se pierde, y el archivo del registro es justo lo que
    # se sube como artefacto cuando algo falla.
    [void](Initialize-Registro)
    $configuracion = New-Configuracion -Perfil 'agresivo'
    Initialize-Guardia -Configuracion $configuracion

    # La misma comprobacion de cordura que hace Cachivache.ps1: si la
    # guardia no estuviera lista respondaria que si a todo, y este guion
    # daria por buenas rutas que no ha llegado a mirar.
    if (-not (Test-RutaIntocable 'C:\Windows\System32')) {
        throw 'La guardia no se ha inicializado: no se puede comprobar nada.'
    }
    return $configuracion
}

# ---------------------------------------------------------------------
#  FASE montaje: el banco esta donde dice el catalogo
# ---------------------------------------------------------------------
function Invoke-FaseMontaje {
    [CmdletBinding()]
    param()

    $raiz = Get-RaizDelBanco
    Write-Host ('Banco: {0}' -f $raiz) -ForegroundColor Cyan

    # Guarda: si Banco-Pruebas.ps1 se hubiera negado a montar -por ejemplo
    # porque no reconocio el agente como maquina virtual- no habria ni
    # carpeta, y todas las fases siguientes pasarian mirando el vacio.
    Write-Veredicto -Que 'el banco se ha montado' -Bien ([IO.Directory]::Exists($raiz)) `
        -Detalle ('Si no existe, Banco-Pruebas.ps1 no llego a montar: mira su salida. ' +
                  'La red de "esto no parece una maquina virtual" tiene que caer sola en un agente.')
    if (-not [IO.Directory]::Exists($raiz)) { return }

    foreach ($cebo in (Get-CebosBanco -ArchivosDeSobra $ArchivosDeSobra)) {
        if ([int]$cebo.Cuantos -le 0) { continue }

        $faltan = 0
        $bytes  = 0.0
        for ($n = 1; $n -le [int]$cebo.Cuantos; $n++) {
            $ruta = '\\?\' + (Get-RutaCebo -Cebo $cebo -Raiz $raiz -Indice $n)
            if ($cebo.EsCarpeta) {
                if (-not [IO.Directory]::Exists($ruta)) { $faltan++ }
            } elseif ([IO.File]::Exists($ruta)) {
                $bytes += [double]([IO.FileInfo]::new($ruta).Length)
            } else {
                $faltan++
            }
        }

        Write-Veredicto -Que ('cebo {0}: los {1} montados' -f $cebo.Id, $cebo.Cuantos) `
            -Bien ($faltan -eq 0) `
            -Detalle ('faltan {0}; ocupan {1:N0} bytes en total ({2})' -f $faltan, $bytes, $cebo.Para)
    }

    # La ruta larga tiene que ser larga DE VERDAD. Si el perfil del usuario
    # fuera muy corto y el cebo no llegara a 260 caracteres, toda la
    # comprobacion de [COR-02] pasaria sin comprobar nada.
    $largo = Get-RutaCebo -Raiz $raiz -Cebo (
        Get-CebosBanco -ArchivosDeSobra $ArchivosDeSobra | Where-Object { $_.Id -eq 'ruta-larga' })
    Write-Veredicto -Que 'el cebo de ruta larga pasa de 260 caracteres' -Bien ($largo.Length -ge 260) `
        -Detalle ('mide {0}' -f $largo.Length)
}

# ---------------------------------------------------------------------
#  FASE analisis: que propuso, y sobre todo que NO tenia que proponer
# ---------------------------------------------------------------------
function Invoke-FaseAnalisis {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $Informe)) {
        throw "No esta el informe del analisis: $Informe"
    }

    $raiz      = Get-RaizDelBanco
    $documento = Get-Content -Raw -LiteralPath $Informe | ConvertFrom-Json
    $candidatos = @($documento.Candidatos)

    # Guarda. Un informe vacio hace que todas las comprobaciones de abajo
    # pasen: no hay nada del sistema porque no hay nada.
    Write-Veredicto -Que 'el analisis ha propuesto algo' -Bien ($candidatos.Count -gt 0) `
        -Detalle ('{0} elementos en el informe' -f $candidatos.Count)
    if ($candidatos.Count -eq 0) { return }

    [void](Initialize-Comprobador)

    $rutas = @($candidatos | ForEach-Object { [string]$_.Ruta })

    # --- 1. Los cebos aparecen -----------------------------------------
    $resumen = Get-ResumenCebos -Cebos (Get-CebosBanco -ArchivosDeSobra $ArchivosDeSobra) `
                                -Raiz $raiz -Propuestas $rutas
    foreach ($fila in $resumen) {
        $detalle = ('{0} de {1}' -f $fila.Encontrados, $fila.Esperados)
        if ($fila.Ejemplos.Count -gt 0) {
            $detalle += ('; falta por ejemplo {0}' -f ($fila.Ejemplos -join ', '))
        }

        if ($fila.EnAnalisis) {
            Write-Veredicto -Que ('el analisis encuentra el cebo {0}' -f $fila.Id) `
                -Bien ($fila.Falta -eq 0) -Detalle $detalle
        } else {
            # No se gatilla, pero el numero se ve: es lo que permitira
            # darse cuenta el dia que empiece a aparecer.
            Write-Host ('  NOTA   el cebo {0} no se espera en el analisis: {1}' -f $fila.Id, $detalle)
            Write-Host ('         {0}' -f $fila.MotivoFuera) -ForegroundColor DarkGray
            if ($fila.Falta -lt $fila.Esperados) {
                # Los parentesis de la concatenacion son imprescindibles:
                # -f se enlaza mas fuerte que +, asi que sin ellos esto
                # formatea la SEGUNDA cadena y el {0} sale literal.
                Write-Aviso (('El cebo {0} SI aparece en el analisis, y el catalogo dice que no. ' +
                              'Es una buena noticia: actualiza EnAnalisis en Get-CebosBanco.') -f $fila.Id)
            }
        }
    }

    # --- 2. Nada de perfiles de otros usuarios --------------------------
    #
    # Esto y lo siguiente son la comprobacion 5.1 del banco, la unica que
    # si falla lo para todo. No se veta "cualquier cosa bajo C:\Windows"
    # porque hay modulos que proponen ahi a proposito -Windows Update, los
    # logs del sistema, el almacen de componentes- y seria un falso
    # positivo en cada ejecucion. El perfil de otro usuario, en cambio, no
    # tiene que salir jamas.
    $carpetaUsuarios = [IO.Path]::GetDirectoryName($env:USERPROFILE)
    Write-Veredicto -Que 'se sabe donde estan los perfiles de usuario' `
        -Bien (-not [string]::IsNullOrWhiteSpace($carpetaUsuarios)) `
        -Detalle ('perfiles en {0}, el propio es {1}' -f $carpetaUsuarios, $env:USERPROFILE)

    $ajenas = @($rutas | Where-Object {
        Test-PerfilAjeno -Ruta $_ -CarpetaUsuarios $carpetaUsuarios -PerfilPropio $env:USERPROFILE
    } | Sort-Object -Unique)
    Write-Veredicto -Que 'no se propone nada del perfil de otro usuario' -Bien ($ajenas.Count -eq 0) `
        -Detalle $(if ($ajenas.Count -eq 0) { 'ninguna de las rutas propuestas cuelga de otro perfil' }
                   else { ($ajenas | Select-Object -First 10) -join ' | ' })

    # --- 3. Nada que la guardia prohiba ---------------------------------
    #
    # Se le pregunta a la guardia, en este equipo y con estas rutas, por
    # cada candidato que de verdad borraria algo. 'Informativo' no borra y
    # 'Comando' no lleva una ruta: los dos quedan fuera a proposito.
    $borrables = @($candidatos | Where-Object {
        $_.Metodo -ne 'Informativo' -and $_.Metodo -ne 'Comando' -and (Test-EsRutaDeVerdad -Texto ([string]$_.Ruta))
    })
    Write-Veredicto -Que 'hay candidatos con ruta real que comprobar' -Bien ($borrables.Count -gt 0) `
        -Detalle ('{0} de {1} candidatos borran algo de una ruta' -f $borrables.Count, $candidatos.Count)

    $prohibidas = [Collections.Generic.List[string]]::new()
    foreach ($candidato in $borrables) {
        $motivo = Get-MotivoIntocable ([string]$candidato.Ruta)
        if ($motivo) { $prohibidas.Add(('{0}  ->  {1}' -f $candidato.Ruta, $motivo)) }
    }
    Write-Veredicto -Que 'la guardia no prohibe ninguna de las rutas propuestas' `
        -Bien ($prohibidas.Count -eq 0) `
        -Detalle $(if ($prohibidas.Count -eq 0) { ('{0} rutas comprobadas una a una' -f $borrables.Count) }
                   else { ($prohibidas | Select-Object -First 10) -join ' | ' })

    # --- 4. [I18N-03]: DISM en un Windows que no esta en castellano -----
    #
    # 75-AlmacenComponentes lee la salida de DISM, que viene TRADUCIDA, y
    # reconoce los rotulos en ingles y en castellano. En un agente de
    # GitHub -que esta en ingles- es donde se comprueba la mitad inglesa,
    # que hasta hoy no habia ejecutado nadie. Si no la reconociera, el
    # modulo cae en su rama de "no se ha podido leer" y lo dice con ese
    # nombre exacto.
    $componentes = @($candidatos | Where-Object { $_.ModuloId -eq 'componentes' })
    if ($componentes.Count -eq 0) {
        Write-Aviso ('el modulo del almacen de componentes no ha dado resultado (necesita administrador): ' +
                     'la comprobacion de [I18N-03] sobre la salida de DISM no ha comprobado nada esta vez.')
    } else {
        $ilegible = @($componentes | Where-Object { [string]$_.Nombre -match 'No se ha podido leer la estimaci' })
        Write-Veredicto -Que '[I18N-03] se entiende la salida de DISM en este idioma' `
            -Bien ($ilegible.Count -eq 0) `
            -Detalle ('el modulo ha dicho: {0}' -f (@($componentes | ForEach-Object { $_.Nombre }) -join ' | '))
    }
}

# ---------------------------------------------------------------------
#  FASE windows: lo que solo se puede comprobar sobre NTFS de verdad
# ---------------------------------------------------------------------
function Invoke-FaseWindows {
    [CmdletBinding()]
    param()

    $raiz = Get-RaizDelBanco
    $configuracion = Initialize-Comprobador

    Write-Host ('Windows: {0}' -f $configuracion.Windows) -ForegroundColor Cyan
    Write-Host ('Idioma de la interfaz: {0} | cultura: {1}' -f `
                [Globalization.CultureInfo]::InstalledUICulture.Name,
                [Globalization.CultureInfo]::CurrentCulture.Name) -ForegroundColor Cyan

    # --- [I18N-03] La guardia, en el idioma que sea ---------------------
    #
    # Test-CarpetaEspejo y Test-ArchivoPersonal comparan contra listas de
    # palabras en castellano Y en ingles. La mitad inglesa no la habia
    # ejecutado nunca nadie: el programa se prueba en el Windows en
    # castellano de su autor. Aqui se le pregunta con los nombres REALES
    # de las carpetas de este equipo, sean los que sean.
    # El @() de fuera es el que importa: si el filtro dejara pasar una sola
    # carpeta, sin el la asignacion produciria una cadena suelta y $carpetas.Count
    # valdria la longitud del texto. Es la leccion de [C-07].
    $carpetas = @(@('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos') |
                  ForEach-Object { Get-CarpetaConocida $_ } |
                  Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    Write-Veredicto -Que 'se han resuelto las carpetas del usuario' -Bien ($carpetas.Count -eq 6) `
        -Detalle (($carpetas | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')

    $sinProteger = @($carpetas | Where-Object { -not (Test-RutaIntocable $_) })
    Write-Veredicto -Que '[I18N-03] la guardia protege las carpetas personales de este idioma' `
        -Bien ($sinProteger.Count -eq 0) -Detalle ($sinProteger -join ' | ')

    # Test-CarpetaEspejo se comprueba SOLO sobre las tres que su lista dice
    # cubrir en ingles -desktop, documents, downloads-, y no sobre las seis.
    # La lista lleva los nombres HEREDADOS de Imagenes, Musica y Videos
    # ("mypictures", "mymusic", "myvideos", que son los enlaces antiguos)
    # pero no los modernos, y eso no es un agujero: esas tres carpetas las
    # veta igualmente Test-RutaIntocable por su filtro de carpeta personal,
    # que es la comprobacion de arriba. Exigir aqui las seis seria un falso
    # positivo en cada ejecucion, y un trabajo que se pone rojo sin motivo
    # se aprende a ignorar.
    $conNombreIngles = @($carpetas | Where-Object {
        (Split-Path $_ -Leaf) -in @('Desktop', 'Documents', 'Downloads')
    })
    Write-Veredicto -Que 'hay carpetas con nombre ingles que preguntar: si no, esto no comprueba nada' `
        -Bien ($conNombreIngles.Count -eq 3) `
        -Detalle (($carpetas | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')

    $sinEspejo = @($conNombreIngles | Where-Object { -not (Test-CarpetaEspejo (Split-Path $_ -Leaf)) })
    Write-Veredicto -Que '[I18N-03] Test-CarpetaEspejo reconoce los nombres ingleses que dice cubrir' `
        -Bien ($sinEspejo.Count -eq 0) `
        -Detalle $(if ($sinEspejo.Count -eq 0) { 'Desktop, Documents y Downloads estan en la lista bilingue' }
                   else { ('no reconoce: {0}' -f (($sinEspejo | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')) })

    # Y las otras tres se miden y se ensenyan, sin gatillar. Es el dato que
    # hara falta si algun dia se decide anyadir "pictures", "music" y
    # "videos" a CarpetasEspejo.
    foreach ($carpeta in $carpetas) {
        $hoja = Split-Path $carpeta -Leaf
        Write-Host ('  NOTA   Test-CarpetaEspejo("{0}") = {1}' -f $hoja, (Test-CarpetaEspejo $hoja))
    }

    # La excepcion de [SEG-10]: "Download" es el ultimo segmento de la
    # cache de Windows Update, y sin la excepcion de la carpeta de Windows
    # el filtro de carpeta personal la vetaria y el modulo que "mas espacio
    # recupera" no propondria nunca nada. En un Windows en ingles el
    # choque es literal, asi que es aqui donde se ve.
    $cacheUpdate = Join-Path (Join-Path $env:SystemRoot 'SoftwareDistribution') 'Download'
    $motivo = Get-MotivoIntocable $cacheUpdate
    Write-Veredicto -Que '[I18N-03] la cache de Windows Update no queda vetada por llamarse Download' `
        -Bien ([string]::IsNullOrEmpty($motivo)) -Detalle ('{0} -> "{1}"' -f $cacheUpdate, $motivo)

    $documentos = Get-CarpetaConocida 'Documents'
    $personales = @(
        (Join-Path $documentos 'quarterly report.pdf')
        (Join-Path $documentos 'Document 3.tmp')
        (Join-Path $documentos 'invoice.xlsx')
    )
    $desprotegidos = @($personales | Where-Object { -not (Test-ArchivoPersonal $_) })
    Write-Veredicto -Que '[I18N-03] Test-ArchivoPersonal protege nombres en ingles' `
        -Bien ($desprotegidos.Count -eq 0) -Detalle ($desprotegidos -join ' | ')

    # --- [VIS-03] Dos nombres, un solo contenido ------------------------
    $duros = Join-Path $raiz '04-enlaces-duros'
    Write-Veredicto -Que 'esta la carpeta de enlaces duros' -Bien (Test-Path -LiteralPath $duros) `
        -Detalle $duros
    if (Test-Path -LiteralPath $duros) {
        $carpeta = [IO.DirectoryInfo]::new($duros)
        $ingenuo = Get-ResumenArbol -Carpeta $carpeta
        $real    = Get-ResumenArbol -Carpeta $carpeta -ContarEnlacesDuros

        # Las dos mediciones, no solo la buena. Con solo la buena, una
        # carpeta que por lo que sea tuviera 20 MB en vez de 40 pasaria la
        # prueba sin que el conteo de enlaces duros hubiera hecho nada:
        # seria otra vez una prueba que acierta por casualidad.
        Write-Veredicto -Que '[VIS-03] sin contar enlaces duros salen 40 MB' `
            -Bien ([Math]::Abs($ingenuo.Bytes - 40MB) -lt 1MB) `
            -Detalle ('{0:N0} bytes en {1} archivos' -f $ingenuo.Bytes, $ingenuo.Archivos)

        Write-Veredicto -Que '[VIS-03] contandolos salen 20 MB, no 40' `
            -Bien ([Math]::Abs($real.Bytes - 20MB) -lt 1MB) `
            -Detalle ('{0:N0} bytes, {1} archivos, {2} compartidos con otro nombre' -f `
                      $real.Bytes, $real.Archivos, $real.Compartidos)

        Write-Veredicto -Que '[VIS-03] el archivo compartido se reconoce como tal' `
            -Bien ([int]$real.Compartidos -eq 1) -Detalle ('Compartidos = {0}' -f $real.Compartidos)
    }

    # --- [COR-02] Una ruta de mas de 260 caracteres, de verdad ----------
    $cebo = Get-CebosBanco -ArchivosDeSobra $ArchivosDeSobra | Where-Object { $_.Id -eq 'ruta-larga' }
    $rutaLarga = Get-RutaCebo -Cebo $cebo -Raiz $raiz

    Write-Veredicto -Que '[COR-02] el cebo largo existe y Windows lo considera largo' `
        -Bien ((Test-RutaDemasiadoLarga -Ruta $rutaLarga) -and [IO.File]::Exists('\\?\' + $rutaLarga)) `
        -Detalle ('{0} caracteres' -f $rutaLarga.Length)
    if (-not [IO.File]::Exists('\\?\' + $rutaLarga)) { return }

    # Se mide desde la carpeta CORTA, que es el caso que arreglo [COR-02]:
    # "no es que la carpeta que se mide sea larga, es que sus DESCENDIENTES
    # pueden serlo". Get-ResumenArbol arranca el recorrido con el prefijo y
    # los hijos heredan la forma del padre. Sin el prefijo, EnumerateFiles
    # lanza PathTooLongException, el catch lo cuenta como inaccesible, y
    # esto daria cero sin un solo error por ninguna parte: exactamente el
    # fallo original, "medir de menos en silencio".
    $carpetaCorta = Join-Path $raiz '02-ruta-larga'
    $esperado = [double]([IO.FileInfo]::new('\\?\' + $rutaLarga).Length)
    $medido   = Measure-Ruta $carpetaCorta

    Write-Veredicto -Que '[COR-02] se mide un arbol cuyo unico archivo pasa de 260 caracteres' `
        -Bien ($medido -eq $esperado) `
        -Detalle ('{0} mide {1:N0} bytes; el cebo pesa {2:N0}' -f $carpetaCorta, $medido, $esperado)

    [void](Initialize-MotorBorrado)

    # Sin -Permanente: la papelera de Windows NO admite rutas largas. Lo
    # que exige [COR-02] es que eso se DIGA, no que se resuelva borrando
    # para siempre por nuestra cuenta: quien no marco borrado permanente
    # pidio poder arrepentirse.
    $script:UltimoError = ''
    $fue = Remove-Elemento -Ruta $rutaLarga -EsCarpeta $false -Confirm:$false
    Write-Veredicto -Que '[COR-02] una ruta larga NO se manda a la papelera a la brava' `
        -Bien ((-not $fue) -and [IO.File]::Exists('\\?\' + $rutaLarga)) `
        -Detalle ('devolvio {0}; el archivo {1}' -f $fue,
                  $(if ([IO.File]::Exists('\\?\' + $rutaLarga)) { 'sigue ahi' } else { 'HA DESAPARECIDO' }))

    # Se exige que el mensaje lleve la LONGITUD DE VERDAD, no solo que hable
    # de rutas largas. En este proyecto un mensaje salio con el "{0}"
    # literal en pantalla porque -f se enlaza mas fuerte que + y faltaban
    # unos parentesis, y la prueba que lo vigilaba no lo vio porque buscaba
    # un trozo del texto que estaba en las dos versiones. Comprobar el
    # numero es lo unico que distingue el mensaje bueno del roto.
    Write-Veredicto -Que '[COR-02] y se explica por que, con la longitud de verdad' `
        -Bien ($script:UltimoError.Contains([string]$rutaLarga.Length) -and
               $script:UltimoError.Contains('260') -and
               $script:UltimoError.Contains('papelera') -and
               -not $script:UltimoError.Contains('{0}')) `
        -Detalle ('"{0}"  (la ruta mide {1})' -f $script:UltimoError, $rutaLarga.Length)

    # Con -Permanente si se puede, via System.IO, que es la otra mitad del
    # arreglo. Se hace al final: a partir de aqui el cebo ya no esta.
    $script:UltimoError = ''
    $fue = Remove-Elemento -Ruta $rutaLarga -EsCarpeta $false -Permanente -Confirm:$false
    Write-Veredicto -Que '[COR-02] con borrado permanente si se borra' `
        -Bien ($fue -and -not [IO.File]::Exists('\\?\' + $rutaLarga)) `
        -Detalle ('devolvio {0}; error "{1}"' -f $fue, $script:UltimoError)
}

# ---------------------------------------------------------------------
#  FASE dosanalisis: dos analisis seguidos en el mismo proceso
# ---------------------------------------------------------------------
function Invoke-FaseDosAnalisis {
    <#
        La ventana comparte un runspace entre analisis, y nunca se habian
        hecho dos seguidos sin cerrar el programa. Aqui no hay ventana,
        pero si el ingrediente que importa: el mismo proceso, el nucleo
        cargado una sola vez, y los modulos ejecutados dos veces sobre el
        mismo disco. Lo que se caza es el estado que sobrevive de una
        pasada a la siguiente -una cache que no se invalida, una lista que
        se acumula, un modulo que se registra dos veces-, que se ve como
        una segunda pasada que da un numero distinto.

        Se saltan los modulos que piden administrador: son los que lanzan
        DISM, tardan minutos y no aportan nada a esta pregunta.
    #>
    [CmdletBinding()]
    param()

    $configuracion = Initialize-Comprobador
    $modulos = @(Get-ModulosLimpieza -Raiz $RaizProyecto | Where-Object { -not $_.RequiereAdmin })

    Write-Veredicto -Que 'hay modulos que ejecutar dos veces' -Bien ($modulos.Count -gt 0) `
        -Detalle ('{0} modulos sin permisos especiales' -f $modulos.Count)
    if ($modulos.Count -eq 0) { return }

    # Se cuenta POR MODULO y no solo el total. Con el total a secas, el dia
    # que esto discrepe el mensaje diria "1.412 y despues 1.411" y habria
    # que reproducirlo entero para saber de donde salio la diferencia. Con
    # el reparto, el propio registro del trabajo dice que modulo cambio y en
    # cuanto, que es lo unico que hara falta dentro de tres meses.
    $pasadas = @()
    foreach ($vuelta in 1, 2) {
        $sync = New-EstadoSincronizado
        $porModulo = [ordered]@{}
        $errores = [Collections.Generic.List[string]]::new()
        foreach ($modulo in $modulos) {
            $resultado = Invoke-ModuloLimpieza -Modulo $modulo -Configuracion $configuracion -Sync $sync
            if ($resultado.Error) { $errores.Add(('{0}: {1}' -f $modulo.Id, $resultado.Error)) }
            $porModulo[$modulo.Id] = @($resultado.Candidatos).Count
        }
        $cuenta = 0
        foreach ($valor in $porModulo.Values) { $cuenta += [int]$valor }

        $pasadas += [pscustomobject]@{
            Vuelta    = $vuelta
            Cuenta    = $cuenta
            PorModulo = $porModulo
            Errores   = @($errores)
            Memoria   = [GC]::GetTotalMemory($true)
        }
        Write-Host ('  pasada {0}: {1} candidatos, {2} modulos con error, {3:N0} bytes de memoria administrada' -f `
                    $vuelta, $cuenta, $errores.Count, [GC]::GetTotalMemory($true))
    }

    Write-Veredicto -Que 'la primera pasada encuentra algo' -Bien ($pasadas[0].Cuenta -gt 0) `
        -Detalle ('{0} candidatos repartidos en {1} modulos' -f $pasadas[0].Cuenta, $modulos.Count)

    $cambiados = [Collections.Generic.List[string]]::new()
    foreach ($id in $pasadas[0].PorModulo.Keys) {
        $antes   = [int]$pasadas[0].PorModulo[$id]
        $despues = [int]$pasadas[1].PorModulo[$id]
        if ($antes -ne $despues) { $cambiados.Add(('{0}: {1} -> {2}' -f $id, $antes, $despues)) }
    }
    Write-Veredicto -Que 'la segunda pasada encuentra lo mismo que la primera, modulo a modulo' `
        -Bien ($cambiados.Count -eq 0) `
        -Detalle $(if ($cambiados.Count -eq 0) { ('{0} candidatos las dos veces' -f $pasadas[0].Cuenta) }
                   else { $cambiados -join ' | ' })

    Write-Veredicto -Que 'ningun modulo falla en la segunda pasada habiendo ido bien en la primera' `
        -Bien ($pasadas[1].Errores.Count -le $pasadas[0].Errores.Count) `
        -Detalle (('primera: ' + (@($pasadas[0].Errores) -join ' | ')) + ' || ' +
                  ('segunda: ' + (@($pasadas[1].Errores) -join ' | ')))

    # La memoria NO gatilla. Un recolector de basura no promete nada sobre
    # cuando devuelve la memoria, asi que un umbral aqui seria un paso que
    # falla algunos dias. Se imprime, que es lo que hace falta para mirarlo
    # si alguna vez hay sospecha.
    Write-Host ('  NOTA   memoria administrada: {0:N0} -> {1:N0} bytes' -f `
                $pasadas[0].Memoria, $pasadas[1].Memoria)
}

# ---------------------------------------------------------------------
#  FASE inventario / simulacion / limpieza
# ---------------------------------------------------------------------
function Invoke-FaseInventario {
    <#
        Lista TODO lo que hay en las carpetas del usuario, que es donde
        mira el modulo de temporales. Se hace antes y despues de la
        limpieza real, y la resta es la unica forma honesta de saber que se
        borro: el informe dice lo que el programa CREE que hizo, y aqui lo
        que se quiere comprobar es justo eso.
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($Salida)) { throw 'Falta -Salida.' }

    $configuracion = Initialize-Comprobador
    $zonas = @($configuracion.ZonasUsuario)
    Write-Veredicto -Que 'hay zonas de usuario que inventariar' -Bien ($zonas.Count -gt 0) `
        -Detalle ($zonas -join ' | ')

    $todo = [Collections.Generic.List[string]]::new()
    foreach ($zona in $zonas) {
        foreach ($archivo in (Get-ArchivosDeVerdad -Carpeta $zona)) { $todo.Add($archivo) }
    }

    [IO.File]::WriteAllLines($Salida, @($todo | Sort-Object -Unique), [Text.UTF8Encoding]::new($false))
    Write-Host ('  {0} archivos inventariados en {1}' -f $todo.Count, $Salida)
}

function Invoke-FaseSimulacion {
    <#
        La red antes de borrar nada. El informe del analisis dice que viene
        MARCADO, y lo marcado es exactamente lo que "-Consola -Ejecutar"
        va a borrar. Si ahi hubiera algo que no es del banco, el paso se
        para AQUI, con el disco intacto.

        No es paranoia de agente efimero: el que borra en el agente es el
        mismo guion que se ejecuta en el equipo de una persona.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $Informe)) { throw "No esta el informe: $Informe" }

    $raiz = Get-RaizDelBanco
    $documento = Get-Content -Raw -LiteralPath $Informe | ConvertFrom-Json
    $marcados = @($documento.Candidatos |
                  Where-Object { $_.Seleccionado -and $_.Metodo -ne 'Informativo' })

    Write-Veredicto -Que 'hay algo marcado que borrar' -Bien ($marcados.Count -gt 0) `
        -Detalle ('{0} elementos vienen marcados' -f $marcados.Count)

    $fuera = Get-RutasFueraDelBanco -Rutas @($marcados | ForEach-Object { [string]$_.Ruta }) -Raiz $raiz
    Write-Veredicto -Que 'todo lo marcado esta dentro del banco' -Bien ($fuera.Count -eq 0) `
        -Detalle $(if ($fuera.Count -eq 0) { ('las {0} rutas cuelgan de {1}' -f $marcados.Count, $raiz) }
                   else { ('{0} fuera: {1}' -f $fuera.Count, (($fuera | Select-Object -First 20) -join ' | ')) })
}

function Invoke-FaseLimpieza {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $Antes))   { throw "No esta el inventario previo: $Antes" }
    if (-not (Test-Path -LiteralPath $Despues)) { throw "No esta el inventario posterior: $Despues" }

    $raiz = Get-RaizDelBanco
    $quedan = [Collections.Generic.HashSet[string]]::new(
        [string[]]@(Get-Content -LiteralPath $Despues), [StringComparer]::OrdinalIgnoreCase)
    $desaparecidas = @(@(Get-Content -LiteralPath $Antes) | Where-Object { -not $quedan.Contains($_) })

    Write-Veredicto -Que 'la limpieza real ha borrado algo' -Bien ($desaparecidas.Count -gt 0) `
        -Detalle ('han desaparecido {0} archivos' -f $desaparecidas.Count)

    $fuera = Get-RutasFueraDelBanco -Rutas $desaparecidas -Raiz $raiz
    Write-Veredicto -Que 'no ha desaparecido nada de fuera del banco' -Bien ($fuera.Count -eq 0) `
        -Detalle $(if ($fuera.Count -eq 0) { ('las {0} rutas borradas cuelgan de {1}' -f $desaparecidas.Count, $raiz) }
                   else { ('{0} fuera: {1}' -f $fuera.Count, (($fuera | Select-Object -First 20) -join ' | ')) })

    # Y lo contrario: lo que el catalogo dice que venia marcado tiene que
    # haberse ido. Sin esto, una limpieza que no borrara nada pasaria las
    # dos comprobaciones de arriba.
    $borradas = [Collections.Generic.HashSet[string]]::new(
        [string[]]$desaparecidas, [StringComparer]::OrdinalIgnoreCase)

    foreach ($cebo in (Get-CebosBanco -ArchivosDeSobra $ArchivosDeSobra)) {
        if (-not $cebo.Premarcado) { continue }

        # EnLimpieza es un campo APARTE de EnAnalisis, y hace falta desde
        # [COR-08]. El cebo de ruta larga ya se propone -esa es la mitad
        # que arreglo el punto- pero no puede desaparecer aqui: la fase
        # windows lo borro antes del inventario previo, y la limpieza real
        # va a la papelera, que no admite rutas de mas de 260 caracteres.
        # Con un solo campo, arreglar el recorrido habria puesto en rojo un
        # paso que esta bien, y la salida facil habria sido apagar tambien
        # la comprobacion del analisis, que es justo la que se acaba de
        # ganar.
        if (-not $cebo.EnAnalisis -or -not $cebo.EnLimpieza) {
            Write-Host ('  NOTA   el cebo {0} no se espera en la limpieza real' -f $cebo.Id)
            Write-Host ('         {0}' -f $cebo.MotivoFuera) -ForegroundColor DarkGray
            continue
        }

        $siguen = [Collections.Generic.List[string]]::new()
        for ($n = 1; $n -le [int]$cebo.Cuantos; $n++) {
            $ruta = Get-RutaCebo -Cebo $cebo -Raiz $raiz -Indice $n
            if (-not $borradas.Contains($ruta)) { $siguen.Add($ruta) }
        }
        Write-Veredicto -Que ('el cebo premarcado {0} se ha borrado entero' -f $cebo.Id) `
            -Bien ($siguen.Count -eq 0) `
            -Detalle ('siguen {0} de {1}{2}' -f $siguen.Count, $cebo.Cuantos,
                      $(if ($siguen.Count -gt 0) { ': ' + (($siguen | Select-Object -First 5) -join ' | ') } else { '' }))
    }
}

# ---------------------------------------------------------------------
#  Ejecucion
# ---------------------------------------------------------------------

Write-Host ''
Write-Host ('=== Banco de pruebas: fase {0} ===' -f $Fase) -ForegroundColor Cyan

switch ($Fase) {
    'montaje'     { Invoke-FaseMontaje }
    'analisis'    { Invoke-FaseAnalisis }
    'windows'     { Invoke-FaseWindows }
    'dosanalisis' { Invoke-FaseDosAnalisis }
    'inventario'  { Invoke-FaseInventario }
    'simulacion'  { Invoke-FaseSimulacion }
    'limpieza'    { Invoke-FaseLimpieza }
}

Write-Host ''
if ($script:Fallos.Count -gt 0) {
    Write-Host ('{0} comprobaciones han fallado:' -f $script:Fallos.Count) -ForegroundColor Red
    foreach ($fallo in $script:Fallos) { Write-Host ('  - {0}' -f $fallo) -ForegroundColor Red }
    exit 1
}
Write-Host 'Todo lo comprobado en esta fase cuadra.' -ForegroundColor Green
exit 0
