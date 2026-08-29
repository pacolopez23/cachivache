# Plan de acción — Cachivache

**Fecha de la auditoría:** 28 de agosto de 2026
**Estado de partida:** 476 pruebas de Pester en verde, 8.685 líneas de PowerShell, 18 módulos.
**Motivo:** tres síntomas reportados en uso real —marca archivos que no son basura, no detecta
muchísima basura real (sobre todo restos de programas y juegos desinstalados), y va lento.

> **Este documento está cerrado.** Las siete fases se completaron el 29 de agosto de 2026. Se
> conserva como registro de qué se arregló, por qué, y qué se decidió no hacer — los comentarios
> del código citan sus identificadores `[SEG-nn]`, `[DET-nn]`, `[FAL-nn]`, `[REN-nn]` e `[INT-nn]`.
>
> **La lista de trabajo vigente es [`HOJA-DE-RUTA.md`](HOJA-DE-RUTA.md).**

## Estado de ejecución

| Fase | Estado | Suite |
|---|---|---|
| 0 — Red de seguridad | ✅ **Hecha** | Banco de 15 pruebas en `tests/Restos.Deteccion.Tests.ps1` |
| 1 — Correcciones críticas | ✅ **Hecha** | 546/546 · analizador limpio |
| 2 — Motor de detección | ✅ **Hecha** | 573/573 · analizador limpio · banco 7 de 7 |
| 3 — Cobertura nueva | ✅ **Hecha** | 605/605 · analizador limpio · 21 módulos |
| 4 — Falsos positivos | ✅ **Hecha** | 613/613 · analizador limpio |
| 5 — Rendimiento | ✅ **Hecha** | 623/623 · analizador limpio |
| 6 — Interfaz y CLI | ✅ **Hecha** | 634/634 · analizador limpio · requiere prueba manual |
| 7 — Higiene del repositorio | ✅ **Hecha** | 634/634 · analizador limpio |

**Medida del banco de detección** (árbol sintético de 12 casos + 1 con partidas guardadas):

| | Restos encontrados | Falsos positivos |
|---|---|---|
| Antes de empezar | **1 de 7** | 0 |
| Tras la fase 1 | 2 de 7 | 0 |
| Tras la fase 2 | **7 de 7** | 0 |

Que el módulo encontrara **uno de siete** restos reales, con cero falsos positivos, es el
resultado más útil de toda la auditoría: confirmó que el problema no era que la guardia fuese
demasiado estricta, sino que el reconocimiento de "esto ya está instalado" era tan laxo que casi
todo pasaba por instalado.

**Medida de `Test-TokenConocido`** (3.017 tokens de vocabulario, 400 carpetas, que es el orden de
magnitud de un equipo con uso):

| | Tiempo | Restos encontrados |
|---|---|---|
| Antes | 160 ms | 394 de 400 |
| Después | **60 ms** | **400 de 400** |

Las dos columnas venían del mismo defecto. El bucle que recorría el vocabulario entero por cada
carpeta era, a la vez, lo que hacía lento el módulo y lo que le impedía encontrar nada: cuantos
más programas tiene instalados el equipo, más lento iba **y** menos basura veía.

### Lo que añadió la fase 3

De 18 módulos a 21. Los tres nuevos y las ampliaciones cubren la basura que antes era invisible:

| Módulo | Qué encuentra |
|---|---|
| `33-Juegos` | Bibliotecas de Steam leídas del `libraryfolders.vdf` —incluidas las de otros discos—, juegos en `steamapps\common` sin manifiesto, cachés de sombreadores y contenido del taller de juegos ya desinstalados, y cachés de Epic, Battle.net, GOG, EA, Ubisoft y Riot. |
| `32-RestosRegistro` | Versiones antiguas de aplicaciones Electron (`app-1.0.9042`), instaladores de controladores ya aplicados, entradas de desinstalación que apuntan a la nada y huérfanos de Archivos de programa. |
| `37-AppsUWP` | Carpetas de `Packages` de aplicaciones de la Store desinstaladas, y las cachés internas de las que sí están. |

Además: seis cachés de sombreadores más en `10-Caches`, seis herramientas de desarrollo
(`.gradle\wrapper\dists`, `conda`, Playwright…), `C:\Windows\Temp` y siete carpetas de registros
del sistema en `65-LogsSistema`, y doce extensiones de instalador más en `35-Descargas`.

**Tres reglas de seguridad que se llevaron su propia prueba**, porque son las que pueden hacer
daño de verdad:

1. **Sin un solo `appmanifest`, no se declara huérfano ningún juego.** Si Steam no ha escrito los
   manifiestos todavía, "todo lo que hay en `common` sin manifiesto" sería la colección entera.
2. **Sin lista de aplicaciones de la Store, no se declara huérfano ningún paquete.** Mismo
   razonamiento: una lista vacía no es "no hay nada instalado".
3. **Las versiones de Electron se ordenan como versiones, no como texto.** Comparadas como
   cadenas, `app-1.0.10` va antes que `app-1.0.9`, y se propondría borrar la que está en uso.

**Partidas guardadas: nunca.** `My Games`, `Saved Games`, `Ubisoft Game Launcher\savegames` y
`userdata\<id>\<appid>\remote` no se proponen para borrar bajo ningún concepto. De esas carpetas
solo se informa de lo que ocupan, y solo se propone lo que hay dentro que el motor del juego
regenera: `Logs`, `Crashes`, `ShaderCache`, `DerivedDataCache`.

### Lo que cambió la fase 4

El caso más raro de la fase: **el arreglo que más espacio libera era un falso positivo al revés.**
`Clear-ContenidoCarpeta` respetaba el veto por extensión personal también dentro de las cachés, y
`.db`, `.txt`, `.md` y `.csv` están en esa lista. Una caché de navegador o de aplicación es en su
mayor parte SQLite, o sea `.db`: el programa anunciaba "se liberan 600 MB", saltaba casi todo,
liberaba una fracción y después culpaba a "archivos en uso por algún programa abierto", que
además era falso. Ahora las cachés genuinas se vacían enteras. El veto sigue intacto en todo lo
demás, y lo que autoriza levantarlo es el mismo `ForzarPermanente` que ya marcaba "esto es caché
que el programa regenera": un solo hecho con sus dos consecuencias, en vez de dos banderas que
mantener de acuerdo a mano.

El resto, por orden de daño evitado:

| Punto | Qué se corrigió |
|---|---|
| `FAL-01` | Un acceso directo bajo `WindowsApps` o en el perfil de otro usuario da `Test-Path $false` por **falta de permisos**, no porque esté roto. Salía premarcado para borrar. |
| `FAL-02` | Las carpetas vacías fuera de AppData ya no se premarcan: una carpeta recién creada para ordenar está vacía justo porque aún no tiene nada dentro. |
| `FAL-10` | En duplicados mandaba `CreationTime`, que no distingue la copia del original —un archivo restaurado de un respaldo también estrena fecha—. Ahora manda el **sitio**: una copia en Documentos o Imágenes gana a una en Descargas o en un temporal. |
| `FAL-11` | Un archivo idéntico dentro de un árbol con `.exe` o `.dll` hermanos no es una copia sobrante: es una dependencia. Dos programas portables pueden traer la misma DLL. |
| `FAL-05` | `%APPDATA%\Zoom\data` guarda `zoomus.enc.db`, el historial de chat local. Ahora solo se propone `Zoom\logs`. |
| `FAL-07` | `Spotify\Data` es la música descargada para escuchar sin conexión, no una caché. Se separa de `Spotify\Storage` y lleva aviso. |
| `FAL-06` | `.m2\repository` y `.nuget\packages` pueden guardar artefactos hechos con `mvn install` o `dotnet pack` que no están en ningún repositorio remoto. Llevan aviso. |
| `FAL-08` | `vendor` y `target` bajan de "prueba suficiente" a "ambiguas". En Go, `vendor/` se versiona a propósito y es lo que permite compilar sin red. |
| `FAL-13` | Los archivos grandes pasan de riesgo `Alto` a `Medio`: el módulo no borra nada, y pintar de rojo un vídeo tuyo de 8 GB no informa de nada. |

### Lo que midió la fase 5

Banco sintético: 8 proyectos Node con 120 paquetes cada uno, 5.776 directorios.

| Módulo | Antes | Después | |
|---|---|---|---|
| `40-CarpetasVacias` | 3.622 ms | **21 ms** | 172× |
| `20-Proyectos` (recorrido) | 291 ms | **21 ms** | 14× |
| Los tres módulos del banco | 4.270 ms | **522 ms** | 8× |

**El hallazgo de la fase no fue de velocidad.** Al medir el recorrido de `20-Proyectos` salió que
proponía **1.928 carpetas donde solo hay 8 `node_modules`**. Todo paquete npm trae su propio
`package.json`, así que sus `dist`, `build` y `lib` pasaban el filtro de manifiesto y se proponían
por separado *además* del `node_modules` que los contiene: los mismos bytes sumados una y otra vez
en el total que ve el usuario, y borrar el padre dejaba a 1.900 filas apuntando a rutas que ya no
existían. El recorrido con poda —al encontrar una carpeta regenerable, emitirla y no entrar—
arregla el rendimiento y la contabilidad de una vez.

El resto de cambios, por orden de impacto:

| Punto | Cambio |
|---|---|
| `REN-31` | `40-CarpetasVacias` recorre con poda y contesta "¿está vacía?" con `EnumerateFileSystemInfos`, cortando en el primer archivo, en vez de materializar el directorio entero con `Get-ChildItem`. |
| `REN-41` | La guardia precalcula en `Initialize-Guardia` lo que antes recalculaba en cada llamada: el conjunto de antepasados protegidos (un `Contains` O(1) en vez de 30 `StartsWith`) y tres expresiones regulares compiladas en vez de 24 `Contains` y dos regex interpretadas. Se ejecuta una vez por candidato **y por cada archivo** al vaciar una caché. |
| `REN-52` | Duplicados ya no lee archivos enteros para descartarlos: un prefiltro con el tamaño más los primeros y últimos 64 KB. Los últimos importan tanto como los primeros —dos grabaciones de la misma cámara comparten cabecera—, y solo los grupos que sobreviven pagan el SHA-256 completo. |
| `REN-51` | `85-DockerWsl` buscaba `*.vhdx` con `-Recurse` sobre cada paquete de la Store: decenas de miles de archivos para encontrar uno. Ahora mira solo en `LocalState`. |
| `REN-55` | `Test-ProcesoAbierto` hacía un `Get-Process` por nombre —y `10-Caches` lo llama con quince—, o sea quince barridos de la tabla de procesos para responder una pregunta que necesita uno. |

**Lo que no se hizo: el índice compartido (`REN-30`).** Era el punto más grande del plan —una sola
pasada de disco que alimentara a los seis módulos que hoy recorren lo mismo—. Después de la poda y
de los enumeradores, su margen se ha reducido mucho: el recorrido ya no es lo caro. Y el coste
sigue siendo alto: reescribe seis módulos y obliga a mantener en memoria el índice de un perfil
entero, que en 200.000 archivos son decenas de MB. Queda pendiente, con el margen real ya medido y
no estimado, que es mejor sitio del que estaba.

### Lo que cambió la fase 6

**Un runspace por operación en vez de veintiuno.** Se creaba uno por módulo, y cada uno cargaba
`Bootstrap.ps1` entero —los diecinueve archivos de `src/Core`, más de cuatro mil líneas— y volvía
a llamar a `Initialize-Guardia`. Ahora se abre al empezar, se reutiliza para todos los módulos y
lo cierra `$cerrarRunspace` en los tres finales posibles: fin de análisis, fin de borrado y cierre
de la ventana.

**Un fallo al lanzar dejaba el programa inservible.** `$lanzarTrabajo` no tenía `try/catch`: si
`Open()` o `BeginInvoke()` fallaban, no se llegaba a arrancar el temporizador, así que nadie
volvía a mirar el estado. `$estado.Ocupado` se quedaba en `$true` **para siempre**, *Analizar*
deshabilitado y *Cancelar* a la vista sin nada que cancelar. La única salida era cerrar el
programa, y el runspace ya abierto no lo cerraba nadie.

| Punto | Cambio |
|---|---|
| `INT-03` | El botón de tema llamaba a `$refrescarDiscos`, que escribe la configuración que el runspace está leyendo **por referencia** en ese momento. El programa ya se blinda contra esto en Ajustes y en los perfiles; al botón de tema se le olvidó. |
| `INT-04` | `Add_Closing` no declaraba los parámetros del evento, y cerrar en mitad de un borrado perdía la entrada del historial: el programa había borrado archivos de verdad y no quedaba constancia. Ahora anota una `limpieza-interrumpida`. |
| `INT-12` | La ventana anotaba en el historial **todos** los bytes y la consola solo los recuperables: el mismo análisis daba dos cifras distintas según por dónde se lanzara. |
| `INT-11` | La consola no pasaba `-Sync` al motor de borrado, así que perdía las líneas de registro del momento que más importa auditar. |
| `INT-14` | "Elementos encontrados" contaba todo e "Recuperable total" solo los borrables: dos números que no cuadraban en el mismo bloque. |
| `INT-09` | Rama inalcanzable en el temporizador: los tres sitios que cancelan paran el temporizador antes de que ese tick pueda ejecutarse. |

**Esto es lo único de todo el trabajo que no se puede verificar automáticamente**, porque WPF no
arranca en la suite. Se han añadido invariantes estructurales sobre el AST y el texto —que el
núcleo se cargue una sola vez, que el montaje esté dentro de un `try`, que existan los tres
llamantes de `$cerrarRunspace`— y **cinco comprobaciones nuevas en `docs/PRUEBA-MANUAL.md`**, que
son las que hay que pasar en Windows antes de publicar.

### Un punto que NO se hizo: `INT-05`

Mover la paleta de colores a `Theme.Dark.xaml` / `Theme.Light.xaml` con un `DataTrigger` sobre
`Riesgo` haría el cambio de tema instantáneo y eliminaría `Get-ColorRiesgo` y
`Get-ColorAcentoTema` —la paleta está hoy en cuatro sitios—. Pero es una reescritura de los tres
XAML de estilo sujeta a tres invariantes de tema, y el resultado solo se puede juzgar **mirándolo**.
Hacerlo a ciegas, sin poder abrir la ventana, es la clase de cambio que se ve bien en el código y
mal en la pantalla. Queda pendiente para quien pueda ejecutar la interfaz.

### Lo que limpió la fase 7

No había archivos huérfanos que borrar —los dos sospechosos estaban justificados—, así que lo que
ensuciaba el proyecto era documentación que mentía.

| Punto | Cambio |
|---|---|
| `REP-02` | `CHANGELOG.md` pasa de **68 KB a 10 KB**, y no se pierde una palabra: el razonamiento largo se conserva íntegro en `docs/historico/DIARIO-2.0.1.md`. Un registro de cambios sirve para saber **qué** cambió de un vistazo; varios cientos de palabras por entrada son otra cosa, y mezclarlos hacía ilegibles las dos. |
| `REP-01` | `docs/OPTIMIZACIONES.md` **no se mueve** —cuarenta y cinco comentarios del código citan sus `[C-nn]`, y esas referencias tienen que seguir llevando a alguna parte—, pero abre con una advertencia que deja claro que es histórico, y una tabla que marca qué entradas ya están resueltas. Se corrigen las tres afirmaciones falsas que quedaban, incluida la que propone eliminar funciones que ya no existen. |
| `REP-03` | Fuera los recuentos de la documentación —"459 pruebas", "18 módulos"—. Caducaban en cada PR, y el propio documento que denunciaba el problema lo cometía. |
| `REP-05` | `datos-MainWindow-antes-de-partir.xaml` pasa a `tests/datos/MainWindow.montado.esperado.xaml`. El nombre parecía un resto de refactor olvidado e invitaba a borrarlo, cuando es lo único que garantiza que la ventana se reconstruye byte a byte. |
| `REP-06` | El `Remove-Variable` de `Bootstrap.ps1` se ejecuta en el ámbito de quien llama. No se cambia —los tres nombres llevan sufijo propio y no pueden chocar—, pero ahora está escrito por qué eso es lo que lo hace seguro. |
| `REP-07` | `MODULOS.md` documenta los 21 módulos, con los tres nuevos y el módulo de restos reescrito. `ARQUITECTURA.md` explica el runspace compartido y la carrera de datos que eso implica. |

**`REP-04` queda pendiente**: la paleta de colores sigue en cuatro sitios porque depende de
`INT-05`, que no se hizo por no poder verlo en pantalla.

### Dos puntos del plan que NO se hicieron, y por qué

**`FAL-12` (fecha de último acceso en Descargas).** La idea era detectar la aplicación portable
que se ejecuta desde Descargas sin que su `.exe` se modifique nunca. Al implementarlo, una prueba
de regresión existente lo rechazó, y al mirarlo de cerca tenía razón: en Windows la actualización
de la fecha de acceso viene **desactivada de fábrica**, y donde está activa la tocan el antivirus,
la indexación y cualquier copia de seguridad. Fiarse de ella haría **desaparecer candidatos
legítimos en silencio**, y el usuario no puede echar de menos lo que no ve. No fiarse hace que una
aplicación portable salga en una lista que este módulo nunca premarca. Se prefiere el error que se
ve. Sí se conservó la otra mitad: una imagen de disco de más de 1 GB lleva aviso, porque casi
nunca es un instalador que se vuelve a bajar.

**`FAL-16` (excepción del filtro de carpetas personales).** Implementarlo obliga a pasar la lista
de raíces autorizadas a `Get-MotivoIntocable`, que es la función más crítica del programa. El
beneficio es estrecho —alguna caché cuyo último segmento se llame `Downloads`— y el coste es
cambiar la firma de la guardia. No compensa.

### Desviación deliberada del plan

`FAL-20` proponía además retirar el `-Preseleccionado $false` fijo para que los candidatos sin
aviso se marcasen solos. **No se ha hecho, y no debería hacerse.** La escala de riesgo sí se
arregló —ahora distingue de verdad y los colores significan algo—, pero premarcar el borrado
automático de carpetas de programas es otra cosa: este módulo es, por su propia descripción, el
más propenso a falsos positivos, y ahora además mira dos niveles y una zona nueva. Que el usuario
tenga que marcar a mano lo que va a borrar aquí es una propiedad del diseño, no un descuido.

---

## Cómo se usa este documento

Cada hallazgo tiene un **identificador estable** que no cambia aunque se reordene el documento.
Los identificadores se citan en los mensajes de commit y en los comentarios del código, igual que
ya se hace hoy con `[C-xx]` de `docs/OPTIMIZACIONES.md`.

| Prefijo | Familia |
|---|---|
| `SEG` | Seguridad y corrección del motor de borrado |
| `DET` | Detección: basura real que hoy no se encuentra |
| `FAL` | Falsos positivos: se propone algo que no es basura |
| `REN` | Rendimiento |
| `INT` | Interfaz, CLI y concurrencia |
| `REP` | Higiene del repositorio |

Severidad: **Crítica** (miente al usuario o puede destruir datos) · **Alta** (el programa no cumple
lo que promete) · **Media** · **Baja**.

**Regla de trabajo.** Se avanza **fase por fase** y, dentro de cada fase, **archivo por archivo**:
se abre un archivo, se aplican *todos* sus puntos, se ejecuta la suite, se cierra el archivo y no
se vuelve a él. Ningún punto se da por hecho sin su criterio de aceptación verificado.

**Entorno de verificación.** La suite se puede ejecutar entera en Linux (PowerShell 7.6.5 +
Pester 5.7.1): 476/476 en 16 s. El CI de Windows sigue siendo la palabra final para los módulos que
tocan registro y WMI, pero el bucle rápido de desarrollo no necesita Windows.

---

## Resumen: por qué falla el programa

Las tres quejas tienen **una causa dominante cada una**, y todo lo demás es acompañamiento.

**No detecta restos → `Test-TokenConocido` se autocensura.**
`src/Core/Registry.ps1:119-122` declara "conocido" cualquier nombre que contenga *o esté contenido
en* cualquier token del vocabulario, con un mínimo de 4 caracteres. El vocabulario incluye nombres
de servicios (`themes`, `power`, `spooler`), de procesos, de publishers y de todos los `.lnk` del
menú Inicio. En un equipo real son entre 2.000 y 6.000 tokens, muchos genéricos y cortos. El
resultado es que casi cualquier carpeta huérfana encuentra *algo* con lo que casar y se descarta
sin mirarla. A eso se suma que el módulo solo mira el **primer nivel** de AppData —los restos de
juegos viven en `Roaming\<Editor>\<Juego>`, nivel 2— y que **`AppData\LocalLow` no se recorre en
ningún módulo**, que es justo donde todo juego de Unity deja sus datos.

**Marca lo que no es basura → dos agujeros concretos, no un problema de diseño.**
El modelo de lista blanca de `Guard.ps1` es sólido. Pero `ConvertTo-RutaNormalizada` **no quita
tildes**, así que el filtro que protege carpetas personales por su nombre no reconoce `D:\Imágenes`,
`E:\Música` ni `F:\Vídeos` —exactamente los ejemplos que su propio comentario presume de cubrir—.
Y `Test-ArchivoPersonal` mira solo la extensión final, de modo que `Contraseñas.kdbx.bak` es un
`.bak` sin protección y `50-Temporales` lo propone.

**Va lento → se recorre el mismo árbol muchas veces.**
Seis módulos enumeran por separado las mismas carpetas del usuario. `30-RestosProgramas` recorre
cada carpeta sospechosa **tres veces**. La guardia se ejecuta **dos veces** por candidato, con
varios `Get-Item` cada vez. Y el runspace de análisis se crea y arranca **18 veces**, una por
módulo, cargando los 18 archivos de `src/Core` en cada arranque.

---

# FASE 0 — Red de seguridad

**Objetivo:** poder cambiar el motor de detección sin romper nada en silencio.
**Sin esta fase, las fases 2 y 3 no son verificables.** Ninguna otra fase empieza hasta cerrarla.

### `tests/` — banco de pruebas de detección

| ID | Severidad | Trabajo |
|---|---|---|
| `SEG-01` | Alta | **Árbol sintético de restos.** Un `New-ArbolDeRestos` en un helper de pruebas que fabrique en una carpeta temporal un AppData falso: 6 carpetas que son restos reales (juego Unity en LocalLow, editor con un solo juego desinstalado en Roaming nivel 2, app Electron con tres `app-<semver>` viejas…) y 6 que **no** lo son (programa instalado, carpeta con partidas guardadas, carpeta de seguridad, carpeta tocada ayer). |
| `SEG-02` | Alta | **Métrica antes/después.** Una prueba que ejecute el módulo `restos` contra ese árbol y afirme exactamente qué encuentra y qué no. Hoy debe fallar en 6 de 12; al terminar la fase 2 debe acertar 12 de 12. Esta prueba es el contrato de todo el trabajo de detección. |
| `SEG-03` | Media | **Pruebas de caracterización de la guardia.** Fijar por escrito el comportamiento actual de `Get-MotivoIntocable` con rutas con tildes, para que el arreglo `SEG-10` sea un cambio visible y no un efecto colateral. |
| `SEG-04` | Baja | **Documentar el entorno Linux.** Añadir a `CONTRIBUTING.md` cómo levantar PowerShell 7 + Pester 5.7 fuera de Windows y qué pruebas no aplican ahí. |

---

# FASE 1 — Correcciones críticas

**Objetivo:** que el programa deje de mentir. Estos puntos no cambian *qué* se detecta, solo
arreglan lo que ya está mal. Van primero porque son pequeños, aislados y de riesgo cero.

### `src/Core/Guard.ps1`

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `SEG-10` | 299 | **Crítica** | **Las carpetas personales con tilde no están protegidas.** El filtro 5a compara el último segmento contra `imagenes?\|musica\|videos?\|documentos?` sobre una ruta normalizada que conserva los diacríticos. `D:\Imágenes`, `E:\Música`, `F:\Vídeos` y `D:\Vídeos\Boda` quedan fuera. **Arreglo:** aplicar `Remove-Tildes` **solo al último segmento** antes del `-match` —nunca a la ruta entera, que rompería las comparaciones textuales de los filtros 2 y 3—. |
| `SEG-11` | 192-200 | **Alta** | **La guardia se declara lista aunque `Initialize-Guardia` haya fallado a medias.** `Test-GuardiaLista` mira `$script:RutasIntocables`, que se asigna en la primera sentencia. Si algo lanza después, `$script:ExtensionesPersonales` queda a `$null` y `$null -contains $ext` es `$false`: el veto por extensión personal desaparece sin que nada avise. **Arreglo:** una bandera `$script:GuardiaLista = $true` como **última** sentencia de `Initialize-Guardia`, y que `Test-GuardiaLista` compruebe esa bandera. |
| `SEG-12` | 348-350 | Alta | **`Test-NombreSensible` casa subcadenas demasiado cortas.** `eset` dentro de *Presets* y *Reset*, `avg` dentro de *savgame*, `mega` dentro de *Omega*, `clave`/`token` dentro de decenas de nombres de librerías. Cada acierto es un `continue` que oculta un resto legítimo. **Arreglo:** anclar a límites de token —`(^\|[^a-z])palabra`— y exigir coincidencia exacta para las palabras de menos de 6 caracteres. |
| `SEG-13` | 390 | Alta | **El patrón de nombre personal es un prefijo sin cierre.** `image` protege `imagecache.dat`; `document` protege `documentdb.log`; `cv` protege cualquier `cv*.tmp`. **Arreglo:** exigir separador o final: `^(...)([ _\-.]\|$)`. |
| `SEG-14` | 389 | **Crítica** | **Doble extensión: `Contraseñas.kdbx.bak` no está protegido.** `Test-ArchivoPersonal` mira solo `$_.Extension`, que para ese archivo es `.bak`. Lo mismo con `.sqlite.bak`, `.pst.bak`, `.mdb.bak`, `.docx.old`. `50-Temporales` los propone como copias antiguas. **Arreglo:** si la extensión es `.bak`/`.old`/`.tmp`, reevaluar la extensión que queda al quitarla. |
| `SEG-15` | 419 | Baja | **Comentario falso.** Afirma que `Test-BajoRaiz` "sigue existiendo para los sitios que solo quieren el booleano". No hay tal sitio: los llamantes reales usan `Get-RaizQueContiene`. La función se **mantiene** (es un envoltorio de tres líneas con siete pruebas propias en un archivo de seguridad), pero el comentario debe decir la verdad: existe para el contrato de pruebas. |
| `SEG-16` | 45, 239 | Media | **`LongitudMinimaRuta = 15` descarta rutas legítimas.** `D:\Juegos\Steam` son 14 caracteres; `E:\Games\Old`, 12. Son exactamente los sitios donde vive la basura de juegos en discos secundarios. **Arreglo:** sustituir el conteo de caracteres por una regla estructural —al menos dos separadores después de la letra de unidad—. |

### `src/Core/Remove.ps1`

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `SEG-20` | 503 vs 507 | **Crítica** | **Se marca como "Eliminado" lo que falló.** `$Candidato.Hecho` se calcula *antes* de volcar `$script:UltimoError` a `$Candidato.Error`. Un `Remove-Item` denegado deja `Hecho = $true` con `Error` relleno: la CLI lo cuenta como hecho, el CSV pone "Eliminado = True" y el historial suma bytes que nunca se liberaron. Es el peor bug del proyecto: destruye la confianza en el registro de auditoría. **Arreglo:** calcular `Hecho` al final, con el `Error` ya consolidado. |
| `SEG-21` | 440-443 | **Crítica** | **`NpmClean` sí pasa por `cmd.exe`.** `Resolve-EjecutablePermitido 'npm'` devuelve `npm.cmd`, un script por lotes; `& $rutaNpm` lo ejecuta a través del intérprete de comandos, justo lo que `[C-03]` dice haber eliminado. **Arreglo preferido:** eliminar el método `NpmClean` —vaciar la carpeta ya libera el espacio, como reconoce el propio comentario— y con él desaparece la superficie. Alternativa: invocar `node.exe` con `npm-cli.js`. |
| `SEG-22` | 442 | Alta | **Invocación nativa fuera de todo `try`.** En Windows PowerShell 5.1 con `$ErrorActionPreference = 'Stop'`, la salida por *stderr* de un comando nativo puede lanzar y abortar el **bucle de eliminación completo**. Desaparece si se aplica `SEG-21`; si no, envolver en `try/catch` con la preferencia bajada localmente. |
| `SEG-23` | 166 | Media | **El corte a profundidad 32 abandona en silencio.** La carpeta queda a medio vaciar y luego el aviso dice "archivos en uso", que es falso. **Arreglo:** anotar el motivo real en `$script:UltimoError`. |

### `src/Core/Comandos.ps1`

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `SEG-30` | 91-99 | **Crítica** | **La resolución de `docker` y `npm` consulta el PATH, y el docblock de la línea 31 promete lo contrario.** `%LOCALAPPDATA%\Microsoft\WindowsApps` está en el PATH del usuario y es escribible por el usuario: dejar ahí un `docker.exe` basta para que el motor de borrado lo lance con los permisos de la sesión. **Arreglo:** resolver contra rutas ancladas conocidas (`%ProgramFiles%\Docker\...`), y rechazar si la ruta resuelta está en una carpeta escribible por el usuario actual. |

### `src/Core/FileSystem.ps1`

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `SEG-40` | 78-91 | Alta | **Un "acceso denegado" trunca la medición.** El `try` envuelve el bucle de archivos **y** el de subcarpetas: una excepción al enumerar archivos impide apilar las subcarpetas, así que la rama entera del árbol no se cuenta. El tamaño sale por debajo del real y el candidato puede caer por debajo del umbral y desaparecer. **Arreglo:** dos `try/catch` independientes, uno por bucle. |

### `src/Core/ModuleRegistry.ps1`

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `SEG-50` | 108-112 | Media | **Si un módulo lanza a mitad, se pierden los candidatos que ya había emitido.** `$candidatos = @(& $Modulo.Buscar ...)` descarta la asignación entera. Además el `catch` guarda solo `.Message`, sin `ScriptStackTrace`, lo que hace muy difícil diagnosticar el fallo. **Arreglo:** acumular en un `List[object]` alimentado por el pipeline, y registrar la traza. |
| `SEG-51` | 36-45 | Media | **Un módulo con salida accidental se descarta en silencio.** `$modulo = . $archivo` produce un array, `.PSObject.Properties['Buscar']` da `$null`, y el `Write-Warning` no se ve en modo ventana. **Arreglo:** `@(. $archivo) \| Where-Object { $_.PSObject.Properties['Buscar'] } \| Select-Object -Last 1`. |

### `src/Core/Ejecutables.ps1` · `Historial.ps1` · `Log.ps1` · `Report.ps1`

| ID | Ubicación | Severidad | Problema y arreglo |
|---|---|---|---|
| `SEG-60` | `Ejecutables.ps1:88` | Media | `Test-Path -LiteralPath` devuelve `$true` para directorios: una entrada de arranque que apunte a una carpeta se da por sana. Añadir `-PathType Leaf`. |
| `SEG-61` | `Ejecutables.ps1:147` | Media | `Get-DestinoAccesoDirecto` crea un `WScript.Shell` si no se le pasa y **nunca** libera el COM. Hacer el parámetro obligatorio y liberar en un `finally` del módulo llamante. |
| `SEG-62` | `Historial.ps1:127-136` | Media | Lectura-modificación-escritura de `historial.json` sin bloqueo: la ventana y la CLI a la vez pierden entradas. Escribir a `.tmp` + `File.Replace`, o abrir con `FileShare.None` y reintentos. |
| `SEG-63` | `Log.ps1:42` | Baja | `$script:DescripcionSistema` nunca se declara. Inicializarla junto a `$script:RutaRegistro`. |
| `SEG-64` | `Report.ps1:57` | Baja | `ConvertTo-CsvSeguro` mira `$Texto[0]` sin recortar: `" =cmd\|..."` pasa el filtro y Excel lo evalúa igual tras el *trim*. Comprobar sobre `$Texto.TrimStart()`. |

**Criterio de cierre de la fase 1:** suite en verde, más una prueba nueva por cada punto Crítico o
Alto que falle contra el código actual y pase contra el arreglado.

---

# FASE 2 — El motor de detección

**Objetivo:** que `30-RestosProgramas` deje de autocensurarse. Esta es la fase que resuelve la queja
principal. Es también la más delicada: aquí se sube la sensibilidad, así que **cada punto que
aumenta la detección va acompañado de su contrapeso** en la escala de riesgo.

### `src/Core/Texto.ps1`

| ID | Severidad | Trabajo |
|---|---|---|
| `DET-01` | Alta | **Variante sin dígitos.** `ConvertTo-Token` borra los dígitos, así que `Python39` no casa con `python` y `Office 2016` / `Office 2021` producen tokens distintos. Devolver además una variante normalizada sin sufijo numérico y comparar contra ambas. |
| `REN-01` | Media | **Atajo ASCII en `Remove-Tildes`.** Recorre carácter a carácter con una llamada a `GetUnicodeCategory` por carácter, y se ejecuta por cada nombre de carpeta *y* por cada token del vocabulario. Salir antes si la cadena es ASCII puro cubre el 95 % de los casos. |

### `src/Core/Registry.ps1` — **el punto más importante de todo el plan**

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `DET-10` | 119-122 | **Crítica** | **`Contains` bidireccional con umbral 4.** Es la causa raíz de "no detecta restos". **Arreglo en tres partes:** (1) coincidencia **exacta** contra el `HashSet` como caso normal; (2) coincidencia por prefijo solo si el token candidato cubre al menos el 70 % del conocido y ambos superan los 6 caracteres; (3) **partir el vocabulario en fuerte y débil** —`DisplayName`, carpeta de `Program Files` y `InstallLocation` son evidencia fuerte; nombres de servicio, de proceso y de `.lnk` son débiles y solo valen para coincidencia exacta—. |
| `REN-10` | 119 | **Crítica** | El bucle `foreach ($conocido in $Tokens)` recorre el `HashSet` entero (2.000-6.000 entradas) por cada una de las 300-800 carpetas de las tres zonas: millones de `String.Contains` en PowerShell interpretado. **Con `DET-10` el bucle desaparece** y queda un `HashSet.Contains` O(1). Este punto se cierra solo. |
| `DET-11` | 36, 116, 120 | Media | Umbral de longitud a 3 en ambos sitios (`nvda`, `obs`, `vlc` nunca se examinan hoy), y borrar la comprobación `$conocido.Length -lt 4` de la línea 120, que es **rama inalcanzable**: `addToken` ya filtró por longitud. |
| `DET-12` | 41-45 | Media | Falta `HKCU:\SOFTWARE\WOW6432Node\...\Uninstall\*`. Los programas de 32 bits instalados por usuario no aportan tokens, así que sus carpetas se proponen como huérfanas: **falso positivo directo**. |
| `SEG-70` | 63-66 | Media | `$_.Company` fuerza la lectura de `FileVersionInfo` de cada proceso y lanza en procesos protegidos; sin `try` y con `ErrorActionPreference = 'Stop'` puede abortar el módulo. Envolver por proceso, o eliminar `Company` (sus tokens ya vienen de `Publisher`). |
| `REN-11` | 70 | Media | `Get-AppxPackage` cuesta entre 1 y 5 s y solo lo necesita un módulo. Ejecutarlo perezosamente y cachear el `HashSet` completo durante la sesión: hoy se reconstruye entero en cada análisis. |

### `src/Modules/30-RestosProgramas.ps1`

| ID | Línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `DET-20` | 36 | **Crítica** | **`AppData\LocalLow` no se recorre.** Es donde todo juego de Unity deja `Player.log`, volcados y datos, y donde quedan los restos de los desinstalados. Añadir `$env:USERPROFILE\AppData\LocalLow` a `$zonas` y recorrerlo a **profundidad 2** (`<Empresa>\<Juego>`), que es su forma real. `locallow` sigue en `$protegidas` para no proponer la raíz; eso no impide entrar. |
| `DET-21` | 48 | **Crítica** | **Solo se mira el primer nivel.** `Ubisoft`, `Electronic Arts`, `Square Enix`, `2K Games`, `Riot Games`, `Adobe` y `JetBrains` existen como token conocido, así que **todo su interior es invisible para siempre** —incluidos los juegos y las apps concretas ya desinstaladas—. **Arreglo:** si una carpeta de nivel 1 es conocida y contiene solo subcarpetas, evaluar cada hija de nivel 2 con el mismo criterio. |
| `FAL-20` | 79 | Alta | **La escala de riesgo está rota e invertida.** `if ($avisos) {'Alto'} elseif ($dias -gt 365) {'Medio'} else {'Alto'}`: como el filtro de la línea 62 ya garantiza `$dias >= DiasSinUso`, todo lo de 180-365 días sale **Alto**; y con `-Preseleccionado $false` fijo en la línea 86, el módulo **no marca nunca nada**. Además contradice la lógica del resto del programa: más antiguo = más seguro, no menos. **Arreglo:** `Bajo`/`Medio` según antigüedad, `Alto` solo con avisos, y retirar el `-Preseleccionado $false` para los casos sin aviso. |
| `REN-20` | 58, 67, 72 | Alta | **Tres recorridos recursivos completos por carpeta candidata**, más un `Get-ChildItem` por cada subcarpeta valiosa encontrada. **Arreglo:** una sola pasada estilo `Get-ResumenArbol` ampliada con predicados, que devuelva a la vez bytes, fecha del último cambio, subcarpetas valiosas y conteo por extensión. |
| `REN-21` | 58 vs 63 | Alta | **Se mide antes de preguntar a la guardia.** Es lo contrario de lo que hacen `10-Caches:101`, `15:62`, `20:73` e `Invoke-BusquedaPorLista`, y de lo que dice `docs/RENDIMIENTO.md §7`. Mover `Test-RutaSegura` arriba. |

**Criterio de cierre de la fase 2:** `SEG-02` pasa de 6/12 a **12/12**. Ninguna de las 6 carpetas
"que no son restos" aparece propuesta. Tiempo del módulo `restos` medido antes y después.

---

# FASE 3 — Cobertura nueva

**Objetivo:** encontrar la basura que hoy no está en ningún módulo. Se hace **después** de la
fase 2 porque el motor de detección arreglado es la base sobre la que se apoya casi todo.

### Módulo nuevo: `src/Modules/33-Juegos.ps1`

La cobertura de juegos hoy es prácticamente cero: una única entrada, `Steam\htmlcache`.

| ID | Severidad | Alcance |
|---|---|---|
| `DET-30` | **Crítica** | **Steam, instalaciones huérfanas.** Leer `config\libraryfolders.vdf` y, por cada biblioteca, proponer las `steamapps\common\<Juego>` sin su `appmanifest_<appid>.acf`. Son decenas de GB. Exigir que exista `steamapps\` y que la unidad esté en línea, para no proponer nada de un disco desmontado. |
| `DET-31` | Alta | **Steam, basura pura** (riesgo Bajo, se regenera): `steamapps\downloading`, `steamapps\temp`, `steamapps\workshop\downloads`, `depotcache\*.manifest`, `appcache\httpcache`, `logs`, `dumps`. |
| `DET-32` | Alta | **Steam, shadercache y workshop huérfanos.** `steamapps\shadercache\<appid>` y `workshop\content\<appid>` sin `appmanifest` correspondiente. Entre 5 y 20 GB habituales. El *workshop* lleva aviso: son mods descargados. |
| `DET-33` | Media | **Steam, `userdata\<id>` de cuentas viejas**, contrastado con `config\loginusers.vdf`. **Riesgo alto**: `userdata\<id>\<appid>\remote` son partidas en la nube → solo `Informativo`. |
| `DET-34` | Alta | **Epic.** Manifiestos de `%ProgramData%\Epic\...\Manifests\*.item` cuyo `InstallLocation` ya no existe (informativo), y `%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache`, que puede superar los 50 GB. |
| `DET-35` | Alta | **Battle.net / Blizzard.** `%ProgramData%\Battle.net\Cache`, `%LOCALAPPDATA%\Battle.net\Cache`, `%APPDATA%\Battle.net\Logs`, `%ProgramData%\Blizzard Entertainment\Battle.net\Cache`. De 2 a 8 GB habituales, todo regenerable. |
| `DET-36` | Media | **GOG, EA/Origin, Ubisoft Connect, Riot, Xbox.** Cachés y logs de cada lanzador, y carpetas de juego sin entrada de desinstalación. **Excepción marcada en rojo:** `Ubisoft Game Launcher\savegames` son partidas guardadas y no se toca jamás. |
| `DET-37` | Alta | **`Documents\My Games` y `%USERPROFILE%\Saved Games`.** La carpeta del juego es **partida guardada** → `Informativo`, nunca premarcado. Lo que sí es seguro proponer con riesgo Bajo es su interior: `<Juego>\Saved\Logs`, `\Saved\Crashes`, `\Saved\DerivedDataCache`. |

### Módulo nuevo: `src/Modules/32-RestosRegistro.ps1`

| ID | Severidad | Alcance |
|---|---|---|
| `DET-40` | Alta | **Entradas de desinstalación fantasma.** Recorrer las claves `Uninstall` y señalar las que apuntan a rutas inexistentes. **Informativo** siempre: el programa no escribe jamás en el registro. Efecto colateral valioso: esas entradas son parte de lo que hoy hace que `Test-TokenConocido` proteja carpetas de programas ya desinstalados. |
| `DET-41` | Alta | **Huérfanos en Program Files.** Carpetas sin entrada de desinstalación, sin servicio y sin acceso del menú Inicio. La guardia veta las raíces pero no las hijas. Riesgo **Alto**, sin premarcar; excluir `WindowsApps`, `Common Files`, `Windows *`, `Microsoft *`, `dotnet`, `ModifiableWindowsApps`. |
| `DET-42` | Alta | **Versiones antiguas de apps Electron.** Patrón universal: `%LOCALAPPDATA%\Discord\app-1.0.90xx`, `\slack\app-*`, `\GitHubDesktop\app-*`, `%LOCALAPPDATA%\Microsoft\Teams\previous`, `SquirrelTemp`. Se conservan versiones viejas de 150-400 MB cada una. Proponer todas salvo la de versión más alta. Riesgo Bajo. |
| `DET-43` | Alta | **Instaladores de controladores ya aplicados.** `C:\NVIDIA\DisplayDriver\<versión>` (800 MB por versión, se acumulan), `%ProgramFiles%\NVIDIA Corporation\Installer2`, `%ProgramData%\NVIDIA Corporation\Downloader`, `C:\AMD\<versión>`, y las carpetas OEM `C:\swsetup`, `C:\Drivers`, `C:\Dell`, `C:\hp`. Riesgo Bajo. **El `DriverStore` sigue vetado, y bien.** |

### Módulo nuevo: `src/Modules/37-AppsUWP.ps1`

| ID | Severidad | Alcance |
|---|---|---|
| `DET-50` | Alta | **`%LOCALAPPDATA%\Packages` de apps desinstaladas.** Contrastar cada `<PackageFamilyName>` con `(Get-AppxPackage).PackageFamilyName`. Riesgo **Medio** con aviso: `LocalState` puede tener datos del usuario. Para los paquetes **instalados**, `LocalCache`, `TempState` y `AC\INetCache` son riesgo Bajo y regenerables. |

### Ampliaciones a módulos existentes

| ID | Archivo | Severidad | Alcance |
|---|---|---|---|
| `DET-60` | `10-Caches.ps1` | Alta | **Cachés de shaders incompletas:** `NVIDIA\ComputeCache`, `NVIDIA Corporation\NV_Cache`, `LocalLow\NVIDIA\PerDriverVersion\DXCache`, `AMD\DxcCache`, `AMD\GLCache`, `AMD\VkCache`, `Intel\ShaderCache`. Todas se regeneran solas. |
| `DET-61` | `10-Caches.ps1` | Media | **Herramientas de desarrollo que faltan:** `.gradle\wrapper\dists` (una distribución por proyecto), `.gradle\daemon`, `.conda\pkgs` (5-15 GB), `Android\Sdk\system-images`, `.android\avd` (informativo: contiene estado), `Yarn\Berry\cache`, `ms-playwright`, `electron`, `electron-builder\Cache`, `VisualStudio\<ver>\ComponentModelCache`. |
| `DET-62` | `65-LogsSistema.ps1` | Alta | **`C:\Windows\Temp` no se limpia en ningún sitio** —solo se cubre el `Temp` del usuario—. Añadir también `Logs\waasmedic`, `Logs\SIH`, `Logs\MoSetup`, `Logs\NetSetup`, `debug\*.log`, `inf\setupapi.dev.log` (llega a GB), `USOShared\Logs`. |
| `DET-63` | `70-WindowsUpdate.ps1` | Alta | **Carpetas `$` de raíz:** `$WinREAgent` y `$GetCurrent` (borrables tras una actualización completada, riesgo Bajo), `$SysReset`, `$Windows.~BT`, `$Windows.~WS` (informativos), `C:\ESD`, `C:\Config.Msi`, `C:\OneDriveTemp`, `C:\PerfLogs`. |
| `DET-64` | `85-DockerWsl.ps1` | Media | **Distros WSL desregistradas cuyo `.vhdx` sigue en disco** —esa es la basura real—: leer `HKCU\...\Lxss\*\BasePath` y detectar los huérfanos. Añadir también `%LOCALAPPDATA%\wsl\{GUID}\ext4.vhdx` y `docker builder prune -a`. |
| `DET-65` | `35-Descargas.ps1` | Media | Mirar también Escritorio y Documentos, no solo Descargas. Extensiones que faltan: `.msu`, `.msp`, `.msixbundle`, `.appxbundle`, `.jar`, `.apk`, `.vhd`, `.esd`, `.torrent`, `.part`. |
| `DET-66` | `65` o `70` | Media | **Office:** `%ProgramFiles%\Microsoft Office\Updates\Download` y `%ProgramData%\Microsoft\Office\ClickToRun` (versión anterior conservada, 2-4 GB). |
| `DET-67` | nuevo `72` | Media | **`C:\Windows\Installer` huérfano y `$PatchCache$`**, de 3 a 10 GB. **Riesgo alto**: borrar un `.msi` vivo impide desinstalar y reparar → informativo o con aviso obligatorio. Requiere admin. |
| `DET-68` | `Guard.ps1` | Media | **`%ProgramData%\Package Cache`** (instaladores de Visual Studio y VC++, 3-8 GB) está **doblemente vetado** —ruta exacta *y* fragmento prohibido—, así que es incobrable por diseño. La vía segura no es levantar el veto sino un candidato `Informativo` que explique usar el propio instalador de Visual Studio. |

**Criterio de cierre de la fase 3:** cada módulo nuevo con su archivo de pruebas y un árbol
sintético propio. Ninguna ruta de partidas guardadas premarcada — prueba explícita para
`My Games`, `Saved Games`, `Ubisoft...\savegames` y `Steam userdata`.

---

# FASE 4 — Falsos positivos, módulo a módulo

**Objetivo:** que nada de lo propuesto sea algo que el usuario quiere conservar. Va después de la
fase 3 a propósito: primero se sube la sensibilidad, luego se recorta con precisión.

| ID | Archivo:línea | Severidad | Problema y arreglo |
|---|---|---|---|
| `FAL-01` | `45-AccesosRotos.ps1:62,70` | Alta | **Un acceso directo a un destino sin permiso de lectura se declara roto.** `Test-Path` devuelve `$false` tanto si el destino no existe como si el usuario no puede leer la carpeta —caso típico: `Program Files\WindowsApps`—, y el candidato sale **premarcado**. **Arreglo:** distinguir "no existe" de "no puedo mirar", y no premarcar destinos bajo `WindowsApps` ni bajo otro perfil de usuario. |
| `FAL-02` | `40-CarpetasVacias.ps1:90` | Alta | **Carpetas vacías del usuario, premarcadas.** Una carpeta recién creada para organizar —"Fotos boda\Sin clasificar"— desaparece por defecto. **Arreglo:** no premarcar fuera de AppData, exigir cierta antigüedad de `CreationTime`, y respetar las que tienen `desktop.ini` de personalización. |
| `FAL-03` | `50-Temporales.ps1:33,76` | Alta | **`.bak` de bases de datos y gestores de contraseñas.** Se resuelve en la raíz con `SEG-14`; aquí queda verificar que el módulo hereda la protección y añadir la prueba. |
| `FAL-04` | `10-Caches.ps1:39` | Media | **`EpicGamesLauncher\Saved` completo** incluye `Config\Windows\GameUserSettings.ini`, los ajustes del lanzador. Apuntar a `Saved\Logs` y `Saved\webcache*` por separado. |
| `FAL-05` | `10-Caches.ps1:50` | Media | **`%APPDATA%\Zoom\data`** contiene `zoomus.enc.db` —historial de chat local— y grabaciones, no solo caché. Limitar a `Zoom\data\*.log` y `Zoom\logs`. |
| `FAL-06` | `10-Caches.ps1:25,27,28` | Media | **`.m2\repository`, `.nuget\packages`, `.cargo\registry`** no son solo caché: `mvn install` deja ahí artefactos que no están en ningún repositorio remoto. Añadir aviso explícito, o excluir los paquetes sin `_remote.repositories`. |
| `FAL-07` | `10-Caches.ps1:43` | Baja | **`Spotify\Data`** es la música descargada para escuchar sin conexión. Preferir `Spotify\Storage` y dejar `Data` como menor con aviso. |
| `FAL-08` | `20-Proyectos.ps1:18` | Media | **`vendor` y `target` no son patrones inequívocos.** En Go, `vendor/` se versiona y es necesario para compilar sin red; `target` es un nombre común fuera de Rust y Maven. Moverlos a `$patronAmbiguo`. |
| `FAL-09` | `20-Proyectos.ps1:20,58-67` | Baja | `bin`/`obj` deben exigir manifiesto **del ecosistema correcto** (`*.csproj`, `*.sln`), no cualquier manifiesto: un `bin` junto a `requirements.txt` puede tener binarios irrecuperables. |
| `FAL-10` | `55-Duplicados.ps1:74,77` | Media | **Se conserva por `CreationTime`, que no distingue la copia del original.** Un archivo restaurado de una copia de seguridad también tiene fecha nueva, así que se puede proponer borrar el de la biblioteca ordenada y conservar el de una carpeta temporal. **Arreglo:** desempatar por zona y profundidad —preferir Documentos e Imágenes sobre Descargas y Temp— y mostrar siempre las dos rutas. |
| `FAL-11` | `55-Duplicados.ps1:82` | Media | **Activos idénticos que deben existir dos veces.** DLLs, fuentes o texturas repetidas en dos carpetas de aplicación: borrar una rompe el programa. Excluir árboles que contengan un `.exe` o `.dll` hermano. |
| `FAL-12` | `35-Descargas.ps1:59-60` | Media | Un `.iso` puede ser una máquina virtual o un respaldo; un `.exe` puede ser una aplicación portable en uso. Usar `LastAccessTime` además de `LastWriteTime`, y dar aviso a las imágenes de más de 1 GB. |
| `FAL-13` | `60:41`, `90:97`, `95:41` | Baja | **Los candidatos informativos salen con riesgo `Alto`.** Nunca borran nada, pero pintan de rojo la lista entera y contaminan el resumen. Por convención, `Metodo = 'Informativo'` debería implicar riesgo `Bajo`: `New-Candidato` ya garantiza que no se premarquen. |
| `FAL-14` | `90-Arranque.ps1:87-97` | Media | Verificar que `Get-EjecutableDeComando` normaliza de verdad los `PathName` con `\??\` y variables antes de declarar un servicio roto. Hay cobertura en `Ejecutables.ps1`, pero falta la prueba de extremo a extremo. |
| `FAL-15` | `Guard.ps1:136-152` | Media | **`.db`, `.txt`, `.md` y `.csv` en `ExtensionesPersonales`** hacen que `Clear-ContenidoCarpeta` salte cualquier `.db` de una caché, que suele ser la mayor parte del espacio. **Arreglo:** aplicar el veto por extensión solo fuera de raíces declaradas explícitamente como caché. Este punto **aumenta** lo que se libera sin tocar la seguridad real. |
| `FAL-16` | `Guard.ps1:299` | Media | La excepción del filtro 5a solo cubre `C:\Windows`. Una carpeta de caché cuyo último segmento sea `Downloads` o `Pictures` bajo AppData o ProgramData queda vetada sin motivo. Extender la excepción a las rutas que ya cuelgan de una raíz autorizada por el módulo. |

---

# FASE 5 — Rendimiento

**Objetivo:** que un análisis completo baje de forma medible. Va al final del trabajo funcional
porque optimizar código que va a cambiar es tirar el trabajo. **Cada punto se mide antes y después**
y el número va al commit, como ya hace `docs/RENDIMIENTO.md`.

### El cambio grande: índice único de carpetas de usuario

| ID | Severidad | Trabajo |
|---|---|---|
| `REN-30` | **Crítica** | **Seis módulos enumeran por separado las mismas carpetas.** Escritorio, Documentos, Descargas, Imágenes, Música, Vídeos y OneDrive se recorren enteros una vez por módulo —`20`, `40`, `45`, `50`, `55`, `60`—, y `40` lo hace dos veces. **Arreglo:** una sola pasada en `src/Core`, estilo `Get-ResumenArbol`, que produzca el índice de archivos y carpetas, se cachee en `$Sync` y la consuman los seis. Es, con diferencia, el mayor ahorro disponible. |
| `REN-31` | **Crítica** | **Nueve puntos siguen usando `Get-ChildItem -Recurse` por pipeline.** El propio proyecto midió 179 ms frente a 4 ms sobre 7.200 archivos y documentó el resultado en `FileSystem.ps1:23-63`, pero solo `Get-ResumenArbol` lo aprovecha. Migrar `20:42`, `25:34`, `35:41`, `40:31`, `45:47`, `50:29`, `55:32`, `60:24`, `85:23`. |
| `REN-32` | **Crítica** | **`20-Proyectos` desciende dentro de `node_modules`.** Enumera decenas de miles de subdirectorios y *después* los descarta por nombre. **Arreglo:** recorrido con pila propia que **pode** el subárbol al reconocer la carpeta — no hay nada que buscar dentro. |

### `src/Core/Guard.ps1` y `Remove.ps1`

| ID | Ubicación | Severidad | Trabajo |
|---|---|---|---|
| `REN-40` | `Remove.ps1:165-172` | Alta | `Clear-ContenidoCarpeta` llama a `Test-RutaIntocable` y `Test-ArchivoPersonal` **por cada archivo**: sobre una caché de 200.000 archivos son ~10 millones de operaciones de cadena antes de borrar nada. Validar la carpeta raíz una vez y, dentro, comprobar solo nombre y extensión contra un `HashSet`. |
| `REN-41` | `Guard.ps1:261-271` | Alta | Precompilar los fragmentos prohibidos en un único `Regex` con `RegexOptions.Compiled` dentro de `Initialize-Guardia`, en lugar de dos bucles de 25 y 24 elementos por llamada. |
| `REN-42` | `Guard.ps1:466-531` | Alta | **Cachear el veredicto de `Test-CadenaSinEnlaces` por carpeta padre** en un `Dictionary[string,bool]` de sesión: los enlaces de la cadena son los mismos para todos los archivos de una carpeta, y hoy se recorre la cadena entera con un `Get-Item` por nivel, por candidato. |
| `REN-43` | `ModuleRegistry.ps1:119-125` | Alta | **La guardia se ejecuta dos veces por candidato.** Marcar en `New-Candidato` los que ya la pasaron y comprobar aquí solo el resto, manteniendo la red de seguridad para módulos que se la salten. |
| `REN-44` | `Remove.ps1:135-142` | Media | El barrido anti-enlaces recorre el árbol completo también cuando no hay enlaces, que es el caso normal. Cortar en el primer punto de reanálisis sin construir objetos de PowerShell. |
| `REN-45` | `Remove.ps1:169,178` | Media | `@(Get-ChildItem ...)` materializa el directorio entero antes de borrar, y luego se vuelve a listar cada subcarpeta solo para saber si quedó vacía. `EnumerateFileSystemEntries` y `MoveNext()`. |
| `REN-46` | `Candidate.ps1:251-262` | Media | `Test-Path` + `Test-RutaSegura` (dos `Get-Item`) + `Measure-Ruta` (otro `Get-Item`) sobre la misma ruta. Un solo `Get-Item` reutilizado. |

### Módulos

| ID | Archivo:línea | Severidad | Trabajo |
|---|---|---|---|
| `REN-50` | `75-AlmacenComponentes.ps1:65` | Alta | `Measure-Ruta` sobre **WinSxS**: ~100.000 archivos en la ruta más lenta del sistema, antes de las tres ramas de salida. Y el número es engañoso, porque WinSxS es casi todo enlaces duros y se suman los mismos bytes varias veces. Usar solo la estimación de DISM, o medir únicamente en la rama que lo muestra. |
| `REN-51` | `85-DockerWsl.ps1:20-25` | Alta | `-Recurse -Filter '*.vhdx'` sobre `%LOCALAPPDATA%\Packages` entero: decenas de miles de archivos para encontrar uno o dos. Buscar solo en `Packages\*\LocalState\*.vhdx`. |
| `REN-52` | `55-Duplicados.ps1:63` | Alta | `Get-FileHash` SHA-256 del archivo completo: un grupo de vídeos de 4 GB obliga a leer 8 GB de disco. Prefiltro con los primeros y últimos 64 KB, y hash completo solo si coinciden. |
| `REN-53` | `25-Papelera.ps1:34-38` | Media | Enumeración archivo a archivo por pipeline: decenas de segundos en una papelera grande. Usar `Get-ResumenArbol`, que ya existe. |
| `REN-54` | `95-PerfilesUsuario.ps1:28` | Media | Mide el árbol completo de cada perfil ajeno para un módulo puramente informativo. Medición bajo demanda. |
| `REN-55` | `FileSystem.ps1:351-353` | Baja | `Test-ProcesoAbierto` hace un `Get-Process` **por nombre**; `10-Caches` lo llama con 15. Un solo `Get-Process` contra un `HashSet`. |
| `REN-56` | `25:42`, `30:70`, `85:24`, `Report.ps1:368` | Baja | `+=` sobre arrays dentro de bucles: cada uno reasigna el array completo. `List[object]`, como ya se hace bien en `55:43` y en `Select-RutasNoAnidadas`. |
| `REN-57` | `Report.ps1:240` | Baja | `Sort-Object { -(Measure-TotalBytes ...) }` y luego `Measure-TotalBytes` otra vez sobre el mismo grupo. Calcular una vez. |

---

# FASE 6 — Interfaz, CLI y concurrencia

| ID | Ubicación | Severidad | Problema y arreglo |
|---|---|---|---|
| `INT-01` | `Window.Analisis.ps1:78-106` | Alta | **El runspace se crea y arranca 18 veces**, una por módulo, y cada arranque dot-sourcea los 18 archivos de `src/Core` (4.249 líneas) y llama a `Initialize-Guardia`. **Arreglo:** un solo runspace abierto al empezar, `Bootstrap` cargado una vez, y `$ps.Commands.Clear(); $ps.AddScript(...)` por módulo. Ahorro: 17 arranques en frío. |
| `INT-02` | `Window.Analisis.ps1:87-105` | Alta | **`$lanzarTrabajo` sin `try/catch`.** Si `Open()` o `BeginInvoke()` lanzan, no se llega a `$temporizador.Start()`: `$estado.Ocupado` queda en `$true` **para siempre** —"Analizar" deshabilitado, nada avanza, solo se sale cerrando el programa— y el runspace abierto no se cierra nunca. **Arreglo:** envolver desde `CreateRunspace` hasta `BeginInvoke`, y en el `catch` llamar a `$limpiarTrabajo` y `$terminarAnalisis`. |
| `INT-03` | `Window.Eventos.ps1:34-36` | Alta | **Carrera de datos: el botón de tema no está bloqueado durante un análisis.** `$aplicarTema` llama a `$refrescarDiscos`, que escribe `Configuracion.Unidades` y `UnidadesSeleccionadas` — el mismo objeto que se pasó **por referencia** al runspace. Es la carrera que el código sí blinda en Ajustes y en los perfiles, y que aquí se olvidó. **Arreglo:** si `$estado.Ocupado`, cambiar solo colores. |
| `INT-04` | `Window.Eventos.ps1:613-627` | Media | **`Add_Closing` sin `param($s,$e)`**: imposible cancelar el cierre. Si se cierra en mitad de un borrado, `$terminarBorrado` no corre y **el historial no se escribe**. Además `PowerShell.Stop()` es bloqueante: cerrar mientras se mide una carpeta enorme congela la ventana. **Arreglo:** declarar los parámetros, escribir el historial parcial antes de parar, y usar `BeginStop` en fase de análisis. |
| `INT-05` | `Window.Ayudantes.ps1:477-487` | Media | **Cambiar de tema reconstruye el `DataGrid` entero y hace cuatro consultas a disco.** La raíz es que los colores viajan como cadenas. **Arreglo:** definir los brushes en `Theme.Dark.xaml`/`Theme.Light.xaml` y un `DataTrigger` sobre `Riesgo` en `Styles.xaml`. El cambio de tema pasa a ser instantáneo y **desaparecen `Get-ColorRiesgo` y `Get-ColorAcentoTema`** — que es también `REP-04`. |
| `INT-06` | `Window.Ayudantes.ps1:171-223` | Media | `$refrescarHistorial` lee el JSON **dos veces** y enumera la carpeta de informes **tres**, en el hilo de UI, en cada clic en "Informes". Pasar las entradas ya leídas a `Get-ResumenHistorial` y refrescar solo si cambió la marca de tiempo. |
| `INT-07` | `Config.ps1:138` + `Ayudantes:93` | Media | `Get-UnidadesFijas` se ejecuta dos veces en el arranque, más un `Get-EspacioLibre`. Reutilizar `Configuracion.Unidades` la primera vez. |
| `INT-08` | `Window.Analisis.ps1:270,300` | Baja | `ItemsSource` se desengancha y reengancha **por módulo**: 18 reconstrucciones completas del `DataGrid`, cada vez más caras. Desenganchar una sola vez al empezar y reenganchar en `$terminarAnalisis`. |
| `INT-09` | `Window.Analisis.ps1:347-350` | Baja | **Rama inalcanzable.** Los tres sitios que ponen `Sync.Cancelar = $true` llaman a `$limpiarTrabajo`, que para el temporizador. Borrarla. |
| `INT-10` | `Eventos.ps1:435,509,591` | Baja | El bloque "sincronizar controles de Ajustes" está escrito **tres veces**. Ya divergieron una vez y causó un bug de seguridad —el borrado permanente se rearmaba solo—, y el propio código lo admite en un comentario. Extraer un cierre. |
| `INT-11` | `Cli.ps1:196` | Baja | La CLI no pasa `-Sync` a `Invoke-EliminacionCandidato`, así que se pierden líneas del registro durante el borrado. La ventana sí lo pasa. |
| `INT-12` | `Cli.ps1:160` vs `Analisis:218` | Baja | **La ventana y la consola anotan bytes distintos** en `historial.json` para el mismo análisis: una cuenta todos los elementos, la otra solo los borrables. Unificar en "recuperable". |
| `INT-13` | 4 sitios | Baja | El patrón "genera informe → si falla vacía la ruta → anota historial" está copiado cuatro veces (`Analisis:204`, `Eliminacion:74`, `Cli:135`, `Cli:227`) y **ya divergió** (`INT-12`). Extraer `Write-CierreEjecucion` a `Historial.ps1`. |
| `INT-14` | `Cli.ps1:116-125` | Baja | "Elementos encontrados" usa el total y "Recuperable total" usa solo los borrables: dos cifras que no cuadran en el mismo bloque de salida. |

---

# FASE 7 — Higiene del repositorio

**Hallazgo de partida:** no hay archivos huérfanos. Los dos sospechosos están justificados —
`Cachivache.exe` ya está en `.gitignore` con una razón excelente escrita al lado, y
`tests/datos-MainWindow-antes-de-partir.xaml` es el oráculo de una prueba de regresión real.
**Lo que ensucia el proyecto no son archivos sobrantes, es documentación desactualizada:**
`docs/OPTIMIZACIONES.md` (83 KB) y `CHANGELOG.md` (68 KB) suman **151 KB de los ~470 KB del
proyecto — más que todo `src/`**.

| ID | Ubicación | Severidad | Trabajo |
|---|---|---|---|
| `REP-01` | `docs/OPTIMIZACIONES.md` | Alta | **Describe bugs ya corregidos y funciones que no existen.** `[U-01]` y `[U-02]` denuncian problemas resueltos hace tiempo (hoy hay *debounce* de 250 ms e `IndexOf` ordinal); `[U-03]` propone eliminar `Get-ColoresRiesgo` y cita `FondoRiesgo`, y **ninguno de los dos identificadores existe ya en `src/`**; la discrepancia "cinco filtros / siete filtros" que denuncia **ya se resolvió** en el README; y describe un `src/Core/Walk.ps1` que nunca se creó. Un colaborador nuevo intentará arreglar cosas ya arregladas. **Arreglo:** mover a `docs/historico/AUDITORIA-2.0.0.md` con una cabecera que remita al estado vigente. |
| `REP-02` | `CHANGELOG.md` | Media | No está inflado en número de entradas —son tres versiones— sino en densidad: **el 85 % del archivo es la sección `[Sin publicar]`**, con ensayos de varios cientos de palabras por entrada. Eso es un diario de desarrollo, no un changelog. **Arreglo:** una línea por cambio con enlace al commit, y el razonamiento largo a `docs/`. Objetivo realista: **menos de 8 KB**. |
| `REP-03` | 4 archivos | Baja | **La cifra de pruebas no cuadra:** README y tres documentos dicen 459, `OPTIMIZACIONES.md` dice 144, el código tiene 312 bloques `It` que expanden a más. Quitar el número de los cuatro sitios, o generarlo desde el `testResults.xml` del CI. |
| `REP-04` | 4 archivos | Media | **La paleta de colores está escrita en cuatro sitios:** `Window.ps1:127`, `Window.ps1:153`, `Theme.Dark.xaml:40`, `Theme.Light.xaml:27`. El propio comentario de `Get-ColorRiesgo` lo admite. **Se resuelve con `INT-05`.** |
| `REP-05` | `tests/` | Baja | Renombrar `datos-MainWindow-antes-de-partir.xaml` a `tests/datos/MainWindow.montado.esperado.xaml` y añadirle una cabecera que diga qué prueba lo usa. El nombre actual parece basura y invita a borrarlo. |
| `REP-06` | `Bootstrap.ps1:58` | Baja | El `Remove-Variable` final se ejecuta en el ámbito del llamante y borraría variables suyas que se llamen igual. Trivial hoy, pero es una fuga de la abstracción. |
| `REP-07` | `docs/` | Media | Cerrado el plan, actualizar `ARQUITECTURA.md`, `MODULOS.md` y `ESTRUCTURA.md` con los módulos nuevos y el índice compartido, y dejar **este documento** como el vigente. |

---

## Orden de ejecución y dependencias

```
FASE 0  Red de seguridad ........... bloquea 2 y 3
   │
FASE 1  Correcciones críticas ...... independiente, se puede empezar en paralelo
   │
FASE 2  Motor de detección ......... requiere 0. Es la fase que arregla la queja principal
   │
FASE 3  Cobertura nueva ............ requiere 2 (usa el motor arreglado)
   │
FASE 4  Falsos positivos ........... requiere 3 (primero se sube, luego se recorta)
   │
FASE 5  Rendimiento ................ requiere 4 (no optimizar código que va a cambiar)
   │
FASE 6  Interfaz y CLI ............. independiente de 2-5, se puede intercalar
   │
FASE 7  Higiene del repositorio .... al final, documenta el estado real
```

**Los cinco puntos que más cambian la experiencia, si hubiera que elegir solo cinco:**

1. `DET-10` — `Test-TokenConocido`. Desbloquea el módulo de restos entero.
2. `DET-20` + `DET-21` — LocalLow y profundidad 2. Donde vive la basura de los juegos.
3. `DET-30`…`DET-37` — el módulo de juegos. Decenas de GB que hoy son invisibles.
4. `REN-30` + `REN-31` — índice único y enumeradores. El grueso del tiempo de análisis.
5. `SEG-10` + `SEG-14` + `SEG-20` — los tres agujeros que hacen que el programa mienta.

---

## Reglas que no se rompen en ninguna fase

- **La guardia solo se relaja con una prueba que demuestre por qué.** Cada excepción nueva a
  `Test-RutaIntocable` viene con su caso en `tests/Guard.Tests.ps1`.
- **Nada que contenga partidas guardadas, documentos o credenciales se premarca jamás**, ni
  aunque el módulo lo pida: la invariante vive en `New-Candidato` y ahí se queda.
- **Ningún punto se cierra sin ejecutar la suite completa.**
- **Cada arreglo de rendimiento lleva su medición** antes y después en el mensaje del commit.
- **El programa nunca escribe en el registro de Windows.** Todo lo que se detecte ahí es
  `Informativo`.
