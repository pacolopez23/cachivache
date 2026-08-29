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

    Ver [VAL-02].
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
