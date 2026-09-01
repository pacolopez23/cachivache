# `VEL-01` · ¿Puede PowerShell leer la tabla maestra lo bastante rápido?

**Medido el 1 de septiembre de 2026.** Este documento no describe una función: describe una
**medición**, y existe porque `VEL-01` llevaba en la hoja de ruta desde el principio marcado como
*«el diferenciador técnico del proyecto»* sin que nadie hubiera comprobado el único supuesto del
que depende entero.

---

## La respuesta, antes que nada

**No compensa.** Leer la tabla maestra desde PowerShell sale entre **tres y nueve veces más lento**
que el recorrido de carpetas que el programa ya tiene, según cuánto se esté dispuesto a sacrificar
por el camino. No es que gane poco: es que **pierde**.

| Sobre un disco de 1.000.000 de archivos | Extrapolado |
|---|---|
| El recorrido de hoy, `Get-ElementosDelArbol` | **21 s** |
| El recorrido de hoy, `New-IndiceDisco` (que es quien lo consume) | **5 s** |
| La tabla maestra, con `Get-RegistroMft` tal como está escrita | **75 s** de parseo |
| …más reconstruir las rutas desde las referencias de padre | **+113 s** |
| **Total del camino «rápido»** | **≈ 188 s** |

Y la parte más incómoda: **la lentitud no está en el parseo.** Está en que en PowerShell cada
registro cuesta una llamada a función, y un millón de llamadas a función cuestan un minuto largo
hagan lo que hagan por dentro.

---

## Cómo se ha medido

Tres bancos, todos en este entorno (Linux, PowerShell 7.4.6), todos repetidos varias veces
quedándose con **la mejor pasada** de cada uno:

1. **El parseo.** 64 registros MFT sintéticos de 1 KB —los mismos que construyen las pruebas, con
   su cabecera, su tabla de correcciones, su `$FILE_NAME` y su `$DATA`— recorridos N veces. Se
   comprueba antes de medir que el registro de muestra se parsea bien; si no, el banco lanza. Medir
   la velocidad a la que se obtiene una respuesta equivocada no habría dicho nada.
2. **El recorrido.** Un árbol de verdad en disco: 100.000 archivos en 801 carpetas, más otro de
   50.000 para comprobar que la extrapolación es lineal antes de extrapolar.
3. **El desglose.** El mismo parseo escrito cinco veces, añadiendo trabajo en cada una, para ver de
   dónde sale cada segundo.

**Los dos lados son lineales por encima de 50.000 elementos**, así que la extrapolación a un millón
es defendible:

| | 25.000 | 50.000 | 100.000 | 200.000 |
|---|---|---|---|---|
| `Get-RegistroMft`, µs por registro | 138,9 | 80,4 | **73,0** | **76,1** |
| `Get-ElementosDelArbol`, µs por archivo | — | **21,3** | **21,1** | — |

(La primera columna lleva dentro el arranque del intérprete. Por eso se mide a partir de 50.000.)

---

## Los números

**El camino de hoy**, sobre 100.000 archivos de verdad:

| | |
|---|---|
| `Get-ElementosDelArbol` | **2,11 s** |
| …leyendo además `Length` de cada uno | 1,87 s |
| `New-IndiceDisco`, que es el consumidor real | **0,47 s** |
| `[IO.Directory]::EnumerateFiles` a pelo, sin objeto por archivo | 0,03 s |

**El camino de la tabla maestra**, sobre 100.000 registros:

| | |
|---|---|
| `Get-RegistroMft`, cortando el registro del buffer | **7,30 s** |
| `Get-RegistroMft` sobre arrays ya cortados | 6,22 s |
| Reconstruir las rutas subiendo de padre en padre | **11,30 s** |

La reconstrucción de rutas no es un extra que se pueda dejar para luego: **la tabla maestra no
contiene rutas.** Contiene «el archivo X cuelga del registro 4711». El recorrido de carpetas trae
la ruta ya hecha porque es lo que estaba haciendo; el camino de la MFT tiene que construir un
millón de cadenas después. Ese paso, él solo, cuesta **cinco veces más que el recorrido completo de
hoy**.

---

## De dónde sale cada segundo

El mismo trabajo, escrito cinco veces, añadiendo una cosa cada vez. 100.000 registros:

| | | |
|---|---|---|
| 1 | Firma, banderas y un entero. Nada más | **0,28 s** |
| 2 | + copiar el registro y deshacer las correcciones de secuencia | 0,25 s |
| 3 | + recorrer los atributos y sacar nombre y tamaño | **0,55 s** |
| 4 | + componer un `pscustomobject` por registro | **1,48 s** |
| 5 | + hacerlo llamando a `Get-RegistroMft`, o sea con una función | **7,90 s** |

**Lee otra vez el salto del paso 4 al 5.** Todo el parseo —la copia, las correcciones, el recorrido
de atributos, el nombre en UTF-16, el objeto— cuesta 1,48 s. Meterlo dentro de una función de
PowerShell con sus parámetros declarados cuesta **6,4 s más**. El 80 % del coste no es leer la
tabla maestra: es el precio de llamar a una función un millón de veces.

Dos medidas sueltas que lo confirman:

- Llamar 100.000 veces a `Get-EnteroLargoLe`, que solo lee ocho bytes: **1,22 s**. O sea **12 µs por
  llamada**, sin hacer nada.
- Componer 100.000 `pscustomobject`: 0,36 s. Casi gratis en comparación.

Y por si quedaba duda de dónde está el límite:

| | |
|---|---|
| El bucle mínimo escrito en línea, sin función ni objeto | **0,26 s** |
| **El mismo bucle en C# compilado con `Add-Type`** | **≈ 0,00 s** |

---

## Por qué WizTree sí puede, y qué significa eso

La hoja de ruta dice que WizTree es cuarenta veces más rápido que WinDirStat porque lee la tabla
maestra. Eso es cierto, pero **está incompleto**, y lo que falta es justo lo que decide este punto:

WizTree es rápido porque lee la tabla maestra **y porque su parseador está en C++, donde procesar
un registro cuesta efectivamente cero**. Su factor de cuarenta sale de que, quitado el recorrido de
carpetas, lo único que queda es leer un gigabyte de disco de forma secuencial. No paga nada por
registro.

En PowerShell **siempre se paga algo por registro**, y ese algo son 75 µs. Un millón de veces son
75 segundos que WizTree no gasta. La ventaja no está en el algoritmo: está en el lenguaje. Y el
algoritmo es lo único que este proyecto podía copiar.

Dicho de otra forma: **`VEL-01` no es un punto de PowerShell mal escrito. Es un punto que PowerShell
no puede tener.**

### La salida que existe, y por qué tampoco

`Add-Type` con el parseador en C# devuelve el coste por registro a cero, y con eso los números
cambiarían por completo. Se ha medido y funciona. No se propone, por tres motivos, y el tercero es
el que pesa:

1. Compilar esa clase cuesta **0,44 s en cada arranque** del programa, medido en un proceso recién
   abierto. La hoja de ruta ya rechazó `Add-Type` en el arranque por exactamente esto.
2. El código que de verdad importa —el que abre `\\.\C:` y sigue la lista de tramos de la MFT—
   seguiría sin poder probarse aquí, y encima pasaría a estar escrito en un segundo lenguaje que
   este repositorio no tiene en ninguna otra parte.
3. **Un ejecutable pequeño y sin firmar que compila código en tiempo de ejecución tiene exactamente
   la forma de un cuentagotas de malware.** Es la misma frase que el propio proyecto usa en `DIS-01`
   para explicar por qué SmartScreen bloquea cada versión. Añadir un compilador al arranque, con la
   firma todavía pendiente, es empeorar a sabiendas el problema número uno de adopción del programa
   a cambio de unos segundos en una función que ya es rápida.

---

## El veredicto

**`VEL-01` se queda descartado, y ahora con números en vez de con una intuición.**

Merece la pena decir qué cambia respecto a antes. `VEL-01` ya figuraba entre los descartados del
relevo, pero descartado **sin haberlo medido**: seguía apareciendo en la hoja de ruta como «el
diferenciador técnico», como la ronda 6 entera y como la condición de la que dependían `VIS-01`,
`VIS-02` y `VIS-04`. Es decir, estaba descartado y planificado a la vez.

Lo que la medición cierra:

- **No hay ningún camino en el que esto gane.** Ni siquiera renunciando a las funciones puras y
  escribiéndolo todo en línea —que sería renunciar a poder probarlo, o sea a la forma de trabajar
  del proyecto entero— se baja de los 128 s por millón frente a los 21 s de hoy.
- **La ronda 6 de la hoja de ruta se queda sin su primer eslabón.** Decía que `VEL-01` «hace baratos
  a los otros dos». No los hace baratos: los haría más caros. `VIS-01` y `VIS-02` van directamente
  sobre `New-IndiceDisco`, que ya recorre un millón de archivos en cinco segundos.
- **`VIS-04` deja de tener una decisión pendiente.** Se anotaba que en unidades extraíbles habría
  que caer al recorrido normal porque suelen venir en exFAT. Ya no hay dos caminos: hay uno.
- **Y `VEL-02`, el índice compartido, recupera todo su sentido.** La hoja de ruta decía que si se
  hacía `VEL-01` este perdía casi todo el margen. No se hace, así que no lo pierde.

Si algún día hay que volver aquí, la señal que lo justificaría no es «PowerShell ha mejorado»: es
que el recorrido de carpetas en Windows real resulte ser mucho más lento de lo que este documento
puede saber. Que es justo lo que viene ahora.

---

## Lo que esta medición NO puede saber

Esto se ha medido en Linux, sobre un sistema de archivos que no es NTFS, en un contenedor
compartido. Hay que decir con precisión qué parte de lo de arriba se sostiene y qué parte no.

**No es fiable desde aquí:**

- **El lado del recorrido, y le favorece.** Enumerar carpetas en ext4 con la caché caliente es
  baratísimo. En Windows sobre NTFS, `FindNextFile` es bastante más caro, y ahí está la ventaja real
  que WizTree explota. **Los 21 µs por archivo son un suelo optimista**: en Windows serán más.
- **La lectura del disco.** Salen 0,05 s por gigabyte, que es la caché de página, no el disco. En un
  SSD real, leer el gigabyte de MFT de un disco de un millón de archivos son segundos, no
  centésimas.
- **Los tiempos absolutos.** El mismo banco dio entre 6,2 s y 7,9 s en pasadas distintas: un 25 % de
  ruido. Las comparaciones aguantan ese margen de sobra; los números sueltos, no.
- **`Read-TablaMaestra` entera.** No se ha ejecutado nunca. Ver más abajo.

**Sí es fiable, y es lo que decide:**

- **Los 75 µs por registro no dependen del sistema de archivos.** Son CPU del intérprete de
  PowerShell parseando bytes que ya están en memoria. En Windows serán los mismos o peores: **el
  programa corre en PowerShell 5.1**, que es más lento que el 7 con el que se ha medido esto, y esa
  diferencia no se ha podido cuantificar aquí.
- **Los 113 s de reconstruir rutas tampoco.** Es aritmética con diccionarios, no disco.
- **El desglose del paso 4 al 5** —que el 80 % se va en el envoltorio de la función— es una
  propiedad del lenguaje, no del entorno.

O sea: **repetir esto en Windows movería el lado bueno de la comparación, no el malo.** Para que
`VEL-01` ganara, el recorrido de carpetas en Windows tendría que ser **nueve veces más lento** de lo
que es aquí solo para empatar con el camino de la MFT tal como está escrito.

### Qué habría que repetir en Windows, si alguna vez se reabre

En este orden, y las tres primeras antes que ninguna otra cosa:

1. **`Get-ElementosDelArbol` sobre un disco real, en frío**, con un `C:` de verdad. Es el número que
   más se mueve y el único que podría cambiar el signo de la comparación.
2. **El mismo banco de parseo en PowerShell 5.1**, que es donde corre el programa. Si 5.1 es el
   doble de lento que 7, los 75 µs pasan a 150 y no hay nada más que hablar.
3. **`Read-TablaMaestra` contra `\\.\C:` con permisos de administrador**, que es lo único que puede
   decir si esa función siquiera funciona.

---

## Qué queda escrito, y para qué sirve

`src/Core/Mft.ps1` se queda en el repositorio aunque el punto esté descartado, y no «por si acaso»
—que el proyecto no hace—, sino porque **es el respaldo de esta medición**. Sin él, este documento
sería una opinión sobre un código que nadie escribió. Con él, cualquiera puede volver a ejecutar el
banco y contradecirlo.

**No está enganchado a nada**: no lo carga `Bootstrap.ps1`, no lo llama `New-IndiceDisco`, y el
comentario de cabecera dice por qué. Las tres funciones puras están probadas byte a byte en
`tests/Mft.Tests.ps1` —46 pruebas, y las invariantes verificadas con veinte mutaciones—, así que lo
que hay es correcto; simplemente es demasiado lento para usarse.

Y de escribirlo salieron dos cosas que sí valen por sí solas, las dos cazadas por la verificación
por mutación y no por las pruebas:

- **`0xFFFFFFFF` en PowerShell es un `Int32` que vale menos uno.** Comparar contra él un entero sin
  signo da **siempre falso**. El fin de la lista de atributos no se reconocía nunca, sin lanzar y sin
  avisar. Hace falta escribir `0xFFFFFFFFL`.
- **Una función que devuelve un `byte[]` sin la coma no devuelve un `byte[]`.** PowerShell lo
  desenvuelve y quien lo recoge se queda con un `Object[]`; al pasarlo luego a un parámetro
  `[byte[]]` se convierte, o sea que la función recibe **una copia**. Eso dejó hueca la prueba de
  que el parseo no toca los bytes del llamante: pasara lo que pasara dentro, el array de fuera no
  se enteraba. Se ve poniendo `return ,$r`.

Las dos son de la familia de trampas que `docs/RELEVO.md` lleva anotadas, y las dos habrían pasado
igual de desapercibidas en cualquier otro punto del programa.
