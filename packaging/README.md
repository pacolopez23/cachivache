# Empaquetado — winget y Scoop

Aquí no hay ningún manifiesto guardado, y es a propósito.

## Por qué esta carpeta está casi vacía

Un manifiesto de winget y uno de Scoop declaran cuatro datos que cambian en **cada** versión:

| Dato | winget | Scoop |
|---|---|---|
| La versión, sin la `v` | `PackageVersion` | `version` |
| La URL de descarga | `InstallerUrl` | `url` |
| La carpeta que hay **dentro** del `.zip` | `NestedInstallerFiles` → `RelativeFilePath` | `extract_dir` |
| El SHA-256 del `.zip` | `InstallerSha256` | `hash` |

Un manifiesto escrito a mano con los datos de la versión anterior **no falla en ningún sitio**: pasa
las pruebas, pasa el analizador, se lee perfectamente y se sube tal cual. Falla en el equipo de quien
lo instala, y lo que su gestor de paquetes le dice es que el archivo descargado no coincide con lo
declarado — es decir, le dice que el paquete está adulterado.

Es la misma familia de fallo silencioso que cerró `DIS-02`, y se resuelve igual: **el dato sale una
sola vez, del archivo real, y de ahí lo copia todo el mundo.**

La carpeta interior es la que más fácil se olvida. `Compress-Archive` no comprime el contenido de la
carpeta, comprime la carpeta: al descomprimir no aparece `Cachivache.exe`, aparece
`Cachivache-v2.1.0\Cachivache.exe`. Ese nombre lleva la versión dentro.

## Dónde está entonces el manifiesto

- El formato lo decide `tools/Manifiestos.ps1`, que es cálculo puro y va probado en
  `tests/Paquetes.Tests.ps1`.
- Los archivos los escribe `tools/Publicar-Manifiestos.ps1`, que calcula el hash del `.zip` real —
  no admite un `-Hash` por parámetro, justamente para que no se le pueda pasar uno copiado a mano.
- `.github/workflows/publicar.yml` lo ejecuta al publicar una etiqueta, comprueba que lo escrito
  declara el paquete que se va a subir, y adjunta los cuatro archivos a la versión.

Para verlos sin publicar nada:

```powershell
.\tools\Publicar-Manifiestos.ps1 -Etiqueta v2.1.0 -Paquete .\Cachivache-v2.1.0.zip
```

Quedan en `packaging\winget\` y en `packaging\cachivache.json`. **Son artefactos: no se versionan.**

## Cómo se envían

Ninguno de los dos canales admite envío automático desde aquí, así que los dos son un paso manual —
una vez por versión, con los archivos ya generados delante.

**winget.** Los tres `.yaml` van a `microsoft/winget-pkgs`, en
`manifests/f/FranciscoLopez/Cachivache/<versión>/`. La forma cómoda es
`wingetcreate submit packaging\winget`. El paquete es un `.zip` portable (`InstallerType: zip` +
`NestedInstallerType: portable`), así que **no hace falta firma de código** para que lo acepten: no
se ejecuta ningún instalador, se descomprime y se crea un alias. Por eso `DIS-03` no depende de
`DIS-01`.

**Scoop.** `cachivache.json` va a un *bucket*, que es un repositorio de git con los manifiestos
dentro. Mientras no exista, el JSON adjunto a cada versión ya se puede instalar directamente:

```powershell
scoop install https://github.com/pacolopez23/cachivache/releases/download/v2.1.0/cachivache.json
```

El manifiesto lleva `checkver` y `autoupdate` aunque se regenere en cada publicación. Son para el día
en que esto se olvide: si alguien mete el `.json` en un bucket y deja de regenerarlo, Scoop se
actualiza solo mirando las versiones de GitHub, y saca el hash del `SHA256SUMS.txt` de la versión en
vez de creerse el que tenga escrito.

## Lo que no está verificado

Nada de esto se ha ejecutado en GitHub Actions, no se ha enviado a `winget-pkgs` y no se ha instalado
con `winget` ni con `scoop`. Lo que sí está comprobado es el formato exacto que producen las
funciones y que el flujo de publicación las usa; lo demás se sabrá en la primera etiqueta.
