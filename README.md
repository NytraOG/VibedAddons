# WoW Forever AddOn Dev

Addon-Entwicklung für den **World of Warcraft: Forever**-Beta-Client (`_classic_beta_`).

- Lua: **5.1** (Blizzards angepasstes 5.1.4)
- TOC: `## Interface: 16001`
- Der Client basiert auf **Retail** (`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`), nicht auf Classic.
  Also `C_Spell`/`C_Item`/`C_UnitAuras` statt `GetSpellInfo`/`GetItemInfo`/`UnitAura`,
  und im Kampf gibt es Secret-Values wie in Midnight.

## Struktur

| Pfad | Inhalt |
|---|---|
| `AddOns/` | Unsere Addons, je ein Ordner pro Addon |
| `wow-ui-source/` | Blizzards UI-Quellcode, Branch `forever` von [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) (nicht im Git) |
| `docs/api-reference.html` | Durchsuchbare API-Referenz, generiert (nicht im Git) |
| `tools/` | Generator für die Referenz, Link-Skript |

## Einrichten / Aktualisieren

```sh
# UI-Quellcode holen (einmalig)
git -c core.longpaths=true clone --depth 1 -b forever https://github.com/Gethe/wow-ui-source wow-ui-source
git -C wow-ui-source config core.longpaths true

# Nach einem neuen Beta-Build: Quellcode aktualisieren und Referenz neu bauen
git -C wow-ui-source pull
python tools/build_api_reference.py
```

Prüfen, ob der Quellcode zum Client passt: `wow-ui-source/version.txt` muss dem Build in
`_classic_beta_/../.build.info` entsprechen (im Spiel: `/dump GetBuildInfo()`).

## Addons ins Spiel verlinken

```powershell
pwsh tools/link-addons.ps1
```

Legt für jeden Ordner in `AddOns/` eine Junction im AddOns-Ordner des Clients an. Danach reicht im Spiel `/reload`.

## API-Referenz

`docs/api-reference.html` im Browser öffnen. Pro Funktion bzw. Event gibt es dort:
- Signatur mit Typen und Rückgabenamen, verlinkte Strukturen und Enums
- Badges für Secret- und Restriktions-Flags (geschützt, secret wenn …, nie secret, …)
- Blizzards Erklärtext, falls vorhanden
- Aufrufbeispiele aus Blizzards eigenem UI-Code (mit GitHub-Link)
- Link zur Seite im Warcraft Wiki
