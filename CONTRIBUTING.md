# Cómo contribuir

Gracias por querer echar una mano. Este documento es corto a propósito.

---

## Antes de nada

Este es un programa que **borra archivos en el equipo de otra persona**. Esa frase gobierna todas las decisiones del proyecto. Si una aportación mejora la potencia a costa de la prudencia, la respuesta va a ser que no.

Tres principios que no se negocian:

1. **La seguridad no se discute con la comodidad.** Ante la duda, no se borra.
2. **El usuario tiene que entender qué está aceptando.** Todo candidato explica qué es y qué pasa si desaparece.
3. **Nada arriesgado viene marcado.** Si hace falta criterio humano, hace falta un humano.

---

## Preparar el entorno

No hay nada que instalar para ejecutar el programa. Para desarrollar sí conviene:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

Antes de abrir un pull request:

```powershell
.\tools\Probar.ps1
```

Un solo comando: la suite, el analizador y el suelo de cobertura. Tiene que salir **TODO EN VERDE**,
y el informe queda en `pruebas\ultima-pasada.txt`. La CI ejecuta este mismo guion, y además pasa la
suite en Windows con PowerShell 5.1 y con 7.

Si añades una función a `src\`, escríbele una prueba que la nombre. Si de verdad no se puede probar
aquí —lo único con ese problema hoy es lo que necesita WPF—, añádela a
`tests\datos\deuda-de-pruebas.txt` con su motivo. La lista solo puede encoger.

### Desarrollar fuera de Windows

La suite entera pasa en Linux y en macOS con PowerShell 7, y eso hace el bucle de desarrollo
mucho más rápido: unos 16 segundos frente a levantar una máquina Windows.

```bash
# PowerShell 7 desde el tarball oficial, sin permisos de administrador
curl -sL -o ps.tar.gz https://github.com/PowerShell/PowerShell/releases/download/v7.6.5/powershell-7.6.5-linux-x64.tar.gz
mkdir -p ~/pwsh && tar -xzf ps.tar.gz -C ~/pwsh && chmod +x ~/pwsh/pwsh
~/pwsh/pwsh -Command "Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck"
```

Las pruebas están escritas para no depender del sistema: las que necesitan registro de Windows,
`Get-AppxPackage` o rutas de `Archivos de programa` sustituyen esas dependencias por variables de
entorno controladas o por `Mock`. Por eso hay dos reglas que conviene respetar al añadir pruebas:

- **Nada de `Join-Path` con una letra de unidad.** Join-Path resuelve la unidad a través del
  proveedor de PowerShell y lanza si `C:` no existe como unidad real. Se concatena texto, como ya
  hacen `Get-EjecutableDeComando` y `Resolve-EjecutablePermitido`.
- **Los archivos de prueba son ASCII puro.** Los caracteres acentuados se construyen por código
  (`[char]0x00E1`), para que la codificación del archivo no cambie lo que se prueba. Justo eso es
  lo que hizo falta para destapar `[SEG-10]`, el agujero de las carpetas personales con tilde.

Lo que **no** se puede comprobar fuera de Windows: WPF, el registro real, la papelera de reciclaje
y DISM. Eso lo cubre la CI, que sigue siendo la palabra final antes de publicar.

**Y si has tocado la interfaz, pasa [`docs/PRUEBA-MANUAL.md`](docs/PRUEBA-MANUAL.md).** Las pruebas automáticas no pueden arrancar WPF, así que hay una parte del programa —justo la que el usuario toca— que solo se comprueba abriéndolo. Esa lista dice qué mirar y, si algo no cuadra, a qué mirar primero.

---

## Añadir un módulo de limpieza

Es lo más habitual y lo más fácil: un archivo nuevo en `src/Modules/`, sin tocar nada más. La guía completa, con plantilla, está en [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

Lo que se va a mirar en la revisión:

- [ ] ¿Las raíces declaradas son lo más específicas posible?
- [ ] ¿Se llama a `Test-RutaSegura` antes de proponer cada candidato?
- [ ] ¿Los bucles largos comprueban `Test-Cancelacion`?
- [ ] ¿El campo `Efecto` explica la consecuencia en castellano llano, sin jerga?
- [ ] ¿El riesgo asignado es honesto? Ante la duda, sube un nivel.
- [ ] ¿Hay algún caso en que esto podría borrar trabajo de alguien? Si lo hay, `-Aviso`.
- [ ] ¿Está documentado en `docs/MODULOS.md`?

---

## Tocar la guardia de seguridad

`src/Core/Guard.ps1` es el archivo más delicado del proyecto. Si lo modificas:

- **Añade pruebas antes que código.** Escribe primero el caso que quieres cubrir en `tests/Guard.Tests.ps1`.
- **Todas las pruebas existentes tienen que seguir pasando.** Ninguna se relaja para que pase un cambio nuevo. Si un cambio las rompe, el problema está en el cambio.
- **Explica el porqué en el PR.** Qué ruta se estaba bloqueando de más o de menos, y cómo lo reprodujiste.

Ampliar las listas negras es bienvenido siempre. Reducirlas necesita una justificación muy buena.

---

## Estilo

El código está en castellano: nombres de función, variables, comentarios y mensajes. Mantenlo así aunque cueste un poco al principio, porque la mezcla es peor que cualquiera de las dos opciones.

- Verbos aprobados de PowerShell: `Get-`, `Set-`, `New-`, `Test-`, `Invoke-`, `Export-`, `Import-`, `Remove-`, `Clear-`, `Measure-`, `Format-`.
- Cuatro espacios de sangría, nunca tabuladores. Líneas de hasta 100 caracteres.
- Comentario de ayuda (`.SYNOPSIS`, `.DESCRIPTION`) en toda función pública.
- **Los comentarios explican el porqué, no el qué.** `# incrementa el contador` sobra; `# Windows tarda un instante en soltar los descriptores` no.
- Compatible con PowerShell 5.1: nada de operador ternario, `??`, `-Parallel` ni sintaxis de 7.x.
- Sin caracteres no ASCII en los archivos `.ps1`, para que la codificación nunca sea un problema. En los textos de la interfaz se escribe "anyadir" y "pestanya"; en los `.md` sí se usan acentos con normalidad.

---

## Informar de un fallo

Abre una incidencia con:

- La salida de `.\Cachivache.ps1 -Diagnostico` (versión, entorno, unidades y el final del registro, todo junto).
- Perfil y módulos con los que ocurrió.
- Qué esperabas y qué pasó.

**Si has encontrado una ruta que el programa propone y no debería, eso no es un fallo normal: es lo más importante que puedes reportar.** Léete [`SECURITY.md`](SECURITY.md) antes de publicarla.
