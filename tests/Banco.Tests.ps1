<#
    Las decisiones del banco de pruebas. [VAL-02].

    Se prueba Banco-Decisiones.ps1, NO Banco-Pruebas.ps1: el segundo crea y
    borra archivos, asi que dot-sourcearlo desde aqui seria ejecutarlo. Esa
    separacion es justo lo que permite que esto exista.

    Y aqui hay un archivo entero para cuatro funciones pequenyas por un
    motivo: Test-DentroDeRaiz es lo unico que separa "-Quitar borra el
    banco" de "-Quitar borra la carpeta Documentos". Un fallo aqui no da un
    resultado raro: se lleva archivos del usuario.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path $script:Raiz 'tools') 'Banco-Decisiones.ps1')

    # La guardia de verdad, para poder preguntarle si un nombre de cebo es
    # visible para el programa. Es la invariante central de [VAL-03]: sin
    # ella los cebos de [COR-01] y [COR-02] estuvieron invisibles desde que
    # se escribio el banco.
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Texto.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'FileSystem.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Guard.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Candidate.ps1')

    $script:Banco = 'C:\Users\quien\Documents\Banco-Cachivache'

    Initialize-Guardia -Configuracion ([pscustomobject]@{
        Escritorio = 'C:\Users\quien\Desktop'
        Documentos = 'C:\Users\quien\Documents'
        Descargas  = 'C:\Users\quien\Downloads'
        Imagenes   = 'C:\Users\quien\Pictures'
        Musica     = 'C:\Users\quien\Music'
        Videos     = 'C:\Users\quien\Videos'
        CarpetaDatos = 'C:\Users\quien\AppData\Local\Cachivache'
    })
}

Describe 'Test-DentroDeRaiz: lo que impide que el banco borre fuera de si mismo' {

    It 'la propia raiz esta dentro' {
        Test-DentroDeRaiz -Ruta $script:Banco -Raiz $script:Banco | Should -BeTrue
    }

    It 'algo debajo esta dentro' {
        Test-DentroDeRaiz -Ruta "$script:Banco\01-temporales\uno.bak" -Raiz $script:Banco | Should -BeTrue
    }

    It 'la carpeta de encima NO esta dentro' {
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\Documents' -Raiz $script:Banco | Should -BeFalse
    }

    It 'una carpeta hermana con el mismo principio NO esta dentro' {
        # El fallo clasico de comparar por prefijo. Aqui costaria la carpeta
        # entera de al lado.
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\Documents\Banco-Cachivache-2\algo.txt' `
                          -Raiz $script:Banco | Should -BeFalse
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\Documents\Banco-CachivacheViejo' `
                          -Raiz $script:Banco | Should -BeFalse
    }

    It 'otra unidad NO esta dentro' {
        Test-DentroDeRaiz -Ruta 'D:\Banco-Cachivache\algo.bak' -Raiz $script:Banco | Should -BeFalse
    }

    It 'las mayusculas no cambian el veredicto' {
        # En Windows las rutas no distinguen, y comparar con distincion
        # habria dado "esta fuera" a algo que si esta dentro: el guion
        # habria lanzado en mitad del borrado.
        Test-DentroDeRaiz -Ruta 'C:\USERS\QUIEN\DOCUMENTS\BANCO-CACHIVACHE\uno.bak' `
                          -Raiz $script:Banco | Should -BeTrue
    }

    It 'el prefijo de ruta larga no cambia el veredicto' {
        # El banco crea la ruta larga con \\?\. Sin normalizarlo, esas rutas
        # parecerian estar fuera de su propia raiz y -Quitar fallaria justo
        # en el cebo mas importante. Es la leccion de [COR-02].
        Test-DentroDeRaiz -Ruta "\\?\$script:Banco\02-ruta-larga\x.bak" -Raiz $script:Banco |
            Should -BeTrue
        Test-DentroDeRaiz -Ruta "$script:Banco\02-ruta-larga\x.bak" -Raiz "\\?\$script:Banco" |
            Should -BeTrue
    }

    It 'una barra final no cambia el veredicto' {
        Test-DentroDeRaiz -Ruta "$script:Banco\uno.bak" -Raiz "$script:Banco\" | Should -BeTrue
    }

    It 'con nulo o vacio dice que NO, y no lanza' {
        # El caso peligroso: si un nulo diera "si", el borrado seguiria.
        { Test-DentroDeRaiz -Ruta $null -Raiz $script:Banco } | Should -Not -Throw
        Test-DentroDeRaiz -Ruta $null -Raiz $script:Banco | Should -BeFalse
        Test-DentroDeRaiz -Ruta "$script:Banco\uno.bak" -Raiz $null | Should -BeFalse
        Test-DentroDeRaiz -Ruta '' -Raiz '' | Should -BeFalse
        Test-DentroDeRaiz -Ruta 'C:\lo-que-sea' -Raiz '   ' | Should -BeFalse
    }

    It 'una raiz que se queda en nada tras normalizar dice que NO' {
        # "\" recortado por los dos lados no es una raiz: es la unidad
        # entera. Si esto dijera "si", -Quitar borraria el disco.
        Test-DentroDeRaiz -Ruta 'C:\Users\quien\algo' -Raiz '\' | Should -BeFalse
    }
}

Describe 'Get-MotivoNoQuitarBanco: los tres candados del borrado' {

    It 'con la raiz correcta y existiendo, no hay motivo' {
        Get-MotivoNoQuitarBanco -Raiz $script:Banco -Existe | Should -BeNullOrEmpty
    }

    It 'si la ruta no termina en el nombre del banco, se para' {
        # El caso que de verdad da miedo: el calculo se fue a Documentos.
        $motivo = Get-MotivoNoQuitarBanco -Raiz 'C:\Users\quien\Documents' -Existe
        $motivo | Should -Not -BeNullOrEmpty
        $motivo | Should -Match 'No se borra nada'
    }

    It 'si esta demasiado arriba, se para' -ForEach @(
        @{ Ruta = 'C:\' }, @{ Ruta = 'C:\Banco-Cachivache' }, @{ Ruta = '\' }
    ) {
        Get-MotivoNoQuitarBanco -Raiz $Ruta -Existe | Should -Not -BeNullOrEmpty
    }

    It 'si no existe, lo dice en vez de callarse' {
        Get-MotivoNoQuitarBanco -Raiz $script:Banco | Should -Match 'No hay ningun banco'
    }

    It 'con nulo o vacio se para, y no lanza' {
        { Get-MotivoNoQuitarBanco -Raiz $null -Existe } | Should -Not -Throw
        Get-MotivoNoQuitarBanco -Raiz $null -Existe | Should -Not -BeNullOrEmpty
        Get-MotivoNoQuitarBanco -Raiz '' -Existe    | Should -Not -BeNullOrEmpty
    }

    It 'el prefijo de ruta larga no despista al candado' {
        Get-MotivoNoQuitarBanco -Raiz "\\?\$script:Banco" -Existe | Should -BeNullOrEmpty
    }
}

Describe 'Get-MotivoNoMontarBanco: la red antes de crear nada' {

    It 'en una VM y con la carpeta libre, adelante' {
        Get-MotivoNoMontarBanco -PareceVirtual | Should -BeNullOrEmpty
    }

    It 'fuera de una VM se para y explica por que' {
        $motivo = Get-MotivoNoMontarBanco
        $motivo | Should -Match 'maquina virtual'
        $motivo | Should -Match 'AunqueNoSeaVirtual' -Because 'un "no" sin salida solo ensenya a buscar rodeos'
    }

    It 'fuera de una VM pero forzado, adelante' {
        Get-MotivoNoMontarBanco -Forzado | Should -BeNullOrEmpty
    }

    It 'con un banco ya montado se para' {
        Get-MotivoNoMontarBanco -PareceVirtual -RaizOcupada | Should -Match 'Quitalo primero'
    }

    It 'si no es una VM Y ademas hay banco, manda el motivo de la VM' {
        # El orden importa: el primer motivo que se da tiene que ser el que
        # el usuario necesita para decidir, y "esto no es una VM" es mas
        # grave que "ya hay una carpeta".
        Get-MotivoNoMontarBanco -RaizOcupada | Should -Match 'maquina virtual'
    }
}

Describe 'Test-PareceMaquinaVirtual' {

    It 'reconoce <Fabricante> / <Modelo>' -ForEach @(
        @{ Fabricante = 'innotek GmbH';          Modelo = 'VirtualBox' }
        @{ Fabricante = 'VMware, Inc.';          Modelo = 'VMware Virtual Platform' }
        @{ Fabricante = 'Microsoft Corporation'; Modelo = 'Virtual Machine' }
        @{ Fabricante = 'QEMU';                  Modelo = 'Standard PC' }
        @{ Fabricante = 'Parallels Software';    Modelo = 'Parallels Virtual Platform' }
    ) {
        Test-PareceMaquinaVirtual -Fabricante $Fabricante -Modelo $Modelo | Should -BeTrue
    }

    It 'un portatil normal no lo parece' {
        Test-PareceMaquinaVirtual -Fabricante 'LENOVO' -Modelo '20XW00ABSP' | Should -BeFalse
        Test-PareceMaquinaVirtual -Fabricante 'ASUSTeK COMPUTER INC.' -Modelo 'ROG Strix' | Should -BeFalse
    }

    It 'sin datos dice que NO' {
        # Si no se puede preguntar, no se puede afirmar. Y no poder afirmar
        # tiene que cerrar la red, no abrirla.
        Test-PareceMaquinaVirtual -Fabricante '' -Modelo ''     | Should -BeFalse
        Test-PareceMaquinaVirtual -Fabricante $null -Modelo $null | Should -BeFalse
    }

    It 'no lanza con nulos' {
        { Test-PareceMaquinaVirtual -Fabricante $null -Modelo $null } | Should -Not -Throw
    }
}

Describe 'Get-RutaRaizBanco' {

    It 'cuelga el banco de Documentos' {
        Get-RutaRaizBanco -Documentos 'C:\Users\quien\Documents' |
            Should -BeExactly 'C:\Users\quien\Documents\Banco-Cachivache'
    }

    It 'una barra final no cambia nada' {
        Get-RutaRaizBanco -Documentos 'C:\Users\quien\Documents\' |
            Should -BeExactly 'C:\Users\quien\Documents\Banco-Cachivache'
    }

    It 'sin Documentos devuelve vacio en vez de componer una ruta absurda' {
        # Si esto devolviera "\Banco-Cachivache", -Quitar se pondria a
        # borrar en la raiz del disco. Lo para Get-MotivoNoQuitarBanco, pero
        # la primera red es no fabricar la ruta.
        Get-RutaRaizBanco -Documentos ''    | Should -BeNullOrEmpty
        Get-RutaRaizBanco -Documentos $null | Should -BeNullOrEmpty
    }

    It 'no lanza con nulo' {
        { Get-RutaRaizBanco -Documentos $null } | Should -Not -Throw
    }
}

# =====================================================================
#  EL CATALOGO DE CEBOS  ([VAL-03])
# =====================================================================

Describe 'Get-CebosBanco: el catalogo' {

    BeforeAll {
        $script:Cebos = @(Get-CebosBanco -ArchivosDeSobra 300)
    }

    It 'la prueba tiene cebos que mirar: si no, no comprueba nada' {
        $script:Cebos.Count | Should -BeGreaterThan 5
    }

    It 'todos los identificadores son unicos' {
        # Los identificadores salen en los mensajes de la CI y son la clave
        # con la que se cruza el catalogo consigo mismo. Dos iguales harian
        # que un fallo apuntara al cebo equivocado.
        @($script:Cebos | ForEach-Object { $_.Id } | Select-Object -Unique).Count |
            Should -Be $script:Cebos.Count
    }

    It 'toda entrada trae los campos completos' {
        # La plantilla de Get-CebosBanco existe para esto. Sin ella, una
        # entrada nueva a la que se le olvide un campo lo tendria a $null, y
        # en PowerShell leer una propiedad que no existe NO lanza: el cebo
        # se comportaria raro en vez de dar un error.
        $campos = @('Id', 'Carpeta', 'Patron', 'Cuantos', 'KiloBytes', 'Relleno',
                    'EsCarpeta', 'EnlaceA', 'SubCarpetas', 'PatronSubCarpeta',
                    'Premarcado', 'EnAnalisis', 'EnLimpieza', 'MotivoFuera', 'Para')
        foreach ($cebo in $script:Cebos) {
            foreach ($campo in $campos) {
                $cebo.PSObject.Properties[$campo] | Should -Not -BeNullOrEmpty `
                    -Because "al cebo '$($cebo.Id)' le falta el campo $campo"
            }
        }
    }

    It 'todo cebo dice para que existe' {
        foreach ($cebo in $script:Cebos) {
            $cebo.Para | Should -Not -BeNullOrEmpty -Because "el cebo '$($cebo.Id)' no dice a que afirmacion sirve"
        }
    }

    It 'un cebo que NO se espera en el analisis o en la limpieza tiene que decir por que' {
        # Sin esta regla, "EnAnalisis = $false" seria la forma comoda de
        # callar una comprobacion que molesta. Con ella, apagarla obliga a
        # escribir el motivo, que es lo unico que permite revisarlo despues.
        #
        # EnLimpieza entra en la misma regla desde [COR-08]: es un segundo
        # interruptor con el mismo poder de apagar un paso de la CI, y un
        # interruptor sin motivo escrito es un colador.
        $sinMotivo = @($script:Cebos | Where-Object {
            (-not $_.EnAnalisis -or -not $_.EnLimpieza) -and [string]::IsNullOrWhiteSpace($_.MotivoFuera)
        })
        $sinMotivo | Should -BeNullOrEmpty
    }

    It 'COR-08: el cebo de ruta larga SI se espera en el analisis' {
        # Era $false porque los modulos recorrian con Get-ChildItem
        # -Recurse y no llegaban a los 260 caracteres. Al cerrarse [COR-08]
        # ese dato paso a ser mentira, y dejarlo en $false habria sido
        # tener una CI que comprueba que el fallo sigue ahi.
        $larga = $script:Cebos | Where-Object { $_.Id -eq 'ruta-larga' }
        $larga             | Should -Not -BeNullOrEmpty
        $larga.EnAnalisis  | Should -BeTrue
        $larga.SubCarpetas | Should -BeGreaterThan 10 -Because 'sin las carpetas anidadas la ruta no es larga'
    }

    It 'COR-08: y NO se espera que desaparezca en la limpieza real' {
        # Dos motivos independientes: la fase windows ya lo borro antes del
        # inventario previo, y la limpieza real va a la papelera, que no
        # admite rutas de mas de 260 caracteres. Si esto se pusiera a
        # $true, el paso de la CI se pondria rojo por algo que esta bien.
        $larga = $script:Cebos | Where-Object { $_.Id -eq 'ruta-larga' }
        $larga.EnLimpieza  | Should -BeFalse
        $larga.MotivoFuera | Should -Match 'papelera'
    }

    It 'VIS-05: el cebo comprimido existe, es grande y dice que hay que comprimirlo a mano' {
        # Es el unico cebo que el guion NO deja listo: comprimir es
        # "compact /C", que solo existe en Windows y sobre NTFS, y el guion
        # tiene que poder ejecutarse donde no hay ninguna de las dos cosas.
        # Si esa instruccion desapareciera del catalogo, el cebo se
        # montaria sin comprimir, el paso 5.12 del banco compararia dos
        # cifras iguales y daria VIS-05 por comprobado sin haber
        # comprimido nada.
        $comprimido = $script:Cebos | Where-Object { $_.Id -eq 'comprimido' }
        $comprimido | Should -Not -BeNullOrEmpty

        # 100 MB: el criterio de aceptacion de [VIS-05] esta escrito con
        # esa cifra, y un cebo pequenyo no distinguiria una compresion de
        # un redondeo.
        $comprimido.KiloBytes | Should -Be 102400
        $comprimido.Para      | Should -Match 'compact'
        $comprimido.Para      | Should -Match 'BANCO-PRUEBAS'

        # Sin comprimir sigue siendo un .dmp de 100 MB en Documentos, asi
        # que la integracion continua lo trata como a cualquier otro.
        $comprimido.EnAnalisis | Should -BeTrue
        $comprimido.EnLimpieza | Should -BeTrue
    }

    It 'el numero de archivos de relleno es el que se pide' {
        $relleno = $script:Cebos | Where-Object { $_.Id -eq 'relleno' }
        $relleno.Cuantos | Should -Be 300
        (@(Get-CebosBanco -ArchivosDeSobra 0) | Where-Object { $_.Id -eq 'relleno' }).Cuantos | Should -Be 0
    }

    It 'un enlace duro apunta a otro cebo de su misma carpeta' {
        # Si apuntara a un nombre que nadie monta, New-Item -ItemType
        # HardLink fallaria al montar el banco. Y si apuntara a otra
        # carpeta, el cebo de [VIS-03] no mediria lo que dice medir.
        foreach ($cebo in @($script:Cebos | Where-Object { $_.EnlaceA })) {
            $destino = @($script:Cebos | Where-Object {
                $_.Carpeta -eq $cebo.Carpeta -and $_.Patron -eq $cebo.EnlaceA
            })
            $destino.Count | Should -Be 1 -Because "'$($cebo.Id)' enlaza a '$($cebo.EnlaceA)'"
        }
    }

    It 'el enlace duro se monta DESPUES de su destino' {
        # New-BancoPruebas recorre el catalogo en orden. Si el enlace fuera
        # antes que el original, no habria a que enlazar.
        $ids = @($script:Cebos | ForEach-Object { $_.Id })
        foreach ($cebo in @($script:Cebos | Where-Object { $_.EnlaceA })) {
            $destino = @($script:Cebos | Where-Object { $_.Patron -eq $cebo.EnlaceA })[0]
            $ids.IndexOf($destino.Id) | Should -BeLessThan $ids.IndexOf($cebo.Id)
        }
    }
}

Describe 'INVARIANTE: ningun cebo puede ser invisible para el analisis' {
    <#
        Esta es la prueba que este archivo existe para tener.

        El banco monta cebos dentro de Documentos para que los modulos los
        encuentren. Tres de ellos no los encontraba nadie:

            copia-enorme.bak    el cebo de [COR-01]
            copia-antigua.bak   el cebo de [COR-02]
            documento-N.bak     ocho de los dieciseis de 01-temporales

        Los tres empiezan por una palabra de Test-ArchivoPersonal -"copia",
        "documento"-, asi que la guardia los protegia como trabajo del
        usuario y Test-RutaSegura los rechazaba antes de que ningun modulo
        llegara a proponerlos. El banco quedaba impecable a la vista y las
        dos afirmaciones que existe para comprobar eran incomprobables.

        No fallaba nada. No habia excepcion, ni aviso, ni una lista mas
        corta de lo esperado: simplemente el cebo no salia, y la unica forma
        de enterarse era montar la maquina virtual, seguir el guion y llegar
        al paso 5.4 a preguntarse donde esta el archivo.

        Se le pregunta a la guardia DE VERDAD, la de src/Core/Guard.ps1, no
        a una copia de sus reglas: una copia se desincronizaria y volveria a
        pasar lo mismo.

        POR QUE EL BUCLE VA DENTRO DE UN SOLO It Y NO EN UN -ForEach.
        Porque un -ForEach se construye en la fase de DESCUBRIMIENTO de
        Pester, que ocurre antes de ejecutar ningun BeforeAll: con el
        catalogo cargado solo en BeforeAll, la lista sale vacia, Pester
        genera CERO casos y la invariante no falla, DESAPARECE. Paso al
        escribir esto -la suite dio 44 en verde con dos invariantes que no
        ejecutaban ni una linea-, que es la misma familia de fallo por la
        que existe tools/Mutar.ps1. Con el bucle dentro, la guarda de abajo
        cuenta lo mismo que recorre y no hay dos fases que puedan discrepar.
    #>

    BeforeAll {
        $script:CebosVisibles = @(Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { -not $_.EsCarpeta })
    }

    It 'hay cebos que mirar y la guardia esta lista: si no, esto no comprueba nada' {
        $script:CebosVisibles.Count | Should -BeGreaterThan 5
        Test-GuardiaLista | Should -BeTrue
        # Y que la guardia sepa decir que SI es personal, o el "ninguno lo
        # es" de abajo saldria de una guardia que no protege nada. El nombre
        # es el del cebo viejo de [COR-01], que es el que descubrio esto.
        Test-ArchivoPersonal 'C:\Users\quien\Documents\copia-enorme.bak' | Should -BeTrue
    }

    It 'la guardia no confunde ningun cebo con trabajo del usuario' {
        $invisibles = @()
        foreach ($cebo in $script:CebosVisibles) {
            $ruta = Get-RutaCebo -Cebo $cebo -Raiz $script:Banco -Indice 1
            if (Test-ArchivoPersonal $ruta) { $invisibles += ('{0}: {1}' -f $cebo.Id, $cebo.Patron) }
        }
        $invisibles | Should -BeNullOrEmpty -Because (
            'si la guardia lo da por personal, Test-RutaSegura lo rechaza y NINGUN modulo lo propone: ' +
            'ese cebo no se puede comprobar ni en la maquina virtual ni en la integracion continua')
    }
}

Describe 'INVARIANTE: el premarcado del catalogo es el que decide el programa' {
    <#
        "-Consola -Ejecutar" borra EXACTAMENTE lo que el analisis marco por
        su cuenta, y quien lo decide es Test-DebeVenirMarcado. El campo
        Premarcado del catalogo es lo que la integracion continua da por
        supuesto para saber que tiene que haber desaparecido despues de una
        limpieza real.

        Si los dos discreparan no habria ningun error: la CI esperaria que
        desapareciera algo que nunca se marca -y fallaria sin motivo-, o
        daria por bueno que no desapareciera algo que si se marca, que es
        peor. Aqui se comparan.

        El riesgo lo asigna 50-Temporales por la extension: .bak y .old son
        de riesgo Medio -una copia reciente puede ser la unica que hay- y el
        resto, Bajo. Los cebos se crean con 400 dias, asi que nunca llevan
        el aviso de "creado hace menos de una semana".
    #>

    BeforeAll {
        $script:CebosArchivo = @(Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { -not $_.EsCarpeta })
    }

    It 'hay cebos de las dos clases: si no, esto no comprueba nada' {
        # Con todos los cebos del mismo lado, la comparacion de abajo
        # pasaria sin haber distinguido nunca un premarcado de uno que no lo
        # esta, que es lo unico que se quiere comprobar.
        $script:CebosArchivo.Count | Should -BeGreaterThan 5
        @($script:CebosArchivo | Where-Object { $_.Premarcado }).Count      | Should -BeGreaterThan 0
        @($script:CebosArchivo | Where-Object { -not $_.Premarcado }).Count | Should -BeGreaterThan 0
    }

    It 'el catalogo y Test-DebeVenirMarcado dicen lo mismo de cada cebo' {
        $discrepan = @()
        foreach ($cebo in $script:CebosArchivo) {
            $extension = [IO.Path]::GetExtension($cebo.Patron).ToLowerInvariant()
            $riesgo = if ($extension -eq '.bak' -or $extension -eq '.old') { 'Medio' } else { 'Bajo' }
            $marca  = Test-DebeVenirMarcado -Riesgo $riesgo -Aviso '' -Metodo 'Ruta'

            if ($marca -ne [bool]$cebo.Premarcado) {
                $discrepan += ('{0} ({1}, riesgo {2}): el catalogo dice Premarcado={3} y el programa dice {4}' -f
                               $cebo.Id, $cebo.Patron, $riesgo, $cebo.Premarcado, $marca)
            }
        }
        $discrepan | Should -BeNullOrEmpty -Because (
            'la integracion continua da por hecho el campo Premarcado para saber que tiene que ' +
            'haber desaparecido despues de una limpieza real')
    }
}

Describe 'INVARIANTE: el guion monta lo que dice el catalogo' {
    <#
        Get-CebosBanco es la unica lista de cebos que hay, y New-BancoPruebas
        la recorre. Si alguien volviera a escribir un nombre a mano ahi
        dentro, el comprobador de la CI buscaria una ruta que nadie monta y
        el paso se pondria rojo sin que el programa tenga nada que ver.

        Se mira el TEXTO del guion, quitando antes los comentarios: las
        pruebas que buscan texto encuentran los propios comentarios, y en
        este archivo hay un comentario entero dedicado a explicar los tres
        nombres viejos.
    #>

    BeforeAll {
        $script:TextoMontaje = (Get-Content -Raw -LiteralPath (
            Join-Path (Join-Path $script:Raiz 'tools') 'Banco-Pruebas.ps1'))
        # Fuera los comentarios de linea y los bloques de ayuda.
        $script:CodigoMontaje = [regex]::Replace($script:TextoMontaje, '(?s)<#.*?#>', '')
        $script:CodigoMontaje = [regex]::Replace($script:CodigoMontaje, '(?m)^\s*#.*$', '')
    }

    It 'la prueba lee el guion de verdad: si no, no comprueba nada' {
        $script:CodigoMontaje | Should -Match 'function New-BancoPruebas'
        $script:CodigoMontaje | Should -Match 'Get-CebosBanco'
        $script:CodigoMontaje.Length | Should -BeGreaterThan 1000
    }

    It 'no hay ni un nombre de cebo escrito a mano en el guion' {
        $sueltos = @()
        foreach ($cebo in (Get-CebosBanco -ArchivosDeSobra 3)) {
            foreach ($trozo in @($cebo.Carpeta, $cebo.Patron)) {
                if ([string]::IsNullOrWhiteSpace($trozo)) { continue }
                if ($script:CodigoMontaje.Contains($trozo)) { $sueltos += ('{0}: {1}' -f $cebo.Id, $trozo) }
            }
        }
        $sueltos | Should -BeNullOrEmpty -Because 'los nombres tienen que salir del catalogo, no del guion'
    }

    It 'el guion no vuelve a recorrer con Get-ChildItem -Recurse' {
        # -Quitar lo hacia, y por eso no podia desmontar el banco entero: en
        # Windows PowerShell 5.1 Get-ChildItem -Recurse se para a los 260
        # caracteres y bajo -ErrorAction SilentlyContinue no dice nada, asi
        # que las doce carpetas del cebo de [COR-02] no aparecian, no se
        # borraban, y despues fallaba al borrar una carpeta que creia vacia.
        $script:CodigoMontaje | Should -Not -Match 'Get-ChildItem[^\r\n]*-Recurse'
    }
}

Describe 'Test-PerfilAjeno: lo que no puede salir en un analisis' {

    BeforeAll {
        $script:Usuarios = 'C:\Users'
        $script:Propio   = 'C:\Users\quien'
    }

    It 'el perfil de otro usuario es ajeno' {
        Test-PerfilAjeno -Ruta 'C:\Users\otro\Documents\algo.bak' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeTrue
        Test-PerfilAjeno -Ruta 'C:\Users\Public\Downloads\x.tmp' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeTrue
    }

    It 'el perfil propio NO es ajeno' {
        Test-PerfilAjeno -Ruta 'C:\Users\quien\Documents\Banco-Cachivache\a.tmp' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeFalse
    }

    It 'un perfil que solo comparte el principio del nombre SI es ajeno' {
        # El fallo clasico de comparar por prefijo, pero al reves: aqui
        # equivocarse hacia "no es ajeno" callaria un fallo de verdad.
        Test-PerfilAjeno -Ruta 'C:\Users\quien2\Documents\algo.bak' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeTrue
    }

    It 'la propia carpeta de perfiles no es "de otro usuario"' {
        Test-PerfilAjeno -Ruta 'C:\Users' -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio |
            Should -BeFalse
    }

    It 'lo que esta fuera de los perfiles no es ajeno' {
        Test-PerfilAjeno -Ruta 'C:\Windows\Temp\x.tmp' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeFalse
        Test-PerfilAjeno -Ruta 'D:\datos\x.tmp' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeFalse
    }

    It 'las mayusculas no cambian el veredicto' {
        Test-PerfilAjeno -Ruta 'C:\USERS\QUIEN\Documents\a.bak' `
                         -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeFalse
    }

    It 'con nulos o vacios dice que NO, y no lanza' {
        # Decir que si sin poder comprobarlo pondria el trabajo en rojo por
        # no saber, que es la peor forma de fallar de una CI.
        { Test-PerfilAjeno -Ruta $null -CarpetaUsuarios $null -PerfilPropio $null } | Should -Not -Throw
        Test-PerfilAjeno -Ruta $null -CarpetaUsuarios $script:Usuarios -PerfilPropio $script:Propio | Should -BeFalse
        Test-PerfilAjeno -Ruta 'C:\Users\otro\x' -CarpetaUsuarios '' -PerfilPropio $script:Propio | Should -BeFalse
    }

    It 'sin saber cual es el perfil propio, cualquiera de C:\Users es ajeno' {
        # Al reves que arriba: aqui SI se sabe donde estan los perfiles, y
        # lo que no se sabe es cual es el nuestro. Dar por propio lo que no
        # se puede identificar dejaria pasar justo lo que se vigila.
        Test-PerfilAjeno -Ruta 'C:\Users\quien\x.bak' -CarpetaUsuarios $script:Usuarios -PerfilPropio '' |
            Should -BeTrue
    }
}

Describe 'Get-RutaCebo' {

    It 'compone la ruta de una familia de uno solo' {
        $cebo = Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { $_.Id -eq 'mas-grande' }
        Get-RutaCebo -Cebo $cebo -Raiz $script:Banco |
            Should -BeExactly "$script:Banco\03-mas-grande-que-la-papelera\volcado-enorme.dmp"
    }

    It 'numera las familias de varios' {
        $cebo = Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { $_.Id -eq 'relleno' }
        Get-RutaCebo -Cebo $cebo -Raiz $script:Banco -Indice 7 |
            Should -BeExactly "$script:Banco\07-muchas-filas\sobra-00007.tmp"
    }

    It 'el cebo de ruta larga pasa de 260 caracteres' {
        # Es lo unico que hace que ese cebo sirva para algo. Si la anidacion
        # se quedara corta, toda la comprobacion de [COR-02] pasaria sin
        # comprobar nada.
        $cebo = Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { $_.Id -eq 'ruta-larga' }
        (Get-RutaCebo -Cebo $cebo -Raiz $script:Banco).Length | Should -BeGreaterThan 260
    }

    It 'siempre con barra invertida, tambien cuando la prueba corre en Linux' {
        # Estas rutas se comparan como TEXTO contra las que devuelve
        # Windows. Con Join-Path, en Linux saldrian con barra normal y el
        # comprobador de la CI no encontraria ni un cebo.
        $cebo = Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { $_.Id -eq 'duplicados' }
        (Get-RutaCebo -Cebo $cebo -Raiz $script:Banco -Indice 1) | Should -Not -Match '/'
    }

    It 'una barra final en la raiz no duplica el separador' {
        $cebo = Get-CebosBanco -ArchivosDeSobra 3 | Where-Object { $_.Id -eq 'mas-grande' }
        Get-RutaCebo -Cebo $cebo -Raiz "$script:Banco\" |
            Should -BeExactly "$script:Banco\03-mas-grande-que-la-papelera\volcado-enorme.dmp"
    }

    It 'con nulos devuelve vacio y no lanza' {
        { Get-RutaCebo -Cebo $null -Raiz $script:Banco } | Should -Not -Throw
        Get-RutaCebo -Cebo $null -Raiz $script:Banco | Should -BeNullOrEmpty
        $cebo = Get-CebosBanco -ArchivosDeSobra 3 | Select-Object -First 1
        Get-RutaCebo -Cebo $cebo -Raiz $null | Should -BeNullOrEmpty
    }
}

Describe 'Get-RutasFueraDelBanco: lo que decide si una limpieza real toco lo que no debia' {

    It 'lo que esta dentro no sale' {
        Get-RutasFueraDelBanco -Raiz $script:Banco -Rutas @(
            "$script:Banco\07-muchas-filas\sobra-00001.tmp"
            "$script:Banco\01-temporales\salida-1.bak"
        ) | Should -BeNullOrEmpty
    }

    It 'lo que esta fuera sale, aunque se parezca' {
        $fuera = Get-RutasFueraDelBanco -Raiz $script:Banco -Rutas @(
            "$script:Banco\07-muchas-filas\sobra-00001.tmp"
            'C:\Users\quien\Documents\tesis.tmp'
            'C:\Users\quien\Documents\Banco-Cachivache-2\x.tmp'
        )
        $fuera.Count | Should -Be 2
        $fuera | Should -Contain 'C:\Users\quien\Documents\tesis.tmp'
    }

    It 'una ruta repetida se cuenta una vez' {
        # El mismo archivo puede llegar dos veces (del informe y del disco),
        # y un mensaje de fallo que lo diga dos veces se lee peor justo
        # cuando mas hay que leerlo.
        (Get-RutasFueraDelBanco -Raiz $script:Banco -Rutas @('C:\otra\x.tmp', 'C:\otra\x.tmp')).Count |
            Should -Be 1
    }

    It 'con la raiz vacia TODO esta fuera' {
        # El caso peligroso al reves: si una raiz que no se ha podido
        # calcular diera "todo dentro", la comprobacion pasaria en verde
        # habiendo mirado un disco entero.
        (Get-RutasFueraDelBanco -Raiz '' -Rutas @('C:\lo\que\sea.tmp')).Count | Should -Be 1
    }

    It 'con nulos y listas vacias no lanza' {
        { Get-RutasFueraDelBanco -Raiz $script:Banco -Rutas @() }   | Should -Not -Throw
        { Get-RutasFueraDelBanco -Raiz $script:Banco -Rutas $null } | Should -Not -Throw
        Get-RutasFueraDelBanco -Raiz $script:Banco -Rutas @() | Should -BeNullOrEmpty
    }
}

Describe 'Get-ResumenCebos: cuantos ha encontrado el analisis' {

    BeforeAll {
        $script:TresCebos = @(Get-CebosBanco -ArchivosDeSobra 3)
        $script:Relleno   = $script:TresCebos | Where-Object { $_.Id -eq 'relleno' }
    }

    It 'con todo propuesto no falta nada' {
        $todas = @()
        foreach ($cebo in $script:TresCebos) {
            for ($n = 1; $n -le $cebo.Cuantos; $n++) {
                $todas += (Get-RutaCebo -Cebo $cebo -Raiz $script:Banco -Indice $n)
            }
        }
        $resumen = Get-ResumenCebos -Cebos $script:TresCebos -Raiz $script:Banco -Propuestas $todas
        @($resumen | Where-Object { $_.Falta -gt 0 }) | Should -BeNullOrEmpty
    }

    It 'cuenta lo que falta y ensenya un ejemplo' {
        $resumen = Get-ResumenCebos -Cebos @($script:Relleno) -Raiz $script:Banco -Propuestas @(
            (Get-RutaCebo -Cebo $script:Relleno -Raiz $script:Banco -Indice 2)
        )
        $resumen[0].Encontrados | Should -Be 1
        $resumen[0].Falta       | Should -Be 2
        $resumen[0].Ejemplos    | Should -Contain "$script:Banco\07-muchas-filas\sobra-00001.tmp"
    }

    It 'no ensenya mas de cinco ejemplos' {
        # Un fallo en 07-muchas-filas imprimiria tres mil rutas y taparia
        # todo lo demas del registro del trabajo, que es lo que hay que leer.
        $muchos = @(Get-CebosBanco -ArchivosDeSobra 3000) | Where-Object { $_.Id -eq 'relleno' }
        $resumen = Get-ResumenCebos -Cebos @($muchos) -Raiz $script:Banco -Propuestas @()
        $resumen[0].Falta            | Should -Be 3000
        @($resumen[0].Ejemplos).Count | Should -Be 5
    }

    It 'las mayusculas de la ruta propuesta no cambian el veredicto' {
        # Windows devuelve las rutas con las mayusculas que tenga el disco,
        # no con las que puso el banco.
        $resumen = Get-ResumenCebos -Cebos @($script:Relleno) -Raiz $script:Banco -Propuestas @(
            (Get-RutaCebo -Cebo $script:Relleno -Raiz $script:Banco -Indice 1).ToUpperInvariant()
            (Get-RutaCebo -Cebo $script:Relleno -Raiz $script:Banco -Indice 2)
            (Get-RutaCebo -Cebo $script:Relleno -Raiz $script:Banco -Indice 3)
        )
        $resumen[0].Falta | Should -Be 0
    }

    It 'conserva EnAnalisis y su motivo, que es con lo que se decide' {
        # Se mira el cebo de carpetas vacias y no el de ruta larga: el de
        # ruta larga paso a EnAnalisis = $true al cerrarse [COR-08], y una
        # prueba que sigue mirando el unico caso que ya no lo es deja de
        # comprobar la rama que le importa.
        $filas = Get-ResumenCebos -Cebos $script:TresCebos -Raiz $script:Banco -Propuestas @()

        $fuera = $filas | Where-Object { $_.Id -eq 'carpetas-vacias' }
        $fuera.EnAnalisis  | Should -BeFalse
        $fuera.MotivoFuera | Should -Not -BeNullOrEmpty

        $larga = $filas | Where-Object { $_.Id -eq 'ruta-larga' }
        $larga.EnAnalisis  | Should -BeTrue -Because 'desde [COR-08] el recorrido si llega hasta el'
    }

    It 'con nulos y vacios no lanza' {
        { Get-ResumenCebos -Cebos $null -Raiz $script:Banco -Propuestas $null } | Should -Not -Throw
        { Get-ResumenCebos -Cebos $script:TresCebos -Raiz '' -Propuestas @() }  | Should -Not -Throw
    }
}
