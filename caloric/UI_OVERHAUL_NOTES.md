# caloric — UI-Redesign "Caloric Ice" (helles Fitness-Design)

Komplettes visuelles Redesign von Dashboard, Daily Journal, Settings und
Onboarding. **Keine State-Variablen, Bindings, Berechnungen oder Logik wurden
verändert** — nur die visuelle Hülle. Die Informationsarchitektur (Tabs,
Screens, Sheets, Flows) ist unverändert.

## Designsystem

- **Helle Fläche:** kühler Eis-Verlauf (`#FBFDFF → #EFF6FB`) mit weichem
  Caloric-Blau-Halo am oberen Rand (`CaloricBackground`).
- **Caloric-Blau-Familie:** `accentSky #66CCFF` (Original-Markenton, für
  Verläufe/Halos) → `accentBlue #119BE8` (interaktiver Primärton, lesbar auf
  Weiß) → `accentDeep #0B7BC4`. Der Signatur-Verlauf Sky→Azure zieht sich durch
  Ring, CTAs, Avatar-Chip und Auswahl-Zustände.
- **Karten:** Weiß, Hairline-Kontur, weicher blau getönter Schatten
  (`GlassCardBackground` — API unverändert, alle `.glassCard()`-Call-Sites
  profitieren automatisch).
- **Typografie:** komplett auf **SF Rounded** umgestellt (sportlicher
  Fitness-Charakter, kräftige Zahlen). Alle `PingFangSC`-Fonts ersetzt.
- **Text:** Tinte `#0E212E` / Slate `#5D7183` statt Weiß-Abstufungen.
- **Energie-Farben:** auf hellem Grund nachjustiert (satteres Grün/Indigo/
  Violett/Amber), BMR = Caloric-Azure.

## Struktur-Änderungen (visuell)

- **Dashboard-Header:** Datum jetzt als weiße Pill mit Kalender-Icon,
  Profil-Button als Verlaufs-Chip.
- **Kalorienring:** heller runder Track, Fortschritt im Sky→Azure-Verlauf,
  neuer gefüllter CTA "Aufschlüsselung ansehen".
- **Onboarding-Welcome:** zentriertes Brand-Hero (Logo im Blau-Halo, große
  Headline, Verlaufs-CTA).
- **Journal-Header:** gleiche Datum-Pill wie im Dashboard.
- **Profil-Panel & Sheets:** helle Flächen (`Theme.canvas`), keine erzwungene
  Dark-Appearance mehr — App läuft durchgängig mit `.light`.

## Kompatibilität

`Theme.obsidian`/`obsidianLift`/`glassFill`/`glassStroke` existieren als
Aliasse auf die neuen hellen Tokens; `ObsidianBackground` ist ein Typalias auf
`CaloricBackground`. Bestehende Call-Sites kompilieren unverändert.

## Unangetastet

Alle `Utils/*`-Services, `UserProfile`, `JournalStore`, HealthKit-Import,
Gemini-Integration, Berechnungen und sämtliche Daten-Bindings.
