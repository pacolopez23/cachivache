<#
.SYNOPSIS
    Normalizacion de texto para COMPARAR identidad.

.DESCRIPTION
    Ojo con la diferencia: esto no es formato de presentación (eso es
    Format.ps1). Aquí se reduce un texto a una forma canonica para poder
    decidir si dos nombres se refieren a la misma cosa, y de esa decisión
    dependen la guardia de seguridad y la detección de restos de
    programas. Un cambio aquí puede hacer que la guardia deje de
    reconocer una carpeta protegida.

    Sus consumidores (Guard.ps1, Registry.ps1 y 30-RestosProgramas) no
    usan ni una sola de las funciones de formato de Format.ps1, donde
    vivian estas dos: son dos grupos con consumidores disjuntos. Ver
    docs/ESTRUCTURA.md (sección 6).
#>

function Remove-Tildes {
    <#
    .SYNOPSIS
        Quita los signos diacriticos de una cadena.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Transforma una cadena: no borra ningún recurso.')]
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Texto)

    if ([string]::IsNullOrWhiteSpace($Texto)) { return '' }

    # Atajo para texto ASCII puro, que es el 95% de lo que pasa por aquí:
    # si no hay ni un caracter fuera del rango imprimible ASCII, no hay
    # nada que descomponer y se devuelve tal cual. Sin esto se recorre
    # caracter a caracter con una llamada a GetUnicodeCategory por cada
    # uno, y esta función se ejecuta por cada nombre de carpeta Y por cada
    # token del vocabulario de programas instalados. Ver [REN-01].
    if ($Texto -cmatch '^[\x20-\x7E]*$') { return $Texto }

    $normalizado = $Texto.Normalize([Text.NormalizationForm]::FormD)
    $sb = [Text.StringBuilder]::new()
    foreach ($c in $normalizado.ToCharArray()) {
        $categoria = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
        if ($categoria -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    return $sb.ToString()
}

function ConvertTo-Token {
    <#
    .SYNOPSIS
        Reduce un texto a minusculas sin tildes ni simbolos.
    .DESCRIPTION
        Se usa para comparar nombres de carpeta con nombres de programas
        instalados: "Adobe Acrobat (2024)" y "adobe-acrobat2024" producen
        el mismo token.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Texto)

    return ((Remove-Tildes $Texto).ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Remove-SufijoVersion {
    <#
    .SYNOPSIS
        Quita los digitos del final de un token YA normalizado.
    .DESCRIPTION
        Sirve para emparejar un nombre con el mismo programa en otra
        version. "python39" y "python", "office2016" y "office", "java8" y
        "java" son la misma cosa a efectos de decidir si una carpeta
        corresponde a algo instalado, y con el token tal cual no casaban.

        Solo se quitan los digitos FINALES, no todos. Quitarlos todos
        convertiria "7zip" en "zip" y "1password" en "password", que son
        programas distintos: el numero de delante forma parte del nombre.
        Ver [DET-01] en docs/PLAN-ACCION.md.

        Recibe un token y no texto libre a proposito. Quien ya tiene el
        token -Test-TokenConocido, que lo consulta por cada carpeta- no
        tiene que volver a normalizar el nombre entero solo para pedir esta
        variante. La regla vive aqui, en un sitio; ConvertTo-TokenSinVersion
        es la comodidad para quien parte del texto.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Transforma una cadena: no borra ningún recurso.')]
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Token)

    if ([string]::IsNullOrEmpty($Token)) { return '' }
    $recortado = $Token -replace '[0-9]+$', ''

    # Si al quitar los digitos no queda casi nada, no aporta: se devuelve
    # el token entero para no emparejar cosas por un resto de dos letras.
    if ($recortado.Length -lt 3) { return $Token }
    return $recortado
}

function ConvertTo-TokenSinVersion {
    <#
    .SYNOPSIS
        Como ConvertTo-Token, pero ademas sin los digitos del final.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Texto)

    return (Remove-SufijoVersion (ConvertTo-Token $Texto))
}
