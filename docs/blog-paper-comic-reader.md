# Papier auf einem Bildschirm — wie ein Designer ohne eine Zeile Code eine iOS-App shippte

*Zehn Tage. 97 Commits. Ein KI-Kompagnon. Und eine peinlich hohe Zahl an Momenten, in denen ich sagte: „Hm. Das **fühlt** sich falsch an."*

---

Ich bin UI-Designer. Ich kann eine halbe Stunde über einen 4-Punkt-Schatten diskutieren, ohne rot zu werden. Ich sehe einen falsch gerundeten Button aus dreißig Metern Entfernung. Aber eine `for`-Schleife bekomme ich ohne fremde Hilfe nicht fehlerfrei zusammengeschraubt.

Trotzdem gibt es jetzt eine native iOS-App, die ich gebaut habe. Sie heißt **Paper Comic Reader**, sie öffnet Comics und lässt jede Seite aussehen wie mit Tinte auf echtes Papier gedruckt statt hinter Glas beleuchtet. Sie läuft auf iPhone und iPad, ohne Accounts, ohne Tracking, ohne dass je etwas nach Hause telefoniert. Und sie ist in genau **zehn Tagen** entstanden.

Und das Schönste ist, wie banal der Startschuss war. Angefangen hat alles auf dem **Mac**: Ich hatte **Simple Comic**, einen alten Open-Source-Comic-Reader, geforkt und ihm aus reiner Design-Lust einen selbstgebauten **Metal-Shader** verpasst — meinen Papier-Look. Ich saß davor, sah zu, wie eine Comicseite plötzlich aussah wie frisch gedruckt, und dachte: *Hmm. Das müsste doch auch als iPhone-App gehen?*

Und dann kam der eigentliche, glorreich unheroische Auslöser. Abends nach der Arbeit warf ich Claude Code an und sah: Ich hatte noch **Tokens für die Woche übrig** — und die würden am nächsten Tag um Punkt zwölf zurückgesetzt. Einfach verfallen. *Use it or lose it.* Ich dachte mir: *„OK. Machen wir's." :D*

Kein Businessplan, kein Roadmap-Workshop. Ein Rest Wochenkontingent, das sonst verpufft wäre, und ein Designer mit einer fixen Idee. So beginnen die besten Expeditionen — aus einer Laune, kurz vor Ladenschluss.

Und ab da hatte ich einen Kompagnon. Die Arbeitsteilung blieb die ganzen zehn Tage dieselbe: **ich fühlte, entschied und sah; Claude Code tippte, rechnete Geometrie durch und rang mit der Toolchain.** Das hier ist das Logbuch dieser Expedition. Mit allen Monstern.

---

## Tag 1: Aus dem Nichts, und dann sofort besessen

Der erste Commit heißt schlicht `Initial commit`. Ab da ging es an einem einzigen Tag durch die Decke: eine Bibliothek mit Cover-Raster, ein Reader, Doppelseiten-Modus, Vorschau-Laden der nächsten Seite, Zoom. Aus einem leeren Ordner wurde binnen Stunden etwas, das man in der Hand halten und durchblättern konnte.

Und dann passierte das, was Designern immer passiert. Ich fing an, ein Detail zu sehen, das ich nicht mehr *nicht* sehen konnte: **das Drehen.**

Wenn man das iPhone quer dreht, muss eine Comicseite sich neu einpassen. Klingt trivial. Ist es nicht. Meine Commit-Historie von Tag eins liest sich wie das Tagebuch eines Menschen, der langsam den Verstand verliert:

> „simpler rotation" → „animate re-fit explicitly" → „*don't* reloadData mid-rotation (revert)" → „fix page jump on rotation" → „rebuild rotation cleanly across the four view configs" → „morph single↔double-page instead of cross-dissolving"

Sechs Anläufe. Für eine Drehung. Der Kern des Problems war ein winziges, sehr designerisches Anliegen: Wenn im Querformat zwei Seiten nebeneinander liegen, darf die *rechte Hälfte* einer Doppelseite beim Drehen niemals plötzlich zur *linken* werden. Die Paarung muss fix sein — Cover allein, dann 2·3, 4·5, und so weiter. Ein Ingenieur hätte vielleicht gesagt „läuft doch". Ich sah jedes Mal, wie die Seite auf der falschen Seite landete, und konnte nicht weiterleben.

**Lektion Nummer eins der Reise:** Für einen Designer ist „es kompiliert" ungefähr so beruhigend wie „das Flugzeug hat Flügel". Schön. Aber fliegt es auch *ruhig*?

---

## Der eigentliche Zaubertrick: Papier aus Licht

Jetzt zu dem Feature, das der App ihren Namen gibt — und der eigentliche Grund, warum ich sie überhaupt bauen wollte.

Ein Bildschirm leuchtet. Papier nicht. Comics wurden gedruckt, auf warmes, leicht raues Papier mit einem Stich ins Cremefarbene — und genau das geht verloren, sobald man sie hinter kaltem, hintergrundbeleuchtetem Glas anschaut. Sie sehen *klinisch* aus. Zu sauber. Zu blau. Mein ganzes Projekt hatte im Grunde nur ein Ziel: dem Glas das Papier zurückzugeben.

Wie im Prolog erzählt, entstand dieser Effekt zuerst auf dem Mac — als selbstgebauter Metal-Shader in meinem **Simple-Comic**-Fork. Ihn überhaupt nach iOS zu holen, war das eine. Ihn dann so lange zu drehen, zu schleifen und zu tunen, bis er sich auf einem iPhone *richtig* anfühlte, das andere. Und *dieses* Tunen ist die eigentliche Geschichte.

Der Trick besteht aus mehreren Ebenen, und jede ist eine kleine Designerwahrheit:

- **Reines Weiß ist kein Papier.** Echtes Papier ist ein warmes Creme. Also ziehe ich jedes Weiß sanft dorthin.
- **Reines Schwarz ist keine Druckfarbe.** Druckschwarz ist ein tiefes, warmes Grau, kein Loch. Also hebe ich das Schwarz ein Stück an.
- Dazu ein Hauch weniger Sättigung und etwas weichere Kontraste — der ganze Unterschied zwischen „Hochglanz-Display" und „mattem Druck".

Aber der Teil, auf den ich wirklich stolz bin, ist das **Papierkorn** — und wie es Papier gleich *zweifach* nachahmt, so wie echtes Papier funktioniert:

- eine feine **Struktur**, die auf den hellen Flächen sitzt und ihnen die raue Oberfläche gibt (dunkelt minimal ab, lässt dichte Druckfarbe fast unberührt), und
- die Papierfasern, die **durch die Druckfarbe hindurchschimmern** — in den dunklen, satten Flächen am stärksten, im hellen Papier fast unsichtbar. Genau dieses Durchscheinen ist der eigentliche Charme eines gedruckten Comics: Man *ahnt* das Papier unter der Farbe.

Und hier kam das Monster. Meine erste Version dieses Korns hatte ein feines, aber sichtbares **horizontal-vertikales Gitter** — es sah aus wie ein Fliegengitter, exakt das Gegenteil von organischem Papier. Der Grund: Das Rausch-Muster war brav am Pixelraster ausgerichtet. Die Kur war fast poetisch — man **dreht jede einzelne Rauschebene** ein Stück, sodass sich das Muster nie mit dem Pixelraster deckt. Ergebnis: ein gleichmäßiges, richtungsloses Korn ohne Naht. Kein Mensch würde je bewusst bemerken, dass diese Ebenen gedreht sind. Aber jeder Mensch bemerkt sofort, wenn sie es *nicht* sind. Das ist Design in einem Satz.

Damit das Ganze live pro Seite läuft — und nicht sekundenlang rechnet —, sitzt der Effekt als winziges GPU-Programm (ein Metal-Shader) direkt auf der Grafikkarte. Falls dieses Programm mal nicht geladen werden kann, gibt es einen kompletten Ersatzweg allein mit Bordmitteln. (Mein Lieblings-Stolperstein am Rande: Auf dem neuen Xcode wollte der Shader zunächst gar nicht bauen — man muss die passende Werkzeugkette erst *einmalig herunterladen*. Eine Stunde Ratlosigkeit für einen Einzeiler in der Konsole.)

Und weil ich Designer bin, denke ich in **Materialien**, nicht in Zahlenkolonnen — also gibt es die Regler nicht nur roh, sondern auch als benannte Papiersorten: *Cream Paper*, *Newsprint*, *Manga*, *E-Ink*. Vier Papiere, ein Fingertipp.

Ein letzter Feinschliff, der mir wichtig war: Der Rahmen rund um die Seite — die „Matte", auf der sie liegt — ist genau auf die Papierwärme abgestimmt. Die Seite ruht auf einem warmen Passepartout, nicht in einem kalten schwarzen Nichts. (Dass ein Regler eine Weile lang die Vorschau nicht aktualisierte, weil im Hintergrund noch ein alt gerendertes Bild klebte, verschweige ich hier großzügig. Fast.)

---

## Der unsichtbare Ruckler

Das nächste Monster war das gemeinste der ganzen Reise, weil es sich vor allen versteckte — außer vor mir.

Ich blätterte durch einen Comic und hatte dieses Bauchgefühl: Das Umblättern per Tipp fühlt sich einen Hauch *weniger flüssig* an als der Doppeltipp-Zoom. Nicht viel. Ein Frame hier, ein Frame da. Ich konnte es nicht benennen, nur fühlen. Mein Kompagnon konnte es zunächst nicht mal reproduzieren — auf dem Papier war alles gleich schnell.

Es stellte sich heraus: Ich hatte recht, und zwar aus einem Grund, den man nur auf modernen 120-Hz-„ProMotion"-Displays überhaupt sehen kann. Zwei verschiedene Animationen liefen über zwei völlig verschiedene Motoren. Der Zoom und die Drehung liefen auf dem **Render-Server** — Apples eigenem, gnadenlos flüssigem Animationsmotor. Das Umblättern dagegen hing an einer selbstgestrickten Schleife, die **auf dem Hauptthread Bild für Bild** die Position weiterschob. Und der Hauptthread hat immer zu tun. Also verschluckte er hin und wieder ein Einzelbild. Auf 60 Hz unsichtbar. Auf 120 Hz: genau der Hauch, den mein Auge einforderte.

Die Kur war radikal: die selbstgebaute Schleife komplett rausreißen und *alles* dem Render-Server überlassen. Jetzt macht ein Umblättern das hier — die alte Seite wird als Foto eingefroren, die Bühne darunter springt bereits ans Ziel, und das Foto gleitet elegant weg. Nichts hakt mehr. (Der lustige Teil: Wir verdächtigten anfangs eine ganz andere Einstellung, die angeblich die Bildrate deckelt. Die war die ganze Zeit korrekt gesetzt. Der wahre Schuldige saß woanders. So ist das mit Monstern.)

**Lektion Nummer zwei:** Das Auge eines Designers ist ein Messgerät. Manchmal ein besseres als der Profiler.

---

## Die App-Store-Tortur

Ende der ersten Woche war die App reif genug, um sie der Welt zu zeigen. Also: ab in den App Store. Ich taufte sie feierlich, setzte eine Versionsnummer, reichte ein.

Zurück kam eine Ablehnung. Zwei Beanstandungen: eine Formalie zur Altersfreigabe — und, mein persönlicher Favorit, „**Tips failed to load**". Ich hatte einen kleinen, freundlichen *Trinkgeld-Knopf* eingebaut, falls jemand einen Kaffee spendieren möchte. Genau dieser Knopf weigerte sich, ausgerechnet vor den Augen des Prüfers, zu laden.

Ich habe an diesem Punkt eine sehr bewusste, sehr designerische Entscheidung getroffen: Das ist es mir nicht wert. Der ganze Genehmigungs- und Vertrags-Zirkus fühlte sich für eine kostenlose kleine App wie eine **Tortur** an. Also machte ich etwas, das sich unerwartet befreiend anfühlte — ich riss den kompletten Bezahl-Code wieder heraus. Trinkgeld-Knopf, Store-Anbindung, Bewertungs-Nagerei: alles weg.

Stattdessen: **Sideloading.** Die App wird jetzt als fertiges, aber bewusst *unsigniertes* Paket auf GitHub veröffentlicht. Wer sie will, lädt sie mit einem Helferlein (AltStore oder Sideloadly), das sie mit der eigenen Apple-ID neu signiert. Ehrlich gesagt: für Endnutzer fummelig. Mit einem kostenlosen Apple-Account hört die App nach **sieben Tagen** einfach auf zu starten, bis man sie erneuert. (Wir bauten später sogar ein nächtliches Skript, das die App automatisch neu baut und installiert, damit dieses 7-Tage-Fenster nie zuschlägt. Man klebt Pflaster über Pflaster.)

Es war umständlich. Aber es war *meins*, und niemand musste es genehmigen.

---

## Glas, Karussells und die Kunst, ein Cover in die Mitte zu rücken

Frei vom Store-Stress kam die verspielte Phase. iOS 26 brachte Apples neue „Liquid Glass"-Optik — durchscheinende, schwebende Oberflächen — und ich wollte sie. Native schwebende Tab-Leiste, gläserne Reader-Bedienung: rein damit.

Und dann verliebte ich mich in ein **Karussell**. Ein „Entdecken"-Modus, bei dem die Cover als Kartenstapel durchgeblättert werden, das nächste Cover lugt links und rechts hervor. Wunderschön — sobald es sitzt. Bis dahin war es ein zweiter Wahnsinnstag:

> „roomier cover" → „centre the first cover on open" → „stop clipping its shadow" → „fix the off-centre cover and give the shadow real room"

Ich habe ehrlich mehrere Commits allein dafür verbraucht, dass beim Öffnen das *erste* Cover mittig sitzt und sein Schatten nicht abgeschnitten wird. Für einen Entwickler ein Rundungsfehler. Für einen Designer ein Grund, nicht schlafen zu gehen.

---

## Metadaten und der Laden, der sich selbst abfackelt

Woche zwei wurde erwachsener. Die App lernte, die in Comics eingebetteten Infos zu lesen — Serie, Ausgabe, Story-Titel, Erscheinungsdatum — sodass eine Datei nicht mehr `Topolino_1900.cbz` heißt, sondern stolz „Topolino 1900" mit Untertitel. Gleichzeitig warf ich ein altes Comic-Format über Bord, das eine Bibliothek aus rund **160 fremden C++-Dateien** mitschleppte. Sie mitzunehmen: raus. Die App wurde spürbar leichter.

Aber hier lauerte das heimtückischste Monster von allen — eines, das nur *einmal* zuschlagen muss. Die Bibliothek merkt sich alles Wertvolle: Lesefortschritt, Lesezeichen, welche Comics man schon durch hat. Ändert man die Struktur dieser Datenbank falsch, kann beim nächsten Start eine Notfallroutine anspringen, die im schlimmsten Fall **die ganze Datenbank löscht und neu anlegt.** Die Comics selbst überleben auf der Festplatte. Aber jedes Lesezeichen, jeder Fortschritt — weg.

Das ist die Sorte Fehler, bei der man nicht „einfach mal ausprobiert". Wir haben die Umstellung deshalb gegen eine *echte alte* Datenbank getestet, wie sie eine frühere Version geschrieben hätte, und Spalte für Spalte nachgesehen, dass nichts verlorengeht, *bevor* es irgendein Nutzer zu sehen bekam. (Dass diese Notfallroutine vielleicht ein bisschen zu schnell den Feuerlöscher zieht, steht bis heute auf meiner Liste. Manche Monster lässt man bewusst in der Kiste, bis man Zeit hat, sie richtig anzusehen.)

Im selben Zug baute ich eine **Suche** ein — und riss sie sofort wieder aus dem Karussell heraus. Denn ein Suchfeld in einem „zum Entdecken durchblättern"-Modus ist ein Widerspruch in sich. Suchen tut man in einer Liste. *Entdecken* tut man mit dem Daumen. Zwei verschiedene Kopfhaltungen, zwei verschiedene Orte.

---

## Ein Regal voller Comics, die gar nicht da sind

Jetzt zu dem Stück Technik, auf das ich heimlich am stolzesten bin — obwohl man es nie zu *sehen* bekommt, sondern nur spürt.

Eine echte Comic-Sammlung ist riesig. Gigabytes über Gigabytes. Kein Mensch will die komplett auf dem Handy liegen haben. Aber — und das ist der Knackpunkt — man will trotzdem seine *ganze* Sammlung sehen: durch alle Cover blättern, alle Titel lesen, suchen. Auch die Comics, die man gerade gar nicht dabeihat.

Die Lösung ist ein einziger Ordner. Man zeigt der App *einen* Ordner, den die Dateien-App erreichen kann — ein NAS im Wohnzimmer, iCloud Drive, ein Fileserver. Die App geht ihn einmal durch und zieht aus jedem Comic nur das **Federgewicht** heraus: das Cover und die Metadaten. Genau die — und *nur* die — landen auf dem Handy. Die schweren Archive bleiben, wo sie sind.

Das Ergebnis fühlt sich, mit Verlaub, ein bisschen wie Magie an: **Deine Bibliothek sieht komplett aus.** Jedes Cover im Regal, jeder Titel durchsuchbar, alles da. Aber die meisten dieser Comics liegen gar nicht auf deinem Handy — sie sind *Versprechen*. Tippst du eins an, wird es genau in dem Moment nachgeladen, und du liest. Ausgelesen, oder Platz gebraucht? Wirf die schwere Datei wieder raus — Cover und Titel bleiben im Regal stehen. Ein Bücherregal, dessen Bücher sich erst materialisieren, wenn man nach ihnen greift.

So schön das für den Leser ist, so viel unsichtbare Klempnerei steckt dahinter — und hier warteten gleich mehrere kleine Biester:

- **Der Schlüssel, den man zurückgeben muss.** Auf einen Ordner *außerhalb* der eigenen App-Sandbox zuzugreifen, verlangt eine spezielle Erlaubnis, die man genau einmal erteilt und die App-Neustarts überleben muss. Und man muss diesen „Schlüssel" nach jedem Zugriff penibel wieder abgeben, sonst leckt das Ganze. Es gibt in der App exakt *eine* Stelle, die dieses Aufschließen-und-wieder-Zusperren besitzt — damit es garantiert nie schiefgeht.
- **Der Ordner, der schläft.** Das NAS ist vielleicht gerade aus, die Freigabe offline. Und die simple Frage „ist der Ordner überhaupt da?" kann sich am Netzwerk *aufhängen*. Fragte man das im falschen Moment, fröre die App ein — beim bloßen Öffnen des Regals. Also passiert jede dieser Fragen abseits des Hauptthreads. Ein Regal, das beim Aufmachen nicht hakt, obwohl es über ein schlafendes Netzlaufwerk redet: erstaunlich viel Arbeit für „es passiert einfach nichts Schlimmes".
- **Das Detail, über das niemand stolpern soll.** Beim Zuordnen der Dateien lauerte ein Klassiker: Ein Ordner namens `Comics` und ein Nachbar namens `ComicsExtra` fangen gleich an — eine naive Prüfung hielte den zweiten fälschlich für einen Unterordner des ersten. Die App vergleicht deshalb sauber auf Pfadgrenzen. So ein Fehler kostet niemanden Schlaf. Bis er es tut.

Zusammen mit den Metadaten aus dem vorigen Kapitel ergibt das den eigentlichen Zaubertrick: Das Cover und die Infos, die einmal beim Einlesen herausgezogen werden, sind genau das, was das lokale „Geister-Regal" echt wirken lässt — schwer aussehend, federleicht auf dem Gerät.

---

## Das Karussell, das einrastete

Und dann, kurz vor Schluss, das eleganteste Rätsel der ganzen Reise. Dasselbe schöne Karussell hatte einen Makel, den nur ich zu sehen schien: Wischte man *langsam*, „rastete" die Karte am Ende ruckartig ein, statt sanft auszurollen. Bei einem schnellen Wisch: perfekt. Bei einem langsamen: ein winziger Stotterer auf der Ziellinie.

Die Ursache war zauberhaft hinterhältig. Der Container, der die Wisch-Bühne zeichnete, las nebenbei mit, *welches* Cover gerade in der Mitte steht — für das Info-Panel darunter. Bei jedem einzelnen Wisch-Frame änderte sich dieser „Mitte"-Wert. Und weil der Container ihn las, zeichnete sich die ganze Bühne bei jedem Frame neu — und schubste die Karte, die gerade in Ruhe einrasten wollte. Das System behinderte sich selbst.

Die Lösung: Der Container darf schlicht **nie wieder** wissen, welches Cover in der Mitte ist. Diese Info wanderte in eine winzige Seitentafel, die nur die *Blätter* am Rand lesen — nie der Container. Ergebnis: Beim Wischen zeichnen sich nur noch zwei kleine Nebenansichten neu, die Bühne selbst bleibt in Ruhe. Butterweich.

Das Ehrlichste, was ich über diesen Fix sagen kann: Er ließ sich **im Simulator gar nicht nachweisen.** Solche „Fühl-Sachen" kann keine Testautomatik für mich abnehmen — kein Skript spürt ein Ruckeln. Ich musste die App aufs echte Gerät spielen, langsam wischen, fühlen, verwerfen, neu bauen. Viele, viele Runden. Meine Werkstatt hatte, was das anging, keine Fenster: Ich musste die App mehr *ertasten* als messen.

---

## Die Rückkehr in den Store — diesmal ohne Trinkgeld

Und dann, am letzten Tag, die Kehrtwende, die eine gute Geschichte braucht: **zurück in den App Store.** Ausgerechnet dorthin, wo ich türeschlagend rausgegangen war.

Was sich geändert hatte? Der Stein des Anstoßes von damals — der Trinkgeld-Knopf, der nicht laden wollte — **existierte gar nicht mehr.** Ich hatte ihn längst herausgerissen. Der schönste Plot-Twist der ganzen Reise: „Bezahlfunktion entfernen" war am Ende gar keine Code-Aufgabe mehr, sondern nur noch ein paar Formularfelder, aus denen ein alter Werbesatz gestrichen werden musste. Das Monster war längst tot; es spukte nur noch im Beipackzettel.

Natürlich wäre es keine echte Rückkehr ohne einen letzten Boss-Kampf. Der signierte Store-Build scheiterte reproduzierbar mit einer nichtssagenden Fehlermeldung — „Kopieren fehlgeschlagen". Der Schuldige: ein per Homebrew nachinstalliertes Kopier-Werkzeug hatte sich im Systempfad vor Apples eigenes gedrängelt und verweigerte einen Apple-spezifischen Handgriff. Eine einzige Zeile, die Apples Original wieder nach vorn stellt, und der Build lief durch. So sterben die undokumentierten Monster: leise, nach zwei Stunden Suche, an einer Einzeiler-Zeile.

Dazu kam noch ein kleiner Papierkram-Drache — Apple verlangt neuerdings eine Erklärung, *warum* eine App bestimmte Systemfunktionen nutzt. Meine nutzt genau eine, um Einstellungen zu speichern. Ein kurzes Manifest, ehrlich ausgefüllt: kein Tracking, keine Datensammlung. Erledigt.

Heute läuft die App über **beide** Wege: als Sideload auf GitHub für die Bastler, und ordentlich im Store für alle anderen.

---

## Was ein Designer auf dieser Reise gelernt hat

Ein paar Dinge nehme ich mit — für andere Designer, für neugierige Leser, und vielleicht auch für die Entwickler, die grinsend mitgelesen haben:

**„Es kompiliert" ist kein Zielband, es ist der Startschuss.** Fast jeder echte Kampf dieser Reise — der ProMotion-Ruckler, das Karussell-Einrasten, die Drehung — war unsichtbar, bis man das Ding in der Hand hielt und *fühlte*. Ein grüner Build beweist, dass die App existiert. Nicht, dass sie sich richtig anfühlt.

**Das Auge des Designers ist ein Feature, kein Bug.** Zweimal habe ich auf ein Bauchgefühl bestanden, das sich zunächst nicht messen ließ — und zweimal saß darunter ein echter, technischer Fehler. Diese Besessenheit, die Kollegen manchmal die Augen verdrehen lässt, ist in Wahrheit ein Präzisionsinstrument.

**Und der ehrlichste Punkt zum Schluss:** Ich hätte das allein nicht gebaut. Nicht in zehn Tagen, wahrscheinlich nicht in zehn Monaten. Ein KI-Pair-Programmer hat aus „einem Designer mit einer Idee" jemanden gemacht, der **shippen** kann. Ich habe nie aufgehört, Designer zu sein — ich habe nie eine `for`-Schleife von Hand geschrieben. Ich habe gefühlt, gezeigt, verworfen, entschieden. Er hat die Geometrie durchgerechnet, die Toolchain gebändigt und meine „hm, das fühlt sich falsch an"-Sätze in echte Fixes übersetzt.

Zehn Tage. 97 Commits. Ein paar besiegte Monster. Und eine kleine App, die Comics wieder wie Papier aussehen lässt — geboren aus einem Rest Wochen-Tokens, der sonst um Punkt zwölf verfallen wäre.

Nächstes Ziel auf der Karte, für alle Neugierigen: Panels automatisch erkennen und sanft heranzoomen — direkt auf dem Gerät, sparsam und schnell. Aber das, liebe Leser, ist eine Geschichte für ein anderes Logbuch.
