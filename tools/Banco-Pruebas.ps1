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
    si esto parece una VM, y sobre todo si una ruta cae dentro del banco.
    Aqui solo se ejecuta. Ese archivo se puede dot-sourcear sin consecuencias;
    este no, porque este crea y borra archivos.

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

    return [IO.Path]::GetFullPath((Join-Path $documentos (Get-NombreRaizBanco)))
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
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Ruta,
        [int] $KiloBytes = 4,
        [string] $Relleno = 'cebo'
    )

    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Crear archivo de prueba')) { return }

    $texto = $Relleno * [Math]::Max(1, [int](($KiloBytes * 1024) / [Math]::Max(1, $Relleno.Length)))
    [IO.File]::WriteAllText($Ruta, $texto)

    $antiguo = (Get-Date).AddDays(-400)
    [IO.File]::SetLastWriteTime($Ruta, $antiguo)
    [IO.File]::SetCreationTime($Ruta, $antiguo)
    [IO.File]::SetLastAccessTime($Ruta, $antiguo)
}

function New-BancoPruebas {
    <#
    .SYNOPSIS
        Monta todos los cebos.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Raiz)

    if (-not $PSCmdlet.ShouldProcess($Raiz, 'Montar el banco de pruebas')) { return }

    [void][IO.Directory]::CreateDirectory($Raiz)
    Write-Host "Banco en: $Raiz" -ForegroundColor Cyan

    # --- 1. Temporales corrientes: el camino normal a la papelera --------
    $normales = Join-Path $Raiz '01-temporales'
    [void][IO.Directory]::CreateDirectory($normales)
    foreach ($n in 1..8) {
        New-ArchivoDeCebo -Ruta (Join-Path $normales ('documento-{0}.bak' -f $n)) -KiloBytes 64
        New-ArchivoDeCebo -Ruta (Join-Path $normales ('version-{0}.old' -f $n)) -KiloBytes 32
    }
    Write-Host '  01-temporales: 16 archivos .bak y .old' -ForegroundColor DarkGray

    # --- 2. Ruta de mas de 260 caracteres [COR-02] -----------------------
    #
    # Se construye por tramos y con el prefijo \\?\ porque en PowerShell 5.1
    # el proveedor de archivos NO admite rutas largas: New-Item falla. Es el
    # mismo prefijo que usa el programa en Get-ResumenArbol.
    $largo = Join-Path $Raiz '02-ruta-larga'
    $acumulado = $largo
    foreach ($n in 1..12) {
        $acumulado = Join-Path $acumulado ('carpeta-anidada-con-nombre-largo-numero-{0:00}' -f $n)
    }
    [void][IO.Directory]::CreateDirectory('\\?\' + $acumulado)
    $archivoLargo = Join-Path $acumulado 'copia-antigua.bak'
    [IO.File]::WriteAllText('\\?\' + $archivoLargo, ('relleno' * 4096))
    [IO.File]::SetLastWriteTime('\\?\' + $archivoLargo, (Get-Date).AddDays(-400))
    Write-Host ('  02-ruta-larga: {0} caracteres' -f $archivoLargo.Length) -ForegroundColor DarkGray

    # --- 3. Un archivo grande, para la cuota de la papelera [COR-01] -----
    #
    # 200 MB. Por si solo no desborda ninguna papelera: hay que BAJAR la
    # cuota de la papelera de la VM a 100 MB a mano, y eso esta en el paso
    # 4 de docs/BANCO-PRUEBAS.md. Se hace asi y no creando un archivo de
    # varios gigas porque el fallo que se quiere ver es "no cabe", y "no
    # cabe" se consigue igual moviendo el techo que el suelo.
    $grande = Join-Path $Raiz '03-mas-grande-que-la-papelera'
    [void][IO.Directory]::CreateDirectory($grande)
    $rutaGrande = Join-Path $grande 'copia-enorme.bak'
    $bloque = [byte[]]::new(1MB)
    $flujo = [IO.File]::Create($rutaGrande)
    try {
        foreach ($n in 1..200) { $flujo.Write($bloque, 0, $bloque.Length) }
    } finally {
        $flujo.Dispose()
    }
    [IO.File]::SetLastWriteTime($rutaGrande, (Get-Date).AddDays(-400))
    Write-Host '  03-mas-grande-que-la-papelera: 200 MB' -ForegroundColor DarkGray

    # --- 4. Enlaces duros [VIS-03] ---------------------------------------
    #
    # Dos entradas de directorio, un solo contenido. Medir la carpeta tiene
    # que dar 20 MB, no 40. Un enlace duro NO necesita administrador; un
    # enlace simbolico si, y por eso aqui se usan duros.
    $duros = Join-Path $Raiz '04-enlaces-duros'
    [void][IO.Directory]::CreateDirectory($duros)
    $original = Join-Path $duros 'original.bak'
    $flujo = [IO.File]::Create($original)
    try {
        foreach ($n in 1..20) { $flujo.Write($bloque, 0, $bloque.Length) }
    } finally {
        $flujo.Dispose()
    }
    [IO.File]::SetLastWriteTime($original, (Get-Date).AddDays(-400))
    $enlace = Join-Path $duros 'mismo-contenido-otro-nombre.bak'
    New-Item -ItemType HardLink -Path $enlace -Target $original -ErrorAction Stop | Out-Null
    Write-Host '  04-enlaces-duros: 20 MB reales, dos nombres' -ForegroundColor DarkGray

    # --- 5. Duplicados de verdad [55-Duplicados] -------------------------
    #
    # Mismo contenido, ficheros independientes: aqui SI se libera espacio al
    # borrar uno, al reves que en el caso de arriba. Los dos juntos son la
    # prueba de que el programa distingue.
    $dobles = Join-Path $Raiz '05-duplicados'
    [void][IO.Directory]::CreateDirectory($dobles)
    foreach ($n in 1..2) {
        New-ArchivoDeCebo -Ruta (Join-Path $dobles ('informe-copia-{0}.bak' -f $n)) `
                          -KiloBytes 512 -Relleno 'contenido-identico-'
    }
    Write-Host '  05-duplicados: dos archivos identicos de 512 KB' -ForegroundColor DarkGray

    # --- 6. Carpetas vacias [40-CarpetasVacias] --------------------------
    $vacias = Join-Path $Raiz '06-carpetas-vacias'
    foreach ($n in 1..5) {
        [void][IO.Directory]::CreateDirectory((Join-Path $vacias ('vacia-{0}' -f $n)))
    }
    Write-Host '  06-carpetas-vacias: 5' -ForegroundColor DarkGray

    # --- 7. Relleno: miles de filas [USO-01] y [VEL-03] ------------------
    if ($ArchivosDeSobra -gt 0) {
        $muchos = Join-Path $Raiz '07-muchas-filas'
        [void][IO.Directory]::CreateDirectory($muchos)
        $antiguo = (Get-Date).AddDays(-400)
        foreach ($n in 1..$ArchivosDeSobra) {
            $r = Join-Path $muchos ('sobra-{0:00000}.tmp' -f $n)
            [IO.File]::WriteAllText($r, 'x')
            [IO.File]::SetLastWriteTime($r, $antiguo)
        }
        Write-Host ('  07-muchas-filas: {0} archivos .tmp' -f $ArchivosDeSobra) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host 'Montado. Sigue docs/BANCO-PRUEBAS.md desde el paso 5.' -ForegroundColor Green
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
    $hijos = @(Get-ChildItem -LiteralPath $Raiz -Recurse -Force -ErrorAction SilentlyContinue |
               Sort-Object { $_.FullName.Length } -Descending)

    foreach ($hijo in $hijos) {
        if (-not (Test-DentroDeRaiz -Ruta $hijo.FullName -Raiz $Raiz)) {
            throw ("Algo esta fuera del banco y no se toca: $($hijo.FullName)")
        }
        [IO.File]::SetAttributes($hijo.FullName, [IO.FileAttributes]::Normal)
        if ($hijo.PSIsContainer) {
            [IO.Directory]::Delete('\\?\' + $hijo.FullName, $false)
        } else {
            [IO.File]::Delete('\\?\' + $hijo.FullName)
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

New-BancoPruebas -Raiz $raiz
