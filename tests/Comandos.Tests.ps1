<#
    Pruebas de Comandos.ps1: que programas externos puede llegar a lanzar
    el programa y de donde salen.

    Vivian en Remove.Tests.ps1 porque la lista blanca vivia en Remove.ps1.
    Al sacarla a su propio archivo, sus pruebas se mudan con ella: un test
    que no esta donde esta el código que prueba es un test que nadie
    encuentra cuando toca.
#>

BeforeAll {
    $script:Raiz = Split-Path $PSScriptRoot -Parent

    # Entorno reproducible: la resolucion de Docker esta anclada a las
    # carpetas de Archivos de programa, que en Linux no existen.
    $env:ProgramFiles = 'C:\Program Files'
    ${env:ProgramFiles(x86)} = 'C:\Program Files (x86)'

    . (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Bootstrap.ps1')
}

Describe 'Resolve-EjecutablePermitido (C-03)' {

    It 'devuelve $null para una cadena vacia' {
        Resolve-EjecutablePermitido -Ejecutable '' | Should -BeNullOrEmpty
    }

    It 'devuelve $null para un ejecutable fuera de la lista blanca' {
        Resolve-EjecutablePermitido -Ejecutable 'powershell' | Should -BeNullOrEmpty
        Resolve-EjecutablePermitido -Ejecutable 'cmd' | Should -BeNullOrEmpty
        Resolve-EjecutablePermitido -Ejecutable 'evil' | Should -BeNullOrEmpty
    }

    It 'resuelve "dism" a la ruta real bajo System32, no a una ruta arbitraria' {
        # Aunque el candidato declare una ruta de otro sitio, el criterio de
        # 'dism' NUNCA se fia de ella: solo mira el nombre base y resuelve
        # siempre bajo System32 del propio $env:SystemRoot. Se fabrica un
        # SystemRoot de prueba con un Dism.exe de mentira para no depender
        # de que este test corra en Windows de verdad.
        #
        # El archivo se coloca en la MISMA ruta que calcula el propio
        # código (Join-Path $env:SystemRoot 'System32\Dism.exe'): en Linux
        # ese segundo argumento con barra invertida no se trata como dos
        # niveles de carpeta, sino como un único nombre literal, así que
        # crear las carpetas "a mano" con barra normal no coincidiria.
        $raizPrueba = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        $dismDeMentira = Join-Path $raizPrueba 'System32\Dism.exe'
        New-Item -ItemType Directory -Path (Split-Path $dismDeMentira -Parent) -Force | Out-Null
        Set-Content -LiteralPath $dismDeMentira -Value 'no es un ejecutable de verdad'

        $anterior = $env:SystemRoot
        try {
            $env:SystemRoot = $raizPrueba
            # Se declara una ruta completamente distinta: el resolver debe
            # ignorarla y devolver solo la ruta de confianza bajo System32.
            Resolve-EjecutablePermitido -Ejecutable 'C:\otra\carpeta\cualquiera\dism.exe' |
                Should -Be $dismDeMentira
        } finally {
            $env:SystemRoot = $anterior
            Remove-Item -LiteralPath $raizPrueba -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'devuelve $null para "dism" si no existe bajo System32' {
        $raizPrueba = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $raizPrueba -Force | Out-Null
        $anterior = $env:SystemRoot
        try {
            $env:SystemRoot = $raizPrueba
            Resolve-EjecutablePermitido -Ejecutable 'dism' | Should -BeNullOrEmpty
        } finally {
            $env:SystemRoot = $anterior
            Remove-Item -LiteralPath $raizPrueba -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'resuelve "docker" contra Archivos de programa, nunca por PATH' {
        # Antes se resolvia con Get-Command, o sea por PATH, y el PATH de
        # cualquier usuario incluye %LOCALAPPDATA%\Microsoft\WindowsApps,
        # que el propio usuario puede escribir. Ver [SEG-30].
        $esperada = $env:ProgramFiles + '\Docker\Docker\resources\bin\docker.exe'
        Mock Test-Path { $LiteralPath -eq $esperada }

        Resolve-EjecutablePermitido -Ejecutable 'docker' | Should -Be $esperada
    }

    It 'devuelve $null si Docker no esta instalado en ninguna ruta conocida' {
        Mock Test-Path { $false }
        Resolve-EjecutablePermitido -Ejecutable 'docker' | Should -BeNullOrEmpty
    }

    It 'no consulta Get-Command para resolver nada de la lista blanca' {
        # La cabecera del archivo prometia "ninguna de las dos consulta
        # jamas el PATH" mientras dos ramas lo consultaban. Esta prueba
        # convierte la promesa en algo verificable.
        Mock Get-Command { throw 'Resolve-EjecutablePermitido no debe consultar el PATH' }
        Mock Test-Path { $false }

        { Resolve-EjecutablePermitido -Ejecutable 'docker' } | Should -Not -Throw
        { Resolve-EjecutablePermitido -Ejecutable 'dism' }   | Should -Not -Throw
    }

    It 'npm ya no esta en la lista blanca: se elimino con el metodo NpmClean' {
        # Resolver "npm" devolvia npm.cmd, un script por lotes, y ejecutar
        # un .cmd pasa por cmd.exe siempre: la lista blanca reintroducia el
        # interprete que [C-03] habia quitado. Ver [SEG-21].
        Resolve-EjecutablePermitido -Ejecutable 'npm' | Should -BeNullOrEmpty
    }

    It 'nada fuera de la lista blanca se resuelve, ni siquiera con ruta absoluta' {
        foreach ($prohibido in @(
                'powershell', 'cmd', 'node', 'python', 'git', 'wget', 'curl', 'rundll32',
                'C:\Windows\System32\cmd.exe', 'C:\Users\x\node.exe')) {
            Resolve-EjecutablePermitido -Ejecutable $prohibido |
                Should -BeNullOrEmpty -Because "'$prohibido' no esta en la lista blanca"
        }
    }

    It 'todo nombre de la lista blanca tiene su rama de resolucion' {
        # Un nombre en la lista sin rama en el switch devolveria $null
        # siempre: pasaria el filtro y luego fallaria en silencio. Esta
        # prueba obliga a tocar las dos cosas a la vez.
        $texto = Get-Content (Join-Path (Join-Path (Join-Path $script:Raiz 'src') 'Core') 'Comandos.ps1') -Raw
        $lista = [regex]::Match($texto, '\$script:EjecutablesPermitidos\s*=\s*@\(([^)]*)\)')
        $lista.Success | Should -BeTrue -Because 'sin encontrar la lista, esta prueba no comprueba nada'
        $nombres = @([regex]::Matches($lista.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $nombres.Count | Should -BeGreaterThan 0
        $switch = [regex]::Match($texto, '(?s)switch \(\$nombre\) \{.*?\n    \}')
        foreach ($n in $nombres) {
            $switch.Value | Should -Match "'$n'" -Because "'$n' esta permitido pero no tiene rama que lo resuelva"
        }
    }
}
