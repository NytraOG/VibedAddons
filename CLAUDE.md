# WoW Forever AddOn Dev

Addon-Entwicklung für den **World of Warcraft: Forever**-Beta-Client. Kommunikation mit dem User auf **Deutsch**.

## Umgebung

| | |
|---|---|
| Client | `X:\Spielplatz\BattleNet\World of Warcraft\_classic_beta_` (`WowB.exe`) |
| Build bei Einrichtung | 1.60.1.70338 (`.build.info` eine Ebene höher; im Spiel `/dump GetBuildInfo()`) |
| Lua | 5.1 (Blizzards Variante): kein `goto`, kein `//`, Bit-Ops über `bit.*` |
| TOC | `## Interface: 16001` |
| Spieltyp | `camelot` (in Blizzards TOCs Teil der Familie `mainline`) |

**Forever basiert auf dem Retail-Client, nicht auf Classic.** `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`; also `C_Spell`, `C_Item`, `C_UnitAuras`, `C_TradeSkillUI`, `C_AuctionHouse` usw. Klassische Globals wie `GetSpellInfo`, `GetItemInfo`, `UnitAura`, `GetMerchantItemInfo`, `CombatLogGetCurrentEventInfo` fehlen. Im Kampf gibt es Midnight-artige Secret-Values (`issecretvalue`, `C_Secrets`).
Retail-Versionsprüfungen wie `>= 100000` greifen nicht, weil `GetBuildInfo()` 16001 liefert. Forever erkennt man so: `local b = select(4, GetBuildInfo()); isForever = b >= 16000 and b < 20000`.

## Repo-Struktur

| Pfad | Inhalt |
|---|---|
| `AddOns/<Name>/` | Unsere Addons, per Junction im Client verlinkt |
| `wow-ui-source/` | Blizzards UI-Quellcode, Branch `forever` von Gethe/wow-ui-source (nicht im Git) |
| `docs/api-reference.html` | Durchsuchbare API-Referenz, generiert (nicht im Git) |
| `tools/build_api_reference.py` | Erzeugt die Referenz neu |
| `tools/check_lua.py` | Lua-5.1-Syntaxprüfung aller Addons + TOC-Dateiliste (lupa) |
| `tools/link-addons.ps1` | Verlinkt jedes Addon aus `AddOns/` in den Client |
| `tools/.venv/` | Python-Umgebung mit `lupa` (nicht im Git) |

Nach einem Beta-Patch: `git -C wow-ui-source pull`, `python tools/build_api_reference.py`, und prüfen, ob `wow-ui-source/version.txt` zum Client-Build passt.

## Arbeitsweise

1. **APIs nie raten.** Vor jeder Verwendung prüfen:
   - in `wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`: Existenz, Signatur, Flags wie `SecretArguments`, `HasRestrictions`, `IsProtectedFunction`, `MayReturnNothing`;
   - wie Blizzards eigener Code sie aufruft;
   - bei Bedarf warcraft.wiki.gg (Retail-Seiten passen meist).
   Undokumentierte Legacy-Globals (Mail, Merchant, TradeSkill) gelten nur dann als vorhanden, wenn Blizzards Camelot/Mainline-Code sie aufruft.
   Welche Datei für Forever lädt, steht in der `.toc` des Blizzard-Addons: `[Game]`/`[AllowLoadGameType camelot]` lädt, `[ExcludeLoadGameType camelot]` lädt nicht.
2. **Größere Addons in Etappen bauen.** Nach jeder Etappe testet der User im Spiel und meldet Fehler (Screenshot oder Fehlertext).
3. **Vor jeder Übergabe:** `tools/.venv/Scripts/python tools/check_lua.py`. Heikle Logik zusätzlich mit lupa-Mocks testen (WoW-APIs als Lua-Stubs, Szenarien durchspielen; Mock-Skripte gehören ins Scratchpad).
4. **`/reload` reicht für Codeänderungen.** Neue Dateien in der TOC oder geänderte TOC-Metadaten brauchen einen **kompletten Client-Neustart**. Das dem User jeweils sagen.
5. **Git:** Nur lokal committen (Branch `master`). Es gibt kein Remote. **Nie pushen** ohne ausdrückliche Anweisung.

## Neues Addon: Checkliste

1. Ordner `AddOns/<Name>/` anlegen, TOC mit `## Interface: 16001`, `## Title`, `## Version`, ggf. `## SavedVariables`, `## IconTexture`.
2. Struktur wie Kontor: `Util.lua` (Print, Formatierung), `Core.lua` (Event-Verteiler `ns.On`, DB-Init auf `ADDON_LOADED`, Slash-Befehle über `ns.commands`), danach Feature-Dateien, `UI/` für Fenster.
3. `pwsh tools/link-addons.ps1` ausführen, dann den Client neu starten.
4. Für Addon-Menü und Minimap: `## AddonCompartmentFunc` in die TOC. Der Eintrag erscheint nur, wenn das Addon für **alle Charaktere** aktiviert ist und der Client neu gestartet wurde. Zusätzlich einen eigenen Minimap-Button anbieten (Vorlage: `AddOns/Kontor/UI/MinimapButton.lua`).

Wiederverwendbare Bausteine in Kontor, die man kopieren und anpassen kann:
- `UI/Widgets.lua`: Fenster und Dropdown
- `UI/Table.lua`: sortierbare ScrollBox-Tabelle
- `UI/MinimapButton.lua`: Minimap-Button
- `Core.lua`: Event-Verteiler

## Forever-Fallstricke (gelernt)

- **Unbekannte Events** in `RegisterEvent` werfen einen Fehler und brechen die Datei ab, deshalb mit `pcall` registrieren. **Hooks** (`hooksecurefunc`) auf eventuell fehlende Funktionen ebenfalls per `pcall`.
- **`%d` in `string.format`** kann nur 32 Bit. Goldbeträge können größer sein (AH-Höchstpreis 99999999999 Kupfer), daher `%.0f`.
- **OnUpdate-Schleifen:** Den Index *vor* dem Verarbeiten erhöhen und den Eintrag per `pcall` lesen. Sonst wiederholt ein fehlerhafter Eintrag den Fehler in jedem Frame.
- **SavedVariables** werden korrekt geschrieben und zurückgeladen (getestet).
- **Tooltips:** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`; `data.id` ist die itemID. Dasselbe Item kann zweimal pro Tooltip gemeldet werden, daher pro Tooltip deduplizieren und bei `OnTooltipCleared` zurücksetzen. Woher der Tooltip kommt, steht in `tooltip.processingInfo.getterName`/`getterArgs`, zum Beispiel `GetBagItem` → Stapelgröße per `C_Container.GetContainerItemInfo`.
- **Auktionshaus** (`C_AuctionHouse`, Retail-Stil mit Commodities):
  - Komplett-Scan: `ReplicateItems()` → `REPLICATE_ITEM_LIST_UPDATE`. Indizes beginnen bei 0. Ca. 91.000 Auktionen in ca. 19 s. `owner` ist immer nil. Die Sperrzeit ist vermutlich 15 Minuten.
  - `AUCTION_CANCELED` feuert für **jede** eigene Auktion, die aus der Liste verschwindet, auch bei Ausverkauf. Ein echter Abbruch ist es nur über `CancelAuction`.
  - Verkauft/abgelaufen online: `AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(notification, text, auctionID)`, kein `CHAT_MSG_SYSTEM`.
  - Erlöse kommen wie in Classic mit Verzögerung per Post.
- **Post:** `GetInboxInvoiceInfo(i)` liefert `invoiceType ("seller"/"buyer"), itemName, playerName, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin, count, commerceAuction`. Post hat keinen Zeitstempel, nur `daysLeft`. Verbuchen über `hooksecurefunc` auf `TakeInboxMoney`/`TakeInboxItem`/`AutoLootMailItem`.
- **Händler:** Preise gibt es nur bei offenem Fenster, über `C_MerchantFrame.GetItemInfo(i)` (price, stackCount, numAvailable, hasExtendedCost) und `GetMerchantItemID(i)`.
- **Berufe** (Retail-Professions-UI, load-on-demand):
  - Rezeptliste-Hover: `EventRegistry:RegisterCallback("Professions.RecipeListOnEnter", fn(_, button, data))`. Blizzard zeigt dort sonst keinen Tooltip.
  - Rezeptdaten: `C_TradeSkillUI.GetRecipeSchematic(id, false)`.
  - `GetFilteredRecipeIDs` hängt von UI-Filtern ab.
  - Ergebnis-Item-Tooltip: `getterName == "GetRecipeResultItem"`. Er wird jeden Frame neu gesetzt.
- **UI:** `BasicFrameTemplateWithInset` (`.TitleText`), `WowScrollBoxList` + `MinimalScrollBar` + `CreateScrollBoxListLinearView` (`SetElementInitializer("Button", fn)` braucht `SetElementExtent`), `WowStyle1DropdownTemplate` mit `SetupMenu`/`CreateRadio`, `MenuUtil.CreateContextMenu`, `SearchBoxTemplate`. Die Standardschrift kennt keine Pfeil-Unicode-Zeichen.
- **Geldbeträge in Spalten:** Rechtsbündiger Text ist nicht pixelgenau (WoW rundet Glyphen beim Rendern anders als `GetStringWidth`), daher springen Münz-Icons aus `GetMoneyString` um 1–3 px. Lösung: eigene FontStrings und Texturen (Atlas `coin-gold`/`coin-silver`/`coin-copper`) in festen Abständen vom rechten Rand, siehe `ns.CreateMoneyDisplay` und `ns.AddMoneyLine` in `AddOns/Kontor/UI/Widgets.lua`. Pfeil-Atlanten: `ui-hud-actionbar-pageuparrow-up`/`pagedownarrow-up` (entsättigt einfärbbar), Zahnrad: `questlog-icon-setting`.
- **Baganator/Syndicator** im Client: Die Autoren untersagen, ihren Code als Referenz zu nutzen. Daran halten; Blizzards Code genügt.

## User-Präferenzen

- Kurze, klare Beschriftungen im Spiel, keine erklärenden Langtexte in Tooltips.
- Annahmen (z.B. Sperrzeiten, Gebührensätze) offen als Annahme kennzeichnen und als Konstante leicht änderbar machen.

## Addons

- **Kontor** (`/kontor`, v0.6.0; bis 0.5.2 im Spiel getestet): Finanz-Journal (AH-Verkäufe, Käufe, Abgelaufen, Abgebrochen aus Events und Postbelegen), AH-Komplett-Scan mit Snapshot und Verlauf, Preis-Tooltips (Ø der 5 günstigsten Angebote, Ausreißer über dem 10-Fachen ausgenommen), Margenrechner im Berufe-Fenster (Zwischenprodukte günstigster Weg aus kaufen oder herstellen), Margen-Liste, Preis-Pfeile gegenüber einem älteren Scan (Material, Erlös, Marge, AH Ø), Optionen im Blizzard-Menü und per Zahnrad im Fenster (Werte in `ns.db.settings`, Standards in `ns.DEFAULTS`).
- **Sanity Enricher** (`/sanity`, v0.1.0, im Spiel getestet): QoL-Sammlung mit Modulen. Quests automatisch annehmen und abgeben (Halt bei Belohnungswahl), Müll verkaufen, reparieren (Gildenbank zuerst). Shift = Pause, Optionen im Blizzard-Menü (Proxy-Settings). Neue Module: Datei anlegen, Standardwerte als Unterbereich in `ns.DEFAULTS` (Core.lua), Checkboxen in `UI/Options.lua`.
