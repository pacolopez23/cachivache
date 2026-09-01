<#
.SYNOPSIS
    Motor de eliminación. Todo borrado del programa pasa por aquí.

.DESCRIPTION
    Principios:
      * Nada se borra sin revalidar la guardia justo antes del borrado.
      * Por defecto se manda a la papelera; el borrado permanente es opt-in,
        salvo que el candidato declare ForzarPermanente (solo módulos de
        cache genuina: ver New-Candidato en Candidate.ps1).
      * Se mide antes y después para informar del espacio REAL liberado,
        en vez de dar por bueno el tamaño estimado en el análisis.
      * Un fallo en un elemento nunca aborta el resto de la eliminación.
#>

$script:UltimoError = ''

# Métodos que vacian el CONTENIDO de una carpeta y la dejan en su sitio,
# a diferencia de 'Ruta' (borra el todo), 'Papelera', 'Comando' e
# 'Informativo'. Solo estos necesitan la pequeña espera antes de
# remedir: son los únicos donde el contenedor sigue existiendo. Ver
# [R-01] en docs/OPTIMIZACIONES.md.
$script:MetodosQueVacianContenido = @('Contenido', 'FirefoxCache', 'Miniaturas')

# Métodos que limpian solo UNA PARTE de lo que hay bajo su ruta, y por tanto
# dejan cosas atras a propósito: FirefoxCache vacía únicamente las carpetas
# cache2 de cada perfil (marcadores, cookies e historial se quedan) y
# Miniaturas borra solo los thumbcache_*.db de la carpeta del Explorador.
# Para estos no tiene sentido avisar de que "queda algo" al terminar. Ver
# [C-06] en docs/OPTIMIZACIONES.md.
$script:MetodosParciales = @('FirefoxCache', 'Miniaturas')

# =====================================================================
#  QUE SE PUEDE RECUPERAR Y QUE NO  ([CNF-03])
# =====================================================================
#
# Todo va a la papelera por defecto, que es el acierto de fondo del
# programa. Pero el usuario no lo sabe: al terminar una limpieza no se le
# decia si lo borrado se podia rescatar, asi que la red de seguridad
# existia y no servia de nada.
#
# Antes de ofrecer nada hay que ser exacto sobre el alcance, porque
# prometer de mas aqui es peor que no prometer nada: alguien confiaria en
# poder deshacer algo que no se puede deshacer.
#
#   RECUPERABLE   Lo que de verdad fue a la papelera de Windows. Se puede
#                 restaurar desde ahi, y solo mientras no se vacie.
#   IRREVERSIBLE  Vaciar la papelera (Papelera), lanzar un comando externo
#                 como DISM o "docker system prune" (Comando), y lo que
#                 no toca nada (Informativo).
#
# Y encima de eso mandan dos banderas: el borrado permanente que pide el
# usuario y ForzarPermanente, que declaran los modulos de cache genuina.
# Con cualquiera de las dos, NADA es recuperable.
#
# Las dos listas se declaran ENTERAS, no una como "todo lo que no es la
# otra": asi, cuando alguien anyada un metodo nuevo, tendra que decidir a
# cual pertenece, y si no lo hace la prueba de [COR-04] falla. Un metodo
# sin clasificar acabaria contado como recuperable por descarte, que es
# justo la promesa que no se puede fallar.
$script:MetodosRecuperables  = @('Contenido', 'Ruta', 'CarpetaVacia', 'FirefoxCache', 'Miniaturas')
$script:MetodosIrreversibles = @('Papelera', 'Comando', 'Informativo')

function Test-CandidatoRecuperable {
    <#
    .SYNOPSIS
        ¿Se podria rescatar esto de la papelera despues de borrarlo?

    .DESCRIPTION
        CALCULO PURO sobre el candidato y el modo de borrado. No mira el
        disco: se puede probar aqui, que para una promesa de este tipo no
        es un detalle.

    .PARAMETER Permanente
        El borrado permanente que ha pedido el usuario para todo el lote.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # AllowNull, por tercera vez en este proyecto: sin el, el enlace de
        # parametros rechaza el nulo ANTES de llegar a la guarda de abajo y
        # esa guarda se queda de adorno. Get-DetalleExcepcion y
        # Test-CabeEnPapelera cayeron en lo mismo, y las tres veces lo cazo
        # la prueba "no revienta con un nulo".
        [Parameter(Mandatory)] [AllowNull()] $Candidato,
        [switch] $Permanente
    )

    if ($null -eq $Candidato) { return $false }
    if ($Permanente) { return $false }
    if ([bool]$Candidato.ForzarPermanente) { return $false }

    return ($script:MetodosRecuperables -contains [string]$Candidato.Metodo)
}

function Get-ResumenRecuperable {
    <#
    .SYNOPSIS
        De un lote ya borrado, cuantos elementos se pueden rescatar y
        cuantos no.

    .DESCRIPTION
        Solo cuenta lo que de verdad se borro (Hecho): prometer que se
        puede recuperar algo que ni siquiera se toco seria otra forma de
        decir lo que no es.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Candidatos,
        [switch] $Permanente
    )

    $recuperables = 0
    $definitivos  = 0
    foreach ($candidato in @($Candidatos)) {
        if (-not $candidato.Hecho) { continue }
        if (Test-CandidatoRecuperable -Candidato $candidato -Permanente:$Permanente) {
            $recuperables++
        } else {
            $definitivos++
        }
    }

    return [pscustomobject]@{
        Recuperables = $recuperables
        Definitivos  = $definitivos
    }
}

function Initialize-MotorBorrado {
    <#
    .SYNOPSIS
        Carga el ensamblado necesario para enviar a la papelera.
    #>
    [CmdletBinding()]
    param()
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Remove-Elemento {
    <#
    .SYNOPSIS
        Primitiva única de borrado: papelera o permanente, archivo o carpeta.
    .DESCRIPTION
        Todo borrado real del programa pasa por aquí: tanto Remove-RutaSegura
        como cada hoja que vacía Clear-ContenidoCarpeta. Antes vivian dos
        copias de esta misma lógica y una de ellas ignoraba -Permanente por
        completo (ver CHANGELOG / docs/OPTIMIZACIONES.md, C-01). Unificarla
        en un solo sitio hace imposible que las dos rutas de borrado vuelvan
        a divergir.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [Parameter(Mandatory)] [bool]   $EsCarpeta,
        [switch] $Permanente
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Eliminar')) { return $false }

    # ---- Rutas de mas de 260 caracteres ([COR-02]) ---------------------
    #
    # Dos caminos distintos porque las dos APIs se comportan distinto:
    #
    #   - System.IO SI admite el prefijo "\\?\", asi que el borrado
    #     permanente de una ruta larga funciona.
    #   - Microsoft.VisualBasic.FileIO, que es quien manda a la papelera,
    #     NO lo admite: valida y normaliza la ruta por su cuenta.
    #
    # O sea que una ruta larga se puede borrar para siempre pero no se
    # puede mandar a la papelera. Y eso hay que DECIRLO, no resolverlo por
    # nuestra cuenta borrandola permanentemente: el usuario que no marco
    # borrado permanente pidio poder arrepentirse. Es la misma regla que
    # [COR-01].
    $esLarga = Test-RutaDemasiadoLarga -Ruta $Ruta

    if ($esLarga -and -not $Permanente) {
        # OJO con los parentesis: -f tiene MAS precedencia que +, asi que
        # sin ellos esto formatea solo la segunda cadena y el {0} de la
        # primera sale literal en pantalla. Paso de verdad, y las pruebas
        # no lo vieron porque buscaban un trozo del texto que si estaba.
        $script:UltimoError = (
            ('La ruta tiene {0} caracteres y Windows no puede mandar a la papelera nada que pase de 260. ' +
             'Marca el borrado permanente si quieres eliminarlo.') -f $Ruta.Length)
        return $false
    }

    try {
        if ($Permanente) {
            # System.IO en vez de Remove-Item CUANDO la ruta es larga: el
            # proveedor de archivos de PowerShell 5.1 no soporta el
            # prefijo, y era el que fallaba. Para las rutas normales se
            # sigue usando Remove-Item, que entiende de proveedores y de
            # rutas relativas y lleva funcionando desde el principio: no
            # se cambia lo que ya va bien.
            if ($esLarga) {
                $larga = ConvertTo-RutaLarga -Ruta $Ruta
                if ($EsCarpeta) { [IO.Directory]::Delete($larga, $true) }
                else            { [IO.File]::Delete($larga) }
                return $true
            }

            if ($EsCarpeta) {
                Remove-Item -LiteralPath $Ruta -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $Ruta -Force -ErrorAction Stop
            }
            return $true
        }

        if ($EsCarpeta) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Ruta,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
                [Microsoft.VisualBasic.FileIO.UICancelOption]::DoNothing)
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Ruta,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
                [Microsoft.VisualBasic.FileIO.UICancelOption]::DoNothing)
        }
        return $true
    } catch {
        $script:UltimoError = $_.Exception.Message
        return $false
    }
}

function Get-MotivoNoSeBorra {
    <#
    .SYNOPSIS
        ¿Hay alguna razon para NO borrar esto? Devuelve la frase que hay
        que ensenyar, o cadena vacia si se puede borrar.

    .DESCRIPTION
        Existe para que el borrado real y la SIMULACION tomen la misma
        decision. Estaba escrito solo dentro de Invoke-EliminacionCandidato,
        asi que la simulacion no pasaba por aqui y prometia borrar cosas
        que la ejecucion de verdad habria rechazado. Una prevision que no
        coincide con lo que va a pasar no sirve para decidir, y decidir es
        para lo unico que existe la simulacion.

        Es la misma leccion de [ARQ-01]: dos caminos que deciden lo mismo
        acaban decidiendo cosas distintas en cuanto uno de los dos se toca.

    .PARAMETER Bytes
        Tamaño ya medido. Se pasa desde fuera porque quien llama lo tiene,
        y medir dos veces un arbol de miles de archivos se nota.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Candidato,
        [Parameter(Mandatory)] [double] $Bytes,
        [switch] $Permanente
    )

    # [VIS-04]. SEGUNDO CORTE, y es defensa en profundidad a proposito.
    #
    # El embudo ya deberia haber tirado cualquier candidato de una unidad
    # extraible, asi que en teoria esto no salta nunca. Se pone igual
    # porque el embudo depende de que la configuracion traiga la lista de
    # unidades con su clase, y hay un camino donde puede no traerla: un
    # disco enchufado DESPUES de arrancar no esta en esa lista hasta que
    # alguien refresca. Ahi el embudo deja pasar -su regla es permisiva
    # ante lo que no conoce, y hace bien- y quien tiene que decir que no
    # es este sitio, que ya tiene la ruta delante.
    #
    # Y aqui la respuesta llega ademas al usuario: esta funcion devuelve la
    # frase que se ensenya, y la comparten el borrado real y la simulacion.
    if ($Candidato.Metodo -notin @('Informativo', 'Papelera', 'Comando')) {
        $clase = Get-ClaseDeUnidad -Tipo (Get-TipoDeUnidad -Ruta $Candidato.Ruta)
        if ($clase -ne 'desconocida' -and -not (Test-PuedeProducirCandidatoBorrable -Clase $clase)) {
            return (Get-MotivoNoBorrableEnUnidad -Clase $clase `
                        -Letra (Get-LetraUnidad -Ruta $Candidato.Ruta))
        }
    }

    # Si el usuario NO ha pedido borrado permanente, ha pedido poder
    # arrepentirse. Cuando algo no cabe en la papelera, Windows lo borra
    # para siempre sin avisar y devolviendo exito: cumplir la orden al pie
    # de la letra seria destruir justo lo que se pidio conservar, y encima
    # anotarlo como PAPELERA. Se para y se explica, en vez de borrar y
    # avisar despues; avisar despues no devuelve el archivo. Ver [COR-01].
    if (-not $Permanente -and $Candidato.Metodo -in @('Ruta', 'CarpetaVacia')) {
        $veredicto = Test-IraAPapelera -Ruta $Candidato.Ruta -Bytes $Bytes
        if (-not $veredicto.Cabe) {
            # Los parentesis alrededor de la concatenacion son
            # imprescindibles: ver la nota en Remove-Elemento.
            return (('No iria a la papelera sino a la nada: {0}. No se ha borrado. ' +
                     'Si aun asi quieres eliminarlo, marca el borrado permanente.') -f $veredicto.Motivo)
        }
    }

    return ''
}

function Remove-RutaSegura {
    <#
    .SYNOPSIS
        Borra un archivo o una carpeta entera, con revalidación previa.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [switch] $Permanente,
        [switch] $PermitirPersonales
    )

    if (Test-RutaIntocable $Ruta) { return $false }

    $item = Get-Item -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue
    if ($null -eq $item)     { return $false }
    if (Test-EsEnlace $item) { return $false }
    if (-not $PermitirPersonales -and
        -not $item.PSIsContainer -and
        (Test-ArchivoPersonal $item.FullName)) { return $false }

    # Test-EsEnlace mira la RAIZ. Para una carpeta hay que mirar también
    # dentro, porque lo que viene después es un borrado recursivo y en
    # Windows PowerShell 5.1 -que este programa declara soportar- el
    # proveedor de archivos DESCIENDE por los enlaces y las uniones al
    # recorrer con -Recurse: se borraria el contenido del destino, no el
    # enlace. Y no es un caso raro precisamente aquí: pnpm construye
    # node_modules casi entero a base de enlaces simbolicos, y npm crea
    # uniones para las dependencias locales y para .bin. En un repositorio
    # con varios paquetes, node_modules apunta a las carpetas de código
    # fuente hermanas.
    #
    # Ante un arbol con enlaces dentro no se borra: se rechaza y que lo
    # decida quien pueda mirarlo. Perder código fuente por limpiar una
    # carpeta regenerable no tiene arreglo posible.
    #
    # Y se busca con Get-ElementosDelArbol, no con Get-ChildItem -Recurse.
    # La comprobacion se paraba a los 260 caracteres sin decir nada, pero el
    # borrado que viene despues NO se para -desde [COR-02] usa System.IO con
    # prefijo-, asi que una union por debajo de esa profundidad no se veia y
    # se borraba igual. Una guardia que mira menos que la accion que
    # protege es peor que no tenerla, porque parece que protege.
    # -IncluirEnlaces es imprescindible: por defecto el recorrido no los
    # devuelve, y aqui son justamente lo que se busca. Ver [COR-08].
    if ($item.PSIsContainer) {
        $enlaceDentro = @(Get-ElementosDelArbol -Ruta $Ruta -Que Todo -IncluirEnlaces |
                          Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
                          Select-Object -First 1)
        if ($enlaceDentro.Count -gt 0) {
            $script:UltimoError = "No se ha tocado: contiene enlaces a otras carpetas (por ejemplo $($enlaceDentro[0].FullName)) y un borrado recursivo podria llevarse lo que hay al otro lado."
            return $false
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Eliminar')) { return $false }

    return Remove-Elemento -Ruta $Ruta -EsCarpeta $item.PSIsContainer -Permanente:$Permanente -Confirm:$false
}

function Invoke-LoteEliminacion {
    <#
    .SYNOPSIS
        Elimina una lista de candidatos y devuelve el resumen de lo que de
        verdad se hizo.

    .DESCRIPTION
        Este bucle existia DOS VECES: en la consola y dentro de una cadena
        de texto que se ejecuta en el runspace de la ventana. Ya habian
        divergido una vez.

        El coste de esa duplicacion no es escribir dos veces lo mismo: es
        que una de las dos copias es TEXTO dentro de una cadena, invisible
        para el analizador estatico y para las pruebas. Cualquier arreglo
        del borrado -contar bien lo hecho, respetar una exclusion, anotar
        el nivel correcto en el registro- habia que acordarse de hacerlo
        en un sitio que ninguna herramienta mira.

        Aqui esta una sola vez, y las dos la llaman.
        Ver [ARQ-01] en docs/HOJA-DE-RUTA.md.

    .PARAMETER Candidatos
        Los que se van a eliminar. Se mutan: cada uno acaba con Hecho,
        BytesLiberados y Error puestos.
    .PARAMETER Simular
        No borra NADA: recorre la lista, mide lo que se liberaria y lo
        anota, para poder ver exactamente que haria el programa antes de
        dejarle hacerlo.

        Es lo que convierte la primera ejecucion en un equipo real en algo
        sin consecuencias. Un limpiador que solo se puede probar borrando
        no se prueba: se estrena. Ver [CNF-02] en docs/HOJA-DE-RUTA.md.

    .PARAMETER AlProgresar
        Cierre opcional que se invoca despues de cada elemento, con el
        candidato y el recuento. Es lo unico que cambia entre la consola
        -que escribe una linea- y la ventana -que actualiza una barra-.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] $Candidatos,
        [switch] $Permanente,
        [switch] $Simular,
        $Configuracion = $null,
        $Sync = $null,
        [scriptblock] $AlProgresar = $null
    )

    $liberado = 0.0
    $hechos   = 0
    $conError = 0
    $simulados = 0
    # Los que la simulacion dice que NO se borrarian. Se cuentan
    # aparte de $simulados para que el resumen pueda distinguir
    # "se habrian borrado 32" de "y uno no". Ver [CNF-02].
    $bloqueados = 0
    $total    = @($Candidatos).Count

    foreach ($candidato in @($Candidatos)) {
        if ($null -eq $candidato) { continue }
        if (Test-Cancelacion $Sync) { break }

        # --- Simulacion: se mide y se anota, no se toca nada ----------
        if ($Simular) {
            # Se mide AHORA, no se reutiliza el tamaño del analisis: entre
            # una cosa y otra la carpeta ha podido crecer o encoger, y el
            # numero que se ensenya tiene que ser el de este momento.
            $tamano = Measure-Ruta $candidato.Ruta
            if ($tamano -le 0) { $tamano = [double]$candidato.Bytes }

            # La simulacion pasa por LA MISMA comprobacion que el borrado
            # real. Antes no lo hacia, y el resultado era una simulacion
            # que mentia: decia "se borraria 9,52 GB" de un archivo que en
            # la ejecucion de verdad se habria rechazado por no caber en la
            # papelera. Una prevision que no coincide con lo que va a pasar
            # no sirve para decidir, que es lo unico para lo que existe
            # este modo. Ver [CNF-02] y [COR-01].
            $permanenteSim = [bool]$Permanente -or [bool]$candidato.ForzarPermanente
            $motivo = Get-MotivoNoSeBorra -Candidato $candidato -Bytes $tamano -Permanente:$permanenteSim
            if (-not [string]::IsNullOrEmpty($motivo)) {
                $bloqueados++
                $candidato.Hecho = $false
                $candidato.BytesLiberados = 0
                Write-Registro -Sync $Sync -Nivel 'BLOQUEADO' -Mensaje (
                    'NO se borraria: {0} -> {1}' -f $candidato.Ruta, $motivo)

                if ($null -ne $AlProgresar) {
                    & $AlProgresar $candidato ([pscustomobject]@{
                        Hechos = $hechos; ConError = $conError
                        Liberado = $liberado; Total = $total; Simulados = $simulados
                    })
                }
                continue
            }

            $liberado += $tamano
            $simulados++
            $candidato.Hecho = $false
            $candidato.BytesLiberados = 0

            Write-Registro -Sync $Sync -Nivel 'SIMULACION' -Mensaje (
                'Se borraria: {0} -> {1}' -f $candidato.Ruta, (Format-Tamano $tamano))

            if ($null -ne $AlProgresar) {
                & $AlProgresar $candidato ([pscustomobject]@{
                    Hechos = $hechos; ConError = $conError
                    Liberado = $liberado; Total = $total; Simulados = $simulados
                })
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($candidato.Ruta, 'Eliminar')) { continue }

        $liberado += Invoke-EliminacionCandidato -Candidato $candidato `
                                                 -Permanente:$Permanente `
                                                 -Sync $Sync `
                                                 -Configuracion $Configuracion -Confirm:$false

        # Se cuenta lo que de VERDAD se hizo. Contar siempre hacia que
        # "N elementos eliminados" sobrecontara, y ese N acababa en el
        # historial. Ver [SEG-20].
        if ($candidato.Hecho) { $hechos++ } else { $conError++ }

        # Una linea por elemento: el registro tiene que servir para
        # auditar exactamente que se borro. El nivel dice lo que paso de
        # verdad -las caches se borran siempre de forma permanente, asi
        # que anotarlas como PAPELERA seria mentir en el archivo de
        # auditoria- y lo que fallo se anota como ERROR.
        $nivel = if ($candidato.Error) { 'ERROR' }
                 elseif ($Permanente -or $candidato.ForzarPermanente) { 'BORRADO' }
                 else { 'PAPELERA' }
        $sufijo = if ($candidato.Error) { " (no se hizo: $($candidato.Error))" } else { '' }
        Write-Registro -Sync $Sync -Nivel $nivel -Mensaje (
            '{0} -> {1}{2}' -f $candidato.Ruta, (Format-Tamano $candidato.BytesLiberados), $sufijo)

        if ($null -ne $AlProgresar) {
            & $AlProgresar $candidato ([pscustomobject]@{
                Hechos = $hechos; ConError = $conError
                Liberado = $liberado; Total = $total; Simulados = $simulados
            })
        }
    }

    return [pscustomobject]@{
        Hechos    = $hechos
        ConError  = $conError
        Liberado  = $liberado
        Total     = $total
        # Cuantos se han contado sin tocarlos. Si es mayor que cero, el
        # numero de Liberado es lo que SE HABRIA liberado, no lo liberado.
        Simulados = $simulados
        Bloqueados = $bloqueados
        Simulado  = [bool]$Simular
    }
}

function Clear-ContenidoCarpeta {
    <#
    .SYNOPSIS
        Vacía una carpeta dejandola en su sitio.
    .DESCRIPTION
        Muchos programas fallan si desaparece su carpeta de cache, así que
        se borra elemento a elemento y el contenedor sobrevive. Los archivos
        en uso lanzan excepción y simplemente se saltan.

    .PARAMETER EsCache
        Levanta el veto por EXTENSIÓN personal dentro de esta carpeta.

        El veto existe para que vaciar algo no se lleve por delante un
        documento del usuario, y fuera de una cache es imprescindible. Pero
        dentro de una cache declarada hacia mas mal que bien: '.db',
        '.txt', '.md' y '.csv' estan en la lista de extensiones personales,
        y una cache de navegador o de aplicacion es en su mayor parte
        SQLite, o sea archivos '.db'. Resultado: el programa anunciaba
        "se liberan 600 MB", saltaba casi todo, liberaba una fraccion, y
        despues culpaba a "archivos en uso por algún programa abierto",
        que ademas era falso. Prometer una cosa y hacer otra es peor que
        no ofrecerla.

        Solo lo activan los candidatos de cache GENUINA -los mismos que ya
        declaran ForzarPermanente, y por el mismo motivo: son rutas cuyo
        contenido entero lo regenera el programa que las creo-. El resto de
        protecciones no se toca: la guardia sigue vetando rutas intocables,
        los enlaces se siguen saltando y los nombres de basura conocida
        siguen decidiendose igual. Ver [FAL-15] en docs/PLAN-ACCION.md.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [switch] $Permanente,
        [switch] $EsCache,
        [int]    $Profundidad = 0
    )

    if (Test-RutaIntocable $Ruta) { return }
    if ($Profundidad -gt 32) {
        # Cortafuegos anti bucle. Abandonaba EN SILENCIO: la carpeta se
        # quedaba a medio vaciar y el mensaje final culpaba a "archivos en
        # uso por algún programa abierto", que es falso y manda al usuario
        # a cerrar programas que no tienen nada que ver. Ver [SEG-23].
        $script:UltimoError = "Se ha alcanzado el límite de 32 niveles de anidamiento en ${Ruta}: el resto no se ha tocado."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Vaciar contenido')) { return }

    foreach ($hijo in @(Get-ChildItem -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue)) {
        if (Test-EsEnlace $hijo)             { continue }
        if (Test-RutaIntocable $hijo.FullName) { continue }
        if (-not $EsCache -and -not $hijo.PSIsContainer -and (Test-ArchivoPersonal $hijo.FullName)) { continue }

        try {
            if ($hijo.PSIsContainer) {
                Clear-ContenidoCarpeta -Ruta $hijo.FullName -Permanente:$Permanente -EsCache:$EsCache `
                                       -Profundidad ($Profundidad + 1) -Confirm:$false
                $restante = @(Get-ChildItem -LiteralPath $hijo.FullName -Force -ErrorAction SilentlyContinue)
                if ($restante.Count -eq 0) {
                    [void](Remove-Elemento -Ruta $hijo.FullName -EsCarpeta $true -Permanente:$Permanente -Confirm:$false)
                }
            } else {
                [void](Remove-Elemento -Ruta $hijo.FullName -EsCarpeta $false -Permanente:$Permanente -Confirm:$false)
            }
        } catch {
            $script:UltimoError = $_.Exception.Message
        }
    }
}

function Clear-CacheFirefox {
    <#
    .SYNOPSIS
        Vacía únicamente las carpetas cache2 de cada perfil de Firefox.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [switch] $Permanente
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Vaciar caché de Firefox')) { return }
    foreach ($perfil in @(Get-ChildItem -LiteralPath $Ruta -Directory -Force -ErrorAction SilentlyContinue)) {
        $cache = Join-Path $perfil.FullName 'cache2'
        if (Test-Path -LiteralPath $cache) {
            Clear-ContenidoCarpeta -Ruta $cache -Permanente:$Permanente -Confirm:$false
        }
    }
}

function Clear-Miniaturas {
    <#
    .SYNOPSIS
        Borra las bases de datos de miniaturas e iconos del Explorador.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [switch] $Permanente
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Borrar miniaturas')) { return }
    Get-ChildItem -LiteralPath $Ruta -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(thumbcache|iconcache)_.*\.db$' -and -not (Test-EsEnlace $_) } |
        ForEach-Object {
            [void](Remove-Elemento -Ruta $_.FullName -EsCarpeta $false -Permanente:$Permanente -Confirm:$false)
        }
}

function Clear-Papelera {
    <#
    .SYNOPSIS
        Vacía la papelera de reciclaje mediante la API del shell.
    .DESCRIPTION
        Se usa Clear-RecycleBin cuando existe (Windows 10+). En equipos
        antiguos se recurre a SHEmptyRecycleBin a traves de P/Invoke.

        Vacía EXACTAMENTE las unidades que se le pasen, y todas si no se le
        pasa ninguna. Esto no es un detalle: el módulo 'papelera' mide solo
        las unidades que el usuario tiene marcadas, así que vaciar de más
        borraria cosas de un disco que el usuario había excluido a
        propósito, y vaciar de menos dejaria al usuario con menos espacio
        del que el programa le acababa de prometer. Se vacía lo que se
        midio, ni más ni menos.

        (Historia útil: este parámetro existio, no lo pasaba nadie y se
        borro por inalcanzable en [C-21]. Vuelve ahora con un llamante de
        verdad, que es la selección de unidades de la interfaz.)
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string[]] $Unidades = @())

    if (-not $PSCmdlet.ShouldProcess('Papelera de reciclaje', 'Vaciar')) { return $false }

    $letras = @($Unidades | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('\').TrimEnd(':') })

    if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
        $fallos = 0
        try {
            if ($letras.Count -gt 0) {
                foreach ($letra in $letras) {
                    # Una unidad sin papelera, o sin permisos, no debe
                    # abortar el resto: se anota y se sigue.
                    try { Clear-RecycleBin -DriveLetter $letra -Force -ErrorAction Stop }
                    catch { $fallos++; $script:UltimoError = $_.Exception.Message }
                }
            } else {
                Clear-RecycleBin -Force -ErrorAction Stop
            }
            # Antes se devolvia $true pase lo que pase: si fallaba vaciar
            # una unidad, el error se anotaba y nadie lo leia, así que el
            # candidato quedaba marcado como hecho y el usuario veia
            # "eliminado" sobre algo que seguia ahi.
            return ($fallos -eq 0)
        } catch {
            $script:UltimoError = $_.Exception.Message
            return $false
        }
    }

    try {
        if (-not ('Cachivache.Shell32' -as [type])) {
            Add-Type -Namespace 'Cachivache' -Name 'Shell32' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SHEmptyRecycleBin(System.IntPtr hwnd, string pszRootPath, uint dwFlags);
'@ -ErrorAction Stop
        }

        # pszRootPath por unidad, no $null. Con $null la API vacía TODAS
        # las papeleras del equipo, incluidas las de los discos que el
        # usuario había desmarcado a propósito: exactamente lo contrario de
        # lo que promete la cabecera de esta función. Se pasaba $null
        # siempre, también cuando llegaban unidades concretas.
        $rutas = if ($letras.Count -gt 0) { @($letras | ForEach-Object { "$_`:\" }) } else { @($null) }

        $fallos = 0
        foreach ($raiz in $rutas) {
            # 0x1 sin confirmación | 0x2 sin animacion | 0x4 sin sonido
            $hr = [Cachivache.Shell32]::SHEmptyRecycleBin([IntPtr]::Zero, $raiz, 0x7)
            # 0 = S_OK. 0x8000FFFF (E_UNEXPECTED) es lo que devuelve cuando
            # la papelera ya estaba vacía: no es un fallo.
            if ($hr -ne 0 -and $hr -ne -2147418113) {
                $fallos++
                $script:UltimoError = 'SHEmptyRecycleBin ha devuelto 0x{0:X8} para {1}.' -f $hr, $(if ($raiz) { $raiz } else { 'todas las unidades' })
            }
        }
        return ($fallos -eq 0)
    } catch {
        $script:UltimoError = $_.Exception.Message
        return $false
    }
}

function Invoke-EliminacionCandidato {
    <#
    .SYNOPSIS
        Ejecuta la eliminación de un candidato y devuelve los bytes reales
        liberados.

    .DESCRIPTION
        Este es el único punto del programa que borra datos del usuario.
        Antes de tocar nada revalida la guardia contra las raices que
        declaro el módulo, de modo que un candidato manipulado o caducado
        no puede colarse.
    .PARAMETER Sync
        La tabla sincronizada de New-EstadoSincronizado, si la hay. Se
        reenvia tal cual a Write-Registro: sin ella, en modo consola, se
        escribe al momento; con ella, se encola para que el temporizador
        de la interfaz la vacie. Ver [C-19] en docs/OPTIMIZACIONES.md.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] $Candidato,
        [switch] $Permanente,
        $Sync = $null,
        # Opcional. Hoy solo lo usa el método 'Papelera', para vaciar
        # únicamente las unidades que el usuario tiene marcadas. Sin ella
        # se vacian todas, que es el comportamiento de siempre.
        $Configuracion = $null
    )

    $script:UltimoError = ''
    $Candidato.Error = ''

    if ($Candidato.Metodo -eq 'Informativo') {
        $Candidato.Error = 'Este elemento solo informa: no se borra nada.'
        return 0.0
    }

    if ($Candidato.Metodo -eq 'Papelera') {
        $antes = Measure-Ruta $Candidato.Ruta
        # Se vacian exactamente las unidades que el módulo midio.
        $unidadesPapelera = @()
        if ($null -ne $Configuracion -and $Configuracion.PSObject.Properties['UnidadesSeleccionadas']) {
            $unidadesPapelera = @($Configuracion.UnidadesSeleccionadas)
        }
        if (-not (Clear-Papelera -Unidades $unidadesPapelera -Confirm:$false)) {
            $Candidato.Error = $script:UltimoError
            return 0.0
        }
        $Candidato.Hecho = $true
        $liberado = $antes - (Measure-Ruta $Candidato.Ruta)
        if ($liberado -lt 0) { $liberado = 0 }
        $Candidato.BytesLiberados = $liberado
        return $liberado
    }

    # 'Comando' no tiene una ruta que exigir ni que validar contra la
    # guardia: su seguridad viene de la lista blanca de ejecutables (ver
    # Resolve-EjecutablePermitido), no del modelo de rutas. Además su
    # campo Ruta puede no ser una ruta real en absoluto (por ejemplo,
    # "docker system prune" es solo una etiqueta): antes de esta excepción,
    # Test-Path fallaba siempre para ese candidato en concreto y el
    # comando de Docker NUNCA llegaba a ejecutarse. Coherente con el mismo
    # criterio que ya aplicaba ModuleRegistry.ps1 al filtrar candidatos
    # tras el análisis ($sinRuta). Ver [C-03] en docs/OPTIMIZACIONES.md.
    # La exclusion del usuario se revalida AQUI, no solo al analizar. El
    # borrado corre en otro runspace y puede pasar tiempo entre una cosa y
    # otra: una exclusion que solo se aplicara en el analisis seria una
    # promesa que el motor no tiene por que cumplir. Ver [CNF-01].
    #
    # Y va FUERA del "if Metodo -ne Comando", que es donde estaba. Dentro,
    # un comando excluido por el usuario pasaba el analisis filtrado pero
    # NO se revalidaba antes de ejecutarse: la unica clase de candidato que
    # lanza un binario externo era justo la que se saltaba la comprobacion.
    # No llegaba a ocurrir porque el filtro del analisis ya lo quitaba,
    # pero la revalidacion existe precisamente para no depender de eso.
    # Encontrado al hacer [ARQ-03].
    #
    # Por ClaveExclusion y no por Ruta: un comando no tiene ruta, y
    # compararlo con una regla de prefijo de carpetas no significa nada.
    if ($null -ne $Configuracion -and $Configuracion.PSObject.Properties['RutasExcluidas']) {
        $claveCandidato = if ($Candidato.PSObject.Properties['ClaveExclusion']) {
            $Candidato.ClaveExclusion
        } else {
            # Un candidato construido a mano puede no traerla. Se calcula
            # con la MISMA funcion, asi que el veredicto es el mismo: no es
            # una degradacion silenciosa, es el mismo camino por otra
            # puerta.
            Get-ClaveExclusion -Ruta $Candidato.Ruta -ModuloId $Candidato.ModuloId -Nombre $Candidato.Nombre
        }

        if (Test-ClaveExcluida -Clave $claveCandidato -Excluidas @($Configuracion.RutasExcluidas)) {
            $Candidato.Error = 'Excluido por ti: esta en tu lista de "no tocar nunca".'
            return 0.0
        }
    }

    if ($Candidato.Metodo -ne 'Comando') {
        if (-not (Test-Path -LiteralPath $Candidato.Ruta)) {
            $Candidato.Error = 'La ruta ya no existe.'
            return 0.0
        }

        # --- Revalidación en vivo de la guardia -------------------------
        if (-not (Test-RutaSegura -Ruta $Candidato.Ruta -Raices $Candidato.Raices `
                                  -PermitirPersonales:$Candidato.PermitirPersonales)) {
            $Candidato.Error = 'Bloqueado por la guardia: ' + (Get-MotivoBloqueo $Candidato.Ruta $Candidato.Raices)
            return 0.0
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Candidato.Ruta, "Eliminar ($($Candidato.Metodo))")) { return 0.0 }

    # Se mide AQUÍ, justo antes de borrar. Antes se reutilizaba
    # $Candidato.Bytes, el tamaño estimado durante el análisis, que puede
    # tener horas: la carpeta ha podido crecer (una cache de navegador
    # abierto crece sola) o encoger. Como esta cifra alimenta el historial,
    # el error se volvia permanente, y además contradecia lo que promete la
    # cabecera de este archivo. Ver [C-18] en docs/OPTIMIZACIONES.md.
    #
    # La medición cuesta un recorrido de la ruta, pero el borrado que viene
    # justo después recorre esos mismos archivos: no cambia el orden de
    # magnitud de la operación.
    $antes = Measure-Ruta $Candidato.Ruta
    # Si no se puede medir (un enlace, una ruta que no lo es de verdad como
    # la del método 'Comando'...), se cae al valor del análisis antes que
    # informar de cero.
    if ($antes -le 0) { $antes = [double]$Candidato.Bytes }

    # El candidato puede forzar el borrado permanente (solo módulos de
    # cache genuina: mandar cientos de miles de archivos a la papelera es
    # lentisimo y la llena). Fuera de eso, manda SIEMPRE la preferencia
    # del usuario. Ver [C-01] en docs/OPTIMIZACIONES.md.
    $permanenteEfectivo = [bool]$Permanente -or [bool]$Candidato.ForzarPermanente

    $motivoBloqueo = Get-MotivoNoSeBorra -Candidato $Candidato -Bytes $antes -Permanente:$permanenteEfectivo
    if (-not [string]::IsNullOrEmpty($motivoBloqueo)) {
        $Candidato.Error = $motivoBloqueo
        Write-Registro -Sync $Sync -Nivel 'BLOQUEADO' -Mensaje (
            'No se borra {0}: {1}' -f $Candidato.Ruta, $motivoBloqueo)
        return $false
    }

    switch ($Candidato.Metodo) {
        'CarpetaVacia' {
            # Este método borra un ARBOL entero de carpetas de una vez, así
            # que se vuelve a comprobar que sigue sin un solo archivo. Entre
            # el análisis y este momento pueden haber pasado minutos y un
            # programa puede haber dejado algo dentro; sin esta comprobación,
            # el borrado recursivo se lo llevaria por delante. La guardia
            # válida la ruta, pero no sabe nada de si esta vacía.
            # Get-ElementosDelArbol y no Get-ChildItem -Recurse: si un
            # archivo estuviera a mas de 260 caracteres, la comprobacion no
            # lo veia, la carpeta parecia vacia y el borrado recursivo se lo
            # llevaba por delante. Ver [COR-08].
            $conArchivos = @(Get-ElementosDelArbol -Ruta $Candidato.Ruta |
                             Select-Object -First 1)
            if ($conArchivos.Count -gt 0) {
                $Candidato.Error = 'Ya no está vacía: algo ha creado archivos dentro desde el análisis. No se ha tocado.'
            } else {
                [void](Remove-RutaSegura -Ruta $Candidato.Ruta -Permanente:$permanenteEfectivo -Confirm:$false)
            }
        }
        # Aquí vivia el método 'NpmClean'. Se ha eliminado en [SEG-21]: la
        # llamada a "npm cache clean" se resolvia a npm.cmd, y ejecutar un
        # script por lotes pasa por cmd.exe pase lo que pase, con lo que la
        # lista blanca de ejecutables acababa reintroduciendo el interprete
        # de shell que [C-03] habia quitado. La cache de npm se sigue
        # limpiando exactamente igual de bien con 'Contenido': vaciar la
        # carpeta es lo que libera el espacio, y npm reconstruye su índice
        # solo en la siguiente instalación.
        'FirefoxCache' { Clear-CacheFirefox -Ruta $Candidato.Ruta -Permanente:$permanenteEfectivo -Confirm:$false }
        'Miniaturas'   { Clear-Miniaturas   -Ruta $Candidato.Ruta -Permanente:$permanenteEfectivo -Confirm:$false }
        'Contenido'    {
            # ForzarPermanente identifica a los candidatos de cache
            # genuina, que es exactamente el conjunto que puede levantar el
            # veto por extensión personal. Un solo hecho -"esto es cache
            # que el programa regenera"- con sus dos consecuencias, en vez
            # de dos banderas que habría que mantener de acuerdo a mano.
            Clear-ContenidoCarpeta -Ruta $Candidato.Ruta -Permanente:$permanenteEfectivo `
                                   -EsCache:([bool]$Candidato.ForzarPermanente) -Confirm:$false
        }
        'Comando' {
            $rutaEjecutable = Resolve-EjecutablePermitido -Ejecutable $Candidato.Ejecutable
            if ($null -eq $rutaEjecutable) {
                $Candidato.Error = "Ejecutable no permitido o no encontrado: '$($Candidato.Ejecutable)'."
                Write-Registro -Sync $Sync -Nivel 'BLOQUEADO' -Mensaje (
                    "Comando rechazado por la lista blanca: ejecutable '{0}' ({1})." -f
                    $Candidato.Ejecutable, $Candidato.Comando)
            } else {
                try {
                    # -ArgumentList recibe un ARRAY: cada elemento se pasa
                    # como argumento nativo del proceso, sin que ningún
                    # interprete de shell (cmd.exe, %VAR%, &, |) llegue a
                    # intervenir nunca. Ver [C-03] en docs/OPTIMIZACIONES.md.
                    $proceso = Start-Process -FilePath $rutaEjecutable -ArgumentList @($Candidato.Argumentos) `
                                             -Wait -NoNewWindow -PassThru -ErrorAction Stop
                    Write-Registro -Sync $Sync -Nivel 'BORRADO' -Mensaje (
                        '{0} {1}  ->  código de salida {2}' -f $rutaEjecutable,
                        ($Candidato.Argumentos -join ' '), $proceso.ExitCode)
                    if ($proceso.ExitCode -ne 0) {
                        $Candidato.Error = "El comando termino con código de salida $($proceso.ExitCode)."
                    }
                } catch {
                    $script:UltimoError = $_.Exception.Message
                }
            }
        }
        default {
            [void](Remove-RutaSegura -Ruta $Candidato.Ruta -Permanente:$permanenteEfectivo `
                                     -PermitirPersonales:$Candidato.PermitirPersonales -Confirm:$false)
        }
    }

    # Error puesto POR UNA RAMA del switch: significa "no se ha ejecutado
    # nada", que no es lo mismo que "se ejecuto y algo fallo". Se guarda
    # antes de que el bloque final pueda escribir encima. Ver [SEG-20].
    $errorDeRama = $Candidato.Error

    # La espera solo tiene sentido para que la remedicion de abajo no
    # cuente descriptores todavía abiertos, y SOLO cuando el contenedor
    # sobrevive (los métodos que vacian contenido en vez de borrar la
    # ruta entera). Para 'Ruta', 'Papelera' y 'Comando' la carpeta o el
    # archivo ya no existen: esperar no aporta nada. Antes se esperaba
    # siempre, 200 ms por candidato sin distinguir el método: en un lote
    # de 500 elementos son 100 s de solo esperar. Ver [R-01] en
    # docs/OPTIMIZACIONES.md.
    if ($script:MetodosQueVacianContenido -contains $Candidato.Metodo) {
        Start-Sleep -Milliseconds 50
    }

    $restante = Measure-Ruta $Candidato.Ruta
    $liberado = $antes - $restante
    if ($liberado -lt 0) { $liberado = 0 }

    # Hecho significa "esto se ha ejecutado", y hay dos ramas del switch que
    # deciden NO ejecutar nada y lo dicen rellenando Error: el comando que
    # la lista blanca rechaza, y la carpeta que ha dejado de estar vacía
    # entre el análisis y ahora. Marcarlas como hechas era mentir dos
    # veces: en la interfaz y en la columna "Eliminado" del CSV, que sale
    # justo de este campo.
    #
    # PERO se calculaba AQUÍ, antes de consolidar $script:UltimoError, que
    # es donde aterrizan los fallos de verdad: un Remove-Item denegado, un
    # Start-Process que lanza, un archivo bloqueado. Esos dejaban Hecho a
    # $true con Error relleno, y entonces la CLI los contaba como hechos,
    # el CSV ponia "Eliminado = True" y el historial sumaba bytes que nunca
    # se llegaron a liberar. El registro de auditoria -que es la razón de
    # ser de este programa- afirmaba haber borrado cosas que seguian ahi.
    #
    # Ahora Hecho se decide al final, con el Error ya completo, y hay una
    # sola fuente de verdad. Ver [SEG-20] en docs/PLAN-ACCION.md.
    $Candidato.BytesLiberados = $liberado
    if ($Candidato.Error) {
        # La rama ya ha explicado por que no se hizo nada; no se pisa.
    } elseif ($script:UltimoError) {
        $Candidato.Error = $script:UltimoError
    } elseif ($restante -gt 1MB -and $antes -gt 0 -and
              $script:MetodosParciales -notcontains $Candidato.Metodo) {
        # El aviso de "queda algo" solo tiene sentido si el método pretendia
        # dejar la ruta vacía. Los métodos parciales dejan cosas atras A
        # PROPÓSITO: FirefoxCache solo vacía las carpetas cache2 y deja
        # intactos marcadores, cookies e historial; Miniaturas solo borra
        # los thumbcache_*.db. Antes se avisaba igual, así que limpiar la
        # cache de Firefox terminaba SIEMPRE con un "Quedan 600 MB: archivos
        # en uso por algún programa abierto" que era falso y alarmaba sin
        # motivo. Ver [C-06] en docs/OPTIMIZACIONES.md.
        $Candidato.Error = "Quedan $(Format-Tamano $restante): archivos en uso por algún programa abierto."
    }

    # Ahora si: con el error ya consolidado. Tres estados, no dos.
    #
    #   - Una rama declino actuar     -> no se ha hecho.
    #   - Algo lanzo al ejecutar      -> no se ha hecho.
    #   - Se ejecuto y quedan archivos en uso -> SI se ha hecho. Es un
    #     resultado parcial, no un fallo: el borrado corrio y libero
    #     espacio, y el mensaje de "quedan X" es informativo. Marcarlo como
    #     no hecho seria el error opuesto al que se estaba corrigiendo.
    $Candidato.Hecho = [string]::IsNullOrEmpty($errorDeRama) -and
                       [string]::IsNullOrEmpty($script:UltimoError)

    return $liberado
}
