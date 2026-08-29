## Qué cambia

<!-- Una o dos frases. Si arregla una incidencia: Cierra #123 -->

## Por qué

<!-- El problema que resuelve. Si es un módulo nuevo, cuánto espacio recupera
     en un equipo real y qué pasa exactamente si se borra. -->

## Cómo lo has probado

<!-- En qué versión de Windows, con qué perfil, qué encontró. -->

---

## Comprobaciones

- [ ] `Invoke-Pester ./tests` pasa entero
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` sale limpio
- [ ] He probado el cambio en un equipo real, no solo las pruebas
- [ ] El código sigue siendo compatible con PowerShell 5.1
- [ ] Los archivos `.ps1` siguen sin caracteres no ASCII

### Si toca la guardia de seguridad (`src/Core/Guard.ps1`)

- [ ] He añadido pruebas nuevas en `tests/Guard.Tests.ps1` **antes** del arreglo
- [ ] Las pruebas de la guardia siguen pasando, ninguna se ha relajado
- [ ] Explico abajo qué ruta se bloqueaba de más o de menos y cómo lo reproduje

### Si añade un módulo

- [ ] Las raíces declaradas son lo más específicas posible
- [ ] Llama a `Test-RutaSegura` antes de proponer cada candidato
- [ ] Los bucles largos comprueban `Test-Cancelacion`
- [ ] El campo `Efecto` explica la consecuencia sin jerga
- [ ] Lo que exige criterio humano lleva `-Aviso` y no viene marcado
- [ ] Está documentado en `docs/MODULOS.md`
