<#
    [VEL-04] · lo que el programa acaba de borrar, convertido en cambios
    del indice.

    LA PREGUNTA QUE DE VERDAD SE PRUEBA AQUI no es "salen las bajas
    correctas" sino "PUEDE ESTA FUNCION QUITAR DEL INDICE ALGO QUE SIGUE EN
    EL DISCO". Quitar de mas es el fallo grave: ese archivo deja de
    ofrecerse para siempre y el programa miente por omision. Quitar de
    menos solo hace que el indice sobreestime hasta el siguiente recorrido.
    Por eso casi todas las pruebas de abajo empujan hacia el mismo sitio:
    ante cualquier duda, NO se da de baja.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    function script:Nuevo {
        # El parametro se llama Fallo y no Error, aunque el CAMPO del
        # candidato si se llame Error. $Error es la variable automatica
        # donde PowerShell acumula los errores de la sesion: usarla de
        # parametro la tapa dentro de la funcion, y si algo fallara ahi
        # dentro no habria donde mirarlo. Lo caza el analizador.
        param(
            [string] $Ruta,
            [string] $Metodo = 'Ruta',
            [bool]   $Hecho  = $true,
            [string] $Fallo  = ''
        )
        [pscustomobject]@{ Ruta = $Ruta; Metodo = $Metodo; Hecho = $Hecho; Error = $Fallo }
    }

    # Un indice de mentira con la forma que importa: las CLAVES de la tabla
    # de archivos, que es lo unico que esta funcion mira.
    $script:Rutas = @(
        'C:\Temp\a.txt'
        'C:\Temp\sub\b.txt'
        'C:\Temp\sub\hondo\c.txt'
        'C:\Temporal\d.txt'      # NO cuelga de C:\Temp: la trampa del prefijo
        'C:\Otra\e.txt'
        'C:\suelto.bin'
    )
}

Describe 'VEL-04: que le hace al indice cada metodo de borrado' {

    It 'los ocho metodos del ValidateSet estan clasificados, y en una sola lista' {
        # ESTA ES LA INVARIANTE, y esta escrita como la pregunta correcta:
        # no "estan bien los ocho que conozco?" sino "HAY ALGUNO SIN
        # CLASIFICAR?" (regla 8 de docs/RELEVO.md). Se lee el ValidateSet
        # de New-Candidato, que es la lista de verdad, en vez de repetirla
        # aqui: una copia a mano se queda vieja el dia que alguien anyada un
        # metodo, y ese dia el metodo nuevo caeria en 'Incierto' sin que
        # nadie lo hubiera decidido.
        $texto = [IO.File]::ReadAllText((Join-Path (Join-Path $script:Raiz 'src') 'Core/Candidate.ps1'))
        $m = [regex]::Match($texto, "ValidateSet\('Contenido'[^)]*\)")
        $m.Success | Should -BeTrue -Because 'sin el ValidateSet no hay lista de verdad que comprobar'
        $delValidateSet = @([regex]::Matches($m.Value, "'([^']+)'") |
                            ForEach-Object { $_.Groups[1].Value })
        $delValidateSet.Count | Should -BeGreaterThan 4

        $clasificados = @($script:MetodosBorranSubarbol) +
                        @($script:MetodosNoTocanIndice) +
                        @($script:MetodosEfectoIncierto)

        $sinClasificar = @($delValidateSet | Where-Object { $_ -notin $clasificados })
        $sinClasificar -join ', ' | Should -BeNullOrEmpty -Because (
            'un metodo sin clasificar contesta Incierto por descarte, y eso es una decision tomada por nadie')

        $fantasmas = @($clasificados | Where-Object { $_ -notin $delValidateSet })
        $fantasmas -join ', ' | Should -BeNullOrEmpty -Because 'clasificar un metodo que no existe es mantener una mentira'

        $repetidos = @($clasificados | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        $repetidos -join ', ' | Should -BeNullOrEmpty -Because 'en dos listas a la vez, gana la primera por casualidad'
    }

    It 'solo Ruta y Contenido borran el subarbol entero' {
        Get-EfectoEnIndice -Metodo 'Ruta'       | Should -Be 'Subarbol'
        Get-EfectoEnIndice -Metodo 'Contenido'  | Should -Be 'Subarbol'
    }

    It 'los metodos parciales y los opacos son inciertos, no "nada"' {
        # FirefoxCache y Miniaturas borran SOLO una parte a proposito;
        # Papelera y Comando no dicen que han tocado. Los cuatro tienen que
        # dar Incierto: 'Nada' afirmaria que no habia nada que quitar.
        foreach ($m in 'FirefoxCache', 'Miniaturas', 'Papelera', 'Comando') {
            Get-EfectoEnIndice -Metodo $m | Should -Be 'Incierto' -Because "$m no dice que ha borrado"
        }
    }

    It 'un metodo desconocido contesta Incierto, nunca Nada' {
        # El caso del futuro: alguien anyade un metodo y no toca este
        # archivo. La invariante de arriba lo cazara, pero mientras tanto el
        # comportamiento por descarte tiene que ser el prudente.
        Get-EfectoEnIndice -Metodo 'MetodoQueNadieHaEscritoTodavia' | Should -Be 'Incierto'
        Get-EfectoEnIndice -Metodo ''    | Should -Be 'Incierto'
        Get-EfectoEnIndice -Metodo $null | Should -Be 'Incierto'
    }
}

Describe 'VEL-04: cuando se puede afirmar que un subarbol ha desaparecido' {

    It 'con el metodo bueno, hecho y sin error, si' {
        Test-CandidatoBorroSuSubarbol -Candidato (script:Nuevo 'C:\Temp') | Should -BeTrue
    }

    It 'si no se hizo, no' {
        Test-CandidatoBorroSuSubarbol -Candidato (script:Nuevo 'C:\Temp' -Hecho $false) | Should -BeFalse
    }

    It 'HECHO CON ERROR NO BASTA: el resultado parcial no da de baja nada' {
        # Remove.ps1 deja Hecho a $true con Error relleno cuando el borrado
        # corrio pero quedaron archivos en uso: "Quedan 600 MB". Para el
        # registro de auditoria eso SI se hizo. Para el indice no, porque no
        # se sabe QUE 600 MB han sobrevivido. Es el mismo dato leido para
        # otra pregunta, y confundirlas quitaria del indice archivos que
        # siguen en el disco.
        $c = script:Nuevo 'C:\Temp'
        $c.Error = 'Quedan 600 MB: archivos en uso por algún programa abierto.'
        Test-CandidatoBorroSuSubarbol -Candidato $c | Should -BeFalse
    }

    It 'con un metodo incierto, no, aunque haya ido perfecto' {
        Test-CandidatoBorroSuSubarbol -Candidato (script:Nuevo 'C:\Temp' -Metodo 'Comando')  | Should -BeFalse
        Test-CandidatoBorroSuSubarbol -Candidato (script:Nuevo 'C:\Temp' -Metodo 'Papelera') | Should -BeFalse
    }

    It 'sin ruta, no' {
        Test-CandidatoBorroSuSubarbol -Candidato (script:Nuevo '')    | Should -BeFalse
        Test-CandidatoBorroSuSubarbol -Candidato (script:Nuevo '   ') | Should -BeFalse
    }

    It 'con un candidato nulo, no, y no lanza' {
        { Test-CandidatoBorroSuSubarbol -Candidato $null } | Should -Not -Throw
        Test-CandidatoBorroSuSubarbol -Candidato $null | Should -BeFalse
    }
}

Describe 'VEL-04: de la limpieza a las bajas del indice' {

    It 'una carpeta limpiada da de baja todo lo que colgaba de ella' {
        $r = Get-CambiosDeLimpieza -Candidatos @(script:Nuevo 'C:\Temp' -Metodo 'Contenido') -RutasIndice $script:Rutas
        $bajas = @($r.Cambios | ForEach-Object { $_.Ruta })
        $bajas | Should -Contain 'C:\Temp\a.txt'
        $bajas | Should -Contain 'C:\Temp\sub\b.txt'
        $bajas | Should -Contain 'C:\Temp\sub\hondo\c.txt'
        @($r.Cambios).Count | Should -Be 3
        @($r.Cambios | Where-Object { $_.Tipo -ne 'Baja' }).Count | Should -Be 0
    }

    It 'NO se lleva por delante una carpeta que solo comparte el principio del nombre' {
        # C:\Temporal empieza por C:\Temp. Sin la barra de separacion, esta
        # funcion borraria del indice archivos de OTRA carpeta que sigue
        # entera en el disco: el fallo grave, en su forma mas clasica. Lo
        # impide Get-RaizQueContiene, que exige la barra final, y por eso la
        # pertenencia se le pregunta a la guardia en vez de escribir aqui un
        # StartsWith.
        $r = Get-CambiosDeLimpieza -Candidatos @(script:Nuevo 'C:\Temp' -Metodo 'Contenido') -RutasIndice $script:Rutas
        @($r.Cambios | ForEach-Object { $_.Ruta }) | Should -Not -Contain 'C:\Temporal\d.txt'
    }

    It 'un archivo suelto se da de baja a si mismo' {
        # Get-RaizQueContiene exige barra final, asi que NO casa una ruta
        # consigo misma. Con el metodo Ruta el candidato puede ser un
        # archivo, y sin la comparacion extra se quedaria en el indice para
        # siempre.
        $r = Get-CambiosDeLimpieza -Candidatos @(script:Nuevo 'C:\suelto.bin') -RutasIndice $script:Rutas
        @($r.Cambios).Count | Should -Be 1
        $r.Cambios[0].Ruta | Should -Be 'C:\suelto.bin'
    }

    It 'no distingue mayusculas: Windows tampoco' {
        $r = Get-CambiosDeLimpieza -Candidatos @(script:Nuevo 'c:\temp\SUB' -Metodo 'Contenido') -RutasIndice $script:Rutas
        @($r.Cambios).Count | Should -Be 2
    }

    It 'un candidato incierto no aporta bajas Y NO ESTROPEA LAS DE LOS DEMAS' {
        # La primera version invalidaba el indice entero en cuanto aparecia
        # un metodo incierto. Como casi toda limpieza vacia la papelera o
        # lanza un comando, el atajo no se habria disparado NUNCA. Los
        # inciertos son deuda que se salda en el siguiente recorrido, no un
        # veneno que contamina la tanda.
        $r = Get-CambiosDeLimpieza -RutasIndice $script:Rutas -Candidatos @(
            (script:Nuevo 'C:\Temp' -Metodo 'Contenido')
            (script:Nuevo 'Papelera de reciclaje' -Metodo 'Papelera')
            (script:Nuevo 'DISM' -Metodo 'Comando')
        )
        @($r.Cambios).Count | Should -Be 3
        $r.Ciertos   | Should -Be 1
        $r.Inciertos | Should -Be 2
    }

    It 'lo que fallo no da de baja nada' {
        $r = Get-CambiosDeLimpieza -RutasIndice $script:Rutas -Candidatos @(
            (script:Nuevo 'C:\Temp'  -Metodo 'Contenido' -Hecho $false)
            (script:Nuevo 'C:\Otra'  -Metodo 'Contenido' -Fallo 'Bloqueado por la guardia')
        )
        @($r.Cambios).Count | Should -Be 0
        $r.Omitidos | Should -Be 2
    }

    It 'sin raices no se recorre el indice, y sale vacio' {
        $r = Get-CambiosDeLimpieza -Candidatos @() -RutasIndice $script:Rutas
        @($r.Cambios).Count | Should -Be 0
        @($r.Raices).Count  | Should -Be 0
    }

    It 'no lanza con nulos por ningun lado' {
        { Get-CambiosDeLimpieza -Candidatos $null -RutasIndice $null } | Should -Not -Throw
        { Get-CambiosDeLimpieza -Candidatos @($null, $null) -RutasIndice $script:Rutas } | Should -Not -Throw
        { Get-CambiosDeLimpieza -Candidatos @(script:Nuevo 'C:\Temp') -RutasIndice @($null, '', '   ') } | Should -Not -Throw
    }

    It 'LA INVARIANTE: ninguna baja cae fuera de lo que se declaro borrado' {
        # La comprobacion de verdad, y la unica que sigue valiendo si
        # manyana se cambia el algoritmo entero: TODA ruta dada de baja
        # tiene que ser una de las raices o colgar de una de ellas. Si esto
        # falla, el indice esta quitando archivos que nadie ha borrado.
        $candidatos = @(
            (script:Nuevo 'C:\Temp\sub' -Metodo 'Contenido')
            (script:Nuevo 'C:\suelto.bin')
            (script:Nuevo 'C:\Otra' -Metodo 'Comando')
        )
        $r = Get-CambiosDeLimpieza -Candidatos $candidatos -RutasIndice $script:Rutas
        @($r.Cambios).Count | Should -BeGreaterThan 0 -Because 'si no sale ninguna baja, esta prueba no comprueba nada'

        foreach ($cambio in $r.Cambios) {
            $dentro = $false
            foreach ($raiz in $r.Raices) {
                if ($cambio.Ruta.Equals($raiz, [StringComparison]::OrdinalIgnoreCase) -or
                    $cambio.Ruta.StartsWith($raiz + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    $dentro = $true; break
                }
            }
            $dentro | Should -BeTrue -Because "$($cambio.Ruta) no cuelga de ninguna ruta que se declarara borrada"
        }
    }

    It 'LA OTRA MITAD: nada que siga en el disco se da de baja' {
        # El reverso, y es el que caza el fallo grave. Se limpia una sola
        # carpeta y se exige que TODO lo que hay fuera de ella siga en el
        # indice. Recorre el indice entero en vez de comprobar dos rutas
        # elegidas a mano.
        $r = Get-CambiosDeLimpieza -Candidatos @(script:Nuevo 'C:\Temp\sub' -Metodo 'Contenido') -RutasIndice $script:Rutas
        $dadasDeBaja = @($r.Cambios | ForEach-Object { $_.Ruta })
        $supervivientes = @($script:Rutas | Where-Object { $_ -notlike 'C:\Temp\sub*' })
        foreach ($viva in $supervivientes) {
            $dadasDeBaja | Should -Not -Contain $viva -Because "$viva sigue en el disco y el indice la estaria perdiendo"
        }
    }
}
