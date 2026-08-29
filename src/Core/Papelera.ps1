<#
.SYNOPSIS
    Estado de la papelera de reciclaje de cada volumen, para no llamar
    "papelera" a un borrado que en realidad es definitivo.

.DESCRIPTION
    -------------------------------------------------------------------
    EL PROBLEMA

    Windows no avisa. Cuando mandas un archivo a la papelera y no cabe
    -porque supera la cuota del volumen, porque la papelera esta
    desactivada en ese disco, o porque el disco no tiene papelera-, el
    sistema lo borra PERMANENTEMENTE y sin preguntar. La llamada devuelve
    exito, igual que si hubiera ido a la papelera.

    Cachivache lo anotaba como PAPELERA. O sea: el usuario leia que su
    archivo era recuperable, iba a buscarlo y no estaba. Y fallaba en el
    caso que mas duele, porque el que no cabe es siempre el archivo mas
    grande. Ver [COR-01] en docs/HOJA-DE-RUTA.md.

    Es la misma familia que [SEG-20] -Hecho puesto antes de consolidar
    errores- y que todo lo que ha ido cerrando esta auditoria: el
    programa contando algo distinto de lo que hizo.

    -------------------------------------------------------------------
    POR QUE ESTA PARTIDO EN DOS

    Leer la cuota exige Windows: registro y CIM. Decidir si algo cabe es
    aritmetica. Si van juntos, la parte que de verdad decide si un archivo
    del usuario sobrevive solo se puede probar en la maquina del usuario,
    que es exactamente como llegamos aqui: el desarrollador anterior dejo
    esto escrito y sin tocar porque no podia probarlo sin Windows.

    Asi que:

      Get-EstadoPapelera   habla con Windows. Devuelve datos, no juicios.
      Test-CabeEnPapelera  es calculo puro. Se prueba aqui, sin Windows.

    Es la misma division que Mapa.ps1 hace entre geometria y dibujado.

    -------------------------------------------------------------------
    DONDE VIVE LA CUOTA

    HKCU\...\Explorer\BitBucket\Volume\{GUID}
        MaxCapacity   tamaño maximo de la papelera de ese volumen, en MB
        NukeOnDelete  1 = no hay papelera en ese volumen, todo definitivo

    El {GUID} es el nombre de volumen que devuelve Win32_Volume en
    DeviceID. Y hay una politica que manda sobre todo lo anterior:

    HKLM\...\Policies\Explorer\NoRecycleFiles = 1  ->  nunca hay papelera
#>

# Lo que se sabe del estado de la papelera de un volumen. Se cachea por
# unidad: la cuota no cambia mientras el programa esta abierto, y una
# limpieza puede preguntar por ella cinco mil veces.
$script:CachePapelera = @{}

function Reset-CachePapelera {
    <#
    .SYNOPSIS
        Olvida lo que se sabe de las papeleras. Para las pruebas y para
        cuando el usuario cambia la configuracion sin cerrar el programa.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo vacía una tabla en memoria.')]
    [CmdletBinding()]
    param()
    $script:CachePapelera = @{}
}

function New-EstadoPapelera {
    <#
    .SYNOPSIS
        Compone el estado de una papelera.

    .PARAMETER Disponible
        Si ese volumen tiene papelera utilizable.
    .PARAMETER CapacidadBytes
        Cuanto admite. 0 con Disponible a $false. -1 significa "no se ha
        podido averiguar", que NO es lo mismo que cero: ver
        Test-CabeEnPapelera.
    .PARAMETER Motivo
        Frase para el usuario. Se escribe aqui y no en quien la muestra
        para que la consola y la ventana digan lo mismo.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Solo compone un objeto en memoria.')]
    [CmdletBinding()]
    param(
        [bool]   $Disponible     = $true,
        [double] $CapacidadBytes = -1,
        [string] $Motivo         = ''
    )

    return [pscustomobject]@{
        Disponible     = $Disponible
        CapacidadBytes = $CapacidadBytes
        Motivo         = $Motivo
    }
}

function Test-CabeEnPapelera {
    <#
    .SYNOPSIS
        Decide si algo de este tamaño iria de verdad a la papelera.

    .DESCRIPTION
        CALCULO PURO: no toca el disco ni el registro. Recibe el estado ya
        leido y un tamaño, y devuelve si cabe y por que no.

        Tres casos, y el tercero es el que hay que pensar despacio:

          1. No hay papelera en ese volumen     -> NO cabe. Seguro.
          2. Hay papelera y el tamaño la supera -> NO cabe. Seguro.
          3. No se ha podido leer la cuota      -> se responde que SI.

        El tercero parece la respuesta cobarde y es la correcta. Un "no se
        sabe" tratado como "no cabe" bloquearia borrados legitimos en
        cualquier equipo donde no se pueda leer el registro, y el usuario
        aprenderia a marcar borrado permanente para que el programa le
        deje trabajar: acabariamos empujandole justo a lo irreversible.
        Ademas el desconocimiento se anota en el registro, asi que no
        desaparece en silencio.

    .PARAMETER Bytes
        Tamaño de lo que se quiere borrar.
    .PARAMETER Estado
        Lo que devuelve Get-EstadoPapelera.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Bytes,
        # AllowNull por la misma razon que Get-DetalleExcepcion: sin el, el
        # enlace de parametros rechaza el nulo ANTES de llegar a la guarda
        # de abajo, que se queda de adorno. Lo caza la prueba "un estado
        # nulo no revienta", que es justo para lo que esta.
        [Parameter(Mandatory)] [AllowNull()] $Estado
    )

    if ($null -eq $Estado) {
        return [pscustomobject]@{ Cabe = $true; Seguro = $false; Motivo = '' }
    }

    if (-not $Estado.Disponible) {
        return [pscustomobject]@{
            Cabe   = $false
            Seguro = $true
            Motivo = $(if ([string]::IsNullOrWhiteSpace($Estado.Motivo)) {
                          'este disco no tiene papelera de reciclaje'
                       } else { $Estado.Motivo })
        }
    }

    # Capacidad desconocida: se deja pasar, pero sin prometer nada.
    if ([double]$Estado.CapacidadBytes -lt 0) {
        return [pscustomobject]@{ Cabe = $true; Seguro = $false; Motivo = '' }
    }

    if ($Bytes -gt [double]$Estado.CapacidadBytes) {
        return [pscustomobject]@{
            Cabe   = $false
            Seguro = $true
            Motivo = ('ocupa {0} y la papelera de este disco admite {1}' -f
                      (Format-Tamano $Bytes), (Format-Tamano $Estado.CapacidadBytes))
        }
    }

    return [pscustomobject]@{ Cabe = $true; Seguro = $true; Motivo = '' }
}

function Get-GuidVolumen {
    <#
    .SYNOPSIS
        Nombre de volumen ({GUID}) de una letra de unidad, que es como se
        llama a si mismo el registro.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Unidad)

    $letra = $Unidad.TrimEnd('\', '/')
    if ($letra.Length -eq 1) { $letra = $letra + ':' }

    try {
        $volumen = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop |
                   Where-Object { $_.DriveLetter -eq $letra } |
                   Select-Object -First 1
        if ($null -eq $volumen) { return '' }

        # DeviceID llega como \\?\Volume{guid}\ y el registro guarda solo
        # la parte {guid}.
        if ($volumen.DeviceID -match '(\{[0-9a-fA-F-]+\})') { return $matches[1] }
        return ''
    } catch {
        return ''
    }
}

function Get-EstadoPapelera {
    <#
    .SYNOPSIS
        Que papelera tiene esta unidad y cuanto admite.

    .DESCRIPTION
        Habla con Windows: politica de grupo, Win32_Volume y registro. Lo
        que no se puede averiguar se devuelve como -1, nunca como 0: cero
        significaria "no cabe nada" y bloquearia todos los borrados.

        Fuera de Windows -las pruebas corren en Linux- devuelve
        desconocido, que es la verdad.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Unidad)

    $letra = $Unidad.TrimEnd('\', '/')
    if ($letra.Length -eq 1) { $letra = $letra + ':' }
    $clave = $letra.ToUpperInvariant()

    if ($script:CachePapelera.ContainsKey($clave)) { return $script:CachePapelera[$clave] }

    $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes -1

    try {
        # 1. La politica manda sobre todo lo demas.
        $politica = Get-ItemProperty -ErrorAction SilentlyContinue `
            -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        if ($politica -and [int]$politica.NoRecycleFiles -eq 1) {
            $estado = New-EstadoPapelera -Disponible $false -CapacidadBytes 0 `
                        -Motivo 'la papelera esta desactivada por directiva del sistema'
            $script:CachePapelera[$clave] = $estado
            return $estado
        }

        # 2. Solo los discos fijos tienen papelera. En uno de red o en un
        #    USB, mandar a la papelera es borrar.
        $unidadInfo = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop |
                      Where-Object { $_.DeviceID -eq $clave } | Select-Object -First 1
        if ($unidadInfo -and [int]$unidadInfo.DriveType -ne 3) {
            $estado = New-EstadoPapelera -Disponible $false -CapacidadBytes 0 `
                        -Motivo 'este disco no es fijo, y solo los discos fijos tienen papelera'
            $script:CachePapelera[$clave] = $estado
            return $estado
        }

        # 3. La cuota del volumen.
        $guid = Get-GuidVolumen -Unidad $clave
        if (-not [string]::IsNullOrWhiteSpace($guid)) {
            $ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\' + $guid
            $cfg  = Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue
            if ($cfg) {
                if ([int]$cfg.NukeOnDelete -eq 1) {
                    $estado = New-EstadoPapelera -Disponible $false -CapacidadBytes 0 `
                                -Motivo ('la papelera esta desactivada en {0}' -f $clave)
                } elseif ($null -ne $cfg.MaxCapacity) {
                    # MaxCapacity viene en MB.
                    $estado = New-EstadoPapelera -Disponible $true `
                                -CapacidadBytes ([double]$cfg.MaxCapacity * 1MB)
                }
            }
        }
    } catch {
        # Se queda en desconocido a proposito. Ver Test-CabeEnPapelera.
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes -1
    }

    $script:CachePapelera[$clave] = $estado
    return $estado
}

function Test-IraAPapelera {
    <#
    .SYNOPSIS
        Lo que preguntan los que van a borrar: ¿esto acabaria de verdad en
        la papelera, o desapareceria para siempre?

    .DESCRIPTION
        Junta las dos mitades -leer Windows y decidir- en la unica pregunta
        que le interesa a Remove.ps1.

    .PARAMETER Ruta
        De aqui sale la unidad.
    .PARAMETER Bytes
        Tamaño ya medido. Se pasa desde fuera porque quien llama suele
        tenerlo, y medir dos veces un arbol de miles de archivos se nota.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [Parameter(Mandatory)] [double] $Bytes
    )

    $unidad = ''
    if ($Ruta -match '^([A-Za-z]):') { $unidad = $matches[1] + ':' }
    if ([string]::IsNullOrWhiteSpace($unidad)) {
        # Rutas UNC y cualquier cosa sin letra: no hay papelera que valga.
        if ($Ruta.StartsWith('\\')) {
            return [pscustomobject]@{
                Cabe = $false; Seguro = $true
                Motivo = 'esta en una carpeta de red, y la red no tiene papelera'
            }
        }
        return [pscustomobject]@{ Cabe = $true; Seguro = $false; Motivo = '' }
    }

    return Test-CabeEnPapelera -Bytes $Bytes -Estado (Get-EstadoPapelera -Unidad $unidad)
}
