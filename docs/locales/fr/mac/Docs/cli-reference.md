# Référence d'intégration de `zislactl`

**Français** | [Langues de la documentation](../../../README.md)

`zislactl` est le protocole local partagé d'état pour les outils d'IA, scripts et tâches de CI intégrés à zisla. Il écrit l'état des tâches, l'utilisation et les notifications comme données structurées et les conserve dans des transactions SQLite pour éviter les écritures partielles. Ce document définit les fournisseurs, commandes et contraintes de champs stables.

## Principes de conception

- L'état est écrit localement et n'envoie jamais les invites, le contenu des réponses ou les identifiants.
- Les mises à jour d'un même ID de tâche sont idempotentes ; les lecteurs voient l'état complet validé de la base.
- Les noms de fournisseurs acceptent des alias de compatibilité mais sont conservés sous leur valeur canonique.

## Persistance locale et limites JSON

Les tâches, utilisations et notifications résident dans `~/Library/Application Support/zisla/ai-state.sqlite`. Les écritures utilisent des transactions SQLite ; le protocole actuel n'écrit pas `ai-state.json`. Effacer les tâches conserve l'historique d'utilisation.

`zislactl` accepte les options de ligne de commande documentées et `list` imprime du texte ligne par ligne. Les intégrations et la configuration utilisent toujours du JSON structuré, y compris les sessions JSON/JSONL des outils externes et l'encodage/décodage JSON des réglages, selon leurs propres règles d'analyse. La CLI elle-même utilise des arguments, une sortie texte et une persistance SQLite.

## Fournisseurs

| Valeur | Alias |
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

WorkBuddy et WorkBuddy AI sont des produits distincts pour les marchés national/international,
et non des versions ancienne/récente d'un même client. Leurs fournisseurs canoniques, stockages, icônes
et liens profonds doivent rester séparés. Les anciens enregistrements WorkBuddy utilisant `harness` restent lisibles ;
ce fournisseur n'est ni renommé ni migré globalement. Les ID de notification d'activité WorkBuddy utilisent
une séparation explicite fournisseur/tâche (`ai-active-workbuddy:<id>` ou `ai-active-workbuddy-ai:<id>`),
afin qu'une tâche WorkBuddy manuelle dont l'ID commence par `ai-` ne soit pas confondue avec WorkBuddy AI.

### Détection automatique de Delta, Orca, WorkBuddy et WorkBuddy AI

- Delta : lit les métadonnées indexées des fils en diffusion depuis `Library/Application Support/Delta/user_*/data.sqlite`
  et l'ancienne base racine. Les fils archivés, inactifs et périmés sont exclus. L'utilisation numérique provient
  du registre `app_model_usage_daily` de Delta, lectures et écritures de cache comprises. Une version sans
  ce registre ne rapporte aucune utilisation automatique ; elle ne déduit pas les comptes des conversations.
- Orca : lit les instantanés locaux `agent-hooks/last-status.json` et l'état actuel des tours de conversation structurée
  depuis `agent-session-journal.db`, y compris les dossiers de profils et les enregistrements v1/v2/v3.
  Les révisions les plus élevées et l'ordre original des tours sont respectés. Les sessions terminées, expirées, distantes
  et limitées à l'identité sont exclues. Les chemins de transcription de référence et les dossiers de compte Claude/Codex
  épinglés contribuent aussi aux tokens. Ces échantillons conservent le fournisseur CLI sous-jacent et
  l'identité de l'événement, empêchant un second comptage par le détecteur CLI habituel. Les caches d'utilisation
  globaux de la machine d'Orca ne sont volontairement pas importés comme utilisation supplémentaire.
- WorkBuddy : lit sa propre base `~/.workbuddy/workbuddy.db` avec le fournisseur `workbuddy`,
  l'icône WorkBuddy et les liens `workbuddy://chat/<id>`. Il n'inspecte pas le stockage de WorkBuddy AI.
- WorkBuddy AI : lit l'état des sessions, les titres, le modèle et les horodatages depuis
  `~/.workbuddy-ai/workbuddy.db`, indépendamment de `~/.workbuddy/workbuddy.db` de WorkBuddy.
  Les sessions terminées, supprimées et périmées sont exclues ; la valeur la plus récente entre `updated_at` et
  `last_activity_at` garde les longues sessions visibles. Les tâches utilisent le fournisseur `workbuddy-ai`,
  l'icône WorkBuddy AI et les liens `workbuddy-ai://chat/<id>`. L'intégration détecte seulement les sessions :
  `session_usage.used` représente l'occupation du contexte et les crédits ne sont pas une utilisation USD/tokens ;
  aucun n'est donc importé comme tokens facturés. L'utilisation numérique manuelle peut être signalée par `zislactl usage`.
- Toutes les intégrations sont en lecture seule et au mieux des données disponibles ; un stockage absent ou incompatible ne renvoie rien.
  Elles n'interrogent ni les contenus répliqués des fils Delta ni les messages du journal Orca. Utilisez `zislactl usage`
  pour les outils ou versions qui n'exposent pas d'utilisation numérique enregistrée.

## Syntaxe des options

- Écrivez une option sous la forme `--key value` ou `--key=value`. Chaque option ne peut apparaître qu'une fois par commande ; une répétition est une erreur d'utilisation, code de sortie 64.
- Une valeur peut commencer par `--`, comme `--detail --verbose`. Exception : un indicateur de la même commande, `--failed` pour `finish` ou `--queued` pour `update`, n'est jamais pris comme valeur. Une variable vide non entre guillemets dans `--detail $DETAIL --failed` marque donc toujours la tâche comme échouée. Pour transmettre cette valeur littérale, utilisez `--detail=--failed`.
- `--failed` et `--queued` sont des indicateurs. Seuls, ils signifient vrai ; `--failed=false` ou `--failed false`, de même pour `--queued`, les désactivent. Toute autre valeur est une erreur d'utilisation.

## `update`

Crée ou remplace une tâche portant le même `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Sans `--progress`, l'interface affiche une progression indéterminée.
- `--pid` est facultatif et doit être fourni seulement si l'appelant peut identifier le processus de la tâche.
- `--status` signale explicitement l'exécution, la mise en file, l'attente d'une action utilisateur ou une erreur pendant l'exécution.
- `--queued` est un alias de `--status queued` ; sans état explicite, la tâche est en cours. Un `--status` explicite a priorité sur `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Les tâches réussies passent à 100 % ; celles qui échouent conservent leur dernière progression.

## `remove`

```text
zislactl remove --id <id>
```

Quitte avec le code 65 lorsque la tâche n'existe pas.

## `clear`

```text
zislactl clear
```

Efface les tâches en conservant l'historique d'utilisation et les notifications.

## `list`

```text
zislactl list
```

Imprime l'état actuel de la tâche, le fournisseur, le titre et le pourcentage, une ligne à la fois.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

L'utilisation alimente le graphique sur 12 heures et la carte thermique 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

La nouvelle notification apparaît du côté choisi et suspend sa fermeture automatique pendant le survol.

## `message`

Envoie une notification de message des deux côtés de l'îlot : le côté gauche affiche le logo et l'expéditeur, le côté droit fait défiler le contenu.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Exemple :

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender` et `--content` sont requis ; `--app-bundle-id` est facultatif et aide à trouver l'icône de l'application installée.
- Les sauts de ligne et espaces superflus sont regroupés et le contenu est tronqué à environ 48 caractères avec des points de suspension.
- Une seule transaction SQLite conserve les deux entrées `IslandNotice` sans changer le comportement existant de `notify`.

## Codes de sortie

| Code | Signification |
| --- | --- |
| `0` | Réussite |
| `64` | Argument ou sous-commande invalide |
| `65` | Erreur de données, tâche absente ou base corrompue |
| `70` | Erreur du système de fichiers ou autre erreur d'exécution |
