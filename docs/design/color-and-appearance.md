# Color and Appearance

Status: implemented, pending user verification  
Last updated: 2026-07-13

This note records the reversible UI design choices agreed during the color-system review. It is not an ADR: these choices are localized and inexpensive to change. It is also not a domain glossary, so it does not belong in `CONTEXT.md`.

## Guiding direction

- Prefer Apple dynamic system colors and semantic foreground/background roles over a hand-authored Light/Dark palette.
- The product targets international market conventions only: positive performance is green and negative performance is red. China-specific red-up/green-down behavior is out of scope.
- Color must not be the only indication of financial direction, status, or destructive intent.

## Agreed decisions

### Semantic color roles

- Keep the application-level palette deliberately small: `accent`, `positivePerformance`, `negativePerformance`, and `warning`.
- Use the international-market convention: positive performance is system green and negative performance is system red.
- Do not create separate theme tokens for error, destructive, disabled, or connection actions by default. Prefer the relevant system component role or semantic foreground treatment at the point of use.
- A normal connection action uses the global accent unless a future product requirement establishes an independent, durable meaning for another color.

### Global accent

- Use the default Apple system accent (`systemBlue`) for interactive emphasis.
- Replace the misleading `blue = systemTeal` concept with `accent = Color.accentColor` when implementation begins.
- Remove the empty `AccentColor.colorset` and both `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` build settings when implementation begins, so the app inherits the system accent instead of mixing an empty global accent with local teal overrides.
- Let system controls inherit the default accent instead of applying page-local teal tints; use the shared accent role only where custom drawing needs the same color.
- A separate Bittern brand color has not been established. Teal must not remain implicitly coupled to interaction merely because the current token is named `blue`.

### Panel depth

- Remove the custom Light/Dark black-shadow opacity branch when implementation begins.
- Express panel separation using the existing dynamic `secondarySystemBackground` surface and `separator` outline.
- Do not introduce a replacement custom Dark Mode shadow unless visual testing reveals a concrete hierarchy problem.

### Allocation colors and ticker avatars

- Keep saturated allocation colors for donut-chart segments.
- Render ticker/avatar circles with a subtle allocation-color tint rather than a fully saturated fill.
- Render ticker text with the dynamic primary ink color rather than fixed white.
- Preserve the color association between a holding's chart segment and avatar while treating chart color and text-background color as different presentation needs.

### Financial chart range selection

- The selected range control uses the same computed performance color as its chart line: green for a positive interval, red for a negative interval, and the neutral secondary color when the interval is flat or unavailable.
- This is an intentional exception to the general blue-accent rule because the selection is part of a financial performance visualization, not merely a generic navigation state.
- Remove the current hard-coded positive green from both holding-history and portfolio-history range controls.

### Informational allocation badge

- Treat the allocation percentage in the Holding Detail "My Holdings" panel as neutral information, not an action or performance result.
- Render it with dynamic primary ink on `secondarySystemFill`, replacing the fixed white foreground and solid accent background.

### Status colors

- Use system green for connected and success feedback at the point of use.
- Use the shared warning role, backed by system orange, for pending states and disabled brokerage connections.
- Use system red at the point of use for errors and destructive actions.
- Use the secondary label color for ordinary disabled, unavailable, or missing-data presentation.
- Reserve positive/negative performance roles for financial values, except where a chart range intentionally mirrors its computed performance color.

### Appearance preference

- Keep the in-app Automatic / Light / Dark appearance switch.
- Automatic remains the default and follows the system appearance.
- The explicit Light and Dark options are intentional product overrides, even though Apple generally recommends relying on the system-wide preference.
- Present Automatic / Light / Dark with a native segmented `Picker` rather than three custom appearance cards.

### SnapTrade action hierarchy

- Saving credentials is the primary action because it registers credentials when needed and refreshes SnapTrade-backed portfolio data.
- Connecting a brokerage is a secondary action that opens the SnapTrade connection portal.
- The Connect button in the credentials panel and the top-right toolbar button are duplicate entry points: both invoke the same connection-portal flow.
- Use the system accent for both actions and express their hierarchy through button style rather than separate teal and purple hues.
- Use the native prominent button style for Save and the native bordered style for Connect; remove their custom teal and purple button styles.
- Keep the clearly labeled secondary Connect action in the credentials panel.
- Replace the duplicate top-right connection-portal action with Clear Credentials, and remove Clear from the panel action row.
- Keep the toolbar Clear Credentials action visible even when no credentials are stored.
- Clear Credentials executes immediately without a confirmation dialog.
- Clearing must be idempotent: invoking it with no stored credentials is a harmless no-op rather than a Keychain error.
- Use the destructive `trash` symbol for the toolbar Clear Credentials action.

### Settings structure

- Build Settings with native `Form` and `Section` containers instead of a scroll view of custom panel cards.
- Present Automatic / Light / Dark as a segmented `Picker` in the Appearance section.
- Present History, Portfolio Accounts, and Credentials as native `NavigationLink` rows with system labels and disclosure behavior.
- Keep intentional plain styles for unrelated custom controls such as dashboard tabs and chart range selectors; do not perform an app-wide button-style rewrite.

## Resulting fixed-white treatment

- Ticker/avatar labels use dynamic ink on tinted allocation backgrounds.
- Save and Connect delegate foreground treatment to native button styles.
- The custom selected Appearance tile is removed in favor of a segmented picker.
- The Holding Detail allocation badge uses dynamic ink on a semantic fill.
- The resulting removal of explicit `.white` is a consequence of semantic component choices, not an independent zero-hard-coded-white goal.

## Verification boundary

The Swift source, asset catalog, and Xcode build settings described above are implemented in the current workspace. Build and runtime testing are intentionally left to the user.
