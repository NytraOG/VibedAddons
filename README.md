# VibedAddons

Addons für den **World of Warcraft: Forever**-Beta-Client (`_classic_beta_`, Interface 16001).

| Addon | Befehl | Kurz |
|---|---|---|
| [Kontor](#kontor) | `/kontor` | Finanz-Journal, Auktionshaus-Scan, Preis-Tooltips, Preisverlauf, Margenrechner |
| [Sanity Enricher](#sanity-enricher) | `/sanity` | Quests automatisch, Müll verkaufen, reparieren, Fenster verschieben |

## Installation

1. Den Ordner des Addons aus `AddOns/` (z.B. `AddOns/Kontor`) nach
   `World of Warcraft\_classic_beta_\Interface\AddOns\` kopieren.
   Alternativ alle Addons per Junction verlinken, siehe [Entwicklung](#addons-ins-spiel-verlinken).
2. Den Client neu starten. Ein `/reload` genügt für neue Addons nicht.
3. Im Addon-Menü des Charakterbildschirms prüfen, dass das Addon aktiv ist.

Beide Addons haben einen Minimap-Button und einen Eintrag im Addon-Menü an der Minimap.
Der Eintrag im Addon-Menü erscheint nur, wenn das Addon für **alle Charaktere** aktiviert ist.

---

## Kontor

Behält Gold, Auktionshaus und Berufe im Blick.

### Erste Schritte

1. Auktionshaus öffnen und oben auf **Kontor: Komplett-Scan** klicken (ca. 20 Sekunden).
   Danach gibt es Preise in Tooltips, Margen und den Preisverlauf. Ein neuer Scan ist erst
   nach der Sperrzeit des Auktionshauses wieder möglich; der Button zeigt die Restzeit.
2. Regelmäßig scannen: Jeder Scan landet im Verlauf und liefert Preis-Pfeile und Graph.

### Funktionen

- **Finanz-Journal:** Verkäufe, Käufe, abgelaufene und abgebrochene Auktionen. Erfasst wird
  über Auktionshaus-Meldungen und beim Abholen der Post.
- **Preis-Tooltips:** Auktionshauspreis (Durchschnitt der 5 günstigsten Angebote) und Händlerpreis
  in jedem Item-Tooltip, auf Wunsch mit Pfeil gegenüber einem älteren Scan.
- **Margenrechner:** Im Berufe-Fenster zeigt der Tooltip eines Rezepts Materialkosten, Erlös und
  Marge. Zwischenprodukte werden auf dem günstigsten Weg gerechnet (kaufen oder selbst herstellen).
- **Margen-Liste:** Alle bekannten Rezepte, sortierbar nach Marge.
- **Preisverlauf:** Graph über alle Scans. Links Items suchen und anklicken, bis zu 8 gleichzeitig.
  Oben lassen sich Preisart (Ø 5 günstigste oder günstigstes Angebot) und Zeitraum wählen.

### Bedienung

| | |
|---|---|
| `/kontor` | Journal öffnen/schließen |
| `/kontor margen` | Margen-Liste |
| `/kontor verlauf` | Preisverlauf |
| `/kontor scan` | Komplett-Scan (Auktionshaus muss offen sein; `force` ignoriert die Sperrzeit) |
| `/kontor status` | Gespeicherte Daten anzeigen |
| `/kontor minimap` | Minimap-Button ein-/ausblenden |
| `/kontor optionen` | Optionen |
| Minimap-Button | Linksklick: Journal · Rechtsklick: Margen-Liste · Shift-Linksklick: Preisverlauf |

**Optionen** (Esc → Optionen → AddOns → Kontor, oder Zahnrad im Fenster): Schwellen für die
Preis-Pfeile, Vergleichs-Scan, Preise und Margen in Tooltips ein/aus, angenommene AH-Gebühr,
Anzahl gespeicherter Scans, Minimap-Button.

---

## Sanity Enricher

Kleine Komfortfunktionen, jede einzeln abschaltbar.

- **Quests:** automatisch annehmen und abgeben. Bei einer Belohnungswahl wird angehalten.
  Graue und wiederholbare Quests sowie das Bestätigen von Gruppenquests sind getrennt schaltbar.
- **Händler:** Müll (graue Items) automatisch verkaufen und reparieren, auf Wunsch zuerst über die Gildenbank.
- **Fenster verschieben:** Taschen, Berufe, Auktionshaus und andere Standardfenster am Hintergrund
  ziehen. Die Positionen bleiben auf Wunsch über das Ausloggen hinaus erhalten.
- **Shift gedrückt halten** pausiert alle Automatiken, etwa um eine Quest selbst zu lesen.

| | |
|---|---|
| `/sanity` | Optionen öffnen |
| `/sanity an` · `aus` · `toggle` | Addon ein-/ausschalten |
| `/sanity minimap` | Minimap-Button ein-/ausblenden |
| `/sanity fenster` | Fensterpositionen zurücksetzen |
| Minimap-Button | Linksklick: ein/aus · Rechtsklick: Optionen |

---

## Entwicklung

Forever basiert auf dem **Retail**-Client (`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`), nicht auf Classic:
`C_Spell`/`C_Item`/`C_UnitAuras` statt `GetSpellInfo`/`GetItemInfo`/`UnitAura`, im Kampf Secret-Values
wie in Midnight. Lua 5.1 (Blizzards angepasstes 5.1.4). Arbeitsweise und gelernte Fallstricke stehen
in [CLAUDE.md](CLAUDE.md).

| Pfad | Inhalt |
|---|---|
| `AddOns/` | Die Addons, je ein Ordner |
| `tools/` | Lua-Prüfung, API-Referenz-Generator, Link-Skript |
| `wow-ui-source/` | Blizzards UI-Quellcode, Branch `forever` von [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) (nicht im Git) |
| `docs/api-reference.html` | Durchsuchbare API-Referenz, generiert (nicht im Git) |

### Einrichten

```sh
# UI-Quellcode holen
git -c core.longpaths=true clone --depth 1 -b forever https://github.com/Gethe/wow-ui-source wow-ui-source
git -C wow-ui-source config core.longpaths true

# Python-Umgebung für die Lua-Prüfung
python -m venv tools/.venv
tools/.venv/Scripts/python -m pip install lupa

# API-Referenz bauen (docs/api-reference.html)
python tools/build_api_reference.py
```

Nach einem neuen Beta-Build: `git -C wow-ui-source pull` und die Referenz neu bauen.
`wow-ui-source/version.txt` muss zum Client-Build passen (`_classic_beta_/../.build.info`,
im Spiel `/dump GetBuildInfo()`).

### Addons ins Spiel verlinken

```powershell
pwsh tools/link-addons.ps1
```

Legt für jeden Ordner in `AddOns/` eine Junction im AddOns-Ordner des Clients an. Danach reicht
für Codeänderungen ein `/reload`; neue Dateien in einer TOC brauchen einen Client-Neustart.

### Prüfen

```sh
tools/.venv/Scripts/python tools/check_lua.py
```

Prüft die Lua-5.1-Syntax aller Addons und ob jede in der TOC genannte Datei existiert.

### API-Referenz

`docs/api-reference.html` im Browser öffnen. Pro Funktion bzw. Event gibt es dort:
- Signatur mit Typen und Rückgabenamen, verlinkte Strukturen und Enums
- Badges für Secret- und Restriktions-Flags (geschützt, secret wenn …, nie secret, …)
- Blizzards Erklärtext, falls vorhanden
- Aufrufbeispiele aus Blizzards eigenem UI-Code (mit GitHub-Link)
- Link zur Seite im Warcraft Wiki
