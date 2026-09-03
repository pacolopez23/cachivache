<#
.SYNOPSIS
    De la lluvia de registros del diario USN a la lista limpia de cambios
    que aplica Update-IndiceConCambios. Calculo puro.

.DESCRIPTION
    [VEL-02], la mitad que decide. DiarioUsn.ps1 saca registros crudos del
    diario de NTFS; Update-IndiceConCambios (IndiceIncremental.ps1) aplica
    altas, bajas y cambios al indice guardado. Este archivo es lo que hay
    entre las dos cosas, y no toca ni el disco ni el sistema: se le dan
    registros y devuelve cambios. Por eso se prueba entero aqui, en Linux,
    sin un solo volumen NTFS delante.

    -------------------------------------------------------------------
    EL CONTRATO DE SALIDA NO ES MIO Y NO SE TOCA

    Lo fija Update-IndiceConCambios, que es quien consume esto:

        Tipo    'Alta' | 'Baja' | 'Cambio'
        Ruta    ruta completa del archivo
        Bytes   tamanyo de AHORA (alta y cambio; la baja lo ignora)

    Escribir 'Borrado' en Tipo no lanzaria nada: el cambio se descartaria
    en silencio al otro lado y el indice quedaria marcado como no fiable.
    Esa forma de fallo -dos mitades en verde que discrepan en lo que nadie
    acordo- ya costo una sesion entera en este punto (ver la cabecera de
    tests/IndiceCostura.Tests.ps1).

    -------------------------------------------------------------------
    POR QUE ESTO ES SOBRE TODO UN COLAPSADOR

    El diario NO es una lista de cambios: es una lista de EVENTOS. Copiar
    un archivo deja crear + extender + extender + ... + cerrar, cada uno
    como registro propio, y todos del mismo archivo. Al indice solo le
    importa donde acaba cada archivo al terminar la tanda, y averiguar su
    tamanyo cuesta una consulta al disco. Colapsar por archivo es la
    diferencia entre una consulta y cuarenta por archivo tocado, y el
    punto entero existe porque este camino tiene que ser mas barato que
    recorrer el disco.

    -------------------------------------------------------------------
    LO QUE NO SE PUEDE HACER AQUI, Y POR ESO SE INYECTA

    Dos cosas que un registro USN no trae y que solo sabe Windows:

      * LA RUTA. El registro lleva el NOMBRE del archivo y el numero de
        referencia de su carpeta, no la ruta. Traducir ese numero exige la
        API de Windows.
      * EL TAMANYO. El diario dice QUE cambio, nunca CUANTO ocupa ahora.

    Las dos entran como scriptblock -ResolverRuta y MedirBytes-. No es solo
    para poder probarlo sin disco: es que si estuvieran dentro, la unica
    prueba posible seria montar un volumen NTFS, que aqui no existe. Con la
    inyeccion, TODAS las decisiones -que manda sobre que, como se colapsa,
    que se descarta- se prueban de verdad.
#>

function Get-CambioDesdeRazonUsn {
    <#
    .SYNOPSIS
        Traduce la mascara de razones de UN registro USN al vocabulario del
        indice: 'Alta', 'Baja', 'Cambio' o '' si no interesa. Calculo puro.

    .DESCRIPTION
        Contesta por un registro suelto; la vida entera del archivo dentro
        de la tanda la junta ConvertTo-CambiosIndice. Lo que decide aqui:

        CARPETA -> '' SIEMPRE. El indice de archivos no lleva carpetas como
        entradas: sus totales los recalcula Update-IndiceConCambios a
        partir de los archivos. Y al borrar una carpeta el diario emite un
        DELETE por cada archivo de dentro, asi que no se pierde nada.

        LA BAJA MANDA. FILE_DELETE -> 'Baja', pase lo que pase con el resto
        de bits del mismo registro. La mascara de un registro se ACUMULA
        mientras el archivo esta abierto, asi que un archivo creado,
        escrito y borrado puede traer CREATE, EXTEND y DELETE en el mismo
        registro; lo que describe donde acaba el archivo es el borrado.

        Y RENAME_OLD_NAME tambien es 'Baja': ese registro lleva el nombre
        VIEJO, y esa ruta deja de tener bytes. Con UNA excepcion, que es la
        unica en que la baja no manda: si el mismo registro trae ademas
        RENAME_NEW_NAME, el nombre que lleva es el NUEVO -asi lo define el
        campo-, y dar de baja la ruta nueva seria quitar del indice la
        unica que existe. El diario emite los dos bits en registros
        separados, asi que en la practica no se juntan; la regla esta para
        que si algun lector los junta, el resultado siga siendo verdad.

        SI NO, EL ALTA. FILE_CREATE o RENAME_NEW_NAME -> 'Alta'. El registro
        del nombre nuevo lleva la ruta que pasa a tener los bytes.

        SI NO, EL CAMBIO. DATA_OVERWRITE, DATA_EXTEND o DATA_TRUNCATION ->
        'Cambio'. Solo EXTEND y TRUNCATION mueven el tamanyo de verdad, pero
        OVERWRITE entra igual: con el colapsador delante, un 'Cambio' de
        mas cuesta una consulta que devuelve el numero que ya habia, y un
        'Cambio' de menos deja el indice mintiendo para siempre.

        TODO LO DEMAS -> ''. BASIC_INFO_CHANGE (atributos y fechas), CLOSE a
        secas, cero, y cualquier bit que no se conozca. Ninguno cambia el
        numero que el indice guarda, y volver a medir por ellos seria
        recorrer el disco cada vez que pasa un antivirus o se toca una
        fecha, que es justo el trabajo que este camino existe para no
        hacer. Un bit desconocido no lanza: vale "no interesa".

    .PARAMETER Razon
        La mascara USN_REASON_* del registro, como [uint32]. Nulo vale 0.

    .PARAMETER EsCarpeta
        Si el registro es de una carpeta.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [uint32] $Razon,
        [switch] $EsCarpeta
    )

    if ($EsCarpeta) { return '' }

    # Con el sufijo L a proposito: 0x80000000 sin L es un Int32 que vale
    # -2147483648, y comparado con un UInt32 no dice lo que parece. Ya
    # mordio en este repositorio (ver docs/RELEVO.md).
    $DATOS       = 0x00000001L -bor 0x00000002L -bor 0x00000004L
    $CREAR       = 0x00000100L
    $BORRAR      = 0x00000200L
    $NOMBREVIEJO = 0x00001000L
    $NOMBRENUEVO = 0x00002000L

    $mascara = [int64]$Razon

    # EL ORDEN ES LA DECISION: de lo mas definitivo a lo menos.
    if (($mascara -band $BORRAR) -ne 0) { return 'Baja' }
    $renombradoViejo = ($mascara -band $NOMBREVIEJO) -ne 0
    $renombradoNuevo = ($mascara -band $NOMBRENUEVO) -ne 0
    if ($renombradoViejo -and -not $renombradoNuevo)   { return 'Baja' }
    if ($renombradoNuevo -or ($mascara -band $CREAR) -ne 0) { return 'Alta' }
    if (($mascara -band $DATOS) -ne 0)                      { return 'Cambio' }
    return ''
}

function ConvertTo-CambiosIndice {
    <#
    .SYNOPSIS
        Convierte una tanda de registros del diario USN en la lista de
        cambios que espera Update-IndiceConCambios, mas la cuenta de lo que
        se ha quedado por el camino.

    .DESCRIPTION
        Calculo puro salvo por los dos scriptblocks inyectados, que son las
        dos cosas que solo sabe Windows. NO LANZA NUNCA: ni con la lista
        vacia o nula, ni con nulos dentro, ni si el resolutor de rutas o el
        medidor revientan. Un arranque no puede morir porque el diario
        traiga algo raro; como mucho se descarta el indice y se recorre.

        -------------------------------------------------------------
        COMO SE COLAPSA: POR ARCHIVO Y EN ORDEN

        Se agrupa por NumeroReferencia, que es lo que identifica al archivo
        aunque cambie de nombre o de carpeta, y se recorre por Usn
        CRECIENTE, que es el orden en que las cosas pasaron. Cada archivo
        lleva un estado pequenyo -donde esta ahora y si nacio dentro de la
        tanda- y cada registro que interesa lo mueve:

          Alta    el archivo pasa a estar en la ruta de ESTE registro. Si
                  ademas es FILE_CREATE, se apunta que nacio en la tanda.
          Cambio  sigue donde estaba y hay que volver a medirlo (salvo que
                  ya fuera un alta: un alta ya se mide).
          Baja    la ruta de ESTE registro deja de existir. Si el archivo
                  estaba en el indice de antes, esa baja se apunta como
                  PENDIENTE; si nacio en la tanda, no hay nada que dar de
                  baja porque el indice nunca lo tuvo.

        De ahi salen solas las reglas que importan, sin un caso especial
        para cada una:

          crear + extender + cerrar         = una Alta
          crear + borrar                    = NADA
          cambiar + borrar                  = una Baja
          borrar + crear con el mismo nombre = una Alta con el tamanyo nuevo
                  (la baja pendiente y el alta caen en la misma ruta y se
                  quedan con el alta; Update-IndiceConCambios ya trata un
                  alta de algo que tenia como cambio de tamanyo)
          renombrar (OLD_NAME + NEW_NAME)   = Baja(ruta vieja) + Alta(ruta
                  nueva). El UNICO caso en que un archivo produce dos
                  cambios, y las dos rutas se resuelven POR SEPARADO porque
                  mover de carpeta es renombrar: el padre puede cambiar.

        El orden por Usn no es un detalle: si los registros llegan
        desordenados, "crear, borrar" y "borrar, crear" son la misma bolsa
        de bits y respuestas opuestas. Se ordena con una EXPRESION y no por
        nombre de propiedad, porque en Windows PowerShell 5.1 Sort-Object
        por nombre sobre lo que sale de un diccionario no ordena y no
        protesta.

        -------------------------------------------------------------
        EL ARCHIVO QUE SE FUE ENTRE EL DIARIO Y NOSOTROS

        Un alta o un cambio cuya ruta ya no existe -MedirBytes devuelve
        nulo- sale como Baja. El diario se escribio antes de que lo
        leyeramos, y en medio el archivo pudo borrarse; lo que cuenta es lo
        que hay ahora. Y MedirBytes se llama SOLO para altas y cambios: la
        baja ignora los bytes, y medir algo que ya no esta seria trabajo
        para descubrir lo que ya se sabe.

        -------------------------------------------------------------
        LO QUE SE DESCARTA SE CUENTA, y por que no se devuelve solo la lista

        Si ResolverRuta no sabe la ruta, ese cambio se descarta: nunca se
        compone una ruta a medias, porque un cambio aplicado sobre una ruta
        inventada mueve bytes de una carpeta que no es. Y se CUENTA, porque
        el modo de fallo natural de este camino es silencioso: si el
        resolutor deja de funcionar, esto devolveria cero cambios y el
        programa ensenyaria datos viejos como si fueran de hoy. Cero
        cambios y "no ha cambiado nada" se ven igual desde fuera; la cuenta
        es lo unico que los distingue, y con ella quien llama tiene una
        salida barata: recorrer el disco entero.

    .PARAMETER Registros
        Los registros del diario, cada uno con NumeroReferencia,
        NumeroReferenciaPadre, Usn, Razon, EsCarpeta y Nombre. Puede llegar
        nulo, vacio o con nulos dentro.

    .PARAMETER ResolverRuta
        Recibe (NumeroReferenciaPadre, Nombre) y devuelve la ruta completa,
        o nulo o vacio si no la sabe. Se inyecta porque traducir una
        referencia a ruta es cosa de Windows.

    .PARAMETER MedirBytes
        Recibe (Ruta) y devuelve los bytes de ahora como numero, o nulo si
        el archivo no esta. Se inyecta por lo mismo.

    .OUTPUTS
        [pscustomobject] con
            Cambios          @() de objetos Tipo / Ruta / Bytes, en orden
                             de Usn. Es lo que consume Update-IndiceConCambios.
            Descartados      cuantos cambios habia que aplicar y no se pudo
            MotivoDescartes  el porque, en castellano, o '' si no hubo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [object[]] $Registros,
        [Parameter(Mandatory)] [AllowNull()] [scriptblock] $ResolverRuta,
        [Parameter(Mandatory)] [AllowNull()] [scriptblock] $MedirBytes
    )

    $CREAR = 0x00000100L

    # Por que se descarto cada cosa. Cuentas separadas porque "no supe la
    # ruta" y "el registro venia roto" piden arreglos distintos.
    $sinRuta      = 0
    $sinMedidor   = 0
    $malMedido    = 0
    $registroRoto = 0

    # @($null) NO es una lista vacia: es una lista con un nulo dentro.
    $lista = @()
    if ($null -ne $Registros) { $lista = @($Registros) }

    # Cada registro se envuelve con su Usn ya convertido, por dos motivos:
    # que la expresion de ordenacion no pueda lanzar con un Usn raro, y
    # que un registro sin referencia se cuente aqui y no reviente despues.
    $envueltos = [Collections.Generic.List[object]]::new()
    foreach ($registro in $lista) {
        if ($null -eq $registro) { $registroRoto++; continue }
        $referencia = [uint64]0
        $usn = [int64]0
        try {
            if ($null -eq $registro.NumeroReferencia) { throw 'sin referencia' }
            $referencia = [uint64]$registro.NumeroReferencia
            if ($null -ne $registro.Usn) { $usn = [int64]$registro.Usn }
        } catch {
            $registroRoto++
            continue
        }
        $envueltos.Add([pscustomobject]@{
            Referencia = $referencia
            Usn        = $usn
            Registro   = $registro
        })
    }

    # El estado de cada archivo visto en la tanda: donde esta ahora, si
    # nacio aqui, que hay que hacer con el al final y que rutas deja atras.
    $archivos = [Collections.Generic.Dictionary[uint64,object]]::new()

    foreach ($envuelto in (@($envueltos) | Sort-Object -Property { [int64]$_.Usn })) {
        $registro = $envuelto.Registro

        $esCarpeta = $false
        if ($registro.EsCarpeta -is [bool]) { $esCarpeta = $registro.EsCarpeta }

        # La razon puede llegar como [uint32], como long, o como un [int]
        # negativo si alguien leyo el bit alto (CLOSE = 0x80000000) con
        # signo. Se reinterpreta el patron de bits en vez de rechazarlo:
        # rechazarlo tiraria justo los registros de cierre, que son los que
        # traen acumulado todo lo que le paso al archivo.
        $razon = [uint32]0
        try {
            $bruto = [int64]$registro.Razon
            if ($bruto -lt 0 -and $bruto -ge [int]::MinValue) { $bruto = $bruto -band 0xFFFFFFFFL }
            $razon = [uint32]$bruto
        } catch {
            $razon = [uint32]0
        }

        $tipo = Get-CambioDesdeRazonUsn -Razon $razon -EsCarpeta:$esCarpeta
        if ($tipo.Length -eq 0) { continue }

        $nombre = ''
        if ($null -ne $registro.Nombre) { $nombre = [string]$registro.Nombre }

        $estado = $null
        if ($archivos.ContainsKey($envuelto.Referencia)) {
            $estado = $archivos[$envuelto.Referencia]
        } else {
            $estado = [pscustomobject]@{
                Tipo     = ''       # que hay que hacer al final con la ruta actual
                Padre    = $null
                Nombre   = ''
                Usn      = [int64]0
                Nacido   = $false   # nacio en esta tanda: el indice nunca lo tuvo
                Bajas    = [Collections.Generic.List[object]]::new()
            }
            $archivos[$envuelto.Referencia] = $estado
        }

        switch ($tipo) {
            'Baja' {
                # La ruta de ESTE registro deja de existir. Solo hay que
                # darla de baja si el indice de antes podia tenerla.
                if (-not $estado.Nacido) {
                    $estado.Bajas.Add([pscustomobject]@{
                        Padre  = $registro.NumeroReferenciaPadre
                        Nombre = $nombre
                        Usn    = $envuelto.Usn
                    })
                }
                $estado.Tipo = ''
            }
            'Alta' {
                if (($razon -band $CREAR) -ne 0) { $estado.Nacido = $true }
                $estado.Tipo   = 'Alta'
                $estado.Padre  = $registro.NumeroReferenciaPadre
                $estado.Nombre = $nombre
                $estado.Usn    = $envuelto.Usn
            }
            'Cambio' {
                # Un alta ya se mide entera: un cambio encima no anyade nada.
                if ($estado.Tipo -ne 'Alta') { $estado.Tipo = 'Cambio' }
                $estado.Padre  = $registro.NumeroReferenciaPadre
                $estado.Nombre = $nombre
                $estado.Usn    = $envuelto.Usn
            }
        }
    }

    # Resolver es cosa de quien llama, y puede lanzar o devolver cualquier
    # cosa: se envuelve y se normaliza a "una ruta o nada". El valor se
    # pasa como PARAMETRO y no confiando en $_: un scriptblock invocado con
    # & corre en otro ambito, y que la variable automatica llegue depende
    # de la version.
    $resolver = {
        param($Padre, $Nombre)
        if ($null -eq $ResolverRuta) { return '' }
        try {
            $bruto = & $ResolverRuta $Padre $Nombre
            if ($null -eq $bruto) { return '' }
            return ([string]$bruto).Trim()
        } catch {
            return ''
        }
    }

    $cambios = [Collections.Generic.List[object]]::new()

    foreach ($estado in $archivos.Values) {
        $rutaFinal = ''
        if ($estado.Tipo.Length -gt 0) {
            $rutaFinal = & $resolver $estado.Padre $estado.Nombre
            if ($rutaFinal.Length -eq 0) { $sinRuta++ }
        }

        # Las bajas pendientes, cada una con SU ruta. Se quita la que cae
        # en la misma ruta que el alta final (borrar y volver a crear con
        # el mismo nombre, o renombrar A -> B -> A): el alta la cubre, y
        # dejar las dos seria decir dos cambios donde hubo uno. Y una
        # misma ruta no se da de baja dos veces.
        $vistas = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($baja in $estado.Bajas) {
            $ruta = & $resolver $baja.Padre $baja.Nombre
            if ($ruta.Length -eq 0) { $sinRuta++; continue }
            if ($rutaFinal.Length -gt 0 -and $ruta.Equals($rutaFinal, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not $vistas.Add($ruta)) { continue }
            $cambios.Add([pscustomobject]@{
                Tipo  = 'Baja'
                Ruta  = $ruta
                Bytes = 0.0
                Usn   = $baja.Usn
            })
        }

        if ($estado.Tipo.Length -eq 0 -or $rutaFinal.Length -eq 0) { continue }

        # Solo aqui se mide: altas y cambios. Sin medidor no se inventa un
        # tamanyo, y menos un cero, que es un tamanyo valido y vaciaria del
        # indice unos bytes que probablemente siguen en el disco.
        if ($null -eq $MedirBytes) { $sinMedidor++; continue }
        $medido = $null
        try {
            $medido = & $MedirBytes $rutaFinal
        } catch {
            # Un medidor que revienta no es "el archivo no esta": es que no
            # se sabe. Se descarta y se cuenta; no se convierte en baja.
            $malMedido++
            continue
        }

        if ($null -eq $medido) {
            # El archivo se fue entre que se escribio el diario y que lo
            # leimos. Lo que cuenta es lo que hay ahora.
            $cambios.Add([pscustomobject]@{
                Tipo  = 'Baja'
                Ruta  = $rutaFinal
                Bytes = 0.0
                Usn   = $estado.Usn
            })
            continue
        }

        $bytes = 0.0
        try {
            $bytes = [double]$medido
        } catch {
            $malMedido++
            continue
        }
        if ([double]::IsNaN($bytes) -or $bytes -lt 0) { $malMedido++; continue }

        $cambios.Add([pscustomobject]@{
            Tipo  = $estado.Tipo
            Ruta  = $rutaFinal
            Bytes = $bytes
            Usn   = $estado.Usn
        })
    }

    # El orden de salida es el orden en que pasaron las cosas: si dos
    # archivos distintos tocan la misma ruta -uno borrado y otro creado en
    # su sitio-, aplicarlos al reves deja el indice sin la entrada buena.
    $ordenados = @(@($cambios) | Sort-Object -Property { [int64]$_.Usn } | ForEach-Object {
        [pscustomobject]@{ Tipo = $_.Tipo; Ruta = $_.Ruta; Bytes = $_.Bytes }
    })

    $descartados = $sinRuta + $sinMedidor + $malMedido + $registroRoto
    $motivo = ''
    if ($descartados -gt 0) {
        $partes = [Collections.Generic.List[string]]::new()
        if ($sinRuta -gt 0)      { $partes.Add(('{0} sin ruta que se pudiera resolver' -f $sinRuta)) }
        if ($sinMedidor -gt 0)   { $partes.Add(('{0} sin nada con qué medir el tamaño' -f $sinMedidor)) }
        if ($malMedido -gt 0)    { $partes.Add(('{0} cuyo tamaño no se pudo medir' -f $malMedido)) }
        if ($registroRoto -gt 0) { $partes.Add(('{0} registros del diario ilegibles' -f $registroRoto)) }
        # Parentesis alrededor de la concatenacion: -f se enlaza mas fuerte
        # que +, y sin ellos solo se formatearia el ultimo trozo.
        $motivo = ('Se han descartado {0} cambios del diario ({1}). Los cambios que faltan no se ' +
                   'van a aplicar, así que conviene recorrer el disco entero.') -f $descartados, ($partes -join '; ')
    }

    return [pscustomobject]@{
        Cambios         = $ordenados
        Descartados     = $descartados
        MotivoDescartes = $motivo
    }
}
