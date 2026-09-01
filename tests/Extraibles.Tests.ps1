<#
    Pruebas de [VIS-04]: que se puede hacer con cada tipo de unidad.

    Hasta ahora un disco externo o una llave USB no se analizaban EN
    ABSOLUTO, porque Get-UnidadesFijas filtra por DriveType Fixed. WizTree
    los recorre. La decision de la hoja de ruta es analizar si y borrar no:
    una extraible se puede desconectar en mitad de una operacion, y eso
    convierte un borrado en un error a medias sobre un disco que ya no
    esta; medir y dibujar no tienen ese problema.

    LO QUE DE VERDAD PROTEGE ESTE ARCHIVO es la invariante del ultimo
    Describe: para toda clase de unidad que el codigo sepa devolver, si no
    es fija, Test-PuedeProducirCandidatoBorrable dice que no.

    Y la lista de clases NO esta escrita a mano aqui: se saca del propio
    src/Core/Extraibles.ps1 leyendo su AST. Escrita a mano, anyadir una
    clase nueva al codigo no haria fallar nada y la clase nueva se quedaria
    sin decidir en silencio, que es justo el fallo que esto viene a
    impedir. Con la lista sacada del codigo, una clase nueva entra
    automaticamente en la invariante Y en la comprobacion de que la tabla
    de respuestas esperadas la cubre.

    Se lee el AST y no una expresion regular porque un comentario que
    mencione 'fija' no es un valor que devuelva la funcion, y las pruebas
    que buscan texto encuentran los comentarios del propio arreglo: ha
    pasado siete veces en este repositorio.
#>

BeforeAll {
    $script:Raiz   = Split-Path $PSScriptRoot -Parent
    $script:Fuente = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Extraibles.ps1'

    # Se carga SOLO este archivo y no Bootstrap.ps1: las cuatro funciones
    # son calculo puro y no llaman a nada del nucleo, asi que cargar el
    # nucleo entero solo escondria una dependencia si algun dia apareciera.
    . $script:Fuente

    # Las clases, sacadas del codigo. Se cogen los literales de cadena que
    # estan DENTRO de un "return" de Get-ClaseDeUnidad: las etiquetas del
    # switch ('fixed', 'removable'...) no cuentan, porque son entradas y no
    # clases del programa.
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Fuente, [ref]$null, [ref]$null)

    $script:FuncionClase = $script:Ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Get-ClaseDeUnidad'
    }, $true)

    $script:Clases = @(
        $script:FuncionClase.FindAll({
            param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst]
        }, $true) |
        ForEach-Object {
            $_.FindAll({
                param($m) $m -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true)
        } |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
    )

    # LA TABLA DE RESPUESTAS ESPERADAS. Hay una prueba que exige que sus
    # claves sean EXACTAMENTE las clases que devuelve el codigo, asi que
    # anyadir una clase alli sin decidir aqui que se puede hacer con ella
    # hace fallar la suite.
    $script:Esperado = @{
        'fija'        = @{ Analizable = $true;  Borrable = $true  }
        'extraible'   = @{ Analizable = $true;  Borrable = $false }
        'red'         = @{ Analizable = $false; Borrable = $false }
        'optica'      = @{ Analizable = $false; Borrable = $false }
        'desconocida' = @{ Analizable = $false; Borrable = $false }
    }
}

Describe 'VIS-04: la lista de clases sale del codigo, no de esta prueba' {

    It 'encuentra las cinco clases: si no, esta prueba no comprueba nada' {
        # Guarda. Si el AST dejara de encontrarlas -por un cambio de forma
        # de la funcion, o porque el archivo se moviera- las pruebas de
        # abajo recorrerian una lista vacia y pasarian todas sin mirar nada.
        $script:Clases.Count | Should -Be 5 -Because 'la invariante recorre esta lista'
        $script:Clases | Should -Contain 'fija'
    }

    It 'la tabla de respuestas de esta prueba cubre exactamente esas clases' {
        # Las dos direcciones. Una clase nueva en el codigo sin respuesta
        # decidida aqui hace fallar la primera; una respuesta aqui para una
        # clase que ya no existe hace fallar la segunda, para que la tabla
        # no se convierta en un cajon de restos.
        $sinDecidir = @($script:Clases | Where-Object { -not $script:Esperado.ContainsKey($_) })
        $sinDecidir | Should -BeNullOrEmpty -Because 'una clase nueva tiene que decidir si se borra en ella'

        $sobran = @($script:Esperado.Keys | Where-Object { $_ -notin $script:Clases })
        $sobran | Should -BeNullOrEmpty -Because 'una respuesta para una clase que no existe engorda la tabla y no protege nada'
    }
}

Describe 'VIS-04: Get-ClaseDeUnidad traduce el numero de DriveType' {

    It 'DriveType <Tipo> es "<Clase>"' -ForEach @(
        @{ Tipo = 0; Clase = 'desconocida' }   # Unknown
        @{ Tipo = 1; Clase = 'desconocida' }   # NoRootDirectory: sin medio dentro
        @{ Tipo = 2; Clase = 'extraible' }     # Removable: la llave USB
        @{ Tipo = 3; Clase = 'fija' }          # Fixed / Local Disk
        @{ Tipo = 4; Clase = 'red' }           # Network
        @{ Tipo = 5; Clase = 'optica' }        # CDRom / Compact Disc
        @{ Tipo = 6; Clase = 'desconocida' }   # Ram: desaparece al reiniciar
    ) {
        Get-ClaseDeUnidad -Tipo $Tipo | Should -Be $Clase
    }

    It 'un numero que no es de la tabla ("<Tipo>") es desconocida' -ForEach @(
        @{ Tipo = 7 }
        @{ Tipo = 42 }
        @{ Tipo = -1 }
    ) {
        Get-ClaseDeUnidad -Tipo $Tipo | Should -Be 'desconocida'
    }

    It 'el numero tambien vale escrito como texto, que es como llega de CIM' {
        Get-ClaseDeUnidad -Tipo '3' | Should -Be 'fija'
        Get-ClaseDeUnidad -Tipo '2' | Should -Be 'extraible'
    }
}

Describe 'VIS-04: Get-ClaseDeUnidad traduce el nombre de System.IO.DriveType' {

    It '"<Tipo>" es "<Clase>"' -ForEach @(
        @{ Tipo = 'Fixed';            Clase = 'fija' }
        @{ Tipo = 'Removable';        Clase = 'extraible' }
        @{ Tipo = 'Network';          Clase = 'red' }
        @{ Tipo = 'CDRom';            Clase = 'optica' }
        @{ Tipo = 'CD-ROM';           Clase = 'optica' }   # asi lo dice Get-Volume
        @{ Tipo = 'Ram';              Clase = 'desconocida' }
        @{ Tipo = 'Unknown';          Clase = 'desconocida' }
        @{ Tipo = 'NoRootDirectory';  Clase = 'desconocida' }
    ) {
        Get-ClaseDeUnidad -Tipo $Tipo | Should -Be $Clase
    }

    It 'no le afecta ni la caja ni los espacios de alrededor' {
        Get-ClaseDeUnidad -Tipo 'fixed'       | Should -Be 'fija'
        Get-ClaseDeUnidad -Tipo 'REMOVABLE'   | Should -Be 'extraible'
        Get-ClaseDeUnidad -Tipo '  Network  ' | Should -Be 'red'
    }

    It 'acepta el valor de la enumeracion tal cual, que es lo que da DriveInfo' {
        Get-ClaseDeUnidad -Tipo ([IO.DriveType]::Fixed)     | Should -Be 'fija'
        Get-ClaseDeUnidad -Tipo ([IO.DriveType]::Removable) | Should -Be 'extraible'
        Get-ClaseDeUnidad -Tipo ([IO.DriveType]::Network)   | Should -Be 'red'
        Get-ClaseDeUnidad -Tipo ([IO.DriveType]::CDRom)     | Should -Be 'optica'
    }

    It 'las dos formas de entrada dan la MISMA respuesta' {
        # Es el motivo entero de que la funcion acepte las dos: si dejaran
        # de coincidir, el veredicto sobre si se borra en un disco
        # dependeria de por donde se haya preguntado.
        foreach ($par in @(
            @{ Numero = 2; Nombre = 'Removable' }
            @{ Numero = 3; Nombre = 'Fixed' }
            @{ Numero = 4; Nombre = 'Network' }
            @{ Numero = 5; Nombre = 'CDRom' }
            @{ Numero = 6; Nombre = 'Ram' }
        )) {
            (Get-ClaseDeUnidad -Tipo $par.Numero) |
                Should -Be (Get-ClaseDeUnidad -Tipo $par.Nombre) -Because ('DriveType {0}' -f $par.Nombre)
        }
    }

    It 'un tipo inventado es desconocida, no fija' {
        Get-ClaseDeUnidad -Tipo 'Holograma'      | Should -Be 'desconocida'
        Get-ClaseDeUnidad -Tipo 'FixedRemovable' | Should -Be 'desconocida'
        Get-ClaseDeUnidad -Tipo 'Fija'           | Should -Be 'desconocida'
    }

    It 'con nulo o vacio no revienta y contesta desconocida' {
        Get-ClaseDeUnidad -Tipo $null | Should -Be 'desconocida'
        Get-ClaseDeUnidad -Tipo ''    | Should -Be 'desconocida'
        Get-ClaseDeUnidad -Tipo '   ' | Should -Be 'desconocida'
    }
}

Describe 'VIS-04: Test-UnidadAnalizable' {

    It 'devuelve los tres campos que hacen falta' {
        # Guarda: si el objeto cambiara de forma, las pruebas de abajo
        # compararian $null contra $null y pasarian todas.
        $r = Test-UnidadAnalizable -Clase 'fija'
        foreach ($campo in @('Analizable', 'Clase', 'Motivo')) {
            $r.PSObject.Properties.Name | Should -Contain $campo
        }
    }

    It 'contesta lo que dice la tabla, para cada clase que el codigo devuelve' {
        # foreach DENTRO del It y no -ForEach: una lista construida en el
        # BeforeAll no existe durante el descubrimiento de Pester, y un
        # -ForEach que la leyera generaria CERO casos con la suite en verde.
        foreach ($clase in $script:Clases) {
            (Test-UnidadAnalizable -Clase $clase).Analizable |
                Should -Be $script:Esperado[$clase].Analizable -Because ('la clase ' + $clase)
        }
    }

    It 'las fijas y las extraibles se analizan; la red y las opticas no' {
        # Escrito aparte y a mano a proposito: la prueba de arriba compara
        # el codigo con una tabla, y si alguien cambiara las dos a la vez
        # seguiria pasando. Esto es lo que [VIS-04] decidio, y es el unico
        # sitio donde esta escrito sin depender de nada.
        (Test-UnidadAnalizable -Clase 'fija').Analizable      | Should -BeTrue
        (Test-UnidadAnalizable -Clase 'extraible').Analizable | Should -BeTrue
        (Test-UnidadAnalizable -Clase 'red').Analizable       | Should -BeFalse
        (Test-UnidadAnalizable -Clase 'optica').Analizable    | Should -BeFalse
    }

    It 'todo "no" viene con un motivo legible, y todo "si" sin el' {
        foreach ($clase in $script:Clases) {
            $r = Test-UnidadAnalizable -Clase $clase
            if ($r.Analizable) {
                $r.Motivo | Should -BeNullOrEmpty -Because ('un si no tiene nada que explicar: ' + $clase)
            } else {
                # Longitud minima: un motivo de tres letras es tan inutil
                # como no tenerlo, y pasaria un simple "no vacio".
                $r.Motivo.Length | Should -BeGreaterThan 20 -Because ('hay que decir por que no: ' + $clase)
            }
        }
    }

    It 'los motivos se escriben en castellano de verdad, con sus tildes' {
        foreach ($clase in $script:Clases) {
            $r = Test-UnidadAnalizable -Clase $clase
            if (-not $r.Analizable) {
                $r.Motivo | Should -Match '[áéíóúñÁÉÍÓÚÑ]' -Because ('lo lee el usuario: ' + $clase)
            }
        }
    }

    It 'con nulo, vacio o una clase inventada no revienta y dice que no' {
        foreach ($entrada in @($null, '', '   ', 'Holograma', 'Fixed', '3')) {
            $r = Test-UnidadAnalizable -Clase $entrada
            $r.Analizable | Should -BeFalse -Because 'ante lo desconocido, la respuesta segura'
            $r.Clase      | Should -Be 'desconocida'
            $r.Motivo     | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'VIS-04: solo las unidades fijas pueden producir un candidato borrable' {

    It 'en una unidad fija si' {
        Test-PuedeProducirCandidatoBorrable -Clase 'fija' | Should -BeTrue
    }

    It 'LA INVARIANTE: ninguna clase que no sea fija puede producirlo' {
        # Esto es lo que sostiene [VIS-04] entero, y por eso recorre las
        # clases que devuelve el CODIGO en vez de una lista escrita aqui:
        # una clase nueva queda cubierta el dia que se anyada, sin que
        # nadie tenga que acordarse de venir a este archivo.
        #
        # foreach dentro del It, no -ForEach: ver la nota de mas arriba
        # sobre el descubrimiento de Pester.
        $script:Clases.Count | Should -BeGreaterThan 1 -Because 'sin clases esta invariante no comprueba nada'

        foreach ($clase in $script:Clases) {
            if ($clase -eq 'fija') { continue }
            Test-PuedeProducirCandidatoBorrable -Clase $clase |
                Should -BeFalse -Because ('una unidad ' + $clase + ' nunca puede producir un candidato borrable')
        }
    }

    It 'y coincide con la tabla de respuestas esperadas' {
        foreach ($clase in $script:Clases) {
            Test-PuedeProducirCandidatoBorrable -Clase $clase |
                Should -Be $script:Esperado[$clase].Borrable -Because ('la clase ' + $clase)
        }
    }

    It 'una extraible se analiza PERO no se borra: las dos cosas a la vez' {
        # El punto entero en una linea. Si alguien "arreglara" la extraible
        # haciendola borrable, o la dejara fuera del analisis para
        # simplificar, esta prueba cae.
        (Test-UnidadAnalizable -Clase 'extraible').Analizable        | Should -BeTrue
        Test-PuedeProducirCandidatoBorrable -Clase 'extraible'       | Should -BeFalse
    }

    It 'con nulo, vacio, una clase inventada o un DriveType sin traducir dice que no' {
        # 'Fixed' y '3' son el tipo del SISTEMA, no la clase del programa:
        # tienen que pasar antes por Get-ClaseDeUnidad. Que aqui contesten
        # "no" es lo correcto, porque equivocarse hacia "no se puede
        # borrar" cuesta una funcion y al reves cuesta archivos.
        foreach ($entrada in @($null, '', '   ', 'Holograma', 'Fixed', '3', 'FIJAS')) {
            Test-PuedeProducirCandidatoBorrable -Clase $entrada |
                Should -BeFalse -Because ('entrada: [' + $entrada + ']')
        }
    }

    It 'pero no se pone tiquismiquis con la caja ni con los espacios' {
        Test-PuedeProducirCandidatoBorrable -Clase 'Fija'    | Should -BeTrue
        Test-PuedeProducirCandidatoBorrable -Clase '  fija ' | Should -BeTrue
    }
}

Describe 'VIS-04: Get-MotivoNoBorrableEnUnidad explica lo que la otra funcion decide' {

    It 'en una unidad fija no hay nada que explicar' {
        Get-MotivoNoBorrableEnUnidad -Clase 'fija' | Should -BeNullOrEmpty
    }

    It 'LA INVARIANTE: hay texto exactamente cuando no se puede borrar' {
        # La misma leccion de [CNF-05]: la funcion que decide y la que
        # explica no pueden divergir. El fallo natural de esta pareja es
        # anyadir una clase, dejarla sin borrado y olvidar el texto; el
        # usuario veria entonces una fila que no puede marcar y NADA que le
        # diga por que, que es indistinguible de un programa roto.
        foreach ($clase in $script:Clases) {
            $motivo = Get-MotivoNoBorrableEnUnidad -Clase $clase
            if (Test-PuedeProducirCandidatoBorrable -Clase $clase) {
                $motivo | Should -BeNullOrEmpty -Because ('se puede borrar: ' + $clase)
            } else {
                $motivo.Length | Should -BeGreaterThan 20 -Because ('no se puede borrar: ' + $clase)
            }
        }
    }

    It 'el texto que lee el usuario lleva tildes y enyes' {
        foreach ($clase in $script:Clases) {
            $motivo = Get-MotivoNoBorrableEnUnidad -Clase $clase
            if ($motivo) {
                $motivo | Should -Match '[áéíóúñÁÉÍÓÚÑ]' -Because ('lo lee el usuario: ' + $clase)
            }
        }
    }

    It 'el de la extraible dice las dos cosas: que se ha medido y que no se borra' {
        # Es la funcion, no una limitacion que haya que disimular: medir
        # sin borrar es exactamente lo que hace WizTree.
        $motivo = Get-MotivoNoBorrableEnUnidad -Clase 'extraible'
        $motivo | Should -Match 'medido'
        $motivo | Should -Match 'extraíble'
    }

    It 'nombra la unidad cuando se le dice cual es' {
        # Con dos o tres discos conectados, "esta unidad" obliga al usuario
        # a adivinar de cual se habla.
        # Se busca 'la unidad D:' y no 'D:' a secas: 'D:' encuentra el
        # 'd:' de "esta unidad: es una..." -Should -Match no distingue
        # mayusculas- y la prueba fallaba diciendo que nombraba una unidad
        # que no nombra. Numeros y trozos magicos en las expresiones
        # regulares, otra vez.
        $conLetra = Get-MotivoNoBorrableEnUnidad -Clase 'extraible' -Letra 'D:'
        $conLetra | Should -Match 'la unidad D:'

        $sinLetra = Get-MotivoNoBorrableEnUnidad -Clase 'extraible'
        $sinLetra | Should -Not -Match 'la unidad D:'
        $sinLetra | Should -Match 'esta unidad'
    }

    It 'con nulo, vacio o una clase inventada no revienta y explica algo' {
        foreach ($entrada in @($null, '', '   ', 'Holograma')) {
            $motivo = Get-MotivoNoBorrableEnUnidad -Clase $entrada
            $motivo.Length | Should -BeGreaterThan 20 -Because ('entrada: [' + $entrada + ']')
        }
        # Y la letra nula tampoco: un Mandatory que puede recibir nulo ha
        # faltado tres veces en este repositorio.
        (Get-MotivoNoBorrableEnUnidad -Clase 'extraible' -Letra $null).Length |
            Should -BeGreaterThan 20
    }
}
