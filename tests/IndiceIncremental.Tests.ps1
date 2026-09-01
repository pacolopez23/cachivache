<#
    Pruebas de la parte que decide SI UN INDICE GUARDADO SE PUEDE CREER, y
    de la que le aplica los cambios.

    Por que este archivo tiene el peso que tiene, y esta escrito en el
    apartado "Que pasa cuando el indice guardado esta obsoleto o corrupto"
    de docs/VEL-02-MEDICION.md:

        UN INDICE QUE MIENTE ES PEOR QUE NO TENER INDICE.

    Si el archivo guardado dice que hay 40 GB en una carpeta que ya no
    existe, el programa ensenya espacio que no esta, el usuario va a
    buscarlo, no lo encuentra, y a partir de ahi no se fia de nada de lo
    que ve. Todo lo de aqui existe para que eso no pase.

    DOS REGLAS DE LA CASA QUE SE NOTAN EN COMO ESTA ESCRITO:

      1. NO BASTA CON COMPROBAR QUE SE RECHAZA. Cada motivo de rechazo se
         comprueba por su CODIGO, porque una prueba que solo mira "se
         rechaza" pasa por el motivo equivocado, y eso ya ha pasado en
         este proyecto. Ademas, todas las tablas de casos parten de una
         cabecera que SI se acepta -y hay una prueba que lo comprueba-,
         asi que el rechazo solo puede venir del campo que se ha tocado.

      2. LO QUE UN It LEE SE CONSTRUYE EN UN BeforeAll. Lo que se arma en
         el cuerpo de un Describe se evalua en el DESCUBRIMIENTO de Pester
         y llega vacio a los It. Por eso las tablas de -ForEach son datos
         literales -no dependen de ninguna variable- y todo lo demas vive
         en BeforeAll.

    Las rutas se componen con Join-Path y nunca con barras a mano: la
    suite se ejecuta en Linux y en Windows, y Split-Path -que es de quien
    depende la propagacion- solo entiende el separador de su sistema.

    Archivo ASCII puro, como el resto de la suite.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
    # Bootstrap.ps1 todavia NO carga este archivo: el enganche es de quien
    # integre el punto. Se carga aparte, igual que hace Extraibles.Tests.
    $script:RutaFuente = Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'IndiceIncremental.ps1'
    . $script:RutaFuente

    # --- Los datos del disco de HOY, fijos para toda la suite ---------
    $script:VersionHoy = 3
    $script:SerieHoy   = 'A1B2-C3D4'
    $script:DiarioHoy  = '0x01d9f4a2b3c4d5e6'
    $script:PrimerUsn  = 1000
    $script:Ahora      = [datetime]'2026-09-01T12:00:00'

    function New-CabeceraDePrueba {
        <#
            Una cabecera que SI se acepta. Cada prueba de rechazo parte de
            aqui y toca UN campo, que es lo que permite decir que el
            rechazo viene de ese campo y no de otra cosa.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone un objeto en memoria.')]
        [CmdletBinding()]
        param()

        return [pscustomobject]@{
            Version      = $script:VersionHoy
            SerieVolumen = $script:SerieHoy
            IdDiario     = $script:DiarioHoy
            UsnCorte     = 250000
            Entradas     = 4
            Suma         = 'a1b2c3d4e5f6'
            Escrito      = $script:Ahora.AddDays(-1)
        }
    }

    function Test-CabeceraDePrueba {
        <#
            Llama a Test-IndiceUtilizable con los datos del disco de hoy,
            para que ninguna prueba tenga que repetirlos. Repetirlos seria
            invitar a que una prueba pase porque cambio el dato del disco
            y no porque cambiara lo que se quiere comprobar.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [AllowNull()] $Cabecera,
            [AllowNull()] $EntradasLeidas = $null,
            [AllowNull()] $SumaCalculada  = $null
        )

        return Test-IndiceUtilizable -Cabecera $Cabecera `
                    -VersionEsperada $script:VersionHoy `
                    -SerieVolumen $script:SerieHoy `
                    -IdDiario $script:DiarioHoy `
                    -PrimerUsn $script:PrimerUsn `
                    -Ahora $script:Ahora `
                    -EntradasLeidas $EntradasLeidas `
                    -SumaCalculada $SumaCalculada
    }

    # --- El arbol de prueba -------------------------------------------
    #
    #   raiz/                 (nivel 0)
    #     rama/               (nivel 1)
    #       hoja/             (nivel 2)   sola.bin  1.000
    #     otra/               (nivel 1)   grande.bin 4.000 + chico.bin 500
    #
    # Dos ramas y no una a proposito: la prueba que sostiene el punto
    # -una baja que deja una carpeta a cero- necesita que la OTRA rama
    # siga valiendo lo mismo. Con una sola rama, poner todo a cero pasaria
    # igual que restar bien.
    $script:RaizArbol = Join-Path ([IO.Path]::GetTempPath()) 'cachivache-indice-incremental'
    $script:Rama      = Join-Path $script:RaizArbol 'rama'
    $script:Hoja      = Join-Path $script:Rama      'hoja'
    $script:Otra      = Join-Path $script:RaizArbol 'otra'
    $script:Sola      = Join-Path $script:Hoja 'sola.bin'
    $script:Grande    = Join-Path $script:Otra 'grande.bin'
    $script:Chico     = Join-Path $script:Otra 'chico.bin'

    function New-IndiceDePrueba {
        <#
            El arbol de arriba, ya sumado A MANO. Los totales se escriben
            literales y no calculados por el codigo que se esta probando:
            si los calculara la propia propagacion, la prueba no podria
            distinguir "propaga bien" de "propaga igual de mal las dos
            veces".
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Solo compone dos diccionarios en memoria.')]
        [CmdletBinding()]
        param()

        $carpetas = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        $archivos = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

        foreach ($par in @(
            @{ Ruta = $script:RaizArbol; Nivel = 0 }
            @{ Ruta = $script:Rama;      Nivel = 1 }
            @{ Ruta = $script:Hoja;      Nivel = 2 }
            @{ Ruta = $script:Otra;      Nivel = 1 }
        )) {
            $carpetas[$par.Ruta] = New-EntradaCarpeta -Ruta $par.Ruta -Nivel $par.Nivel
        }

        $archivos[$script:Sola]   = 1000.0
        $archivos[$script:Grande] = 4000.0
        $archivos[$script:Chico]  = 500.0

        $carpetas[$script:Hoja].Propios  = 1000.0
        $carpetas[$script:Hoja].Bytes    = 1000.0
        $carpetas[$script:Hoja].Archivos = 1

        $carpetas[$script:Rama].Bytes    = 1000.0
        $carpetas[$script:Rama].Archivos = 1

        $carpetas[$script:Otra].Propios  = 4500.0
        $carpetas[$script:Otra].Bytes    = 4500.0
        $carpetas[$script:Otra].Archivos = 2

        $carpetas[$script:RaizArbol].Bytes    = 5500.0
        $carpetas[$script:RaizArbol].Archivos = 3

        return [pscustomobject]@{
            Carpetas      = $carpetas
            Archivos      = $archivos
            Bytes         = 5500.0
            TotalArchivos = 3
        }
    }

    function Get-OraculoDeTotales {
        <#
            EL ORACULO. Para cada carpeta del indice, cuanto suman los
            archivos que cuelgan de ella, contado desde cero recorriendo
            la tabla de archivos.

            Es a proposito el algoritmo mas tonto posible -comparar
            prefijos de ruta, sin niveles ni cadenas de padres- porque
            tiene que ser INDEPENDIENTE de la propagacion incremental que
            se esta probando. Dos implementaciones del mismo algoritmo
            comparten los mismos fallos y no prueban nada.
        #>
        [CmdletBinding()]
        param([Parameter(Mandatory)] $Indice)

        $separador = [IO.Path]::DirectorySeparatorChar
        $oraculo = @{}

        foreach ($carpeta in @($Indice.Carpetas.Keys)) {
            $oraculo[$carpeta] = [pscustomobject]@{ Bytes = 0.0; Propios = 0.0; Archivos = 0 }
        }

        foreach ($ruta in @($Indice.Archivos.Keys)) {
            $bytes = [double]$Indice.Archivos[$ruta]
            $padre = [string](Split-Path $ruta -Parent)

            foreach ($carpeta in @($Indice.Carpetas.Keys)) {
                $prefijo = $carpeta.TrimEnd([char]'\', [char]'/') + $separador
                if ($ruta.StartsWith($prefijo, [StringComparison]::OrdinalIgnoreCase)) {
                    $oraculo[$carpeta].Bytes += $bytes
                    $oraculo[$carpeta].Archivos++
                }
                if ($padre.Equals($carpeta, [StringComparison]::OrdinalIgnoreCase)) {
                    $oraculo[$carpeta].Propios += $bytes
                }
            }
        }

        return $oraculo
    }

    function Get-DiferenciasConElOraculo {
        <#
            Las carpetas cuyos totales no coinciden con el oraculo, con
            nombre y apellidos para que el fallo diga QUE carpeta miente y
            no solo que algo no cuadra.
        #>
        [CmdletBinding()]
        param([Parameter(Mandatory)] $Indice)

        $oraculo = Get-OraculoDeTotales -Indice $Indice
        $diferencias = [Collections.Generic.List[string]]::new()

        foreach ($carpeta in @($Indice.Carpetas.Keys)) {
            $tiene = $Indice.Carpetas[$carpeta]
            $debe  = $oraculo[$carpeta]
            if ([double]$tiene.Bytes -ne $debe.Bytes) {
                $diferencias.Add(('{0}: Bytes {1} y deberia ser {2}' -f $carpeta, $tiene.Bytes, $debe.Bytes))
            }
            if ([double]$tiene.Propios -ne $debe.Propios) {
                $diferencias.Add(('{0}: Propios {1} y deberia ser {2}' -f $carpeta, $tiene.Propios, $debe.Propios))
            }
            if ([int]$tiene.Archivos -ne $debe.Archivos) {
                $diferencias.Add(('{0}: Archivos {1} y deberia ser {2}' -f $carpeta, $tiene.Archivos, $debe.Archivos))
            }
        }

        return @($diferencias)
    }

    function Get-FuenteSinComentarios {
        <#
            El codigo de IndiceIncremental.ps1 sin comentarios.

            PRIMERO los bloques de comentario y DESPUES las lineas que
            empiezan por almohadilla. Al reves -que es como estaba en
            varios archivos de esta suite- el primer paso se lleva la
            linea del cierre, el bloque se queda abierto y el segundo se
            come codigo de verdad.

            (Y ese cierre no se escribe aqui ni de ejemplo: escribirlo
            dentro de un bloque de comentario lo cierra de verdad, que es
            justo lo que le paso a este archivo la primera vez.)

            Hace falta porque las pruebas que buscan texto encuentran los
            propios comentarios: ha pasado siete veces en este
            repositorio, y aqui la cabecera del archivo habla justo de lo
            que la prueba prohibe.
        #>
        [CmdletBinding()]
        param()

        $texto = [IO.File]::ReadAllText($script:RutaFuente)
        $texto = [regex]::Replace($texto, '(?s)<#.*?#>', ' ')
        $texto = [regex]::Replace($texto, '(?m)^\s*#.*$', ' ')
        return $texto
    }
}

Describe 'Get-CaducidadIndice' {

    It 'es un numero de dias positivo y razonable' {
        $dias = Get-CaducidadIndice
        $dias | Should -BeOfType ([int])
        $dias | Should -BeGreaterThan 0
        # Un indice de mas de un mes no lo defiende nadie: el diario ya ha
        # dado la vuelta varias veces y la ventana de cambios con el diario
        # apagado seria enorme.
        $dias | Should -BeLessOrEqual 31
    }

    It 'es la funcion la que manda: justo en el limite se acepta' {
        # El numero NO se escribe aqui. Si alguien cambia la caducidad, esta
        # prueba y la siguiente lo siguen; si la decision dejara de pedirle
        # el numero a la funcion, las dos caerian.
        $cabecera = New-CabeceraDePrueba
        $cabecera.Escrito = $script:Ahora.AddDays(-1 * (Get-CaducidadIndice))
        (Test-CabeceraDePrueba -Cabecera $cabecera).Utilizable | Should -BeTrue
    }

    It 'es la funcion la que manda: un dia mas y caduca' {
        $cabecera = New-CabeceraDePrueba
        $cabecera.Escrito = $script:Ahora.AddDays(-1 * ((Get-CaducidadIndice) + 1))
        $veredicto = Test-CabeceraDePrueba -Cabecera $cabecera
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'Caducado'
    }
}

Describe 'Test-IndiceUtilizable: la cabecera buena' {

    <#
        ESTA ES LA GUARDA DE TODO EL ARCHIVO. Si la cabecera de partida no
        se aceptara, todas las pruebas de rechazo de mas abajo pasarian
        sin comprobar nada: rechazarian igual con el campo tocado y sin
        tocarlo.
    #>

    It 'una cabecera que cuadra con el disco de hoy se acepta' {
        $veredicto = Test-CabeceraDePrueba -Cabecera (New-CabeceraDePrueba)
        $veredicto.Utilizable | Should -BeTrue
        $veredicto.Codigo     | Should -Be 'Utilizable'
        $veredicto.Motivo     | Should -BeNullOrEmpty
    }

    It 'se acepta tambien si el cuerpo leido cuadra con la cabecera' {
        $cabecera = New-CabeceraDePrueba
        $veredicto = Test-CabeceraDePrueba -Cabecera $cabecera `
                        -EntradasLeidas $cabecera.Entradas -SumaCalculada $cabecera.Suma
        $veredicto.Utilizable | Should -BeTrue
    }

    It 'una cabecera en tabla hash vale igual que en objeto' {
        # El lector del indice puede componerla de las dos formas, y la
        # decision no puede depender de eso.
        $veredicto = Test-CabeceraDePrueba -Cabecera @{
            Version      = $script:VersionHoy
            SerieVolumen = $script:SerieHoy
            IdDiario     = $script:DiarioHoy
            UsnCorte     = 250000
            Entradas     = 4
            Suma         = 'a1b2c3d4e5f6'
            Escrito      = $script:Ahora.AddDays(-1)
        }
        $veredicto.Utilizable | Should -BeTrue
    }

    It 'el corte justo en el primer USN disponible todavia vale' {
        # -lt y no -le: si el corte coincide con el primero que queda, no
        # se ha perdido ni un registro.
        $cabecera = New-CabeceraDePrueba
        $cabecera.UsnCorte = $script:PrimerUsn
        (Test-CabeceraDePrueba -Cabecera $cabecera).Utilizable | Should -BeTrue
    }
}

Describe 'Test-IndiceUtilizable: cada mentira tiene su motivo, y es el suyo' {

    <#
        La tabla es literal a proposito: se lee en el DESCUBRIMIENTO de
        Pester, donde no existe nada de lo que monta el BeforeAll.

        Cada fila toca UN campo de la cabecera buena y exige un codigo
        concreto. Que el codigo sea el correcto y no otro que tambien
        rechace es la mitad del valor de este archivo: comprobar solo
        "Utilizable = falso" dejaria pasar que el volumen se rechace por
        caducidad, o que un campo ausente se cuele como version distinta.
    #>

    It 'con <Caso> el motivo es <Esperado>' -ForEach @(
        @{ Caso = 'otra version del formato';        Campo = 'Version';      Valor = 99;                     Esperado = 'VersionDistinta' }
        @{ Caso = 'otro numero de serie';            Campo = 'SerieVolumen'; Valor = 'FFFF-0000';            Esperado = 'VolumenDistinto' }
        @{ Caso = 'otro identificador de diario';    Campo = 'IdDiario';     Valor = '0x0000000000000001';   Esperado = 'DiarioDistinto' }
        @{ Caso = 'el diario dado la vuelta';        Campo = 'UsnCorte';     Valor = 1;                      Esperado = 'DiarioDioLaVuelta' }
        @{ Caso = 'la version a nulo';               Campo = 'Version';      Valor = $null;                  Esperado = 'CampoAusente' }
        @{ Caso = 'la suma vacia';                   Campo = 'Suma';         Valor = '';                     Esperado = 'CampoAusente' }
        @{ Caso = 'la suma en blancos';              Campo = 'Suma';         Valor = '   ';                  Esperado = 'CampoAusente' }
        @{ Caso = 'una version que no es un numero'; Campo = 'Version';      Valor = 'tres';                 Esperado = 'ValorImposible' }
        @{ Caso = 'un corte negativo';               Campo = 'UsnCorte';     Valor = -5;                     Esperado = 'ValorImposible' }
        @{ Caso = 'entradas negativas';              Campo = 'Entradas';     Valor = -1;                     Esperado = 'ValorImposible' }
        @{ Caso = 'una fecha sin escribir';          Campo = 'Escrito';      Valor = ([datetime]::MinValue); Esperado = 'ValorImposible' }
        @{ Caso = 'una fecha que no es fecha';       Campo = 'Escrito';      Valor = 'ayer por la tarde';    Esperado = 'ValorImposible' }
    ) {
        $cabecera = New-CabeceraDePrueba
        $cabecera.$Campo = $Valor

        $veredicto = Test-CabeceraDePrueba -Cabecera $cabecera
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be $Esperado -Because 'el motivo tiene que ser el suyo, no otro que tambien rechace'
        $veredicto.Motivo     | Should -Not -BeNullOrEmpty -Because 'un rechazo mudo es indistinguible de un fallo del programa'
    }

    It 'si falta el campo <Campo> se dice que falta' -ForEach @(
        @{ Campo = 'Version' }
        @{ Campo = 'SerieVolumen' }
        @{ Campo = 'IdDiario' }
        @{ Campo = 'UsnCorte' }
        @{ Campo = 'Entradas' }
        @{ Campo = 'Suma' }
        @{ Campo = 'Escrito' }
    ) {
        # Aqui el campo no esta a nulo: NO ESTA. Es lo que pasa cuando el
        # indice lo escribio algo que no conocia ese campo.
        $cabecera = @{
            Version      = $script:VersionHoy
            SerieVolumen = $script:SerieHoy
            IdDiario     = $script:DiarioHoy
            UsnCorte     = 250000
            Entradas     = 4
            Suma         = 'a1b2c3d4e5f6'
            Escrito      = $script:Ahora.AddDays(-1)
        }
        $cabecera.Remove($Campo)

        $veredicto = Test-CabeceraDePrueba -Cabecera $cabecera
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'CampoAusente'
        $veredicto.Motivo     | Should -Match $Campo
    }

    It 'sin cabecera no hay nada que creer' {
        $veredicto = Test-CabeceraDePrueba -Cabecera $null
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'CabeceraAusente'
    }

    It 'una fecha en el futuro no es una fecha' {
        $cabecera = New-CabeceraDePrueba
        $cabecera.Escrito = $script:Ahora.AddDays(2)
        $veredicto = Test-CabeceraDePrueba -Cabecera $cabecera
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'ValorImposible'
    }

    It 'un ajuste de reloj de unos segundos no tira un indice bueno' {
        # El margen existe para esto y solo para esto. Sin el, cualquier
        # sincronizacion de hora obligaria a recorrer el disco entero.
        $cabecera = New-CabeceraDePrueba
        $cabecera.Escrito = $script:Ahora.AddSeconds(3)
        (Test-CabeceraDePrueba -Cabecera $cabecera).Utilizable | Should -BeTrue
    }

    It 'un cuerpo con otro numero de entradas esta truncado' {
        $cabecera = New-CabeceraDePrueba
        $veredicto = Test-CabeceraDePrueba -Cabecera $cabecera -EntradasLeidas ($cabecera.Entradas - 1)
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'CuerpoNoCuadra'
    }

    It 'un cuerpo con otra suma de comprobacion esta alterado' {
        $veredicto = Test-CabeceraDePrueba -Cabecera (New-CabeceraDePrueba) -SumaCalculada 'ffffffffffff'
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'CuerpoNoCuadra'
    }

    It 'sin el dato del disco <Dato> no se puede contrastar nada' -ForEach @(
        @{ Dato = 'VersionEsperada' }
        @{ Dato = 'SerieVolumen' }
        @{ Dato = 'IdDiario' }
        @{ Dato = 'PrimerUsn' }
        @{ Dato = 'Ahora' }
    ) {
        # Un indice que no se ha podido contrastar es igual de peligroso
        # que uno que no cuadra, asi que se contesta lo mismo: no se usa.
        $argumentos = @{
            Cabecera        = New-CabeceraDePrueba
            VersionEsperada = $script:VersionHoy
            SerieVolumen    = $script:SerieHoy
            IdDiario        = $script:DiarioHoy
            PrimerUsn       = $script:PrimerUsn
            Ahora           = $script:Ahora
        }
        $argumentos[$Dato] = $null

        $veredicto = Test-IndiceUtilizable @argumentos
        $veredicto.Utilizable | Should -BeFalse
        $veredicto.Codigo     | Should -Be 'DatosDelDiscoNoValidos'
    }

    It 'con todo a nulo no revienta: contesta que no' {
        # La trampa del relevo: [AllowNull] en los Mandatory que puedan
        # recibir nulo. Ha faltado tres veces en este repositorio y las
        # tres lo cazo una prueba como esta.
        { Test-IndiceUtilizable -Cabecera $null -VersionEsperada $null -SerieVolumen $null `
              -IdDiario $null -PrimerUsn $null -Ahora $null } | Should -Not -Throw

        $veredicto = Test-IndiceUtilizable -Cabecera $null -VersionEsperada $null -SerieVolumen $null `
                        -IdDiario $null -PrimerUsn $null -Ahora $null
        $veredicto.Utilizable | Should -BeFalse
    }

    It 'cada motivo se explica con palabras distintas' {
        # Todos los codigos llevan su frase, y no la misma frase. Un motivo
        # copiado seria un motivo que no dice cual de las cinco mentiras se
        # ha detectado, que es justo para lo que existe.
        $motivos = [Collections.Generic.List[string]]::new()
        foreach ($caso in @(
            @{ Campo = 'Version';      Valor = 99 }
            @{ Campo = 'SerieVolumen'; Valor = 'FFFF-0000' }
            @{ Campo = 'IdDiario';     Valor = '0x01' }
            @{ Campo = 'UsnCorte';     Valor = 1 }
            @{ Campo = 'Entradas';     Valor = -1 }
        )) {
            $cabecera = New-CabeceraDePrueba
            $cabecera.($caso.Campo) = $caso.Valor
            $motivos.Add((Test-CabeceraDePrueba -Cabecera $cabecera).Motivo)
        }

        @($motivos).Count | Should -Be 5 -Because 'si no hay cinco motivos, esta prueba no compara nada'
        @($motivos | Select-Object -Unique).Count | Should -Be 5
    }
}

Describe 'Update-IndiceConCambios: el indice de partida' {

    It 'cuadra con el oraculo antes de tocar nada' {
        # Sin esta guarda, las pruebas de abajo podrian pasar comparando un
        # indice mal sumado contra un oraculo que tampoco mira lo que cree.
        Get-DiferenciasConElOraculo -Indice (New-IndiceDePrueba) | Should -BeNullOrEmpty
    }
}

Describe 'Update-IndiceConCambios: altas, bajas y cambios' {

    It 'un alta suma en su carpeta y en todas las de encima' {
        $indice = New-IndiceDePrueba
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Alta'; Ruta = (Join-Path $script:Hoja 'nuevo.bin'); Bytes = 300 }
        )

        $resultado.Aplicados | Should -Be 1
        $resultado.Altas     | Should -Be 1
        $resultado.Confiable | Should -BeTrue

        $indice.Carpetas[$script:Hoja].Propios      | Should -Be 1300.0
        $indice.Carpetas[$script:Hoja].Bytes        | Should -Be 1300.0
        $indice.Carpetas[$script:Rama].Bytes        | Should -Be 1300.0
        $indice.Carpetas[$script:RaizArbol].Bytes   | Should -Be 5800.0
        $indice.Carpetas[$script:RaizArbol].Archivos | Should -Be 4
        $indice.Bytes | Should -Be 5800.0
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'una baja resta en su carpeta y en todas las de encima' {
        $indice = New-IndiceDePrueba
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Chico }
        )

        $resultado.Bajas     | Should -Be 1
        $resultado.Confiable | Should -BeTrue

        $indice.Carpetas[$script:Otra].Propios     | Should -Be 4000.0
        $indice.Carpetas[$script:Otra].Bytes       | Should -Be 4000.0
        $indice.Carpetas[$script:Otra].Archivos    | Should -Be 1
        $indice.Carpetas[$script:RaizArbol].Bytes  | Should -Be 5000.0
        $indice.Archivos.ContainsKey($script:Chico) | Should -BeFalse
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'una modificacion de tamanyo sube la diferencia, no el tamanyo entero' {
        $indice = New-IndiceDePrueba
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Cambio'; Ruta = $script:Grande; Bytes = 6000 }
        )

        $resultado.Modificados | Should -Be 1
        $resultado.Altas       | Should -Be 0

        # Si se sumara el tamanyo entero en vez de la diferencia, la
        # carpeta valdria 10.500 en vez de 6.500.
        $indice.Carpetas[$script:Otra].Bytes      | Should -Be 6500.0
        $indice.Carpetas[$script:Otra].Archivos   | Should -Be 2
        $indice.Carpetas[$script:RaizArbol].Bytes | Should -Be 7500.0
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'una modificacion que encoge tambien resta hacia arriba' {
        $indice = New-IndiceDePrueba
        $null = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Cambio'; Ruta = $script:Grande; Bytes = 100 }
        )

        $indice.Carpetas[$script:Otra].Bytes      | Should -Be 600.0
        $indice.Carpetas[$script:RaizArbol].Bytes | Should -Be 1600.0
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'la fecha de la carpeta sube con un archivo mas nuevo' {
        $indice = New-IndiceDePrueba
        $cuando = [datetime]'2026-08-30T10:00:00'
        $null = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Alta'; Ruta = (Join-Path $script:Hoja 'reciente.bin'); Bytes = 10; Ultimo = $cuando }
        )

        $indice.Carpetas[$script:Hoja].Ultimo      | Should -Be $cuando
        $indice.Carpetas[$script:RaizArbol].Ultimo | Should -Be $cuando
    }

    It 'un alta en una carpeta nueva la cuelga de la que si esta, con su nivel' {
        $indice = New-IndiceDePrueba
        $nueva  = Join-Path (Join-Path $script:Rama 'reciente') 'honda'
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Alta'; Ruta = (Join-Path $nueva 'x.bin'); Bytes = 700 }
        )

        $resultado.Aplicados | Should -Be 1
        $resultado.Confiable | Should -BeTrue
        $indice.Carpetas.ContainsKey($nueva) | Should -BeTrue
        # rama esta en el nivel 1, asi que reciente es 2 y honda es 3.
        $indice.Carpetas[$nueva].Nivel            | Should -Be 3
        $indice.Carpetas[$script:Rama].Bytes      | Should -Be 1700.0
        $indice.Carpetas[$script:RaizArbol].Bytes | Should -Be 6200.0
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'una tanda entera deja el indice cuadrado con el oraculo' {
        $indice = New-IndiceDePrueba
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Alta';   Ruta = (Join-Path $script:Hoja 'a.bin'); Bytes = 111 }
            [pscustomobject]@{ Tipo = 'Cambio'; Ruta = $script:Grande;                   Bytes = 2222 }
            [pscustomobject]@{ Tipo = 'Baja';   Ruta = $script:Chico }
            [pscustomobject]@{ Tipo = 'Alta';   Ruta = (Join-Path $script:Otra 'b.bin'); Bytes = 33 }
            [pscustomobject]@{ Tipo = 'Baja';   Ruta = $script:Sola }
        )

        $resultado.Aplicados   | Should -Be 5
        $resultado.Confiable   | Should -BeTrue
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }
}

Describe 'Update-IndiceConCambios: el espacio que ya no esta tiene que desaparecer del mapa' {

    <#
        ESTA ES LA PRUEBA QUE SOSTIENE EL PUNTO ENTERO.

        Si la propagacion se olvida de restar, el mapa ensenya para siempre
        un espacio que ya no existe: el usuario ve 40 GB en una carpeta,
        va a buscarlos, no los encuentra, y a partir de ahi no se fia de
        nada de lo que ve. Es exactamente la mentira que este trabajo
        viene a impedir.
    #>

    It 'una baja que deja la carpeta a cero deja su total a cero' {
        $indice = New-IndiceDePrueba
        $null = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Sola }
        )

        $indice.Carpetas[$script:Hoja].Propios  | Should -Be 0.0
        $indice.Carpetas[$script:Hoja].Bytes    | Should -Be 0.0
        $indice.Carpetas[$script:Hoja].Archivos | Should -Be 0
    }

    It 'y el cero sube por toda la cadena hasta la raiz' {
        $indice = New-IndiceDePrueba
        $null = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Sola }
        )

        # rama no tenia archivos propios: todo lo suyo era de hoja.
        $indice.Carpetas[$script:Rama].Bytes    | Should -Be 0.0
        $indice.Carpetas[$script:Rama].Archivos | Should -Be 0
        # Y la raiz pierde exactamente esos 1.000 bytes, ni uno mas.
        $indice.Carpetas[$script:RaizArbol].Bytes | Should -Be 4500.0
        $indice.Bytes | Should -Be 4500.0
    }

    It 'la otra rama sigue valiendo lo mismo' {
        # Sin esto, poner el arbol entero a cero pasaria la prueba de
        # arriba igual de bien que restar donde toca.
        $indice = New-IndiceDePrueba
        $null = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Sola }
        )

        $indice.Carpetas[$script:Otra].Bytes    | Should -Be 4500.0
        $indice.Carpetas[$script:Otra].Archivos | Should -Be 2
    }

    It 'quitandolo todo, el indice entero vale cero' {
        $indice = New-IndiceDePrueba
        $null = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Sola }
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Grande }
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Chico }
        )

        foreach ($carpeta in @($indice.Carpetas.Keys)) {
            $indice.Carpetas[$carpeta].Bytes    | Should -Be 0.0
            $indice.Carpetas[$carpeta].Propios  | Should -Be 0.0
            $indice.Carpetas[$carpeta].Archivos | Should -Be 0
        }
        $indice.Bytes         | Should -Be 0.0
        $indice.TotalArchivos | Should -Be 0
        @($indice.Archivos.Keys).Count | Should -Be 0
    }
}

Describe 'Update-IndiceConCambios: no revienta con nada' {

    It 'con una lista vacia no hace nada y no protesta' {
        $indice = New-IndiceDePrueba
        { Update-IndiceConCambios -Indice (New-IndiceDePrueba) -Cambios @() } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @()

        $resultado.Aplicados   | Should -Be 0
        $resultado.Descartados | Should -Be 0
        $resultado.Confiable   | Should -BeTrue -Because 'que no haya cambiado nada no es motivo para desconfiar'
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'con la lista a nulo tampoco' {
        $indice = New-IndiceDePrueba
        { Update-IndiceConCambios -Indice (New-IndiceDePrueba) -Cambios $null } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios $null

        # @($null) NO es una lista vacia sino una lista con un nulo dentro:
        # sin cuidado, "no ha cambiado nada" se contaria como un cambio
        # perdido y el indice quedaria marcado como no fiable por nada.
        $resultado.Aplicados   | Should -Be 0
        $resultado.Descartados | Should -Be 0
        $resultado.Confiable   | Should -BeTrue
    }

    It 'con nulos dentro de la lista los descarta y lo dice' {
        $indice = New-IndiceDePrueba
        { Update-IndiceConCambios -Indice (New-IndiceDePrueba) -Cambios @($null, $null) } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @($null, $null)

        $resultado.Descartados | Should -Be 2
        $resultado.Confiable   | Should -BeFalse -Because 'un indice al que se le han caido cambios puede estar mintiendo'
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'con el indice a nulo no revienta y no se fia' {
        $cambios = @([pscustomobject]@{ Tipo = 'Alta'; Ruta = 'x'; Bytes = 1 })
        { Update-IndiceConCambios -Indice $null -Cambios $cambios } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $null -Cambios $cambios

        $resultado.Confiable | Should -BeFalse
        $resultado.Aplicados | Should -Be 0
        $resultado.Motivo    | Should -Not -BeNullOrEmpty
    }

    It 'con un indice sin las dos tablas no aplica nada' {
        # Lo que la medicion prohibe: un indice con solo la tabla de
        # archivos obliga a volver a sumar el millon de entradas, que
        # cuesta mas que recorrer el disco entero.
        $medias  = [pscustomobject]@{ Archivos = @{}; Carpetas = $null }
        $cambios = @([pscustomobject]@{ Tipo = 'Alta'; Ruta = 'x'; Bytes = 1 })
        { Update-IndiceConCambios -Indice $medias -Cambios $cambios } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $medias -Cambios $cambios

        $resultado.Confiable   | Should -BeFalse
        $resultado.Descartados | Should -Be 1
    }

    It 'una baja de algo que no existia no es un fallo' {
        $indice  = New-IndiceDePrueba
        $cambios = @([pscustomobject]@{ Tipo = 'Baja'; Ruta = (Join-Path $script:Hoja 'jamas.bin') })
        { Update-IndiceConCambios -Indice (New-IndiceDePrueba) -Cambios $cambios } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios $cambios

        # El archivo pudo crearse y borrarse entre dos pasadas: no hay nada
        # que restar y no hay nada de lo que desconfiar.
        $resultado.Ignorados   | Should -Be 1
        $resultado.Descartados | Should -Be 0
        $resultado.Confiable   | Should -BeTrue
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'un cambio sobre una carpeta que ya no esta se descarta ENTERO' {
        $indice = New-IndiceDePrueba
        $forastero = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'otro-arbol-distinto') 'z.bin'

        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Alta'; Ruta = $forastero; Bytes = 900 })

        $resultado.Descartados | Should -Be 1
        $resultado.Confiable   | Should -BeFalse
        # Y ni medio cambio: si el archivo hubiera entrado en la tabla sin
        # que ninguna carpeta lo sumara, el indice diria una cosa en una
        # tabla y otra en la otra.
        $indice.Archivos.ContainsKey($forastero) | Should -BeFalse
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'una baja sin carpeta conocida no quita el archivo de la tabla' {
        # El caso peor de aplicar medio cambio: quitar el archivo y no
        # poder corregir su carpeta deja el indice diciendo que ese
        # espacio sigue ahi.
        $indice = New-IndiceDePrueba
        $suelto = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'arbol-que-no-esta') 'y.bin'
        $indice.Archivos[$suelto] = 50.0

        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $suelto })

        $resultado.Descartados | Should -Be 1
        $resultado.Confiable   | Should -BeFalse
        $indice.Archivos.ContainsKey($suelto) | Should -BeTrue
    }

    It 'un cambio con <Caso> se descarta sin tocar el indice' -ForEach @(
        @{ Caso = 'un tipo que no existe'; Tipo = 'Renombrado'; Bytes = 10 }
        @{ Caso = 'el tipo vacio';         Tipo = '';           Bytes = 10 }
        @{ Caso = 'un tamanyo negativo';   Tipo = 'Alta';       Bytes = -10 }
        @{ Caso = 'un tamanyo que no es un numero'; Tipo = 'Alta'; Bytes = 'mucho' }
        @{ Caso = 'un tamanyo a nulo';     Tipo = 'Alta';       Bytes = $null }
    ) {
        $indice  = New-IndiceDePrueba
        $cambios = @([pscustomobject]@{ Tipo = $Tipo; Ruta = (Join-Path $script:Hoja 'raro.bin'); Bytes = $Bytes })
        { Update-IndiceConCambios -Indice (New-IndiceDePrueba) -Cambios $cambios } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios $cambios

        $resultado.Aplicados   | Should -Be 0
        $resultado.Descartados | Should -Be 1
        $resultado.Confiable   | Should -BeFalse
        Get-DiferenciasConElOraculo -Indice $indice | Should -BeNullOrEmpty
    }

    It 'un cambio sin ruta se descarta' {
        $indice  = New-IndiceDePrueba
        $cambios = @([pscustomobject]@{ Tipo = 'Alta'; Ruta = $null; Bytes = 10 })
        { Update-IndiceConCambios -Indice (New-IndiceDePrueba) -Cambios $cambios } | Should -Not -Throw
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios $cambios

        $resultado.Descartados | Should -Be 1
        $resultado.Confiable   | Should -BeFalse
    }

    It 'el tipo vale igual en mayusculas' {
        $indice = New-IndiceDePrueba
        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'BAJA'; Ruta = $script:Chico })

        $resultado.Bajas | Should -Be 1
    }

    It 'un total que saldria negativo se recorta a cero y se cuenta' {
        # Un indice descuadrado de antes -mitad escrito, por ejemplo- no
        # puede acabar ensenyando un tamanyo negativo, que seria una
        # mentira peor. Se recorta, PERO SE CUENTA: recortar en silencio
        # seria tapar el sintoma en el archivo escrito para no tapar
        # ninguno.
        $indice = New-IndiceDePrueba
        $indice.Carpetas[$script:Otra].Propios = 0.0
        $indice.Carpetas[$script:Otra].Bytes   = 0.0

        $resultado = Update-IndiceConCambios -Indice $indice -Cambios @(
            [pscustomobject]@{ Tipo = 'Baja'; Ruta = $script:Grande })

        $indice.Carpetas[$script:Otra].Bytes   | Should -Be 0.0
        $indice.Carpetas[$script:Otra].Propios | Should -Be 0.0
        $resultado.Recortes | Should -BeGreaterThan 0
        $resultado.Confiable | Should -BeFalse
    }
}

Describe 'ConvertTo-NumeroIndice y Resolve-CarpetaIndice: las dos piezas de abajo' {

    It 'un numero escrito como texto se lee' {
        ConvertTo-NumeroIndice -Valor ' 4200 ' | Should -Be 4200
    }

    It 'no se redondea un numero con decimales: se rechaza' {
        # El cast de PowerShell devolveria 4, y un USN de corte redondeado
        # no es el USN que se guardo.
        ConvertTo-NumeroIndice -Valor '3.7' | Should -BeNullOrEmpty
        ConvertTo-NumeroIndice -Valor 3.7   | Should -BeNullOrEmpty
    }

    It 'un booleano no es un numero' {
        # [long]$true vale 1 sin protestar, que seria inventarse una
        # version a partir de un campo que no es una version.
        ConvertTo-NumeroIndice -Valor $true | Should -BeNullOrEmpty
    }

    It 'lo que no es un numero devuelve nulo en vez de lanzar' -ForEach @(
        @{ Valor = $null }
        @{ Valor = '' }
        @{ Valor = '   ' }
        @{ Valor = 'catorce' }
    ) {
        { ConvertTo-NumeroIndice -Valor $Valor } | Should -Not -Throw
        ConvertTo-NumeroIndice -Valor $Valor | Should -BeNullOrEmpty
    }

    It 'Resolve-CarpetaIndice no inventa una carpeta que no cuelga de nada' {
        $indice = New-IndiceDePrueba
        $lejos  = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'ni-de-lejos') 'aqui'
        Resolve-CarpetaIndice -Carpetas $indice.Carpetas -Ruta $lejos -Crear | Should -BeNullOrEmpty
        $indice.Carpetas.ContainsKey($lejos) | Should -BeFalse
    }

    It 'Resolve-CarpetaIndice sin -Crear no crea nada' {
        $indice = New-IndiceDePrueba
        $nueva  = Join-Path $script:Rama 'todavia-no'
        Resolve-CarpetaIndice -Carpetas $indice.Carpetas -Ruta $nueva | Should -BeNullOrEmpty
        $indice.Carpetas.ContainsKey($nueva) | Should -BeFalse
    }

    It 'Resolve-CarpetaIndice y Update-CadenaCarpetas aguantan nulos' {
        { Resolve-CarpetaIndice -Carpetas $null -Ruta $null } | Should -Not -Throw
        { Update-CadenaCarpetas -Carpetas $null -Ruta $null }  | Should -Not -Throw
        Update-CadenaCarpetas -Carpetas $null -Ruta $null | Should -Be 0
    }

    It 'Update-CadenaCarpetas no se pierde con un antepasado que falta' {
        # La cadena no se corta: el total del abuelo SI contiene ese
        # archivo, asi que pararse en el hueco seria dejar de restar justo
        # donde mas se nota.
        $indice = New-IndiceDePrueba
        $null = $indice.Carpetas.Remove($script:Rama)

        $null = Update-CadenaCarpetas -Carpetas $indice.Carpetas -Ruta $script:Hoja -DeltaBytes -1000.0
        $indice.Carpetas[$script:RaizArbol].Bytes | Should -Be 4500.0
    }
}

Describe 'El indice guardado pinta el mapa; no decide que se borra' {

    <#
        LA DECISION DE DISENYO QUE MANDA SOBRE TODAS LAS DEMAS, y por eso
        tiene prueba y no solo un parrafo en la cabecera.

        Cachivache borra desde lo que acaba de ver con sus propios ojos en
        esta ejecucion. Si el indice se equivoca, el peor caso es un
        rectangulo mal dibujado; nunca un archivo borrado por error. Esa
        separacion hay que ponerla el primer dia: anyadirla despues de que
        algo dependa del indice no se hace.
    #>

    BeforeAll {
        $script:Fuente = Get-FuenteSinComentarios
        $script:Funciones = @([regex]::Matches($script:Fuente, '(?m)^function\s+([A-Za-z]+-[A-Za-z0-9]+)') |
                              ForEach-Object { $_.Groups[1].Value })
    }

    It 'la prueba encuentra las funciones: si no, no comprueba nada' {
        @($script:Funciones).Count | Should -BeGreaterOrEqual 5
    }

    It 'quitar los comentarios deja codigo, no un archivo vacio' {
        # Sin esta guarda, un fallo del recortador dejaria las dos pruebas
        # de abajo pasando sobre una cadena vacia.
        $script:Fuente | Should -Match 'Test-IndiceUtilizable'
        $script:Fuente.Length | Should -BeGreaterThan 2000
    }

    It 'ninguna funcion suena a decidir que se borra' {
        @($script:Funciones | Where-Object { $_ -match 'Candidat|Borr|Elimin|Limpi' }) | Should -BeNullOrEmpty
    }

    It 'el codigo no nombra el contrato de candidato ni el motor de borrado' {
        # Que ninguna funcion de aqui devuelva algo que se parezca a un
        # candidato, y que este archivo no sepa siquiera como se llaman las
        # piezas que borran.
        foreach ($prohibido in @('Candidato', 'Remove-RutaSegura', 'Invoke-EliminacionCandidato',
                                 'New-Candidato', 'Get-MotivoNoSeBorra')) {
            $script:Fuente | Should -Not -Match $prohibido
        }
    }

    It 'lo que se devuelve son numeros y veredictos, no rutas para actuar' {
        # El veredicto no lleva ni una ruta: quien lo lea solo puede
        # decidir si se fia del indice, nunca que hacer con un archivo.
        $veredicto = Test-CabeceraDePrueba -Cabecera (New-CabeceraDePrueba)
        @($veredicto.PSObject.Properties.Name | Sort-Object) | Should -Be @('Codigo', 'Motivo', 'Utilizable')
    }
}
