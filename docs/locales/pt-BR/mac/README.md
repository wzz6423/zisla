# zisla para macOS

**Português (Brasil)** | [Idiomas da documentação](../../README.md)

Este diretório contém a implementação do zisla para macOS. Mova o ponteiro para o centro superior da tela para expandir a ilha; afaste-o para ocultá-la. A aplicação usa AppKit `NSPanel`, SwiftUI e serviços orientados a eventos, sem manter uma janela transparente permanente na área de ativação nem um ciclo de quadros enquanto está oculta.

Os targets Swift, o identificador do pacote, o diretório de dados locais e `zislactl` usam o identificador zisla. As atualizações migram automaticamente os dados locais e as preferências das versões anteriores.

O macOS 14 e versões posteriores são compatíveis. O macOS 26 usa Liquid Glass; o macOS 14/15 usa o material nativo do sistema como alternativa.

## Recursos

### 12 módulos da ilha

| Módulo | Recursos implementados |
| --- | --- |
| Início | Resume sob demanda o temporizador Pomodoro atual, a primeira tarefa de IA ativa, os downloads nativos e o progresso de vários downloads de navegadores. |
| Sons e estatísticas do teclado | Oferece 20 sons de teclado integrados e controles independentes para estatísticas locais de digitação, tendências, linha do tempo por aplicação e mapa de calor por tecla. |
| Transferência | Arraste arquivos, mídia ou links para a área de ativação superior para mantê-los na bandeja de transferência, mostrá-los no Finder ou abrir o menu de compartilhamento do sistema. As capturas guardadas têm cartões azuis com largura dupla e uma categoria própria, com cópia de imagem, exportação PNG e exclusão. Comprima os arquivos e pastas selecionados em ZIP, redimensione ou converta as imagens selecionadas nas Ferramentas de imagem e devolva os resultados bem-sucedidos à bandeja, ou importe as imagens, os vídeos e os áudios selecionados para a biblioteca de mídia do estúdio preservando o projeto e a linha do tempo atuais. |
| Área de transferência | Guarda um histórico local pesquisável, filtra por imagem, URL e arquivo e permite marcar favoritos; o histórico e a detecção de links têm controles independentes. As novas imagens do histórico entram na fila de reconhecimento de texto no dispositivo; pesquise seu texto para encontrar a imagem original ou clique com o botão direito em uma imagem para reconhecer ou copiar seu texto. O reconhecimento em andamento pode ser cancelado; o reconhecimento em segundo plano não copia o texto automaticamente. |
| Monitoramento de IA | Agrega tarefas ativas, estados, tendências de tokens, mapas de calor de contribuições e avisos laterais de CLIs, aplicações de desktop e IDEs compatíveis. |
| Downloads | Usa `yt-dlp` para vídeo e áudio; sem `ffmpeg`, AVFoundation encapsula as faixas compatíveis e oferece uma alternativa de somente leitura para Bilibili. |
| Agenda | Mostra o clima da localização atual e de até seis locais salvos; permite visualizar, criar e excluir eventos de calendário e lembretes e marcar lembretes como concluídos. O horário de atualização da lista do tempo aparece no cabeçalho, à esquerda do botão de atualizar. Quando faltam dados meteorológicos, outras fontes complementam o resultado mais completo; os dados disponíveis são mantidos se o restante não puder ser obtido. |
| E-mail | Lê as contas selecionadas do Mail.app para visualizar caixas de entrada, marcar mensagens como lidas, responder, redigir e mover mensagens para a lixeira. |
| Notas | Usa Notas da Apple como única fonte de dados para visualizar, editar, criar e excluir notas Markdown, com prévia ao vivo e gravação automática das alterações. |
| Mixer de volume de aplicações | No macOS 14.4+, permite ajustar o volume e silenciar cada aplicação em reprodução, lembrando seu volume; exige a permissão de Gravação de Áudio do Sistema. |
| Utilitários | Oferece um temporizador Pomodoro que toca um alerta sonoro e mostra uma notificação local ao terminar uma sessão, modo de manter acordado, prevenção de repouso por inatividade, limpeza da tela e do teclado, teleprompter, espelho da câmera e esvaziamento da lixeira após confirmação. O nome do temporizador vale apenas para a sessão atual e volta ao padrão quando ela termina ou é cancelada. Na ilha recolhida, o sol indica que a tela continua ligada e o notebook indica que o repouso por inatividade está bloqueado. |
| Sistema | Mostra o estado de CPU, GPU, memória, disco, rede, temperatura e ventoinhas; libera memória e analisa caches, logs e dados temporários que podem ser removidos com segurança; inclui a saúde da bateria e os níveis de carga dos acessórios. |

### Recursos entre módulos

- **Reprodução atual:** MediaRemote mostra a capa, o título, o progresso, as letras com rolagem e os controles; Core Audio identifica a fonte real de áudio como alternativa. As fontes pausadas, paradas ou silenciadas ficam ocultas.
- **Downloads do navegador:** Mostra a origem e o progresso dos downloads de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc na tela inicial, no estado recolhido e nos avisos laterais. A presença de um arquivo `.crdownload` na pasta temporária do sistema, por si só, não exibe um cartão de download.
- **Entrada de voz:** Oferece atalhos de alternância ou de pressionar para falar, atalhos globais personalizados, reconhecimento de fala do sistema, organização local ou remota das transcrições e histórico local das gravações.
- **Ações rápidas:** Após cada cópia, um pequeno aviso no estilo da ilha mostra uma prévia rica e ações inteligentes: abrir links, mostrar arquivos no Finder, pesquisar com um mecanismo selecionável, traduzir, calcular, criar eventos a partir de datas reconhecidas e salvar textos longos ou imagens. Após um download do navegador ou a chegada de um arquivo AirDrop, o mesmo atalho pode abrir a pasta que contém o arquivo; isso é controlado por Ações rápidas, independentemente do progresso de downloads. Reconhece URLs, caminhos de arquivos, e-mails, números de telefone, cores CSS com amostras ao vivo, operações aritméticas, datas e horários, texto em idioma diferente do sistema, trechos de código, texto simples com contagens, imagens com miniaturas e referências a arquivos. Os gatilhos são os botões de ação, o atalho adicional padrão Command+N ou uma tecla modificadora/botão lateral do mouse configurado. Também oferece um gesto de cópia rápida mantendo o botão esquerdo pressionado e clicando com o direito, desligado por padrão, uma lista de aplicações bloqueadas, controles de reconhecimento por tipo e um modo leve de lembrete.
- **Gerenciamento de CLI e Skills:** Detecta, instala, atualiza e remove CLIs comuns de IA e gerencia Skills locais em Ajustes.
- **Mascotes de desktop:** Em Ajustes → Pet, veja uma prévia dos mascotes integrados e importados. “Mascote fixo” mantém o mesmo mascote. A rotação aleatória inclui todos por padrão. Escolha quem participa em “Mascotes para o sorteio”. O sorteio ocorre à meia-noite no horário local. Em “Intervalo de troca”, escolha “Personalizado” para definir uma duração de 1 segundo a 99:59:59. O valor inicial é de 1 hora. Coloque o mascote de qualquer lado da ilha. Ao expandir a ilha em uma tela, os mascotes das outras telas permanecem no lugar.
- **Atualizações:** O canal Release ou Preview selecionado resolve o código de país da saída pública de rede uma vez por execução da aplicação. `CN` consulta primeiro o appcast assinado do Gitee e tenta GitHub uma vez; outros códigos consultam GitHub primeiro e tentam Gitee uma vez. Uma consulta indisponível preserva a prioridade de Gitee. Depois, Sparkle baixa, verifica, instala e reinicia as atualizações. Alterar o canal afeta as verificações automáticas e manuais.
- **Aparência e interação:** Ajustes pode seguir o sistema ou usar aparência clara ou escura. A ilha oferece superfícies transparentes ou foscas, expansão fixada, várias telas, Spaces e telas externas sem recorte. Com o navegador em tela cheia, passe o cursor sobre a ilha para expandi-la no mesmo espaço.
- **Padrões:** As instalações novas habilitam os módulos de recursos por padrão. Cada recurso, indicador do estado recolhido, aviso lateral, métrica da barra de menus e comportamento de atualização pode ser ajustado independentemente; instalações existentes mantêm sua configuração.
- Com várias telas conectadas, Ajustes → Geral → Modos de tela permite escolher para cada tela o modo Dynamic Island (posição da câmera ou personalizada), o modo notch ou ocultar. Com uma tela, esse ajuste fica oculto e vale a aparência global; ao reconectar, as configurações salvas de cada tela são restauradas. Todas as telas visíveis mantêm a ilha recolhida ao mesmo tempo. Expandir a ilha, usar ações rápidas, gravar e exibir mensagens temporárias substitui apenas a ilha da própria tela; selecionar telas para notificações filtra o conteúdo sem ocultar a ilha inativa.

### Ferramentas independentes e fluxos

- **Estúdio de gravação:** Abra-o pela barra de menus ou por Ajustes. Grave uma tela, janela ou região com áudio do sistema, microfone e câmera opcionais. Edite vídeo, áudio, imagens e texto em várias faixas, incluindo legendas, zooms, animações e efeitos de retrato e voz; visualize antes de exportar vídeo, GIF, Live Photo ou áudio. Alguns formatos exigem FFmpeg; a gravação HDR depende do suporte do dispositivo. Importe imagens, vídeo e áudio da prateleira para a biblioteca de mídia preservando o projeto e a linha do tempo atuais.
- **Ferramentas de imagem, áudio e PDF:** Abra as ferramentas independentes em Ajustes. As imagens têm 9 operações locais e exportação em lote/ZIP. O áudio tem 27 operações, incluindo mixagem, normalização LUFS e tratamento de ruído, e exige FFmpeg e ffprobe. O PDF tem 14 operações; a conversão de Office exige LibreOffice ou OpenOffice.
- **Resumo diário:** Escolha entre 8 modelos e selecione as métricas em Ajustes, visualize a prévia e exporte PNG manualmente ou em um horário diário. As métricas indisponíveis não são apresentadas como um zero medido.
- **Prévias de janelas:** Passe o ponteiro sobre o Dock ou alterne com Command+Tab e clique em uma prévia para ativar sua janela. Gerencie o recurso e as permissões em Ajustes.
- **Notas contextuais e reuniões:** Mantenha pressionado o atalho de nota configurado e agite o ponteiro para anexar uma nota a uma página, janela ou à área de trabalho. Eventos de calendário com links de reunião mostram uma contagem regressiva 10 minutos antes do início; entre na reunião, crie uma nota ou vincule uma nota existente. Gerencie as notas contextuais na prateleira.
- **Agitar para soltar:** Agite o ponteiro enquanto arrasta arquivos para mostrar o destino de soltura; ajuste esse gesto independentemente em Ajustes.
- **Saída de áudio e preferências do player:** Escolha um dispositivo de saída na área de mídia. Ajustes permite selecionar uma fonte automática ou um player preferido, o layout compacto de mídia e as condições de parada dos sons ambientes.
- **Cotas e redefinições de IA:** Monitoramento de IA e Ajustes mostram as cotas de contas compatíveis, os horários de amostragem e redefinição e os avisos de cota baixa, incluindo janelas 5h/7d disponíveis e orçamentos Cursor em USD. Essas informações são separadas do histórico de tokens registrado localmente. As cotas Gemini e Claude/GPT do Antigravity têm monitoramento, exibição e alertas independentes. As cotas de conversa do Gemini App usam um Cookie da web da mesma conta Google; o Gemini CLI continua separado.

### Ordem de teclado de ações rápidas

O aviso de Ações rápidas atribui `Command+1` até `Command+9`, depois `Command+0`, na ordem atual das ações. O gatilho adicional padrão para novas configurações é `Command+N`, que executa a primeira ação; `Command+Delete` fecha o aviso. Configure o gatilho, o botão lateral do mouse e a ordem das ações em Ajustes. As atualizações mantêm todas as combinações explicitamente salvas, incluindo o antigo `Command+1`, atalhos personalizados e gatilhos apagados; somente configurações novas ou um campo de gatilho ausente adotam `Command+N`.

### Locais de salvamento

Ajustes → Local de salvamento seleciona pastas separadas para downloads, capturas de tela, ferramentas de imagem, gravações, PDF, Ações rápidas e resumos diários. As configurações novas usam por padrão subpastas de `~/Downloads`: `picture` para capturas/imagens, `video` para gravações, `pdf`, `quick` e `daily`. As ferramentas de áudio usam uma janela de exportação para escolher um arquivo ou uma pasta. Os arquivos da prateleira mantêm referências aos originais; as capturas guardadas e o estado das notas contextuais são gerenciados localmente em `~/Library/Application Support/zisla`, enquanto os projetos usam a pasta de gravação. O texto das Notas rápidas fica em Notas da Apple.

[Ajuda ao usuário e guias passo a passo](https://wzz6423.github.io/zisla/help.html?lang=pt-BR#help) cobrem nove tópicos: área de transferência, captura, prateleira, reuniões, IA, ferramentas de mídia, resumos diários, notas da área de trabalho/prévias de janelas e reprodução/mixagem, com pequenos trechos do filme.

### Atalhos e armazenamento de capturas

A ação **Guardar na bandeja** da barra de captura fica entre **Fixar** e **Copiar**. Ela guarda a imagem final editada, incluindo anotações e capturas roláveis concluídas, na bandeja de transferência sem copiá-la para a área de transferência. O PNG e os metadados de captura, incluindo a aplicação de origem e o horário, ficam armazenados localmente em SQLite e sobrevivem a reinícios. A categoria **Capturas guardadas** mostra somente esses cartões.

**Marca-texto** fica depois de **Pincel** e desenha um destaque translúcido; as linhas nas extremidades e os marcadores circulares são mantidos por padrão e podem ser desativados em seu menu. **Extrair** fica depois de **Desfocar** e permite extrair o assunto ou o fundo pelo macOS, além de selecionar livremente áreas arbitrárias. Vários contornos mantêm a união das áreas, com controles de Selecionar tudo e Limpar; pixels não selecionados ficam transparentes e a extração pode ser desfeita. O raio padrão dos cantos é 0. Arraste a alça de raio acima da seleção ou use o controle **Raio dos cantos**; o indicador de tamanho mostra `r`. Exportações PNG têm cantos transparentes, e voltar ao raio 0 restaura os pixels originais dos cantos.

| Contexto | Ação | Atalho padrão |
| --- | --- | --- |
| Global | Captura de tela | `Control+1` |
| Global | Captura rolável | `Control+2` |
| Editor de captura | Fixar | `Control+1` |
| Editor de captura | Guardar na bandeja | `Control+2` |
| Editor de captura | Retângulo | `Control+3` |
| Editor de captura | Elipse | `Control+4` |
| Editor de captura | Pincel | `Control+5` |
| Editor de captura | Marca-texto | `Control+6` |
| Editor de captura | Seta | `Control+7` |
| Editor de captura | Número | `Control+8` |
| Editor de captura | Texto | `Control+9` |
| Editor de captura | Desfocar | `Control+0` |
| Editor de captura | Extração | `Control+A` |
| Editor de captura | Captura rolável | `Control+B` |
| Editor de captura | Copiar | `Enter` |
| Editor de captura | Salvar | `Command+S` |
| Editor de captura | Desfazer | `Command+Z` |
| Editor de captura | Refazer | `Command+Shift+Z` |

Os ajustes de captura mostram e registram os atalhos globais e do editor. Copiar, Salvar, Desfazer e Refazer são exibidos, mas não podem ser regravados. Os atalhos registrados pelo usuário são mantidos nas atualizações; Fixar é uma ação do editor, não um atalho global separado, e seu item de menu continua disponível.

Os atalhos padrão do editor seguem a ordem da barra: `Control+1` até `Control+9`, depois `Control+0`, `Control+A`, `Control+B` e as letras seguintes. A atribuição padrão ignora `Q`, `M`, `N` e `W`: pressionar Command por engano poderia encerrar a aplicação, minimizar uma janela, abrir outra ou fechar uma janela. Combinações registradas pelo usuário continuam permitidas.

Na atualização, os layouts antigos não modificados, incluindo o antigo layout Fixar/Guardar, passam uma vez aos padrões acima. Se algum atalho de captura foi personalizado, o layout existente é mantido; novas ações escolhem uma combinação Control livre na mesma ordem segura quando seu padrão entra em conflito. Essas combinações iniciais também podem ser regravadas.

## Início rápido

### Ambiente

- macOS 14+
- Swift 6 / Xcode 16+ (só Command Line Tools também compila)
- Opcional: `yt-dlp` e `ffmpeg`; Office para PDF também exige LibreOffice ou OpenOffice

Com Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Executar pelo código-fonte

```bash
swift run zisla
```

A aplicação inicia como um acessório da barra de menus. Mova o ponteiro para a área de 6 px no centro superior da tela atual para expandi-la, ou escolha “Mostrar ilha” no ícone da barra de menus.

Para testar um intervalo de 5 segundos na compilação de depuração, execute `ZISLA_DEBUG_PET_ROTATION_SECONDS=5 make run` na raiz do repositório, ative “Rotação aleatória” e selecione pelo menos dois mascotes. Execute `make update` sem a variável para restaurar o intervalo salvo.

### Compilar uma `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Para incluir auxiliar oficial `yt-dlp`:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` baixa um arquivo oficial autônomo macOS de versão fixada e verifica-o com o arquivo oficial `SHA2-256SUMS` antes de instalá-lo em `Tools/yt-dlp`.

## Integração de IA

### Detecção automática

zisla lê o estado público ou local estável de sessões das ferramentas compatíveis e extrai somente os eventos estruturados e metadados locais necessários para determinar o estado das tarefas. Não lê prompts nem o conteúdo das respostas.

| Ambiente | Detecção automática |
| --- | --- |
| OpenAI / Anthropic | Codex CLI e Desktop, Claude Code e ambientes anfitriões |
| GitHub / Google / xAI | GitHub Copilot CLI e VS Code, Gemini CLI e Desktop e Grok CLI |
| Independentes e regionais | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop e CLI, TRAE, OpenCode, Harnext/Harness e WorkBuddy |

A espera por aprovação ou resposta do usuário aparece em amarelo, erros de ferramentas ou comandos em vermelho e execução normal em verde; fontes simultâneas são agrupadas nessa ordem: vermelho, amarelo, verde. O sidecar de execução Qwen é considerado ativo apenas enquanto seu PID está vivo, evitando informações antigas após sua saída.

Se uma aplicação de chat para desktop não persiste eventos estruturados de atividade, o sistema não consegue distinguir de forma confiável uma aplicação aberta e ociosa de um modelo gerando conteúdo. Essas ferramentas, incluindo ChatGPT, devem usar o hook `zislactl` abaixo; zisla não simula atividade com um processo residente.

### Protocolo local `zislactl`

`zislactl` grava o estado das tarefas e o histórico de uso em SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

O histórico de uso sobrevive aos reinícios da aplicação, às atualizações por substituição e à limpeza de tarefas. Só é perdido quando o usuário exclui os dados da aplicação manualmente.

Exemplo:

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

Os fornecedores canônicos incluem `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness` e `doubao`; aliases comuns são normalizados automaticamente. Chame-o a partir de qualquer hook de ferramenta, wrapper de shell ou script de tarefa.

A lista de execuções de IA e o estado recolhido usam o logotipo oficial de cada ferramenta para identificar sua fonte.

Veja protocolo na [referência CLI](Docs/cli-reference.md).

## Progresso de downloads do navegador

zisla escuta as informações públicas de progresso de arquivos do macOS no diretório Downloads e combina extensões de arquivos temporários, atributos estendidos da origem do download e informações dos navegadores em execução para identificar a fonte. Não lê bancos de histórico de navegador nem faz requisições de rede para identificar o progresso; o indicador de conclusão fica visível por cerca de três segundos. Ações rápidas usa a mesma fonte de eventos e oferece Abrir pasta depois que uma transferência bem-sucedida chega à localização final. A duração do aviso segue o ajuste de Ações rápidas, e o aviso de cópia ou transferência mais recente substitui o anterior.

## Downloader

Executáveis são procurados nesta ordem:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

A URL é passada para `Process` como um valor argv separado, em vez de passar por um shell. A configuração de execução e os plugins são ignorados, `--exec` é desativado, os limites de um único item são aplicados e o arquivo final é verificado para garantir que permaneça no diretório autorizado.

Sem `ffmpeg`:

- O vídeo prefere faixas de vídeo AVC/MP4 e áudio M4A, depois as encapsula em MP4 com AVFoundation; formatos de arquivo único são mantidos como estão.
- O áudio prefere M4A e, caso contrário, mantém o formato de áudio original.
- Se yt-dlp recebe HTTP 412, não encontra um formato ou está indisponível localmente, Bilibili usa sua API de somente leitura para obter faixas DASH e segue o mesmo caminho de encapsulamento nativo sem instalar outra ferramenta.

## Notas

As notas Markdown na ilha usam Notas da Apple como única fonte de dados. Você pode criar, visualizar, editar e excluir notas existentes, em vez de apenas adicionar novas notas.

- **Lista:** Ao entrar, JXA (`osascript -l JavaScript`) lê títulos e datas de modificação das notas não excluídas e ordena pela modificação mais recente. Voltar de Notas atualiza a lista; notas em Apagadas recentemente ficam ocultas. Selecione uma nota para editá-la, atualize a lista, crie uma nota ou exclua-a pelo menu de contexto.
- **Ver e editar:** AppleScript lê o `plaintext` da nota selecionada, que é a fonte Markdown, para o editor. O `TextEditor` nativo grava as mudanças após cerca de 0,8 segundo de inatividade para evitar uma chamada AppleScript a cada tecla. Novas notas são criadas em Notas da Apple e selecionadas.
- **Prévia:** O analisador de blocos integrado renderiza títulos, listas não ordenadas/ordenadas/de tarefas, citações, blocos de código delimitados, separadores, negrito, itálico, código em linha, tachado e links como `AttributedString`.
- **Armazenamento:** A fonte Markdown é armazenada como texto comum no `body` da nota, com escape HTML e linhas em branco preservadas. Ler `plaintext` restaura a fonte; Notas da Apple exibe texto simples em vez de renderizar Markdown.
- **Permissões:** A primeira leitura ou escrita solicita a autorização de automação macOS para Notas da Apple; uma recusa retorna um aviso de falha na lista ou no editor.

O módulo Notas não mantém uma segunda cópia local; Notas da Apple é o armazenamento de dados.

## Permissões e privacidade

- **Calendário:** As permissões de Calendário e Lembretes são solicitadas separadamente na primeira entrada; eventos e lembretes são atualizados após criação, exclusão ou conclusão.
- **Localização:** O clima solicita a localização atual uma única vez e não faz rastreamento contínuo; outros locais podem ser pesquisados, salvos e removidos em Ajustes.
- **Arquivos e downloads:** Diretórios selecionados pelo usuário usam marcadores de escopo de segurança; a transferência de arquivos não copia o original.
- **Área de transferência:** Instalações novas habilitam o histórico e a detecção de links por padrão, com controles independentes. Em cada `changeCount`, no máximo um link é reconhecido localmente; parâmetros de consulta não são registrados e nenhuma API de limpar, declarar tipo ou escrever é chamada, portanto a área de transferência universal não é substituída.
- **Ações rápidas:** Quando habilitadas, executam localmente em cada `changeCount` e também tratam downloads do navegador concluídos e arquivos AirDrop recebidos. O gatilho rápido pode usar Monitoramento de Entrada para teclas modificadoras isoladas e botões laterais do mouse; o gesto de cópia rápida opcional também envia um ⌘C sintético e exige Acessibilidade. O reconhecimento nunca se conecta à rede; abrir links, pesquisar, traduzir e salvar só ocorre após um clique ou acionamento explícito. A lista de aplicações bloqueadas e os controles por tipo regulam os avisos de cópia; o controle de Ações rápidas também regula os avisos de transferências concluídas.
- **Estado de IA:** A detecção automática lê apenas os eventos estruturados e metadados locais de atividade necessários para determinar o estado das tarefas.
- **Voz:** Microfone e reconhecimento de fala só são acessados após uma ação explícita do usuário. Gravações, transcrições brutas e texto organizado são gerenciados localmente; o texto organizado é enviado somente ao modelo local, fornecedor remoto ou perfil CLI selecionado, e credenciais remotas são mantidas em um banco privado.
- **Bluetooth e dispositivos:** Os níveis de bateria de acessórios e dispositivos móveis Apple confiáveis são lidos apenas quando a vista Bateria em Sistema está aberta.
- **Câmera e Monitoramento de Entrada:** O espelho e a prévia/gravação de câmera do estúdio solicitam acesso à câmera. Sons do teclado, estatísticas de digitação, limpeza do teclado e gatilhos de modificadores isolados/botões laterais usam Monitoramento de Entrada; as estatísticas ficam locais e os controles são independentes.
- **Tela e áudio do sistema:** Capturas, gravações e prévias de janelas leem o conteúdo da tela com a permissão de Gravação de Tela. A gravação salva as fontes selecionadas localmente; o acesso opcional a microfone/câmera é solicitado somente para fontes habilitadas. O mixer exige macOS 14.4+ e Gravação de Áudio do Sistema e usa taps locais de Core Audio.
- **Downloads do navegador:** Somente o progresso público de arquivos do sistema e arquivos temporários de download são inspecionados; o histórico do navegador e o conteúdo das páginas não são lidos.
- **Mídia:** MediaRemote fornece metadados e o estado de saída dos processos Core Audio confirma a reprodução. MediaRemote é um framework privado, portanto a compilação atual não é adequada para envio direto ao Mac App Store; se faltarem metadados, usa-se a aplicação de áudio ativa.
- **Rede:** As previsões consultam China Weather, Open-Meteo e MET Norway conforme a região, recorrendo a outras fontes quando faltam dados. Os alertas oficiais são obtidos separadamente de China Weather ou WeatherKit. O canal de atualização resolve o código de país da saída pública uma vez por execução via `ipinfo.io/country`: `CN` usa Gitee e depois GitHub, outros códigos usam GitHub e depois Gitee, e uma consulta indisponível mantém Gitee primeiro. A alternativa Bilibili usa informações de vídeo de somente leitura, URLs de reprodução e seu CDN de mídia; reconhecer links da área de transferência não usa rede. As verificações habilitadas de cotas contatam os fornecedores selecionados; tradução, edições de gravação por IA e limpeza de transcrições opcionais contatam o modelo ou CLI selecionado. O reconhecimento de fala pode usar serviços Apple conforme o suporte do sistema/idioma. Instalar ou atualizar dependências e CLIs, consultar IP público e executar ações de rede explicitamente escolhidas pelo usuário também gera requisições.
- **Automação:** Notas usa AppleScript/JXA para listar, visualizar, editar, criar e excluir notas de Notas da Apple. Exige autorização de automação, não usa a rede e mantém os dados em Notas da Apple.

## Testes

Com Xcode completo:

```bash
swift test
```

Somente Command Line Tools:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Documentação

- [Projeto de arquitetura e desempenho](Docs/architecture.md)
- [Referência de integração CLI](Docs/cli-reference.md)
- [Projeto de assinatura e publicação](Docs/releasing.md)
- [Dependências incluídas no repositório (inglês)](../../../../mac/Vendor/README.md)
- [Avisos de terceiros (inglês)](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Limitações do sistema

- macOS não oferece uma API pública de Dynamic Island; o recorte físico é inferido de `safeAreaInsets` e da área auxiliar superior, enquanto telas sem recorte usam a mesma simulação de sobreposição personalizada.
- Vídeos DRM, janelas de login, tela bloqueada e algumas aplicações exclusivas em tela cheia podem não expor os dados de reprodução nem permitir uma sobreposição.
- Aplicações sem integração com a central de mídia do sistema ainda podem expor sua fonte de áudio, mas não garantem título, capa ou progresso; vídeos pausados, parados e silenciados são ocultados intencionalmente.
- Um navegador deve publicar progresso de arquivos macOS ou usar arquivos temporários reconhecíveis em Downloads para que zisla mostre uma porcentagem.
- Saúde da bateria, temperatura, potência ao vivo e níveis dos acessórios dependem do hardware, do método de conexão e dos dados expostos pelo macOS; campos ausentes são mostrados como indisponíveis.
- A conversão de Office para PDF exige LibreOffice ou OpenOffice; as demais operações PDF executam localmente.
- Os pacotes não são notarizados e podem exigir **Abrir Mesmo Assim** no primeiro início. As versões estáveis usam um único certificado autoassinado para preservar as permissões macOS nas atualizações posteriores; Sparkle verifica separadamente cada atualização com a chave pública EdDSA incorporada antes de extrair, substituir e reiniciar a aplicação.

## Licença

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). O uso não comercial é permitido; vender este software ou fazer qualquer outro uso comercial é proibido.
