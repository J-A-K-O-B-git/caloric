# caloric — UI-Redesign "Caloric Ice" (adaptiv: Hell & Dunkel)

Komplettes visuelles Redesign von Dashboard, Daily Journal, Settings und
Onboarding. **Keine State-Variablen, Bindings, Berechnungen oder Logik wurden
verändert** — nur die visuelle Hülle. Die Informationsarchitektur (Tabs,
Screens, Sheets, Flows) ist unverändert.

## Zwei Erscheinungsbilder, ein Designsystem

Alle Oberflächen-Tokens in `Theme.swift` sind **dynamische Farben** und
wechseln automatisch mit dem Farbschema:

| Token          | Hell ("Ice")            | Dunkel ("Night")        |
|----------------|-------------------------|-------------------------|
| canvas         | #EFF6FB Eis-Verlauf     | #0B0E12 tiefes Kühlblau |
| canvasLift     | #FBFDFF                 | #131922                 |
| card           | Weiß                    | #161E28 angehoben       |
| textPrimary    | #0E212E Tinte           | #EDF4FA                 |
| textSecondary  | #5D7183 Slate           | #90A2B3                 |
| cardShadow     | Blau getönt, weich      | Schwarz, tief           |

Die **Caloric-Blau-Familie** ist in beiden Modi identisch:
`accentSky #66CCFF` (Verläufe/Halos) → `accentBlue #119BE8` (Primärton) →
`accentDeep #0B7BC4`. Signatur-Verlauf Sky→Azure auf Ring, CTAs, Avatar-Chip
und Auswahl-Zuständen. Typografie: durchgängig **SF Rounded**.

## Erscheinungsbild-Umschalter (System / Hell / Dunkel)

- `AppearanceMode` (Theme.swift) — gespeichert via
  `@AppStorage("caloricAppearanceMode")`, Default: **System** (folgt dem
  Gerätemodus).
- `` — ViewModifier, der den gewählten Modus als
  `preferredColorScheme` anwendet. Aktiv auf App-Root (`caloricApp`) und auf
  allen Sheets (ersetzt die früheren erzwungenen Schemata).
- `AppearancePicker` — segmentierter Umschalter, eingebaut an zwei Stellen:
  1. **Dashboard → Profil-Panel** (Avatar oben rechts) — Sektion "Darstellung"
  2. **SettingsView** — Karte "Darstellung"
  Die Umschaltung wirkt sofort und app-weit.

## Struktur-Änderungen (visuell)

- **Dashboard-Header:** Datum als Karten-Pill mit Kalender-Icon,
  Profil-Button als Verlaufs-Chip.
- **Kalorienring:** runder Track, Fortschritt im Sky→Azure-Verlauf,
  gefüllter CTA "Aufschlüsselung ansehen".
- **Onboarding-Welcome:** zentriertes Brand-Hero (Logo im Blau-Halo).
- **Journal-Header:** gleiche Datum-Pill wie im Dashboard.

## Kompatibilität

`Theme.obsidian`/`obsidianLift`/`glassFill`/`glassStroke` sind Aliasse auf die
adaptiven Tokens; `ObsidianBackground` ist ein Typalias auf
`CaloricBackground`. Bestehende Call-Sites kompilieren unverändert.

## Unangetastet

Alle `Utils/*`-Services, `UserProfile`, `JournalStore`, HealthKit-Import,
Gemini-Integration, Berechnungen und sämtliche Daten-Bindings.
