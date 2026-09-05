<#
.SYNOPSIS
    Que le pasa al indice de disco cuando el programa acaba de limpiar.
    Calculo puro: no toca el disco ni el reloj.

.DESCRIPTION
    [VEL-04]. Despues de limpiar, el usuario vuelve a analizar para
    comprobar que ha funcionado, y hoy eso recorre el disco entero otra vez
    -42 segundos- para descubrir exactamente lo que el programa acaba de
    hacer el mismo. Aqui se convierte el resultado de una limpieza en la
    lista de cambios que Update-IndiceConCambios sabe aplicar.

    -------------------------------------------------------------------
    DE DONDE SALE ESTE ARCHIVO: DE QUE [VEL-02] SE MURIO

    La idea original era leer el diario de cambios de NTFS. Se escribio, se
    ejecuto en Windows y se midio: 74-82 registros por segundo -70 minutos
    para el diario entero, contra 42 segundos de recorrer el disco- y una
    retencion de entre 10 y 80 minutos, cuando un limpiador se usa cada
    semanas. Descartado. Ver docs/VEL-02-MEDICION.md, tercera parte.

    Pero al medir aparecio el unico caso donde el atajo se disparaba de
    verdad -reanalizar justo despues de limpiar- y ese caso NO NECESITA EL
    DIARIO: el programa ya sabe que acaba de borrar. Esto es ese cable.

    Y sale mejor que lo que sustituye: sin administrador, sin NTFS, sin
    P/Invoke. Funciona en FAT32, en exFAT y en unidades de red, donde el
    diario ni siquiera existe. Y se puede probar entero, que es justo lo
    que con [VEL-02] no se podia.

    -------------------------------------------------------------------
    LA REGLA, Y NO ES LA QUE PARECE

    "Ante la duda, ser pesimista" suena obvio hasta que hay que decidir
    hacia que lado. Aqui pesimista es DEJAR ENTRADAS, no quitarlas:

      - Si el indice conserva un archivo que ya no esta, SOBREESTIMA lo
        ocupado. El siguiente analisis ofrecera borrar algo que ya no
        existe y no pasara nada: al intentarlo dira "la ruta ya no existe".
        Molesto e inofensivo.

      - Si el indice quita un archivo que SIGUE AHI, SUBESTIMA. Ese archivo
        no se vuelve a ofrecer nunca, y el programa miente por omision: el
        usuario cree que su disco esta mas limpio de lo que esta. Ese es el
        fallo grave, y es el que este archivo existe para no cometer.

    Por eso NO hay invalidacion global. Un candidato cuyo efecto no se
    conoce no estropea el resto: simplemente no aporta ninguna baja, y sus
    archivos se quedan en el indice hasta el siguiente recorrido completo.
    La primera version de esto invalidaba el indice entero en cuanto
    aparecia un metodo incierto -y como casi toda limpieza vacia la
    papelera o lanza un comando, el atajo no se habria disparado nunca-.

    -------------------------------------------------------------------
    POR QUE HAY QUE MIRAR EL METODO Y NO SOLO "SE HIZO"

    Los ocho metodos de New-Candidato no dejan la misma huella:

      Ruta, Contenido            -> lo que colgaba de Ruta ha DESAPARECIDO.
                                    Son los dos unicos que permiten dar de
                                    baja el subarbol entero.
      CarpetaVacia, Informativo  -> no habia archivos que el indice
                                    conociera: carpetas vacias, o nada.
      FirefoxCache, Miniaturas   -> borran SOLO una parte a proposito
                                    (cache2, thumbcache_*.db). Saber cual
                                    exige repetir aqui la regla del modulo,
                                    y dos sitios decidiendo lo mismo es lo
                                    que este proyecto evita. Inciertos.
      Papelera, Comando          -> la API del shell y un ejecutable
                                    externo. No se sabe que han tocado.

    La clasificacion vive en tres listas y no en un switch escondido para
    que una prueba pueda exigir que los ocho metodos del ValidateSet esten
    en exactamente una de ellas. Un metodo nuevo sin clasificar no puede
    colarse contandose como "no hace nada", que seria el fallo por omision
    de arriba. Es la misma forma que $script:MetodosRecuperables en
    Remove.ps1 y la misma invariante que [COR-04].

    -------------------------------------------------------------------
    Y "HECHO" NO BASTA. La otra mitad del criterio.

    Remove.ps1 pone Hecho a $true cuando la rama corrio sin lanzar, pero
    eso incluye el resultado PARCIAL: "Quedan 600 MB: archivos en uso por
    algun programa abierto" deja Hecho a $true con Error relleno, porque
    para el registro de auditoria eso si se hizo. Para el indice no: no se
    sabe QUE 600 MB han sobrevivido. Asi que aqui hace falta Hecho a $true
    Y Error vacio. Es el mismo dato leido para otra pregunta.
#>

# Los ocho metodos de New-Candidato, repartidos por lo que le hacen al
# indice. La suma tiene que ser exactamente el ValidateSet de -Metodo:
# hay una invariante que lo comprueba y que falla si alguien anyade un
# metodo y no lo clasifica aqui.
$script:MetodosBorranSubarbol = @('Contenido', 'Ruta')
$script:MetodosNoTocanIndice  = @('CarpetaVacia', 'Informativo')
$script:MetodosEfectoIncierto = @('FirefoxCache', 'Miniaturas', 'Papelera', 'Comando')

function Get-EfectoEnIndice {
    <#
    .SYNOPSIS
        Que le hace al indice un metodo de borrado. Decision pura.

    .OUTPUTS
        'Subarbol'    todo lo que colgaba de la ruta ha desaparecido
        'Nada'        no habia nada que el indice conociera
        'Incierto'    no se sabe que ha tocado; el indice se deja como esta

    .NOTES
        UN METODO DESCONOCIDO CONTESTA 'Incierto', NUNCA 'Nada'. Son las
        dos respuestas que mas se parecen y la diferencia es justo el fallo
        grave: 'Nada' dice "no hay nada que quitar" y 'Incierto' dice "no
        se que quitar". Con un metodo nuevo sin clasificar, contestar
        'Nada' seria correcto por casualidad; contestar 'Incierto' es
        correcto siempre.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Metodo)

    $m = ''
    if ($null -ne $Metodo) { $m = $Metodo.Trim() }
    if ($script:MetodosBorranSubarbol -contains $m) { return 'Subarbol' }
    if ($script:MetodosNoTocanIndice  -contains $m) { return 'Nada' }
    return 'Incierto'
}

function Test-CandidatoBorroSuSubarbol {
    <#
    .SYNOPSIS
        Se puede afirmar que todo lo que colgaba de la ruta de este
        candidato ha desaparecido? Decision pura.

    .DESCRIPTION
        Las cuatro condiciones, y cada una tapa un fallo distinto:

        1. El metodo borra el subarbol entero. Ver las tres listas.
        2. Hecho a $true: la rama corrio.
        3. Error vacio: no fue un resultado PARCIAL. Ver la cabecera.
        4. Ruta no vacia: sin ruta no hay nada que buscar en el indice, y
           una cadena vacia como prefijo casaria con TODO.

        La cuarta parece de tramite y es la mas peligrosa de las cuatro:
        para los metodos Papelera y Comando la Ruta es una etiqueta, no una
        carpeta. Que ademas esten clasificados como inciertos es un cinturon
        de mas, no el motivo.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [AllowNull()] $Candidato)

    if ($null -eq $Candidato) { return $false }
    if ((Get-EfectoEnIndice -Metodo ([string]$Candidato.Metodo)) -ne 'Subarbol') { return $false }
    if (-not $Candidato.Hecho) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Candidato.Error)) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Candidato.Ruta)) { return $false }
    return $true
}

function Get-CambiosDeLimpieza {
    <#
    .SYNOPSIS
        Convierte el resultado de una limpieza en las bajas que
        Update-IndiceConCambios sabe aplicar. Calculo puro, nunca lanza.

    .PARAMETER Candidatos
        Los candidatos DESPUES de limpiar, con Hecho, Error y Metodo ya
        puestos por Remove.ps1.

    .PARAMETER RutasIndice
        Las rutas que el indice conoce hoy: las claves de su tabla de
        archivos. Se recorren una sola vez.

    .OUTPUTS
        Cambios      las bajas, en la forma {Tipo; Ruta} que espera
                     Update-IndiceConCambios
        Raices       las rutas de las que se ha dado de baja el subarbol
        Ciertos      candidatos que han aportado bajas
        Inciertos    candidatos limpiados cuyo efecto no se conoce; sus
                     archivos se quedan en el indice a proposito
        Omitidos     candidatos que no tenian nada que aportar (no se
                     hicieron, o su metodo no toca el indice)

    .NOTES
        SI NO HAY NINGUNA RAIZ, NO SE RECORRE EL INDICE. Un millon de
        comparaciones para saber que no hay nada que quitar es exactamente
        el coste que este punto existe para no pagar.

        LA PERTENENCIA LA DECIDE Get-RaizQueContiene, DE Guard.ps1, y no un
        StartsWith escrito aqui. Es la misma pregunta que se hace la
        guardia -"esta ruta cuelga de esta otra?"- y ya trae resueltas las
        dos trampas: normaliza antes de comparar, y compara con
        StringComparison::Ordinal, porque con la cultura actual un caracter
        ignorable mete una ruta dentro de otra sin estarlo. Escribirla otra
        vez aqui seria un segundo sitio decidiendo lo mismo, con el
        agravante de que el primero es el archivo mas importante del
        programa.

        LA PROPIA RAIZ SE ANYADE APARTE. Get-RaizQueContiene exige la barra
        final -para que una raiz autorizada nunca resulte borrable por si
        misma-, asi que no casa la ruta consigo misma. Aqui si hace falta:
        con el metodo Ruta, el candidato PUEDE SER un archivo suelto, y su
        propia ruta es la unica entrada que el indice tiene de el. Sin esa
        comparacion extra, limpiar un archivo lo dejaria en el indice para
        siempre.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Candidatos,
        [Parameter(Mandatory)] [AllowNull()] $RutasIndice
    )

    $cambios = [Collections.Generic.List[object]]::new()
    $raices  = [Collections.Generic.List[object]]::new()
    $ciertos = 0; $inciertos = 0; $omitidos = 0

    # @($null) es una lista con un nulo dentro, no una lista vacia. Ya
    # mordio en Update-IndiceConCambios y esta funcion le da de comer.
    $lista = @()
    if ($null -ne $Candidatos) { $lista = @($Candidatos | Where-Object { $null -ne $_ }) }

    foreach ($c in $lista) {
        if (Test-CandidatoBorroSuSubarbol -Candidato $c) {
            $raices.Add([string]$c.Ruta)
            $ciertos++
            continue
        }
        # Se separa "no se sabe" de "no habia nada" porque son dos
        # respuestas distintas y quien llama las cuenta distinto: los
        # inciertos son la deuda que se salda con el siguiente recorrido
        # completo, y merecen poder decirse en voz alta.
        $limpiado = $c.Hecho -and [string]::IsNullOrWhiteSpace([string]$c.Error)
        if ($limpiado -and (Get-EfectoEnIndice -Metodo ([string]$c.Metodo)) -eq 'Incierto') {
            $inciertos++
        } else {
            $omitidos++
        }
    }

    if ($raices.Count -gt 0 -and $null -ne $RutasIndice) {
        $comoArray = @($raices.ToArray())
        foreach ($ruta in @($RutasIndice)) {
            if ([string]::IsNullOrWhiteSpace([string]$ruta)) { continue }
            $texto = [string]$ruta
            $dentro = -not [string]::IsNullOrEmpty((Get-RaizQueContiene -Ruta $texto -Raices $comoArray))
            if (-not $dentro) {
                # La raiz consigo misma: el candidato era un archivo suelto.
                foreach ($r in $comoArray) {
                    if ($texto.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { $dentro = $true; break }
                }
            }
            if ($dentro) {
                $cambios.Add([pscustomobject]@{ Tipo = 'Baja'; Ruta = $texto })
            }
        }
    }

    return [pscustomobject]@{
        Cambios   = $cambios.ToArray()
        Raices    = $raices.ToArray()
        Ciertos   = $ciertos
        Inciertos = $inciertos
        Omitidos  = $omitidos
    }
}
