# `VEL-02` · ¿Compensa guardar el índice y actualizarlo con el diario de cambios?

**Medido el 1 de septiembre de 2026.** Como [`VEL-01`](VEL-01-MEDICION.md), esto no describe una
función: describe una **medición**. Y por el mismo motivo — porque el punto entero depende de un
supuesto que nadie había comprobado.

La idea es esta. WizTree vuelve a escanear el disco cada vez que se abre y tarda un segundo con un
millón de archivos porque está escrito en C++. Cachivache tarda cinco. `VEL-01` ya midió que
**escanear más rápido no es un camino**: en PowerShell se paga un coste fijo por elemento que WizTree
no paga, y no hay forma de bajarlo. Queda el otro camino: **no volver a escanear**. Guardar el índice
en disco y, al abrir otra vez, leer solo lo que ha cambiado desde la última vez. NTFS lleva un diario
de cambios —el *USN Journal*— exactamente para eso.

---

## La respuesta, antes que nada

> ## ⛔ ESTA RESPUESTA ERA FALSA. Corregida el 5 de septiembre de 2026.
>
> El punto 3 de la letra pequeña de aquí abajo decía: *«el tercio de la medición que decide el punto
> no se ha ejecutado nunca… si esa llamada resulta ser cara, el número de arriba baja»*. **Se ejecutó
> en un Windows real, y no bajó: se desplomó.**
>
> | | supuesto el 1 de septiembre | medido el 5 de septiembre |
> |---|---|---|
> | Coste por registro | 33,4 µs | **12.800 µs** (74–82 reg/s en 5.1) |
> | Punto de equilibrio | 125.000 registros | **≈ 330 registros** |
>
> La vara de medir del encargo era: *«si compensa mientras cambien menos de 50.000 archivos, la idea
> es buena; si es menos de 500, es inservible»*. **330 cae por debajo de 500. Inservible, según el
> criterio que se escribió antes de conocer el resultado.**
>
> Y hay un segundo hallazgo que lo cierra por otro lado, independiente de la velocidad: **el diario
> solo conserva entre 10 y 80 minutos de historia** en esa máquina. Un limpiador de disco se usa
> cada semanas. Ver la *Tercera parte*, al final.
>
> **Todo lo que sigue se conserva sin tocar.** Es lo que se creía el 1 de septiembre, y el valor de
> este documento está justamente en poder comparar las dos cosas.

**Compensa, y por un margen amplio: el punto de equilibrio está en unos 125.000 registros del
diario, que son del orden de 30.000 archivos tocados.** Por debajo de eso sale más barato leer el
diario; por encima, volver a recorrer el disco.

| Sobre un disco de 1.000.000 de archivos | |
|---|---|
| Volver a recorrerlo (`New-IndiceDisco`, medido y extrapolado) | **5,7 s** |
| Cargar el índice guardado en formato binario | **1,0 s** |
| Margen que queda para el camino incremental | **4,2 s** |
| Coste por registro del diario (parsear + resolver ruta + medir + aplicar) | **33,4 µs** |
| **PUNTO DE EQUILIBRIO** | **≈ 125.000 registros ≈ 30.000 archivos** |

Contra la vara de medir del encargo —*«si compensa mientras cambien menos de 50.000 archivos, la
idea es buena; si es menos de 500, es inservible»*— esto cae claramente del lado bueno. Un día
normal de uso no mueve treinta mil archivos.

**Pero el veredicto no es «adelante» a secas, y la letra pequeña importa tanto como el número:**

1. **Con `ConvertTo-Json` no compensa nunca.** No es que sea lento: es que con un millón de entradas
   **no termina**. Ver el apartado del formato.
2. **Hay que guardar también la tabla de carpetas.** Si solo se guardan los archivos, al cargar hay
   que volver a sumar el millón de entradas, y eso cuesta **6 s** — más que recorrer el disco
   entero. La carga barata deja de serlo.
3. **El tercio de la medición que decide el punto no se ha ejecutado nunca.** Leer el diario de
   verdad es `DeviceIoControl` con `FSCTL_READ_USN_JOURNAL`, que fuera de Windows no existe. Aquí se
   ha medido el **parseo** de registros sintéticos, no la lectura. Si esa llamada resulta ser cara,
   el número de arriba baja. Es la primera comprobación que hay que hacer en Windows.

---

## Cómo se ha medido

Un solo banco, [`tools/Banco-VEL02.ps1`](../tools/Banco-VEL02.ps1), con cuatro bloques. Todo en este
entorno (Linux, PowerShell 7.4.6, 2 núcleos, 3,9 GB de memoria), cada medida repetida varias veces
quedándose con **la mejor pasada**, por lo mismo que en `VEL-01`: la pasada mala mide al vecino del
contenedor.

```bash
~/pwsh/pwsh -NoProfile -File tools/Banco-VEL02.ps1
```

El banco crea archivos **solo dentro de una carpeta propia** en el temporal del sistema, y **no borra
nada**: sobrescribe sus propios archivos, que tienen nombre fijo, y al terminar dice dónde han
quedado. Se puede ejecutar un bloque suelto con `-Bloque Persistencia|Aplicar|Usn|Recorrido`, que es
como se ha ejecutado aquí, porque la pasada completa no cabe en el tiempo que aguanta este entorno.

**Los cuatro bloques:**

1. **El recorrido**, que es la línea base. 20.000 archivos de verdad en disco, recorridos con la
   función del programa. Se mide en la misma sesión que el resto en vez de copiar el número de
   `VEL-01`, porque para que la comparación valga los dos lados tienen que haber corrido en la misma
   máquina el mismo día.
2. **La persistencia.** Índices sintéticos de 10.000 / 100.000 / 1.000.000 de entradas con la forma
   exacta que devuelve `New-IndiceDisco` —`Ruta`, `Nombre`, `Carpeta`, `Extension`, `Bytes`,
   `Ultimo`—, guardados y cargados en cuatro formatos.
3. **Aplicar los cambios.** Un índice de un millón de archivos en 20.823 carpetas, y D cambios
   —altas, bajas y modificaciones a partes iguales— aplicados y propagados.
4. **El diario.** 64 registros `USN_RECORD_V2` construidos byte a byte, con su cabecera de 60 bytes
   y su relleno a múltiplo de ocho, parseados N veces. Igual que `VEL-01` hizo con los registros de
   la tabla maestra. **Antes de medir, el banco comprueba que el registro de muestra se parsea
   bien y lanza si no**: medir la velocidad a la que se obtiene una respuesta equivocada no dice
   nada.

**Y se comprueba que la relación es lineal antes de extrapolar**, que fue la regla que hizo
defendible el número de `VEL-01`:

| | mitad del árbol | árbol entero |
|---|---|---|
| Recorrido, µs por archivo | 1,87 | **1,99** |

| | 50.000 | 100.000 | 200.000 |
|---|---|---|---|
| Parseo USN, µs por registro | 17,91 | **17,46** | **18,20** |
| Aplicar cambios, µs por cambio (D = 10.000 / 100.000) | — | 10,33 | **11,70** |

(Las columnas pequeñas llevan dentro el calentamiento del intérprete: 25.000 registros dan 33,7 µs
y 100 cambios dan 19,3 µs. Por eso se extrapola desde las grandes.)

---

## 1. Guardar y cargar el índice

Este bloque va primero porque **puede matar la idea entera**: si cargar el índice cuesta más que los
5,7 s del recorrido completo, no hay camino incremental que valga.

Mejor pasada de cada medida. El tamaño es el del archivo en disco.

| Formato | 10.000 · guardar / cargar | 100.000 · guardar / cargar | 1.000.000 · guardar / cargar | 1.000.000 en disco |
|---|---|---|---|---|
| **JSON** `ConvertTo-Json` | 0,08 / 0,15 s | 0,53 / 0,95 s | **no termina** | — (20,6 MB a 100.000) |
| **CSV** `Export-Csv` | 0,07 / 0,09 s | 0,25 / 0,46 s | 4,09 / **6,25 s** | 142,3 MB |
| **TSV** → diccionario | 0,02 / 0,02 s | 0,16 / 0,12 s | 4,55 / **1,75 s** | 74,9 MB |
| **TSV** → `pscustomobject` | 0,02 / 0,09 s | 0,16 / 0,69 s | 4,55 / **12,38 s** | 74,9 MB |
| **Binario** `BinaryWriter` → diccionario | 0,02 / 0,01 s | 0,13 / 0,08 s | **3,27 / 1,04 s** | 65,6 MB |

**Gana el binario, y no por poco.** Cargar un millón de entradas:

| | | contra el binario |
|---|---|---|
| Binario → diccionario | **1,04 s** | — |
| TSV → diccionario | 1,75 s | 1,7 veces más |
| CSV `Import-Csv` | 6,25 s | **6 veces más** |
| TSV → `pscustomobject` | 12,38 s | 12 veces más |
| JSON `ConvertFrom-Json` | — | **no termina** |

### Lo de `ConvertTo-Json`, que era la sospecha y se confirma

A 100.000 entradas JSON funciona y es el más lento de los cuatro. A un millón **el proceso muere**.
Con la forma real de las entradas —los seis campos de `New-IndiceDisco`— `ConvertTo-Json` se lleva
por delante el proceso entero sin llegar a lanzar una excepción: lo mata el sistema por memoria, así
que no hay ni `catch` que valga. En una prueba aparte con entradas más ligeras, de solo tres campos,
sí llegó a terminar: **20,24 s** para producir una cadena de 104 MB, y entonces murió
`ConvertFrom-Json`.

Y aunque hubiera memoria de sobra, los números de 100.000 ya lo descartan: extrapolados dan **5,3 s
de guardado y 9,5 s de carga**, los dos por encima del recorrido completo que se pretendía evitar.

**Es la tercera vez que `ConvertTo-Json` da problemas en este proyecto y la primera vez que se sabe
cuánto cuesta.** Aquí no es un ajuste de rendimiento: es la diferencia entre que el punto exista y
que no exista.

### Dos cosas más que salieron de este bloque

**No hay que cargar el índice como objetos.** El mismo archivo TSV leído a un diccionario cuesta
1,75 s y leído a `pscustomobject` cuesta 12,38 s. Es el hallazgo de `VEL-01` otra vez, desde el otro
lado: componer un millón de objetos de PowerShell cuesta segundos por sí solo. El índice no necesita
objetos, necesita poder contestar *«¿cuánto medía este archivo?»*, y para eso un
`Dictionary[string, object]` sobra.

Se ve también en la fila de arriba de la tabla: **construir en memoria la lista de un millón de
entradas cuesta 12,2 s y 1,6 GB.** Ese objeto no debe existir nunca en el camino de arranque.

**Y una trampa de método que casi falsea la medición.** En la primera versión del banco las cargas
iban intercaladas entre las escrituras, con la lista de 1,6 GB todavía viva al lado. Así el CSV de
un millón daba **10,92 s**; soltando la lista antes de cronometrar, **6,25 s**. Se estaba midiendo la
presión sobre el recolector de basura, no el formato. Al abrir el programa de verdad la memoria está
vacía, así que ahora el banco guarda todo primero, suelta la lista, y solo entonces mide las cargas.

---

## 2. Aplicar los cambios al índice

Índice de 1.000.000 de archivos repartidos en 20.823 carpetas de tres niveles. Mejor de tres.

| | |
|---|---|
| Propagar los totales **desde la tabla de archivos** (recorriendo el millón) | **6,00 s** |
| Propagar los totales **solo sobre la tabla de carpetas** (20.823 entradas) | **0,03 s** |

| D (cambios) | | µs por cambio |
|---|---|---|
| 100 | 0,00 s | 19,30 |
| 1.000 | 0,01 s | 10,57 |
| 10.000 | 0,10 s | 10,33 |
| 100.000 | **1,17 s** | **11,70** |

Aplicar un cambio cuesta **unos 12 µs**: buscar la entrada, cambiarla o quitarla, y subir la
diferencia por la cadena de carpetas hasta la raíz. Es barato y es lineal.

**Pero la línea que decide algo es la primera.** Volver a sumar las carpetas recorriendo el millón de
archivos cuesta **6 segundos**, más que recorrer el disco entero. Es decir: **si el índice guardado
contiene solo los archivos, la carga rápida no sirve de nada**, porque detrás viene una propagación
que cuesta más que lo que se quería ahorrar.

La conclusión de diseño es directa y hay que dejarla escrita: **se guardan las dos tablas, la de
archivos y la de carpetas.** La de carpetas son 20.823 entradas —nada— y con ella la propagación
tras aplicar los cambios es incremental, no completa.

---

## 3. El diario de cambios

**Aviso, y va antes que los números: esta parte NO se ha ejecutado nunca.** Leer el diario de verdad
es abrir `\\.\C:` con permisos de administrador y llamar a `DeviceIoControl` con
`FSCTL_READ_USN_JOURNAL`. Eso solo existe en Windows y solo sobre NTFS. Lo que hay medido aquí es el
**parseo** de registros `USN_RECORD_V2` construidos a mano, byte a byte, exactamente igual que
`VEL-01` midió los registros de la tabla maestra.

Mejor de tres, sobre registros de 112 bytes:

| N | escrito como función | escrito en línea |
|---|---|---|
| 25.000 | 33,69 µs | 8,69 µs |
| 50.000 | 17,91 µs | 6,78 µs |
| 100.000 | **17,46 µs** | 6,80 µs |
| 200.000 | **18,20 µs** | **7,83 µs** |

| | |
|---|---|
| Resolver la ruta desde la referencia del padre | **1,71 µs** |
| Preguntar al disco el tamaño de un archivo por su ruta | **1,80 µs** |

**Se confirma el hallazgo de `VEL-01`, en otro contexto y con otro formato de registro:** el mismo
trabajo escrito dentro de una función cuesta 18,2 µs y escrito en línea 7,8 µs. Diez microsegundos
por llamada, igual que allí. Aquí se usa el número de la función, no el de en línea, porque el
programa lo escribiría como función — es la forma de trabajar del proyecto, y medir la versión que
nunca se va a escribir sería hacerse trampas.

### Dos cosas que el registro USN no trae, y hay que pagarlas aparte

Esto es lo mismo que hundió a `VEL-01` con la tabla maestra, y conviene verlo antes de celebrar
nada:

- **No trae la ruta.** Trae el nombre del archivo y la *referencia* de su carpeta padre. Hay que
  resolverla. La buena noticia es que aquí sale barato —**1,71 µs**, una búsqueda en diccionario—
  y no los 113 µs de `VEL-01`, porque no hay que subir de padre en padre reconstruyendo el árbol
  entero: solo hacen falta las carpetas, son 20.823, y el índice guardado las trae ya hechas.
  **Eso obliga a guardar una tercera tabla: la de referencia de carpeta a ruta.**
- **No trae el tamaño.** El diario dice *qué* cambió, no *cuánto ocupa ahora*. Por cada archivo
  tocado hay que ir al disco a preguntarlo: **1,80 µs aquí**, y ver el apartado de lo que esta
  medición no puede saber, porque este número es de los que peor viajan a Windows.

---

## El punto de equilibrio, con la cuenta a la vista

La cuenta está escrita como función pura en el banco (`Get-PuntoDeEquilibrio`) para que se pueda
discutir sin volver a medir nada:

```
incremental = arrancar la interoperabilidad + cargar el índice + D × (coste por registro)
completo    = volver a recorrer el disco
```

**Guardar el índice al final no entra en ninguno de los dos lados**, porque los dos lo pagan igual:
el camino incremental tiene que reescribir el archivo y el completo también.

| | |
|---|---|
| Recorrer el disco entero, 1.000.000 de archivos | **5,72 s** |
| − cargar la tabla de archivos (binario) | −1,04 s |
| − cargar las tablas de carpetas y de referencias | −0,05 s |
| − compilar la interoperabilidad con `Add-Type` (número de `VEL-01`) | −0,44 s |
| **Margen** | **4,19 s** |

| Coste por registro del diario | |
|---|---|
| Parsearlo | 18,20 µs |
| Resolver su ruta | 1,71 µs |
| Preguntar su tamaño al disco | 1,80 µs |
| Aplicarlo al índice y propagar | 11,70 µs |
| **Total** | **33,41 µs** |

> **4,19 s ÷ 33,41 µs = 125.400 registros del diario.**
>
> A cuatro registros por archivo tocado —un solo guardado produce varios: `DATA_EXTEND`,
> `DATA_OVERWRITE`, `CLOSE`…— salen **unos 31.000 archivos cambiados**.

### El mismo número, con el supuesto más desfavorable

Los 5,72 s son los de `New-IndiceDisco`, la función que el programa tiene hoy. Pero un recorrido
escrito solo para esto —enumerar, preguntar el tamaño, meterlo en un diccionario, sin componer un
objeto por carpeta— se midió también, y cuesta **2,5 s por millón**. Si `VEL-02` se compara contra
*ese* recorrido en vez de contra el actual:

| | margen | registros | archivos |
|---|---|---|---|
| Contra `New-IndiceDisco` (5,72 s) | 4,19 s | 125.400 | **31.000** |
| Contra un recorrido escrito para esto (2,50 s) | 0,97 s | 29.000 | **7.200** |

**Aun en el caso peor son siete mil archivos**, que es un orden de magnitud por encima de los 500
que harían la idea inservible. El número aguanta el supuesto desfavorable; eso es lo que lo hace
defendible.

### Y un límite que no es de velocidad, sino del propio diario

El diario de cambios tiene un tamaño máximo y **da la vuelta**: cuando se llena, se come los
registros más antiguos. El tamaño por omisión en Windows es del orden de 32 MB, que a ~112 bytes por
registro son **unos 300.000 registros**. Ese dato no está medido aquí —se comprueba con
`fsutil usn queryjournal C:`— pero si se confirma, cierra el punto de forma elegante:

**el punto de equilibrio (125.000) está más o menos a la mitad de lo que cabe en el diario
(300.000).** O sea que la regla rápida y la regla segura casi coinciden: si el diario ha dado la
vuelta por encima del corte guardado, hay que recorrer el disco entero **por obligación**; y bastante
antes de eso ya conviene hacerlo **por velocidad**. No hace falta una heurística complicada: se lee
cuánto ha crecido el diario y, por encima del umbral, se recorre.

---

## Qué pasa cuando el índice guardado está obsoleto o corrupto

Esta es la pregunta más importante del punto, y no tiene un número por respuesta.

**Un índice que miente es peor que no tener índice.** Si el archivo guardado dice que hay 40 GB en
una carpeta que ya no existe, el programa enseña espacio que no está, el usuario va a buscarlo y no
lo encuentra, y a partir de ahí ya no se fía de nada de lo que ve. Cachivache no puede permitirse
eso: **su producto no es la velocidad, es que lo que dice sea verdad.**

**Cómo se detecta.** El índice tiene que llevar una cabecera con datos que se puedan contrastar
contra el disco de hoy, y cada uno cierra una forma distinta de mentir:

| En la cabecera | Qué mentira detecta |
|---|---|
| Versión del formato | El índice lo escribió una versión anterior del programa con otra estructura |
| Número de serie del volumen | Es **otro disco** que ha heredado la misma letra: un USB, una unidad remontada |
| Identificador del diario (`UsnJournalID`) | El diario se borró y se creó de nuevo — `chkdsk`, una restauración, o alguien lo desactivó. La historia anterior ya no existe |
| El USN de corte de la última pasada | Comparado con el `FirstUsn` de ahora dice si el diario **ha dado la vuelta** y se ha comido el tramo que hacía falta |
| Número de entradas y suma de comprobación del cuerpo | El archivo está truncado o alterado — el caso típico es un apagón a mitad de escritura |

**Qué hace el programa entonces.** Lo mismo en los cinco casos, y es la respuesta segura de siempre
en este proyecto: **ante la duda, no afirmar. Recorrer de nuevo.** No hay reparación parcial, no hay
*«uso lo que parece bueno y lo demás lo dejo»*. Un índice que no se puede validar entero se tira
entero y se hace la pasada completa, que cuesta cinco segundos. Y no se avisa con un error: se
recorre y ya está, porque desde fuera lo único que se nota es que esta vez tardó lo de siempre.

**Y hay una forma de corrupción que ninguna cabecera detecta**, así que hay que decirla: los cambios
hechos **con el diario apagado**. Si alguien lo desactiva, si el disco se monta desde otro sistema en
un arranque dual, o si se toca desde un contenedor, los cambios ocurren y el diario no se entera. El
identificador sigue coincidiendo y el corte sigue siendo válido: el índice miente **y todo cuadra**.
Contra eso solo hay dos redes, las dos baratas:

- **Caducidad.** Un índice de hace más de unos días se descarta sin mirarlo. El ahorro que da un
  índice viejo es pequeño —han cambiado muchos archivos— y el riesgo es alto.
- **Comprobación por muestreo.** Antes de fiarse, verificar contra el disco unas cuantas carpetas
  elegidas al azar. Si alguna no cuadra, recorrido completo. Cuesta milisegundos y convierte un fallo
  silencioso en un recorrido de más.

**Y la decisión de diseño que se deriva de todo esto, que vale más que las anteriores:** el índice
guardado sirve para **pintar el mapa**, nunca para **decidir qué se borra**. Cachivache borra desde
lo que acaba de ver con sus propios ojos en esta ejecución. Si el índice se equivoca, el peor caso es
un rectángulo mal dibujado; nunca un archivo borrado por error. Esa separación tiene que estar en el
código desde el primer día, porque añadirla después de que algo dependa del índice no se hace.

---

## El veredicto

**`VEL-02` sigue en pie, y ahora con números en vez de con una intuición.** El punto de equilibrio
está en unos 125.000 registros del diario —del orden de 30.000 archivos tocados—, y aguanta 7.000
incluso con el supuesto más desfavorable. Un uso normal no se acerca ni de lejos.

Merece la pena decir qué cambia respecto a antes. La hoja de ruta decía de `VEL-02` que *«si se hace
`VEL-01`, este pierde casi todo el sentido»*. `VEL-01` se midió y se descartó, así que no lo pierde;
y ahora se sabe además que la idea que queda **no es una versión de consolación**, sino el único
camino que gana. Lo que la medición añade:

- **Es un punto de PowerShell que PowerShell sí puede tener.** Justo lo contrario de `VEL-01`. El
  coste por elemento del intérprete —esos 10-18 µs que hundieron la tabla maestra— aquí se paga
  sobre **decenas de miles** de registros en vez de sobre un millón. Ese es todo el mecanismo:
  la idea no consiste en ser más rápido por elemento, sino en tocar muchos menos elementos.
- **El formato de persistencia no es un detalle, es la mitad del punto.** Entre el peor formato
  razonable y el mejor hay un factor de doce en la carga, y el peor de todos —JSON— ni siquiera
  termina. Elegir mal aquí no habría hecho el punto lento: lo habría hecho imposible, y desde
  dentro del código habría parecido que la idea era mala.
- **Hay que guardar tres tablas, no una**: archivos, carpetas y referencias de carpeta a ruta. Con
  una sola, la propagación posterior cuesta 6 s y se lo come todo.
- **La parte que falta por medir es la que puede tumbarlo.** Ver abajo.

Si algún día hay que volver aquí, la señal que lo justificaría no es que las cuentas de este
documento estén mal: es que leer el diario en Windows resulte costar mucho más de lo que este
entorno puede saber.

---

## Lo que esta medición NO puede saber

Esto se ha medido en Linux, sobre un sistema de archivos que no es NTFS, en un contenedor compartido
con 3,9 GB de memoria y dos núcleos, y con **PowerShell 7**, mientras que el programa corre en
**5.1**. Hay que decir con precisión qué se sostiene y qué no.

**No es fiable desde aquí, y hay que mirarlo con lupa:**

- **La lectura del diario. No se ha ejecutado nunca.** Es `DeviceIoControl` con
  `FSCTL_READ_USN_JOURNAL` sobre un manejador de `\\.\C:`, con permisos de administrador y sobre
  NTFS. Aquí no existe ninguna de las tres cosas. **Todo lo que dice este documento sobre el diario
  es el coste de PARSEAR sus registros, no el de obtenerlos.** Es el agujero grande.
- **Preguntar el tamaño de un archivo suelto: 1,80 µs.** Esto es caché de página en ext4 y en
  Windows será **bastante peor** — `GetFileAttributesEx` sobre una ruta suelta, sin la localidad que
  da recorrer una carpeta entera, y en frío mucho más. Si en Windows cuesta 30 µs en vez de 2, el
  coste por registro pasa de 33 a 62 µs y **el punto de equilibrio se parte por la mitad**: unos
  68.000 registros, unos 17.000 archivos. Sigue siendo bueno, pero conviene saberlo.
- **El recorrido, y le favorece al lado equivocado.** Enumerar carpetas en ext4 con la caché
  caliente es baratísimo; en Windows sobre NTFS es más caro. Aquí eso juega **a favor** de `VEL-02`,
  al revés que en `VEL-01`: si el recorrido completo es más lento en Windows, el margen crece y el
  punto de equilibrio sube. Los 5,7 s son un suelo optimista **del lado que queremos batir**.
- **PowerShell 5.1 contra 7.** Todo lo de aquí está medido en 7. El bucle de `BinaryReader` que
  carga el índice y el bucle que aplica los cambios son código de intérprete puro, y 5.1 es más
  lento. Si fuera el doble, la carga pasa de 1,0 a 2,1 s y el coste por registro de 33 a unos 60:
  el punto de equilibrio caería a **unos 51.000 registros, 13.000 archivos**. Sigue compensando,
  pero es la diferencia entre cómodo y justo. (Y es una cuenta conservadora: en 5.1 el recorrido
  completo también sería más lento, lo que devolvería parte del margen.)
- **El árbol de 20.000 archivos es poco profundo** —200 carpetas, un nivel— mientras que el índice
  sintético tiene tres niveles. Propagar un cambio cuesta un salto por nivel, así que en un
  `C:\Users\...\AppData\Local\...\Cache\...` de verdad, con ocho o diez niveles, los 11,7 µs de
  aplicar serán más.
- **Los tiempos absolutos.** Entre pasadas hubo hasta un 40 % de diferencia en las medidas de un
  millón. Las comparaciones aguantan ese margen de sobra; los números sueltos, no.

**Sí es fiable, y es lo que decide:**

- **Que `ConvertTo-Json` no sirve.** Es coste de intérprete y de memoria, y en 5.1 será peor, no
  mejor. Este resultado no se mueve.
- **Los 18 µs por registro de parseo.** Es CPU parseando bytes que ya están en memoria, exactamente
  como los 75 µs de `VEL-01`. No dependen del sistema de archivos.
- **Que el binario gana a `Import-Csv` por seis veces y a los objetos por doce.** Es una propiedad
  de cómo PowerShell compone objetos, no del entorno.
- **Que hay que guardar la tabla de carpetas.** Los 6 s de propagación completa son aritmética con
  diccionarios.

### Qué habría que medir en Windows, y en este orden

Las dos primeras antes que escribir una sola línea del punto:

1. **`DeviceIoControl` con `FSCTL_READ_USN_JOURNAL` contra `C:` con permisos de administrador**, en
   PowerShell 5.1. Cuánto cuesta la llamada, cuántos registros devuelve por buffer, y sobre todo
   **cuántos registros al día genera un equipo de verdad**. Ese último dato es el que dice si el
   punto de equilibrio de este documento queda cómodamente por encima del uso real o justo por
   debajo. Sin él, todo lo demás es aritmética sin sujeto.
2. **`fsutil usn queryjournal C:`**, para saber el tamaño real del diario y confirmar —o no— los
   ~300.000 registros que caben.
3. **El mismo banco entero en PowerShell 5.1**, que es donde corre el programa.
4. **El recorrido sobre un `C:` de verdad, en frío**, para saber cuánto margen hay de verdad.

---

## Qué queda escrito, y qué no

**Queda `tools/Banco-VEL02.ps1`, y nada más.** No se ha implementado el índice incremental: este
encargo era medir si merece la pena, no construirlo. El banco existe para que cualquiera pueda
volver a ejecutarlo y contradecir este documento — sin él, esto sería una opinión sobre un código
que nadie escribió.

El banco **no está enganchado a nada**: no lo carga `Bootstrap.ps1` y no lo llama ninguna función del
programa. Solo lee `src/Core/Indice.ps1` —junto con `Progreso.ps1`, `Format.ps1` y `FileSystem.ps1`,
que son sus dependencias— para poder medir `New-IndiceDisco` de verdad y no una imitación.

Y de escribirlo salieron dos cosas que valen por sí solas, las dos ya anotadas en `docs/RELEVO.md` y
las dos vueltas a pisar aquí:

- **`.GetNewClosure()` deja al bloque sin las funciones del guion.** La primera versión del banco
  usaba cierres para pasarles las variables a los bloques que se cronometran. Habría fallado en
  cuanto uno de ellos llamara a `Get-RegistroUsn` o a `New-IndiceDisco`, porque el cierre se ejecuta
  en un módulo dinámico donde esas funciones no se ven. Se cambió por variables `$script:`, que es
  lo que el relevo ya decía que había que hacer.
- **`[int]($i / 20)` redondea, no trunca.** Generando las carpetas sintéticas a partir del índice del
  archivo, el redondeo se saltaba combinaciones y salían archivos colgando de carpetas que no
  existían — con lo que la propagación medía un árbol distinto del que se creía. Se ve enseguida
  porque el número de carpetas no cuadra; si el banco no lo hubiera impreso, no se habría visto.

---

## Segunda parte · 2 de septiembre de 2026 — la mitad de Windows, escrita y sin ejecutar

El párrafo de arriba que dice *«no se ha implementado el índice incremental»* ha caducado. Desde el
1 de septiembre existen `IndicePersistente.ps1` e `IndiceIncremental.ps1` (guardar, leer, decidir si
se puede creer, aplicar cambios), y desde hoy existe **la lectura del diario**:

| Archivo | Qué hace | Probado |
|---|---|---|
| `src/Core/DiarioUsn.ps1` · `Get-RegistroUsn`, `Get-RegistrosUsn` | bytes `USN_RECORD_V2` → registros | **64 pruebas**, byte a byte, 16 mutaciones cazadas |
| `src/Core/DiarioUsnCambios.ps1` · `Get-CambioDesdeRazonUsn`, `ConvertTo-CambiosIndice` | registros → `Alta`/`Baja`/`Cambio` colapsados por archivo, con renombrados y orden por USN | **43 pruebas**, 12 mutaciones cazadas |
| `src/Core/DiarioUsn.ps1` · `Test-PuedeLeerDiarioUsn` | si se puede leer y, si no, por qué | 7 pruebas |
| `tests/DiarioUsnCostura.Tests.ps1` | **el camino entero**: bytes → registros → cambios → índice guardado → leído → actualizado, y el total cuadra al byte | 17 pruebas, 4 mutaciones cazadas en las tres juntas |
| `src/Core/DiarioUsn.ps1` · `Get-DatosDiarioUsn`, `Read-DiarioUsn` | abrir el volumen y pedirle el diario con `DeviceIoControl` | **NUNCA EJECUTADO** |

Las dos mitades puras se escribieron **en paralelo**, cada una por un agente, con el contrato de en
medio dictado por escrito. Es la situación de la regla 4 del relevo, y la prueba de costura existe
por eso: es la única que recorre las tres juntas seguidas, y cada junta se rompió a propósito para
ver que la costura lo nota.

### Lo que sigue siendo una hipótesis

`Get-DatosDiarioUsn` y `Read-DiarioUsn` están en la misma situación que `Read-TablaMaestra` en
`VEL-01`: escritas donde no hay NTFS, contra la documentación del formato, y sin haberse ejecutado
ni una vez. Hasta que alguien las corra en un Windows real son PowerShell con forma de función.

**`tools/Banco-VEL02-Diario.ps1` existe para eso.** Se ejecuta como administrador, no toca nada, y
mide cuatro cosas en orden: si el diario responde, cuánto tarda en leerse, cuánto de lo leído se
entiende, y cuántas altas/bajas/cambios salen de la última hora. Si el punto 1 falla siendo
administrador, el fallo está en el `DeviceIoControl` y se mira con `-Verbose`.

### Las dos cosas que este trabajo ha dejado claras, y que cambian el punto

**1. El camino rápido es solo para administradores.** Leer el diario exige abrir `\\.\C:` en crudo,
igual que la tabla maestra, y eso sin elevación falla con acceso denegado. El programa arranca sin
privilegios. O sea que **en el uso normal el segundo análisis NO va a ser más rápido**: lo será
cuando el usuario reinicie como administrador, que es cuando ya se ejecutan los módulos que lo
piden. `Test-PuedeLeerDiarioUsn` lo dice con esas palabras. No es un fallo de diseño —es el precio
de no pedir permisos que el usuario no ha dado— pero hay que decirlo al vender el punto.

**2. Falta una pieza, y es la que decide el diseño.** El diario no da rutas: da la **referencia** de
la carpeta padre y el nombre del archivo. Convertir esa referencia en una ruta es cosa de Windows —
`OpenFileById` + `GetFinalPathNameByHandle`, una llamada al sistema por carpeta— o cosa del índice,
si al recorrer se guarda la referencia de cada carpeta y la resolución se vuelve una búsqueda en
diccionario. **Cuál de las dos conviene lo dice un número que solo el banco puede dar:** cuántas
carpetas padre distintas aparecen en una hora de uso. Si son cientos, se resuelve al vuelo; si son
decenas de miles, se guarda en el índice y hay que subir la versión del formato.

`ConvertTo-CambiosIndice` ya está preparada: recibe el resolutor como un bloque, así que da igual
cuál de las dos formas gane. Lo que no existe todavía es ninguna de las dos.

### Qué hay que hacer para cerrar `VEL-02`

1. Ejecutar `tools/Banco-VEL02-Diario.ps1` **como administrador** y pegar la salida.
2. Con el número de carpetas padre, elegir el resolutor y escribirlo.
3. Enganchar el camino en `Invoke-Analisis`: guardar el índice al terminar un recorrido, y al
   siguiente análisis pasar por `Test-PuedeLeerDiarioUsn` → `Get-DatosDiarioUsn` →
   `Test-IndiceUtilizable` → `Read-DiarioUsn` → `ConvertTo-CambiosIndice` → `Update-IndiceConCambios`,
   con el recorrido completo como salida de cualquier «no» por el camino.
4. Medir en `C:` de verdad los dos caminos, y contrastar con el punto de equilibrio de la primera
   parte (~30.000 cambios).

---

## Tercera parte · 5 de septiembre de 2026 — ejecutado en Windows real. El veredicto se invierte.

Todo lo anterior daba por bueno un supuesto que el propio documento marcaba como no comprobado.
Se comprobó, en la máquina del autor, Windows 11, PowerShell 5.1, como administrador, con
[`tools/Diagnostico-DiarioUsn.ps1`](../tools/Diagnostico-DiarioUsn.ps1) y
[`tools/Banco-VEL02-Retencion.ps1`](../tools/Banco-VEL02-Retencion.ps1).

### Lo que sí funciona, y no es poco

`Get-DatosDiarioUsn` y `Read-DiarioUsn` **funcionan**. La P/Invoke a `DeviceIoControl`, el
`FileStream` sobre `\\.\C:`, los códigos de control `0x000900F4` y `0x000900BB`, el `USN_JOURNAL_DATA`
y el recorrido de registros pegados: todo correcto contra hardware real. Las seis variantes de la
petición devuelven `BIEN`, los registros llegan en **versión 2.0** —la que `Get-RegistroUsn` sabe
leer— y el parseador los entiende. El volumen declara admitir de la V2 a la V4, así que la V2 no está
en peligro de desaparecer.

Hubo un fallo, y era de una línea: la máscara de razones se escribía `[uint32]0xFFFFFFFF`. En
PowerShell ese literal es un **`Int32` que vale −1**, y convertirlo lanza. Lanzaba dentro del `try`,
dos líneas antes de la única llamada al sistema de la función, así que el `catch` lo devolvía como
`$null` y desde fuera se veía idéntico a *«Windows ha dicho que no»*. Los **81 ms** que tardaba en
fallar eran la pista: ninguna llamada al sistema tarda tan poco.

### El número que lo tumba: la velocidad

| | |
|---|---|
| Parseo medido en Windows PowerShell 5.1 | **74–82 registros/s** |
| Parseo del mismo código en pwsh 7 sobre Linux | 5.694 registros/s (**70×**) |
| Diario del equipo en ese momento | 38,2 MB ≈ **341.000 registros** |
| Parsearlo entero | **4.154–4.587 s ≈ 70 minutos** |
| Recorrer el disco entero, hoy, en ese equipo | **42 segundos** |

Con el margen de 4,2 s que dejaba la medición original, a 12.800 µs por registro el punto de
equilibrio cae a **unos 330 registros**. El encargo decía que por debajo de 500 la idea era
inservible.

**Y no es un problema de esta implementación.** Incluso al ritmo bueno —5.694 reg/s, que es pwsh 7 en
Linux— el diario entero costaría 60 s, más que los 42 s de recorrer el disco. El problema es hacer
parseo binario en PowerShell: 341.000 `pscustomobject`, con dos llamadas a función cada uno, es
trabajo que este lenguaje no hace a esa escala. En C# con `Add-Type` sería menos de un segundo. Esa
puerta queda abierta y documentada, pero no se cruza, por lo que viene ahora.

### El número que lo cierra por el otro lado: la retención

El diario NTFS es un **buffer circular**. Se midió con reloj durante 10,5 minutos, con el equipo en
uso normal:

```
  reloj        generado (MB)      tirado (MB)  conserva (MB)
  00:30                  0,3              0,0         39,0
  05:30                  1,2              0,0         39,9
  06:27                  1,5              8,0         32,2     <- NTFS recorta de golpe
  10:27                  4,7              8,0         35,4
```

- **Genera 0,4 MB/min** con el equipo tranquilo → ventana de **79 minutos**.
- Entre dos ejecuciones anteriores había generado **148 MB**, unas 9 veces más rápido → ventana de
  **~10 minutos**.
- NTFS **no recorta poco a poco**: descarta en bloques de 8 MB de golpe (la fila de 06:27).

O sea que la historia que guarda el diario está entre **diez minutos y hora y pico**, según lo que
esté haciendo el equipo. **No son días.**

Eso mata la premisa, y de forma independiente de la velocidad. La promesa de `VEL-02` era *«el
segundo análisis no recorre el disco»*. Un limpiador de disco se usa cada semanas: para cuando el
usuario vuelve, `FirstUsn` hace mucho que pasó de su `UsnCorte`, `Test-IndiceUtilizable` lo detecta
correctamente y se recorre el disco entero igual. **El camino rápido casi nunca se dispararía.**

### Lo que sí queda, y es la parte útil

Hay un caso en el que el camino rápido sí se dispararía: **volver a analizar justo después de
limpiar**, para comprobar que ha funcionado. Ahí han pasado segundos, no semanas.

Pero ese caso **no necesita el diario para nada**. El programa ya sabe exactamente qué acaba de
borrar —`Remove.ps1` deja `BytesLiberados` en cada candidato— y `Update-IndiceConCambios` ya existe y
ya está probado. Lo único que falta es el cable entre los dos. Eso es `VEL-04`, y no necesita
administrador, ni NTFS, ni P/Invoke: funciona también en FAT32, exFAT y unidades de red, donde el
diario ni siquiera existe.

### Qué se aprende de esto, más allá de `VEL-02`

1. **La letra pequeña del 1 de septiembre acertó de pleno**, y por eso estaba escrita. El punto 3
   decía qué comprobación faltaba y qué pasaría si salía mal. Salió mal. Un documento que enumera
   sus propios supuestos no comprobados vale más que uno que solo da resultados.
2. **107 pruebas verdes alrededor de una función no dicen nada sobre esa función.** Las de `VEL-02`
   cubrían el cálculo puro que rodea a `Read-DiarioUsn`; ninguna podía ejecutarla, porque abre el
   volumen en crudo. El fallo vivió ahí hasta que alguien lo ejecutó a mano, elevado.
3. **Medir antes de optimizar, incluso cuando "está claro" que va a compensar.** El punto de
   equilibrio calculado y el real se llevaban un factor de 380.
