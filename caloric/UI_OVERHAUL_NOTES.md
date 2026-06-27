# caloric — Premium Dark UI Overhaul

A visual-only overhaul of the Dashboard, Daily Journal, and Settings. **No state
variables, bindings, calculations, or logic were changed** — only the visual shell,
plus one new presentation feature (the energy breakdown sheet).

## Where these files go
Drop these back into your Xcode project's source group (`caloric/caloric/…`),
replacing the existing files. Folder structure is unchanged.

## Files changed
- **Utils/Theme.swift** — added the premium dark design system: `obsidian` palette,
  `ObsidianBackground`, `GlassCardBackground` + `.glassCard()` modifier, and the
  harmonious energy-segment accent colors. Your `accentBlue` (#66CCFF) is untouched
  and still drives every ring, value, and selected state.
- **Onboarding/MainTabView.swift** — the signed-in app now runs as a forced dark
  experience (`.preferredColorScheme(.dark)`). Onboarding is left as-is.
- **Onboarding/DashboardView.swift**
  - Obsidian background + glassmorphic cards everywhere (blue-tinted fills → frosted
    glass with hairline strokes).
  - Reworked calorie ring: crisp white value, blue progress ring with glow, "BURNED"
    label.
  - **Burned-calories card is now fully tappable** (the whole card, not just a small
    link) → opens the breakdown sheet.
  - **Rebuilt breakdown sheet** — big total, a stacked micro-chart of all components,
    and per-component cards (BMR / NEAT / EAT / TEF / Caffeine) each with kcal, % of
    total, and a thin horizontal progress bar. "How is this calculated?" still links
    through to the full formula view, now on an obsidian backdrop.
- **Onboarding/DailyJournalView.swift** — obsidian background, white title, glass
  cards. Every input, toggle, and field is preserved exactly.
- **Onboarding/SettingsView.swift** — obsidian background, glass cards, dark edit sheets.

## Untouched
ContentView (onboarding), all `Utils/*` services, `UserProfile`, `JournalStore`,
HealthKit import, calculations, and every data binding.
