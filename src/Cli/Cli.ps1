<#
.SYNOPSIS
    Modo consola: analiza y limpia sin abrir ninguna ventana.

.DESCRIPTION
    Pensado para automatizar. Por defecto SOLO ANALIZA: hace falta pasar
    -Ejecutar de forma explicita para que borre algo, y aun así solo toca
    los elementos que el análisis había marcado por su cuenta, que son los
    de riesgo bajo y sin avisos.
#>

function Write-Linea {
    param(
        [string] $Texto = '',
        [ValidateSet('normal', 'titulo', 'ok', 'aviso', 'error', 'tenue')]
        [string] $Estilo = 'normal'
    )
    switch ($Estilo) {
        'titulo' { Write-Host $Texto -ForegroundColor Cyan }
        'ok'     { Write-Host $Texto -ForegroundColor Green }
        'aviso'  { Write-Host $Texto -ForegroundColor Yellow }
        'error'  { Write-Host $Texto -ForegroundColor Red }
        'tenue'  { Write-Host $Texto -ForegroundColor DarkGray }
        default  { Write-Host $Texto }
    }
}

function Write-Cabecera {
    param([string] $Texto)
    Write-Linea ''
    Write-Linea ('  ' + $Texto) 'titulo'
    Write-Linea ('  ' + ('-' * $Texto.Length)) 'tenue'
}

# ---------------------------------------------------------------------
#  El aviso de avance del borrado
# ---------------------------------------------------------------------
#
# ESTE BLOQUE ESTABA DENTRO DE Invoke-CachivacheCli CON .GetNewClosure(), Y
# ASI EL MODO CONSOLA NO PODIA BORRAR NADA. Merece leerse entero, porque el
# fallo es de los que no se ven mirando el codigo.
#
# .GetNewClosure() copia las variables del ambito actual, que es justo lo
# que parece hacer falta aqui. Lo que ademas hace, y no se anuncia, es
# ejecutar el bloque dentro de un MODULO DINAMICO nuevo: la resolucion de
# funciones pasa a ir contra ese modulo y contra el ambito GLOBAL, y no
# contra el sitio donde se escribio.
#
# Cachivache.ps1 dot-sourcea Bootstrap.ps1 en su ambito de SCRIPT, no en
# global. Asi que desde dentro del cierre no se veia ni una funcion del
# nucleo, y la primera -Invoke-VaciarColaRegistro- reventaba:
#
#     Invoke-LoteEliminacion : The term 'Invoke-VaciarColaRegistro' is not
#     recognized as the name of a cmdlet, function, script file...
#
# O sea: "Cachivache.ps1 -Consola -Ejecutar" moria EN EL MOMENTO DE BORRAR.
# El analisis funcionaba, el informe se guardaba, y al llegar al primer
# elemento se caia. Llevaba asi desde que se escribio [ARQ-01].
#
# POR QUE NO LO VIO NADIE, que es la parte importante:
#
#   - La comprobacion de arranque de la integracion continua ejecuta el
#     modo consola SIN -Ejecutar, asi que nunca pisaba esta linea.
#   - Las pruebas del modo consola SI lo pisaban... y al escribirlas se
#     tropezaron con este mismo error. Se dio por hecho que era una rareza
#     de Pester y se rodeo cargando el nucleo como modulo, que hace
#     globales las funciones y tapa el fallo. Se rodeo el sintoma de un
#     fallo de verdad. Ahora las pruebas cargan como carga el programa.
#
# EL ARREGLO. Sin GetNewClosure el bloque conserva el ambito donde se
# escribio, y desde ahi si se ven las funciones del nucleo. Lo que se
# pierde es la captura de variables, y por eso las dos que necesita van en
# $script:, puestas por Invoke-CachivacheCli antes de empezar el lote.
$script:CliSilencioso = $false
$script:CliSync       = $null

$script:MostrarAvanceBorrado = {
    param($candidato, $avance)
    [void](Invoke-VaciarColaRegistro -Sync $script:CliSync)
    if (-not $script:CliSilencioso) {
        $marca  = if ($candidato.Error) { '!' } else { '+' }
        $estilo = if ($candidato.Error) { 'aviso' } else { 'normal' }
        Write-Linea ('  {0} {1,-52} {2,10}' -f $marca,
                     (Get-RutaElidida $candidato.Nombre 52),
                     (Format-Tamano $candidato.BytesLiberados)) $estilo
    }
}

function Invoke-CachivacheCli {
    <#
    .SYNOPSIS
        Punto de entrada del modo consola.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] $Configuracion,
        [Parameter(Mandatory)] $Modulos,
        [string[]] $Ids       = @(),
        [switch]   $Ejecutar,
        [string]   $Informe   = '',
        # Anonimiza el informe: perfil, usuario y equipo pasan a ser
        # marcadores. Para poder adjuntarlo a una incidencia sin publicar
        # de paso el nombre de usuario de Windows en cada fila.
        [switch]   $InformeAnonimo,
        # Ensenya lo que se borraria sin borrarlo. Ver [CNF-02].
        [switch]   $Simular,
        [switch]   $Silencioso
    )

    if (-not $Silencioso) {
        Write-Linea ''
        Write-Linea "  Cachivache v$script:VersionCachivache" 'titulo'
        Write-Linea "  $($Configuracion.Equipo) - perfil $($Configuracion.Perfil) - $(if ($Configuracion.Admin) { 'administrador' } else { 'modo estandar' })" 'tenue'
    }

    # Sin -Sync aquí: la cabecera se escribe al momento. Los módulos SI
    # reciben la tabla sincronizada (más abajo), y su cola se vacía después
    # de cada uno.
    # Ver [T-05] en docs/OPTIMIZACIONES.md.
    Write-CabeceraSesion -Perfil $Configuracion.Perfil -Admin $Configuracion.Admin

    # --- Selección de módulos --------------------------------------------
    $seleccionados = if ($Ids.Count -gt 0) {
        @($Modulos | Where-Object { $Ids -contains $_.Id })
    } else {
        @($Modulos | Where-Object { Test-ModuloEnPerfil -Modulo $_ -Perfil $Configuracion.Perfil })
    }
    $seleccionados = @($seleccionados | Where-Object { -not ($_.RequiereAdmin -and -not $Configuracion.Admin) })

    if ($seleccionados.Count -eq 0) {
        if (-not $Silencioso) { Write-Linea '  No hay ningún módulo que ejecutar con esta configuración.' 'aviso' }
        return 1
    }

    # --- Análisis ---------------------------------------------------------
    if (-not $Silencioso) { Write-Cabecera 'Analisis' }

    $todos = [Collections.Generic.List[object]]::new()
    $sync  = New-EstadoSincronizado
    $cronometro = [Diagnostics.Stopwatch]::StartNew()

    # Modulos que no han llegado a dar resultado. La ventana ya lo cuenta y
    # lo ensenya en una franja; la consola tiene que decir lo mismo o
    # tendremos otra vez dos caminos contando cosas distintas, que es el
    # error de [ARQ-01] y de [INT-12]. Ver [CNF-04].
    $fallidos = [Collections.Generic.List[string]]::new()

    foreach ($modulo in $seleccionados) {
        if (-not $Silencioso) { Write-Host ('  {0,-42}' -f $modulo.Nombre) -NoNewline }

        $resultado = Invoke-ModuloLimpieza -Modulo $modulo -Configuracion $Configuracion -Sync $sync

        if ($resultado.Omitido) {
            if (-not $Silencioso) { Write-Linea ('omitido: ' + $resultado.Omitido) 'tenue' }
            continue
        }
        if ($resultado.Error) {
            if (-not $Silencioso) { Write-Linea ('error: ' + $resultado.Error) 'error' }
            Write-Registro -Mensaje "$($modulo.Id): $($resultado.Error)" -Nivel 'ERROR'
            $fallidos.Add([string]$modulo.Nombre)
            continue
        }

        $suma = 0.0
        foreach ($candidato in $resultado.Candidatos) {
            $suma += $candidato.Bytes
            $todos.Add($candidato)
        }
        if (-not $Silencioso) {
            if ($resultado.Candidatos.Count -eq 0) { Write-Linea 'nada' 'tenue' }
            else { Write-Linea ('{0,4} elementos   {1,10}' -f $resultado.Candidatos.Count, (Format-Tamano $suma)) 'ok' }
        }

        # Se le pasa $sync a los módulos, así que si alguno registra algo
        # acaba encolado y no en el archivo. En la ventana lo vacía el
        # temporizador; aquí no había nadie que lo hiciera y esas líneas se
        # perdian en silencio. Hoy ningún módulo registra nada, pero el
        # primero que lo haga no debe estrenarse perdiendo su rastro.
        [void](Invoke-VaciarColaRegistro -Sync $sync)
    }
    $cronometro.Stop()

    $borrables = @($todos | Where-Object { $_.Metodo -ne 'Informativo' })
    $marcados  = @($borrables | Where-Object { $_.Seleccionado })
    $bytesMarcados = 0.0
    foreach ($candidato in $marcados) { $bytesMarcados += $candidato.Bytes }
    $bytesTotales = 0.0
    foreach ($candidato in $borrables) { $bytesTotales += $candidato.Bytes }

    if (-not $Silencioso) {
        Write-Cabecera 'Resumen'
        # Las dos primeras cifras tienen que hablar de lo mismo. Antes
        # "Elementos encontrados" contaba TODO -informativos incluidos- y
        # "Recuperable total" solo los borrables, asi que en el mismo
        # bloque salian dos numeros que no cuadraban y no habia forma de
        # saber por que. Ver [INT-14].
        $informativos = $todos.Count - $borrables.Count
        Write-Linea ('  Elementos encontrados : {0} ({1} recuperables, {2} solo informativos)' -f `
                     $todos.Count, $borrables.Count, $informativos)
        Write-Linea ('  Recuperable total     : {0}' -f (Format-Tamano $bytesTotales))
        Write-Linea ('  Marcado por defecto   : {0} elementos, {1}' -f $marcados.Count, (Format-Tamano $bytesMarcados))
        # El CRITERIO, no solo la cuenta. "Marcado por defecto: 33" no dice
        # si eso significa "el programa cree que sobran" o "son los que
        # estaban arriba". Ver [CNF-05]. La misma frase que la ventana:
        # dos textos distintos para la misma regla acabarian divergiendo.
        $criterio = Get-ResumenPremarcado -Candidatos $borrables
        if ($criterio) { Write-Linea ('                          {0}' -f $criterio) 'tenue' }
        Write-Linea ('  Tiempo de análisis    : {0}' -f (Format-Duracion $cronometro.Elapsed))
        Write-Linea ('  Libre en {0}           : {1}' -f $Configuracion.Unidad, (Format-Tamano (Get-EspacioLibre $Configuracion.Unidad)))

        # El aviso va DESPUES de las cifras, que es donde se lee. Puesto
        # antes, queda tapado por la tabla que viene detras.
        if ($fallidos.Count -gt 0) {
            Write-Linea ''
            Write-Linea ('  ATENCIÓN: esta lista está incompleta. {0} no se {1} podido completar: {2}.' -f `
                         $(if ($fallidos.Count -eq 1) { '1 módulo' } else { '{0} módulos' -f $fallidos.Count }),
                         $(if ($fallidos.Count -eq 1) { 'ha' } else { 'han' }),
                         (@($fallidos) -join ', ')) 'error'
            Write-Linea '  Puede haber basura que no aparece aquí. El detalle está en el registro.' 'error'
        }
    }

    # --- Informe ----------------------------------------------------------
    # Va antes del historial para poder anotar en la entrada la ruta del
    # informe, igual que hace la ventana.
    $rutaInforme = ''
    if ($Informe) {
        $extension = [IO.Path]::GetExtension($Informe).TrimStart('.').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($extension)) { $extension = 'html'; $Informe = "$Informe.html" }
        try {
            switch ($extension) {
                'csv'  { Export-InformeCsv  -Candidatos $todos -Ruta $Informe -Anonimo:$InformeAnonimo -Confirm:$false }
                'json' { Export-InformeJson -Candidatos $todos -Ruta $Informe -Configuracion $Configuracion -Anonimo:$InformeAnonimo -Confirm:$false }
                default { Export-InformeHtml -Candidatos $todos -Ruta $Informe -Configuracion $Configuracion -Modulos $Modulos -Anonimo:$InformeAnonimo -Confirm:$false }
            }
            if (-not $Silencioso) { Write-Linea ('  Informe guardado en {0}' -f $Informe) 'ok' }

            # Aquí la ruta la elige el usuario con -Informe y puede ser
            # cualquier sitio del disco. Solo se anota si cae dentro de la
            # carpeta de informes, que es lo único que la ventana va a
            # aceptar abrir después: guardar una ruta que la guardia
            # rechazara siempre dejaria una tarjeta que parece pulsable y
            # no hace nada.
            $rutaInforme = [string](Resolve-InformeAbrible -Ruta $Informe -CarpetaDatos $Configuracion.CarpetaDatos)
        } catch {
            if (-not $Silencioso) { Write-Linea ('  No se ha podido guardar el informe: {0}' -f $_.Exception.Message) 'error' }
            Write-Registro -Mensaje "No se ha podido guardar el informe '$Informe': $($_.Exception.Message)" -Nivel 'ERROR'
        }
    }

    # -Modulos son los que DIERON resultado, no los que se pidieron. Anotar
    # los que fallaron como si hubieran corrido convierte el historial en
    # otro sitio donde el programa dice haber mirado lo que no miro.
    $idsFallidos = @($seleccionados | Where-Object { $fallidos -contains $_.Nombre } | ForEach-Object { $_.Id })
    Add-EntradaHistorial -Tipo 'analisis' -Elementos $todos.Count -Bytes $bytesTotales `
                         -Perfil $Configuracion.Perfil `
                         -Modulos @($seleccionados | Where-Object { $_.Id -notin $idsFallidos } | ForEach-Object { $_.Id }) `
                         -Informe $rutaInforme `
                         -Incompleto:($fallidos.Count -gt 0) `
                         -Motivo $(if ($fallidos.Count -gt 0) {
                                      'No se pudieron completar: {0}.' -f ((@($fallidos)) -join ', ')
                                   } else { '' }) `
                         -CarpetaDatos $Configuracion.CarpetaDatos -Confirm:$false

    # --- Eliminación ------------------------------------------------------
    if (-not $Ejecutar) {
        if (-not $Silencioso) {
            Write-Linea ''
            Write-Linea '  Esto ha sido solo un análisis: no se ha borrado nada.' 'aviso'
            Write-Linea '  Añade -Ejecutar para eliminar los elementos marcados.' 'tenue'
            Write-Linea ''
        }
        return 0
    }

    if ($marcados.Count -eq 0) {
        if (-not $Silencioso) { Write-Linea '  No hay nada marcado para eliminar.' 'aviso' }
        return 0
    }

    if (-not $PSCmdlet.ShouldProcess(
            "$($marcados.Count) elementos ($(Format-Tamano $bytesMarcados))",
            'Eliminar')) {
        return 0
    }

    if (-not $Silencioso) { Write-Cabecera 'Eliminacion' }

    # Lo que el cierre de avance necesita y ya no puede capturar solo.
    $script:CliSilencioso = [bool]$Silencioso
    $script:CliSync       = $sync

    [void](Initialize-MotorBorrado)
    $libreAntes = Get-EspacioLibre $Configuracion.Unidad
    $liberado = 0.0
    $hechos = 0

    # El bucle vive en Remove.ps1 y lo comparten la consola y la ventana:
    # antes habia dos copias y una de ellas era texto dentro de una cadena,
    # invisible para el analizador y para las pruebas. Ver [ARQ-01].
    #
    # Lo unico propio de la consola es como se informa de cada elemento,
    # y eso es justo lo que recibe el cierre.
    $resultadoLote = Invoke-LoteEliminacion -Candidatos $marcados `
                        -Permanente:$Configuracion.Permanente -Simular:$Simular `
                        -Configuracion $Configuracion -Sync $sync -Confirm:$false `
                        -AlProgresar $script:MostrarAvanceBorrado

    $liberado = $resultadoLote.Liberado
    $hechos   = $resultadoLote.Hechos
    $conError = $resultadoLote.ConError

    # Informe de la limpieza, con lo que de verdad se hizo. Antes el único
    # informe se generaba ANTES de borrar, así que con -Ejecutar -Informe
    # salia con "Eliminado = false" y "Liberado = 0" en todas las filas.
    $informeLimpieza = ''
    if ($Simular) {
        # No hay limpieza que documentar. El informe del ANALISIS, que si
        # se genero mas arriba, ya dice que se propuso.
        if (-not $Silencioso) { Write-Linea '' }
    } else {
    try {
        $informeLimpieza = New-NombreInforme -Tipo 'limpieza' -Extension 'html' -CarpetaDatos $Configuracion.CarpetaDatos
        Export-InformeHtml -Candidatos @($marcados | Where-Object { $_.Hecho }) -Ruta $informeLimpieza `
                           -Configuracion $Configuracion -Tipo 'limpieza' -Modulos $Modulos -Confirm:$false
        if (-not $Silencioso) { Write-Linea ('  Informe de la limpieza en {0}' -f $informeLimpieza) 'ok' }
    } catch {
        Write-Registro -Nivel 'ERROR' -Mensaje "No se ha podido generar el informe de la limpieza: $($_.Exception.Message)"
        $informeLimpieza = ''
    }
    }

    $libreDespues = Get-EspacioLibre $Configuracion.Unidad

    # Una simulacion NO se anota en el historial. No ha ocurrido nada que
    # registrar, y un historial con limpiezas que no pasaron es justo el
    # tipo de mentira que este programa lleva toda la auditoria
    # corrigiendo. Ver [CNF-02] y [SEG-20].
    if (-not $Simular) {
        Add-EntradaHistorial -Tipo 'limpieza' -Elementos $hechos -Bytes $liberado `
                             -Perfil $Configuracion.Perfil -LibreAntes $libreAntes -LibreDespues $libreDespues `
                             -Informe $informeLimpieza `
                             -CarpetaDatos $Configuracion.CarpetaDatos -Confirm:$false
    }

    if (-not $Silencioso) {
        if ($Simular) {
            # En simulacion todos los verbos van en condicional, sin
            # excepcion. Un resumen que diga "eliminados" cuando no se ha
            # eliminado nada es peor que no dar resumen.
            Write-Cabecera 'Resultado de la simulacion'
            Write-Linea ('  Se habrian eliminado : {0} elementos' -f $resultadoLote.Simulados) 'ok'
            Write-Linea ('  Se habrian liberado  : {0}' -f (Format-Tamano $liberado)) 'ok'
            # Los rechazados van en el resumen y no solo en el registro: son
            # justo los que rompen la prevision, y callarlos aqui devolveria
            # la simulacion al problema que tenia. Ver [CNF-02].
            if ([int]$resultadoLote.Bloqueados -gt 0) {
                Write-Linea ('  NO se habrian borrado: {0} elementos (mira las lineas BLOQUEADO)' -f `
                             $resultadoLote.Bloqueados) 'error'
            }
            Write-Linea ('  Libre en {0}          : {1} -> {2} (estimado)' -f `
                         $Configuracion.Unidad, (Format-Tamano $libreAntes),
                         (Format-Tamano ($libreAntes + $liberado)))
            Write-Linea ''
            Write-Linea '  NO SE HA BORRADO NADA. Quita -Simular para hacerlo de verdad.' 'aviso'
        } else {
            Write-Cabecera 'Resultado'
            Write-Linea ('  Elementos eliminados : {0}' -f $hechos) 'ok'
            if ($conError -gt 0) {
                Write-Linea ('  No se han podido     : {0} (ver el registro)' -f $conError) 'aviso'
            }
            Write-Linea ('  Espacio liberado     : {0}' -f (Format-Tamano $liberado)) 'ok'
            Write-Linea ('  Libre en {0}          : {1} (antes {2})' -f `
                         $Configuracion.Unidad, (Format-Tamano $libreDespues), (Format-Tamano $libreAntes))
        }
        Write-Linea ''
    }
    return 0
}
