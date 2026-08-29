<#
    Pruebas del historial, centradas en [CNF-04].

    El historial es lo UNICO que queda semanas despues: el registro se
    rota por meses y los informes se acumulan sin que nadie los abra. Si
    una limpieza detenida en el elemento 3 de 400 se anota igual que una
    completa, dentro de un mes no hay forma de saber que paso.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'Add-EntradaHistorial: incompleto y motivo' {

    BeforeEach {
        $script:Datos = Join-Path ([IO.Path]::GetTempPath()) ('cachivache-hist-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Datos -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Datos -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'por defecto una entrada NO es incompleta' {
        # El caso normal no puede requerir que nadie se acuerde de nada.
        Add-EntradaHistorial -Tipo 'analisis' -Elementos 10 -Bytes 1000 `
                             -CarpetaDatos $script:Datos -Confirm:$false
        $e = @(Get-Historial -CarpetaDatos $script:Datos)[-1]
        $e.Incompleto | Should -BeFalse
        $e.Motivo     | Should -BeNullOrEmpty
    }

    It 'guarda que quedo incompleta y por que' {
        Add-EntradaHistorial -Tipo 'limpieza' -Elementos 3 -Bytes 500 `
                             -Incompleto -Motivo 'La detuviste a mitad: 3 de 400.' `
                             -CarpetaDatos $script:Datos -Confirm:$false
        $e = @(Get-Historial -CarpetaDatos $script:Datos)[-1]
        $e.Incompleto | Should -BeTrue
        $e.Motivo     | Should -BeLike '*3 de 400*'
    }

    It 'los dos campos sobreviven a la ida y vuelta por JSON' {
        # El historial se guarda en disco y se relee. Un campo que se
        # escribe pero no se lee no sirve de nada, y es justo el tipo de
        # cosa que se cuela cuando se anyaden campos a mano.
        Add-EntradaHistorial -Tipo 'analisis' -Elementos 1 -Bytes 1 `
                             -Incompleto -Motivo 'Fallaron 2 modulos.' `
                             -CarpetaDatos $script:Datos -Confirm:$false

        $texto = Get-Content -Raw -LiteralPath (Get-RutaHistorial -CarpetaDatos $script:Datos)
        $texto | Should -BeLike '*Incompleto*'
        $texto | Should -BeLike '*Fallaron 2 modulos*'
    }

    It 'una entrada antigua sin los campos nuevos se sigue leyendo' {
        # historial.json es de una version anterior en cualquier equipo que
        # ya tuviera Cachivache. Si anyadir campos rompiera la lectura, el
        # usuario perderia su historial entero al actualizar, que es
        # exactamente lo que no puede pasar por anyadir una bandera.
        $ruta = Get-RutaHistorial -CarpetaDatos $script:Datos
        $viejo = @([pscustomobject]@{
            Fecha = (Get-Date).ToString('o'); Tipo = 'limpieza'; Perfil = 'equilibrado'
            Modulos = @('caches'); Elementos = 5; Bytes = 100
            LibreAntes = 0; LibreDespues = 0; Informe = ''
        })
        $viejo | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ruta -Encoding UTF8

        $leido = @(Get-Historial -CarpetaDatos $script:Datos)
        $leido.Count | Should -Be 1
        $leido[0].Elementos | Should -Be 5
        # Sin el campo, la propiedad no existe: quien lo lea tiene que
        # tratar la ausencia como "completa", que es lo que era antes.
        [bool]$leido[0].Incompleto | Should -BeFalse
    }

    It 'anyadir una entrada nueva junto a otra antigua no rompe nada' {
        $ruta = Get-RutaHistorial -CarpetaDatos $script:Datos
        @([pscustomobject]@{
            Fecha = (Get-Date).ToString('o'); Tipo = 'analisis'; Perfil = 'equilibrado'
            Modulos = @(); Elementos = 1; Bytes = 1
            LibreAntes = 0; LibreDespues = 0; Informe = ''
        }) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ruta -Encoding UTF8

        Add-EntradaHistorial -Tipo 'limpieza' -Elementos 2 -Bytes 2 -Incompleto `
                             -CarpetaDatos $script:Datos -Confirm:$false

        $leido = @(Get-Historial -CarpetaDatos $script:Datos)
        $leido.Count | Should -Be 2
        [bool]$leido[-1].Incompleto | Should -BeTrue
    }
}
