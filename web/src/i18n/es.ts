import { createCatalog } from './createCatalog';

export const es = createCatalog({
  meta: {
    documentTitle: 'zisla · Espacio de trabajo dinámico',
    description:
      'zisla es un espacio de trabajo dinámico nativo para macOS. Reúne tareas de IA, medios, archivos y agenda, además de sonidos del teclado, estadísticas de escritura, anotaciones de capturas y un asistente de copia.',
    ogTitle: 'zisla · Pon lo que ocurre donde puedas verlo',
    ogDescription:
      'De tareas de IA y reproducción multimedia a sonidos del teclado, estadísticas de escritura, asistente de copia, anotaciones de capturas y herramientas de escritorio: un espacio nativo de macOS que aparece cuando lo necesitas.',
  },
  tagline: 'Espacio de trabajo dinámico nativo para macOS',
  header: {
    navAriaLabel: 'Navegación principal',
    brandHomeAriaLabel: 'Inicio de zisla',
    menuOpenLabel: 'Abrir menú de navegación',
    menuCloseLabel: 'Cerrar navegación',
    menuButtonTitle: 'Abrir navegación',
    navItems: {
      showcase: 'Funciones',
      ai: 'Flujo de IA',
      download: 'Descargar',
      faq: 'Preguntas frecuentes',
      developers: 'Desarrolladores',
    },
    downloadCta: 'Descargar',
    downloadCtaAriaLabel: 'Ir a la sección de descargas',
    languageLabel: 'Idioma de la interfaz',
  },
  hero: {
    eyebrow: 'ESPACIO DE TRABAJO NATIVO PARA MACOS',
    title: 'zisla<br><em>Lo que ocurre,<br>justo donde<br class="hero-mobile-break"> puedes verlo.</em>',
    lede:
      'Reúne tareas de IA, medios, archivos y agenda en la parte superior de la pantalla. Después de copiar algo, una barra de asistencia independiente lo previsualiza arriba y sugiere el siguiente paso. Aparece cuando hace falta y se aparta al terminar.',
    downloadCta: 'Descargar',
    downloadCtaAriaLabel: 'Descargar',
    sourceCta: 'Ver código',
    sourceCtaAriaLabel: 'Ver el código fuente de zisla en GitHub',
    hints: [
      'Mueve el puntero a la parte superior para expandir, sin hacer clic',
      'Después de copiar, pulsa Command+N para el siguiente paso inteligente',
      'Se oculta sola sin interrumpir tu trabajo',
    ],
    identityCaption: 'Parte superior de la pantalla',
  },
  proof: {
    ariaLabel: 'Descripción del producto',
    items: {
      modules: { title: '{count} módulos superiores', desc: 'Activa los flujos que necesitas' },
      os: { title: 'macOS 14+', desc: 'Una experiencia de escritorio nativa' },
      displays: { title: 'Varias pantallas', desc: 'Funciona con notch y pantallas externas' },
      local: { title: 'Local primero', desc: 'El estado de IA nunca lee tus conversaciones' },
    },
  },
  showcase: {
    eyebrow: 'UN SOLO PUNTO DE ENTRADA / FLUJOS DIARIOS',
    title: 'Los flujos diarios, <span>en la parte superior de la pantalla.</span>',
    lede:
      'Desde tareas de IA hasta el portapapeles, la agenda y el estado del sistema, zisla reúne los flujos dispersos detrás de un único punto de entrada.',
    ariaLabel: 'Catálogo de funciones de zisla',
    summaryMono: '{modules} MÓDULOS / {groups} FLUJOS',
    summaryLede:
      'De los flujos superiores a las herramientas locales, aquí se detalla cada tarea que realmente puedes completar.',
    summaryNote:
      '{modules} módulos superiores y {features} capacidades independientes para capturas, voz, medios, descargas, asistente de copia, gestión de IA, mascota y pantalla bloqueada.',
    groupNames: {
      island: 'Flujos superiores',
      ai: 'Flujo de IA',
      daily: 'Información diaria',
      tools: 'Utilidades',
    },
    groupCount: '{count} módulos',
    pointsAriaLabel: 'Puntos destacados de {name}',
    modules: {
      dashboard: {
        name: 'Inicio',
        caption:
          'Las tarjetas dinámicas solo aparecen durante una sesión de concentración, una tarea de IA o una descarga; si no ocurre nada, no ocupan espacio.',
        points: ['Aparece cuando hace falta', 'Progreso en tiempo real', 'Diseño adaptable'],
      },
      shelf: {
        name: 'Bandeja',
        caption:
          'Arrastra archivos, audio, vídeo o enlaces a la franja superior para guardarlos en la bandeja, mostrarlos en Finder o abrir el menú Compartir de macOS.',
        points: ['Arrastra arriba para guardar', 'Mostrar en Finder', 'Menú Compartir del sistema'],
      },
      clipboard: {
        name: 'Portapapeles',
        caption:
          'Consulta el historial del portapapeles dentro de la isla y filtra por imagen, URL, ruta o tipo de archivo. Envía una entrada a Notas rápidas, márcala como favorita o elimínala.',
        points: ['Historial dentro de la isla', 'Filtrado por tipo', 'Notas rápidas y favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Detecta automáticamente actividad de CLI, apps de escritorio e IDE compatibles, incluidos los hilos de Zed Agent, y muestra tareas, estado, tendencias de tokens y un mapa de contribuciones. Solo analiza eventos estructurados y nunca lee conversaciones.',
        points: ['Tareas agrupadas entre herramientas', 'Tendencias de consumo de tokens', 'Nunca lee prompts ni respuestas'],
      },
      keyboardSound: {
        name: 'Sonidos del teclado',
        caption:
          'Reproduce 20 sonidos mecánicos integrados para las pulsaciones globales, con volumen ajustable y variación natural del tono, además de sonidos de liberación cuando están disponibles. Activa las estadísticas locales para ver el resumen, tendencias, historial, línea temporal de apps y mapa por tecla F1-F12.',
        points: ['20 sonidos integrados', 'Sonido al soltar y variación de tono', 'Estadísticas opcionales'],
      },
      download: {
        name: 'Descargador',
        caption:
          'Pega un enlace o deja que zisla lo detecte en el portapapeles al activarlo. Elige vídeo o audio y descarga en la carpeta predeterminada o en otra. Los enlaces compatibles muestran icono de origen, progreso en vivo y estado final.',
        points: ['Modos vídeo / audio', 'Carpeta predeterminada o propia', 'Origen y progreso en vivo'],
      },
      agenda: {
        name: 'Agenda y tiempo',
        caption:
          'Muestra el tiempo de tu ubicación y hasta seis lugares elegidos. Consulta, añade y elimina eventos y recordatorios, y marca los recordatorios como completados.',
        points: ['Tarjetas meteorológicas para varios lugares', 'Calendario y tareas', 'Completa un recordatorio con un toque'],
      },
      mail: {
        name: 'Correo',
        caption:
          'Lee las cuentas activadas en Mail, muestra la bandeja de entrada y permite marcar, responder, redactar y mover mensajes a la papelera dentro de la isla, con indicaciones claras si falta un permiso.',
        points: ['Cuentas de Mail', 'Responder y redactar en la isla', 'Permisos explicados'],
      },
      quickNotes: {
        name: 'Notas rápidas',
        caption:
          'Usa la app Notas del sistema para ver, editar, crear y eliminar notas con vista previa Markdown en vivo. Los borradores se escriben de nuevo en Notas automáticamente.',
        points: ['Datos en Notas', 'Editor Markdown', 'Borradores guardados automáticamente'],
      },
      pdf: {
        name: 'Herramientas PDF',
        caption:
          'Catorce operaciones locales: unir, dividir, girar, recortar, convertir imágenes y Office, renderizar a imágenes, extraer texto, añadir marcas de agua y números de página, cifrar, quitar contraseñas y editar metadatos.',
        points: ['14 herramientas en el dispositivo', 'Une en el orden que quieras', 'Nada sale de tu Mac'],
      },
      toolbox: {
        name: 'Utilidades',
        caption:
          'Temporizador de concentración, mantener la pantalla activa, limpieza de pantalla y teclado (bloquea incluso F1-F12), alarmas, teleprompter, espejo y papelera en una sola página.',
        points: ['Temporizador de concentración', 'Bloquea F1-F12 durante la limpieza', 'Teleprompter y espejo'],
      },
      system: {
        name: 'Estado del sistema',
        caption:
          'Consulta CPU, GPU, memoria, disco, red y ventiladores; lee la temperatura SMART de NVMe cuando el hardware la ofrece y limpia cachés y registros seguros de eliminar.',
        points: ['Monitorización a nivel de chip', 'Temperatura NVMe cuando es compatible', 'Limpia cachés con un toque'],
      },
      battery: {
        name: 'Batería',
        caption:
          'Consulta carga, salud, ciclos, temperatura y capacidad de este Mac, además del nivel de batería de los dispositivos cercanos que expone el sistema.',
        points: ['Indicadores de salud del Mac', 'Tiempo restante', 'Batería de dispositivos cercanos'],
      },
    },
  },
  extensions: {
    eyebrow: 'DENTRO Y FUERA DE LA ISLA',
    title: 'Lejos de la isla, <span>sigue siendo una herramienta de escritorio.</span>',
    lede:
      'Capturas, voz, medios, descargas del navegador y gestión de IA aparecen donde resulta más fácil acceder a ellos.',
    ariaLabel: 'Capacidades de escritorio independientes',
    summaryMono: 'MÁS ALLÁ DE LA ISLA',
    summaryLede: 'Capacidades frecuentes, cada una en su lugar natural.',
    summaryNote:
      'Capturas, grabación, medios, descargas del navegador, asistente de copia, gestión de IA, mascota y pantalla bloqueada aparecen por separado.',
    features: {
      capture: {
        title: 'Capturas, capturas con desplazamiento y fijado',
        description:
          'Captura o fija una parte de la pantalla con un atajo global, anota, une una captura con desplazamiento y reconoce o exporta tablas. Las anotaciones que sigues editando se conservan al exportar.',
        detail: 'Atajo global · Anotar y deshacer · Ediciones conservadas al exportar',
      },
      voice: {
        title: 'Entrada de voz y limpieza',
        description:
          'Activa con una tecla o mantén para hablar usando el reconocedor del sistema. Añade vocabularios, palabras personalizadas, formato estructurado o limpieza con un modelo local o remoto.',
        detail: 'Dos modos de grabación · Vocabularios y palabras clave · Limpieza opcional',
      },
      media: {
        title: 'Medios y sonidos ambientales del sistema',
        description:
          'Controla lo que se reproduce desde la parte superior de la isla o elige un sonido ambiental de macOS. Puede detenerse al bloquear la pantalla, iniciar el salvapantallas o dormir el monitor.',
        detail: 'Control de reproducción · Letras sincronizadas · Parada automática',
      },
      browserDownloads: {
        title: 'Progreso de descargas del navegador',
        description:
          'Detecta descargas de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera y Arc, y muestra su origen y progreso en vivo arriba.',
        detail: '8 navegadores · Detección de origen · Aviso de finalización',
      },
      copyAssistant: {
        title: 'Asistente de copia y siguientes pasos',
        description:
          'Al activarlo, previsualiza texto, enlaces, archivos o imágenes copiados en una barra independiente y propone abrir, mostrar en Finder, buscar, traducir, calcular o guardar, solo después de tu confirmación.',
        detail: 'Activación opcional · Reconocimiento local · Command+N por defecto',
      },
      aiManagement: {
        title: 'Gestión de CLI de IA y Skills',
        description:
          'Detecta, instala, actualiza y elimina CLI de IA desde Ajustes, y revisa y gestiona Skills locales para cambiar menos entre terminales y herramientas.',
        detail: 'Detectar e instalar · Actualizar y eliminar · Skills locales',
      },
      pet: {
        title: 'Mascota de la isla',
        description: 'Elige una mascota integrada y colócala a la izquierda o derecha de la isla. Desactívala cuando quieras.',
        detail: 'Personajes integrados · Izquierda o derecha · Actívala cuando quieras',
      },
      lockScreen: {
        title: 'Información de la pantalla bloqueada',
        description:
          'Muestra opcionalmente fecha, estado y reproducción en la pantalla bloqueada de macOS. Es una superposición independiente y nunca aparece en la lista ni el carrusel de módulos.',
        detail: 'Superposición independiente · Activación voluntaria · No roba el foco',
      },
    },
  },
  ai: {
    eyebrow: 'IA SIN CAJA NEGRA',
    title: 'Mira el estado de la IA <span>sin leer la conversación.</span>',
    lede:
      'Las tareas, el estado y las tendencias de tokens permanecen en tu Mac. Esta página describe la función y no simula una tarea en ejecución.',
    summaryMono: 'ESTADO LOCAL / LÍMITES CLAROS',
    summaryLede: 'Conecta tus herramientas de IA y conserva los límites de contexto que necesita tu trabajo.',
    summaryNote: 'Solo se explican el alcance de detección, los datos y la conexión; no se simula una sesión en vivo.',
    toolsHeading: 'Herramientas de IA compatibles',
    toolsLede: 'Detecta actividad de CLI, apps de escritorio e IDE compatibles y agrupa el estado de las tareas.',
    toolsAriaLabel: 'Herramientas de IA compatibles',
    doubaoName: 'Doubao',
    boundariesHeading: 'Solo se registra el estado',
    privacyPoints: [
      'Analiza únicamente tipo de evento, estado, hora, modelo e ID de sesión de eventos estructurados',
      'Nunca lee el texto de prompts o respuestas',
      'El protocolo y el estado se guardan en tu Mac',
    ],
    bridgeHeading: 'Conecta tus propias tareas',
    bridgeLede: 'Usa zislactl para enviar el estado estructurado de tareas externas a la barra superior.',
    zislactlTaskTitle: 'Compilación y publicación',
    copyZislactlAriaLabel: 'Copiar el comando zislactl',
  },
  flow: {
    eyebrow: 'RITMO DE INTERACCIÓN',
    title: 'Sube, <span>mira y déjalo ir.</span>',
    lede: 'Nunca roba el foco y se repliega cuando terminas de mirar.',
    ariaLabel: 'Ritmo de interacción superior',
    summaryMono: 'BARRA DE ESTADO / 3 PASOS',
    summaryLede: 'Se expande cuando la necesitas y se repliega al terminar.',
    summaryNote: 'Se activa por la posición del puntero, no ocupa espacio cuando está vacía y nunca roba el foco.',
    steps: {
      trigger: {
        phase: 'Activar',
        title: 'Mueve el puntero al centro superior',
        desc: 'Las pantallas con notch y externas usan el mismo activador; oculta no ejecuta ningún bucle de fotogramas.',
      },
      review: {
        phase: 'Revisar',
        title: 'Echa un vistazo al estado actual',
        desc: 'Medios, archivos, IA, agenda y herramientas del sistema están en el mismo lugar.',
      },
      dismiss: {
        phase: 'Cerrar',
        title: 'Vuelve a lo que estabas haciendo',
        desc: 'Aleja el puntero y se repliega; expandir nunca activa la app ni toma el foco.',
      },
    },
  },
  download: {
    eyebrow: 'LISTO CUANDO TÚ LO ESTÉS',
    title: 'Descargar zisla',
    copy:
      'Para Mac con Apple Silicon. Las versiones, otras arquitecturas y las sumas de comprobación están en la página de versiones. Tras instalar, Sparkle verifica primero la firma y luego descarga, instala y reinicia manual o automáticamente según tus ajustes.',
    primaryCta: 'Descargar',
    primaryCtaAriaLabel: 'Descargar zisla',
    releaseCta: 'Ver versión',
    releaseCtaAriaLabel: 'Ver los detalles de la versión en GitHub',
    notes: {
      system: { term: 'Sistema', value: 'macOS 14 o posterior · Configuración compatible actual: Mac con Apple Silicon' },
      install: { term: 'Instalar', value: 'Monta el DMG y arrástralo a Aplicaciones' },
      package: { term: 'Paquete', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Otras arquitecturas', value: 'Página de versiones' },
      mirror: { term: 'Espejo', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: 'RESPUESTAS DIRECTAS',
    title: 'Preguntas frecuentes.',
    lede: 'Permisos, privacidad y compatibilidad.',
    items: {
      audience: {
        question: '¿Para quién es zisla?',
        answer: 'Para usuarios de Mac que quieren IA, medios, archivos y agenda en un solo lugar. También funciona sin notch.',
      },
      aiPrivacy: {
        question: '¿zisla lee mis conversaciones de IA?',
        answer: 'No. El monitor de IA solo lee el estado de las tareas, nunca el texto de prompts o respuestas.',
      },
      copyAssistant: {
        question: '¿El asistente de copia abre o sube lo que copio?',
        answer: 'No. El reconocimiento y la vista previa ocurren en tu Mac, y el siguiente paso solo se ejecuta después de que lo confirmes.',
      },
      permissions: {
        question: '¿Qué permisos del sistema necesita zisla?',
        answer: `
      <p>zisla no solicita todos los permisos al iniciar por primera vez. macOS muestra cada aviso solo cuando activas y utilizas realmente la función correspondiente:</p>
      <ul>
        <li><strong>Calendarios y Recordatorios:</strong> se solicitan por separado al abrir el módulo de agenda, para leer, crear y gestionar eventos del calendario y recordatorios con fecha.</li>
        <li><strong>Servicios de localización:</strong> se solicitan cuando eliges el tiempo de tu ubicación actual. zisla obtiene una sola ubicación y no te sigue continuamente. Añadir una ciudad manualmente no requiere permiso de ubicación.</li>
        <li><strong>Micrófono y reconocimiento de voz:</strong> se solicitan al iniciar la entrada de voz. El audio solo se captura mientras grabas activamente y solo se transcribe esa grabación.</li>
        <li><strong>Accesibilidad:</strong> es necesaria para insertar automáticamente una transcripción en la app actual, copiar rápidamente con un gesto del ratón, limpiar el teclado y controlar algunos reproductores compatibles. Se utiliza para localizar campos de entrada que no son contraseñas o enviar las teclas de sistema necesarias.</li>
        <li><strong>Supervisión de entrada:</strong> se usa para los sonidos del teclado, las estadísticas de escritura locales opcionales y activadores globales como una tecla modificadora independiente o un botón lateral del ratón. Solo escucha los eventos globales que necesitan esas funciones; los atajos globales normales no la requieren.</li>
        <li><strong>Grabación de pantalla y grabación de audio del sistema:</strong> son necesarias para las capturas, su edición y la forma de onda del audio del sistema. Las capturas leen la imagen de la pantalla; la forma de onda solo analiza los niveles actuales del audio del sistema y nunca guarda ni sube audio.</li>
        <li><strong>Cámara:</strong> solo se utiliza mientras la ventana del espejo está abierta.</li>
        <li><strong>Bluetooth:</strong> solo se utiliza mientras el módulo de batería está abierto, para leer el nivel de batería que publican los dispositivos conectados o enlazados.</li>
        <li><strong>Automatización:</strong> la primera vez que usas Notas rápidas, Mail, la limpieza del escritorio o el control directo de un reproductor compatible, macOS pregunta por separado si zisla puede controlar Notas, Mail, Finder o esa app. Notas rápidas lee y escribe en Notas; Mail puede leer, redactar, responder, marcar y eliminar mensajes.</li>
        <li><strong>Acceso total al disco:</strong> solo es necesario cuando Mail no está en ejecución y zisla aún debe leer el índice local de correo para mostrar cuentas, remitentes, asuntos, vistas previas, marcas de tiempo y estado de lectura.</li>
        <li><strong>Notificaciones:</strong> se solicitan al activar el temporizador Pomodoro o las alarmas, únicamente para mostrar una notificación local cuando termina un temporizador o se activa una alarma.</li>
      </ul>
      <p><strong>Las carpetas no son Acceso total al disco:</strong> para las carpetas de la bandeja, de importación/exportación o de descargas que eliges en el selector de archivos del sistema, zisla solo obtiene acceso a esa carpeta, nunca permiso de lectura para todo el disco.</p>
      <p><strong>Sonidos del teclado y estadísticas de escritura:</strong> ambas funciones están desactivadas de forma predeterminada y los eventos globales del teclado solo se observan cuando una de ellas está activada. Con los sonidos del teclado, los eventos de las teclas se usan únicamente para reproducir un sonido; con las estadísticas de escritura, solo se guardan datos agregados —recuento de caracteres, códigos físicos de teclas, marcas de tiempo y la app en primer plano—, nunca lo que escribes. Puedes desactivarlas por separado en Ajustes; después no se registra nada más. Los datos ya guardados permanecen en un archivo de base de datos local que puedes eliminar.</p>
      <p>Puedes desactivar una función en los ajustes de la app o revocar un permiso en cualquier momento en Ajustes del Sistema → Privacidad y seguridad. Revocar un permiso solo desactiva la función relacionada y no afecta a los demás módulos. Los nombres de los elementos pueden variar ligeramente según la versión de macOS.</p>
    `.trim(),
      },
      network: {
        question: '¿zisla se conecta a Internet?',
        answer: 'El tiempo, las actualizaciones firmadas, las descargas que inicias y la limpieza de voz remota opcional usan la red cuando hace falta. La detección de enlaces es local.',
      },
      multiDisplay: {
        question: '¿zisla admite varias pantallas?',
        answer: 'Sí: varias pantallas, Spaces y apps normales a pantalla completa; al expandirse nunca roba el foco.',
      },
      intel: {
        question: '¿Puedo usarlo en un Mac Intel?',
        answer: 'Puede existir una compilación para Intel, pero no se garantiza la compatibilidad. La configuración compatible actual es Apple Silicon.',
      },
      storage: {
        question: '¿Dónde guarda zisla sus datos?',
        answer: 'Los datos locales están en ~/Library/Application Support/zisla/. Las estadísticas de escritura se guardan aparte en ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Notas rápidas usa Notas.',
      },
    },
  },
  developers: {
    eyebrow: 'CÓDIGO ABIERTO POR DEFECTO',
    title: 'Recursos para desarrolladores.',
    lede: 'Con licencia MIT: úsalo tal cual o compílalo desde el código fuente.',
    docs: {
      macos: { title: 'Guía de desarrollo para macOS', description: 'Funciones, compilación, pruebas y límites del sistema' },
      architecture: { title: 'Arquitectura y rendimiento', description: 'Activación superior, ventanas y diseño de rendimiento' },
      cli: { title: 'Integración CLI', description: 'Comandos y campos de zislactl' },
      releasing: { title: 'Firma y publicación', description: 'Firma, notarización y proceso de publicación' },
      contributing: { title: 'Guía de contribución', description: 'Entorno, ramas, commits y requisitos de pull request' },
    },
    quickStartMono: 'INICIO RÁPIDO / CÓDIGO FUENTE',
    quickStartHeading: 'Ejecútalo desde el código o conecta tus propias tareas.',
    copyRunCommandAriaLabel: 'Copiar el comando para ejecutar desde el código fuente',
    githubRepoLabel: 'Repositorio de GitHub',
    giteeRepoLabel: 'Repositorio de Gitee',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Admite varias pantallas, Spaces y apps normales a pantalla completa; expandirse nunca activa la app ni roba el foco',
      'Oculta no crea una ventana transparente persistente ni ejecuta un bucle de fotogramas; se activa mediante eventos globales y geometría',
      'Usa una sola capa de material del sistema y cambia a un fondo opaco con Reducir transparencia',
      'Liquid Glass en macOS 26+, con retorno automático a materiales nativos en macOS 14 y 15',
      'El notch físico se infiere de la zona segura; las pantallas externas sin notch reciben una barra simulada en una superposición dedicada',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Volver al inicio de zisla',
    previewChannelLabel: 'Canal Preview',
    tagline: 'Código abierto, nativo y bajo tu control.',
  },
  common: {
    copyCommandTitle: 'Copiar comando',
    copiedAriaLabel: 'Copiado',
  },
  toast: {
    runCommandCopied: 'Comando para ejecutar desde el código copiado',
    zislactlCopied: 'Comando zislactl copiado',
  },
});
