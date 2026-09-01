<#
.SYNOPSIS
    Las decisiones del banco de pruebas. Calculo puro, sin tocar el disco.

.DESCRIPTION
    Vive aparte de Banco-Pruebas.ps1 por el mismo motivo por el que Xaml.ps1
    vive aparte de Window.ps1: este archivo se puede dot-sourcear sin que
    pase nada. El otro CREA Y BORRA ARCHIVOS, asi que dot-sourcearlo desde
    una prueba seria ejecutar el banco entero.

    Y aqui esta lo que de verdad importa proteger. El banco monta cebos
    dentro de las carpetas del usuario -en Documentos- porque es el unico
    sitio donde los modulos de Cachivache los van a encontrar, y despues los
    quita. O sea: un guion que borra recursivamente una carpeta calculada en
    tiempo de ejecucion. Si esa cuenta sale mal una sola vez, borra lo que no
    debe. Por eso las dos decisiones que deciden DONDE y SI se puede, salen
    de aqui y van probadas una a una.

    Y desde [VAL-03] aqui vive tambien EL CATALOGO DE CEBOS y las cuentas
    que juzgan una pasada del banco. El motivo es el mismo de siempre: el
    banco se ejecuta ahora en cada push, en un agente de GitHub, y quien
    decide si un analisis ha propuesto algo que no debia no puede ser un
    trozo de YAML sin pruebas. El paso de la CI solo invoca lo de aqui.

    Ver [VAL-02] y [VAL-03].
#>

# El nombre de la carpeta que el banco crea y de la que nunca sale.
$script:NombreRaizBanco = 'Banco-Cachivache'

function Get-NombreRaizBanco {
    <#
    .SYNOPSIS
        El nombre de la carpeta raiz del banco.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $script:NombreRaizBanco
}

function Get-RutaRaizBanco {
    <#
    .SYNOPSIS
        Donde va el banco, dada la carpeta Documentos. Calculo puro.

    .DESCRIPTION
        La parte que habla con Windows -preguntar cual es la carpeta
        Documentos de este usuario- se queda fuera, en Banco-Pruebas.ps1.
        Aqui solo se compone la ruta.

        Lo hacen DOS guiones: el que monta el banco y el que comprueba una
        pasada en la integracion continua. Si cada uno la compusiera por su
        cuenta, el comprobador podria estar mirando una carpeta distinta de
        la que se monto y decir que todo esta bien sin haber mirado nada.

    .PARAMETER Documentos
        Lo que devuelve [Environment]::GetFolderPath('MyDocuments').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Documentos)

    if ([string]::IsNullOrWhiteSpace($Documentos)) { return '' }
    return ($Documentos.Trim().TrimEnd('\', '/') + '\' + $script:NombreRaizBanco)
}

function Test-PareceMaquinaVirtual {
    <#
    .SYNOPSIS
        Si la descripcion del equipo parece la de una maquina virtual.

    .DESCRIPTION
        No es una comprobacion de seguridad y no pretende serlo: un
        hipervisor puede disfrazarse y una maquina fisica puede llamarse
        "VirtualBox". Es una RED, para que el descuido normal -abrir el
        guion en el equipo de trabajo y darle a ejecutar- se pare solo.

        Se mira lo que Windows dice del fabricante y del modelo. Son los
        mismos campos que consulta cualquiera para esto, y en los cuatro
        hipervisores que importan vienen rellenos.

    .PARAMETER Fabricante
        Win32_ComputerSystem.Manufacturer.

    .PARAMETER Modelo
        Win32_ComputerSystem.Model.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # AllowNull y AllowEmptyString: en un equipo con el WMI capado, o en
        # PowerShell 7 sobre un sistema raro, estas consultas devuelven nulo.
        # Que el dato no este es un "no parece virtual", no una excepcion.
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Fabricante,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Modelo
    )

    $senyales = @(
        'virtualbox', 'vmware', 'qemu', 'kvm', 'bochs', 'xen',
        'microsoft corporation virtual', 'virtual machine', 'hyper-v', 'parallels'
    )

    $texto = (('{0} {1}' -f $Fabricante, $Modelo)).ToLowerInvariant()
    foreach ($senyal in $senyales) {
        if ($texto.Contains($senyal)) { return $true }
    }
    return $false
}

function Test-DentroDeRaiz {
    <#
    .SYNOPSIS
        Si una ruta cae DENTRO de la raiz del banco. La comprobacion que
        impide que el banco borre nada que no haya creado el.

    .DESCRIPTION
        Comparar cadenas a pelo no vale, y este proyecto ya lo aprendio en
        [COR-02]: la guardia daba el veredicto correcto por el motivo
        equivocado hasta que se normalizo el prefijo \\?\.

        Aqui se normalizan tres cosas antes de comparar:

        - El prefijo \\?\, que el banco usa para las rutas largas. Sin
          quitarlo, "\\?\C:\...\Banco" no parece estar dentro de "C:\...\Banco".
        - Las barras finales, para que la raiz y la raiz con barra sean lo
          mismo.
        - Las mayusculas, porque en Windows las rutas no distinguen.

        Y se exige separador despues de la raiz: sin eso, "C:\Documentos\Banco-Cachivache-2"
        pasaria por estar dentro de "C:\Documentos\Banco-Cachivache". Es el
        clasico fallo de comparar por prefijo, y aqui costaria una carpeta
        del usuario.

        Lo que NO hace: resolver enlaces ni ".." . La ruta tiene que llegar
        ya resuelta; el guion la resuelve con GetFullPath antes de preguntar.
        Se dice aqui porque un dia alguien le pasara una sin resolver.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Raiz
    )

    if ([string]::IsNullOrWhiteSpace($Ruta) -or [string]::IsNullOrWhiteSpace($Raiz)) { return $false }

    $limpiar = {
        param([string] $Valor)
        $v = $Valor.Trim()
        if ($v.StartsWith('\\?\')) { $v = $v.Substring(4) }
        return $v.TrimEnd('\', '/')
    }

    $r = (& $limpiar $Ruta)
    $z = (& $limpiar $Raiz)

    if ([string]::IsNullOrWhiteSpace($z)) { return $false }
    if ($r.Equals($z, [StringComparison]::OrdinalIgnoreCase)) { return $true }

    # El separador es obligatorio: si no, "...\Banco-Cachivache-2" entraria.
    return $r.StartsWith(($z + '\'), [StringComparison]::OrdinalIgnoreCase)
}

function Get-MotivoNoMontarBanco {
    <#
    .SYNOPSIS
        Por que NO se puede montar el banco aqui, o nada si se puede.

    .DESCRIPTION
        Devuelve el texto que se le va a enseyar al usuario, no un codigo.
        Es la misma forma que Get-MotivoNoSeBorra: una sola funcion decide y
        explica, para que la explicacion no pueda dejar de coincidir con la
        decision.

    .PARAMETER PareceVirtual
        Lo que dijo Test-PareceMaquinaVirtual.

    .PARAMETER Forzado
        Si el usuario paso -AunqueNoSeaVirtual.

    .PARAMETER RaizOcupada
        Si ya existe la carpeta del banco con algo dentro.

    .OUTPUTS
        El motivo, o $null si se puede seguir.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch] $PareceVirtual,
        [switch] $Forzado,
        [switch] $RaizOcupada
    )

    if (-not $PareceVirtual -and -not $Forzado) {
        return ('Esto no parece una maquina virtual. El banco crea archivos dentro de ' +
                'tus carpetas personales y despues los borra: hazlo en la VM con su ' +
                'instantanea, no aqui. Si de verdad quieres, pasa -AunqueNoSeaVirtual.')
    }

    # Se comprueba DESPUES de lo anterior a proposito: si no es una VM, ese
    # es el motivo que hay que dar, aunque ademas la carpeta este ocupada.
    if ($RaizOcupada) {
        return ('Ya hay un banco montado. Quitalo primero con -Quitar: montar encima ' +
                'dejaria cebos de dos tandas mezclados y no sabrias cual es cual.')
    }

    return $null
}

function Get-MotivoNoQuitarBanco {
    <#
    .SYNOPSIS
        Por que NO se puede borrar esta carpeta, o nada si se puede.

    .DESCRIPTION
        La comprobacion mas importante del archivo. -Quitar hace un borrado
        recursivo de una ruta CALCULADA, y si el calculo sale mal -Documentos
        no se encuentra, una variable de entorno vacia, un GetFullPath que
        devuelve la unidad entera- el borrado recursivo se come lo que haya
        debajo.

        Tres candados, y ninguno sobra:

        1. Que la ruta termine exactamente en el nombre del banco. Si el
           calculo se fue a "C:\Users\quien\Documentos", esto lo para.
        2. Que tenga profundidad suficiente. Una raiz de unidad -"C:\"- o
           algo con dos segmentos no puede ser el banco jamas.
        3. Que exista. Borrar lo que no hay no es peligroso, pero decirlo
           evita que alguien crea que ha limpiado algo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Raiz,
        [switch] $Existe
    )

    if ([string]::IsNullOrWhiteSpace($Raiz)) {
        return 'No se ha podido calcular donde esta el banco.'
    }

    $limpia = $Raiz.Trim()
    if ($limpia.StartsWith('\\?\')) { $limpia = $limpia.Substring(4) }
    $limpia = $limpia.TrimEnd('\', '/')

    $hojas = @($limpia -split '[\\/]' | Where-Object { $_ })

    if ($hojas.Count -lt 3) {
        return ("'$Raiz' esta demasiado arriba para ser el banco. No se borra nada.")
    }

    if ($hojas[-1] -ne $script:NombreRaizBanco) {
        return ("'$Raiz' no termina en '$($script:NombreRaizBanco)'. No se borra nada.")
    }

    if (-not $Existe) {
        return ("No hay ningun banco montado en '$Raiz'.")
    }

    return $null
}

# =====================================================================
#  EL CATALOGO DE CEBOS  ([VAL-03])
# =====================================================================
#
# Antes los cebos se creaban a mano, uno detras de otro, dentro de
# New-BancoPruebas. Funcionaba para montarlos y no servia para nada mas:
# no habia forma de preguntar "que tenia que haber salido en el analisis"
# sin volver a escribir la lista en otro sitio, y una lista escrita dos
# veces son dos listas.
#
# Y hacia falta preguntarlo, porque montar el banco resulto no ser
# suficiente. TRES DE LOS CEBOS ERAN INVISIBLES PARA EL PROGRAMA:
#
#   copia-enorme.bak   (el cebo de [COR-01], el mas importante de los tres)
#   copia-antigua.bak  (el cebo de [COR-02])
#   documento-N.bak    (ocho de los dieciseis de 01-temporales)
#
# Los tres empiezan por una palabra de la lista de Test-ArchivoPersonal
# -"copia", "documento"-, asi que la guardia los protegia como si fueran
# trabajo del usuario y NINGUN modulo llegaba a proponerlos. El banco
# montaba impecablemente unos cebos que la comprobacion no podia ver.
# Nadie lo noto porque el banco nunca se habia llegado a ejecutar: es
# exactamente el fallo que [VAL-02] existe para destapar, aparecido en el
# propio [VAL-02].
#
# De ahi el catalogo. Los nombres, los tamanyos y -sobre todo- LO QUE
# TIENE QUE PASAR CON CADA CEBO viven aqui, en calculo puro, y hay una
# invariante en tests/Banco.Tests.ps1 que le pregunta a la guardia de
# verdad si cada nombre es visible. Un cebo mal bautizado ya no puede
# llegar hasta la maquina virtual.

function Get-CebosBanco {
    <#
    .SYNOPSIS
        Que monta el banco, y que tiene que hacer el programa con cada
        cosa. Calculo puro: no toca el disco.

    .DESCRIPTION
        Cada entrada describe una FAMILIA de cebos (uno o varios archivos
        con el mismo patron de nombre) con estos campos:

          Id            Identificador corto, unico. Es lo que sale en los
                        mensajes de la CI.
          Carpeta       Subcarpeta del banco donde vive la familia.
          Patron        Nombre del archivo. Con Cuantos > 1 lleva "{0}",
                        que se rellena con el numero de orden.
          Cuantos       Cuantos archivos crea la familia.
          KiloBytes     Tamanyo de cada uno.
          Relleno       Texto con el que se rellenan. Dos cebos con el
                        mismo relleno y el mismo tamanyo salen identicos
                        byte a byte, que es lo que necesita el modulo de
                        duplicados.
          EsCarpeta     La familia son carpetas vacias, no archivos.
          EnlaceA       Si no esta vacio, el archivo es un ENLACE DURO al
                        que se llame asi en la misma carpeta.
          SubCarpetas   Cuantos niveles anidados hay entre la carpeta y el
                        archivo. Solo lo usa el cebo de ruta larga.
          PatronSubCarpeta  Como se llama cada nivel.
          Premarcado    Si el analisis tiene que traerlo MARCADO SOLO. Es
                        lo unico que borra "-Consola -Ejecutar", asi que
                        este campo decide que desaparece en una limpieza
                        real y que no. Una invariante lo compara con
                        Test-DebeVenirMarcado, que es quien lo decide de
                        verdad.
          EnAnalisis    Si el analisis tiene que ENCONTRARLO. Cuando vale
                        $false, MotivoFuera dice por que, y se exige que
                        lo diga.
          EnLimpieza    Si la limpieza REAL del final tiene que haberlo
                        hecho desaparecer. Es un campo aparte de
                        EnAnalisis porque no son la misma pregunta, y
                        confundirlas costo un paso en rojo: el cebo de
                        ruta larga si tiene que salir en el analisis, pero
                        no puede desaparecer en la limpieza, que va a la
                        papelera y la papelera de Windows NO admite rutas
                        de mas de 260 caracteres. Cuando vale $false,
                        MotivoFuera dice por que.
          MotivoFuera   Por que este cebo se queda fuera de una de las dos
                        comprobaciones de arriba.
          Para          Que afirmacion del banco sostiene este cebo.

    .PARAMETER ArchivosDeSobra
        Cuantos archivos de relleno lleva 07-muchas-filas. Es un parametro
        y no una constante porque el banco lo deja elegir: a mano se
        montan 3.000 para ver el desplazamiento, y en la integracion
        continua bastan unos pocos cientos, que hacen la misma
        comprobacion en una decima parte del tiempo.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [ValidateRange(0, 50000)]
        [int] $ArchivosDeSobra = 3000
    )

    # La plantilla existe para que cada entrada solo escriba lo que la
    # distingue. Sin ella, anyadir un campo obligaria a tocar las nueve
    # entradas y la que se olvidara quedaria con la propiedad a $null: en
    # PowerShell leer una propiedad que no existe no lanza, asi que el
    # sintoma seria un cebo que se comporta raro, no un error.
    $plantilla = @{
        Id = ''; Carpeta = ''; Patron = ''; Cuantos = 1; KiloBytes = 4
        Relleno = 'cebo'; EsCarpeta = $false; EnlaceA = ''
        SubCarpetas = 0; PatronSubCarpeta = ''
        Premarcado = $false; EnAnalisis = $true; EnLimpieza = $true
        MotivoFuera = ''; Para = ''
    }

    $entradas = @(
        @{
            Id = 'temporales-bak'; Carpeta = '01-temporales'
            Patron = 'salida-{0}.bak'; Cuantos = 8; KiloBytes = 64
            Premarcado = $false
            Para = 'El camino normal: proponer, marcarlo a mano y borrarlo a la papelera'
        }
        @{
            Id = 'temporales-old'; Carpeta = '01-temporales'
            Patron = 'version-{0}.old'; Cuantos = 8; KiloBytes = 32
            Premarcado = $false
            Para = 'Lo mismo que el anterior, con la otra extension de copia antigua'
        }
        @{
            Id = 'ruta-larga'; Carpeta = '02-ruta-larga'
            SubCarpetas = 12
            PatronSubCarpeta = 'carpeta-anidada-con-nombre-largo-numero-{0:00}'
            Patron = 'volcado-antiguo.dmp'; Cuantos = 1; KiloBytes = 28
            Premarcado = $true
            # EnAnalisis paso de $false a $true al cerrarse [COR-08]. Antes
            # los modulos recorrian con Get-ChildItem -Recurse y este cebo
            # no se proponia NUNCA; ahora recorren con Get-ElementosDelArbol,
            # que pone el prefijo, y 50-Temporales tiene que encontrar el
            # .dmp del fondo. Es la comprobacion dura del punto: si el
            # recorrido volviera a pararse en los 260, este paso se pone
            # rojo en el push siguiente.
            EnAnalisis = $true
            # Pero NO desaparece en la limpieza real, y por dos motivos
            # independientes que van en la misma direccion: la fase
            # 'windows' ya lo borra con -Permanente para probar la otra
            # mitad de [COR-02], asi que cuando se toma el inventario
            # 'antes' este cebo ya no esta; y aunque siguiera, la limpieza
            # del final va a la PAPELERA, que en Windows no admite rutas de
            # mas de 260 caracteres, de modo que el programa se negaria a
            # borrarlo -diciendolo, que es lo que exige [COR-02]-.
            EnLimpieza = $false
            MotivoFuera = ('La fase windows ya lo borra con -Permanente, asi que no esta en el ' +
                           'inventario previo; y la limpieza real va a la papelera, que no ' +
                           'admite rutas de mas de 260 caracteres. Que se NIEGUE con el motivo ' +
                           'correcto es justo lo que comprueba la fase windows.')
            Para = '[COR-08] que el recorrido lo encuentre, y [COR-02] medirlo y borrarlo'
        }
        @{
            Id = 'mas-grande'; Carpeta = '03-mas-grande-que-la-papelera'
            Patron = 'volcado-enorme.dmp'; Cuantos = 1; KiloBytes = 204800
            Premarcado = $true
            Para = '[COR-01]: con la cuota de la papelera bajada a 100 MB, esto no cabe'
        }
        @{
            Id = 'enlace-original'; Carpeta = '04-enlaces-duros'
            Patron = 'original.bak'; Cuantos = 1; KiloBytes = 20480
            Premarcado = $false
            Para = '[VIS-03]: el contenido de verdad, 20 MB'
        }
        @{
            Id = 'enlace-duro'; Carpeta = '04-enlaces-duros'
            Patron = 'mismo-contenido-otro-nombre.bak'; Cuantos = 1
            EnlaceA = 'original.bak'
            Premarcado = $false
            Para = '[VIS-03]: el segundo nombre. Medir la carpeta tiene que dar 20 MB, no 40'
        }
        @{
            Id = 'duplicados'; Carpeta = '05-duplicados'
            Patron = 'informe-copia-{0}.bak'; Cuantos = 2; KiloBytes = 512
            Relleno = 'contenido-identico-'
            Premarcado = $false
            Para = 'Duplicados de verdad, y el contraste con los enlaces duros de al lado'
        }
        @{
            Id = 'carpetas-vacias'; Carpeta = '06-carpetas-vacias'
            Patron = 'vacia-{0}'; Cuantos = 5; EsCarpeta = $true
            Premarcado = $false
            EnAnalisis = $false
            MotivoFuera = ('40-CarpetasVacias propone solo LA CIMA de una cadena de carpetas ' +
                           'vacias, asi que lo que sale en el analisis es 06-carpetas-vacias, ' +
                           'no cada una de las cinco hojas. Es correcto y esta explicado en ' +
                           '[C-09]: proponer las cinco haria falta ejecutar el programa cinco veces.')
            Para = 'El modulo de carpetas vacias'
        }
        @{
            Id = 'relleno'; Carpeta = '07-muchas-filas'
            Patron = 'sobra-{0:00000}.tmp'; Cuantos = $ArchivosDeSobra; KiloBytes = 0
            Premarcado = $true
            Para = 'Miles de filas: [USO-01] desplazamiento, [VEL-03] marcar en lote, y el borrado real en lote'
        }
        @{
            Id = 'comprimido'; Carpeta = '08-comprimido'
            Patron = 'volcado-comprimible.dmp'; Cuantos = 1; KiloBytes = 102400
            Premarcado = $true
            # El cebo de [VIS-05], y el unico del catalogo que NO queda
            # listo al montarlo: comprimir una carpeta es "compact /C", que
            # solo existe en Windows y sobre NTFS, y el guion que monta el
            # banco tiene que poder ejecutarse tambien donde no hay ninguna
            # de las dos cosas. El paso va escrito en docs/BANCO-PRUEBAS.md,
            # en el apartado de lo que la integracion continua no puede ver.
            #
            # Sin comprimir sigue sirviendo -es un .dmp de 100 MB que el
            # analisis tiene que encontrar y la limpieza real borrar-, asi
            # que la CI lo trata como a cualquier otro y sus dos campos van
            # a $true. Lo que solo se ve despues de comprimirlo es la
            # afirmacion del punto: que lo prometido baja al tamano en
            # disco y no se queda en los 100 MB que el archivo mide.
            Para = ('[VIS-05]: 100 MB que, comprimidos con NTFS, ocupan mucho menos. Lo prometido ' +
                    'tiene que ser lo que ocupan, no lo que miden. Hay que comprimirlo a mano ' +
                    'con "compact /C": ver docs/BANCO-PRUEBAS.md, apartado 8.')
        }
    )

    $cebos = [Collections.Generic.List[object]]::new()
    foreach ($entrada in $entradas) {
        $campos = $plantilla.Clone()
        foreach ($clave in $entrada.Keys) { $campos[$clave] = $entrada[$clave] }
        $cebos.Add([pscustomobject]$campos)
    }
    return @($cebos)
}

function Get-RutaCebo {
    <#
    .SYNOPSIS
        Donde va a estar exactamente un cebo. Calculo puro.

    .DESCRIPTION
        La usan los tres sitios que necesitan la misma respuesta: el guion
        que monta el banco, el comprobador de la CI que busca esa ruta en
        el informe del analisis, y las pruebas. Si cada uno la compusiera
        por su cuenta, un cambio en el catalogo dejaria al comprobador
        buscando rutas que ya no existen y el paso pasaria en verde sin
        comprobar nada.

        Se compone con barra invertida a mano y NO con Join-Path: las
        pruebas corren en Linux, donde Join-Path pone barra normal, y estas
        rutas se comparan luego, como texto, contra las que devuelve
        Windows.

    .PARAMETER Indice
        Numero de orden dentro de la familia, empezando en 1. Se ignora en
        las familias de un solo elemento.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Cebo,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Raiz,
        [int] $Indice = 1
    )

    if ($null -eq $Cebo) { return '' }
    if ([string]::IsNullOrWhiteSpace($Raiz)) { return '' }

    $ruta = $Raiz.Trim().TrimEnd('\', '/') + '\' + $Cebo.Carpeta
    for ($nivel = 1; $nivel -le [int]$Cebo.SubCarpetas; $nivel++) {
        $ruta = $ruta + '\' + ($Cebo.PatronSubCarpeta -f $nivel)
    }

    $nombre = if ([int]$Cebo.Cuantos -gt 1) { $Cebo.Patron -f $Indice } else { [string]$Cebo.Patron }
    return $ruta + '\' + $nombre
}

function Test-PerfilAjeno {
    <#
    .SYNOPSIS
        Si una ruta cae dentro del perfil de OTRO usuario. Calculo puro.

    .DESCRIPTION
        Es la mitad dura de la unica comprobacion del banco que, si falla,
        para todo: "el analisis no propone nada del sistema ni de perfiles
        de otros usuarios". Lo demas que hay bajo C:\Windows o Archivos de
        programa lo proponen a proposito modulos que existen para eso
        -Windows Update, logs del sistema, almacen de componentes-, asi que
        vetarlo entero daria un falso positivo en cada ejecucion. El perfil
        ajeno no: ahi no tiene nada que hacer ningun modulo.

        No se leen variables de entorno aqui dentro. Se reciben las dos
        rutas ya resueltas para que esto se pueda probar en Linux, que es
        donde corre la suite.

    .PARAMETER CarpetaUsuarios
        C:\Users, resuelta por quien llama.

    .PARAMETER PerfilPropio
        El perfil del usuario que ejecuta el programa. Lo que cuelga de el
        NO es ajeno.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Ruta,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $CarpetaUsuarios,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $PerfilPropio
    )

    # Sin saber donde estan los perfiles no se puede afirmar que una ruta
    # sea de otro. Se responde que no, que es lo que deja pasar; el aviso
    # de que no se ha podido comprobar lo da quien llama.
    if ([string]::IsNullOrWhiteSpace($Ruta)) { return $false }
    if ([string]::IsNullOrWhiteSpace($CarpetaUsuarios)) { return $false }

    if (-not (Test-DentroDeRaiz -Ruta $Ruta -Raiz $CarpetaUsuarios)) { return $false }
    # La propia C:\Users no es "de otro usuario": es la carpeta que los
    # contiene. Test-DentroDeRaiz la da por dentro de si misma, y sin esta
    # linea el primer candidato que la mencionara se contaria como fallo.
    if (Test-DentroDeRaiz -Ruta $CarpetaUsuarios -Raiz $Ruta) { return $false }

    if ([string]::IsNullOrWhiteSpace($PerfilPropio)) { return $true }
    return (-not (Test-DentroDeRaiz -Ruta $Ruta -Raiz $PerfilPropio))
}

function Get-RutasFueraDelBanco {
    <#
    .SYNOPSIS
        De una lista de rutas, las que NO estan dentro del banco. Calculo
        puro.

    .DESCRIPTION
        Es la pregunta que hace toda la limpieza real de la integracion
        continua: "esto que ha desaparecido del disco, .era un cebo mio o
        era del agente?". Cualquier respuesta distinta de "todo era mio"
        para el paso, y lo para DESPUES de haber mirado la lista entera,
        para que el registro del trabajo ensenye las rutas y no solo un
        numero.

        Devuelve rutas UNICAS y ordenadas: la misma ruta repetida en el
        informe y en el disco contaria dos veces y el mensaje de fallo
        seria confuso justo cuando mas hay que leerlo.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [string[]] $Rutas,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Raiz
    )

    $fuera = [Collections.Generic.List[string]]::new()
    foreach ($ruta in @($Rutas)) {
        if ([string]::IsNullOrWhiteSpace($ruta)) { continue }
        if (Test-DentroDeRaiz -Ruta $ruta -Raiz $Raiz) { continue }
        $fuera.Add($ruta)
    }
    return @($fuera | Sort-Object -Unique)
}

function Get-ResumenCebos {
    <#
    .SYNOPSIS
        Cuantos cebos de cada familia ha encontrado el analisis, y cuales
        faltan. Calculo puro.

    .DESCRIPTION
        Recibe las rutas que propuso el analisis y el catalogo, y devuelve
        una fila por familia. El comprobador de la CI decide con la
        columna Falta: si una familia con EnAnalisis a $true no esta
        completa, el recorrido se ha parado en algun sitio y eso es un
        fallo de verdad.

        Las familias con EnAnalisis a $false tambien se miden y se
        ensenyan. No se gatilla sobre ellas -su motivo esta escrito en el
        catalogo- pero el numero se ve, que es lo que permitira darse
        cuenta el dia que empiecen a aparecer.

    .PARAMETER Propuestas
        Las rutas que el analisis puso en la lista.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] $Cebos,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Raiz,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [string[]] $Propuestas
    )

    # Conjunto y no un -contains por cebo: con 3.000 archivos de relleno,
    # la version con -contains es cuadratica y tarda minutos en decidir
    # algo que se responde en milisegundos.
    $vistas = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($ruta in @($Propuestas)) {
        if ([string]::IsNullOrWhiteSpace($ruta)) { continue }
        [void]$vistas.Add($ruta.Trim().TrimEnd('\', '/'))
    }

    $filas = [Collections.Generic.List[object]]::new()
    foreach ($cebo in @($Cebos)) {
        if ($null -eq $cebo) { continue }

        $encontrados = 0
        $faltan = [Collections.Generic.List[string]]::new()
        for ($n = 1; $n -le [int]$cebo.Cuantos; $n++) {
            $ruta = Get-RutaCebo -Cebo $cebo -Raiz $Raiz -Indice $n
            if ($vistas.Contains($ruta)) {
                $encontrados++
            } elseif ($faltan.Count -lt 5) {
                # Solo las cinco primeras: un fallo en 07-muchas-filas
                # imprimiria tres mil rutas y taparia todo lo demas del
                # registro del trabajo, que es justo lo que hay que leer.
                $faltan.Add($ruta)
            }
        }

        $filas.Add([pscustomobject]@{
            Id          = [string]$cebo.Id
            Esperados   = [int]$cebo.Cuantos
            Encontrados = $encontrados
            Falta       = ([int]$cebo.Cuantos - $encontrados)
            EnAnalisis  = [bool]$cebo.EnAnalisis
            MotivoFuera = [string]$cebo.MotivoFuera
            Ejemplos    = @($faltan)
        })
    }
    return @($filas)
}
