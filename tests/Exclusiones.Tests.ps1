<#
    Pruebas de la deuda de [CNF-01]: ver la lista de exclusiones y poder
    quitar una.

    El banner de [CNF-01] daba por hecha una tarjeta en Ajustes con anyadir y
    quitar. Se hizo la mitad: [USO-06] trajo "Excluir siempre esto" al menu
    contextual de la tabla, asi que hasta ahora el programa abria una puerta
    de un solo sentido y su propio dialogo tenia que avisar de que aquello
    solo se deshacia editando preferencias.json a mano.

    Lo que se protege aqui:

      1. La CLAVE no se pierde nunca. Lo que se ensenya y lo que se guarda
         son dos cosas distintas desde [ARQ-03] -"modulo:<Id>|<Nombre>" no es
         una ruta- y el boton de quitar tiene que llevar la de guardar. Si se
         quitara por el titulo, no encontraria nada que quitar.
      2. La cadena interna no llega a la pantalla. Ensenyar
         "modulo:dockerwsl|Cache de Docker" es pedirle al usuario que
         interprete un detalle de implementacion.
      3. La tarjeta VACIA dice algo util. Es la leccion de [USO-09]: un hueco
         en blanco se lee como un programa roto, y ademas el vacio es el
         estado normal del primero que abra Ajustes.
      4. Quitar actualiza las DOS listas -preferencias y configuracion- y
         guarda al momento, igual que anyadir.
      5. Quitar NO pregunta y anyadir SI. La asimetria se comprueba en los
         dos sentidos, porque una confirmacion que se cuela aqui es tan fallo
         como una que se pierda alli.

    Toda prueba de texto lleva su guarda previa, y el codigo se lee sin
    comentarios: las pruebas de texto encuentran los comentarios del propio
    arreglo, que en este repositorio ha pasado seis veces.
#>

BeforeAll {
    $script:Raiz      = Split-Path $PSScriptRoot -Parent
    $script:CarpetaUi = Join-Path (Join-Path $script:Raiz 'src') 'UI'

    . (Join-Path $script:CarpetaUi 'Types.ps1')
    Initialize-TiposInterfaz

    # El nucleo entero: hacen falta Get-ExclusionVista, Get-ClaveExclusion y
    # Test-ClaveExcluida, que son las tres piezas cuya coherencia se prueba.
    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')

    # Codigo sin comentarios: de linea (#), de bloque (<# #>) y de C# (///),
    # que es como estan comentadas las clases dentro de Types.ps1.
    function Get-CodigoSinComentarios {
        param([string] $Ruta)
        $lineas = @(Get-Content -LiteralPath $Ruta |
                    Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*///' })
        return [regex]::Replace(($lineas -join "`n"), '(?s)<#.*?#>', '')
    }

    $script:Ayudantes = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Ayudantes.ps1')
    $script:Eventos   = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.Eventos.ps1')
    $script:Ventana   = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Window.ps1')
    $script:Tipos     = Get-CodigoSinComentarios (Join-Path $script:CarpetaUi 'Types.ps1')

    # El XAML del panel sin sus comentarios <!-- -->, por lo mismo.
    $script:PanelAjustes = [regex]::Replace(
        (Get-Content -Raw -LiteralPath (Join-Path $script:CarpetaUi 'Panel.Ajustes.xaml')),
        '(?s)<!--.*?-->', '')

    # El bloque de la tarjeta, acotado: desde su titulo hasta el cierre del
    # Border. Se acota para que las pruebas de "aqui no hay mecanismos de
    # XAML" miren la tarjeta y no el panel entero, donde si hay estilos
    # legitimos.
    $script:TarjetaXaml = [regex]::Match($script:PanelAjustes,
        '(?s)<TextBlock Text="Lo que no se toca nunca".*?</ItemsControl>').Value

    $script:QuitarExclusion = [regex]::Match($script:Ayudantes,
        '(?s)\$quitarExclusion = \{.*?\n    \}').Value
    $script:RefrescarExclusiones = [regex]::Match($script:Ayudantes,
        '(?s)\$refrescarExclusiones = \{.*?\n    \}').Value
    $script:ManejadorQuitar = [regex]::Match($script:Eventos,
        '(?s)\$c\.ListaExclusiones\.AddHandler\(.*?\n        \}\)').Value
    $script:Excluir = [regex]::Match($script:Eventos,
        '(?s)\$c\.MenuExcluirSiempre\.Add_Click\(\{.*?\n        \}\)').Value

    # Las claves de las dos formas que existen de verdad, compuestas por la
    # MISMA funcion que las compone en el programa. Escribirlas a mano aqui
    # seria una tercera copia del formato, y entonces estas pruebas seguirian
    # pasando el dia que Get-ClaveExclusion cambiara de forma.
    $script:ClaveCarpeta = Get-ClaveExclusion -Ruta 'C:\Proyectos\web' -ModuloId 'proyectos' -Nombre 'web'
    $script:ClaveComando = Get-ClaveExclusion -Ruta 'docker system prune -a -f' `
                               -ModuloId 'dockerwsl' -Nombre 'Caché de Docker'
    $script:ClaveManual  = 'docker system prune'
}

Describe 'CNF-01: cada clave se presenta segun lo que es' {

    It 'devuelve los cuatro campos que la tarjeta necesita' {
        # Guarda: si el objeto cambiara de forma, las pruebas de abajo
        # compararian $null contra $null y pasarian todas.
        $r = Get-ExclusionVista -Clave $script:ClaveCarpeta
        foreach ($campo in @('Clave', 'Titulo', 'Detalle', 'Tipo')) {
            $r.PSObject.Properties.Name | Should -Contain $campo
        }
    }

    It 'las dos formas de clave existen de verdad y no se parecen' {
        # La otra guarda: si Get-ClaveExclusion devolviera lo mismo en los
        # dos casos, todo lo de abajo estaria probando un solo camino.
        $script:ClaveCarpeta | Should -Be 'C:\Proyectos\web'
        $script:ClaveComando | Should -Not -Be $script:ClaveCarpeta
        $script:ClaveComando | Should -Match '\|'
    }

    It 'una ruta se ensenya entera, no solo el ultimo tramo' {
        # Dos proyectos llamados "web" en carpetas distintas darian dos filas
        # identicas, y la lista existe justo para decidir cual sobra.
        $r = Get-ExclusionVista -Clave $script:ClaveCarpeta
        $r.Tipo   | Should -Be 'carpeta'
        $r.Titulo | Should -Be 'C:\Proyectos\web'
        $r.Detalle | Should -Match 'dentro'
    }

    It 'una clave sintetica ensenya el nombre, no la cadena interna' {
        $r = Get-ExclusionVista -Clave $script:ClaveComando
        $r.Tipo   | Should -Be 'modulo'
        $r.Titulo | Should -Be 'Caché de Docker'
        $r.Titulo | Should -Not -Match 'modulo:'
        $r.Titulo | Should -Not -Match '\|'
    }

    It 'y el detalle nombra el modulo, que es lo que las distingue' {
        # Dos modulos pueden traer un elemento con el mismo nombre. Si el Id
        # no se dijera en ningun sitio, dos exclusiones distintas serian dos
        # filas iguales y no habria forma de saber cual se quita.
        $r = Get-ExclusionVista -Clave $script:ClaveComando
        $r.Detalle | Should -Match 'dockerwsl'
        $r.Detalle | Should -Match 'no es una carpeta'
    }

    It 'lo escrito a mano se ensenya tal cual y dice hasta donde llega' {
        # Ni ruta ni clave sintetica: solo puede venir de editar
        # preferencias.json o de -Excluir en consola. Test-ClaveExcluida lo
        # compara por igualdad exacta, asi que callarlo dejaria al usuario
        # creyendo que excluye algo mas.
        $r = Get-ExclusionVista -Clave $script:ClaveManual
        $r.Tipo   | Should -Be 'texto'
        $r.Titulo | Should -Be $script:ClaveManual
        $r.Detalle | Should -Match 'exactamente'
    }

    It 'ningun titulo se queda en blanco' {
        # Una fila sin texto no se ve, y lo que no se ve no se puede quitar.
        foreach ($clave in @($script:ClaveCarpeta, $script:ClaveComando, $script:ClaveManual,
                             'modulo:dockerwsl|', 'modulo:|Algo', 'modulo:|', 'C:\', '\\equipo\recurso')) {
            $r = Get-ExclusionVista -Clave $clave
            $r         | Should -Not -BeNullOrEmpty -Because "'$clave' tiene contenido"
            $r.Titulo  | Should -Not -BeNullOrEmpty -Because "'$clave' se tiene que poder ver"
            $r.Detalle | Should -Not -BeNullOrEmpty
        }
    }

    It 'un nombre con barras verticales dentro llega entero' {
        # El Id no puede llevar la barra; el nombre si, y partir por la
        # primera dejaria el titulo a medias.
        $r = Get-ExclusionVista -Clave 'modulo:raro|Uno | Dos'
        $r.Titulo | Should -Be 'Uno | Dos'
    }

    It 'no revienta con nulo ni con blanco, y no ensenya una fila vacia' {
        { Get-ExclusionVista -Clave $null } | Should -Not -Throw
        Get-ExclusionVista -Clave $null  | Should -BeNullOrEmpty
        Get-ExclusionVista -Clave ''     | Should -BeNullOrEmpty
        Get-ExclusionVista -Clave '   '  | Should -BeNullOrEmpty
    }
}

Describe 'CNF-01: la clave que se ofrece quitar es la que compara el nucleo' {

    <#
        Esta es LA invariante del punto. Lo que se ensenya es texto para
        leer; lo que se quita tiene que ser la cadena exacta que esta
        guardada y que compara el motor de borrado. Si la presentacion
        recortara, normalizara o cambiara de mayusculas la clave, el boton
        pediria quitar algo que no esta en la lista y no quitaria nada: un
        boton que se pulsa y no hace nada es [USO-15] otra vez.
    #>

    It 'la clave vuelve identica, caracter por caracter' {
        foreach ($clave in @($script:ClaveCarpeta, $script:ClaveComando, $script:ClaveManual,
                             'C:\Proyectos\WEB', 'c:/proyectos/web/', 'modulo:dockerwsl|Caché de Docker')) {
            (Get-ExclusionVista -Clave $clave).Clave | Should -BeExactly $clave
        }
    }

    It 'lo que devuelve la presentacion sigue excluyendo lo mismo' {
        # El recorrido completo, sin texto de por medio: el candidato compone
        # su clave, la tarjeta la presenta, y la clave que sale de la tarjeta
        # se compara con la MISMA funcion que usan el embudo y el motor.
        foreach ($clave in @($script:ClaveCarpeta, $script:ClaveComando, $script:ClaveManual)) {
            $ofrecida = (Get-ExclusionVista -Clave $clave).Clave
            Test-ClaveExcluida -Clave $clave -Excluidas @($ofrecida) |
                Should -BeTrue -Because 'quitar de la lista lo que la tarjeta ensenya tiene que quitar ESA exclusion'
        }
    }

    It 'y el titulo NO sirve para excluir cuando la clave es sintetica' {
        # La razon de que Clave y Titulo esten separados. Si algun dia se
        # quitara por el titulo, esto es lo que pasaria.
        $vista = Get-ExclusionVista -Clave $script:ClaveComando
        Test-ClaveExcluida -Clave $script:ClaveComando -Excluidas @($vista.Titulo) |
            Should -BeFalse -Because 'el titulo es texto para leer, no la clave'
    }
}

Describe 'CNF-01: la tarjeta vacia dice algo util' {

    It 'con la lista vacia no se queda en blanco y dice como se llena' {
        # [USO-09]: un hueco donde deberia haber algo se lee como que el
        # programa ha perdido los datos. Y aqui el vacio es el estado normal
        # de cualquiera que abra Ajustes antes de excluir nada.
        $t = Get-TextoListaExclusiones -Cuantas 0
        $t | Should -Not -BeNullOrEmpty
        $t | Should -Match 'Excluir siempre esto'
        $t | Should -Match 'Resultados'
    }

    It 'un negativo se trata como vacio' {
        Get-TextoListaExclusiones -Cuantas -3 | Should -Be (Get-TextoListaExclusiones -Cuantas 0)
    }

    It 'no dice "1 elementos"' {
        # El fallo que ya salio en las cabeceras de grupo y en el historial.
        $uno = Get-TextoListaExclusiones -Cuantas 1
        $uno | Should -Match '1 elemento excluido'
        $uno | Should -Not -Match '1 elementos'
    }

    It 'con varios dice cuantos' {
        Get-TextoListaExclusiones -Cuantas 7 | Should -Match '7 elementos excluidos'
    }

    It 'los tres textos dicen que quitar de la lista no borra nada' {
        # De esto depende que el boton de quitar pueda no preguntar: la
        # tarjeta explica que la accion devuelve el elemento a estar
        # propuesto, no que destruya nada.
        foreach ($cuantas in @(0, 1, 7)) {
            Get-TextoListaExclusiones -Cuantas $cuantas |
                Should -Match 'quitar|Quitar' -Because 'la tarjeta tiene que decir que se puede quitar'
        }
        Get-TextoListaExclusiones -Cuantas 1 | Should -Match 'no borra nada'
        Get-TextoListaExclusiones -Cuantas 7 | Should -Match 'no borra nada'
    }
}

Describe 'CNF-01: la clase de la vista y la funcion no pueden divergir' {

    It 'ExclusionVista existe y se puede rellenar' {
        $fila = New-Object Cachivache.ExclusionVista
        $fila.Clave   = $script:ClaveComando
        $fila.Titulo  = 'Caché de Docker'
        $fila.Detalle = 'x'
        $fila.Tipo    = 'modulo'
        $fila.Clave | Should -BeExactly $script:ClaveComando
    }

    It 'la clase declara exactamente los campos que devuelve la funcion' {
        # Dos listas de campos separadas divergen, y aqui divergir significa
        # que un campo se calcula y no llega a la pantalla, en silencio.
        $devueltos = @((Get-ExclusionVista -Clave $script:ClaveCarpeta).PSObject.Properties.Name | Sort-Object)
        $declarados = @([regex]::Matches($script:Tipos,
                            '(?s)class ExclusionVista.*?\n    \}') |
                        ForEach-Object { [regex]::Matches($_.Value, 'public string (\w+)') } |
                        ForEach-Object { $_.Groups[1].Value } | Sort-Object)

        $declarados.Count | Should -BeGreaterThan 3 -Because 'si no, se leyo mal Types.ps1'
        ($declarados -join ',') | Should -Be ($devueltos -join ',')
    }
}

Describe 'CNF-01: la tarjeta de Ajustes ensenya la lista' {

    It 'la tarjeta esta en el panel: si no, esta prueba no mira nada' {
        $script:TarjetaXaml | Should -Not -BeNullOrEmpty
        $script:TarjetaXaml.Length | Should -BeGreaterThan 400
        $script:PanelAjustes | Should -Match 'Lo que no se toca nunca'
    }

    It 'tiene el rotulo del resumen y la lista' {
        $script:TarjetaXaml | Should -Match 'x:Name="TxtResumenExclusiones"'
        $script:TarjetaXaml | Should -Match 'x:Name="ListaExclusiones"'
    }

    It 'cada fila ensenya el titulo y el detalle' {
        $script:TarjetaXaml | Should -Match '\{Binding Titulo\}'
        $script:TarjetaXaml | Should -Match '\{Binding Detalle\}'
    }

    It 'el boton de quitar lleva la CLAVE en el Tag, no el titulo' {
        # Lo que se pulsa tiene que llevar lo que se guarda. Con el titulo
        # ahi, quitar una exclusion sintetica no encontraria nada.
        $boton = [regex]::Match($script:TarjetaXaml, '(?s)<Button x:Name="BtnQuitarExclusion".*?/>').Value
        $boton | Should -Not -BeNullOrEmpty
        $boton | Should -Match 'Tag="\{Binding Clave\}"'
        $boton | Should -Match 'Content="Quitar"'
    }

    It 'la tarjeta no decide nada con mecanismos de XAML' {
        # La regla de [USO-04] y [USO-09]: aqui no hay WPF con el que
        # comprobar un disparador, asi que no se deja ninguno. Lo que se ve
        # sale de una funcion pura y lo asigna la ventana.
        $script:TarjetaXaml | Should -Not -Match 'DataTrigger'
        $script:TarjetaXaml | Should -Not -Match 'Trigger'
        $script:TarjetaXaml | Should -Not -Match 'Converter'
        $script:TarjetaXaml | Should -Not -Match 'Visibility='
    }

    It 'los dos controles los resuelve la lista de siempre de Window.ps1' {
        # Y no una tabla propia: un segundo sitio donde resolver controles
        # deja fuera a la invariante que impide que $c y el XAML diverjan.
        # Es lo que hubo que corregir en [USO-09].
        $bloque = [regex]::Match($script:Ventana,
            '(?s)\$c = @\{\}.*?\$c\[\$nombre\] = \$ventana\.FindName').Value
        $bloque | Should -Not -BeNullOrEmpty
        $bloque | Should -Match "'TxtResumenExclusiones'"
        $bloque | Should -Match "'ListaExclusiones'"
    }

    It 'el rotulo sale de la funcion pura, no de un texto compuesto en la ventana' {
        $script:RefrescarExclusiones | Should -Not -BeNullOrEmpty
        $script:RefrescarExclusiones | Should -Match '\$c\.TxtResumenExclusiones\.Text = Get-TextoListaExclusiones'
        $script:RefrescarExclusiones | Should -Match 'Get-ExclusionVista -Clave'
    }

    It 'la ventana no interpreta la clave por su cuenta' {
        # Dos sitios partiendo la misma cadena es como se llega a ensenyar
        # una cosa y borrar otra. La forma de la clave la conoce
        # src/Core/Exclusiones.ps1 y nadie mas.
        $script:Ayudantes | Should -Match 'ExclusionVista' -Because 'si no, se leyo mal el archivo'
        foreach ($texto in @($script:Ayudantes, $script:Eventos, $script:Ventana, $script:Tipos)) {
            $texto | Should -Not -Match 'modulo:'
        }
    }

    It 'la lista se rellena en UN solo sitio' {
        @([regex]::Matches($script:Ayudantes, '\$c\.ListaExclusiones\.ItemsSource')).Count | Should -Be 1
    }

    It 'la tarjeta se rehace al abrir Ajustes' {
        $script:Eventos | Should -Match '\$c\.NavAjustes\.Add_Checked\(\{\s*& \$refrescarExclusiones'
    }
}

Describe 'CNF-01: quitar una exclusion' {

    It 'el cierre y su manejador estan ahi: si no, esto no mira nada' {
        $script:QuitarExclusion  | Should -Not -BeNullOrEmpty
        $script:QuitarExclusion.Length | Should -BeGreaterThan 300
        $script:ManejadorQuitar  | Should -Not -BeNullOrEmpty
    }

    It 'actualiza la lista de las preferencias Y la de la configuracion' {
        # Las dos, porque solo se sincronizan al refrescar los discos: sin la
        # segunda, el elemento seguiria rechazado por el motor en la limpieza
        # que el usuario esta a punto de lanzar, y la tarjeta estaria
        # diciendo que ya no lo esta.
        $script:QuitarExclusion | Should -Match '\$estado\.Preferencias\.RutasExcluidas\s*='
        $script:QuitarExclusion | Should -Match '\$estado\.Configuracion\.RutasExcluidas\s*='
    }

    It 'guarda en disco al momento, no al cerrar la ventana' {
        # Si "nunca mas" se escribe en cuanto se promete, retirarlo tambien
        # tiene que escribirse en cuanto se retira: un cierre anormal que
        # resucitara la exclusion es la misma promesa rota del reves.
        $script:QuitarExclusion | Should -Match '& \$guardarPreferencias'
    }

    It 'vuelve a pintar la tarjeta' {
        $script:QuitarExclusion | Should -Match '& \$refrescarExclusiones'
    }

    It 'compara la clave de forma exacta' {
        # La clave viene del Tag, o sea que es la misma cadena guardada.
        # Comparar sin distinguir mayusculas se llevaria por delante otra
        # entrada que solo se diferencie en eso, y el usuario veria
        # desaparecer una fila que no habia tocado.
        $script:QuitarExclusion | Should -Match 'StringComparison\]::Ordinal'
        $script:QuitarExclusion | Should -Not -Match 'OrdinalIgnoreCase'
    }

    It 'NO pregunta' {
        # La mitad de la asimetria que hay que vigilar por este lado: quitar
        # no destruye nada, devuelve el elemento a estar PROPUESTO, que es de
        # donde salio, y entre proponer y borrar siguen estando la casilla,
        # el dialogo de confirmacion y la guardia del motor. Ademas una
        # confirmacion que sale siempre se aprende a despachar sin leerla, y
        # entonces deja de proteger donde importa.
        $script:QuitarExclusion | Should -Not -Match 'MessageBox'
        $script:QuitarExclusion | Should -Not -Match 'YesNo'
    }

    It 'y anyadir SI pregunta' {
        # La otra mitad. Anyadir es una promesa de "nunca mas", y lo que deja
        # de proponerse no se ve: una exclusion puesta por error es invisible
        # justo despues de ponerla.
        $script:Excluir | Should -Not -BeNullOrEmpty
        $script:Excluir | Should -Match "'YesNo'"
        $script:Excluir | Should -Match "-ne 'Yes'\) \{ return \}"
    }

    It 'el boton se reconoce por su nombre, no por su rotulo' {
        # Mirar el Content ataria el comportamiento a la etiqueta: cambiar
        # "Quitar" por "Quitar de la lista" dejaria de quitar sin dar ningun
        # error.
        $script:ManejadorQuitar | Should -Match "\`$boton\.Name -ne 'BtnQuitarExclusion'"
        $script:ManejadorQuitar | Should -Not -Match '\$boton\.Content'
    }

    It 'el manejador pasa el Tag, que es la clave' {
        $script:ManejadorQuitar | Should -Match '& \$quitarExclusion \(\[string\]\$boton\.Tag\)'
    }

    It 'el dialogo de excluir ya no promete que solo se deshace a mano' {
        # Era verdad hasta hoy y ha dejado de serlo. Un aviso que sobrevive a
        # lo que describia es una mentira con mas credito que ninguna otra:
        # la escribio el propio programa.
        $script:Excluir | Should -Not -Match 'preferencias\.json'
        $script:Excluir | Should -Match 'Lo que no se toca nunca'
    }

    It 'restablecer los ajustes no se lleva por delante las exclusiones' {
        # La tarjeta vive dos dedos por encima de ese boton, asi que hay
        # motivo para temerlo. Ni lo hace ni lo dice a medias.
        $restablecer = [regex]::Match($script:Eventos,
            '(?s)\$c\.BtnRestablecer\.Add_Click\(\{.*?\n    \}\)').Value
        $restablecer | Should -Not -BeNullOrEmpty
        $restablecer | Should -Not -Match 'RutasExcluidas'
        $restablecer | Should -Match 'lo que hayas excluido no se tocan'
    }
}
