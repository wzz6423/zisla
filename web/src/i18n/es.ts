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
      help: "Ayuda",
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
          'Las tarjetas dinámicas solo aparecen durante una sesión de concentración, una tarea de IA o una descarga; si no ocurre nada, no ocupan espacio. El inicio agrupa las tareas de IA en curso por aplicación.',
        points: ['Aparece cuando hace falta', 'Progreso en tiempo real', 'Diseño adaptable'],
      },
      shelf: {
        name: 'Bandeja',
        caption:
          "Guarda archivos en la bandeja para buscar, seleccionar y compartir. Crea ZIP o PDF, cambia tamaño o formato de imágenes y envía medios a notas o al estudio.",
        points: ['Búsqueda y acciones por lotes', 'Imágenes a PDF y Notas rápidas', 'Edición de vídeo en el estudio'],
      },
      clipboard: {
        name: 'Portapapeles',
        caption:
          "Busca en el historial local y en el texto de las imágenes. Filtra por tipo o aplicación, guarda favoritos y envía entradas a Notas rápidas.",
        points: ['Historial dentro de la isla', 'Filtrado por tipo', 'Notas rápidas y favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Reúne tareas y estados de CLI de IA, apps de escritorio e IDE. Los datos numéricos fiables alimentan las tendencias de tokens y el mapa de contribuciones; elige una fecha para ver tokens de entrada, salida y totales por proveedor y modelo. Consulta el historial en Ajustes, expórtalo completo como .xlsx o bórralo. Muestra cuotas reales, fechas de reinicio y avisos de cuota baja, incluidas las ventanas 5h/7d y los presupuestos de Cursor en dólares cuando están disponibles. No lee el texto de prompts ni respuestas. Los diseños compactos también muestran la cuota restante en anillos. Elige las regiones de cada cuenta por separado; los registros diarios y los colores de la cuota restante coinciden en todos los diseños. Las cuotas Gemini y Claude/GPT de Antigravity tienen supervisión, visualización y avisos independientes. Las cuotas de conversación de Gemini App usan un Cookie web de la misma cuenta de Google; Gemini CLI se supervisa por separado.',
        points: ['Tareas de varias herramientas de IA', 'Historial por modelo y exportación .xlsx', 'Cuotas y fechas de reinicio'],
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
          'Pega un enlace o deja que zisla lo detecte en el portapapeles al activarlo. Elige vídeo o audio y descarga en la carpeta predeterminada o en otra. Los enlaces compatibles muestran icono de origen, progreso en vivo y estado final. Elige la carpeta de descargas en Ajustes → Ubicación de guardado, separada de capturas y grabaciones. Los enlaces Bilibili descargan la parte elegida. Gestiona los componentes en Ajustes → Componentes necesarios y, si quieres, actualiza a diario los ya instalados.',
        points: ['Modos vídeo / audio', 'Carpeta predeterminada o propia', 'Origen y progreso en vivo'],
      },
      agenda: {
        name: 'Agenda y tiempo',
        caption:
          'Muestra el tiempo de tu ubicación y hasta seis lugares elegidos. Consulta, añade o elimina eventos y recordatorios y marca estos como completados. Los eventos con enlace de reunión muestran una cuenta atrás 10 minutos antes de empezar y permiten unirse con un clic. Crea una nota de reunión o vincula y desvincula notas contextuales existentes. La hora de actualización de la lista del tiempo aparece en la cabecera, a la izquierda del botón de actualizar. Si faltan datos del tiempo, otras fuentes completan el resultado más completo; los datos disponibles se conservan cuando no se puede obtener el resto.',
        points: ['Tiempo y calendario', 'Cuenta atrás de 10 minutos', 'Unirse y vincular notas'],
      },
      mail: {
        name: 'Correo',
        caption:
          'Lee las cuentas activadas en Mail. Consulta la bandeja de entrada, marca un mensaje o todos los mensajes de entrada como leídos, responde, redacta y mueve mensajes a la Papelera desde la isla. Elige adjuntos al redactar; los permisos que faltan se explican con claridad.',
        points: ['Cuentas de Mail', 'Responder y redactar en la isla', 'Permisos explicados'],
      },
      quickNotes: {
        name: 'Notas rápidas',
        caption:
          'Usa la app Notas del sistema para ver, editar, crear y eliminar notas con vista previa Markdown en vivo, y saltar directamente a las primeras nueve notas con Command+1 a 9. Los borradores se escriben de nuevo en Notas automáticamente. Previsualiza adjuntos manuscritos y edita el texto anterior o posterior conservando los originales. Navega entre notas con Command y las flechas. El texto pegado adopta la tipografía nativa del cuerpo de texto.',
        points: ['Datos en Notas', 'Editor Markdown', 'Borradores guardados automáticamente'],
      },
      volumeMixer: {
        name: 'Mezclador de volumen por app',
        caption: 'Ajusta el volumen y silencia por separado las apps que reproducen audio. Requiere macOS 14.4 o posterior y permiso para grabar audio del sistema. El volumen se recuerda por aplicación y las fuentes de audio obsoletas desaparecen cuando se detiene la reproducción.',
        points: ['Volumen por app', 'Silenciar por separado', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilidades',
        caption:
          'Temporizador de concentración, mantener la pantalla activa, limpieza de pantalla y teclado que bloquea también F1-F12, teleprónter, espejo y Papelera en una página. Pausa, reanuda o reinicia el Pomodoro y sigue su progreso en las vistas compactas horizontal y vertical. Inicia la limpieza de archivos innecesarios desde las utilidades con tus ajustes de limpieza del sistema y sigue el progreso y los resultados en la isla. El nombre del temporizador solo se aplica a la sesión actual y vuelve al predeterminado cuando termina o se cancela.',
        points: ['Temporizador de concentración', 'Bloquea F1-F12 durante la limpieza', 'Teleprompter y espejo'],
      },
      system: {
        name: 'Estado del sistema',
        caption:
          'Supervisa CPU, GPU, memoria, disco, red, ventiladores y temperatura NVMe SMART disponible. Consulta el historial por minuto para un intervalo de fechas, expórtalo en .xlsx o bórralo en Ajustes. Revisa salud, ciclos, temperatura y capacidad de la batería, carga de dispositivos cercanos e IPv4/IPv6 públicas. Elige modos automáticos de energía con corriente o batería y, si quieres, bajo consumo al 20 % o menos. Carga inmediatamente al 100 % cuando macOS lo permita. Revisa cachés, registros, preferencias residuales y espacios de IA huérfanos antes de moverlos a la Papelera; la limpieza opcional puede hacerse cada 7, 15 o 30 días. La limpieza programada está desactivada por defecto; elige solo elementos fiables o todos los procesables, incluidos los que requieren revisión. Ejecuta la limpieza en segundo plano y consulta el progreso y los resultados en la isla. Detecta instalaciones duplicadas y archivos residuales de actualizaciones.',
        points: ['Monitorización a nivel de chip', 'Gráficas de historial y exportación .xlsx', 'Revisa antes de mover a la Papelera'],
      },
    },
  },
  extensions: {
    eyebrow: 'DENTRO Y FUERA DE LA ISLA',
    title: 'Lejos de la isla, <span>sigue siendo una herramienta de escritorio.</span>',
    lede:
      'Capturas, herramientas de imagen y audio, dictado, medios, descargas del navegador y gestión de IA aparecen donde resultan fáciles de alcanzar.',
    ariaLabel: 'Capacidades de escritorio independientes',
    summaryMono: 'MÁS ALLÁ DE LA ISLA',
    summaryLede: 'Capacidades frecuentes, cada una en su lugar natural.',
    summaryNote:
      'Las vistas previas de ventanas, las capturas y las acciones rápidas están a mano; las apps recomendadas te ayudan a descubrir más herramientas de escritorio.',
    features: {
      floatingIsland: {
        title: 'Una isla flotante que se adapta',
        description: 'Usa la posición de la cámara o elige una posición en el borde de la pantalla. La posición propia se conserva al cambiar de modo. Los diseños compactos horizontales y verticales ajustan su longitud a iconos, tareas de IA, descargas y medios, con una opción para mostrar más información. Reordena los módulos arrastrándolos en Ajustes → Diseño de Dynamic Island o restaura el orden predeterminado. En la misma página puedes cambiar la prioridad de la información de estado compacta. Con varias pantallas conectadas, Ajustes → General → Modos de pantalla permite elegir para cada una el modo Dynamic Island (posición de cámara o personalizada), el modo muesca u ocultarla. Con una sola pantalla, este ajuste se oculta y se usa la apariencia global; al volver a conectarlas se recupera la configuración guardada de cada pantalla. Todas las pantallas visibles mantienen su isla contraída al mismo tiempo. La expansión, las acciones rápidas, la grabación y los mensajes temporales sustituyen solo la isla de su propia pantalla; la selección de pantallas para notificaciones filtra el contenido sin ocultar la isla inactiva.',
        detail: 'Posición propia · Iconos persistentes · Información adaptable',
      },
      dailyBriefing: {
        title: 'Tu día en un informe diario',
        description: "Elige entre ocho plantillas, selecciona métricas de uso, escritura, sistema y actividad zisla, y revisa la vista previa. Exporta un PNG manualmente o a una hora diaria. El historial de Tiempo de Uso se incluye si está activado y disponible. Elige una carpeta de exportación independiente en Ajustes → Ubicación de guardado. También puedes incluir las cuotas reales de las cuentas y la hora de su consulta.",
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
        description: "Graba pantalla, ventana o región, edita pistas, subtítulos y efectos de retrato/voz y exporta. HDR en equipos compatibles e importación desde la bandeja.",
        detail: 'Efectos de retrato y voz · Estelas de cursor en color · Reproducción y exportación multipista',
      },
      permissions: {
        title: 'Permisos del sistema en un lugar',
        description: "Consulta el estado en Ajustes → Permisos, inicia solicitudes compatibles o abre la página correspondiente del sistema. El estado de los permisos se actualiza al conceder acceso. Una ayuda para arrastrar la aplicación facilita los permisos que requieren añadirla.",
        detail: "Estado de permisos · Solicitudes y enlaces",
      },
      imageTools: {
        title: 'Herramientas de imagen',
        description: 'Nueve herramientas locales en Ajustes: comprimir; convertir PNG, JPEG, WebP, AVIF y JPEG XL; redimensionar y recortar; comparar el formato más pequeño; girar y reflejar; marcas de agua; mosaico y desenfoque; reconocer texto y tablas; quitar fondos. Exporta por lotes o en ZIP, con una carpeta propia en Ajustes → Ubicación de guardado.',
        detail: '9 herramientas locales · Cinco formatos · Exportación por lotes y ZIP',
      },
      audioTools: {
        title: 'Herramientas de audio',
        description: 'Veintisiete operaciones locales en Ajustes, como convertir, comprimir, recortar, dividir, unir y mezclar, extraer audio de vídeo, normalizar LUFS, fundidos, velocidad y tono, reducción de ruido y eliminación de silencios, EQ, dinámica, canales y etiquetas. Requiere FFmpeg y ffprobe; elige un archivo o una carpeta al exportar.',
        detail: '27 operaciones locales · Edición y mezcla · FFmpeg y ffprobe',
      },
      pdf: {
        title: 'Herramientas PDF',
        description: "Disponible en Ajustes. Catorce operaciones locales: unir, dividir, girar, recortar, convertir imágenes y Office, renderizar a imágenes, extraer texto, añadir marcas de agua y números de página, cifrar, quitar contraseñas y editar metadatos.",
        detail: '14 herramientas en el dispositivo · Une en el orden que quieras · Nada sale de tu Mac',
      },

      windowPreviews: {
        title: 'Mira la ventana y cambia con un clic',
        description:
          'Previsualiza ventanas desde el Dock o con Command-Tab y pulsa una tarjeta para activar su ventana. Las configuraciones nuevas activan esta función; gestiona la función y sus permisos en Ajustes. Se filtran las ventanas cerradas o duplicadas y las vistas previas del Dock se ocultan mientras hay un menú contextual abierto.',
        detail: 'Dock y Command-Tab · Cambiar de ventana con un clic · Configurable',
      },
      capture: {
        title: 'Capturas, capturas con desplazamiento y fijado',
        description:
          'Captura, fija o une capturas con desplazamiento usando atajos personalizables. Resalta, extrae zonas de imagen, redondea esquinas y conserva anotaciones al exportar. Reconoce y copia texto, tradúcelo y copia el resultado, o exporta tablas reconocidas como .xlsx. Guarda capturas en la bandeja. Los ajustes comprueban conflictos con voz y acciones rápidas. El diálogo se abre en la carpeta de capturas de Ajustes → Ubicación de guardado. Las capturas fijadas permanecen al volver a capturar. Las capturas largas admiten desplazamiento automático lento; los dispositivos compatibles pueden capturar HDR. La selección automática de ventanas incluye la ventana de ajustes de zisla. Las imágenes fijadas se ajustan a su marco al ampliar con la barra de herramientas o el trackpad, o al arrastrar una esquina.',
        detail: 'Resaltar y extraer · Reconocer, traducir y copiar · Esquinas redondas y .xlsx',
      },
      voice: {
        title: 'Entrada de voz y limpieza',
        description:
          'Activa con una tecla o mantén pulsado para hablar usando el reconocimiento del sistema, con vocabularios especializados y palabras personalizadas. Opcionalmente, usa Ollama, LM Studio o un modelo remoto para corregir la transcripción sin cambiar el sentido y dar formato a los elementos enumerados explícitamente. Ajustes → Monitor del Sistema y Limpieza puede borrar el audio guardado de más de 7, 15 o 30 días y conservar las transcripciones; la limpieza automática está desactivada por defecto.',
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
          'Detecta descargas de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera y Arc, y muestra su origen y progreso en vivo arriba. El progreso muestra el nombre real del archivo de destino cuando el navegador lo facilita.',
        detail: '8 navegadores · Detección de origen · Aviso de finalización',
      },
      copyAssistant: {
        title: 'Acciones rápidas y siguientes pasos',
        description:
          'Al activarlo, previsualiza texto, enlaces, archivos o imágenes copiados en una barra independiente y propone abrir, mostrar en Finder, buscar, traducir, calcular o guardar, solo después de tu confirmación. Abre la carpeta del archivo mediante acciones rápidas tras una descarga del navegador o una transferencia AirDrop. Admite las carpetas de Chrome predeterminadas y elegidas, con un interruptor independiente del progreso de descarga. Las IP tienen acciones separadas para consultar y abrir el enlace. La conversión reconoce unidades monetarias menores y el catálogo incluye Emoji 18.0. El texto y las imágenes guardados usan la carpeta independiente de Acciones rápidas en Ajustes → Ubicación de guardado. Si una app no se abre, las acciones rápidas comprueban su integridad, firma y la política de seguridad de macOS. Tras superar las comprobaciones, pueden quitar los atributos de cuarentena y abrirla. Reordena las acciones de cada tipo reconocido en Ajustes → Acciones rápidas. Los importes admiten símbolos regionales y códigos de moneda con prefijo. La detección de comandos admite here-documents.',
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
        description: 'Elige del catálogo ampliado de animales y personajes o importa una imagen, animación o vídeo compatible con un nombre propio. Previsualiza las mascotas y conserva una, o deja que zisla elija de tu lista a medianoche, según la hora local, o con el intervalo que indiques. Coloca la mascota a un lado de la isla y elimina las importadas en Ajustes. Las animaciones admiten hasta 30 segundos y los archivos hasta 100 MB. Al desplegar la isla en una pantalla, las mascotas de las demás pantallas permanecen en su sitio.',
        detail: 'Vista previa y rotación aleatoria · Importar imágenes y vídeos · Eliminar mascotas propias',
      },
      lockScreen: {
        title: 'Información de la pantalla bloqueada',
        description:
          "Muestra opcionalmente fecha, estado y reproducción en la pantalla bloqueada de macOS.",
        detail: "Activación voluntaria · No roba el foco",
      },
      recommendedTools: {
        title: 'Apps recomendadas',
        description:
          'Descubre OpenScreen para grabación y edición de vídeo, DockDoor para previsualizar ventanas y cambiar de app, y Zshell como espacio de trabajo de terminal nativo de macOS. Son apps de terceros que se instalan por separado.',
        detail: 'Descubre herramientas de escritorio · Apps de terceros · Instalación aparte',
      },
    },
  },
  ai: {
    eyebrow: "FLUJO DE IA",
    title: "Sigue las tareas de IA, <span>el uso y las cuotas.</span>",
    lede:
      "Consulta tareas por aplicación, uso de modelos por fecha y cuotas restantes de tus cuentas.",
    summaryMono: "TAREAS / USO / CUOTAS",
    summaryLede: "Tareas de IA, uso y cuotas en un solo lugar.",
    toolsHeading: 'Herramientas de IA compatibles',
    toolsLede: "Detecta tareas de las CLI, aplicaciones de escritorio e IDE compatibles.",
    toolsAriaLabel: 'Herramientas de IA compatibles',
    boundariesHeading: "Privacidad",
    privacyPoints: [
      "El estado de las tareas y el uso quedan en tu Mac",
      "No se leen los prompts ni las respuestas",
      "No se suben conversaciones",
    ],
    bridgeHeading: 'Conecta tus propias tareas',
    bridgeLede: "Usa zislactl para mostrar tus scripts y tareas de compilación en la barra de estado.",
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
        desc: "Funciona en pantallas con notch y pantallas externas.",
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
  help: {
    "title": "Empieza con zisla",
    "lede": "Elige una tarea y sigue su acceso, pasos, permisos y destino.",
    "labels": {
      "entry": "Acceso",
      "shortcuts": "Atajos",
      "permissions": "Permisos",
      "output": "Resultado y almacenamiento"
    },
    "guides": {
      "clipboard": {
        "title": "Reutiliza lo que copiaste",
        "summary": "Busca un elemento o elige una acción después de copiar.",
        "entry": "Isla → Portapapeles; Ajustes → Acciones rápidas.",
        "steps": [
          "Activa el historial o las acciones rápidas y copia un texto o enlace de ejemplo.",
          "Abre el portapapeles, filtra o busca y pulsa Copiar en un elemento.",
          "Copia una imagen de ejemplo con texto legible, espera el reconocimiento local en segundo plano y busca una palabra de la imagen para encontrar el original.",
          "Haz clic derecho en la imagen para reconocer o copiar su texto; puedes cancelar mientras se reconoce. El reconocimiento en segundo plano no copia el texto automáticamente.",
          "Pega en la aplicación de destino; con una copia nueva, elige la siguiente acción en la ventana rápida."
        ],
        "shortcuts": "Command+1…9 y Command+0 siguen el orden de acciones. Las configuraciones nuevas añaden Command+N para la primera; Command+Delete cierra. Se conservan los atajos guardados y borrados.",
        "permissions": "Historial y reconocimiento son locales. Los disparadores de modificador/ratón necesitan Monitorización de entrada; el gesto opcional de copia necesita Accesibilidad. Traducir usa el servicio elegido.",
        "output": "Historial en datos locales. Guardar texto/imagen usa Ajustes → Ubicación de guardado → Acciones rápidas; nuevo valor: ~/Downloads/quick."
      },
      "capture": {
        "title": "Captura y edita la pantalla",
        "summary": "Edita una captura o grabación y exporta el resultado.",
        "entry": "Barra de menús → Captura/Grabación; Ajustes → Grabación → Estudio.",
        "steps": [
          "Captura una región o ventana; edita, copia, guarda o deposita en la bandeja.",
          "Elige pantalla, ventana o región y activa solo las fuentes de audio/cámara necesarias.",
          "Detén la grabación, edita y previsualiza en el estudio, y exporta el formato elegido."
        ],
        "shortcuts": "Control+1 captura; Control+2 captura larga. Control+Shift+1/2/3 graban pantalla/ventana/región; Control+Shift+6 abre el estudio. Se cambian en Ajustes.",
        "permissions": "Grabación de pantalla requerida. Micrófono y cámara necesitan sus permisos; también la vista previa de cámara.",
        "output": "Nuevos destinos: ~/Downloads/picture para capturas y ~/Downloads/video para grabaciones/proyectos. Configúralos por separado. Algunos formatos requieren FFmpeg."
      },
      "shelf": {
        "title": "Pasa archivos por la bandeja",
        "summary": "Prepara archivos para otra app sin copiar los originales.",
        "entry": "Isla → Bandeja; arrastra al activador superior.",
        "steps": [
          "Arrastra un archivo de ejemplo arriba o agita al arrastrar si el gesto está activo.",
          "Abre la bandeja y elige una categoría o los elementos necesarios.",
          "Arrastra al destino, muestra en Finder o comparte; una captura guardada se puede exportar como PNG.",
          "Selecciona archivos o carpetas y elige comprimir a ZIP en el menú contextual; el archivo vuelve a la bandeja.",
          "Selecciona imágenes de la bandeja y elige cambiar su tamaño o convertir su formato; ejecuta las herramientas de imagen y los resultados correctos vuelven a la bandeja.",
          "Selecciona imágenes, vídeo o audio e impórtalos a la biblioteca del estudio de grabación; se conservan el proyecto y la línea de tiempo actuales."
        ],
        "shortcuts": "Arrastra con el puntero. El gesto de agitar se configura por separado; no requiere atajo fijo.",
        "permissions": "El selector y los marcadores seguros dan acceso a archivos elegidos. Las capturas requieren Grabación de pantalla.",
        "output": "Los originales permanecen en su ubicación. Referencias y capturas persisten localmente; el PNG usa el destino elegido. Los ZIP y los resultados de imagen correctos vuelven a la bandeja; los medios importados se añaden a la biblioteca del proyecto de grabación."
      },
      "weather": {
        "title": "Ver el tiempo más completo disponible",
        "summary": "Consulta el tiempo de tu ubicación o lugares guardados y completa los datos que faltan.",
        "entry": "Isla → Agenda; Ajustes → Tiempo.",
        "steps": [
          "Activa Tiempo en Ajustes → Funciones; busca y guarda otros lugares en los ajustes del tiempo.",
          "Abre Agenda o actualiza el tiempo. Si faltan datos, otras fuentes completan el resultado más completo.",
          "Si las fuentes adicionales no están disponibles, conserva los datos obtenidos y oculta las medidas que faltan.",
          "Consulta los enlaces bajo la lista del tiempo para ver las fuentes utilizadas; las alertas oficiales se obtienen por separado."
        ],
        "shortcuts": "Usa el botón de actualización en Agenda; no hay un atajo global fijo.",
        "permissions": "La ubicación actual necesita permiso de ubicación; los lugares añadidos manualmente no. El tiempo y las alertas usan la red.",
        "output": "El tiempo se mantiene en memoria y los lugares guardados permanecen localmente. Se muestran los datos parciales cuando no se pueden completar; las previsiones de más de una hora se ocultan."
      },
      "meeting": {
        "title": "Únete a una reunión y guarda notas",
        "summary": "Vincula una reunión del calendario con una nota de contexto.",
        "entry": "Isla → Agenda; activa calendario y notas de contexto en Ajustes.",
        "steps": [
          "Crea o abre un evento con enlace de reunión compatible e inicio/final válidos.",
          "Pulsa Unirse; la cuenta atrás aparece 10 minutos antes.",
          "Crea, guarda o vincula una nota desde el evento y vuelve a abrirla desde la agenda o bandeja."
        ],
        "shortcuts": "Unirse y notas son botones. En otros lugares, mantén la tecla configurada y agita; por defecto, Command.",
        "permissions": "Se requiere acceso al calendario. Las notas de ventana pueden necesitar Accesibilidad; las capturas adjuntas necesitan Grabación de pantalla.",
        "output": "Las notas de reunión se guardan en la bandeja local. Notas rápidas es otra función que usa Notas de Apple."
      },
      "ai": {
        "title": "Conecta IA y revisa las cuotas",
        "summary": "Sigue tareas, uso registrado y cuotas de cuenta.",
        "entry": "Ajustes → IA; isla → Monitor IA.",
        "steps": [
          "Activa una herramienta local compatible o informa una tarea con zislactl según la referencia CLI.",
          "Activa la supervisión del proveedor y elige por separado la supervisión y visualización de Gemini y Claude/GPT en Antigravity. Para Gemini App, inicia sesión con la misma cuenta de Google en gemini.google.com/usage y guarda su Cookie en las credenciales de cuota web; selecciona Gemini CLI por separado.",
          "Consulta muestreo, reinicio y avisos de cuota; revisa el historial o exporta .xlsx."
        ],
        "shortcuts": "Usa el monitor o Ajustes, sin atajo global fijo. zislactl acepta los argumentos documentados.",
        "permissions": "La detección local lee estados estructurados. Las cuotas consultan al proveedor; la edición IA opcional usa el modelo o CLI elegido.",
        "output": "Tareas/uso: ~/Library/Application Support/zisla/ai-state.sqlite. Las cuotas son muestras del proveedor, no estimaciones por token; lo ausente sigue no disponible."
      },
      "media-tools": {
        "title": "Procesa imágenes, audio y PDF",
        "summary": "Usa las herramientas locales independientes con un ejemplo.",
        "entry": "Ajustes → Herramientas de imagen / Audio / PDF.",
        "steps": [
          "Añade una imagen, elige operación y opciones, ejecuta y exporta resultado o ZIP.",
          "Selecciona imágenes de la bandeja y elige cambiar su tamaño o convertir su formato; ejecuta las herramientas de imagen y los resultados correctos vuelven a la bandeja.",
          "Instala FFmpeg y ffprobe en Componentes, añade audio, elige recorte o mezcla y selecciona archivo o carpeta de salida.",
          "Añade PDF en el orden necesario, ejecuta la operación y guarda. Convertir Office requiere LibreOffice u OpenOffice."
        ],
        "shortcuts": "Botones de herramientas; sin atajo global fijo.",
        "permissions": "El selector permite acceder a archivos y carpetas elegidos. Procesamiento local; instalar componentes descarga archivos.",
        "output": "Nuevos destinos: imágenes ~/Downloads/picture, PDF ~/Downloads/pdf, configurables por separado. Audio usa el diálogo de exportación."
      },
      "daily-briefing": {
        "title": "Crea un resumen diario",
        "summary": "Revisa las estadísticas antes de exportar PNG.",
        "entry": "Ajustes → Resumen diario.",
        "steps": [
          "Elige plantilla y estadísticas.",
          "Abre la vista previa, revisa datos disponibles y elige la carpeta de salida.",
          "Exporta hoy o activa exportación diaria y fija la hora."
        ],
        "shortcuts": "Botones Vista previa y Exportar; sin atajo fijo.",
        "permissions": "Activa las funciones de estadísticas relacionadas. Tiempo de uso puede necesitar Acceso total al disco; las cuotas consultan al proveedor.",
        "output": "PNG en la carpeta de resumen; nuevo valor ~/Downloads/daily. Los datos ausentes no son un cero medido."
      },
      "desktop": {
        "title": "Previsualiza ventanas y crea notas de contexto",
        "summary": "Cambia de ventana y deja una nota para ese lugar.",
        "entry": "Ajustes → Vista previa de ventanas / Notas de contexto; Dock, Command+Tab y bandeja.",
        "steps": [
          "Activa las vistas y sus permisos, pasa por una app del Dock o usa Command+Tab y pulsa la tarjeta.",
          "En una página, ventana o escritorio de ejemplo, mantén la tecla configurada y agita; escribe y guarda la nota.",
          "Vuelve al lugar o abre desde la bandeja; añade un recordatorio recurrente o una captura si lo necesitas."
        ],
        "shortcuts": "Command+Tab cambia de app. Las notas usan Command mantenido por defecto, configurable en Ajustes.",
        "permissions": "Vistas: Accesibilidad y Grabación de pantalla. Detectar ventanas usa Accesibilidad; capturas adjuntas Grabación de pantalla.",
        "output": "Notas y capturas en datos locales de bandeja bajo ~/Library/Application Support/zisla."
      },
      "playback": {
        "title": "Elige reproducción y mezcla el volumen de apps",
        "summary": "Selecciona salida y ajusta aplicaciones en reproducción.",
        "entry": "Zona multimedia → Salida; Ajustes → Fuente multimedia; isla → Mezclador.",
        "steps": [
          "Reproduce audio de ejemplo y elige una salida disponible.",
          "Selecciona fuente automática o reproductor preferido y prueba los controles.",
          "En macOS 14.4+, abre el mezclador, concede Grabación de audio del sistema y ajusta o silencia una app."
        ],
        "shortcuts": "Botones y deslizadores; sin atajo fijo.",
        "permissions": "Mezclador: macOS 14.4+ y Grabación de audio del sistema. Los dispositivos dependen de conexiones; Bluetooth puede requerir permiso.",
        "output": "La salida es la selección del sistema. El volumen por app se guarda localmente; no se exportan archivos."
      }
    },
    "workflowsTitle": "Demostraciones breves",
    "workflows": {
      "copy-next": {
        "title": "Busca, copia y reutiliza",
        "steps": [
          "Busca la palabra de ejemplo «brew» en el historial.",
          "Copia el elemento coincidente.",
          "Pega en la app destino. El fragmento muestra búsqueda y copia; una nueva copia tiene acciones rápidas aparte."
        ]
      },
      "drop-output": {
        "title": "Suelta un archivo y prepara su salida",
        "steps": [
          "Arrastra una imagen de ejemplo desde Finder hasta la bandeja superior.",
          "Abre la bandeja y selecciona la imagen.",
          "Arrastra al destino o guarda una captura como PNG. El fragmento muestra el arrastre a la bandeja."
        ]
      },
      "meeting-note": {
        "title": "De la reunión a la nota",
        "steps": [
          "Abre la reunión con su enlace para unirse.",
          "Elige Nueva nota o Vincular nota existente.",
          "Guarda y abre desde el evento o la bandeja. El fragmento muestra creación y vínculo."
        ]
      }
    },
    "excerptLabel": "Reproducir fragmento",
    "guideLinkLabel": "Leer guía",
    "videoNotice": "Fragmentos de la presentación existente con datos de demostración. Los subtítulos del vídeo están en inglés; los pasos usan tu idioma. La presentación completa de 2:40 y los créditos musicales están abajo.",
    "preferencesTitle": "Preferencias útiles",
    "preferences": [
      "En Ajustes → Mascota puedes previsualizar las mascotas integradas e importadas. «Mascota fija» mantiene una sola mascota. «Rotación aleatoria» incluye todas por defecto. Limita la lista en «Mascotas para el sorteo». El cambio se hace a medianoche según la hora local. En «Intervalo de cambio», elige «Personalizado» para indicar una duración entre 1 segundo y 99:59:59. El valor inicial es de 1 hora.",
      "Activa agitar al arrastrar para mostrar la bandeja. Las notas de contexto tienen su propia tecla mantenida.",
      "Elige salida de audio en la zona multimedia y fuente automática o reproductor preferido en Ajustes. Esta opción no asigna dispositivos distintos por app.",
      "Sonidos y estadísticas de teclado son independientes y usan Monitorización de entrada. El mezclador necesita macOS 14.4+ y Grabación de audio del sistema.",
      "El resumen diario ofrece 8 plantillas, vista previa y exportación PNG manual o diaria con carpeta independiente."
    ]
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
      'v0.1.25': [
        'Inicia la limpieza de archivos innecesarios desde las utilidades con tus ajustes actuales. El progreso y los resultados aparecen en la isla; los mensajes de resultados de IA se mantienen legibles antes de volver a mostrar la limpieza.',
        'El contenido de las capturas fijadas cambia de tamaño junto con el marco al usar la barra de herramientas, el trackpad o las esquinas, también con imágenes HDR.',
        'El tiempo de actualización del tiempo meteorológico aparece una sola vez para la lista y las fuentes se agrupan sin duplicados.',
        'Las estadísticas de escritura recuperan la barra de desplazamiento vertical y el panel se mantiene dentro del área visible.',
        'Las herramientas de audio se ajustan al área visible de los ajustes, con desplazamiento independiente para la lista de operaciones y el panel de edición.',
        'El mezclador de volumen oculta las fuentes de audio inactivas, conserva los controles de volumen y silencio guardados y permite reintentar la detección de audio si falla.',
      ],
      'v0.1.24': [
        'El historial del portapapeles permite buscar y agrupar por aplicación de origen. Las acciones rápidas reconocen comandos que contienen here-documents.',
        'La limpieza del sistema puede ejecutarse en segundo plano con progreso y resultados en la isla. La limpieza del disco detecta instalaciones duplicadas y residuos de actualizaciones de aplicaciones.',
        'Todas las carpetas de salida se pueden restaurar a sus valores predeterminados con una acción. Se reorganizan los grupos y el orden de las páginas de ajustes.',
        'Los dispositivos compatibles pueden grabar en HDR. Se recuperan el reconocimiento de texto, la traducción y las vistas previas HDR de capturas; la selección de ventanas incluye los ajustes de zisla.',
        'Las notas rápidas admiten navegación con Command y las flechas. El texto pegado conserva la tipografía nativa del cuerpo de texto.',
        'Los ajustes de cuota de IA admiten regiones independientes. El historial diario y los colores de cuota restante coinciden entre tarjetas expandidas y avisos compactos. Cancelar un turno de Kimi borra sus errores; una actualización de suscripción cancelada no lee credenciales.',
        'Las vistas previas filtran ventanas cerradas y duplicadas, respetan su identidad al usar métodos alternativos y se ocultan mientras están abiertos los menús contextuales del Dock.',
        'La monitorización de medios actualiza fuentes obsoletas y finaliza la actividad de audio cuando dejan de llegar muestras. Se conserva el volumen por aplicación y los fundidos siguen el tiempo de las muestras decodificadas. Los sonidos y estadísticas del teclado gestionan la ausencia de reproducción y los datos vacíos.',
        'Los permisos se actualizan al conceder acceso, con una ayuda para arrastrar la aplicación durante la configuración. Los errores de las herramientas recomendadas siguen siendo legibles.',
      ],
      'v0.1.23': [
        'Las herramientas de imagen añaden nueve operaciones locales: compresión, conversión entre cinco formatos, tamaño y recorte, comparación del formato más pequeño, giro y reflejo, marcas de agua, mosaico y desenfoque, reconocimiento de texto y tablas, y eliminación de fondo. Admiten exportación por lotes o ZIP y carpetas independientes para PDF e imagen.',
        'Las herramientas de audio añaden 27 operaciones locales de conversión, edición, división, unión, mezcla, extracción, normalización LUFS, efectos, canales y etiquetas. Requieren FFmpeg y ffprobe; elige un archivo o carpeta de exportación.',
        'El seguimiento de cuentas de IA añade anillos de cuota restante, horas de reinicio y avisos de cuota baja en los diseños de la isla, incluidas ventanas 5h/7d y presupuestos USD de Cursor cuando están disponibles. Los resúmenes diarios pueden incluir cuotas reales y su hora de consulta.',
        'Selecciona una fecha en la tendencia de uso de IA o el mapa térmico para ver tokens de entrada, salida y totales por proveedor y modelo. Consulta, exporta todo el historial como .xlsx o bórralo en Ajustes. Inicio agrupa los trabajos de IA por aplicación y muestra el resultado de exportar resúmenes en la isla.',
        'Los eventos con enlace de reunión muestran una cuenta atrás desde 10 minutos antes del inicio y permiten unirse con un clic. Crea notas de reunión o vincula y desvincula notas contextuales. Mail añade marcar toda la bandeja de entrada como leída.',
        'La bandeja añade búsqueda, filtros y selección múltiple para copiar, compartir o enviar a notas rápidas. Convierte imágenes a PDF, reconoce su texto para notas y abre los vídeos seleccionados en el estudio de grabación.',
        'Elige modos de energía automáticos para corriente y batería, con la opción de mantener el bajo consumo al 20% o menos. Carga de inmediato al 100% cuando macOS lo permita. En Ajustes puedes ver el historial del sistema, exportarlo como .xlsx y borrarlo.',
        'Los diseños Pomodoro compactos horizontales y verticales añaden progreso, pausa, reanudación y reinicio. Pasar el puntero por los controles mantiene la isla contraída, también en el diseño vertical con más información.',
        'Las capturas largas añaden desplazamiento automático lento en la ventana elegida. La captura HDR está disponible en dispositivos compatibles y la edición conserva los ajustes de renderizado y exportación de imágenes.',
        'Las acciones rápidas pueden reparar una app que no abre tras verificar su integridad, firma y política de seguridad de macOS. Reordena las acciones por tipo, consulta más ejemplos y usa símbolos monetarios regionales o códigos con prefijo. Las búsquedas de vuelos, trenes y paquetes tienen prioridad.',
        'Ajustes separa el diseño de Dynamic Island, el resumen diario, las notificaciones y cuidados, y el flujo de trabajo en páginas propias. Reordena las prioridades compactas y activa las actualizaciones diarias de componentes instalados. La limpieza de grabaciones pasa a Monitor del Sistema y Limpieza y conserva las transcripciones.',
        'Las descargas muestran nombres reales de destino cuando están disponibles. El renderizado en reposo, los escaneos de IA, la carga del historial y la reproducción del estudio consumen menos recursos. Se ajustan los logos compactos de IA, tarjetas de cuota y animaciones, y se corrigen el desplazamiento del tiempo, las entregas a la bandeja, las escrituras de Mail y la conservación del portapapeles.',
        'La página de inicio añade un recorrido de 160 segundos que se reproduce al hacer clic y un enlace al vídeo original. El sitio sigue siendo utilizable sin WebGL y las apps recomendadas incluyen el espacio de trabajo de terminal Zshell.',
      ],
      'v0.1.22': [
        'El estudio añade suavizado de piel, brillo, afinamiento de cara y cuerpo, preajustes de voz regulables y monitorización opcional del micrófono. Ajusta los efectos antes de grabar y durante la edición.',
        'Las estelas suaves del cursor permiten elegir el color. La reproducción en el estudio muestra el resultado editado con sus pistas, efectos y audio.',
        'Ajustes → Ubicación de guardado separa descargas, capturas, grabaciones, Acciones rápidas y resúmenes diarios. La actualización conserva las ubicaciones anteriores y luego cada carpeta se cambia de forma independiente.',
        'La limpieza opcional mueve elementos a la Papelera cada 7, 15 o 30 días. Elige elementos fiables o todos los procesables, incluidos los que requieren revisión; viene desactivada. La limpieza de disco añade revisión de carpetas de IA sin sesiones conservadas, protegiendo sesiones guardadas y carpetas nuevas.',
        'El historial del portapapeles puede borrar automáticamente entradas de más de 7, 15 o 30 días conservando favoritos. El borrado automático viene desactivado.',
        'Notas rápidas previsualiza adjuntos manuscritos y permite editar el texto anterior o posterior mediante Notas, conservando los adjuntos originales.',
        'El monitor de IA oculta las cuotas restantes y conserva el uso diario, con mejoras en el desplazamiento de gráficos y etiquetas de meses. Los ajustes de batería se reúnen en Estado del sistema.',
        'Quiet.md se incorpora a las apps recomendadas para notas locales, con instalación y gestión desde Ajustes.',
        'Bilibili respeta la parte de vídeo elegida y admite más formatos de enlace. La eliminación del calendario afecta a la ocurrencia recurrente seleccionada. Las capturas fijadas permanecen entre capturas, con etiquetas de herramientas más claras e indicadores de tamaño más fiables.',
      ],
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
        answer: 'El tiempo, las actualizaciones firmadas, las descargas que inicias y la limpieza de voz remota opcional usan la red cuando hace falta. La detección de enlaces es local. El modelo local corrige el texto después de la transcripción; el reconocimiento de voz de Apple puede seguir usando la red, según el idioma y la compatibilidad del sistema. Al activar el seguimiento de cuotas de IA también se consultan los servicios de los proveedores elegidos.',
      },
      multiDisplay: {
        question: '¿zisla admite varias pantallas?',
        answer: 'Sí: varias pantallas, Spaces y apps normales a pantalla completa; al expandirse nunca roba el foco. Con varias pantallas conectadas, Ajustes → General → Modos de pantalla permite elegir para cada una el modo Dynamic Island (posición de cámara o personalizada), el modo muesca u ocultarla. Con una sola pantalla, este ajuste se oculta y se usa la apariencia global; al volver a conectarlas se recupera la configuración guardada de cada pantalla. Todas las pantallas visibles mantienen su isla contraída al mismo tiempo. La expansión, las acciones rápidas, la grabación y los mensajes temporales sustituyen solo la isla de su propia pantalla; la selección de pantallas para notificaciones filtra el contenido sin ocultar la isla inactiva.',
      },
      intel: {
        question: '¿Puedo usarlo en un Mac Intel?',
        answer: 'Puede existir una compilación para Intel, pero no se garantiza la compatibilidad. La configuración compatible actual es Apple Silicon.',
      },
      storage: {
        question: '¿Dónde guarda zisla sus datos?',
        answer: 'Los datos locales están en ~/Library/Application Support/zisla/. Las estadísticas de escritura se guardan aparte en ~/Library/Application Support/zisla/typing-stats.sqlite3. Las notas rápidas usan la app Notas del sistema. Ajustes → Ubicación de guardado ofrece carpetas independientes para descargas, herramientas PDF e imagen, capturas, grabaciones, acciones rápidas y resúmenes diarios. La actualización conserva las ubicaciones elegidas y luego permite cambiar cada carpeta por separado. Restaura todas las carpetas de guardado predeterminadas con una sola acción.',
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
      "Usa un fondo opaco cuando está activado Reducir transparencia",
      'Liquid Glass en macOS 26+, con retorno automático a materiales nativos en macOS 14 y 15',
    ],
  },
  film: {
    title: "Vídeo de presentación",
    videoAriaLabel: "Vídeo de presentación de zisla",
    openVideoLabel: "Abrir el vídeo",
    playbackError: "No se puede reproducir el vídeo.",
    musicLabel: "Música",
    excerptLabel: "Fragmento",
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
