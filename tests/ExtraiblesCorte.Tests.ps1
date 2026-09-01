<#
    [VIS-04], los dos cortes.

    Archivo aparte de Extraibles.Tests.ps1 A PROPOSITO: aquel carga SOLO
    src/Core/Extraibles.ps1, porque sus cuatro funciones son calculo puro y
    cargar el nucleo entero escondria una dependencia el dia que apareciera.
    Esa decision es buena y no se toca. Lo de aqui es lo contrario: son los
    ENGANCHES, y necesitan el nucleo montado.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio = ''; Documentos = ''; Descargas = ''
        Imagenes   = ''; Musica     = ''; Videos     = ''; CarpetaDatos = ''
    })
}

Describe 'VIS-04: los dos cortes que impiden borrar en una extraible' {
    <#
        El punto entero se sostiene sobre que una unidad extraible se
        ANALICE y no se pueda BORRAR en ella. Eso son dos cortes en dos
        sitios, y aqui se comprueban los dos, porque cada uno cubre un
        agujero del otro:

          - El del EMBUDO usa la lista de unidades de la configuracion, que
            se calcula al arrancar. Es barato -mira una tabla en memoria- y
            se aplica a todos los candidatos de todos los modulos.
          - El del MOTOR mira la ruta directamente. Es el que salva el caso
            que al embudo se le escapa: un disco enchufado DESPUES de
            arrancar, que todavia no esta en esa lista.

        Y hay un tercero que NO se toca y tiene que seguir sin tocarse: el
        indice, el mapa y el informe. Ahi la extraible tiene que aparecer.
    #>

    BeforeAll {
        # La configuracion que ve el embudo: C: es un disco fijo, E: una
        # llave USB. Las dos elegidas por el usuario, para que lo que
        # rechace a E: sea su regla y no otra.
        $script:CfgConLlave = [pscustomobject]@{
            Admin                 = $true
            UnidadesSeleccionadas = @('C:', 'E:')
            RutasExcluidas        = @()
            Unidades              = @(
                [pscustomobject]@{ Letra = 'C:'; Clase = 'fija';      Borrable = $true  }
                [pscustomobject]@{ Letra = 'E:'; Clase = 'extraible'; Borrable = $false }
            )
        }
    }

    It 'el contexto del embudo sabe en que letras no se puede borrar' {
        $contexto = New-ContextoEmbudo -Configuracion $script:CfgConLlave
        $contexto.NoBorrables.Contains('E:') | Should -BeTrue
        $contexto.NoBorrables.Contains('C:') | Should -BeFalse
    }

    It 'y no distingue mayusculas, porque las letras de unidad no las distinguen' {
        $contexto = New-ContextoEmbudo -Configuracion $script:CfgConLlave
        $contexto.NoBorrables.Contains('e:') | Should -BeTrue
    }

    It 'una configuracion sin lista de unidades no inventa prohibiciones' {
        # El caso de siempre: ante lo que no se conoce, el comportamiento
        # anterior. Si esto devolviera "todo prohibido", el programa se
        # quedaria sin poder borrar nada en cuanto la configuracion llegara
        # a medias.
        $contexto = New-ContextoEmbudo -Configuracion ([pscustomobject]@{ Admin = $true })
        $contexto.NoBorrables.Count | Should -Be 0
        { New-ContextoEmbudo -Configuracion $null } | Should -Not -Throw
    }

    It 'la regla del embudo tira lo de la extraible y respeta lo del disco fijo' {
        $regla = @(Get-ReglasFiltroCandidato |
                   Where-Object { $_.Nombre -eq 'Unidad donde se puede borrar' })
        $regla.Count | Should -Be 1 -Because 'sin la regla esto no comprueba nada'

        $contexto = New-ContextoEmbudo -Configuracion $script:CfgConLlave
        $enLlave = New-Candidato -ModuloId 'p' -Categoria 'c' -Nombre 'en la llave' `
                                 -Ruta 'E:\fotos\x.tmp' -Bytes 10 -Metodo 'Ruta' -Raices @('E:\fotos')
        $enDisco = New-Candidato -ModuloId 'p' -Categoria 'c' -Nombre 'en el disco' `
                                 -Ruta 'C:\normal\x.tmp' -Bytes 10 -Metodo 'Informativo' -Raices @()

        (& $regla[0].Predicado $contexto $enLlave) | Should -BeFalse
        (& $regla[0].Predicado $contexto $enDisco) | Should -BeTrue
    }

    It 'lo que no tiene letra de unidad sobrevive a la regla' {
        # Un comando de Docker, la papelera, lo informativo. Si esto
        # devolviera $false desaparecerian todos los candidatos de tipo
        # comando, que es como se rompe un modulo entero sin un solo error.
        $regla = @(Get-ReglasFiltroCandidato |
                   Where-Object { $_.Nombre -eq 'Unidad donde se puede borrar' })
        $contexto = New-ContextoEmbudo -Configuracion $script:CfgConLlave
        $comando = New-Candidato -ModuloId 'p' -Categoria 'c' -Nombre 'prune' `
                                 -Ruta 'docker system prune' -Bytes 0 -Metodo 'Comando' `
                                 -Ejecutable 'docker' -Argumentos @('system', 'prune')
        (& $regla[0].Predicado $contexto $comando) | Should -BeTrue
    }

    It 'un candidato de papelera CON letra de unidad sobrevive a la regla' {
        # Este es el caso que hace falta para que la guarda de SinRuta
        # signifique algo. El candidato de comando ya sobrevivia por la
        # otra puerta -no tiene letra-, asi que quitarla no rompia nada y
        # la prueba pasaba igual: lo canto la mutacion.
        #
        # El de la papelera si tiene letra: su Ruta es 'E:\'. Sin la
        # guarda desapareceria, y con el la papelera de un disco externo
        # dejaria de poder vaciarse desde la ventana aunque el usuario lo
        # pidiera. Que ese modulo NO deba tocarla es otra decision, y vive
        # en el modulo, no aqui.
        $regla = @(Get-ReglasFiltroCandidato |
                   Where-Object { $_.Nombre -eq 'Unidad donde se puede borrar' })
        $contexto = New-ContextoEmbudo -Configuracion $script:CfgConLlave
        $papelera = New-Candidato -ModuloId 'papelera' -Categoria 'c' -Nombre 'Papelera de E:' `
                                  -Ruta 'E:\' -Bytes 100 -Metodo 'Papelera' -Raices @()
        (& $regla[0].Predicado $contexto $papelera) | Should -BeTrue -Because (
            'lo que no se borra por ruta no lo juzga esta regla')
    }

    It 'Get-TipoDeUnidad no lanza y responde "no lo se" con lo que no es una unidad' {
        # Fuera de Windows esto devuelve $null SIEMPRE, y esa es justo la
        # rama que importa que no reviente: se llama desde el motor de
        # borrado, en el camino que toca los archivos del usuario.
        { Get-TipoDeUnidad -Ruta 'C:\algo\x.tmp' } | Should -Not -Throw
        { Get-TipoDeUnidad -Ruta $null }           | Should -Not -Throw
        Get-TipoDeUnidad -Ruta ''                        | Should -BeNullOrEmpty
        Get-TipoDeUnidad -Ruta 'docker system prune'     | Should -BeNullOrEmpty
        Get-TipoDeUnidad -Ruta '\\servidor\recurso\x'    | Should -BeNullOrEmpty
    }

    It 'el motor no rechaza nada cuando no sabe de que unidad se trata' {
        # Aqui, en Linux, Get-TipoDeUnidad siempre dice "no lo se". El
        # corte tiene que quedarse callado: si dijera que no, el programa
        # dejaria de borrar en el equipo de cualquiera cuyo disco no
        # supieramos clasificar.
        $candidato = New-Candidato -ModuloId 'p' -Categoria 'c' -Nombre 'x' `
                                   -Ruta 'C:\normal\x.tmp' -Bytes 10 -Metodo 'Ruta' `
                                   -Raices @('C:\normal')
        $motivo = Get-MotivoNoSeBorra -Candidato $candidato -Bytes 10 -Permanente

        # VACIO, y no "que no mencione las extraibles". La diferencia la
        # cazo una mutacion: al quitar la guarda de 'desconocida', el motor
        # pasaba a rechazarlo TODO -aqui ninguna unidad se puede
        # clasificar- pero con un texto distinto, asi que un Should -Not
        # -Match seguia pasando. La prueba decia que si mientras el
        # programa se quedaba sin poder borrar nada.
        $motivo | Should -BeNullOrEmpty -Because (
            'sin saber que clase de unidad es, el motor no puede objetar nada')
    }
}

Describe 'VIS-04: el modulo de la papelera, que la regla del embudo no puede proteger' {
    <#
        La trampa del punto. 25-Papelera emite UN candidato cuya Ruta es la
        primera unidad con contenido, y el vaciado vacia las letras que se
        le pasen. La regla del embudo mira la ruta del candidato -que es de
        C:- asi que no ve la llave USB que va dentro de la lista. El corte
        tiene que estar en el modulo, donde se decide QUE letras se miden.
    #>

    It 'no mide ni vacia la papelera de una unidad no borrable' {
        $modulo = Get-ModuloLimpieza -Id 'papelera' -Raiz $script:Raiz
        $modulo | Should -Not -BeNullOrEmpty -Because 'sin el modulo esto no comprueba nada'

        # Una configuracion con la llave USB PRIMERA en la lista: si el
        # filtro no estuviera, seria la que acabaria en la Ruta del
        # candidato. El orden no es casual.
        $cfg = [pscustomobject]@{
            Admin                 = $true
            UnidadesSeleccionadas = @()
            Unidades              = @(
                [pscustomobject]@{ Letra = 'E:'; Clase = 'extraible'; Borrable = $false }
                [pscustomobject]@{ Letra = 'C:'; Clase = 'fija';      Borrable = $true  }
            )
        }
        $resultado = Invoke-ModuloLimpieza -Modulo $modulo -Configuracion $cfg `
                                           -Sync (New-EstadoSincronizado)

        foreach ($candidato in @($resultado.Candidatos)) {
            $candidato.Ruta | Should -Not -Match '^[Ee]:' -Because (
                'la papelera de una unidad extraible no se toca')
        }
    }

    It 'y una unidad sin el campo Borrable se comporta como antes de VIS-04' {
        # Compatibilidad hacia atras: una configuracion vieja, o construida
        # a mano por una prueba, no puede quedarse sin papelera porque le
        # falte un campo que antes no existia.
        $modulo = Get-ModuloLimpieza -Id 'papelera' -Raiz $script:Raiz
        $cfg = [pscustomobject]@{
            Admin                 = $true
            UnidadesSeleccionadas = @()
            Unidades              = @([pscustomobject]@{ Letra = 'C:' })
        }
        { Invoke-ModuloLimpieza -Modulo $modulo -Configuracion $cfg `
                                -Sync (New-EstadoSincronizado) } | Should -Not -Throw
    }
}

Describe 'VIS-04: lo que no se puede ejecutar aqui, se ata por texto' {
    <#
        Tres de los cuatro cortes de este punto NO se pueden ejercitar
        fuera de Windows, y hay que decirlo en vez de fingir que si:

          - El del motor solo salta con una unidad extraible de verdad.
            Aqui Get-TipoDeUnidad dice siempre "no lo se".
          - El del modulo de la papelera necesita un E:\$Recycle.Bin.
          - El filtro de Get-UnidadesAnalizables necesita una llave USB
            enchufada.

        Lo probado de verdad es la DECISION -Extraibles.ps1, con sus 44
        pruebas- y lo que se ata aqui es que los enganches sigan llamandola.
        No es lo mismo y no se vende como si lo fuera: esto caza que alguien
        borre el corte, no que el corte funcione. Lo segundo es un cebo del
        banco y una comprobacion en tu Windows.

        Sin comentarios, que si no esta misma explicacion contaria como
        codigo.
    #>

    BeforeAll {
        function script:Get-CodigoSinComentarios {
            param([string] $Ruta)
            $t = [regex]::Replace([IO.File]::ReadAllText($Ruta), '(?s)<#.*?#>', '')
            return (@($t -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
        }
        $script:Motor    = script:Get-CodigoSinComentarios (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Remove.ps1')
        $script:Discos   = script:Get-CodigoSinComentarios (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'FileSystem.ps1')
        $script:Papelera = script:Get-CodigoSinComentarios (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Modules') '25-Papelera.ps1')
    }

    It 'los tres archivos se han leido de verdad' {
        # Guarda: sin contenido, las tres pruebas de abajo pasarian solas.
        $script:Motor.Length    | Should -BeGreaterThan 1000
        $script:Discos.Length   | Should -BeGreaterThan 1000
        $script:Papelera.Length | Should -BeGreaterThan 500
    }

    It 'el motor sigue preguntando por la clase de unidad antes de borrar' {
        $script:Motor | Should -Match 'Get-TipoDeUnidad'
        $script:Motor | Should -Match 'Test-PuedeProducirCandidatoBorrable'
        $script:Motor | Should -Match 'Get-MotivoNoBorrableEnUnidad'
    }

    It 'y sigue callandose cuando no sabe de que unidad se trata' {
        # Sin esta comparacion, en un equipo donde la clasificacion fallara
        # el programa dejaria de borrar TODO en silencio. Es la mutacion
        # que mas caro habria salido de las ocho.
        $script:Motor | Should -Match "desconocida"
    }

    It 'el descubrimiento de unidades ya no filtra por Fixed a mano' {
        # La decision vive en Extraibles.ps1. Volver a escribir aqui
        # "-ne Fixed" seria un segundo sitio decidiendo que discos mira el
        # programa, y el que se quedaria atras es siempre este.
        $script:Discos | Should -Match 'Test-UnidadAnalizable'
        $script:Discos | Should -Not -Match '\-ne \[IO\.DriveType\]::Fixed'
    }

    It 'y cada unidad sale con su clase y con si en ella se puede borrar' {
        $script:Discos | Should -Match 'Clase\s+= \$clase'
        $script:Discos | Should -Match 'Borrable\s+= \(Test-PuedeProducirCandidatoBorrable'
    }

    It 'el modulo de la papelera sigue mirando el campo Borrable' {
        # La regla del embudo NO puede proteger a este modulo: emite un
        # candidato cuya ruta es de C: aunque la lista lleve dentro una
        # llave USB. Si este filtro desaparece, o se pierde la papelera de
        # C: o se vacia la del disco externo.
        $script:Papelera | Should -Match '\$_\.Borrable'
    }

    It 'Get-UnidadesAnalizables no puede contradecir a Extraibles.ps1' {
        # Esta SI se ejecuta, y sobre las unidades de verdad de la maquina
        # que ejecute las pruebas, sean las que sean. No comprueba QUE
        # responde -eso depende del equipo- sino que las dos respuestas
        # salen de la misma funcion y no pueden divergir.
        $unidades = @(Get-UnidadesAnalizables)
        foreach ($unidad in $unidades) {
            $unidad.Clase    | Should -Not -BeNullOrEmpty
            $unidad.Borrable | Should -BeOfType [bool]
            $unidad.Borrable | Should -Be (Test-PuedeProducirCandidatoBorrable -Clase $unidad.Clase) `
                -Because ('la unidad ' + $unidad.Letra + ' dice una cosa y la regla dice otra')
            (Test-UnidadAnalizable -Clase $unidad.Clase).Analizable | Should -BeTrue `
                -Because 'lo que sale de aqui es, por definicion, lo que se analiza'
        }
    }
}
