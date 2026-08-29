<#
.SYNOPSIS
    Versión del programa. Único sitio donde se toca al publicar.
#>

$script:VersionCachivache = '2.0.0'
$script:RepositorioUrl   = 'https://github.com/pacolopez23/cachivache'

function Get-VersionCachivache {
    [OutputType([string])]
    param()
    return $script:VersionCachivache
}
