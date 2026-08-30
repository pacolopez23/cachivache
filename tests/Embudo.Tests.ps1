<#
    ARQ-02: el embudo de Invoke-ModuloLimpieza, convertido en lista de reglas.

    Invoke-ModuloLimpieza es el unico sitio por el que pasan todos los
    candidatos de todos los modulos. Hasta ahora aplicaba tres filtros
    cableados a mano, uno detras de otro; ahora recorre la lista que
    devuelve Get-ReglasFiltroCandidato.

    LO QUE HACE PELIGROSO ESTE CAMBIO, y el motivo de que estas pruebas
    existan: aqui se decide QUE SE PROPONE BORRAR. Una regla que deje de
    aplicarse no lanza ninguna excepcion ni deja ningun rastro en el
    registro: propone DE MAS. El sintoma de "se me ha olvidado aplicar la
    guardia" es identico al de "todo va bien" salvo por una fila de mas en
    una tabla de miles.

    De ahi las cuatro cosas que se exigen aqui:

      1. Regla a regla: para CADA regla de la lista hay un candidato que
         solo esa regla rechaza, y el embudo lo tira. Si alguien recorre
         media lista, o quita una regla, cae una prueba con nombre propio.
      2. La lista es el contrato: toda regla tiene su caso. Anyadir una
         regla sin caso hace fallar la prueba, asi que la cobertura no se
         queda atras por olvido.
      3. El resultado NO depende del orden: se compara el embudo con las
         mismas reglas aplicadas al reves y aplicadas por separado.
      4. El coste SI depende del orden: las reglas van de barata a cara, y
         se comprueba que al embudo no le da tiempo a preguntarle al disco
         por un candidato que una regla de texto ya habia tirado.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Guardia inicializada con carpetas personales vacias: asi el veredicto
    # de la guardia depende solo de la ruta del caso, no de donde se
    # ejecuten las pruebas.
    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio = ''; Documentos = ''; Descargas = ''
        Imagenes   = ''; Musica     = ''; Videos     = ''; CarpetaDatos = ''
    })

    # La configuracion de referencia de todo el archivo: una unidad
    # elegida y una carpeta excluida, que es lo que hace falta para que
    # cada regla tenga algo que rechazar.
    $script:Cfg = [pscustomobject]@{
        Admin                 = $true
        UnidadesSeleccionadas = @('C:')
        RutasExcluidas        = @('C:\excluida')
    }

    # Aplica UNA regla suelta EXACTAMENTE como la aplica el embudo. Si el
    # embudo cambiara la forma de invocarlas, esta funcion tendria que
    # cambiar con el, y eso es deliberado: no se prueba un mecanismo
    # distinto del que corre en produccion.
    function Invoke-ReglaSuelta {
        param($Regla, $Candidatos, $Contexto)
        return @(@($Candidatos) | Where-Object { & $Regla.Predicado $Contexto })
    }

    # Los candidatos de los casos. Cada uno esta construido para que lo
    # rechace UNA sola regla, con lo que su desaparicion no se puede
    # atribuir a otra cosa.
    function Get-CandidatoDeCaso {
        param([string] $Caso)

        switch ($Caso) {
            # Metodo Informativo: exento de la guardia. Unidad C: elegida.
            # Fuera de la carpeta excluida. No lo rechaza ninguna regla.
            'control' {
                return New-Candidato -ModuloId 'prueba' -Categoria 'c' -Nombre 'control' `
                                     -Ruta 'C:\normal\cosa' -Bytes 100 -Metodo 'Informativo' -Raices @()
            }
            # Unidad D:, que no esta elegida. Informativo, asi que la
            # guardia no tiene nada que decir sobre el.
            'otra unidad' {
                return New-Candidato -ModuloId 'prueba' -Categoria 'c' -Nombre 'en D' `
                                     -Ruta 'D:\algo\en-d' -Bytes 90 -Metodo 'Informativo' -Raices @()
            }
            # Dentro de la carpeta que el usuario excluyo, en la unidad
            # elegida y exento de la guardia.
            'excluido' {
                return New-Candidato -ModuloId 'prueba' -Categoria 'c' -Nombre 'excluido' `
                                     -Ruta 'C:\excluida\cosa' -Bytes 80 -Metodo 'Informativo' -Raices @()
            }
            # Ruta del sistema en la unidad elegida y fuera de lo excluido:
            # solo la guardia puede tirarlo. Y la tira sin tocar el disco,
            # por el fragmento prohibido "\system32\", de modo que el caso
            # da el mismo veredicto en Windows y en Linux.
            'vetado por la guardia' {
                return New-Candidato -ModuloId 'prueba' -Categoria 'c' -Nombre 'system32' `
                                     -Ruta 'C:\Windows\System32' -Bytes 70 -Metodo 'Ruta' `
                                     -Raices @('C:\Windows')
            }
            default { throw "Caso desconocido: $Caso" }
        }
    }

    # Modulo de mentira que emite los candidatos que se le dejen en
    # $script:Emision. Se usa una variable de ambito de script y no un
    # cierre a proposito: un cierre se ejecuta en el ambito de un modulo
    # dinamico donde no se ven las funciones del nucleo.
    $script:Emision = @()
    $script:ModuloFalso = New-ModuloLimpieza -Id 'prueba' -Orden 99 `
        -Nombre 'Modulo de prueba' -Descripcion 'Emite lo que se le deje preparado.' `
        -Buscar {
            param($Configuracion, $Sync)
            foreach ($c in $script:Emision) { $c }
        }

    function Get-ClavesOrdenadas {
        param($Lista)
        return @(@($Lista) | Where-Object { $null -ne $_ } |
                 ForEach-Object { $_.ClaveExclusion } | Sort-Object)
    }
}

Describe 'ARQ-02: la lista de reglas es el contrato del embudo' {

    It 'hay al menos las cuatro reglas de hoy, y cada una tiene nombre, coste y predicado' {
        $reglas = @(Get-ReglasFiltroCandidato)

        # Guarda: sin reglas, todo lo demas de este archivo comprobaria el
        # vacio y pasaria.
        $reglas.Count | Should -BeGreaterOrEqual 4 -Because 'sin reglas el embudo no filtra nada'

        foreach ($regla in $reglas) {
            $regla.Nombre    | Should -Not -BeNullOrEmpty
            $regla.Predicado | Should -BeOfType [scriptblock]
            $regla.Coste     | Should -BeOfType [int]
        }
    }

    It 'los nombres no se repiten: son la clave con la que las prueba todo esto' {
        $nombres = @(Get-ReglasFiltroCandidato | ForEach-Object { $_.Nombre })
        @($nombres | Select-Object -Unique).Count | Should -Be $nombres.Count
    }

    It 'la lista no depende de la configuracion: se puede pedir sin nada montado' {
        # Las reglas son estaticas; lo que varia entre analisis es el
        # contexto. Si esto dejara de ser cierto habria dos fuentes de
        # verdad sobre que filtros existen.
        { Get-ReglasFiltroCandidato } | Should -Not -Throw
    }
}

Describe 'ARQ-02: regla a regla, cada una rechaza lo suyo y respeta el resto' {
    <#
        Nivel de regla, sin embudo. Cada caso comprueba las dos mitades:
        que la regla tira lo que tiene que tirar Y que deja pasar el
        control. Una regla que rechazara todo tambien seria un fallo, y
        uno que en el embudo se veria igual: menos filas.
    #>

    It "la regla '<Regla>' rechaza el candidato '<Caso>' y deja pasar el control" -ForEach @(
        @{ Regla = 'Unidad seleccionada';     Caso = 'otra unidad' }
        @{ Regla = 'Exclusiones del usuario'; Caso = 'excluido' }
        @{ Regla = 'Guardia de rutas';        Caso = 'vetado por la guardia' }
    ) {
        $regla = @(Get-ReglasFiltroCandidato | Where-Object { $_.Nombre -eq $Regla })
        $regla.Count | Should -Be 1 -Because "sin la regla '$Regla' este caso no comprueba nada"

        $contexto = New-ContextoEmbudo -Configuracion $script:Cfg
        $malo     = Get-CandidatoDeCaso -Caso $Caso
        $bueno    = Get-CandidatoDeCaso -Caso 'control'

        (Invoke-ReglaSuelta -Regla $regla[0] -Candidatos $malo  -Contexto $contexto).Count |
            Should -Be 0 -Because "'$Regla' existe para rechazar esto"
        (Invoke-ReglaSuelta -Regla $regla[0] -Candidatos $bueno -Contexto $contexto).Count |
            Should -Be 1 -Because "'$Regla' no puede llevarse por delante un candidato legitimo"
    }

    It 'la regla del candidato nulo tira el nulo y solo el nulo' {
        # Esta no se puede probar por el embudo: quien recoge los
        # candidatos ya descarta los nulos antes de llegar a las reglas.
        # Es defensa en profundidad, y se prueba donde vive.
        $regla = @(Get-ReglasFiltroCandidato | Where-Object { $_.Nombre -eq 'Candidato existente' })
        $regla.Count | Should -Be 1

        $contexto = New-ContextoEmbudo -Configuracion $script:Cfg

        # Los nulos van MEZCLADOS con un candidato de verdad, y no solos,
        # porque solos no prueban nada: al pasar @($null) a un parametro
        # sin tipo, PowerShell lo entrega como $null a secas, la lista
        # llega vacia y el filtro no llega a ejecutarse ni una vez. Esta
        # prueba paso una version entera siendo hueca, y lo canto la
        # mutacion: quitar la regla no la hacia fallar.
        $mezcla = @($null, (Get-CandidatoDeCaso -Caso 'control'), $null)
        $mezcla.Count | Should -Be 3 -Because 'si la lista llega colapsada, este caso no comprueba nada'

        $vivos = Invoke-ReglaSuelta -Regla $regla[0] -Candidatos $mezcla -Contexto $contexto
        $vivos.Count | Should -Be 1
        $vivos[0].ClaveExclusion | Should -Be 'C:\normal\cosa'
    }

    It 'toda regla de la lista tiene su caso aqui: anyadir una sin probarla hace fallar esto' {
        # La cobertura no se puede quedar atras por olvido. Si manyana
        # entra la cuarta regla y nadie escribe su caso, cae esta prueba y
        # dice cual falta.
        $conCaso = @(
            'Candidato existente'
            'Unidad seleccionada'
            'Exclusiones del usuario'
            'Guardia de rutas'
        )
        $sinCaso = @(Get-ReglasFiltroCandidato |
                     Where-Object { $_.Nombre -notin $conCaso } |
                     ForEach-Object { $_.Nombre })

        $sinCaso | Should -BeNullOrEmpty -Because (
            'una regla sin caso es una regla que puede dejar de aplicarse sin que nadie se entere')
    }
}

Describe 'ARQ-02: el embudo aplica TODAS las reglas, no las que le apetezca' {
    <#
        Lo mismo pero de punta a punta, por Invoke-ModuloLimpieza. Es lo
        que caza que alguien recorra media lista, se salte el bucle o
        vuelva a cablear un filtro por su cuenta.
    #>

    BeforeEach {
        $script:Emision = @(
            (Get-CandidatoDeCaso -Caso 'control')
            (Get-CandidatoDeCaso -Caso 'otra unidad')
            (Get-CandidatoDeCaso -Caso 'excluido')
            (Get-CandidatoDeCaso -Caso 'vetado por la guardia')
        )
    }

    It "el embudo tira '<Caso>', que es lo que rechaza la regla '<Regla>'" -ForEach @(
        @{ Regla = 'Unidad seleccionada';     Caso = 'otra unidad';           Clave = 'D:\algo\en-d' }
        @{ Regla = 'Exclusiones del usuario'; Caso = 'excluido';              Clave = 'C:\excluida\cosa' }
        @{ Regla = 'Guardia de rutas';        Caso = 'vetado por la guardia'; Clave = 'C:\Windows\System32' }
    ) {
        $r = Invoke-ModuloLimpieza -Modulo $script:ModuloFalso -Configuracion $script:Cfg

        $claves = Get-ClavesOrdenadas $r.Candidatos
        $claves | Should -Not -BeNullOrEmpty -Because 'si no sobrevive nada, esta prueba no distingue nada'
        $claves | Should -Contain 'C:\normal\cosa' -Because 'el control tiene que seguir vivo'
        $claves | Should -Not -Contain $Clave -Because "la regla '$Regla' ha dejado de aplicarse: se propone de mas"
    }

    It 'de los cuatro candidatos sobrevive exactamente el control' {
        $r = Invoke-ModuloLimpieza -Modulo $script:ModuloFalso -Configuracion $script:Cfg
        $r.Candidatos.Count | Should -Be 1
        $r.Descartados      | Should -Be 3 -Because 'lo que tira el embudo se sigue contando'
    }
}

Describe 'ARQ-02: el ORDEN de las reglas no cambia el resultado' {
    <#
        Los predicados son puros y no dependen unos de otros, asi que lo
        que sobrevive es la interseccion, y una interseccion es la misma se
        calcule en el orden que se calcule. Esto no es una obviedad que
        sobre: es lo que AUTORIZA a reordenar las reglas por coste. Si un
        dia alguien anyade una regla con estado -que cuente, que recuerde,
        que dependa de lo que ya paso-, esta prueba es la que se entera.
    #>

    BeforeEach {
        $script:Emision = @(
            (Get-CandidatoDeCaso -Caso 'control')
            (Get-CandidatoDeCaso -Caso 'otra unidad')
            (Get-CandidatoDeCaso -Caso 'excluido')
            (Get-CandidatoDeCaso -Caso 'vetado por la guardia')
        )
    }

    It 'el embudo, las reglas al derecho, las reglas al reves y las reglas por separado dan lo mismo' {
        $contexto = New-ContextoEmbudo -Configuracion $script:Cfg
        $reglas   = @(Get-ReglasFiltroCandidato)
        $todos    = @($script:Emision)

        $delEmbudo = Get-ClavesOrdenadas (Invoke-ModuloLimpieza -Modulo $script:ModuloFalso `
                                                                -Configuracion $script:Cfg).Candidatos

        $enOrden = $todos
        foreach ($regla in $reglas) {
            $enOrden = Invoke-ReglaSuelta -Regla $regla -Candidatos $enOrden -Contexto $contexto
        }

        $alReves = $todos
        foreach ($regla in ($reglas[($reglas.Count - 1)..0])) {
            $alReves = Invoke-ReglaSuelta -Regla $regla -Candidatos $alReves -Contexto $contexto
        }

        # Y por separado: cada candidato se somete a cada regla a solas,
        # sin que ninguna haya podido quitar nada antes.
        $porSeparado = @()
        foreach ($candidato in $todos) {
            $loAceptanTodas = $true
            foreach ($regla in $reglas) {
                if ((Invoke-ReglaSuelta -Regla $regla -Candidatos $candidato -Contexto $contexto).Count -eq 0) {
                    $loAceptanTodas = $false
                }
            }
            if ($loAceptanTodas) { $porSeparado += $candidato }
        }

        # Guarda: con todo vacio las cuatro listas serian iguales y esto
        # no comprobaria nada.
        $delEmbudo.Count | Should -BeGreaterThan 0
        $todos.Count     | Should -BeGreaterThan $delEmbudo.Count

        (Get-ClavesOrdenadas $enOrden)     | Should -Be $delEmbudo
        (Get-ClavesOrdenadas $alReves)     | Should -Be $delEmbudo -Because 'el resultado no puede depender del orden'
        (Get-ClavesOrdenadas $porSeparado) | Should -Be $delEmbudo -Because 'ninguna regla puede depender de otra'
    }
}

Describe 'ARQ-02: el COSTE si depende del orden, y por eso van de barata a cara' {
    <#
        La guardia es la unica regla que consulta el disco: un Get-Item por
        candidato mas uno por nivel de carpeta dentro de
        Test-CadenaSinEnlaces. Preguntarle al disco por un candidato que la
        lista de unidades o la de exclusiones ya iba a tirar es trabajo
        tirado, y antes de este punto era exactamente lo que pasaba, porque
        la guardia iba la primera.

        Que vaya la ultima no la debilita: para sobrevivir hay que pasar
        TODAS, y eso lo fija el Describe de arriba.
    #>

    It 'los costes declarados no decrecen' {
        $reglas = @(Get-ReglasFiltroCandidato)

        # Guarda: si todas costaran lo mismo, "no decrece" seria cierto
        # por vacio y esta prueba no diria nada.
        @($reglas | ForEach-Object { $_.Coste } | Select-Object -Unique).Count |
            Should -BeGreaterThan 1 -Because 'sin costes distintos no hay orden que proteger'

        for ($i = 1; $i -lt $reglas.Count; $i++) {
            $reglas[$i].Coste | Should -BeGreaterOrEqual $reglas[$i - 1].Coste -Because (
                ("la regla '{0}' cuesta menos que la anterior '{1}': el embudo esta pagando " +
                 'el filtro caro para candidatos que el barato ya iba a tirar') -f
                $reglas[$i].Nombre, $reglas[$i - 1].Nombre)
        }
    }

    It 'la unica regla que toca el disco es la mas cara de la lista' {
        $reglas  = @(Get-ReglasFiltroCandidato)
        $guardia = @($reglas | Where-Object { $_.Nombre -eq 'Guardia de rutas' })
        $guardia.Count | Should -Be 1

        $maximo = @($reglas | ForEach-Object { $_.Coste } | Measure-Object -Maximum).Maximum
        $guardia[0].Coste | Should -Be $maximo
    }

    Context 'y se nota: al disco no se le pregunta por lo que ya estaba descartado' {

        BeforeAll {
            # Metodo 'Ruta', que NO esta exento de la guardia, para que la
            # unica razon de que no se consulte el disco sea que otra regla
            # lo tiro antes.
            function Get-CandidatoEnUnidad {
                param([string] $Unidad)
                return New-Candidato -ModuloId 'prueba' -Categoria 'c' -Nombre 'algo' `
                                     -Ruta ($Unidad + '\carpeta\cosa') -Bytes 10 -Metodo 'Ruta' `
                                     -Raices @($Unidad + '\carpeta')
            }
        }

        It 'un candidato de una unidad no elegida no llega a la guardia' {
            Mock Test-RutaSegura { return $true }
            $script:Emision = @(Get-CandidatoEnUnidad -Unidad 'D:')

            $null = Invoke-ModuloLimpieza -Modulo $script:ModuloFalso -Configuracion $script:Cfg

            Should -Invoke Test-RutaSegura -Times 0 -Exactly -Because (
                'la regla de unidad cuesta una comparacion de texto y la guardia, varias lecturas de disco')
        }

        It 'pero a un candidato que llega hasta ella si se le pregunta' {
            # Guarda de la prueba de arriba: sin esto, un embudo que no
            # llamara NUNCA a la guardia tambien la pasaria.
            Mock Test-RutaSegura { return $true }
            $script:Emision = @(Get-CandidatoEnUnidad -Unidad 'C:')

            $null = Invoke-ModuloLimpieza -Modulo $script:ModuloFalso -Configuracion $script:Cfg

            Should -Invoke Test-RutaSegura -Times 1 -Exactly
        }
    }
}

Describe 'ARQ-02: el contexto del embudo se calcula una vez y aguanta lo raro' {

    It 'sin configuracion no revienta y no inventa exclusiones' {
        # [AllowNull] en un parametro Mandatory que de verdad recibe nulo:
        # el modo consola y varias pruebas llaman al embudo asi.
        { New-ContextoEmbudo -Configuracion $null } | Should -Not -Throw

        $contexto = New-ContextoEmbudo -Configuracion $null
        $contexto.Excluidas.Count | Should -Be 0
        $contexto.SinRuta         | Should -Contain 'Informativo'
    }

    It 'una configuracion sin RutasExcluidas se comporta como antes de existir la funcion' {
        $contexto = New-ContextoEmbudo -Configuracion ([pscustomobject]@{ Admin = $true })
        $contexto.Excluidas.Count | Should -Be 0
    }

    It 'las reglas saben responder con un contexto sin configuracion' {
        # No es un caso hipotetico: New-ContextoEmbudo admite el nulo a
        # proposito, y si una regla se atragantara con el, el embudo
        # entero lanzaria en mitad de un analisis.
        $contexto = New-ContextoEmbudo -Configuracion $null
        $control  = Get-CandidatoDeCaso -Caso 'control'

        foreach ($regla in @(Get-ReglasFiltroCandidato)) {
            { Invoke-ReglaSuelta -Regla $regla -Candidatos $control -Contexto $contexto } |
                Should -Not -Throw -Because "la regla '$($regla.Nombre)' tiene que aguantar un contexto vacio"
        }
    }

    It 'el embudo, en cambio, EXIGE configuracion: sin ella no hay analisis que valga' {
        # Deliberado y distinto de lo anterior. Un contexto sin
        # configuracion significa "no hay nada que excluir"; un embudo sin
        # configuracion significa que quien llama se ha dejado algo, y eso
        # tiene que doler en el sitio, no filtrar a medias en silencio.
        $script:Emision = @(Get-CandidatoDeCaso -Caso 'control')
        { Invoke-ModuloLimpieza -Modulo $script:ModuloFalso -Configuracion $null } | Should -Throw
    }

    It 'un modulo que emite nulos no produce candidatos fantasma' {
        $script:Emision = @($null, (Get-CandidatoDeCaso -Caso 'control'), $null)
        $r = Invoke-ModuloLimpieza -Modulo $script:ModuloFalso -Configuracion $script:Cfg
        $r.Candidatos.Count | Should -Be 1
        $r.Candidatos[0].ClaveExclusion | Should -Be 'C:\normal\cosa'
    }
}
