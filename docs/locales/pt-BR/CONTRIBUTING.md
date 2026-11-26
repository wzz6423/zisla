# Contribuir com o zisla

**Português (Brasil)** | [Idiomas da documentação](../README.md)

Obrigado por contribuir com o zisla.

## Issues

Obrigado por abrir uma issue. Pesquise primeiro as Issues e Discussions existentes para não duplicar os relatos.

- Use `[Bug] Short problem description` para relatar erros, por exemplo `[Bug] Voice input is not written to the current text field`. Inclua a versão do zisla, a versão do macOS e o dispositivo, o método de instalação, as etapas de reprodução, o comportamento esperado e o comportamento observado.
- Use `[Feature] Short request description` para solicitar recursos, por exemplo `[Feature] Support custom voice-organization prompts`. Descreva o problema, a solução proposta e as alternativas consideradas.
- Escolha uma **Area** no formulário. O campo é obrigatório e determina a etiqueta `area:*`: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` ou `Community & Discussion`. Os formulários em chinês simplificado oferecem as mesmas opções, associadas às mesmas etiquetas.
- Remova tokens, dados de contas, caminhos locais e outras informações sensíveis dos logs, capturas de tela e gravações.
- Relate vulnerabilidades em privado por meio de [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), em vez de abrir uma issue pública.
- A automação aplica `bug` ou `enhancement` junto com a etiqueta `area:*` correspondente e preserva todas as outras etiquetas. Quando o prefixo do título ou um campo obrigatório não segue o formulário, também aplica `needs-more-info` e mantém um único comentário com as informações ausentes. Ao editar a issue, esse comentário se atualiza.

## Desenvolvimento

A implementação macOS atual está em `mac/` e exige macOS 14+ com Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Remova os binários produzidos pelos testes, pela compilação e pelo empacotamento antes de fazer commit.

Antes de cada commit ou amend, execute `make format` na raiz do repositório com SwiftFormat 0.64.7, a mesma versão da CI. Revise as diferenças e mantenha apenas a formatação necessária para a tarefa atual.

## Branches e commits

- Crie branches a partir do `main` mais recente e use o prefixo do tipo declarado pela pull request: `feat/` ou `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/` ou `revert/`. Exemplos: `fix/download-timeout` e `ci/skip-directive-timing`.
- Use o formato [Conventional Commits](https://www.conventionalcommits.org/) em inglês, como `type(scope): description` ou `fix(ui): resolve layout issue in notch area`.
- Mantenha uma branch e uma pull request concentradas em um objetivo claro; evite alterações apenas de formatação e refatorações sem relação com a tarefa.
- As branches `publish-v*` são reservadas à manutenção de publicações. Envie todas as outras contribuições para `main`.

## Pull requests

Obrigado por abrir uma pull request. Confira estes requisitos enquanto ela aguarda revisão.

- O **título da PR** deve ser um assunto Conventional Commit em inglês, por exemplo:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Os tipos permitidos são `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci` e `revert`.

- O **corpo da PR** deve estar em inglês e conter as seções `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue` e `AI Attribution` fornecidas por `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` mantém o valor do modelo `- Project: zisla Development`. `Project Automation` lê esse campo para colocar a pull request no quadro compartilhado.
  - Em `GitHub Project`, `Start date` e `Target date` são obrigatórios. Declare cada um exatamente uma vez como uma data real no formato `YYYY-MM-DD`; `Target date` deve ser igual ou posterior a `Start date`. Datas ausentes, vazias, comentadas, duplicadas ou inválidas fazem `PR Quality` falhar. `Submitted date` usa automaticamente a data de criação em UTC+08:00; `End date` é preenchido automaticamente ao mesclar a PR. Nenhum dos dois precisa ser inserido manualmente.
  - `PR Type` declara exatamente um valor `- Type:`, que deve corresponder ao tipo do título. Os títulos usam tipos canônicos; o corpo também aceita nomes de etiquetas de tipo e aliases configurados, portanto `fix`, `bug`, `bug fix`, `bugfix` e `hotfix` correspondem a `fix`. `PR Automation` transforma o tipo resolvido em uma etiqueta, por exemplo `fix` em `bug`.
  - `Project Automation` escolhe `Status` a partir do mapeamento de etiquetas configurado, incluindo a etiqueta de tipo da PR, e o define como `Done` quando a PR é fechada ou mesclada. Não preencha `Status` manualmente.
  - `Summary` deve descrever a mudança. `Risk and Rollback` deve conter exatamente um campo `Risk` não vazio e um campo `Rollback` não vazio.
  - Cada entrada de `Validation` começa com seu próprio `- Status:`, declarando exatamente `passed`, `failed` ou `not run`. Cada entrada `passed` ou `failed` precisa de seus próprios `Command` e `Result` não vazios; cada entrada `not run` precisa de seu próprio `Reason` não vazio. Campos de outra entrada não atendem a esses requisitos. Relate as falhas honestamente com `failed`.
  - `Related Issue` deve fechar uma issue com uma palavra-chave como `Closes #123`, que também aplica a etiqueta `development`, ou ser exatamente `None`.
  - `AI Attribution` deve declarar exatamente um campo `- Agent:` não vazio. Qualquer agente diferente de `None` exige uma linha correspondente `- Co-authored-by: Name <email>`, que também deve aparecer como trailer em pelo menos um commit, e aplica a etiqueta `ai-assisted`.

  Exemplo de título: `fix(ci): validate every PR metadata entry`

  Exemplo de corpo; registre seus resultados reais de validação:

  ```markdown
  ## Summary
  - Validate every PR metadata field and each Validation entry independently.
  - Keep contributor welcome replies aligned with the current PR template.

  ## GitHub Project
  - Project: zisla Development
  - Start date: 2026-10-05
  - Target date: 2026-10-12
  <!--
  Automatic Project fields (illustration only; not PR body inputs):
  - Submitted date: 2026-10-05 (PR creation date in UTC+08:00)
  - End date: 2026-10-12 (assumed merge date in UTC+08:00; blank before merge)
  Automation updates Project date fields and the PR Timeline; it does not fill these comment lines.
  -->

  ## PR Type
  - Type: fix

  ## Validation
  - Status: passed
  - Command: ruby .github/scripts/pr-metadata-test.rb
  - Result: All PR metadata contract tests passed.

  - Status: passed
  - Command: ruby .github/scripts/contributor-welcome-test.rb
  - Result: Both documented examples pass PR validation and the welcome reply preserves the complete example.

  - Status: passed
  - Command: actionlint .github/workflows/*.yml
  - Result: All workflow files passed actionlint.

  - Status: not run
  - Reason: Local macOS tests were not run because this change only affects PR metadata and contributor guidance. Platform checks still run in CI.

  ## Risk and Rollback
  - Risk: Stricter metadata checks may reject incomplete PR descriptions; no application behavior changes.
  - Rollback: Revert this pull request to restore the previous metadata checks and guidance.

  ## Related Issue
  None

  ## AI Attribution
  - Agent: Codex
  - Co-authored-by: Codex <noreply@openai.com>
  ```

  Exemplo de datas: suponha que a PR seja criada em 2026-10-05 e mesclada em 2026-10-12, em UTC+08:00. Os campos automáticos do comentário de código ilustram os valores do Project; não são entradas do corpo da PR. A automação atualiza GitHub Project e a linha do tempo da PR, não essas linhas de comentário.

  | Data | Na criação (2026-10-05) | Após mesclar (2026-10-12) | Origem |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Entrada obrigatória |
  | `Target date` | 2026-10-12 | 2026-10-12 | Entrada obrigatória |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Data de criação automática |
  | `End date` | Vazio | 2026-10-12 | Data de mesclagem automática |

- A verificação `PR Quality` valida esse formato; uma pull request não pode ser mesclada enquanto a verificação falhar. Depois, `PR Automation` aplica as etiquetas e atribui a pull request.
- Execute `cd mac && swift test` para alterações no código macOS. Em alterações de interface, descreva os resultados da verificação manual em texto.
- Os corpos das PRs e as notas de publicação podem conter somente texto; imagens, capturas de tela e capas não são obrigatórias.
- Atualize a documentação formal relacionada e a ajuda do site no mesmo patch ao alterar recursos, comportamento, valores padrão, instruções de compilação ou processos de publicação. Os textos do site voltados ao usuário abrangem os 17 idiomas; reutilize a estrutura de ajuda existente e o diretório de documentação localizada.
- Não faça commit de `.build`, `dist`, arquivos baixados, logs, tokens, materiais de assinatura ou dados pessoais.
- `main` e `publish-v*` são protegidas e só podem ser atualizadas por uma pull request revisada que passe em suas verificações.

## Ignorar verificações de CI

Os mantenedores e revisores solicitados podem ignorar verificações que uma mudança não pode afetar, como uma correção somente de documentação. Escreva a diretiva em sua própria linha em um comentário da pull request:

| Diretiva | Efeito |
| --- | --- |
| `skip-all` | Ignora todos os workflows listados em `.github/ci-skip.json`. |
| `skip-<workflow>` | Ignora um workflow por nome, arquivo ou alias, como `skip-swift`, `skip-web-ci` ou `skip-Web CI`. |
| `unskip-all` | Remove todas as diretivas de omissão. |
| `unskip-<workflow>` | Restaura um workflow. |

- Um texto livre pode seguir a diretiva, por exemplo `skip-all: documentation only change`.
- O workflow pode ser identificado pelo nome exibido no GitHub, incluindo espaços; portanto `skip-CI Lint` e `skip-lint` são a mesma diretiva. O nome correspondente mais longo prevalece, e as palavras restantes formam a observação.
- Só são aceitas diretivas do proprietário do repositório, de um membro da organização, de um colaborador ou de um revisor solicitado. Comentários de bots são ignorados.
- `CI Skip` cancela as execuções em andamento, informa as verificações ignoradas como bem-sucedidas para satisfazer as verificações obrigatórias, aplica a etiqueta `skip-ci` e atualiza um único comentário de resumo com a decisão atual.
- Todo o histórico de comentários é reprocessado a cada comentário, portanto a diretiva mais recente sempre prevalece.
- Uma diretiva expira assim que um novo commit é enviado: ela só pode se referir ao código que seu autor viu, pois uma verificação marcada como bem-sucedida permitiria mesclar o novo commit sem compilá-lo. `CI Skip` roda novamente em cada push para remover `skip-ci` e restaurar as verificações; o comentário de resumo lista as diretivas expiradas. Comente a diretiva novamente para ignorar também o novo commit.
- Um mantenedor pode reaplicar a decisão atual sem criar um comentário em **Actions -> CI Skip -> Run workflow**, informando o número da pull request.
- `.github/ci-skip.json` associa cada workflow aos nomes das verificações que publica. `CI Checks` falha quando o manifesto diverge dos arquivos dos workflows.

## Verificações por caminho

Um workflow de plataforma só executa suas verificações quando a pull request toca os arquivos que ele compila; alterações de documentação são verificadas de acordo com seu caminho:

| Workflow | Executa quando a PR toca |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- O campo `paths` de `.github/ci-skip.json` define os escopos. Um workflow que não declara esse campo sempre executa, portanto `CI Lint`, `PR Quality Gates`, `CodeQL` e `Dependency Review` executam em toda PR. A higiene do repositório e a validação de skills fazem parte de `CI Checks`; os antigos aliases `hygiene` e `skills` não são mais usados.
- Qualquer alteração em `.github/` executa tudo, porque uma mudança na CI deve ser validada em todas as plataformas.
- Os jobs são ignorados por uma condição no job, em vez de um filtro `paths:` do workflow, para que uma verificação obrigatória informe sucesso em vez de permanecer pendente.
- Um arquivo renomeado é comparado pelo caminho antigo e pelo novo, sem diferenciar maiúsculas de minúsculas.
