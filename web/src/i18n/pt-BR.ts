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
      help: "Ajuda",
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
          "Guarde arquivos na prateleira para pesquisar, selecionar e compartilhar. Crie ZIP ou PDF, redimensione ou converta imagens e envie mídia para notas ou estúdio.",
        points: ['Busca e ações em lote', 'Imagens para PDF e Notas rápidas', 'Editar vídeos no estúdio'],
      },
      clipboard: {
        name: 'Clipboard',
        caption:
          "Pesquise o histórico local e texto em imagens. Filtre por tipo ou aplicativo, salve favoritos e envie itens para Notas rápidas.",
        points: ['Histórico dentro da ilha', 'Filtro por tipo', 'Notas rápidas e favoritos'],
      },
      aiMonitor: {
        name: 'Monitor de IA',
        caption:
          'Reúne tarefas e estados de CLIs de IA, apps de desktop e IDEs. Dados numéricos confiáveis geram tendências de tokens e o mapa de contribuições; escolha uma data para ver tokens de entrada, saída e totais por provedor e modelo. Consulte o histórico nos Ajustes, exporte tudo em .xlsx ou apague. Mostra cotas reais, horários de redefinição e alertas de cota baixa, incluindo janelas 5h/7d e orçamentos do Cursor em dólares quando disponíveis. Não lê o texto dos prompts nem das respostas. Os layouts compactos também mostram a cota restante em anéis. Escolha as regiões das contas de forma independente; os registros diários e as cores da cota restante são consistentes em todos os layouts. As cotas Gemini e Claude/GPT do Antigravity têm monitoramento, exibição e alertas independentes. As cotas de conversa do Gemini App usam um Cookie da web da mesma conta Google; o Gemini CLI continua separado.',
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
          'Cole um link ou deixe o zisla identificá-lo no clipboard quando ativado. Escolha vídeo ou áudio e baixe para a pasta padrão ou outra de sua escolha. Links compatíveis exibem ícone de origem, progresso ao vivo e estado final. Escolha a pasta de downloads em Ajustes → Local de salvamento, separada de capturas e gravações. Links Bilibili baixam a parte selecionada. Gerencie os componentes em Ajustes → Componentes necessários e escolha atualizar diariamente os que já estão instalados.',
        points: ['Modos vídeo / áudio', 'Pasta padrão ou personalizada', 'Origem e progresso ao vivo'],
      },
      agenda: {
        name: 'Agenda e clima',
        caption:
          'Mostra o tempo da sua localização e de até seis lugares escolhidos. Consulte, adicione ou exclua eventos e lembretes e marque os lembretes como concluídos. Eventos com link de reunião exibem uma contagem regressiva 10 minutos antes do início e permitem entrar com um clique. Crie uma nota de reunião ou vincule e desvincule notas contextuais existentes. O horário de atualização da lista do tempo aparece no cabeçalho, à esquerda do botão de atualizar.',
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
          'Usa o app Notas do sistema para ver, editar, criar e excluir notas com prévia Markdown ao vivo, e ir direto às primeiras nove notas com Command+1 a 9. Os rascunhos são gravados de volta automaticamente. Veja anexos manuscritos e edite o texto antes ou depois deles preservando os originais. Navegue entre notas com Command e as setas. O texto colado segue a tipografia nativa do corpo do texto.',
        points: ['Dados nas Notas', 'Editor Markdown', 'Rascunhos salvos automaticamente'],
      },
      volumeMixer: {
        name: 'Mixer de volume por aplicativo',
        caption: 'Ajuste o volume e silencie separadamente os apps que reproduzem áudio. Requer macOS 14.4 ou posterior e permissão de gravação de áudio do sistema. O volume é lembrado por aplicativo, e fontes de áudio desatualizadas desaparecem quando a reprodução para.',
        points: ['Volume por app', 'Silenciar separadamente', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilitários',
        caption:
          'Temporizador de foco, manter a tela ligada, limpeza de tela e de teclado que também bloqueia F1-F12, teleprompter, espelho e Lixo na mesma página. Pause, continue ou reinicie o Pomodoro e acompanhe o progresso nas visualizações compactas horizontal e vertical. Inicie a limpeza de arquivos desnecessários nos utilitários com suas configurações de limpeza do sistema e acompanhe o progresso e os resultados na ilha. O nome do temporizador vale apenas para a sessão atual e volta ao padrão quando ela termina ou é cancelada.',
        points: ['Temporizador de foco', 'Bloqueia F1-F12 durante a limpeza', 'Teleprompter e espelho'],
      },
      system: {
        name: 'Estado do sistema',
        caption:
          'Monitora CPU, GPU, memória, disco, rede, ventoinhas e temperatura NVMe SMART disponível. Consulte o histórico por minuto em um período, exporte .xlsx ou apague nos Ajustes. Veja saúde, ciclos, temperatura e capacidade da bateria, carga de aparelhos próximos e IPv4/IPv6 públicos. Escolha modos automáticos de energia na tomada e na bateria, com modo de baixo consumo opcional em 20% ou menos. Carregue imediatamente até 100% quando o macOS permitir. Revise caches, registros, preferências residuais e espaços de IA órfãos antes de enviá-los ao Lixo; a limpeza opcional pode ocorrer a cada 7, 15 ou 30 dias. A limpeza agendada vem desativada; escolha apenas itens confiáveis ou todos os itens processáveis, inclusive os que precisam de revisão. Execute a limpeza em segundo plano e acompanhe o progresso e os resultados na ilha. Encontre instalações duplicadas e arquivos deixados por atualizações de aplicativos.',
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
        description: 'Use a posição da câmera ou escolha uma posição na borda da tela. A posição personalizada é lembrada ao trocar de modo. Layouts compactos horizontais e verticais ajustam o comprimento a ícones, tarefas de IA, downloads e mídia, com uma opção para exibir mais informações. Reordene os módulos arrastando em Ajustes → Layout da Dynamic Island ou restaure a ordem padrão. Na mesma página, você pode definir a prioridade das informações de status compactas.',
        detail: 'Posição personalizada · Ícones persistentes · Informações adaptáveis',
      },
      dailyBriefing: {
        title: 'Seu dia em um relatório diário',
        description: "Escolha entre oito modelos, selecione dados de uso, digitação, sistema e atividade zisla e confira a prévia. Exporte um PNG manualmente ou em um horário diário. O histórico de Tempo de Uso entra quando ativado e disponível. Escolha uma pasta de exportação independente em Ajustes → Local de salvamento. Também é possível incluir as cotas reais das contas e o horário da consulta.",
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
        description: "Grave tela, janela ou região, edite faixas, legendas e efeitos de retrato/voz e exporte. HDR em aparelhos compatíveis e importação da prateleira.",
        detail: 'Efeitos de retrato e voz · Rastros coloridos do cursor · Reprodução e exportação multifaixa',
      },
      permissions: {
        title: 'Permissões do sistema em um lugar',
        description: "Veja os estados em Ajustes → Permissões, inicie pedidos compatíveis ou abra a página correspondente do sistema. O estado das permissões é atualizado após a concessão do acesso. Uma ajuda para arrastar o aplicativo facilita as permissões que exigem adicioná-lo.",
        detail: "Estado das permissões · Pedidos e links",
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
        description: "Disponível nos Ajustes. Quatorze operações no próprio Mac: unir, dividir, girar, recortar, converter imagens e arquivos Office, renderizar imagens, extrair texto, adicionar marcas d’água e números de página, criptografar, remover senha e editar metadados.",
        detail: '14 ferramentas no dispositivo · Una na ordem que quiser · Nada sai do seu Mac',
      },

      windowPreviews: {
        title: 'Veja a janela e clique para alternar',
        description:
          'Veja janelas pelo Dock ou com Command-Tab e clique no cartão para ativar a janela. Novas configurações ativam esse recurso; gerencie-o e suas permissões nos Ajustes. Janelas fechadas ou duplicadas são filtradas; as prévias do Dock ficam ocultas enquanto um menu de contexto está aberto.',
        detail: 'Dock e Command-Tab · Trocar de janela com um clique · Configurável',
      },
      capture: {
        title: 'Capturas, rolagem e fixação',
        description:
          'Capture, fixe ou una capturas com rolagem usando atalhos personalizáveis. Destaque áreas, extraia partes da imagem, arredonde cantos e preserve anotações ao exportar. Reconheça e copie texto, traduza e copie o resultado ou exporte tabelas reconhecidas como .xlsx. Guarde capturas na prateleira. Os ajustes verificam conflitos com voz e Ações Rápidas. A caixa de diálogo abre na pasta de capturas definida em Ajustes → Local de salvamento. Capturas fixadas permanecem ao capturar novamente. Capturas longas podem usar rolagem automática lenta; dispositivos compatíveis podem capturar HDR. A seleção automática de janelas inclui a janela de ajustes do zisla. As imagens fixadas acompanham o tamanho da moldura ao usar o zoom da barra de ferramentas ou do trackpad, ou ao arrastar um canto.',
        detail: 'Destaque e extração · Reconhecimento, tradução e cópia · Cantos arredondados e .xlsx',
      },
      voice: {
        title: 'Entrada de voz e limpeza',
        description:
          'Alterne com uma tecla ou segure para falar usando o reconhecimento do sistema, com vocabulários especializados e palavras personalizadas. Se quiser, use Ollama, LM Studio ou um modelo remoto para corrigir a transcrição preservando o sentido e formatar itens enumerados explicitamente. Ajustes → Monitor e Limpeza do Sistema pode apagar áudio com mais de 7, 15 ou 30 dias e manter as transcrições; a limpeza automática vem desativada.',
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
          'Detecta downloads do Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc, mostrando origem e progresso ao vivo no topo. O progresso mostra o nome real do arquivo de destino quando o navegador o fornece.',
        detail: '8 navegadores · Detecção de origem · Aviso de conclusão',
      },
      copyAssistant: {
        title: 'Ações rápidas e próximos passos',
        description:
          'Quando ativado, mostra uma prévia de textos, links, arquivos ou imagens copiados em uma barra separada e sugere abrir, mostrar no Finder, buscar, traduzir, calcular ou salvar, somente após sua confirmação. Abra a pasta do arquivo pelas ações rápidas após um download do navegador ou uma transferência AirDrop. Aceita pastas padrão e escolhidas no Chrome, com ativação independente do progresso dos downloads. IPs têm ações separadas para consulta e abertura do link. A conversão reconhece subunidades monetárias e o catálogo inclui Emoji 18.0. Textos e imagens salvos usam a pasta independente de Ações rápidas em Ajustes → Local de salvamento. Se um app não abrir, as Ações rápidas verificam sua integridade, assinatura e a política de segurança do macOS. Após passar nas verificações, podem remover os atributos de quarentena e abrir o app. Reordene as ações de cada tipo reconhecido em Ajustes → Ações rápidas. Valores aceitam símbolos regionais e códigos de moeda com prefixo. A detecção de comandos aceita here-documents.',
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
        description: 'Escolha no catálogo ampliado de animais e personagens ou importe uma imagem, animação ou vídeo compatível com um nome próprio. Posicione o mascote em um lado da ilha e remova os importados nos Ajustes. Animações de até 30 segundos e arquivos de até 100 MB. Ao expandir a ilha em uma tela, os mascotes das outras telas permanecem no lugar.',
        detail: 'Catálogo ampliado · Importar imagens e vídeos · Remover mascotes personalizados',
      },
      lockScreen: {
        title: 'Informações da tela bloqueada',
        description:
          "Mostre opcionalmente data, estado e reprodução na tela bloqueada do macOS.",
        detail: "Ativação opcional · Não rouba o foco",
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
    eyebrow: "FLUXO DE IA",
    title: "Acompanhe tarefas de IA, <span>uso e cotas.</span>",
    lede:
      "Veja tarefas por aplicativo, uso de modelos por data e cotas restantes das suas contas.",
    summaryMono: "TAREFAS / USO / COTAS",
    summaryLede: "Tarefas de IA, uso e cotas em um só lugar.",
    toolsHeading: 'Ferramentas de IA compatíveis',
    toolsLede: "Detecta tarefas de CLIs, aplicativos de desktop e IDEs compatíveis.",
    toolsAriaLabel: 'Ferramentas de IA compatíveis',
    boundariesHeading: "Privacidade",
    privacyPoints: [
      "O estado das tarefas e o uso ficam no seu Mac",
      "Prompts e respostas não são lidos",
      "Conversas não são enviadas",
    ],
    bridgeHeading: 'Conecte suas próprias tarefas',
    bridgeLede: "Use zislactl para mostrar scripts e tarefas de compilação na barra de status.",
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
        desc: "Funciona em telas com notch e monitores externos.",
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
  help: {
    "title": "Comece a usar o zisla",
    "lede": "Escolha uma tarefa e siga o acesso, as etapas, as permissões e o destino.",
    "labels": {
      "entry": "Acesso",
      "shortcuts": "Atalhos",
      "permissions": "Permissões",
      "output": "Resultado e armazenamento"
    },
    "guides": {
      "clipboard": {
        "title": "Reutilize o que copiou",
        "summary": "Encontre um item ou escolha uma ação após copiar.",
        "entry": "Ilha → Área de transferência; Ajustes → Ações rápidas.",
        "steps": [
          "Ative o histórico ou as ações rápidas e copie um texto ou link de exemplo.",
          "Abra a área de transferência, filtre ou pesquise e copie um item.",
          "Copie uma imagem de exemplo com texto legível, aguarde o reconhecimento local em segundo plano e pesquise uma palavra da imagem para encontrar o original.",
          "Clique com o botão direito na imagem para reconhecer ou copiar seu texto; cancele durante o reconhecimento se necessário. O reconhecimento em segundo plano não copia o texto automaticamente.",
          "Cole no aplicativo de destino; para uma nova cópia, escolha a próxima ação na janela rápida."
        ],
        "shortcuts": "Command+1…9 e Command+0 seguem a ordem das ações. Novas configurações também usam Command+N para a primeira; Command+Delete fecha. Atalhos salvos ou apagados são mantidos.",
        "permissions": "Histórico e reconhecimento são locais. Modificadores/botões do mouse usam Monitoramento de Entrada; o gesto opcional de cópia usa Acessibilidade. Tradução usa o serviço escolhido.",
        "output": "Histórico nos dados locais. Salvar texto/imagem usa Ajustes → Local de salvamento → Ações rápidas; novo padrão: ~/Downloads/quick."
      },
      "capture": {
        "title": "Capture e edite a tela",
        "summary": "Edite uma captura ou gravação e exporte o resultado.",
        "entry": "Barra de menus → Captura/Gravação; Ajustes → Gravação → Estúdio.",
        "steps": [
          "Capture uma região ou janela e edite, copie, salve ou guarde na prateleira.",
          "Escolha tela, janela ou região e ative só as fontes de áudio/câmera necessárias.",
          "Pare, edite e visualize no estúdio, depois exporte o formato escolhido."
        ],
        "shortcuts": "Control+1 captura; Control+2 captura longa. Control+Shift+1/2/3 gravam tela/janela/região; Control+Shift+6 abre o estúdio. Ajustáveis nas configurações.",
        "permissions": "Gravação de Tela necessária. Microfone e câmera precisam de suas permissões, inclusive a prévia da câmera.",
        "output": "Novos padrões: ~/Downloads/picture para capturas e ~/Downloads/video para gravações/projetos. Pastas independentes. Alguns formatos precisam de FFmpeg."
      },
      "shelf": {
        "title": "Passe arquivos pela prateleira",
        "summary": "Deixe arquivos prontos sem copiar os originais.",
        "entry": "Ilha → Prateleira; arraste até o alvo superior.",
        "steps": [
          "Arraste um arquivo de exemplo para cima ou agite ao arrastar se o gesto estiver ativo.",
          "Abra a prateleira e escolha uma categoria ou os itens necessários.",
          "Arraste ao destino, mostre no Finder ou compartilhe; capturas guardadas podem ser salvas como PNG.",
          "Selecione arquivos ou pastas e escolha a compactação ZIP no menu de contexto; o arquivo volta à prateleira.",
          "Selecione imagens da prateleira e escolha redimensionar ou converter o formato; execute as ferramentas de imagem e os resultados concluídos voltam à prateleira.",
          "Selecione imagens, vídeo ou áudio e importe para a biblioteca do estúdio de gravação; o projeto e a linha do tempo atuais são mantidos."
        ],
        "shortcuts": "Arraste com o ponteiro. Agitar para soltar é configurável separadamente; não exige atalho fixo.",
        "permissions": "O seletor e os marcadores seguros permitem acesso aos arquivos escolhidos. Capturas exigem Gravação de Tela.",
        "output": "Os originais ficam no lugar. Referências e capturas persistem localmente; o PNG vai ao destino escolhido. Os ZIP e os resultados de imagem concluídos voltam à prateleira; a mídia importada entra na biblioteca do projeto de gravação."
      },
      "meeting": {
        "title": "Entre em uma reunião e guarde notas",
        "summary": "Vincule a reunião do calendário a uma nota de contexto.",
        "entry": "Ilha → Agenda; ative calendário e notas de contexto nos Ajustes.",
        "steps": [
          "Crie ou abra um evento com link de reunião compatível e horários válidos de início/fim.",
          "Clique em Entrar; a contagem aparece 10 minutos antes.",
          "Crie, salve ou vincule uma nota pelo evento e reabra na agenda ou prateleira."
        ],
        "shortcuts": "Entrar e notas são botões. Em outros locais, segure a tecla configurada e agite; o padrão é Command.",
        "permissions": "Acesso ao calendário necessário. Notas de janela podem precisar de Acessibilidade; capturas anexas exigem Gravação de Tela.",
        "output": "Notas de reunião ficam na prateleira local. Notas rápidas é um recurso separado que usa Notas da Apple."
      },
      "ai": {
        "title": "Conecte IA e consulte cotas",
        "summary": "Acompanhe tarefas, uso registrado e cotas da conta.",
        "entry": "Ajustes → IA; ilha → Monitor de IA.",
        "steps": [
          "Ative uma ferramenta local compatível ou informe a tarefa com zislactl conforme a referência CLI.",
          "Ative o monitoramento do provedor desejado e escolha separadamente o monitoramento e a exibição de Gemini e Claude/GPT no Antigravity. Para o Gemini App, entre com a mesma conta Google em gemini.google.com/usage e salve seu Cookie nas credenciais de cota da web; selecione o Gemini CLI separadamente.",
          "Confira coleta, redefinição e aviso de cota; veja o histórico ou exporte .xlsx."
        ],
        "shortcuts": "Use o monitor ou Ajustes; não há atalho global fixo. zislactl aceita os argumentos documentados.",
        "permissions": "A detecção local lê estado estruturado. Cotas consultam o provedor; edições IA opcionais usam o modelo ou CLI escolhido.",
        "output": "Tarefas/uso: ~/Library/Application Support/zisla/ai-state.sqlite. Cotas vêm do provedor, sem estimativas por token; dados ausentes continuam indisponíveis."
      },
      "media-tools": {
        "title": "Processe imagens, áudio e PDF",
        "summary": "Use as ferramentas locais independentes com exemplos.",
        "entry": "Ajustes → Ferramentas de imagem / Áudio / PDF.",
        "steps": [
          "Adicione uma imagem, escolha operação e opções, execute e exporte o resultado ou ZIP.",
          "Selecione imagens da prateleira e escolha redimensionar ou converter o formato; execute as ferramentas de imagem e os resultados concluídos voltam à prateleira.",
          "Instale FFmpeg e ffprobe nos componentes, adicione áudio, escolha corte ou mixagem e selecione arquivo ou pasta de saída.",
          "Adicione PDF na ordem necessária, execute e salve. Conversão de Office exige LibreOffice ou OpenOffice."
        ],
        "shortcuts": "Botões das ferramentas; sem atalho global fixo.",
        "permissions": "O seletor dá acesso aos arquivos e pastas escolhidos. Processamento local; instalar componentes faz downloads.",
        "output": "Novos padrões: imagens ~/Downloads/picture, PDF ~/Downloads/pdf, configuráveis separadamente. Áudio usa o diálogo de exportação."
      },
      "daily-briefing": {
        "title": "Crie um resumo diário",
        "summary": "Confira estatísticas antes de exportar PNG.",
        "entry": "Ajustes → Resumo diário.",
        "steps": [
          "Escolha modelo e estatísticas.",
          "Abra a prévia, confira dados disponíveis e escolha a pasta.",
          "Exporte hoje ou ative a exportação diária com horário."
        ],
        "shortcuts": "Botões de prévia e exportação; sem atalho fixo.",
        "permissions": "Ative os recursos de estatística correspondentes. Tempo de Uso pode precisar de Acesso Total ao Disco; cotas consultam o provedor.",
        "output": "PNG na pasta do resumo; novo padrão ~/Downloads/daily. Dados ausentes não viram zero medido."
      },
      "desktop": {
        "title": "Pré-visualize janelas e anote seu contexto",
        "summary": "Mude de janela e deixe uma nota para esse local.",
        "entry": "Ajustes → Prévia de janelas / Notas de contexto; Dock, Command+Tab e prateleira.",
        "steps": [
          "Ative prévias e permissões, passe sobre o app do Dock ou use Command+Tab e clique no cartão.",
          "Em uma página, janela ou mesa de exemplo, segure a tecla configurada e agite; escreva e salve a nota.",
          "Retorne ao local ou abra pela prateleira; adicione lembrete recorrente ou captura de janela se quiser."
        ],
        "shortcuts": "Command+Tab muda apps. Notas usam Command segurado por padrão, alterável nos Ajustes.",
        "permissions": "Prévias precisam de Acessibilidade e Gravação de Tela. Detectar janela usa Acessibilidade; capturas anexas Gravação de Tela.",
        "output": "Notas e capturas nos dados locais da prateleira em ~/Library/Application Support/zisla."
      },
      "playback": {
        "title": "Escolha reprodução e misture volumes",
        "summary": "Selecione saída e ajuste apps reproduzindo áudio.",
        "entry": "Área de mídia → Saída; Ajustes → Fonte de mídia; ilha → Mixer.",
        "steps": [
          "Reproduza áudio de exemplo e escolha uma saída disponível.",
          "Escolha fonte automática ou player preferido e teste os controles.",
          "No macOS 14.4+, abra o mixer, permita Gravação de Áudio do Sistema e ajuste ou silencie uma app."
        ],
        "shortcuts": "Botões e controles deslizantes; sem atalho fixo.",
        "permissions": "Mixer exige macOS 14.4+ e Gravação de Áudio do Sistema. Dispositivos dependem das conexões; Bluetooth pode precisar de permissão.",
        "output": "A saída é a escolha do sistema. Volumes por app são lembrados localmente; nenhum arquivo é exportado."
      }
    },
    "workflowsTitle": "Demonstrações curtas",
    "workflows": {
      "copy-next": {
        "title": "Encontre, copie e reutilize",
        "steps": [
          "Pesquise a palavra de exemplo “brew” no histórico.",
          "Copie o item correspondente.",
          "Cole no app de destino. O trecho mostra busca e cópia; uma nova cópia tem ações rápidas separadas."
        ]
      },
      "drop-output": {
        "title": "Solte um arquivo e prepare a saída",
        "steps": [
          "Arraste uma imagem de exemplo do Finder até a prateleira superior.",
          "Abra a prateleira e selecione a imagem.",
          "Arraste ao destino ou salve uma captura como PNG. O trecho mostra a entrada na prateleira."
        ]
      },
      "meeting-note": {
        "title": "Da reunião à nota",
        "steps": [
          "Abra a reunião com seu link de entrada.",
          "Escolha Nova nota ou Vincular nota existente.",
          "Salve e reabra pelo evento ou prateleira. O trecho mostra criação e vínculo."
        ]
      }
    },
    "excerptLabel": "Reproduzir trecho",
    "guideLinkLabel": "Ler guia",
    "videoNotice": "Trechos da apresentação existente com dados de demonstração. As legendas do vídeo estão em inglês; as etapas usam seu idioma. O vídeo completo de 2:40 e os créditos musicais estão abaixo.",
    "preferencesTitle": "Preferências úteis",
    "preferences": [
      "Ative agitar ao arrastar para revelar a prateleira. Notas de contexto usam sua própria tecla mantida.",
      "Escolha a saída de áudio na área de mídia e fonte automática ou player preferido nos Ajustes. Isso não atribui um dispositivo diferente a cada app.",
      "Sons e estatísticas do teclado são independentes e usam Monitoramento de Entrada. O mixer exige macOS 14.4+ e Gravação de Áudio do Sistema.",
      "O resumo diário oferece 8 modelos, prévia e exportação PNG manual ou diária, com pasta própria."
    ]
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
      'v0.1.25': [
        'Inicie a limpeza de arquivos desnecessários nos utilitários com suas configurações atuais. O progresso e os resultados aparecem na ilha; as mensagens de resultado da IA continuam legíveis antes de voltar à limpeza.',
        'O conteúdo das capturas fixadas acompanha o tamanho da moldura ao usar a barra de ferramentas, o trackpad ou os cantos, inclusive em imagens HDR.',
        'A lista de previsão do tempo mostra um único horário de atualização e reúne as fontes sem entradas repetidas.',
        'As estatísticas de digitação recuperam a barra de rolagem vertical e o painel permanece dentro da área visível.',
        'As ferramentas de áudio se ajustam à área visível das configurações, com rolagem separada para a lista de operações e o painel de edição.',
        'O mixer de volume dos aplicativos oculta fontes de áudio inativas, mantém os controles de volume e silêncio salvos e permite tentar novamente quando a detecção de áudio falha.',
      ],
      'v0.1.24': [
        'O histórico da área de transferência permite pesquisar e agrupar pelo aplicativo de origem. As ações rápidas reconhecem comandos que contêm here-documents.',
        'A limpeza do sistema pode ser executada em segundo plano, com progresso e resultados na ilha. A limpeza do disco identifica instalações duplicadas e arquivos deixados por atualizações de aplicativos.',
        'Todas as pastas de saída podem ser restauradas ao padrão em uma ação. Os grupos e a ordem das páginas de ajustes foram reorganizados.',
        'Dispositivos compatíveis podem gravar em HDR. O reconhecimento de texto, a tradução e as prévias HDR de capturas foram restaurados; a seleção de janelas inclui os ajustes do zisla.',
        'As notas rápidas permitem navegar com Command e as setas. O texto colado mantém a tipografia nativa do corpo do texto.',
        'Os ajustes de cota de IA permitem regiões independentes. O histórico diário e as cores da cota restante são consistentes entre cartões expandidos e avisos compactos. Cancelar um turno do Kimi limpa os erros; uma atualização de assinatura cancelada não lê credenciais.',
        'As prévias filtram janelas fechadas e duplicadas, respeitam sua identidade durante métodos alternativos e ficam ocultas enquanto os menus de contexto do Dock estão abertos.',
        'O monitoramento de mídia atualiza fontes desatualizadas e encerra a atividade de áudio quando as amostras param. O volume por aplicativo é mantido, e os fades seguem o tempo das amostras decodificadas. Sons e estatísticas do teclado tratam a ausência de reprodução e dados vazios.',
        'As permissões são atualizadas após a concessão do acesso, com uma ajuda para arrastar o aplicativo na configuração. Falhas de ferramentas recomendadas continuam legíveis.',
      ],
      'v0.1.23': [
        'As ferramentas de imagem ganham nove operações locais: compressão, conversão entre cinco formatos, tamanho e recorte, comparação do menor formato, rotação e espelhamento, marcas d’água, mosaico e desfoque, reconhecimento de texto e tabelas e remoção de fundo. Há exportação em lote e ZIP, com pastas separadas para ferramentas PDF e de imagem.',
        'As ferramentas de áudio ganham 27 operações locais de conversão, edição, divisão, união, mixagem, extração, normalização LUFS, efeitos, canais e etiquetas. Exigem FFmpeg e ffprobe; escolha um arquivo ou pasta de exportação.',
        'O monitoramento de contas de IA mostra anéis de cota restante, horários de renovação e avisos de cota baixa nos layouts da ilha, incluindo janelas 5h/7d e orçamentos Cursor em USD quando disponíveis. Os resumos diários podem incluir as cotas reais e os horários da consulta.',
        'Escolha uma data nos gráficos de uso de IA ou no mapa de calor para ver tokens de entrada, saída e totais por provedor e modelo. Consulte, exporte todo o histórico como .xlsx ou limpe-o nos Ajustes. A tela inicial agrupa tarefas de IA por app e mostra os resultados da exportação de resumos na ilha.',
        'Eventos com link de reunião mostram contagem regressiva a partir de 10 minutos antes e permitem entrar com um clique. Crie notas de reunião ou vincule e desvincule notas contextuais. O Mail permite marcar toda a caixa de entrada como lida.',
        'A bandeja ganha busca, filtros e seleção múltipla para copiar, compartilhar ou enviar às notas rápidas. Converta imagens em PDF, reconheça texto para notas e abra os vídeos selecionados no estúdio de gravação.',
        'Escolha modos automáticos de energia para tomada e bateria, com a opção de manter baixo consumo em 20% ou menos. Carregue até 100% imediatamente quando o macOS oferecer a ação. Os Ajustes dão acesso ao histórico do sistema, à exportação .xlsx e à limpeza.',
        'Os layouts Pomodoro compactos horizontais e verticais ganham progresso, pausa, retomada e reinício. Passar o ponteiro sobre os controles mantém a ilha recolhida, inclusive no layout vertical com mais informações.',
        'Capturas longas ganham rolagem automática lenta da janela escolhida. Captura HDR está disponível em aparelhos compatíveis; a edição mantém os ajustes de renderização e exportação da imagem.',
        'As ações rápidas podem reparar um app que não abre após verificar integridade, assinatura e política de segurança do macOS. Reordene ações por tipo, veja mais exemplos e use símbolos regionais ou códigos de moeda com prefixo. Consultas de voos, trens e encomendas têm prioridade.',
        'Os Ajustes separam layout da Dynamic Island, resumo diário, notificações e cuidados e fluxo de trabalho em páginas próprias. Reordene prioridades compactas e, se desejar, atualize componentes instalados diariamente. A limpeza de gravações fica em Monitor e Limpeza do Sistema e mantém as transcrições.',
        'Downloads do navegador usam nomes reais de destino quando disponíveis. Renderização ociosa, varreduras de IA, carregamento de histórico e reprodução no estúdio consomem menos recursos. Logos compactos de IA, cartões de cota e animações foram ajustados; rolagem do clima, arrastos para a bandeja, escritas de Mail e preservação do histórico da área de transferência foram corrigidos.',
        'A página inicial ganha um tour de 160 segundos iniciado por clique e um link para o vídeo original. O site continua utilizável sem WebGL e os apps recomendados incluem o espaço de trabalho de terminal Zshell.',
      ],
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
        answer: 'Clima, verificações de atualização assinadas, downloads iniciados por você e limpeza de voz remota opcional usam a rede sob demanda. A detecção de links é local. O modelo local revisa o texto após a transcrição; o reconhecimento de voz da Apple ainda pode usar a rede, dependendo do idioma e do suporte do sistema. O monitoramento de cotas de IA ativado também consulta os serviços dos provedores selecionados.',
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
        answer: 'Os dados locais ficam em ~/Library/Application Support/zisla/. As estatísticas de digitação ficam separadas em ~/Library/Application Support/zisla/typing-stats.sqlite3. As notas rápidas usam o app Notas do sistema. Ajustes → Local de salvamento oferece pastas independentes para downloads, ferramentas PDF e de imagem, capturas, gravações, ações rápidas e resumos diários. A atualização preserva os locais já escolhidos; depois, cada pasta pode ser alterada separadamente. Restaure todas as pastas de salvamento padrão em uma única ação.',
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
      "Usa um fundo opaco quando Reduzir Transparência está ativado",
      'Liquid Glass no macOS 26+, com fallback automático para materiais nativos no macOS 14 e 15',
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
