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

**Estado hoy: 1612 pruebas en verde, analizador limpio, 47 puntos de la hoja de ruta cerrados.**

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
4. **Los comentarios explican el PORQUÉ, no el qué.** El repositorio está lleno de comentarios que
   cuentan qué fallaba antes y por qué la solución es esa. Mantén ese nivel: es media nota del
   portfolio. Comentarios en ASCII sin tildes; el texto que lee el usuario, con tildes y eñes.
5. **Todo archivo `.ps1` y `.xaml` va en UTF-8 CON BOM.** Hay una prueba que lo comprueba.
6. **Se borra el código muerto.** No se deja "por si acaso".
7. **Documentar al cerrar cada punto**: banner `> ✅ **RESUELTO.**` en `docs/HOJA-DE-RUTA.md`
   (conservando el análisis original debajo, porque explica el porqué) y entrada en `CHANGELOG.md`.

---

## Cómo ejecutar las pruebas

Desde la raíz del repositorio, en el entorno Linux del agente.

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

Después:

```bash
~/pwsh/pwsh -NoProfile -Command '
Import-Module Pester -MinimumVersion 5.0
$c = New-PesterConfiguration; $c.Run.Path = "tests"; $c.Output.Verbosity = "None"; $c.Run.PassThru = $true
$r = Invoke-Pester -Configuration $c
"PRUEBAS: {0}  OK: {1}  FALLAN: {2}" -f $r.TotalCount, $r.PassedCount, $r.FailedCount
$r.Failed | ForEach-Object { "=== " + $_.ExpandedPath; $_.ErrorRecord.Exception.Message }
Import-Module PSScriptAnalyzer
"ANALIZADOR: {0} avisos" -f @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1).Count'
```

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

- **`-f` se enlaza más fuerte que `+`.** `'texto {0}' + 'más' -f $x` deja el `{0}` literal en
  pantalla. Ha mordido **cuatro veces**. Pon paréntesis siempre: `('a' + 'b {0}') -f $x`.
- **`-f` dentro de `.Add(...)`**: ahí la coma la lee PowerShell como separador de argumentos *del
  método*, no del formato. Arma la cadena en una variable y luego añádela.
- **`New-Object System.Collections.Generic.List[...]`** devuelve algo que `@()` no sabe recorrer.
  Rompió todos los informes (`COR-07`). Usa siempre `::new()`. Hay una invariante.
- **`$x = try { } catch { }`** es sintaxis de PowerShell 7. Aquí el programa corre en **5.1**.
- **`[AllowNull()]` en los parámetros `Mandatory`** que puedan recibir nulo. Ha faltado tres veces, y
  las tres lo cazó una prueba de "no revienta con nulo". Escribe siempre esa prueba.
- **Leer un `$null.Propiedad` no lanza; escribirla sí.** Un `FindName` fallido se traga la línea en
  silencio. Si un bloque existe para *decir* algo, comprueba que puede decirlo.

**De las pruebas**

- **Las pruebas que buscan texto encuentran tus propios comentarios.** Ha pasado cinco veces. Quita
  `^\s*#`, `<# #>` y `<!-- -->` antes de buscar.
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

`docs/HOJA-DE-RUTA.md` es la fuente de verdad y está al día. Quedan **9 puntos**. El bloque de
accesibilidad está cerrado, y el de distribución entero salvo la firma. Lo que toca ahora:

| Qué | Por qué |
|---|---|
| **Pasar el banco en la VM** | `docs/BANCO-PRUEBAS.md`. Ahora es **mucho más corto**: la CI ya cubre lo que no exige mirar una ventana. Lo que queda a mano está en su apartado 8. Es lo primero, con diferencia: `COR-01`, `COR-02` y `COR-03` **no se han ejecutado nunca**, y ya son doce puntos entregados que él no ha visto. Cada punto nuevo ensancha esa distancia |
| **Mirar la pestaña Actions** | La CI corre la suite en Windows real, en PowerShell 5.1 y en 7. Aquí solo se ejecuta en Linux con 7. Es información que no existe en ningún otro sitio |
| **Enviar a `winget-pkgs`** | Trámite, no código: los manifiestos ya los genera la publicación. Hasta que se envíen, `winget install` no lo encuentra |
| `USO-10` | La tabla salta al reengancharse por módulo: pierde posición y selección. Es lo más molesto de lo que queda |
| `USO-11` | Limpiezas programadas. **Tiene una decisión de diseño pendiente que es suya**: qué significa "más conservador en desatendido" |

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
