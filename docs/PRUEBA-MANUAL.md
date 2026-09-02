# Prueba manual en Windows

Todo lo demás de este proyecto se verifica solo: la suite de Pester, el analizador estático y unos cuantos invariantes que leen el propio código. Pero **WPF no arranca en el entorno donde se ejecutan esas pruebas**, así que hay una parte del programa —la que el usuario toca— que no ha visto nadie funcionando.

Esta lista existe para eso. No es burocracia: cada punto dice **qué hacer**, **qué tiene que pasar** y, si no pasa, **a qué cambio hay que mirar primero**. Está ordenada por riesgo, no por el orden en que se usa el programa, para que las primeras diez casillas sean las que más información dan.

> **Si solo tienes diez minutos:** haz el bloque 0 y el bloque 1. Cubren lo único que puede estar roto de una forma que ninguna prueba automática detectaría.

> **Si nunca has dejado que el programa borre nada en tu equipo**, empieza por
> [la primera ejecución sin riesgo](#empieza-por-aquí-la-primera-ejecución-sin-riesgo): marca
> **Solo simular** en el pie de los resultados y el programa te enseña exactamente lo que haría
> sin tocar un archivo. Es la forma de descubrir un falso positivo sin pagarlo.

---

## Antes de empezar

**Ten a mano tu último informe.** El programa guarda uno con cada análisis en `%LOCALAPPDATA%\Cachivache\informes`. Si hay alguno de *antes* de estos cambios, es la mejor referencia que existe: un análisis nuevo en el mismo perfil debería proponer aproximadamente lo mismo. Pega esto en PowerShell para ver los que tienes:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Cachivache\informes" | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name, LastWriteTime, Length
```

**Y anota la versión de PowerShell**, porque es la diferencia que más veces ha mordido en este proyecto:

```powershell
$PSVersionTable.PSVersion
```

Si sale **5.1**, tu ejecución vale doble: las pruebas automáticas corren en PowerShell 7, y el único fallo de arranque que ha llegado a producción hasta hoy era una diferencia entre las dos versiones que 7 no podía reproducir.

---

## Bloque 0 · Que arranque

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Doble clic en `tools\Crear-ejecutable.bat` | Es la vía del usuario: no debe exigir abrir PowerShell ni tocar la política de ejecución. La ventana **se queda abierta** al terminar |
| ☐ | Lo que dice esa ventana | *"Listo"*, la ruta del icono y un tamaño de **unos 45 KB** (el icono se lleva casi todo). Si son cientos de KB, algo se ha colado dentro |
| ☐ | Doble clic en `Cachivache.exe` | Se abre la ventana **y no hay ninguna consola negra detrás**. Ese es el único motivo por el que el `.exe` existe |
| ☐ | Mira el icono del `.exe` en el Explorador y el de la ventana en la barra de tareas | La C turquesa, no el icono genérico de .NET ni el de PowerShell. Son dos caminos distintos: uno lo incrusta `csc`, el otro lo carga la ventana desde `assets\cachivache.ico` |
| ☐ | Mira el tema con el que abre | Debe coincidir con el de Windows (claro/oscuro) **la primera vez**. Si ya lo habías abierto antes, recuerda tu última elección, y eso también es correcto |

**Si Windows avisa al abrirlo** es SmartScreen: el ejecutable no está firmado. No es un fallo del programa. Usa `.\Cachivache.bat` y sigue.

**Si no arranca**, copia el mensaje entero —incluida la línea `archivo: línea`— antes de cerrar nada.

---

## Sesión de verificación · 2 de septiembre de 2026

Guion en orden para hacerlo de una sentada. **Las fases van de más urgente a menos**: si te quedas
sin tiempo, para donde estés — lo de arriba es lo que más falta hace.

**Reglas de la sesión, las tres:**

1. **No actives *Solo simular* salvo donde se diga**, y **no marques nunca el borrado permanente**.
   Todo tiene que poder rescatarse de la papelera.
2. Cuando algo no cuadre, manda **captura** y, si hubo error, el registro de
   `%LOCALAPPDATA%\Cachivache\registros\`. Desde `COR-06` lleva dentro el tipo de excepción y la
   línea exacta.
3. Si algo se ve raro pero no está en esta lista, **dilo igual**. Los dos fallos del 1 de septiembre
   los encontró un ojo mirando, no una casilla de este documento.

---

### Fase A · Las nueve rejillas — **lo único que nadie ha visto** (5 min)

El 1 de septiembre se arreglaron nueve `Grid` que colocaban cosas a la derecha sin declarar
columnas. Dos se solapaban de verdad; los otros siete eran la misma bomba sin estallar. **Aquí no
hay WPF: ninguna prueba puede mirar un píxel de esto.** Es la fase que de verdad hace falta.

Cierra el programa y vuelve a abrirlo antes de empezar.

| Paso | Dónde | Qué mirar | 📸 |
|---|---|---|---|
| A1 | **Resultados**, ventana ancha | Los cinco botones de la derecha se leen enteros y separados: *Marcar todo · Desmarcar todo · Solo lo seguro · Ver contenido · Abrir ubicación* | ✅ |
| A2 | **Resultados**, arrastra el borde derecho hasta que no quepa | *Ocultar lo ya eliminado* **baja de línea**. Nada se cruza | ✅ |
| A3 | **Resultados**, barra de abajo, con la ventana estrecha | *«N elementos marcados»* y la casilla *Solo simular* **no se pisan** | ✅ |
| A4 | **Inicio**, barra de abajo | *«Listo para analizar.»* y el botón *Analizar el equipo* separados | ✅ |
| A5 | **Registro** (`Ctrl+3`) | El párrafo de la izquierda y los botones *Copiar* / *Abrir carpeta* no se cruzan | ✅ |
| A6 | **Ajustes** (`Ctrl+5`) | Los dos deslizadores y sus rótulos, separados | ✅ |
| A7 | Marca **una sola cosa de riesgo Bajo** y pulsa *Eliminar lo marcado*. **Lee el diálogo y CANCELA** | Las tres filas del resumen (*Elementos marcados*, *Espacio*, *Destino*) con su valor a la derecha, sin pisarse | ✅ |

En A2 y A3 estrecha de verdad: hasta unos 1000 px, que es donde salió el fallo.

---

### Fase B · Lo del 1 de septiembre en el núcleo (5 min)

Es el **bloque 0 ter** de más abajo. Hazlo entero salvo el punto del USB, que ya está descartado
por no haber unidad extraíble.

Resumen: analiza `C:`, comprueba que termina sin franja de aviso, y **cronometra** un análisis con
perfil *Equilibrado* para ver si se ha vuelto lento.

---

### Fase C · Los dieciocho puntos de interfaz (15 min)

Es el **bloque 0 bis**. Llevan sin mirarse desde el 30 de agosto. Empieza por su discriminador de
versión y ve bajando.

---

## Bloque 0 ter · Lo del 1 de septiembre — **cuatro puntos que nadie ha visto nunca**

Esto es más nuevo que el bloque 0 bis y está **menos verificado que nada en este documento**: se
escribió, se probó con 2288 pruebas automáticas, y no lo ha mirado un ser humano ni una vez. Toca
el análisis en sí —lo que se mide y lo que se propone—, así que un fallo aquí sale en la primera
pantalla.

**Hazlo antes que el 0 bis.** Son cinco minutos y despeja lo más caro de arreglar si va mal.

### 0t.1 · El discriminador de esta versión

Antes de nada, en **Acerca de** (`Ctrl+6`) mira la versión. Y en **Inicio** (`Ctrl+1`), la lista de
discos de la izquierda tiene que enseñar **todas** tus unidades, no solo las internas. Si el USB no
aparece, estás en la versión anterior a `VIS-04` y el resto del bloque no significa nada.

### 0t.2 · Los discos extraíbles se analizan y NO se borra en ellos — `VIS-04`

Es el punto con más riesgo de los cuatro, porque cambia **qué se propone borrar**.

Enchufa el USB o el disco externo **antes de abrir el programa**.

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | **Inicio** (`Ctrl+1`), lista de discos | El USB **aparece**, con su espacio libre y su barra |
| ☐ | Déjalo marcado y pulsa **Analizar el equipo** | Termina sin franja de aviso |
| ☐ | **Resultados** (`Ctrl+2`), filtra por la letra del USB | Si sale algo suyo, mira la columna *qué pasa si se borra* |
| ☐ | Lee ese texto | Tiene que decir **«Se ha medido, pero no se borra nada en…: es una unidad extraíble y se puede desconectar en mitad del borrado»** |
| ☐ | Intenta marcar esa fila y pulsar **Eliminar lo marcado** | **No se borra.** Si desaparece algo del USB, para y dímelo: es lo único de hoy que destruiría datos |

**Estado a 1 de septiembre de 2026: SIN VERIFICAR, y no por olvido.** En el equipo de desarrollo no
hay ninguna unidad extraíble. Medido:

```powershell
[IO.DriveInfo]::GetDrives() | Select-Object Name, DriveType
# C:\  Fixed
# D:\  Fixed   <- la particion reservada de 50 MB; por eso sale en la lista de discos
```

O sea que `VIS-04` está probado por 2288 pruebas automáticas y **no lo ha visto funcionar nadie con
un disco extraíble de verdad enchufado**. El embudo es defensivo —si no sabe de qué clase es la
unidad, no borra— pero eso es un argumento, no una comprobación. Queda como deuda, no como punto
cerrado.

**Cuando haya un pendrive o una tarjeta SD a mano**, son dos minutos: la tabla de arriba, entera.

Y un aviso para ese día: un **pendrive** suele declararse `Removable` y `VIS-04` lo protege; un
**disco duro externo por USB** muchas veces se declara `Fixed`, y entonces Windows no lo distingue
de un disco interno y el programa tampoco puede. Eso no sería un fallo nuestro sino un límite del
sistema, pero cambiaría lo que hay que construir.

### 0t.3 · Lo comprimido ya no promete espacio que no existe — `VIS-05`

Un archivo comprimido por NTFS dice ocupar 100 MB y en el disco ocupa 30. Antes se prometían los
100.

Para tener uno: clic derecho en una carpeta grande → *Propiedades* → *Opciones avanzadas* →
**Comprimir contenido para ahorrar espacio en disco**. Su nombre se pone en azul en el Explorador.

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Analiza y busca algo dentro de esa carpeta comprimida | En *qué pasa si se borra* aparecen **las dos cifras**: lo que ocupa y lo que se libera |
| ☐ | Compara con lo que dice el Explorador (*Tamaño* y *Tamaño en disco*) | La cifra que **promete liberar** es la segunda, la pequeña |
| ☐ | Mira el total del pie de Resultados | No promete más de lo que hay |

### 0t.4 · Lo que más me preocupa: que el análisis no se haya vuelto lento

Cuatro módulos preguntan ahora al sistema cuánto ocupa cada cosa **de verdad**. Se pregunta solo
cuando el archivo lleva la marca de comprimido, precisamente para no pagarlo siempre — pero eso no
se ha medido nunca en Windows.

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Cronometra un análisis con perfil **Equilibrado** | Parecido a lo que tardaba antes |
| ☐ | Si notas que va bastante más lento, **dilo** | Se arregla en una función; lo caro es no enterarse |

---

## Bloque 0 bis · La tanda del 30 de agosto — **dieciocho puntos sin ver**

Esta es la lista de esta subida. Todo lo de aquí es **XAML o cableado de ventana**, o sea lo único
que ninguna prueba de este proyecto puede ejecutar. Está ordenado por lo de siempre: si falla el
primero, los de debajo dan igual.

**Antes de nada, el discriminador de versión.** Si estas tres cosas no están, estás ejecutando la
versión vieja y el resto de la lista no significa nada:

- En **Resultados**, junto al desplegable de riesgo, una casilla **«Ocultar lo ya eliminado»**.
- En **Ajustes**, una tarjeta **«Lo que no se toca nunca»**.
- En **Acerca de**, un botón **«Buscar si hay una versión nueva»**.

### 0b.1 · Que la ventana abra y la tabla pinte sus grupos

Es lo único que, si falla, invalida todo lo demás. El contenido de una plantilla de WPF se analiza
**tarde**, al aplicarse: el XAML puede cargar, la ventana abrir, y reventar al aparecer la primera
cabecera de grupo. Ya pasó en `USO-14`.

- [ ] La ventana abre y un análisis pinta la tabla agrupada por categoría.

### 0b.2 · El menú contextual y el doble clic — `USO-06`

- [ ] **Clic derecho sobre una fila: ¿queda esa fila seleccionada antes de aparecer el menú?** Es lo
      único que no se pudo comprobar y de lo que dependen las cuatro órdenes, que actúan sobre la fila
      *seleccionada*. Si el clic derecho no selecciona, el menú actuaría sobre la fila anterior.
- [ ] El menú **se lee**: letra clara sobre fondo oscuro. Si sale un menú blanco de Windows, el color
      no se ha heredado.
- [ ] **Copiar ruta** sobre una fila normal: pega en la barra del Explorador y llega.
- [ ] **Copiar ruta sobre algo sin ruta real** (la Papelera, o Docker si sale): tiene que salir un
      aviso y **no** cambiar el portapapeles. Comprueba pegando: debe seguir lo de antes.
- [ ] **Doble clic** en una fila abre su carpeta. Sobre la cabecera de columna sigue ordenando.

### 0b.3 · Excluir y desexcluir — `USO-06` + `CNF-01`

Es la vuelta completa, y la que más partes nuevas junta.

- [ ] *Excluir siempre esto* sobre algo inofensivo → el diálogo dice **«Podrás quitarlo cuando quieras
      en Ajustes»**. Si dice *«editando preferencias.json»*, es la versión vieja.
- [ ] Acepta: la fila **se desmarca al momento**.
- [ ] **Ajustes → Lo que no se toca nunca**: la exclusión está, con la ruta entera.
- [ ] Pulsa **Quitar**: desaparece **sin preguntar**, y el registro dice *«Ya no está excluido…»*.
- [ ] Repite con algo que **no** sea una carpeta (Docker, la Papelera): la fila tiene que leerse
      *«Caché de Docker»*, **nunca** `modulo:dockerwsl|Caché de Docker`. Y **Quitar** tiene que
      quitarla: si esa fila no se va, la clave no está llegando al botón.
- [ ] Cierra y reabre el programa: lo excluido sigue excluido.

### 0b.4 · Estados vacíos y ocultar lo eliminado — `USO-09` + `USO-13`

- [ ] Resultados **sin analizar**: un recuadro con borde en medio de la tabla, no un rectángulo en
      blanco.
- [ ] Con la lista llena, escribe `zzzzz` en el filtro: sale el texto con el **número real** de
      elementos y el botón **Quitar el filtro de texto**. Pon además el desplegable en *Solo riesgo
      alto*: el botón pasa a decir **Quitar los dos filtros**.
- [ ] Pulsa el botón: vuelve la tabla entera, el desplegable a *Todos los riesgos*, y el cursor al
      cuadro de filtro.
- [ ] Limpia varias cosas, marca **Ocultar lo ya eliminado**: desaparecen las verdes y **lo que falló
      sigue viéndose en rojo**. Esa es la mitad que importa.

### 0b.5 · Teclado y lector de pantalla — `A11Y-01`, `A11Y-04`, `A11Y-06`

- [ ] `Ctrl+2` y `Ctrl+5` cambian de panel.
- [ ] Escribe `chrome` en el filtro: **las letras llegan al cuadro**. Si el campo se queda vacío, el
      despachador de atajos se está comiendo las teclas.
- [ ] `Ctrl+A` **dentro** del filtro selecciona el texto; **fuera**, marca la tabla.
- [ ] `F5` con un análisis corriendo no hace nada; `Esc` lo cancela.
- [ ] Tab desde la barra lateral: **ninguna parada nueva ni vacía**.
- [ ] Con el **Narrador** (`Ctrl+Win+Enter`; `Ctrl` lo calla): los botones de la barra de título dicen
      su nombre, cambiar de panel anuncia el panel, y la casilla de una fila dice **el nombre del
      elemento**.

### 0b.6 · Acerca de: versión y diagnóstico — `DIS-05` + `USO-12`

- [ ] Pulsa **Buscar si hay una versión nueva** y, mientras piensa, **arrastra la ventana**. Tiene que
      moverse. Si se congela, el runspace de la consulta no está haciendo su trabajo.
- [ ] Terminará diciendo *«No se ha podido comprobar»* — **es lo esperado** hasta que publiques una
      versión con etiqueta.
- [ ] **Copiar diagnóstico** → pega en el Bloc de notas y compáralo con `.\Cachivache.ps1 -Diagnostico`.
      Tienen que ser el mismo texto.
- [ ] Marca **Anonimizar rutas**, guarda un informe HTML y busca tu nombre de usuario dentro: no debe
      estar. Repite con CSV y JSON desde *Informes* — la casilla vale también para ellos.

### 0b.7 · La tabla ya no te devuelve al principio — `USO-10`

Es lo más molesto de todo lo que había, y **hace falta un análisis largo para verlo**: perfil
**Exhaustivo**, y hay que mirar la tabla *mientras* sigue analizando.

- [ ] Con el análisis en marcha, **baja hasta la fila 200 y quédate ahí**. Cuando termine el módulo
      siguiente y aparezcan filas nuevas, **la tabla no se mueve**. Antes saltabas al principio en
      cada módulo.
- [ ] **Selecciona una fila cualquiera** y espera a que termine otro módulo: la fila **sigue
      seleccionada**.
- [ ] Escribe algo en el filtro que **esconda esa fila seleccionada** y deja que termine un módulo.
      Al quitar el filtro, **no debe quedar nada raro seleccionado**. Es deliberado: una selección
      que no se ve no se restaura, porque *Abrir la ubicación* actuaría sobre ella.
- [ ] Con la tabla llena y desplazada, **cambia de tema** (el botón de la luna/sol). Los colores
      cambian y **sigues donde estabas**. Este sitio no estaba en el plan; salió al arreglarlo.
- [ ] Si algo de esto no va, **mira el registro**: un fallo aquí se anota con nivel `AVISO` y el
      texto *«No se ha podido restaurar la posición de la tabla»*. Que no aparezca esa línea es
      parte de la comprobación.

### 0b.8 · Lo que se ve solo mirando

- [ ] **El resumen del análisis compara con el anterior** (`CNF-06`): al terminar el segundo análisis
      debe decir algo como *«(hace 4 días eran 890 elementos y 3,20 GB)»*. En el primero no dice nada,
      que es lo correcto.
- [x] ~~**El ancho de la barra de Resultados**: la casilla nueva suma unos 170 px a la fila de
      filtros, que ya iba justa. A 1020 px de ancho, ¿se solapan los filtros con los botones de la
      derecha?~~ **SÍ SE SOLAPABAN.** Confirmado el 1 de septiembre de 2026, la primera vez que
      alguien miró la ventana: *Marcar todo*, *Desmarcar todo* y *Ocultar lo ya eliminado* se
      pintaban unos encima de otros e ilegibles. La barra era un `Grid` sin columnas con los dos
      grupos en la misma celda. Arreglado, y con invariante en `tests/Invariantes.Tests.ps1`.
- [ ] **Vuelve a mirar esa fila**, que el arreglo no lo ha visto nadie: los cinco botones de la
      derecha (*Marcar todo* … *Abrir ubicación*) se leen enteros y separados, y el filtro, el
      desplegable y la casilla no se cruzan con ellos. **Estrecha la ventana** hasta que no quepan:
      la casilla debe **bajar a una segunda línea**, no recortarse ni superponerse.
- [ ] **`COR-08`, y esto es medible:** cronometra un análisis con perfil **Exhaustivo** y compáralo con
      lo que tardaba antes. El recorrido cambió de motor y en PowerShell 5.1 se espera empate o mejora,
      pero no se ha podido medir en Windows. Si se nota lento, dilo: el arreglo es de una sola función.

---

## Bloque 1 · Lo que ha cambiado esta semana

Aquí está el riesgo real. Son cambios de rendimiento, y un cambio de rendimiento mal hecho **no da error: da un resultado distinto en silencio.**

### 1.1 El filtro de resultados

Antes de nada haz un análisis (perfil **Equilibrado**) para tener filas con las que jugar.

| | Qué hacer | Qué tiene que pasar | Si falla |
|---|---|---|---|
| ☐ | Escribe `cache` en el cuadro de filtro, a velocidad normal | La lista se reduce **un cuarto de segundo después de que pares de escribir**, no letra a letra | El temporizador o el ámbito de `$solicitarFiltro`, en `Window.Ayudantes.ps1` |
| ☐ | Escribe una palabra larga **muy rápido** | No se pierde ninguna letra y la ventana no da tirones | Lo mismo |
| ☐ | Borra el texto del todo | Vuelve la lista completa | `Filter = $null` cuando no hay criterios |
| ☐ | Escribe `*` y luego `[` | Los busca **como texto literal**. Antes se interpretaban como comodines y daban resultados absurdos o ninguno | El cambio de `-like` a `IndexOf` |
| ☐ | Cambia el desplegable de riesgo | Filtra **al momento**, sin esperar (esto es a propósito: elegir en una lista no se encadena como las teclas) | |

> **El fallo más probable de toda esta lista** es que el filtro no filtre *en absoluto*: sin error, sin excepción, simplemente no pasa nada al escribir. El temporizador se conecta sin `GetNewClosure`, deliberadamente y por el mismo motivo que el manejador de casillas, pero si me he equivocado de ámbito el síntoma es exactamente ese.

### 1.2 El resumen del pie

| | Qué hacer | Qué tiene que pasar | Si falla |
|---|---|---|---|
| ☐ | Marca y desmarca una casilla cualquiera | El pie actualiza **número de elementos y bytes** al instante | El recorrido único de `$actualizarResumenSeleccion` |
| ☐ | Con la tabla llena, marca varias seguidas | Sin congelaciones perceptibles entre clic y clic | Lo mismo |
| ☐ | Pulsa *Marcar todo* sin filtro, y **después** escribe algo en el filtro | El pie debe decir **"(N que el filtro no está mostrando)"** | El segundo recorrido, que ahora solo ocurre si hay filtro |
| ☐ | Pon un filtro, pulsa *Marcar todo*, quita el filtro | Solo quedan marcadas **las que estaban a la vista**. Esto es una garantía de seguridad, no una comodidad | |

### 1.3 Los discos y el espacio libre

Esto ha pasado de WMI a `System.IO.DriveInfo`, y es el punto que **menos se ha podido comprobar**: la prueba que fija la forma de la letra de unidad no muerde fuera de Windows.

| | Qué hacer | Qué tiene que pasar | Si falla |
|---|---|---|---|
| ☐ | Mira el panel lateral de Inicio | Aparecen **todos** tus discos fijos, con su letra (`C:`, `D:`…), su etiqueta y el porcentaje usado | `Get-UnidadesFijas` |
| ☐ | Compara el espacio libre con el Explorador | Debe coincidir | `AvailableFreeSpace` |
| ☐ | Mira el pie: *"En C: pasarías de X a Y"* | X coincide con el Explorador | `Get-EspacioLibre` |
| ☐ | Desmarca un disco y analiza | No sale ni un candidato de esa unidad | El filtro de unidades |
| ☐ | Si tienes algo en la papelera, analiza con el módulo `papelera` | Lo encuentra y da un tamaño razonable | La letra con o sin `\` final: es justo el sitio donde se hace `Letra + '\'` |

### 1.4 Que el análisis siga encontrando lo mismo

Este es el bloque que justifica haber guardado los informes.

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Analiza con el **mismo perfil** que tu informe anterior y compara los totales por categoría | Parecidos. No idénticos —el disco cambia entre un día y otro— pero **una categoría que desaparece o que se queda a la mitad es una señal** |
| ☐ | Elige una carpeta grande que proponga (un `node_modules`, una caché) y mira sus propiedades en el Explorador | El tamaño debe cuadrar. Ojo con dos cosas: el Explorador enseña *tamaño* y *tamaño en disco*, que no son lo mismo; y si esa carpeta contiene una **junction**, ahora el programa da menos, y eso es correcto y deliberado |
| ☐ | Comprueba que siguen apareciendo `caches`, `navegadores` y `proyectos` | Son los tres que más cambiaron de orden interno |
| ☐ | Mira el texto bajo la barra de progreso, en Inicio, mientras analiza | Va diciendo *"Midiendo: …"* con el módulo *(N de 18)*. Ya no aparece para rutas que la guardia veta —se pregunta antes de medir— y eso es una mejora, no una pérdida |

---

## Bloque 2 · Lo visual, acumulado sin verificar

Nada de esto se ha visto funcionando: la paleta, las etiquetas, el XAML partido en seis paneles y el arreglo del maximizado.

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Maximiza la ventana | **No se mete por debajo de la barra de tareas** ni la tapa |
| ☐ | Si tienes la barra de tareas arriba o en un lado, o dos monitores: maximiza en cada uno | Lo mismo en todos. Se calcula por monitor a propósito |
| ☐ | Restaura y vuelve a maximizar un par de veces | Sin saltos ni tamaños raros |
| ☐ | Recorre los seis paneles: Inicio, Resultados, Registro, Informes, Ajustes, Acerca | Ninguno aparece vacío, descolocado ni a medias. El XAML se partió en seis archivos y se vuelve a montar al arrancar |
| ☐ | Cambia de tema con el botón de la luna, en cada panel | Todo legible en claro **y** en oscuro. Fíjate en las etiquetas de riesgo: son un punto de color y texto, sin fondo |
| ☐ | Mira las etiquetas de riesgo y las insignias | Bajo/Medio/Alto bien diferenciados, y el verde de "correcto" distinto del acento turquesa |
| ☐ | Pasa el ratón por botones, filas y pestañas | Los estados de hover y foco se ven, y el botón de cerrar se pone rojo |

> El cambio de tema tarda cerca de un segundo con la tabla llena. **Es conocido y está medido**; el arreglo es de la Fase C. Aquí solo interesa que no rompa nada.

---

## Bloque 3 · Que borrar siga siendo seguro

Es el bloque más importante y el que menos hay que forzar. **No actives el borrado permanente para esta prueba.**

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Marca **dos o tres** elementos de riesgo Bajo y sin aviso, y elimínalos | Pide confirmación escribiendo `SI` |
| ☐ | Abre la papelera de Windows | **Están ahí.** Recupéralos |
| ☐ | Marca algo de riesgo Medio o Alto | Ahora la confirmación exige escribir `ELIMINAR`, no `SI` |
| ☐ | Comprueba que lo que lleva aviso sale **en rojo y sin marcar** | Es una invariante del programa: nada arriesgado viene marcado de fábrica |
| ☐ | Cancela un análisis a mitad | Se detiene y la ventana responde |
| ☐ | Mira `%LOCALAPPDATA%\Cachivache\registros` | Hay una línea por acción, con el identificador de sesión |

### 3.1 · Los enlaces duros — `VIS-03`. **Esto SOLO lo puede comprobar tu equipo**

La unidad de los ejecutores de GitHub no admite enlaces duros, así que en la
integración continua estas cuatro pruebas **se saltan** con el motivo *"el
sistema no admite enlaces duros"*. Se saltan limpiamente y la pasada sale
verde: es decir, `VIS-03` **no lo verifica nadie salvo tú**. Se descubrió
leyendo el registro de la CI del 1 de septiembre de 2026, no porque algo
fallara.

Dos enlaces duros al mismo contenido son **un solo archivo** ocupando espacio
una sola vez. Si el programa los cuenta dos veces, promete liberar el doble de
lo que hay; y si propone borrar uno como si fuera un duplicado, el usuario
pierde un nombre creyendo que conserva el otro.

Desde una consola en una carpeta temporal tuya:

```
mkdir %TEMP%\cachivache-enlaces
cd /d %TEMP%\cachivache-enlaces
fsutil file createnew original.bin 10000000
mklink /H copia.bin original.bin
```

| | Qué hacer | Qué tiene que pasar |
|---|---|---|
| ☐ | Analiza esa carpeta y mira lo que dice ocupar | **10 MB, no 20**: el contenido se cuenta una sola vez |
| ☐ | Mira si el módulo de duplicados propone borrar `copia.bin` | **NO lo propone.** No es una copia, es el mismo archivo con otro nombre |
| ☐ | Borra la carpeta entera cuando termines | `rmdir /s /q %TEMP%\cachivache-enlaces` |

Si el primer punto dice 20 MB, es la degradación conocida de PowerShell 7
(`COR-09`): en 5.1 el enlace duro se detecta y en 7 no. El programa arranca en
5.1, así que **la respuesta que cuenta es la de la ventana**, no la de una
consola de `pwsh`.

---

## Bloque 4 · Modo consola

Merece dos minutos por un motivo concreto: la consola es el único sitio donde `$ErrorActionPreference` vale `Stop`, y eso cambia cómo se comporta cualquier error no terminante dentro de las funciones que se han tocado.

```powershell
.\Cachivache.ps1 -Listar
.\Cachivache.ps1 -Consola -Perfil conservador -Informe .\informe.html
.\Cachivache.ps1 -Diagnostico
```

| | Qué tiene que pasar |
|---|---|
| ☐ | `-Listar` enseña los 21 módulos |
| ☐ | El análisis termina **sin ninguna excepción roja** y escribe `informe.html` |
| ☐ | Abre el HTML: se ve bien y los números cuadran con los de la ventana |
| ☐ | `-Diagnostico` enseña versión, entorno, **unidades** y las últimas líneas del registro |

La sección *Unidades* del diagnóstico es la comprobación más rápida de que `DriveInfo` funciona: si sale vacía en un equipo con discos, ahí está el fallo.

---

## Empieza por aquí: la primera ejecución sin riesgo

Antes de dejar que el programa borre nada en tu equipo, hazle enseñar lo que haría. Se puede
desde la ventana y desde la consola; **desde la ventana es el camino normal**.

### Desde la ventana (doble clic en `Cachivache.exe`)

Analiza como siempre. Después, en el pie de la lista de resultados, junto al botón rojo, hay una
casilla **Solo simular**. Márcala y pulsa.

| | Qué tiene que pasar | Si falla |
|---|---|---|
| ☐ | Al marcarla, el botón deja de ser rojo y pasa a decir **Simular limpieza** | `$sincronizarSimular` en `Window.Eventos.ps1` |
| ☐ | Al pulsarlo **no aparece el diálogo de confirmación**. No hay nada que confirmar | La rama `if (-not $simular)` en el manejador de `BtnEliminar` |
| ☐ | Mientras corre, la barra dice *"Midiendo: …"*, no *"Eliminando: …"* | `$verbo` en `Window.Analisis.ps1` |
| ☐ | Al terminar: **SIMULACIÓN TERMINADA: se habrían eliminado N… NO SE HA BORRADO NADA** | |
| ☐ | Las filas **siguen marcadas** y ninguna pone *Eliminado* | |
| ☐ | Ve a la pestaña **Informes**: no hay ningún informe de limpieza nuevo | El corte de `$simulado` en `Window.Eliminacion.ps1` |
| ☐ | Ve al **Historial**: no hay ninguna entrada de limpieza nueva | Lo mismo |
| ☐ | Cierra el programa y vuelve a abrirlo: la casilla está **desmarcada** | Es a propósito; ver la nota en `Preferencias.ps1` |

Los dos últimos puntos son el corazón de esto. Un historial con limpiezas que nunca ocurrieron y
un informe titulado *limpieza* lleno de archivos que siguen en el disco son la misma clase de
mentira que esta auditoría lleva corrigiendo desde el principio.

### Desde la consola

```powershell
.\Cachivache.ps1 -Consola -Ejecutar -Simular
```

Anota cada elemento en el registro como `[SIMULACION] Se borraría: …` y no toca ni un archivo.

| | Qué mirar |
|---|---|
| ☐ | El resumen dice *"Se habrían eliminado N"* y termina con **NO SE HA BORRADO NADA** |
| ☐ | Lee la lista del registro. ¿Hay algo ahí que **no** quieras perder? |
| ☐ | Si lo hay, exclúyelo: `-Excluir 'C:\Esa\Carpeta'` y vuelve a simular |
| ☐ | Cuando la lista te parezca bien, quita `-Simular` |

> **Ojo con el `.exe` y la consola.** `Cachivache.exe` sí pasa los argumentos al programa, pero se
> compila como ejecutable *de ventana* (`/target:winexe`) y arranca PowerShell con
> `CreateNoWindow`. Es justo lo que queremos para la interfaz —ninguna consola negra detrás— pero
> significa que `Cachivache.exe -Consola` **no enseña nada**: el proceso corre sin ventana donde
> escribir. Para el modo consola, usa `Cachivache.bat` o PowerShell directamente.

Si algo de lo que propone te sorprende, **eso es un fallo que merece reportarse**, aunque no
llegues a borrarlo. Es exactamente la información más valiosa que puede recibir este proyecto.

---

## Ciclo de vida del runspace (fase 6 del plan de acción)

Estas cuatro comprobaciones no las puede hacer la suite: WPF no arranca en las pruebas. Son la
única parte de la reescritura de `[INT-01]` y `[INT-02]` que depende de mirar la ventana.

El cambio: antes se creaba **un runspace por módulo** —veintiuno por análisis, cada uno cargando
las más de cuatro mil líneas de `src/Core`—. Ahora se abre uno al empezar y se cierra al terminar.

| | Qué tiene que pasar |
|---|---|
| ☐ | **Análisis completo.** Termina, la lista se llena y el botón *Analizar* vuelve a estar disponible. Debería notarse claramente más rápido en arrancar cada módulo. |
| ☐ | **Cancelar a mitad.** Pulsa *Cancelar* con el análisis en marcha: la ventana vuelve a estado de reposo y *Analizar* se puede pulsar otra vez. |
| ☐ | **Dos análisis seguidos.** Lanza uno, déjalo terminar, y lanza otro sin cerrar el programa. Tiene que funcionar igual que el primero: es lo que comprueba que el runspace se cerró y se vuelve a abrir bien. |
| ☐ | **Cerrar en mitad de un borrado.** Con una limpieza en marcha, cierra la ventana. Al volver a abrir, el historial debe tener una entrada `limpieza-interrumpida` con lo que llegó a borrarse. |
| ☐ | **Cambiar de tema durante un análisis.** Los colores cambian y el análisis sigue sin inmutarse. La barra de espacio en disco no se actualiza hasta que termine: es deliberado (`[INT-03]`). |

Si el Administrador de tareas muestra el consumo de memoria de Cachivache subiendo análisis tras
análisis sin bajar, el runspace no se está cerrando: eso es lo que hay que reportar.

---

## Si algo falla

No hace falta que lo diagnostiques. Lo que sirve:

1. **El mensaje completo**, con la línea `archivo: línea` si la hay. Un pantallazo vale.
2. **`.\Cachivache.ps1 -Diagnostico`**, que ya trae versión, entorno, unidades y el final del registro.
3. **Qué esperabas y qué pasó.** "El filtro no hace nada al escribir" es suficiente: dice más que cualquier teoría sobre por qué.

Con eso se localiza. Y si el fallo es que el programa **propone borrar algo que no debería**, eso no es un fallo normal: mira [`SECURITY.md`](../SECURITY.md) antes de publicarlo en ningún sitio.
