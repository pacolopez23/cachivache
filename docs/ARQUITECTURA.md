# Arquitectura

Guía para entender el código y para escribir módulos nuevos.

---

## Idea central

Todo lo que el programa sabe hacer vive en **módulos independientes** dentro de `src/Modules/`. El resto del código no conoce ningún módulo concreto: los descubre al arrancar leyendo la carpeta.

Añadir una categoría de limpieza nueva es escribir un archivo. No hay ninguna lista central que actualizar, ningún `switch` que ampliar y ningún número de paso que renumerar.

---

## Carga del núcleo

El núcleo se carga **dot-sourceando** `src/Core/Bootstrap.ps1`:

```powershell
. (Join-Path (Join-Path (Join-Path $Raiz 'src') 'Core') 'Bootstrap.ps1')
```

Esto es importante y es fácil equivocarse. Una función que dot-sourcea archivos los carga en **su propio** ámbito, y las definiciones desaparecen en cuanto la función termina. Por eso el cargador es un script y no una función: al dot-sourcearlo, todo acaba en el ámbito de quien llama.

El mismo `Bootstrap.ps1` lo cargan el proceso principal y cada runspace de análisis, así que los dos ven exactamente el mismo código.

El orden de carga es explícito, no alfabético, porque hay dependencias reales: `Guard` necesita `Texto`, `Config` necesita `Profiles` y `FileSystem`, `Remove` necesita `Guard` y `Log`, y `Progreso` va primero porque lo usan los veintiún módulos. El propio `Bootstrap.ps1` lleva la lista comentada.

---

## Escribir un módulo

Un módulo es un archivo `.ps1` en `src/Modules/` cuyo nombre empieza por dos dígitos que fijan el orden. El archivo **termina** devolviendo el objeto que crea `New-ModuloLimpieza`.

```powershell
<#
.SYNOPSIS
    Una frase de qué hace este módulo.
.DESCRIPTION
    Qué busca exactamente, y por qué es seguro proponerlo.
#>

$BuscarLoQueSea = {
    param($Configuracion, $Sync)

    # 1. Declara la lista blanca de raíces. Solo se podrá borrar lo que
    #    cuelgue de aquí dentro. Sé lo más específico que puedas.
    $raices = @($env:LOCALAPPDATA)

    foreach ($carpeta in @('MiApp\Cache', 'MiApp\Logs')) {
        # 2. Respeta la cancelación en todos los bucles largos.
        if (Test-Cancelacion $Sync) { break }

        $ruta = Join-Path $env:LOCALAPPDATA $carpeta
        if (-not (Test-Path -LiteralPath $ruta)) { continue }

        # 3. Informa del progreso: se ve bajo la barra de la ventana.
        Set-Progreso $Sync "Midiendo: $carpeta"

        $bytes = Measure-Ruta $ruta
        if ($bytes -lt ($Configuracion.MinimoMB * 1MB)) { continue }

        # 4. Pregunta a la guardia ANTES de proponer nada.
        if (-not (Test-RutaSegura $ruta $raices)) { continue }

        # 5. Emite el candidato al canal de salida.
        New-Candidato -ModuloId 'miapp' -Categoria 'Mi aplicacion' `
                      -Nombre "Cache de MiApp" -Ruta $ruta -Bytes $bytes `
                      -Info 'se vacia el contenido, la carpeta se queda' `
                      -Efecto 'Se regenera al abrir el programa.' `
                      -Metodo 'Contenido' -Raices $raices -Riesgo 'Bajo'
    }
}

New-ModuloLimpieza -Id 'miapp' -Orden 42 `
    -Nombre 'Cache de MiApp' `
    -Descripcion 'Explicacion de una o dos lineas que se ve en la pantalla de inicio.' `
    -Riesgo 'Bajo' `
    -Perfiles @('equilibrado', 'agresivo') `
    -Buscar $BuscarLoQueSea
```

### Reglas que el registro hace cumplir

- **`Id`** en minúsculas, sin espacios ni números. Debe ser único.
- **`Orden`** único. Determina la posición en la interfaz y el orden de ejecución.
- **`Buscar`** recibe siempre dos parámetros: `$Configuracion` y `$Sync`. Aunque no uses uno de los dos, decláralos: el contrato es uniforme.
- **`Perfiles`** solo admite `conservador`, `equilibrado` y `agresivo`. Un módulo de riesgo alto nunca puede estar en `conservador`.

Estas reglas están comprobadas en `tests/Modules.Tests.ps1`. Si te saltas alguna, la CI falla.

### Red de seguridad

`Invoke-ModuloLimpieza` vuelve a pasar cada candidato por `Test-RutaSegura` antes de entregarlo a la interfaz, y descarta los que no la pasen. Es decir: **aunque un módulo se olvide de comprobar la guardia, no puede colar una ruta peligrosa**. Los descartes se cuentan siempre (`Resultado.Descartados`); hoy solo el **modo ventana** los anota en el registro (`Window.Analisis.ps1`), el modo consola no lo hace todavía.

Los métodos `Informativo`, `Papelera` y `Comando` están exentos de esa comprobación porque no borran archivos por ruta: no tienen una ruta convencional que validar.

Por el mismo sitio pasa el **filtro de unidades**: si el usuario ha desmarcado un disco en el panel lateral, `Test-UnidadSeleccionada` descarta ahí los candidatos que caigan en él. Está puesto en el registro y no en cada módulo por el mismo motivo que la guardia: así ninguno puede olvidarse de respetarlo, y un módulo nuevo lo hereda sin escribir una línea. El filtro solo puede **quitar** candidatos, nunca añadirlos.

Ante la duda no filtra: si no hay lista de unidades, o la ruta no tiene letra (un recurso de red, la etiqueta que usa el método `Comando`), el candidato pasa. Equivocarse hacia "no" haría desaparecer cosas legítimas sin explicación visible, que es peor que no filtrar.

**Si tu módulo razona por unidad, tiene que filtrar además por su cuenta.** Le pasa a `papelera`: mide todas las unidades pero emite un único candidato en la del sistema, así que el filtro central lo dejaría pasar entero. Ese módulo consulta `Test-UnidadSeleccionada` al medir, y `Clear-Papelera` vacía exactamente las mismas unidades. La regla es sencilla: **se vacía lo que se midió**.

### Elegir el método de eliminación

| Método | Qué hace | Cuándo usarlo |
|---|---|---|
| `Contenido` | Vacía la carpeta y la deja en su sitio | Cachés. Es el caso normal: muchos programas fallan si su carpeta desaparece |
| `Ruta` | Borra el archivo o la carpeta entera | Archivos sueltos, carpetas que sobran del todo |
| `CarpetaVacia` | Borra un árbol de carpetas vacías, comprobando otra vez que sigue sin un solo archivo | Cadenas de carpetas vacías anidadas. La revalidación importa: entre el análisis y el borrado alguien puede haber dejado algo dentro |
| `Informativo` | No borra nada | Cuando lo correcto es que lo haga Windows o una persona |
| `Comando` | Ejecuta un comando externo declarado en el candidato | DISM, `docker system prune`… |
| `Papelera` | Vacía la papelera vía API del shell | Solo el módulo `papelera` |
| `FirefoxCache`, `Miniaturas` | Casos especiales con lógica propia | Ver `src/Core/Remove.ps1` |

### Elegir el riesgo

- **Bajo** — se regenera solo, sin intervención y sin pérdida. Se marca por defecto.
- **Medio** — se puede recuperar, pero cuesta algo: volver a descargar, volver a compilar. No se marca por defecto.
- **Alto** — el programa está haciendo una conjetura sobre la intención del usuario. Nunca se marca por defecto.

Rellenar `-Aviso` fuerza que el elemento salga en rojo y sin marcar, sea cual sea el riesgo. Úsalo cuando hayas encontrado algo concreto que el usuario debe saber: partidas guardadas dentro, un programa abierto que bloquea archivos, un comprimido que puede contener cualquier cosa.

---

## Concurrencia

El análisis y la eliminación no pueden ejecutarse en el hilo de la ventana: bloquearían la interfaz durante minutos.

```
Hilo de la interfaz                    Runspace de trabajo
───────────────────                    ───────────────────
lanzarTrabajo ──────────────────────►  carga Bootstrap.ps1
                                       Initialize-Guardia
DispatcherTimer (200 ms)               Invoke-ModuloLimpieza
  lee $sync.Mensaje  ◄─────────────┐     escribe $sync.Mensaje
  actualiza etiquetas              │
  ¿$sync.Terminado? ───────────────┴───  $sync.Resultado
       │                                 $sync.Terminado = $true
       ▼
  limpiarTrabajo, siguiente módulo
```

`$sync` es una `[hashtable]::Synchronized(@{})`. **Nada que toque un control de WPF ocurre fuera del hilo de la interfaz**: el runspace solo escribe datos en la tabla, y es el temporizador el que pinta.

La cancelación funciona al revés: la interfaz pone `$sync.Cancelar = $true` y cada bucle de módulo lo consulta con `Test-Cancelacion`. Por eso todo bucle largo debe comprobarlo.

Esa bandera **no basta por sí sola**, y conviene entender por qué: un módulo que esté midiendo una carpeta enorme no vuelve a consultarla hasta terminar esa medición, que pueden ser minutos. Por eso el botón *Cancelar* además **para el runspace** y cierra el análisis en el acto, en vez de esperar al siguiente tick del temporizador. Detalle importante si alguna vez se toca ese camino: al parar el runspace, la línea `$sync.Terminado = $true` del final del guion puede no llegar a ejecutarse nunca, así que quien cancela tiene que encargarse él mismo de cerrar el trabajo.

**Un solo runspace por operación, no uno por módulo.** Se abre al empezar el análisis, se carga `Bootstrap.ps1` y se llama a `Initialize-Guardia` **una vez**, y ese mismo runspace ejecuta los veintiún módulos. Antes se creaba uno nuevo por módulo, así que las más de cuatro mil líneas del núcleo se dot-sourceaban veintiuna veces en cada análisis. `$limpiarTrabajo` suelta el trabajo de cada módulo; el runspace lo cierra `$cerrarRunspace`, y tiene que llamarlo cada uno de los tres finales posibles: fin de análisis, fin de borrado y cierre de la ventana.

Consecuencia que conviene tener presente al tocar esto: como la configuración se pasa **por referencia** al runspace y ahora vive toda la operación, cualquier cosa de la interfaz que la modifique durante un trabajo es una carrera de datos. Por eso Ajustes, los perfiles y el botón de tema se inhiben mientras `$estado.Ocupado` esté a `$true`.

Los módulos se ejecutan **uno detrás de otro**, no en paralelo. Es deliberado: medir tamaños satura el disco, y varios módulos compitiendo por él acabarían siendo más lentos que en serie, además de hacer el progreso incomprensible.

---

## La interfaz

WPF cargado con `XamlReader.Parse`, sin `x:Class` ni manejadores en línea. Los controles se buscan por `FindName` y los eventos se conectan desde `Window.Eventos.ps1`.

**La ventana está repartida en cinco archivos.** `Show-VentanaPrincipal` vive en `Window.ps1`, construye la ventana y la tabla `$estado`, y **dot-sourcea desde dentro de sí misma** los cuatro trozos de su propio cuerpo (`Window.Ayudantes.ps1`, `Window.Analisis.ps1`, `Window.Eliminacion.ps1`, `Window.Eventos.ps1`). Esto es deliberado y no es lo mismo que cargar un archivo de funciones: al dot-sourcear *dentro* de la función, el código de cada trozo se ejecuta en el ámbito de `Show-VentanaPrincipal` y ve `$c`, `$estado`, `$ventana` y los cierres de los demás trozos, exactamente igual que si estuviera pegado ahí. Cargarlos desde fuera de la función no funcionaría: las definiciones morirían con el ámbito del cargador.

La consecuencia práctica: **esos cuatro archivos no se pueden ejecutar ni razonar por separado**. Son un único cuerpo de función escrito en cinco pedazos por comodidad de lectura.

**Temas.** `Theme.Dark.xaml` y `Theme.Light.xaml` definen las mismas claves con distintos valores. `Styles.xaml` las consume con `DynamicResource`, así que cambiar de tema es sustituir un diccionario en `Application.Resources`. Los colores que viajan como cadenas en los objetos de vista (las etiquetas de riesgo) sí hay que recalcularlos a mano.

**Tipos.** WPF necesita `INotifyPropertyChanged` para que una casilla marcada actualice el resumen del pie. Un `PSCustomObject` no lo implementa, así que `src/UI/Types.ps1` compila unas clases pequeñas con `Add-Type`. No dependen de WPF: los colores y las visibilidades viajan como cadenas y el motor de enlace de datos las convierte al tipo real con el convertidor por defecto.

---

## Dónde tocar cada cosa

| Quiero… | Archivo |
|---|---|
| Añadir una categoría de limpieza | `src/Modules/NN-Loquesea.ps1` |
| Cambiar qué se puede borrar | `src/Core/Guard.ps1` **y sus pruebas** |
| Cambiar cómo se borra | `src/Core/Remove.ps1` |
| Cambiar cómo se comparan nombres (guardia, restos) | `src/Core/Texto.ps1` **y sus pruebas** |
| Cambiar cómo se muestran tamaños, fechas o rutas | `src/Core/Format.ps1` |
| Cambiar el aspecto | `src/UI/Styles.xaml`, `Theme.*.xaml` |
| Cambiar la disposición | `src/UI/MainWindow.xaml` |
| Cambiar qué hace un botón o un control | `src/UI/Window.Eventos.ps1` |
| Cambiar cómo se refresca una lista, el filtro o el tema | `src/UI/Window.Ayudantes.ps1` |
| Cambiar el análisis, el runspace o el temporizador | `src/UI/Window.Analisis.ps1` |
| Cambiar la preparación o el cierre del borrado | `src/UI/Window.Eliminacion.ps1` |
| Cambiar el arranque de la ventana o el estado inicial | `src/UI/Window.ps1` |
| Cambiar los perfiles | `src/Core/Profiles.ps1` |
| Cambiar los informes | `src/Core/Report.ps1` |
| Cambiar qué programas externos se pueden lanzar | `src/Core/Comandos.ps1` |
| Cambiar el aspecto de un panel | `src/UI/Panel.<Panel>.xaml` |
| Cambiar qué se anota en el registro | `src/Core/Log.ps1` |
| Cambiar el historial de ejecuciones | `src/Core/Historial.ps1` |
| Cambiar qué se recuerda entre sesiones | `src/Core/Preferencias.ps1` |
| Añadir un parámetro de consola | `Cachivache.ps1` y `src/Cli/Cli.ps1` |

Los archivos de `src/Core/` están pensados para tener **una sola razón de cambio** cada uno. Si un cambio te obliga a tocar tres, merece la pena preguntarse si falta una pieza compartida. El razonamiento detrás de dónde está cada frontera está en [`ESTRUCTURA.md`](ESTRUCTURA.md).