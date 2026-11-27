# zisla voor macOS

**Nederlands** | [English](../../../../mac/README.md) | [简体中文](../../../../mac/README.zh-CN.md) | [Andere talen](../../README.md)

Deze map bevat de macOS-implementatie van zisla. Beweeg naar het midden van de bovenrand om het eiland te openen en weg om het te verbergen. AppKit `NSPanel`, SwiftUI en gebeurtenisgestuurde diensten vermijden een permanent transparant raakvenster en een renderlus in verborgen toestand.

Swift-targets, bundle-ID, lokale gegevensmap en `zislactl` gebruiken de zisla-identificatie. Updates migreren gegevens en voorkeuren uit eerdere versies automatisch.

macOS 14 en later zijn ondersteund. macOS 26 gebruikt Liquid Glass; macOS 14/15 gebruiken het native systeemmateriaal.

## Functies

### 12 eilandmodules

| Module | Geïmplementeerde mogelijkheden |
| --- | --- |
| Home | Bundelt op aanvraag huidige Pomodoro, eerste actieve AI-taak, native downloads en voortgang van meerdere browserdownloads. |
| Toetsenbordgeluiden en statistieken | 20 ingebouwde klanken; lokale typstatistieken zijn apart schakelbaar, met trends, app-tijdlijn en kaart per toets. |
| Overdracht | Sleep bestanden, media of links naar boven om ze te bewaren, in Finder te tonen of te delen. Bewaarde schermafbeeldingen hebben blauwe dubbelbrede kaarten en een eigen categorie voor kopiëren, PNG-export en verwijderen. Comprimeer geselecteerde bestanden/mappen naar ZIP, wijzig of converteer afbeeldingen met Afbeeldingstools en stuur geslaagde resultaten terug. Importeer afbeeldingen, video en audio in de opnamebibliotheek met behoud van huidig project en tijdlijn. |
| Klembord | Doorzoekbare lokale geschiedenis, filters voor afbeelding, URL en bestand en favorieten; geschiedenis en linkdetectie hebben aparte schakelaars. Nieuwe afbeeldingen krijgen lokale tekstherkenning: vind het origineel via tekst of klik rechts voor herkennen/kopiëren. Lopende herkenning is annuleerbaar; achtergrondherkenning kopieert niet automatisch. |
| AI-monitor | Verzamelt taken, status, tokentrends, bijdragekaarten en zijmeldingen uit ondersteunde CLI's, desktopapps en IDE's. |
| Downloads | `yt-dlp` voor video/audio; zonder `ffmpeg` verpakt AVFoundation compatibele sporen en is een alleen-lezen Bilibili-alternatief beschikbaar. |
| Agenda | Weer voor huidige en maximaal zes opgeslagen locaties; afspraken en herinneringen bekijken, maken, verwijderen en herinneringen voltooien. Het tijdstip van de weerupdate staat in de kop, links van de vernieuwknop. |
| Mail | Geselecteerde Mail.app-accounts voor inbox, gelezen markeren, antwoorden, schrijven en naar prullenmand verplaatsen. |
| Notities | Apple Notities is de enige bron voor Markdown-notities bekijken, bewerken, maken en verwijderen, met voorvertoning en automatisch terugschrijven. |
| Appvolumemixer | Volume en dempen per spelende app op macOS 14.4+, met onthouden volume; vereist Systeemaudio-opname. |
| Hulpprogramma's | Pomodoro met één signaal en lokale melding, wakker houden, inactieve sluimerstand voorkomen, scherm/toetsenbordreiniging, teleprompter, cameraspiegel en bevestigd legen van prullenmand. De timernaam geldt alleen voor de huidige sessie en keert terug naar de standaardnaam na afloop of annulering. |
| Systeem | CPU, GPU, geheugen, schijf, netwerk, temperatuur, ventilatoren, geheugen vrijmaken en veilige caches/logs/tijdelijke gegevens scannen; batterijgezondheid en accessoireniveaus. |

### Functies over modules heen

- **Nu afgespeeld:** MediaRemote toont hoes, titel, voortgang, scrollende tekst en bediening; Core Audio vindt de werkelijke bronapp als alternatief. Gepauzeerde, gestopte en gedempte bronnen zijn verborgen.
- **Browserdownloads:** bron en voortgang voor Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera en Arc in Home, ingeklapte toestand en zijmeldingen.
- **Spraakinvoer:** schakelen of ingedrukt praten, eigen globale sneltoetsen, systeemspraakherkenning, lokale/externe tekstverwerking en lokale opnamegeschiedenis.
- **Snelle acties:** na kopiëren toont een kleine eilandmelding voorvertoning en acties voor links openen, Finder, zoeken met gekozen zoekmachine, vertalen, rekenen, agenda uit datums en lange tekst/afbeeldingen opslaan. Na browserdownload of AirDrop opent dezelfde toets de map, onafhankelijk van de voortgangschakelaar. Herkent URL's, paden, mail, telefoon, CSS-kleuren met voorbeelden, sommen, datum/tijd, tekst in andere taal, code, tekst met tellingen, afbeeldingen met miniaturen en bestandsverwijzingen. Toegang via knoppen, aanvullende standaard `Command+N` of ingestelde modificatietoets/muiszijtoets. Optioneel links vasthouden plus rechts klikken kopieert, standaard uit; appuitsluitingen, typen en lichte herinneringsmodus zijn instelbaar.
- **CLI en Skills:** detecteren, installeren, bijwerken, verwijderen en lokale Skills beheren in Instellingen.
- **Desktophuisdieren:** ingebouwde of geïmporteerde dieren aan één van beide kanten.
- **Updates:** Release/Preview vraagt eenmaal per start de openbare landcode. `CN` controleert ondertekende Gitee-feed en probeert eenmaal GitHub; andere landen andersom. Fout behoudt Gitee eerst. Sparkle downloadt, verifieert, installeert en herstart. Kanaal geldt voor automatische/handmatige checks.
- **Uiterlijk en bediening:** systeem/licht/donker, transparant/mat, vastgezet uitklappen, meerdere schermen, Spaces en externe schermen zonder notch.
- **Standaarden:** nieuwe installaties activeren modules. Functie, compacte indicator, zijmelding, menubalkstatistiek en updategedrag zijn apart instelbaar; bestaande configuraties blijven behouden.

### Afzonderlijk gereedschap en werkstromen

- **Opnamestudio:** open via menubalk of Instellingen. Neem scherm, venster of gebied met optionele systeemaudio, microfoon en camera op. Bewerk video, audio, afbeeldingen en tekst op meerdere sporen met ondertitels, zoom, animaties en portret-/stemeffecten. Bekijk en exporteer video, GIF, Live Photo of audio. Sommige formaten vereisen FFmpeg; HDR hangt van hardware af. Importeer plankmedia in de bibliotheek met behoud van project en tijdlijn.
- **Afbeelding-, audio- en PDF-tools:** via Instellingen. Afbeeldingen bieden 9 lokale bewerkingen en batch/ZIP-export. Audio biedt 27 bewerkingen, waaronder mixen, LUFS-normalisatie en ruisverwerking, en vereist FFmpeg/ffprobe. PDF biedt 14 bewerkingen; Office-conversie vereist LibreOffice/OpenOffice.
- **Dagoverzicht:** kies uit 8 sjablonen en statistieken, bekijk voorvertoning en exporteer PNG handmatig of dagelijks. Ontbrekende gegevens worden geen gemeten nul.
- **Venstervoorbeelden:** wijs Dock aan of gebruik Command+Tab en klik een voorbeeld om het venster te activeren. Beheer functie en rechten in Instellingen.
- **Contextnotities en vergaderingen:** houd de ingestelde toets vast en schud voor een notitie bij pagina, venster of desktop. Afspraken met vergaderlink tonen 10 minuten aftelling, deelnemen en nieuwe/bestaande notities koppelen. Beheer ze op de plank.
- **Schudden om neer te zetten:** schud tijdens slepen om een bestemming te tonen; apart instelbaar.
- **Uitvoer en speler:** kies apparaat in het mediagebied, automatische bron/voorkeurspeler, compacte weergave en stopvoorwaarden voor omgevingsgeluiden in Instellingen.
- **AI-tegoeden en resets:** accounttegoeden, meet- en resetmomenten en waarschuwingen, inclusief beschikbare 5h/7d-vensters en Cursor USD-budgetten. Los van lokale tokengeschiedenis. De Gemini- en Claude/GPT-tegoeden van Antigravity hebben afzonderlijke bewaking, weergave en meldingen. Gemini App gebruikt voor chattegoeden een web-Cookie van hetzelfde Google-account; Gemini CLI blijft apart.

### Toetsvolgorde van Snelle acties

De popup gebruikt `Command+1`…`Command+9` en `Command+0` in actievolgorde. Nieuwe configuraties krijgen aanvullend `Command+N` voor de eerste actie; `Command+Delete` sluit. Stel toets, muiszijtoets en volgorde in. Elke expliciet opgeslagen combinatie blijft bij updates behouden, ook oude `Command+1`, eigen toetsen en gewiste triggers. Alleen nieuw of ontbrekend triggerveld neemt N over.

### Opslaglocaties

Instellingen → Opslaglocatie biedt afzonderlijke mappen voor downloads, schermafbeeldingen, afbeeldingstools, opnames, PDF, Snelle acties en dagoverzicht. Nieuwe configuraties gebruiken `~/Downloads` met `picture`, `video`, `pdf`, `quick`, `daily`. Audiotools kiezen bestand/map met exportdialoog. De plank bewaart verwijzingen naar originelen; schermafbeeldingen en contextnotities onder `~/Library/Application Support/zisla`, projecten in de opnamemap en Snelle notities in Apple Notities.

[Gebruikershulp](https://wzz6423.github.io/zisla/help.html?lang=nl#help) biedt negen gidsen met stappen en korte films: klembord, vastleggen, plank, vergaderingen, AI, mediatools, dagoverzicht, desktopnotities/venstervoorbeelden en afspelen/mixen.

### Schermafbeeldingstoetsen en bewaren

**Bewaren** staat tussen **Vastzetten** en **Kopiëren**. Het bewaart het eindbeeld met annotaties en voltooide scrollopnames op de plank zonder te kopiëren. PNG en metadata, waaronder bronapp en tijd, staan lokaal in SQLite en overleven herstart. De aparte categorie bevat alleen deze kaarten.

**Markeerstift** volgt **Penseel** en tekent transparante markering, met eindlijnen en cirkelmarkeringen standaard aan en uitzetbaar in het menu. **Uitsnijden** volgt **Vervagen** en ondersteunt macOS-onderwerp/achtergrondextractie en vrije selectie. Meerdere lussen worden samengevoegd; Alles selecteren/Wissen, transparantie buiten selectie en ongedaan maken zijn beschikbaar. Hoekradius begint op 0; handgreep of schuifregelaar verandert hem, de badge toont `r`, PNG-hoeken zijn transparant en terug naar 0 herstelt originelen.

| Context | Actie | Standaardtoets |
| --- | --- | --- |
| Globaal | Schermafbeelding | `Control+1` |
| Globaal | Scrollende schermafbeelding | `Control+2` |
| Editor | Vastzetten | `Control+1` |
| Editor | Bewaren | `Control+2` |
| Editor | Rechthoek | `Control+3` |
| Editor | Ellips | `Control+4` |
| Editor | Penseel | `Control+5` |
| Editor | Markeerstift | `Control+6` |
| Editor | Pijl | `Control+7` |
| Editor | Nummer | `Control+8` |
| Editor | Tekst | `Control+9` |
| Editor | Vervagen | `Control+0` |
| Editor | Uitsnijden | `Control+A` |
| Editor | Scrollopname | `Control+B` |
| Editor | Kopiëren | `Enter` |
| Editor | Opslaan | `Command+S` |
| Editor | Ongedaan maken | `Command+Z` |
| Editor | Opnieuw | `Command+Shift+Z` |

Instellingen tonen en registreren globale/editor-toetsen. Kopiëren, Opslaan, Ongedaan en Opnieuw zijn alleen zichtbaar. Gebruikerstoetsen blijven bij update behouden; Vastzetten is een editoractie, geen aparte globale toets, met behoud van menu-ingang.

Standaarden volgen de werkbalk: `Control+1`…`Control+9`, `Control+0`, `Control+A`, `Control+B`, daarna letters. `Q`, `M`, `N`, `W` worden overgeslagen omdat per ongeluk Command afsluiten, minimaliseren, nieuw venster of sluiten kan activeren. Eigen combinaties zijn toegestaan.

Onaangepaste oude indelingen, ook Vastzetten/Bewaren, gaan eenmaal naar nieuwe standaarden. Zodra een screenshottoets aangepast is blijft de indeling staan; nieuwe acties bij conflict nemen een vrije Control-combinatie in dezelfde veilige volgorde. Ook deze zijn opnieuw opneembaar.

## Snel starten

### Omgeving

- macOS 14+
- Swift 6 / Xcode 16+, alleen Command Line Tools kunnen ook bouwen
- Optioneel `yt-dlp`/`ffmpeg`; Office-PDF vereist LibreOffice/OpenOffice

Met Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Uit bron draaien

```bash
swift run zisla
```

Start als menubalkaccessoire. Beweeg binnen de bovenste centrale 6 px van het huidige scherm of kies “Toon eiland” in het menu.

### Een `.app` bouwen

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Officiële `yt-dlp`-helper verpakken:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` haalt een vastgelegde officiële standalone macOS-versie op en controleert de officiële `SHA2-256SUMS` voordat die in `Tools/yt-dlp` komt.

## AI-integratie

### Automatisch detecteren

zisla leest openbare of stabiele lokale sessiestatus en alleen gestructureerde gebeurtenissen/metadata die nodig zijn voor taakstatus. Geen prompts of antwoordteksten.

| Omgeving | Detectie |
| --- | --- |
| OpenAI / Anthropic | Codex CLI/Desktop, Claude Code en hun hosts |
| GitHub / Google / xAI | Copilot CLI/VS Code, Gemini CLI/Desktop en Grok CLI |
| Onafhankelijke/regionale tools | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop/CLI, TRAE, OpenCode, Harnext/Harness en WorkBuddy |

Wachten op goedkeuring/antwoord is geel, tool-/opdrachtfouten rood en normaal werk groen. Bronnen worden in rood/geel/groen gegroepeerd. Qwen-sidecar is alleen actief bij levende PID, zodat na afsluiten geen oude activiteit resteert.

Een chatdesktopapp zonder gestructureerde gebeurtenissen onderscheidt open maar inactief niet betrouwbaar van genereren. Gebruik voor zulke tools, waaronder ChatGPT, de `zislactl`-hook; een blijvend proces wordt niet als activiteit verzonnen.

### Lokaal `zislactl`-protocol

`zislactl` schrijft taakstatus en gebruik in SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

Gebruiksgeschiedenis overleeft herstart, vervangende updates en wissen van taken; alleen handmatig verwijderen van appgegevens verwijdert haar.

Voorbeeld:

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

Canonieke providers: `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness`, `doubao`. Aliassen worden automatisch genormaliseerd. Aanroep vanuit hook, shellwrapper of script.

AI-lijst en compacte status gebruiken officiële bronlogo's. Zie de [CLI-referentie](Docs/cli-reference.md).

## Browserdownloadvoortgang

zisla volgt openbare macOS-bestandsvoortgang in Downloads en combineert tijdelijke extensies, uitgebreide bronattributen en draaiende browsers. Geen browsergeschiedenis of netwerkopvragen om voortgang te bepalen. De afronding blijft ongeveer drie seconden. Snelle acties gebruiken dezelfde bron en bieden Map openen nadat overdracht de eindlocatie bereikt. De meldingduur volgt Instellingen; de laatste kopie of overdracht vervangt de vorige.

## Downloader

Volgorde van uitvoerbare bestanden:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

URL gaat als apart argv naar `Process`, zonder shell. Runtimeconfiguratie/plugins worden genegeerd, `--exec` staat uit, één-itemlimieten gelden en het eindbestand wordt binnen de toegestane map gecontroleerd.

Zonder `ffmpeg`:

- Video: voorkeur AVC/MP4 en M4A, AVFoundation verpakt in MP4; enkelbestand blijft ongewijzigd.
- Audio: voorkeur M4A, anders origineel formaat.
- Bij HTTP 412, ontbrekend formaat of ontbrekende yt-dlp gebruikt Bilibili alleen-lezen API voor DASH en dezelfde native verpakking, zonder extra installatie.

## Notities

Markdown gebruikt alleen Apple Notities als bron. Maken, lezen, bewerken en verwijderen, niet alleen toevoegen.

- **Lijst:** JXA (`osascript -l JavaScript`) leest titels en wijzigingsmomenten van niet-verwijderde notities en sorteert nieuwst eerst. Terugkeer uit Notities ververst; Recent verwijderd is verborgen. Selecteer voor bewerken, vernieuwen, maken of verwijderen via contextmenu.
- **Lezen/bewerken:** AppleScript leest `plaintext`, de Markdown-bron. `TextEditor` schrijft na circa 0,8 s inactiviteit terug om niet bij elke toets een AppleScript-call te doen. Nieuwe notities worden in Apple Notities gemaakt en geselecteerd.
- **Voorvertoning:** blokparser voor koppen, ongenummerde/genummerde/takenlijsten, citaten, codeblokken, lijnen, vet, cursief, inlinecode, doorhalen en links als `AttributedString`.
- **Opslag:** gewone tekst in `body`, HTML-escaping en lege regels behouden. `plaintext` herstelt bron; Apple Notities toont tekst, geen gerenderde Markdown.
- **Rechten:** eerste lezen/schrijven vraagt Automatisering voor Notities; weigeren levert melding uit lijst/editor.

Geen tweede lokale kopie; Apple Notities is opslagbackend.

## Rechten en privacy

- **Agenda:** agenda- en herinneringsrechten apart bij eerste bezoek; na maken, verwijderen of voltooien verversen ze.
- **Locatie:** weer vraagt eenmalig positie, geen tracking; andere locaties zoek, bewaar en verwijder je in Instellingen.
- **Bestanden/downloads:** gekozen mappen via security-scoped bookmarks; overdracht kopieert origineel niet.
- **Klembord:** nieuwe installatie activeert geschiedenis en links afzonderlijk. Per `changeCount` maximaal één lokale link; query's worden niet gelogd en geen clear-, type- of schrijf-API gebruikt, zodat Universal Clipboard intact blijft.
- **Snelle acties:** lokaal per `changeCount` wanneer aan, plus downloads/AirDrop. Modificatietoets/muis kan Invoercontrole vragen; kopiegebaar plaatst synthetische ⌘C en vereist Toegankelijkheid. Herkenning offline; openen, zoeken, vertalen, opslaan na expliciete actie. Appuitsluiting en typen sturen kopiemeldingen; algemene schakelaar stuurt ook overdrachtmeldingen.
- **AI-status:** alleen noodzakelijke gestructureerde gebeurtenissen en lokale metadata.
- **Spraak:** microfoon/herkenning pas na actie. Opname, ruwe en bewerkte tekst lokaal; tekst alleen naar gekozen model/provider/CLI en externe inloggegevens in privédatabase.
- **Bluetooth/apparaten:** openbare accessoire- en vertrouwde Apple-mobiele batterijgegevens alleen bij Systeem-batterijweergave.
- **Camera/input:** spiegel en studiovoorvertoning/opname vragen Camera. Toetsgeluid, statistiek, reinigen en modificatie/muis gebruiken Invoercontrole; statistieken lokaal, schakelaars apart.
- **Scherm/audio:** screenshot, opname, venstervoorbeelden met Schermopname. Opname bewaart gekozen bronnen lokaal; microfoon/camera alleen voor aanstaande bronnen. Mixer vereist macOS 14.4+ en Systeemaudio-opname met lokale Core Audio-taps.
- **Browser:** alleen openbare voortgang en tijdelijke files; geen geschiedenis of pagina-inhoud.
- **Media:** MediaRemote-metadata en Core Audio-uitvoer. MediaRemote is privaat, dus huidige build niet rechtstreeks geschikt voor Mac App Store; ontbrekende metadata vallen terug op actieve bronapp.
- **Netwerk:** Open-Meteo en openbare Chinese waarschuwingen waar relevant, elders bij voorkeur WeatherKit. `ipinfo.io/country` eenmaal per start: `CN` Gitee/GitHub, elders omgekeerd, fout Gitee eerst. Bilibili alleen-lezen video/playback/CDN; klembordlinkherkenning offline. Actieve accountcontroles benaderen providers; vertaling, AI-opnamebewerking en transcriptieopschoning gekozen model/CLI. Apple-spraak kan netwerk gebruiken naar systeem/taal. Installatie/update afhankelijkheden/CLI, openbaar IP en gekozen netwerkacties doen verzoeken.
- **Automatisering:** AppleScript/JXA voor lijst, lezen, bewerken, maken, verwijderen van Apple Notities; vraagt toestemming, geen netwerk, opslag in Notities.

## Tests

Volledig Xcode:

```bash
swift test
```

Alleen Command Line Tools:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Documentatie

- [Architectuur en prestaties](Docs/architecture.md)
- [CLI-referentie](Docs/cli-reference.md)
- [Ondertekenen en releases](Docs/releasing.md)
- [Meegeleverde afhankelijkheden](../../../../mac/Vendor/README.md)
- [Derdenverklaringen](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Systeemgrenzen

- Geen publieke Dynamic Island-API; fysieke notch uit `safeAreaInsets` en bovenste hulpgebied, andere schermen dezelfde overlay.
- DRM, login, toegangsscherm en sommige exclusieve schermvullende apps kunnen media of overlay blokkeren.
- Apps zonder mediacenterintegratie kunnen bron tonen, geen titel/hoes/voortgang garanderen; gepauzeerde/gestopte/gedempte video bewust verborgen.
- Browser moet openbare voortgang of herkenbare tijdelijke Downloads-bestanden gebruiken voor percentages.
- Batterij, temperatuur, vermogen en accessoires hangen af van hardware, verbinding en macOS-data; ontbrekend is niet beschikbaar.
- Office-PDF vereist LibreOffice/OpenOffice; overige PDF-bewerkingen lokaal.
- Niet-genotariseerde pakketten vragen mogelijk **Open toch**. Stabiele releases houden één zelfondertekend certificaat voor blijvende rechten; Sparkle controleert updates apart met ingebouwde EdDSA-sleutel vóór uitpakken, vervangen en herstarten.

## Licentie

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Niet-commercieel gebruik toegestaan, verkoop/overig commercieel niet.
