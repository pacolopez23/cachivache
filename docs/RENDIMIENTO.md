# Rendimiento: qué hace lento a Cachivache y en qué orden arreglarlo

Este documento es un plan de implementación, no una lista de deseos. Cada punto lleva **archivo:línea**, **cuánto cuesta hoy**, **cuánto costaría después** y **qué riesgo tiene**. Lo que se ha cronometrado va marcado **[MED]**; lo que se ha razonado sin poder ejecutarlo, **[EST]**, con el razonamiento a la vista.

> **Estado: la Fase A esta hecha** (19/08/2026). Los cinco puntos que la componen —§1, §7, §8a y los dos de §9— van marcados **[HECHO]** mas abajo, con lo que se midio despues. Las fases B, C y D siguen siendo plan.

Hermano de [`OPTIMIZACIONES.md`](OPTIMIZACIONES.md) (que cubre correcciones y sigue siendo válido para lo que marca como pendiente) y de [`ESTRUCTURA.md`](ESTRUCTURA.md) (cómo está repartido el código).

---

## Cómo se ha medido, y por qué puedes fiarte de los números

Todo se ha cronometrado con **pwsh 7.4.6 sobre Linux**, con `Stopwatch`, descontando el bucle vacío, mediana de varias repeticiones y calentamiento previo, sobre árboles sintéticos de 7.200 y 21.027 archivos.

Eso plantea una pregunta legítima: **¿valen esos números para Windows PowerShell 5.1, que es donde el programa se ejecuta de verdad?** La respuesta corta es que **las proporciones sí y los absolutos no**. Se comprobó calibrando tres funciones contra el mismo código en el equipo real:

| Función | Windows | Banco de pruebas | Factor |
|---|---|---|---|
| `Get-MotivoIntocable` | 134 µs | 60,0 µs | 2,23 |
| `Test-BajoRaiz` | 105 µs | 49,6 µs | 2,12 |
| `Test-ArchivoPersonal` | 74 µs | 32,2 µs | 2,30 |

Factor consistente de **≈2,2**. Cuando este documento da una cifra "en tu equipo", es la medida del banco escalada por ese factor y va marcada como tal. **PowerShell 5.1 es además más lento que 7 en llamadas a función y en `Add-Type`**, así que las ganancias reales tenderán a ser mayores que las que aquí se prometen, no menores.

Tres cosas **no** se han podido medir y se dicen abiertamente: el coste de una consulta CIM (no existe `Get-CimInstance` fuera de Windows), el coste de abrir COM por acceso directo, y todo lo que sea WPF.

---

## Resumen: los diez cambios que importan

Ordenado por segundos ganados, no por elegancia. El escenario de referencia es un equipo con 150.000 archivos en las carpetas del usuario y perfil Exhaustivo.

| # | Cambio | Dónde | Gana | Riesgo | Esfuerzo |
|---|---|---|---|---|---|
| 1 | **[HECHO]** `Measure-Ruta` y `Measure-RutaDetalle` con enumeración .NET | `FileSystem.ps1:23-100` | **~20 s** | Bajo | 3 h |
| 2 | Las tres patologías de carpetas vacías | `40-CarpetasVacias.ps1:52,77-79,32-36` | **~31 s** | Bajo | 4 h |
| 3 | Sondeo parcial antes de hashear duplicados | `55-Duplicados.ps1:59-71` | **75×** en el caso normal | Ninguno | 3 h |
| 4 | Helper de recorrido con poda, usado por 5 módulos | `FileSystem.ps1` (nuevo) | **~20 s** | Bajo | 5 h |
| 5 | La guardia con tablas precalculadas | `Guard.ps1` (varias) | **~38 s** al vaciar una caché grande | Medio | 6 h |
| 6 | Un runspace reutilizado en vez de 18 | `Window.Analisis.ps1:87-105` | **~2,4 s** | Medio | 4 h |
| 7 | Ventana de "Preparando…" durante el arranque | `Window.ps1:15` (nuevo) | **percibida: 2,5 s → 0,7 s** | Bajo | 2 h |
| 8 | **[HECHO]** Retardo en el filtro de resultados | `Window.Eventos.ps1:169` | **2,9 s → 0,5 s** al escribir | Bajo | 30 min |
| 9 | **[HECHO]** Resumen del pie en una sola pasada | `Window.Ayudantes.ps1:288-354` | clic de casilla **100 ms → 25 ms** | Ninguno | 1 h |
| 10 | Barra de progreso honesta | `Window.Analisis.ps1:345` | percibida, alta | Ninguno | 2 h |

**Si sólo se hacen tres:** el 1, el 3 y el 8. Suman menos de un día, tienen riesgo casi nulo y cubren los tres momentos en que el usuario espera: analizar, buscar duplicados y filtrar.

---

## 1. El error que se repite en todo el programa: `Get-ChildItem -Recurse`

Es, de largo, el hallazgo con mejor relación ganancia/riesgo, y no es un truco: es que el cmdlet cuesta lo que cuesta.

```
Sobre 7.200 archivos                                     [MED]
  Get-ChildItem -Recurse -Force -File .............. 179 ms
  [IO.Directory]::EnumerateFiles ...................   4 ms      45×
  DirectoryInfo.EnumerateFiles + suma de tamaños ...  20 ms       9×
  Measure-Ruta tal y como está hoy ................. 183 ms
```

`Get-ChildItem` construye un objeto de PowerShell con su `PSObject` por cada archivo, resuelve el proveedor y pasa por la canalización. `EnumerateFiles` devuelve directamente lo que le da `FindNextFile`. Para **contar y sumar**, que es todo lo que hace `Measure-Ruta`, la diferencia es de casi un orden de magnitud.

**`Measure-Ruta` tiene 18 puntos de llamada** y la usan seis módulos. Un solo cambio en `FileSystem.ps1:102-130` los acelera a todos:

| Quién la llama | Sobre qué | Hoy [EST] | Después [EST] |
|---|---|---|---|
| `10-Caches` | `.m2`, `.nuget`, `.cargo`, `.gradle` en perfil Exhaustivo | 6,3 s | 0,8 s |
| `70-WindowsUpdate:48` | `Windows.old` (~150.000 archivos) | 3,8 s | 0,5 s |
| `95-PerfilesUsuario:28` | el perfil entero de otro usuario | 3,0 s | 0,4 s |
| `75-AlmacenComponentes:65` | WinSxS (~90.000 archivos) | 2,3 s | ver §6 |
| `20-Proyectos:71` | cada `node_modules` | 5,4 s | 0,5 s |
| `15-Navegadores:61` | cada subcarpeta de caché | 1,0 s | 0,1 s |

**Y `Measure-RutaDetalle` es peor todavía.** `FileSystem.ps1:132-167` hace **tres pasadas** sobre los mismos datos y, para quedarse con la fecha más reciente, **ordena el array entero**:

```powershell
$resultado.Ultimo = ($archivos | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
```

Ordenar 7.200 elementos para sacar un máximo cuesta **36 ms**; el mismo máximo con un `foreach` cuesta **2,1 ms** [MED]. La función completa: **222 ms → 18,6 ms** con una sola pasada [MED], verificado campo a campo (`Bytes`, `Archivos` y `Ultimo` coinciden exactamente). En el módulo de restos de programas, que mide una carpeta por programa: **8,9 s → 0,74 s** [EST].

**[HECHO]** Medido después del cambio, sobre el mismo árbol de 7.200 archivos: `Measure-Ruta` **204 ms → 25 ms (8,1×)** y `Measure-RutaDetalle` **335 ms → 23 ms (14,3×)**, con los tres campos verificados idénticos contra la implementación anterior. La red de seguridad es `tests/FileSystem.Tests.ps1`, una prueba de caracterización que lleva dentro una copia literal del código viejo y compara los dos.

**Corrección a este documento: la trampa que anunciaba aquí no existía.** Se afirmaba que `Get-ChildItem -ErrorAction SilentlyContinue` encola los errores de acceso denegado en `$ps.Streams.Error` y que `Window.Analisis.ps1:129-146` los agrupa para informar de "N rutas inaccesibles". **Es falso, y se comprobó ejecutándolo:** con `SilentlyContinue` el registro de error no llega al flujo de error del `PowerShell` —sólo pone `HadErrors` a `$true`—, así que ese diagnóstico nunca vio un acceso denegado de un recorrido. No se ha perdido nada al cambiar de API porque no había nada que perder.

Lo que **no** se ha hecho, y a propósito: emitir esos errores a mano con `Write-Error`. `Cachivache.ps1:82` pone `$ErrorActionPreference = 'Stop'` para todo el modo consola, y ahí un `Write-Error` dentro de `Measure-Ruta` abortaría la medición entera. `Get-ResumenArbol` los devuelve contados en `Inaccesibles` por si algún día se quieren mostrar; que ese diagnóstico vuelva a funcionar es un arreglo aparte, no un efecto colateral de una optimización.

**Y una diferencia deliberada:** el recorrido nuevo **no atraviesa los puntos de reanálisis**. `Get-ChildItem -Recurse` de PowerShell 5.1 sí entra en las junctions, de modo que un enlace a una carpeta hermana contaba sus bytes dos veces y un enlace a un ancestro daba vueltas. `Measure-Ruta` ya se negaba a seguir un enlace que le dieran como raíz; ahora la regla vale también dentro. Hay una prueba que lo fija.

---

## 2. Carpetas vacías: el módulo más caro del programa, y el que menos libera

`40-CarpetasVacias.ps1` consume más segundos que ningún otro, y su propia descripción dice *"Ordenan, no liberan espacio"*. Tiene tres problemas independientes.

### a) Un bucle cuadrático que se coló · `:77-79`

```powershell
$niveles = @($candidatas | Where-Object {
    $_.FullName.StartsWith($dir.FullName + [IO.Path]::DirectorySeparatorChar, ...)
}).Count
```

Por **cada carpeta emitida** se recorre **toda** la lista de candidatas. Medido: **30,5 ms por emitida** con 2.186 candidatas [MED]. Con 18.000 candidatas: **~15 s** [EST].

Tiene guasa: el comentario de `:39-43` presume de que el paso 1 es lineal *"no cuadrático, ver [R-05]"*, y es verdad — el cuadrático se coló en el paso 2, después de aquella corrección.

**Arreglo:** el subárbol de una carpeta limpia es enteramente limpio, así que `$niveles` es el número de descendientes candidatos, y se puede acumular en O(1) durante el recorrido ascendente que ya existe en `:49-62`. Produce exactamente el mismo entero. **Riesgo: ninguno.**

### b) Un `Get-ChildItem` por carpeta candidata · `:52`

Segundo recorrido completo del árbol, carpeta a carpeta. **650 µs por carpeta** [MED], frente a **70 µs** con `EnumerateFileSystemEntries` y un solo `MoveNext` — que es literalmente todo lo que hace falta para saber si una carpeta está vacía. Con 18.000 carpetas: **11,7 s → 1,3 s** [EST].

**Arreglo:** el recorrido de `:31` ya visita cada carpeta; anotar ahí mismo si tiene algún archivo directo y propagar hacia el padre. **Riesgo: bajo**, pero hay que conservar la regla de `:57` (una subcarpeta desconocida cuenta como contenido), que es lo que hace segura la propagación.

### c) Dos funciones de PowerShell por carpeta · `:32-36`

| | Hoy [MED] | En línea / con `HashSet` [MED] |
|---|---|---|
| `Test-EsEnlace` | 113 µs | **1,4 µs** (`$_.Attributes -band ReparsePoint`) |
| `Test-CarpetaEspejo` | 234 µs | **14 µs** |

`Test-CarpetaEspejo` es cara porque baja a `ConvertTo-Token` → `Remove-Tildes`, que hace `Normalize(FormD)` y recorre **carácter a carácter** con un `StringBuilder` el nombre de cada carpeta. Juntas, 347 µs × 18.000 carpetas = **6,1 s** [EST].

**Arreglo:** precalcular en `Initialize-Guardia` un `HashSet` con los nombres espejo ya normalizados, y saltarse el `Normalize` cuando el nombre es ASCII puro (`-match '[^\x00-\x7F]'` cuesta 2 µs y falla el 99 % de las veces). **Riesgo: medio-bajo** — es código de la guardia y hay que pasarlo por `Guard.Tests.ps1`, pero la semántica para ASCII es idéntica.

**Total del módulo: ~33 s → ~1,6 s.**

---

## 3. Duplicados: hashear entero cuando basta con mirar los bordes

`55-Duplicados.ps1:63` hashea el archivo **completo** con SHA-256, sin ninguna fase intermedia entre "coinciden en tamaño" y "veredicto final".

Medido sobre 60 archivos de 40 MB (2,4 GB), caché caliente, **sólo CPU**:

| Estrategia | Tiempo [MED] | Factor |
|---|---|---|
| `Get-FileHash` SHA-256 entero (hoy) | 2.709 ms | 1× |
| `[SHA256]::ComputeHash($stream)` entero | 1.750 ms | 1,5× |
| Hash parcial: primeros 64 KB | 36 ms | 75× |
| **Hash parcial: 4 KB cabeza + 4 KB cola** | **24 ms** | **113×** |
| `Get-FileHash` MD5 entero | 3.663 ms | 0,74× (**más lento**) |

Tres conclusiones, y una es contraintuitiva:

- **El sondeo parcial elimina el caso dominante en la vida real:** dos archivos que coinciden en tamaño por casualidad y no tienen nada que ver. Hoy esos dos se leen y hashean enteros para descubrir que son distintos.
- **Cabeza + cola, no sólo cabeza.** Es más barato (24 ms frente a 36 ms) y detecta los archivos que sólo divergen al final, que es exactamente el caso de vídeos y contenedores con metadatos al cierre.
- **No cambies a MD5.** Es más lento, porque los procesadores modernos llevan instrucciones SHA. Medido, no supuesto.

**Riesgo: cero, si se implementa como pre-filtro.** Coincidir en el hash parcial es condición *necesaria* para ser idénticos. Manteniendo el SHA-256 completo como veredicto final, el conjunto devuelto es **exactamente el mismo**. Lo que sería peligroso es *sustituir* el hash completo por el parcial: eso produce falsos positivos, y este módulo es el único que borra archivos personales (`:82`, `-PermitirPersonales`).

### Lo que no se ve en los milisegundos: el disco

Los 886 MB/s medidos son CPU con la caché caliente. En un equipo real manda la lectura:

| Disco | 40 GB de candidatos [EST] |
|---|---|
| NVMe (3 GB/s) | ~14 s |
| SSD SATA (500 MB/s) | ~80 s |
| Disco mecánico (100 MB/s) | ~400 s |

Y en perfil Exhaustivo `MinimoDuplicadoMB` baja a **3 MB** (`Profiles.ps1:61`), lo que mete de golpe toda la fototeca y la videoteca. **El sondeo parcial no es una optimización de CPU: convierte una lectura secuencial de decenas de gigas en unos miles de saltos de 8 KB.** En un portátil con disco mecánico es la diferencia entre siete minutos y quince segundos.

### Dos cosas más de este módulo

- **`:56` el progreso va por grupo, no por archivo.** Un grupo de 30 vídeos de 4 GB deja la barra congelada varios minutos en "grupo 7 de 412".
- **`:60` la cancelación no funciona dentro de un archivo grande.** `Get-FileHash` sobre un archivo de 40 GB no es interrumpible. Con hasheo incremental por bloques de 1 MB se puede consultar `Test-Cancelacion` en cada trozo. Esto arregla un problema real de la interfaz, no sólo de velocidad.
- **`:36` `Test-EsEnlace` protege sin querer contra un desastre.** Los archivos "sólo en la nube" de OneDrive son puntos de reanálisis y quedan excluidos. Menos mal: hashear un OneDrive de 200 GB en modo bajo demanda **forzaría la descarga íntegra de los 200 GB**. Merece un comentario explícito, porque hoy la protección es accidental y una refactorización podría quitarla sin que nadie se entere.

---

## 4. El árbol del usuario se recorre seis veces

No son cinco módulos, son **seis recorridos** sobre Escritorio y Documentos, porque `20-Proyectos` y `35-Descargas` trabajan sobre subconjuntos de las mismas zonas (`Config.ps1:119-132`).

| Módulo | Línea | Qué enumera | ¿Poda el descenso? |
|---|---|---|---|
| `20-Proyectos` | `:42` | todas las carpetas | **no** — baja dentro de cada `node_modules` para descartarlo después |
| `40-CarpetasVacias` | `:31` | todas las carpetas | **no** |
| `40-CarpetasVacias` | `:52` | otra vez, carpeta a carpeta | — |
| `45-AccesosRotos` | `:47` | todo el árbol filtrando `*.lnk` | **no** |
| `50-Temporales` | `:29` | todos los archivos | **no** |
| `55-Duplicados` | `:32` | todos los archivos | **no** |
| `60-ArchivosGrandes` | `:24` | todos los archivos | **no** |

Medido sobre 21.027 archivos, los cinco módulos tal cual están: **3.490 ms**. Un único recorrido .NET con poda: **102-237 ms** [MED]. Factor **14-34×**.

Y el desperdicio bruto: **13.680 de 21.027 archivos (65 %)** están dentro de `node_modules` o `.git`, y se enumeran **enteros en tres recorridos consecutivos** para tirarse después con una expresión regular.

### Por qué NO conviene un índice compartido

La idea evidente —recorrer una vez, guardar el resultado, alimentar a los cinco— es técnicamente viable en cuanto a datos: se comprobó campo a campo qué necesita cada módulo (nombre, extensión, tamaño, atributos, las tres fechas) y **todo viene en el mismo registro que devuelve `FindNextFile`**. Nadie necesita nada que obligue a una lectura extra.

Y aun así, **no compensa**, por cinco motivos que no son de datos:

1. **Cada módulo corre en su propio runspace** (`Window.Analisis.ps1:87-105`). Un índice compartido no puede sobrevivir entre módulos, y serializar 150.000 `FileInfo` a través de esa frontera cuesta más que volver a recorrer.
2. **Los conjuntos de exclusión no coinciden.** Un recorrido común sólo puede podar la intersección, y en esa intersección está `45-AccesosRotos`, que no excluye nada.
3. **`40-CarpetasVacias` necesita saber que una carpeta excluida existe** (`:26-29`: un `.git` cuenta como contenido para su padre). Un índice genérico pierde exactamente ese tipo de sutileza.
4. **Frescura.** `50-Temporales:22` compara contra `(Get-Date).AddMinutes(-30)`. Con un índice construido 40 segundos antes, un `.tmp` que se está escribiendo ahora se juzga contra una foto vieja.
5. **Cancelación y progreso.** El botón Cancelar quedaría muerto durante toda la construcción del índice, y la interfaz pasaría de 18 pasos comparables a un paso que hace todo y cuatro instantáneos — peor experiencia aunque el total baje.

**Lo que sí conviene, y da el 80 % del beneficio con el 10 % del riesgo:** un helper en `FileSystem.ps1` —`Get-ArchivosDeZona -Ruta -Podar @('node_modules','.git') -Filtro '*.lnk'`— que hace un recorrido .NET con pila explícita, poda en el descenso y salta puntos de reanálisis. **Cada módulo lo llama por su cuenta, como hoy.** Cero estado compartido, cero cambio en el modelo de ejecución. Medido: **513 ms → 90 ms por recorrido**, y la poda elimina el 65 % de los archivos que hoy se enumeran para nada.

Si algún día se quiere el índice de verdad, el diseño correcto no es "un módulo que construye un índice" sino **"un grupo de módulos que comparten runspace"**. Eso es una decisión de arquitectura, no una optimización.

---

## 5. La guardia: 88 recorridos de lista por llamada

`Get-MotivoIntocable` cuesta **134 µs** en el equipo real. De dónde salen, comparación a comparación [MED]:

| Pieza | Línea | Coste | Qué es |
|---|---|---|---|
| `ConvertTo-RutaNormalizada` | `:236` | 11,4 µs | de los cuales **0,47 µs es trabajo real**: el 96 % es la llamada a función |
| `Test-GuardiaLista` | `:231` | 9,5 µs | para comprobar un `$null -ne` |
| filtro 2: `-contains` sobre 32 rutas | `:253` | 2,66 µs | O(n) |
| filtro 3: 32 × `StartsWith` | `:261-265` | **13,83 µs** | O(n) |
| filtro 4: 24 × `Contains` | `:269-271` | 7,19 µs | O(n) |
| resto (5 expresiones regulares) | | ~9 µs | |

**88 recorridos de lista por llamada**, sobre listas que son constantes y se pueden precalcular una vez en `Initialize-Guardia`. Con `HashSet`, expresiones regulares compiladas y el filtro 3 reformulado, la función completa baja de **62,2 µs a 17,5 µs** [MED]: **3,5×**.

El **filtro 3 merece explicación aparte**, porque es un cambio algorítmico y no un truco. Hoy recorre las 32 rutas protegidas preguntando *"¿esta protegida empieza por mi ruta?"*. Eso es lo mismo que preguntar *"¿mi ruta es antecesora de alguna protegida?"*, y el conjunto de todos los antecesores de las 32 rutas **son sólo 9**. Un diccionario antecesor → protegida da además el mismo texto de mensaje. **13,83 µs → 0,50 µs**, y deja de crecer si la lista negra se alarga.

### Dónde duele de verdad: por archivo, no por candidato

Lo importante no es el coste por candidato —que son cientos— sino que `Clear-ContenidoCarpeta` (`Remove.ps1:169-172`) llama a la guardia **una vez por archivo**:

| Vaciar una caché de Chrome de 200.000 archivos | |
|---|---|
| Hoy | **57 s** de CPU pura de guardia [EST escalado] |
| Con las tablas precalculadas | **19 s** [EST escalado] |

**~38 segundos**, sin tocar el disco ni una vez más.

**Riesgo: medio, y es el único punto de este documento que toca código de seguridad.** Por eso se verificó con fuzz: 38 casos escritos a mano y **60.000 rutas generadas** con segmentos adversariales (`winsxs`, `$recycle.bin`, `copias de seguridad`, `proyecto v1..2`, barras mezcladas, no-ASCII) dieron **0 diferencias de decisión y 0 de texto**. Con una condición: el filtro 4 debe usar la expresión regular sólo como **criba negativa** (`if ($rx.IsMatch(...)) { <el foreach de hoy> }`). La variante "gana el regex" es 0,4 µs más rápida y también acierta siempre la decisión, pero **cambia qué fragmento se nombra en el mensaje** en 4.205 de 60.000 casos. Para un archivo cuyo propósito declarado es ser auditable, no vale la pena.

### Otros dos de la misma familia

- **`Test-BajoRaiz` normaliza dentro del bucle** (`Guard.ps1:428-436`): llama a `ConvertTo-RutaNormalizada` sobre cada raíz **en cada invocación**, para normalizar una constante. Con las raíces normalizadas una vez por módulo: **49,6 µs → 12,6 µs** [MED].
- **`Test-UnidadSeleccionada`** (`FileSystem.ps1:143-182`), llamada una vez por candidato desde `ModuleRegistry.ps1:134`, monta una canalización completa de PowerShell para responder *"¿la ruta empieza por C: o D:?"*: **78,8 µs**. Con un `HashSet` de letras precalculado: **0,95 µs** [MED]. Con 2.000 candidatos, 347 ms → 4 ms.

---

## 6. Trabajo caro en módulos que no borran nada

En conjunto, **~15 s del análisis Exhaustivo**, más el minuto de DISM.

| Módulo | Qué paga | Coste [EST] | Qué produce |
|---|---|---|---|
| `60-ArchivosGrandes` | recorrido completo del árbol | 4,8 s | una lista informativa |
| `70-WindowsUpdate:48` | `Measure-Ruta` sobre `Windows.old` | 3,8 s | un candidato que el propio texto dice que **no se toca** |
| `95-PerfilesUsuario:28` | `Measure-Ruta` sobre el perfil entero de otro usuario | 3,0 s | un candidato informativo |
| `75-AlmacenComponentes:65` | `Measure-Ruta` sobre WinSxS | 2,3 s | un texto — **y el número es falso** |
| `85-DockerWsl:20-25` | `-Recurse` dentro de cada paquete de la Store buscando `.vhdx` | 1,5 s | candidatos informativos |
| `80-ArchivosSistema:82` | `Get-ComputerRestorePoint` | 1-5 s | el número de puntos, sólo decorativo |

**Lo de WinSxS merece pararse.** Medir esa carpeta con `Length` da una cifra **entre 2 y 4 veces mayor que la real**, porque WinSxS está lleno de enlaces duros y cada uno se cuenta por separado. Y la salida de `DISM /AnalyzeComponentStore` que el módulo **ya está capturando** en `:24` incluye "Actual Size of Component Store" / "Tamaño real del almacén de componentes", que es el número correcto. Quitar el `Measure-Ruta` gana 2,3 s **y arregla una cifra equivocada**. Hay que añadir un tercer par de rótulos ES/EN al parser de `:52`, con el mismo cuidado que se tuvo en `[C-05]`.

**Y una propuesta de orden, no de velocidad:** los módulos `-SoloInforma` (60, 80, 90, 95) deberían ejecutarse **al final** y ser interrumpibles sin perder el resto del análisis. Hoy el usuario espera por información que no puede accionar antes de ver lo que sí puede borrar.

---

## 7. Medir antes de filtrar

El error clásico, y está en tres sitios con la misma forma:

```powershell
$bytes = Measure-Ruta $carpeta.FullName                        # segundos
if ($bytes -lt ($Configuracion.MinimoMB * 1MB)) { return }
if (-not (Test-RutaSegura $carpeta.FullName $raices)) { return }   # 0,95 ms
```

Se mide un `node_modules` de 30.000 archivos —**0,75 s**— y **después** se le pregunta a una guardia que cuesta 0,95 ms si se podía tocar. **La guardia es 790 veces más barata que la medición que la precede.**

| Dónde | Qué mide antes de preguntar |
|---|---|
| `20-Proyectos.ps1:73-79` | cada carpeta regenerable |
| `Candidate.ps1:253-262` (`Invoke-BusquedaPorLista`) | afecta a `10-Caches`, `65-LogsSistema` y `70-WindowsUpdate` |
| `15-Navegadores.ps1:62-66` | cada subcarpeta de caché |

**Arreglo: subir `Test-RutaSegura` por encima de `Measure-Ruta`.** Las dos condiciones son independientes y el `return` es el mismo, así que el resultado no cambia. Único efecto visible: los mensajes "Midiendo: …" dejan de aparecer para rutas vetadas, lo cual es una mejora. **Riesgo: ninguno.**

**[HECHO]**, y en dos sitios más de los que decía esta tabla: `10-Caches.ps1:99` (las cachés de JetBrains, una por producto y versión) y el bloque de Firefox del mismo archivo, donde la guardia se ha subido por encima del bucle que mide `cache2` en cada perfil. `tests/BusquedaPorLista.Tests.ps1` fija que los candidatos propuestos siguen siendo exactamente los mismos.

---

## 8. El arranque: 2,4 a 3,9 segundos mirando una pantalla quieta

Y con `Cachivache.exe`, sin consola, **el escritorio no cambia en nada** durante todo ese rato. Este es el hallazgo de mayor impacto percibido, y es previo a cualquier optimización: aunque el arranque bajara a 1,5 s, 1,5 segundos de nada siguen pareciendo un fallo.

Las fases que **no se pueden evitar** —arrancar el proceso, cargar los cuatro ensamblados de WPF, interpretar 100 KB de XAML, el primer render— suman **1,0-1,7 s** [EST] y son el suelo de cualquier WPF lanzado desde PowerShell.

**La propuesta principal es de interfaz, no de código:** una ventana mínima de treinta líneas de XAML, sin diccionarios de tema ni estilos, mostrada **justo después del `Add-Type` de WPF** (`Window.ps1:15`) y cerrada en el `ContentRendered` de la principal. Aparecería a los ~700 ms en vez de a los 2.400-3.900. Es la diferencia entre *"no ha arrancado"* y *"está arrancando"*.

### Lo que sí se puede quitar

| # | Qué | Dónde | Gana |
|---|---|---|---|
| a | **Cuatro consultas WMI donde basta una** | `Config.ps1:95,138`, `Log.ps1:46,152`, `Window.Ayudantes.ps1:93-94` | 150-350 ms [EST] |
| b | **Dos compilaciones de C# en el camino crítico** | `Types.ps1:20` y `Maximizar.ps1:36` | 650-750 ms [MED+EST] |
| c | `Get-ModulosLimpieza` ejecuta 18 archivos para leer 8 campos | `ModuleRegistry.ps1:34-49` | 60-90 ms [MED] |
| d | El panel de Informes se rellena al arrancar **sin que nadie lo esté viendo**, y enumera la carpeta **tres veces** | `Window.Ayudantes.ps1:144,212` | 20-80 ms, **creciente sin límite** |
| e | El historial se lee del disco **dos veces** por refresco | `Window.Ayudantes.ps1:172` + `Historial.ps1:147` | 10-16 ms × 5 sitios |

Sobre (a): `Win32_OperatingSystem` se consulta dos veces —la segunda cuando **el valor ya está en `$Configuracion.Windows`**— y `Win32_LogicalDisk` otras dos, con dos segundos de diferencia, más una tercera filtrada por `C:` cuyo dato venía en la anterior.

**[HECHO]**, y por una vía mejor que la prevista. `Get-DescripcionSistema` recuerda su respuesta y `Config.ps1` la reutiliza en vez de lanzar su propia consulta: de dos, una. Y `Get-UnidadesFijas` y `Get-PropiedadUnidad` ya no usan CIM en absoluto, sino `System.IO.DriveInfo` —el mismo dato, porque `DriveType Fixed` y `DriveType=3` salen los dos de la misma `GetDriveType` de Win32—, así que **no queda ninguna consulta WMI en el camino de arranque ni en el resumen del pie**. Hay un efecto secundario que no es de velocidad y vale más que ella: si el servicio WMI está estropeado, cosa que pasa más de lo que parece, la lista de discos se quedaba vacía y con ella el panel entero. `DriveInfo` no depende de ningún servicio.

Sobre (b): bajo PowerShell 5.1 cada `Add-Type -Language CSharp` **arranca `csc.exe` como proceso aparte**. Son 417 ms medidos para `Types.ps1` y otros 300-400 ms para la interoperabilidad del maximizado, que además ocurre **dentro de `SourceInitialized`**, es decir, bloqueando el primer fotograma. Fusionar las dos llamadas en una ya ahorra ~350 ms. Precompilar un `Cachivache.Tipos.dll` en el mismo paso que ya genera `Cachivache.exe` y cargarlo con `Add-Type -Path` cuesta **43-80 ms** en vez de 750 [MED].

Sobre (d): la carpeta de informes **no tiene tope**, y desde que cada análisis y cada limpieza generan su HTML automático crece para siempre. Con 1.000 informes, esas tres enumeraciones son 82 ms [MED] en cada arranque.

---

## 9. La interfaz con 15.000 filas

### El filtro: 180.000 invocaciones por escribir una palabra

`Window.Eventos.ps1:169` engancha `Add_TextChanged` directamente al filtro, **sin ningún retardo**. Cada tecla crea un `[Predicate[object]]` nuevo con `.GetNewClosure()` y provoca una pasada completa.

> Escribir **"chrome"** con 15.000 filas: **6 pulsaciones × (15.000 invocaciones del predicado + 15.000 del bloque del resumen) = 180.000 invocaciones de scriptblock**. ≈ **2,9 s de hilo de ventana bloqueado** [MED escalado], en seis tirones de ~490 ms. Las teclas se pierden.

| Arreglo | Gana | Riesgo |
|---|---|---|
| **Retardo de 250 ms** con un `DispatcherTimer` que se reinicia en cada tecla | 6 pasadas → **1**: 2,9 s → 0,5 s. **El 85 % de la mejora por diez líneas** | Bajo |
| `String.IndexOf(..., OrdinalIgnoreCase)` en vez de `-like "*$texto*"` | 15,9 → 10,8 µs/fila [MED]. Además arregla que `*` y `?` escritos por el usuario se interpreten como comodines | Bajo |
| Predicado compilado en C# | **238 ms → 1,7 ms por pasada: 140×** [MED] | Medio |

Con el retardo y el predicado compilado, escribir "chrome" pasaría de 2,9 s de congelación a **menos de 10 ms**.

**[HECHO] las dos primeras filas.** El retardo son 250 ms con un `DispatcherTimer` que se reinicia en cada tecla, y hay un invariante en `tests/Invariantes.Tests.ps1` que exige que el cuadro de texto **pida** el filtro en vez de ejecutarlo: es de las cosas fáciles de "simplificar" sin querer, y el síntoma —la ventana a tirones al escribir— no salta en ninguna prueba funcional. `IndexOf` ordinal frente a `-like`, medido sobre 15.000 filas: **148 ms → 84 ms por pasada (1,8×)**, con las mismas filas devueltas.

Y un tercer cambio que no estaba en la tabla: **sin criterios ya no se instala un predicado permisivo, se quita el filtro.** Un predicado que dice que sí a todo obliga igualmente a WPF a invocarlo una vez por fila; `Filter = $null` se salta el filtrado entero. De paso deja "¿hay algún filtro puesto?" como una pregunta que se puede hacer, y de eso depende el ahorro del párrafo siguiente. El predicado compilado en C# queda para la Fase C.

### Marcar una casilla cuesta 100 ms

`Window.Ayudantes.ps1:312` hace `@($estado.Items | Where-Object { ... })` —una invocación de scriptblock por fila— y luego suma en un segundo bucle. Y esto se ejecuta **en cada clic de casilla**, por el binding `UpdateSourceTrigger=PropertyChanged`.

**75-135 ms por clic** con 15.000 filas [MED]. Con un único `foreach` que cuente y sume a la vez: **17 ms**. Y hay un segundo recorrido (`:337`) que sólo tiene sentido cuando hay un filtro puesto; con `if ($null -ne $estado.Vista.Filter)` se ahorra en el 90 % de los clics. **Riesgo: ninguno.**

**[HECHO].** Medido de nuevo sobre 15.000 filas con el banco de pruebas: **178 ms → 22 ms (8,1×)**, mismo recuento y misma suma de bytes. El segundo recorrido sólo ocurre si hay filtro, que es lo que habilita el `Filter = $null` de más arriba.

### Cambiar de tema congela la ventana un segundo

`$aplicarTema` (`Window.Ayudantes.ps1:439-487`) hace, todo seguido y en el hilo de la interfaz: recargar el diccionario, recalcular el color de las 15.000 filas —llamando a `Get-ColorRiesgo`, que **construye dos hashtables nuevas en cada llamada** (`Window.ps1:127-128`)—, reasignar `ItemsSource`, un `Refresh()` completo, **dos consultas WMI** y **dos lecturas del JSON del historial**. Total: **0,9-1,3 s** [MED+EST] por pulsar el botón de la luna.

Ni el espacio libre ni el historial cambian al cambiar de tema. Sacar las hashtables a variables de ámbito de script es un arreglo de dos líneas.

### Y dos momentos más en que la ventana se queda muerta

- **Al terminar el análisis** (`Window.Analisis.ps1:170-229`): tres recorridos completos de la lista, más `Export-InformeHtml` (**1.370 ms** con 15.000 candidatos [MED]), más el historial, más el resumen. **≈1,8 s** justo cuando el usuario lee "Análisis terminado".
- **Al cerrar** (`Window.Analisis.ps1:108-158`): `PowerShell.Stop()` es **síncrono**. Si un módulo está dentro de un recorrido sobre una unidad de red, la ventana se queda pintada e inerte varios segundos — que es la definición de "se ha colgado" para cualquiera.

### La barra de progreso miente

`Window.Analisis.ps1:345` avanza **por módulos, no por trabajo**. Los 18 no cuestan ni remotamente lo mismo: `25-Papelera` termina en milisegundos y `55-Duplicados` puede tardar minutos. El resultado es una barra que salta a 55 % en tres segundos y luego se queda clavada.

Pesos por módulo, aunque sean groseros (los tres que recorren discos valen 10, el resto 1), y **mostrar el cronómetro, que ya existe en `$estado.Cronometro` y sólo se lee al final**. "3 de 18 · 1 min 12 s" es infinitamente mejor que una barra parada.

---

## 10. Efectividad: lo que un limpiador debería encontrar y este no busca

Ordenado por gigas típicos recuperables en un Windows 10/11 real.

1. **`C:\Windows\Temp`.** El módulo 10 vacía `%LOCALAPPDATA%\Temp` pero **el temporal del sistema no aparece en ningún módulo**, ni siquiera en `65-LogsSistema`, que ya requiere administrador. Es de lo más grande y seguro que hay: 0,5-5 GB. Es **una línea** en la lista de `65-LogsSistema.ps1:13-23`.
2. **`%LOCALAPPDATA%\Packages\*\TempState` y `\LocalCache`.** Donde tiran su caché las aplicaciones de la Store, incluido el Teams nuevo. Hoy es territorio prohibido en bloque (`Guard.ps1:87`). `TempState` es seguro por definición del contrato de AppContainer. Típico: 1-10 GB.
3. **`Windows.edb`**, el índice de búsqueda: 5-15 GB. No se borra a mano, se reconstruye desde Opciones de indización — encaja perfecto como candidato `Informativo`, patrón que el programa ya domina.
4. **SDK y emuladores.** Se cubren npm, Yarn, pnpm, Gradle, Maven, pip, NuGet, Cargo, Go y Composer, pero falta lo más gordo de una máquina de desarrollo: `Android\Sdk\system-images` (10-40 GB), `.android\avd` (5-20 GB), `.gradle\wrapper\dists`, `pypoetry\Cache`, `uv\cache`.
5. **`20-Proyectos` sólo mira siete carpetas fijas** (`Config.ps1:125-132`). Un `D:\code` o un `C:\dev` —completamente normales— son invisibles. Y es precisamente el módulo que más gigas recupera en esos equipos.
6. **Cachés de Chromium que faltan:** `ShaderCache` y `GrShaderCache` cuelgan del nivel de *User Data*, no del perfil, y el bucle de `15-Navegadores.ps1:27-35` sólo mira dentro de perfiles.
7. **Restos de plataformas de juego:** `steamapps\downloading` y `\temp` (descargas interrumpidas, 1-50 GB), `shadercache`, Battle.net, EA App, Riot. Hoy sólo se toca `Steam\htmlcache`, que es lo más pequeño de todo Steam.
8. **Tamaño en disco frente a tamaño lógico.** Todos los módulos usan `Length`. En volúmenes con compresión NTFS o archivos dispersos —frecuente en `Windows.old` y en los `.vhdx` de WSL, que son dispersos por definición— `Length` **sobreestima** lo que se va a recuperar. `85-DockerWsl.ps1:50` informa justo del número que no interesa. El proyecto ya tuvo un `[C-18]` sobre "que los bytes sean honestos", así que la sensibilidad existe.

---

## 11. Lo que se ha mirado y NO conviene tocar

Tan importante como la lista de arriba. Todo esto se midió y se descartó **con el número delante**:

| Qué | Por qué no |
|---|---|
| **El índice compartido entre los cinco módulos** | Los datos lo permiten; el modelo de un runspace por módulo no, y ese modelo es lo mejor que tiene el programa. Ver §4 |
| `+=` sobre array en `Report.ps1:327` | El patrón O(n²) de manual, sí. Pero son **70 ms con 500 informes** [MED], y el coste lo domina la creación de objetos, no la copia. Es higiene, no rendimiento |
| Todo `Historial.ps1` | 2,0 ms leer, 4,4 ms añadir, 4,6 ms el resumen [MED]. Tope de 100 entradas |
| `Select-RutasNoAnidadas` (`FileSystem.ps1:271-281`) | Doble bucle O(n²) real, con **n = 7 zonas** |
| Cambiar SHA-256 por MD5 en duplicados | **Medido: MD5 es un 35 % más lento**, porque los procesadores modernos llevan instrucciones SHA |
| La virtualización del `DataGrid` | Está **bien hecha**: `IsVirtualizingWhenGrouping`, `Recycling`, `RowHeight` fijo y un `Grid` en vez de `StackPanel` en el `GroupItem`, con el comentario correcto sobre la altura infinita. Es raro verlo bien y merece decirse |
| El `DispatcherTimer` de 200 ms | **0,043 ms por pasada en vacío** [MED]: 0,02 % del hilo. El problema no es el temporizador, es lo que se hace dentro |
| El orden de los filtros en `55-Duplicados:32-37` y `60-ArchivosGrandes:24-29` | Ya está bien: la comparación barata (`Length`) va primera y cortocircuita la cara. **Bien hecho** |
| `Show-Confirmacion` reinterpreta su XAML cada vez | 20-50 ms [EST] en un diálogo modal precedido de una decisión humana |
| Quitar la revalidación de la guardia en `ModuleRegistry.ps1:122` | Ahorraría 0,4 s y quitaría una red de seguridad deliberada. No |

---

## 12. Plan por fases

**Fase A — HECHA** (19/08/2026)
`Measure-Ruta`/`Measure-RutaDetalle` con .NET · retardo en el filtro · resumen del pie en una pasada · subir la guardia por encima de las mediciones · las cuatro consultas WMI duplicadas.
→ **~22 s del análisis** y la interfaz deja de dar tirones.

Lo medido en el banco de pruebas: `Measure-Ruta` 8,1×, `Measure-RutaDetalle` 14,3×, resumen del pie 8,1×, predicado del filtro 1,8× y seis pasadas por la tabla convertidas en una al escribir. La suite pasa entera, el analizador no da avisos, y `tests/FileSystem.Tests.ps1` (18 nuevas) compara campo a campo contra una copia literal del código anterior. **Nada de esto se ha visto ejecutarse en Windows**: WPF no arranca en el entorno donde se verifica.

**Fase B — dos días, riesgo bajo**
Las tres patologías de carpetas vacías · sondeo parcial en duplicados · helper de recorrido con poda · ventana de "Preparando…" · barra de progreso con pesos y cronómetro.
→ **~50 s más**, y el arranque deja de parecer un fallo.

**Fase C — riesgo medio, hay que probar bien**
Guardia con tablas precalculadas (con el fuzz como red) · runspace reutilizado · informe HTML fuera del hilo de la ventana · predicado del filtro compilado.
→ **~40 s más** y ninguna congelación por encima de 100 ms.

**Fase D — cobertura**
`C:\Windows\Temp`, `TempState`, SDK de Android, raíces de proyecto configurables, cachés de Chromium que faltan, tamaño en disco frente a lógico.
→ No es velocidad: es que el programa encuentre lo que debería encontrar.

---

## Apéndice: cómo reproducir las medidas

Los números de este documento se obtuvieron con `Stopwatch` sobre árboles sintéticos, descontando el bucle vacío y tomando la mediana de varias repeticiones. Para repetirlos en tu equipo, que es donde de verdad cuentan:

```powershell
# El coste real de Get-ChildItem frente a .NET, sobre una carpeta grande de verdad
$ruta = "$env:LOCALAPPDATA\Temp"
Measure-Command { @(Get-ChildItem -LiteralPath $ruta -Recurse -Force -File -ErrorAction SilentlyContinue).Count }
Measure-Command { @([IO.Directory]::EnumerateFiles($ruta, '*', 'AllDirectories')).Count }

# El coste de una consulta CIM, la unica cifra que este documento no tiene
Measure-Command { 1..20 | ForEach-Object { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" } }
```

Si la consulta CIM está en el rango habitual de milisegundos, sustituir `Get-PropiedadUnidad` (`FileSystem.ps1:226`) por `[IO.DriveInfo]` es un cambio de tres órdenes de magnitud por dos líneas: `[IO.DriveInfo]::new('C:\').AvailableFreeSpace` cuesta **1,3 µs** tras la primera llamada [MED].
