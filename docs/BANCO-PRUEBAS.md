# Banco de pruebas — comprobar lo que aquí no se puede comprobar

`[VAL-02]`

Cachivache tiene **1612 pruebas en verde y tres afirmaciones que nadie ha visto cumplirse**. No es
una contradicción: las tres solo ocurren **al borrar de verdad**, y un borrado de verdad no se
ensaya sobre las carpetas de uno.

| Afirmación | Estado |
|---|---|
| `COR-01` · si algo no cabe en la papelera, **no se borra** y se dice | Escrito, probado en frío, **nunca ejecutado** |
| `COR-02` · una ruta de más de 260 caracteres se mide y se borra bien | Escrito, probado en frío, **nunca ejecutado** |
| `COR-03` · un archivo de OneDrive bajo demanda no se descarga sin querer | Escrito, probado en frío, **nunca ejecutado** |

Este documento convierte esas tres en *"lo he visto"*. Lleva un rato la primera vez; después son
veinte minutos por tanda.

> **Buena parte de esto ya no hace falta hacerlo a mano.** Desde `VAL-03`, la integración continua
> monta este mismo banco en un agente de Windows y ejecuta una limpieza **real** en cada push:
> comprueba que los cebos aparecen, que no se propone nada del sistema, las rutas largas de `COR-02`,
> los enlaces duros de `VIS-03`, dos análisis seguidos y —gratis, porque los agentes de GitHub están
> en **inglés**— buena parte de `I18N-03`. Lo que sigue exigiendo la máquina virtual está en el
> apartado 8, al final, y es una lista corta.
>
> **Los nombres de los cebos cambiaron en `VAL-03`, y el motivo merece leerse:** se llamaban
> `copia-enorme.bak`, `copia-antigua.bak` y `documento-N.bak`, y empiezan por palabras de la lista de
> `Test-ArchivoPersonal`. La guardia los protegía como trabajo tuyo y **no se proponían nunca**. O
> sea: los pasos 5.4 y 5.5 —los de `COR-01` y `COR-02`, justo los que este banco existe para ver—
> eran incomprobables, y lo habrías descubierto en la VM buscando un archivo que no aparecía.
>
> **Regla que no se salta.** El banco crea archivos **dentro de Documentos**, porque es el único
> sitio donde los módulos los buscan, y después se hace una limpieza **real** sobre ellos. Eso se
> hace en una máquina virtual con instantánea. No en el equipo de trabajo. El guion se niega a
> montarse si no cree estar en una VM, y esa negativa es una red, no una garantía: la garantía es
> la instantánea.

---

## 1. La máquina virtual

Cualquier hipervisor vale — VirtualBox, VMware, Hyper-V. Lo que importa es que **se pueda hacer
una instantánea y volver a ella**.

- Windows 11, instalación limpia, cuenta local de administrador.
- Disco de 60 GB o más. Menos aprieta la papelera y confunde las mediciones.
- **Carpetas compartidas desactivadas.** Una carpeta compartida es una ruta del equipo anfitrión
  montada dentro de la VM: la instantánea no la protege.

Instala Cachivache dentro de la VM como lo haría cualquiera: copia el `.zip`, descomprímelo,
ejecuta `Cachivache.exe`.

## 2. Bajar la cuota de la papelera

Es el paso que hace posible probar `COR-01` sin fabricar un archivo de varios gigas.

1. Clic derecho en la Papelera de reciclaje → **Propiedades**.
2. Selecciona la unidad `C:`.
3. **Tamaño personalizado: 100 MB**. Aceptar.

Ahora un archivo de 200 MB **no cabe**, que es justo el caso que nunca se ha visto.

## 3. La instantánea

Con la VM apagada, crea una instantánea y llámala `limpia`. **Todo lo que viene después se
deshace volviendo aquí.** El `-Quitar` del guion recoge sus propios cebos, pero no devuelve lo que
Cachivache borró.

## 4. Montar el banco

Dentro de la VM, en la carpeta del programa:

```powershell
# Primero mirar, sin tocar nada:
.\tools\Banco-Pruebas.ps1 -WhatIf

# Y montarlo:
.\tools\Banco-Pruebas.ps1
```

Crea `Documentos\Banco-Cachivache` con siete grupos de cebos. Cada uno existe para una afirmación
concreta:

| Carpeta | Qué contiene | Para qué |
|---|---|---|
| `01-temporales` | 16 archivos `salida-N.bak` y `version-N.old`, con fecha de hace más de un año | El camino normal: proponer, marcar y borrar a la papelera |
| `02-ruta-larga` | Doce carpetas anidadas y `volcado-antiguo.dmp` al fondo, más de 260 caracteres | `COR-02` |
| `03-mas-grande-que-la-papelera` | `volcado-enorme.dmp`, de 200 MB | `COR-01`, con la cuota bajada a 100 MB |
| `04-enlaces-duros` | 20 MB reales con **dos** nombres | `VIS-03`: no contar dos veces |
| `05-duplicados` | Dos archivos idénticos de 512 KB, independientes | El módulo de duplicados, y el contraste con el anterior |
| `06-carpetas-vacias` | Cinco carpetas vacías | El módulo de carpetas vacías |
| `07-muchas-filas` | 3.000 `.tmp` de un byte | `USO-01` desplazamiento, `VEL-03` marcar en lote |

**Las fechas son de hace 400 días a propósito.** El módulo de temporales no propone un `.tmp`
escrito hace menos de treinta minutos, porque podría estar en uso ahora mismo. Con cebos recién
creados no saldría ninguno y parecería que el módulo está roto.

---

## 5. Las comprobaciones, en orden

**El orden importa**: si falla una, las de debajo no significan nada. Para en cuanto algo no
cuadre y manda el registro de `%LOCALAPPDATA%\Cachivache\informes\`, que desde `COR-06` lleva tipo
de excepción y línea.

### 5.1 · El análisis encuentra los cebos y no propone nada del sistema

Perfil **Exhaustivo**, analizar. Al terminar:

- [ ] Aparecen los `salida-N.bak` y `version-N.old` de `01-temporales`.
- [ ] **`volcado-antiguo.dmp`, el de `02-ruta-larga`, TIENE que aparecer.** Hasta `COR-08` no
      aparecía: `COR-02` había arreglado medir y borrar las rutas largas, pero no **encontrarlas**.
      Si no aparece, `COR-08` no funciona en tu Windows y quiero saberlo — la CI ya lo exige, así
      que lo normal es que salga verde antes de que llegues aquí.
- [ ] Aparecen los 3.000 de `07-muchas-filas`.
- [ ] **Nada de `C:\Windows`, `Archivos de programa` ni perfiles de otros usuarios.** Esto es la
      guardia, y es lo único de esta lista que, si falla, se para todo.

### 5.2 · Dos análisis seguidos sin cerrar el programa

Vuelve a Inicio y analiza otra vez, sin cerrar.

- [ ] Termina igual que la primera vez.
- [ ] El Administrador de tareas no muestra la memoria del proceso creciendo sin volver a bajar.

Esto es lo que comprueba que el runspace compartido no gotea. Nunca se ha hecho.

### 5.3 · Desplazamiento con miles de filas — `USO-01`

Con los 3.000 en la lista:

- [ ] Bajar con la rueda es fluido, no a saltos.
- [ ] La columna *qué pasa si se borra* crece cuando el texto es largo, en vez de recortarse.

`USO-01` cambió la altura fija por altura mínima, y quedó anotado que **eso puede volver el
desplazamiento a saltos**. Aquí es donde se ve.

### 5.4 · La papelera que no cabría — `COR-01`

Marca **solo** `volcado-enorme.dmp` (200 MB) y elimina.

- [ ] **No se borra.** Aparece la explicación con las dos cifras: lo que ocupa y lo que cabe.
- [ ] Se ofrece el borrado permanente como decisión aparte.
- [ ] El registro **no** dice `PAPELERA` sobre ese archivo.

> Si se borra y el registro dice `PAPELERA`, ese es el fallo original entero: Windows lo ha
> destruido y el programa ha mentido. Para aquí y manda el registro.

### 5.5 · La ruta larga — `COR-02`

Marca **solo** `volcado-antiguo.dmp`, el del fondo de `02-ruta-larga`, y elimina.

- [ ] O va a la papelera, o se dice que **no puede ir** y por qué. Las dos son correctas; lo que no
      vale es borrarlo permanentemente llamándolo papelera.
- [ ] El tamaño liberado que informa coincide con el del archivo.

### 5.6 · Los enlaces duros — `VIS-03`

Antes de tocar nada, mira lo que dice de `04-enlaces-duros`.

- [ ] Dice **20 MB**, no 40. Hay dos nombres y un solo contenido.
- [ ] Si propone borrar uno de los dos, **no** promete liberar 20 MB: borrar un nombre no libera
      nada mientras el otro exista.

### 5.7 · Los duplicados

- [ ] Los dos de `05-duplicados` salen como duplicados entre sí.
- [ ] **Ninguno viene marcado.** Elegir cuál se queda es del usuario.

### 5.8 · Marcar en lote — `VEL-03`

Con los 3.000 en la lista, pulsa **Marcar todo** (o `Ctrl+A`).

- [ ] La ventana no se queda congelada más de un segundo o dos.
- [ ] El resumen de abajo cuadra con lo marcado.

### 5.9 · La limpieza real, entera

Marca todo lo del banco y elimina de verdad.

- [ ] El diálogo de confirmación enseña la lista completa, desplazable, **con todo comando externo
      visible entero** — lo exige `SECURITY.md`.
- [ ] Al terminar dice cuántos fueron a la papelera y cuántos no tienen vuelta atrás.
- [ ] Aparece **Abrir la papelera**, y abre.
- [ ] Lo que falló se ve **en rojo**, no en verde, y **sigue marcado** para poder reintentarlo.
- [ ] El espacio liberado que informa se parece al que ves en las propiedades del disco.

### 5.10 · Detener a mitad

Vuelve a la instantánea, monta el banco otra vez, marca los 3.000 y **detén** la eliminación a
mitad.

- [ ] Lo ya borrado sigue borrado; el resto sigue en la lista.
- [ ] El historial lo anota como **interrumpida**, no como una limpieza normal.

### 5.11 · Accesibilidad — `A11Y-01`, `A11Y-04`, `A11Y-06`

Enciende el Narrador con **Ctrl + Win + Enter**. (Se calla con `Ctrl`; se apaga con el mismo
atajo.)

- [ ] Tab por los botones de la barra de título: dice *"Cambiar entre tema oscuro y claro"*,
      *"Minimizar la ventana"*, *"Maximizar o restaurar la ventana"*, *"Cerrar Cachivache"*.
- [ ] `Ctrl+2` y `Ctrl+5`: al cambiar de panel dice su nombre.
- [ ] Sobre una fila de la tabla, la casilla dice el **nombre del elemento**.
- [ ] `Ctrl+A` dentro del filtro selecciona el texto; fuera, marca la lista.
- [ ] Tab no se para en ningún sitio vacío.

---

## 6. Las tres variantes que faltan

Lo de arriba se hace sobre una VM en español con cuenta de administrador. Las tres siguientes son
las que el README promete y nadie ha comprobado. Cada una es una instantánea distinta.

### 6.1 · Windows en inglés — `I18N-03`

Es la más importante de las tres, y la razón está escrita en la hoja de ruta: `Test-CarpetaEspejo`,
`Test-ArchivoPersonal` y la lista de nombres sensibles comparan contra **palabras en castellano e
inglés**. En un Windows en otro idioma **protegen menos de lo que el README dice**, y no avisan.

- [ ] Un análisis completo no propone nada del sistema.
- [ ] Los módulos que leen la salida de DISM (`70-WindowsUpdate`, `75-AlmacenComponentes`) no
      informan de cosas absurdas: **esa salida está traducida**.

### 6.2 · Cuenta sin privilegios

- [ ] La insignia dice *Modo estándar* y el botón de reiniciar como administrador está.
- [ ] Los módulos que necesitan permisos **se anuncian como no disponibles**, en vez de fallar en
      silencio o proponer cosas que luego no se pueden borrar.
- [ ] Al eliminar, lo que no se pueda por permisos sale **en rojo con su motivo**.

### 6.3 · OneDrive con archivos bajo demanda — `COR-03`

Inicia sesión en OneDrive dentro de la VM, sube una carpeta con archivos grandes y libera espacio
(clic derecho → *Liberar espacio*): quedan como marcadores de posición.

- [ ] Un análisis completo **no dispara descargas**. Mira el icono de OneDrive: no debe ponerse a
      sincronizar.
- [ ] El módulo de duplicados **dice cuántos archivos se saltó** por estar en la nube. Es el que
      calcula hashes, o sea el que los materializaría.
- [ ] El de archivos grandes no promete espacio que en el disco no está.

---

## 8. Lo que la integración continua NO puede ver

Después de `VAL-03`, esto es lo que sigue necesitando la máquina virtual y tus ojos:

1. **`COR-01` entero** — bajar la cuota de la papelera a 100 MB, marcar `volcado-enorme.dmp` y ver
   que **no se borra**, que se dan las dos cifras y que el registro no dice `PAPELERA`. Se dejó
   fuera de la CI a propósito: quien lee la cuota pasa por una clase CIM que exige elevación, y si
   un día el agente dejara de estar elevado la comprobación **se invertiría sola y en silencio**,
   hacia el lado que no avisa.
2. **`COR-03`, OneDrive** — necesita cuenta y archivos bajo demanda.
3. **Todo lo visual**: desplazamiento con miles de filas, marcar en lote, el diálogo de confirmación
   con los comandos externos enteros, lo que falló en rojo y todavía marcado, y detener a mitad.
4. **Accesibilidad**: el Narrador, los atajos, la tabulación.
5. **Cuenta sin privilegios**: el agente va elevado.
6. **La memoria de dos análisis seguidos**: la CI compara los recuentos e imprime la memoria, pero no
   falla por ella — un recolector de basura no promete cuándo devuelve memoria, y un umbral ahí sería
   un paso que falla algunos días.

---

## 7. Al terminar

```powershell
.\tools\Banco-Pruebas.ps1 -Quitar
```

Y **restaura la instantánea igualmente**. `-Quitar` recoge los cebos que montó él; no devuelve lo
que borró Cachivache, que es el objetivo del ejercicio.

Lo que se encuentre va a `docs/HOJA-DE-RUTA.md` con identificador propio. La primera ejecución en
Windows (`VAL-01`) encontró **cuatro fallos en dos ejecuciones** que ninguna prueba veía. Esa es la
tasa de retorno de mirar la pantalla, y no hay motivo para pensar que la de mirar un borrado real
sea menor.
