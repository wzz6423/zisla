import { createCatalog } from './createCatalog';

export const es = createCatalog({
  meta: {
    documentTitle: 'zisla · Espacio de trabajo dinámico',
    description:
      'zisla es un espacio nativo de macOS para tareas de IA, informes diarios y edición de grabaciones, con mascotas propias, capturas y permisos reunidos.',
    ogTitle: 'zisla · Pon lo que ocurre donde puedas verlo',
    ogDescription:
      'Mantén tus tareas de IA y tu día a la vista, graba y edita en Mac, importa tu mascota y gestiona los permisos en un lugar.',
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
      changelog: 'Registro de cambios',
      faq: 'Preguntas frecuentes',
      developers: 'Desarrolladores',
    },
    downloadCta: 'Descargar',
    downloadCtaAriaLabel: 'Ir a la sección de descargas',
    languageLabel: 'Idioma de la interfaz',
    themeLabel: 'Apariencia',
    themeModes: { auto: 'Automático (sistema)', light: 'Modo claro', dark: 'Modo oscuro' },
  },
  hero: {
    eyebrow: 'ESPACIO DE TRABAJO NATIVO PARA MACOS',
    title: 'zisla<br><em>Lo que ocurre,<br>justo donde puedes verlo.</em>',
    lede:
      'Reúne tareas de IA, medios, archivos y agenda en la parte superior de la pantalla. Después de copiar algo, una barra de acciones rápidas independiente lo previsualiza arriba y sugiere el siguiente paso. Aparece cuando hace falta y se aparta al terminar.',
    downloadCta: 'Descargar',
    downloadCtaAriaLabel: 'Descargar',
    sourceCta: 'Ver código',
    sourceCtaAriaLabel: 'Ver el código fuente de zisla en GitHub',
    hints: [
      'Mueve el puntero a la parte superior para expandir, sin hacer clic',
      'Después de copiar, pulsa Command+N para el siguiente paso inteligente',
      'Se oculta sola sin interrumpir tu trabajo',
    ],
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
      '{modules} módulos superiores y {features} funciones independientes, desde vistas previas de ventanas y capturas hasta gestión de IA y apps recomendadas.',
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
          'Consulta el historial del portapapeles dentro de la isla y filtra por imagen, URL, ruta o tipo de archivo y mira cuándo se copió cada entrada. Envía una entrada a Notas rápidas, márcala como favorita o elimínala.',
        points: ['Historial dentro de la isla', 'Filtrado por tipo', 'Notas rápidas y favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Detecta automáticamente actividad de CLI, apps de escritorio e IDE compatibles y muestra tareas, estado, tendencias de tokens y un mapa de contribuciones. Solo analiza eventos estructurados y nunca lee conversaciones. Se añade detección de tareas de Cursor, junto con uso numérico y cuotas de suscripción disponibles de Cursor y Muse Code; las ejecuciones largas de herramientas en Cursor siguen visibles.',
        points: ['Tareas agrupadas entre herramientas', 'Tendencias de consumo de tokens', 'Nunca lee prompts ni respuestas'],
      },
      keyboardSound: {
        name: 'Sonidos del teclado',
        caption:
          'Reproduce 20 sonidos mecánicos integrados para las pulsaciones globales, con volumen ajustable y variación natural del tono, además de sonidos de liberación cuando están disponibles. Activa las estadísticas locales para ver el resumen, tendencias, historial, línea temporal de apps y mapa por tecla F1-F12. Los totales de voz, duración del dictado, velocidad y tiempo ahorrado aparecen en el panel del teclado. Las configuraciones nuevas activan sonidos y estadísticas, con controles separados.',
        points: ['20 sonidos integrados', 'Sonido al soltar y variación de tono', 'Estadísticas con control separado'],
      },
      download: {
        name: 'Descargador',
        caption:
          'Pega un enlace o deja que zisla lo detecte en el portapapeles al activarlo. Elige vídeo o audio y descarga en la carpeta predeterminada o en otra. Los enlaces compatibles muestran icono de origen, progreso en vivo y estado final. Descargas, grabaciones y capturas comparten esta ubicación de guardado.',
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
          'Lee las cuentas activadas en Mail, muestra la bandeja de entrada y permite marcar, responder, redactar y mover mensajes a la papelera dentro de la isla, con indicaciones claras si falta un permiso. Selecciona archivos al redactar para adjuntarlos al mensaje.',
        points: ['Cuentas de Mail', 'Responder y redactar en la isla', 'Permisos explicados'],
      },
      quickNotes: {
        name: 'Notas rápidas',
        caption:
          'Usa la app Notas del sistema para ver, editar, crear y eliminar notas con vista previa Markdown en vivo, y saltar directamente a las primeras nueve notas con Command+1 a 9. Los borradores se escriben de nuevo en Notas automáticamente.',
        points: ['Datos en Notas', 'Editor Markdown', 'Borradores guardados automáticamente'],
      },
      volumeMixer: {
        name: 'Mezclador de volumen por app',
        caption: 'Ajusta el volumen y silencia por separado las apps que reproducen audio. Requiere macOS 14.4 o posterior y permiso para grabar audio del sistema.',
        points: ['Volumen por app', 'Silenciar por separado', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilidades',
        caption:
          'Temporizador de concentración, mantener la pantalla activa, limpieza de pantalla y teclado (bloquea incluso F1-F12), teleprompter, espejo y papelera en una sola página.',
        points: ['Temporizador de concentración', 'Bloquea F1-F12 durante la limpieza', 'Teleprompter y espejo'],
      },
      system: {
        name: 'Estado del sistema',
        caption:
          'Consulta CPU, GPU, memoria, disco, red y ventiladores; lee la temperatura SMART de NVMe cuando el hardware la ofrece, guarda un historial por minuto que puedes graficar para cualquier periodo y exportar a .xlsx. Analiza cachés de apps y de usuario de Apple, registros y archivos de preferencias residuales. Revisa los elementos, mueve los seleccionados a la Papelera y consulta los resultados. Consulta carga, salud, ciclos, temperatura y capacidad de este Mac, además del nivel de batería de los dispositivos cercanos que expone el sistema. Las direcciones IPv4 e IPv6 públicas se muestran por separado. El historial se conserva de forma predeterminada hasta que lo borres.',
        points: ['Monitorización a nivel de chip', 'Gráficas de historial y exportación .xlsx', 'Revisa antes de mover a la Papelera'],
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
      'Las vistas previas de ventanas, las capturas y las acciones rápidas están a mano; las apps recomendadas te ayudan a descubrir más herramientas de escritorio.',
    features: {
      floatingIsland: {
        title: 'Una isla flotante que se adapta',
        description: 'Usa la posición de la cámara o elige una posición en el borde de la pantalla. La posición propia se conserva al cambiar de modo. Los diseños compactos horizontales y verticales ajustan su longitud a iconos, tareas de IA, descargas y medios, con una opción para mostrar más información.',
        detail: 'Posición propia · Iconos persistentes · Información adaptable',
      },
      dailyBriefing: {
        title: 'Tu día en un informe diario',
        description: 'Elige entre ocho plantillas, selecciona métricas de uso, escritura, sistema y actividad zisla, y revisa la vista previa. Exporta un PNG manualmente o a una hora diaria. El historial de Tiempo de Uso se incluye si está activado y disponible; los datos ausentes no se presentan como un cero medido.',
        detail: '8 plantillas · Contenido a elegir · Vista previa y exportación PNG programada',
      },
      userCare: {
        title: 'Recordatorios mientras trabajas',
        description: 'Ajusta el intervalo de descansos, agua, movimiento y reposo de la vista. Los mensajes se adaptan a la hora del día. Las pausas naturales, el bloqueo y el reposo reinician el contador. Al terminar una sesión o editar notas puede aparecer una respuesta breve. Actívalo o desactívalo en Ajustes.',
        detail: 'Intervalo ajustable · Mensajes según la hora · Respeta inactividad y reposo',
      },
      contextNotes: {
        title: 'Notas vinculadas a un lugar',
        description: 'Guarda una nota editable para una web, ventana o escritorio y recupérala al volver. Adjunta una captura de ventana, gestiona las notas en la bandeja y configura recordatorios recurrentes de una hora a tres días, o desactívalos.',
        detail: 'Notas de ubicación · Capturas de ventanas · Recordatorios recurrentes',
      },
      recording: {
        title: 'Graba y edita en el estudio',
        description: 'Graba pantalla, ventana o región con audio del sistema, micrófono y cámara opcionales. Edita vídeo, audio, imágenes y texto en varias pistas, añade animaciones, zooms y subtítulos y revisa una vista previa nítida. Elige proporción original, 16:9, 9:16, 1:1 o 4:3. Exporta vídeo, GIF, Live Photo o audio; algunos formatos requieren FFmpeg. Las propuestas de IA opcionales se revisan antes de aplicarlas. Las grabaciones usan la ubicación definida en los ajustes de descarga.',
        detail: 'Edición multipista · Proporciones y vista previa · Vídeo, GIF, Live Photo y audio',
      },
      permissions: {
        title: 'Permisos del sistema en un lugar',
        description: 'Consulta el estado en Ajustes → Permisos, inicia solicitudes compatibles o abre la página correspondiente del sistema. La bienvenida inicial usa la misma lista y marca los permisos que se configuran manualmente.',
        detail: 'Estado de permisos · Solicitudes y enlaces · Compartido con la bienvenida',
      },
      pdf: {
        title: 'Herramientas PDF',
        description: 'Disponible en Ajustes, fuera del carrusel de módulos de la isla. Catorce operaciones locales: unir, dividir, girar, recortar, convertir imágenes y Office, renderizar a imágenes, extraer texto, añadir marcas de agua y números de página, cifrar, quitar contraseñas y editar metadatos.',
        detail: '14 herramientas en el dispositivo · Une en el orden que quieras · Nada sale de tu Mac',
      },

      windowPreviews: {
        title: 'Mira la ventana y cambia con un clic',
        description:
          'Previsualiza ventanas desde el Dock o con Command-Tab y pulsa una tarjeta para activar su ventana. Las configuraciones nuevas activan esta función; gestiona la función y sus permisos en Ajustes.',
        detail: 'Dock y Command-Tab · Cambiar de ventana con un clic · Configurable',
      },
      capture: {
        title: 'Capturas, capturas con desplazamiento y fijado',
        description:
          'Captura, fija o une capturas con desplazamiento usando atajos personalizables. Resalta, extrae zonas de imagen, redondea esquinas y conserva anotaciones al exportar. Reconoce y copia texto, tradúcelo y copia el resultado, o exporta tablas reconocidas como .xlsx. Guarda capturas en la bandeja. Los ajustes comprueban conflictos con voz y acciones rápidas. El diálogo de guardado se abre en la carpeta de descarga actual.',
        detail: 'Resaltar y extraer · Reconocer, traducir y copiar · Esquinas redondas y .xlsx',
      },
      voice: {
        title: 'Entrada de voz y limpieza',
        description:
          'Activa con una tecla o mantén pulsado para hablar usando el reconocimiento del sistema, con vocabularios especializados y palabras personalizadas. Opcionalmente, usa Ollama, LM Studio o un modelo remoto para corregir la transcripción sin cambiar el sentido y dar formato a los elementos enumerados explícitamente.',
        detail: 'Dos modos de grabación · Vocabularios y palabras clave · Limpieza opcional',
      },
      media: {
        title: 'Medios y sonidos ambientales del sistema',
        description:
          'Controla lo que se reproduce desde la parte superior de la isla o elige un sonido ambiental de macOS. Puede detenerse al bloquear la pantalla, iniciar el salvapantallas o dormir el monitor. Elige una onda o un brillo de portada; el progreso también aparece en los diseños compactos y flotantes.',
        detail: 'Control de reproducción · Letras sincronizadas · Parada automática',
      },
      browserDownloads: {
        title: 'Progreso de descargas del navegador',
        description:
          'Detecta descargas de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera y Arc, y muestra su origen y progreso en vivo arriba.',
        detail: '8 navegadores · Detección de origen · Aviso de finalización',
      },
      copyAssistant: {
        title: 'Acciones rápidas y siguientes pasos',
        description:
          'Al activarlo, previsualiza texto, enlaces, archivos o imágenes copiados en una barra independiente y propone abrir, mostrar en Finder, buscar, traducir, calcular o guardar, solo después de tu confirmación. Abre la carpeta del archivo mediante acciones rápidas tras una descarga del navegador o una transferencia AirDrop. Admite las carpetas de Chrome predeterminadas y elegidas, con un interruptor independiente del progreso de descarga. Las IP tienen acciones separadas para consultar y abrir el enlace. La conversión reconoce unidades monetarias menores y el catálogo incluye Emoji 18.0.',
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
        description: 'Elige del catálogo ampliado de animales y personajes o importa una imagen, animación o vídeo compatible con un nombre propio. Coloca la mascota a un lado de la isla y elimina las importadas en Ajustes. Las animaciones admiten hasta 30 segundos y los archivos hasta 100 MB.',
        detail: 'Catálogo ampliado · Importar imágenes y vídeos · Eliminar mascotas propias',
      },
      lockScreen: {
        title: 'Información de la pantalla bloqueada',
        description:
          'Muestra opcionalmente fecha, estado y reproducción en la pantalla bloqueada de macOS. Es una superposición independiente y nunca aparece en la lista ni el carrusel de módulos.',
        detail: 'Superposición independiente · Activación voluntaria · No roba el foco',
      },
      recommendedTools: {
        title: 'Apps recomendadas',
        description:
          'Descubre OpenScreen para grabar la pantalla y editar vídeos, y DockDoor para previsualizar ventanas del Dock y cambiar de app. Son aplicaciones de terceros que se instalan por separado.',
        detail: 'Descubre herramientas de escritorio · Apps de terceros · Instalación aparte',
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
      'Para Mac con Apple Silicon. Las versiones, otras arquitecturas y las sumas de comprobación están en la página de versiones. Tras instalar, Sparkle verifica primero la firma y luego descarga, instala y reinicia manual o automáticamente según tus ajustes, y las actualizaciones conservan los permisos ya concedidos. Si una versión no te interesa, puedes omitirla y no volverá a avisar. Consulta las notas de versión antes de instalar y después de reiniciar.',
    primaryCta: 'Descargar',
    primaryCtaAriaLabel: 'Descargar zisla',
    releaseCta: 'Ver versión',
    releaseCtaAriaLabel: 'Ver los detalles de la versión en GitHub',
    brewMono: 'HOMEBREW / UN COMANDO',
    brewNote: 'Sparkle mantiene zisla actualizada, así que brew upgrade solo la reemplaza cuando la copia instalada es realmente anterior a la del tap: desde Homebrew 5.1.6 se lee la versión de la propia app. Nombrar el cask, como en brew upgrade --cask zisla, se basa en los registros de instalación de Homebrew y puede devolverte a la versión del tap después de una actualización de Sparkle. El tap solo sirve versiones estables. Es un tap de terceros y la app no está notarizada, por lo que el primer arranque necesita «Abrir de todos modos» en Ajustes del Sistema → Privacidad y seguridad.',
    copyBrewCommandAriaLabel: 'Copiar el comando de instalación de Homebrew',
    notes: {
      system: { term: 'Sistema', value: 'macOS 14 o posterior · Configuración compatible actual: Mac con Apple Silicon' },
      install: { term: 'Instalar', value: 'Monta el DMG y arrástralo a Aplicaciones' },
      package: { term: 'Paquete', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Otras arquitecturas', value: 'Página de versiones' },
      mirror: { term: 'Espejo', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.21': [
        'La monitorización del sistema conserva de forma predeterminada todo el historial por minuto, tanto existente como nuevo, hasta que lo borres. Siguen disponibles las gráficas por periodo y la exportación .xlsx.',
        'Descargas, grabaciones y capturas comparten una ubicación. Los diálogos para guardar capturas se abren en la carpeta de descarga actual; se ha eliminado el ajuste duplicado de ubicación de las grabaciones.',
        'La ubicación de los indicadores de estado y su entrada de búsqueda solo aparecen en las píldoras con posición personalizada. La fila se oculta en diseños con muesca o píldoras junto a la cámara cuando solo pueden usar la barra de menús.',
        'La cuenta atrás de las acciones rápidas usa una barra de progreso inferior en los diseños con muesca. Las píldoras conservan el progreso en todo el contorno.',
      ],
      'v0.1.20': [
        'Elige entre ocho plantillas, selecciona métricas de uso, escritura, sistema y actividad zisla, y revisa la vista previa. Exporta un PNG manualmente o a una hora diaria. El historial de Tiempo de Uso se incluye si está activado y disponible; los datos ausentes no se presentan como un cero medido.',
        'Ajusta el intervalo de descansos, agua, movimiento y reposo de la vista. Los mensajes se adaptan a la hora del día. Las pausas naturales, el bloqueo y el reposo reinician el contador. Al terminar una sesión o editar notas puede aparecer una respuesta breve. Actívalo o desactívalo en Ajustes. Guarda una nota editable para una web, ventana o escritorio y recupérala al volver. Adjunta una captura de ventana, gestiona las notas en la bandeja y configura recordatorios recurrentes de una hora a tres días, o desactívalos.',
        'Usa la posición de la cámara o elige una posición en el borde de la pantalla. La posición propia se conserva al cambiar de modo. Los diseños compactos horizontales y verticales ajustan su longitud a iconos, tareas de IA, descargas y medios, con una opción para mostrar más información. Elige una onda o un brillo de portada; el progreso también aparece en los diseños compactos y flotantes.',
        'Elige del catálogo ampliado de animales y personajes o importa una imagen, animación o vídeo compatible con un nombre propio. Coloca la mascota a un lado de la isla y elimina las importadas en Ajustes. Las animaciones admiten hasta 30 segundos y los archivos hasta 100 MB.',
        'Graba pantalla, ventana o región con audio del sistema, micrófono y cámara opcionales. Edita vídeo, audio, imágenes y texto en varias pistas, añade animaciones, zooms y subtítulos y revisa una vista previa nítida. Elige proporción original, 16:9, 9:16, 1:1 o 4:3. Exporta vídeo, GIF, Live Photo o audio; algunos formatos requieren FFmpeg. Las propuestas de IA opcionales se revisan antes de aplicarlas.',
        'Captura, fija o une capturas con desplazamiento usando atajos personalizables. Resalta, extrae zonas de imagen, redondea esquinas y conserva anotaciones al exportar. Reconoce y copia texto, tradúcelo y copia el resultado, o exporta tablas reconocidas como .xlsx. Guarda capturas en la bandeja. Los ajustes comprueban conflictos con voz y acciones rápidas.',
        'Se añade detección de tareas de Cursor, junto con uso numérico y cuotas de suscripción disponibles de Cursor y Muse Code; las ejecuciones largas de herramientas en Cursor siguen visibles. Las IP tienen acciones separadas para consultar y abrir el enlace. La conversión reconoce unidades monetarias menores y el catálogo incluye Emoji 18.0.',
        'Ajusta el volumen y silencia por separado las apps que reproducen audio. Requiere macOS 14.4 o posterior y permiso para grabar audio del sistema. Disponible en Ajustes, fuera del carrusel de módulos de la isla. Consulta el estado en Ajustes → Permisos, inicia solicitudes compatibles o abre la página correspondiente del sistema. La bienvenida inicial usa la misma lista y marca los permisos que se configuran manualmente. Los totales de voz, duración del dictado, velocidad y tiempo ahorrado aparecen en el panel del teclado. Las configuraciones nuevas activan sonidos y estadísticas, con controles separados. Selecciona archivos al redactar para adjuntarlos al mensaje. Consulta las notas de versión antes de instalar y después de reiniciar.',
      ],
    },
    eyebrow: 'Registro de cambios',
    title: 'Qué cambió en cada versión de zisla: funciones nuevas, mejoras y correcciones.',
    lede: 'Qué cambió en cada versión de zisla: funciones nuevas, mejoras y correcciones.',
    ariaLabel: 'historial de versiones de zisla',
    releaseCountLabel: 'versiones',
    latestLabel: 'última',
    shippedLabel: 'publicado',
    latestBadge: 'Última',
    noteLabel: 'versión',
    pagerAriaLabel: 'Páginas del registro de cambios',
    pageLabel: 'Página {page}',
    prevPageLabel: 'Anterior',
    nextPageLabel: 'Siguiente',
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
        question: '¿Las acciones rápidas abren o suben lo que copio?',
        answer: 'No. El reconocimiento y la vista previa ocurren en tu Mac, y el siguiente paso solo se ejecuta después de que lo confirmes.',
      },
      permissions: {
        question: '¿Qué permisos del sistema necesita zisla?',
        answer: '<p>Ajustes → Permisos reúne estados, solicitudes y enlaces a Ajustes del Sistema. Algunos permisos necesitan configuración manual. Tú eliges qué solicitudes iniciar; la bienvenida inicial también ofrece estos controles.</p><p>Grabación de pantalla y audio del sistema, micrófono y cámara sirven a captura, grabación, mezclador y espejo según la función. El dictado usa además reconocimiento de voz. Calendarios, Recordatorios, Ubicación, Bluetooth y Automatización sirven a sus funciones. Añadir una ciudad del tiempo manualmente no requiere ubicación.</p><p>Las configuraciones nuevas activan sonidos de teclado y estadísticas, desactivables por separado. Los eventos globales requieren monitorización de entrada. Las estadísticas guardan cantidades, códigos de tecla, horas y nombres de apps, nunca el texto escrito. Accesibilidad permite inserción, gestos, limpieza y control de ventanas.</p><p>El acceso total al disco puede ser necesario para el índice local de correo y el historial de Tiempo de Uso de los informes diarios. El selector de archivos concede acceso a la carpeta elegida. Desactiva funciones en zisla o revoca permisos en Ajustes del Sistema → Privacidad y seguridad.</p>',
      },
      localVoice: {
        question: '¿Cómo uso un modelo local para corregir una transcripción de voz?',
        answer: `
      <p>Se admiten Ollama, LM Studio y otros servicios locales compatibles con OpenAI.</p>
      <ol>
        <li>Descarga o carga el modelo que quieras en tu aplicación de modelos locales y, después, inicia su servicio.</li>
        <li>Abre Ajustes → Voz → Modelos Locales, añade y activa una configuración, elige Ollama o LM Studio e introduce la URL del servicio. Para otros servicios compatibles con OpenAI, elige también LM Studio. Deja API Key vacío si el servicio no exige autenticación.</li>
        <li>Selecciona uno de los modelos detectados automáticamente y elige esa configuración en Modelo de Organización de Voz → Usar Modelo.</li>
      </ol>
      <p>zisla recomienda un modelo Gemma 4 QAT según el chip y la memoria RAM total. No descarga ni carga automáticamente el modelo recomendado.</p>
    `.trim(),
      },
      network: {
        question: '¿zisla se conecta a Internet?',
        answer: 'El tiempo, las actualizaciones firmadas, las descargas que inicias y la limpieza de voz remota opcional usan la red cuando hace falta. La detección de enlaces es local. El modelo local corrige el texto después de la transcripción; el reconocimiento de voz de Apple puede seguir usando la red, según el idioma y la compatibilidad del sistema.',
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
        answer: 'Los datos locales están en ~/Library/Application Support/zisla/. Las estadísticas de escritura se guardan aparte en ~/Library/Application Support/zisla/typing-stats.sqlite3. Notas rápidas usa Notas.',
      },
    },
  },
  developers: {
    eyebrow: 'CÓDIGO ABIERTO POR DEFECTO',
    title: 'Recursos para desarrolladores.',
    lede: 'Con licencia PolyForm Noncommercial 1.0.0: solo uso no comercial, tal cual o compilado desde el código fuente.',
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
    brewCommandCopied: 'Comando de instalación de Homebrew copiado',
  },
});
