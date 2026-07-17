# Papier aus Licht: Wie ich als Designer in zehn Tagen eine iOS-App baute

*Eine kurze Heldenreise: zehn Tage, 97 Commits, ein KI-Kompagnon — und eine peinlich hohe Zahl an Momenten, in denen ich sagte: „Hm. Das **fühlt** sich falsch an."*

Ich bin UI-Designer. Ich diskutiere gern eine halbe Stunde über einen 4-Punkt-Schatten, aber eine `for`-Schleife bekomme ich allein nicht sauber zusammengeschraubt. Trotzdem liegt jetzt eine native iOS-App im App Store, die ich gebaut habe: **Paper Comic Reader**, die Comics wieder aussehen lässt wie mit Tinte auf echtes Papier gedruckt — statt hinter kaltem, beleuchtetem Glas.

Angefangen hat alles auf dem Mac. Ich hatte *Simple Comic*, einen alten Open-Source-Reader, geforkt und ihm aus reiner Design-Lust einen selbstgebauten **Metal-Shader** verpasst: meinen Papier-Look. Ich saß davor, sah zu, wie eine Comicseite plötzlich aussah wie frisch gedruckt, und dachte: *Hmm. Das müsste doch auch aufs iPhone gehen?*

Der eigentliche Startschuss war dann glorreich unheroisch. Abends nach der Arbeit warf ich Claude Code an und sah: Ich hatte noch **Tokens für die Woche übrig** — und die würden am nächsten Tag um Punkt zwölf zurückgesetzt. Einfach verfallen. *Use it or lose it.* Ich dachte mir: *„OK. Machen wir's." :D* Kein Businessplan, kein Roadmap-Workshop — ein Rest Wochenkontingent, das sonst verpufft wäre, und ein Designer mit einer fixen Idee. So beginnen die besten Expeditionen: aus einer Laune, kurz vor Ladenschluss.

Ab da hatte ich einen Kompagnon. Die Arbeitsteilung blieb die ganzen zehn Tage dieselbe: **ich fühlte, entschied und sah — Claude Code tippte, rechnete Geometrie durch und rang mit der Toolchain.**

## Der Zaubertrick: Papier aus Licht

Ein Bildschirm leuchtet. Papier nicht. Comics wurden gedruckt — auf warmes, cremefarbenes Papier —, und hinter Glas sehen sie klinisch aus. Zu sauber. Zu blau. Also: reines Weiß sanft Richtung Creme ziehen, reines Schwarz zu einem tiefen warmen Grau anheben, Sättigung und Kontrast eine Spur zurücknehmen. Aus „Hochglanz" wird „matter Druck".

Der Teil, auf den ich wirklich stolz bin, ist das **Korn** — und wie es Papier gleich *zweifach* nachahmt, so wie echtes Papier funktioniert: eine feine Struktur, die auf den hellen Flächen sitzt (die raue Oberfläche des Stocks), *und* Fasern, die durch die Druckfarbe hindurchschimmern, am stärksten in den dunklen, satten Partien. Genau dieses Durchscheinen ist der eigentliche Charme eines gedruckten Comics: Man *ahnt* das Papier unter der Farbe.

Und hier lauerte das erste Monster. Mein erstes Korn hatte ein feines, aber sichtbares horizontal-vertikales **Gitter** — es sah aus wie ein Fliegengitter, exakt das Gegenteil von organischem Papier. Der Grund: Das Rausch-Muster war brav am Pixelraster ausgerichtet. Die Kur war fast poetisch — man dreht jede einzelne Rauschebene ein kleines Stück, sodass sich nichts mehr mit dem Raster deckt. Kein Mensch bemerkt je bewusst, dass diese Ebenen gedreht sind. Aber jeder Mensch bemerkt sofort, wenn sie es *nicht* sind. Das ist Design in einem Satz.

Und weil ich in Materialien denke statt in Zahlenkolonnen, gibt es die Regler auch als benannte Papiersorten: *Cream Paper*, *Newsprint*, *Manga*, *E-Ink*. Vier Papiere, ein Fingertipp. Damit das Ganze live pro Seite läuft, sitzt der Effekt übrigens als winziges GPU-Programm direkt auf der Grafikkarte — mit einem kompletten Ersatzweg für den Fall, dass es mal nicht lädt.

## Die Dinge, die nur ich sah

Comics lesen heißt Umblättern und Drehen — und ausgerechnet da wurde ich zum Wahnsinnigen. Allein am ersten Tag brauchte ich sechs Anläufe für *eine* Drehung, weil im Querformat die rechte Hälfte einer Doppelseite beim Drehen niemals zur linken werden darf. Ein Ingenieur hätte „läuft doch" gesagt. Ich sah jedes Mal die Seite auf der falschen Seite landen und konnte nicht weiterleben.

Das gemeinste Monster war aber unsichtbar — für alle außer mir. Beim Durchblättern hatte ich das hartnäckige Bauchgefühl, dass das Umblättern einen Hauch *weniger flüssig* ist als der Zoom. Nur ein Frame hier, ein Frame da. Es stellte sich heraus: Ich hatte recht. Zwei Animationen liefen über zwei völlig verschiedene Motoren — die eine auf Apples gnadenlos glattem Render-Server, die andere auf einer selbstgebauten Schleife, die Bild für Bild am immer beschäftigten Hauptthread hing und deshalb auf 120-Hz-Displays gelegentlich ein Einzelbild verschluckte. Auf 60 Hz unsichtbar. Auf 120 Hz: genau der Hauch, den mein Auge einforderte. Die Kur: Schleife raus, alles dem Render-Server überlassen. **Das Auge eines Designers ist ein Messgerät — manchmal ein besseres als der Profiler.**

## Die Apple-Tortur

Ende der ersten Woche: ab in den App Store. Zurück kam eine Ablehnung mit meinem persönlichen Lieblingsgrund — „**Tips failed to load**". Ich hatte einen kleinen, freundlichen Trinkgeld-Knopf eingebaut, falls jemand einen Kaffee spendieren möchte. Und ausgerechnet der weigerte sich, vor den Augen des Prüfers zu laden.

Ich traf an diesem Punkt eine sehr bewusste, sehr designerische Entscheidung: Das ist es mir nicht wert. Der ganze Genehmigungs- und Vertrags-Zirkus fühlte sich für eine kostenlose kleine App wie eine **Tortur** an. Also machte ich etwas unerwartet Befreiendes — ich riss den kompletten Bezahl-Code wieder heraus und wich auf **Sideloading** aus: Die App wandert als fertiges, aber bewusst *unsigniertes* Paket auf GitHub, jeder signiert sie mit der eigenen Apple-ID neu. Ehrlich fummelig für Endnutzer, aber es war *meins*, und niemand musste es genehmigen.

## Ein Regal voller Comics, die gar nicht da sind

Auf das nächste Stück bin ich heimlich am stolzesten, obwohl man es nie zu *sehen* bekommt. In Woche zwei wurde die App erwachsen: Sie lernte, die in Comics eingebetteten Infos zu lesen — Serie, Ausgabe, Story-Titel — und hütet all das zusammen mit dem Lesefortschritt in einer kleinen Datenbank. (Ein falscher Handgriff an deren Struktur, und eine Notfallroutine löscht im schlimmsten Fall die *ganze* Datenbank: jedes Lesezeichen, jeder Fortschritt weg. Also testeten wir die Umstellung gegen eine echte alte Datenbank, Spalte für Spalte, *bevor* irgendein Nutzer sie zu sehen bekam.)

Der eigentliche Zaubertrick kam obendrauf. Eine echte Comic-Sammlung ist gigabyteweise groß; kein Mensch will die komplett auf dem Handy haben. Aber man will sie trotzdem *sehen* — alle Cover, alle Titel, durchsuchbar. Die Lösung: Man zeigt der App *einen* Ordner, den die Dateien-App erreicht — ein NAS im Wohnzimmer, iCloud, ein Fileserver. Sie geht ihn einmal durch und zieht aus jedem Comic nur das **Federgewicht** heraus: Cover und Metadaten. Nur die landen aufs Handy; die schweren Archive bleiben, wo sie sind.

Das Ergebnis fühlt sich wie Magie an: **Deine Bibliothek sieht komplett aus** — aber die meisten dieser Comics liegen gar nicht auf deinem Handy, sie sind bloß *Versprechen*. Tippst du eins an, wird es in dem Moment nachgeladen. Ausgelesen, oder Platz gebraucht? Wirf die schwere Datei wieder raus — Cover und Titel bleiben im Regal stehen. Ein Bücherregal, dessen Bücher sich erst materialisieren, wenn man nach ihnen greift.

Dahinter steckt viel unsichtbare Klempnerei: eine Sonder-Erlaubnis, um überhaupt auf einen fremden Ordner zuzugreifen, die App-Neustarts überlebt und die man nach jedem Zugriff penibel wieder abgeben muss. Ein NAS, das gerade schläft — und die simple Frage „ist der Ordner überhaupt da?" kann sich am Netzwerk *aufhängen*, also passiert sie fern vom Hauptthread, sonst fröre die App beim bloßen Öffnen des Regals ein. Und ein Klassiker: Ein Ordner `Comics` und ein Nachbar `ComicsExtra` fangen gleich an — die App vergleicht deshalb sauber auf Pfadgrenzen, damit der zweite nicht fälschlich im ersten landet. So ein Fehler kostet niemanden Schlaf. Bis er es tut.

## Das Karussell, das einrastete

Kurz vor Schluss das eleganteste Rätsel: Ein „Entdecken"-Karussell ruckte am Ende eines *langsamen* Wischens — aber nur da. Bei einem schnellen Wisch: perfekt. Die Ursache war zauberhaft hinterhältig: Die Bühne las bei jedem Wisch-Frame mit, welches Cover gerade mittig steht — und zeichnete sich deshalb komplett neu, mitten in der Bewegung, und schubste die Karte, die gerade einrasten wollte. Die Lösung: Der Container darf das schlicht nie wieder wissen; nur die Randansichten lesen es. Butterweich. Nachweisbar war das übrigens nur am echten Gerät — solche Fühl-Sachen spürt kein Testskript für einen. Ich musste die App mehr *ertasten* als messen.

## Die Rückkehr

Und dann, am letzten Tag, die Kehrtwende: zurück in den App Store — ausgerechnet dorthin, wo ich türeschlagend rausgegangen war. Diesmal ohne Bezahlfunktion. Der schönste Plot-Twist: Der Trinkgeld-Knopf von damals existierte längst nicht mehr; „Bezahlfunktion entfernen" war am Ende keine Code-Aufgabe, sondern ein gestrichener Werbesatz in einem Formular. Das Monster war längst tot; es spukte nur noch im Beipackzettel.

Ein letzter Boss-Kampf durfte natürlich nicht fehlen: Der signierte Build scheiterte reproduzierbar mit einer nichtssagenden Meldung. Der Schuldige — ein per Homebrew nachinstalliertes Kopier-Werkzeug, das sich im Systempfad vor Apples eigenes gedrängelt hatte. Zwei Stunden Suche, eine Zeile Fix. So sterben die undokumentierten Monster: leise, an einem Einzeiler. Heute läuft die App über **beide** Wege: Sideload auf GitHub für die Bastler, und ordentlich im Store für alle anderen.

## Was ein Designer gelernt hat

„Es kompiliert" ist kein Zielband, sondern der Startschuss — fast jeder echte Kampf dieser Reise war unsichtbar, bis ich das Ding in der Hand hielt und *fühlte*. Das Auge des Designers, das Kollegen manchmal die Augen verdrehen lässt, ist in Wahrheit ein Präzisionsinstrument. Und der ehrlichste Punkt zum Schluss: Allein hätte ich das nie gebaut — nicht in zehn Tagen, wahrscheinlich nicht in zehn Monaten. Ein KI-Pair-Programmer machte aus „einem Designer mit einer Idee" jemanden, der **shippt**. Ich habe nie eine Schleife von Hand geschrieben. Ich habe gefühlt, gezeigt, verworfen, entschieden.

Zehn Tage. 97 Commits. Ein paar besiegte Monster. Und eine kleine App, die Comics wieder wie Papier aussehen lässt — geboren aus einem Rest Wochen-Tokens, der sonst um Punkt zwölf verfallen wäre.
