import { createCatalog } from './createCatalog';

export const ptBR = createCatalog({
  meta: {
    documentTitle: 'zisla · Espaço de trabalho dinâmico',
    description:
      'zisla é um espaço nativo do macOS para tarefas de IA, relatórios diários e edição de gravações, com mascotes personalizados, capturas e permissões reunidos.',
    ogTitle: 'zisla · Coloque o que está acontecendo onde você pode ver',
    ogDescription:
      'Mantenha tarefas de IA e seu dia à vista, grave e edite no Mac, importe seu mascote e gerencie permissões em um lugar.',
  },
  tagline: 'Espaço de trabalho dinâmico nativo para macOS',
  header: {
    navAriaLabel: 'Navegação principal',
    brandHomeAriaLabel: 'Início do zisla',
    menuOpenLabel: 'Abrir menu de navegação',
    menuCloseLabel: 'Fechar navegação',
    menuButtonTitle: 'Abrir navegação',
    navItems: {
      showcase: 'Recursos',
      ai: 'Fluxo de IA',
      download: 'Baixar',
      changelog: 'Registro de alterações',
      faq: 'Perguntas frequentes',
      developers: 'Desenvolvedores',
    },
    downloadCta: 'Baixar',
    downloadCtaAriaLabel: 'Ir para a seção de download',
    languageLabel: 'Idioma da interface',
    themeLabel: 'Aparência',
    themeModes: { auto: 'Automático (sistema)', light: 'Modo claro', dark: 'Modo escuro' },
  },
  hero: {
    eyebrow: 'ESPAÇO DE TRABALHO NATIVO PARA MACOS',
    title: 'zisla<br><em>O que está acontecendo,<br>bem onde você pode ver.</em>',
    lede:
      'Reúna tarefas de IA, mídia, arquivos e agenda no topo da tela. Depois de copiar algo, uma barra de ações rápidas separada mostra uma prévia e sugere o próximo passo. Ela aparece quando necessário e sai do caminho quando você termina.',
    downloadCta: 'Baixar',
    downloadCtaAriaLabel: 'Baixar',
    sourceCta: 'Ver código',
    sourceCtaAriaLabel: 'Ver o código-fonte do zisla no GitHub',
    hints: [
      'Mova o cursor para o topo da tela para expandir, sem clicar',
      'Depois de copiar, pressione Command+N para o próximo passo inteligente',
      'Recolhe sozinha sem interromper seu trabalho',
    ],
  },
  proof: {
    ariaLabel: 'Visão geral do produto',
    items: {
      modules: { title: '{count} módulos no topo', desc: 'Ative os fluxos de que precisa' },
      os: { title: 'macOS 14+', desc: 'Uma experiência de desktop nativa' },
      displays: { title: 'Vários monitores', desc: 'Funciona em telas com notch e externas' },
      local: { title: 'Local primeiro', desc: 'O estado da IA nunca lê suas conversas' },
    },
  },
  showcase: {
    eyebrow: 'UM PONTO DE ENTRADA / FLUXOS DIÁRIOS',
    title: 'Fluxos do dia a dia, <span>no topo da tela.</span>',
    lede:
      'De tarefas de IA ao clipboard, agenda e estado do sistema, o zisla reúne fluxos espalhados em um único ponto de entrada.',
    ariaLabel: 'Catálogo de recursos do zisla',
    summaryMono: '{modules} MÓDULOS / {groups} FLUXOS',
    summaryLede:
      'Dos fluxos no topo às ferramentas locais, cada tarefa que você realmente pode concluir está descrita aqui.',
    summaryNote:
      '{modules} módulos no topo e {features} recursos independentes, de prévias de janelas e capturas à gestão de IA e aos apps recomendados.',
    groupNames: {
      island: 'Fluxos no topo',
      ai: 'Fluxo de IA',
      daily: 'Informações diárias',
      tools: 'Utilitários',
    },
    groupCount: '{count} módulos',
    pointsAriaLabel: 'Destaques de {name}',
    modules: {
      dashboard: {
        name: 'Início',
        caption:
          'Cartões dinâmicos aparecem apenas durante uma sessão de foco, tarefa de IA ou download; quando nada acontece, não ocupam espaço.',
        points: ['Aparece sob demanda', 'Progresso em tempo real', 'Layout adaptável'],
      },
      shelf: {
        name: 'Prateleira',
        caption:
          'Arraste arquivos, áudio, vídeo ou links para a faixa no topo da tela para guardá-los na prateleira, mostrá-los no Finder ou abrir o menu Compartilhar do macOS.',
        points: ['Arraste para o topo e guarde', 'Mostrar no Finder', 'Menu Compartilhar do sistema'],
      },
      clipboard: {
        name: 'Clipboard',
        caption:
          'Consulte o histórico do clipboard dentro da ilha e filtre por imagem, URL, caminho ou tipo de arquivo e veja quando cada item foi copiado. Envie um item para Notas rápidas, fixe-o como favorito ou exclua-o.',
        points: ['Histórico dentro da ilha', 'Filtro por tipo', 'Notas rápidas e favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Detecta atividade de CLIs, apps de desktop e IDEs compatíveis e mostra tarefas, estado, tendências acumuladas de tokens e um mapa de contribuições. Analisa apenas eventos estruturados e nunca lê conversas. Há detecção de tarefas do Cursor, além de uso numérico e cotas de assinatura disponíveis do Cursor e Muse Code; execuções longas de ferramentas no Cursor continuam visíveis.',
        points: ['Tarefas agregadas entre ferramentas', 'Tendências de consumo de tokens', 'Nunca lê prompts ou respostas'],
      },
      keyboardSound: {
        name: 'Sons do teclado',
        caption:
          'Reproduz 20 sons mecânicos integrados para teclas globais, com volume ajustável e variação natural de tom, além de sons de soltura quando disponíveis. Ative as estatísticas locais para ver resumo, tendências, histórico, linha do tempo de apps e mapa por tecla F1-F12. Totais de voz, duração do ditado, velocidade e tempo economizado também aparecem no painel do teclado. Novas configurações ativam sons e estatísticas, com controles separados.',
        points: ['20 sons integrados', 'Som de soltura e variação de tom', 'Estatísticas com controle separado'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Cole um link ou deixe o zisla identificá-lo no clipboard quando ativado. Escolha vídeo ou áudio e baixe para a pasta padrão ou outra de sua escolha. Links compatíveis exibem ícone de origem, progresso ao vivo e estado final. Downloads, gravações e capturas de tela compartilham este local de salvamento.',
        points: ['Modos vídeo / áudio', 'Pasta padrão ou personalizada', 'Origem e progresso ao vivo'],
      },
      agenda: {
        name: 'Agenda e clima',
        caption:
          'Mostra o clima da sua localização e de até seis lugares escolhidos. Veja, adicione e exclua eventos e lembretes, e marque lembretes como concluídos.',
        points: ['Cartões de clima para vários lugares', 'Calendário e tarefas', 'Conclua um lembrete com um toque'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Lê as contas ativadas no Mail, mostra a caixa de entrada e permite marcar, responder, redigir e mover mensagens para o Lixo dentro da ilha, com orientação clara quando falta uma permissão. Selecione arquivos durante a composição para anexá-los à mensagem.',
        points: ['Contas do Mail', 'Responder e redigir na ilha', 'Permissões transparentes'],
      },
      quickNotes: {
        name: 'Notas rápidas',
        caption:
          'Usa o app Notas do sistema para ver, editar, criar e excluir notas com prévia Markdown ao vivo, e ir direto às primeiras nove notas com Command+1 a 9. Os rascunhos são gravados de volta automaticamente.',
        points: ['Dados nas Notas', 'Editor Markdown', 'Rascunhos salvos automaticamente'],
      },
      volumeMixer: {
        name: 'Mixer de volume por aplicativo',
        caption: 'Ajuste o volume e silencie separadamente os apps que reproduzem áudio. Requer macOS 14.4 ou posterior e permissão de gravação de áudio do sistema.',
        points: ['Volume por app', 'Silenciar separadamente', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilitários',
        caption:
          'Temporizador de foco, manter a tela ativa, limpeza de tela e teclado (bloqueia inclusive F1-F12), teleprompter, espelho e Lixo em uma única página.',
        points: ['Temporizador de foco', 'Bloqueia F1-F12 durante a limpeza', 'Teleprompter e espelho'],
      },
      system: {
        name: 'Estado do sistema',
        caption:
          'Veja CPU, GPU, memória, disco, rede e ventoinhas; leia a temperatura SMART de NVMe quando o hardware informar, guarde um histórico por minuto que você pode grafar em qualquer período e exportar como .xlsx. Analise caches de apps e de usuário da Apple, registros e arquivos de preferências residuais. Revise a seleção, mova os itens para o Lixo e confira os resultados. Veja carga, saúde, ciclos, temperatura e capacidade deste Mac, além do nível de bateria de dispositivos próximos exposto pelo sistema. Os endereços IPv4 e IPv6 públicos são exibidos separadamente. O histórico é mantido por padrão até você apagá-lo.',
        points: ['Monitoramento no nível do chip', 'Gráficos de histórico e exportação .xlsx', 'Revise antes de mover para o Lixo'],
      },
    },
  },
  extensions: {
    eyebrow: 'DENTRO E FORA DA ILHA',
    title: 'Longe da ilha, <span>ainda uma ferramenta de desktop.</span>',
    lede:
      'Capturas, voz, mídia, downloads do navegador e gestão de IA aparecem onde são mais fáceis de acessar.',
    ariaLabel: 'Recursos de desktop independentes',
    summaryMono: 'ALÉM DA ILHA',
    summaryLede: 'Recursos frequentes, cada um em seu lugar natural.',
    summaryNote:
      'Prévias de janelas, capturas e ações rápidas ficam à mão; os apps recomendados ajudam você a descobrir mais ferramentas para o desktop.',
    features: {
      floatingIsland: {
        title: 'Uma ilha flutuante que se adapta',
        description: 'Use a posição da câmera ou escolha uma posição na borda da tela. A posição personalizada é lembrada ao trocar de modo. Layouts compactos horizontais e verticais ajustam o comprimento a ícones, tarefas de IA, downloads e mídia, com uma opção para exibir mais informações.',
        detail: 'Posição personalizada · Ícones persistentes · Informações adaptáveis',
      },
      dailyBriefing: {
        title: 'Seu dia em um relatório diário',
        description: 'Escolha entre oito modelos, selecione dados de uso, digitação, sistema e atividade zisla e confira a prévia. Exporte um PNG manualmente ou em um horário diário. O histórico de Tempo de Uso entra quando ativado e disponível; dados ausentes não são apresentados como zero medido.',
        detail: '8 modelos · Conteúdo à escolha · Prévia e exportação PNG agendada',
      },
      userCare: {
        title: 'Lembretes durante o trabalho',
        description: 'Ajuste o intervalo para pausas, água, movimento e descanso dos olhos. As mensagens acompanham o horário do dia. Pausas naturais, bloqueio e repouso reiniciam a contagem. Concluir o foco ou trabalhar com notas pode mostrar um retorno breve. Ative ou desative nos Ajustes.',
        detail: 'Intervalo ajustável · Mensagens por horário · Respeita inatividade e repouso',
      },
      contextNotes: {
        title: 'Notas ligadas a um lugar',
        description: 'Salve uma nota editável para uma página, janela ou mesa e veja-a ao voltar. Anexe uma captura de janela, gerencie as notas na prateleira e configure lembretes recorrentes de uma hora a três dias, ou desative-os.',
        detail: 'Notas de localização · Capturas de janelas · Lembretes recorrentes',
      },
      recording: {
        title: 'Grave e edite no estúdio',
        description: 'Grave tela, janela ou região com áudio do sistema, microfone e câmera opcionais. Edite vídeos, áudio, imagens e texto em várias faixas, adicione animações, zooms e legendas e confira uma prévia nítida. Escolha proporção original, 16:9, 9:16, 1:1 ou 4:3. Exporte vídeo, GIF, Live Photo ou áudio; alguns formatos exigem FFmpeg. Propostas opcionais de IA são revisadas antes de aplicar. As gravações usam o local definido nos ajustes de download.',
        detail: 'Edição multifaixa · Proporções e prévia · Vídeo, GIF, Live Photo e áudio',
      },
      permissions: {
        title: 'Permissões do sistema em um lugar',
        description: 'Veja os estados em Ajustes → Permissões, inicie pedidos compatíveis ou abra a página correspondente do sistema. As boas-vindas iniciais usam a mesma lista e identificam permissões com configuração manual.',
        detail: 'Estado das permissões · Pedidos e links · Compartilhado com as boas-vindas',
      },
      pdf: {
        title: 'Ferramentas de PDF',
        description: 'Disponível nos Ajustes, fora do carrossel de módulos da ilha. Quatorze operações no próprio Mac: unir, dividir, girar, recortar, converter imagens e arquivos Office, renderizar imagens, extrair texto, adicionar marcas d’água e números de página, criptografar, remover senha e editar metadados.',
        detail: '14 ferramentas no dispositivo · Una na ordem que quiser · Nada sai do seu Mac',
      },

      windowPreviews: {
        title: 'Veja a janela e clique para alternar',
        description:
          'Veja janelas pelo Dock ou com Command-Tab e clique no cartão para ativar a janela. Novas configurações ativam esse recurso; gerencie-o e suas permissões nos Ajustes.',
        detail: 'Dock e Command-Tab · Trocar de janela com um clique · Configurável',
      },
      capture: {
        title: 'Capturas, rolagem e fixação',
        description:
          'Capture, fixe ou una capturas com rolagem usando atalhos personalizáveis. Destaque áreas, extraia partes da imagem, arredonde cantos e preserve anotações ao exportar. Reconheça e copie texto, traduza e copie o resultado ou exporte tabelas reconhecidas como .xlsx. Guarde capturas na prateleira. Os ajustes verificam conflitos com voz e Ações Rápidas. A caixa de diálogo de salvamento abre na pasta de download atual.',
        detail: 'Destaque e extração · Reconhecimento, tradução e cópia · Cantos arredondados e .xlsx',
      },
      voice: {
        title: 'Entrada de voz e limpeza',
        description:
          'Alterne com uma tecla ou segure para falar usando o reconhecimento do sistema, com vocabulários especializados e palavras personalizadas. Se quiser, use Ollama, LM Studio ou um modelo remoto para corrigir a transcrição preservando o sentido e formatar itens enumerados explicitamente.',
        detail: 'Dois modos de gravação · Vocabulários e palavras-chave · Limpeza opcional',
      },
      media: {
        title: 'Mídia e sons ambientes do sistema',
        description:
          'Controle o que está tocando no topo da ilha ou escolha um som ambiente do macOS. Ele pode parar ao bloquear a tela, iniciar o protetor ou suspender o monitor. Escolha uma onda ou brilho da capa; o progresso também aparece nos layouts compactos e flutuantes.',
        detail: 'Controle de reprodução · Letras sincronizadas · Parada automática',
      },
      browserDownloads: {
        title: 'Progresso de downloads do navegador',
        description:
          'Detecta downloads do Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc, mostrando origem e progresso ao vivo no topo.',
        detail: '8 navegadores · Detecção de origem · Aviso de conclusão',
      },
      copyAssistant: {
        title: 'Ações rápidas e próximos passos',
        description:
          'Quando ativado, mostra uma prévia de textos, links, arquivos ou imagens copiados em uma barra separada e sugere abrir, mostrar no Finder, buscar, traduzir, calcular ou salvar, somente após sua confirmação. Abra a pasta do arquivo pelas ações rápidas após um download do navegador ou uma transferência AirDrop. Aceita pastas padrão e escolhidas no Chrome, com ativação independente do progresso dos downloads. IPs têm ações separadas para consulta e abertura do link. A conversão reconhece subunidades monetárias e o catálogo inclui Emoji 18.0.',
        detail: 'Ativação opcional · Reconhecimento local · Command+N por padrão',
      },
      aiManagement: {
        title: 'Gestão de CLIs de IA e Skills',
        description:
          'Detecte, instale, atualize e remova CLIs de IA nos Ajustes, além de revisar e gerenciar Skills locais para alternar menos entre terminais e ferramentas.',
        detail: 'Detectar e instalar · Atualizar e remover · Skills locais',
      },
      pet: {
        title: 'Mascote da ilha',
        description: 'Escolha no catálogo ampliado de animais e personagens ou importe uma imagem, animação ou vídeo compatível com um nome próprio. Posicione o mascote em um lado da ilha e remova os importados nos Ajustes. Animações de até 30 segundos e arquivos de até 100 MB.',
        detail: 'Catálogo ampliado · Importar imagens e vídeos · Remover mascotes personalizados',
      },
      lockScreen: {
        title: 'Informações da tela bloqueada',
        description:
          'Mostre opcionalmente data, estado e reprodução na tela bloqueada do macOS. É uma sobreposição independente e nunca aparece na lista ou no carrossel de módulos da ilha.',
        detail: 'Sobreposição independente · Ativação opcional · Não rouba o foco',
      },
      recommendedTools: {
        title: 'Apps recomendados',
        description:
          'Conheça OpenScreen para gravação de tela e edição de vídeo e DockDoor para prévias de janelas no Dock e alternância de apps. São aplicativos de terceiros instalados separadamente.',
        detail: 'Descubra ferramentas para o desktop · Apps de terceiros · Instalação separada',
      },
    },
  },
  ai: {
    eyebrow: 'IA SEM CAIXA-PRETA',
    title: 'Veja o estado da IA <span>sem ler a conversa.</span>',
    lede:
      'Tarefas, estado e tendências de tokens ficam no seu Mac. Esta página descreve o recurso sem simular uma tarefa em execução.',
    summaryMono: 'ESTADO LOCAL / LIMITES CLAROS',
    summaryLede: 'Conecte as ferramentas de IA que você já usa, mantendo os limites de contexto necessários.',
    summaryNote: 'A página explica apenas escopo de detecção, dados e conexão; não simula uma sessão ao vivo.',
    toolsHeading: 'Ferramentas de IA compatíveis',
    toolsLede: 'Detecta atividade de CLIs, apps e IDEs compatíveis e agrega o estado das tarefas.',
    toolsAriaLabel: 'Ferramentas de IA compatíveis',
    boundariesHeading: 'Somente o estado é registrado',
    privacyPoints: [
      'Analisa apenas tipo de evento, estado, horário, modelo e ID da sessão em eventos estruturados',
      'Nunca lê o texto de prompts ou respostas',
      'Protocolo e estado ficam armazenados no seu Mac',
    ],
    bridgeHeading: 'Conecte suas próprias tarefas',
    bridgeLede: 'Use zislactl para enviar o estado estruturado de tarefas externas à barra superior.',
    zislactlTaskTitle: 'Build e publicação',
    copyZislactlAriaLabel: 'Copiar o comando zislactl',
  },
  flow: {
    eyebrow: 'RITMO DE INTERAÇÃO',
    title: 'Suba, <span>olhe e deixe passar.</span>',
    lede: 'Nunca rouba o foco e se recolhe quando você termina de olhar.',
    ariaLabel: 'Ritmo de interação no topo',
    summaryMono: 'BARRA DE STATUS / 3 PASSOS',
    summaryLede: 'Expande quando você precisa e se recolhe quando termina.',
    summaryNote: 'É acionada pela posição do cursor, não ocupa espaço vazia e nunca rouba o foco.',
    steps: {
      trigger: {
        phase: 'Acionar',
        title: 'Mova o cursor para o centro superior',
        desc: 'Telas com notch e externas usam o mesmo acionador; oculta, nenhum loop de quadros é executado.',
      },
      review: {
        phase: 'Revisar',
        title: 'Veja o estado atual de relance',
        desc: 'Mídia, arquivos, IA, agenda e ferramentas do sistema ficam no mesmo lugar.',
      },
      dismiss: {
        phase: 'Fechar',
        title: 'Volte ao que estava fazendo',
        desc: 'Afaste o cursor e ela se recolhe; expandir nunca ativa o app nem toma o foco.',
      },
    },
  },
  download: {
    eyebrow: 'PRONTO QUANDO VOCÊ ESTIVER',
    title: 'Baixar zisla',
    copy:
      'Para Macs com Apple Silicon. Versões, outras arquiteturas e checksums estão na página de releases. Após instalar, o Sparkle verifica a assinatura primeiro e depois baixa, instala e reinicia manual ou automaticamente conforme seus ajustes, e as atualizações mantêm as permissões já concedidas. Se uma versão não interessa, ignore-a e ela não será lembrada de novo. Leia as notas de versão antes da instalação e depois de reiniciar.',
    primaryCta: 'Baixar',
    primaryCtaAriaLabel: 'Baixar o zisla',
    releaseCta: 'Ver release',
    releaseCtaAriaLabel: 'Ver os detalhes da release no GitHub',
    brewMono: 'HOMEBREW / UM COMANDO',
    brewNote: 'O Sparkle mantém o zisla atualizado, então o brew upgrade só substitui o app quando a cópia instalada é realmente mais antiga que a do tap — a partir do Homebrew 5.1.6 é lida a versão do próprio app. Nomear o cask, como em brew upgrade --cask zisla, usa os registros de instalação do Homebrew e pode levar você de volta à versão do tap depois de uma atualização do Sparkle. O tap serve apenas versões estáveis. Ele é um tap de terceiros e o app não é notarizado, por isso a primeira abertura exige "Abrir mesmo assim" em Ajustes do Sistema → Privacidade e Segurança.',
    copyBrewCommandAriaLabel: 'Copiar o comando de instalação do Homebrew',
    notes: {
      system: { term: 'Sistema', value: 'macOS 14 ou posterior · Configuração compatível atual: Mac com Apple Silicon' },
      install: { term: 'Instalação', value: 'Monte o DMG e arraste para Aplicativos' },
      package: { term: 'Pacote', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Outras arquiteturas', value: 'Página de releases' },
      mirror: { term: 'Espelho', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.21': [
        'O monitoramento do sistema mantém por padrão todo o histórico por minuto, existente e novo, até você apagá-lo. Os gráficos por período e a exportação .xlsx continuam disponíveis.',
        'Downloads, gravações e capturas de tela compartilham um local. O diálogo para salvar capturas abre na pasta de download atual; o ajuste duplicado de local das gravações foi removido.',
        'O local de exibição dos indicadores de status e sua entrada de busca aparecem apenas nas pílulas com posição personalizada. A linha fica oculta em layouts com recorte ou pílulas na câmera quando só podem usar a barra de menus.',
        'A contagem regressiva das Ações Rápidas usa uma barra de progresso inferior nos layouts com recorte. As pílulas mantêm o progresso por todo o contorno.',
      ],
      'v0.1.20': [
        'Escolha entre oito modelos, selecione dados de uso, digitação, sistema e atividade zisla e confira a prévia. Exporte um PNG manualmente ou em um horário diário. O histórico de Tempo de Uso entra quando ativado e disponível; dados ausentes não são apresentados como zero medido.',
        'Ajuste o intervalo para pausas, água, movimento e descanso dos olhos. As mensagens acompanham o horário do dia. Pausas naturais, bloqueio e repouso reiniciam a contagem. Concluir o foco ou trabalhar com notas pode mostrar um retorno breve. Ative ou desative nos Ajustes. Salve uma nota editável para uma página, janela ou mesa e veja-a ao voltar. Anexe uma captura de janela, gerencie as notas na prateleira e configure lembretes recorrentes de uma hora a três dias, ou desative-os.',
        'Use a posição da câmera ou escolha uma posição na borda da tela. A posição personalizada é lembrada ao trocar de modo. Layouts compactos horizontais e verticais ajustam o comprimento a ícones, tarefas de IA, downloads e mídia, com uma opção para exibir mais informações. Escolha uma onda ou brilho da capa; o progresso também aparece nos layouts compactos e flutuantes.',
        'Escolha no catálogo ampliado de animais e personagens ou importe uma imagem, animação ou vídeo compatível com um nome próprio. Posicione o mascote em um lado da ilha e remova os importados nos Ajustes. Animações de até 30 segundos e arquivos de até 100 MB.',
        'Grave tela, janela ou região com áudio do sistema, microfone e câmera opcionais. Edite vídeos, áudio, imagens e texto em várias faixas, adicione animações, zooms e legendas e confira uma prévia nítida. Escolha proporção original, 16:9, 9:16, 1:1 ou 4:3. Exporte vídeo, GIF, Live Photo ou áudio; alguns formatos exigem FFmpeg. Propostas opcionais de IA são revisadas antes de aplicar.',
        'Capture, fixe ou una capturas com rolagem usando atalhos personalizáveis. Destaque áreas, extraia partes da imagem, arredonde cantos e preserve anotações ao exportar. Reconheça e copie texto, traduza e copie o resultado ou exporte tabelas reconhecidas como .xlsx. Guarde capturas na prateleira. Os ajustes verificam conflitos com voz e Ações Rápidas.',
        'Há detecção de tarefas do Cursor, além de uso numérico e cotas de assinatura disponíveis do Cursor e Muse Code; execuções longas de ferramentas no Cursor continuam visíveis. IPs têm ações separadas para consulta e abertura do link. A conversão reconhece subunidades monetárias e o catálogo inclui Emoji 18.0.',
        'Ajuste o volume e silencie separadamente os apps que reproduzem áudio. Requer macOS 14.4 ou posterior e permissão de gravação de áudio do sistema. Disponível nos Ajustes, fora do carrossel de módulos da ilha. Veja os estados em Ajustes → Permissões, inicie pedidos compatíveis ou abra a página correspondente do sistema. As boas-vindas iniciais usam a mesma lista e identificam permissões com configuração manual. Totais de voz, duração do ditado, velocidade e tempo economizado também aparecem no painel do teclado. Novas configurações ativam sons e estatísticas, com controles separados. Selecione arquivos durante a composição para anexá-los à mensagem. Leia as notas de versão antes da instalação e depois de reiniciar.',
      ],
    },
    eyebrow: 'Registro de alterações',
    title: 'O que mudou em cada versão do zisla: novos recursos, melhorias e correções.',
    lede: 'O que mudou em cada versão do zisla: novos recursos, melhorias e correções.',
    ariaLabel: 'histórico de versões do zisla',
    releaseCountLabel: 'versões',
    latestLabel: 'mais recente',
    shippedLabel: 'publicado',
    latestBadge: 'Mais recente',
    noteLabel: 'versão',
    pagerAriaLabel: 'Páginas do changelog',
    pageLabel: 'Página {page}',
    prevPageLabel: 'Anterior',
    nextPageLabel: 'Próxima',
  },
  faq: {
    eyebrow: 'RESPOSTAS DIRETAS',
    title: 'Perguntas frequentes.',
    lede: 'Permissões, privacidade e compatibilidade.',
    items: {
      audience: {
        question: 'Para quem é o zisla?',
        answer: 'Para usuários de Mac que querem IA, mídia, arquivos e agenda em um só lugar. Telas sem notch também são compatíveis.',
      },
      aiPrivacy: {
        question: 'O zisla lê minhas conversas de IA?',
        answer: 'Não. O monitor de IA lê apenas o estado das tarefas, nunca o texto de prompts ou respostas.',
      },
      copyAssistant: {
        question: 'As ações rápidas abrem ou enviam o que copio?',
        answer: 'Não. O reconhecimento e a prévia acontecem no Mac, e o próximo passo só é executado após sua confirmação.',
      },
      permissions: {
        question: 'Quais permissões do sistema o zisla precisa?',
        answer: '<p>Ajustes → Permissões reúne estados, solicitações e links para os Ajustes do Sistema. Algumas permissões exigem configuração manual. Você escolhe quais pedidos iniciar; as boas-vindas iniciais também oferecem esses controles.</p><p>Gravação de tela e áudio do sistema, microfone e câmera atendem captura, gravação, mixer e espelho conforme a função. O ditado também usa reconhecimento de fala. Calendários, Lembretes, Localização, Bluetooth e Automação atendem os recursos relacionados. Adicionar uma cidade de clima manualmente não exige localização.</p><p>Novas configurações ativam sons do teclado e estatísticas, desativáveis separadamente. Eventos globais exigem monitoramento de entrada. As estatísticas guardam contagens, códigos de teclas, horários e nomes de apps, nunca o texto digitado. Acessibilidade permite inserção, gestos, limpeza e controle de janelas.</p><p>Acesso Total ao Disco pode ser necessário para o índice local de e-mail e o histórico de Tempo de Uso dos relatórios diários. O seletor de arquivos concede acesso à pasta escolhida. Desative recursos no zisla ou revogue permissões em Ajustes do Sistema → Privacidade e Segurança.</p>',
      },
      localVoice: {
        question: 'Como uso um modelo local para revisar a transcrição de voz?',
        answer: `
      <p>Ollama, LM Studio e outros serviços locais compatíveis com OpenAI são aceitos.</p>
      <ol>
        <li>Baixe ou carregue o modelo desejado no aplicativo de modelos locais e inicie o serviço.</li>
        <li>Abra Ajustes → Voz → Modelos Locais, adicione e ative uma configuração, escolha Ollama ou LM Studio e informe a URL do serviço. Para outros serviços compatíveis com OpenAI, escolha também LM Studio. Deixe API Key vazio se o serviço não exigir autenticação.</li>
        <li>Selecione um modelo descoberto automaticamente e escolha essa configuração em Modelo de Organização de Voz → Usar Modelo.</li>
      </ol>
      <p>O zisla sugere um modelo Gemma 4 QAT com base no chip e na memória RAM total. O modelo recomendado não é baixado nem carregado automaticamente.</p>
    `.trim(),
      },
      network: {
        question: 'O zisla acessa a Internet?',
        answer: 'Clima, verificações de atualização assinadas, downloads iniciados por você e limpeza de voz remota opcional usam a rede sob demanda. A detecção de links é local. O modelo local revisa o texto após a transcrição; o reconhecimento de voz da Apple ainda pode usar a rede, dependendo do idioma e do suporte do sistema.',
      },
      multiDisplay: {
        question: 'O zisla funciona com vários monitores?',
        answer: 'Sim: vários monitores, Spaces e apps em tela cheia; expandir nunca rouba o foco.',
      },
      intel: {
        question: 'Posso usar em um Mac Intel?',
        answer: 'Pode existir uma build para Intel, mas a compatibilidade não é garantida. A configuração compatível atual é Apple Silicon.',
      },
      storage: {
        question: 'Onde o zisla armazena os dados?',
        answer: 'Os dados locais ficam em ~/Library/Application Support/zisla/. Estatísticas de digitação ficam separadas em ~/Library/Application Support/zisla/typing-stats.sqlite3. Notas rápidas usa o app Notas.',
      },
    },
  },
  developers: {
    eyebrow: 'CÓDIGO ABERTO POR PADRÃO',
    title: 'Recursos para desenvolvedores.',
    lede: 'Licença PolyForm Noncommercial 1.0.0: apenas uso não comercial, como está ou compilado a partir do código-fonte.',
    docs: {
      macos: { title: 'Guia de desenvolvimento macOS', description: 'Recursos, build, testes e limites do sistema' },
      architecture: { title: 'Arquitetura e desempenho', description: 'Acionamento no topo, janelas e design de desempenho' },
      cli: { title: 'Integração CLI', description: 'Comandos e campos do zislactl' },
      releasing: { title: 'Assinatura e release', description: 'Assinatura, notarização e processo de release' },
      contributing: { title: 'Guia de contribuição', description: 'Ambiente, branches, commits e requisitos de pull request' },
    },
    quickStartMono: 'INÍCIO RÁPIDO / CÓDIGO-FONTE',
    quickStartHeading: 'Execute a partir do código ou conecte suas próprias tarefas.',
    copyRunCommandAriaLabel: 'Copiar o comando para executar a partir do código-fonte',
    githubRepoLabel: 'Repositório GitHub',
    giteeRepoLabel: 'Repositório Gitee',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Compatível com vários monitores, Spaces e apps normais em tela cheia; expandir nunca ativa o app nem rouba o foco',
      'Oculto, não cria janela transparente persistente nem executa loop de quadros; a expansão usa eventos globais e geometria',
      'Usa uma única camada de material do sistema e troca para fundo opaco quando Reduzir transparência está ativo',
      'Liquid Glass no macOS 26+, com fallback automático para materiais nativos no macOS 14 e 15',
      'O notch físico é inferido pela área segura; telas externas sem notch recebem uma barra simulada em uma sobreposição dedicada',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Voltar ao início do zisla',
    previewChannelLabel: 'Canal Preview',
    tagline: 'Código aberto, nativo e sob seu controle.',
  },
  common: {
    copyCommandTitle: 'Copiar comando',
    copiedAriaLabel: 'Copiado',
  },
  toast: {
    runCommandCopied: 'Comando de execução copiado',
    zislactlCopied: 'Comando zislactl copiado',
    brewCommandCopied: 'Comando de instalação do Homebrew copiado',
  },
});
