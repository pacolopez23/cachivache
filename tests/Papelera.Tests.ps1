<#
    Pruebas de [COR-01]: la papelera que en realidad borra para siempre.

    Windows borra PERMANENTEMENTE, sin avisar y devolviendo exito, cuando
    lo que mandas a la papelera no cabe en ella. Cachivache lo anotaba
    como PAPELERA, asi que el usuario creia que podia recuperarlo.

    Todo lo que decide si un archivo del usuario sobrevive esta en
    Test-CabeEnPapelera, que es calculo puro y se puede probar aqui, en
    Linux, sin registro de Windows y sin arriesgar nada. Esa es la razon
    de partir el modulo en dos: la version anterior de este fallo se
    quedo sin corregir precisamente porque "no se podia probar".

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'Test-CabeEnPapelera: los tres casos' {

    It 'lo que cabe, cabe' {
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes 10GB
        $r = Test-CabeEnPapelera -Bytes 1GB -Estado $estado
        $r.Cabe   | Should -BeTrue
        $r.Seguro | Should -BeTrue
    }

    It 'lo que supera la cuota NO cabe' {
        # El caso que mas duele: el que no cabe es siempre el archivo mas
        # grande, o sea el que mas rabia da perder.
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes 10GB
        $r = Test-CabeEnPapelera -Bytes 11GB -Estado $estado
        $r.Cabe   | Should -BeFalse
        $r.Seguro | Should -BeTrue
    }

    It 'justo en el limite cabe, y un byte mas no' {
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes 1000
        (Test-CabeEnPapelera -Bytes 1000 -Estado $estado).Cabe | Should -BeTrue
        (Test-CabeEnPapelera -Bytes 1001 -Estado $estado).Cabe | Should -BeFalse
    }

    It 'si no hay papelera en ese volumen, nada cabe' {
        $estado = New-EstadoPapelera -Disponible $false -CapacidadBytes 0 `
                    -Motivo 'la papelera esta desactivada en D:'
        $r = Test-CabeEnPapelera -Bytes 1 -Estado $estado
        $r.Cabe   | Should -BeFalse
        $r.Motivo | Should -BeLike '*desactivada*'
    }

    It 'capacidad desconocida (-1) deja pasar, pero lo marca como no seguro' {
        # Tratar "no se sabe" como "no cabe" bloquearia borrados legitimos
        # en cualquier equipo donde no se pueda leer el registro, y el
        # usuario aprenderia a marcar borrado permanente para poder
        # trabajar: le empujariamos justo a lo irreversible.
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes -1
        $r = Test-CabeEnPapelera -Bytes 500GB -Estado $estado
        $r.Cabe   | Should -BeTrue
        $r.Seguro | Should -BeFalse -Because 'no se ha podido comprobar, y eso no se oculta'
    }

    It 'un estado nulo no revienta' {
        { Test-CabeEnPapelera -Bytes 10 -Estado $null } | Should -Not -Throw
        (Test-CabeEnPapelera -Bytes 10 -Estado $null).Seguro | Should -BeFalse
    }

    It 'el motivo dice los dos tamanos, no solo que no cabe' {
        # "No cabe" sin cifras obliga al usuario a adivinar si el problema
        # es su archivo o su configuracion.
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes 5GB
        $r = Test-CabeEnPapelera -Bytes 20GB -Estado $estado
        $r.Motivo | Should -BeLike '*20*GB*'
        $r.Motivo | Should -BeLike '*5*GB*'
    }
}

Describe 'Test-IraAPapelera: rutas sin letra de unidad' {

    It 'una ruta de red no tiene papelera' {
        $r = Test-IraAPapelera -Ruta '\\servidor\comun\cosa.bin' -Bytes 10
        $r.Cabe   | Should -BeFalse
        $r.Motivo | Should -BeLike '*red*'
    }

    It 'una ruta sin letra ni UNC no bloquea nada' {
        # Las pruebas corren en Linux, donde no hay ni letras ni papelera.
        # Bloquear aqui dejaria la suite sin poder probar el borrado.
        $r = Test-IraAPapelera -Ruta '/tmp/lo/que/sea' -Bytes 10
        $r.Cabe | Should -BeTrue
    }
}

Describe 'Get-EstadoPapelera: se comporta fuera de Windows' {

    BeforeEach { Reset-CachePapelera }

    It 'no lanza aunque no haya registro de Windows' {
        { Get-EstadoPapelera -Unidad 'C:' } | Should -Not -Throw
    }

    It 'sin poder averiguarlo, responde desconocido y no cero' {
        # Cero significaria "no cabe nada" y bloquearia TODOS los borrados.
        # La diferencia entre "no cabe" y "no lo se" es justo la que evita
        # convertir un fallo de lectura en una parada total del programa.
        $e = Get-EstadoPapelera -Unidad 'C:'

        # $IsWindows NO EXISTE en Windows PowerShell 5.1: vale $null, y
        # "-not $null" es verdadero, asi que esta rama -pensada para NO
        # ejecutarse en Windows- se ejecutaba justo alli, exigiendo un -1
        # sobre una papelera de verdad que si sabe decir su cuota.
        # 5.1 solo corre en Windows, de modo que "no lo se" tambien cuenta
        # como Windows.
        $esWindows = $IsWindows -or ($null -eq $IsWindows)
        if (-not $esWindows) {
            $e.CapacidadBytes | Should -Be -1
            $e.Disponible     | Should -BeTrue
        }
    }

    It 'la respuesta se cachea: la cuota no cambia mientras el programa esta abierto' {
        $a = Get-EstadoPapelera -Unidad 'C:'
        $b = Get-EstadoPapelera -Unidad 'C:'
        [object]::ReferenceEquals($a, $b) | Should -BeTrue
    }

    It 'Reset-CachePapelera obliga a volver a preguntar' {
        $a = Get-EstadoPapelera -Unidad 'C:'
        Reset-CachePapelera
        $b = Get-EstadoPapelera -Unidad 'C:'
        [object]::ReferenceEquals($a, $b) | Should -BeFalse
    }
}

Describe 'COR-01: el motor no borra lo que no iria a la papelera' {

    <#
        La comprobacion de que el cableado existe. No se puede ejecutar el
        borrado real contra una papelera llena en Linux, asi que se sigue
        el CAMINO en el codigo: que Invoke-EliminacionCandidato pregunte
        antes de borrar, que lo haga solo cuando el usuario NO ha pedido
        borrado permanente, y que se pare en vez de continuar.
    #>

    BeforeAll {
        $script:Motor = Get-Content -Raw -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core/Remove.ps1')
        $script:Codigo = (Get-Content -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core/Remove.ps1') |
            Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'el motor pregunta si algo iria de verdad a la papelera' {
        $script:Codigo | Should -Match 'Test-IraAPapelera'
    }

    It 'solo pregunta cuando NO se ha pedido borrado permanente' {
        # Con borrado permanente el usuario ya ha dicho que no quiere
        # marcha atras: preguntar ahi seria estorbar.
        #
        # La condicion se mudo de Invoke-EliminacionCandidato a
        # Get-MotivoNoSeBorra al hacer que la simulacion pase por la misma
        # decision. La prueba sigue al CAMINO, no a una linea concreta.
        $script:Codigo | Should -Match 'if \(-not \$Permanente -and \$Candidato\.Metodo'
        $script:Codigo | Should -Match 'Get-MotivoNoSeBorra -Candidato \$Candidato .*-Permanente:\$permanenteEfectivo'
    }

    It 'cuando no cabe, se para: ni borra ni sigue al switch' {
        $i = $script:Codigo.IndexOf('Test-IraAPapelera')
        $f = $script:Codigo.IndexOf('switch ($Candidato.Metodo)')
        $i | Should -BeGreaterThan -1
        $f | Should -BeGreaterThan $i -Because 'la comprobacion va ANTES de repartir por metodo'

        $trozo = $script:Codigo.Substring($i, $f - $i)
        $trozo | Should -Match 'return \$false'
        $trozo | Should -Match 'Candidato\.Error'
    }

    It 'lo deja anotado en el registro, no solo en la fila' {
        $i = $script:Codigo.IndexOf('Test-IraAPapelera')
        $f = $script:Codigo.IndexOf('switch ($Candidato.Metodo)')
        $script:Codigo.Substring($i, $f - $i) | Should -Match "Write-Registro.*BLOQUEADO"
    }

    It 'el mensaje le dice al usuario que puede hacer' {
        # Un error que no ofrece salida convierte al programa en un muro.
        $script:Motor | Should -Match 'marca el borrado permanente'
    }
}

Describe 'CNF-02: la simulacion predice lo mismo que hace el borrado real' {

    <#
        Encontrado ejecutando el programa en Windows, no aqui.

        La simulacion medía y decia "se borraria X" sin pasar por la
        comprobacion de la papelera, que solo vivia dentro de
        Invoke-EliminacionCandidato. Resultado: prometia eliminar un
        archivo de 9,52 GB que en la ejecucion de verdad se habria
        rechazado. Una prevision que no coincide con lo que va a pasar no
        sirve para decidir, y decidir es para lo unico que existe este
        modo.

        Es [ARQ-01] otra vez: dos caminos que deciden lo mismo acaban
        decidiendo cosas distintas en cuanto uno de los dos se toca. La
        respuesta es la misma: una sola funcion.
    #>

    BeforeAll {
        $script:Codigo2 = (Get-Content -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core/Remove.ps1') |
            Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'la decision vive en UNA funcion, no repetida' {
        $script:Codigo2 | Should -Match 'function Get-MotivoNoSeBorra'
        # Test-IraAPapelera solo se invoca desde ella: si apareciera en mas
        # sitios, volverian a poder divergir.
        @([regex]::Matches($script:Codigo2, 'Test-IraAPapelera')).Count |
            Should -Be 1 -Because 'solo Get-MotivoNoSeBorra decide, y los demas la llaman'
    }

    It 'la usan los DOS caminos: el borrado real y la simulacion' {
        @([regex]::Matches($script:Codigo2, 'Get-MotivoNoSeBorra -Candidato')).Count |
            Should -BeGreaterOrEqual 2
    }

    It 'la simulacion consulta ANTES de sumar el espacio' {
        # Si sumara primero, el total seguiria prometiendo un espacio que
        # no se va a liberar aunque la linea dijera "NO se borraria".
        $i = $script:Codigo2.IndexOf('if ($Simular)')
        $consulta = $script:Codigo2.IndexOf('Get-MotivoNoSeBorra', $i)
        $suma     = $script:Codigo2.IndexOf('$liberado += $tamano', $i)

        $consulta | Should -BeGreaterThan -1
        $suma     | Should -BeGreaterThan $consulta
    }

    It 'lo rechazado se cuenta aparte y sale en el resultado' {
        # Sin contarlo, el resumen diria "se habrian eliminado 33" cuando
        # uno de ellos no se habria tocado.
        $script:Codigo2 | Should -Match '\$bloqueados\+\+'
        $script:Codigo2 | Should -Match 'Bloqueados = \$bloqueados'
    }

    It 'el mensaje sale FORMATEADO, sin marcadores {0} a la vista' {
        <#
            Lo vio una ejecucion de verdad, no la suite.

            El mensaje se escribio asi:

                ('texto con {0}...' + 'mas texto' -f $motivo)

            y en PowerShell el operador -f tiene MAS precedencia que +, de
            modo que formatea SOLO la segunda cadena. El {0} de la primera
            llegaba tal cual a la pantalla del usuario.

            Las pruebas de antes no lo cazaban porque buscaban un trozo del
            texto -"marca el borrado permanente"- que estaba presente en
            las dos versiones, la rota y la buena. Comprobar que una cadena
            CONTIENE algo no es comprobar que dice lo que tiene que decir.
        #>
        $estado = New-EstadoPapelera -Disponible $true -CapacidadBytes 5GB
        $candidato = New-Candidato -ModuloId 'x' -Categoria 'c' -Nombre 'grande.bin' `
                        -Ruta 'C:\zona\grande.bin' -Bytes 9GB -Metodo 'Ruta'

        # Se sustituye la consulta al disco por el estado de prueba.
        Mock Test-IraAPapelera { Test-CabeEnPapelera -Bytes $Bytes -Estado $estado }

        $motivo = Get-MotivoNoSeBorra -Candidato $candidato -Bytes 9GB

        $motivo | Should -Not -BeNullOrEmpty
        $motivo | Should -Not -Match '\{\d\}' -Because 'un marcador sin sustituir es texto roto en la cara del usuario'
        $motivo | Should -BeLike '*9*GB*' -Because 'tiene que decir CUANTO ocupa'
        $motivo | Should -BeLike '*5*GB*' -Because 'y cuanto admite la papelera'
    }

    It 'y lo dicen las dos interfaces, no solo el registro' {
        $raiz = Split-Path $PSScriptRoot -Parent
        $ventana = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/UI/Window.Eliminacion.ps1')
        $consola = Get-Content -Raw -LiteralPath (Join-Path $raiz 'src/Cli/Cli.ps1')

        $ventana | Should -Match 'se habrian quedado sin borrar'
        $consola | Should -Match 'NO se habrian borrado'
    }
}

Describe 'CNF-03: que se puede rescatar de la papelera y que no' {

    <#
        El programa manda a la papelera por defecto -es su red de
        seguridad- pero nunca lo decia: la red existia y el usuario no se
        enteraba, asi que iba a buscar sus archivos a mano entre miles.

        Lo importante aqui es NO PROMETER DE MAS. Decir que algo se puede
        recuperar cuando no se puede es peor que callarse: alguien contaria
        con rescatar un archivo que ya no existe.
    #>

    BeforeAll {
        function Get-Cand {
            param([string] $Metodo, [switch] $Forzar, [switch] $Hecho)
            $c = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\x\y' `
                    -Metodo $Metodo -ForzarPermanente:$Forzar
            $c.Hecho = [bool]$Hecho
            return $c
        }
    }

    It 'lo que va a la papelera se puede recuperar' {
        foreach ($m in @('Ruta', 'CarpetaVacia', 'Contenido', 'FirefoxCache', 'Miniaturas')) {
            Test-CandidatoRecuperable -Candidato (Get-Cand -Metodo $m) |
                Should -BeTrue -Because "el metodo $m manda a la papelera"
        }
    }

    It 'vaciar la papelera NO se puede deshacer' {
        # Es el caso mas obvio y el mas facil de olvidar: el propio acto de
        # vaciar la papelera no tiene papelera donde caer.
        Test-CandidatoRecuperable -Candidato (Get-Cand -Metodo 'Papelera') | Should -BeFalse
    }

    It 'un comando externo tampoco' {
        # DISM o "docker system prune" no dejan nada que rescatar.
        Test-CandidatoRecuperable -Candidato (Get-Cand -Metodo 'Comando') | Should -BeFalse
    }

    It 'lo informativo no se ha tocado siquiera' {
        Test-CandidatoRecuperable -Candidato (Get-Cand -Metodo 'Informativo') | Should -BeFalse
    }

    It 'el borrado permanente del usuario manda sobre todo' {
        Test-CandidatoRecuperable -Candidato (Get-Cand -Metodo 'Ruta') -Permanente | Should -BeFalse
    }

    It 'y ForzarPermanente de los modulos de cache tambien' {
        Test-CandidatoRecuperable -Candidato (Get-Cand -Metodo 'Contenido' -Forzar) | Should -BeFalse
    }

    It 'un candidato nulo no revienta y responde que no' {
        { Test-CandidatoRecuperable -Candidato $null } | Should -Not -Throw
        Test-CandidatoRecuperable -Candidato $null | Should -BeFalse
    }
}

Describe 'CNF-03: el resumen solo cuenta lo que de verdad se borro' {

    BeforeAll {
        function Get-Cand2 {
            param([string] $Metodo, [switch] $Hecho)
            $c = New-Candidato -ModuloId 'm' -Categoria 'c' -Nombre 'n' -Ruta 'C:\x\y' -Metodo $Metodo
            $c.Hecho = [bool]$Hecho
            return $c
        }
    }

    It 'separa lo rescatable de lo definitivo' {
        $lote = @(
            (Get-Cand2 -Metodo 'Ruta' -Hecho)
            (Get-Cand2 -Metodo 'Ruta' -Hecho)
            (Get-Cand2 -Metodo 'Comando' -Hecho)
        )
        $r = Get-ResumenRecuperable -Candidatos $lote
        $r.Recuperables | Should -Be 2
        $r.Definitivos  | Should -Be 1
    }

    It 'NO cuenta lo que no se llego a borrar' {
        # Prometer que se puede recuperar algo que ni se toco seria otra
        # forma de decir lo que no es.
        $lote = @(
            (Get-Cand2 -Metodo 'Ruta' -Hecho)
            (Get-Cand2 -Metodo 'Ruta')          # fallo o quedo sin tocar
        )
        (Get-ResumenRecuperable -Candidatos $lote).Recuperables | Should -Be 1
    }

    It 'con borrado permanente no hay nada que rescatar' {
        $lote = @((Get-Cand2 -Metodo 'Ruta' -Hecho), (Get-Cand2 -Metodo 'Ruta' -Hecho))
        $r = Get-ResumenRecuperable -Candidatos $lote -Permanente
        $r.Recuperables | Should -Be 0
        $r.Definitivos  | Should -Be 2
    }

    It 'una lista vacia da ceros, no un error' {
        { Get-ResumenRecuperable -Candidatos @() } | Should -Not -Throw
        (Get-ResumenRecuperable -Candidatos @()).Recuperables | Should -Be 0
    }
}

Describe 'CNF-03: la ventana ofrece la papelera solo cuando hay algo dentro' {

    BeforeAll {
        $script:Raiz2   = Split-Path $PSScriptRoot -Parent
        # Sin comentarios de linea NI de bloque: es la quinta vez que una
        # prueba encuentra lo que busca dentro del comentario que explica
        # por que esta ahi.
        $script:Cierre2 = [regex]::Replace(
            ((Get-Content -LiteralPath (Join-Path $script:Raiz2 'src/UI/Window.Eliminacion.ps1') |
              Where-Object { $_ -notmatch '^\s*#' }) -join "`n"), '(?s)<#.*?#>', '')
        $script:Eventos2 = [regex]::Replace(
            ((Get-Content -LiteralPath (Join-Path $script:Raiz2 'src/UI/Window.Eventos.ps1') |
              Where-Object { $_ -notmatch '^\s*#' }) -join "`n"), '(?s)<#.*?#>', '')
    }

    It 'el boton solo aparece si hay elementos recuperables' {
        # Se comprueba el ORDEN, no una distancia en caracteres. La primera
        # version ponia un tope de 300 y el bloque medía 403: la prueba
        # fallaba por el tamanyo del mensaje, no por el comportamiento.
        # Un numero magico en una expresion regular es una prueba que se
        # rompe cuando alguien mejora un texto.
        $condicion = $script:Cierre2.IndexOf('$rescate.Recuperables -gt 0')
        $boton     = $script:Cierre2.IndexOf("BtnAbrirPapelera.Visibility = 'Visible'")

        $condicion | Should -BeGreaterThan -1
        $boton     | Should -BeGreaterThan $condicion -Because (
            'el boton se enciende DENTRO de la condicion, no antes')
    }

    It 'se esconde al empezar la limpieza siguiente' {
        # Ofrecer "abrir la papelera" cuando la limpieza en curso todavia
        # no ha mandado nada alli seria hablar de otra cosa.
        $script:Eventos2 | Should -Match "BtnAbrirPapelera\.Visibility = 'Collapsed'"
    }

    It 'lo irreversible se dice, no se calla' {
        $script:Cierre2 | Should -Match 'no tiene vuelta atras'
    }

    It 'la simulacion no ofrece rescatar nada' {
        # Sale por return antes: no se ha borrado, no hay nada en la
        # papelera y ofrecerla seria absurdo.
        $corte  = $script:Cierre2.IndexOf('if ($simulado)')
        $rescate = $script:Cierre2.IndexOf('Get-ResumenRecuperable')
        $rescate | Should -BeGreaterThan $corte
    }
}

Describe 'El boton de confirmar no puede llamar definitivo a lo que va a la papelera' {

    # EL FALLO, y se vio mirando el dialogo en pantalla el 2 de septiembre
    # de 2026, no con una prueba.
    #
    # El dialogo enseñaba dos frases que se contradecian:
    #
    #     Destino de lo borrado      Papelera de reciclaje
    #     [ boton ]                  Eliminar definitivamente
    #
    # La primera se calculaba; la segunda estaba escrita a mano en el XAML
    # y no cambiaba nunca. Es la familia de [COR-01] -el programa afirmando
    # algo que no es verdad- y ademas empuja al reves: pinta de
    # irreversible el camino que SI tiene red de seguridad.

    It 'con la papelera, ni el destino ni el boton dicen que sea definitivo' {
        $t = Get-TextosDestinoBorrado
        $t.Destino | Should -Be 'Papelera de reciclaje'
        $t.Boton   | Should -Not -Match 'definitiv'
        $t.Boton   | Should -Match 'papelera'
    }

    It 'con borrado permanente, los dos lo dicen' {
        $t = Get-TextosDestinoBorrado -Permanente
        $t.Destino | Should -Be 'Borrado permanente'
        $t.Boton   | Should -Match 'definitiv'
    }

    It 'INVARIANTE: "definitivo" en el boton solo si el destino es permanente' {
        foreach ($permanente in @($true, $false)) {
            $t = Get-TextosDestinoBorrado -Permanente:$permanente
            $diceDefinitivo = $t.Boton -match 'definitiv|para siempre|irreversible'
            $diceDefinitivo | Should -Be $permanente -Because (
                'el rotulo del boton y el destino son la misma decision')
        }
    }

    It 'la palabra de confirmacion es mas dura cuando no hay vuelta atras' {
        (Get-TextosDestinoBorrado).Palabra             | Should -Be 'SI'
        (Get-TextosDestinoBorrado -Permanente).Palabra | Should -Be 'ELIMINAR'
    }

    It 'el rotulo de reserva del XAML existe y es NEUTRO' {
        # La mitad que importa, y tiene dos caras que se contradicen solo en
        # apariencia:
        #
        #   - El boton NECESITA texto en el XAML. Sin el se queda mudo para
        #     un lector de pantalla, y la invariante de [A11Y-01] lo prohibe.
        #     Se intento dejarlo vacio y esa prueba lo paro en el acto.
        #   - Pero ese texto NO puede prometer que el borrado sea definitivo,
        #     porque no lo sabe: eso depende de una preferencia que se lee
        #     en tiempo de ejecucion.
        #
        # Asi que la regla no es "sin Content", es "Content que sea cierto
        # en los dos casos". El rotulo de verdad lo pone Dialogs.ps1.
        $raiz = Split-Path $PSScriptRoot -Parent
        $xaml = [IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz 'src') 'UI') 'ConfirmDialog.xaml'))
        $sinComentarios = [regex]::Replace($xaml, '(?s)<!--.*?-->', '')

        $m = [regex]::Match($sinComentarios, '(?s)<Button[^>]*x:Name="BtnSi".*?/>')
        $m.Success | Should -BeTrue -Because 'si no se encuentra el boton, esta prueba no mira nada'

        $contenido = [regex]::Match($m.Value, 'Content="(?<t>[^"]*)"')
        $contenido.Success | Should -BeTrue -Because (
            'un boton sin texto se queda mudo para un lector de pantalla: lo exige [A11Y-01]')
        $contenido.Groups['t'].Value | Should -Not -Match 'definitiv|para siempre|irreversible' -Because (
            'el XAML no sabe si el borrado sera permanente; decirlo aqui es mentir la mitad de las veces')
    }

    It 'y Dialogs.ps1 lo toma de esa funcion, no de un if suyo' {
        $raiz = Split-Path $PSScriptRoot -Parent
        $ps = [IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz 'src') 'UI') 'Dialogs.ps1'))
        $codigo = ($ps -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $codigo | Should -Match 'Get-TextosDestinoBorrado'
        $codigo | Should -Match '\$btnSi\.Content\s*=\s*\$textos\.Boton'
        # Y que no se haya quedado un segundo sitio decidiendo lo mismo.
        $codigo | Should -Not -Match "Destino\.Text\s*=\s*if"
    }
}
