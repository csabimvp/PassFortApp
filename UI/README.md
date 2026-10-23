# UI

The app's visual design: the colour tokens the build uses, and the mockups they came from.

| Path | What it is | Used by the build |
|---|---|---|
| `tokens.json` | Every app colour, light and dark: brand, success / warning / danger / favorite, and the five category families | Yes, through `scripts/gen_palette.swift`, `scripts/make_icon.swift` and `scripts/make_readme_art.swift` |
| `mockups/` | The design canvas the palette was worked out on (2026-10-22). Gitignored, local only | No, reference only |

## Changing a colour

1. Edit `tokens.json`. Colours are `#RRGGBB`, a `light` and a `dark` value each.
2. Regenerate:

   ```bash
   swift scripts/gen_palette.swift
   ```

   This rewrites `PassFort/Support/PaletteTokens.swift` and
   `PassFort/Assets.xcassets/AccentColor.colorset/Contents.json`. Both are generated, so never edit
   them by hand. Both are committed, so the app builds without this step. CI re-runs the generator
   and fails if either file has drifted from `tokens.json`.
3. If the brand changed, regenerate the app icon, whose tile runs from the dark-mode brand down to
   the light-mode brand:

   ```bash
   swift scripts/make_icon.swift PassFort/Assets.xcassets/AppIcon.appiconset
   ```

4. Regenerate the README banner (`docs/images/hero-light.svg` and `hero-dark.svg`), which draws
   the icon and a small vault window from the brand, semantic and family tokens:

   ```bash
   swift scripts/make_readme_art.swift
   ```

   CI checks neither the icon nor the banner for drift, so these two steps are on you.
5. Build the app as usual.

The generator rejects a malformed colour, a non-identifier name, or a category listed twice. It
warns, but still writes, when white text on the brand colour drops below WCAG contrast (4.5:1 in
light mode, 3:1 for dark-mode controls): buttons and list selection draw white on it.

## Tokens

- **`brand`**: the accent. `Palette.primary`, the root `.tint`, and the AccentColor asset that
  AppKit-drawn controls (focus rings, selection) use.
- **`semantic`**: `Palette.success`, `Palette.warning`, `Palette.danger`, `Palette.favorite`.
  Warning is amber, not orange, so orange only ever means PassFort. Favorite is the star's gold, a
  step brighter than warning so a star never reads as an alert. Views use these, never the system
  `.red` / `.green` / `.orange` / `.yellow`.
- **`tile`**: the opacity of a family colour drawn as a background behind its own glyph
  (`Palette.tint(_:)`), in light and dark.
- **`families`**: five hues shared by the eleven categories. `categories` uses the
  `AccountCategory` case names. Every case must appear exactly once. A missing or misspelt case
  becomes a compile error in the generated `AccountCategory.family` switch. In Swift:
  `Palette.color(category.family)` and `Palette.tint(category.family)`.

Adding a token kind (a new top-level key) means extending `Tokens` and `swiftSource` in
`scripts/gen_palette.swift` alongside the JSON.

## Where the app draws it

The shared parts live in `PassFort/Support/VisualParts.swift`: `CategoryTile` (the family-tinted
initial on list rows, health rows and the detail header), `StrengthLevel` with `Pill` and
`StrengthMeter`, `CountdownRing` (the one-time code), `Toast`, `ClassedPassword` (a revealed
password with digits in the personal blue and symbols in the brand colour), and `IconButton` (the
grey copy and reveal icons, so actions never draw in the brand colour). The sidebar colours
each icon by meaning and draws the Password Health count as a danger badge; Password Health opens
with a score ring; the unlock screen warns when Caps Lock is on.

The generator follows the mockup's card, Words mode included (passphrases from the EFF large word
list). The add / edit form has no mockup of its own; it borrows the detail view's header (tile,
title, category in its family colour, the star) and section order, shows the password's strength
under it with the generator in a popover, and keeps the rarer fields (one-time code, PIN, memorable
word, expiry, security questions, recovery codes, custom fields) behind an Add Field menu until
they hold something.

Not built from the mockups, because the feature behind them doesn't exist yet: the sidebar's sync
status (M5), Undo on the delete toast, and the health rows' Change… button. The detail view follows the mockup's cards on the system grouped `Form`, then shows Details,
History and Stats in full rather than behind the mockup's "Advanced" toggle: everything the record
holds is on screen once it is selected. The search field sits in the list column's
header and the account's star and Edit lead the detail toolbar, as in the mockup.

## Mockups

`mockups/` holds the design canvas the palette and the visual parts were worked out on. It is
**gitignored and kept locally only**, so it is not in this repository; its own `README.md`, next to
the files, explains how to view and edit them. Nothing in the build reads it.
