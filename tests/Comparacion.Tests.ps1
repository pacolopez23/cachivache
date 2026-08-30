<#
    Pruebas de [CNF-06]: decir como estaba esto la vez anterior.

    El programa guarda historial desde hace tiempo y al terminar un
    analisis no decia nada de lo que habia antes. El dato estaba escrito
    en disco; solo faltaba decirlo.

    Casi todas las pruebas de aqui son sobre lo que NO se puede decir:
    comparar un analisis con una limpieza, dar por buena la cifra de un
    analisis que se canceló a mitad, o restar dos numeros que salieron de
    perfiles distintos. Las tres producen la misma frase -"antes habia
    menos"- y las tres son mentira por motivos distintos.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Codigo sin comentarios. Las pruebas que buscan texto encuentran los
    # comentarios del propio arreglo -ha pasado cinco veces en este
    # repositorio- y entonces pasan sin mirar nada.
    function script:Get-CodigoSinComentarios {
        param([string] $Ruta)
        $lineas = [IO.File]::ReadAllText($Ruta) -split "`r?`n"
        $fuera  = $false
        $limpio = foreach ($linea in $lineas) {
            if ($linea -match '<#')  { $fuera = $true }
            if ($fuera) {
                if ($linea -match '#>') { $fuera = $false }
                continue
            }
            if ($linea -match '^\s*#') { continue }
            $linea
        }
        ($limpio -join "`n")
    }

    $script:RutaComparacion = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Comparacion.ps1'
    $script:Codigo = script:Get-CodigoSinComentarios $script:RutaComparacion

    # Una entrada de historial como la que escribe Add-EntradaHistorial.
    # Las fechas llevan una hora de propina sobre los dias justos: sin
    # ella, un cambio de horario deja "hace 4 dias" en 3,96 dias y el
    # entero se queda en 3. Ha pasado en otros proyectos y no se ve venir.
    function script:New-EntradaFalsa {
        param(
            [string] $Tipo = 'analisis',
            [double] $DiasAtras = 4,
            [string] $Perfil = 'equilibrado',
            [string[]] $Modulos = @('caches', 'temporales'),
            [int] $Elementos = 890,
            [double] $Bytes = 3435973836.8,
            [bool] $Incompleto = $false
        )
        [pscustomobject]@{
            Fecha        = (Get-Date).AddDays(-$DiasAtras).AddHours(-1).ToString('o')
            Tipo         = $Tipo
            Perfil       = $Perfil
            Modulos      = @($Modulos)
            Elementos    = $Elementos
            Bytes        = $Bytes
            LibreAntes   = 0
            LibreDespues = 0
            Informe      = ''
            Incompleto   = $Incompleto
            Motivo       = ''
        }
    }
}

Describe 'CNF-06: de donde sale "el analisis anterior"' {

    It 'devuelve los ocho campos que la ventana necesita' {
        # Guarda: si el objeto cambiara de forma, las pruebas de abajo
        # compararian $null contra $null y pasarian todas.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa) -Perfil 'equilibrado' `
                                     -Modulos @('caches', 'temporales')
        foreach ($campo in @('HayReferencia', 'Caso', 'Motivos', 'Fecha',
                             'Elementos', 'Bytes', 'Texto', 'Sufijo')) {
            $r.PSObject.Properties.Name | Should -Contain $campo
        }
    }

    It 'una limpieza NO sirve de termino de comparacion' {
        # Los "Elementos" de una limpieza son los que se borraron y sus
        # "Bytes" el espacio liberado. Compararlos con lo que ENCUENTRA un
        # analisis es presentar dos magnitudes distintas como la misma.
        $historial = @(
            script:New-EntradaFalsa -Tipo 'analisis' -DiasAtras 9 -Elementos 890
            script:New-EntradaFalsa -Tipo 'limpieza' -DiasAtras 2 -Elementos 12
        )
        # Guarda: si el historial de prueba no trajera las dos clases,
        # esto no estaria comprobando nada.
        @($historial | Where-Object { $_.Tipo -eq 'limpieza' }).Count | Should -Be 1
        @($historial | Where-Object { $_.Tipo -eq 'analisis' }).Count | Should -Be 1

        $r = Get-ComparacionAnalisis -Historial $historial -Perfil 'equilibrado' `
                                     -Modulos @('caches', 'temporales')
        $r.Elementos | Should -Be 890
        $r.Texto     | Should -Not -BeLike '*12 elementos*'
    }

    It 'un tipo que no se conoce tampoco sirve' {
        # historial.json es texto plano en una carpeta escribible: puede
        # traer cualquier cosa. Lo que no se sabe que cuenta, no se compara.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Tipo 'limpieza-interrumpida') `
                                     -Perfil 'equilibrado' -Modulos @('caches')
        $r.HayReferencia | Should -BeFalse
        $r.Caso          | Should -Be 'sin-referencia'
    }

    It 'se compara con el ULTIMO analisis, no con el ultimo apunte' {
        $historial = @(
            script:New-EntradaFalsa -Tipo 'analisis' -DiasAtras 30 -Elementos 100
            script:New-EntradaFalsa -Tipo 'analisis' -DiasAtras 4  -Elementos 890
            script:New-EntradaFalsa -Tipo 'limpieza' -DiasAtras 1  -Elementos 5
        )
        (Get-ComparacionAnalisis -Historial $historial -Perfil 'equilibrado' `
                                 -Modulos @('caches', 'temporales')).Elementos | Should -Be 890
    }

    It 'sin ningun analisis anterior no se dice nada' {
        # El primer analisis de siempre. No hay un "0 elementos antes" que
        # ensenyar: antes no hubo una medicion de cero, es que no hubo
        # medicion.
        foreach ($h in @(@(), @($null), @(script:New-EntradaFalsa -Tipo 'limpieza'))) {
            $r = Get-ComparacionAnalisis -Historial $h -Perfil 'equilibrado' -Modulos @('caches')
            $r.HayReferencia | Should -BeFalse
            $r.Caso          | Should -Be 'sin-referencia'
            $r.Texto         | Should -BeNullOrEmpty
            $r.Sufijo        | Should -BeNullOrEmpty
            $r.Texto         | Should -Not -Match '0 elementos'
        }
    }

    It 'no revienta con nulos ni con un historial corrupto' {
        { Get-ComparacionAnalisis -Historial $null -Perfil $null -Modulos $null } | Should -Not -Throw
        (Get-ComparacionAnalisis -Historial $null -Perfil $null -Modulos $null).Caso |
            Should -Be 'sin-referencia'

        # Cadenas sueltas, nulos por medio y campos que traen un array
        # donde se esperaba un numero: es lo que dejo el fallo de
        # Get-Historial, y lo que reviento el arranque de la ventana.
        $basura = @(
            'esto no es una entrada'
            $null
            [pscustomobject]@{ Tipo = 'analisis'; Elementos = @(1, 2); Bytes = @('x'); Fecha = @('a') }
        )
        { Get-ComparacionAnalisis -Historial $basura -Perfil 'equilibrado' -Modulos @('caches') } |
            Should -Not -Throw
        (Get-ComparacionAnalisis -Historial $basura -Perfil 'equilibrado' -Modulos @('caches')).Elementos |
            Should -Be 0
    }
}

Describe 'CNF-06: no se compara lo que no es comparable' {

    It 'dos analisis iguales SI son comparables' {
        # Guarda del bloque entero: si el caso bueno tampoco saliera
        # comparable, todas las pruebas de abajo pasarian sin distinguir
        # nada.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa) -Perfil 'equilibrado' `
                                     -Modulos @('caches', 'temporales')
        $r.Caso    | Should -Be 'comparable'
        $r.Motivos | Should -BeNullOrEmpty
    }

    It 'el orden y las mayusculas de los modulos no cuentan' {
        # Es un conjunto, no una lista. Si contara el orden, cualquier
        # cambio en la cola de modulos diria que el usuario cambio algo.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Modulos @('Caches', 'Temporales')) `
                                     -Perfil 'equilibrado' -Modulos @('temporales', 'caches')
        $r.Caso | Should -Be 'comparable'
    }

    It 'un analisis incompleto NUNCA se da por comparable' {
        # [CNF-04]. Un analisis cancelado en el modulo 7 de 21 encontro
        # menos porque se MIRO menos. Callarlo es el programa afirmando
        # que habia menos cuando lo que paso es que miro menos.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Incompleto $true) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Caso    | Should -Be 'no-equiparable'
        $r.Motivos | Should -Contain 'incompleto'
        $r.Texto   | Should -BeLike '*incompleto*'
    }

    It 'un analisis incompleto se sigue ensenyando, con su aviso' {
        # No se esconde: es el unico dato que hay, y un hueco donde
        # deberia estar la comparacion se lee como que el programa no sabe
        # hacerla. Se ensenya diciendo que no vale del todo.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Incompleto $true -Elementos 890) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.HayReferencia | Should -BeTrue
        $r.Texto         | Should -BeLike '*890 elementos*'
        $r.Texto         | Should -BeLike '*no son cifras equiparables*'
    }

    It 'un incompleto no acusa ademas de haber mirado otros modulos' {
        # Un analisis cancelado anota los modulos REVISADOS, que son menos
        # POR estar cancelado. Contarlo aparte seria decir dos veces el
        # mismo hecho, y el segundo trozo suena a que el usuario cambio
        # algo cuando no cambio nada.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Incompleto $true -Modulos @('caches')) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Motivos | Should -Contain 'incompleto'
        $r.Motivos | Should -Not -Contain 'otros-modulos'
    }

    It 'otro perfil no es comparable, y se dice' {
        # Exhaustivo encuentra muchisimo mas que Conservador. Las dos
        # cifras son correctas y la resta no significa nada.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Perfil 'agresivo') `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Caso    | Should -Be 'no-equiparable'
        $r.Motivos | Should -Contain 'otro-perfil'
        $r.Texto   | Should -BeLike '*otro perfil*'
    }

    It 'otros modulos no es comparable, y se dice' {
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Modulos @('caches')) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Caso    | Should -Be 'no-equiparable'
        $r.Motivos | Should -Contain 'otros-modulos'
        $r.Texto   | Should -BeLike '*otros módulos*'
    }

    It 'lo que no consta no se da por igual NI se acusa de distinto' {
        # Una entrada que no anoto su perfil o sus modulos no dice que
        # fueran otros: dice que no se sabe. Inventarse una diferencia es
        # la misma familia de mentira que dar por buena una igualdad.
        foreach ($caso in @(
            @{ Perfil = ''; Modulos = @('caches', 'temporales') }
            @{ Perfil = 'equilibrado'; Modulos = @() }
        )) {
            $r = Get-ComparacionAnalisis `
                    -Historial @(script:New-EntradaFalsa -Perfil $caso.Perfil -Modulos $caso.Modulos) `
                    -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
            $r.Caso    | Should -Be 'no-equiparable'
            $r.Motivos | Should -Contain 'no-consta'
            $r.Motivos | Should -Not -Contain 'otro-perfil'
            $r.Motivos | Should -Not -Contain 'otros-modulos'
        }
    }

    It 'no se acusa dos veces de lo mismo' {
        # 'no-consta' cubre "no se sabe con que se hizo": si faltan las dos
        # cosas, sigue siendo un solo motivo y una sola frase.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Perfil '' -Modulos @()) `
                                     -Perfil 'equilibrado' -Modulos @('caches')
        @($r.Motivos | Where-Object { $_ -eq 'no-consta' }).Count | Should -Be 1
    }

    It 'varios motivos a la vez se dicen todos' {
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Perfil 'agresivo' -Incompleto $true) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Motivos | Should -Contain 'incompleto'
        $r.Motivos | Should -Contain 'otro-perfil'
        $r.Texto   | Should -BeLike '*quedó incompleto y usó otro perfil*'
    }
}

Describe 'CNF-06: cada motivo tiene su frase, y son distintas' {

    It 'los cuatro motivos se dicen de cuatro formas distintas' {
        # Guarda: si dos motivos compartieran frase, las pruebas de arriba
        # pasarian mirando la frase del otro.
        $codigos = @('incompleto', 'otro-perfil', 'otros-modulos', 'no-consta')
        $frases  = @($codigos | ForEach-Object { Get-FraseMotivoComparacion -Motivo $_ })
        @($frases | Select-Object -Unique).Count | Should -Be 4
        foreach ($f in $frases) { $f | Should -Not -BeNullOrEmpty }
    }

    It 'un motivo que no existe no inventa una frase' {
        Get-FraseMotivoComparacion -Motivo 'lo-que-sea' | Should -BeNullOrEmpty
    }

    It 'no revienta con nulos' {
        { Get-FraseMotivoComparacion -Motivo $null } | Should -Not -Throw
    }
}

Describe 'CNF-06: el texto que lee el usuario' {

    BeforeAll {
        $script:Textos = @(
            (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa) `
                 -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto
            (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Incompleto $true) `
                 -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto
            (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Perfil 'agresivo') `
                 -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto
            (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Modulos @('caches')) `
                 -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto
        )
    }

    It 'hay cuatro textos distintos: si no, esta prueba no compara nada' {
        @($script:Textos | Select-Object -Unique).Count | Should -Be 4
        foreach ($t in $script:Textos) { $t.Length | Should -BeGreaterThan 30 }
    }

    It 'ninguno usa una palabra sin su tilde' {
        $sinTilde = @('analisis', 'dias', 'modulos', 'quedo', 'uso', 'miro', 'anadido')
        $patron = '\b(' + ($sinTilde -join '|') + ')\b'
        foreach ($t in $script:Textos) { $t | Should -Not -CMatch $patron }
    }

    It 'dice cuando fue y cuanto habia, como pide la hoja de ruta' {
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -DiasAtras 4 -Elementos 890) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Texto | Should -BeLike '*hace 4 días*'
        $r.Texto | Should -BeLike '*890 elementos*'
        $r.Texto | Should -BeLike '*GB*'
    }

    It 'concuerda en singular: "era 1 elemento", nunca "eran 1 elementos"' {
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -Elementos 1) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Texto | Should -BeLike '*era 1 elemento *'
        $r.Texto | Should -Not -Match '1 elementos'
        $r.Texto | Should -Not -Match 'eran 1 '
    }

    It 'el Sufijo es el Texto con su espacio delante, y se pega sin un if' {
        # La ventana hace "$resumen += $comparacion.Sufijo" y ya esta. Con
        # Texto a secas habria que acordarse del espacio solo cuando hay
        # algo que anyadir, y ese if es una decision viviendo fuera de la
        # funcion pura.
        $r = Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa) `
                                     -Perfil 'equilibrado' -Modulos @('caches', 'temporales')
        $r.Sufijo | Should -Be (' ' + $r.Texto)
        $r.Sufijo.StartsWith(' ') | Should -BeTrue

        $vacia = Get-ComparacionAnalisis -Historial @() -Perfil 'equilibrado' -Modulos @('caches')
        $vacia.Sufijo | Should -Be ''

        # El primer dia el resumen tiene que quedar EXACTAMENTE igual que
        # antes de este punto: ni un espacio colgando al final.
        $resumen = '812 elementos encontrados.'
        ($resumen + $vacia.Sufijo) | Should -Be $resumen
    }

    It 'el tiempo transcurrido se dice en dias o en horas, segun toque' {
        (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -DiasAtras 4) `
             -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto |
            Should -BeLike '*hace 4 días*'

        # Dos horas. Format-Antiguedad solo sabria decir "hoy", que delante
        # de una cifra se lee como si fuera de ahora mismo.
        (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -DiasAtras 0.0417) `
             -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto |
            Should -BeLike '*hace 2 h*'

        (Get-ComparacionAnalisis -Historial @(script:New-EntradaFalsa -DiasAtras 1) `
             -Perfil 'equilibrado' -Modulos @('caches', 'temporales')).Texto |
            Should -BeLike '*ayer*'
    }

    It 'una fecha ilegible o del futuro no se convierte en un "hace"' {
        # Reloj desajustado o archivo tocado a mano. "hace menos de 1 s"
        # delante de un analisis de la semana que viene es una cifra
        # inventada; no saber cuando fue no impide decir cuanto habia.
        $futuro = script:New-EntradaFalsa
        $futuro.Fecha = (Get-Date).AddDays(5).ToString('o')
        $rota = script:New-EntradaFalsa
        $rota.Fecha = 'esto no es una fecha'

        foreach ($entrada in @($futuro, $rota)) {
            $r = Get-ComparacionAnalisis -Historial @($entrada) -Perfil 'equilibrado' `
                                         -Modulos @('caches', 'temporales')
            $r.Texto | Should -BeLike '*el análisis anterior*'
            $r.Texto | Should -Not -Match 'hace '
            $r.Texto | Should -BeLike '*890 elementos*'
        }
    }
}

Describe 'CNF-06: no se escribe un segundo formateador' {

    It 'el archivo tiene codigo: si no, nada de esto comprueba nada' {
        $script:Codigo.Length | Should -BeGreaterThan 2000
    }

    It 'el tiempo lo formatean las funciones que ya estaban en Format.ps1' {
        # Dos formateadores de tiempo acaban discrepando, y el usuario ve
        # "ayer" en la tabla y "hace 1 día" en el resumen.
        $script:Codigo | Should -Match 'Format-Antiguedad'
        $script:Codigo | Should -Match 'Format-Duracion'
    }

    It 'no hay aqui ni una unidad de tiempo escrita a mano' {
        # Si alguna vez aparece un "hace {0} dias" en este archivo, es que
        # se ha vuelto a escribir el formateador que ya existe.
        foreach ($palabra in @('días', 'meses', 'años', 'semanas')) {
            $script:Codigo | Should -Not -Match $palabra
        }
    }

    It 'el tamanyo lo formatea Format-Tamano, no una division a mano' {
        $script:Codigo | Should -Match 'Format-Tamano'
        $script:Codigo | Should -Not -Match '/ 1GB'
    }

    It 'los numeros del historial pasan por ConvertTo-DoubleSeguro' {
        # Un array donde se esperaba un numero ya tiro la ventana una vez.
        $script:Codigo | Should -Match 'ConvertTo-DoubleSeguro'
    }
}

Describe 'CNF-06: el nucleo carga el archivo' {

    It 'Bootstrap.ps1 nombra Comparacion.ps1' {
        # Sin esto la funcion no existe en el hilo de la ventana y la
        # llamada del resumen se va al catch general sin decir nada.
        $bootstrap = Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
        $bootstrap | Should -Match "'Comparacion\.ps1'"
    }
}
