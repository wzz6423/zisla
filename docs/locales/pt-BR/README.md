# zisla

**Português (Brasil)** | [Idiomas da documentação](../README.md)

**zisla é um espaço de trabalho nativo do macOS que aparece quando você precisa e depois sai do caminho.** Mova o ponteiro para o centro superior da tela para abrir um lugar leve para trabalhos de IA ativos, mídia, transferência de arquivos, downloads e utilitários da área de trabalho. Telas sem recorte usam a mesma área de status simulada.

Implementação atual: **macOS 14+**. Apple Silicon é a configuração compatível; pacotes para Intel podem funcionar, mas a compatibilidade não é garantida.

[Assista ao tour completo de recursos — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Assista ao vídeo de lançamento do zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Música: “Funkorama”, de Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Fonte](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Por que ele fica no topo da tela

- **Sob demanda, sem roubar o foco.** Expanda pela borda superior, fixe quando necessário e continue na aplicação atual.
- **Um lugar para o trabalho em andamento.** Veja reprodução, tarefas de IA, downloads, temporizadores, e-mail, status do sistema e bateria sem abrir um painel completo.
- **Atividade de IA sem acesso às conversas.** zisla lê apenas eventos estruturados e metadados locais necessários para determinar o estado das tarefas. Nunca lê prompts nem o conteúdo das respostas.
- **O controle permanece local.** Módulos, histórico da área de transferência e detecção de links têm controles independentes; permissões são solicitadas no primeiro uso da função.

## O que ele faz

### Manter o trabalho da área de trabalho em movimento

| Recurso | Descrição |
| --- | --- |
| Reprodução atual | Mostra capa, título, progresso, letra e controles; Core Audio identifica a aplicação que realmente emite áudio quando faltam metadados. |
| Transferência e compartilhamento | Solte arquivos, mídia ou links na área superior para mantê-los na bandeja, mostrar no Finder ou abrir o compartilhamento do macOS. Comprima arquivos e pastas selecionados em ZIP, redimensione ou converta imagens selecionadas nas Ferramentas de imagem e devolva resultados bem-sucedidos à bandeja, ou importe imagens, vídeo e áudio à biblioteca do estúdio preservando o projeto e a linha do tempo atuais. |
| Área de transferência e notificações | Registra opcionalmente histórico local, reconhece novos links localmente e mostra mídia, atividade de IA, downloads do navegador, temporizadores, e-mail e atualizações no estado recolhido. Ações rápidas opcionais mostram após cada cópia um pequeno aviso da ilha com prévia rica e ações inteligentes: abrir, mostrar no Finder, pesquisar, traduzir, calcular e salvar. Após um download ou arquivo AirDrop recebido, o mesmo atalho abre sua pasta. Novas imagens do histórico entram na fila de reconhecimento de texto no dispositivo; pesquise o texto para encontrar a imagem original ou clique com o botão direito para reconhecer ou copiar o texto. |
| Espaço de trabalho diário | Inclui clima, calendário, lembretes, Mail.app, notas Markdown armazenadas no Notas da Apple, informações na tela bloqueada e mascotes opcionais. Veja uma prévia dos mascotes e mantenha um fixo ou deixe o zisla sortear um da sua lista à meia-noite no horário local ou em um intervalo personalizado. Quando faltam dados meteorológicos, outras fontes complementam o resultado mais completo; os dados disponíveis são mantidos se o restante não puder ser obtido. |

### Tornar o trabalho da IA visível

zisla monitora atividade local de Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI e outras fontes compatíveis. Mostra tarefas, estado, tendências de tokens, mapas de calor de contribuições e avisos laterais.

Para ferramentas sem fonte local estável, `zislactl` permite que scripts, CI e hooks informem progresso, uso e notificações, mantendo o protocolo neste Mac. Ajustes também detecta, instala, atualiza e remove CLIs comuns de IA e gerencia Skills locais. Veja fornecedores e comandos na [referência de integração CLI](mac/Docs/cli-reference.md).

### Resolver as pequenas tarefas úteis

| Área | Ferramentas incluídas |
| --- | --- |
| Downloads e documentos | Downloads de vídeo e áudio por `yt-dlp`; mesclar, dividir, girar, recortar, converter, renderizar, exportar texto, marcas d'água, números de página, criptografia, desbloqueio e edição de metadados PDF localmente. |
| Foco e apresentação | Pomodoro com um alerta sonoro e notificação local ao final da sessão, manter acordado, impedir repouso por inatividade, limpeza de tela e teclado, teleprompter e espelho de câmera. O nome do temporizador vale apenas para a sessão atual e volta ao padrão quando ela termina ou é cancelada. |
| Sistema e bateria | CPU, GPU, memória, disco, rede, ventoinha e bateria, além de limpeza de caches e logs que podem ser removidos com segurança. |
| Entrada de voz | Atalhos globais para gravação e transcrição, organização opcional local ou remota e histórico de voz local. |

### Acessos e fluxos atuais

A ilha tem 12 módulos: Início, Transferência, Área de transferência, Monitoramento de IA, Sons do teclado, Downloads, Agenda, E-mail, Notas, Mixer de volume de aplicações, Utilitários e Sistema. A bateria fica em Sistema; a apresentação na tela bloqueada é separada. Abra ferramentas PDF, de imagem e áudio em Ajustes; o estúdio abre em Ajustes ou na barra de menus.

- **Gravação e criação:** Grave tela, janela ou região com áudio do sistema, microfone e câmera opcionais. Edite legendas, zooms e efeitos de retrato e voz em várias faixas, visualize e exporte vídeo, GIF, Live Photo ou áudio. Imagem oferece 9 operações locais; áudio, 27.
- **Mixagem e reprodução:** macOS 14.4+ permite volume e silêncio por aplicação. Escolha saída no espaço de mídia e preferências do player em Ajustes.
- **Área de trabalho e reuniões:** Prévia de janelas do Dock e Command+Tab, notas contextuais de páginas/janelas/área de trabalho, contagem regressiva de 10 minutos, entrada e notas vinculadas. Agite o ponteiro ao arrastar arquivos para mostrar o destino da prateleira.
- **Resumo diário:** 8 modelos, prévia, exportação PNG manual ou agendada, métricas escolhidas e pasta independente.
- **Contas de IA:** Veja cotas de contas compatíveis, horários de redefinição, avisos de cota baixa e horários de amostragem; exporte histórico local de tokens em `.xlsx`. As cotas Gemini e Claude/GPT do Antigravity têm monitoramento, exibição e alertas independentes. As cotas de conversa do Gemini App usam um Cookie da web da mesma conta Google; o Gemini CLI continua separado.
- **Ações rápidas:** Ações do aviso usam `Command+1` até `Command+0` em ordem. O gatilho adicional padrão para configurações novas é `Command+N` para a primeira ação. Atualizações preservam atalhos salvos e gatilhos apagados.

A [ajuda ao usuário](https://wzz6423.github.io/zisla/help.html?lang=pt-BR#help) oferece nove guias passo a passo: área de transferência, captura, prateleira, reuniões, IA, ferramentas de mídia, resumos diários, notas da área de trabalho/prévias de janelas e reprodução/mixagem. O [guia macOS](mac/README.md) lista pastas e dependências.

## Primeiros passos

### Instalar a aplicação

Baixe o DMG mais recente em [GitHub Releases](https://github.com/wzz6423/zisla/releases) ou [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), monte e arraste `zisla.app` para `Applications`.

Homebrew é outra opção:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew obtém a compilação do seu chip, então Apple Silicon e Intel baixam só sua arquitetura. O cask vem do tap de terceiros `wzz6423/tap`, e não do repositório próprio do Homebrew; instalar significa confiar nesse tap.

Após abrir, mova o ponteiro ao centro superior ou escolha **Mostrar ilha** no ícone da barra de menus. Pacotes não são notarizados; qualquer instalação exige no primeiro início **Abrir Mesmo Assim** em **Ajustes do Sistema > Privacidade e Segurança**, ou remover o atributo de quarentena manualmente:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Atualizar a aplicação

zisla atualiza via Sparkle independentemente da instalação. Para Homebrew: `brew upgrade` substitui somente uma cópia realmente anterior à do tap, porque Homebrew 5.1.6 ou posterior lê a versão no pacote. Assim não interfere no Sparkle nem deixa instalação antiga. Nomear o cask usa os registros do Homebrew e pode restaurar uma aplicação atualizada pelo Sparkle à versão do tap:

```bash
brew upgrade --cask zisla
```

O tap só oferece estáveis; Preview fica em Releases e `brew upgrade` nunca muda para pré-lançamento. Nomear o cask durante Preview substitui pelo estável atual. Sparkle nunca rebaixa versão; voltar a Release mantém Preview até uma estável superá-la. `brew uninstall --cask zisla` remove a aplicação e `brew uninstall --zap --cask zisla` também remove dados locais.

### Executar a partir do código-fonte

Requer Swift 6 / Xcode 16+; apenas Command Line Tools também pode compilar.

```bash
cd mac
swift run zisla
```

O downloader exige `yt-dlp`; `ffmpeg` é opcional. Office para PDF exige LibreOffice ou OpenOffice. Compilação, testes e pacotes estão no [guia de desenvolvimento macOS](mac/README.md).

## Projetado para não atrapalhar

- Admite várias telas, Spaces e aplicações comuns em tela cheia sem ativar nem tirar o foco da aplicação atual.
- Com várias telas conectadas, Ajustes → Geral → Modos de tela permite escolher para cada tela o modo Dynamic Island (posição da câmera ou personalizada), o modo notch ou ocultar. Com uma tela, esse ajuste fica oculto e vale a aparência global; ao reconectar, as configurações salvas de cada tela são restauradas. Todas as telas visíveis mantêm a ilha recolhida ao mesmo tempo. Expandir a ilha, usar ações rápidas, gravar e exibir mensagens temporárias substitui apenas a ilha da própria tela; selecionar telas para notificações filtra o conteúdo sem ocultar a ilha inativa.
- Oculto, não mantém janela transparente permanente de ativação nem ciclo de quadros; eventos globais e geometria disparam expansão.
- Usa um material do sistema e fundo opaco quando Reduzir Transparência está ativo.
- Detecta recorte físico pela área segura; telas externas sem recorte usam sobreposição de mesmo contorno.

Veja decisões no [projeto de arquitetura e desempenho](mac/Docs/architecture.md).

## Privacidade e permissões

zisla pede permissão apenas quando uma função habilitada precisa dela pela primeira vez. Desative módulos em Ajustes ou revogue autorização no macOS a qualquer momento.

| Escopo | Limite |
| --- | --- |
| Atividade de IA | Lê apenas eventos estruturados e metadados locais. Nunca lê prompts ou respostas. |
| Área de transferência e arquivos | Histórico, links e ações rápidas têm controles separados; ações rápidas tratam downloads concluídos e AirDrop independentemente do progresso do navegador. Reconhecimento ocorre no dispositivo e abrir links ou executar ações exige clique ou gatilho explícito. Transferência usa marcadores de escopo de segurança e não copia originais. |
| Notas, e-mail e voz | Notas e E-mail usam AppleScript/JXA com automação. Voz grava apenas quando ativa; organização envia texto somente ao modelo local, fornecedor remoto ou perfil CLI escolhido. |
| Downloads do navegador e mídia | Usa progresso público macOS, metadados MediaRemote e estado Core Audio. Não lê histórico de navegador. Formas de onda e mixagem processam áudio local; gravação salva áudio apenas com a fonte correspondente ativa. |
| Rede | Clima, IP público, espelho de atualização, downloads, cotas habilitadas e instalação de dependências/CLI contatam seus serviços. Tradução, limpeza de voz e edição IA opcionais usam fornecedor ou CLI escolhido. Reconhecimento Apple pode usar rede conforme sistema e idioma. |

### Permissões por recurso

zisla solicita autorização no primeiro uso. Se já negou, abra o item em **Ajustes do Sistema > Privacidade e Segurança** e permita `zisla`; nomes variam entre versões.

| Permissão ou ajuste do sistema | Quando necessário | Escopo autorizado |
| --- | --- | --- |
| Controle do dispositivo e acesso a dados (Acessibilidade em algumas versões) | Inserir transcrição automaticamente no campo atual | Lê e localiza campos não protegidos por senha e entrega por APIs de acessibilidade ou `Cmd+V`. Sem autorização, ainda copia à área de transferência. |
| Microfone | Entrada de voz ou microfone do estúdio | Captura microfone escolhido para gravação ou monitoramento habilitado. |
| Reconhecimento de fala | Converter gravação em texto | Processa só fala gravada ativamente. Entrada de voz exige ambas as autorizações de microfone e reconhecimento. |
| Acesso Total ao Disco | Ver e-mail sem Mail.app aberto | Lê índice em `~/Library/Mail` para contas, remetentes, assuntos, resumos, horários e status de leitura. Esse acesso ao índice exige autorização. |
| Automação | Ler, escrever, responder, marcar ou excluir Mail.app; ler e escrever Notas | Permite controlar aplicações correspondentes; permissões Mail e Notas são revogadas separadamente. |
| Calendários; Lembretes | Usar Agenda | Lê e gerencia eventos e lembretes com autorizações separadas. |
| Serviços de Localização | Clima atual | Solicita posição uma vez, sem rastreamento contínuo. Locais manuais dispensam acesso. |
| Câmera | Espelho ou prévia/gravação do estúdio | Usa câmera escolhida durante a função ativa. |
| Monitoramento de Entrada | Sons, estatísticas, limpeza de teclado e atalhos só de modificadores ou botões laterais | Observa eventos da função; estatísticas ficam locais. Atalhos globais comuns não exigem autorização. |
| Bluetooth | Bateria de acessórios em Sistema → Bateria | Lê só informações públicas de dispositivos conectados ou pareados. |
| Gravação de Tela e Áudio do Sistema (Gravação de Tela em versões antigas) | Capturas, prévias, gravação, formas de onda e mixer | Lê imagens e fontes escolhidas. Gravação salva fontes ativas localmente; mixer exige macOS 14.4+. |
| Notificações | Avisos Pomodoro | Toca um alerta e mostra notificação local ao terminar. |
| Pastas escolhidas pelo usuário (sem autorização manual) | Transferência, importação/exportação ou pasta de download | Seletor do sistema concede acesso à pasta escolhida. Não exige Acesso Total ao Disco. |

Revogar permissão desativa só o recurso correspondente. Se continuar indisponível após alterar ajuste, feche e reabra zisla e tente novamente.

O [guia macOS](mac/README.md) documenta todas as permissões e comportamento de rede.

## Documentação

| Documento | Finalidade |
| --- | --- |
| [Guia de desenvolvimento macOS](mac/README.md) | Módulos, IA, dependências, compilação, testes, permissões e limites. |
| [Guia do site (inglês)](../../../web/README.md) | Desenvolvimento local, produção e links atuais. |
| [Guia do vídeo de lançamento (inglês)](../../../promo/README.md) | Prévia Remotion, renderização, composições, trilhas e licenças. |
| [Projeto de arquitetura e desempenho](mac/Docs/architecture.md) | Ativação superior, janelas, concorrência, mídia e segurança. |
| [Referência de integração CLI](mac/Docs/cli-reference.md) | Fornecedores, comandos, campos e códigos de `zislactl`. |
| [Projeto de assinatura e publicação](mac/Docs/releasing.md) | Assinatura, notarização, DMG, canais e aceitação. |
| [Guia de contribuição](CONTRIBUTING.md) | Ambiente, branches, commits e requisitos PR. |

## Contribuir

Issues e pull requests são bem-vindas. Leia o [guia de contribuição](CONTRIBUTING.md). Relate segurança em privado por [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), em vez de issue pública.

## Licença

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Uso não comercial é permitido; venda ou qualquer uso comercial é proibido.
