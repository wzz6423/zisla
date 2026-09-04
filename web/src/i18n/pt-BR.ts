import { createCatalog } from './createCatalog';

export const ptBR = createCatalog({
  meta: {
    documentTitle: 'zisla · Espaço de trabalho dinâmico',
    description:
      'O zisla é um espaço de trabalho dinâmico nativo para macOS. Reúne tarefas de IA, mídia, arquivos e agenda, além de sons do teclado, estatísticas de digitação, anotações de capturas e um assistente de cópia.',
    ogTitle: 'zisla · Coloque o que está acontecendo onde você pode ver',
    ogDescription:
      'De tarefas de IA e mídia a sons do teclado, estatísticas de digitação, assistente de cópia, anotações de capturas e ferramentas de desktop: um espaço nativo do macOS que aparece quando você precisa.',
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
      faq: 'Perguntas frequentes',
      developers: 'Desenvolvedores',
    },
    downloadCta: 'Baixar',
    downloadCtaAriaLabel: 'Ir para a seção de download',
    languageLabel: 'Idioma da interface',
  },
  hero: {
    eyebrow: 'ESPAÇO DE TRABALHO NATIVO PARA MACOS',
    title: 'zisla<br><em>O que está acontecendo,<br>bem onde<br class="hero-mobile-break"> você pode ver.</em>',
    lede:
      'Reúna tarefas de IA, mídia, arquivos e agenda no topo da tela. Depois de copiar algo, uma barra de assistência separada mostra uma prévia e sugere o próximo passo. Ela aparece quando necessário e sai do caminho quando você termina.',
    downloadCta: 'Baixar',
    downloadCtaAriaLabel: 'Baixar',
    sourceCta: 'Ver código',
    sourceCtaAriaLabel: 'Ver o código-fonte do zisla no GitHub',
    hints: [
      'Mova o cursor para o topo da tela para expandir, sem clicar',
      'Depois de copiar, pressione Command+N para o próximo passo inteligente',
      'Recolhe sozinha sem interromper seu trabalho',
    ],
    identityCaption: 'Topo da tela',
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
      '{modules} módulos no topo e {features} recursos independentes para capturas, voz, mídia, downloads, assistente de cópia, gestão de IA, mascote e tela bloqueada.',
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
          'Consulte o histórico do clipboard dentro da ilha e filtre por imagem, URL, caminho ou tipo de arquivo. Envie um item para Notas rápidas, fixe-o como favorito ou exclua-o.',
        points: ['Histórico dentro da ilha', 'Filtro por tipo', 'Notas rápidas e favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Detecta atividade de CLIs, apps de desktop e IDEs compatíveis, incluindo threads do Zed Agent, e mostra tarefas, estado, tendências acumuladas de tokens e um mapa de contribuições. Analisa apenas eventos estruturados e nunca lê conversas.',
        points: ['Tarefas agregadas entre ferramentas', 'Tendências de consumo de tokens', 'Nunca lê prompts ou respostas'],
      },
      keyboardSound: {
        name: 'Sons do teclado',
        caption:
          'Reproduz 20 sons mecânicos integrados para teclas globais, com volume ajustável e variação natural de tom, além de sons de soltura quando disponíveis. Ative as estatísticas locais para ver resumo, tendências, histórico, linha do tempo de apps e mapa por tecla F1-F12.',
        points: ['20 sons integrados', 'Som de soltura e variação de tom', 'Estatísticas opcionais'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Cole um link ou deixe o zisla identificá-lo no clipboard quando ativado. Escolha vídeo ou áudio e baixe para a pasta padrão ou outra de sua escolha. Links compatíveis exibem ícone de origem, progresso ao vivo e estado final.',
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
          'Lê as contas ativadas no Mail, mostra a caixa de entrada e permite marcar, responder, redigir e mover mensagens para o Lixo dentro da ilha, com orientação clara quando falta uma permissão.',
        points: ['Contas do Mail', 'Responder e redigir na ilha', 'Permissões transparentes'],
      },
      quickNotes: {
        name: 'Notas rápidas',
        caption:
          'Usa o app Notas do sistema para ver, editar, criar e excluir notas com prévia Markdown ao vivo. Os rascunhos são gravados de volta automaticamente.',
        points: ['Dados nas Notas', 'Editor Markdown', 'Rascunhos salvos automaticamente'],
      },
      pdf: {
        name: 'Ferramentas de PDF',
        caption:
          'Quatorze operações no próprio Mac: unir, dividir, girar, recortar, converter imagens e arquivos Office, renderizar imagens, extrair texto, adicionar marcas d’água e números de página, criptografar, remover senha e editar metadados.',
        points: ['14 ferramentas no dispositivo', 'Una na ordem que quiser', 'Nada sai do seu Mac'],
      },
      toolbox: {
        name: 'Utilitários',
        caption:
          'Temporizador de foco, manter a tela ativa, limpeza de tela e teclado (bloqueia inclusive F1-F12), alarmes, teleprompter, espelho e Lixo em uma única página.',
        points: ['Temporizador de foco', 'Bloqueia F1-F12 durante a limpeza', 'Teleprompter e espelho'],
      },
      system: {
        name: 'Estado do sistema',
        caption:
          'Veja CPU, GPU, memória, disco, rede e ventoinhas; leia a temperatura SMART de NVMe quando o hardware informar e limpe caches e registros seguros para excluir.',
        points: ['Monitoramento no nível do chip', 'Temperatura NVMe quando compatível', 'Limpe caches com um toque'],
      },
      battery: {
        name: 'Bateria',
        caption:
          'Veja carga, saúde, ciclos, temperatura e capacidade deste Mac, além do nível de bateria de dispositivos próximos exposto pelo sistema.',
        points: ['Indicadores de saúde do Mac', 'Tempo restante', 'Bateria de dispositivos próximos'],
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
      'Capturas, gravação, mídia, downloads do navegador, assistente de cópia, gestão de IA, mascote e tela bloqueada são apresentados separadamente.',
    features: {
      capture: {
        title: 'Capturas, rolagem e fixação',
        description:
          'Capture ou fixe uma área da tela com um atalho global, anote, una uma captura com rolagem e reconheça ou exporte tabelas. Anotações ainda em edição são preservadas na exportação.',
        detail: 'Atalho global · Anotar e desfazer · Edições mantidas na exportação',
      },
      voice: {
        title: 'Entrada de voz e limpeza',
        description:
          'Alterne com uma tecla ou segure para falar usando o reconhecedor do sistema. Adicione vocabulários, palavras personalizadas, formatação estruturada ou limpeza por modelo local ou remoto.',
        detail: 'Dois modos de gravação · Vocabulários e palavras-chave · Limpeza opcional',
      },
      media: {
        title: 'Mídia e sons ambientes do sistema',
        description:
          'Controle o que está tocando no topo da ilha ou escolha um som ambiente do macOS. Ele pode parar ao bloquear a tela, iniciar o protetor ou suspender o monitor.',
        detail: 'Controle de reprodução · Letras sincronizadas · Parada automática',
      },
      browserDownloads: {
        title: 'Progresso de downloads do navegador',
        description:
          'Detecta downloads do Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc, mostrando origem e progresso ao vivo no topo.',
        detail: '8 navegadores · Detecção de origem · Aviso de conclusão',
      },
      copyAssistant: {
        title: 'Assistente de cópia e próximos passos',
        description:
          'Quando ativado, mostra uma prévia de textos, links, arquivos ou imagens copiados em uma barra separada e sugere abrir, mostrar no Finder, buscar, traduzir, calcular ou salvar, somente após sua confirmação.',
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
        description: 'Escolha um mascote integrado e coloque-o à esquerda ou à direita da ilha. Desative quando quiser.',
        detail: 'Personagens integrados · Esquerda ou direita · Ative quando quiser',
      },
      lockScreen: {
        title: 'Informações da tela bloqueada',
        description:
          'Mostre opcionalmente data, estado e reprodução na tela bloqueada do macOS. É uma sobreposição independente e nunca aparece na lista ou no carrossel de módulos da ilha.',
        detail: 'Sobreposição independente · Ativação opcional · Não rouba o foco',
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
    doubaoName: 'Doubao',
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
      'Para Macs com Apple Silicon. Versões, outras arquiteturas e checksums estão na página de releases. Após instalar, o Sparkle verifica a assinatura primeiro e depois baixa, instala e reinicia manual ou automaticamente conforme seus ajustes.',
    primaryCta: 'Baixar',
    primaryCtaAriaLabel: 'Baixar o zisla',
    releaseCta: 'Ver release',
    releaseCtaAriaLabel: 'Ver os detalhes da release no GitHub',
    notes: {
      system: { term: 'Sistema', value: 'macOS 14 ou posterior · Configuração compatível atual: Mac com Apple Silicon' },
      install: { term: 'Instalação', value: 'Monte o DMG e arraste para Aplicativos' },
      package: { term: 'Pacote', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Outras arquiteturas', value: 'Página de releases' },
      mirror: { term: 'Espelho', value: 'Gitee Releases' },
    },
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
        question: 'O assistente de cópia abre ou envia o que copio?',
        answer: 'Não. O reconhecimento e a prévia acontecem no Mac, e o próximo passo só é executado após sua confirmação.',
      },
      permissions: {
        question: 'Quais permissões do sistema o zisla precisa?',
        answer: `
      <p>O zisla não solicita todas as permissões no primeiro uso. O macOS mostra cada solicitação somente quando você ativa e usa de fato o recurso correspondente:</p>
      <ul>
        <li><strong>Calendários e Lembretes:</strong> solicitados separadamente ao abrir o módulo de agenda, para ler, criar e gerenciar eventos do calendário e lembretes com data.</li>
        <li><strong>Serviços de Localização:</strong> solicitados quando você escolhe o clima da sua localização atual. O zisla obtém uma única localização e não acompanha você continuamente. Adicionar uma cidade manualmente não exige permissão de localização.</li>
        <li><strong>Microfone e Reconhecimento de Fala:</strong> solicitados quando você inicia a entrada de voz. O áudio é capturado somente enquanto você grava ativamente, e apenas essa gravação é transcrita.</li>
        <li><strong>Acessibilidade:</strong> necessária para inserir uma transcrição automaticamente no app atual, copiar rapidamente com um gesto do mouse, limpar o teclado e controlar alguns players compatíveis. Ela é usada para localizar campos de entrada que não sejam de senha ou enviar as teclas de sistema necessárias.</li>
        <li><strong>Monitoramento de Entrada:</strong> usado para sons do teclado, estatísticas locais opcionais de digitação e acionadores globais, como uma tecla modificadora isolada ou um botão lateral do mouse. Ele observa apenas os eventos globais necessários para esses recursos; atalhos globais comuns não precisam dessa permissão.</li>
        <li><strong>Gravação de Tela e Gravação de Áudio do Sistema:</strong> necessárias para capturas de tela, edição de capturas e a forma de onda do áudio reproduzido pelo sistema. As capturas leem a imagem da tela; a forma de onda apenas analisa os níveis atuais do áudio do sistema e nunca armazena nem envia áudio.</li>
        <li><strong>Câmera:</strong> usada somente enquanto a janela do espelho estiver aberta.</li>
        <li><strong>Bluetooth:</strong> usado somente enquanto o módulo de bateria estiver aberto, para ler o nível de bateria publicado por dispositivos conectados ou emparelhados.</li>
        <li><strong>Automação:</strong> na primeira vez que você usa Notas rápidas, Mail, a organização da mesa ou o controle direto de um player compatível, o macOS pergunta separadamente se o zisla pode controlar Notas, Mail, Finder ou o app correspondente. Notas rápidas lê e grava no Notas; o Mail pode ler, redigir, responder, sinalizar e apagar mensagens.</li>
        <li><strong>Acesso Total ao Disco:</strong> necessário somente quando o Mail não está em execução e o zisla ainda precisa ler o índice local de e-mails para mostrar contas, remetentes, assuntos, prévias, horários e status de leitura.</li>
        <li><strong>Notificações:</strong> solicitadas quando você ativa o timer Pomodoro ou alarmes, exclusivamente para mostrar uma notificação local quando o timer termina ou um alarme dispara.</li>
      </ul>
      <p><strong>Pastas não são Acesso Total ao Disco:</strong> para as pastas de transferência, importação/exportação ou download escolhidas no seletor de arquivos do sistema, o zisla recebe acesso apenas àquela pasta, nunca acesso de leitura ao disco inteiro.</p>
      <p><strong>Sons do teclado e estatísticas de digitação:</strong> ambos ficam desativados por padrão, e os eventos globais do teclado só são observados quando um deles está ativado. Com os sons do teclado, os eventos das teclas servem apenas para reproduzir um som; com as estatísticas de digitação, somente dados agregados — contagem de caracteres, códigos físicos das teclas, horários e o app em primeiro plano — são armazenados, nunca o que você digitou. Você pode desativar cada opção separadamente nos Ajustes; depois disso, nada mais é registrado. Os dados já armazenados permanecem em um arquivo de banco de dados local que você pode excluir.</p>
      <p>Você pode desativar um recurso nos ajustes do app ou revogar uma permissão a qualquer momento em Ajustes do Sistema → Privacidade e Segurança. Revogar uma permissão desativa apenas o recurso relacionado e não afeta os outros módulos. Os nomes dos itens podem variar um pouco conforme a versão do macOS.</p>
    `.trim(),
      },
      network: {
        question: 'O zisla acessa a Internet?',
        answer: 'Clima, verificações de atualização assinadas, downloads iniciados por você e limpeza de voz remota opcional usam a rede sob demanda. A detecção de links é local.',
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
        answer: 'Os dados locais ficam em ~/Library/Application Support/zisla/. Estatísticas de digitação ficam separadas em ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Notas rápidas usa o app Notas.',
      },
    },
  },
  developers: {
    eyebrow: 'CÓDIGO ABERTO POR PADRÃO',
    title: 'Recursos para desenvolvedores.',
    lede: 'Licença MIT: use como está ou compile a partir do código-fonte.',
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
  },
});
