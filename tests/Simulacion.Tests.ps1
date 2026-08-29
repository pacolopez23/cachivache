BeforeAll {
    . (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core') 'Format.ps1')
}

Describe 'La simulación tiene que decir lo que ha hecho' {
    <#
        [USO-15]. La simulación corria entera y solo escribia en el panel de
        Registro. Quien la pulsa esta mirando la tabla de Resultados, donde
        no cambiaba absolutamente nada. En la primera prueba real el usuario
        pulso el boton TRES VECES seguidas creyendo que estaba roto; el
        registro demostraba que habia hecho las tres.
    #>

    It 'dice cuantos y cuanto' {
        $texto = Format-ResumenSimulacion -Simulados 33 -Liberado 10553584517
        $texto | Should -Match '33 elementos'
        $texto | Should -Match ([regex]::Escape((Format-Tamano 10553584517)))
    }

    It 'deja claro que NO se ha borrado nada' {
        # Es lo primero que hay que poder leer sin leerlo entero: alguien
        # que mire de reojo tiene que quedarse con esto y no con la cifra.
        $texto = Format-ResumenSimulacion -Simulados 33 -Liberado 1024
        $texto | Should -Match 'NO se ha borrado nada'
    }

    It 'dice que hacer ahora' {
        $texto = Format-ResumenSimulacion -Simulados 5 -Liberado 1024
        $texto | Should -Match 'Solo simular'
    }

    It 'cuenta los que no se habrian podido borrar' {
        # Callarlos seria volver a prometer un espacio que no llega, que es
        # el fallo que cerro [COR-01].
        $texto = Format-ResumenSimulacion -Simulados 33 -Liberado 1024 -Bloqueados 4
        $texto | Should -Match '4 no se habrian borrado'
        $texto | Should -Match 'BLOQUEADO'
    }

    It 'y no los menciona cuando no hay ninguno' {
        $texto = Format-ResumenSimulacion -Simulados 33 -Liberado 1024 -Bloqueados 0
        $texto | Should -Not -Match 'BLOQUEADO'
    }

    It 'habla en singular cuando es uno' {
        $texto = Format-ResumenSimulacion -Simulados 1 -Liberado 1024 -Bloqueados 1
        $texto | Should -Match '1 elemento\b'
        $texto | Should -Not -Match '1 elementos'
        $texto | Should -Match '1 no se habria borrado'
    }

    It 'con cero marcados no promete nada' {
        $texto = Format-ResumenSimulacion -Simulados 0 -Liberado 0
        $texto | Should -Match 'no habia nada que borrar'
        $texto | Should -Not -Match '0 elementos'
    }

    It 'nunca se queda un hueco de formato sin rellenar' {
        # El '-f' se enlaza mas fuerte que el '+': 'texto {0}' + 'mas' -f $x
        # deja el {0} literal en pantalla. Ya paso dos veces en este
        # proyecto y las pruebas no lo vieron porque buscaban un trozo que
        # existia en las dos versiones.
        foreach ($caso in @(@(0,0,0), @(1,1024,0), @(33,99999,4))) {
            $texto = Format-ResumenSimulacion -Simulados $caso[0] -Liberado $caso[1] -Bloqueados $caso[2]
            $texto | Should -Not -Match '\{\d+\}'
        }
    }
}
