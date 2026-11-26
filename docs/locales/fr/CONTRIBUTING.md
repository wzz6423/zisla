# Contribuer à zisla

**Français** | [Langues de la documentation](../README.md)

Merci de contribuer à zisla.

## Signalement de problèmes

Merci d'ouvrir une issue. Recherchez d'abord parmi les Issues et Discussions existantes pour éviter les doublons.

- Utilisez `[Bug] Short problem description` pour les anomalies, par exemple `[Bug] Voice input is not written to the current text field`. Indiquez la version de zisla, la version macOS et l'appareil, la méthode d'installation, les étapes de reproduction, le comportement attendu et celui observé.
- Utilisez `[Feature] Short request description` pour les fonctionnalités, par exemple `[Feature] Support custom voice-organization prompts`. Décrivez le problème, la solution proposée et les alternatives envisagées.
- Choisissez une **Area** dans le formulaire. Ce champ obligatoire détermine le label `area:*` : `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` ou `Community & Discussion`. Les formulaires en chinois simplifié proposent les mêmes choix et labels.
- Retirez les tokens, détails de compte, chemins locaux et autres informations sensibles des journaux, captures et enregistrements.
- Signalez les vulnérabilités en privé via [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) au lieu d'ouvrir une issue publique.
- L'automatisation applique `bug` ou `enhancement` et le label `area:*` correspondant sans toucher aux autres labels. Si le préfixe du titre ou un champ requis ne respecte pas le formulaire, elle ajoute `needs-more-info` et conserve un seul commentaire listant les éléments manquants ; modifier l'issue actualise ce commentaire.

## Développement

L'implémentation macOS actuelle se trouve dans `mac/` et nécessite macOS 14+ avec Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Supprimez les binaires de test, de compilation et de création de paquets avant de commiter.

Avant chaque commit ou amend, exécutez `make format` depuis la racine avec SwiftFormat 0.64.7, comme la CI. Examinez les différences et conservez seulement le formatage nécessaire à la tâche actuelle.

## Branches et commits

- Créez les branches depuis le dernier `main` et préfixez-les selon le type déclaré par la pull request : `feat/` ou `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/` ou `revert/`, par exemple `fix/download-timeout` ou `ci/skip-directive-timing`.
- Utilisez le format anglais [Conventional Commits](https://www.conventionalcommits.org/), comme `type(scope): description` ou `fix(ui): resolve layout issue in notch area`.
- Gardez une branche et une pull request centrées sur un objectif clair ; évitez les changements uniquement de formatage et les refactorisations sans rapport.
- Les branches `publish-v*` sont réservées à la maintenance des publications. Soumettez toutes les autres contributions à `main`.

## Pull requests

Merci d'ouvrir une pull request. Vérifiez ces exigences pendant qu'elle attend une revue.

- Le **titre de la PR** doit être un sujet Conventional Commit en anglais, par exemple :
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Les types autorisés sont `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci` et `revert`.

- Le **corps de la PR** doit être en anglais et contenir les sections `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue` et `AI Attribution` fournies par `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` conserve la valeur du modèle `- Project: zisla Development`. `Project Automation` la lit pour placer la PR sur le tableau partagé.
  - Dans `GitHub Project`, `Start date` et `Target date` sont obligatoires. Déclarez chaque champ exactement une fois avec une date réelle au format `YYYY-MM-DD` ; `Target date` doit être égale ou postérieure à `Start date`. Les dates absentes, vides, en commentaire, dupliquées ou invalides font échouer `PR Quality`. `Submitted date` utilise automatiquement la date de création UTC+08:00 ; `End date` est rempli à la fusion. Ces deux champs ne sont pas à saisir.
  - `PR Type` déclare exactement une valeur `- Type:` correspondant au type du titre. Les titres utilisent les types canoniques ; le corps accepte aussi les noms de labels et alias configurés, donc `fix`, `bug`, `bug fix`, `bugfix` et `hotfix` correspondent à `fix`. `PR Automation` convertit le type en label, par exemple `fix` en `bug`.
  - `Project Automation` choisit `Status` selon la correspondance configurée des labels, dont celui du type de PR, puis le passe à `Done` à la fermeture ou fusion. Ne saisissez pas `Status` manuellement.
  - `Summary` doit décrire le changement ; `Risk and Rollback` doit contenir exactement un champ `Risk` non vide et un champ `Rollback` non vide.
  - Chaque entrée de `Validation` commence par son propre `- Status:` contenant exactement `passed`, `failed` ou `not run`. Chaque entrée `passed` ou `failed` nécessite ses propres `Command` et `Result` non vides ; chaque `not run` nécessite son propre `Reason` non vide. Les champs d'une autre entrée ne satisfont pas ces exigences. Signalez honnêtement les échecs par `failed`.
  - `Related Issue` doit fermer une issue avec un mot-clé tel que `Closes #123`, ce qui applique aussi `development`, ou contenir exactement `None`.
  - `AI Attribution` doit déclarer exactement un champ `- Agent:` non vide. Tout agent autre que `None` nécessite une ligne correspondante `- Co-authored-by: Name <email>`, également présente comme trailer dans au moins un commit, et applique `ai-assisted`.

  Exemple de titre : `fix(ci): validate every PR metadata entry`

  Exemple de corps, à remplir avec vos résultats réels de validation :

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

  Exemple de dates : la PR est supposée créée le 2026-10-05 et fusionnée le 2026-10-12, UTC+08:00. Les champs automatiques dans le commentaire de code illustrent les valeurs Project, et ne sont pas des entrées. L'automatisation actualise GitHub Project et la chronologie PR, pas ces lignes d'exemple.

  | Date | À la création (2026-10-05) | Après fusion (2026-10-12) | Source |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Entrée obligatoire |
  | `Target date` | 2026-10-12 | 2026-10-12 | Entrée obligatoire |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Date de création automatique |
  | `End date` | Vide | 2026-10-12 | Date de fusion automatique |

- Le contrôle `PR Quality` valide ce format ; une PR ne peut pas être fusionnée tant qu'il échoue. `PR Automation` applique ensuite les labels et affecte la PR.
- Exécutez `cd mac && swift test` pour les changements de code macOS ; décrivez par écrit les résultats de vérification manuelle pour les changements d'interface.
- Les corps de PR et notes de publication peuvent être uniquement textuels ; aucune image, capture ou couverture n'est requise.
- Lors de changements de fonctionnalités, comportements, valeurs par défaut, instructions de compilation ou processus de publication, actualisez les documents officiels et l'aide du site dans le même correctif. Les textes du site destinés aux utilisateurs couvrent les 17 langues ; réutilisez la structure d'aide et le répertoire de documentation localisée.
- Ne commitez pas `.build`, `dist`, téléchargements, journaux, tokens, éléments de signature ou données personnelles.
- `main` et `publish-v*` sont protégés et ne peuvent être actualisés que via une PR revue dont les contrôles réussissent.

## Ignorer des contrôles CI

Les responsables et réviseurs sollicités peuvent ignorer les contrôles qu'un changement ne peut pas affecter, par exemple une correction de documentation. Écrivez la directive seule sur une ligne de commentaire de PR :

| Directive | Effet |
| --- | --- |
| `skip-all` | Ignore tous les workflows de `.github/ci-skip.json`. |
| `skip-<workflow>` | Ignore un workflow par nom, fichier ou alias, tel que `skip-swift`, `skip-web-ci` ou `skip-Web CI`. |
| `unskip-all` | Efface toutes les directives d'exclusion. |
| `unskip-<workflow>` | Rétablit un workflow. |

- Un texte libre peut suivre la directive, par exemple `skip-all: documentation only change`.
- Un workflow peut être nommé comme sur GitHub, espaces compris ; `skip-CI Lint` et `skip-lint` sont donc équivalents. Le nom correspondant le plus long l'emporte et les mots restants deviennent la note.
- Seules les directives du propriétaire du dépôt, d'un membre de l'organisation, d'un collaborateur ou d'un réviseur sollicité sont prises en compte. Les commentaires de bots sont ignorés.
- `CI Skip` annule les exécutions en cours, signale comme réussis les contrôles ignorés pour satisfaire les contrôles requis, applique `skip-ci` et actualise un seul commentaire résumant la décision.
- Tout le fil des commentaires est rejoué à chaque commentaire ; la directive la plus récente l'emporte toujours.
- Une directive expire dès qu'un nouveau commit est poussé : elle ne concerne que le code que son auteur avait vu, sinon un contrôle réussi permettrait de fusionner le nouveau commit sans compilation. `CI Skip` se relance à chaque push pour retirer `skip-ci` et rétablir les contrôles ; le commentaire récapitulatif liste les directives expirées. Commentez de nouveau la directive pour ignorer aussi le nouveau commit.
- Un responsable peut réappliquer la décision sans nouveau commentaire depuis **Actions -> CI Skip -> Run workflow**, en indiquant le numéro de PR.
- `.github/ci-skip.json` associe chaque workflow à ses noms de contrôles. `CI Checks` échoue si le manifeste diverge des fichiers de workflows.

## Contrôles selon les chemins

Un workflow de plateforme n'exécute ses contrôles que si la PR touche les fichiers qu'il construit ; les changements documentaires sont donc vérifiés selon leur chemin :

| Workflow | S'exécute si la PR touche |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- Le champ `paths` de `.github/ci-skip.json` définit les périmètres ; un workflow sans ce champ s'exécute toujours. `CI Lint`, `PR Quality Gates`, `CodeQL` et `Dependency Review` s'exécutent donc sur chaque PR. L'hygiène du dépôt et la validation des skills font partie de `CI Checks` ; les anciens alias `hygiene` et `skills` ne sont plus utilisés.
- Tout changement sous `.github/` exécute l'ensemble des contrôles, car une modification CI doit être validée sur toutes les plateformes.
- Les jobs sont ignorés par une condition de job plutôt qu'un filtre `paths:` du workflow, ce qui permet au contrôle requis de réussir au lieu de rester indéfiniment en attente.
- Un fichier renommé est comparé selon son ancien et son nouveau chemin, sans tenir compte de la casse.
