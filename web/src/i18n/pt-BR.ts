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
          'Cartões dinâmicos aparecem apenas durante uma sessão de foco, tarefa de IA ou download; quando nada acontece, não ocupam espaço. A página inicial agrupa as tarefas de IA em andamento por aplicativo.',
        points: ['Aparece sob demanda', 'Progresso em tempo real', 'Layout adaptável'],
      },
      shelf: {
        name: 'Prateleira',
        caption:
          'Arraste arquivos, áudios, vídeos ou links para o topo da tela. Pesquise, filtre e selecione vários itens para copiar, compartilhar ou enviar às Notas rápidas. Converta imagens em PDF, envie o texto reconhecido às Notas rápidas ou abra vídeos no estúdio de gravação para editar. Você também pode localizar os arquivos no Finder.',
        points: ['Busca e ações em lote', 'Imagens para PDF e Notas rápidas', 'Editar vídeos no estúdio'],
      },
      clipboard: {
        name: 'Clipboard',
        caption:
          'Consulte o histórico do clipboard dentro da ilha e filtre por imagem, URL, caminho ou tipo de arquivo e veja quando cada item foi copiado. Envie um item para Notas rápidas, fixe-o como favorito ou exclua-o. Você pode excluir automaticamente o histórico com mais de 7, 15 ou 30 dias e manter os favoritos. A exclusão automática vem desativada.',
        points: ['Histórico dentro da ilha', 'Filtro por tipo', 'Notas rápidas e favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Reúne tarefas e estados de CLIs de IA, apps de desktop e IDEs. Dados numéricos confiáveis geram tendências de tokens e o mapa de contribuições; escolha uma data para ver tokens de entrada, saída e totais por provedor e modelo. Consulte o histórico nos Ajustes, exporte tudo em .xlsx ou apague. Mostra cotas reais, horários de redefinição e alertas de cota baixa, incluindo janelas 5h/7d e orçamentos do Cursor em dólares quando disponíveis. Não lê o texto dos prompts nem das respostas.',
        points: ['Tarefas de várias ferramentas de IA', 'Histórico por modelo e exportação .xlsx', 'Cotas e horários de redefinição'],
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
          'Cole um link ou deixe o zisla identificá-lo no clipboard quando ativado. Escolha vídeo ou áudio e baixe para a pasta padrão ou outra de sua escolha. Links compatíveis exibem ícone de origem, progresso ao vivo e estado final. Escolha a pasta de downloads em Ajustes → Local de salvamento, separada de capturas e gravações. Links Bilibili baixam a parte selecionada.',
        points: ['Modos vídeo / áudio', 'Pasta padrão ou personalizada', 'Origem e progresso ao vivo'],
      },
      agenda: {
        name: 'Agenda e clima',
        caption:
          'Mostra o tempo da sua localização e de até seis lugares escolhidos. Consulte, adicione ou exclua eventos e lembretes e marque os lembretes como concluídos. Eventos com link de reunião exibem uma contagem regressiva 10 minutos antes do início e permitem entrar com um clique. Crie uma nota de reunião ou vincule e desvincule notas contextuais existentes.',
        points: ['Tempo e calendário', 'Contagem regressiva de 10 minutos', 'Entrar e vincular notas'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Lê as contas ativadas no Mail. Veja a caixa de entrada, marque uma mensagem ou todas as mensagens recebidas como lidas, responda, escreva e mova mensagens para o Lixo dentro da ilha. Escolha anexos ao escrever; permissões ausentes têm orientação clara.',
        points: ['Contas do Mail', 'Responder e redigir na ilha', 'Permissões transparentes'],
      },
      quickNotes: {
        name: 'Notas rápidas',
        caption:
          'Usa o app Notas do sistema para ver, editar, criar e excluir notas com prévia Markdown ao vivo, e ir direto às primeiras nove notas com Command+1 a 9. Os rascunhos são gravados de volta automaticamente. Veja anexos manuscritos e edite o texto antes ou depois deles preservando os originais.',
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
          'Temporizador de foco, manter a tela ligada, limpeza de tela e de teclado que também bloqueia F1-F12, teleprompter, espelho e Lixo na mesma página. Pause, continue ou reinicie o Pomodoro e acompanhe o progresso nas visualizações compactas horizontal e vertical.',
        points: ['Temporizador de foco', 'Bloqueia F1-F12 durante a limpeza', 'Teleprompter e espelho'],
      },
      system: {
        name: 'Estado do sistema',
        caption:
          'Monitora CPU, GPU, memória, disco, rede, ventoinhas e temperatura NVMe SMART disponível. Consulte o histórico por minuto em um período, exporte .xlsx ou apague nos Ajustes. Veja saúde, ciclos, temperatura e capacidade da bateria, carga de aparelhos próximos e IPv4/IPv6 públicos. Escolha modos automáticos de energia na tomada e na bateria, com modo de baixo consumo opcional em 20% ou menos. Carregue imediatamente até 100% quando o macOS permitir. Revise caches, registros, preferências residuais e espaços de IA órfãos antes de enviá-los ao Lixo; a limpeza opcional pode ocorrer a cada 7, 15 ou 30 dias. A limpeza agendada vem desativada; escolha apenas itens confiáveis ou todos os itens processáveis, inclusive os que precisam de revisão.',
        points: ['Monitoramento no nível do chip', 'Gráficos de histórico e exportação .xlsx', 'Revise antes de mover para o Lixo'],
      },
    },
  },
  extensions: {
    eyebrow: 'DENTRO E FORA DA ILHA',
    title: 'Longe da ilha, <span>ainda uma ferramenta de desktop.</span>',
    lede:
      'Capturas, ferramentas de imagem e áudio, ditado, mídia, downloads do navegador e gerenciamento de IA aparecem onde são fáceis de acessar.',
    ariaLabel: 'Recursos de desktop independentes',
    summaryMono: 'ALÉM DA ILHA',
    summaryLede: 'Recursos frequentes, cada um em seu lugar natural.',
    summaryNote:
      'Prévias de janelas, capturas e ações rápidas ficam à mão; os apps recomendados ajudam você a descobrir mais ferramentas para o desktop.',
    features: {
      floatingIsland: {
        title: 'Uma ilha flutuante que se adapta',
        description: 'Use a posição da câmera ou escolha uma posição na borda da tela. A posição personalizada é lembrada ao trocar de modo. Layouts compactos horizontais e verticais ajustam o comprimento a ícones, tarefas de IA, downloads e mídia, com uma opção para exibir mais informações. Reordene os módulos arrastando em Ajustes → Informações ou restaure a ordem padrão.',
        detail: 'Posição personalizada · Ícones persistentes · Informações adaptáveis',
      },
      dailyBriefing: {
        title: 'Seu dia em um relatório diário',
        description: 'Escolha entre oito modelos, selecione dados de uso, digitação, sistema e atividade zisla e confira a prévia. Exporte um PNG manualmente ou em um horário diário. O histórico de Tempo de Uso entra quando ativado e disponível; dados ausentes não são apresentados como zero medido. Escolha uma pasta de exportação independente em Ajustes → Local de salvamento. Também é possível incluir as cotas reais das contas e o horário da consulta.',
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
        description: 'Grave tela, janela ou região com áudio do sistema, microfone e câmera opcionais. Edite vídeo, áudio, imagens e texto em várias faixas com animações, zooms e legendas. Ajuste suavização da pele, brilho, afinamento de rosto e corpo, efeitos de voz e rastros suaves do cursor na cor escolhida. Reproduza a edição no estúdio. Escolha proporção original, 16:9, 9:16, 1:1 ou 4:3; exporte vídeo, GIF, Live Photo ou áudio. Alguns formatos exigem FFmpeg. Revise propostas opcionais de IA antes de aplicar. A pasta de gravação é definida separadamente em Ajustes → Local de salvamento.',
        detail: 'Efeitos de retrato e voz · Rastros coloridos do cursor · Reprodução e exportação multifaixa',
      },
      permissions: {
        title: 'Permissões do sistema em um lugar',
        description: 'Veja os estados em Ajustes → Permissões, inicie pedidos compatíveis ou abra a página correspondente do sistema. As boas-vindas iniciais usam a mesma lista e identificam permissões com configuração manual.',
        detail: 'Estado das permissões · Pedidos e links · Compartilhado com as boas-vindas',
      },
      imageTools: {
        title: 'Ferramentas de imagem',
        description: 'Nove ferramentas locais nos Ajustes: comprimir; converter PNG, JPEG, WebP, AVIF e JPEG XL; redimensionar e recortar; comparar o menor formato; girar e espelhar; marcas d’água; mosaico e desfoque; reconhecer texto e tabelas; remover fundos. Exporte em lote ou em ZIP, com pasta própria em Ajustes → Local de salvamento.',
        detail: '9 ferramentas locais · Cinco formatos · Exportação em lote e ZIP',
      },
      audioTools: {
        title: 'Ferramentas de áudio',
        description: 'Vinte e sete operações locais nos Ajustes, como converter, comprimir, recortar, dividir, unir e mixar, extrair áudio de vídeo, normalizar LUFS, fades, velocidade e tom, redução de ruído e remoção de silêncio, EQ, dinâmica, canais e tags. Requer FFmpeg e ffprobe; escolha um arquivo ou pasta ao exportar.',
        detail: '27 operações locais · Edição e mixagem · FFmpeg e ffprobe',
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
          'Capture, fixe ou una capturas com rolagem usando atalhos personalizáveis. Destaque áreas, extraia partes da imagem, arredonde cantos e preserve anotações ao exportar. Reconheça e copie texto, traduza e copie o resultado ou exporte tabelas reconhecidas como .xlsx. Guarde capturas na prateleira. Os ajustes verificam conflitos com voz e Ações Rápidas. A caixa de diálogo abre na pasta de capturas definida em Ajustes → Local de salvamento. Capturas fixadas permanecem ao capturar novamente. Capturas longas podem usar rolagem automática lenta; dispositivos compatíveis podem capturar HDR.',
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
          'Quando ativado, mostra uma prévia de textos, links, arquivos ou imagens copiados em uma barra separada e sugere abrir, mostrar no Finder, buscar, traduzir, calcular ou salvar, somente após sua confirmação. Abra a pasta do arquivo pelas ações rápidas após um download do navegador ou uma transferência AirDrop. Aceita pastas padrão e escolhidas no Chrome, com ativação independente do progresso dos downloads. IPs têm ações separadas para consulta e abertura do link. A conversão reconhece subunidades monetárias e o catálogo inclui Emoji 18.0. Textos e imagens salvos usam a pasta independente de Ações rápidas em Ajustes → Local de salvamento. Se um app não abrir, as Ações rápidas verificam sua integridade, assinatura e a política de segurança do macOS. Após passar nas verificações, podem remover os atributos de quarentena e abrir o app.',
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
          'Conheça OpenScreen para gravação e edição de vídeo, DockDoor para prévias de janelas e alternância de apps, e Zshell como espaço de trabalho de terminal nativo do macOS. São apps de terceiros instalados separadamente.',
        detail: 'Descubra ferramentas para o desktop · Apps de terceiros · Instalação separada',
      },
    },
  },
  ai: {
    eyebrow: 'IA SEM CAIXA-PRETA',
    title: 'Veja o estado da IA <span>sem ler a conversa.</span>',
    lede:
      'Acompanhe tarefas por aplicativo, uso de modelos por data e cotas reais das contas. Os estados e dados numéricos ficam no Mac; o texto das conversas não é lido.',
    summaryMono: 'ESTADO LOCAL / LIMITES CLAROS',
    summaryLede: 'Conecte as ferramentas de IA que você já usa, mantendo os limites de contexto necessários.',
    summaryNote: 'A página explica apenas escopo de detecção, dados e conexão; não simula uma sessão ao vivo.',
    toolsHeading: 'Ferramentas de IA compatíveis',
    toolsLede: 'Detecta atividade de CLIs, apps e IDEs compatíveis e agrega o estado das tarefas.',
    toolsAriaLabel: 'Ferramentas de IA compatíveis',
    usageNote: 'Detecção de sessões, histórico de tokens e cotas usam fontes diferentes. Delta utiliza seu registro numérico local; Orca elimina duplicatas do uso do CLI vinculado e o atribui ao provedor original. WorkBuddy AI pode detectar sessões e consultar créditos; ocupação de contexto e créditos não são convertidos em tokens nem custos em dólares. A disponibilidade das cotas depende do provedor e da forma de login.',
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
      'v0.1.22': [
        'O estúdio adiciona suavização da pele, brilho, afinamento de rosto e corpo, predefinições de voz ajustáveis e monitoração opcional do microfone. Os efeitos podem ser ajustados antes de gravar e durante a edição.',
        'Rastros suaves do cursor permitem escolher a cor. A reprodução no estúdio mostra o resultado editado com faixas, efeitos e áudio.',
        'Ajustes → Local de salvamento separa downloads, capturas, gravações, Ações rápidas e relatórios diários. Os locais antigos são mantidos na atualização e cada pasta pode ser alterada de forma independente.',
        'A limpeza opcional move itens ao Lixo a cada 7, 15 ou 30 dias. Escolha itens confiáveis ou todos os processáveis, incluindo os que exigem revisão; vem desativada. A limpeza de disco também permite revisar pastas de IA sem sessões mantidas, protegendo sessões conservadas e pastas novas.',
        'O histórico do clipboard pode excluir entradas com mais de 7, 15 ou 30 dias automaticamente e manter favoritos. A exclusão automática vem desativada.',
        'Notas rápidas mostra anexos manuscritos e permite editar o texto antes ou depois pelo app Notas, preservando os anexos originais.',
        'O monitor de IA oculta cotas restantes, mantém o uso diário e melhora a rolagem de gráficos e os rótulos de meses. Os ajustes de bateria ficam em Estado do sistema.',
        'Quiet.md entra nas recomendações para notas locais, com instalação e gerenciamento em Ajustes.',
        'Bilibili baixa a parte selecionada do vídeo e aceita mais formatos de links. A exclusão no calendário afeta a ocorrência recorrente selecionada. Capturas fixadas permanecem entre novas capturas, com rótulos mais claros e indicadores de tamanho mais confiáveis.',
      ],
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
        answer: 'Os dados locais ficam em ~/Library/Application Support/zisla/. Estatísticas de digitação ficam separadas em ~/Library/Application Support/zisla/typing-stats.sqlite3. Notas rápidas usa o app Notas. Ajustes → Local de salvamento oferece pastas independentes para downloads, capturas, gravações, Ações rápidas e relatórios diários. A atualização mantém a pasta compartilhada anterior; depois cada uma pode ser alterada separadamente.',
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
  film: {
    title: "Vídeo de apresentação",
    videoAriaLabel: "Vídeo de apresentação do zisla",
    openVideoLabel: "Abrir vídeo",
    playbackError: "Não foi possível reproduzir o vídeo.",
    musicLabel: "Música",
    excerptLabel: "Trecho",
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
