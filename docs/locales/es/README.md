# zisla

**Español** | [Idiomas de la documentación](../README.md)

**zisla es un espacio de trabajo nativo de macOS que aparece cuando lo necesitas y luego se aparta.** Mueve el puntero al centro superior de la pantalla para abrir un lugar ligero que reúne tareas de IA activas, contenido multimedia, transferencia de archivos, descargas y utilidades del escritorio. Las pantallas sin muesca utilizan la misma zona de estado simulada.

Implementación actual: **macOS 14+**. Apple Silicon es la configuración compatible; los paquetes para Intel pueden funcionar, pero no se garantiza su compatibilidad.

[Ver el recorrido completo de funciones — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Ver el vídeo de presentación de zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Música: «Funkorama» de Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Fuente](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Por qué encaja en la parte superior de tu pantalla

- **Cuando lo necesitas, sin quitar el foco.** Despliégalo desde el borde superior, fíjalo cuando haga falta y sigue trabajando en la aplicación actual.
- **Un lugar para el trabajo en curso.** Consulta reproducción, tareas de IA, descargas, temporizadores, correo, estado del sistema y batería sin abrir un panel completo.
- **Actividad de IA sin acceso a las conversaciones.** zisla solo lee eventos estructurados y metadatos locales necesarios para determinar el estado de las tareas. Nunca lee instrucciones ni el contenido de las respuestas.
- **El control permanece local.** Los módulos, el historial del portapapeles y la detección de enlaces tienen interruptores independientes; los permisos se solicitan al usar una función por primera vez.

## Qué puede hacer

### Mantener en marcha el trabajo del escritorio

| Función | Descripción |
| --- | --- |
| Reproducción actual | Muestra carátula, título, progreso, letra y controles de reproducción; Core Audio puede identificar la aplicación que realmente emite audio cuando faltan metadatos. |
| Transferencia y uso compartido | Suelta archivos, contenido multimedia o enlaces en la zona superior para conservarlos en la bandeja de transferencia, mostrarlos en Finder o abrir el menú de compartir de macOS. Comprime los archivos y carpetas seleccionados en ZIP, redimensiona o convierte las imágenes seleccionadas en Herramientas de imagen y devuelve los resultados correctos a la bandeja, o importa imágenes, vídeo y audio seleccionados a la biblioteca multimedia del estudio manteniendo su proyecto y cronología actuales. |
| Portapapeles y notificaciones | Registra opcionalmente el historial local del portapapeles, reconoce enlaces nuevos de forma local y muestra contenido multimedia, actividad de IA, descargas del navegador, temporizadores, correo y actualizaciones en el estado contraído. Las acciones rápidas opcionales muestran tras cada copia un pequeño aviso de la isla con una vista previa enriquecida y acciones inteligentes: abrir, mostrar en Finder, buscar, traducir, calcular y guardar. Tras finalizar una descarga del navegador o recibir un archivo por AirDrop, el mismo atajo puede abrir su carpeta. Las nuevas imágenes del historial se ponen en cola para reconocer texto en el dispositivo; busca su texto para encontrar la imagen original o haz clic derecho en una imagen para reconocer o copiar su texto. |
| Espacio de trabajo diario | Incluye tiempo, calendario, recordatorios, Mail.app, notas Markdown almacenadas en Notas de Apple, información de la pantalla bloqueada y mascotas de escritorio opcionales. Si faltan datos del tiempo, otras fuentes completan el resultado más completo; los datos disponibles se conservan cuando no se puede obtener el resto. |

### Hacer visible el trabajo de la IA

zisla supervisa actividad local de Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI y otras fuentes compatibles. Muestra tareas, estado, tendencias de tokens, mapas de calor de contribuciones y avisos laterales.

Para herramientas sin una fuente local estable, `zislactl` permite a scripts, CI y hooks informar de progreso, uso y notificaciones, manteniendo el estado del protocolo en este Mac. Ajustes también detecta, instala, actualiza y elimina CLI de IA habituales y gestiona Skills locales. Consulta la [referencia de integración CLI](mac/Docs/cli-reference.md) para proveedores y comandos.

### Resolver las pequeñas tareas útiles

| Área | Herramientas incluidas |
| --- | --- |
| Descargas y documentos | Descargas de vídeo y audio mediante `yt-dlp`; combinación, división, rotación, recorte, conversión, renderizado, exportación de texto, marcas de agua, números de página, cifrado, desbloqueo y edición de metadatos PDF en local. |
| Concentración y presentación | Temporizador Pomodoro con un aviso sonoro y una notificación local al acabar una sesión, modo de mantener despierto, prevención del reposo por inactividad, limpieza de pantalla y teclado, teleprompter y espejo de cámara. El nombre del temporizador solo se aplica a la sesión actual y vuelve al predeterminado cuando termina o se cancela. |
| Sistema y batería | Información de CPU, GPU, memoria, disco, red, ventilador y batería, además de limpieza de cachés y registros que se pueden eliminar de forma segura. |
| Entrada de voz | Atajos globales de grabación y transcripción, organización opcional de transcripciones en local o a distancia e historial de voz local. |

### Accesos y flujos actuales

La isla tiene 12 módulos: Inicio, Transferencia, Portapapeles, Supervisión de IA, Sonidos del teclado, Descargas, Agenda, Correo, Notas, Mezclador de volumen de aplicaciones, Utilidades y Sistema. Los detalles de batería están en Sistema; la presentación de la pantalla bloqueada es independiente. Abre las herramientas PDF, de imagen y de audio desde Ajustes; abre el estudio de grabación desde Ajustes o la barra de menús.

- **Grabación y creación:** Graba una pantalla, ventana o región con audio del sistema, micrófono y cámara opcionales. Edita subtítulos, zooms y efectos de retrato y voz en varias pistas, previsualiza y exporta vídeo, GIF, Live Photo o audio. Las herramientas de imagen ofrecen 9 operaciones locales; las de audio, 27.
- **Mezcla y reproducción:** macOS 14.4+ permite ajustar volumen y silencio por aplicación. Elige la salida de audio en el área multimedia y las preferencias del reproductor en Ajustes.
- **Escritorio y reuniones:** Vistas previas de ventanas del Dock y Command+Tab, notas contextuales de páginas/ventanas/escritorio, cuenta atrás de reuniones de 10 minutos, acceso a reuniones y notas vinculadas. Agita el puntero al arrastrar archivos para mostrar el destino de la estantería.
- **Resumen diario:** 8 plantillas, vista previa, exportación PNG manual o programada, métricas seleccionadas y carpeta de guardado independiente.
- **Cuentas de IA:** Consulta cuotas disponibles de cuentas compatibles, horas de reinicio, avisos de cuota baja y horas de muestreo; exporta el historial local de tokens como `.xlsx`. Las cuotas Gemini y Claude/GPT de Antigravity tienen supervisión, visualización y avisos independientes. Las cuotas de conversación de Gemini App usan un Cookie web de la misma cuenta de Google; Gemini CLI se supervisa por separado.
- **Acciones rápidas:** Las acciones del aviso usan `Command+1` a `Command+0` en orden. El activador adicional predeterminado para configuraciones nuevas es `Command+N` para la primera acción. Las actualizaciones conservan atajos guardados y activadores borrados.

La [ayuda para usuarios](https://wzz6423.github.io/zisla/help.html?lang=es#help) ofrece nueve guías paso a paso: portapapeles, captura, estantería, reuniones, IA, herramientas multimedia, resúmenes diarios, notas de escritorio/vistas previas de ventanas y reproducción/mezcla. La [guía de macOS](mac/README.md) enumera las carpetas de guardado y dependencias de las herramientas.

## Primeros pasos

### Instalar la aplicación

Descarga el último DMG de [GitHub Releases](https://github.com/wzz6423/zisla/releases) o [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), móntalo y arrastra `zisla.app` a `Applications`.

También puedes instalarla con Homebrew:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew obtiene la compilación correspondiente a tu chip, por lo que cada Mac Apple Silicon o Intel descarga solo su arquitectura. El cask proviene del tap de terceros `wzz6423/tap` y no del repositorio propio de Homebrew; instalarlo implica confiar en ese tap.

Tras iniciar, mueve el puntero al centro superior de la pantalla actual o elige **Mostrar isla** en el icono de la barra de menús. Los paquetes no están notarizados: sea cual sea la instalación, el primer inicio requiere **Abrir igualmente** en **Ajustes del Sistema > Privacidad y seguridad**, o eliminar manualmente el atributo de cuarentena:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Actualizar la aplicación

zisla se actualiza mediante Sparkle independientemente del método de instalación. Homebrew merece una aclaración: `brew upgrade` sustituye la aplicación solo si la copia instalada es realmente más antigua que la del tap, porque Homebrew 5.1.6 y posteriores leen la versión del paquete. Así no interfiere con Sparkle ni deja una instalación obsoleta. Al nombrar el cask se usan, en cambio, los registros de instalación de Homebrew, lo que puede devolver una aplicación actualizada por Sparkle a la versión del tap:

```bash
brew upgrade --cask zisla
```

El tap solo ofrece versiones estables; las Preview permanecen en Releases, por lo que `brew upgrade` nunca cambia a una versión preliminar. Nombrar el cask mientras usas Preview la sustituye por la versión estable actual. Sparkle nunca retrocede de versión, así que volver a Release conserva Preview hasta que una estable la supere. `brew uninstall --cask zisla` elimina la aplicación y `brew uninstall --zap --cask zisla` también elimina sus datos locales.

### Ejecutar desde el código fuente

Se requiere Swift 6 / Xcode 16+; solo Command Line Tools también permite compilar el proyecto.

```bash
cd mac
swift run zisla
```

El descargador requiere `yt-dlp`; `ffmpeg` es opcional. La conversión Office a PDF necesita LibreOffice u OpenOffice. Las instrucciones de compilación, pruebas y empaquetado están en la [guía de desarrollo macOS](mac/README.md).

## Diseñado para no interrumpir

- Admite varias pantallas, Spaces y aplicaciones normales a pantalla completa sin activar ni quitar el foco a la aplicación actual.
- El estado oculto no tiene una ventana transparente permanente de activación ni ejecuta un bucle de fotogramas; los eventos globales y comprobaciones geométricas disparan la expansión.
- Usa un solo material del sistema y pasa a un fondo opaco cuando se activa Reducir transparencia.
- Detecta la muesca física a partir del área segura del sistema; las pantallas externas sin muesca usan una superposición con el mismo contorno.

Consulta el [diseño de arquitectura y rendimiento](mac/Docs/architecture.md) para las decisiones de implementación.

## Privacidad y permisos

zisla solicita un permiso cuando una función habilitada lo necesita por primera vez. Puedes desactivar módulos en Ajustes y revocar autorizaciones en los ajustes de macOS en cualquier momento.

| Ámbito | Límite |
| --- | --- |
| Actividad de IA | Solo lee eventos estructurados y metadatos de actividad local. Nunca lee instrucciones ni contenidos de respuesta. |
| Portapapeles y archivos | Historial, detección de enlaces y acciones rápidas tienen interruptores locales separados; las acciones rápidas gestionan descargas terminadas y archivos AirDrop independientemente del progreso de descargas. Todo reconocimiento se ejecuta en el dispositivo; abrir enlaces o ejecutar acciones requiere un clic o activador explícito. Transferencia usa marcadores con ámbito de seguridad y no copia el archivo original. |
| Notas, correo y voz | Notas y correo usan AppleScript/JXA con autorización de automatización. La voz se graba solo mientras está activa; la organización envía texto únicamente al modelo local, proveedor remoto o perfil CLI elegido. |
| Descargas del navegador y multimedia | Usa información pública de progreso de archivos de macOS, metadatos MediaRemote y estado de salida Core Audio. No lee bases de historial de navegadores. Las formas de onda del sistema y la mezcla procesan audio localmente; la grabación lo guarda solo con la fuente correspondiente habilitada. |
| Red | Tiempo, consulta de IP pública, selección de espejo de actualización, descargas, comprobaciones habilitadas de cuotas e instalación de dependencias/CLI contactan sus servicios. Traducción, limpieza de voz y edición IA de grabaciones opcionales usan el proveedor o CLI elegido. El reconocimiento de Apple puede usar la red según sistema e idioma. |

### Permisos por función

zisla solicita la autorización necesaria al usar una función por primera vez. Si antes denegaste el acceso, abre el elemento correspondiente en **Ajustes del Sistema > Privacidad y seguridad** y permite `zisla`; los nombres varían entre versiones de macOS.

| Permiso o ajuste del sistema | Cuándo hace falta | Ámbito autorizado |
| --- | --- | --- |
| Control del dispositivo y acceso a datos (Accesibilidad en algunas versiones) | Insertar transcripciones automáticamente en el campo de texto de la aplicación actual | Lee y localiza campos que no son de contraseña y entrega la transcripción mediante API de accesibilidad o `Cmd+V`. Sin permiso, la transcripción se sigue copiando al portapapeles. |
| Micrófono | Entrada de voz o micrófono del estudio habilitado | Captura el micrófono seleccionado para grabación o monitorización habilitada. |
| Reconocimiento de voz | Convertir voz grabada a texto | Procesa solo la voz grabada activamente. La entrada de voz necesita permisos de micrófono y reconocimiento. |
| Acceso total al disco | Consultar correo sin Mail.app en ejecución | Lee el índice local de `~/Library/Mail` para cuentas, remitentes, asuntos, resúmenes, marcas de tiempo y estado leído. Esta ruta de acceso al índice Mail necesita autorización. |
| Automatización | Leer, redactar, responder, marcar o eliminar mensajes de Mail.app; leer y escribir Notas de Apple | Permite controlar las aplicaciones del sistema correspondientes. Los permisos de Mail y Notas se revocan por separado. |
| Calendarios; Recordatorios | Usar Agenda | Lee y gestiona eventos y recordatorios con autorizaciones independientes. |
| Localización | Tiempo en la ubicación actual | Solicita una vez la posición, sin seguimiento continuo. Las ubicaciones añadidas manualmente no necesitan acceso. |
| Cámara | Abrir el espejo o habilitar vista previa/grabación del estudio | Usa la cámara elegida mientras la función correspondiente está activa. |
| Monitorización de entrada | Sonidos, estadísticas y limpieza del teclado, atajos solo de modificadores o botones laterales | Observa los eventos de la función habilitada; las estadísticas permanecen locales. Los atajos globales normales no requieren este permiso. |
| Bluetooth | Ver batería de accesorios en Sistema → Batería | Solo lee información pública de batería de dispositivos conectados o enlazados. |
| Grabación de pantalla y audio del sistema (Grabación de pantalla en macOS antiguo) | Capturas, vistas previas, grabación, formas de onda del sistema y mezclador | Lee imágenes de pantalla y fuentes de audio elegidas. La grabación guarda las fuentes habilitadas localmente; el mezclador requiere macOS 14.4+. |
| Notificaciones | Alertas Pomodoro | Emite un aviso sonoro y una notificación local al terminar el temporizador. |
| Carpetas elegidas por el usuario (sin autorización manual) | Transferencia, importación/exportación o elegir descargas | El selector del sistema concede acceso a la carpeta elegida. Estas funciones no necesitan acceso total al disco. |

Revocar un permiso desactiva solo la función correspondiente. Si sigue sin estar disponible tras cambiar un ajuste, cierra y vuelve a abrir zisla e inténtalo de nuevo.

La [guía de macOS](mac/README.md) documenta todos los permisos y el comportamiento de red.

## Documentación

| Documento | Propósito |
| --- | --- |
| [Guía de desarrollo macOS](mac/README.md) | Módulos, integración de IA, dependencias, compilación, pruebas, permisos y límites del sistema. |
| [Guía del sitio web (inglés)](../../../web/README.md) | Desarrollo local, compilación de producción y enlaces de descarga actuales. |
| [Guía del vídeo de presentación (inglés)](../../../promo/README.md) | Vista previa Remotion, renderizado, composiciones, música y licencias. |
| [Diseño de arquitectura y rendimiento](mac/Docs/architecture.md) | Activación superior, comportamiento de ventanas, concurrencia, multimedia y seguridad de descargas. |
| [Referencia de integración CLI](mac/Docs/cli-reference.md) | Proveedores, comandos, campos y códigos de salida de `zislactl`. |
| [Diseño de firmas y publicaciones](mac/Docs/releasing.md) | Firma, notarización, DMG, canales de actualización y aceptación de publicaciones. |
| [Guía de contribución](CONTRIBUTING.md) | Entorno de desarrollo, ramas, commits y requisitos de pull requests. |

## Contribuir

Las issues y pull requests son bienvenidas. Lee primero la [guía de contribución](CONTRIBUTING.md). Informa de problemas de seguridad en privado mediante [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), en lugar de abrir una issue pública.

## Licencia

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Se permite uso no comercial; vender este software o cualquier otro uso comercial está prohibido.
