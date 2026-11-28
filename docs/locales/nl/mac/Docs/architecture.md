# Architectuur en prestatieontwerp

**Nederlands** | [English](../../../../../mac/Docs/architecture.md) | [简体中文](../../../../../mac/Docs/architecture.zh-CN.md) | [Andere talen](../../../README.md)

## Activering aan de bovenrand

In de verborgen toestand is er geen transparant venster. `PointerEdgeMonitor` installeert globale en lokale `NSEvent`-monitors voor muisbewegingen en slepen; `ScreenLayoutEngine` bepaalt uitsluitend met geometrie of de aanwijzer het centrale gebied van 6 px bovenaan elk scherm binnenkomt.

Elk scherm krijgt een stabiele identiteit door `NSScreenNumber` aan zijn `CGDirectDisplayID` te koppelen. Het ontwerp is verankerd aan `screen.frame.maxY` en ondersteunt negatieve coördinaten, verticaal gestapelde schermen en externe schermen zonder notch.

Als meerdere schermen zijn aangesloten, kun je onder Instellingen → Algemeen → Schermmodi per scherm de Dynamic Island-modus (camerapositie of eigen positie), notch-modus of verbergen kiezen. Met één scherm is deze instelling verborgen en geldt de algemene weergave; na opnieuw aansluiten worden de opgeslagen scherminstellingen hersteld. Op alle zichtbare schermen blijft het ingeklapte eiland tegelijk zichtbaar. Uitklappen, snelle acties, opnemen en tijdelijke berichten vervangen alleen het eiland op hun eigen scherm; de selectie van meldingsschermen filtert de inhoud zonder het inactieve eiland te verbergen.

## Venster

Het hoofdeiland heeft één `.borderless + .nonactivatingPanel`:

- Gebruikt het niveau `.statusBar` en bedekt geen toegangsscherm of systeemmenu.
- `.canJoinAllSpaces + .fullScreenAuxiliary` ondersteunt Spaces en gewone schermvullende apps.
- Uitklappen bij aanwijzen roept nooit `NSApp.activate` aan en neemt de focus van de huidige app niet over.
- Verbergen gebruikt `orderOut`, zodat een transparant venster geen ruimte in de menubalk inneemt.

Linker- en rechtermeldingspanelen worden op aanvraag gemaakt en verdwijnen zodra hun wachtrijen leeg zijn.

## Toestand en gelijktijdigheid

- AppKit, SwiftUI-toestand en vensterbediening blijven op `MainActor`.
- Als menubalkbeheer is ingeschakeld, maakt zisla twee `NSStatusItem`-elementen aan. Zolang de lijst met symbolen open is, leest zisla `AXExtrasMenuBar` en controleert het na een verplaatsing de positie van het gekozen symbool.
- Downloads, weer en GitHub-verzoeken gebruiken actors.
- AI-status die hooks schrijven wordt via bestandssysteemgebeurtenissen op de map gevolgd. Elke AI-sessiebron vergelijkt wijzigingstijd en grootte van het nieuwste lokale sessie- of activiteitsbestand en gebruikt de parsercache opnieuw als niets veranderde.
- Automatische detectie leest alleen gestructureerde gebeurtenissen, vaste statusmarkeringen en activiteitsmetadata die nodig zijn om de taakstatus te bepalen. Prompt- en antwoordteksten worden niet gelezen; een parserfout bij één provider blokkeert andere providers niet.
- AI-accounttegoeden worden per aanbieder gemeten. De Gemini- en Claude/GPT-tegoeden van Antigravity behouden eigen resetvensters en meldingen. Het gewone chattegoed van Gemini App gebruikt de opgeslagen web-Cookie van hetzelfde Google-account; Gemini CLI behoudt de lokale OAuth-bron. Ontbrekende tegoeden worden nooit geschat.
- Vertraagd inklappen gebruikt annuleerbare `Task`s en een generatietoken, zodat een oude taak een opnieuw geopend eiland niet verbergt.
- De verborgen toestand heeft geen `TimelineView`, 60 Hz-timer of voortdurende aanlevering van animaties.

## Mediadetectie

MediaRemote levert titel, hoes, voortgang en bediening. Procesobjecteigenschappen van Core Audio 14.4+ bevestigen een actieve uitvoerstroom en vinden de bronapp wanneer metadata ontbreken. Proceslijsten en uitvoerstatus gebruiken eigenschapslisteners met begrensde periodieke controle; audio-inhoud wordt niet vastgelegd en Schermopname of Toegankelijkheid wordt niet gevraagd. Gepauzeerde, gestopte en gedempte bronnen blijven niet in het mediagebied staan.

## Opnemen en applicaties mixen

Schermopname en de applicatievolumemixer staan los van metadatadetectie. Opnemen vraagt Schermopname en de rechten van ingeschakelde microfoon/camera, bewaart gekozen media lokaal en beheert projecten in de gekozen opnamemap. De mixer gebruikt Core Audio-taps op macOS 14.4+ en vereist Systeemaudio-opname.

## Materialen

macOS 26 gebruikt één SwiftUI-`glassEffect`-laag; macOS 14/15 gebruiken één `NSVisualEffectView`-laag. Verminder transparantie schakelt een ondoorzichtige achtergrond in. Het eiland stapelt geen meerdere vervagings- of materiaallagen.

## Veiligheidsgrens voor downloads

Swift start `yt-dlp` met `Process.executableURL` en een argumentenarray; de URL is altijd een afzonderlijke argv-waarde na `--`. Runtimeconfiguratie, plugins en exec zijn uitgeschakeld, uitvoerpijpen worden gelijktijdig geleegd en voortgang wordt met een JSON-markering gelezen.

Een taak slaagt alleen bij afsluitcode 0, een bestaand uitvoerpad en een opgelost pad binnen de toegestane map. Elke taak ruimt alleen haar eigen tijdelijke UUID-map op.

## Updates controleren en downloaden

Het gekozen updatekanaal bepaalt eenmaal per appstart de landcode van het openbare IP. Sparkle haalt de ondertekende appcast voor de geïnstalleerde build op, downloadt de genoemde ZIP via HTTPS, controleert EdDSA-archief- en feedhandtekeningen vóór uitpakken, vervangt de app en start haar opnieuw. `CN` probeert eerst Gitee (`update-release` voor Release, `preview` voor Preview) en daarna eenmaal de overeenkomstige GitHub-feed; andere landcodes gebruiken de omgekeerde volgorde. Bij een mislukte landopvraag blijft Gitee eerst. Elke feed verwijst naar een ondertekende ZIP op zijn eigen host.

Een release publiceert per architectuur een appcast naast het gedeelde `appcast.xml`. Een installatie met één architectuur vraagt de feed voor haar eigen slice (een vertaald uitgevoerde x86_64-slice vraagt `arm64`) en wordt dus niet vervangen door Universal. Een Universal-installatie telt haar eigen uitvoerbare slices en blijft op `appcast.xml`, dat ook apps van vóór architectuurgebonden updates bedient. De instelling beïnvloedt automatische en handmatige controles en stelt Sparkle's volgende controlecyclus opnieuw in. De ingebouwde openbare sleutel bevat geen accountgegevens; de privésleutel blijft in de macOS-sleutelhanger van de releasebeheerder of in een apart beveiligd sleutelbestand.
