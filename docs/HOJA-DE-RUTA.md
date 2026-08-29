# Hoja de ruta — de programa correcto a programa que la gente elige

**Fecha:** 29 de agosto de 2026
**Punto de partida:** 21 módulos, 643 pruebas en verde, analizador limpio, `docs/PLAN-ACCION.md` cerrado.
**Estado al 29 de agosto de 2026:** 1206 pruebas, analizador limpio, 38 puntos cerrados y **ejecutado en Windows 11 con PowerShell 5.1**.
**Objetivo de este documento:** decidir qué convierte a Cachivache en la mejor opción de su categoría,
y en qué orden hacerlo.

> Este documento sustituye a `PLAN-ACCION.md` como lista de trabajo. Aquel arregló lo que estaba
> roto; este decide hacia dónde crece. Los identificadores son estables y se citan en los commits.

---

## Parte I — Estrategia: en qué hay que ser mejor

Antes de una lista de tareas hace falta una tesis. Si no, se acaba añadiendo funciones porque el
vecino las tiene.

### El terreno, como está hoy

| Programa | Qué hace bien | Dónde falla |
|---|---|---|
| **CCleaner** | Reconocimiento de marca, cubre mucho | Se ha vuelto un producto monetizado con venta agresiva de la versión de pago, y sigue destacando un limpiador de registro que **Microsoft desaconseja expresamente** en Windows moderno. Sus usuarios de siempre se quejan de que se ha hinchado |
| **BleachBit** | Libre de verdad, sin anuncios ni telemetría, sin versión "Pro". Es el que citan los expertos en seguridad | Interfaz austera, **sin red de seguridad**, y sin automatización. Premia al usuario cuidadoso y frustra al principiante |
| **WizTree / WinDirStat** | Enseñan **dónde** se fue el disco con un mapa de árbol. WizTree lee la tabla maestra de NTFS y va 40 veces más rápido que recorrer carpetas | No limpian. Solo miran |
| **Cachivache, hoy** | Guardia con lista blanca, revalidación antes de borrar, explica el efecto de cada cosa, nunca premarca lo dudoso, registro auditable, sin dependencias. **Modo simulación, exclusiones del usuario, tabla ordenable, y dice la verdad cuando algo no se pudo borrar o el análisis quedó a medias** | Sin deshacer real —solo abre la papelera—, solo en español, sin firmar. Ejecutado en un solo equipo |

### El hueco que nadie ocupa

Los tres primeros dejan un espacio libre, y es justo donde Cachivache ya está construido:

> **El limpiador en el que se puede confiar.**
> El que te explica qué va a borrar y por qué es seguro, el que nunca marca solo lo que no está
> claro, el que deja constancia de todo lo que hizo, y el que te deja deshacerlo.

Eso no es una función: es una propiedad del conjunto. Y es **defendible**, porque los otros no
pueden copiarla sin rehacerse: CCleaner tiene un modelo de negocio que empuja en contra, y
BleachBit tiene una cultura de "el usuario sabrá lo que hace".

### Los tres pilares, y qué significa cada uno

**1. Confianza.** Todo lo que el programa hace es explicable, reversible y auditable.
→ Deshacer, modo simulación, exclusiones del usuario, informes honestos, cero mentiras sobre lo
que se hizo.

**2. Criterio.** El valor no está en encontrar más basura, está en **saber qué no tocar**.
→ La guardia, la escala de riesgo, el premarcado por construcción. Ya existe: hay que
protegerlo y hacerlo visible.

**3. Claridad.** El usuario decide con información suficiente, sin leer documentación.
→ Ordenar, agrupar, ver dentro, entender por qué algo viene marcado, saber si el análisis quedó
incompleto.

### Lo que NO vamos a hacer, y por qué

Decidir esto ahora ahorra meses.

- **Limpiador de registro.** Microsoft lo desaconseja, el riesgo es alto, el beneficio es
  imaginario y es la función que más desprestigia a CCleaner. Un "no" explícito en el README es
  una ventaja competitiva, no una carencia.
- **Promesas de rendimiento.** "Acelera tu PC un 300%". Es mentira y el público técnico lo sabe.
- **Complementos de terceros.** Un módulo es código que borra archivos con los permisos del
  usuario. Sin un modelo de restricciones completo, un sistema de complementos es ejecución de
  código arbitrario disfrazada de limpieza.
- **Borrado seguro con sobreescritura.** En SSD con TRIM y con capas de traducción no garantiza
  nada. Prometerlo sería mentir.
- **Más módulos de detección, por ahora.** La cobertura ya es amplia. Cada módulo nuevo suma
  riesgo de falso positivo y superficie que mantener. El techo del proyecto no está ahí.

---

## Parte II — Validación en Windows

### `VAL-01` · Ejecutarlo en Windows · ~~Bloqueante~~ → **Hecho en parte, y hay que seguir haciéndolo**

> ✅ Ejecutado el 29 de agosto de 2026 en Windows 11 Pro con PowerShell 5.1, desde `Cachivache.exe`.
> Análisis completo, informe, simulación de 33 elementos y 9,83 GB. Confirmado funcionando:
> la ventana abre, los módulos encuentran cosas reales, el registro se escribe, el informe se
> genera y la simulación no toca nada.

**Lo que esa ejecución encontró, y ninguna prueba veía:**

| Fallo | Por qué la suite no lo veía |
|---|---|
| `New-Object List[object]` rompía **todos** los informes | Las pruebas pasaban un array; la aplicación pasa una lista |
| Un mensaje salía con `{0}` literal | Las pruebas buscaban un trozo del texto que estaba en las dos versiones |
| La simulación no pasaba por la comprobación de la papelera | Nadie había mirado la salida real |
| *"elementos pequenyos"* en el registro | El invariante era una lista de cinco palabras escrita a mano |

Cuatro fallos en dos ejecuciones. **Esa es la tasa de retorno de mirar la pantalla**, y la razón
de que esto pase de "bloqueante que se hace una vez" a **hábito**: ejecutarlo después de cada
tanda de cambios, no al final.

**Lo que sigue sin comprobarse:**

- Los caminos de Windows de `COR-01`, `COR-02` y `COR-03`: la cuota de la papelera, el prefijo
  `\\?\` sobre una ruta larga de verdad, un marcador de OneDrive. Solo se ejercitan al **borrar**,
  y todavía no se ha hecho un borrado real.
- Que el runspace compartido no filtre memoria: **dos análisis seguidos sin cerrar el programa**.
- El desplazamiento con la altura de fila automática de `USO-01`, con listas de miles de filas.
- Windows en inglés, una cuenta sin privilegios, un equipo con OneDrive activo. Eso es `VAL-02`.

### `VAL-02` · Banco de pruebas en una máquina virtual · Alta

> 🟡 **El banco está hecho y probado. Falta la primera pasada, que es suya.**
>
> `docs/BANCO-PRUEBAS.md` monta la VM y lleva los escenarios en orden, cada uno diciendo qué
> afirmación comprueba y qué tiene que pasar. `tools/Banco-Pruebas.ps1` monta cebos deterministas
> —ruta de más de 260 caracteres, archivo mayor que la cuota de la papelera, dos enlaces duros al
> mismo contenido, duplicados de verdad, 3.000 filas de relleno— y los quita.
>
> **Los cebos van dentro de Documentos, y esa es la decisión de fondo.** Los módulos no recorren el
> disco: miran las `ZonasUsuario`. Un cebo en `C:\pruebas` no lo encuentra nadie, y una prueba que
> el programa no llega a ver no prueba nada. Para servir, el banco tiene que ponerse donde duele —
> que es exactamente por qué esto pide una VM con instantánea y no un rato de tarde.
>
> **Lo que hace que un guion así se pueda tener en el repositorio** es dónde vive la decisión.
> `tools/Banco-Decisiones.ps1` es cálculo puro y va probado con 31 pruebas: dónde está el banco, si
> esto parece una máquina virtual, y sobre todo `Test-DentroDeRaiz`, que es lo único que separa
> *"-Quitar borra el banco"* de *"-Quitar borra Documentos"*. Ahí se normaliza el prefijo `\\?\`
> —la lección de `COR-02`, o el cebo de ruta larga parecería estar fuera de su propia raíz— y se
> exige separador tras la raíz, porque comparar por prefijo a pelo mete
> `Banco-Cachivache-2` dentro de `Banco-Cachivache`. Las dos cosas verificadas mutándolas.
>
> `Banco-Pruebas.ps1` no se puede dot-sourcear sin consecuencias, y por eso las decisiones están
> fuera: mismo reparto que `Xaml.ps1` frente a `Window.ps1`.
>
> **La comprobación de máquina virtual es una red, no una garantía**, y se dice así en el código:
> un hipervisor puede disfrazarse. Lo que evita es el descuido normal —abrirlo en el equipo de
> trabajo y darle a ejecutar—. La garantía es la instantánea.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Una VM de Windows 11 limpia, con una instantánea previa, donde poder:
ejecutar un análisis completo y comprobar que no propone nada del sistema; ejecutar una limpieza
real y restaurar la instantánea; repetirlo con Windows en inglés, con OneDrive y con una cuenta
sin privilegios. Es la única forma de convertir "creo que es seguro" en "lo he comprobado".

---

## Parte III — Correcciones abiertas

### `COR-01` · La papelera borra permanentemente y el programa lo llama papelera · **Crítica**

> ✅ **RESUELTO.** `src/Core/Papelera.ps1`. Si algo no cabría en la papelera **no se borra**: se explica con las dos cifras y se ofrece el borrado permanente. `Test-CabeEnPapelera` es cálculo puro y va probado.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

`Remove-Elemento` usa `DeleteFile` con `SendToRecycleBin`. Cuando un archivo **no cabe en la
papelera** —porque supera su cuota—, Windows lo borra **permanentemente y sin preguntar**, y el
programa lo anota como `PAPELERA`.

Es la misma clase de fallo que `[SEG-20]`, el peor que encontró la auditoría anterior: **el
programa miente sobre lo que hizo**. Y falla en el caso que más duele, con el archivo más grande.
El desarrollador anterior lo dejó escrito y sin tocar porque no podía probarlo sin Windows.

**Arreglo:** leer la capacidad de la papelera del volumen antes de borrar y, si el archivo no
cabe, o bien saltarlo con un aviso explícito, o bien pedir confirmación de borrado permanente.
Nunca llamarlo papelera.
**Criterio de aceptación:** un archivo mayor que la cuota de la papelera no se borra en silencio, y
el registro dice la verdad. Requiere `VAL-02`.

### `COR-02` · Rutas de más de 260 caracteres · Alta

> ✅ **RESUELTO.** Prefijo `\\?\` en `Get-ResumenArbol` (un solo sitio, lo heredan los ocho llamantes) y en el borrado permanente vía `System.IO`. Una ruta larga **no puede ir a la papelera** y se dice.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

No hay ni una aparición del prefijo `\\?\` en todo el proyecto. En PowerShell 5.1 el proveedor de
archivos no soporta rutas largas aunque el registro lo permita: eso llegó a .NET Core, no a .NET
Framework.

Y este dominio es justo donde ocurre: un `node_modules` anidado o una caché de Gradle desbordan
el límite con facilidad. Entonces `Get-ChildItem` falla **en silencio** bajo el
`-ErrorAction SilentlyContinue` que usan casi todos los módulos, el programa **mide de menos y
borra de menos**, y después informa de *"Quedan X: archivos en uso por algún programa abierto"* —
un mensaje falso, exactamente el tipo de fallo que ya se corrigió dos veces en otros sitios.

**Arreglo:** prefijo `\\?\` en las primitivas de `Remove.ps1` y `Measure-Ruta`, o migrarlas a
`System.IO` directo. **Tamaño: medio.**

### `COR-03` · OneDrive con archivos bajo demanda · Alta

> ✅ **RESUELTO.** `Test-EsMarcadorNube` por valor numérico de atributo. **Corrección del diagnóstico de arriba:** medir NO dispara descargas —`Length` sale de la entrada de directorio—; solo las dispara abrir el archivo, o sea el hash.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

El proyecto conoce OneDrive —resuelve las carpetas por API, lo veta en la guardia— pero **ningún
sitio comprueba el atributo `FILE_ATTRIBUTE_OFFLINE`**. Consecuencias reales:

- Medir un árbol con marcadores de posición **dispara descargas de gigabytes** sin avisar.
- El módulo de duplicados calcula hashes, lo que **materializa cada archivo**. En una conexión
  medida, eso es dinero del usuario.

**Arreglo:** detectar el atributo y saltar esos archivos, avisando de cuántos se saltaron.

### `COR-04` · Las cuatro listas de métodos que pueden divergir · Alta

> ✅ **RESUELTO.** Cuatro listas comparadas por AST. Ampliado en `CNF-03` a una quinta: recuperable / irreversible.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

La lista de métodos válidos vive en **cuatro sitios**: el comentario de cabecera de
`Candidate.ps1`, su `ValidateSet`, el array `$sinRuta` de `ModuleRegistry.ps1` y el `switch` de
`Remove.ps1`. **Nada falla si olvidas uno**: el `switch` cae en `default` y **borra por ruta**.

Es el fallo silencioso más peligroso que queda en el contrato. **Arreglo: un test que compare las
cuatro listas por AST. Diez líneas.** Debería hacerse antes que cualquier otra cosa de esta lista.

### `COR-05` · El mapeo candidato → fila de la interfaz es manual · Media

> ✅ **RESUELTO.** `tests/Contrato.Tests.ps1`. **No hay ningún fallo vivo:** los 8 campos del
> contrato sin contraparte en `ItemVista` están fuera a propósito, y las 18 propiedades rellenables
> se rellenan todas.
>
> **El hueco era real y está comprobado, no deducido.** La invariante que ya existía —*"el candidato
> y la fila de la interfaz no pueden divergir"*— cubre **la intersección y solo la intersección**:
> comprueba que lo que existe en los dos lados se copia de verdad. Un campo nuevo del contrato **sin
> contraparte** no está en esa intersección, así que nadie lo echa de menos. Mutando `Candidate.ps1`
> con un campo nuevo, la invariante vieja pasa sus 160 pruebas sin inmutarse. Eso es exactamente
> `COR-05`.
>
> **Las exclusiones llevan motivo escrito, una por una** —`ModuloId`, `Ejecutable`, `Argumentos`,
> `Raices`, `PermitirPersonales`, `ForzarPermanente`, `BytesLiberados`, `Error`— y hay una prueba
> que impide que una exclusión se quede sin motivo, y otra que impide nombrar campos que ya no
> existen: una exclusión huérfana taparía por casualidad al siguiente campo que se llame igual. Una
> lista de excepciones sin porqué es una forma de desactivar la prueba.
>
> **Dos cosas que salieron por el camino.** `ItemVista` se comprueba **por reflexión sobre el tipo
> compilado**, que contesta el compilador y además distingue lo rellenable de lo calculado; pero
> `Initialize-TiposInterfaz` no hace nada si el tipo ya existe, así que la reflexión puede estar
> contestando por un `ItemVista` viejo. Por eso se extraen además las propiedades del **texto** y se
> exige que los dos conjuntos coincidan — y en una de las mutaciones, esa fue la única prueba que se
> dio cuenta. Y: **el mapeo no está en `Window.Ayudantes.ps1`**, como decía este documento, sino en
> `Window.Analisis.ps1`; la prueba recorre los cuatro `Window*.ps1` para que mudarlo no la apague.
>
> **Aviso para el futuro:** `ForzarPermanente` está excluido porque hoy la fila no promete papelera
> ni borrado permanente en ninguna columna. Si algún día una columna o el diálogo hablan de
> papelera, esa exclusión deja de valer.
>
> Nueve mutaciones, todas cazadas.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

`Candidato` tiene 20 propiedades; `ItemVista` expone 16; la correspondencia se copia a mano. Nada
avisa si una propiedad nueva se queda sin mapear: **cualquier campo que añadas para deshacer o
exclusiones nace invisible en la interfaz**. Test por AST, pequeño.

---

## Parte IV — Confianza: las funciones que definen el producto

Esta es la parte que convierte a Cachivache en algo que la gente elige.

### `CNF-01` · Lista de exclusiones del usuario · **Alta — la función que más falta**

> ✅ **RESUELTO.** Preferencia, filtro en el embudo, revalidación en el motor y `-Excluir` en consola.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

No existe. Si el programa propone la carpeta de un proyecto vivo, la desmarcas hoy y **vuelve a
aparecer mañana**. Es la primera petición de cualquiera que usa un limpiador más de una vez.

**Diseño:**
- `RutasExcluidas` en las preferencias, con su regla de validación.
- Tarjeta *"Carpetas que nunca se tocan"* en Ajustes, con añadir y quitar.
- Orden *"Excluir siempre esta carpeta"* en el menú contextual de la fila.
- Filtro en `Invoke-ModuloLimpieza`, junto a `Test-UnidadSeleccionada`: el mismo embudo por el que
  ya pasan todos los candidatos, así ningún módulo puede saltárselo.
- **Y revalidación en `Invoke-EliminacionCandidato`**, porque el borrado corre en otro runspace y
  no puede fiarse del filtro del análisis.

**Detalle que importa:** la clave de exclusión no puede ser la ruta a secas. Para los métodos sin
ruta real —`Comando`, `Informativo`— la ruta es una etiqueta como `"docker system prune"`. Hace
falta un `ClaveExclusion` estable en el contrato.

### `CNF-02` · Modo simulación · Alta — y está casi hecho

> ✅ **RESUELTO.** Consola con `-Simular`, ventana con la casilla *Solo simular*. Pasa por `Get-MotivoNoSeBorra`, la misma función que el borrado real: antes prometía liberar un archivo que la ejecución de verdad habría rechazado.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

`Remove-Elemento`, `Remove-RutaSegura`, `Clear-ContenidoCarpeta` e `Invoke-EliminacionCandidato`
**ya declaran `SupportsShouldProcess`**. El motor está preparado. Lo que ocurre es que todos los
llamantes lo anulan con `-Confirm:$false` y ninguno propaga `-WhatIf`.

Un modificador `-Simular` que se propague en lugar de anularse permite: enseñar exactamente qué
pasaría sin tocar nada, probar un perfil nuevo sin riesgo, y **verificar en Windows sin borrar**,
que es lo que `VAL-01` necesita. **Tamaño: pequeño.** Depende de `ARQ-01`.

> **Lección aprendida al implementarlo, y vale para todo lo que queda de esta hoja.**
>
> La primera versión salió solo como bandera de consola: `-Simular`. Sobre el papel, hecho. En la
> práctica no existía para casi nadie, porque el camino normal de este programa es hacer doble
> clic en `Cachivache.exe`, y ese ejecutable se compila como `/target:winexe` y arranca PowerShell
> con `CreateNoWindow`. Pasa los argumentos, sí — pero `Cachivache.exe -Consola` corre **sin
> ninguna ventana donde escribir**. La función estaba entregada en el único sitio donde el usuario
> del `.exe` no podía llegar a ella.
>
> Es un fallo distinto de los que veníamos cazando y por eso se apunta aquí: no era código
> incorrecto —la suite pasaba entera— sino una función correcta puesta donde nadie la iba a
> encontrar. **Una capacidad que solo existe en la consola es una capacidad que la mayoría de los
> usuarios no tiene.** De aquí en adelante, todo punto que cambie lo que el usuario puede hacer se
> considera terminado cuando está en los **dos** caminos, y con un invariante que impida que
> vuelvan a separarse: es el mismo error de divergencia que ya nos costó `ARQ-01` y `INT-12`, solo
> que en vez de dos copias del mismo bucle, una copia y un hueco.

### `CNF-03` · Deshacer la última limpieza · Alta — y no es incremental

> ✅ **RESUELTO.** **Parcial a propósito.** Hecho: clasificación recuperable/irreversible, resumen honesto y botón *Abrir la papelera*. Falta el deshacer real, que exige `IFileOperation` por COM y no se puede escribir a ciegas.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Todo va a la papelera por defecto, que es el acierto de fondo. Pero **no hay ningún botón que lo
aproveche**: el usuario tiene que ir a la papelera de Windows y buscar entre miles de archivos.

Ser honesto sobre el alcance: **solo se puede deshacer lo que fue a la papelera.** Los métodos
`Comando` —DISM, `docker system prune`—, `Papelera` y todo lo marcado con `ForzarPermanente` son
irreversibles por naturaleza. Prometer más sería mentir.

**Lo que hace falta:** capturar el identificador de papelera de cada elemento borrado (la API
actual **no lo devuelve**: hay que pasar a `IFileOperation` por COM, o enumerar `$Recycle.Bin`
antes y después), persistir un manifiesto del lote, y marcar en el contrato qué es deshacible.

**Tamaño: grande.** Es la función de más valor percibido del documento y la que más trabajo
cuesta. Un primer paso barato y honesto: **botón "Abrir la papelera"** tras una limpieza, más un
informe que ya lista las rutas exactas.

### `CNF-04` · Decir la verdad cuando el análisis quedó incompleto · **Alta**

> ✅ **RESUELTO.** Cancelar dice *"Análisis detenido: 7 de 21"*; los módulos que fallan se nombran en una franja pegada a la lista; el historial guarda `Incompleto` y `Motivo` y solo apunta los módulos revisados.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Dos casos, los dos activos hoy:

- **Cancelas en el módulo 7 de 21** y la ventana dice *"Análisis terminado"*. El usuario cree que
  la lista es completa. → Bandera de cancelado y texto distinto: *"Análisis detenido: se revisaron
  7 de 21 módulos. La lista está incompleta."* Más una franja persistente en Resultados.
- **Fallan 4 módulos** y solo se anota en el registro. En Resultados nada lo indica. → Contador de
  módulos fallidos y franja: *"3 módulos no se pudieron completar (…). Los resultados están
  incompletos. [Ver registro]"*.

Lo mismo al detener un borrado: hoy se anota en el historial como `limpieza` normal.

### `CNF-05` · Explicar por qué algo viene marcado · Media

> ✅ **RESUELTO.** El criterio estaba en el README, en `ARQUITECTURA.md` y en el panel *Acerca de*: tres sitios donde nadie mira mientras decide qué borrar. Ahora se dice donde se decide, y la explicación sale de la **misma función** que la decisión — si fueran dos copias acabarían diciendo cosas distintas, y una explicación que no coincide con lo que hizo el programa es peor que no explicar nada.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

El resumen dice cuántos elementos hay, pero **en ningún sitio se explica el criterio**. Una frase
lo arregla: *"N vienen marcados: riesgo bajo y sin avisos. Los de riesgo medio y alto los tienes
que marcar tú."* Es lo que convierte una lista en una decisión informada.

### `CNF-06` · Comparar con el análisis anterior · Media

Hay historial e informes JSON, pero ninguna vista de diferencias. Mínimo viable: añadir al resumen
*"(hace 4 días eran 890 elementos, 3,2 GB)"*. Completo: botón *"Comparar"* que coloree lo nuevo y
lo desaparecido.

---

## Parte V — Uso: donde el usuario decide

### `USO-01` · La columna que sostiene la decisión se corta · **Alta**

> ✅ **RESUELTO.** `MinRowHeight` en vez de `RowHeight`, más `TextoCompleto` en la ayuda emergente. **Pendiente de mirar en un equipo real:** la altura variable puede volver el desplazamiento a saltos con miles de filas.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

La altura de fila está fijada en 52 píxeles —altura **exacta**, no mínima—. La columna *"qué pasa
si se borra"* apila hasta cuatro textos con ajuste de línea: aviso, efecto, comando y estado. Caben
dos líneas. **Todo lo demás se recorta sin puntos suspensivos y sin tooltip.**

Es la columna sobre la que el usuario decide si borra algo. → Altura automática con mínimo de 52,
o como poco un tooltip con el texto completo.

### `USO-02` · Un fallo de borrado se pinta en verde, o no se pinta · **Alta**

> ✅ **RESUELTO.** `VisibilidadEstado` y `EstadoEsFallo` viven en `ItemVista`, no en un `DataTrigger`: un disparador de XAML no se puede probar y una propiedad sí. Solo se desmarca lo que se borró de verdad.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

El texto de estado tiene color de éxito fijo y **solo es visible cuando el elemento se borró**.
Resultado: un error que impidió el borrado **no se muestra en absoluto**, y un borrado con aviso
sale en verde. → Visible también cuando hay error, y en color de peligro.

### `USO-03` · La tabla no se puede ordenar · **Alta**

> ✅ **RESUELTO.** Las cinco columnas declaran su campo, y la lista sale ordenada de mayor a menor al terminar el análisis. Lo que no era obvio: declarar el campo a lo bruto habría sido **peor que no ordenar**, porque el tamaño ordenaría por su texto formateado y el riesgo por orden alfabético. Los dos casos tienen prueba.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Las cinco columnas no declaran por qué campo ordenar, así que las cabeceras **parecen pulsables y
no hacen nada**. Con 500 filas no hay forma de ver *"lo más grande primero"*, que es la primera
cosa que quiere cualquiera. → Declararlo en las cinco columnas y ordenar por tamaño al terminar el
análisis.

### `USO-04` · Los grupos no se pliegan ni se marcan en bloque · **Alta**

> ✅ **RESUELTO, con una desviación deliberada.** Lo plegable está. La casilla de tres estados **no**, y no por dificultad: no se puede mantener honesta dentro de un panel virtualizado, y una casilla que miente sobre el estado es justo la familia de fallo que este proyecto lleva cerrando. Dos botones en su lugar.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Con 21 módulos y miles de filas, el usuario baja por una lista infinita sin poder cerrar *"Cachés"*
ni decir *"todo Navegadores, sí"*. → Cabecera de grupo plegable y casilla de tres estados que
marque la categoría entera.

### `USO-05` · Ver qué hay dentro antes de decidir · Alta

> ✅ **RESUELTO.** Botón *Ver contenido* en la barra de Resultados. El cálculo vive en `Get-DetalleCarpeta` y el texto en `Format-DetalleCarpeta`, separados de la ventana para poder probarlos: 24 pruebas.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Ante *"Caché de Electron — 1,2 GB"* el usuario no puede saber qué contiene. → Panel de detalle de
la fila seleccionada: número de archivos, fecha del más reciente, y los diez mayores por tamaño.
Calculado bajo demanda.

### `USO-06` · Menú contextual y doble clic · Media

Abrir la ubicación existe y está bien resuelto, pero exige seleccionar y subir a la barra. No hay
forma de copiar una ruta. → Doble clic abre la ubicación; menú contextual con *Abrir ubicación ·
Copiar ruta · Excluir siempre · Desmarcar el grupo*.

### `USO-07` · Un módulo lento parece un cuelgue · **Alta**

> ✅ **RESUELTO.** `Format-ProgresoAnalisis` añade tiempo y elementos: dos datos que se mueven aunque el módulo lleve minutos en la misma operación.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

La barra avanza **por módulo terminado**. El módulo de duplicados puede tardar cinco minutos con
la barra clavada en el 38% y sin un solo número moviéndose. → Añadir tiempo transcurrido y
elementos encontrados: *"Duplicados (8 de 21) · 2 min 14 s · 1.203 elementos"*. Dos datos que se
mueven demuestran que el programa está vivo.

### `USO-08` · El diálogo de confirmación enseña 5 elementos de los que haya · **Alta**

> ✅ **RESUELTO.** **Todo** comando externo se enseña, sin contar para el tope —`SECURITY.md` lo exige y antes se perdía fuera del top 5—. La decisión vive en `Get-LineasConfirmacion`, con 12 pruebas.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Dice *"218 de los elementos marcados requieren tu criterio"* y enseña cinco. El otro 97% no se ve
nunca. Peor: el comando externo que `SECURITY.md` **exige mostrar antes de confirmar** se corta,
porque su plantilla no ajusta líneas y sí recorta.

→ Lista desplazable con hasta 25 entradas, ajuste de línea, y botón *"Ver los 218 en la lista"*.

### `USO-09` · Estados vacíos · Media

> ✅ **RESUELTO.** `Get-EstadoVacio` en `src/Core/EstadoVacio.ps1` decide; la ventana solo asigna lo
> que salga. En el XAML no hay ni un `DataTrigger`, ni un `Style`, ni un convertidor, y hay una
> invariante que lo prohíbe sobre el bloque del cartel — es la regla de `USO-04`: aquí no hay WPF,
> así que no se deja un mecanismo que no se pueda verificar.
>
> **El botón quita LOS DOS filtros, y el rótulo dice cuántos.** El panel tiene dos —el cuadro de
> texto y el desplegable de riesgo—, y quitar solo uno puede dejar la tabla igual de vacía: un botón
> que se pulsa y no cambia nada es indistinguible de uno roto, que es `USO-15` otra vez. Pero
> llevarse por delante un filtro que el usuario no había nombrado también sorprende, así que el
> rótulo lo dice: *Quitar los dos filtros* / *Quitar el filtro de texto* / *Quitar el filtro de
> riesgo*. La acción siempre limpia los dos, así que el rótulo nunca miente.
>
> **«Analizado y sin resultados» no suena a fallo**, y hay una prueba que lo exige: el texto dice
> que es una buena noticia y nombra de qué depende —los módulos y los ajustes de *ese* análisis—,
> sin llegar a prometer que el equipo está limpio, porque con otro perfil puede haber gigas.
>
> **Salieron dos casos que este documento no pedía, y los dos hacían falta.** El orden de las
> preguntas es: ¿hay algo a la vista? → ¿hay algo en la colección? → ¿en qué punto va el análisis.
> Al revés, un análisis en marcha sobre una lista ya filtrada diría *"se irá llenando sola"* con 700
> filas escondidas detrás. Y hay una rama defensiva para "hay elementos, no se ve ninguno, y no hay
> filtro puesto": no debería ocurrir nunca, pero ofrecer *quitar el filtro* cuando no hay filtro es
> peor que admitir que no se sabe.
>
> **Y dos cosas que se arreglaron después de integrar.** Los tres controles nuevos nacieron en una
> tabla aparte —`Window.ps1` estaba ocupado por otro carril—, lo que era un segundo sitio donde
> resolver controles y obligaba a replicar la invariante entera en las pruebas; ahora están en la
> lista de `$c` de siempre y la invariante estándar los cubre (verificado mutando). Y la prueba de
> `$c` **falló** por un comentario que escribía el acceso literal: la trampa que este documento dice
> que ha mordido cinco veces, la sexta.
>
> Catorce mutaciones, todas cazadas. **Sin verificar hasta que se ejecute en Windows**, como todo lo
> que es XAML.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

La tabla vacía enseña el mismo rectángulo en blanco en tres situaciones distintas: recién abierto,
analizado sin resultados, y **filtro que no deja pasar nada**. La tercera es peligrosa: el usuario
cree que el análisis falló. → Texto según el caso, con *"[Quitar filtros]"* en el tercero.

### `USO-10` · La tabla salta mientras se analiza · Media

Se reengancha la colección por módulo, lo cual es correcto para el rendimiento pero **pierde la
posición y la selección**: si estás leyendo la fila 200 cuando termina un módulo, saltas al
principio. → Guardar y restaurar desplazamiento y selección.

### `USO-11` · Programar limpiezas · Media

La CLI ya está preparada y documentada para tareas programadas, pero la ventana no lo expone. →
Tarjeta *"Análisis periódico"* en Ajustes que registre una tarea programada llamando a la propia
CLI, **sin borrar**: solo analiza y deja informe.

**Decisión de diseño pendiente:** desatendido conviene ser más conservador que interactivo, y hoy
no hay dónde expresar esa distinción.

### `USO-12` · Exponer en la ventana lo que ya existe en la CLI · Media

`-InformeAnonimo` y `-Diagnostico` solo están en consola. El informe que genera la ventana lleva el
nombre de usuario en cada ruta, y es justo el que uno adjunta a una incidencia. → Casilla
*"Anonimizar rutas"* junto a los botones de exportar, y *"Copiar diagnóstico"* en Acerca de.

### `USO-13` · Ocultar lo ya eliminado · Baja

Tras limpiar 800 elementos, la lista sigue teniendo 800 filas fantasma al 45% de opacidad.

### `USO-14` · Un fallo repetido enterraba la ventana bajo avisos · **Alta**

> ✅ **RESUELTO.** Dos fallos distintos, uno detrás de otro, y el segundo es el interesante.
>
> **El fallo.** Dentro de la cabecera de grupo había `<RotateTransform x:Name="Giro"/>` y un
> `<Setter TargetName="Giro" Property="Angle"/>`. Una `RotateTransform` es un `Freezable`, no un
> `FrameworkElement`: **no entra en el ámbito de nombres de la plantilla**, así que `TargetName` no
> la encuentra nunca. Se arregló apuntando al `Path` —que sí es un elemento— y reemplazándole la
> transformación entera.
>
> **Por qué no lo vieron 928 pruebas ni el analizador.** El contenido de una plantilla se analiza
> *tarde*, la primera vez que se aplica. El XAML cargaba sin una queja, la ventana abría y la
> navegación funcionaba. El fallo salía al aparecer la primera cabecera de grupo. Ninguna prueba
> de este repositorio puede instanciar WPF, así que **este agujero solo lo cierra una invariante
> sobre el texto del XAML**: ahora ninguna transformación, pincel o geometría puede llevar
> `x:Name`, y todo `TargetName` tiene que resolver.
>
> **Y el segundo fallo, que es peor.** El manejador de `DispatcherUnhandledException` abría un
> cuadro **modal** por cada excepción. Como esta se repetía por cada cabecera, la ventana quedó
> enterrada bajo más de veinte avisos idénticos que había que cerrar de uno en uno, mientras el
> análisis seguía corriendo detrás sin forma de llegar al botón de pararlo. Un aviso repetido no
> informa más que el primero: **informa peor, porque tapa el programa.** Ahora se avisa una vez por
> fallo distinto y como mucho de tres; al registro siguen yendo todos, con su cuenta.

### `USO-15` · La simulación hacía todo el trabajo y no lo decía · **Alta**

> ✅ **RESUELTO.** El resultado aparece ahora en un cartel dentro de **Resultados**, con las cifras,
> los bloqueados si los hay, y qué hacer para hacerlo de verdad. Caduca en cuanto se cambia la
> selección: sus números son los de lo que estaba marcado al simular, y un cartel viejo encima de
> una selección nueva volvería a mentir.
>
> Salió de la tercera ejecución en Windows. La simulación solo escribía en el panel de **Registro**,
> que es otro panel: quien pulsa el botón está mirando la tabla, y ahí no cambiaba ni un número ni
> una marca. El usuario la pulsó **tres veces seguidas** convencido de que el botón estaba roto —
> y el registro demuestra que hizo las tres. **Hacer el trabajo y no decirlo es, desde el lado de
> quien mira, indistinguible de no hacerlo.**
>
> De paso: `1 elementos` en las cabeceras de grupo, y las columnas `TAMAÑO` y `QUÉ PASA SI SE BORRA`
> recuperaron sus tildes.

---

## Parte VI — Accesibilidad

Esto no es un extra. Es lo que separa un proyecto de portfolio de un producto.

### `A11Y-01` · Cero propiedades de automatización en todo el proyecto · **Alta**

> ✅ **RESUELTO.** Trece controles sin rótulo propio llevan ya nombre de automatización, y una
> invariante impide que vuelva a haber uno mudo.
>
> **La decisión que importa:** donde hay un rótulo visible enlazado —casillas de fila, de módulo y
> de disco, tarjetas de perfil—, el nombre accesible **usa el mismo enlace**, no una cadena escrita
> a mano. Una cadena fija habría anunciado las veintiuna casillas de módulo con el mismo texto, que
> es exactamente el problema que se venía a arreglar; y dos copias del mismo rótulo acaban
> divergiendo. Es el patrón de `CNF-05` aplicado a otra cosa: la misma fuente decide y describe.
>
> **Por qué hacía falta una invariante y no bastaba con arreglarlo.** Este fallo es mudo en las dos
> direcciones: no hay excepción, no hay aviso del analizador, ninguna otra prueba lo nota, y quien
> mira la pantalla no lo percibe **nunca**. Es la familia de `USO-14` —algo que solo se manifiesta
> delante de un usuario concreto, en un equipo que aquí no hay— con el agravante de que allí al
> menos reventaba. La invariante exige tres cosas: que todo control sin texto propio declare
> nombre, que no esté en blanco, y que un nombre enlazado apunte a una propiedad **que exista**.
> La tercera es la que de verdad muerde: un `{Binding Titluo}` mal escrito no lanza, WPF lo
> resuelve a vacío, y el control se queda tan mudo como estaba pero con el atributo puesto y
> aparentando estar arreglado. Verificado mutando el código en cuatro sitios —quitar un nombre,
> dejarlo en blanco, romper un enlace y cegar la propia prueba—, y las cuatro veces falló la
> comprobación correcta nombrando el control exacto.
>
> **Lo que no se ha hecho, a propósito:** `AutomationProperties.LabeledBy` para atar el campo de
> filtro a su marcador de posición, que sobre el papel es más limpio. Es un mecanismo de XAML que
> aquí no se puede ejecutar, y la regla del proyecto tras `USO-04` es no dejar en el código un
> mecanismo que no se pueda verificar. Un nombre literal es aburrido y comprobable.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Ni una en los siete XAML. Los cuatro botones de la barra de título son formas sin texto: un lector
de pantalla los anuncia como *"botón"* a secas. Lo mismo la columna de casillas de la tabla y el
campo de filtro, cuyo único rótulo es decorativo. → Nombre de automatización en botones de ventana,
casillas de fila —con el nombre del elemento—, casillas de módulo y de disco, y campo de filtro.

### `A11Y-02` · La ventana no cabe con escalado del 150% · **Alta**

El mínimo es 1020×620. Un portátil de 1366×768 al 150% son 910×512 puntos: **la ventana no puede
reducirse por debajo del mínimo**, se sale de la pantalla y el botón de eliminar queda fuera. El
panel lateral es de ancho fijo. → Bajar el mínimo, panel lateral plegable, sección de discos
plegable.

### `A11Y-03` · El diálogo de confirmación puede salirse de la pantalla · **Alta**

> ✅ **RESUELTO.** `MaxHeight="760"` en la ventana del diálogo, e `IsCancel="True"` en *Cancelar*,
> que hace que Escape cierre con el foco donde sea. Y **no** se ha puesto `IsDefault` en el botón
> de borrar: eso habría hecho que Enter lanzase la eliminación desde cualquier foco, en el único
> diálogo que existe para frenar un gesto automático.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Crece con su contenido, sin altura máxima, sin poder redimensionarse ni arrastrarse. Con varios
elementos de riesgo, **los botones quedan por debajo del borde inferior**. Y no se puede cerrar con
Escape salvo que el foco esté en el sitio justo. → Altura máxima con la lista desplazable, y
Escape como cancelar.

### `A11Y-04` · Ningún atajo de teclado · Media

> ✅ **RESUELTO, con una desviación deliberada: `Supr` no se ha puesto.**
>
> Hechos: `F5` analizar · `Ctrl+F` ir a Resultados y enfocar el filtro · `Ctrl+A` marcar todo ·
> `Esc` cancelar lo que esté corriendo · `Ctrl+1..6` los seis paneles, con la fila de números y con
> el teclado numérico, porque para el usuario son la misma tecla.
>
> **Por qué `Supr` no.** Es el único de la lista que empieza algo destructivo, y hay dos motivos
> para dejarlo fuera. El primero es de significado: dentro de una tabla `Supr` quiere decir *"borra
> esta fila"*, y aquí querría decir *"borra las 800 cosas marcadas"* mientras el usuario mira una
> sola fila seleccionada. La tecla y su consecuencia no se corresponden. El segundo es que el
> diálogo de confirmación existe para frenar un clic distraído; si `Supr` llega hasta él, pasa de
> ser la **segunda** barrera a ser la única. No se pierde nada: *Eliminar lo marcado* se alcanza
> tabulando y dice su nombre. Si lo quieres, se añade — pero conviene que sea una decisión y no un
> descuido.
>
> **La decisión vive en `Get-AtajoDeTecla`** (`src/UI/Atajos.ps1`), que es cálculo puro y no toca
> WPF: entran la tecla, si había Control y si el foco está en un cuadro de texto, y sale el nombre
> de una acción. Por eso se puede recorrer combinación por combinación aquí, sin interfaz gráfica.
> Lo que queda sin verificar hasta ejecutarlo es solo el cableado.
>
> **Y el despachador pulsa el botón, no repite lo que hace.** Levanta el `Click` del control en vez
> de copiar el cuerpo del manejador. Copiarlo habría sido `ARQ-01` otra vez —dos versiones de la
> misma acción, una de las cuales se queda sin el arreglo siguiente—; así el atajo no *puede* hacer
> algo distinto del botón, porque hace el botón. Efecto de propina: los botones ya saben cuándo no
> toca (`BtnAnalizar` está deshabilitado mientras se analiza), y un control deshabilitado no
> atiende el evento, así que el atajo hereda todas esas guardas sin escribir ninguna.
>
> **El único choque real es `Ctrl+A`**, que dentro de un cuadro de texto ya significa *"selecciona
> todo el texto"* — y el registro de la sesión **es** un cuadro de texto, así que robárselo dejaría
> al usuario sin poder seleccionarlo para copiarlo. Se aparta solo ahí; los demás atajos siguen
> valiendo mientras se escribe, que es justo cuando más falta hace poder parar un análisis.
>
> Invariantes: que `Ctrl+1..6` siga el orden en que se ven las entradas en la barra lateral —
> reordenarla y no tocar los atajos no rompe nada, simplemente hace que `Ctrl+3` mienta—, que toda
> acción devuelta tenga rama en el despachador, que el despachador no contenga lógica de negocio, y
> que la tecla se marque como atendida **después** de saber que era un atajo, porque al revés se
> come cada letra que se escribe en el filtro. Verificado mutando en seis sitios.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Ni uno. → `F5` analizar · `Ctrl+F` filtro · `Ctrl+A` marcar todo · `Supr` eliminar · `Esc`
cancelar · `Ctrl+1..6` paneles.

### `A11Y-05` · La navegación lateral se dispara al tabular · Media-Alta

> ✅ **RESUELTO.** `KeyboardNavigation.DirectionalNavigation="None"` en la barra lateral, más
> `IsTabStop="True"` en las seis entradas. Queda el patrón correcto de una barra de navegación:
> Tab mueve el foco, Espacio activa. El anillo de foco ya estaba en el estilo.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Son botones de radio en grupo: en WPF las flechas mueven la selección **y cambian el panel al
instante**. Un usuario de teclado que pulse *Flecha abajo* para mirar, acaba en otro panel.

### `A11Y-06` · El foco no se mueve al cambiar de panel · Media

> ✅ **RESUELTO.** `mostrarPanel` le da el foco al panel que acaba de mostrar. Los seis lo declaran
> con `Focusable="True"` y `KeyboardNavigation.IsTabStop="False"`: destino de foco, **no** parada de
> tabulación — si no, cada panel añadiría una parada nueva que atravesar a quien ya ve la pantalla.
>
> **Al panel entero y no a su primer control**, por dos motivos. El panel lleva por nombre su título
> visible, así que el lector anuncia *"Resultados del análisis"*, que es exactamente el dato que
> faltaba, y Tab sigue desde ahí hacia dentro en orden. Y porque el primer control de Inicio es
> *Analizar el equipo*: dejar el foco encima de la acción principal convierte un Espacio distraído
> en un análisis que nadie pidió.
>
> **El nombre accesible de cada panel es su título visible, y hay una prueba que lo exige.** Son dos
> copias del mismo rótulo a pocas líneas de distancia, y dos copias divergen: se cambia el título
> que se ve, el que se oye se queda con el de antes, y quien no mira la pantalla oye un nombre que
> ya no existe en ningún sitio.
>
> **De paso se cerró un agujero más viejo que estaba al lado.** Los nombres de los seis paneles
> viven en **cuatro sitios** —el `x:Name` del XAML, la lista que resuelve `Window.ps1`, el bucle de
> `mostrarPanel` y las seis líneas que los enganchan a la barra lateral— y nada comparaba las cuatro
> listas. Es la misma forma de `COR-04`, con el mismo final silencioso: añadir un séptimo panel y
> olvidar el bucle no rompe nada visible, ese panel simplemente **no se oculta nunca** y se queda
> pintado encima del que toca. Ahora hay invariante.
>
> **El orden importa y también va probado:** el foco se pide *después* de fijar la visibilidad.
> `Focus()` sobre un elemento `Collapsed` devuelve `$false`, no lanza, y deja el panel mostrado y
> mudo — código nuevo que aparenta arreglarlo sin arreglar nada. Verificado mutando en seis sitios.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Solo se alterna la visibilidad. Un lector de pantalla no anuncia que el contenido cambió.

### `A11Y-07` · La etiqueta de riesgo es el texto más pequeño de la interfaz · Media

> ✅ **RESUELTO.** Etiqueta a 12 y punto a 9, en el estilo compartido, así que sube en los cuatro
> sitios que lo usan. **No se ha añadido un séptimo tamaño**: 12 ya estaba en la escala. El 11 se
> queda en `Seccion` y en las cabeceras de columna, que son rótulos de estructura y se leen una
> vez; lo que estaba mal no era que existiera un 11, sino que el riesgo lo compartiera con ellos.
> Una invariante exige ahora que la etiqueta sea **estrictamente mayor** que el texto más pequeño
> del programa.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Está a 11 píxeles con un punto de 7, y es **el dato de seguridad más importante de cada fila**.

> **Lo que está bien y no hay que tocar:** el contraste está verificado y pasa holgadamente en los
> dos temas, incluidos los colores de riesgo del tema claro. La escala tipográfica de seis tamaños
> es lo que hace que seis paneles se lean como un solo programa.

---

## Parte VII — Arquitectura habilitante

Nada de la parte IV se puede hacer con comodidad sin esto. Son todos pequeños.

### `ARQ-01` · El bucle de borrado está duplicado y ya divergió · **Alta**

> ✅ **RESUELTO.** `Invoke-LoteEliminacion` en `Remove.ps1`; las dos interfaces la llaman.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Existe dos veces: en la CLI y **dentro de una cadena de texto** que se ejecuta en el runspace de la
ventana. Ya han divergido una vez. Consecuencia: **toda función que toque el borrado hay que
escribirla dos veces**, y una de las copias es invisible para el analizador estático y para las
pruebas.

→ Extraer `Invoke-LoteEliminacion` a `Remove.ps1`. **Es el prerrequisito de `CNF-02`, `CNF-03` y
`CNF-01`.**

### `ARQ-02` · Convertir los filtros en una lista de reglas · Media

`Invoke-ModuloLimpieza` ya es el embudo único y aplica dos filtros —guardia y unidades—, pero
**cableados a mano**. Con las exclusiones serán tres. Una lista de reglas hace que la cuarta sea
gratis.

### `ARQ-03` · Campos que le faltan al contrato · Pequeña

`Deshacible`, `ClaveExclusion` estable, `EsCarpeta` explícito —hoy se redescubre en cada capa— y
un `Origen` estructurado. Hoy se agrupa por `Categoria`, que es **texto libre con 29 valores
distintos**: *"Steam"*, *"Juegos que Steam ya no reconoce"* y *"Plataformas de juego"* son tres
categorías del mismo dominio.

### `ARQ-04` · Las clases de la interfaz se compilan en cada arranque · Baja

`Add-Type` en cada inicio. Retrasa la apertura sin necesidad.

---

## Parte VIII — Velocidad

### `VEL-01` · Leer la tabla maestra de NTFS · Alta — y es el diferenciador técnico

WizTree es **cuarenta veces más rápido** que WinDirStat por una sola razón: no recorre carpetas,
**lee directamente la tabla maestra de archivos de NTFS**. Un disco de 250 GB pasa de 45 segundos
a 1.

Cachivache recorre carpetas. Para los módulos que necesitan *"todos los archivos de más de X"* o
*"todos los archivos por tamaño"* —archivos grandes, duplicados, temporales— leer la tabla maestra
sería un salto de orden de magnitud, no un ajuste.

**Requiere privilegios de administrador y solo funciona en NTFS**, así que sería un camino rápido
con retroceso al recorrido normal. **Tamaño: grande.** Pero es lo que convertiría el análisis
completo en algo que se ejecuta sin pensárselo.

### `VEL-02` · El índice compartido de disco · Media

Heredado de `[REN-30]`. Seis módulos recorren las mismas carpetas. Tras las podas de la fase 5 su
margen se redujo mucho; **si se hace `VEL-01`, este pierde casi todo el sentido**. Decidir uno u
otro, no los dos.

### `VEL-03` · Marcar 5.000 filas bloquea la ventana · Media

El recorrido es síncrono en el hilo de la interfaz. → Trocear por encima de unas 2.000 filas.

---

## Parte IX — Distribución

### `DIS-01` · Firma de código · **Alta — el mayor freno a la adopción**

No hay ni rastro de firma en el proyecto. Y el propio código lo reconoce: *"un ejecutable pequeño
y sin firmar que lanza PowerShell tiene exactamente la forma de un cuentagotas de malware"*.

Consecuencia: **SmartScreen bloqueará cada versión nueva** y los antivirus darán falsos positivos.
Por delante de winget, por delante de cualquier función. Un certificado es coste y trámite, no
código; el paso de integración continua son unas diez líneas.

### `DIS-02` · Publicar los hashes · Trivial

> ✅ **RESUELTO. Y no era una línea.**
>
> Hecho: `tools/Publicar-Sumas.ps1` calcula las sumas **después** de armar el paquete y **antes** de
> adjuntar nada; se publican en la página de la versión *y* en un `SHA256SUMS.txt` adjunto; el
> README explica cómo comprobarlas.
>
> **Van en los dos sitios a propósito.** Si las sumas solo viven dentro de un archivo que se
> descarga del mismo sitio que el paquete, quien pueda cambiar uno puede cambiar el otro. En el
> cuerpo de la versión quedan escritas donde el paquete no llega.
>
> **Por qué no era una línea.** Un archivo de sumas no es texto informativo: lo leen otras
> herramientas, y cuatro descuidos lo rompen **sin que se note al mirarlo** — hash en mayúsculas
> (`Get-FileHash` los devuelve así, `sha256sum` los escribe en minúsculas), un solo espacio en vez
> de dos, saltos CRLF que meten un `\r` dentro del nombre del archivo, y el BOM. Ninguno se ve
> leyendo el archivo. Los cuatro se ven en `Format-SumasSha256`, que es cálculo puro y va probado.
>
> **Y el BOM tiene doble filo, que es el hallazgo del punto.** Este proyecto **exige** BOM en todo
> `.ps1` y `.xaml`, con su propia invariante; aquí es justo al revés, y quien venga detrás verá el
> `$false` y pensará que es un descuido. Peor: probado a mano contra la herramienta de verdad, un
> archivo con BOM da `WARNING: 1 line is improperly formatted`, verifica el resto y **sale con
> código 0**. La comprobación que se añadió para que esto no pasara habría pasado por alto justo
> esto, en verde, publicando un `.zip` cuya suma no comprueba nadie. De ahí el `--strict`, que
> convierte una línea mal formada en un error.
>
> **Lo que no cubre ninguna prueba**, y conviene decirlo: nada de esto se ha ejecutado en GitHub
> Actions. El formato está verificado de extremo a extremo contra `sha256sum -c --strict`, pero que
> el paso del flujo funcione tal cual está escrito se sabrá en la primera etiqueta.
>
> Con esto quedan desbloqueados `DIS-03` (winget) y `DIS-04` (Scoop), que declaran el hash en su
> manifiesto.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

El flujo de publicación no publica SHA256 de los artefactos. Es **prerrequisito de winget y de
Scoop**, y es una línea.

### `DIS-03` · winget · Pequeña

> ✅ **RESUELTO junto con `DIS-04`**, en una sola pieza y a propósito: los dos manifiestos declaran
> los mismos cuatro datos, y mantenerlos separados es como se llega a que uno diga una versión y el
> otro, otra. Tres pruebas se dedican a que digan lo mismo.
>
> **Los manifiestos se GENERAN en la publicación, no se mantienen a mano.** No son dos datos que
> caducan, son **cuatro**: la versión sin la `v`, la URL de descarga, el SHA-256 del `.zip` y —el
> que casi se escapa— **la carpeta de dentro del `.zip`**, porque `Compress-Archive -Path $carpeta`
> comprime la carpeta y su nombre lleva la versión. Los cuatro envejecen a la vez y en silencio: un
> manifiesto viejo pasa las pruebas, pasa el analizador, se lee perfectamente y falla en casa de
> quien instala, con un mensaje que dice que el archivo no coincide con lo declarado. Misma familia
> que `DIS-02`, misma solución: el dato sale una vez, del archivo real. Consecuencia deliberada:
> `Publicar-Manifiestos.ps1` **no tiene parámetro `-Hash`**, y hay una prueba que exige que no lo
> tenga.
>
> **El caso del hash no es el mismo en los dos**, y las dos elecciones van protegidas: winget en
> **mayúsculas** (compara sin distinguir, pero `wingetcreate` escribe así, y una diferencia debe
> significar que cambió el paquete, no el formato); Scoop en **minúsculas**, y ahí no es cosmético,
> porque su `autoupdate` saca el hash de nuestro `SHA256SUMS.txt`, que va en minúsculas.
>
> **Hallazgo del punto: en YAML, `2.1` no es la cadena `"2.1"`, es el número 2.1.** Este proyecto
> admite etiquetas de dos partes, así que `v2.1` habría producido `PackageVersion: 2.1` y el
> validador de winget lo rechaza con un error que no habla de versiones. Con tres partes no se nota
> nunca. De ahí `ConvertTo-EscalarYaml`.
>
> `Architecture: neutral` y no `x64`: son guiones de PowerShell más un lanzador AnyCPU, y declarar
> `x64` dejaría fuera Windows ARM64. `InstallerType: zip` con `NestedInstallerType: portable` es lo
> que hace que winget acepte un paquete **sin firmar**, y por eso esto no depende de `DIS-01`.
>
> **Sin verificar:** nada se ha ejecutado en GitHub Actions, no se ha pasado `winget validate` ni
> `wingetcreate`, y **no se ha enviado a `microsoft/winget-pkgs`** — hasta que se envíe,
> `winget install` no lo encuentra. El identificador `FranciscoLopez.Cachivache` está puesto por
> convención `Editor.Paquete`; cambiarlo es una línea.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Es el canal natural en Windows 10 y 11, y no exige firma para un `.zip` portable si el manifiesto
declara el hash. El más rentable de los tres gestores.

### `DIS-04` · Scoop · Pequeña

> ✅ **RESUELTO junto con `DIS-03`** — el porqué de hacerlos en una pieza está allí.
>
> **Desviación deliberada: no se ha creado ningún repositorio propio (*bucket*).** Se sale de este
> repositorio y no se puede verificar desde aquí. En su lugar el `.json` se adjunta a cada versión y
> ya es instalable por URL, que da el mismo resultado hoy sin dejar un repositorio a medias:
> `scoop install https://.../releases/download/v2.1.0/cachivache.json`.
>
> Lleva `checkver` y `autoupdate` aunque el manifiesto se regenere en cada publicación, y es a
> propósito: son para el día en que esto se olvide. Si alguien mete el `.json` en un bucket y deja
> de regenerarlo, Scoop se actualiza solo mirando las versiones de GitHub y saca el hash de nuestro
> `SHA256SUMS.txt` en vez de creerse el suyo.
>
> El JSON se arma con `ConvertTo-Json`, no concatenando texto: escribir JSON a mano funciona hasta
> que un valor lleva una comilla, y entonces produce algo que se parsea con el valor cambiado.
>
> **Sin verificar:** no se ha instalado con `scoop`; en concreto, ni el shim sobre `Cachivache.ps1`
> ni que `checkver`/`autoupdate` extraigan el hash de nuestro archivo de sumas.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Un `.json` en un repositorio propio. Su público —desarrolladores— está muy alineado con los
módulos que Cachivache ya cubre: npm, Gradle, cargo, conda, Playwright.

### `DIS-05` · Aviso de versión nueva · Pequeña

`Version.ps1` **ya tiene la versión y la URL del repositorio**: las dos piezas están. Falta
consultar la última publicación y avisar en Acerca de. Actualizar los archivos en su sitio es
delicado porque el `.zip` se descomprime donde el usuario quiera; **avisar y abrir la página es la
opción honesta**.

---

## Parte X — Internacionalización

### `I18N-01` · Unas 870 cadenas visibles, todas en duro · Media-Grande

> ✅ **RESUELTO.** Repasada toda la prosa de cara al usuario. Dos invariantes: palabras sin tilde, y variables acentuadas por un reemplazo automático (que es justo lo que rompió la detección al corregirlo la primera vez).
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

No hay ningún patrón de localización. El reparto aproximado: ~102 en los XAML, ~477 en los
módulos, ~180 en el núcleo, ~66 en los informes, ~90 en la CLI.

**Por dónde empezar:** los XAML son la parte fácil y visible. Los módulos son la parte cara, y
extraer sus textos rompería la propiedad más valiosa del proyecto —*un módulo es un archivo
autocontenido*— salvo que cada uno lleve su propio archivo de idioma al lado.

### `I18N-02` · ⚠ Aviso crítico para quien haga la traducción

`Test-CarpetaEspejo`, `Test-ArchivoPersonal` y la lista de nombres sensibles comparan contra
**listas de palabras en castellano e inglés**. Eso **no es texto de interfaz: es lógica de
seguridad**.

Si un traductor las mete en el archivo de idioma, **rompe la guardia en silencio**. Cualquier
extracción de textos debe excluirlas explícitamente, y hace falta **un test que lo verifique**.

### `I18N-03` · Windows en otros idiomas · Media

Consecuencia del anterior, ya activa: en un Windows alemán o francés, esas listas bilingües
**degradan en silencio**. No rompe nada —la lista blanca de raíces sigue mandando— pero protege
menos de lo que el README promete. Y los módulos que ejecutan DISM analizan una salida que **está
traducida**.

---

## Parte XI bis — Medirse contra WizTree y BCU

Objetivo declarado: **superar en funciones a WizTree y a Bulk Crap Uninstaller.** Este apartado
mide si el plan lleva ahí, sin adornos.

### Contra WizTree — objetivo alcanzable

WizTree hace **una cosa**: enseñar dónde se fue el disco, muy rápido. Su superficie de funciones
es pequeña, y eso lo hace superable.

| Función de WizTree | Cachivache hoy | Con el plan |
|---|---|---|
| Lectura de la tabla maestra de NTFS (velocidad) | ✗ | `VEL-01` |
| Mapa de árbol visual | ✗ | **falta: `VIS-01`** |
| Vista de archivos: todos, ordenados por tamaño | ~ solo los mayores de X MB, e informativo | **falta: `VIS-02`** |
| Búsqueda por nombre y tipo con comodines | ~ filtra la lista de candidatos, no el disco | `VIS-02` |
| Incluir y excluir carpetas concretas | ✗ | `CNF-01` |
| Duplicados por nombre, tamaño y fecha | ✓ **mejor**: SHA-256 con prefiltro | ✓ |
| Exportar a CSV | ✓ **mejor**: CSV, HTML y JSON | ✓ |
| Reimportar para comparar | ✗ | `CNF-06` |
| Contar bien los enlaces duros | ✗ **los cuenta dos veces** | **falta: `VIS-03`** |
| Borrar desde el programa | ✓ WizTree apenas lo hace | ✓ |
| Limpieza por categorías (21 módulos) | ✓ **WizTree no lo hace** | ✓ |

**Hoy: en torno al 50%. Con el plan actual: ~65%. Con los tres puntos `VIS`: por encima del 100%**,
porque a lo suyo se le suma todo lo que WizTree no hace.

**Veredicto: sí, es alcanzable, y con tres puntos nuevos.**

### Estado tras la primera tanda (29 de agosto de 2026)

| Punto | Estado |
|---|---|
| `VIS-03` enlaces duros | ✅ **Hecho.** Y de paso destapó que el módulo de duplicados proponía borrar un enlace duro creyendo que liberaba espacio |
| `IDX` índice de disco | ✅ **Hecho.** `src/Core/Indice.ps1`, una pasada, agregados por carpeta y archivos mayores |
| `VIS-01` algoritmo del mapa | ✅ **Hecho.** `src/Core/Mapa.ps1`, cálculo puro y probado |
| `VIS-01b` mapa dibujado | ✅ **Hecho en SVG** dentro del informe HTML. Falta el panel de WPF |
| `VIS-02` vista de archivos | ✅ **Hecho en consola** con `-Espacio`. Falta el panel de la ventana |
| `VEL-01` tabla maestra | ⬜ Pendiente. El índice ya está preparado para recibirlo como proveedor alternativo |

**Por qué el mapa se dibujó primero en SVG y no en WPF.** No fue comodidad. En WPF el resultado
**no se puede comprobar**: la interfaz no arranca en las pruebas, así que un mapa dibujado allí
sería código que nadie ha visto funcionar. El SVG es texto: se verifica que los rectángulos están
donde deben, que suman el área y que el documento es válido. Cuando el mapa se lleve a la ventana,
el cálculo y los colores ya estarán probados.

Y hay un segundo motivo. Añadir un panel a la ventana obliga a regenerar el oráculo de la prueba
que compara el XAML montado **byte a byte** con el documento anterior a partirlo. Esa prueba está
diseñada para pararte —lo dice su propio comentario— y el momento de tocarla es cuando se puede
mirar el resultado en pantalla, no antes.

**El color del mapa dice algo que ningún competidor puede decir.** En WizTree el color distingue
tipos de archivo. Aquí distingue **cuánto de ese espacio es recuperable**: una carpeta con
candidatos se pinta en el color de su riesgo, y una carpeta sin nada que limpiar, en gris. WizTree
no sabe qué es basura; los limpiadores no dibujan el disco. Esto hace las dos cosas sobre el mismo
dibujo.

**Medido:** el mapa cubre el 100% del área con una proporción máxima de 2,78, frente a 16 del
reparto ingenuo a tiras. Casi seis veces más legible, que es exactamente la razón de usar el
algoritmo cuadrado y no cortar en franjas.

**Lo que queda para cerrar la comparación con WizTree:** el dibujado del mapa en la ventana
—coloreado por módulo y por riesgo, que es lo que no tiene ninguno de los dos— y `VEL-01`.

### Contra BCU — no alcanzable, y perseguirlo haría daño

| Función de BCU | Cachivache hoy | Con el plan |
|---|---|---|
| Desinstalar programas en lote | ✗ | ✗ |
| Desinstalación forzada, desinstaladores rotos | ✗ | ✗ |
| Entradas registradas y ocultas | ~ solo señala las huérfanas | ~ |
| Aplicaciones portables en discos locales y extraíbles | ✗ | ✗ |
| Instalaciones de Steam | ✓ **mejor**: lee `libraryfolders.vdf` y detecta juegos sin manifiesto | ✓ |
| Instalaciones de Oculus | ✗ | ✗ |
| Aplicaciones de la Store | ✓ | ✓ |
| Características de Windows | ✗ | ✗ |
| Actualizaciones de Windows | ~ limpia la caché, no las desinstala | ~ |
| Restos: archivos y carpetas | ✓ | ✓ |
| Restos: servicios y tareas programadas | ~ informativo | ~ |
| Restos: claves del registro | ~ informativo, **nunca escribe** | ~ |
| Listas de desinstalación automática | ✗ | ✗ |
| Valoraciones de la comunidad | ✗ | ✗ |
| Cachés de desarrollo, navegador y sombreadores | ✓ **BCU no lo hace** | ✓ |
| Análisis de espacio en disco | ✗ BCU no lo hace | `VIS-01` |

**Hoy: en torno al 30% de BCU. Con el plan: sigue en el 30%,** porque el plan optimiza confianza,
no amplitud.

**Y no se debe cerrar esa brecha.** Superar a BCU en funciones exige **desinstalar programas**, y
eso significa ejecutar `uninstall.exe` de terceros, sacado del registro, con privilegios elevados.
Es lo contrario del modelo de este programa: la lista blanca, la revalidación y el "solo borro
dentro de raíces autorizadas" **dejan de significar nada** en cuanto lanzas un binario ajeno que
hace lo que quiere. Toda la historia de seguridad del proyecto se cae de golpe.

**Veredicto: no. Y el "no" es la decisión correcta, no una limitación.** BCU desinstala; Cachivache
limpia lo que queda y lo que los programas generan. Son vecinos, no rivales. De hecho **se
complementan**: BCU quita el programa, Cachivache encuentra lo que dejó atrás.

---

## Parte XI ter — Los tres puntos que faltan para superar a WizTree

### `VIS-01` · Mapa del disco · Alta — es la función que más se ve

> ✅ **RESUELTO.** Mapa de árbol en SVG. Falta el panel de WPF.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Un mapa de árbol donde cada archivo es un rectángulo proporcional a su tamaño. Es lo que hace que
alguien entienda en dos segundos que sus 40 GB están en una carpeta que no sabía que existía.

**Cómo encaja aquí y no en WizTree:** los rectángulos se pueden **colorear por módulo y por
riesgo**. WizTree te enseña dónde está el espacio; Cachivache podría enseñarte, sobre el mismo
mapa, **cuánto de eso es basura y de qué tipo**. Eso no lo hace ninguno de los dos.

WPF dibuja esto sin dependencias con un `Canvas` y rectángulos, o con un `DrawingVisual` si hay
que llegar a decenas de miles. **Tamaño: grande**, pero es la función de más impacto visual del
documento — y para un portfolio, la que se ve en la primera captura de pantalla.

### `VIS-02` · Vista de archivos completa · Media-Alta

> ✅ **RESUELTO.** Vista de archivos en consola. Falta el panel de WPF.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

Hoy el módulo de archivos grandes solo mira las **zonas del usuario**, solo los que superan un
umbral, y es **informativo**. WizTree lista *todos* los archivos del disco ordenados por tamaño,
con búsqueda por nombre y comodines.

Con `VEL-01` —la tabla maestra— esto es casi gratis: **si ya has leído todos los archivos del
disco, listarlos y buscarlos no cuesta nada más.** Los dos puntos se sostienen mutuamente.

### `VIS-03` · Contar bien los enlaces duros · Media — y hoy es un error de cálculo

> ✅ **RESUELTO.** Los enlaces duros ya no se cuentan como espacio recuperable.
>
> *El análisis de abajo se conserva porque explica el porqué, que no caduca.*

**Cachivache cuenta dos veces los archivos con enlaces duros.** El recorrido salta los puntos de
reanálisis —enlaces simbólicos y uniones— pero un enlace duro no es un punto de reanálisis: es otra
entrada de directorio apuntando al mismo contenido.

No es teórico. `WinSxS` es casi todo enlaces duros, y la propia hoja de optimizaciones ya avisaba
de que su medición está inflada. WizTree lo resuelve porque lee la tabla maestra, donde cada
archivo aparece una vez.

**Arreglo sin la tabla maestra:** llevar un conjunto de identificadores de archivo —el índice de
la tabla maestra más el número de serie del volumen, que se obtienen con `GetFileInformationByHandle`—
y contar cada uno una sola vez, pero **solo cuando el contador de enlaces sea mayor que uno**, para
no pagar el coste en el caso normal.

**Criterio de aceptación:** medir una carpeta con dos enlaces duros al mismo archivo de 100 MB
devuelve 100 MB, no 200.

---

## Parte XI — Orden de ejecución

### Estado (29 de agosto de 2026)

| Punto | Estado |
|---|---|
| `COR-04` cuatro listas de métodos | ✅ Hecho. **Verificado mutando el código**: al añadir un método sin rama, la prueba lo caza por dos vías |
| `ARQ-01` bucle de borrado duplicado | ✅ Hecho. `Invoke-LoteEliminacion` en `Remove.ps1`; las dos interfaces la llaman |
| `CNF-01` exclusiones del usuario | ✅ Hecho. Preferencia, filtro en el embudo, revalidación en el motor y `-Excluir` en consola |
| `CNF-02` modo simulación | ✅ Hecho **en los dos caminos**. Consola con `-Simular`; ventana con la casilla *Solo simular* junto al botón. Mide y anota sin tocar nada, y no deja informe ni entrada de historial. Siete invariantes cubren que no pueda divergir |
| `CNF-03` deshacer | 🟡 **Parcial, a propósito.** Hecho: clasificación recuperable/irreversible por método —con invariante dentro de `COR-04` para que un método nuevo no pueda quedarse sin clasificar y contarse como recuperable por descarte—, resumen honesto al terminar (*"3 en la papelera, 3 sin vuelta atrás"*) y botón **Abrir la papelera**. **Falta el deshacer de verdad** —restaurar solo lo de esta limpieza, en su sitio—: exige `IFileOperation` por COM, son cientos de líneas que no puedo ejecutar ni probar aquí, y el camino que restaura archivos del usuario es el peor sitio para escribir a ciegas. Requiere `VAL-02` |
| `CNF-05` por qué está marcado | ✅ Hecho. La regla vive en `Test-DebeVenirMarcado` y su explicación en `Get-MotivoPremarcado`: **la misma función decide y explica**, con un invariante que recorre las 24 combinaciones y falla si discrepan. En el resumen (*"2 vienen marcados por ser de riesgo bajo y sin avisos. Los otros 2 los marcas tú"*) y en cada fila. En ventana y consola |
| `USO-05` ver qué hay dentro | ✅ Hecho. `Get-DetalleCarpeta` en `src/Core/Inspeccion.ps1`: cuántos archivos, de cuándo es lo más reciente y los diez mayores. **No abre ni un archivo** —solo enumera—, así que no descarga nada de OneDrive; usa el prefijo de ruta larga y lo quita antes de devolver nada; no sigue enlaces. Con un tope de archivos que, si salta, **se dice**: unos "diez mayores" de medio recorrido son un dato que parece cierto y no lo es |
| `USO-04` grupos plegables | ✅ Hecho **con una desviación del plan**. Cabecera plegable y botones *Marcar* / *Quitar* por categoría. El plan pedía una **casilla de tres estados** y se descartó: para mostrar el estado "a medias" tendría que recalcularse con cada cambio de cualquier fila, y las cabeceras viven en un panel virtualizado que las crea y destruye al desplazarse. Una casilla que dice "sin marcar" con cinco de diez marcados **miente sobre el estado**. Dos botones no afirman nada: hacen algo |
| `USO-03` tabla ordenable | ✅ Hecho. `SortMemberPath` en las cinco columnas, y ordenada por tamaño de mayor a menor al terminar. El tamaño ordena por **`Bytes`, no por el texto** —"9,52 GB" es alfabéticamente menor que "980 MB"— y el riesgo por `OrdenRiesgo` —la cadena daría Alto, Bajo, Medio— |
| `USO-07` módulo lento | ✅ Hecho. `Format-ProgresoAnalisis` añade tiempo transcurrido y elementos encontrados: dos datos que se mueven aunque el módulo lleve minutos en la misma operación. Función pura, 10 pruebas. El contador va pegado al **módulo**, no al mensaje — el módulo trae el suyo y salía *"grupo 3 de 47 (8 de 21)"* |
| `USO-08` confirmación truncada | ✅ Hecho. **Todo** comando externo se enseña, sea cual sea su tamaño y sin contar para el tope —SECURITY.md lo exige y antes se perdía fuera del top 5—; hasta 25 elementos más, lista desplazable con ajuste de línea, y se dice cuántos quedan fuera. La decisión vive en `Get-LineasConfirmacion`, con 12 pruebas |
| `USO-01` columna recortada | ✅ Hecho. `MinRowHeight` en vez de `RowHeight`, más `TextoCompleto` en la ayuda emergente. **Pendiente de mirar en tu equipo:** la altura variable puede volver el desplazamiento a saltos con miles de filas, y WPF no arranca en las pruebas |
| `USO-02` fallos invisibles | ✅ Hecho. `VisibilidadEstado` y `EstadoEsFallo` viven en `ItemVista`, no en un `DataTrigger`: un disparador de XAML no se puede probar y una propiedad sí. Un fallo se ve siempre y en rojo; solo se desmarca lo que se borró de verdad, para poder reintentarlo. Verificado mutando la clase |
| `CNF-02b` simulación fiel | ✅ Hecho. La simulación pasa por `Get-MotivoNoSeBorra`, la misma función que el borrado real, y cuenta aparte los rechazados. Antes prometía liberar un archivo que la ejecución de verdad habría rechazado. Encontrado ejecutándolo en Windows |
| `COR-03` archivos en la nube | ✅ Hecho. `Test-EsMarcadorNube` mira los tres atributos (`Offline`, `RecallOnOpen`, `RecallOnDataAccess`) por valor numérico, no por nombre de enumeración —el de OneDrive no existe en .NET Framework—. `Get-HuellaRapida` se protege sola antes de abrir; duplicados los descarta y **dice cuántos**; archivos grandes ya no promete espacio que en el disco no está. **Corrección del diagnóstico:** medir NO dispara descargas (`Length` sale de la entrada de directorio); solo las dispara abrir el archivo, o sea el hash |
| `COR-02` rutas largas | ✅ Hecho. Prefijo `\\?\` aplicado en `Get-ResumenArbol` (un solo sitio, lo heredan los ocho llamantes) y en el borrado permanente vía `System.IO`. Una ruta larga **no puede ir a la papelera** —`VisualBasic.FileIO` no lo admite— y se dice, en vez de borrarla permanentemente por nuestra cuenta. La guardia normaliza el prefijo: sin eso daba el veredicto correcto por el motivo equivocado |
| `CNF-04` análisis incompleto | ✅ Hecho. Cancelar dice *"Análisis detenido: se revisaron 7 de 21"*; los módulos que fallan se cuentan y se nombran en una franja pegada a la lista; una limpieza detenida se anota como tal; el historial guarda `Incompleto` y `Motivo`, y solo apunta los módulos **revisados**. En ventana y consola |
| `COR-01` papelera que no lo es | ✅ Hecho. `Papelera.ps1` lee cuota, `NukeOnDelete`, directiva y tipo de disco; `Test-CabeEnPapelera` es cálculo puro y va probado. Si algo no cabría, **no se borra**: se explica y se ofrece el borrado permanente. "No lo sé" no bloquea, pero queda anotado |
| `I18N-01` textos sin tildes | ✅ Hecho. Repasada toda la prosa de cara al usuario en `src/`. Dos invariantes: uno prohíbe una lista de palabras inequívocas sin tilde, otro impide que una variable acabe acentuada por un reemplazo automático (que es justo lo que rompió la detección al corregirlo la primera vez) |
| `REP-06` tabla del informe | ✅ Hecho. `table-layout:fixed` con anchos por columna y `overflow-wrap:anywhere`: la columna de rutas ya no se aplasta a cuatro caracteres |
| `COR-07` informes rotos | ✅ Hecho. `New-Object System.Collections.Generic.List[object]` devuelve una lista que `@( )` no puede enumerar (`ArgumentException`). Todos los informes fallaban, en ventana y consola. Sustituido por `::new()` en los 7 sitios, con invariante que prohíbe la forma peligrosa |
| `COR-06` errores sin sitio | ✅ Hecho. `Get-DetalleExcepcion` añade tipo, archivo y línea; la pila va al registro y no a la pantalla. Guardar el informe y abrirlo son ya dos `try` distintos: abrir el Explorador no puede hacerse pasar por un fallo al guardar |
| `VIS-03` enlaces duros | ✅ Hecho |
| `IDX` índice de disco | ✅ Hecho |
| `VIS-01` mapa de árbol | ✅ Hecho en SVG. Falta el panel de WPF |
| `VIS-02` vista de archivos | ✅ Hecho en consola. Falta el panel de WPF |
| `A11Y-01` nombres de automatización | ✅ Hecho. Trece controles sin rótulo propio ya se anuncian; los que tienen rótulo visible enlazado toman el **mismo enlace**, no una copia. Invariante de tres reglas —presencia, no vacío, y que el enlace apunte a una propiedad que exista— verificada mutando en cuatro sitios. **Pendiente de oírlo con un lector de pantalla real:** aquí no hay WPF, así que lo comprobado es el texto del XAML, no lo que dice el Narrador |
| `A11Y-06` el foco al cambiar de panel | ✅ Hecho. `mostrarPanel` enfoca el panel mostrado, que se anuncia con su título visible; destino de foco pero no parada de tabulación. Y de paso, invariante que compara las **cuatro** listas de paneles que hasta ahora podían divergir en silencio, al estilo de `COR-04`. **Pendiente de oírlo:** el `Focus()` en sí no se puede ejecutar aquí |
| `DIS-03` winget · `DIS-04` Scoop | ✅ Hechos, en una pieza. Los manifiestos se **generan** en la publicación: declaran cuatro datos que caducan a la vez y en silencio, y el cuarto —la carpeta de dentro del `.zip`— casi se escapa. Hallazgo: en YAML, `2.1` es el número 2.1, no la cadena, así que una etiqueta de dos partes producía un manifiesto que winget rechaza. **Sin enviar a `winget-pkgs`**, así que `winget install` aún no lo encuentra |
| `COR-05` mapeo candidato–vista | ✅ Hecho. **No hay fallo vivo**, pero el hueco era real y está comprobado: mutando el contrato con un campo nuevo, la invariante que ya existía pasa sus 160 pruebas sin inmutarse, porque solo cubría la intersección. Las exclusiones llevan motivo escrito una a una. De paso: el mapeo no estaba donde este documento decía |
| `USO-09` estados vacíos | ✅ Hecho. La decisión en `Get-EstadoVacio`, cálculo puro; en el XAML ni un `DataTrigger`, y hay invariante que lo prohíbe. El botón quita **los dos** filtros y el rótulo dice cuántos. Salieron dos casos que no estaban en el plan y hacían falta. **Pendiente de verlo en tu Windows** |
| `DIS-02` publicar los hashes | ✅ Hecho, y **no era una línea**. Sumas en la página de la versión y en `SHA256SUMS.txt`; el formato va probado, porque los cuatro descuidos que rompen un archivo de sumas no se ven mirándolo. El hallazgo: sin `--strict`, `sha256sum -c` sobre un archivo con BOM avisa, se salta esa línea y **sale con código 0** — la comprobación habría pasado por alto justo lo que venía a comprobar. Desbloquea `DIS-03` y `DIS-04` |
| `VAL-02` banco de pruebas | 🟡 **El banco está hecho; falta la primera pasada.** `docs/BANCO-PRUEBAS.md` con los escenarios en orden y `tools/Banco-Pruebas.ps1` que monta los cebos. Las decisiones peligrosas —sobre todo "esta ruta cae dentro del banco"— viven aparte, en cálculo puro, con 31 pruebas y verificadas por mutación. Es lo único que puede convertir `COR-01`, `COR-02` y `COR-03` de "escrito" en "visto" |
| `A11Y-04` atajos de teclado | ✅ Hecho, **sin `Supr`** y a propósito: es el único que empieza algo destructivo, y en una tabla esa tecla significa "esta fila", no "las 800 marcadas". La decisión vive en `Get-AtajoDeTecla`, cálculo puro, probada combinación por combinación; el despachador **levanta el `Click` del botón** en vez de repetir lo que hace, así que no pueden divergir y hereda gratis las guardas de cada botón |

### Ronda 0 — Antes de tocar nada (días)

`COR-04` cuatro listas de métodos · `COR-05` mapeo candidato–vista · `ARQ-01` extraer el bucle de
borrado. Los tres son pequeños, y los tres evitan que el trabajo siguiente se escriba dos veces o
se rompa en silencio.

### Ronda 1 — Verificar (bloqueante)

`VAL-01` ejecutarlo en Windows · `VAL-02` montar la máquina virtual · `CNF-02` modo simulación,
que hace la verificación segura.

**Nada de lo que sigue debería empezar antes de cerrar esta ronda.**

### Ronda 2 — Que no mienta (semanas)

`COR-01` la papelera · `CNF-04` decir la verdad cuando el análisis quedó incompleto · `USO-02` los
errores en verde · `USO-01` la columna que se corta.

Son los cuatro sitios donde el programa hoy **afirma algo que no es cierto**. En un programa que
borra archivos, eso va antes que cualquier función nueva.

### Ronda 3 — Que se pueda usar de verdad (semanas)

~~`CNF-01` exclusiones~~ · ~~`USO-03` ordenar~~ · ~~`USO-04` plegar y marcar por grupo~~ ·
~~`USO-07` progreso que se mueve~~ · ~~`USO-08` el diálogo completo~~ · ~~`A11Y-03` que quepa en la
pantalla~~ · queda `A11Y-02`, que no se puede verificar sin WPF delante.

Al terminar esta ronda, el programa es **cómodo**, que es lo que hoy le falta frente a BleachBit.

### Ronda 4 — Que se pueda instalar (semanas)

~~`DIS-02` hashes~~ · ~~`DIS-03` winget~~ · ~~`DIS-04` Scoop~~ · queda `DIS-05` aviso de versión, y
`DIS-01` firma en cuanto haya certificado. **La ronda está cerrada salvo esos dos**, y falta enviar
los manifiestos de winget a `microsoft/winget-pkgs`, que es trámite, no código.

### Ronda 5 — Que se pueda confiar del todo (meses)

~~`CNF-03` deshacer~~ (parcial) · ~~`COR-02` rutas largas~~ · ~~`COR-03` OneDrive~~ ·
~~`A11Y-01` nombres de automatización~~ · ~~`A11Y-06` el foco al cambiar de panel~~ ·
~~`A11Y-04` atajos de teclado~~. **El bloque de accesibilidad queda cerrado**, salvo `A11Y-02`
—descartado, no se puede verificar sin WPF delante— y `Supr`, descartado a propósito en `A11Y-04`.

### Ronda 6 — Superar a WizTree (meses)

`VEL-01` tabla maestra de NTFS → `VIS-02` vista de archivos completa → `VIS-01` mapa del disco
coloreado por riesgo. En ese orden: los tres se apoyan uno en otro, y el primero hace baratos a
los otros dos.

`VIS-03` enlaces duros puede ir antes y por separado: es un error de cálculo, no una función.

### Ronda 7 — Alcance (meses)

`I18N-01` traducción · `USO-11` limpiezas programadas · `CNF-06` comparar análisis.

---

## Cómo saber si ha funcionado

Métricas honestas, no vanidosas:

| Señal | Qué demostraría |
|---|---|
| Un análisis completo en un equipo real, sin proponer nada del sistema | Que la guardia funciona fuera del laboratorio |
| Cero incidencias de *"me ha borrado algo que necesitaba"* | El único indicador que de verdad importa |
| Alguien lo usa una segunda vez | Que el programa es cómodo, no solo correcto |
| Una traducción enviada por otra persona | Que la arquitectura permite colaborar |
| Instalable con `winget install` | Que la distribución dejó de ser fricción |

Y una que no es una métrica: **que se pueda leer el código y entender por qué cada decisión está
tomada así.** Eso ya lo tiene, y es lo que hace este documento posible. Al crecer, no se diluye.

---

## Fuentes de la parte estratégica

- [AlternativeTo — alternativas de código abierto a CCleaner](https://alternativeto.net/software/ccleaner/?license=opensource)
- [StoredBits — mejores alternativas a CCleaner en 2026](https://storedbits.com/ccleaner-alternative/)
- [The High Tech Society — análisis de BleachBit](https://thehightechsociety.com/bleachbit-reviews/)
- [XDA — por qué cambiar de WinDirStat](https://www.xda-developers.com/stop-using-windirstat-and-switch-to-this-free-tool-instead/)
- [WizTree frente a WinDirStat](https://freeupdisk.com/blog/wiztree-vs-windirstat)
