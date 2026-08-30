<#
.SYNOPSIS
    Formato de tamaños, tiempos y rutas para MOSTRAR al usuario.
.DESCRIPTION
    Funciones puras, sin efectos secundarios. Se cargan tanto en el hilo
    de la interfaz como en los hilos de análisis.

    La normalizacion de texto para comparar identidad (Remove-Tildes,
    ConvertTo-Token) NO vive aquí: esta en Texto.ps1, porque es lógica de
    la que depende la guardia de seguridad y no un detalle de
    presentación. Ver docs/ESTRUCTURA.md (sección 6).
#>

function ConvertTo-DoubleSeguro {
    <#
    .SYNOPSIS
        Convierte a número lo que venga, o devuelve 0 si no se puede.

    .DESCRIPTION
        Para los campos que salen de un JSON escrito en disco. Ese archivo
        lo puede haber editado el usuario, lo puede haber escrito una
        versión anterior del programa con otro esquema, o puede llegar con
        una forma inesperada; nada de eso justifica que el programa no
        abra.

        Y no es hipotetico: un array donde se esperaba un número hizo
        exactamente eso, tirar la ventana al arrancar, porque
        "[double]$entrada.Bytes" lanza en vez de devolver algo. Ver la
        cabecera de Get-Historial en Historial.ps1.

        Cero es la respuesta correcta ante la duda: un total que se queda
        corto se nota y se puede investigar; un programa que no arranca,
        no.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param($Valor)

    if ($null -eq $Valor) { return 0.0 }

    # Un array no es "un número raro", es otra cosa: no se suma ni se toma
    # el primero, que sería inventarse un dato.
    #
    # En PowerShell 7 esta línea es REDUNDANTE: [double] sobre un array
    # lanza, también con un solo elemento, y el catch de abajo devolveria 0
    # igualmente. Se comprueba aquí a propósito, y no por descuido: el
    # fallo que obligo a escribir esta función fue precisamente una
    # diferencia de comportamiento entre 5.1 y 7 que las pruebas -que
    # corren en 7- no podian ver. Fiarse de que una conversión lanza igual
    # en las dos versiones es repetir el mismo error. Que el resultado sea
    # el mismo pase lo que pase sale por unos microsegundos.
    if ($Valor -is [System.Collections.IEnumerable] -and $Valor -isnot [string]) { return 0.0 }

    try {
        return [double]$Valor
    } catch {
        return 0.0
    }
}

function ConvertTo-RutaAnonima {
    <#
    .SYNOPSIS
        Sustituye los datos que identifican al equipo y a su dueño por
        marcadores, dejando la ruta legible.

    .DESCRIPTION
        Un informe de Cachivache es, sin quererlo, un retrato del equipo:
        cada candidato lleva una ruta, y casi todas empiezan por
        "C:\Users\<nombre de usuario real>". Un informe de mil filas
        publica ese nombre mil veces.

        Eso importa porque SECURITY.md pide adjuntar el informe y el
        registro para reportar un fallo. Sin esta función, colaborar con el
        proyecto obligaba a publicar el nombre de usuario de Windows y el
        del equipo. Nadie deberia tener que elegir entre reportar un fallo
        y su privacidad.

        Se sustituye de lo mas especifico a lo mas general -el perfil
        entero antes que el nombre suelto- para que "C:\Users\paco\paco.txt"
        no quede como "C:\Users\<usuario>\<usuario>.txt". El nombre suelto
        se cambia solo cuando aparece como SEGMENTO de ruta, no dentro de
        otra palabra: si el usuario se llama "ana", una carpeta llamada
        "Semana" no tiene por que salir mutilada.

        Lo que NO hace: adivinar. Nombres de proyecto, de cliente o de
        archivo pueden identificar tanto como el usuario, y eso no lo puede
        decidir un reemplazo de texto. Por eso el aviso de SECURITY.md sigue
        diciendo que hay que leer el informe antes de publicarlo.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Transforma una cadena: no toca el sistema.')]
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Texto)

    if ([string]::IsNullOrEmpty($Texto)) { return $Texto }
    $resultado = $Texto

    # 1. El perfil completo, que es la coincidencia mas larga y por tanto
    #    la primera. Con y sin barra final.
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $perfil = $env:USERPROFILE.TrimEnd('\')
        $resultado = $resultado -replace [regex]::Escape($perfil), '<perfil>'
    }

    # 2. El nombre de usuario suelto, solo como segmento de ruta.
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME) -and $env:USERNAME.Length -ge 2) {
        $resultado = $resultado -replace
            ('(?i)(?<=[\\/])' + [regex]::Escape($env:USERNAME) + '(?=[\\/]|$)'), '<usuario>'
    }

    # 3. El nombre del equipo, aparezca donde aparezca.
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME) -and $env:COMPUTERNAME.Length -ge 2) {
        $resultado = $resultado -replace ('(?i)' + [regex]::Escape($env:COMPUTERNAME)), '<equipo>'
    }

    return $resultado
}

function Format-Tamano {
    <#
    .SYNOPSIS
        Convierte bytes en un texto legible (KB, MB, GB, TB).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [double] $Bytes
    )
    process {
        if ($Bytes -lt 0) { $Bytes = 0 }
        if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
        if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
        if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
        if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
        return ('{0:N0} B' -f $Bytes)
    }
}

function ConvertFrom-NumeroLocal {
    <#
    .SYNOPSIS
        Interpreta un número de texto sin asumir el idioma de Windows.
    .DESCRIPTION
        Herramientas como vssadmin o DISM escriben sus cifras con el
        separador decimal del idioma del sistema: coma en español, punto
        en inglés. Tratar siempre el punto como separador de miles rompe en
        Windows en inglés: "15.5 GB" se convertia en 155 GB. Ver [C-04] en
        docs/OPTIMIZACIONES.md.

        Regla: si aparecen los dos separadores, el último es el decimal.
        Si solo aparece uno, se mira el grupo final: 1-2 digitos es
        decimal, exactamente 3 (o más de un grupo) es separador de miles.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([string] $Texto)

    $limpio = if ($null -ne $Texto) { $Texto.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($limpio)) { return 0.0 }

    $tienePunto = $limpio.Contains('.')
    $tieneComa  = $limpio.Contains(',')
    $normalizado = $limpio

    if ($tienePunto -and $tieneComa) {
        # El separador que aparece más a la derecha es el decimal.
        if ($limpio.LastIndexOf('.') -gt $limpio.LastIndexOf(',')) {
            $normalizado = $limpio.Replace(',', '')
        } else {
            $normalizado = $limpio.Replace('.', '').Replace(',', '.')
        }
    } elseif ($tienePunto -or $tieneComa) {
        $separador = if ($tienePunto) { '.' } else { ',' }
        $partes = $limpio.Split($separador)
        $esDecimal = $partes.Count -eq 2 -and $partes[-1].Length -le 2
        $normalizado = if ($esDecimal) {
            $limpio.Replace($separador, '.')
        } else {
            $limpio.Replace($separador, '')
        }
    }

    $resultado = 0.0
    [void][double]::TryParse(
        $normalizado,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref] $resultado)
    return $resultado
}

function ConvertTo-BytesConUnidad {
    <#
    .SYNOPSIS
        Convierte un número y una unidad de texto (KB/MB/GB/TB) a bytes.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [double] $Numero,
        [string] $Unidad
    )
    switch ($Unidad.ToUpperInvariant()) {
        'KB' { return $Numero * 1KB }
        'MB' { return $Numero * 1MB }
        'GB' { return $Numero * 1GB }
        'TB' { return $Numero * 1TB }
        default { return 0.0 }
    }
}


function Get-RutaCorta {
    <#
    .SYNOPSIS
        Acorta una ruta sustituyendo el perfil del usuario por "~".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Ruta)

    if ([string]::IsNullOrWhiteSpace($Ruta)) { return '' }
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $Ruta }
    return ($Ruta -replace [regex]::Escape($env:USERPROFILE), '~')
}

function Get-RutaElidida {
    <#
    .SYNOPSIS
        Recorta una ruta por el centro para que quepa en la interfaz.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Ruta,
        [int]    $Maximo = 70
    )

    $corta = Get-RutaCorta $Ruta
    if ($corta.Length -le $Maximo) { return $corta }

    $mitad = [Math]::Floor(($Maximo - 3) / 2)
    return $corta.Substring(0, $mitad) + '...' + $corta.Substring($corta.Length - $mitad)
}

function Format-Duracion {
    <#
    .SYNOPSIS
        Convierte un TimeSpan en un texto breve en castellano.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([TimeSpan] $Duracion)

    if ($Duracion.TotalSeconds -lt 1)  { return 'menos de 1 s' }
    if ($Duracion.TotalSeconds -lt 60) { return ('{0:N0} s' -f $Duracion.TotalSeconds) }
    if ($Duracion.TotalMinutes -lt 60) {
        return ('{0:N0} min {1:N0} s' -f [Math]::Floor($Duracion.TotalMinutes), $Duracion.Seconds)
    }
    return ('{0:N0} h {1:N0} min' -f [Math]::Floor($Duracion.TotalHours), $Duracion.Minutes)
}

function Format-ProgresoAnalisis {
    <#
    .SYNOPSIS
        La línea de estado mientras se analiza: qué se está haciendo,
        cuánto se lleva y cuánto se ha encontrado.

    .DESCRIPTION
        Antes ponia solo "Analizando Duplicados (8 de 21)". La barra avanza
        POR MODULO TERMINADO, asi que el modulo de duplicados podia estar
        cinco minutos con la barra clavada en el 38% y sin un solo numero
        moviendose. Para el usuario eso no se distingue de un cuelgue, y lo
        razonable ante un programa colgado es matarlo -a mitad de una
        limpieza-. Ver [USO-07] en docs/HOJA-DE-RUTA.md.

        El arreglo no es una barra mas fina: es ensenyar DOS DATOS QUE SE
        MUEVEN. El tiempo avanza siempre, aunque el modulo no encuentre
        nada, y el contador de elementos avanza cuando encuentra. Con
        cualquiera de los dos cambiando, el programa demuestra que sigue
        vivo sin tener que prometer cuanto le queda.

        Es una funcion aparte, y pura, porque asi se puede probar: la
        alternativa era componer la cadena dentro del temporizador de WPF,
        que no arranca en las pruebas.

    .PARAMETER Modulo
        Nombre del módulo en curso. Va con su contador PEGADO -"Duplicados
        (8 de 21)"- y separado del mensaje: el módulo puede traer su propia
        cuenta, y "grupo 3 de 47 (8 de 21)" son dos contadores seguidos que
        no hay quien lea. Se vio al mirar la línea escrita, no al pensarla.
    .PARAMETER Mensaje
        Lo que el módulo dice estar haciendo ahora mismo.
    .PARAMETER Indice
        Cuántos módulos van, empezando en 1.
    .PARAMETER Transcurrido
        Desde que empezó el análisis entero, no este módulo: lo que
        importa es que el número cambie.
    .PARAMETER Elementos
        Encontrados hasta ahora, sumando todos los módulos.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]   $Modulo  = '',
        [string]   $Mensaje = '',
        [int]      $Indice  = 0,
        [int]      $Total   = 0,
        [TimeSpan] $Transcurrido = [TimeSpan]::Zero,
        [int]      $Elementos = 0
    )

    $partes = [Collections.Generic.List[string]]::new()

    $cabeza = if ([string]::IsNullOrWhiteSpace($Modulo)) { 'Analizando' } else { $Modulo }
    if ($Total -gt 0) { $cabeza = '{0} ({1} de {2})' -f $cabeza, $Indice, $Total }
    $partes.Add($cabeza)

    # El mensaje del modulo solo se anyade si dice algo distinto del nombre
    # del modulo: al arrancar uno, los dos valen lo mismo y quedaria
    # "Duplicados (8 de 21) - Duplicados".
    if (-not [string]::IsNullOrWhiteSpace($Mensaje) -and $Mensaje -ne $Modulo) {
        $partes.Add($Mensaje)
    }

    # El tiempo solo aparece a partir del segundo: antes de eso cambia tan
    # rapido que parpadea, y con un modulo corto no aporta nada.
    if ($Transcurrido.TotalSeconds -ge 1) { $partes.Add((Format-Duracion $Transcurrido)) }

    if ($Elementos -gt 0) {
        $partes.Add(('{0} {1}' -f $Elementos, $(if ($Elementos -eq 1) { 'elemento' } else { 'elementos' })))
    }

    return ($partes -join '  ·  ')
}

function Format-Antiguedad {
    <#
    .SYNOPSIS
        Describe cuanto hace que se toco algo por última vez.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([datetime] $Fecha)

    if ($Fecha -le [datetime]'1900-01-02') { return 'fecha desconocida' }
    $dias = [int]((Get-Date) - $Fecha).TotalDays
    if ($dias -le 0)   { return 'hoy' }
    if ($dias -eq 1)   { return 'ayer' }
    if ($dias -lt 30)  { return "hace $dias días" }
    if ($dias -lt 365) {
        # Singular. Decia "hace 1 meses" durante todo un mes del anyo, que
        # es el mismo descuido que ya se corrigio en las cabeceras de grupo
        # ("1 elementos", ver [USO-15]). Aqui se arregla con un if y no con
        # un plural automatico: son dos casos, no un mecanismo.
        $meses = [int][Math]::Floor($dias / 30)
        if ($meses -eq 1) { return 'hace un mes' }
        return ('hace {0} meses' -f $meses)
    }
    $anios = [Math]::Floor($dias / 365)
    # El singular de los anyos ya estaba resuelto aqui desde antes. Al
    # arreglar el de los meses anyadi una segunda rama identica sin mirar
    # que esta existia: codigo muerto, inalcanzable, y de los que no falla
    # nunca. Lo cazo la prueba al esperar un texto que no salia.
    if ($anios -eq 1) { return 'hace más de 1 año' }
    return "hace más de $anios años"
}

function Format-ResumenSimulacion {
    <#
    .SYNOPSIS
        Lo que la simulación deja escrito EN LA PANTALLA donde se decide.

    .DESCRIPTION
        La simulación hacia todo su trabajo y lo contaba solo en el panel de
        Registro. Quien pulsa "Simular limpieza" esta mirando la tabla de
        Resultados, y ahi no cambiaba absolutamente nada: ni un numero, ni
        una marca, ni un aviso. En la primera prueba real el usuario la
        pulso TRES VECES seguidas convencido de que el boton estaba roto.

        Hacer el trabajo y no decirlo es, desde el lado de quien mira,
        indistinguible de no hacerlo. Ver [USO-15].

        Devuelve el texto ya montado, con las cuatro cosas que hay que
        saber: que era una simulación, cuanto se habria liberado, que hay
        que hacer ahora, y -si los hay- cuantos NO se habrian podido borrar,
        que es la parte que no se puede callar sin volver a prometer un
        espacio que no llega.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [int]    $Simulados,
        [Parameter(Mandatory)] [double] $Liberado,
        [int] $Bloqueados = 0
    )

    if ($Simulados -le 0) {
        return ('Simulación terminada: no habia nada que borrar. ' +
                'No se ha borrado nada, porque no se ha tocado nada.')
    }

    $elementos = if ($Simulados -eq 1) { '1 elemento' } else { '{0} elementos' -f $Simulados }

    # ::new() y NO New-Object. New-Object System.Collections.Generic.List
    # devuelve algo que @() no sabe recorrer, y eso es lo que rompio TODOS
    # los informes en [COR-07]. Lo escribi otra vez aqui sin pensarlo; lo
    # paro la invariante que quedo de aquella.
    $lineas = [System.Collections.Generic.List[string]]::new()

    # Se arma en una variable y DESPUES se anyade. Escribirlo dentro del
    # parentesis de .Add() no vale: alli la coma del '-f' la lee PowerShell
    # como separador de argumentos DEL METODO, asi que la cadena se queda
    # con un solo valor y {1} revienta. Es la tercera vez que el '-f' muerde
    # en este proyecto, y la primera que lo caza una prueba en vez del
    # usuario.
    $primera = ('Esto era una simulación: NO se ha borrado nada. ' +
                'Se habrian eliminado {0} y liberado {1}.') -f $elementos, (Format-Tamano $Liberado)
    [void]$lineas.Add($primera)

    if ($Bloqueados -gt 0) {
        $cuantos = if ($Bloqueados -eq 1) { '1 no se habria borrado' } else { '{0} no se habrian borrado' -f $Bloqueados }
        $aviso = 'De esos, {0}: el detalle esta en Registro, en las lineas [BLOQUEADO].' -f $cuantos
        [void]$lineas.Add($aviso)
    }

    [void]$lineas.Add('Lo marcado sigue marcado. Para hacerlo de verdad, quita "Solo simular" y vuelve a pulsar.')

    return ($lineas -join ' ')
}
