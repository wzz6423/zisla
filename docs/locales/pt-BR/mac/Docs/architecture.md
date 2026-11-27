# Projeto de arquitetura e desempenho

**Português (Brasil)** | [Idiomas da documentação](../../../README.md)

## Ativação na borda superior

O estado oculto não tem uma janela transparente. `PointerEdgeMonitor` instala observadores globais e locais `NSEvent` para movimento e arrasto do mouse; `ScreenLayoutEngine` usa somente geometria para determinar se o ponteiro entra na área de 6 px no centro superior de cada tela.

Cada tela tem uma identidade estável combinando `NSScreenNumber` com seu `CGDirectDisplayID`. O layout é ancorado em `screen.frame.maxY`, permitindo coordenadas negativas, telas empilhadas verticalmente e telas externas sem recorte.

Com várias telas conectadas, Ajustes → Geral → Modos de tela permite escolher para cada tela o modo Dynamic Island (posição da câmera ou personalizada), o modo notch ou ocultar. Com uma tela, esse ajuste fica oculto e vale a aparência global; ao reconectar, as configurações salvas de cada tela são restauradas.

## Janela

A ilha principal mantém um `.borderless + .nonactivatingPanel`:

- Usa o nível `.statusBar` e não cobre a tela bloqueada nem o menu do sistema.
- `.canJoinAllSpaces + .fullScreenAuxiliary` oferece suporte a Spaces e aplicações comuns em tela cheia.
- A expansão ao passar o ponteiro nunca chama `NSApp.activate`, portanto não tira o foco da aplicação atual.
- O estado oculto usa `orderOut`, para que a área da barra de menus não seja ocupada por uma janela transparente.

Os painéis esquerdo e direito de notificação são criados sob demanda e ocultados assim que suas filas ficam vazias.

## Estado e concorrência

- AppKit, o estado SwiftUI e o controle de janelas permanecem em `MainActor`.
- Downloads, clima e requisições GitHub usam actors.
- O estado de IA escrito pelos hooks é monitorado por eventos do sistema de arquivos do diretório. Cada fonte de sessão compara o horário de modificação e o tamanho do arquivo local de sessão ou atividade mais recente e reutiliza o cache de análise quando nada mudou.
- A detecção automática lê apenas eventos estruturados, marcadores fixos de estado e metadados de atividade necessários para determinar as tarefas. Não lê prompts nem respostas, e uma falha no analisador de um fornecedor não bloqueia os outros.
- Os atrasos de recolhimento usam `Task`s canceláveis e um token de geração para que uma tarefa antiga não oculte uma ilha que já foi reaberta.
- O estado oculto não tem `TimelineView`, temporizador de 60 Hz nem envio contínuo de animações.

## Detecção de mídia

MediaRemote fornece título, capa, progresso e controles. As propriedades de objetos de processo do Core Audio 14.4+ confirmam se uma aplicação tem um fluxo de saída ativo e fornecem uma aplicação alternativa quando os metadados estão ausentes. As listas de processos e o estado de saída usam observadores de propriedades junto com verificação periódica limitada; o conteúdo de áudio nunca é capturado, e nenhuma permissão de Gravação de Tela ou Acessibilidade é solicitada. Fontes pausadas, paradas ou silenciadas não permanecem na área de mídia.

## Gravação e mixagem de aplicações

A gravação de tela e o mixer de volume de aplicações são separados da detecção de metadados. A gravação pede Gravação de Tela e permissões das fontes de microfone/câmera habilitadas, salva a mídia escolhida localmente e gerencia os projetos na pasta de gravação selecionada. O mixer usa taps Core Audio no macOS 14.4+ e exige Gravação de Áudio do Sistema.

## Materiais

macOS 26 usa uma única camada SwiftUI `glassEffect`; macOS 14/15 usa uma única camada `NSVisualEffectView`. Reduzir Transparência muda para um fundo opaco. A ilha não empilha várias camadas de desfoque ou material.

## Limite de segurança de downloads

Swift inicia `yt-dlp` com `Process.executableURL` e um array de argumentos; a URL sempre é um valor argv separado após `--`. A configuração de execução, os plugins e exec são desativados, os canais de saída são drenados simultaneamente e o progresso é analisado por um marcador JSON.

Uma tarefa só tem sucesso quando o código de saída é 0, o caminho de saída existe e o caminho resolvido permanece no diretório autorizado. Cada tarefa limpa apenas seu próprio diretório temporário com nome UUID.

## Verificações e downloads de atualização

O canal escolhido resolve o código de país da saída pública uma vez por execução e usa Sparkle para obter o appcast assinado da compilação instalada, baixar o ZIP referenciado por HTTPS, verificar as assinaturas EdDSA do arquivo e do feed antes de extrair, substituir a aplicação e reiniciá-la. `CN` começa com Gitee, `update-release` para Release e `preview` para Preview, e tenta o feed GitHub correspondente uma vez; outros códigos começam com GitHub e tentam Gitee uma vez. Uma consulta indisponível mantém Gitee primeiro; cada feed aponta para um ZIP assinado no próprio host. A publicação oferece um appcast por arquitetura junto com `appcast.xml`. Uma instalação de arquitetura única pede o appcast correspondente à sua variante; uma x86_64 executada por tradução pede `arm64`, portanto não é substituída pela compilação universal. Uma instalação universal conta as variantes no próprio executável e mantém `appcast.xml`, que também atende aplicações anteriores às atualizações por arquitetura. Alterar o ajuste afeta verificações automáticas e manuais e redefine o próximo ciclo do Sparkle. A chave pública incorporada não contém informações de conta; a chave privada fica no chaveiro macOS do responsável pela publicação ou em um arquivo privado protegido separadamente.
