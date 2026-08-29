<#
.SYNOPSIS
    Perfiles de limpieza: conjuntos de umbrales y módulos preconfigurados.
#>

$script:PerfilesDisponibles = @(
    [pscustomobject]@{
        Id          = 'conservador'
        Nombre      = 'Conservador'
        Resumen     = 'Solo lo que el sistema vuelve a crear solo.'
        Descripcion = @'
Toca unicamente cachés y temporales que cualquier programa regenera sin
intervencion. No propone nada que dependa de un juicio sobre si algo se usa
o no. Es la opcion recomendada si es la primera vez que ejecutas el programa.
'@
        DiasSinUso        = 365
        MinimoMB          = 50
        MinimoGrandeMB    = 250
        MinimoDuplicadoMB = 5
        IncluirMenores    = $false
        Permanente        = $false
        Color             = '#3DD68C'
    }
    [pscustomobject]@{
        Id          = 'equilibrado'
        Nombre      = 'Equilibrado'
        Resumen     = 'Cachés, restos de programas y descargas antiguas.'
        Descripcion = @'
Anyade los restos de programas desinstalados, los instaladores viejos de la
carpeta Descargas y las carpetas regenerables de proyectos. Todo lo que
implique una decision aparece marcado en rojo y sin seleccionar.
'@
        DiasSinUso        = 180
        MinimoMB          = 10
        MinimoGrandeMB    = 250
        MinimoDuplicadoMB = 5
        IncluirMenores    = $false
        Permanente        = $false
        Color             = '#4C8DFF'
    }
    [pscustomobject]@{
        Id          = 'agresivo'
        Nombre      = 'Exhaustivo'
        Resumen     = 'Analiza todo, incluidos duplicados y archivos grandes.'
        Descripcion = @'
Activa todos los modulos, baja los umbrales y busca ademas duplicados por
hash y archivos grandes sin abrir. Tarda bastante mas y encuentra muchisimo
mas, pero exige revisar la lista con calma antes de eliminar nada.
'@
        DiasSinUso        = 90
        MinimoMB          = 1
        # Archivos grandes no levanta ningún veto: bajar el umbral solo
        # significa mirar más archivos propios del usuario y enseñarlos,
        # nunca proponer nada que la guardia no aprobara igual.
        MinimoGrandeMB    = 100
        # Duplicados SI levanta el veto por extensión personal (es el único
        # módulo que lo hace, porque garantiza que existe otra copia). Por
        # eso su umbral baja poco y a propósito: cuanto más bajo, más
        # documentos y fotos personales entran en la lista. 3 MB sigue
        # dejando fuera el grueso de archivos pequeños.
        MinimoDuplicadoMB = 3
        IncluirMenores    = $true
        Permanente        = $false
        Color             = '#F5A524'
    }
    [pscustomobject]@{
        Id          = 'personalizado'
        Nombre      = 'Personalizado'
        Resumen     = 'Tus propios umbrales y tu propia selección de módulos.'
        Descripcion = @'
Mantiene exactamente lo que hayas configurado en la pestaña de ajustes y
la seleccion de modulos que dejaste la ultima vez.
'@
        DiasSinUso        = 180
        MinimoMB          = 10
        MinimoGrandeMB    = 250
        MinimoDuplicadoMB = 5
        IncluirMenores    = $false
        Permanente        = $false
        Color             = '#8A93A6'
    }
)

function Get-PerfilesLimpieza {
    <#
    .SYNOPSIS
        Devuelve la lista de perfiles disponibles.
    #>
    [CmdletBinding()]
    param()
    return $script:PerfilesDisponibles
}

function Get-PerfilLimpieza {
    <#
    .SYNOPSIS
        Busca un perfil por su identificador.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Id)

    $perfil = $script:PerfilesDisponibles | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $perfil) {
        $perfil = $script:PerfilesDisponibles | Where-Object { $_.Id -eq 'equilibrado' } | Select-Object -First 1
    }
    return $perfil
}

function Set-PerfilConfiguracion {
    <#
    .SYNOPSIS
        Aplica los umbrales de un perfil sobre un objeto de configuración.
    .DESCRIPTION
        El perfil "personalizado" respeta lo que ya hubiera configurado el
        usuario y por tanto no sobreescribe nada.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Modifica un objeto en memoria que recibe por parámetro.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Configuracion,
        [Parameter(Mandatory)] [string] $Perfil
    )

    $Configuracion.Perfil = $Perfil
    if ($Perfil -eq 'personalizado') { return $Configuracion }

    # Se escriben TODOS los umbrales que declara el perfil. Antes solo se
    # copiaban cuatro, y MinimoGrandeMB/MinimoDuplicadoMB se quedaban en el
    # valor por defecto de New-Configuracion pasara lo que pasara: el perfil
    # Exhaustivo prometia "baja los umbrales" y el módulo de archivos
    # grandes seguia en 250 MB en los tres perfiles. Ver [C-20].
    $datos = Get-PerfilLimpieza $Perfil
    $Configuracion.DiasSinUso        = $datos.DiasSinUso
    $Configuracion.MinimoMB          = $datos.MinimoMB
    $Configuracion.MinimoGrandeMB    = $datos.MinimoGrandeMB
    $Configuracion.MinimoDuplicadoMB = $datos.MinimoDuplicadoMB
    $Configuracion.IncluirMenores    = $datos.IncluirMenores
    $Configuracion.Permanente        = $datos.Permanente
    return $Configuracion
}

function Test-ModuloEnPerfil {
    <#
    .SYNOPSIS
        Indica si un módulo forma parte de un perfil.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] $Modulo,
        [Parameter(Mandatory)] [string] $Perfil
    )

    if ($Perfil -eq 'personalizado') { return $true }
    return $Modulo.Perfiles -contains $Perfil
}
