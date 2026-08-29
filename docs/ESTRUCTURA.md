# Estructura de archivos: por qué está repartida así

Este documento explica **por qué cada archivo del núcleo contiene lo que contiene**, qué se decidió deliberadamente NO separar, y qué queda pendiente de reorganizar. Es hermano de [`ARQUITECTURA.md`](ARQUITECTURA.md) (cómo funciona el código) y de [`OPTIMIZACIONES.md`](OPTIMIZACIONES.md) (qué falta por mejorar).

La reorganización que describe la sección 2 **ya está hecha**; el detalle de qué se movió está en [`CHANGELOG.md`](../CHANGELOG.md). Lo que sigue vivo es la sección 4.

---

## 1. El criterio

Un archivo debería tener **una sola razón para cambiar**. El criterio no es el número de líneas: `Guard.ps1` tiene 468 y no se toca; `Registry.ps1` tenía 237 y se dividió.

La señal más objetiva para decidir es **quién consume cada función**. Si las funciones de un archivo las usan conjuntos de archivos completamente distintos, y ninguno usa las dos mitades, ese archivo son en realidad dos que comparten domicilio por casualidad histórica. Ese fue el argumento decisivo en casi todas las divisiones.

Al verificar esto conviene desconfiar de `grep` a secas: muchas coincidencias son el nombre de una función mencionado dentro de un comentario `.PARAMETER` o `.DESCRIPTION`, no una llamada real.

---

## 2. Por qué cada archivo del núcleo está donde está

| Archivo | Qué contiene | Por qué está separado |
|---|---|---|
| `Version.ps1` | Versión y URL del repositorio | Único sitio que se toca al publicar. Fusionarlo mezclaría el `diff` de cada versión con cambios ajenos |
| `Progreso.ps1` | `Test-Cancelacion`, `Set-Progreso` | Las usan **los 21 módulos sin excepción**. No miden nada del disco: son la comunicación con la ventana. Vivían en `FileSystem.ps1`, cuyo docblock ni las mencionaba |
| `Texto.ps1` | `Remove-Tildes`, `ConvertTo-Token` | Normalizan texto para **comparar identidad**, no para mostrar. De ellas dependen la guardia y la detección de restos. Sus consumidores (`Guard`, `Registry`) no usan ni una función de formato |
| `Format.ps1` | Tamaños, tiempos y rutas para mostrar | Lo contrario: presentación pura, sin consecuencias |
| `FileSystem.ps1` | Medir rutas, unidades, carpetas conocidas | Consultar el disco y su entorno |
| `Guard.ps1` | El veredicto "¿se puede borrar esto?" | **No dividir.** Ver sección 3 |
| `Candidate.ps1` | Contrato de candidato y de módulo | Define la forma de los datos que circulan |
| `Remove.ps1` | Motor de eliminación | Lo único que borra datos del usuario |
| `Registry.ps1` | Vocabulario de programas instalados | Solo lo usa `30-RestosProgramas` |
| `Ejecutables.ps1` | Resolver ejecutables, arranque, accesos directos | Solo lo usan `90-Arranque` y `45-AccesosRotos`. Ningún módulo consume las dos mitades |
| `Profiles.ps1` | Perfiles de limpieza | Todo gira en torno a una estructura de datos |
| `Config.ps1` | Configuración del **equipo** | Se descubre en cada arranque, nunca se guarda |
| `Preferencias.ps1` | Preferencias del **usuario** | Persisten entre sesiones y las puede editar a mano |
| `Log.ps1` | Registro de actividad (`.log`) | Una línea por acción, se rota por meses |
| `Historial.ps1` | Historial de ejecuciones (`.json`) | Una entrada por ejecución, se reescribe entero |
| `Report.ps1` | Informes HTML, CSV y JSON | Ver sección 4.1 |
| `ModuleRegistry.ps1` | Descubrir y ejecutar módulos | |

### La ventana, repartida en cinco archivos

`Show-VentanaPrincipal` ocupaba 1053 líneas ella sola. Hoy vive en `Window.ps1` (344 líneas: construye la ventana y `$estado`) y **dot-sourcea desde dentro de sí misma** los cuatro trozos de su propio cuerpo: `Window.Ayudantes.ps1`, `Window.Analisis.ps1`, `Window.Eliminacion.ps1` y `Window.Eventos.ps1`.

Esto funciona porque un `.` **dentro** de una función carga el archivo en el ámbito de esa función: cada trozo ve `$c`, `$estado`, `$ventana` y los cierres de los demás, igual que si estuviera pegado ahí. Cargarlos desde fuera no funcionaría.

Tres consecuencias que conviene tener presentes:

- **Esos cuatro archivos no se pueden ejecutar ni analizar por separado.** PSScriptAnalyzer no puede ver que un cierre definido en `Ayudantes` se consume en `Eventos`, y los da por "asignados y nunca usados"; por eso `PSScriptAnalyzerSettings.psd1` excluye esa regla, con la justificación escrita al lado. Es el argumento más sólido *en contra* de esta división, y se aceptó a sabiendas: el acoplamiento es inherente al diseño de cierres de la ventana, no algo que la división haya creado.
- **Nada de lo que viva ahí puede depender de `$PSScriptRoot`**, porque ya no es fiable saber en qué archivo físico se ejecuta cada fragmento. Para localizar la carpeta de la interfaz existe `$estado.CarpetaUi`, que se resuelve una sola vez al principio.
- **En el momento de la carga cada archivo solo define sus cierres.** Las referencias cruzadas (el temporizador de `Analisis` llama a `$terminarBorrado`, que define `Eliminacion`) viven dentro de scriptblocks que no se evalúan hasta mucho después, con los cuatro ya cargados. El orden se respeta por legibilidad, no por necesidad técnica.

---

## 3. Lo que NO conviene dividir

### `Guard.ps1` (468 líneas) — el archivo más grande, y debe seguir unido

Sus once funciones son caras del mismo veredicto: *¿se puede borrar esta ruta?* [C-08] existió precisamente porque `Test-RutaIntocable` y `Get-MotivoBloqueo` mantenían listas de comprobaciones por separado y **divergieron**; la corrección fue unificarlas en `Get-MotivoIntocable` como única fuente de verdad. Dividir el archivo reintroduciría ese riesgo: nada obligaría a que dos archivos definan "intocable" igual. Un archivo de seguridad se audita mejor entero.

Si algún día crece más, el criterio para dividirlo no debería ser el tamaño sino la aparición de una **segunda pregunta** distinta de "¿se puede borrar esto?".

### `src/Modules/*.ps1` (18 archivos) — es el grano correcto

Cada archivo es una categoría de limpieza, autorregistrado, sin lista central que mantener. Ninguno define funciones propias fuera de su `$Buscar` y su `New-ModuloLimpieza`. Es el patrón mejor diseñado del proyecto.

Dos observaciones sobre la complejidad *interna*, que no justifican tocar la granularidad:

- **`20-Proyectos.ps1`** tiene el anidamiento más profundo de los 18 (cinco niveles, decidiendo si una carpeta ambigua tipo `dist`/`build` tiene un manifiesto al lado). Si alguna vez se toca por otro motivo, esa comprobación pide una función auxiliar.
- **`90-Arranque.ps1`** es el "raro": internamente ya son cuatro secciones numeradas que consultan cuatro APIs distintas de Windows (registro, COM, CIM, tareas programadas) y emiten bajo **tres categorías diferentes**. Si sigue creciendo, la frontera para partirlo en `arranque-registro`/`arranque-servicios`/`arranque-tareas` ya existe en el propio código.

### `Version.ps1` (13 líneas) — no fusionar por ser pequeño

Un archivo con una sola razón de ser no es un problema a resolver.

---

## 4. Lo que sigue pendiente

### 4.1. `Report.ps1`: refactor interno, no división — **hecho**

Las cinco funciones cambiaban por el mismo motivo, así que el archivo estaba bien. Lo que no lo estaba era `Export-InformeHtml` (127 líneas): mezclaba el cómputo de totales con **31 líneas de CSS** incrustadas como literal, y el mismo archivo sumaba bytes de tres formas distintas. Extraídos `Get-InformeEstiloCss` y `Measure-TotalBytes`.

El archivo ha crecido después con **la parte de lectura**, que antes no existía: sólo sabía escribir informes, y nadie podía enumerar los ya escritos. Ahora `Get-CarpetaInformes` dice dónde viven (antes lo sabía sólo `New-NombreInforme`, escondido a mitad de su cuerpo), `Get-InformesGuardados` los enumera y `Resolve-InformeAbrible` decide cuáles se pueden abrir. Esa última **no es una comodidad, es una guardia**: es la única puerta por la que el programa abre un archivo con el programa predeterminado del sistema, y la ruta puede venir del `historial.json`, que es texto plano en una carpeta escribible. Ver el CHANGELOG para las cuatro condiciones que exige.

### 4.2. El patrón de "lista de rutas conocidas" — **hecho, en tres de los cuatro**

`10-Caches`, `65-LogsSistema` y `70-WindowsUpdate` repetían casi literalmente el mismo bucle: array de entradas, medir cada ruta, comprobar el umbral, pasar la guardia, emitir candidato. Ahora los tres llaman a `Invoke-BusquedaPorLista` (en `Candidate.ps1`).

**`80-ArchivosSistema` se queda fuera, a propósito.** Recorre *archivos* sueltos, no carpetas, y todos sus candidatos son informativos: meterlo dentro obligaría a que la función común supiera de las dos cosas, y una función común que necesita un interruptor por cada llamante ya no es común. Por lo mismo se quedan donde estaban `MEMORY.DMP` de `logs` y `Windows.old` de `windowsupdate`.

**Cada módulo conserva lo suyo**: su umbral (1 MB en cachés y registros, 10 MB en Windows Update), su categoría y su texto. Unificar eso habría sido cambiar comportamiento con la excusa de refactorizar.

Por ser el único refactor del proyecto que toca lógica de negocio, primero se escribió `tests/BusquedaPorLista.Tests.ps1`, que fija los candidatos exactos —nombre, método, riesgo, aviso y marcado— que producía cada módulo *antes* de tocarlo. Y sirvió: al mutar el umbral de Windows Update a 1 MB, la prueba cayó al instante. De paso destapó que los tres pasaban un `-Preseleccionar` propio que ya era redundante, porque `New-Candidato` garantiza esa misma regla por construcción; una segunda forma de decir lo mismo es una forma de que las dos acaben diciendo cosas distintas.

### 4.3. Dividir `MainWindow.xaml` por panel — **hecho**

De 783 líneas a 191 de armazón (ventana, barra de título, panel lateral) más seis `Panel.*.xaml`, el mayor de 234 líneas.

**El obstáculo que señalaba este documento era real** y decidió la solución. `Window.ps1` resuelve 72 controles con un único bucle de `FindName` sobre `$ventana`, y `FindName` sólo busca dentro del ámbito de nombres del árbol donde se declaró el nombre: con seis paneles cargados por separado, cada uno tendría el suyo y las 72 búsquedas devolverían `$null`.

Por eso los paneles **se pegan como texto antes de interpretar**, no se cargan aparte. `Expand-PanelesXaml` (en `src/UI/Xaml.ps1`) sustituye cada marca `<!--#panel Archivo.xaml-->` por el contenido de ese archivo. Lo que WPF acaba interpretando es el mismo documento de siempre: un árbol, un ámbito, cero cambios en tiempo de ejecución.

Y eso permite la garantía más fuerte posible para un refactor así: hay una prueba que monta el documento y lo compara con una copia del original guardada en `tests/`, exigiendo **igualdad byte a byte**. Mientras pase, partir el XAML no ha podido cambiar nada.

`Expand-PanelesXaml` vive en su propio archivo y no en `Window.ps1` porque este empieza cargando los ensamblados de WPF, que sólo existen en Windows: separada, las pruebas la cargan tal cual en cualquier sistema, en vez de recortarla del archivo grande y evaluarla con `Invoke-Expression`.

### 4.4. Un contrato sin verificación automática

`Candidate.ps1` define un candidato con 20 propiedades; `Types.ps1` define `ItemVista`, la versión que ve la interfaz, con un subconjunto. **La correspondencia se mantiene a mano**, campo a campo, en un único sitio de `Window.Analisis.ps1`.

Hoy funciona, pero lo que lo garantiza es la disciplina de quien programa, no el código: nada avisa si una propiedad nueva se queda sin mapear. Encaja como entrada nueva en la familia [A-04]/[A-09] de `OPTIMIZACIONES.md`: un test que compare ambas listas por AST y falle si divergen.

### 4.5. Extraer `Comandos.ps1` de `Remove.ps1` — **hecho**

La pregunta "qué programa externo puede lanzar este código, y de dónde sale" estaba repartida entre dos archivos que no se citaban: `Resolve-EjecutablePermitido` en `Remove.ps1`, entre las funciones que borran archivos, y `Resolve-EjecutableDeSistema` en `Ejecutables.ps1`, entre las que leen accesos directos. Quien auditara eso tenía que dar con las dos por su cuenta.

Ahora viven juntas en `src/Core/Comandos.ps1`, con sus dos puertas bien separadas en el docblock: la lista blanca cerrada del **motor de borrado** y el anclaje a `System32` de las **consultas de sólo lectura** del análisis. Sus pruebas se mudaron con ellas a `tests/Comandos.Tests.ps1`: un test que no está donde está el código que prueba es un test que nadie encuentra cuando toca.

### 4.6. Empaquetar el núcleo como módulo de PowerShell ([A-01])

Cambia **cómo se cargan** los archivos, no cuántos hay. Se dejó para después de la reorganización a propósito: mover código dentro de dot-sourcing plano es barato y reversible; hacerlo con `Export-ModuleMember` de por medio obliga a tocar la lista de exportación en cada movimiento.

Un dato útil para cuando llegue: `Remove.ps1` declara 9 funciones y solo 2 las usa código de producción fuera del archivo. Ahí es donde `Export-ModuleMember` aportaría valor real inmediato.

**Ojo:** `Get-RutaBootstrap` existía para esto y se ha borrado, porque es inservible por diseño — vive dentro del propio núcleo que sirve para localizar, así que no se puede llamar antes de cargarlo y después ya no hace falta. La idea de [A-02] de unificar con ella las diez construcciones a mano de esa ruta no funciona mientras el núcleo se cargue por dot-sourcing.

---

## 5. Tres lecciones del proceso

Merecen quedarse escritas porque en su momento el proceso falló antes que el código:

1. **La auditoría por lectura no sustituye a ejecutar el programa.** `OPTIMIZACIONES.md` llegó a listar un `DeferRefresh()` en su sección *"lo que ya está bien y no conviene romper"*. Se leía como una optimización sensata y era un fallo que rompía el análisis entero: WPF prohíbe modificar la colección mientras hay un refresco aplazado, así que reventaba en cuanto el primer módulo devolvía un resultado.
2. **Un diagnóstico sin la línea exacta es una conjetura.** Ese fallo se resolvió instrumentando (`DispatcherUnhandledException` + volcado de `ScriptStackTrace`), no razonando más. Un error dentro de un manejador de WPF no ocurre en ninguna línea del arranque lineal, así que ninguna lectura del código lo iba a señalar.
3. **Si un refactor promete "no cambia nada", que no cambie nada.** Durante la división de la ventana se añadió un `param()` vacío a tres fragmentos para callar a PSScriptAnalyzer. No era la causa del fallo, pero al aparecer este fue el primer sospechoso y hubo que descartarlo antes de poder mirar a otro sitio. La regla se excluye ahora en la configuración del analizador, y los fragmentos son reubicación pura.

---

*Al completar cualquiera de los puntos de la sección 4, márcalo aquí y anótalo en `CHANGELOG.md`.*
