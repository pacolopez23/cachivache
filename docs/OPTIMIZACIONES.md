# Auditoría de la versión 2.0.0 — documento histórico

> ## ⚠ Esto NO es la lista de pendientes
>
> Es la auditoría de la versión 2.0.0, y **buena parte ya está hecha**. Se conserva porque cerca
> de cuarenta y cinco comentarios del código citan sus identificadores `[C-nn]`, `[R-nn]` y
> `[U-nn]` para explicar por qué algo está escrito como está: esas referencias tienen que seguir
> llevando a alguna parte.
>
> **El estado vigente del proyecto está en [`PLAN-ACCION.md`](PLAN-ACCION.md).** Si buscas en qué
> trabajar, empieza por ahí.
>
> Entradas de este documento que **ya están resueltas** y no hay que volver a tocar:
>
> | Entrada | Estado |
> |---|---|
> | `[U-01]` El filtro congela la ventana | ✅ Hecho: hay retardo de 250 ms y comparación ordinal |
> | `[U-02]` El resumen recorre 5.000 elementos por clic | ✅ Hecho: un solo `foreach` |
> | `[U-03]` Los colores viajan como cadenas | ⚠ Parcial. Los identificadores que cita —`Get-ColoresRiesgo`, `FondoRiesgo`— **ya no existen**. Lo que queda es mover la paleta al XAML: ver `[INT-05]` en el plan |
> | `[R-05]` Recorrido cuadrático en carpetas vacías | ✅ Hecho |
> | `[R-06]` Descenso dentro de `node_modules` | ✅ Hecho: medido, de 291 ms a 21 ms |
> | `[R-07]` Coste de la guardia por candidato | ✅ Hecho (a) y (c): antepasados precalculados y expresiones compiladas |
> | `[R-04]` `Walk.ps1` con recorrido único | ⬜ Pendiente, con el margen ya medido: ver `[REN-30]` en el plan |
> | Recuento de pruebas y de módulos | ✅ Los números se han quitado de la documentación: quedaban obsoletos en cada PR |
>
> Lo demás sigue siendo válido como diagnóstico, pero **compruébalo contra el código antes de
> actuar**: este documento describe el proyecto tal y como estaba en agosto de 2026.

---

Auditoría completa del código de la versión 2.0.0. No es una lista de deseos: cada punto tiene archivo, línea, el cambio concreto y qué riesgo tiene hacerlo.

**Cómo leerlo.** Los `[C-nn]` son **correcciones**: el programa hace algo distinto de lo que dice. Los demás son mejoras. Dentro de cada bloque, el orden es por impacto real, no por facilidad.

**Método.** Lectura completa de los 61 archivos, medición con PowerShell 7.4 sobre árboles de prueba donde era medible, y verificación manual de cada afirmación contra el código. Los tiempos en microsegundos son de pwsh sobre Linux; en PowerShell 5.1 sobre NTFS el código con muchas llamadas a función va entre 1,5 y 3 veces más lento, pero las **proporciones** se trasladan. Los tiempos de la interfaz son estimaciones razonadas, no medidas: WPF no se puede ejecutar fuera de Windows.

**Nada de lo que sigue es un fallo de seguridad de la guardia.** El modelo de lista blanca, la revalidación en vivo y el comportamiento a prueba de fallos se han verificado y son correctos. Los problemas están en otras capas.

---

> **Nota (posterior).** Las entradas `[R-xx]` de rendimiento de este documento se han vuelto a analizar **con medidas reales** en [`RENDIMIENTO.md`](RENDIMIENTO.md), que es el plan vigente para velocidad. Varias estimaciones de aquí se quedaron cortas y al menos una propuesta —el índice compartido entre módulos— se descartó tras medirla. Este documento sigue siendo la referencia para las correcciones `[C-xx]`.

## Resumen: lo que cambiaría primero

| | Qué | Dónde | Ganancia | Estado |
|---|---|---|---|---|
| 1 | El borrado permanente está siempre activo para cachés | `Remove.ps1:111,114` | **Corrección** | ✅ Fase 1 |
| 2 | Duplicados puede proponer el único ejemplar de un archivo | `55-Duplicados.ps1` + `Config.ps1` | **Corrección crítica** | ✅ Fase 1 |
| 3 | Los comandos externos no se muestran nunca al usuario | `Remove.ps1:262` + `Types.ps1` | **Seguridad** | Fase 2 |
| 4 | 200 ms de espera por elemento eliminado | `Remove.ps1:279` | 100 s → 2 s en 500 elementos | ✅ Fase 1 |
| 5 | Un runspace nuevo por módulo, 18 arranques en frío | `Window.Analisis.ps1` | −3 a −8 s por análisis | Fase 3 |
| 6 | El ensamblado de tipos se recompila en cada arranque | `Types.ps1:20` | −1,2 a −3 s de arranque | Fase 3 |
| 7 | El disco de usuario se recorre 8-14 veces por análisis | 5 módulos | 25-40 min → 3-5 min | Fase 5 |
| 8 | Cifras multiplicadas por 100 en Windows en inglés | `80:60`, `75:34` | **Corrección** | ✅ Fase 1 |
| 9 | El filtro de resultados congela la interfaz 4-6 s | `Window.Ayudantes.ps1` | → 80 ms | Fase 3 |
| 10 | Los errores de los módulos se tragan en silencio | `Window.Ayudantes.ps1` | Diagnosticabilidad | ✅ Fase 1 |

---

# 1. Correcciones

Cosas que hacen algo distinto de lo documentado. Van primero porque ninguna optimización compensa un programa que miente.

### ✅ [C-01] El borrado permanente está siempre activo al vaciar cachés · `Remove.ps1:111,114`

`Clear-ContenidoCarpeta` declara `[switch] $Permanente`, lo propaga en la llamada recursiva de la línea 105… y **nunca lo lee**. Las líneas 111 y 114 hacen `Remove-Item -Force` incondicionalmente. Lo mismo en `Clear-CacheFirefox` y `Clear-Miniaturas`, que ni siquiera aceptan el parámetro.

Consecuencia: **todo candidato con método `Contenido`, `NpmClean`, `FirefoxCache` o `Miniaturas` se borra sin pasar por la papelera**, aunque el usuario tenga la casilla desmarcada. Eso es la mayoría de lo que el programa propone y de lo que viene premarcado. Contradice la cabecera del propio archivo (`Remove.ps1:8`) y la casilla de Ajustes.

**Cambio.** Extraer una primitiva `Remove-Elemento -Ruta -Permanente -EsCarpeta` con las dos ramas (papelera vía `Microsoft.VisualBasic.FileIO` / `Remove-Item`) y usarla en los tres sitios. `Remove-RutaSegura:57-69` ya tiene ese código duplicado literalmente, así que unificarlo mata también la duplicación.

**Aviso importante.** Arreglarlo *empeora* el tiempo: mandar 200.000 archivos de caché a la papelera es lentísimo y además la llena, con lo que no se libera espacio hasta vaciarla. La solución completa es un campo `ForzarPermanente` en el candidato que los módulos de caché activen explícitamente, y que el resto respete la preferencia del usuario. Así el comportamiento sigue siendo el actual **pero declarado**, que es la diferencia entre un diseño y un descuido.

**Riesgo.** Medio en tiempo, ninguno en datos.

### ✅ [C-02] Duplicados puede proponer borrar el único ejemplar de un archivo · `55-Duplicados.ps1:26,66` + `Config.ps1`

Tres vías, las tres verificadas en el código:

**(a) Zonas anidadas.** `Config.ps1` compone `ZonasUsuario` con Escritorio, Documentos, Imágenes… **y `OneDrive`**. Con OneDrive Known Folder Move activado —el caso por defecto en equipos OEM y cuentas Microsoft 365— `Get-CarpetaConocida 'Desktop'` devuelve `%USERPROFILE%\OneDrive\Escritorio`. `Select-Object -Unique` solo elimina duplicados **exactos**, no rutas contenidas, así que `OneDrive` y `OneDrive\Escritorio` conviven en la lista. Cada archivo se indexa dos veces con el mismo `FullName`; en la línea 66 `$copias[0]` y `$copias[1]` son **el mismo archivo**, y se emite un candidato cuyo `Info` dice "copia idéntica de sí mismo". Como `-PermitirPersonales` levanta el veto por extensión, la guardia lo aprueba. Borrarlo destruye el original.

**(b) Hardlinks NTFS.** Dos rutas al mismo contenido: mismo tamaño, mismo hash. `Test-EsEnlace` comprueba `ReparsePoint`, que un hardlink **no tiene**. Se propone borrar, no se libera un byte y el programa anuncia que sí.

**(c) Junctions.** El `-Recurse` de la línea 26 desciende por ellos (ver [R-08]), así que el mismo archivo aparece por su ruta real y por la del enlace.

**Cambio.** (1) Filtro de contención en `Config.ps1` tras el `Select-Object -Unique`: descartar toda zona que cuelgue de otra ya aceptada. (2) Deduplicar por ruta normalizada al insertar en `$porTamano`. (3) Antes de proponer, descartar si coinciden `(VolumeSerialNumber, FileIndex)` —obtenible con `fsutil hardlink list` o `GetFileInformationByHandle`.

**Riesgo.** Ninguno: solo deja de proponer. **Es el único escenario del programa en el que se pierde información irrecuperable.**

### ✅ [C-03] Los comandos externos nunca se muestran al usuario · `Remove.ps1:262` + `Types.ps1`

`SECURITY.md` afirma: *"El único comando externo es DISM o Docker, siempre declarado en el candidato, **siempre visible en la interfaz** y siempre con confirmación."*

Verificado: la cadena `Comando` **no aparece en ningún punto de la interfaz**. `ItemVista` no tiene ese campo (`grep Comando src/UI/` da cero resultados), el diálogo de confirmación lista nombre, tamaño y aviso, y los informes HTML/CSV/JSON tampoco lo incluyen. El usuario confirma "Limpiar imágenes de Docker sin usar" sin ver nunca `docker system prune -a -f`.

Encadenado con eso: `ModuleRegistry.ps1:127` exime al método `Comando` de la guardia (correcto: no hay ruta que validar), `Remove.ps1` no valida la cadena contra ninguna lista blanca, y se ejecuta a través de `cmd.exe /c`, que interpreta `&`, `|` y `%VAR%`. El uso actual es legítimo y son solo dos casos, pero el mecanismo es el único camino de ejecución de código del programa.

**Cambio, en cuatro partes.** (1) Añadir `Comando` a `ItemVista`, mostrarlo en monoespaciado en la fila cuando corresponda y listarlo íntegro en la confirmación. (2) Lista blanca de ejecutables (`dism`, `docker`), resolviendo DISM a su ruta absoluta bajo `System32`. (3) Sustituir `cmd.exe /c` por `Start-Process -FilePath -ArgumentList -Wait -NoNewWindow`, lo que elimina la interpretación del shell; exige que el candidato declare ejecutable y argumentos por separado, con solo dos usos que migrar. (4) Registrar siempre el comando y su código de salida con nivel `BORRADO`: hoy la salida va a `Write-Verbose` y se pierde.

**Riesgo.** Medio, ~60 líneas. Acompañar de un test que compruebe que ningún módulo declara un ejecutable fuera de la lista blanca.

### ✅ [C-04] Cifras multiplicadas por 100 en Windows en inglés · `80-ArchivosSistema.ps1:60`, `75-AlmacenComponentes.ps1:34`

```powershell
$numero = [double](($Matches[2] -replace '\.', '') -replace ',', '.')
```

La intención es tratar el punto como separador de miles, formato español. Pero `vssadmin list shadowstorage` en inglés devuelve `Used Shadow Copy Storage space: 15.5 GB`: se elimina el punto → `155` → **el programa afirma que los puntos de restauración ocupan 155 GB**.

**Cambio.** `[double]::TryParse` con `InvariantCulture` y caída a `es-ES`. Regla práctica: un separador seguido de 1-2 dígitos es decimal; seguido de exactamente 3, es de miles.

Extra en el mismo bloque: `80:68` hace `break` en la primera coincidencia, así que con varios volúmenes protegidos solo cuenta el primero e **infravalora**. Debe acumular.

### ✅ [C-05] La consulta a DISM nunca devuelve una cifra · `75-AlmacenComponentes.ps1:33`

La regex busca `reclaimable|recuperable` seguido de un número **con unidad**. La salida de `/AnalyzeComponentStore` no tiene ninguna línea así: la única con esa palabra es `Number of Reclaimable Packages : 0`, sin `KB|MB|GB`. `$recuperable` se queda siempre en 0.

Resultado: cuando DISM sí recomienda limpiar, el candidato sale con `-Bytes 0` y el texto literal *"DISM estima 0 B recuperables"*, lo que hace que el usuario descarte una acción que puede liberar varios GB.

**Cambio.** Parsear las líneas que sí llevan unidad —`Backups and Disabled Features` y `Cache and Temporary Data`—, cuya suma es la estimación real. Si nada casa, poner `Bytes 0` pero con un `Info` honesto: *"no se ha podido interpretar la salida de DISM"*.

### ✅ [C-06] La caché de Firefox siempre informa "0 bytes liberados" y un error falso · `10-Caches.ps1:129` + `Remove.ps1:281`

El candidato tiene `Bytes` = suma de los `cache2` (pongamos 400 MB) pero `Ruta` = la carpeta `Profiles` entera. Tras limpiar, `Remove.ps1:281` mide **toda** la carpeta de perfiles, que incluye `places.sqlite`, `cookies.sqlite` y las extensiones. Entonces:

- `400 MB − 600 MB` → negativo → se fuerza a **0**.
- `$restante > 1MB` → `Error = "Quedan 600 MB: archivos en uso por algún programa abierto."`

El usuario ve que la limpieza falló y liberó cero, cuando en realidad funcionó. Mismo problema, más leve, con el método `Miniaturas`.

**Cambio.** Añadir al candidato un campo `RutasMedidas` opcional (los `cache2` concretos) y que `Invoke-EliminacionCandidato` mida con el mismo criterio que usó el módulo para `$antes`.

### ✅ [C-07] `ZonasUsuario` puede ser una cadena en lugar de un array · `Config.ps1`

El `@(...)` envuelve el **literal**, no el resultado del pipeline. Si tras el `Where-Object` sobrevive **una sola** ruta, la asignación produce un `[string]` escalar.

Consecuencia concreta y comprobada: `45-AccesosRotos.ps1:14` hace `$Configuracion.ZonasUsuario + @(...)`. Con un escalar, `"C:\...\Desktop" + @('A','B')` **no concatena arrays, concatena cadenas**, produciendo una sola cadena basura que no pasa `Test-Path`. El módulo de accesos directos rotos **devuelve cero resultados en silencio**, sin error ni aviso. Solo se manifiesta en perfiles nuevos o con pocas carpetas presentes: justo las máquinas donde se prueba.

**Cambio.** `@( @(...) | Where-Object {...} | Select-Object -Unique )`. Y en el módulo 45, `@($Configuracion.ZonasUsuario) + @(...)`.

### ✅ [C-08] `Get-MotivoBloqueo` informa "Sin bloqueo" sobre rutas bloqueadas · `Guard.ps1:400`

`Test-RutaIntocable` tiene ocho comprobaciones. `Get-MotivoBloqueo` reimplementa seis y **omite tres**: la travesía con `..`, el veto del último segmento por carpeta personal y el veto de carpetas de copia de seguridad (verificado: cero coincidencias de esos tres patrones dentro de la función).

`Remove.ps1:244` compone `'Bloqueado por la guardia: ' + (Get-MotivoBloqueo ...)`. Para una ruta rechazada por cualquiera de esos tres filtros, el usuario lee literalmente **"Bloqueado por la guardia: Sin bloqueo."** en la única función cuyo propósito declarado es hacer auditable el programa sin leer el código.

**Cambio.** Eliminar la duplicación de raíz: `Get-MotivoIntocable` devuelve el motivo (cadena vacía = no bloqueado) y `Test-RutaIntocable` pasa a ser un envoltorio booleano. Así es imposible que las dos listas se desincronicen otra vez. Acompañar de un test que compare `Test-RutaIntocable $r` con `[bool](Get-MotivoIntocable $r)` sobre un corpus de 200 rutas.

**Riesgo.** Medio: es la guardia. Bajo si se hace con el test de equivalencia delante.

### ✅ [C-09] Carpetas vacías: el comentario dice lo contrario del código · `40-CarpetasVacias.ps1:28`

El comentario promete que *"una carpeta con solo subcarpetas vacías también cuenta como vacía, pero se propone el árbol de una vez"*. El código hace `Get-ChildItem -Recurse` y descarta si `Count -ne 0`: una carpeta que contiene una subcarpeta vacía devuelve 1 y **se descarta**. Solo se proponen las hojas, y hay que ejecutar el programa N veces para vaciar una cadena de N niveles.

**Cambio.** Recorrido post-orden que emita el antecesor común más alto sin archivos en todo el subárbol, y corregir el comentario. De paso deja de ser cuadrático ([R-05]).

### ✅ [C-10] Ramas muertas en la asignación de riesgo · `30-RestosProgramas.ps1:76`, `35-Descargas.ps1:54`

```powershell
$riesgo = if ($avisos.Count -gt 0) { 'Alto' } elseif ($dias -gt 365) { 'Medio' } else { 'Medio' }
$riesgo = if ($esComprimido) { 'Medio' } else { 'Medio' }
```

La escala se quedó a medio escribir en los dos sitios.

**Cambio.** En el 30, el `else` debería ser `'Alto'`: menos de un año sin tocar es *más* sospechoso de estar en uso, no menos. En el 35, `else { 'Bajo' }` —un instalador antiguo es de los candidatos más seguros del programa—, teniendo en cuenta que `Bajo` implica premarcado.

### ✅ [C-11] `-Silencioso` no se respeta en tres sitios · `Cli.ps1:65,136,162`

Tres `Write-Linea`/`Write-Cabecera` sin el guardia: el mensaje de "no hay ningún módulo", el error al guardar el informe y la cabecera "Eliminación". Rompe el uso en tareas programadas, que es para lo que existe la opción.

### ✅ [C-12] La agrupación de resultados se duplica al cambiar de tema · `Window.Ayudantes.ps1`

`GetDefaultView` devuelve **siempre la misma instancia** de vista para la misma colección. La línea 976 ya añadió la `PropertyGroupDescription`; la 335 la vuelve a añadir cada vez que se pulsa el botón de tema con la lista poblada. Resultado: agrupación anidada por la misma propiedad, dos niveles tras un cambio de tema, tres tras dos, con cabeceras repetidas.

**Cambio.** En `aplicarTema`, dejar solo `$estado.Vista.Refresh()`. Desaparece del todo si se aplica [U-03].

### ✅ [C-13] Los errores de los módulos se tragan en silencio · `Window.Ayudantes.ps1`

El runspace fija `$ErrorActionPreference = 'SilentlyContinue'` y **nadie lee `$ps.Streams.Error` nunca**. Un módulo que falle con un error no terminante —acceso denegado, ruta larga, disco desconectado— devuelve cero candidatos y la interfaz escribe *"nada que limpiar"*. El usuario cree que está limpio.

**Cambio.** `$ErrorActionPreference = 'Continue'` y, en `limpiarTrabajo`, si `$ps.HadErrors`, volcar las primeras N entradas al registro con nivel `AVISO`, agrupadas por tipo ("N rutas inaccesibles") para no ahogar la consola con los "acceso denegado" legítimos de cualquier recorrido de disco.

### ✅ [C-14] Accesos directos a red o USB desconectado se marcan como rotos, y premarcados · `45-AccesosRotos.ps1:38`

`Test-Path` sobre `\\NAS\media\...` con el NAS apagado, o sobre `E:\...` sin el USB puesto, devuelve `$false`. El candidato sale con riesgo `Bajo`, sin aviso y **preseleccionado**. El usuario limpia y pierde todos sus accesos al NAS.

**Cambio.** Descartar los destinos UNC sin juzgarlos, y para los de letra de unidad comprobar `DriveType` con `Win32_LogicalDisk`: si no es disco fijo, emitir con aviso explícito y sin preseleccionar.

**Es el falso positivo más probable de todo el programa, y encima está premarcado.**

### ✅ [C-15] Temporales de programas abiertos, premarcados · `50-Temporales.ps1:26,27`

- `~$*` casa los archivos de bloqueo que Word y Excel crean **mientras el documento está abierto**. Riesgo bajo, sin aviso, premarcado. El `Efecto` dice "sobra si el documento no está abierto" y el módulo **nunca comprueba si lo está**.
- `.crdownload`, `.partial`, `.download`: una descarga **en curso ahora mismo** se propone y se premarca.
- `.tmp`, `.temp`: sin ningún filtro de antigüedad.
- `*.~*` casa cualquier nombre con `.~` en cualquier posición, no solo la extensión.

**Cambio.** Filtro `LastWriteTime -lt (fecha).AddMinutes(-30)` para los tres primeros grupos, comprobación de procesos de Office para `~$*`, y restringir el último a `$_.Extension -like '.~*'`.

### ✅ [C-16] Los valores binarios del registro generan entradas de arranque inventadas · `90-Arranque.ps1:35`

`[string]$_.Value` sobre un `REG_BINARY` produce una cadena de números separados por espacios; `Get-EjecutableDeComando` la parte, `Test-EjecutableExiste` falla y se emite un candidato falso. Añadir `if ($_.Value -isnot [string]) { return }`.

Relacionado, en `Win32_Service`: las rutas con sintaxis NT (`\??\C:\...`, `\SystemRoot\...`) no las expande `ExpandEnvironmentVariables`, así que producen falsos "servicio roto" con riesgo Alto. Normalizarlas en `Ejecutables.ps1`.

### ✅ [C-17] `Test-EjecutableExiste` da falsos positivos por alias · `Ejecutables.ps1`

`Get-Command` sin `-CommandType Application` resuelve **alias, funciones y cmdlets**. Una entrada de arranque llamada `where`, `set`, `sc` o `start` se declara existente por coincidir con un alias de PowerShell. Además es el `if` más caro posible: recorre todo el `PATH`.

**Cambio.** `-CommandType Application`. Reduce falsos "existe", así que el módulo 90 propondrá **más** entradas rotas: verificar con casos reales antes.

### ✅ [C-18] "Espacio liberado" no es el medido, contra lo que dice el archivo · `Remove.ps1:250`

`$antes = if ($Candidato.Bytes -gt 0) { $Candidato.Bytes } else { ... }` usa el valor del **análisis**, que puede tener horas. La cabecera del archivo dice *"Se mide antes y después para informar del espacio REAL liberado, en vez de dar por bueno el tamaño estimado"*. Esas cifras alimentan el historial, así que el error se hace permanente.

**Cambio.** O se mide de verdad, o se renombra el campo a `BytesEstimados` y se corrige la cabecera. Dado [R-01], recomiendo lo segundo. Lo que no vale es que código y documentación digan cosas distintas.

### ✅ [C-19] El registro pierde líneas justo durante el borrado · `Log.ps1`

**Corregido en Fase 2.** Ver `CHANGELOG.md`.

El runspace de borrado y el hilo de la interfaz llaman ambos a `Write-Registro` sobre **el mismo archivo, sin ninguna sincronización**. Dos `Add-Content` simultáneos producen una violación de uso compartido que el `catch` de la línea 51 convierte en un `Write-Verbose` invisible. El registro de auditoría —cuyo propósito declarado es *"auditar exactamente qué se borró"*— pierde entradas de forma no determinista en el único momento que importa.

**Cambio.** Una `ConcurrentQueue[string]` en la hashtable sincronizada que ya existe, vaciada por el temporizador de la interfaz con un único `AppendAllLines`. Como mínimo, un mutex con nombre y **quitar el `catch` mudo**.

### ✅ [C-20] Ningún perfil ajusta los umbrales de archivos grandes ni de duplicados · `Profiles.ps1`

`Set-PerfilConfiguracion` solo escribe cuatro campos: `Perfil`, `DiasSinUso`, `MinimoMB` e `IncluirMenores`. Pero la configuración define además `MinimoGrandeMB` (250) y `MinimoDuplicadoMB` (5), que **sí se leen** —en `60-ArchivosGrandes` y `55-Duplicados`— y que **ningún perfil modifica**.

Consecuencia: el perfil Exhaustivo promete *"baja los umbrales"* y el módulo de archivos grandes sigue en 250 MB en los tres perfiles. La promesa de la interfaz no se cumple.

**Cambio.** Añadir los dos campos a la definición de cada perfil y escribirlos en `Set-PerfilConfiguracion`. Ojo también con `Permanente`: los cuatro perfiles lo definen a `$false`, así que ese campo del perfil tampoco hace nada hoy.

### ✅ [C-21] `Clear-Papelera -Unidad` es inalcanzable · `Remove.ps1`

El parámetro existe y se usa en el cuerpo (`Clear-RecycleBin -DriveLetter`), pero **ningún llamante lo pasa nunca**: la única llamada del programa es `Clear-Papelera -Confirm:$false`. Esa rama no se ejecuta jamás; siempre se vacía la papelera de todas las unidades.

**Cambio.** O se conecta de verdad (el módulo `papelera` sabe de qué unidad habla) o se borra el parámetro. Lo que no vale es dejar una capacidad que parece existir y no existe.

### ✅ [C-22] La barra de desplazamiento horizontal podría salir de 10 px · `Styles.xaml`

**Sin confirmar, hace falta verlo en ejecución.** El estilo de `ScrollBar` fija `Width="10"` como setter del propio `Style`, y luego intenta ponerlo en `Auto` desde un `Trigger` dentro de `ControlTemplate.Triggers` para la orientación horizontal. Por precedencia de WPF, un setter de estilo gana a un trigger de plantilla, así que la barra horizontal de la consola del panel Registro podría estar saliendo con 10 px de ancho.

**Cambio, si se confirma.** Mover ese trigger a `Style.Triggers`.

---

# 2. Rendimiento del análisis y del borrado

### ✅ [R-01] 200 ms de espera por cada elemento eliminado · `Remove.ps1:279`

`Start-Sleep -Milliseconds 200` dentro de `Invoke-EliminacionCandidato`, que se llama una vez por candidato. Con 500 elementos marcados —perfectamente alcanzable en perfil exhaustivo— son **100 segundos de sueño puro**, más que todo el borrado real. Con 2.000, seis minutos y medio.

La espera solo tiene sentido para que la medición posterior no cuente descriptores aún abiertos, y solo cuando la carpeta sobrevive. Para el método `Ruta` la carpeta ya no existe y no aporta nada.

**Cambio.** Condicionarla a los métodos que vacían contenido y bajarla a 50 ms; o eliminarla junto con la remedición ([C-18]).

**Ganancia.** 100 s → ~2 s en un lote de 500.

### [R-02] Un runspace nuevo por módulo · `Window.Analisis.ps1`

Cada módulo paga: crear y abrir el runspace (60-180 ms), dot-sourcear los 12 archivos del núcleo (120-250 ms), `Initialize-Guardia` (3-10 ms), y el cierre (15-50 ms). **200-500 ms por módulo sin analizar nada**, es decir **3,6-9 s de puro andamiaje** con los 18 activos, más hasta 3,6 s de latencia acumulada por el hueco de 200 ms del temporizador entre módulos. En perfil conservador, el andamiaje puede ser la mayor parte del tiempo total.

**Cambio, escalón 1 (recomendado).** Un runspace persistente creado al abrir la ventana con el núcleo ya cargado; `lanzarTrabajo` solo hace `SetVariable` y `AddScript`. Unas 30 líneas.

Tres cosas que hay que gestionar: fuga de estado entre módulos (envolver el trabajo en `& { ... }`), que `Stop()` deja el runspace en estado indeterminado y hay que detectar `RunspaceStateInfo.State -ne 'Opened'` y recrearlo, y que si el usuario cambia de perfil entre análisis hay que reenviar la configuración y volver a llamar a `Initialize-Guardia`.

**Ganancia.** −180 a −480 ms por módulo, **−3 a −8 s por análisis completo**.

**Escalón 2 (pool de 3-4), solo si se rediseña la sincronización.** `$estado.Sync` es **uno solo compartido**: con trabajos concurrentes, `Mensaje`, `Terminado`, `Resultado` y `Error` se pisan. Haría falta un `Sync` por trabajo y una cola concurrente que el temporizador drene. Los módulos son I/O-bound sobre rutas distintas, así que en SSD el tiempo de pared caería 2-3×; en disco mecánico puede empeorar. **Riesgo alto.**

Aparte: `CreateRunspace()` sin argumentos carga todos los snap-ins por defecto. `[initialsessionstate]::CreateDefault2()` ahorra 20-80 ms por runspace, pero **hay que importar explícitamente `Microsoft.PowerShell.Management`** o `Clear-RecycleBin` deja de existir.

### [R-03] El ensamblado de tipos se recompila en cada arranque · `Types.ps1:20`

`Add-Type -Language CSharp` lanza el compilador de C# del .NET Framework, escribe en `%TEMP%` y Defender escanea el DLL resultante: **1,2-3 s**, el coste unitario más grande del programa. Además no hay plan B si `%TEMP%` no es escribible.

**Cambio.** Compilar una vez a `%LOCALAPPDATA%\Cachivache\Cachivache.Tipos.<version>.dll` y cargarlo con `Add-Type -Path` en los arranques siguientes (~40 ms). El nombre lleva la versión, así que publicar una nueva invalida la caché sola.

**Riesgo.** Un DLL en `%LOCALAPPDATA%` es un vector de secuestro si un tercero lo sobrescribe. Mitigación honesta: comprobar el hash del `.cs` embebido, o distribuir el DLL firmado junto al repositorio con el `.cs` al lado para auditabilidad.

### [R-04] El disco de usuario se recorre entre 8 y 14 veces por análisis

Con el perfil exhaustivo, Escritorio y Documentos se recorren enteros por `proyectos`, `temporales`, `vacias`, `accesos`, `duplicados` y `grandes` —seis veces—, más el recorrido cuadrático de `vacias` ([R-05]) y el descenso dentro de `node_modules` ([R-06]). Con el anidamiento de OneDrive ([C-02a]), entre 13 y 14. **Ninguno de esos recorridos comparte una sola lectura de directorio con otro.**

**Cambio.** Un `src/Core/Walk.ps1` con recorrido único de pila explícita que publique un índice post-orden por directorio (`Bytes`, `Archivos`, `Ultimo`), y que los módulos se registren como **visitantes** en lugar de hacer su propio `Get-ChildItem -Recurse`. `temporales`, `vacias`, `grandes`, `accesos` y la primera fase de `duplicados` son filtros puros sobre el mismo flujo. El índice convierte además `Measure-Ruta` en O(1) para cualquier directorio ya visitado.

**Ganancia.** De 8-14 recorridos a **1**. En un perfil con 200.000 archivos, de 25-40 min a 3-5 min.

**Riesgo.** Alto en esfuerzo —reescribe seis módulos—, bajo en seguridad: la guardia no se toca y el contrato de candidato no cambia. Se puede hacer por fases: primero el índice de tamaños, que ya arregla las mediciones redundantes sin tocar los módulos.

### ✅ [R-05] Recorrido cuadrático en carpetas vacías · `40-CarpetasVacias.ps1:30`

Un `Get-ChildItem -Recurse` completo **por cada directorio encontrado**. Con 20.000 directorios y profundidad media 5 son del orden de un millón de enumeraciones: **10-25 minutos en un solo módulo**.

**Cambio inmediato de una línea:** sustituir el `-Recurse` por una comprobación no recursiva que corte en el primer elemento (`| Select-Object -First 1`). **Cambio correcto:** el recorrido post-orden de [C-09].

### [R-06] `20-Proyectos` desciende dentro de cada `node_modules` · `20-Proyectos.ps1:42`

`Get-ChildItem -Recurse -Directory` enumera **todo** el interior de cada `node_modules` —decenas de miles de directorios— para después descartar los anidados con una regex. El filtro se aplica al resultado, no a la travesía.

**Cambio.** Recorrido con poda: al encontrar una carpeta que casa el patrón inequívoco, emitirla y **no descender**.

**Ganancia.** Con diez proyectos Node, de ~300.000 directorios a ~5.000. **Probablemente el mayor ahorro de una sola línea del proyecto.**

Relacionado: la exclusión actual solo evita `node_modules` dentro de `node_modules`. Los `dist`, `build` y `lib` de cada paquete npm sí pasan el filtro de manifiesto —todo paquete publicado lleva su `package.json`—, así que se proponen cientos de subcarpetas **además** del `node_modules` que las contiene, y **los mismos bytes se suman dos veces** en el total que ve el usuario.

### [R-07] La guardia cuesta 300 µs por candidato y se ejecuta dos o tres veces · `Guard.ps1`

Desglose medido de `Test-RutaSegura`: `Test-RutaIntocable` 42 µs, `Test-BajoRaiz` 92 µs, `Get-Item` 83 µs, `Test-ArchivoPersonal` 73 µs.

**(a) El bucle "es antecesora" es innecesario** (`:222`). `$protegida.StartsWith($r + '\')` es cierto si y solo si `$r` es ancestro estricto. Se puede precalcular en `Initialize-Guardia` un `HashSet` con las rutas protegidas **más todos sus ancestros** y sustituirlo por un `Contains` O(1). Verificado: el conjunto resultante tiene 33 entradas y da **cero discrepancias** sobre una muestra de 16 rutas representativas.

**(b) Dos llamadas a función dentro de la función más caliente** (`:207,210`). Una llamada con `[CmdletBinding()]` cuesta 11-16 µs de puro despacho; entre `Test-GuardiaLista` y `ConvertTo-RutaNormalizada` se van **19 de los 42 µs**. Insertarlas en línea, manteniendo las funciones públicas para el resto del código.

**(c) Cuatro regex interpretadas por llamada.** Precompilar con `RegexOptions.Compiled` en `Initialize-Guardia`. De paso se evita el efecto secundario de `-match` sobre `$Matches`.

**Medido, (a)+(b)+(c) juntos: 41,7 µs → 13,5 µs. 3,1× en régimen, 5,7× en frío, cero discrepancias.**

**(d) `Test-BajoRaiz` renormaliza las raíces en cada llamada** (`:339`). Las raíces son constantes durante todo el módulo, pero se renormalizan, se les concatena `'\'` y se comparan con **cultura** cada vez. Cachear los prefijos por referencia de array: **92,3 µs → 18,0 µs, 5,1×**.

El cambio a `StringComparison::Ordinal` **es además una mejora de seguridad**: `Test-BajoRaiz` es la lista blanca, la comparación que *autoriza* el borrado. Con comparación de cultura, ciertos caracteres ignorables de Unicode pueden hacer que `StartsWith` devuelva cierto para una cadena que no es prefijo literal. Una decisión de autorización debe ser ordinal, siempre.

**Total: la parte de cadenas pasa de ~207 µs a ~52 µs.** Sobre 10.000 candidatos validados dos veces, unos 10 s → 2,5 s en PowerShell 5.1.

### [R-08] Ningún recorrido está protegido contra bucles de junction

Afecta a `Measure-Ruta`, `Measure-RutaDetalle`, `Registry.ps1`, `Remove.ps1:100` y los módulos 20, 25, 30, 35, 40, 45, 50, 55, 60, 85.

En **Windows PowerShell 5.1** el proveedor de sistema de archivos **sí desciende por los junctions de directorio**; el cambio llegó en PowerShell Core 6. Los módulos comprueban `Test-EsEnlace` sobre el **resultado**, es decir, después de que el recorrido ya haya bajado. Un usuario con `Documentos\Espejo → C:\` provoca un recorrido del disco entero; un ciclo provoca recursión hasta agotar `MAX_PATH`, y con `-ErrorAction SilentlyContinue` **no se entera nadie**.

Consecuencias: el recorrido se repite perdiendo minutos sin señal, y `Measure-Ruta` cuenta el mismo contenido varias veces e infla el tamaño anunciado.

**Cambio.** Recorrido de pila explícita que compruebe `ReparsePoint` **antes** de encolar, con un `HashSet` de directorios visitados. Mitigación barata mientras tanto: `-Depth 12` en los recorridos de zonas de usuario.

**Ganancia adicional, y no menor:** un `Get-ChildItem -Recurse` sobre `C:\Users\x` **no se puede cancelar**. Hoy el botón Cancelar no hace nada hasta que termine. El recorrido manual permite comprobar la cancelación dentro del bucle y reportar progreso.

### [R-09] `Measure-RutaDetalle` recorre la colección tres veces y ordena para sacar un máximo · `FileSystem.ps1`

El `@()` materializa **todos** los `FileInfo` —una carpeta de AppData con 50.000 archivos son 30-50 MB de objetos vivos—, luego `Measure-Object` los recorre, y luego `Sort-Object` hace un O(n log n) completo solo para obtener el más reciente.

**Medido con 1.100 archivos: 30,56 ms. Una sola pasada con `foreach`: 12,14 ms.** El pico de memoria pasa de O(n) a O(1).

*Nota sobre `[IO.Directory]::EnumerateFiles`, que sería 12×:* **no sirve en PowerShell 5.1.** En .NET Framework lanza `UnauthorizedAccessException` y **aborta la enumeración entera** al primer directorio sin permisos; `EnumerationOptions.IgnoreInaccessible` es .NET Core 2.1+. En AppData eso pasa siempre.

### [R-10] `Test-TokenConocido` recorre el HashSet entero por carpeta · `Registry.ps1`

O(carpetas × tokens). Un equipo real produce 2.000-4.000 tokens; el módulo 30 itera 300-400 carpetas. **Medido: 1,69 ms por llamada → 0,6 s en pwsh, 1,5-2 s en PowerShell 5.1**, solo en ese bucle, y crece con lo que el usuario tenga instalado.

**Cambio.** Partir la condición en sus dos direcciones: la subcadena "el token está en algún conocido" se resuelve con una sola búsqueda en un blob precalculado (`|token1|token2|…`, seguro porque `ConvertTo-Token` solo deja `[a-z0-9]`); la inversa, probando las subcadenas del token contra el HashSet. **Medido: 1,69 ms → 0,46 ms, 3,7×.**

**Observación de diseño, más importante que el rendimiento.** El umbral de 4 caracteres con coincidencia **bidireccional** hace la heurística tan laxa que casi nada pasa el filtro: `Code` casa con `vscode`, `java` con cualquier token que lo contenga, `data` con `metadata`. Con miles de tokens, la probabilidad de que una carpeta cualquiera no sea subcadena de ninguno es muy baja. **El módulo 30 probablemente no propone casi nada.** Es el sesgo seguro, pero conviene saberlo: exigir longitud ≥6 y una sola dirección lo haría útil, a costa de más falsos positivos en el módulo más peligroso.

### [R-11] `$_.Company` abre cada ejecutable del sistema · `Registry.ps1`

`Process.Company` fuerza a leer `MainModule.FileVersionInfo`: abrir el ejecutable en disco y parsear su recurso de versión, **por cada proceso**. Con 200-300 procesos son 200-300 aperturas de archivo: **1-3 s**, la línea más lenta de la función.

**Cambio.** Eliminarla —aporta poco vocabulario frente a `ProcessName` más los fabricantes de los desinstaladores— o usar `Get-CimInstance Win32_Process`, que ya trae la ruta sin abrir nada.

### [R-12] `Get-EspacioLibre` abre una sesión WMI en cada llamada · `FileSystem.ps1`

Se llama desde siete sitios, uno de ellos en el manejador que se dispara al terminar cada borrado. Cada llamada abre una sesión CIM/DCOM: **50-200 ms en frío**.

**Cambio.** `[IO.DriveInfo]::new($Unidad).AvailableFreeSpace` es una llamada directa a `GetDiskFreeSpaceEx`, del orden de microsegundos. Y `AvailableFreeSpace` es **más correcto** que el `FreeSpace` de WMI porque respeta las cuotas de usuario. **Elimina además una inyección de cadena en el filtro WQL** (`"DeviceID='$Unidad'"`): hoy es inofensiva porque el valor viene de `$env:SystemDrive`, pero es un patrón que no debería estar ahí.

### [R-13] Mediciones caras en módulos que no borran nada

- `70-WindowsUpdate.ps1:58` mide `C:\Windows.old` entero —200-400k archivos, muchos con ACL denegada— para un candidato **informativo** que el programa declara que no va a tocar. **1-3 minutos** en cualquier equipo recién actualizado.
- `95-PerfilesUsuario.ps1:28` mide perfiles ajenos completos, decenas de GB cada uno, también informativo.
- `75-AlmacenComponentes.ps1:46` mide WinSxS, que es en su práctica totalidad **hardlinks** a System32: sumar `Length` cuenta los mismos bytes físicos entre 5 y 10 veces. **La cifra es incorrecta por construcción**, además de costar minutos. DISM ya da el tamaño real del almacén en su propia salida.

**Cambio.** Estimación a profundidad 1-2 y etiquetarla como aproximada, o `robocopy /L /S /BYTES` (5-20× más rápido y sin problemas con rutas largas), o simplemente `-Bytes 0` con el aviso.

### [R-14] `85-DockerWsl` recorre todo `LOCALAPPDATA\Packages` · `85-DockerWsl.ps1:23`

`Packages` contiene el `LocalCache` de todas las apps de la Store: decenas de miles de archivos recorridos para encontrar cero o dos `.vhdx`.

**Cambio.** Leer `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*` → `BasePath`, que da la ruta exacta de **todas** las distribuciones, incluidas las importadas fuera del perfil y las instaladas con `wsl --install` moderno en `%LOCALAPPDATA%\wsl\{GUID}\ext4.vhdx` —que el código actual **no encuentra**. De 30-90 s a menos de 1 s, y deja de perder distros.

### [R-15] Medir antes de filtrar · `10-Caches.ps1:80`, `65-LogsSistema.ps1:32`, `70-WindowsUpdate.ps1:42`

En los tres, `Measure-Ruta` se ejecuta **antes** de `Test-RutaSegura`. Si la guardia va a vetar la ruta, el recorrido se ha hecho para nada. Invertir las dos líneas es gratis.

Lo mismo en `30-RestosProgramas.ps1:58`: se recorre la carpeta entera y **después** se descarta por antigüedad, que es lo que descarta el 60-80 % de las carpetas de AppData. Cribar primero por la fecha del propio directorio.

### [R-16] Tres recorridos completos por carpeta candidata · `30-RestosProgramas.ps1:58,67,72`

`Measure-RutaDetalle` recorre entera la carpeta, la línea 67 la vuelve a recorrer buscando directorios valiosos, la 72 una tercera vez buscando extensiones personales, y la 69 una cuarta por cada subcarpeta valiosa. Un solo `Get-ChildItem -Recurse` puede alimentar las tres decisiones: **3-4×**, la diferencia entre dos minutos y treinta segundos.

### [R-17] Duplicados hashea archivos enteros para descartarlos · `55-Duplicados.ps1:55`

Dos vídeos de 4 GB que casualmente miden lo mismo → **8 GB leídos** para descubrir que son distintos.

**Cambio.** Prehash parcial: leer los primeros y últimos 64 KB y solo si coinciden calcular el SHA-256 completo. En el caso típico se leen 128 KB en lugar de 8 GB, y el hash completo sigue decidiendo. Además, la barra de progreso cuenta grupos, no bytes: con archivos grandes parece congelada.

### [R-18] Costes menores pero repetidos en rutas calientes

| Dónde | Problema | Medido | Cambio |
|---|---|---|---|
| `Format.ps1` | `Get-RutaCorta` compila una regex por llamada para una sustitución literal | 54,1 → 17,1 µs | `String.Replace` con el perfil izado a `$script:`. Ojo: pasa a ser sensible a mayúsculas; es cosmético |
| `Texto.ps1`, `50-Temporales.ps1:53` | `Get-Date` (cmdlet) en bucles; en el módulo 50, **por archivo del perfil entero** | 29,0 → 12,1 µs | `[datetime]::Now` e izar la fecha fuera del bucle. **~1,7 s sobre 100.000 archivos** |
| `Format.ps1` | `ConvertTo-Token` hace cuatro pasadas y asigna cuatro cadenas | 67,1 → 45,6 µs | Una sola pasada con `StringBuilder`. Se llama >10.000 veces por análisis |
| `Report.ps1:174` | `ConvertTo-HtmlSeguro` es una función PS llamada 7 veces por fila | 35,6 → 14,5 µs | Llamar al método estático en el bucle. **1,5 s con 10.000 candidatos** |
| `FileSystem.ps1` | `Get-Process` enumera la tabla completa **una vez por nombre** | 243 µs × 8 | Una enumeración y un `HashSet` |
| `Guard.ps1:295,299` | `ToLowerInvariant()` redundante: `-contains` ya es insensible a mayúsculas | 73 → 45 µs | `HashSet` con `OrdinalIgnoreCase` |
| `Candidate.ps1:93` | `Raices = @($Raices)` copia el array por candidato | ~700 KB con 10.000 | Quitar el `@()`: el parámetro ya está tipado |
| `Registry.ps1` | `Get-ItemProperty` lee 15-30 valores por clave para usar 3 | 3-5× | `-Name DisplayName, Publisher, InstallLocation` |
| `Registry.ps1` | `Split-Path -Leaf` en un bucle | 100,7 → 16,7 µs | `[IO.Path]::GetFileName` |
| `Config.ps1` | `Get-CarpetaDatos` hace 3 `Test-Path` y 3 `New-Item` **en cada llamada**, y se usa como valor por defecto en seis funciones | ~150 µs × N | Memoizar |
| `Log.ps1` | `Get-ResumenHistorial` vuelve a leer y parsear el JSON que el llamante acaba de leer | 30-80 ms × 3 refrescos | Aceptar `-Historial` ya leído |
| `Remove.ps1:236` | Cinco `stat` por elemento borrado (`Test-Path` + guardia + `Remove-RutaSegura` + doble medición) | 5 → 2 | Quitar el `Test-Path` redundante y pasar el `$item` ya obtenido |
| `Remove.ps1:109` | Cada directorio se enumera dos veces: una para vaciarlo, otra para comprobar que quedó vacío | ~2× en árboles profundos | Que la recursión devuelva los elementos no borrados |
| `Report.ps1:161` | La suma de cada grupo se calcula una vez para ordenar y otra para imprimir | 2× | Calcular una vez a un array de tuplas |
| `FileSystem.ps1` | `Test-Path` seguido de `Get-Item`, que ya devuelve `$null` si no existe. Además el `Test-Path` va **sin `-Force`**, así que un archivo oculto devuelve 0 bytes | 45 % de la ruta rápida | Borrar la línea |

### [R-19] Rutas de más de 260 caracteres

No hay una sola aparición de `\\?\` en `src/`. En PowerShell 5.1, `Get-Item`, `Test-Path`, `Get-ChildItem` y `Remove-Item` fallan por encima de `MAX_PATH`. Consecuencias en cadena, todas silenciosas: `Measure-Ruta` **infravalora** cualquier árbol con `node_modules` —que es exactamente el caso de uso de `20-Proyectos`—; `Test-RutaSegura` devuelve falso porque `Get-Item` da `$null` y el candidato **se descarta sin avisar**; y `Clear-ContenidoCarpeta` deja archivos atrás, tras lo cual el usuario ve *"Quedan X: archivos en uso"*, que es un **diagnóstico erróneo**.

**Cambio.** Una función que anteponga `\\?\` (o `\\?\UNC\`) por encima de ~248 caracteres, usada en los `-LiteralPath` de medición y borrado, **nunca** en la ruta que se muestra ni en la que se guarda en el candidato.

**Riesgo.** Medio. El prefijo desactiva la normalización de Windows: no admite `/`, ni `.`, ni `..`. La guardia normaliza y rechaza `..` antes, así que las precondiciones se cumplen, pero el prefijo debe aplicarse **después** de la guardia, jamás antes: una ruta con `\\?\` se saltaría el filtro de recurso de red. Alternativa barata: al menos **contar y reportar** los `PathTooLongException` en lugar de tragarlos.

### [R-20] Ningún límite de candidatos

`temporales`, `duplicados`, `grandes`, `accesos` y `vacias` emiten un candidato por archivo o carpeta, sin tope. Cada uno es un `[pscustomobject]` de 15 propiedades que acaba en una `ObservableCollection` de WPF. Con 200.000 archivos en Documentos, el análisis produce del orden de **15.000 candidatos y supera 1,5 GB de memoria en los picos**.

**Cambio.** Un `MaximoCandidatos` por módulo (p. ej. 2.000); al alcanzarlo, agregar el resto en un candidato de resumen por carpeta padre: *"1.847 archivos .tmp más en ~\Documentos\…, 340 MB"*. Es además **mejor información** que 20.000 filas de 2 KB.

### [R-21] Fases largas que no se pueden cancelar

`55-Duplicados.ps1:32` (recolección), `25-Papelera.ps1:24` (recorrido de la papelera) y `75-AlmacenComponentes.ps1:22` (DISM, 1-5 minutos bloqueantes sin timeout) no comprueban la cancelación dentro del bucle. Añadir la comprobación en los dos primeros es una línea; DISM necesita `Start-Process -PassThru` con sondeo y `Kill()`. Matar DISM durante un *análisis* es seguro.

---

# 3. Interfaz

### [U-01] El filtro congela la ventana 4-6 segundos · `Window.Ayudantes.ps1`

Cada pulsación dispara `Refresh()` sobre una vista **agrupada**, con un predicado construido desde un scriptblock: **cada invocación monta un pipeline de PowerShell** (~100 µs). Con 5.000 filas, escribir "chrome" son 4-6 s de interfaz congelada. Y `GetNewClosure()` crea un scriptblock nuevo cada vez, así que no hay ni caché de delegado.

Aparte, `-like "*$texto*"` **no escapa los comodines**: si el usuario escribe `[`, el filtro se rompe en silencio.

**Cambio, tres cosas juntas.** (1) Debounce de 250 ms con un `DispatcherTimer`. (2) Predicado en C# dentro de `Types.ps1`, con `IndexOf(..., OrdinalIgnoreCase)` en lugar de `-like`: delegado nativo, ~0,1 µs por fila. (3) Opcionalmente, filtrado incremental cuando el texto nuevo empieza por el anterior.

**Ganancia.** De 4-6 s a **menos de 80 ms** por búsqueda completa.

### [U-02] El resumen recorre los 5.000 elementos en cada clic de casilla · `Window.Ayudantes.ps1`

`Where-Object` sobre 5.000 objetos son 50-120 ms por clic. El `SuprimirResumen` tapa el marcado en lote pero **no el clic individual**, que es el uso normal.

**Cambio.** Contadores incrementales en el manejador (`$estado.MarcadosCount++`, `$estado.MarcadosBytes += ...`) y recuento completo solo al terminar análisis, terminar borrado y salir del marcado en lote. Mejor aún, el agregado en C# con una clase que se suscriba una sola vez.

**Ganancia.** De ~100 ms a menos de 1 ms por casilla.

Relacionado: `$item.add_PropertyChanged($manejadorSeleccionGlobal)` convierte el scriptblock a delegado **en cada llamada** —PowerShell no cachea la conversión—, así que poblar la lista crea 5.000 wrappers, cada uno arrastrando su `SessionState`. Mover el agregado a C# elimina eso y de paso hace posible desenganchar, que hoy no lo es.

### [U-03] Los colores de riesgo viajan como cadenas · `Window.ps1` + `Types.ps1:88`

`FondoRiesgo` y `ColorRiesgo` son `string` sin notificación, así que WPF invoca el `BrushConverter` **por celda realizada** y otra vez en cada scroll con virtualización por reciclado. Y como no notifican, cambiar de tema obliga a reasignar `ItemsSource`, que destruye y reconstruye todos los contenedores y los grupos —y provoca [C-12].

**Cambio.** Eliminar `Get-ColoresRiesgo` entero. Definir seis brushes en cada archivo de tema y un estilo con `DataTrigger` sobre `Riesgo` en `Styles.xaml`. El cambio de tema pasa a ser **instantáneo y sin tocar la lista**, porque `DynamicResource` se re-resuelve solo.

**Es el cambio con mejor relación beneficio/esfuerzo de toda la interfaz:** arregla un bug, quita una conversión por celda y elimina tres bloques de código imperativo.

### [U-04] `lanzarTrabajo` sin `try/catch` deja un estado sin salida · `Window.Analisis.ps1`

Si `Open()` o `BeginInvoke()` lanzan —memoria, límite de hilos, política—, no se ejecuta `$temporizador.Start()`, `$estado.Ocupado` se queda en cierto **para siempre** y el runspace queda sin liberar. La interfaz se queda con "Analizar" deshabilitado, "Cancelar" visible y nada avanzando. Solo se sale cerrando el programa.

### [U-05] Cerrar durante un borrado · `Window.Eventos.ps1`

Tres problemas a la vez. El manejador de `Closing` **no declara `param($s,$e)`**, así que es imposible cancelar el cierre. `PowerShell.Stop()` es **bloqueante**: si el runspace está midiendo una carpeta de 200.000 archivos, la ventana se congela al cerrar. Y si se estaba borrando, **`Add-EntradaHistorial` nunca se escribe**: se pierde la traza de auditoría de esa ejecución, aunque las líneas por elemento del `.log` sí sobrevivan.

**Cambio.** Declarar los parámetros del evento, preguntar al usuario si hay un borrado en curso, escribir el historial parcial **antes** de matar el runspace, y usar `BeginStop` (asíncrono) solo en fase de análisis, nunca en borrado.

### [U-06] Arranque: nada indica que el programa está vivo · `Window.Eventos.ps1`

Entre 3 y 6 segundos sin ninguna señal. El usuario que hace doble clic ve una consola negra y nada más.

**Cambio.** Una ventana de carga mínima antes de compilar los tipos: un `XamlReader.Parse` de 15 líneas cuesta menos de 20 ms y convierte la percepción de 4 s en 200 ms. Cerrarla **antes** de `Run()` por el `ShutdownMode`.

Otros costes de arranque evitables: `Get-UnidadesFijas` se ejecuta **dos veces** (`New-Configuracion` y `refrescarDiscos`), más un tercer `Get-EspacioLibre`, más `Win32_OperatingSystem`: cuatro viajes a WMI antes de ver nada. `MainWindow.xaml` monta los **seis paneles** aunque cinco arranquen colapsados. Y `Get-ModulosLimpieza` dot-sourcea 18 archivos para pintar 18 tarjetas cuando solo necesita los metadatos —y el `Buscar` que carga **no se usa nunca en modo ventana**, porque el runspace vuelve a cargar el archivo por su cuenta. Una caché JSON de metadatos invalidada por fecha y tamaño son 30 líneas.

### [U-07] Accesibilidad: nada implementado

Verificado sobre el XAML completo:

- **Cero atajos de teclado.** Ni `Ctrl+F` para filtrar, ni `F5` para analizar, ni `Esc` para cancelar, ni `Espacio` para marcar.
- **Cero `AutomationProperties`.** Un lector de pantalla no puede describir la ventana.
- **Ningún `ControlTemplate` tiene indicador de foco.** Navegar con Tab es invisible: cinco plantillas afectadas.
- **El orden de tabulación arranca en la barra de título.**
- **`SelectionMode="Extended"` sin ninguna acción de multiselección**: se pueden seleccionar 200 filas y no hay forma de marcarlas.
- **No se puede ordenar por ninguna columna**: falta `SortMemberPath`.
- **Sin menú contextual** en la lista.
- **Sin estados vacíos**: tres sitios donde una lista vacía muestra un hueco en blanco sin explicación.
- **Contraste AA fallido en dos botones**: blanco sobre el azul de acento da 3,20:1 y blanco sobre el rojo de peligro da 3,01:1, frente al 4,5:1 exigido. El segundo es el botón de *Eliminar*. El estado deshabilitado con `Opacity 0.35` deja el texto en ~1,3:1.
- **A 1024×768 la ventana no cabe**: nace 216 px más ancha que la pantalla, y a 125 % de escalado el `MinWidth` de 1020 DIP son 1275 px físicos, con lo que el pie con el botón de analizar puede quedar fuera.
- **La columna "qué pasa si se borra" recorta el texto** con `RowHeight` fijo de 52 px y tres `TextBlock` apilados; a 150 % de escalado recorta siempre.
- **El diálogo de confirmación** compara con `-ceq` (sensible a mayúsculas) sin decirlo en ninguna parte.

**Ninguno de estos puntos es difícil.** El foco visible y los atajos son media tarde y cambian por completo la sensación de acabado.

### [U-08] Modo consola y lanzador

- **`Cachivache.bat`** no usa `-WindowStyle Hidden`: el usuario acaba con **dos entradas en la barra de tareas** y una consola negra que si cierra, mata el programa.
- **`-ExecutionPolicy Bypass` no salta las políticas de GPO.** En un equipo corporativo el `.bat` falla y luego imprime *"revisa el registro"* —registro que nunca llegó a crearse—. Detectar `MachinePolicy`/`UserPolicy` y dar un mensaje real.
- **`cd /d` falla en rutas UNC.** Usar `pushd`/`popd`.
- **Códigos de salida sin semántica**: solo 0 y 1. Para automatizar hacen falta códigos distintos para "nada encontrado", "cancelado", "error de módulo", "faltan permisos".
- **Falta `Unblock-File` en la documentación.** Al descomprimir un ZIP descargado, los `.ps1` llevan Mark-of-the-Web.
- **`$env:OS -ne 'Windows_NT'`** y `PSVersion.Major -lt 5` aceptan PowerShell 5.0 y Windows 7, cuando el README promete 5.1 y Windows 10.

---

# 4. Cobertura de detección

Lo que el programa no encuentra hoy y podría. Ordenado por espacio típico recuperable.

### [D-01] IA y modelos: el hueco más grande de 2024-2026

| Ruta | Típico | Nota |
|---|---|---|
| `%USERPROFILE%\.cache\huggingface\hub` | **20-200 GB** | Respetar `HF_HOME` si está definida. Se re-descarga |
| `%USERPROFILE%\.ollama\models\blobs` | **10-100 GB** | **No es caché.** Informativo: re-descargar 40 GB no es "sin efecto" |
| `%USERPROFILE%\.cache\lm-studio\models` | 10-100 GB | Igual, informativo |
| `%USERPROFILE%\.cache\torch\hub\checkpoints` | 2-20 GB | Pesos preentrenados |
| `%LOCALAPPDATA%\NVIDIA\ComputeCache` | 1-5 GB | CUDA JIT, se regenera |

Es hoy la categoría que más disco ocupa en máquinas de desarrollo y **no se detecta nada de ella**. Los modelos descargados deben ser informativos, nunca premarcados.

### [D-02] Motores de juego y creación audiovisual: nada detectado

`%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache` (**50-200 GB**), `Library` y `Temp` de cada proyecto Unity (**5-50 GB cada uno**), `%LOCALAPPDATA%\Unity\cache`, `%APPDATA%\Unity\Asset Store-5.x`, la caché de Fusion de DaVinci Resolve (**10-100 GB**), el Disk Cache de After Effects, `%APPDATA%\obs-studio\logs`.

`Library`, `Intermediate` y `DerivedDataCache` encajan en `20-Proyectos` como ambiguos, añadiendo `ProjectSettings\ProjectVersion.txt` y `*.uproject` a la lista de manifiestos. `Library` de Unity regenera en 10-40 minutos de importación: riesgo medio con aviso, nunca premarcado.

### [D-03] Gestores de paquetes y toolchains modernos

Faltan **bun** (`~\.bun\install\cache`), **uv** (`%LOCALAPPDATA%\uv\cache`), **Deno**, **Yarn Berry**, **Poetry**, **Conda** (`~\.conda\pkgs`, 5-20 GB), **Go modules** (`~\go\pkg\mod`, 5-30 GB, archivos de solo lectura: encaja con el método `Comando` y `go clean -modcache`), la **caché de instaladores de Visual Studio** (`%LOCALAPPDATA%\Microsoft\VisualStudio\Packages`, **10-30 GB**), `NuGet\v3-cache`, `.pub-cache` y la caché de Flutter.

Y en `20-Proyectos` faltan los patrones `.vs`, `.dart_tool`, `.terraform`, `.expo`, `.astro`, `.vite`, `.nx`, `bower_components`, `.eggs`.

Además, **`pnpm-cache` es el layout antiguo**: hoy es `%LOCALAPPDATA%\pnpm\store`.

### [D-04] Android y emuladores

AVDs (`~\.android\avd\*.avd`, **8-25 GB por dispositivo**), imágenes de sistema del SDK (10-40 GB), NDKs antiguos. **Android Studio no se detecta**: el bucle de JetBrains mira solo `%LOCALAPPDATA%\JetBrains` y Android Studio cuelga de `Google`. Generalizarlo a ambas raíces es una línea. Los AVDs contienen el estado del dispositivo virtual del usuario: informativos.

### [D-05] Navegadores: faltan las cachés fuera de los perfiles

El bucle actual solo mira dentro de cada perfil, así que nunca ve `User Data\ShaderCache` (más de 1 GB con juegos web), `GrShaderCache`, `component_crx_cache` ni `Crashpad\reports`. Falta también `optimization_guide_model_store` (modelos de IA locales de Chrome y Edge, 200 MB-1,5 GB por perfil). Y faltan navegadores: Arc, Zen, LibreWolf, Floorp.

De Firefox solo se toca `cache2`: faltan `startupCache`, `jumpListCache` y `%LOCALAPPDATA%\Mozilla\updates`, donde se acumulan los instaladores de actualización.

### [D-06] Juegos y tiendas

`<Steam>\steamapps\downloading` (**hasta 100 GB** de descargas a medias) y `shadercache`, con la ruta obtenible de `HKCU:\Software\Valve\Steam` → `SteamPath` y las bibliotecas extra de `libraryfolders.vdf`. Battle.net, EA Desktop, Riot, la caché de Game Pass. Y falta `%LOCALAPPDATA%\Intel\ShaderCache`, cuando AMD y NVIDIA sí están.

### [D-07] Restos de actualización de Windows

`C:\$WinREAgent` (1-5 GB), `C:\$Windows.~BT` y `~WS` (5-10 GB), `C:\ESD`, `%SystemRoot%\Temp`, `%SystemRoot%\Logs\MoSetup`. Y dos informativos que hoy no aparecen en ningún sitio: **`Windows.edb`**, el índice de búsqueda (**5-25 GB**, reconstruible desde el Panel de control) y `C:\Windows\Installer` (5-20 GB, que no se debe tocar a mano).

`45-AccesosRotos` no mira `%APPDATA%\Microsoft\Windows\Recent`, que estadísticamente es **el sitio con más `.lnk` rotos del equipo**.

### [D-08] Clasificación `Menor` incorrecta en las cachés más grandes · `10-Caches.ps1:25,27,28,29,30`

Están marcadas como "suele ocupar poco" —y por tanto ocultas fuera del perfil exhaustivo— `.m2\repository` (1-10 GB), `.nuget\packages` (3-15 GB), `.cargo\registry` (1-8 GB), `go-build` (1-5 GB) y `Composer`. Mientras tanto `pip\Cache`, que suele ser diez veces menor, está como no-menor.

**Cambio.** Eliminar el campo `Menor` y decidir por el tamaño medido contra `MinimoMB`, que es lo que ya hacen todos los demás módulos. Elimina un juicio codificado a mano y saca varios GB a la luz en el perfil por defecto.

---

# 5. Arquitectura y diseño

### [A-01] Empaquetar el núcleo como módulo de PowerShell

Hoy todo es dot-sourcing, con consecuencias concretas: los `$script:` de `Guard.ps1` y `Log.ps1` acaban en el ámbito del llamante y funcionan por un accidente del mecanismo —`Test-GuardiaLista` existe precisamente para detectar cuándo eso falla, es un parche a un problema de empaquetado—; las más de 60 funciones son igual de accesibles, sin distinguir API de interno; no hay versión consultable; la cadena de carga no se puede cachear, de ahí [R-02]; y es imposible publicar en PowerShell Gallery.

**Cambio por fases, sin big-bang.** (1) `Cachivache.Core.psd1` + `.psm1` que hace exactamente lo que hoy hace `Bootstrap.ps1`, sin tocar los `.ps1`, terminando con `Export-ModuleMember`. (2) `Bootstrap.ps1` se queda como shim (`Import-Module ... -Global`), así que tests y código siguen funcionando. (3) Sustituir las **seis** construcciones a mano de la ruta a `Bootstrap.ps1` por la `Get-RutaBootstrap` que ya existe. (4) Los runspaces pasan a `Import-Module` en el `InitialSessionState`.

**Trampa concreta.** Dentro de un módulo, `$script:` pasa a ser ámbito de módulo —lo cual es *mejor*—, pero el test "Guardia sin inicializar" dot-sourcea tres archivos sueltos y hay que adaptarlo **con cuidado, no relajarlo**: es justo el tipo de cambio que podría convertir un comportamiento a prueba de fallos en uno permisivo sin que ninguna prueba actual lo detecte.

### [A-02] Duplicación real

| Qué | Dónde | Impacto |
|---|---|---|
| El bucle de eliminación | `Cli.ps1:168` y `Window.Analisis.ps1` (here-string) | **Ya divergen**: la de la interfaz añade `(aviso: …)` al registro, la del CLI no. Un arreglo en una no llega a la otra |
| La paleta de colores | `Profiles.ps1:20,35,50` · `Theme.Dark.xaml` · `Window.ps1` · `Report.ps1:109` (CSS) | Cambiar el verde de "riesgo bajo" exige editar 4 archivos en 2 lenguajes. **El informe HTML solo tiene tema oscuro** |
| La lista de métodos válidos | `Candidate.ps1:15`, `Candidate.ps1:67` (`ValidateSet` copiado a mano), `ModuleRegistry.ps1:127`, `Remove.ps1:252` | Añadir un método exige tocar cuatro sitios y **nada falla si olvidas uno**: el `switch` cae en `default` y borra por ruta |
| La ruta a `Bootstrap.ps1` | 10 sitios, 7 de ellos tests | Renombrar `src/Core` obliga a tocarlos todos. **Ojo:** la idea de unificarlo con `Get-RutaBootstrap` no funciona, ver [A-09] |
| El patrón "lista de rutas conocidas" | `10-Caches`, `65-LogsSistema`, `70-WindowsUpdate`, `80-ArchivosSistema` | El mismo bucle cuatro veces con umbrales distintos. Más de 100 líneas |
| Las exclusiones de recorrido | 5 módulos, **5 variantes distintas** | `50-Temporales` excluye `.git` pero no `.svn` ni `.hg`; cada uno excluye cosas diferentes sin motivo |
| Los sumatorios de bytes | 4 sitios | Cuatro bucles idénticos |

**El más valioso es el primero:** extraer `Invoke-LoteEliminacion` a `Remove.ps1` unifica el camino crítico **y lo hace probable de una vez**, que es [P-01].

Para la lista de métodos, `[ValidateSet]` exige literales y no se puede parametrizar en PowerShell 5.1, pero **un test que compare ambas listas por AST son diez líneas** y cierra el agujero.

### [A-03] `Get-CarpetaDatos` mezcla consulta y efecto secundario · `Config.ps1`

Una función `Get-` que **crea tres directorios**, usada como valor por defecto en siete parámetros. Impide probar `Config`, `Log` y `Report` sin ensuciar el `%LOCALAPPDATA%` real, y `New-Configuracion` no acepta `-CarpetaDatos`, que es el eslabón que rompe la testabilidad de toda la cadena.

**Cambio.** Separar `Get-CarpetaDatos` (pura) de `Initialize-CarpetaDatos` (crea), y aceptar la carpeta como parámetro en `New-Configuracion`.

### [A-04] Contrato de retorno inconsistente · `ModuleRegistry.ps1:102`

`Invoke-ModuloLimpieza` devuelve un objeto **sin** `Descartados` en la rama de omitido y **con** ella en la normal. `Window.Analisis.ps1` la lee sin comprobar. Funciona porque la rama de omitido hace `continue` antes, pero es frágil. Añadir `Descartados = 0` y un test que compruebe que ambas ramas devuelven el mismo conjunto de propiedades.

### [A-05] Configuración: tres capas que se mezclan a mano · `Cachivache.ps1:133`

`New-Configuracion` (entorno + perfil), `Import-Preferencias` (persistencia) y los parámetros de línea de comandos se funden a mano, con conversiones sin validar (`[int]$preferencias.MinimoMB` sobre un JSON que el usuario puede haber editado). El objeto de configuración además mezcla lo inmutable (`Equipo`, `Windows`), lo ajustable (`MinimoMB`) y lo derivado (`ZonasUsuario`).

**Cambio.** Validar en `Import-Preferencias` con un esquema por clave —tipo y rango— descartando con aviso lo que no encaje; precedencia explícita y documentada (*defaults → usuario → máquina → parámetros*); y separar entorno, umbrales y derivados. Un `%ProgramData%\Cachivache\politica.json` de solo lectura haría el programa desplegable en empresa, que es donde un limpiador con estas garantías tiene mercado.

### [A-06] Configuración muerta · `Config.ps1`

`AnalizarTodasUnidades` **no lo lee nadie** (verificado). `MinimoGrandeMB` y `MinimoDuplicadoMB` sí se leen, pero **ningún perfil los modifica**: `Set-PerfilConfiguracion` solo toca cuatro campos. El perfil Exhaustivo promete "baja los umbrales" y el de archivos grandes sigue en 250 MB.

### [A-07] Textos: acentos correctos sin romper la regla ASCII

Todo el texto visible está incrustado y **sin acentos** por la regla ASCII de `CONTRIBUTING.md`. Es defendible para código, pero produce una interfaz visiblemente pobre: "Analisis", "Configuracion", "Eliminacion".

**Cambio, barato y de alto impacto visual.** PowerShell 5.1 lee `.psd1` con `Import-PowerShellDataFile`, y **un `.psd1` de datos sí puede ser UTF-8 con BOM**. Mover las cadenas a `src/i18n/es-ES.psd1` permite escribir "Análisis" hoy mismo sin tocar la política de los `.ps1`.

Para multiidioma, `Get-Texto 'clave'` resolviendo contra `$PSUICulture` con caída a `es-ES`. **Advertencia crítica:** `Test-CarpetaEspejo` y `Test-ArchivoPersonal` comparan contra listas de nombres en castellano e inglés. **Eso no es texto de interfaz, es lógica de seguridad** y no debe moverse a archivos de traducción bajo ningún concepto: alguien "traduciría" la lista de carpetas espejo y rompería la guardia.

### [A-08] Complementos de terceros: hoy sería un vector de malware

Técnicamente ya casi funciona: copiar un `.ps1` a `src/Modules` basta. Pero hay que meterlo dentro del árbol del programa —que se sobrescribe al actualizar—, el `Orden` debe ser único globalmente (dos complementos colisionarán inevitablemente), el `Id` no admite prefijos, y sobre todo: **un módulo de terceros es código PowerShell arbitrario que se dot-sourcea con los privilegios del programa y puede emitir candidatos con método `Comando`, que está exento de la guardia**. Hoy, "instalar un complemento" es ejecución de código arbitrario disfrazada de limpieza.

**Cambio.** Carpeta fuera del árbol (`%LOCALAPPDATA%\Cachivache\modulos\`); prefijo obligatorio de autor en el `Id`; ordenar por `(Origen, Orden)` con los de terceros al final, lo que elimina la colisión por diseño; **prohibir `Comando` y `PermitirPersonales` a los módulos de terceros, comprobado en código y no en documentación**; y marcarlos visualmente con una advertencia en la primera carga.

**Si no se van a implementar los dos últimos puntos, es preferible documentar explícitamente que los complementos de terceros no están soportados.**

### [A-09] Código muerto y contratos implícitos

- ✅ **`Get-RutaBootstrap` era código muerto y se ha borrado.** Merece una nota, porque no era un descuido: es inservible *por diseño*. Vive dentro del propio núcleo que sirve para localizar, así que no se puede llamar antes de cargarlo, y después ya no hace falta. Eso invalida la propuesta de [A-02] de usarla para unificar las diez construcciones a mano de esa ruta: mientras el núcleo se cargue por dot-sourcing, no hay alternativa.
- ✅ **`$script:MetodosValidos` se ha borrado**: no lo usaba nadie y duplicaba a mano el `ValidateSet`, que es la única fuente de verdad.
- **`Get-ModuloLimpieza`** (`ModuleRegistry.ps1`) sí tiene llamantes: cuatro pruebas. Se conserva, pero se ha corregido su ayuda, que decía cargar un módulo suelto cuando en realidad carga los dieciocho y filtra. Por eso el hilo de análisis no la usa.
- **`[OutputType]` ausente** en unas 20 funciones. Las que importan son las que devuelven objetos con forma fija que otros consumen por nombre de propiedad —`Measure-RutaDetalle`, `Invoke-ModuloLimpieza`, `New-Candidato`, `New-Configuracion`—: ahí no es decorativo, es el único sitio donde queda escrito el contrato.
- **Parámetros sin tipar** en fronteras del núcleo: `Test-EsEnlace($Elemento)` debería ser `[IO.FileSystemInfo]`, `$Sync` debería ser `[hashtable]`.
- **`Bootstrap.ps1` no se protege contra doble carga**: reejecutarlo reinicializa todos los `$script:`. Hoy no pasa, pero es un `if ($script:NucleoCargado) { return }` de una línea.

---

# 6. Pruebas y CI

### 🟡 [P-01] La cobertura de `Remove.ps1`

**Parcialmente resuelto:** `tests/Remove.Tests.ps1` existe desde [C-03] con 19 pruebas, centradas en la lista blanca de ejecutables y en el método `Comando`. Lo que sigue sin cubrir es lo que enumera el resto de este punto.

**Las 293 líneas que borran datos del usuario no están cubiertas por ninguna prueba.** La guardia está probada de sobra, pero *el consumidor de la guardia* no. Sin cubrir: la revalidación en vivo, el cortafuegos de profundidad 32, el veto de enlaces, el filtro de archivos personales y el cálculo `antes − restante` que puede dar negativo.

Hoy un refactor de `Remove.ps1` pasa la CI en verde aunque rompa la revalidación. Es exactamente lo que ocurrió con [C-01].

**Cambio.** `tests/Remove.Tests.ps1` con árbol temporal bajo `GetTempPath()`, siempre con `-Permanente` para no depender del shell:

```
It 'rechaza una ruta intocable'                      -> System32 => $false, nada borrado
It 'rechaza un .docx sin PermitirPersonales'
It 'lo acepta con PermitirPersonales'
It 'no sigue un junction'                            -> comprobar destino intacto
It 'Clear-ContenidoCarpeta deja la carpeta'
It 'Clear-ContenidoCarpeta salta archivos personales'
It 'Clear-ContenidoCarpeta para a profundidad 33'
It 'bloquea un candidato manipulado'                 -> mutar $c.Ruta a C:\Windows tras crearlo
It 'devuelve 0 si la ruta ya no existe'
It 'nunca devuelve negativo'
It 'Metodo Informativo no borra nada'
It 'Clear-Miniaturas solo toca thumbcache_*.db'      -> foto.db debe sobrevivir
It 'Clear-CacheFirefox solo vacia cache2'            -> logins.json debe sobrevivir
It 'respeta -Permanente'                             <- la que habria pillado [C-01]
```

~200 líneas, medio día. El riesgo de que un test borre algo real se mitiga usando exclusivamente rutas bajo `GetTempPath()` con `AfterAll` de limpieza; el de junction requiere permisos, así que va con `-Skip`.

### 🟡 [P-02] Sin pruebas: `Config.ps1`, `Cli.ps1`, la interfaz

**Parcialmente resuelto:** `Report.ps1` y `Log.ps1` ya tienen pruebas propias (`tests/Report.Tests.ps1`, `tests/Log.Tests.ps1`), y `tests/Invariantes.Tests.ps1` cubre el invariante estructural: ningun modulo puede borrar, escribir ni lanzar procesos por su cuenta, y el candidato no puede divergir de la fila que ve el usuario. Siguen sin cubrir `Config.ps1`, `Cli.ps1` y la interfaz.

- **`Report.ps1`**: nada comprueba que el HTML escapa correctamente. Un nombre de archivo con `<script>` acaba en el informe. Test trivial: candidato con `<b>` en el nombre → el HTML no debe contener `<b>`.
- **`Config.ps1`/`Log.ps1`**: bloqueados por [A-03]; resolverlo los desbloquea.
- **`Cli.ps1`**: `Invoke-CachivacheCli` sin `-Ejecutar` debe garantizar cero borrados. Es la promesa central del modo consola y nada la verifica.
- **Invariante transversal muy rentable:** un test que ejecute los 18 módulos con `-WhatIf` sobre un árbol temporal y compruebe que **ningún archivo cambió**. Diez líneas, cubre los 18 de golpe.

### [P-03] Lo que le falta a la CI

- **Sin cobertura de código.** Pester la calcula con `CodeCoverage.Enabled`; sin umbral, nadie sabe si un PR baja la cobertura de la guardia.
- **Versiones sin fijar.** `Install-Module PSScriptAnalyzer -Force` instala lo último que haya ese día: **el resultado de la CI no es reproducible**. Fijar con `-RequiredVersion` y las actions por SHA.
- **Sin caché** de los módulos de PowerShell: cada job los reinstala.
- **El XAML se valida como XML, no como WPF.** En `windows-latest` se puede cargar de verdad con `XamlReader.Parse` **y comprobar que los 67 `FindName` devuelven algo**, que es el fallo que más caro sale.
- **Sin guardia de caracteres no ASCII ni de BOM**, pese a que `CONTRIBUTING.md` lo exige.
- **Sin badge de estado** en el README, aunque el README afirme que la CI corre en cada push. Es lo primero que mira un visitante para decidir si el proyecto está vivo.
- **El job de arranque no ejercita ninguna eliminación.** Un `-Ejecutar` sobre un árbol temporal fabricado cerraría el hueco de extremo a extremo.
- **Sin comprobación de enlaces rotos** en la documentación.
- **Sin `dependabot.yml`** ni análisis de seguridad.
- **Test que falle si aparece `tu-usuario`** en cualquier archivo.

---

# 7. Distribución y confianza

Estado actual: **no hay nada**. Ni repositorio git, ni tags, ni releases, ni firma, ni actualización.

### ✅ [X-01] Los cinco `tu-usuario/cachivache` · bloqueante

En `Version.ps1:8`, `Cachivache.ps1:53`, `README.md:40` y dos URLs de `.github/ISSUE_TEMPLATE/config.yml`. El `git clone` del README no funciona y los enlaces de "reportar vulnerabilidad" y "discusiones" van a 404. **Es lo primero que ve un usuario nuevo.** Minutos de trabajo; hacerlo antes que nada.

### [X-02] Releases con verificación de versión

Un workflow disparado por tags `v*` que: **verifique que el tag coincide con `Version.ps1`** —esto elimina de raíz la clase entera de errores "publiqué v2.1.0 y el programa dice 2.0.0"—, construya el ZIP decidiendo explícitamente qué excluir, y publique el ZIP, un `SHA256SUMS.txt` y las notas extraídas del `CHANGELOG.md`.

Sin esto, la única forma de obtener el programa es *Download ZIP* de `main`: siempre una versión de desarrollo sin identificar, y un usuario que reporte un fallo no puede decir qué versión usa. `SECURITY.md` dice "solo la última versión publicada" cuando no hay ninguna publicada.

### [X-03] SmartScreen: el mayor obstáculo real de adopción

El usuario descarga un ZIP, lo descomprime y todos los archivos llevan Mark-of-the-Web. Al hacer doble clic aparece "Windows protegió su PC". Y `Cachivache.bat` usa `-ExecutionPolicy Bypass`, **exactamente el patrón que los antivirus marcan como sospechoso**. Un limpiador de disco sin firma que pide bypass de política es indistinguible de malware para un usuario prudente, y este proyecto vende prudencia.

**Coste cero, hacerlo ya:** una sección del README titulada algo así como *"Windows te va a avisar, y así se comprueba que esto es lo que dice ser"*, explicando por qué aparece, cómo verificar el hash contra el `SHA256SUMS.txt` y cómo quitar la marca con `Unblock-File`. **Anticipar el aviso es lo que separa "software sospechoso" de "software honesto".**

**Con certificado** (Azure Trusted Signing, ~9 $/mes, sin token físico, integrable con OIDC en Actions): firmar los `.ps1` permite cambiar `Bypass` por `AllSigned`, que es un cambio de postura de seguridad enorme. Ojo: un certificado OV nuevo **no** elimina el aviso de SmartScreen hasta acumular reputación; solo un EV lo hace desde el día uno.

### [X-04] Canales de distribución

| Canal | Encaje | Veredicto |
|---|---|---|
| **Scoop** | Bucket propio, JSON de 20 líneas, sin admin, sin firma | **Lo más rápido de todo.** Público desarrollador, el que aprecia `-Consola` |
| **PowerShell Gallery** | Encaje conceptual perfecto **si** se hace [A-01]. `Install-Module Cachivache`. Sin firma, sin SmartScreen, sin MOTW, `Update-Module` | **Muy infravalorado.** Es el canal natural y elimina de un golpe los tres problemas |
| **winget** | Nativo en Win10/11, verifica SHA256, `winget upgrade` | Cuando haya releases estables |
| **Chocolatey** | Moderación humana lenta, público corporativo | Solo si hay demanda |
| **PS2EXE** | — | **No.** Destruye el argumento "puedes leer qué hace", es de las firmas más marcadas por antivirus, y el programa seguiría necesitando la carpeta al lado |

**Un `.ps1` portable único sí merece la pena** como artefacto secundario generado en CI: concatenar el núcleo en el orden que `Bootstrap.ps1` ya declara —**reutilizar esa lista literal como manifiesto de build**— más los 18 módulos y el CLI. Un archivo, auditable de una lectura, ideal para tareas programadas y sesiones remotas. Generarlo siempre en CI y ejecutar `-Listar` sobre él como prueba de humo evita que diverja.

### [X-05] Reproducibilidad: el proyecto está en una posición excepcional

No hay compilación, ni dependencias, ni toolchain: **el artefacto es literalmente el código fuente**. Con tres cosas —construir el ZIP solo en CI con timestamps normalizados, `actions/attest-build-provenance` (una línea de YAML, atestación SLSA firmada por el runner), y documentar cómo reproducirlo desde el tag— el proyecto puede ofrecer *"no tienes que confiar en mí, puedes reconstruirlo byte a byte"*. Para un limpiador de disco ese argumento es demoledor, aquí es **cierto y barato**, y muy pocos proyectos de este tamaño lo ofrecen.

### [X-06] Convertir las promesas en invariantes verificadas

`SECURITY.md` promete "sin dependencias" y "ninguna comunicación de red". **Un paso de CI que falle si aparece `Install-Module` o `Invoke-WebRequest` fuera de `.github/`** convierte las dos promesas centrales del proyecto de afirmación humana a invariante comprobada por una máquina en cada PR. Es de las mejoras de confianza con mejor relación coste/beneficio.

### [X-07] Actualización sin romper la promesa de red

`SECURITY.md` dice "actualizar es reemplazar la carpeta". Un usuario que instaló hace seis meses no sabe que hay un arreglo de seguridad de la guardia.

La solución correcta **no** es un autoupdater: rompería *"el programa no tiene ninguna comunicación de red"*, que es una promesa valiosa. Es (a) delegar en el gestor de paquetes, que es donde debe vivir; (b) mostrar versión y fecha en la ventana con enlace a las releases; (c) opcionalmente, una comprobación **explícitamente opt-in y desactivada por defecto**, actualizando `SECURITY.md` con honestidad. **Cualquier tráfico por defecto rompe la promesa: opt-in o nada.**

---

# 8. Documentación

### ✅ [T-01] Promesas que el código no cumple

| Dónde | Dice | Realidad |
|---|---|---|
| `SECURITY.md` | El comando externo es "siempre visible en la interfaz" | **No se muestra en ninguna parte.** Ver [C-03]. Es la más grave porque es justo el camino que ejecuta código |
| `README.md:47` | "los **dos** módulos que los necesitan" | Son **cuatro**: logs, windowsupdate, componentes, perfiles. La propia tabla del README los marca los cuatro: se contradice a sí mismo |
| `README.md:58` | "Hay que escribir `ELIMINAR`" | Es `ELIMINAR` solo si hay elementos de riesgo o borrado permanente; si no, es `SI` |
| `ARQUITECTURA.md:94` | Los descartes "se anotan en el registro" | Solo en modo ventana |
| `Window.ps1` | El temporizador consulta "cuatro veces por segundo" | Son cinco (200 ms). El README y `ARQUITECTURA.md` lo dicen bien; el comentario del propio archivo, no |
| `README.md:49` | "Windows 10 o superior" | Solo se comprueba `PSVersion.Major -lt 5`: acepta PowerShell 5.0 y Windows 7 |
| `Guard.ps1:15` | "cinco filtros" | El README dice siete. Ambos son ciertos según qué se cuente, pero ninguno lo aclara |

En un proyecto cuyo argumento central es *"puedes verificar lo que hace"*, cada promesa incumplida que un lector detecte cuesta desproporcionadamente.

### ✅ [T-02] `exhaustivo` no existe como identificador de perfil

`docs/MODULOS.md` dice "Perfiles: conservador, equilibrado, **exhaustivo**" en las 18 secciones. El id real es `agresivo`; *Exhaustivo* es solo el nombre visible. Un usuario que lea la documentación y escriba `-Perfil exhaustivo` **recibe un error de parámetro**. El README dice `agresivo` en la tabla de parámetros y "Exhaustivo" en el paso 1 de "cómo se usa".

**Cambio.** Escribir `Exhaustivo (agresivo)` en la documentación, o mejor, aceptar `exhaustivo` como alias en el `ValidateSet`. El desajuste entre nombre visible e id es una trampa permanente.

### [T-03] Números que caducan

"144 pruebas", "95 de la guardia", "18 módulos", "siete filtros" están escritos en seis sitios. Hoy son exactos (verificado), pero cambiarán con el próximo PR. La plantilla de PR llega a exigir *"las 95 pruebas de la guardia siguen pasando"*: una casilla que quedará mal en cuanto alguien añada la número 96, que es justo lo que el propio documento pide hacer.

**Cambio.** "Todas las pruebas de la guardia" dice lo mismo y no caduca. Y badges generados por la CI en lugar de números a mano.

### [T-04] Lo que falta

- **Nada sobre SmartScreen ni `Unblock-File`.** El usuario se va a encontrar el aviso; que se lo cuente el README primero.
- **Nada sobre desinstalar**: hay que borrar `%LOCALAPPDATA%\Cachivache` a mano.
- **Nada sobre recuperación**: cómo restaurar desde la papelera, y qué **no** se puede recuperar (borrado permanente, papelera vaciada, `docker system prune`).
- **`docs/interfaz.svg` es un esquema, no una captura.** Para un programa con interfaz, dos capturas reales valen más que toda la sección de "por qué otro limpiador".
- Ausentes: `CODE_OF_CONDUCT.md`, `dependabot.yml`, `CODEOWNERS`, y un `docs/SOPORTE.md` con el flujo de diagnóstico.

### ✅ [T-05] El registro no basta para depurar un reporte

**Corregido en Fase 2.** Cabecera de sesión al arrancar, id corto por línea, y `-Diagnostico`. Ver `CHANGELOG.md`.

---

# 9. Lo que ya está bien y no conviene romper

Vale la pena enumerarlo porque son decisiones acertadas que un refactor podría erosionar sin que nadie se dé cuenta:

- **El modelo de lista blanca es real, no cosmético.** La propia raíz autorizada nunca es borrable: solo lo que cuelga de ella.
- **La revalidación en vivo antes de borrar** (`Remove.ps1:242`) y la red de seguridad de `Invoke-ModuloLimpieza`.
- **La guardia no inicializada bloquea todo en lugar de permitir todo** (`Guard.ps1:207,267,286,317`). Es la elección correcta de comportamiento a prueba de fallos, y está probada en un runspace limpio. **Cualquier cambio de [A-01] debe re-verificar los cuatro `Test-GuardiaLista`**: el cambio de semántica de `$script:` es exactamente el tipo de cosa que convierte un fallo seguro en un fallo permisivo sin que ninguna prueba actual lo detecte.
- **La comprobación de cordura de `Cachivache.ps1:149`** que aborta el arranque si la guardia no funciona.
- **`Test-EsEnlace` sobre cada hijo en `Clear-ContenidoCarpeta`** y el cortafuegos de profundidad 32.
- **La estrategia en dos fases de duplicados**: agrupar por tamaño antes de hashear.
- **El aislamiento de errores por módulo**: un módulo que revienta no aborta el análisis.
- El `Grid` en lugar de `StackPanel` en la plantilla de grupo, que es lo que mantiene viva la virtualización.

  ~~`DeferRefresh` al poblar la lista~~ — **esto estaba mal y se ha corregido.** `DeferRefresh()` sirve para agrupar cambios en las *propiedades* de la vista (orden, agrupación, filtro), no para añadir elementos: WPF prohíbe modificar la colección mientras hay un refresco aplazado y lanza `InvalidOperationException` en el primer `Add`. El análisis reventaba siempre, en cuanto un módulo devolvía su primer resultado. Ahora se desengancha el `ItemsSource` durante el lote y se vuelve a enganchar al terminar, que consigue el mismo ahorro y es legal. Que este documento lo listara como acierto es un recordatorio de que una auditoría por lectura no sustituye a ejecutar el programa.
- **El comentario de `Guard.ps1:29-33`** explicando por qué el filtro de carpetas personales mira solo el último segmento: decisión correcta y bien argumentada. Sin ese comentario, alguien "arreglaría" el filtro y volvería a romper cinco módulos.
- **El arranque sin permisos de administrador por defecto** y los datos generados fuera del árbol del repositorio.
- **`-Ejecutar` en modo consola limitado a lo preseleccionado.**

---

# 10. Plan por fases

**Fase 1 — correcciones (una semana, código poco, impacto alto)** ✅ cerrada

1. ✅ [C-01] Respetar `-Permanente`, con el campo `ForzarPermanente` para cachés.
2. ✅ [C-02] Desanidar `ZonasUsuario` + deduplicar en duplicados. (No se ha hecho todavía la detección de hardlinks NTFS de la parte (b); queda para cuando se retome [R-04].)
3. ✅ [C-07] El `@()` en el sitio correcto.
4. ✅ [C-04] [C-05] Parseo numérico por cultura y regex de DISM.
5. ✅ [C-10] [C-11] [C-12] [C-14] [C-15] [C-16] Ramas muertas, `-Silencioso`, agrupación duplicada, falsos positivos premarcados. De paso apareció y se corrigió un bug relacionado no listado originalmente: la guardia trataba cualquier `~$archivo.docx` de Office como personal por su extensión, así que el propio [C-15] no podía proponer ni un solo bloqueo de Office real.
6. ✅ [C-13] Dejar de tragar los errores de los módulos.
7. ✅ [X-01] Los cinco `tu-usuario` (ahora `pacolopez23/cachivache`). [T-01] [T-02] Promesas y el `exhaustivo`.
8. ✅ [R-01] Quitar el `Start-Sleep`. [R-05] La línea del recorrido cuadrático.

Verificado con 192 pruebas de Pester en verde (95 → 99 de la guardia, más las nuevas de esta fase) y `Invoke-ScriptAnalyzer` limpio. [C-08], [C-09], [C-17], [C-18], [C-19] y el resto de `[R-xx]`/`[U-xx]` siguen pendientes de las fases 2 en adelante.

**Fase 2 — seguridad y pruebas (dos semanas)**

9. [C-03] Comando visible, lista blanca, `Start-Process`, registro. Con test.
10. [P-01] `tests/Remove.Tests.ps1` completo. [P-02] El invariante de "ningún módulo escribe con `-WhatIf`".
11. [C-08] Unificar `Get-MotivoBloqueo` con la guardia, con test de equivalencia.
12. [C-19] Cola concurrente para el registro. [T-05] Cabecera de sesión y `-Diagnostico`.
13. [P-03] CI: versiones fijadas, caché, XAML real, guardia ASCII, cobertura, badge.

**Fase 3 — rendimiento (un mes)**

14. [R-03] Cachear el ensamblado. [U-06] Ventana de carga.
15. [R-02] Runspace persistente (escalón 1, no el pool).
16. [U-01] [U-02] [U-03] Debounce y predicado en C#, contadores incrementales, colores por `DataTrigger`.
17. [R-07] Optimizar la guardia (HashSet de ancestros, inline, regex compiladas, prefijos cacheados, `Ordinal`).
18. [R-09] [R-18] Una sola pasada en las mediciones y los costes menores repetidos.
19. [R-13] [R-14] [R-15] [R-16] Dejar de medir lo que no hace falta.

**Fase 4 — distribución (un mes)**

20. [X-02] Workflow de release con verificación tag↔versión, hashes y attestation.
21. [X-03] Sección de SmartScreen en el README. [X-04] Bucket de Scoop.
22. [X-06] Los dos invariantes de CI. [T-04] Capturas reales y documentación que falta.

**Fase 5 — estructural (cuando haya tiempo)**

23. [R-04] `Walk.ps1` con recorrido único, por fases: primero el índice, luego los visitantes.
24. [R-08] Recorrido de pila con protección de junctions y cancelación real. [R-19] Rutas largas.
25. [A-01] Módulo de PowerShell por fases, re-verificando los `Test-GuardiaLista`. Después, PSGallery.
26. [A-02] `Invoke-LoteEliminacion` compartido y paleta única.
27. [A-07] Cadenas a `.psd1` con acentos correctos: barato y muy visible.
28. [D-01] a [D-08] Ampliar la cobertura de detección. Es lo que más espacio recupera al usuario final.
29. [A-08] Complementos de terceros, **solo** si se implementan las restricciones de seguridad.

---

*Documento generado en la auditoría de la versión 2.0.0. Al cerrar cada punto, márcalo aquí y anótalo en `CHANGELOG.md`.*
