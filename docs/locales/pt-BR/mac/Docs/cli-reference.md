# Referência de integração do `zislactl`

**Português (Brasil)** | [Idiomas da documentação](../../../README.md)

`zislactl` é o protocolo local compartilhado de estado para ferramentas de IA, scripts e tarefas CI integrados ao zisla. Grava o estado das tarefas, o uso e as notificações como dados estruturados e os persiste em transações SQLite para evitar estado parcialmente escrito. Este documento define fornecedores, comandos e restrições de campos estáveis.

## Princípios

- O estado é gravado localmente e nunca envia prompts, conteúdo de respostas ou credenciais.
- As atualizações do mesmo ID de tarefa são idempotentes; os leitores veem o estado completo confirmado no banco de dados.
- Os nomes dos fornecedores aceitam aliases de compatibilidade, mas são armazenados com seu valor canônico.

## Persistência local e limites JSON

As tarefas, o uso e os avisos ficam em `~/Library/Application Support/zisla/ai-state.sqlite`. As escritas usam transações SQLite; o protocolo atual não grava `ai-state.json`. Limpar as tarefas mantém o histórico de uso.

`zislactl` aceita as opções documentadas de linha de comando, e `list` imprime texto orientado a linhas. Integrações e configuração continuam usando JSON estruturado, incluindo entradas de sessões externas JSON/JSONL e codificação/decodificação JSON dos ajustes, segundo suas próprias regras de análise. A CLI em si usa argumentos, saída de texto e persistência SQLite.

## Fornecedores

| Valor | Aliases |
| --- | --- |
| `claude` | `claude-code`, `claude-cli`, `claude-desktop` |
| `codex` | `openai-codex`, `codex-cli`, `codex-desktop` |
| `gemini` | `google-gemini`, `gemini-cli`, `gemini-code-assist` |
| `grok` | `grok-cli`, `xai` |
| `gpt` | `openai`, `chatgpt`, `openai-gpt` |
| `copilot` | `github-copilot`, `copilot-cli`, `copilot-chat` |
| `kimi` | `kimi-code`, `kimi-code-cli`, `kimi-vscode` |
| `qwen` | `tongyi`, `qwen-code`, `qwen-code-cli`, `qwen-vscode` |
| `coder` | `qoder`, `qoder-cli`, `qoderwork`, `qoderwork-cn`, `qoderwake`, `qwen-coder` |
| `zcode` | `z-code`, `zcode-cli`, `zcode-desktop`, `glm`, `glm-coding`, `z-ai`, `z.ai` |
| `trae` | `trae-work`, `traework`, `trae-solo`, `trae-cn` |
| `opencode` | `open-code`, `open_code` |
| `pi` | `pi-coding`, `pi-coding-agent`, `pi-cli`, `pi-agent` |
| `harness` | `harnext`, `harnext-cli`, `harness-cli` |
| `doubao` | `豆包` |
| `delta` | `delta-app`, `delta-desktop`, `zed-delta` |
| `orca` | `orca-desktop`, `orca-ide` |
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`, `workbuddy ai` |

WorkBuddy e WorkBuddy AI são produtos separados para os mercados nacional/internacional,
não versões antiga/nova do mesmo cliente. Seus fornecedores canônicos, bancos, ícones e links diretos
devem permanecer separados. Os registros históricos de WorkBuddy com `harness` continuam legíveis;
esse fornecedor não é renomeado nem migrado globalmente. IDs de avisos de atividade WorkBuddy usam
uma separação explícita entre fornecedor e tarefa (`ai-active-workbuddy:<id>` ou `ai-active-workbuddy-ai:<id>`),
para que uma tarefa manual WorkBuddy com ID iniciado em `ai-` não seja confundida com WorkBuddy AI.

### Detecção automática de Delta, Orca, WorkBuddy e WorkBuddy AI

- Delta lê metadados indexados de threads em streaming de `Library/Application Support/Delta/user_*/data.sqlite`
  e do banco raiz legado. Threads arquivadas, ociosas e antigas são excluídas. O uso numérico vem
  do registro `app_model_usage_daily`, incluindo leituras e escritas de cache. Uma versão sem esse registro
  não informa uso automático e não estima contagens a partir do conteúdo das conversas.
- Orca lê snapshots locais de `agent-hooks/last-status.json` e o estado atual dos turnos de chat estruturado
  de `agent-session-journal.db`, incluindo diretórios de perfil e registros de turnos v1/v2/v3.
  As revisões mais altas e a ordem original dos turnos são respeitadas. Sessões concluídas, expiradas, remotas
  e apenas de identidade são excluídas. Os caminhos oficiais de transcrição e diretórios de contas Claude/Codex
  fixados também contribuem para o uso de tokens. Essas amostras mantêm o fornecedor CLI subjacente e
  a identidade do evento, evitando uma nova contagem pelo detector CLI comum. Os caches de uso do Orca
  para toda a máquina não são importados deliberadamente como uso adicional.
- WorkBuddy lê seu próprio `~/.workbuddy/workbuddy.db` com o fornecedor `workbuddy`,
  o ícone WorkBuddy e links `workbuddy://chat/<id>`. Não inspeciona o armazenamento WorkBuddy AI.
- WorkBuddy AI lê estado, títulos, modelo e horários das sessões de
  `~/.workbuddy-ai/workbuddy.db`, independentemente de `~/.workbuddy/workbuddy.db` do WorkBuddy.
  Sessões finalizadas, excluídas e antigas são descartadas; o horário mais recente entre `updated_at` e
  `last_activity_at` mantém as sessões longas visíveis. As tarefas usam o fornecedor `workbuddy-ai`,
  o ícone WorkBuddy AI e links `workbuddy-ai://chat/<id>`. Essa integração detecta somente sessões:
  `session_usage.used` é ocupação de contexto, e créditos não são uso em USD/tokens, portanto nenhum
  é importado como tokens faturados. O uso numérico manual pode ser informado com `zislactl usage`.
- Todas as integrações são de somente leitura e de melhor esforço; bancos ausentes ou incompatíveis não retornam dados.
  Elas não consultam corpos de threads Delta replicados nem mensagens do diário Orca. Use `zislactl usage`
  para ferramentas ou versões que não expõem uso numérico registrado.

## Sintaxe de opções

- Escreva uma opção como `--key value` ou `--key=value`. Cada opção só pode aparecer uma vez por comando; repeti-la é um erro de uso, com código de saída 64.
- Um valor pode começar com `--`, como em `--detail --verbose`. A exceção é uma flag do mesmo comando: `--failed` de `finish` e `--queued` de `update` nunca são tratados como valores. Assim, uma variável vazia sem aspas em `--detail $DETAIL --failed` ainda marca a tarefa como falha. Passe esse valor literal como `--detail=--failed`.
- `--failed` e `--queued` são flags. Sozinhas, significam verdadeiro; `--failed=false` ou `--failed false`, e o mesmo para `--queued`, as desligam. Qualquer outro valor é um erro de uso.

## `update`

Cria ou substitui uma tarefa com o mesmo `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Se `--progress` for omitido, a interface mostra progresso indeterminado.
- `--pid` é opcional e só deve ser fornecido quando o chamador consegue identificar o processo da tarefa.
- `--status` informa explicitamente execução, fila, espera por ação do usuário ou erro durante a execução.
- `--queued` é um alias de `--status queued`; sem status explícito, a tarefa está em execução. Um `--status` explícito tem prioridade sobre `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

As tarefas bem-sucedidas são definidas como 100%; as tarefas com falha mantêm seu último progresso.

## `remove`

```text
zislactl remove --id <id>
```

Sai com o código 65 quando a tarefa não existe.

## `clear`

```text
zislactl clear
```

Limpa as tarefas preservando o histórico de uso e as notificações.

## `list`

```text
zislactl list
```

Imprime o estado atual da tarefa, o fornecedor, o título e a porcentagem, uma linha por vez.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

O uso alimenta o gráfico de 12 horas e o mapa de calor 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

A nova notificação aparece no lado escolhido e pausa o fechamento automático enquanto o ponteiro está sobre ela.

## `message`

Envia uma notificação de mensagem para os dois lados da ilha: à esquerda mostra o logotipo da aplicação e o remetente; à direita rola o corpo da mensagem.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Exemplo:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender` e `--content` são obrigatórios; `--app-bundle-id` é opcional e ajuda a localizar o ícone da aplicação instalada.
- Quebras de linha e espaços excedentes são reduzidos, e o corpo é truncado em cerca de 48 caracteres com reticências.
- Uma única transação SQLite persiste as duas entradas `IslandNotice` sem alterar o comportamento existente de `notify`.

## Códigos de saída

| Código | Significado |
| --- | --- |
| `0` | Sucesso |
| `64` | Argumento ou subcomando inválido |
| `65` | Erro de dados, tarefa ausente ou banco corrompido |
| `70` | Erro do sistema de arquivos ou outro erro de execução |
