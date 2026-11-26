# Projeto de assinatura e publicação

**Português (Brasil)** | [Idiomas da documentação](../../../README.md)

O processo completo de publicação, os dois canais de atualização e a sincronização de artefatos entre GitHub e Gitee são mantidos em [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Esta página documenta apenas as restrições de projeto relativas a assinatura, notarização e pacotes de atualização. Siga o skill ao publicar uma versão.

Ambos os canais selecionados usam Sparkle para verificar o ZIP e o appcast assinados antes de substituir e reiniciar a aplicação. A aplicação resolve o código de país da saída pública de rede uma vez por execução: `CN` consulta Gitee primeiro e tenta GitHub exatamente uma vez; outros códigos consultam GitHub primeiro e tentam Gitee uma vez. Se a consulta não estiver disponível, a ordem continua priorizando Gitee. `package-release.sh` exige que `SPARKLE_GENERATE_APPCAST` aponte para o `generate_appcast` do Sparkle 2.9.4 e grava `appcast-gitee.xml` e `appcast-github.xml` ao lado do ZIP e do DMG. Cada appcast deve ser assinado independentemente e apontar para o ZIP produzido nessa execução e hospedado no seu próprio site. `build-package.sh` executa o script uma vez por arquitetura, de modo que uma publicação contém três pares: envie o par universal como `appcast.xml`, nome ainda solicitado pelas aplicações anteriores às atualizações por arquitetura, e os pares de arquitetura única como `appcast-arm64.xml` e `appcast-x86_64.xml`. Uma instalação de arquitetura única reescreve a URL do feed no Info.plist para o appcast da variante em execução; uma variante x86_64 executada por tradução solicita `arm64`. Assim, continua atualizando para sua própria arquitetura em vez de se tornar universal. Uma instalação universal conta suas próprias variantes, mantém o nome compartilhado e permanece universal. Gitee mantém os feeds permanentes `update-release` para Release e `preview` para Preview; GitHub usa `latest` para Release e a pré-publicação permanente `preview` para Preview. Para publicar sem interação, defina `SPARKLE_ED_KEY_FILE` como o caminho do arquivo EdDSA guardado em privado, ou deixe a variável ausente para usar a conta `zisla-update-ed25519` no chaveiro de login. A chave privada nunca deve entrar no repositório. As versões estáveis usam por padrão o mesmo certificado autoassinado para manter o requisito designado estável e preservar as permissões macOS nas atualizações. Elas continuam sem notarização. Os pacotes Developer ID devem ser notarizados; as prévias gratuitas com assinatura ad hoc também não podem ser notarizadas.

## Pré-requisitos

- A identidade `zisla Release Signing` no chaveiro dedicado à publicação, ou um certificado Developer ID Application
- Credenciais Apple de notarização ao usar Developer ID
- O auxiliar oficial `yt-dlp` obtido e verificado por `Scripts/fetch-yt-dlp.sh`

## 1. Compilar uma aplicação assinada

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Para uma versão estável, o script usa por padrão `RELEASE_SIGNING_MODE=selfsigned`, lê `zisla Release Signing` de `~/Library/Keychains/zisla-release-signing.keychain-db` e desbloqueia esse chaveiro por meio do item `dev.wzz.zisla.release-signing-keychain` no chaveiro de login. Isso não remove o aviso de primeiro início do Gatekeeper, mas mantém um requisito designado baseado no certificado em vez de um cdhash específico de cada compilação.

Com um certificado Developer ID, selecione explicitamente o caminho que permite notarização:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Saída:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Distribuição gratuita de Preview

Sem participar do Apple Developer Program, compile uma prévia com assinatura ad hoc:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Esse pacote não é notarizado e não inclui a autorização WeatherKit. Após publicar seu appcast assinado no feed Preview permanente, a aplicação verifica, baixa, valida, instala e reinicia as atualizações Preview por meio do Sparkle. O primeiro início ainda pode exigir **Ajustes do Sistema > Privacidade e Segurança > Abrir Mesmo Assim**. A assinatura Developer ID e a notarização continuam sendo o caminho recomendado para distribuir sem avisos de segurança.

## 2. Notarizar

```bash
xcrun notarytool submit \
  dist/zisla-v1.0.0-macOS-universal.zip \
  --keychain-profile AC_NOTARY \
  --wait

xcrun stapler staple 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'

# Repackage the stapled app so both the ZIP and DMG contain the final artifact.
export SKIP_BUILD=true
Scripts/package-release.sh
```

## 3. Publicar e verificar

Envie os ZIPs, DMGs, somas de verificação e appcasts GitHub para a mesma tag versionada no GitHub, nomeando os appcasts como `appcast.xml` para universal, `appcast-arm64.xml` e `appcast-x86_64.xml`. Envie os artefatos correspondentes e os appcasts Gitee com os mesmos três nomes para a mesma tag no Gitee. Uma versão estável não deve ser marcada como pré-publicação. Copie os três appcasts Gitee para `update-release` permanente; copie os appcasts Preview para `preview` permanente nos dois sites. O canal escolhido consulta Gitee e depois GitHub para `CN`, e GitHub e depois Gitee para os outros códigos de país.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

As publicações rotineiras mantêm as verificações locais de artefatos, assinaturas, somas de verificação, estrutura dos pacotes e appcasts, as verificações dos artefatos e feeds permanentes nos dois sites e a validação dos metadados de publicação. Baixar novamente os pacotes, verificar a instalação e realizar a aceitação de uma atualização real pelo Sparkle só ocorre mediante solicitação explícita.

Quando a aceitação da atualização for solicitada, use uma versão anterior da aplicação para verificar a nova publicação. Confirme que as verificações automáticas e manuais a partir de uma saída pública `CN` consultam o feed Gitee selecionado primeiro e tentam GitHub uma vez, enquanto outras saídas consultam GitHub primeiro e tentam Gitee uma vez. Verifique se Sparkle instala e reinicia o ZIP da arquitetura em execução, mantendo uma instalação de arquitetura única nessa arquitetura. Teste as mudanças Release→Preview e Preview→Release, além das atualizações no mesmo canal. As verificações não solicitadas são registradas como `Not verified` e não são pré-requisitos para concluir a publicação.

## 4. Sincronizar o cask Homebrew

Uma publicação estável termina no Homebrew. As versões Preview param antes desta etapa: o tap oferece apenas versões estáveis, portanto `brew upgrade` nunca leva o usuário a uma pré-publicação.

Depois de publicar os artefatos, execute a partir da raiz do repositório:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

O script reescreve `version` e os dois valores `sha256` em `Casks/zisla.rb`, lendo cada resumo de `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` e do arquivo correspondente `x86_64` quando eles existem, ou dos artefatos publicados no GitHub caso contrário. O cask resolve `#{arch}` para cada máquina, de modo que Apple Silicon e Intel baixam somente sua variante; a verificação rejeita um cask que reutiliza o mesmo resumo para ambas. O script recusa gravar um cask que falhe em `homebrew-cask.rb verify` e depois espelha o arquivo em `wzz6423/homebrew-tap`. Omita `PUBLISH_TAP` para uma simulação que atualiza apenas o cask dentro do repositório.

O cask declara `auto_updates true` porque Sparkle gerencia as atualizações: `brew upgrade` só substitui a aplicação quando o pacote instalado é realmente anterior à versão do tap, decisão que Homebrew 5.1.6 ou posterior toma lendo a versão dentro da aplicação. `brew upgrade --cask zisla` e `--greedy` usam os registros de instalação do Homebrew e podem desfazer uma atualização Sparkle ao reinstalar a versão do tap. Faça commit do cask reescrito junto com o aumento de `latestRelease` no site; CI falha quando os dois fixam versões diferentes. Valide o cask e os metadados do site a partir da raiz:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

As verificações de aceitação de download, instalação, atualização e `livecheck` do Homebrew só são executadas mediante solicitação explícita. Exemplo de aceitação da instalação:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

As verificações de aceitação Homebrew não solicitadas são registradas como `Not verified` e não são pré-requisitos para concluir uma publicação.
