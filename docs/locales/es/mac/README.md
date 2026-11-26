# zisla para macOS

**Español** | [Idiomas de la documentación](../../README.md)

Este directorio contiene la implementación macOS de zisla. Mueve el puntero al centro superior para desplegar la isla y aléjalo para ocultarla. La aplicación usa AppKit `NSPanel`, SwiftUI y servicios por eventos, sin ventana transparente permanente de activación ni bucle de fotogramas mientras está oculta.

Los destinos Swift, el identificador del paquete, el directorio local y `zislactl` usan el identificador zisla. Las actualizaciones migran automáticamente datos y preferencias de versiones anteriores.

Se admite macOS 14 y posteriores. macOS 26 usa Liquid Glass; macOS 14/15 recurren al material nativo del sistema.

## Funciones

### 12 módulos de la isla

| Módulo | Funciones implementadas |
| --- | --- |
| Inicio | Resume a demanda el Pomodoro actual, la primera tarea activa de IA, descargas nativas y progreso de varias descargas del navegador. |
| Sonidos y estadísticas del teclado | 20 sonidos integrados; interruptores independientes para estadísticas locales, tendencias, cronología por aplicación y mapa de calor por tecla. |
| Transferencia | Arrastra archivos, contenido multimedia o enlaces a la zona superior para guardarlos en la bandeja, mostrarlos en Finder o abrir compartir. Las capturas guardadas tienen tarjetas azules de doble anchura y categoría propia, con copia de imagen, exportación PNG y eliminación. Comprime archivos y carpetas seleccionados en ZIP, redimensiona o convierte imágenes seleccionadas en Herramientas de imagen y devuelve los resultados correctos a la bandeja, o importa imágenes, vídeo y audio seleccionados a la biblioteca del estudio manteniendo proyecto y cronología actuales. |
| Portapapeles | Guarda historial local buscable, filtra imágenes, URL y archivos y marca favoritos; historial y detección de enlaces son independientes. Las nuevas imágenes se ponen en cola para reconocimiento de texto en el dispositivo; busca su texto para encontrar la imagen original o haz clic derecho para reconocerlo o copiarlo. Puedes cancelar el reconocimiento en curso; el reconocimiento de fondo no copia texto automáticamente. |
| Supervisión de IA | Agrupa tareas, estados, tendencias de tokens, mapas de calor de contribuciones y avisos de CLI, aplicaciones e IDE compatibles. |
| Descargas | Usa `yt-dlp` para vídeo y audio; sin `ffmpeg`, AVFoundation empaqueta pistas compatibles y existe una alternativa de Bilibili de solo lectura. |
| Agenda | Muestra tiempo actual y hasta seis ubicaciones guardadas; consulta, crea y elimina eventos y recordatorios y marca los recordatorios como completados. |
| Correo | Lee cuentas de Mail.app seleccionadas para ver entradas, marcar leído, responder, redactar y mover mensajes a la papelera. |
| Notas | Usa Notas de Apple como única fuente para consultar, editar, crear y eliminar Markdown con vista previa en directo y escritura automática. |
| Mezclador de volumen de aplicaciones | En macOS 14.4+, ajusta volumen y silencio de cada aplicación en reproducción y recuerda su volumen; requiere grabación de audio del sistema. |
| Utilidades | Pomodoro con un aviso sonoro y notificación local al finalizar, mantener despierto, prevenir reposo por inactividad, limpiar pantalla y teclado, teleprompter, espejo de cámara y vaciado confirmado de papelera. |
| Sistema | CPU, GPU, memoria, disco, red, temperatura y ventiladores; libera memoria y analiza cachés, registros y temporales seguros de eliminar; incluye salud de batería y niveles de accesorios. |

### Funciones entre módulos

- **Reproducción actual:** MediaRemote muestra carátula, título, progreso, letra desplazable y controles; Core Audio identifica la fuente real como alternativa. Las fuentes pausadas, detenidas o silenciadas se ocultan.
- **Descargas del navegador:** Muestra fuente y progreso de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera y Arc en Inicio, estado contraído y avisos laterales.
- **Entrada de voz:** Atajos con alternancia o pulsar para hablar, atajos globales personalizados, reconocimiento del sistema, organización local o remota e historial local.
- **Acciones rápidas:** Tras cada copia, un pequeño aviso de la isla ofrece vista previa enriquecida y acciones: abrir enlaces, mostrar archivos en Finder, buscar con motor elegible, traducir, calcular, crear eventos desde fechas y guardar textos largos o imágenes. Tras una descarga o AirDrop, el mismo atajo abre la carpeta; lo controla Acciones rápidas independientemente del progreso del navegador. Reconoce URL, rutas, correos, teléfonos, colores CSS con muestra en vivo, aritmética, fechas y horas, texto de idioma distinto al sistema, código, texto con recuentos, miniaturas de imagen y referencias de archivos. Se activa por botones, el atajo adicional predeterminado Command+N o modificador/botón lateral configurado. Incluye gesto de copia manteniendo botón izquierdo y clic derecho, desactivado por defecto, lista de aplicaciones excluidas, interruptores por tipo y modo ligero de recordatorio.
- **Gestión de CLI y Skills:** Detecta, instala, actualiza y elimina CLI de IA habituales y gestiona Skills locales en Ajustes.
- **Mascotas de escritorio:** Elige una mascota integrada o importada y colócala a cualquier lado de la isla.
- **Actualizaciones:** El canal Release o Preview resuelve una vez por ejecución el código de país de salida pública. `CN` consulta primero el appcast firmado de Gitee y reintenta GitHub una vez; otros códigos consultan GitHub y reintentan Gitee una vez. Si la consulta no está disponible, Gitee sigue primero. Sparkle descarga, verifica, instala y reinicia. Cambiar canal afecta comprobaciones automáticas y manuales.
- **Apariencia e interacción:** Ajustes sigue el sistema o usa tema claro u oscuro. La isla admite superficies transparentes o esmeriladas, expansión fijada, varios monitores, Spaces y pantallas externas sin muesca.
- **Valores predeterminados:** Las instalaciones nuevas habilitan los módulos. Cada función, indicador contraído, aviso lateral, métrica de menú y comportamiento de actualización se ajusta independientemente; las instalaciones anteriores conservan su configuración.

### Herramientas independientes y flujos

- **Estudio de grabación:** Ábrelo en barra de menús o Ajustes. Graba pantalla, ventana o región con audio del sistema, micrófono y cámara opcionales. Edita vídeo, audio, imágenes y texto en varias pistas, incluidos subtítulos, zooms, animaciones y efectos de retrato y voz; previsualiza antes de exportar vídeo, GIF, Live Photo o audio. Algunos formatos necesitan FFmpeg; HDR depende del dispositivo. Importa imágenes, vídeo y audio desde la estantería a la biblioteca manteniendo proyecto y cronología actuales.
- **Herramientas de imagen, audio y PDF:** Ábrelas desde Ajustes. Imagen tiene 9 operaciones locales y exportación por lotes/ZIP. Audio tiene 27 operaciones, incluidas mezcla, normalización LUFS y tratamiento de ruido, y requiere FFmpeg y ffprobe. PDF tiene 14 operaciones; Office necesita LibreOffice u OpenOffice.
- **Resumen diario:** Elige entre 8 plantillas y selecciona métricas en Ajustes, previsualiza y exporta PNG manualmente o a una hora diaria. Las métricas no disponibles no se presentan como cero medido.
- **Vistas previas de ventanas:** Pasa por Dock o cambia con Command+Tab y haz clic en una vista previa para activar su ventana. Gestiona función y permisos en Ajustes.
- **Notas contextuales y reuniones:** Mantén el atajo de nota y agita el puntero para adjuntar una nota a página, ventana o escritorio. Los eventos con enlaces muestran cuenta atrás 10 minutos antes; entra, crea una nota o vincula una existente. Gestiona las notas en la estantería.
- **Agitar para soltar:** Agita el puntero al arrastrar archivos para revelar el destino; activa el gesto de forma independiente.
- **Salida de audio y preferencias:** Elige dispositivo en el área multimedia. Ajustes selecciona fuente automática o reproductor preferido, diseño compacto y condiciones de parada del sonido ambiental.
- **Cuotas y reinicios de IA:** Supervisión y Ajustes muestran cuotas, horas de muestreo y reinicio y avisos de cuota baja, incluidas ventanas 5h/7d y presupuestos Cursor USD disponibles. Son distintos del historial local de tokens.

### Orden de teclado de acciones rápidas

El aviso asigna `Command+1` a `Command+9` y después `Command+0` según el orden de las acciones. El activador adicional predeterminado de configuraciones nuevas es `Command+N`, que ejecuta la primera acción; `Command+Delete` cierra el aviso. Configura activador, botón lateral y orden en Ajustes. Las actualizaciones conservan cada combinación guardada explícitamente, incluido el antiguo `Command+1`, atajos propios y activadores borrados; solo configuraciones nuevas o sin campo de activador adoptan `Command+N`.

### Ubicaciones de guardado

Ajustes → Ubicación de guardado elige carpetas independientes para descargas, capturas, herramientas de imagen, grabaciones, PDF, acciones rápidas y resúmenes. Las configuraciones nuevas usan subcarpetas de `~/Downloads`: `picture` para capturas/imágenes, `video` para grabaciones, `pdf`, `quick` y `daily`. Audio usa un diálogo de exportación para elegir archivo o carpeta. La estantería mantiene referencias a originales; capturas guardadas y estado de notas contextuales se gestionan en `~/Library/Application Support/zisla`, mientras los proyectos usan la carpeta de grabación. El texto de notas rápidas vive en Notas de Apple.

La [ayuda y guías paso a paso](https://wzz6423.github.io/zisla/help.html?lang=es#help) cubren nueve temas: portapapeles, captura, estantería, reuniones, IA, herramientas multimedia, resúmenes diarios, notas de escritorio/vistas previas y reproducción/mezcla, con fragmentos de vídeo.

### Atajos y almacenamiento de capturas

La acción **Guardar en bandeja** está entre **Fijar** y **Copiar**. Conserva la imagen final editada, incluidas anotaciones y capturas con desplazamiento completas, en Transferencia sin copiarla al portapapeles. PNG y metadatos, incluidos aplicación original y hora, se guardan localmente en SQLite y sobreviven al reinicio. **Capturas guardadas** solo muestra esas tarjetas.

**Resaltador** sigue a **Pincel** y dibuja resaltado translúcido; conserva líneas finales y marcadores circulares por defecto, desactivables en su menú. **Extraer** sigue a **Desenfocar** y admite extracción de sujeto o fondo de macOS y selección libre de cualquier zona. Varios contornos conservan su unión, con Seleccionar todo y Borrar; los píxeles no elegidos quedan transparentes y se puede deshacer. Las esquinas tienen radio 0 por defecto. Arrastra el control encima de la selección o usa **Radio de esquina**; la etiqueta muestra `r`. PNG tiene esquinas transparentes y volver a 0 restaura los píxeles originales.

| Contexto | Acción | Atajo predeterminado |
| --- | --- | --- |
| Global | Captura de pantalla | `Control+1` |
| Global | Captura con desplazamiento | `Control+2` |
| Editor de captura | Fijar | `Control+1` |
| Editor de captura | Guardar en bandeja | `Control+2` |
| Editor de captura | Rectángulo | `Control+3` |
| Editor de captura | Elipse | `Control+4` |
| Editor de captura | Pincel | `Control+5` |
| Editor de captura | Resaltador | `Control+6` |
| Editor de captura | Flecha | `Control+7` |
| Editor de captura | Número | `Control+8` |
| Editor de captura | Texto | `Control+9` |
| Editor de captura | Desenfocar | `Control+0` |
| Editor de captura | Extracción | `Control+A` |
| Editor de captura | Captura con desplazamiento | `Control+B` |
| Editor de captura | Copiar | `Enter` |
| Editor de captura | Guardar | `Command+S` |
| Editor de captura | Deshacer | `Command+Z` |
| Editor de captura | Rehacer | `Command+Shift+Z` |

Los ajustes muestran y registran atajos globales y del editor. Copiar, Guardar, Deshacer y Rehacer se muestran pero no se regraban. Los atajos del usuario se conservan al actualizar; Fijar es una acción del editor, no un atajo global independiente, y su menú sigue disponible.

Los atajos del editor siguen el orden de herramientas: `Control+1` a `Control+9`, `Control+0`, `Control+A`, `Control+B` y letras siguientes. La asignación omite `Q`, `M`, `N` y `W`: pulsar Command por error podría salir, minimizar, abrir o cerrar ventanas. Las combinaciones del usuario siguen permitidas.

Al actualizar, disposiciones antiguas intactas, incluida Fijar/Guardar en bandeja, pasan una vez a los valores anteriores. Si se personalizó cualquier atajo, se conserva la disposición; las acciones nuevas eligen una combinación Control libre en el mismo orden seguro si hay conflicto. Estas combinaciones iniciales también se pueden regrabar.

## Inicio rápido

### Entorno

- macOS 14+
- Swift 6 / Xcode 16+ (solo Command Line Tools también puede compilar)
- Opcional: `yt-dlp` y `ffmpeg`; Office a PDF también necesita LibreOffice u OpenOffice

Con Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Ejecutar desde el código fuente

```bash
swift run zisla
```

La aplicación inicia como accesorio de la barra de menús. Mueve el puntero a los 6 px del centro superior de la pantalla actual para desplegar o elige «Mostrar isla» en el icono de menú.

### Compilar una `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Para incluir el auxiliar oficial `yt-dlp`:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` descarga un archivo autónomo oficial macOS de versión fija y lo comprueba con `SHA2-256SUMS` oficial antes de instalar en `Tools/yt-dlp`.

## Integración de herramientas de IA

### Detección automática

zisla lee estado de sesiones público o local estable y extrae solo eventos estructurados y metadatos necesarios para determinar las tareas. No lee instrucciones ni contenidos de respuestas.

| Entorno | Detección automática |
| --- | --- |
| OpenAI / Anthropic | Codex CLI y Desktop, Claude Code y sus entornos anfitriones |
| GitHub / Google / xAI | GitHub Copilot CLI y VS Code, Gemini CLI y Desktop y Grok CLI |
| Herramientas independientes y regionales | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop y CLI, TRAE, OpenCode, Harnext/Harness y WorkBuddy |

Esperar aprobación o respuesta es amarillo, errores de herramientas o comandos rojo y ejecución normal verde; las fuentes simultáneas se agrupan rojo, amarillo, verde. El sidecar Qwen solo está activo mientras vive su PID, evitando informes obsoletos al salir.

Si una aplicación de chat no persiste eventos estructurados, no se distingue de forma fiable entre aplicación abierta inactiva y modelo generando. Esas herramientas, incluido ChatGPT, deben usar el hook `zislactl` siguiente; zisla no simula actividad con procesos residentes.

### Protocolo local `zislactl`

`zislactl` escribe estado e historial de uso en SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

El historial sobrevive a reinicios, actualizaciones por sustitución y limpieza de tareas. Solo se pierde al borrar datos de la aplicación manualmente.

Ejemplo:

```bash
swift run zislactl update \
  --id build-42 \
  --provider claude \
  --title "Refactor index" \
  --progress 68 \
  --detail "17/25"

swift run zislactl usage \
  --provider claude \
  --input-tokens 12400 \
  --output-tokens 2100 \
  --model claude-opus-4-8

swift run zislactl finish --id build-42 --detail "Complete"
```

Los proveedores canónicos incluyen `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness` y `doubao`; los alias habituales se normalizan automáticamente. Llámalo desde hooks, wrappers de shell o scripts.

La lista de tareas y el estado contraído usan el logotipo oficial de cada herramienta para identificar la fuente.

Consulta la [referencia de integración CLI](Docs/cli-reference.md) para el protocolo.

## Progreso de descargas del navegador

zisla escucha progreso público de archivos macOS en Descargas y combina extensiones temporales, atributos extendidos de origen y navegadores activos para identificar la fuente. No lee historial ni solicita red para conocer progreso; el indicador final permanece unos tres segundos. Acciones rápidas usa el mismo origen y ofrece Abrir carpeta cuando una transferencia correcta llega al destino final. La duración sigue sus ajustes y el aviso de copia o transferencia más reciente sustituye al anterior.

## Descargador

Los ejecutables se resuelven en este orden:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

La URL pasa a `Process` como argv independiente y no mediante shell. Se ignoran configuración y plugins, se desactiva `--exec`, se limita a un elemento y se verifica que el archivo final quede en el directorio autorizado.

Sin `ffmpeg`:

- Vídeo prefiere pistas AVC/MP4 y M4A y las empaqueta en MP4 con AVFoundation; el formato de un archivo se conserva.
- Audio prefiere M4A o conserva el formato original.
- Si yt-dlp recibe HTTP 412, no encuentra formato o no está disponible, Bilibili obtiene pistas DASH con API de solo lectura y sigue el empaquetado nativo sin otra herramienta.

## Notas

Las notas Markdown usan Notas de Apple como única fuente. Puedes crear, consultar, editar y eliminar notas existentes, no solo añadir nuevas.

- **Lista:** Al entrar, JXA (`osascript -l JavaScript`) lee títulos y fechas de notas no eliminadas y ordena por modificación reciente. Volver de Notas actualiza; Eliminadas recientemente se oculta. Elige para editar, actualiza, crea o elimina desde el menú contextual.
- **Consulta y edición:** AppleScript lee `plaintext`, fuente Markdown, en el editor. `TextEditor` escribe tras unos 0,8 segundos de inactividad para evitar una llamada por tecla. Las notas nuevas se crean en Notas de Apple y se seleccionan.
- **Vista previa:** El analizador de bloques renderiza títulos, listas sin orden/ordenadas/de tareas, citas, bloques de código, separadores, negrita, cursiva, código en línea, tachado y enlaces como `AttributedString`.
- **Almacenamiento:** La fuente se guarda como texto en `body`, escapando HTML y conservando líneas vacías. Leer `plaintext` restaura la fuente; Notas de Apple muestra texto plano, no Markdown renderizado.
- **Permisos:** La primera lectura o escritura solicita automatización macOS para Notas; un rechazo muestra fallo en lista o editor.

Notas no conserva segunda copia local; Notas de Apple es el almacenamiento.

## Permisos y privacidad

- **Calendario:** Calendario y Recordatorios se solicitan por separado al entrar; se actualizan tras crear, eliminar o completar.
- **Ubicación:** Tiempo solicita una vez la ubicación sin rastreo continuo; otras ubicaciones se buscan, guardan y eliminan en Ajustes.
- **Archivos y descargas:** Directorios elegidos usan marcadores de seguridad; Transferencia no copia originales.
- **Portapapeles:** Instalaciones nuevas habilitan historial y enlaces con interruptores independientes. Cada `changeCount` reconoce como máximo un enlace local; no registra parámetros ni llama API de borrar, declarar tipos o escribir, por lo que no sustituye el portapapeles universal.
- **Acciones rápidas:** Habilitadas, se ejecutan localmente cada `changeCount` y gestionan descargas terminadas y AirDrop. Modificadores solos y botones laterales pueden requerir monitorización; el gesto opcional envía ⌘C sintético y requiere Accesibilidad. Reconocimiento nunca usa red; abrir, buscar, traducir y guardar requiere clic o activador explícito. Exclusiones y tipos controlan avisos de copia; el interruptor controla también transferencias terminadas.
- **Estado de IA:** Solo lee eventos y metadatos necesarios para determinar las tareas.
- **Voz:** Micrófono y reconocimiento solo se acceden tras acción explícita. Grabaciones, transcripciones y texto organizado se gestionan localmente; este se envía solo al modelo, proveedor o perfil elegido, y credenciales remotas se guardan en base privada.
- **Bluetooth y dispositivos:** La batería de accesorios y dispositivos móviles Apple confiables se lee solo al abrir Batería bajo Sistema.
- **Cámara y monitorización:** Espejo y vista previa/grabación solicitan cámara. Sonidos, estadísticas, limpieza y activadores modificadores/laterales usan monitorización; estadísticas locales e interruptores independientes.
- **Pantalla y audio del sistema:** Capturas, grabaciones y vistas previas leen pantalla con permiso de grabación. Graba fuentes seleccionadas localmente; micrófono/cámara se solicita solo si se habilitan. El mezclador necesita macOS 14.4+ y grabación del sistema, con taps Core Audio locales.
- **Descargas del navegador:** Solo se inspecciona progreso público y temporales; no historial ni contenido de páginas.
- **Multimedia:** MediaRemote da metadatos y salida Core Audio confirma reproducción. Es un framework privado, así que esta compilación no sirve para envío directo al Mac App Store; sin metadatos se usa la aplicación de audio activa.
- **Red:** Tiempo usa Open-Meteo y alertas públicas chinas cuando corresponde, prefiriendo WeatherKit fuera. El canal resuelve una vez por ejecución el país vía `ipinfo.io/country`: `CN` Gitee→GitHub, otros GitHub→Gitee y fallo Gitee primero. Bilibili usa información de vídeo de lectura, URL y CDN; reconocer enlaces no conecta. Cuotas contactan proveedores; traducción, edición IA y limpieza opcionales contactan modelo o CLI elegido. Voz puede usar Apple según sistema/idioma. Instalar/actualizar dependencias y CLI, consultar IP y acciones de red explícitas también hacen peticiones.
- **Automatización:** Notas usa AppleScript/JXA para listar, ver, editar, crear y eliminar. Necesita autorización, no red y guarda en Notas de Apple.

## Pruebas

Con Xcode completo:

```bash
swift test
```

Solo con Command Line Tools:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Documentación

- [Diseño de arquitectura y rendimiento](Docs/architecture.md)
- [Referencia de integración CLI](Docs/cli-reference.md)
- [Diseño de firmas y publicaciones](Docs/releasing.md)
- [Dependencias incluidas en el repositorio (inglés)](../../../../mac/Vendor/README.md)
- [Avisos de terceros (inglés)](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Limitaciones del sistema

- macOS no tiene API pública Dynamic Island; la muesca se deduce de `safeAreaInsets` y área auxiliar superior, y pantallas sin muesca usan la misma simulación propia.
- Vídeo DRM, inicio de sesión, bloqueo y algunas aplicaciones exclusivas a pantalla completa pueden no exponer datos o permitir superposición.
- Aplicaciones sin integración multimedia pueden exponer fuente pero no garantizar título, carátula o progreso; vídeo pausado, parado o silenciado se oculta deliberadamente.
- El navegador debe publicar progreso macOS o usar temporales reconocibles en Descargas para mostrar porcentaje.
- Salud de batería, temperatura, potencia actual y accesorios dependen de hardware, conexión y datos macOS; campos ausentes aparecen no disponibles.
- Office a PDF necesita LibreOffice u OpenOffice; otras operaciones son locales.
- Paquetes no notarizados pueden exigir **Abrir igualmente**. Versiones estables usan un certificado autofirmado para mantener permisos tras actualizar; Sparkle verifica cada actualización con clave pública EdDSA antes de extraer, sustituir y reiniciar.

## Licencia

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Se permite uso no comercial; vender o usar comercialmente este software está prohibido.
