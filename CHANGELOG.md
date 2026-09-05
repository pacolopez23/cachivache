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
- **Excluir un comando ya significa algo.** La lista de «no tocar nunca» comparaba contra la ruta del
  elemento, y para un comando o para la papelera esa «ruta» es una **etiqueta**: se comparaba en
  minúsculas, sin barra final y por prefijo de carpeta, sobre algo que no tiene carpetas. Ahora cada
  candidato lleva una clave estable —la ruta cuando la hay, y una clave sintética con una barra
  vertical cuando no, que ninguna exclusión de carpeta puede alcanzar—. Para todo lo que ya
  funcionaba no cambia nada. `[ARQ-03]`
- **Y un comando excluido ya se comprueba también antes de ejecutarse.** La revalidación de la
  exclusión en el motor estaba dentro del `if` que separa los comandos del resto, así que la única
  clase de candidato que lanza un binario externo era justo la que se la saltaba. `[ARQ-03]`
- **El programa ya encuentra lo que hay al fondo de una ruta larga.** `COR-02` arregló medir y
  borrar las rutas de más de 260 caracteres, pero no **encontrarlas**: los ocho módulos recorrían con
  `Get-ChildItem -Recurse`, que en PowerShell 5.1 se para ahí y bajo `SilentlyContinue` no dice nada.
  Un `node_modules` anidado o una caché de Gradle desbordan el límite con facilidad, y el programa
  medía de menos y borraba de menos, igual que antes de `COR-02` pero por otro motivo. `[COR-08]`
- **Y de paso, dos sitios peores que ese.** La comprobación que busca enlaces dentro de una carpeta
  antes de borrarla recursivamente se paraba a los 260 — pero el borrado que viene después **no**,
  porque ya usaba el prefijo: una guardia que mira menos que la acción que protege. Y la lista de
  programas instalados que consulta la guardia se truncaba, con lo que una carpeta legítima podía
  parecer desconocida y **proponerse para borrar**. `[COR-08]`
- **El banco de pruebas se ejecuta solo, en cada push.** La integración continua lo monta en un
  agente de Windows y hace una limpieza **real**: comprueba que los cebos aparecen, que no se propone
  nada del sistema, las rutas largas, los enlaces duros, dos análisis seguidos y —gratis, porque los
  agentes están en inglés— buena parte de lo que `I18N-03` avisaba y nadie había ejecutado nunca
  fuera del español. `[VAL-03]`
- **Y lo primero que encontró fue que el banco no podía funcionar.** Tres de los cebos empezaban por
  palabras de la lista de archivos personales de la guardia, así que quedaban protegidos como trabajo
  del usuario y **no se proponían nunca**: los dos pasos que ese documento existe para comprobar
  —la papelera que no cabe y las rutas largas— eran incomprobables. `[VAL-03]`
- **Ya se pueden QUITAR las exclusiones desde la ventana.** `CNF-01` daba por hecha en su banner una
  tarjeta de Ajustes que nunca se hizo, y cuando `USO-06` añadió *Excluir siempre esto* al menú
  contextual quedó una puerta de un solo sentido: se añadían exclusiones pero deshacerlo exigía
  editar `preferencias.json` a mano. Ahora está la tarjeta *Lo que no se toca nunca*, con la lista y
  un botón por fila. Una clave interna como `modulo:dockerwsl|Caché de Docker` se enseña legible sin
  perder la clave real, que es la que hay que quitar. **Quitar no pide confirmación y añadir sí**: la
  asimetría sigue la dirección del daño, no la del esfuerzo. `[CNF-01]`
- **Menú contextual en la tabla, y doble clic.** *Abrir ubicación · Copiar ruta · Excluir siempre
  esto · Desmarcar el grupo*; el doble clic abre la carpeta. Copiar una ruta no se podía hacer de
  ninguna forma. Copiar algo que **no tiene ruta real** —un comando, la papelera— no copia nada y lo
  dice: el portapapeles no cuenta de dónde salió lo que lleva dentro, y el usuario lo descubriría al
  pegarlo, en otro programa y sin ninguna pista. `[USO-06]`
- **Casilla «Ocultar lo ya eliminado».** Esconde lo que se borró bien; **lo que falló sigue viéndose
  siempre, en rojo**. Es casilla y no automático: esconder el resultado justo cuando acabas de
  pulsar el botón es hacer el trabajo y no decirlo. `[USO-13]`
- **El resumen del análisis compara con el anterior**: *«(hace 4 días eran 890 elementos y 3,20
  GB)»*. Un análisis incompleto, o hecho con otro perfil, se compara **diciendo que no son cifras
  equiparables**; y cuando no hay con qué comparar, no se dice nada — no hay ningún «0 elementos
  antes» que inventar. `[CNF-06]`
- **Buscar si hay una versión nueva**, en *Acerca de*. **Solo si pulsas el botón**: ni al arrancar,
  ni al abrir ese panel, ni con un temporizador. El programa presume de no tener comunicación de
  red, y una consulta automática entrega tu IP y la hora a un tercero cada vez que abres una
  pantalla. Con el botón, la promesa sigue siendo cierta y además es comprobable. `[DIS-05]`
- **Anonimizar rutas al guardar un informe, y copiar el diagnóstico**, las dos desde la ventana.
  Estaban solo en la consola, que es donde no llega quien abre el programa con doble clic. Llaman a
  la misma función que la CLI, con invariantes que impiden que se separen. `[USO-12]`
- **Los filtros del embudo son ahora una lista de reglas**, y eran **cuatro**, no tres: había un
  filtro sin nombre escondido dentro de otro. La guardia, que es la única que toca el disco, estaba
  la primera: ahora va la última y a un candidato de una unidad no elegida ya no se le pregunta al
  disco. `[ARQ-02]`
- **El aviso para quien traduzca el programa es ahora una prueba que falla.** Las listas de palabras
  de la guardia son lógica de seguridad, no texto de interfaz: si alguien se las lleva a un archivo
  de idioma, rompe la guardia en silencio. `[I18N-02]`

### El diario de cambios de NTFS: se lee bien, y aun así no sirve

`VEL-02` queda **medido y descartado**, como `VEL-01`. Se ejecutó por primera vez en un Windows real
y como administrador, que es la única forma de saberlo.

**Lo que funciona.** Leer el diario de NTFS desde PowerShell **se puede**: la llamada al sistema, el
volumen abierto en crudo y el parseo de registros son correctos contra hardware real, y el disco
sirve los registros en la versión que el programa sabe leer. Había un fallo, y era de una línea: la
máscara de razones se escribía `[uint32]0xFFFFFFFF`, y en PowerShell ese literal no vale 4.294.967.295
sino **−1**, así que reventaba dos líneas antes de la llamada al sistema. Desde fuera se veía idéntico
a *«Windows ha dicho que no»*. La pista fueron los **81 ms** que tardaba en fallar: ninguna llamada al
sistema tarda tan poco.

**Lo que no funciona, y son dos cosas distintas.** Parsear el diario en PowerShell va a **74–82
registros por segundo**: el diario entero son 70 minutos, contra los **42 segundos** que cuesta
recorrer el disco. El atajo era 100 veces más lento que el camino largo. Y aunque se arreglara —en
C# sería menos de un segundo—, el diario **solo conserva entre 10 y 80 minutos de historia**, medido
con reloj. Un limpiador de disco se usa cada semanas: cuando el usuario vuelve, el diario ya olvidó
lo que hacía falta.

**Lo que se rescata.** El único momento en que el atajo se dispararía es al reanalizar justo después
de limpiar. Y ese caso no necesita ningún diario: **el programa ya sabe qué acaba de borrar.** Queda
abierto como `VEL-04`, funciona sin permisos de administrador y hasta en discos que no son NTFS.

De propina, una invariante nueva barre todo el repositorio buscando la trampa del literal: un `0x` de
ocho dígitos que empiece por 8-F es un `Int32` negativo. Estaba explicada por escrito **en la cabecera
del mismo archivo que la cometía**, 436 líneas más arriba. Saber una cosa escrita no es tenerla
comprobada.

### Marcar 5.000 filas ya no deja la ventana colgada

`VEL-03`. *Marcar todo*, *Desmarcar todo* y *Solo lo seguro* recorrían la lista entera de un tirón en
el hilo de la interfaz. Con 119 elementos no se nota; con 5.000 —un disco con muchos duplicados— la
ventana se quedaba congelada varios segundos, sin repintar y sin responder, hasta que Windows podía
llegar a ofrecer cerrarla. El usuario no veía un programa trabajando: veía un programa roto.

Ahora, por encima de 2.000 filas se trocea en tandas de 500 y entre tanda y tanda se deja repintar.
Por debajo del umbral se hace de un tirón, **igual que antes**: respirar cuesta una vuelta por
trozo, y con pocas filas eso solo añade lentitud y parpadeo donde no había ninguno.

**Y arreglarlo abrió un agujero que no estaba en el enunciado.** Una ventana que responde también
**acepta clics**: mientras se marcan 5.000 filas, el botón de eliminar sigue ahí, y se podría pulsar
con la mitad de las filas marcadas creyendo que están todas. Congelada, la ventana estaba protegida
*por accidente*. Así que el arreglo apaga los cuatro botones que pueden hacer daño mientras dura y
los vuelve a encender en un `finally`.

La decisión vive en `Get-PlanMarcadoEnLote` (`src/UI/Lotes.ps1`), cálculo puro y sin un solo tipo de
WPF, porque aquí no hay interfaz gráfica que mirar. La invariante no mide el rendimiento —eso no se
puede desde aquí— sino que **los trozos cubran exactamente las filas**: se recorre el plan sobre
5.001 posiciones y se exige que cada una se toque una sola vez. Trocear es la forma clásica de perder
la última fila.

De propina, una prueba se cazó a sí misma: *«Lotes.ps1 no menciona ningún tipo de `System.Windows`»*
salía roja porque **la cabecera del archivo promete justamente eso**, con esas palabras. Ahora mira
el código y no los comentarios, como ya hacía la prueba equivalente de `Posicion.ps1`.

### El paquete que se le entrega al usuario llevaba dentro el banco de pruebas

Ensayando el empaquetado en local **antes** de etiquetar la primera versión —el canal de
distribución está escrito desde hace días y no se había ejecutado nunca— salió que `publicar.yml`
copiaba **`tools/` entera** al `.zip`. Iban dentro los cinco bancos, `Mutar.ps1` y el ejecutor de
pruebas: 14 archivos que nadie necesita para ejecutar el programa.

Y no es solo desorden. **`Banco-Pruebas.ps1` crea y borra árboles de archivos** —su propia cabecera
dice *«EJECUTAR SOLO EN UNA MÁQUINA VIRTUAL CON INSTANTÁNEA»*— y `Mutar.ps1` reescribe archivos
fuente a propósito. Eso viajaba a cualquiera que se bajase un limpiador de disco.

Lo mejor del hallazgo es dónde estaba: **justo debajo de un comentario que decía *«ni pruebas, ni
herramientas de desarrollo, ni el `.github`»***. El comentario declaraba la intención correcta y la
línea siguiente hacía lo contrario, y llevaban así desde que se escribió el flujo.

La invariante nueva no prohíbe `tools` por su nombre —eso sería escribir la lista de los fallos que
ya conocemos, que es la regla 8— sino que exige que **cada elemento del paquete esté declarado con
su motivo**: qué es y por qué lo necesita quien lo descarga. Añadir algo obliga a justificarlo, y
quitar algo sin quitar su motivo también se ve. Además comprueba lo que hay **dentro** de cada
carpeta entregada, no su nombre.

El paquete pasa de 105 a 91 entradas y de 594 a 528 KB, con cero herramientas de desarrollo dentro.

### `VEL-02`, la mitad de Windows: leer el diario de cambios de NTFS

Tres archivos nuevos y una prueba de costura. `src/Core/DiarioUsn.ps1` convierte los bytes de un
registro `USN_RECORD_V2` en un objeto —**64 pruebas byte a byte**, 16 mutaciones cazadas—;
`src/Core/DiarioUsnCambios.ps1` convierte la lluvia de registros del diario —el sistema emite crear,
extender y cerrar como tres— en la lista limpia de altas, bajas y cambios que `Update-IndiceConCambios`
ya sabe aplicar, colapsando por archivo, respetando el orden por USN y tratando el renombrado como
baja + alta (**43 pruebas**, 12 mutaciones cazadas). Y `Test-PuedeLeerDiarioUsn` decide si se puede
leer el diario y, si no, por qué — reutilizando las tres condiciones de `Test-PuedeLeerTablaMaestra`,
que era código muerto desde `VEL-01` y vuelve a tener quien lo llame.

**Las dos mitades puras se escribieron en paralelo, con el contrato de en medio dictado por
escrito** — la lección de `VEL-02` del día anterior, aplicada a propósito esta vez. Y
`tests/DiarioUsnCostura.Tests.ps1` recorre las tres juntas seguidas: bytes → registros → cambios →
índice guardado → leído → actualizado, y exige que **6 MB menos 2 más 3 más 2 sean 9 MB al byte**.
Cada junta se rompió a propósito para comprobar que la costura lo nota.

**Lo que sigue sin ejecutarse**, y está escrito con esas palabras: `Get-DatosDiarioUsn` y
`Read-DiarioUsn`, que abren el volumen y le piden el diario con `DeviceIoControl`. Están donde estaba
`Read-TablaMaestra` en `VEL-01`: escritas contra la documentación del formato, sin un NTFS delante.
`tools/Banco-VEL02-Diario.ps1` se ejecuta como administrador, no toca nada, y dice si responden.

**Y dos cosas que rebajan la promesa del punto, y hay que decirlas.** Leer el diario exige abrir
`\\.\C:` en crudo, así que **el camino rápido es solo para administradores** — en el uso normal el
segundo análisis no va a ser más rápido. Y el diario no da rutas sino referencias de carpeta, y
**resolverlas a rutas es la pieza que falta**; qué forma tomar lo dice un número que solo el banco
puede dar.

De limpiar el terreno salió un huérfano: dos archivos de un intento anterior que definían **otra**
`ConvertTo-CambiosIndice` con otro contrato. Si las dos hubieran entrado en `Bootstrap`, habría
ganado la que cargase última, en silencio. Borrados.

### La ventana ya cabe en un portátil normal, y el diálogo también

`A11Y-02`. **El mínimo baja de 1020×620 a 880×460.** Un portátil corriente de 1366×768 con el
escalado de Windows al 150 % mide **910×512 puntos** —WPF trabaja en puntos, no en píxeles—, así que
la ventana no podía encogerse lo suficiente: se salía de la pantalla y el botón de eliminar quedaba
fuera, sin forma de alcanzarlo.

Hay invariante, y ata el número **por los dos lados**: no puede subir hasta no caber, y tampoco
bajar hasta volverse inútil. Arreglar esto poniendo 300×200 también «cabría».

**Bajarlo solo es seguro gracias a lo de ayer.** Las nueve rejillas que se pintaban unas encima de
otras al estrechar eran justo lo que habría convertido *«no cabe»* en *«cabe y no se entiende»*.

**Y apareció un agujero dentro de un arreglo anterior.** `A11Y-03` había puesto `MaxHeight="760"` en
el diálogo de confirmación para que sus botones no quedaran fuera de la pantalla, con un comentario
que decía *«es la altura útil de un portátil de 768 px»*. En ese mismo portátil al 150 % la pantalla
mide 512 puntos: **760 es más alto que el escritorio entero y el tope no topaba nada**. El arreglo de
`A11Y-03` no funcionaba precisamente en la máquina de la que habla `A11Y-02`.

El comentario acertaba en una cosa —el XAML no sabe cuánta pantalla hay— pero la conclusión era
otra: no había que elegir mejor el número fijo, había que no fijarlo. Ahora sale de
`Get-AlturaMaximaDialogo`, cálculo puro que se prueba sin abrir ninguna ventana, alimentado con
`SystemParameters.WorkArea`, que ya viene en puntos y ya descuenta la barra de tareas.

**Falta la otra mitad**, y está escrita como tal: la barra lateral sigue ocupando 228 puntos fijos,
que a 880 de ancho son la cuarta parte de la ventana. Plegarla pide verla en una pantalla escalada
de verdad.

### El botón llamaba «definitivo» a un borrado que iba a la papelera

El diálogo de confirmación enseñaba dos frases que se contradecían:

```
Destino de lo borrado      Papelera de reciclaje
[ botón ]                  Eliminar definitivamente
```

La primera se calculaba. La segunda estaba escrita a mano en `ConfirmDialog.xaml` y **no cambiaba
nunca**. Es la familia de `COR-01` —el programa afirmando algo que no es verdad— y empuja además en
la dirección equivocada: pintaba de irreversible el único camino que **sí** tiene red de seguridad,
que es justo el que el programa quiere que la gente use.

Las tres cadenas del destino —el nombre del destino, el rótulo del botón y la palabra que hay que
escribir para confirmar— salen ahora de **una sola función**, `Get-TextosDestinoBorrado`. No es que
hoy coincidan: es que no pueden dejar de coincidir. Con la papelera el botón dice *«Enviar a la
papelera»*; solo con el borrado permanente dice *«Eliminar definitivamente»*.

**Y arreglarlo destapó una tensión real entre dos invariantes.** Al quitar el rótulo fijo del XAML,
`A11Y-01` lo rechazó al instante: un botón sin texto se queda **mudo** para un lector de pantalla.
Las dos reglas tenían razón, así que la solución no era ceder en ninguna — el XAML conserva un
rótulo **deliberadamente neutro** (*«Eliminar lo marcado»*), cierto en los dos casos, que además
sirve de reserva si algún día esa línea no llega a ejecutarse. La prueba no exige que no haya
rótulo: exige que el rótulo **no hable de ser definitivo**.

Se vio mirando el diálogo en pantalla. Ninguna de las 2288 pruebas lo habría encontrado, porque
ninguna puede leer lo que dice un botón dibujado.

### Nueve rejillas fingían dos columnas con la alineación, y dos ya se solapaban

Se vio a simple vista en cuanto alguien abrió la ventana. En la barra de herramientas de Resultados,
*Marcar todo*, *Desmarcar todo* y *Ocultar lo ya eliminado* aparecían **superpuestos e ilegibles**; y
al estrechar la ventana, *«32 elementos marcados»* se pintaba encima de la casilla *Solo simular*.

La causa es la misma en los dos sitios y en otros siete: **un `Grid` sin columnas donde alguien pone
un hijo con `HorizontalAlignment="Right"`**. Eso finge dos columnas con la alineación, pero en un
`Grid` sin columnas **todos los hijos ocupan la misma celda**: funciona exactamente hasta que el
contenido crece, y entonces se pintan uno encima del otro. No se recortan, no se desplazan, no
avisan. La casilla de `USO-13` añadió unos 170 px a una fila que ya iba justa y la cruzó.

Corregidos los nueve —en `Resultados`, `Inicio`, `Ajustes`, `Registro` y el diálogo de
confirmación— con una columna `*` y una `Auto`: la `Auto` reserva lo que necesita **antes** de
repartir, y el solape deja de poder ocurrir. Donde el texto puede quedarse sin sitio, ahora acaba en
puntos suspensivos o se ajusta a la línea siguiente en vez de recortarse a media palabra.

**La invariante hizo falta dos veces, y la primera estuvo mal.** Se escribió exigiendo *dos grupos
horizontales* en el mismo `Grid`, que era el caso que se acababa de arreglar. Media hora después la
misma captura enseñaba el fallo en la barra de abajo, donde el grupo de la izquierda es un
`StackPanel` **vertical**: la prueba ni lo miraba. Estaba escrita sobre el ejemplo que tenía delante
en vez de sobre la regla — el error de la regla 8 del relevo, cometido el mismo día que se escribió
esa regla. La segunda versión pregunta lo que hay que preguntar: *¿hay algo alineado a la derecha en
un `Grid` que no declara columnas?*

Y una tercera cosa que salió de rebote: al añadir puntos suspensivos al diálogo de confirmación,
**`USO-08` lo rechazó**. Ese diálogo tiene prohibido recortar texto —`SECURITY.md` exige que los
comandos externos se vean enteros— y la invariante lo paró en el acto. Se cambió por ajuste de línea.

### La barra de Resultados se pintaba encima de sí misma

*Marcar todo*, *Desmarcar todo* y *Ocultar lo ya eliminado* aparecían **superpuestos e ilegibles**.
La barra de herramientas era un `Grid` **sin columnas** con dos grupos horizontales dentro, uno
alineado a la izquierda y otro a la derecha: en un `Grid` sin columnas los dos hijos ocupan la misma
celda, así que en cuanto la suma de sus anchos pasa del disponible **se pintan uno encima del otro**.
No se recortan ni se desplazan. La casilla de `USO-13` añadió unos 170 px a un grupo que ya iba justo
y los cruzó.

Ahora la columna derecha es `Auto` —reserva lo que necesitan sus botones antes de repartir— y el
grupo izquierdo es un `WrapPanel`, así que cuando no cabe la casilla baja a una segunda línea en vez
de recortarse.

**Lo que este fallo dice del proyecto es más interesante que el fallo.** Estaba escrito como
sospecha en `docs/PRUEBA-MANUAL.md` desde el 30 de agosto —*«a 1020 px de ancho, ¿se solapan los
filtros con los botones de la derecha?»*— y se confirmó a los dos días, en cuanto alguien abrió la
ventana y miró. Dos días de una pregunta ya formulada esperando a que alguien la mirase. Aquí no hay
WPF: ninguna de las 2288 pruebas puede medir un píxel. Lo que sí se puede es prohibir la
**estructura** que lo hace posible, y eso es la invariante nueva: ningún `Grid` puede llevar dos
grupos horizontales sin declarar columnas.

### `VEL-02` estaba muerto en Windows, y la suite de Linux no podía verlo

`src/Core/IndiceIncremental.ps1` comprobaba `$Valor -is [short]`. **`[short]` es un acelerador de
tipos que PowerShell no tiene hasta la versión 6**: en Windows PowerShell 5.1 —la versión con la que
arranca el programa— esa línea lanza *"Unable to find type [short]"* y se lleva por delante la
función entera. Todo el índice incremental estaba inservible en la única plataforma donde el programa
se ejecuta, con las pruebas en verde y el analizador a cero.

Se cuela porque un nombre de tipo dentro de un `-is` **solo se resuelve al ejecutar esa línea**: no
falla al cargar el archivo y el analizador no dice nada. Lo destapó la integración continua de 5.1,
con veintiuna pruebas en rojo de golpe. Hay ahora una invariante que barre `src/` entera buscando
aceleradores posteriores a la 5.1.

Y tirando de ese hilo aparecieron tres más de la misma familia — **cosas que en PowerShell 7 van y
en 5.1 no, sin decir nada**:

- **`Sort-Object Bytes` sobre un diccionario no ordena en 5.1, y no protesta.** Devuelve la lista
  tal cual. Como el índice guardado se lee a diccionarios —es lo que hace la carga doce veces más
  rápida—, en cuanto `VEL-02` se enganche, cuatro sitios habrían empezado a mostrar «los archivos más
  grandes» en el orden en que se leyeron: `Indice.ps1` en tres puntos y el mapa de árbol en
  `Mapa.ps1`, que además ya filtraba con una expresión y ordenaba sin ella. Los cuatro ordenan ahora
  con `{ [double]$_.Bytes }`, y hay una invariante que lo exige.
- **`Test-Path -LiteralPath $null` lanza en 5.1** —lo rechaza el enlazador de parámetros— mientras en
  7 solo escribe un error no terminante. Una sola entrada mal escrita en la lista de un módulo
  abortaba el recorrido entero y dejaba sin proponer todo lo que viniera detrás.
- **`Get-CarpetaConocida` devolvía `%USERPROFILE%\Downloads` sin expandir.** El registro guarda la
  entrada así, y `ExpandEnvironmentVariables` no falla con una variable que no existe: deja el
  `%...%` dentro. Una ruta con pinta de ruta que no existe en ningún sitio es peor que no contestar.

**Los suelos de cobertura suben por fin**: total a 65, `src/Core` a 87, `src/Modules` a 64 y
`src/Cli` a 88. Se subieron con las dos medidas delante —Linux 66,1 % y Windows 66,8 %— cogiendo el
menor de cada fila y dejando un punto de margen, que es la receta que quedó escrita el día que un
suelo puesto con una sola medida tumbó un trabajo.

### La deuda de pruebas, pagada entera: dos fallos vivos que llevaban meses escondidos

`tests\datos\deuda-de-pruebas.txt` nombraba **31 funciones que ninguna prueba tocaba**. Quedan 8, y
las 8 son WPF: necesitan una ventana de verdad y no se pueden cubrir aquí por mucho que se quiera.
La lista dejó de ser deuda que se pueda pagar escribiendo código; ahora es el límite de lo que una
prueba automática alcanza en este proyecto, y así está escrito en su cabecera.

Se escribieron **227 pruebas nuevas** en cinco archivos, y aparecieron dos fallos de verdad:

- **Las preferencias se perdían en silencio.** `Export-Preferencias` escribía con `Set-Content` sin
  `-ErrorAction Stop`. Ese fallo no es terminante, así que el `catch` de la propia función **no se
  disparaba nunca**: volvía sin decir nada y sin archivo. El usuario cerraba la ventana, la abría al
  día siguiente y se encontraba sus ajustes por defecto sin una sola línea que lo explicara. Ahora
  devuelve un booleano, y el cierre que la llama —el cierre de la ventana, el botón de restablecer y
  el reinicio como administrador— **avisa en el Registro** cuando no se ha podido guardar.
- **Y un sexto sitio igual, en el historial.** `Set-Content` sobre el archivo temporal, también sin
  `-ErrorAction Stop`: un disco lleno dejaba un temporal truncado que el `Move-Item` de la línea
  siguiente instalaba tan tranquilo encima del historial bueno. El JSON inválido resultante hace que
  `Get-Historial` devuelva vacío, o sea que se pierde el registro entero. La escritura atómica
  protegía contra el corte de luz pero no contra el disco lleno, que produce el mismo estropicio.

**Los dos estaban delante de una prueba en verde.** La invariante que persigue exactamente este
fallo —"un informe que no se puede escribir NO se anuncia como guardado"— nombraba `Report.ps1` y
`ReportEspacio.ps1` y exigía cuatro escrituras. Preguntaba *"¿lo hacen bien estos cuatro?"* en vez
de *"¿hay alguno mal?"*, así que era una lista de fallos pasados disfrazada de invariante. Ahora
barre **todo `src\`** y lleva una guarda de cordura: si el barrido no encuentra escrituras, es el
barrido lo que está roto. Verificado plantando una escritura mala en `src\UI` y otra en
`src\Modules`; las caza las dos. Es la regla 6 nueva de `docs\RELEVO.md`.

Otros dos arreglos menores, los dos de la misma familia —una función que revienta donde prometía
decir que no—: `Get-CarpetaConocida` llamaba a `Join-Path` con `$env:USERPROFILE` sin comprobar que
existiera, y `Test-CadenaSinEnlaces` —la que impide que un *junction* haga pasar por "dentro" lo que
está fuera— rechazaba la cadena vacía **lanzando** desde el enlazador de parámetros, de modo que su
propia guarda de "falla cerrado" era inalcanzable. Una función de seguridad que lanza obliga a
envolverla en un `try`, y un `try` es justo donde un rechazo se convierte por descuido en un permiso.

Cobertura del **64,9 % al 66,1 %**; `src/Core`, del 86,4 % al 88,6 %. 2288 pruebas.

Los suelos de cobertura **no se han subido**, y no es un olvido: se miden en dos sistemas y el suelo
es el del peor. De Windows solo hay la medida del 31 de agosto, o sea de antes de estas pruebas.
Subirlos con la medida de Linux es exactamente lo que ya tumbó un trabajo una vez. Cuando la
integración continua publique la medida de Windows, se cogen el menor de los dos y un punto de
margen; si confirma números parecidos, el total va a 65 y `Core` a 87.

### Una sola pasada lo prueba todo, y dice qué no está probado

- **`tools\Probar.ps1`**: un comando ejecuta la suite, el analizador y el suelo de cobertura, y deja
  el informe en `pruebas\ultima-pasada.txt` con una copia fechada al lado. Antes eso era un bloque
  de PowerShell que había que **pegar a mano** desde el relevo, y un ritual copiado a mano se rompe
  en silencio: basta olvidar la segunda mitad para que el analizador deje de mirarse durante
  semanas. La integración continua ahora llama al mismo guion en vez de a una copia suya.
- **El modo consola pasó del 0 % al 87 % de cobertura.** `src/Cli` son 330 líneas de PowerShell
  corriente —el camino que la documentación recomienda para la primera ejecución sin riesgo, y el
  que usaría una tarea programada— que se podían haber ejecutado desde una prueba desde el primer
  día, y nadie lo hizo nunca. En total, del 55,7 % al 60,7 %.
- **Un suelo de cobertura por carpeta**, en `tools\Cobertura.ps1`, que solo puede subir. Un único
  número total se sube escribiendo pruebas fáciles de lo que ya estaba bien mientras lo difícil se
  pudre.
- **`tests\datos\deuda-de-pruebas.txt`**: las funciones de `src\` que ninguna prueba nombra. La
  lista solo puede encoger — la suite falla si aparece una función sin probar que no esté ahí, **y
  también si un nombre de ahí ya está probado o ya no existe**. Sin esa segunda regla sería un
  cajón donde meter lo incómodo.

  Aviso que va escrito en los tres sitios: **cobertura no es lo mismo que probado.** Que una línea
  se haya ejecutado no dice que haga lo correcto. Los dos fallos de más abajo vivían en líneas
  perfectamente cubiertas.

### `VEL-02`: la mitad que se puede escribir sin Windows, hecha y probada

`src/Core/IndicePersistente.ps1` guarda y lee el índice en binario con escritura atómica.
`src/Core/IndiceIncremental.ps1` decide si un índice guardado se puede creer —**diez motivos de
rechazo, cada uno con su frase**: otro disco que heredó la letra, el diario recreado, el diario que
dio la vuelta, el cuerpo truncado, caducidad…— y le aplica los cambios propagando los totales.

**Lo que enseñó escribir las dos mitades en paralelo:** las dos estaban en verde —55 y 82 pruebas—
**el día que no encajaban**. Coincidían en la cabecera, que estaba acordada, y discrepaban en dos
cosas que nadie había acordado. El síntoma era que se descartaban **todas** las bajas. Ninguna
prueba de una sola mitad podía verlo, y de ahí `tests/IndiceCostura.Tests.ps1`: recorre el camino
entero y exige que una baja de 2 MB deje el total en 4 MB. De paso apareció un **rechazo mudo** —
*"no te fíes"* con el motivo vacío—, que es indistinguible de un fallo del programa.

Falta la mitad de Windows: leer el diario de cambios. Hasta entonces el programa se comporta igual
que antes.

### `VIS-04`: los discos externos y las llaves USB ya se analizan, y nunca se borran en ellos

Hasta hoy un disco externo o una llave USB **no se analizaban en absoluto**: el descubrimiento
filtraba por `DriveType Fixed`. Ahora entran en el mapa, en la vista de archivos y en el informe, y
**no pueden producir ni un candidato borrable** — una extraíble se puede desconectar en mitad de una
operación, y eso convierte un borrado en un error a medias sobre un disco que ya no está.

Son **cuatro cortes**, y cada uno tapa un agujero del otro: el descubrimiento —`Get-UnidadesFijas`
pasó a llamarse **`Get-UnidadesAnalizables`**, porque el nombre había empezado a mentir—, una regla
nueva en el embudo, un segundo corte en el motor de borrado que mira la ruta directamente (el que
salva el caso de un disco enchufado **después** de arrancar), y el módulo de la papelera, que la
regla del embudo **no puede proteger** porque su candidato apunta a `C:` aunque la lista lleve dentro
una llave USB.

**Lo que destapó la verificación por mutación merece leerse:** de las ocho mutaciones, **seis no las
cazaba nadie**. Seis pruebas que pasaban mirando otra cosa. La peor: quitarle al motor la
comparación con `'desconocida'` hacía que el programa **dejara de borrar absolutamente todo en
silencio** en cualquier equipo donde la clasificación fallara — y la prueba seguía en verde porque
comprobaba que el motivo *"no mencionara las extraíbles"* en vez de exigir que estuviera vacío.

### `VIS-05` cerrado: los dos módulos que faltaban

`55-Duplicados` pregunta el tamaño en disco **al final y solo por los candidatos**, igual que ya
hacía con los enlaces duros. Y `45-AccesosRotos` **no lo hace, y es una decisión escrita**: un `.lnk`
son dos kilobytes, por debajo del clúster donde NTFS empieza a comprimir.

### `VEL-02` medido: guardar el índice SÍ compensa, y es la forma de ganarle en velocidad

Descartado `VEL-01`, quedaba el otro camino: **no volver a escanear**. WizTree vuelve a recorrer el
disco entero cada vez que se abre; si Cachivache guarda su índice y al abrirse lee **solo lo que ha
cambiado**, la comparación se da la vuelta.

**El punto de equilibrio está en ~30.000 archivos tocados** entre una sesión y la siguiente. Por
debajo compensa leer el diario de cambios de NTFS; por encima, recorrer de nuevo. Un orden de
magnitud por encima de lo que haría inservible la idea. Y esta vez el coste por elemento del
intérprete —lo que hundió a `VEL-01`— se paga sobre decenas de miles de registros, no sobre un
millón.

Tres cosas que solo se supieron midiendo: el índice **tiene que ir en binario** (`ConvertTo-Json`
con un millón de entradas **no termina**: el proceso muere por memoria sin llegar a lanzar); hay que
guardar **tres tablas y no una**, porque volver a sumar las carpetas cuesta más que el recorrido que
se quería evitar; y falta medir en Windows lo único que no se puede medir aquí, que es leer el
diario. Todo en [`docs/VEL-02-MEDICION.md`](docs/VEL-02-MEDICION.md), incluida la decisión que
protege al programa: **el índice pinta el mapa, nunca decide qué se borra**, y ante un índice dudoso
se recorre de nuevo sin reparación parcial.

### `VIS-05` enganchado: deja de prometer espacio que no va a liberar

En una carpeta comprimida con NTFS, el programa prometía liberar el **tamaño lógico** y liberaba
bastante menos. Ahora el recorrido lee el bit de comprimido —que viene gratis en la enumeración— y
**solo entonces** pregunta lo que ocupa de verdad; `New-Candidato` lleva un `TamanoEnDisco`
anulable y `Bytes` **nace ya siendo la promesa**, así que los ocho sitios que suman bytes heredan la
cifra correcta y **solo hay un sitio que decide**. Cuatro módulos lo piden: archivos grandes,
descargas, temporales y WSL/Docker.

El detalle que más costó y que la hoja de ruta ya avisaba: `TamanoEnDisco` es **anulable de verdad**.
Si naciera a `0` en vez de a `$null` se perdería la diferencia entre *"no ocupa nada"* y *"no lo
sé"*, que es justo lo que este punto viene a establecer. Hay una mutación que lo comprueba.

### `VIS-02`: la consola dejó de tener su propia versión peor

`Show-InformeEspacio` filtraba y ordenaba por su cuenta. Ahora usa la capa de consulta, y el usuario
ve tres cosas que antes no: el resumen **siempre** —faltaba justo *"y queda 1 más sin mostrar"*
cuando había filtro, que es lo que hacía creer que el análisis se dejó cosas—, buscar `foto[1].jpg`
**encuentra `foto[1].jpg`** en vez de `foto1.jpg`, y un `-Orden` cuya cabecera dice el orden que de
verdad se aplicó.

### `VEL-01` medido y descartado: el diferenciador técnico no lo era

`VEL-01` —leer la tabla maestra de NTFS— llevaba en la hoja de ruta desde el principio marcado como
**«el diferenciador técnico del proyecto»**, y nadie había comprobado el único supuesto del que
dependía entero. Se ha medido:

| Sobre un disco de 1.000.000 de archivos | |
|---|---|
| El recorrido de hoy (`New-IndiceDisco`) | **5 s** |
| El camino «rápido» de la tabla maestra, completo | **≈ 188 s** |

**Pierde por un factor de nueve**, y lo incómodo es dónde está la lentitud: no en el parseo. El
80 % del coste es *llamar a una función de PowerShell* —12 µs cada una— y un millón de llamadas son
doce segundos hagan lo que hagan por dentro. El mismo bucle en C# tarda prácticamente cero: **la
ventaja de WizTree está en el lenguaje, no en el algoritmo**, y el algoritmo es lo único copiable.

Consecuencia directa: **superar a WizTree en TODO ya no es posible**, porque una de sus funciones es
ser muy rápido. Se le gana en superficie y se le pierde en velocidad, y eso está ahora escrito en la
hoja de ruta en lugar de la promesa anterior. Medirlo costó una tarde; construirlo habría costado
meses para llegar a un programa más lento. Todo en
[`docs/VEL-01-MEDICION.md`](docs/VEL-01-MEDICION.md).

### Tres mitades de núcleo, escritas y probadas

- **`VIS-05` compresión NTFS** (`src/Core/Compresion.ps1`): hoy, en una carpeta comprimida, el
  programa **promete liberar más de lo que va a liberar**. `Get-EspacioRecuperable` decide cuánto se
  puede prometer y ante la duda nunca promete de más.
- **`VIS-04` unidades extraíbles** (`src/Core/Extraibles.ps1`): la regla del punto —*entra en el
  mapa y en el informe, y NUNCA produce un candidato borrable*— con una invariante que saca las
  clases de unidad del AST, así que añadir una sin decidir su respuesta hace fallar la suite.
- **`VIS-02` vista de archivos** (`src/Core/VistaArchivos.ps1`): búsqueda por comodines **sin
  `-like`**, que interpreta los corchetes y hacía imposible encontrar un `foto[1].jpg`; orden por
  bytes y no por el texto; y lo que sale es informativo **por construcción**, copiado a un objeto de
  seis campos para que ninguna fila pueda llegar a la ventana pareciendo un candidato.

Las tres están **sin enganchar** todavía: hasta que lo estén, el programa se comporta igual que
antes.

### El ejecutor de pruebas podía decir "todo en verde" con un archivo roto

Si un `.Tests.ps1` revienta al cargarse —un error de sintaxis, un `BeforeAll` que lanza—, Pester lo
apunta como **contenedor** roto y `FailedCount` sigue a cero. `tools\Probar.ps1` miraba solo ese
contador, así que la suite entera de ese archivo desaparecía y el resumen decía **TODO EN VERDE**
con los contadores de los demás. Comprobado: con un archivo mal cerrado a propósito, ahora imprime
*1871 bien, 0 mal* y aun así se pone en rojo nombrando el archivo. Es el error de siempre —"no he
medido nada" pareciéndose a "todo bien"— y esta vez estaba en el guion escrito para no fiarse.

### El modo consola no podía borrar nada, y llevaba así desde `[ARQ-01]`

`Cachivache.ps1 -Consola -Ejecutar` **moría en el momento de borrar**, con
*"El término `Invoke-VaciarColaRegistro` no se reconoce"*. El análisis funcionaba, el informe se
guardaba, y al llegar al primer elemento se caía.

La causa: el aviso de avance del borrado se pasaba con `.GetNewClosure()`, que además de copiar las
variables ejecuta el bloque en un **módulo dinámico**, donde las funciones se resuelven contra ese
módulo y contra **global**. `Cachivache.ps1` carga el núcleo en ámbito de **script**, así que desde
ahí dentro no se veía ni una función del programa.

**Por qué no lo vio nadie**, que es la parte que importa:

- La comprobación de arranque de la CI ejecuta el modo consola **sin `-Ejecutar`**, así que nunca
  pisaba esa línea.
- Las pruebas del modo consola sí la pisaban, y al escribirlas **se tropezaron con este mismo
  error**. Se dio por hecho que era una rareza de Pester y se rodeó cargando el núcleo como módulo,
  que hace globales las funciones y hace desaparecer el síntoma. Se rodeó el síntoma de un fallo de
  verdad.

Lo destapó el banco de pruebas de la integración continua, que es el único sitio donde se ejecuta
una limpieza real. Las pruebas cargan ahora **igual que `Cachivache.ps1`**, y volver a poner el
cierre hace fallar tres de ellas con el mensaje exacto. La lección está en la regla 4 de
`docs/RELEVO.md`: **si el arnés de pruebas necesita un apaño que el programa no tiene, el apaño es
el síntoma.**

### La suite nunca había estado verde en Windows, y nadie lo sabía

Tres ejecuciones de la integración continua, tres rojos. El proyecto se había validado siempre
contra Linux con PowerShell 7; el programa corre en Windows con **5.1**. Trece pruebas fallaban
allí, y **ninguna era un fallo del programa**: las trece eran pruebas mal escritas para la versión
en la que el programa vive de verdad.

- **`-Include` se ignora con `-LiteralPath` en 5.1.** La invariante que exige BOM a los `.ps1`
  estaba recorriendo el repositorio entero y exigiéndoselo a `.md`, `.yml` y `.gitignore`.
- **`$IsWindows` no existe en 5.1**, así que vale `$null` y `if (-not $IsWindows)` es **verdadero
  en Windows**: una rama escrita para no ejecutarse allí se ejecutaba justo allí.
- **`.Count` sobre una lista de un elemento vale `$null` en 5.1** y 1 en 7. Cuatro pruebas del
  embudo fallaban por cómo contaban, no por lo que comprobaban.
- **`[void]$x.A().B() | Out-Null` revienta en 5.1**: cinturón y tirantes a la vez.
- **`Remove-Item` sobre un enlace simbólico a una carpeta lanza `NullReferenceException` en 5.1**, y
  `-ErrorAction SilentlyContinue` no lo tapa.
- **Los cebos de duplicados vivían en `%TEMP%`**, que en Windows es `AppData\Local\Temp`, y el
  módulo descarta `\AppData\` a propósito: eran invisibles para el programa. Mismo fallo que
  `[VAL-03]` encontró en el banco, con otro disfraz.
- **Una prueba comprobaba el escapado del SVG con una carpeta llamada `a <b> & "c"`**, con
  caracteres **prohibidos en Windows**. Verde por un caso imposible en el único sistema donde el
  programa corre.

Las cinco primeras están ahora en la lista de trampas de `docs/RELEVO.md`, que es donde se miran
antes de escribir una prueba.

### Corregido en esta tanda

- **Un informe que no se podía guardar se anunciaba como guardado.** `Set-Content` y `Export-Csv`
  sobre una carpeta que no existe dan un error **no terminante**: la función sigue y no lanza. Los
  cuatro exportadores iban dentro de un `try/catch` de quien llama, así que el `catch` no se
  disparaba nunca y la consola escribía *"Informe guardado en ..."* sobre un archivo inexistente —
  y anotaba esa ruta en el historial, con lo que la ventana ofrecía después una tarjeta para abrir
  un informe que no se escribió jamás. Misma familia que `[COR-01]`: el programa afirmando haber
  hecho algo que no hizo. **Lo encontró la primera prueba que se escribió para el modo consola.**

- **La tabla de resultados te devolvía al principio cada vez que terminaba un módulo.** Con quince
  mil filas y un análisis de dos minutos, leer la fila 200 era imposible: se reengancha la colección
  por módulo —correcto, y por rendimiento— y WPF regenera la lista entera, así que el desplazamiento
  vuelve arriba y la selección se pierde. Ahora se guarda el sitio antes y se devuelve después.
  Salieron dos cosas que el plan no decía: **el cambio de tema hacía el mismo salto** por el mismo
  motivo, y una selección escondida por el filtro **no se restaura** —devolverla dejaría a *Abrir la
  ubicación* actuando sobre una fila que nadie ve—. `[USO-10]`

- **`-Quitar` no podía desmontar el banco de pruebas.** Recorría con `Get-ChildItem -Recurse`, que en
  PowerShell 5.1 se para a los 260 caracteres y bajo `-ErrorAction SilentlyContinue` no dice nada:
  las carpetas del cebo de ruta larga no se veían, no se borraban, y después reventaba al intentar
  borrar una carpeta que creía vacía. `[VAL-03]`

- **`.editorconfig` decía `crlf` y el repositorio entero está en `lf`.** Se contradecían, y ganaba el
  disco: un editor que obedeciera al archivo habría tumbado la prueba que compara el XAML montado
  byte a byte, con un error que no habla de finales de línea.
- **Dos pruebas que afirmaban más de lo que comprobaban.** Una contaba 1400 caracteres desde un punto
  del archivo y decía «dentro del manejador» cuando en realidad medía «cerca» — y ya había empezado a
  mandar sobre el código, obligando a colocar un cierre donde no tocaba para que cayera dentro de la
  ventana. Otra fijaba una línea de **texto** en vez de un comportamiento, y por eso descartó la forma
  más simple de escribir las reglas del embudo en `[ARQ-02]`. Las dos reescritas: la primera por AST,
  la segunda ejecutando el embudo de verdad.

- **Una limpieza detenida no se anotaba en el historial.** El `ValidateSet` admitía `analisis` y
  `limpieza`, la ventana llevaba desde `[CNF-04]` llamando con `limpieza-interrumpida`, la llamada
  lanzaba, el `catch` de al lado se lo tragaba y **no se guardaba nada**. La parte de `[CNF-04]` que
  promete «una limpieza detenida se anota como tal» no funcionaba por el camino normal del programa.
- **«hace 1 meses»**, durante un mes de cada año, en cualquier sitio que dijera la antigüedad de
  algo. Mismo descuido que el «1 elementos» de las cabeceras de grupo.
- **La integración continua estaba rota desde que se escribió, y no se sabía.** `ci.yml` ponía
  `shell: ${{ matrix.shell }}` en dos pasos, y la clave `shell:` de un paso es de los pocos sitios
  de un flujo donde el contexto `matrix` **no** está disponible. Eso no da un shell equivocado:
  invalida el archivo entero, y GitHub no ejecuta nada. Se descubrió en el primer push del
  proyecto, porque hasta entonces no había repositorio donde ejecutarlo — el único archivo que
  nadie había verificado nunca era justo el que existe para verificar todo lo demás. El shell pasa
  a `jobs.<id>.defaults.run.shell`, que sí admite el contexto, y hay dos invariantes: una prohíbe
  la expresión en un paso, y otra exige que el `defaults` esté — sin ella, quitar lo primero y
  olvidar lo segundo dejaría las dos ramas de la matriz corriendo `pwsh` y PowerShell 5.1 sin
  probarse jamás, todo en verde.
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
