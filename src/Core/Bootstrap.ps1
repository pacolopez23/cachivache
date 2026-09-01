<#
.SYNOPSIS
    Carga todo el nucleo en el ámbito de quien lo invoca.

.DESCRIPTION
    Este archivo se DOT-SOURCEA, nunca se ejecuta:

        . (Join-Path $raiz 'src\Core\Bootstrap.ps1')

    Es importante que sea un script y no una función. Una función que
    dot-sourcea archivos los carga en SU propio ámbito, y las funciones
    desaparecen en cuanto la función termina. Al dot-sourcear este script,
    todo acaba en el ámbito de quien llama, que es lo que hace falta tanto
    en el proceso principal como en cada runspace de análisis.

    El orden importa: Guard necesita Texto, Config necesita Profiles y
    FileSystem, Remove necesita Guard y también Log (desde [C-03], para
    dejar constancia del comando externo que ejecuta), Historial necesita
    Config, y Progreso va primero porque lo usan todos los módulos. Por
    eso la lista es explicita y no un simple recorrido alfabetico de la
    carpeta.

    Nota: como todo se carga entero antes de ejecutar nada, una llamada
    "hacia adelante" no rompe en tiempo de ejecución; el orden esta para
    que el archivo se pueda leer de arriba abajo y para no depender de ese
    detalle si alguna vez se carga solo una parte del nucleo.
#>

$OrdenNucleoCachivache = @(
    'Version.ps1'         # versión y constantes
    'Progreso.ps1'        # progreso y cancelación (lo usan todos los módulos)
    'Texto.ps1'           # normalizacion de texto para comparar identidad
    'Format.ps1'          # formato de tamaños, tiempos y rutas para mostrar
    'EstadoVacio.ps1'     # que decir cuando la tabla no ensenya ni una fila
    'Extraibles.ps1'      # que clase de unidad es cada letra: la lee FileSystem para decidir cuales se analizan
    'FileSystem.ps1'      # medición, unidades, carpetas conocidas
    'Compresion.ps1'      # compresion NTFS: lo que se libera de verdad, que no es lo que ocupa
    'Exclusiones.ps1'     # como se ensenya la lista de "no tocar": lee la clave que compone FileSystem
    'Guard.ps1'           # guardia de seguridad
    'Candidate.ps1'       # contrato de candidato y de módulo
    'Comandos.ps1'        # que programas externos se pueden lanzar, y de donde
    'Papelera.ps1'        # cuota de la papelera: va ANTES que Remove, que la consulta
    'Remove.ps1'          # motor de eliminación
    'Registry.ps1'        # vocabulario de programas instalados (solo lectura)
    'Steam.ps1'           # bibliotecas y juegos que Steam conoce (solo lectura)
    'Ejecutables.ps1'     # resolución de ejecutables, arranque y accesos directos
    'Profiles.ps1'        # perfiles de limpieza
    'Config.ps1'          # configuración del equipo (se descubre al arrancar)
    'Preferencias.ps1'    # preferencias del usuario (persisten entre sesiones)
    'Log.ps1'             # registro de actividad (.log)
    'Historial.ps1'       # historial de ejecuciones (.json)
    'Comparacion.ps1'     # comparar con el analisis anterior: lee Historial, formatea con Format
    'Inspeccion.ps1'      # que hay dentro de una carpeta, para poder decidir
    'Indice.ps1'          # indice de espacio en disco (una sola pasada)
    'VistaArchivos.ps1'   # la capa de consulta del indice: todos los archivos por tamano, con comodines
    'Mft.ps1'             # tabla maestra de NTFS. MEDIDO Y DESCARTADO como camino rapido: ver docs/VEL-01-MEDICION.md
    'Mapa.ps1'            # disposicion del mapa de arbol (calculo puro)
    'Report.ps1'          # informes HTML, CSV y JSON
    'ReportEspacio.ps1'   # informe de espacio con mapa de arbol en SVG
    'ModuleRegistry.ps1'  # descubrimiento y ejecución de módulos
)

foreach ($ArchivoNucleoCachivache in $OrdenNucleoCachivache) {
    $RutaNucleoCachivache = Join-Path $PSScriptRoot $ArchivoNucleoCachivache
    if (-not (Test-Path -LiteralPath $RutaNucleoCachivache)) {
        throw "Falta un archivo del nucleo: $RutaNucleoCachivache"
    }
    . $RutaNucleoCachivache
}

# Este script se DOT-SOURCEA, asi que sus variables se crean en el ambito
# de quien llama y hay que recogerlas. Por eso los tres nombres llevan el
# sufijo "Cachivache": un Remove-Variable en el ambito ajeno solo es
# seguro si los nombres no se los puede haber puesto nadie mas. Con
# nombres corrientes -$archivo, $ruta, $orden- esta linea borraria
# variables del llamante. Ver [REP-06] en docs/PLAN-ACCION.md.
Remove-Variable -Name 'ArchivoNucleoCachivache', 'RutaNucleoCachivache', 'OrdenNucleoCachivache' `
                -ErrorAction SilentlyContinue
