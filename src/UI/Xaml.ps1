<#
.SYNOPSIS
    Montaje del XAML de la ventana a partir de sus trozos.

.DESCRIPTION
    Vive en su propio archivo, y no dentro de Window.ps1, por un motivo
    práctico: Window.ps1 empieza cargando los ensamblados de WPF, que solo
    existen en Windows. Aquí no hay nada de WPF -es manejo de texto puro-,
    así que las pruebas pueden cargarlo tal cual, en cualquier sistema, en
    vez de tener que recortar la función del archivo grande y evaluarla con
    Invoke-Expression. Que un módulo se pueda probar sin arrastrar sus
    dependencias pesadas suele ser señal de que estaba en el sitio
    equivocado.
#>

function Expand-PanelesXaml {
    <#
    .SYNOPSIS
        Sustituye cada marca "<!--#panel Archivo.xaml-->" por el contenido
        de ese archivo, y devuelve el XAML completo.

    .DESCRIPTION
        MainWindow.xaml tenia 783 líneas con los seis paneles dentro: era el
        archivo más grande del proyecto y el último que seguia siendo un
        cajon. Ahora el armazon -ventana, barra de titulo, panel lateral- se
        queda en MainWindow.xaml y cada panel vive en su Panel.*.xaml.

        Se pegan como TEXTO antes de interpretar, en vez de cargar cada
        panel por separado, y el motivo es concreto: FindName solo busca
        dentro del ámbito de nombres del arbol donde se declaro el nombre.
        Con seis arboles cargados aparte, $ventana.FindName('BtnAnalizar')
        devolveria $null, y habría que rehacer la resolución de los 72
        controles de la ventana. Pegando el texto, lo que WPF interpreta es
        EXACTAMENTE el mismo documento de antes: un arbol, un ámbito, cero
        cambios en tiempo de ejecución. Hay una prueba que reconstruye el
        documento y lo compara con el original guardado.

        La cabecera de comentario de cada Panel.*.xaml se descarta al
        pegar: son notas para quien lee el archivo suelto, no parte de la
        ventana.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Texto,
        [Parameter(Mandatory)] [string] $Carpeta
    )

    $resultado = $Texto
    foreach ($marca in [regex]::Matches($Texto, '(?m)^[ \t]*<!--#panel\s+([^\s>]+?)\s*-->[ \t]*\r?\n?')) {
        $archivo = $marca.Groups[1].Value
        $ruta = Join-Path $Carpeta $archivo
        if (-not (Test-Path -LiteralPath $ruta)) {
            throw "MainWindow.xaml pide el panel '$archivo' y no esta en $Carpeta."
        }
        $trozo = [IO.File]::ReadAllText($ruta)
        # Fuera la cabecera de comentario del archivo suelto. Lo que queda
        # se pega TAL CUAL, sin recortar ni añadir saltos: así el documento
        # montado es copia literal del que había antes de partirlo, y la
        # prueba que los compara puede exigir igualdad exacta en vez de
        # "parecido salvo espacios".
        $trozo = [regex]::Replace($trozo, '(?s)\A\s*<!--.*?-->\s*\r?\n', '')
        $resultado = $resultado.Replace($marca.Value, $trozo)
    }
    return $resultado
}
