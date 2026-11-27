# Diseño de arquitectura y rendimiento

**Español** | [Idiomas de la documentación](../../../README.md)

## Activación en el borde superior

El estado oculto no tiene ventana transparente. `PointerEdgeMonitor` instala observadores globales y locales `NSEvent` para movimiento y arrastre; `ScreenLayoutEngine` usa solo geometría para detectar entrada en los 6 px centrales superiores de cada pantalla.

Cada pantalla tiene identidad estable al combinar `NSScreenNumber` y `CGDirectDisplayID`. El diseño se ancla en `screen.frame.maxY`, admitiendo coordenadas negativas, monitores apilados verticalmente y pantallas externas sin muesca.

Con varias pantallas conectadas, Ajustes → General → Modos de pantalla permite elegir para cada una el modo Dynamic Island (posición de cámara o personalizada), el modo muesca u ocultarla. Con una sola pantalla, este ajuste se oculta y se usa la apariencia global; al volver a conectarlas se recupera la configuración guardada de cada pantalla. Todas las pantallas visibles mantienen su isla contraída al mismo tiempo. La expansión, las acciones rápidas, la grabación y los mensajes temporales sustituyen solo la isla de su propia pantalla; la selección de pantallas para notificaciones filtra el contenido sin ocultar la isla inactiva.

## Ventana

La isla principal mantiene un único `.borderless + .nonactivatingPanel`:

- Usa nivel `.statusBar` y no cubre pantalla bloqueada ni menú del sistema.
- `.canJoinAllSpaces + .fullScreenAuxiliary` admite Spaces y aplicaciones normales a pantalla completa.
- La expansión al pasar el puntero nunca llama `NSApp.activate`, así que no quita el foco a la aplicación actual.
- El estado oculto usa `orderOut` para que ninguna ventana transparente ocupe la barra de menús.

Los paneles izquierdo y derecho se crean a demanda y se ocultan en cuanto sus colas quedan vacías.

## Estado y concurrencia

- AppKit, estado SwiftUI y control de ventanas permanecen en `MainActor`.
- Descargas, tiempo y solicitudes GitHub usan actors.
- El estado IA de hooks se supervisa con eventos del sistema de archivos del directorio. Cada fuente compara mtime y tamaño del último archivo local de sesión o actividad y reutiliza la caché de análisis si no cambió.
- La detección automática lee solo eventos estructurados, marcadores fijos y metadatos necesarios para determinar tareas. No lee instrucciones ni respuestas y un fallo de un proveedor no bloquea otros.
- Las cuotas de cuentas de IA se consultan por proveedor. Las cuotas Gemini y Claude/GPT de Antigravity mantienen ventanas de reinicio y avisos propios. La cuota de conversación normal de Gemini App usa el Cookie web guardado de la misma cuenta de Google; Gemini CLI conserva su OAuth local. Nunca se estiman cuotas ausentes.
- Los retardos de contracción usan `Task` cancelables y un token de generación para que una tarea antigua no oculte una isla ya reabierta.
- El estado oculto no tiene `TimelineView`, temporizador de 60 Hz ni envío continuo de animación.

## Detección multimedia

MediaRemote aporta título, carátula, progreso y controles. Las propiedades de objetos de proceso de Core Audio 14.4+ confirman flujo activo y dan una aplicación alternativa si faltan metadatos. Las listas de procesos y el estado de salida usan observadores de propiedades más verificación periódica acotada; nunca se captura audio ni se solicita grabación de pantalla o Accesibilidad. Fuentes pausadas, detenidas o silenciadas no permanecen en el área multimedia.

## Grabación y mezcla de aplicaciones

Grabación y mezclador son independientes de la detección de metadatos. Grabar solicita pantalla y permisos de micrófono/cámara habilitados, conserva medios localmente y gestiona proyectos en la carpeta elegida. El mezclador usa taps Core Audio en macOS 14.4+ y requiere grabación de audio del sistema.

## Materiales

macOS 26 usa una capa SwiftUI `glassEffect`; macOS 14/15 una `NSVisualEffectView`. Reducir transparencia cambia a fondo opaco. La isla no apila múltiples capas de desenfoque o material.

## Límite de seguridad de descargas

Swift inicia `yt-dlp` mediante `Process.executableURL` y argumentos en array; la URL siempre es un argv independiente después de `--`. Configuración, plugins y exec están desactivados, las salidas se vacían en paralelo y el progreso se analiza mediante centinela JSON.

Una tarea solo tiene éxito con código 0, ruta existente y ruta resuelta dentro del directorio autorizado. Cada tarea limpia solo su propio directorio temporal nombrado con UUID.

## Comprobación y descarga de actualizaciones

El canal resuelve una vez por ejecución el país de salida pública y usa Sparkle para obtener el appcast firmado de la compilación instalada, descargar ZIP por HTTPS, verificar firmas EdDSA del archivo y feed antes de extraer, sustituir y reiniciar. `CN` empieza en Gitee, `update-release` para Release y `preview` para Preview, y reintenta GitHub una vez; otros países empiezan GitHub y reintentan Gitee una vez. Si falla la consulta se mantiene Gitee primero; cada feed apunta a un ZIP firmado en su propio servidor. Cada publicación ofrece appcast por arquitectura junto a `appcast.xml`; una instalación de arquitectura única solicita su variante, y una x86_64 traducida solicita `arm64`, por lo que no se sustituye por universal. Una universal cuenta variantes en su ejecutable y conserva `appcast.xml`, que sirve también a versiones previas a actualizaciones por arquitectura. Cambiar el ajuste afecta consultas automáticas y manuales y reinicia el ciclo Sparkle siguiente. La clave pública no contiene cuentas; la privada permanece en el llavero macOS del responsable o en archivo privado protegido por separado.
