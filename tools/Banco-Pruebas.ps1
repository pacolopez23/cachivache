<#
.SYNOPSIS
    Monta y quita el banco de pruebas de Cachivache. EJECUTAR SOLO EN UNA
    MAQUINA VIRTUAL CON INSTANTANEA.

.DESCRIPTION
    Cachivache lleva tres puntos cerrados que nadie ha visto funcionar:
    la papelera que no cabe ([COR-01]), las rutas de mas de 260 caracteres
    ([COR-02]) y los archivos de OneDrive bajo demanda ([COR-03]). Los tres
    solo se ejercitan AL BORRAR DE VERDAD, y un borrado de verdad no se
    ensaya sobre las carpetas propias.

    Este guion monta cebos deterministas dentro de Documentos, en una
    carpeta suya, para que los modulos los encuentren y se pueda hacer una
    limpieza real y medir si el programa hizo lo que dijo. Cada cebo existe
    para una afirmacion concreta que hoy no esta comprobada; docs/BANCO-PRUEBAS.md
    dice cual y que tiene que pasar.

    POR QUE DENTRO DE DOCUMENTOS Y NO EN UNA CARPETA CUALQUIERA
    ----------------------------------------------------------
    Porque si no, no sirve. Los modulos no recorren el disco entero: miran
    las ZonasUsuario -Escritorio, Documentos, Descargas, Imagenes, Musica,
    Videos, OneDrive-. Un cebo en C:\pruebas no lo encuentra nadie, y una
    prueba que el programa no llega a ver no prueba nada.

    Ese es exactamente el motivo de que esto pida una VM: para ser util
    tiene que ponerse donde duele.

    LAS DECISIONES ESTAN EN OTRO ARCHIVO
    ------------------------------------
    Banco-Decisiones.ps1 es calculo puro y va probado: donde esta el banco,
    si esto parece una VM, si una ruta cae dentro del banco, y desde
    [VAL-03] tambien EL CATALOGO DE CEBOS. Aqui solo se ejecuta. Ese archivo
    se puede dot-sourcear sin consecuencias; este no, porque este crea y
    borra archivos.

    QUE NOMBRE PUEDE LLEVAR UN CEBO
    -------------------------------
    Uno que la guardia no confunda con trabajo del usuario. Parece un
    detalle y era el fallo mas grave que tenia el banco: "copia-enorme.bak",
    "copia-antigua.bak" y "documento-1.bak" empiezan por una palabra de
    Test-ArchivoPersonal, asi que NINGUN modulo llegaba a proponerlos y los
    cebos de [COR-01] y [COR-02] -las dos afirmaciones que el banco existe
    para comprobar- eran invisibles. Los nombres estan ahora en el catalogo,
    con una invariante que se lo pregunta a la guardia de verdad.

.PARAMETER Quitar
    Borra el banco entero en vez de montarlo.

.PARAMETER AunqueNoSeaVirtual
    Salta la comprobacion de maquina virtual. Existe para que la respuesta
    a "no me deja" sea una decision escrita y no un rodeo.

.PARAMETER ArchivosDeSobra
    Cuantos archivos temporales de relleno crear, para la prueba de
    desplazamiento con miles de filas ([USO-01]) y la de marcar en lote
    ([VEL-03]). Por defecto 3000.

.EXAMPLE
    .\Banco-Pruebas.ps1 -WhatIf
    Ensenya lo que haria sin tocar nada. Empieza siempre por aqui.

.EXAMPLE
    .\Banco-Pruebas.ps1
    Monta el banco.

.EXAMPLE
    .\Banco-Pruebas.ps1 -Quitar
    Lo quita. Aun asi, restaura la instantanea: lo que borro Cachivache no
    lo devuelve este guion.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch] $Quitar,
    [switch] $AunqueNoSeaVirtual,
    [ValidateRange(0, 50000)]
    [int] $ArchivosDeSobra = 3000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Banco-Decisiones.ps1')

# ---------------------------------------------------------------------
#  Donde vive el banco
# ---------------------------------------------------------------------

function Get-RaizBanco {
    <#
    .SYNOPSIS
        La carpeta del banco, ya resuelta a ruta absoluta.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # MyDocuments y no "$env:USERPROFILE\Documents": con OneDrive activo,
    # Documentos esta redirigido y las dos rutas son distintas. La que
    # importa es la que ve Cachivache, y Cachivache usa esta misma API.
    $documentos = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if ([string]::IsNullOrWhiteSpace($documentos)) { return $null }

    $compuesta = Get-RutaRaizBanco -Documentos $documentos
    if ([string]::IsNullOrWhiteSpace($compuesta)) { return $null }
    return [IO.Path]::GetFullPath($compuesta)
}

function Get-DescripcionEquipo {
    <#
    .SYNOPSIS
        Fabricante y modelo, para saber si esto es una maquina virtual.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        # CimInstance y no Get-WmiObject: el segundo no existe en
        # PowerShell 7, y este guion tiene que correr en los dos.
        $s = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return @{ Fabricante = [string]$s.Manufacturer; Modelo = [string]$s.Model }
    } catch {
        # Si no se puede preguntar, no se puede afirmar que sea virtual, y
        # la red se cierra. Que es lo que queremos.
        Write-Verbose "No se ha podido leer Win32_ComputerSystem: $($_.Exception.Message)"
        return @{ Fabricante = ''; Modelo = '' }
    }
}

# ---------------------------------------------------------------------
#  Los cebos
# ---------------------------------------------------------------------

function New-ArchivoDeCebo {
    <#
    .SYNOPSIS
        Un archivo de tamanyo dado y fecha antigua.

    .DESCRIPTION
        La fecha importa: el modulo de temporales NO propone un .tmp
        escrito hace menos de treinta minutos, porque puede estar en uso
        ahora mismo. Un cebo recien creado no aparecería en la lista y
        pareceria que el modulo no funciona.

        Dos formas de escribir, segun el tamanyo. Hasta 1 MB se repite el
        texto de relleno, que es lo que hace falta para que dos cebos
        salgan identicos byte a byte y el modulo de duplicados los empareje.
        A partir de ahi se escribe por bloques: el cebo de la papelera son
        200 MB, y componer 200 MB de texto en memoria para escribirlos de
        una vez es la forma de quedarse sin memoria montando un banco.

        El prefijo de ruta larga va SIEMPRE. Es inocuo para una ruta corta
        -la API lo acepta igual- y es lo unico que permite crear el cebo de
        [COR-02], que pasa de 260 caracteres y con el que New-Item y
        Set-Content de PowerShell 5.1 fallan.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [int] $KiloBytes = 4,
        [string] $Relleno = 'cebo'
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Crear archivo de prueba')) { return }

    $largo = '\\?\' + $Ruta

    if ($KiloBytes -le 1024) {
        # Al menos un byte: un cebo de cero bytes no lo propone nadie.
        $veces = [Math]::Max(1, [int](($KiloBytes * 1024) / [Math]::Max(1, $Relleno.Length)))
        [IO.File]::WriteAllText($largo, ($Relleno * $veces))
    } else {
        $bloque = [byte[]]::new(1MB)
        $flujo  = [IO.File]::Create($largo)
        try {
            foreach ($n in 1..[int]($KiloBytes / 1024)) { $flujo.Write($bloque, 0, $bloque.Length) }
        } finally {
            $flujo.Dispose()
        }
    }

    $antiguo = (Get-Date).AddDays(-400)
    [IO.File]::SetLastWriteTime($largo, $antiguo)
    [IO.File]::SetCreationTime($largo, $antiguo)
    [IO.File]::SetLastAccessTime($largo, $antiguo)
}

function New-BancoPruebas {
    <#
    .SYNOPSIS
        Monta todos los cebos del catalogo.

    .DESCRIPTION
        No hay ni una ruta ni un nombre escritos aqui: todo sale de
        Get-CebosBanco, que es calculo puro y va probado. Antes estaban
        escritos a mano en esta funcion, y por eso nadie podia preguntarle
        al banco "que tenia que haber salido en el analisis" sin volver a
        escribir la lista. Ver [VAL-03].
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Raiz,
        [ValidateRange(0, 50000)]
        [int] $DeSobra = 3000
    )

    if (-not $PSCmdlet.ShouldProcess($Raiz, 'Montar el banco de pruebas')) { return }

    [void][IO.Directory]::CreateDirectory($Raiz)
    Write-Host "Banco en: $Raiz" -ForegroundColor Cyan

    foreach ($cebo in (Get-CebosBanco -ArchivosDeSobra $DeSobra)) {
        if ([int]$cebo.Cuantos -le 0) { continue }

        for ($n = 1; $n -le [int]$cebo.Cuantos; $n++) {
            $ruta = Get-RutaCebo -Cebo $cebo -Raiz $Raiz -Indice $n

            if ($cebo.EsCarpeta) {
                [void][IO.Directory]::CreateDirectory('\\?\' + $ruta)
                continue
            }

            # La carpeta se crea con el prefijo por el cebo de ruta larga:
            # doce niveles anidados pasan de 260 caracteres y
            # [IO.Directory]::CreateDirectory sin prefijo lanza.
            $carpeta = $ruta.Substring(0, $ruta.LastIndexOf('\'))
            [void][IO.Directory]::CreateDirectory('\\?\' + $carpeta)

            if (-not [string]::IsNullOrWhiteSpace($cebo.EnlaceA)) {
                # Dos entradas de directorio, un solo contenido: es el cebo
                # de [VIS-03]. Un enlace duro NO necesita administrador; un
                # enlace simbolico si, y por eso aqui se usan duros.
                $destino = Join-Path $carpeta $cebo.EnlaceA
                New-Item -ItemType HardLink -Path $ruta -Target $destino -ErrorAction Stop | Out-Null
                continue
            }

            New-ArchivoDeCebo -Ruta $ruta -KiloBytes ([int]$cebo.KiloBytes) `
                              -Relleno ([string]$cebo.Relleno)
        }

        Write-Host ('  {0,-16} {1,6} en {2}   {3}' -f `
                    $cebo.Id, $cebo.Cuantos, $cebo.Carpeta, $cebo.Para) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host 'Montado. Sigue docs/BANCO-PRUEBAS.md desde el paso 5.' -ForegroundColor Green
}

function ConvertFrom-PrefijoLargo {
    <#
    .SYNOPSIS
        Quita el "\\?\" de una ruta. La misma regla que ConvertFrom-RutaLarga
        del nucleo, escrita aqui porque el banco no carga el nucleo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Ruta)

    if ($Ruta.StartsWith('\\?\')) { return $Ruta.Substring(4) }
    return $Ruta
}

function Get-ContenidoBanco {
    <#
    .SYNOPSIS
        Todo lo que hay dentro del banco, de lo mas profundo a lo mas
        superficial, incluida la ruta larga.

    .DESCRIPTION
        Se recorre con una pila propia y DirectoryInfo sobre el prefijo
        "\\?\", igual que Get-ResumenArbol, y NO con Get-ChildItem -Recurse.
        No es una preferencia de estilo: en Windows PowerShell 5.1
        Get-ChildItem -Recurse se para al llegar a 260 caracteres y bajo
        -ErrorAction SilentlyContinue no dice nada. O sea que el cebo de
        [COR-02] -y las doce carpetas que lo cuelgan- NO aparecian en la
        lista, -Quitar no los borraba, y despues fallaba al intentar borrar
        una carpeta que creia vacia y no lo estaba. El banco no se podia
        desmontar entero, que es justo el ingrediente que hacia falta para
        ejecutarlo en cada push.

        Devuelve rutas SIN el prefijo: el prefijo entra en las llamadas a
        la API y no sale de ahi, que es la regla de [COR-02].
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string] $Raiz)

    $encontrados = [Collections.Generic.List[string]]::new()
    $pendientes  = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pendientes.Push([IO.DirectoryInfo]::new('\\?\' + $Raiz))

    while ($pendientes.Count -gt 0) {
        $actual = $pendientes.Pop()
        foreach ($archivo in $actual.EnumerateFiles()) {
            $encontrados.Add((ConvertFrom-PrefijoLargo -Ruta $archivo.FullName))
        }
        foreach ($sub in $actual.EnumerateDirectories()) {
            $encontrados.Add((ConvertFrom-PrefijoLargo -Ruta $sub.FullName))
            $pendientes.Push($sub)
        }
    }

    # De mas larga a mas corta: asi una carpeta siempre se borra despues de
    # su contenido y nunca hace falta un borrado recursivo.
    return @($encontrados | Sort-Object -Property Length -Descending)
}

function Remove-BancoPruebas {
    <#
    .SYNOPSIS
        Quita el banco. Solo el banco.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)] [string] $Raiz)

    if (-not $PSCmdlet.ShouldProcess($Raiz, 'Borrar el banco de pruebas')) { return }

    # Se borra de dentro hacia fuera y comprobando CADA ruta contra la raiz,
    # en vez de un Remove-Item -Recurse a secas. Parece paranoia y no lo es:
    # es la unica forma de que un error en el calculo de la raiz no se
    # convierta en un borrado recursivo de otra carpeta. Ver Test-DentroDeRaiz.
    foreach ($hijo in (Get-ContenidoBanco -Raiz $Raiz)) {
        if (-not (Test-DentroDeRaiz -Ruta $hijo -Raiz $Raiz)) {
            throw ("Algo esta fuera del banco y no se toca: $hijo")
        }
        $largo = '\\?\' + $hijo
        if ([IO.Directory]::Exists($largo)) {
            # Sin recursion: Get-ContenidoBanco devuelve de mas profundo a
            # menos profundo, asi que cuando le toca a una carpeta ya no
            # queda nada dentro. Un borrado recursivo aqui haria inutil la
            # comprobacion ruta a ruta de arriba.
            [IO.Directory]::Delete($largo, $false)
        } else {
            # Solo a los archivos: un cebo de solo lectura no se puede
            # borrar, y quitarle los atributos a una carpeta no hace falta.
            [IO.File]::SetAttributes($largo, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($largo)
        }
    }

    [IO.Directory]::Delete('\\?\' + $Raiz, $false)
    Write-Host "Banco quitado: $Raiz" -ForegroundColor Green
    Write-Host 'Esto NO devuelve lo que borro Cachivache. Restaura la instantanea.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
#  Ejecucion
# ---------------------------------------------------------------------

$raiz = Get-RaizBanco
if (-not $raiz) {
    throw 'No se ha podido encontrar la carpeta Documentos de este usuario.'
}

$existe = [IO.Directory]::Exists($raiz)

if ($Quitar) {
    $motivo = Get-MotivoNoQuitarBanco -Raiz $raiz -Existe:$existe
    if ($motivo) {
        Write-Host $motivo -ForegroundColor Yellow
        return
    }
    Remove-BancoPruebas -Raiz $raiz
    return
}

$equipo = Get-DescripcionEquipo
$virtual = Test-PareceMaquinaVirtual -Fabricante $equipo.Fabricante -Modelo $equipo.Modelo

$ocupada = $existe -and
           @(Get-ChildItem -LiteralPath $raiz -Force -ErrorAction SilentlyContinue).Count -gt 0

$motivo = Get-MotivoNoMontarBanco -PareceVirtual:$virtual -Forzado:$AunqueNoSeaVirtual -RaizOcupada:$ocupada
if ($motivo) {
    Write-Host $motivo -ForegroundColor Yellow
    return
}

New-BancoPruebas -Raiz $raiz -DeSobra $ArchivosDeSobra
