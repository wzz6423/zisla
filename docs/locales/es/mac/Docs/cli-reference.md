# Referencia de integración de `zislactl`

**Español** | [Idiomas de la documentación](../../../README.md)

`zislactl` es el protocolo local compartido de estado de herramientas IA, scripts y tareas CI integradas con zisla. Escribe estado, uso y notificaciones como datos estructurados y los persiste mediante transacciones SQLite para evitar escrituras parciales. Aquí se definen proveedores, comandos y restricciones estables.

## Principios de diseño

- El estado se escribe localmente y nunca sube instrucciones, respuestas ni credenciales.
- Actualizaciones del mismo ID son idempotentes; los lectores ven el estado completo confirmado.
- Los nombres admiten alias compatibles pero se guardan en su forma canónica.

## Persistencia local y límites JSON

Tareas, uso y avisos viven en `~/Library/Application Support/zisla/ai-state.sqlite`. Las escrituras usan transacciones; el protocolo actual no escribe `ai-state.json`. Borrar tareas conserva uso.

`zislactl` acepta opciones documentadas y `list` imprime texto por líneas. Integraciones y configuración siguen usando JSON estructurado, incluidas sesiones JSON/JSONL externas y codificación/decodificación de ajustes, con sus propias reglas. La CLI usa argumentos, salida de texto y SQLite.

## Proveedores

| Valor | Alias |
| --- | --- |
| `claude` | `claude-code`, `claude-cli`, `claude-desktop` |
| `codex` | `openai-codex`, `codex-cli`, `codex-desktop` |
| `gemini` | `google-gemini`, `gemini-cli`, `gemini-code-assist` |
| `grok` | `grok-cli`, `xai` |
| `gpt` | `openai`, `chatgpt`, `openai-gpt` |
| `copilot` | `github-copilot`, `copilot-cli`, `copilot-chat` |
| `kimi` | `kimi-code`, `kimi-code-cli`, `kimi-vscode` |
| `qwen` | `tongyi`, `qwen-code`, `qwen-code-cli`, `qwen-vscode` |
| `coder` | `qoder`, `qoder-cli`, `qoderwork`, `qoderwork-cn`, `qoderwake`, `qwen-coder` |
| `zcode` | `z-code`, `zcode-cli`, `zcode-desktop`, `glm`, `glm-coding`, `z-ai`, `z.ai` |
| `trae` | `trae-work`, `traework`, `trae-solo`, `trae-cn` |
| `opencode` | `open-code`, `open_code` |
| `pi` | `pi-coding`, `pi-coding-agent`, `pi-cli`, `pi-agent` |
| `harness` | `harnext`, `harnext-cli`, `harness-cli` |
| `doubao` | `豆包` |
| `delta` | `delta-app`, `delta-desktop`, `zed-delta` |
| `orca` | `orca-desktop`, `orca-ide` |
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`, `workbuddy ai` |

WorkBuddy y WorkBuddy AI son productos distintos para los mercados nacional/internacional,
no versiones antigua/nueva de un cliente. Proveedores canónicos, almacenes, iconos y enlaces profundos
deben permanecer separados. Los registros históricos WorkBuddy con `harness` siguen legibles;
el proveedor no se renombra ni migra globalmente. Los ID de aviso de actividad usan
un límite explícito proveedor/tarea (`ai-active-workbuddy:<id>` o `ai-active-workbuddy-ai:<id>`),
para no confundir una tarea manual WorkBuddy con ID que empieza `ai-` con WorkBuddy AI.

### Detección automática de Delta, Orca, WorkBuddy y WorkBuddy AI

- Delta lee metadatos indexados de hilos en streaming de `Library/Application Support/Delta/user_*/data.sqlite`
  y la base raíz antigua. Excluye hilos archivados, inactivos y obsoletos. El uso numérico viene
  del registro `app_model_usage_daily`, incluidas lecturas y escrituras de caché. Sin ese registro,
  la versión no informa uso automático ni calcula cifras a partir de conversaciones.
- Orca lee instantáneas locales `agent-hooks/last-status.json` y estado actual de turnos estructurados
  de `agent-session-journal.db`, incluidos perfiles y registros de turnos v1/v2/v3.
  Respeta revisiones más altas y orden original. Excluye sesiones completas, vencidas, remotas
  y de solo identidad. Rutas autoritativas de transcripción y directorios fijados de cuentas Claude/Codex
  también contribuyen tokens. Esas muestras conservan proveedor CLI y
  identidad del evento, evitando doble conteo del detector habitual. Las cachés de uso de Orca
  para toda la máquina no se importan deliberadamente como uso adicional.
- WorkBuddy lee su propia `~/.workbuddy/workbuddy.db` con proveedor `workbuddy`,
  icono WorkBuddy y enlaces `workbuddy://chat/<id>`. No inspecciona WorkBuddy AI.
- WorkBuddy AI lee estado, títulos, modelo y marcas de tiempo desde
  `~/.workbuddy-ai/workbuddy.db`, independientemente de `~/.workbuddy/workbuddy.db`.
  Excluye sesiones terminadas, eliminadas y obsoletas; el valor más reciente de `updated_at` y
  `last_activity_at` mantiene visibles las sesiones largas. Usa proveedor `workbuddy-ai`,
  icono WorkBuddy AI y enlaces `workbuddy-ai://chat/<id>`. Solo detecta sesiones:
  `session_usage.used` es ocupación de contexto y créditos no son USD/tokens, por lo que ninguno
  se importa como tokens facturados. El uso numérico manual se informa con `zislactl usage`.
- Todas las integraciones son de solo lectura y según disponibilidad; almacenes ausentes o incompatibles no aportan datos.
  No consultan cuerpos replicados de Delta ni mensajes del diario Orca. Usa `zislactl usage`
  para versiones o herramientas sin uso numérico registrado.

## Sintaxis de opciones

- Escribe `--key value` o `--key=value`. Cada opción aparece una vez por comando; repetirla produce error de uso, código 64.
- Un valor puede empezar con `--`, como `--detail --verbose`. Excepto indicadores del propio comando: `--failed` de `finish` y `--queued` de `update` nunca son valores. Así una variable vacía sin comillas en `--detail $DETAIL --failed` aún marca fallo. Pasa el literal como `--detail=--failed`.
- `--failed` y `--queued` son indicadores. Solos significan verdadero; `--failed=false` o `--failed false`, igual con `--queued`, los apagan. Otro valor es error de uso.

## `update`

Crea o sustituye una tarea con el mismo `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Sin `--progress`, la interfaz muestra progreso indeterminado.
- `--pid` es opcional y solo se proporciona si el llamante identifica el proceso.
- `--status` informa ejecución, cola, espera de usuario o error durante ejecución.
- `--queued` equivale a `--status queued`; sin estado explícito, la tarea está en ejecución. Un `--status` explícito tiene prioridad sobre `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Tareas correctas pasan a 100 %; las fallidas conservan su último progreso.

## `remove`

```text
zislactl remove --id <id>
```

Sale con código 65 si no existe la tarea.

## `clear`

```text
zislactl clear
```

Borra tareas y conserva historial y notificaciones.

## `list`

```text
zislactl list
```

Imprime estado, proveedor, título y porcentaje una línea cada vez.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

El uso alimenta el gráfico de 12 horas y mapa 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

El aviso aparece del lado elegido y pausa el cierre al pasar el puntero.

## `message`

Envía un aviso a ambos lados: izquierda muestra logo y remitente, derecha desplaza el cuerpo.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Ejemplo:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender` y `--content` son obligatorios; `--app-bundle-id` es opcional y ayuda a resolver el icono instalado.
- Se colapsan saltos y espacios sobrantes y se trunca a unos 48 caracteres con puntos suspensivos.
- Una transacción SQLite guarda ambas entradas `IslandNotice` sin cambiar `notify`.

## Códigos de salida

| Código | Significado |
| --- | --- |
| `0` | Éxito |
| `64` | Argumento o subcomando inválido |
| `65` | Error de datos, tarea ausente o base corrupta |
| `70` | Error del sistema de archivos u otro error de ejecución |
