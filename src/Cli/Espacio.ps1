<#
.SYNOPSIS
    Modo "¿dónde se fue el espacio?" en consola: el árbol de carpetas por
    tamaño y la lista de archivos mayores.

.DESCRIPTION
    Es la mitad que le faltaba al programa. Cachivache sabía encontrar
    basura; no sabía enseñar el disco, que es justo lo que hacen WizTree y
    WinDirStat y por lo que mucha gente tiene dos programas instalados.

    Aquí sale en consola. La misma información alimentará el mapa de árbol
    de la ventana: el índice y la geometría ya están en el núcleo
    (`Indice.ps1` y `Mapa.ps1`), y son cálculo puro y probado. Lo que falta
    para la ventana es el dibujado.

    NO BORRA NADA, ni lo propone. Es un informe.
#>

function Write-BarraProporcion {
    <#
    .SYNOPSIS
        Barra de texto proporcional a una fracción.
    .DESCRIPTION
        El equivalente en consola de un rectángulo del mapa: se ve de un
        vistazo qué se lleva el espacio, sin leer los números.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([double] $Parte, [double] $Total, [int] $Ancho = 24)

    if ($Total -le 0) { return ''.PadRight($Ancho) }
    $llenos = [int][Math]::Round($Ancho * ($Parte / $Total))
    if ($llenos -lt 0)      { $llenos = 0 }
    if ($llenos -gt $Ancho) { $llenos = $Ancho }

    # Caracteres de bloque de la tabla de dibujo: se ven igual en la
    # consola clasica y en la nueva.
    return ([string][char]0x2588 * $llenos) + ([string][char]0x2591 * ($Ancho - $llenos))
}

function Show-InformeEspacio {
    <#
    .SYNOPSIS
        Vuelca el índice de espacio: carpetas por tamaño y archivos
        mayores.

    .PARAMETER Rutas
        Carpetas por las que empezar. Si no se dan, las zonas del usuario.
    .PARAMETER Profundidad
        Cuántos niveles de carpeta mostrar.
    .PARAMETER Archivos
        Cuántos archivos mayores listar.
    .PARAMETER Buscar
        Filtra los archivos por nombre. Admite comodines: * es "cualquier
        cosa" y ? es "un carácter". Todo lo demás es literal, corchetes
        incluidos.
    .PARAMETER Orden
        Tamaño (de mayor a menor) o Nombre (alfabético). El ValidateSet
        tiene que ser el mismo que el de la capa de consulta; hay una
        invariante que compara los tres.
    .PARAMETER Anonimo
        Sustituye perfil, usuario y equipo por marcadores, para poder
        pegar la salida en una incidencia.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Rutas        = @(),
        [int]      $Profundidad  = 2,
        [int]      $Archivos     = 15,
        [string]   $Buscar       = '',
        # El mismo ValidateSet que Get-VistaArchivos y
        # Get-ResumenVistaArchivos. Copiado a mano, si: PowerShell no deja
        # poner una llamada a funcion dentro de un atributo. Por eso lo
        # ata una invariante en tests/VistaArchivos.Tests.ps1 que compara
        # los tres contra Get-OrdenesVistaArchivos.
        [ValidateSet('Tamano', 'Nombre')]
        [string]   $Orden        = 'Tamano',
        [switch]   $ContarEnlacesDuros,
        [switch]   $Anonimo,
        # Si se da, ademas del volcado en consola se escribe un informe
        # HTML con el mapa de arbol dibujado.
        [string]   $Informe = '',
        $Configuracion = $null
    )

    $zonas = @($Rutas | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($zonas.Count -eq 0 -and $null -ne $Configuracion) {
        $zonas = @($Configuracion.ZonasUsuario | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    }
    if ($zonas.Count -eq 0) {
        Write-Linea '  No hay ninguna carpeta que analizar.' 'aviso'
        return
    }

    $mostrar = {
        param([string] $Texto)
        if ($Anonimo) { return ConvertTo-RutaAnonima $Texto }
        return $Texto
    }

    Write-Cabecera 'Donde se fue el espacio'
    foreach ($z in $zonas) { Write-Linea ('  Analizando: {0}' -f (& $mostrar $z)) }
    Write-Linea ''

    $cronometro = [Diagnostics.Stopwatch]::StartNew()
    $indice = New-IndiceDisco -Rutas $zonas -MinimoArchivoBytes 1MB `
                              -ContarEnlacesDuros:$ContarEnlacesDuros
    $cronometro.Stop()

    if ($indice.Bytes -le 0) {
        Write-Linea '  No se ha podido medir nada. Comprueba los permisos.' 'aviso'
        return
    }

    # ---------------- Carpetas ----------------
    Write-Cabecera 'Carpetas por tamaño'

    $pilaVisita = [Collections.Generic.Stack[object]]::new()
    foreach ($z in ($zonas | Sort-Object { -$indice.Carpetas[$_].Bytes })) {
        if ($indice.Carpetas.ContainsKey($z)) {
            $pilaVisita.Push([pscustomobject]@{ Ruta = $z; Nivel = 0; Total = $indice.Carpetas[$z].Bytes })
        }
    }

    while ($pilaVisita.Count -gt 0) {
        $nodo = $pilaVisita.Pop()
        $entrada = $indice.Carpetas[$nodo.Ruta]
        if ($null -eq $entrada) { continue }

        $sangria = '  ' + ('   ' * $nodo.Nivel)
        $nombre  = if ($nodo.Nivel -eq 0) { & $mostrar $nodo.Ruta } else { $entrada.Nombre }

        Write-Linea ('{0}{1} {2,10}  {3}' -f $sangria,
                     (Write-BarraProporcion -Parte $entrada.Bytes -Total $indice.Bytes),
                     (Format-Tamano $entrada.Bytes),
                     (Get-RutaElidida $nombre 46))

        if ($nodo.Nivel -ge $Profundidad) { continue }

        # Se apilan del reves para que salgan de mayor a menor.
        $hijas = @(Get-HijasDirectas -Indice $indice -Ruta $nodo.Ruta |
                   Where-Object { $_.Bytes -ge ($indice.Bytes * 0.01) })
        for ($i = $hijas.Count - 1; $i -ge 0; $i--) {
            if (-not $indice.Carpetas.ContainsKey($hijas[$i].Ruta)) { continue }
            $pilaVisita.Push([pscustomobject]@{
                Ruta = $hijas[$i].Ruta; Nivel = $nodo.Nivel + 1; Total = $hijas[$i].Bytes
            })
        }
    }

    Write-Linea ''
    Write-Linea '  Solo se muestran las carpetas que pasan del 1% del total.'

    # ---------------- Archivos ----------------
    # La cabecera dice lo que se ha hecho. Con -Orden Nombre esta lista no
    # son "los mayores", y dejar ese titulo seria el programa afirmando
    # algo que no ha hecho, que es la familia de fallos de [COR-01].
    $titulo = 'Archivos mayores'
    if ($Orden -eq 'Nombre') { $titulo = 'Archivos por nombre' }
    Write-Cabecera $titulo

    # AQUI NO SE FILTRA NI SE ORDENA A MANO. Esto lo decide la capa de
    # consulta del nucleo (src/Core/VistaArchivos.ps1), y la razon es la
    # de [ARQ-01]: dos sitios que deciden lo mismo acaban decidiendo cosas
    # distintas. Lo que habia aqui era una segunda version, peor, de ese
    # mismo trabajo, y ya divergia en dos puntos concretos:
    #
    #   1. Filtraba con -like, que interpreta ademas [ y ] como clases de
    #      caracteres. Buscar "foto[1].jpg" -el nombre que pone el
    #      navegador a la segunda descarga- pedia sin querer "foto, un
    #      caracter que sea 1, y .jpg": encontraba foto1.jpg, que no es lo
    #      que se pidio, y NO encontraba foto[1].jpg, que si lo es. El
    #      usuario no tenia forma de entender por que.
    #   2. Escribia el resumen SOLO cuando la lista salia vacia, asi que
    #      faltaba justo el caso peligroso: hay mas de los que se ensenyan
    #      Y hay un filtro puesto. El usuario veia quince lineas, ninguna
    #      la que buscaba, y concluia que el analisis se dejo cosas.
    if (-not [string]::IsNullOrWhiteSpace($Buscar)) {
        Write-Linea ('  Filtrando por: {0}' -f $Buscar)
        Write-Linea ''
    }

    # @() alrededor: en PowerShell 5.1, .Count sobre el resultado de una
    # funcion que devolvio un solo objeto vale $null.
    $vista = @(Get-VistaArchivos -Indice $indice -Buscar $Buscar `
                                 -Cuantos $Archivos -Orden $Orden)
    foreach ($a in $vista) {
        Write-Linea ('  {0,10}  {1}' -f (Format-Tamano $a.Bytes),
                     (Get-RutaElidida (& $mostrar $a.Ruta) 60))
    }

    # El resumen se escribe SIEMPRE, haya filas o no. Es lo unico que
    # distingue "esto es todo lo que hay" de "esto es lo que cabe", y las
    # dos cosas se ven exactamente igual: una lista que se acaba.
    if ($vista.Count -gt 0) { Write-Linea '' }
    $resumen = Get-ResumenVistaArchivos -Indice $indice -Buscar $Buscar `
                                        -Cuantos $Archivos -Orden $Orden
    # Amarillo SOLO cuando hay una busqueda que no encontro nada, que es
    # lo unico que el usuario puede corregir. El texto de "no hay nada por
    # encima del umbral" dice que el analisis fue bien: pintarlo de aviso
    # seria contradecir con el color lo que pone la linea, que es el fallo
    # de [USO-02] al reves.
    $estilo = 'normal'
    if ($vista.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Buscar)) { $estilo = 'aviso' }
    Write-Linea ('  ' + $resumen) $estilo

    # ---------------- Resumen ----------------
    Write-Cabecera 'Resumen'
    Write-Linea ('  Espacio medido    : {0}' -f (Format-Tamano $indice.Bytes))
    Write-Linea ('  Archivos          : {0:N0}' -f $indice.TotalArchivos)
    Write-Linea ('  Carpetas          : {0:N0}' -f $indice.Carpetas.Count)
    Write-Linea ('  Tiempo            : {0}' -f (Format-Duracion $cronometro.Elapsed))

    if ($indice.Compartidos -gt 0) {
        Write-Linea ('  Enlaces duros     : {0:N0} archivos comparten contenido y se han contado una sola vez' -f
                     $indice.Compartidos)
    }
    if ($indice.Inaccesibles -gt 0) {
        Write-Linea ('  Sin permiso       : {0:N0} carpetas no se han podido leer' -f $indice.Inaccesibles) 'aviso'
    }

    # ---------------- Informe con mapa ----------------
    if (-not [string]::IsNullOrWhiteSpace($Informe)) {
        try {
            Export-InformeEspacio -Indice $indice -Ruta $Informe -Anonimo:$Anonimo -Confirm:$false
            Write-Linea ''
            Write-Linea ('  Mapa del disco guardado en: {0}' -f $Informe) 'ok'
        } catch {
            Write-Linea ('  No se ha podido guardar el informe: {0}' -f $_.Exception.Message) 'error'
        }
    }

    Write-Linea ''
    Write-Linea '  Esto es un informe: no se ha propuesto ni borrado nada.'
}
