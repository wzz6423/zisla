# zisla

**Nederlands** | [English](../../../README.md) | [简体中文](../../../README.zh-CN.md) | [Andere talen](../README.md)

**zisla is een native macOS-werkplek die verschijnt wanneer je haar nodig hebt en daarna uit beeld gaat.** Beweeg de aanwijzer naar het midden van de bovenrand om één lichte toegang te openen voor AI-werk, media, bestandsoverdracht, downloads en desktopgereedschap. Schermen zonder notch gebruiken hetzelfde nagebootste statusgebied.

De huidige implementatie vereist **macOS 14+**. Apple Silicon is de ondersteunde configuratie; Intel-releasepakketten kunnen werken, maar compatibiliteit is niet gegarandeerd.

[Bekijk de volledige rondleiding — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Bekijk de introductiefilm van zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Muziek: “Funkorama” van Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Bron](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Waarom het bovenaan je scherm past

- **Op aanvraag, zonder de focus over te nemen.** Klap het eiland uit vanaf de bovenrand, zet het zo nodig vast en werk verder in je huidige app.
- **Eén plek voor lopend werk.** Bekijk afspelen, AI-taken, downloads, timers, mail, systeemstatus en batterijgegevens zonder een volledig dashboard te openen.
- **AI-activiteit zonder gesprekken te lezen.** zisla leest alleen gestructureerde gebeurtenissen en lokale activiteitsmetadata die nodig zijn om de taakstatus te bepalen. Het leest nooit prompts of antwoordteksten.
- **Lokale bediening.** Modules, klembordgeschiedenis en linkdetectie hebben onafhankelijke schakelaars; rechten worden pas gevraagd wanneer een functie voor het eerst wordt gebruikt.

## Wat het kan

### Desktopwerk voortzetten

| Mogelijkheid | Werking |
| --- | --- |
| Nu afgespeeld | Toont hoes, titel, voortgang, songteksten en afspeelknoppen; Core Audio kan de app vinden die werkelijk geluid uitvoert wanneer metadata ontbreken. |
| Overdracht en delen | Sleep bestanden, media of links naar het bovenste activeringsgebied om ze in de overdrachtsbak te bewaren, in Finder te tonen of het macOS-deelmenu te openen. Comprimeer geselecteerde bestanden en mappen naar ZIP, wijzig of converteer afbeeldingen met Afbeeldingstools en stuur geslaagde resultaten terug naar de bak, of importeer afbeeldingen, video en audio in de opnamebibliotheek terwijl het huidige project en de tijdlijn behouden blijven. |
| Klembord en meldingen | Slaat optioneel lokale klembordgeschiedenis op, herkent nieuwe links op het apparaat en toont media, AI-activiteit, browserdownloads, timers, mail en updates in de ingeklapte weergave. Optionele Snelle acties tonen na elke kopie een kleine eilandmelding met een rijke voorvertoning en passende vervolgacties: openen, tonen in Finder, zoeken, vertalen, rekenen en opslaan. Na een browserdownload of ontvangen AirDrop-bestand kan dezelfde sneltoets de bijbehorende map openen. Nieuwe afbeeldingen in de geschiedenis worden ingepland voor tekstherkenning op het apparaat; zoek hun tekst om het origineel te vinden of klik met rechts om de tekst te herkennen of kopiëren. |
| Dagelijkse werkplek | Bevat weer, agenda, herinneringen, Mail.app, Markdown-notities met Apple Notities als opslag, informatie op het toegangsscherm en optionele desktophuisdieren. |

### AI-werk zichtbaar maken

zisla volgt lokale activiteit van Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI en andere ondersteunde bronnen. Het toont taken, status, tokentrends, bijdragekaarten en zijmeldingen.

Voor gereedschap zonder stabiele lokale activiteitsbron kunnen scripts, CI en hooks met `zislactl` voortgang, gebruik en meldingen doorgeven. De protocolstatus blijft op deze Mac. Instellingen kunnen ook veelgebruikte AI-CLI's detecteren, installeren, bijwerken en verwijderen en lokale Skills beheren. De [CLI-integratiereferentie](mac/Docs/cli-reference.md) beschrijft providers en opdrachten.

### Handige kleine taken uitvoeren

| Gebied | Inbegrepen gereedschap |
| --- | --- |
| Downloads en documenten | Video en audio downloaden via `yt-dlp`; lokaal PDF's samenvoegen, splitsen, draaien, bijsnijden, converteren en renderen, tekst exporteren, watermerken, paginanummers, versleuteling, ontgrendeling en metadata bewerken. |
| Focus en presenteren | Pomodoro met één geluidssignaal en een lokale melding aan het einde van een sessie, wakker houden, inactieve sluimerstand voorkomen, scherm- en toetsenbordreiniging, teleprompter en cameraspiegel. |
| Systeem en batterij | CPU-, GPU-, geheugen-, schijf-, netwerk-, ventilator- en batterijgegevens en het opruimen van veilig verwijderbare caches en logs. |
| Spraakinvoer | Globale sneltoetsen voor opnemen en transcriberen, optionele lokale of externe verwerking van transcripties en lokale spraakgeschiedenis. |

### Huidige toegangen en werkstromen

Het eiland heeft 12 modules: Home, Overdracht, Klembord, AI-monitor, Toetsenbordgeluiden, Downloads, Agenda, Mail, Notities, Applicatievolumemixer, Hulpprogramma's en Systeem. Batterijgegevens staan onder Systeem; de toegangsschermweergave is apart. Open PDF-, afbeelding- en audiotools via Instellingen; open de opnamestudio via Instellingen of de menubalk.

- **Opnemen en maken:** neem een scherm, venster of gebied op met optioneel systeemgeluid, microfoon en camera. Bewerk ondertitels, zoom en portret- en stemeffecten over meerdere sporen, bekijk de voorvertoning en exporteer video, GIF, Live Photo of audio. Afbeeldingstools bieden 9 lokale bewerkingen; audiotools bieden er 27.
- **Mixen en afspelen:** macOS 14.4+ ondersteunt volume en dempen per app. Kies audio-uitvoer in het mediagebied en spelerinstellingen in Instellingen.
- **Desktop en vergaderingen:** venstervoorbeelden via Dock en Command+Tab, contextnotities voor webpagina's, vensters en desktop, een aftelling van 10 minuten voor vergaderingen, deelnemen en gekoppelde notities. Schud tijdens het slepen van bestanden om de plankbestemming te tonen.
- **Dagoverzicht:** 8 sjablonen, voorvertoning, handmatige of geplande PNG-export, geselecteerde statistieken en een afzonderlijke opslagmap.
- **AI-accounts:** bekijk ondersteunde accounttegoeden, resetmomenten, waarschuwingen bij laag tegoed en meetmomenten; exporteer lokale tokengeschiedenis als `.xlsx`. De Gemini- en Claude/GPT-tegoeden van Antigravity hebben afzonderlijke bewaking, weergave en meldingen. Gemini App gebruikt voor chattegoeden een web-Cookie van hetzelfde Google-account; Gemini CLI blijft apart.
- **Snelle acties:** popupacties gebruiken `Command+1` tot en met `Command+0` in volgorde. De aanvullende standaardsneltoets voor nieuwe configuraties is `Command+N` voor de eerste actie. Updates behouden opgeslagen en gewiste sneltoetsen.

De [gebruikershulp](https://wzz6423.github.io/zisla/help.html?lang=nl#help) bevat negen stapsgewijze gidsen: klembord, schermafbeeldingen/opnames, plank, vergaderingen, AI, mediatools, dagoverzichten, desktopnotities/venstervoorbeelden en afspelen/mixen. De [macOS-gids](mac/README.md#opslaglocaties) beschrijft uitvoermappen en afhankelijkheden.

## Aan de slag

### De app installeren

Download de nieuwste DMG van [GitHub Releases](https://github.com/wzz6423/zisla/releases) of [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), koppel die en sleep `zisla.app` naar `Applications`.

Installeren kan ook met Homebrew:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew haalt de build voor je chip op: Apple Silicon- en Intel-Macs downloaden alleen hun eigen architectuur. De cask komt van de externe tap `wzz6423/tap`, niet uit Homebrew's officiële caskrepository; installeren betekent deze tap vertrouwen.

Beweeg na starten de aanwijzer naar het midden van de bovenrand van het huidige scherm of kies **Toon eiland** bij het menubalkpictogram. Pakketten zijn niet door Apple genotariseerd; bij de eerste start moet je daarom, ongeacht de installatiemethode, **Open toch** kiezen in **Systeeminstellingen > Privacy en beveiliging** of zelf de quarantainemarkering verwijderen:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### De app bijwerken

zisla werkt zichzelf bij via Sparkle, ongeacht hoe het is geïnstalleerd. Bij Homebrew vervangt `brew upgrade` de app alleen als de geïnstalleerde versie werkelijk ouder is dan de versie in de tap: Homebrew 5.1.6 en later lezen de versie uit de appbundle. Zo wordt een Sparkle-update niet overschreven en blijft een oude installatie niet achter. Als je de cask expliciet noemt, gebruikt Homebrew zijn installatieregistratie en kan het een door Sparkle bijgewerkte app terugzetten naar de tapversie:

```bash
brew upgrade --cask zisla
```

De tap levert alleen stabiele releases; previews staan op Releases. `brew upgrade` zet je dus niet op een prerelease. Als je tijdens een preview de cask expliciet noemt, vervangt Homebrew die door de huidige stabiele build. Sparkle voert geen downgrade uit: terugschakelen naar Release laat de preview staan totdat een stabiele release nieuwer is. `brew uninstall --cask zisla` verwijdert de app; `brew uninstall --zap --cask zisla` verwijdert ook lokale gegevens.

### Vanuit broncode uitvoeren

Swift 6 / Xcode 16+ zijn vereist; alleen Command Line Tools kunnen het project ook bouwen.

```bash
cd mac
swift run zisla
```

De downloader vereist `yt-dlp`; `ffmpeg` is optioneel. Office naar PDF converteren vereist LibreOffice of OpenOffice. Bouw-, test- en verpakkingsinstructies staan in de [macOS-ontwikkelgids](mac/README.md).

## Ontworpen om niet in de weg te zitten

- Ondersteunt meerdere schermen, Spaces en gewone schermvullende apps zonder de huidige app te activeren of haar focus over te nemen.
- De verborgen toestand heeft geen permanent transparant venster en geen renderlus; globale gebeurtenissen en geometrie activeren het uitklappen.
- Gebruikt één systeemmateriaal en een ondoorzichtige achtergrond wanneer Verminder transparantie is ingeschakeld.
- Vindt een fysieke notch via het veilige systeemgebied; externe schermen zonder notch krijgen een overlay met dezelfde omtrek.

De [architectuur- en prestatiegids](mac/Docs/architecture.md) beschrijft de implementatiekeuzes.

## Privacy en rechten

zisla vraagt een recht alleen als een ingeschakelde functie het voor het eerst nodig heeft. Je kunt modules uitschakelen in Instellingen en rechten op elk moment intrekken in macOS Systeeminstellingen.

| Gebied | Grens |
| --- | --- |
| AI-activiteit | Leest uitsluitend gestructureerde gebeurtenissen en lokale activiteitsmetadata, nooit prompts of antwoordteksten. |
| Klembord en bestanden | Geschiedenis, linkdetectie en Snelle acties zijn afzonderlijke lokale schakelaars. Snelle acties verwerken afgeronde browserdownloads en ontvangen AirDrop-bestanden onafhankelijk van browserdownloadvoortgang. Herkenning gebeurt geheel op het apparaat; openen en acties uitvoeren gebeurt pas na een expliciete klik of sneltoets. Overdracht gebruikt security-scoped bookmarks en kopieert het origineel niet. |
| Notities, mail en spraak | Notities en Mail gebruiken AppleScript/JXA met Automatiseringstoestemming. Spraak wordt alleen tijdens actieve opname vastgelegd; tekstverwerking stuurt transcripties alleen naar het gekozen lokale model, de externe provider of het CLI-profiel. |
| Browserdownloads en media | Gebruikt openbare macOS-bestandsvoortgang, MediaRemote-metadata en Core Audio-uitvoerstatus. Leest geen browsergeschiedenisdatabases. Systeemgolfvormen en appmixen verwerken audio lokaal; een opname slaat audio alleen op als de betreffende bron is ingeschakeld. |
| Netwerk | Weer, openbaar IP, updatebronnen, downloads, ingeschakelde AI-tegoedcontroles en installatie van afhankelijkheden/CLI's benaderen hun diensten. Optionele vertaling, spraakopschoning en AI-opnamebewerking gebruiken de gekozen provider of CLI. Apple-spraakherkenning kan afhankelijk van systeem en taal een netwerkverbinding gebruiken. |

### Rechten per functie

zisla vraagt de vereiste toestemming bij het eerste gebruik. Als je toegang eerder weigerde, open de betreffende instelling onder **Systeeminstellingen > Privacy en beveiliging** en geef `zisla` toegang; namen verschillen soms per macOS-versie.

| Recht of systeeminstelling | Wanneer nodig | Toegestaan bereik |
| --- | --- | --- |
| Apparaatbediening en gegevenstoegang (Toegankelijkheid in sommige versies) | Transcripties automatisch invoegen in het tekstveld van de huidige app | Vindt invoervelden die geen wachtwoordveld zijn en voegt tekst in via toegankelijkheids-API's of `Cmd+V`. Zonder toestemming wordt de transcriptie nog steeds gekopieerd. |
| Microfoon | Spraakinvoer of studiomicrofoon inschakelen | Legt de geselecteerde microfoon vast voor opname of ingeschakelde monitoring. |
| Spraakherkenning | Opgenomen spraak naar tekst omzetten | Verwerkt alleen actief opgenomen spraak. Spraakinvoer vereist zowel Microfoon als Spraakherkenning. |
| Volledige schijftoegang | Mail bekijken als Mail.app niet draait | Leest de lokale index in `~/Library/Mail` voor accounts, afzenders, onderwerpen, samenvattingen, tijden en leesstatus. Dit pad vereist toestemming. |
| Automatisering | Mail.app-berichten lezen, schrijven, beantwoorden, markeren of verwijderen; Apple Notities lezen en schrijven | Laat zisla de bijbehorende systeemapps aansturen. Mail- en Notitiestoestemming kunnen apart worden ingetrokken. |
| Agenda's; Herinneringen | De agendamodule gebruiken | Leest en beheert afspraken en herinneringen met afzonderlijke rechten. |
| Locatievoorzieningen | Weer voor huidige locatie | Vraagt de locatie eenmaal zonder continue tracking. Handmatig toegevoegde locaties vereisen geen locatietoegang. |
| Camera | De spiegel openen of cameravoorvertoning/opname in de studio inschakelen | Gebruikt de gekozen camera zolang de functie actief is. |
| Invoercontrole | Toetsenbordgeluiden, typstatistieken, toetsenbordreiniging en sneltoetsen met alleen modificatietoetsen of muiszijtoetsen | Observeert gebeurtenissen voor de ingeschakelde functie; typstatistieken blijven lokaal. Gewone globale sneltoetsen vereisen dit recht niet. |
| Bluetooth | Accessoirebatterijen onder Systeem → Batterij bekijken | Leest alleen openbare batterijniveaus van verbonden of gekoppelde apparaten. |
| Scherm- en systeemaudio-opname (Schermopname in oudere versies) | Schermafbeeldingen, venstervoorbeelden, opnames, audiogolfvormen en appmixer | Leest schermbeelden en geselecteerde audiobronnen. Opnames bewaren ingeschakelde bronnen lokaal; de mixer vereist macOS 14.4+. |
| Meldingen | Pomodoro-waarschuwingen | Speelt één geluidssignaal en toont een lokale melding wanneer de timer eindigt. |
| Door gebruiker geselecteerde mappen (geen handmatige toestemming) | Overdracht, import, export en downloadmap kiezen | De bestandskiezer geeft toegang tot de gekozen map. Volledige schijftoegang is hiervoor niet nodig. |

Een ingetrokken recht schakelt alleen de bijbehorende functie uit. Als een functie na wijziging nog niet werkt, sluit zisla, open het opnieuw en probeer het nogmaals.

De [macOS-gids](mac/README.md#rechten-en-privacy) beschrijft alle rechten en het netwerkgedrag.

## Documentatie

| Document | Doel |
| --- | --- |
| [macOS-ontwikkelgids](mac/README.md) | Modules, AI-integratie, afhankelijkheden, bouwen, testen, rechten en systeemgrenzen. |
| [Websitegids](../../../web/README.md) | Lokale ontwikkeling, productiebuilds en huidige downloadlinks. |
| [Introductiefilmgids](../../../promo/README.md) | Remotion-voorvertoning, rendering, composities, muziek en assetlicenties. |
| [Architectuur en prestaties](mac/Docs/architecture.md) | Bovenrand, vensters, gelijktijdigheid, media en downloadveiligheid. |
| [CLI-integratiereferentie](mac/Docs/cli-reference.md) | `zislactl`-providers, opdrachten, velden en afsluitcodes. |
| [Ondertekening en releases](mac/Docs/releasing.md) | Ondertekenen, notarissen, DMG's, updatekanalen en releasecontrole. |
| [Bijdragegids](CONTRIBUTING.md) | Ontwikkelomgeving, branches, commits en pullrequestvereisten. |

## Bijdragen

Issues en pullrequests zijn welkom. Lees eerst de [bijdragegids](CONTRIBUTING.md). Meld beveiligingsproblemen privé via [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) in plaats van een openbare issue te openen.

## Licentie

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Niet-commercieel gebruik is toegestaan; verkoop van deze software en ander commercieel gebruik niet.
