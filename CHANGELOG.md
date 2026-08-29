# Registro de cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [versionado semántico](https://semver.org/lang/es/).

---

## [Sin publicar]

> El razonamiento completo de estos cambios —por qué se hizo cada uno, qué se descartó y qué
> quedó pendiente— está en [`docs/historico/DIARIO-2.0.1.md`](docs/historico/DIARIO-2.0.1.md),
> en [`docs/PLAN-ACCION.md`](docs/PLAN-ACCION.md) y en
> [`docs/HOJA-DE-RUTA.md`](docs/HOJA-DE-RUTA.md).

### Primera ejecución en Windows

El programa se ejecutó por primera vez en el sistema para el que está escrito: Windows 11 Pro con
PowerShell 5.1. Dos ejecuciones encontraron **cuatro fallos que las 800 pruebas no veían**, y los
cuatro están corregidos más abajo. Es la razón de que `VAL-01` haya pasado de ser un bloqueante
que se hace una vez a un hábito después de cada tanda de cambios.

### Ya no miente sobre lo que hizo

- **La papelera que borraba para siempre.** Cuando algo no cabe en la papelera, Windows lo borra
  permanentemente, sin avisar y devolviendo éxito; el programa lo anotaba como `PAPELERA`. Ahora
  se comprueba antes: si no cabría, **no se borra**, se explica con las dos cifras y se ofrece el
  borrado permanente. `[COR-01]`
- **Un análisis incompleto ya no se presenta como completo.** Cancelar en el módulo 7 de 21 decía
  exactamente lo mismo que recorrer los 21. Ahora hay franja en Resultados, los módulos que fallan
  se cuentan y se nombran, y el historial guarda `Incompleto` y `Motivo`. `[CNF-04]`
- **Un borrado que falla ya no se pinta en verde ni se esconde.** El texto de estado solo se veía
  con el borrado hecho, así que un fallo no mostraba nada; y cuando se veía, salía en color de
  éxito. `[USO-02]`
- **La simulación pasa por la misma comprobación que el borrado real.** Prometía liberar un
  archivo de 9,52 GB que la ejecución de verdad habría rechazado. `[CNF-02]`
- **Una limpieza detenida a mitad se anota como detenida**, no como una limpieza completa.
  `[CNF-04]`

### Corregido

- `New-Object System.Collections.Generic.List[object]` devuelve una lista que el operador `@( )`
  **no puede enumerar**: rompía todos los informes, en ventana y en consola. `[COR-07]`
- Rutas de más de 260 caracteres: prefijo `\\?\` al medir y al borrar. Antes se medía de menos y
  se borraba de menos **en silencio**, y luego se informaba de "archivos en uso". `[COR-02]`
- Archivos de OneDrive a petición: buscar duplicados podía **descargar gigabytes** sin avisar, y
  los archivos grandes prometían liberar un espacio que en el disco no está. `[COR-03]`
- Los errores dicen **dónde** han ocurrido: tipo, archivo y línea, con la pila en el registro.
  Guardar el informe y abrirlo son ya dos operaciones distintas. `[COR-06]`
- Toda la prosa de cara al usuario lleva sus tildes y sus eñes. `[I18N-01]`

### Añadido

- **Modo simulación** en los dos caminos: casilla *Solo simular* en la ventana y `-Simular` en la
  consola. No deja informe ni entrada en el historial, porque no ha ocurrido nada. `[CNF-02]`
- **Exclusiones del usuario**: carpetas que no se tocan nunca, con `-Excluir` en consola. `[CNF-01]`
- Al terminar una limpieza se dice **qué se puede rescatar de la papelera y qué no**, con un botón
  para abrirla. `[CNF-03]`
- El progreso enseña **tiempo transcurrido y elementos encontrados**: un módulo lento ya no se
  distingue de un cuelgue. `[USO-07]`

### Interfaz

- La columna *"qué pasa si se borra"* deja de recortarse: altura de fila automática y el texto
  completo en la ayuda emergente. `[USO-01]`
- El diálogo de confirmación enseña **todos** los comandos externos —`SECURITY.md` lo exige y
  antes se perdían fuera de los cinco primeros—, hasta 25 elementos más con ajuste de línea, y
  dice cuántos quedan fuera. `[USO-08]`
- La tabla del informe HTML ya no aplasta la columna de rutas. `[REP-06]`

### La simulación ya se ve

- **El resultado de la simulación aparece en Resultados**, no solo en el Registro. Antes hacía todo
  su trabajo en silencio: la tabla no cambiaba ni un número, y el botón parecía roto. Ahora hay un
  cartel con las cifras, los bloqueados y qué hacer para hacerlo de verdad — y **caduca en cuanto
  se cambia la selección**, porque a partir de ahí sus números ya no corresponden a nada. `[USO-15]`
- Las cabeceras de grupo ya no dicen `1 elementos`: ahora es una etiqueta, `Elementos: 12`, donde el
  número no concuerda con nada. El primer intento fue un `Style` con `DataTrigger` para el singular,
  y en Windows el disparador se aplicaba pero el valor por defecto no: las categorías de una fila
  decían "1 elemento" y las demás se quedaban en "12", sin palabra. `[USO-15]`
- Si el cartel de la simulación no estuviera en la ventana, el programa **lo dice** en el registro en
  vez de callarse: un bloque que existe para que la simulación deje de ser muda no puede fallar en
  silencio. `[USO-15]`
- Las columnas `TAMAÑO` y `QUÉ PASA SI SE BORRA` recuperan sus tildes. `[I18N-01]`

### Corregido en la segunda ejecución en Windows

- **La cabecera de grupo tumbaba el programa.** `Setter TargetName` apuntaba a una
  `RotateTransform`, que es un `Freezable` y no existe en el ámbito de nombres de la plantilla.
  Como el contenido de una plantilla se analiza al aplicarse y no al cargar, el XAML pasaba, la
  ventana abría y el fallo salía después. Ahora la invariante prohíbe nombrar transformaciones,
  pinceles y geometrías, y exige que todo `TargetName` resuelva. `[USO-14]`
- **Un fallo repetido ya no entierra la ventana.** El manejador de errores de la interfaz abría un
  diálogo modal por cada excepción; una que se repetía dejaba veinte avisos idénticos encima del
  programa, sin poder llegar al botón de parar el análisis. Ahora se avisa del primero de cada
  clase, con un máximo de tres, y al registro van todos con su cuenta. `[USO-14]`

### Accesibilidad

- **Un lector de pantalla ya puede decir qué es cada control.** No había **ni una sola** propiedad
  de automatización en los ocho XAML del proyecto. Los cuatro botones de la barra de título son
  formas dentro de un `Button` —un `Path`, un `Border`—, así que se anunciaban los cuatro igual,
  como *"botón"*, sin forma de saber cuál cerraba el programa. La casilla de cada fila era peor:
  cientos de *"casilla, sin marcar"* seguidos, sin decir de qué, en la columna que decide lo que se
  borra. Ahora llevan nombre los botones de ventana, el campo de filtro, el selector de riesgo, el
  botón de plegar categoría, el registro, los dos deslizadores de Ajustes y el campo del diálogo de
  confirmación; y las casillas de fila, de módulo y de disco y las tarjetas de perfil lo toman
  **del mismo enlace que pinta su rótulo visible**, para que no puedan separarse. `[A11Y-01]`
- **Y una invariante que impide que vuelva a pasar**, porque este fallo es mudo en las dos
  direcciones: ni la ventana se queja, ni el analizador lo ve, ni quien mira la pantalla lo nota
  jamás. Exige que todo control sin texto propio declare su nombre, que no esté en blanco, y —lo
  que de verdad muerde— que un nombre enlazado apunte a una propiedad **que exista**: un
  `{Binding}` mal escrito no lanza, WPF lo resuelve a vacío y el control se queda igual de mudo,
  pero con el atributo puesto y aparentando estar arreglado. `[A11Y-01]`
- **Instalable con Scoop, y listo para winget.** Cada versión publica también su manifiesto de
  Scoop y los tres `.yaml` de winget, **generados por la propia publicación** con el hash del `.zip`
  que acaba de armar. Se generan y no se mantienen a mano porque declaran cuatro datos que caducan a
  la vez y en silencio —versión, URL, hash y la carpeta de dentro del `.zip`—: un manifiesto viejo
  pasa las pruebas y falla en casa de quien instala. Todavía **no está enviado a
  `microsoft/winget-pkgs`**, así que `winget install` aún no lo encuentra. `[DIS-03]` `[DIS-04]`
- **La tabla vacía ya dice cuál de los tres casos es.** Enseñaba el mismo rectángulo en blanco
  recién abierto el programa, tras un análisis sin resultados, y con un filtro que no deja pasar
  nada. El tercero era el peligroso: parecía que el análisis había fallado. Ahora se explica, y en
  el caso del filtro hay un botón que quita **los dos** filtros —el de texto y el de riesgo— con un
  rótulo que dice cuántos va a quitar, porque quitar solo uno puede dejar la tabla igual de vacía.
  `[USO-09]`
- **Un campo nuevo del contrato ya no puede nacer invisible en la interfaz.** La invariante que
  había cubría solo lo que existe en los dos lados, así que un campo sin contraparte en la fila no
  lo echaba de menos nadie. No había ningún fallo vivo; ahora tampoco puede haberlo. `[COR-05]`
- **Cada versión publica el SHA-256 de lo que adjunta**, en la página de la versión y en un
  `SHA256SUMS.txt`. En los dos sitios a propósito: quien pudiera cambiar el paquete podría cambiar
  también su archivo de sumas, pero no el texto de la versión. Es prerrequisito de winget y de
  Scoop. `[DIS-02]`
- **Y el flujo de publicación se verifica a sí mismo con `sha256sum -c --strict`.** El `--strict`
  no es adorno: sin él, un archivo de sumas con BOM avisa de que una línea está mal formada,
  comprueba las demás y **sale con código 0**. El paso habría quedado en verde publicando un `.zip`
  cuya suma no ha comprobado nadie. `[DIS-02]`
- **Banco de pruebas para máquina virtual.** `docs/BANCO-PRUEBAS.md` y `tools/Banco-Pruebas.ps1`:
  monta cebos deterministas —ruta de más de 260 caracteres, archivo mayor que la cuota de la
  papelera, dos enlaces duros al mismo contenido, duplicados, 3.000 filas de relleno— dentro de
  Documentos, que es el único sitio donde los módulos los buscan. Es lo que permite hacer una
  limpieza **real** y comprobar `COR-01`, `COR-02` y `COR-03`, que hasta hoy están escritos y
  probados en frío pero **nunca ejecutados**. Las decisiones que deciden qué se puede borrar viven
  aparte, en cálculo puro y con 31 pruebas: un error ahí no daría un resultado raro, se llevaría
  archivos del usuario. `[VAL-02]`
- **Atajos de teclado**, que no había ninguno: `F5` analizar, `Ctrl+F` ir a Resultados y enfocar el
  filtro, `Ctrl+A` marcar todo, `Esc` cancelar lo que esté corriendo, `Ctrl+1..6` los seis paneles
  —con la fila de números y con el numérico, que para el usuario son la misma tecla—. El atajo
  **levanta el clic del botón** en vez de repetir lo que hace: no pueden divergir, y hereda gratis
  las guardas de cada botón. `Ctrl+A` se aparta dentro de un cuadro de texto, donde ya significa
  *seleccionar todo el texto* y el registro de la sesión es uno. `[A11Y-04]`
- **`Supr` no elimina, y es deliberado.** Estaba en el plan y se descartó: en una tabla esa tecla
  significa *"borra esta fila"* y aquí significaría *"borra las 800 marcadas"*; y el diálogo de
  confirmación existe para frenar un gesto distraído, así que dejar que una sola tecla llegue hasta
  él lo convierte de segunda barrera en única. `[A11Y-04]`
- **Cambiar de panel ahora se nota sin mirar la pantalla.** Solo se alternaba la visibilidad, y los
  lectores de pantalla anuncian lo que tiene el **foco**, no lo que se ha vuelto visible: el usuario
  pulsaba *Resultados*, oía *"Resultados, botón de opción, marcado"*, y ahí se acababa — ninguna
  pista de que delante tenía ya una tabla con seiscientas filas. Ahora el foco va al panel mostrado,
  que se anuncia con su título visible. Al panel entero y no a su primer control, entre otras cosas
  porque el primero de Inicio es *Analizar el equipo* y un Espacio distraído habría lanzado un
  análisis. `[A11Y-06]`
- **Las cuatro listas de paneles ya no pueden divergir.** Los nombres de los seis paneles viven en
  el XAML, en la lista que resuelve la ventana, en el bucle que los muestra y en las seis líneas de
  la barra lateral, y nada las comparaba. Un panel nuevo que se olvidase en el bucle **no se
  ocultaría nunca**: se quedaría pintado encima del que toca, sin error ninguno. Misma forma que
  `[COR-04]`. `[A11Y-06]`
- **El diálogo de confirmación ya no puede sacar sus botones de la pantalla.** Crecía con su
  contenido, y el contenido lo decide el usuario: con bastantes elementos de riesgo, *Cancelar* y
  *Eliminar* acababan por debajo del borde inferior. Ahora tiene altura máxima. `[A11Y-03]`
- **Escape cancela desde cualquier foco.** Antes solo funcionaba con el cursor dentro del cuadro
  de texto. Enter sigue sin ser global a propósito: este diálogo existe para frenar un gesto
  automático. `[A11Y-03]`
- **Las flechas ya no cambian de panel sin querer.** La barra lateral son botones de radio, y en
  WPF la flecha mueve el foco *y marca a la vez*. Ahora Tab recorre y Espacio activa. `[A11Y-05]`
- **La etiqueta de riesgo deja de ser el texto más pequeño del programa** — era el dato que decide
  si algo se borra. Sube de 11 a 12 y el punto de color de 7 a 9, sin añadir un tamaño nuevo a la
  escala. `[A11Y-07]`

### Seguridad

- La lista blanca ya no se puede esquivar con una junction: `Test-CadenaSinEnlaces` comprueba los atributos reales de cada carpeta hasta la raíz autorizada.
- `powershell.exe` y `explorer.exe` se resuelven anclados a `%SystemRoot%`, no por orden de búsqueda.
- El informe CSV neutraliza las celdas que Excel evaluaría como fórmula.
- Las carpetas personales con tilde —`Imágenes`, `Música`, `Vídeos`— vuelven a estar protegidas: la guardia comparaba sin quitar diacríticos. `[SEG-10]`
- Un `Initialize-Guardia` que falle a medias ya no deja la guardia dando por buenas unas listas incompletas. `[SEG-11]`
- Una copia de seguridad con doble extensión (`Contraseñas.kdbx.bak`) ya no se propone como basura. `[SEG-14]`
- Se elimina el método `NpmClean` y `npm` sale de la lista blanca de ejecutables: resolverlo devolvía `npm.cmd`, y ejecutar un `.cmd` pasa siempre por `cmd.exe`. `[SEG-21]`
- Docker se resuelve contra las rutas reales de instalación, no por `PATH`. `[SEG-30]`
- El historial se escribe de forma atómica: un corte a mitad ya no lo deja truncado. `[SEG-62]`

### Corregido

- **`Hecho` ya no afirma que se borró algo que falló.** Se calculaba antes de consolidar el error, así que un borrado denegado aparecía como "Eliminado" en el CSV y sumaba bytes al historial. `[SEG-20]`
- Un "acceso denegado" al medir una carpeta ya no descarta también todo lo que cuelga de ella. `[SEG-40]`
- Un módulo que falla a mitad conserva los candidatos que ya había encontrado. `[SEG-50]`
- El módulo de proyectos proponía cada `dist` y `build` de cada paquete npm además del `node_modules` que los contiene: los mismos bytes contados muchas veces. `[REN-32]`
- Las carpetas vacías fuera de AppData ya no vienen premarcadas. `[FAL-02]`
- Un acceso directo cuyo destino no se puede leer por permisos ya no se da por roto ni se premarca. `[FAL-01]`
- En duplicados se conserva la copia mejor ubicada, no la más antigua. `[FAL-10]`
- Vaciar una caché ya no se salta sus `.db` y `.txt`, que eran la mayor parte del espacio prometido. `[FAL-15]`
- Un fallo al lanzar el análisis ya no deja la ventana bloqueada para siempre. `[INT-02]`
- El botón de tema ya no modifica la configuración que el hilo de análisis está leyendo. `[INT-03]`
- Cerrar la ventana durante un borrado ya no pierde la entrada del historial. `[INT-04]`
- La ventana y la consola anotan la misma cifra para el mismo análisis. `[INT-12]`

### Añadido

- **Módulo de juegos** (`33-Juegos`): bibliotecas de Steam leídas del `libraryfolders.vdf`, juegos sin manifiesto, cachés de sombreadores y contenido del taller huérfanos, y cachés de Epic, Battle.net, GOG, EA, Ubisoft y Riot. Nunca toca partidas guardadas. `[DET-30]`–`[DET-37]`
- **Módulo de restos fuera de AppData** (`32-RestosRegistro`): versiones antiguas de aplicaciones Electron, instaladores de controladores ya aplicados, entradas de desinstalación fantasma y huérfanos de Archivos de programa. `[DET-40]`–`[DET-43]`
- **Módulo de aplicaciones de la Store** (`37-AppsUWP`). `[DET-50]`
- `AppData\LocalLow` y el segundo nivel de `AppData` entran en el módulo de restos: es donde viven los restos de juegos. `[DET-20]` `[DET-21]`
- Seis cachés de sombreadores más, seis herramientas de desarrollo, `C:\Windows\Temp`, siete carpetas de registros del sistema y doce extensiones de instalador. `[DET-60]`–`[DET-65]`

### Rendimiento

- **`Test-TokenConocido` deja de recorrer el vocabulario entero por cada carpeta.** El vocabulario se separa en evidencia fuerte y débil, con coincidencia exacta e índice por prefijo. De 160 ms a 60 ms sobre 3.017 tokens y 400 carpetas — y de 394 a 400 restos detectados. `[DET-10]`
- El módulo de carpetas vacías recorre con poda y corta en el primer archivo: de 3.622 ms a 21 ms. `[REN-31]`
- El módulo de proyectos no desciende dentro de `node_modules`: de 291 ms a 21 ms. `[REN-32]`
- La guardia precalcula el conjunto de antepasados protegidos y compila sus expresiones regulares. `[REN-41]`
- Duplicados prefiltra con tamaño y 128 KB de los extremos antes de leer archivos enteros. `[REN-52]`
- Un solo runspace por operación en vez de uno por módulo: el núcleo se carga una vez, no veintiuna. `[INT-01]`

### Documentación

- `docs/PLAN-ACCION.md`: auditoría completa con 80 hallazgos, su estado y las mediciones.
- El razonamiento largo se mueve a `docs/historico/`.
- `docs/PRUEBA-MANUAL.md` incorpora las comprobaciones del ciclo de vida del runspace, que son las únicas que la suite no puede hacer.

## [2.0.0] — 2026-08-16

Reescritura completa. La versión 1.0 era un único script de 1.688 líneas más nueve scripts sueltos que había que ejecutar a mano y en orden. Esta versión es un solo programa.

### Añadido

- **Interfaz WPF** con tema oscuro y claro, barra de título propia, navegación lateral, estado de los discos en tiempo real y lista de resultados agrupada por categoría con etiquetas de riesgo.
- **Arquitectura modular.** Cada categoría de limpieza es un archivo independiente en `src/Modules/`. El registro los descubre solo: añadir una categoría no obliga a tocar ningún otro archivo.
- **Diez módulos nuevos**: papelera de reciclaje, duplicados por hash SHA-256, archivos grandes sin usar, caché de Windows Update, almacén de componentes vía DISM, archivos gigantes del sistema, WSL y Docker, arranque y servicios rotos, perfiles de usuario abandonados, y cachés de navegadores separadas en su propio módulo perfil por perfil.
- **Módulos informativos.** Categoría nueva de módulos que nunca borran: solo señalan dónde se va el disco y explican cómo recuperarlo desde Windows. Es lo correcto para `hiberfil.sys`, `Windows.old`, WinSxS, puntos de restauración y perfiles de usuario.
- **Perfiles de limpieza**: conservador, equilibrado, exhaustivo y personalizado, cada uno con sus umbrales y su selección de módulos.
- **Modo consola** (`-Consola`) con selección de módulos, informes y ejecución silenciosa para tareas programadas.
- **Informes** en HTML autocontenido, CSV y JSON, más historial persistente de las cien últimas ejecuciones.
- **Cancelación real** del análisis en curso, con la interfaz siempre viva.
- **144 pruebas automatizadas** con Pester, 95 de ellas dedicadas exclusivamente a la guardia de seguridad, e integración continua en GitHub Actions con PowerShell 5.1 y 7.

### Cambiado

- **La guardia de seguridad se ha reescrito y endurecido.** Modelo de lista blanca explícito, siete filtros encadenados, protección de `.aws`, `.kube`, `System Volume Information` y `Recovery`, detección de travesías con `..`, y un motivo de bloqueo legible para cada rechazo.
- **Revalidación en vivo antes de borrar.** Ya no basta con que una ruta fuera segura durante el análisis: se vuelve a comprobar contra las mismas raíces en el momento de la eliminación.
- **El lanzador ya no pide permisos de administrador.** Arranca con los permisos mínimos; los dos módulos que los necesitan se activan desde *Ajustes → Reiniciar como administrador*.
- **Los datos generados salen del repositorio.** Registros, informes, historial y preferencias viven ahora en `%LOCALAPPDATA%\Cachivache`, de modo que el proyecto se puede clonar en solo lectura.
- El análisis se ejecuta en runspaces aparte cargando el mismo núcleo que el proceso principal, en lugar de un motor serializado como cadena de texto.
- Las carpetas ambiguas de proyecto (`dist`, `build`, `out`, `bin`, `obj`) ahora exigen un manifiesto de proyecto junto a ellas antes de proponerse.
- La detección de restos de programas consulta siete fuentes en lugar de la lista de programas instalados, y ahora inspecciona el contenido en busca de partidas guardadas y documentos antes de proponer nada.

### Corregido

- **La guardia vetaba todo lo que hubiera dentro de Descargas, Documentos, Escritorio, Imágenes, Música y Vídeos**, no solo esas carpetas. El efecto era que los módulos de proyectos, instaladores antiguos, carpetas vacías, accesos rotos, temporales sueltos y duplicados no podían devolver ni un solo resultado. Ahora el filtro comprueba únicamente el último tramo de la ruta, y lo que protege el contenido es la lista blanca de raíces de cada módulo más el veto por extensión.
- Las comparaciones de la guardia normalizan el separador de ruta, de modo que una ruta escrita con barra normal —que Windows acepta— no puede saltarse los filtros.
- `Thumbs.db` quedaba protegido para siempre por llevar extensión `.db`. Se ha añadido una lista explícita de basura conocida que tiene prioridad sobre las extensiones protegidas.
- La extracción del ejecutable de una línea de comandos rompía en rutas con espacios sin comillas (`C:\Program Files\...`). Ahora se resuelve en tres estrategias y se comprueba la existencia de tres formas antes de declarar algo roto.
- Las carpetas `Descargas`, `Documentos` y demás se resuelven mediante las carpetas conocidas de Windows, de modo que la redirección a OneDrive y Windows en otros idiomas funcionan correctamente.
- El análisis ya no puede dejar la ventana congelada ni sin forma de cancelar.

### Movido

- Los scripts originales (`Auditar-*.ps1`, `Limpiar-*.ps1`, `Verificar-Arranque.ps1`) pasaron a `legacy/`. Toda su lógica quedó integrada en los módulos. *(Esa carpeta se eliminó después; ver la sección «Sin publicar».)*

---

## [1.0.0] — 2025-08-15

Primera versión: `Cachivache.ps1` con interfaz WinForms y ocho pasos de limpieza, más scripts sueltos de auditoría y limpieza por fases.
