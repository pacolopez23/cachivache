<#
    Pruebas de la normalizacion de texto para comparar identidad.
    De estas funciones dependen la guardia de seguridad y la detección
    de restos de programas: no son formato de presentación.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'ConvertTo-Token' {

    It 'normaliza "<Texto>" a "<Esperado>"' -ForEach @(
        @{ Texto = 'Adobe Acrobat (2024)'; Esperado = 'adobeacrobat2024' }
        @{ Texto = 'Nvidia-Corporation';   Esperado = 'nvidiacorporation' }
        @{ Texto = '';                     Esperado = '' }
    ) { ConvertTo-Token $Texto | Should -Be $Esperado }

    It 'normaliza tambien los acentos y la enye' {
        # Los caracteres se construyen por código para que este archivo
        # siga siendo ASCII puro y no dependa de la codificación.
        $texto = 'Cami' + [char]0x00F3 + 'n Espa' + [char]0x00F1 + 'ol'
        ConvertTo-Token $texto | Should -Be 'camionespanol'
    }
}

Describe 'Remove-Tildes' {

    It 'quita los acentos conservando las letras' {
        $texto = 'Configuraci' + [char]0x00F3 + 'n R' + [char]0x00E1 + 'pida'
        Remove-Tildes $texto | Should -Be 'Configuracion Rapida'
    }

    It 'reduce la enye a n, que es lo que permite emparejar nombres' {
        # Es deliberado: así "Espanol" y "Espanol" con enye producen el
        # mismo token y una carpeta se reconoce escriba como se escriba.
        Remove-Tildes ([char]0x00F1) | Should -Be 'n'
    }
}
