# Diseño de firmas y publicaciones

**Español** | [Idiomas de la documentación](../../../README.md)

El proceso completo de publicación, canales dobles y sincronización GitHub/Gitee se mantiene en [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Esta página solo documenta restricciones de firma, notarización y paquetes; sigue el skill al publicar.

Ambos canales usan Sparkle para verificar ZIP y appcast firmados antes de sustituir y reiniciar. La aplicación resuelve una vez por ejecución el país de salida pública: `CN` consulta Gitee y reintenta GitHub exactamente una vez; otros países GitHub y Gitee una vez, y si no hay consulta se mantiene Gitee primero. `package-release.sh` exige `SPARKLE_GENERATE_APPCAST` apuntando a `generate_appcast` de Sparkle 2.9.4 y escribe `appcast-gitee.xml` y `appcast-github.xml` junto a ZIP y DMG. Cada appcast se firma independientemente y apunta al ZIP de esa ejecución en su propio sitio. `build-package.sh` ejecuta por arquitectura, generando tres pares: universal como `appcast.xml`, nombre solicitado por versiones anteriores a actualizaciones por arquitectura, y pares únicos como `appcast-arm64.xml` y `appcast-x86_64.xml`. La instalación única reescribe el feed de Info.plist para su variante en ejecución, x86_64 traducida solicita `arm64`, y conserva su arquitectura sin convertirse en universal. Universal cuenta sus variantes y mantiene nombre compartido y formato universal. Gitee conserva `update-release` para Release y `preview` para Preview; GitHub usa `latest` y prerelease permanente `preview`. Define `SPARKLE_ED_KEY_FILE` a la clave EdDSA privada para publicar sin interacción, o no lo definas para usar `zisla-update-ed25519` del llavero de inicio. La clave privada nunca entra al repositorio. Estables usan por defecto un certificado autofirmado para mantener requisito designado y permisos tras actualizar; siguen sin notarizar. Los paquetes Developer ID deben notarizarse; Preview ad hoc gratuitas tampoco pueden notarizarse.

## Requisitos previos

- Identidad `zisla Release Signing` en el llavero dedicado o certificado Developer ID Application
- Credenciales de notarización Apple al usar Developer ID
- Auxiliar oficial `yt-dlp` obtenido y verificado por `Scripts/fetch-yt-dlp.sh`

## 1. Compilar una aplicación firmada

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Para estable, el script usa `RELEASE_SIGNING_MODE=selfsigned`, lee `zisla Release Signing` en `~/Library/Keychains/zisla-release-signing.keychain-db` y desbloquea con `dev.wzz.zisla.release-signing-keychain` del llavero de inicio. No elimina la advertencia inicial Gatekeeper, pero mantiene requisito de certificado en lugar de cdhash específico de compilación.

Con certificado Developer ID elige explícitamente la ruta notarizable:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Salida:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Distribución gratuita de Preview

Sin Apple Developer Program, compila Preview firmada ad hoc:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

No se notariza ni incluye autorización WeatherKit. Tras publicar appcast firmado en Preview permanente, Sparkle comprueba, descarga, verifica, instala y reinicia actualizaciones Preview. El primer inicio puede exigir **Ajustes del Sistema > Privacidad y seguridad > Abrir igualmente**. Developer ID y notarización siguen recomendados para distribuir sin avisos de seguridad.

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

## 3. Publicar y verificar

Sube ZIP, DMG, sumas y appcasts GitHub al mismo tag versionado, llamados `appcast.xml` universal, `appcast-arm64.xml` y `appcast-x86_64.xml`; sube recursos y appcasts Gitee equivalentes con esos tres nombres al mismo tag Gitee. Estables no se marcan prerelease. Copia los tres appcasts Gitee a `update-release`; Preview a `preview` permanente en ambos. El canal consulta Gitee→GitHub para `CN`, GitHub→Gitee para otros.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Las publicaciones habituales conservan controles locales de artefactos, firmas, sumas, diseño de paquete y appcast, verificaciones de ambos sitios y feeds permanentes y validación de metadatos. Descargar de nuevo, comprobar instalación y aceptar actualización real Sparkle solo se hace si se solicita explícitamente.

Si se solicita aceptación, usa una versión anterior para comprobar la nueva. Confirma que consultas automáticas y manuales desde salida pública `CN` usan Gitee elegido y reintentan GitHub una vez, y otras salidas GitHub y Gitee una vez. Verifica instalación y reinicio del ZIP de la arquitectura actual y que una instalación única siga única. Prueba Release→Preview, Preview→Release y mismo canal. Controles no pedidos se registran `Not verified` y no son prerrequisitos para completar publicación.

## 4. Sincronizar cask Homebrew

Una estable termina en Homebrew. Preview se detiene antes: tap solo sirve estables, por lo que `brew upgrade` no lleva a prerelease.

Desde raíz tras publicar recursos:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

El script reescribe `version` y dos `sha256` en `Casks/zisla.rb`, leyendo `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` y su equivalente `x86_64` si existen, o recursos GitHub publicados si no. El cask resuelve `#{arch}` por máquina; Apple Silicon e Intel descargan su variante, y verificación rechaza digest idéntico para ambas. No escribe cask si falla `homebrew-cask.rb verify`; después lo refleja en `wzz6423/homebrew-tap`. Omite `PUBLISH_TAP` para simulación que solo actualiza cask local.

El cask declara `auto_updates true` porque Sparkle gestiona actualización: `brew upgrade` sustituye solo si el paquete instalado es realmente anterior al tap, leyendo versión interna desde Homebrew 5.1.6. `brew upgrade --cask zisla` y `--greedy` usan registros de instalación y pueden deshacer Sparkle reinstalando tap. Haz commit del cask reescrito junto con el aumento de `latestRelease` del sitio; CI falla si difieren versiones. Valida cask y metadatos desde raíz:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Aceptación Homebrew de descarga, instalación, actualización y `livecheck` solo bajo solicitud explícita. Ejemplo de instalación:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Controles Homebrew no solicitados se registran `Not verified` y no son prerrequisitos para completar publicación.
