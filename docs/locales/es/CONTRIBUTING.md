# Contribuir a zisla

**Español** | [Idiomas de la documentación](../README.md)

Gracias por contribuir a zisla.

## Issues

Gracias por abrir una issue. Busca primero en Issues y Discussions existentes para evitar informes duplicados.

- Usa `[Bug] Short problem description` para errores, por ejemplo `[Bug] Voice input is not written to the current text field`. Incluye versión de zisla, versión de macOS y dispositivo, instalación, pasos de reproducción, comportamiento esperado y real.
- Usa `[Feature] Short request description` para funciones, por ejemplo `[Feature] Support custom voice-organization prompts`. Describe el problema, la solución propuesta y alternativas consideradas.
- Elige una **Area** en el formulario. Es obligatoria y determina `area:*`: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` o `Community & Discussion`. Los formularios en chino simplificado ofrecen las mismas opciones y etiquetas.
- Elimina tokens, datos de cuenta, rutas locales y otra información sensible de registros, capturas y grabaciones.
- Informa de vulnerabilidades en privado mediante [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), no con una issue pública.
- La automatización aplica `bug` o `enhancement` junto con `area:*` correspondiente y no altera otras etiquetas. Si el prefijo o un campo requerido no sigue el formulario, añade `needs-more-info` y mantiene un comentario con lo que falta; al editar la issue, el comentario se actualiza.

## Desarrollo

La implementación macOS está en `mac/` y requiere macOS 14+ con Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Elimina binarios de pruebas, compilación y empaquetado antes de hacer commit.

Antes de cada commit o amend, ejecuta `make format` en la raíz con SwiftFormat 0.64.7, igual que CI. Revisa diferencias y conserva solo el formato necesario para la tarea.

## Ramas y commits

- Crea ramas desde el último `main` con prefijo del tipo declarado en la PR: `feat/` o `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/` o `revert/`, como `fix/download-timeout` o `ci/skip-directive-timing`.
- Usa [Conventional Commits](https://www.conventionalcommits.org/) en inglés, como `type(scope): description` o `fix(ui): resolve layout issue in notch area`.
- Centra una rama y PR en un objetivo claro; evita cambios solo de formato y refactorizaciones ajenas.
- Las ramas `publish-v*` están reservadas para mantenimiento de publicaciones. Las demás contribuciones se envían a `main`.

## Pull requests

Gracias por abrir una pull request. Comprueba estos requisitos mientras espera revisión.

- El **título de PR** debe ser un asunto Conventional Commit en inglés, por ejemplo:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Tipos permitidos: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci` y `revert`.

- El **cuerpo de PR** debe estar en inglés y contener `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue` y `AI Attribution` de `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` conserva `- Project: zisla Development`. `Project Automation` lo lee para colocar la PR en el tablero compartido.
  - `Start date` y `Target date` son obligatorias en `GitHub Project`. Declara cada una exactamente una vez como fecha real `YYYY-MM-DD`; `Target date` debe ser igual o posterior a `Start date`. Fechas ausentes, vacías, comentadas, duplicadas o inválidas fallan `PR Quality`. `Submitted date` usa creación en UTC+08:00 y `End date` se rellena al fusionar; no se introducen manualmente.
  - `PR Type` declara exactamente un `- Type:` que se resuelve al tipo del título. Títulos usan tipos canónicos; cuerpo acepta etiquetas y alias configurados: `fix`, `bug`, `bug fix`, `bugfix` y `hotfix` resuelven a `fix`. `PR Automation` lo convierte en etiqueta, por ejemplo `fix` en `bug`.
  - `Project Automation` elige `Status` según mapeo de etiquetas, incluido tipo PR, y establece `Done` al cerrar o fusionar. No introduzcas `Status` manualmente.
  - `Summary` describe el cambio; `Risk and Rollback` necesita exactamente un `Risk` no vacío y un `Rollback` no vacío.
  - Cada entrada de `Validation` empieza con su propio `- Status:` que declara exactamente `passed`, `failed` o `not run`. Cada `passed` o `failed` tiene `Command` y `Result` propios no vacíos; cada `not run` tiene `Reason` propio no vacío. Campos de otras entradas no satisfacen el requisito. Informa de fallos honestamente con `failed`.
  - `Related Issue` cierra una issue con palabras como `Closes #123`, aplicando también `development`, o es exactamente `None`.
  - `AI Attribution` declara exactamente un `- Agent:` no vacío. Cualquier agente distinto de `None` requiere `- Co-authored-by: Name <email>` correspondiente, también como trailer en al menos un commit, y aplica `ai-assisted`.

  Ejemplo de título: `fix(ci): validate every PR metadata entry`

  Ejemplo de cuerpo; registra resultados reales:

  ```markdown
  ## Summary
  - Validate every PR metadata field and each Validation entry independently.
  - Keep contributor welcome replies aligned with the current PR template.

  ## GitHub Project
  - Project: zisla Development
  - Start date: 2026-10-05
  - Target date: 2026-10-12
  <!--
  Automatic Project fields (illustration only; not PR body inputs):
  - Submitted date: 2026-10-05 (PR creation date in UTC+08:00)
  - End date: 2026-10-12 (assumed merge date in UTC+08:00; blank before merge)
  Automation updates Project date fields and the PR Timeline; it does not fill these comment lines.
  -->

  ## PR Type
  - Type: fix

  ## Validation
  - Status: passed
  - Command: ruby .github/scripts/pr-metadata-test.rb
  - Result: All PR metadata contract tests passed.

  - Status: passed
  - Command: ruby .github/scripts/contributor-welcome-test.rb
  - Result: Both documented examples pass PR validation and the welcome reply preserves the complete example.

  - Status: passed
  - Command: actionlint .github/workflows/*.yml
  - Result: All workflow files passed actionlint.

  - Status: not run
  - Reason: Local macOS tests were not run because this change only affects PR metadata and contributor guidance. Platform checks still run in CI.

  ## Risk and Rollback
  - Risk: Stricter metadata checks may reject incomplete PR descriptions; no application behavior changes.
  - Rollback: Revert this pull request to restore the previous metadata checks and guidance.

  ## Related Issue
  None

  ## AI Attribution
  - Agent: Codex
  - Co-authored-by: Codex <noreply@openai.com>
  ```

  Ejemplo de fechas: PR creada el 2026-10-05 y fusionada el 2026-10-12, UTC+08:00. Campos automáticos del comentario de código ilustran valores Project; no son entradas. Automatización actualiza GitHub Project y cronología PR, no esas líneas de muestra.

  | Fecha | Al crear (2026-10-05) | Tras fusionar (2026-10-12) | Fuente |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Entrada obligatoria |
  | `Target date` | 2026-10-12 | 2026-10-12 | Entrada obligatoria |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Fecha de creación automática |
  | `End date` | Vacío | 2026-10-12 | Fecha de fusión automática |

- `PR Quality` valida el formato; no se fusiona una PR mientras falla. `PR Automation` aplica etiquetas y asigna la PR después.
- Ejecuta `cd mac && swift test` para cambios de código macOS; describe resultados de verificación manual en texto para cambios de interfaz.
- Cuerpos PR y notas de publicación pueden ser solo texto; no necesitan imágenes, capturas ni portadas.
- Actualiza documentación formal y ayuda web en el mismo parche al cambiar funciones, comportamiento, valores predeterminados, compilación o publicación. Los textos web para usuarios cubren 17 idiomas; reutiliza ayuda y directorio localizado existentes.
- No confirmes `.build`, `dist`, descargas, registros, tokens, materiales de firma ni datos personales.
- `main` y `publish-v*` están protegidas y solo cambian mediante PR revisada que supera sus controles.

## Omitir CI

Mantenedores y revisores solicitados pueden omitir controles que el cambio no afecta, como una corrección documental. Escribe la directiva sola en una línea de comentario PR:

| Directiva | Efecto |
| --- | --- |
| `skip-all` | Omite todos los flujos de `.github/ci-skip.json`. |
| `skip-<workflow>` | Omite un flujo por nombre, archivo o alias, como `skip-swift`, `skip-web-ci` o `skip-Web CI`. |
| `unskip-all` | Borra todas las directivas de omisión. |
| `unskip-<workflow>` | Restaura un flujo. |

- Puede seguir texto libre, como `skip-all: documentation only change`.
- Puede usarse el nombre GitHub con espacios; `skip-CI Lint` y `skip-lint` son iguales. Gana el nombre coincidente más largo y el resto forma la nota.
- Solo se aceptan directivas del propietario, miembro de organización, colaborador o revisor solicitado. Se ignoran bots.
- `CI Skip` cancela ejecuciones activas, informa controles omitidos como correctos para cumplir requisitos, aplica `skip-ci` y edita un comentario resumen con decisión actual.
- Se reproduce todo el hilo en cada comentario; gana la directiva más nueva.
- La directiva vence al enviar un commit nuevo: solo cubre el código visto por el autor, o un éxito permitiría fusionar código nuevo sin compilar. `CI Skip` se ejecuta en cada push, quita `skip-ci`, restaura controles y lista directivas vencidas. Coméntala otra vez para omitir también el commit nuevo.
- Un mantenedor puede reaplicar decisión sin comentario nuevo desde **Actions -> CI Skip -> Run workflow**, pasando número PR.
- `.github/ci-skip.json` mapea flujos a nombres de controles. `CI Checks` falla si manifiesto y archivos difieren.

## Controles por ruta

Un flujo de plataforma solo verifica cuando la PR toca sus archivos de compilación; la documentación se comprueba según ruta:

| Flujo | Se ejecuta al tocar |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- `paths` de `.github/ci-skip.json` define ámbitos; sin campo, se ejecuta siempre. `CI Lint`, `PR Quality Gates`, `CodeQL` y `Dependency Review` corren en cada PR. Higiene y validación de skills forman `CI Checks`; alias antiguos `hygiene` y `skills` ya no se usan.
- Cambiar cualquier `.github/` ejecuta todo, porque CI debe probarse en todas las plataformas.
- Los jobs se omiten con condición de job y no filtro `paths:` del flujo, así el control requerido informa éxito en vez de quedar pendiente.
- Archivos renombrados coinciden por ruta antigua y nueva, ignorando mayúsculas.
