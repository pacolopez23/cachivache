<#
    Lo que se mide de la propia red de seguridad.

    Dos cosas distintas y con el mismo proposito: que ningun trozo del
    programa pueda quedarse sin que nadie lo ejecute nunca, como le paso a
    src/Cli, que estuvo al 0 % de cobertura toda su vida sin que nada lo
    dijera.

      1. EL SUELO DE COBERTURA. Las decisiones puras de tools/Cobertura.ps1:
         cuando la cobertura medida vale y cuando no. El guion que mide
         -tools/Probar.ps1- no decide nada; solo pregunta.

      2. EL INVENTARIO DE FUNCIONES. Toda funcion de src/ tiene que estar
         nombrada en alguna prueba, o figurar en una lista de deuda con su
         motivo. La lista SOLO PUEDE ENCOGER: si una funcion de la lista
         pasa a estar probada, o deja de existir, esta prueba falla para
         que se quite. Sin esa segunda regla la lista seria un cajon donde
         meter lo incomodo.

    AVISO QUE NO SE PUEDE REPETIR BASTANTE: que una linea se haya ejecutado
    NO dice que haga lo correcto. El fallo del ValidateSet del historial y
    el de los informes que se anunciaban guardados sin escribirse vivian
    los dos en lineas perfectamente cubiertas. Esto no mide calidad; mide
    abandono.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent
    # LA DEUDA VIVE EN UN .txt, Y HAY DOS MOTIVOS.
    #
    # Uno: escrita aqui se nombraria a si misma. El inventario busca cada
    # nombre de funcion en el codigo de tests/*.ps1, asi que las 32
    # funciones sin probar constaban como probadas por figurar en la lista
    # de las que no lo estan. La suite se quedaba en verde diciendo lo
    # contrario de la verdad.
    #
    # Y dos: escrita en el cuerpo del Describe tampoco valia. Pester
    # ejecuta ese cuerpo durante el DESCUBRIMIENTO, y lo que se asigne alli
    # no llega al ambito de los It: la lista se veia VACIA desde dentro de
    # la prueba. Otra vez el sintoma peor, la suite en verde, y solo salio
    # al verificar por mutacion: meter en la lista un nombre que ya sobra
    # no hacia fallar nada. Es la tercera vez que el descubrimiento de
    # Pester muerde en este proyecto. Regla: si un It lo lee, se construye
    # en un BeforeAll.
    $script:RutaDeuda = Join-Path (Join-Path $script:Raiz 'tests') 'datos/deuda-de-pruebas.txt'
    $script:Deuda = @(Get-Content -LiteralPath $script:RutaDeuda |
                      ForEach-Object { $_.Trim() } |
                      Where-Object { $_ -and $_ -notmatch '^#' })

    . (Join-Path (Join-Path $script:Raiz 'tools') 'Cobertura.ps1')
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # El inventario: nombre de funcion -> .la nombra alguna prueba?
    #
    # SIN COMENTARIOS, y esto lo cazo la primera ejecucion de este mismo
    # archivo: la lista de deuda de mas abajo explica en un comentario por
    # que Get-ColorRiesgo y Get-GeometriaTema no se pueden probar aqui...
    # y al mencionarlas, el inventario las daba por probadas. Trece
    # funciones se marcaron como cubiertas por el comentario que decia que
    # NO lo estaban.
    #
    # Es la trampa que este proyecto lleva anotada seis veces en el relevo,
    # y aparecio otra vez en la prueba escrita para no fiarse de las
    # pruebas.
    #
    # Orden: primero los bloques <# #>, DESPUES las lineas que empiezan por
    # #. Al reves, el primer paso se lleva la linea del "#>" y el bloque se
    # queda sin cierre.
    $script:TextoPruebas = (Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'tests') `
                              -Filter '*.ps1' -Recurse |
                            ForEach-Object {
                                $t = [regex]::Replace([IO.File]::ReadAllText($_.FullName), '(?s)<#.*?#>', '')
                                (@($t -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
                            }) -join "`n"

    $script:Funciones = [Collections.Generic.List[object]]::new()
    foreach ($archivo in (Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'src') -Filter '*.ps1' -Recurse)) {
        $tokens = $null; $errores = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($archivo.FullName, [ref]$tokens, [ref]$errores)
        foreach ($fn in $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $script:Funciones.Add([pscustomobject]@{
                Nombre   = $fn.Name
                Archivo  = $archivo.Name
                Nombrada = $script:TextoPruebas -match [regex]::Escape($fn.Name)
            })
        }
    }
}

Describe 'El suelo de cobertura' {

    It 'hay suelo para el total y para las cuatro carpetas de src' {
        # Guarda: sin suelos, todo lo de abajo comprueba el vacio.
        $suelo = Get-SueloCobertura
        foreach ($clave in @('total', 'Core', 'Modules', 'Cli', 'UI')) {
            $suelo.ContainsKey($clave) | Should -BeTrue -Because "'$clave' tiene que tener suelo"
        }
    }

    It 'con la cobertura de hoy no hay ningun motivo de queja' {
        # Las dos mediciones reales: la de aqui y la de la integracion
        # continua en Windows. El suelo tiene que aguantar LAS DOS, que es
        # la leccion que costo un trabajo en rojo.
        #
        # Las dos son del 1 de septiembre de 2026, con la deuda de pruebas
        # ya pagada. Windows cubre MAS que Linux en las cuatro filas, asi
        # que el suelo lo marca Linux: por eso importa que esten las dos.
        @(Test-CoberturaSuficiente -Medido @{
            'total' = 66.1; 'Core' = 88.6; 'Modules' = 65.4; 'Cli' = 89.4; 'UI' = 5.1
        }) | Should -BeNullOrEmpty -Because 'medido en Linux'
        @(Test-CoberturaSuficiente -Medido @{
            'total' = 66.8; 'Core' = 89.4; 'Modules' = 66.6; 'Cli' = 89.4; 'UI' = 5.1
        }) | Should -BeNullOrEmpty -Because 'medido en Windows por la integracion continua'
    }

    # LOS TRES CASOS DE ABAJO SE CONSTRUYEN DESDE EL PROPIO SUELO, y no con
    # numeros escritos a mano. Nacieron a mano y caducaron a la primera:
    # el dia que los suelos subieron, "una carpeta que baja de su suelo"
    # empezo a nombrar TRES carpetas en vez de una, porque los numeros del
    # ejemplo se habian quedado por debajo de los suelos nuevos.
    #
    # Una prueba sobre un mecanismo no debe llevar dentro los datos que el
    # mecanismo vigila: se rompe cada vez que los datos cambian, y el que
    # la arregla acaba tocando el numero sin mirar que comprobaba.
    BeforeAll {
        function script:New-MedicionQueAprueba {
            # Una medicion que pasa todos los suelos con holgura, sea cual
            # sea el suelo de hoy.
            $m = @{}
            foreach ($par in (Get-SueloCobertura).GetEnumerator()) {
                $m[$par.Key] = [double]$par.Value + 5.0
            }
            return $m
        }
    }

    It 'una carpeta que baja de su suelo se nombra, y solo esa' {
        $medido = script:New-MedicionQueAprueba
        $medido['Core'] = (Get-SueloCobertura)['Core'] - 10.0
        $motivos = @(Test-CoberturaSuficiente -Medido $medido)
        $motivos.Count | Should -Be 1 -Because 'solo Core esta por debajo'
        $motivos[0] | Should -Match 'Core'
    }

    It 'y una que esta JUSTO en su suelo no se nombra' {
        # El borde exacto. Sin esto, un ">=" cambiado por un ">" pasaria
        # desapercibido y el trinquete se volveria un punto mas estricto
        # de lo que dice ser.
        $medido = script:New-MedicionQueAprueba
        $medido['Core'] = [double](Get-SueloCobertura)['Core']
        @(Test-CoberturaSuficiente -Medido $medido) | Should -BeNullOrEmpty
    }

    It 'una carpeta que FALTA es un fallo, no un aprobado' {
        # El caso de verdad peligroso: alguien renombra src/Core y la
        # medicion deja de incluirla. Si esto pasara, estariamos exigiendo
        # un suelo a algo que ya nadie mide.
        $medido = script:New-MedicionQueAprueba
        $medido.Remove('Core')
        $motivos = @(Test-CoberturaSuficiente -Medido $medido)
        ($motivos -join ' ') | Should -Match "Falta la cobertura de 'Core'"
    }

    It 'una carpeta nueva sin suelo obliga a decidir' {
        $medido = script:New-MedicionQueAprueba
        $medido['Extensiones'] = 12.0
        ($motivos = @(Test-CoberturaSuficiente -Medido $medido)) | Should -Not -BeNullOrEmpty
        ($motivos -join ' ') | Should -Match 'Extensiones'
    }

    It 'no haber medido nada NO es estar en verde' {
        # La misma leccion que le costo una pasada a tools/Probar.ps1: el
        # sintoma de "la medicion fallo" es identico al de "todo bien" si
        # nadie los distingue.
        @(Test-CoberturaSuficiente -Medido @{})   | Should -Not -BeNullOrEmpty
        @(Test-CoberturaSuficiente -Medido $null) | Should -Not -BeNullOrEmpty
        { Test-CoberturaSuficiente -Medido $null } | Should -Not -Throw
    }
}

Describe 'Funciones que ninguna prueba nombra todavia' {


    It 'la lista de deuda se ha leido de verdad' {
        # Guarda de las dos pruebas de abajo. Si el archivo se moviera o se
        # vaciara, "no hay ninguna deuda" y "no he podido leer la deuda" se
        # verian igual, y la segunda dejaria pasar cualquier cosa. Es la
        # misma leccion que el suelo de cobertura con la medida vacia.
        Test-Path -LiteralPath $script:RutaDeuda | Should -BeTrue
        $script:Deuda.Count | Should -BeGreaterThan 0 -Because (
            'el dia que la lista se quede vacia de verdad, hay que borrar estas pruebas ' +
            'y celebrarlo, no dejarlas pasando por inercia')
    }

    It 'toda funcion de src esta nombrada en alguna prueba, o en la lista de deuda' {
        # Guarda: si el inventario sale vacio, esta prueba no comprueba
        # nada y tiene que decirlo en vez de pasar celebrando.
        $script:Funciones.Count | Should -BeGreaterThan 100 -Because 'el programa tiene casi doscientas funciones'

        $huerfanas = @($script:Funciones |
                       Where-Object { -not $_.Nombrada -and $script:Deuda -notcontains $_.Nombre } |
                       ForEach-Object { '{0} ({1})' -f $_.Nombre, $_.Archivo } | Sort-Object)

        ($huerfanas -join ', ') | Should -BeNullOrEmpty -Because (
            'una funcion que ninguna prueba nombra es codigo que nadie ha ejercitado nunca. ' +
            'Escribe la prueba, o anyadela a la lista de deuda con su motivo')
    }

    It 'la lista de deuda no tiene nombres que ya sobran' {
        # Esto es lo que la convierte en un trinquete y no en un cajon. Si
        # alguien prueba una funcion de la lista, o la borra, hay que
        # quitarla de aqui: una lista de deuda con deudas saldadas deja de
        # leerse.
        $nombresReales = @($script:Funciones | ForEach-Object { $_.Nombre })
        $sobran = @()
        foreach ($n in $script:Deuda) {
            if ($nombresReales -notcontains $n) {
                $sobran += ('{0}: ya no existe ninguna funcion asi' -f $n)
                continue
            }
            $probada = @($script:Funciones | Where-Object { $_.Nombre -eq $n -and $_.Nombrada })
            if ($probada.Count -gt 0) {
                $sobran += ('{0}: ya la nombra alguna prueba' -f $n)
            }
        }
        ($sobran -join '; ') | Should -BeNullOrEmpty -Because 'la lista de deuda solo puede encoger'
    }
}

Describe 'Las funciones pequenyas que estaban sin nombrar' {
    <#
        Ocho de las que estaban en la lista, saldadas en la misma pasada
        que creo la lista. Ninguna necesita nada del sistema: son calculo
        puro que llevaba sin ejecutarse desde que se escribio.
    #>

    It 'Remove-SufijoVersion quita los digitos del final' {
        Remove-SufijoVersion -Token 'python39'   | Should -Be 'python'
        Remove-SufijoVersion -Token 'office2016' | Should -Be 'office'
    }

    It 'Remove-SufijoVersion NO parte un nombre que empieza por numero' {
        # Quitar todos los digitos convertiria "7zip" en "zip" y
        # "1password" en "password", que son programas distintos.
        Remove-SufijoVersion -Token '7zip'      | Should -Be '7zip'
        Remove-SufijoVersion -Token '1password' | Should -Be '1password'
    }

    It 'Remove-SufijoVersion no deja un token demasiado corto' {
        # "vs2019" recortado seria "vs": dos letras casan con demasiadas
        # cosas y la deteccion empezaria a dar falsos positivos.
        Remove-SufijoVersion -Token 'vs2019' | Should -Be 'vs2019'
        Remove-SufijoVersion -Token ''       | Should -Be ''
        Remove-SufijoVersion -Token $null    | Should -Be ''
    }

    It 'Format-VersionNormalizada escribe siempre igual lo que entiende' {
        Format-VersionNormalizada -Etiqueta 'v2.1'  | Should -Be '2.1.0'
        Format-VersionNormalizada -Etiqueta '2.1.3' | Should -Be '2.1.3'
    }

    It 'Format-VersionNormalizada devuelve vacio con lo que NO entiende' {
        # Esto viene de la red. Lo que se pinta son los numeros que se han
        # entendido, nunca el texto tal cual llego. Ver [DIS-05].
        foreach ($basura in @('', $null, 'ultima', '<script>alert(1)</script>', 'v')) {
            Format-VersionNormalizada -Etiqueta $basura | Should -Be ''
        }
    }

    It 'Test-ModuloEnPerfil responde por la lista de perfiles del modulo' {
        $modulo = [pscustomobject]@{ Perfiles = @('rapido', 'equilibrado') }
        Test-ModuloEnPerfil -Modulo $modulo -Perfil 'equilibrado' | Should -BeTrue
        Test-ModuloEnPerfil -Modulo $modulo -Perfil 'exhaustivo'  | Should -BeFalse
    }

    It 'en el perfil personalizado entran todos' {
        # El perfil personalizado significa "lo elige el usuario con las
        # casillas", asi que aqui no se filtra nada.
        $modulo = [pscustomobject]@{ Perfiles = @() }
        Test-ModuloEnPerfil -Modulo $modulo -Perfil 'personalizado' | Should -BeTrue
    }

    It 'Get-RaizQueContiene devuelve la raiz de la que cuelga la ruta' {
        Get-RaizQueContiene -Ruta 'C:\Windows\Temp\x.tmp' -Raices @('C:\Windows') |
            Should -Not -BeNullOrEmpty
    }

    It 'Get-RaizQueContiene NO da por buena la propia raiz' {
        # Exige la barra final justo para esto: la raiz autorizada nunca
        # puede resultar borrable, solo lo que hay dentro.
        Get-RaizQueContiene -Ruta 'C:\Windows' -Raices @('C:\Windows') | Should -BeNullOrEmpty
    }

    It 'Get-RaizQueContiene con nada dentro no lanza y dice que no' {
        { Get-RaizQueContiene -Ruta $null -Raices @('C:\Windows') } | Should -Not -Throw
        Get-RaizQueContiene -Ruta $null   -Raices @('C:\Windows') | Should -BeNullOrEmpty
        Get-RaizQueContiene -Ruta 'C:\x'  -Raices @()             | Should -BeNullOrEmpty
        Get-RaizQueContiene -Ruta 'C:\x'  -Raices $null           | Should -BeNullOrEmpty
    }

    It 'Join-RutaNativa une sin preguntarle al proveedor por la unidad' {
        # Join-Path resuelve la unidad a traves del proveedor y lanza si la
        # letra no existe en el proceso, que es justo lo que pasa al
        # ejecutar las pruebas fuera de Windows. Ya mordio dos veces.
        $s = [IO.Path]::DirectorySeparatorChar
        Join-RutaNativa -Base 'Z:' -Segmentos 'uno', 'dos' | Should -Be ('Z:{0}uno{0}dos' -f $s)
        { Join-RutaNativa -Base 'Z:' -Segmentos 'uno' }    | Should -Not -Throw
    }

    It 'Join-RutaNativa parte los segmentos por cualquier barra y se salta los huecos' {
        # La BASE se respeta tal cual -solo se le quita la barra final-, y
        # los SEGMENTOS se parten por las dos barras y se vuelven a unir
        # con el separador nativo. La asimetria es deliberada: la base
        # viene de una carpeta que ya existe en disco y no hay que
        # reescribirla; los segmentos son texto que se le anyade.
        $s = [IO.Path]::DirectorySeparatorChar
        Join-RutaNativa -Base 'C:\base\' -Segmentos 'uno/dos', '', 'tres' |
            Should -Be ('C:\base{0}uno{0}dos{0}tres' -f $s)
    }

    It 'Get-ProporcionPeor castiga los rectangulos alargados' {
        # Cuanto mas cuadrada es la fila, menor es la proporcion. Es lo
        # unico que decide cuando cerrar una fila del mapa de arbol.
        $cuadrada  = Get-ProporcionPeor -Tamanos @(50.0, 50.0) -Suma 100.0 -Lado 10.0
        $alargada  = Get-ProporcionPeor -Tamanos @(99.0,  1.0) -Suma 100.0 -Lado 10.0
        $alargada | Should -BeGreaterThan $cuadrada
    }

    It 'Get-ProporcionPeor devuelve el peor caso con datos imposibles' {
        # Devolver un numero pequenyo aqui haria que el algoritmo creyera
        # haber encontrado una fila estupenda y no cerrara nunca.
        Get-ProporcionPeor -Tamanos @()      -Suma 100.0 -Lado 10.0 | Should -Be ([double]::MaxValue)
        Get-ProporcionPeor -Tamanos @(1.0)   -Suma 0.0   -Lado 10.0 | Should -Be ([double]::MaxValue)
        Get-ProporcionPeor -Tamanos @(1.0)   -Suma 100.0 -Lado 0.0  | Should -Be ([double]::MaxValue)
        Get-ProporcionPeor -Tamanos @(0.0)   -Suma 100.0 -Lado 10.0 | Should -Be ([double]::MaxValue)
    }

    It 'New-Rectangulo compone los cuatro campos del mapa' {
        $r = New-Rectangulo -X 1.5 -Y 2.5 -Ancho 30.0 -Alto 40.0
        $r.X | Should -Be 1.5
        $r.Y | Should -Be 2.5
        $r.Ancho | Should -Be 30.0
        $r.Alto  | Should -Be 40.0
    }

    It 'Test-EsRutaDeVerdad distingue una ruta de una etiqueta' {
        # Las tres formas de ruta anclada. La tercera -la raiz POSIX- no
        # sobra aunque el programa solo corra en Windows: la suite se
        # ejecuta en Linux y sin ella una ruta de verdad se tomaba por
        # etiqueta. Ver [ARQ-03].
        Test-EsRutaDeVerdad -Texto 'C:\Windows\Temp'      | Should -BeTrue
        Test-EsRutaDeVerdad -Texto '\\servidor\recurso'   | Should -BeTrue
        Test-EsRutaDeVerdad -Texto '/tmp/algo'            | Should -BeTrue
    }

    It 'Test-EsRutaDeVerdad dice que no a lo que solo es texto' {
        foreach ($etiqueta in @('Cache de Chrome', 'Papelera de reciclaje', '', $null, 'C-algo')) {
            Test-EsRutaDeVerdad -Texto $etiqueta | Should -BeFalse -Because "'$etiqueta' no es una ruta"
        }
    }
}
