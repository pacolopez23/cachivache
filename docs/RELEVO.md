# Relevo — cómo seguir con Cachivache

Este archivo existe para que otro agente pueda continuar sin haber leído la conversación anterior.
Léelo entero antes de tocar nada. **Está escrito para pegarse como primer mensaje.**

---

## Qué es esto

**Cachivache** es un limpiador de disco para Windows escrito en PowerShell 5.1/7 + WPF, propiedad de
Francisco López. Lo hace **para su portfolio**, así que la calidad del código y de la documentación
importa tanto como que funcione.

- Repositorio: la carpeta `AuditoriaBasura`.
- Se ejecuta con `Cachivache.exe`, que lanza `powershell.exe` (5.1) sin consola visible.
- Las pruebas se ejecutan con PowerShell 7 + Pester.

**Estado hoy: 2055 pruebas en verde, analizador limpio, 50 puntos de la hoja
de ruta cerrados. La suite pasa también en Windows, en PowerShell 5.1 y en 7**, y los seis trabajos
de la integración continua están en verde — nada de eso había pasado nunca hasta el 1 de septiembre
de 2026.

---

## Cómo trabajamos — esto no es opcional

1. **Un punto cada vez.** Nada de tandas grandes. Él dice "procede" y se hace el siguiente punto.
   Cuando se le pregunte qué hacer, se le dan 2–4 opciones concretas con su porqué.
2. **Extraer la decisión a una función pura, y protegerla con una invariante.** Es el patrón central
   del proyecto: cuando dos sitios tienen que decidir lo mismo, se saca a una sola función que se
   pueda probar, y se añade una prueba que prohíba que vuelvan a divergir. Ejemplos ya hechos:
   `Get-MotivoNoSeBorra`, `Test-DebeVenirMarcado`, `Get-LineasConfirmacion`,
   `Format-ResumenSimulacion`, `Test-DebeAvisarDelFallo`.
3. **Toda invariante se verifica por mutación.** Se rompe el código a propósito, se comprueba que la
   prueba falla *por el motivo correcto*, y se restaura. Una invariante que no se ha visto fallar no
   sirve para nada. Esto ha cazado ya siete pruebas que pasaban mirando otra cosa.

   **Usa `tools/Mutar.ps1`, no un sustituidor a mano.** Existe porque este paso se rompió dos veces
   en una sola sesión, siempre igual: el sustituidor no encontraba el texto, no decía nada, y la
   suite pasaba. El paso que existe para no fiarse de que una prueba pasa dio por buena una prueba
   porque pasaba. `Invoke-Mutacion` **lanza** si el texto no aparece o si aparece más de una vez, y
   restaura el archivo aunque el bloque reviente.

   **Y verifica la mutación sobre lo que el `It` ve, no sobre lo que crees que ve.** Una lista
   construida en el cuerpo de un `Describe` se evalúa en el DESCUBRIMIENTO de Pester y llega
   **vacía** a los `It`. La suite se queda en verde diciendo lo contrario de la verdad, y solo se
   ve mutando. Regla: **si un `It` lo lee, se construye en un `BeforeAll`.** Ha mordido tres veces.
4. **Dos mitades escritas en paralelo pueden estar las dos en verde y no encajar.** Pasó con
   `VEL-02`: 55 y 82 pruebas, todas pasando, y las dos partes discrepaban en la forma de la tabla
   que se pasaban. Coincidían en lo que estaba *acordado* y discrepaban en lo que nadie había
   acordado. **Cuando dos trabajos van a tocarse, escribe la prueba que recorre el camino entero
   antes de darlos por buenos** — una costura solo se ve desde los dos lados.
5. **Si el arnés de pruebas necesita un apaño que el programa no tiene, el apaño es el síntoma.**
   Al escribir las pruebas del modo consola, la que borra de verdad falló con *"el término
   `Invoke-VaciarColaRegistro` no se reconoce"*. Se dio por hecho que era una rareza de Pester y se
   rodeó cargando el núcleo como módulo, que hace globales las funciones y hace desaparecer el
   error. **Era un fallo del programa**, y siguió vivo hasta que una limpieza real en la CI murió
   con ese mismo mensaje. Carga, invoca y resuelve **igual que `Cachivache.ps1`**; cuando no puedas,
   para y pregunta por qué el programa no lo necesita.
6. **Los comentarios explican el PORQUÉ, no el qué.** El repositorio está lleno de comentarios que
   cuentan qué fallaba antes y por qué la solución es esa. Mantén ese nivel: es media nota del
   portfolio. Comentarios en ASCII sin tildes; el texto que lee el usuario, con tildes y eñes.
7. **Todo archivo `.ps1` y `.xaml` va en UTF-8 CON BOM.** Hay una prueba que lo comprueba.
8. **Se borra el código muerto.** No se deja "por si acaso".
9. **Documentar al cerrar cada punto**: banner `> ✅ **RESUELTO.**` en `docs/HOJA-DE-RUTA.md`
   (conservando el análisis original debajo, porque explica el porqué) y entrada en `CHANGELOG.md`.

---

## Cómo ejecutar las pruebas

**Un solo comando**, desde la raíz del repositorio:

```bash
~/pwsh/pwsh -NoProfile -File tools/Probar.ps1
```

Eso ejecuta la suite entera, el analizador y el suelo de cobertura, y deja el informe en
`pruebas/ultima-pasada.txt` más una copia fechada al lado. Sale con código 0 si todo está en verde
y 1 si no, así que sirve igual en la integración continua —donde ya lo usa el trabajo *Pasada
completa*— y en un gancho de git.

Opciones:

- `-Rapido` — sin medir cobertura. Medirla multiplica por tres o cuatro lo que tarda, así que
  mientras se itera sobre un punto no compensa.
- `-Ruta tests/Cli.Tests.ps1` — un solo archivo.
- `-SinRegistro` — no escribe el informe en disco.

**Antes existía un bloque de PowerShell que había que pegar a mano desde aquí.** Se sustituyó por
el guion porque un ritual copiado a mano es exactamente el tipo de cosa que se rompe en silencio:
basta con que alguien olvide la segunda mitad para que el analizador deje de mirarse durante
semanas.

**Si `~/pwsh/pwsh` no existe, el entorno es nuevo y hay que montarlo primero** (tarda un par de
minutos y solo hace falta una vez por sesión):

```bash
curl -sL https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-x64.tar.gz -o /tmp/pwsh.tar.gz
mkdir -p ~/pwsh && tar -xzf /tmp/pwsh.tar.gz -C ~/pwsh && chmod +x ~/pwsh/pwsh
~/pwsh/pwsh -NoProfile -Command '
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force'
```

### Qué mide, y qué NO mide

`Probar.ps1` imprime la cobertura por carpeta y la compara con el suelo de `tools/Cobertura.ps1`,
que solo puede subir. Hoy:

| Carpeta | Cobertura | Por qué |
|---|---|---|
| `src/Cli` | ~87 % | Estuvo **al 0 %** hasta el 31 de agosto de 2026 |
| `src/Core` | ~85 % | |
| `src/Modules` | ~65 % | Muchos módulos solo encuentran algo si el programa está instalado |
| `src/UI` | ~5 % | **Aquí no hay WPF.** Ese 95 % no lo cubre ninguna prueba que se pueda escribir |

**Cobertura no es lo mismo que probado.** Que una línea se haya ejecutado no dice que haga lo
correcto: el fallo del `ValidateSet` del historial y el de los informes que se anunciaban guardados
sin escribirse vivían los dos en líneas perfectamente cubiertas. Lo que protege este proyecto son
las invariantes y la verificación por mutación; el suelo solo impide que un trozo entero se quede
sin ejecutar nunca, como le pasó a `src/Cli` durante toda su vida.

Y `tests/datos/deuda-de-pruebas.txt` lista **las funciones de `src/` que ninguna prueba nombra**.
La lista solo puede encoger: `tests/Inventario.Tests.ps1` falla si aparece una función sin probar
que no esté ahí, y falla también si un nombre de ahí ya está probado o ya no existe. Es la mejor
lista de "qué hacer ahora" que tiene el proyecto.

**Si tocas cualquier `src/UI/*.xaml`, regenera el oráculo de la ventana antes de ejecutar:**

```bash
~/pwsh/pwsh -NoProfile -Command '
. ./src/UI/Xaml.ps1
$ui = Join-Path (Get-Location) "src/UI"
$m = Expand-PanelesXaml -Texto ([IO.File]::ReadAllText((Join-Path $ui "MainWindow.xaml"))) -Carpeta $ui
[void][xml]$m
[IO.File]::WriteAllText("tests/datos/MainWindow.montado.esperado.xaml", $m, [Text.UTF8Encoding]::new($true))'
```

El `[Text.UTF8Encoding]::new($true)` es obligatorio: sin él se pierde el BOM y falla otra prueba.

---

## Trampas que ya han mordido — no repitas ninguna

Cada una de estas costó una sesión. Están aquí porque volverán a aparecer.

**Del lenguaje**

- **`0xFFFFFFFF` es un `Int32` que vale −1.** Comparado con un `UInt32` da **siempre falso**, sin
  lanzar ni avisar. Si necesitas el valor de verdad, escribe `0xFFFFFFFFL`. Dejó una detección de
  fin de lista que no funcionaba nunca, y lo cazó la mutación, no la prueba.
- **Una función que devuelve un `byte[]` sin la coma no devuelve un `byte[]`.** PowerShell lo
  desenvuelve a `Object[]`, y al enlazarlo a un parámetro `[byte[]]` se **copia**: una prueba de «no
  toca los bytes de quien llama» pasaba sola. Se arregla con `return ,$r`.
- **`-f` se enlaza más fuerte que `+`.** `'texto {0}' + 'más' -f $x` deja el `{0}` literal en
  pantalla. Ha mordido **cuatro veces**. Pon paréntesis siempre: `('a' + 'b {0}') -f $x`.
- **`-f` dentro de `.Add(...)`**: ahí la coma la lee PowerShell como separador de argumentos *del
  método*, no del formato. Arma la cadena en una variable y luego añádela.
**De PowerShell 5.1 contra 7 — la suite pasa aquí en 7 y el programa corre allí en 5.1, así que
esta lista es la frontera más cara del proyecto. Las cinco salieron de una sola tanda de CI.**

- **`.Count` sobre el resultado de una función es `$null` en 5.1** cuando la función devolvió un
  solo objeto: PowerShell desenvuelve la lista de un elemento, y `.Count` sobre un `PSCustomObject`
  suelto vale 1 en PowerShell 7 y **`$null` en 5.1**. Escribe siempre `@(f ...).Count`. Se
  manifestó como `Expected 1 ... but got $null` **solo en la integración continua**.
- **`-Include` se IGNORA con `-LiteralPath` en 5.1.** En 7 filtra; en 5.1 devuelve el árbol entero.
  Una invariante que exigía BOM a los `.ps1` pasó a exigírselo a `.md`, `.yml` y `.gitignore`.
  Filtra por `$_.Extension` a mano.
- **`$IsWindows` NO EXISTE en 5.1**: vale `$null`, así que `if (-not $IsWindows)` es **verdadero en
  Windows**. Una rama escrita para no ejecutarse allí se ejecutaba justo allí. Usa
  `$IsWindows -or ($null -eq $IsWindows)`.
- **`[void]$x.A().B() | Out-Null` revienta en 5.1** con *"Argument type cannot be System.Void"*.
  Cinturón y tirantes a la vez: elige uno. La misma línea sin el `Out-Null` funcionaba.
- **`Remove-Item` sobre un enlace simbólico A UNA CARPETA lanza `NullReferenceException` en 5.1**, y
  `-ErrorAction SilentlyContinue` no lo tapa porque es una excepción del proveedor. Usa
  `[IO.Directory]::Delete($ruta, $false)`, que además nunca sigue el enlace.
- **`.GetNewClosure()` te deja sin las funciones del núcleo.** Copia las variables, sí, pero además
  ejecuta el bloque en un **módulo dinámico**, y ahí la resolución de funciones va contra ese módulo
  y contra **global**. `Cachivache.ps1` dot-sourcea `Bootstrap.ps1` en ámbito de **script**, así que
  desde un cierre no se ve ni una función del programa. Tuvo al modo consola **muriendo al borrar**
  desde `ARQ-01`. Si el bloque necesita valores, ponlos en `$script:` y no uses el cierre.
- **Un `$_` que atraviesa un `&` no es un mecanismo, es una apuesta.** Un scriptblock invocado con
  `&` corre en un ámbito nuevo y con la afinidad de sesión de donde se creó, así que si la variable
  automática llega depende de la versión. Pasa lo que necesite el bloque **como parámetro**.
- **`New-Object System.Collections.Generic.List[...]`** devuelve algo que `@()` no sabe recorrer.
  Rompió todos los informes (`COR-07`). Usa siempre `::new()`. Hay una invariante.
- **`$x = try { } catch { }`** es sintaxis de PowerShell 7. Aquí el programa corre en **5.1**.
- **`[AllowNull()]` en los parámetros `Mandatory`** que puedan recibir nulo. Ha faltado tres veces, y
  las tres lo cazó una prueba de "no revienta con nulo". Escribe siempre esa prueba.
- **Leer un `$null.Propiedad` no lanza; escribirla sí.** Un `FindName` fallido se traga la línea en
  silencio. Si un bloque existe para *decir* algo, comprueba que puede decirlo.

**De las pruebas**

- **Las pruebas que buscan texto encuentran tus propios comentarios.** Ha pasado **siete** veces, y
  las dos últimas el 31 de agosto de 2026: una prueba que prohibía `System.Windows` lo encontró en
  la frase *"ni un tipo de System.Windows"* de la cabecera, y el inventario de funciones dio por
  probadas trece funciones porque el comentario que explicaba que NO lo estaban las nombraba. Quita
  `^\s*#`, `<# #>` y `<!-- -->` antes de buscar.
- **Y quita los bloques `<# #>` ANTES que las líneas que empiezan por `#`.** Al revés —que es como
  está en varios archivos de pruebas— el primer paso se lleva por delante la línea del `#>`, el
  bloque se queda sin cierre y el segundo encuentra el `#>` del bloque siguiente: sobrevive
  documentación entera y desaparece código de verdad.
- **Números mágicos en las expresiones regulares** (`{0,300}` sobre un bloque de 403 caracteres).
  Extrae el elemento y mira dentro, no cuentes caracteres.
- **Toda prueba de texto necesita una guarda previa** del tipo "si no encuentro N cosas, esta prueba
  no está comprobando nada". Ha salvado tres pruebas huecas.
- **Comprueba el *mismo veredicto*, no solo que se rechace.** Una prueba pasó porque una ruta se
  rechazaba por el motivo equivocado.

**De WPF — lo más caro**

- **El contenido de una plantilla (`ControlTemplate`, `DataTemplate`) se analiza TARDE**, la primera
  vez que se aplica. El XAML carga, la ventana abre, y revienta después. Las 928 pruebas y el
  analizador no vieron nada.
- **`Setter TargetName` no puede apuntar a un `Freezable`** (`RotateTransform`, pinceles,
  geometrías): no entran en el ámbito de nombres. Tumbó el programa (`USO-14`). Hay invariante.
- **Un `Style` con `DataTrigger` dentro de la cabecera de grupo se comportó de forma incoherente** en
  Windows: el disparador se aplicaba y el valor por defecto no. **No se pudo averiguar por qué**, y
  por eso se sustituyó por algo sin mecanismo. Regla general: **aquí no hay WPF, así que no dejes en
  el código un mecanismo de XAML que no puedas verificar.** Prefiere lo aburrido.
- **`localStorage` no aplica, pero sí esto**: cualquier cambio en `src/UI/*.xaml` es *no verificado*
  hasta que él lo ejecuta. Dilo claramente cuando entregues.

---

## Lo que hay que pedirle a él, y cómo

**Tú no puedes ejecutar la interfaz.** No hay WPF en el entorno del agente. Él prueba en su Windows
11 Pro con PowerShell 5.1 y está dispuesto a hacerlo, pero:

- **Pídele pocas cosas y en orden**, empezando por la que, si falla, hace inútiles las demás. Ya
  dijo una vez "me estoy perdiendo": tres o cuatro comprobaciones concretas como máximo.
- **Pídele el registro, no la captura**, cuando algo falle. Está en
  `%LOCALAPPDATA%\Cachivache\informes\..` y el registro lleva tipo de excepción y línea desde
  `COR-06`.
- **Si dice que algo "no hace nada", desconfía primero de que esté ejecutando la versión nueva.** Ha
  pasado. Dale un discriminador visual barato ("¿la columna pone TAMAÑO con eñe?") en vez de
  preguntarle si reinició.

---

## Lo que queda abierto

`docs/HOJA-DE-RUTA.md` es la fuente de verdad y está al día. Quedan **10 puntos**, dos de ellos nuevos (`VIS-04` y `VIS-05`). El bloque de
accesibilidad está cerrado, y el de distribución entero salvo la firma. Lo que toca ahora:

| Qué | Por qué |
|---|---|
| **Pasar el banco en la VM** | `docs/BANCO-PRUEBAS.md`. Ahora es **mucho más corto**: la CI ya cubre lo que no exige mirar una ventana. Lo que queda a mano está en su apartado 8. Es lo primero, con diferencia: `COR-01`, `COR-02` y `COR-03` **no se han ejecutado nunca**, y ya son doce puntos entregados que él no ha visto. Cada punto nuevo ensancha esa distancia |
| **Mirar la pestaña Actions** | La CI corre la suite en Windows real, en PowerShell 5.1 y en 7. Aquí solo se ejecuta en Linux con 7. Es información que no existe en ningún otro sitio |
| **Enviar a `winget-pkgs`** | Trámite, no código: los manifiestos ya los genera la publicación. Hasta que se envíen, `winget install` no lo encuentra |
| `USO-11` | Limpiezas programadas. **Tiene una decisión de diseño pendiente que es suya**: qué significa "más conservador en desatendido" |
| `VEL-03` | Marcar 5.000 filas bloquea la ventana. El recorrido es síncrono en el hilo de la interfaz |
| `VIS-04` · `VIS-05` | Los dos huecos frente a WizTree que la hoja de ruta **no contemplaba**: analizar unidades extraíbles (solo analizar, nunca borrar) y enseñar la compresión NTFS. Salieron de comparar función a función en agosto de 2026 |

La deuda de `CNF-01` —la tarjeta de Ajustes que su banner daba por hecha y nunca se hizo— **ya está
cerrada**: *Lo que no se toca nunca*, con la lista y un botón por fila. Queda anotada en su banner.

Deliberadamente **descartados**, con su justificación escrita en la hoja de ruta — no los
reabras sin hablarlo: el deshacer completo de `CNF-03` (necesita COM `IFileOperation`), la casilla de
tres estados de `USO-04`, `VEL-01` (tabla maestra de NTFS), `DIS-01` (firma, necesita certificado) y
`A11Y-02` (no se puede verificar sin WPF delante).

---

## Lo primero que deberías hacer

1. Leer `docs/HOJA-DE-RUTA.md` entero. Es largo y merece la pena: explica el porqué de todo.
2. Ejecutar las pruebas y confirmar **960 en verde y analizador a cero**. Si no cuadra, eso es lo
   primero, antes que cualquier punto nuevo.
3. Preguntarle con qué punto quiere seguir, ofreciéndole las opciones de la tabla de arriba con una
   frase de porqué cada una. No empieces por tu cuenta.
