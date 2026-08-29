<#
.SYNOPSIS
    Contrato de un candidato a limpieza y del resultado de un módulo.
#>

# Métodos de eliminación admitidos. La lista de verdad es el ValidateSet
# del parámetro -Método de New-Candidato; esto es solo la explicación de
# que hace cada uno. Aquí hubo también un array $script:MetodosValidos que
# no leia nadie: dos listas que había que mantener a mano en paralelo, con
# el riesgo de que divergieran sin que nada avisara.
#   Contenido    -> vacía la carpeta pero la deja en su sitio
#   Ruta         -> borra el archivo o la carpeta entera
#   CarpetaVacia -> borra un arbol de carpetas vacías, revalidando que
#                   sigue sin un solo archivo justo antes de tocarlo
#   FirefoxCache -> vacía solo las subcarpetas cache2 de cada perfil
#   Miniaturas   -> borra únicamente thumbcache_*.db e iconcache_*.db
#   Papelera     -> vacía la papelera de reciclaje mediante la API del shell
#   Comando      -> delega en un comando externo declarado en el candidato
#   Informativo  -> no borra nada, solo informa

# =====================================================================
#  POR QUE VIENE MARCADO O NO  ([CNF-05])
# =====================================================================
#
# El programa marca algunas cosas solo y otras no, y hasta ahora no lo
# decia en ninguna parte: el resumen contaba CUANTOS elementos habia, pero
# el criterio estaba en el README, en ARQUITECTURA.md y en el panel
# "Acerca de" -o sea, en tres sitios donde nadie mira mientras decide-.
#
# Y ese criterio es justo lo que sostiene el pilar del proyecto. "Nunca
# marca solo lo dudoso" no vale de nada si el usuario no sabe que esa es
# la regla: sin saberlo, o desconfia de todo o se fia de todo.
#
# La regla y su EXPLICACION salen de la misma funcion a proposito. Si
# fueran dos copias acabarian divergiendo -es [ARQ-01] otra vez- y una
# explicacion que no coincide con lo que hizo el programa es peor que no
# explicar nada: convierte la confianza en un malentendido.

function Test-DebeVenirMarcado {
    <#
    .SYNOPSIS
        La regla: ¿esto se marca solo?

    .DESCRIPTION
        CALCULO PURO sobre los tres hechos que deciden. Solo se marca lo
        de riesgo bajo, sin avisos y que de verdad borre algo. Cualquier
        otra cosa exige una decisión consciente del usuario.

        No recibe el candidato entero sino sus tres campos, para que se
        pueda preguntar ANTES de que el candidato exista: New-Candidato la
        llama mientras lo está construyendo.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string] $Riesgo = 'Bajo',
        [string] $Aviso  = '',
        [string] $Metodo = 'Ruta'
    )

    if ($Metodo -eq 'Informativo') { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Aviso)) { return $false }
    return ($Riesgo -eq 'Bajo')
}

function Get-MotivoPremarcado {
    <#
    .SYNOPSIS
        Por qué este elemento viene marcado, o por qué no.

    .DESCRIPTION
        Una frase, en el orden en que manda la regla: primero lo que veta
        -informativo, aviso-, después el riesgo. Ese orden importa porque
        un elemento puede cumplir dos motivos a la vez, y hay que
        enseñarle el que de verdad decidió.

        Se explica el estado que produce LA REGLA, no la casilla que se ve
        ahora mismo: si el usuario ya la ha tocado, lo que quiere saber es
        por qué el programa opinaba lo que opinaba.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Riesgo = 'Bajo',
        [string] $Aviso  = '',
        [string] $Metodo = 'Ruta'
    )

    if ($Metodo -eq 'Informativo') {
        return 'Sin marcar: este módulo no borra nada, solo informa.'
    }
    if (-not [string]::IsNullOrWhiteSpace($Aviso)) {
        return 'Sin marcar: lleva un aviso, y lo que lleva aviso no se marca nunca solo.'
    }
    if ($Riesgo -ne 'Bajo') {
        return ('Sin marcar: riesgo {0}. Solo se marca solo lo de riesgo bajo.' -f
                ([string]$Riesgo).ToLower())
    }
    return 'Marcado: riesgo bajo y sin avisos.'
}

function Get-ResumenPremarcado {
    <#
    .SYNOPSIS
        La frase del pie: cuántos vienen marcados y por qué.

    .DESCRIPTION
        Es lo que convierte una lista en una decisión informada. Antes el
        resumen decia cuántos elementos habia y nada más, asi que el
        usuario no tenia forma de saber si "marcado" significaba "el
        programa cree que esto sobra" o "esto es lo que estaba arriba".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] $Candidatos)

    $todos = @($Candidatos)
    if ($todos.Count -eq 0) { return '' }

    $marcados = @($todos | Where-Object { $_.Seleccionado }).Count
    $sinMarcar = $todos.Count - $marcados

    if ($sinMarcar -eq 0) {
        return ('Los {0} vienen marcados: todos son de riesgo bajo y sin avisos.' -f $todos.Count)
    }
    if ($marcados -eq 0) {
        return ('Ninguno viene marcado: todos llevan aviso o riesgo por encima de bajo. Los marcas tú.')
    }
    return ('{0} vienen marcados por ser de riesgo bajo y sin avisos. Los otros {1} los marcas tú.' -f
            $marcados, $sinMarcar)
}

function New-Candidato {
    <#
    .SYNOPSIS
        Crea un elemento propuesto para limpieza.

    .PARAMETER ModuloId
        Identificador del módulo que lo propone.
    .PARAMETER Categoria
        Grupo visible en la interfaz.
    .PARAMETER Nombre
        Titulo corto y legible.
    .PARAMETER Ruta
        Ruta absoluta afectada.
    .PARAMETER Bytes
        Espacio que se recuperaria.
    .PARAMETER Info
        Detalle secundario (fechas, número de archivos...).
    .PARAMETER Efecto
        Que ocurre después de borrarlo, en lenguaje llano.
    .PARAMETER Aviso
        Motivo por el que conviene revisarlo a mano. Si viene relleno el
        elemento se muestra en rojo y NUNCA se marca por defecto.
    .PARAMETER Metodo
        Como se elimina. Los valores admitidos son los del ValidateSet de
        este mismo parámetro; el comentario de cabecera del archivo explica
        que hace cada uno.
    .PARAMETER Raices
        Lista blanca de carpetas de las que debe colgar la ruta.
    .PARAMETER Riesgo
        Bajo | Medio | Alto. Determina el color de la etiqueta.
    .PARAMETER PermitirPersonales
        Levanta el veto por extensión personal. Reservado al módulo de
        duplicados, que garantiza que existe otra copia identica.
    .PARAMETER Preseleccionado
        Si se marca solo al aparecer. Por defecto se deriva del riesgo.
    .PARAMETER ForzarPermanente
        Solo para módulos de cache genuina (cachés de aplicaciones y de
        navegador). Ignora la preferencia "enviar a la papelera" del
        usuario para ESTE candidato: mandar cientos de miles de archivos
        de cache a la papelera es lentisimo y la llena sin liberar espacio
        hasta vaciarla. El resto de métodos SIEMPRE respeta la preferencia
        del usuario. Ver Remove.ps1 (Invoke-EliminacionCandidato).
    .PARAMETER Comando
        Solo para -Método 'Comando'. Cadena LEGIBLE para mostrar en la
        interfaz y en el registro (por ejemplo, la ruta completa resuelta
        de DISM). No se ejecuta nunca tal cual: ver Ejecutable y
        Argumentos. Ver [C-03] en docs/OPTIMIZACIONES.md.
    .PARAMETER Ejecutable
        Solo para -Método 'Comando'. Nombre del ejecutable SIN ruta ni
        argumentos (por ejemplo 'dism' o 'docker'). Remove.ps1 lo resuelve
        contra su propia lista blanca en el momento de borrar: el módulo
        declara la intencion, el motor decide si se fia.
    .PARAMETER Argumentos
        Solo para -Método 'Comando'. Los argumentos como un array, uno por
        elemento, nunca como una única cadena: se pasan a Start-Process sin
        pasar por ningún interprete de shell, así que '&', '|' y '%VAR%' no
        se interpretan.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria: no toca el sistema.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ModuloId,
        [Parameter(Mandatory)] [string] $Categoria,
        [Parameter(Mandatory)] [string] $Nombre,
        [Parameter(Mandatory)] [string] $Ruta,
        [double]   $Bytes  = 0,
        [string]   $Info   = '',
        [string]   $Efecto = '',
        [string]   $Aviso  = '',
        [ValidateSet('Contenido', 'Ruta', 'CarpetaVacia', 'FirefoxCache', 'Miniaturas', 'Papelera', 'Comando', 'Informativo')]
        [string]   $Metodo = 'Ruta',
        [string[]] $Raices = @(),
        [ValidateSet('Bajo', 'Medio', 'Alto')]
        [string]   $Riesgo = 'Bajo',
        [string]   $Comando = '',
        [string]   $Ejecutable = '',
        [string[]] $Argumentos = @(),
        [switch]   $PermitirPersonales,
        [switch]   $ForzarPermanente,
        [Nullable[bool]] $Preseleccionado = $null
    )

    # La regla vive en Test-DebeVenirMarcado, no aqui. Es la misma funcion
    # que usa Get-MotivoPremarcado para EXPLICARSELA al usuario: si la
    # decision y su explicacion fueran dos copias, acabarian diciendo
    # cosas distintas, y una explicacion que no coincide con lo que hizo
    # el programa es peor que no explicar nada. Ver [CNF-05] y [ARQ-01].
    $marcado = Test-DebeVenirMarcado -Riesgo $Riesgo -Aviso $Aviso -Metodo $Metodo
    if ($null -ne $Preseleccionado) { $marcado = [bool]$Preseleccionado }

    # -Preseleccionado puede DESMARCAR lo que la regla marcaria, pero no al
    # revés: un candidato con aviso no se marca nunca, lo pida quien lo
    # pida. La regla estaba escrita arriba y documentada en tres sitios
    # (README, ARQUITECTURA y el panel "Acerca de"), pero -Preseleccionado
    # la pisaba y dos módulos lo hacian; así que lo prometido -"lo que
    # lleva aviso sale en rojo y sin marcar"- era falso. Ahora la
    # invariante se cumple por construcción, aquí, para los 18 módulos y
    # para cualquiera que se añada.
    #
    # Un aviso es un motivo para mirar antes de borrar. Si algo tiene que
    # ir marcado, no lleva aviso: lleva Info.
    if (-not [string]::IsNullOrWhiteSpace($Aviso)) { $marcado = $false }
    if ($Metodo -eq 'Informativo') { $marcado = $false }

    [pscustomobject]@{
        ModuloId       = $ModuloId
        Categoria      = $Categoria
        Nombre         = $Nombre
        Ruta           = $Ruta
        Bytes          = [double]$Bytes
        Info           = $Info
        Efecto         = $Efecto
        Aviso          = $Aviso
        Metodo         = $Metodo
        Comando        = $Comando
        Ejecutable     = $Ejecutable
        Argumentos     = @($Argumentos)
        Raices         = @($Raices)
        # Solo lo usa el módulo de duplicados. Ver Test-RutaSegura.
        PermitirPersonales = [bool]$PermitirPersonales
        # Solo lo usan los módulos de cache genuina. Ver Remove.ps1.
        ForzarPermanente = [bool]$ForzarPermanente
        Riesgo         = $Riesgo
        Seleccionado   = $marcado
        Hecho          = $false
        BytesLiberados = 0.0
        Error          = ''
    }
}

function New-ModuloLimpieza {
    <#
    .SYNOPSIS
        Declara un módulo de limpieza.
    .DESCRIPTION
        Cada archivo de src/Modules termina llamando a esta función. El
        objeto resultante es lo único que el resto del programa conoce del
        módulo, de modo que añadir uno nuevo no obliga a tocar nada más.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria: no toca el sistema.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Nombre,
        [Parameter(Mandatory)] [string] $Descripcion,
        [Parameter(Mandatory)] [int]    $Orden,
        [Parameter(Mandatory)] [scriptblock] $Buscar,
        [ValidateSet('Bajo', 'Medio', 'Alto')]
        [string]   $Riesgo        = 'Bajo',
        [switch]   $RequiereAdmin,
        [switch]   $SoloInforma,
        [string[]] $Perfiles      = @('equilibrado', 'agresivo')
    )

    [pscustomobject]@{
        Id            = $Id
        Nombre        = $Nombre
        Descripcion   = $Descripcion
        Orden         = $Orden
        Riesgo        = $Riesgo
        RequiereAdmin = [bool]$RequiereAdmin
        SoloInforma   = [bool]$SoloInforma
        Perfiles      = @($Perfiles)
        Buscar        = $Buscar
    }
}

function Invoke-BusquedaPorLista {
    <#
    .SYNOPSIS
        Recorre una lista de rutas conocidas y propone las que valen.

    .DESCRIPTION
        Tres módulos -caches, logs y windowsupdate- hacian exactamente el
        mismo bucle, escrito tres veces: recorrer una lista de entradas,
        mirar si la ruta existe, medirla, descartarla si no llega al
        umbral, pasarla por la guardia y emitir el candidato. Más de cien
        líneas repetidas, con el riesgo clasico: arreglar tres y olvidar el
        cuarto.

        Lo que NO se ha unificado, a propósito:

          * 80-ArchivosSistema recorre ARCHIVOS sueltos, no carpetas, y
            todos sus candidatos son informativos. Meterlo aquí obligaria a
            que esta función supiera de las dos cosas, y una función común
            que necesita un interruptor por cada llamante ya no es común.
          * MEMORY.DMP de logs y Windows.old de windowsupdate se quedan
            donde estaban, por lo mismo: son un archivo suelto y un caso
            informativo, no entradas de una lista.

        Cada módulo conserva SU umbral (caches y logs, 1 MB; windowsupdate,
        10 MB), su categoría y su forma de decidir el marcado. Unificar eso
        habría sido cambiar comportamiento con la excusa de refactorizar.

    .PARAMETER Entradas
        Lista de tablas con: N (nombre), R (ruta), E (efecto) y,
        opcionalmente, M (método, por defecto 'Contenido'), A (aviso) y
        Menor (si solo sale con -IncluirMenores).

    .NOTES
        No hay parámetro para forzar el marcado, y es deliberado: la regla
        vive entera en New-Candidato -riesgo bajo, sin aviso y sin método
        informativo- y ahi se cumple por construcción para los 18 módulos.
        Los tres módulos que usan esta función llegaron a pasar su propio
        cierre de preseleccion; sobraba, porque decia exactamente lo mismo
        que la regla por defecto. Una segunda forma de decir lo mismo es
        una forma de que las dos acaben diciendo cosas distintas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ModuloId,
        [Parameter(Mandatory)] [string] $Categoria,
        [Parameter(Mandatory)] $Entradas,
        [Parameter(Mandatory)] [string[]] $Raices,
        $Sync = $null,
        [double] $MinimoBytes = 1MB,
        [string] $Info = 'se vacía el contenido, la carpeta se queda',
        [switch] $ForzarPermanente,
        [switch] $IncluirMenores,
        # Cierre opcional que recibe la entrada y devuelve texto para
        # añadir al campo Info. Lo usa caches para avisar de que el
        # programa esta abierto.
        [scriptblock] $NotaExtra = $null
    )

    foreach ($entrada in @($Entradas)) {
        if (Test-Cancelacion $Sync) { break }
        if (-not $IncluirMenores -and $entrada.Menor) { continue }
        if (-not (Test-Path -LiteralPath $entrada.R)) { continue }

        # La guardia ANTES de medir. Las dos condiciones son independientes
        # y el continue es el mismo, así que el resultado no cambia; pero
        # medir cuesta segundos y preguntar cuesta un milisegundo, y una
        # ruta vetada se descarta igual después de haberla recorrido
        # entera. Ver docs/RENDIMIENTO.md (sección 7).
        if (-not (Test-RutaSegura $entrada.R $Raices)) { continue }

        Set-Progreso $Sync "Midiendo: $($entrada.N)"
        $bytes = Measure-Ruta $entrada.R
        if ($bytes -lt $MinimoBytes) { continue }

        $metodo = if ($entrada.M) { $entrada.M } else { 'Contenido' }
        $aviso  = if ($entrada.A) { $entrada.A } else { '' }
        $nota   = if ($NotaExtra) { [string](& $NotaExtra $entrada) } else { '' }

        $parametros = @{
            ModuloId  = $ModuloId
            Categoria = $Categoria
            Nombre    = $entrada.N
            Ruta      = $entrada.R
            Bytes     = $bytes
            Info      = $Info + $nota
            Efecto    = $entrada.E
            Aviso     = $aviso
            Metodo    = $metodo
            Raices    = $Raices
            Riesgo    = 'Bajo'
        }
        if ($ForzarPermanente) { $parametros['ForzarPermanente'] = $true }

        New-Candidato @parametros
    }
}
