# Mouse Pomodoro — macOS app · Dev log

A native macOS **menu-bar** port of the Mouse Pomodoro Figma plugin: a tamagotchi-style
pomodoro timer with a pixel-art mouse companion. Non-punitive by design — nothing is ever lost,
only earned. Fully offline (no network entitlement, no accounts, no analytics).

- **Status:** feature parity with the Figma plugin reached (Phases 1–3 minus the dropped cloud sync);
  polish/bug-hunt pass done. **Not yet packaged for distribution** — see *Known gaps*.
- **Source of truth for behaviour:** the plugin's [`../Dev/DEV-LOG.md`](../Dev/DEV-LOG.md) and
  [`../Dev/README.md`](../Dev/README.md). This log only records what is *specific to the Mac app*
  and where it deliberately differs.
- **Design:** Figma file `1yS4QIV0NpFOJEl6S8MmpK` — `Design system` `39:3224`, `Final UI` `39:3225`,
  `minimized screens` `224:4458`, `15 - weekly-stats` `212:3796`.
- **Bundle id:** `com.soheeplays.MousePomodoro` · Swift 5 mode · SwiftUI + AppKit · **macOS 14+**
  (effective deployment target is `$(RECOMMENDED_MACOSX_DEPLOYMENT_TARGET)` = 14.0; the two-argument
  `onChange` needs it — the project-level 13.0 is overridden) · built with Xcode 27.

## Quick start

```bash
open MousePomodoro.xcodeproj          # ⌘R in Xcode, or:
xcodebuild -project MousePomodoro.xcodeproj -scheme MousePomodoro -configuration Debug build
```

Signing is **Automatic** with team `8VQQ8JN5VJ` (set in `project.pbxproj`) — change it to your own team
if you fork. An unsigned/ad-hoc build runs but **notifications are silently dropped** (see *Gotchas*).

The app is an *accessory* app (`LSUIElement`): no Dock icon, no menu bar menu. It lives in the status
item; **Quit** is in Settings → Session settings (there is no ⌘Q).

## Project layout

| File | What it is |
|---|---|
| `App.swift` | `@main`, `AppDelegate`: status item (icon + live `mm:ss` title), the full-size **popover**, the floating **compact panel**, notification delegate |
| `TimerEngine.swift` | The whole app logic as one `@MainActor ObservableObject`: state machine, timestamp timer, plan/auto-chain, credit, streak, note, weekly stats, scenes/shop, break interactions, persistence calls |
| `Store.swift` | Persisted schema (`Codable`) + tolerant decoding + `UserDefaults` load/save |
| `ContentView.swift` | All screens and overlays (Idle, Plan, Focus, Complete, Break, Entire-complete, Weekly stats, Settings+Shop, confirms, naming) and the compact strip |
| `DesignSystem.swift` | Color tokens, Pixelify Sans font helpers, `NumberField` input |
| `HeaderBar.swift`, `BottomBar.swift`, `ScreenCard.swift` | Shared chrome ported from the Figma Header / Bottom / Screen components; `PrimaryButton`, `SecondaryButtonRow`, `TimerPill` |
| `SpriteSheet.swift`, `SpriteView.swift` | Pixel-grid sprite loader + `Canvas` renderer + `AnimatedSpriteView` (bob/hop/wiggle/pop) |
| `SceneCatalog.swift` | Levels, seasons/hemisphere, holiday windows, milestones, shop catalog |
| `AnimatedGIFView.swift` | Frame-stepping GIF player for milestone art |
| `sprites.json`, `Fonts/`, `Milestones/`, `Assets.xcassets` | Art: 8 mouse poses (32×32 char grids), 4 Pixelify Sans weights, 3 GIFs, 12 pixelarticons SVGs, 17 scene PNGs |

~2.8k lines of Swift. No dependencies.

## Architecture

### State machine
`view`: `idle → plan → focus ⇄ (paused) → complete → break ⇄ (paused) → (auto-chain to focus, or entireComplete) → idle`
plus `overlay`: `none | naming | settings | confirmEnd | confirmWrap | weeklyStats`, and an independent
`compact` flag. Same shape as the plugin; names differ only where Swift keywords force it (`breakTime`).

- **Timestamp timing.** A running session stores `endAt`; a 250 ms poll derives `remaining`. Pausing
  freezes `remaining` and re-derives `endAt` on resume, so a throttled or sleeping app can't drift.
- **Running session persisted** (`store.running`): quitting mid-Focus/Break resumes exactly. A session
  that expired while the app was closed is credited on launch (non-punitive, like the plugin).
- **Complete auto-advances** to Break after 5 s ("Starting your break automatically in 5s…" — no button,
  tap the text to skip). Complete / Entire-complete / naming are *not* restored across a quit (same as
  the plugin).
- **Confirm modals freeze the clock** (`confirmFreeze`); the UI behind the scrim keeps showing
  "Pause", not "Paused" (`showsPaused`), matching the Figma frame.

### Credit model
- Full Focus: `+1` cheese (+ streak bonus on the day's first session), `days[today].s/m/c` updated.
- **Early end / Wrap-up mid-Focus: `+0.5` cheese.** `cheeseCount` is a `Double` so the message is truthful;
  early ends add to `m` and `c` but **not** `s` (no session count, streak, milestone or plan progress).
- Wrap-up mid-Break: no credit. Streak bonus: day 2–4 +1, 5–9 +2, 10+ +3, first full session of the day only.

### Persistence (`UserDefaults`, key `mousePomodoroState`, one JSON blob)
Fields: `mouseName, cheeseCount, totalSessionsCompleted, focusMinutes, breakMinutes, dailyTotal,
days{yyyy-MM-dd: {s,m,c}}, noteDay, compact, showMenuBarTime, owned[], sceneFocus, sceneBreak, running`.

- **Decoding is tolerant**: every key uses `decodeIfPresent` + a default (the plugin's
  `Object.assign(defaults, saved)`). See *Gotchas #1* for why this matters.
- `hasNamedMouse` is derived from `store.mouseName != nil`, and the placeholder "Unknown Mouse" is
  **never persisted**, so saving from Settings before naming can't skip the naming prompt.
- The app is **sandboxed**, so the real plist lives in
  `~/Library/Containers/com.soheeplays.MousePomodoro/Data/Library/Preferences/`.

### Windows
- **Full size** = an `NSPopover` anchored to the status item, 340 wide; height per screen from
  `TimerEngine.popoverHeight` (Idle/Plan 399 · Focus/Break 440 · Complete 372 · Entire-complete 392 ·
  Weekly stats 458, 496 with the streak chip). We size the popover ourselves
  (`NSHostingController.sizingOptions = []`, `animates = false`) — see *Gotchas #2*.
- **Compact** = a separate borderless, always-on-top, draggable `NSPanel` (232×84), *not* attached to the
  menu bar. Position is remembered (`setFrameAutosaveName`); persisted compact mode reopens it on launch.
  Compact is never restored before the mouse is named, and is blocked on the Plan screen.
- **Menu bar**: the status item shows `mm:ss` next to the icon during Focus/Break (also while paused),
  hidden otherwise; toggle in Settings ("Show time in menu bar", default on). Monospaced digits so the
  width doesn't jitter.
- **Notifications** (`UserNotifications`): Focus complete / Break over. Clicking one opens the app
  (popover, or brings the compact panel forward). Banners also show while the app is frontmost.

## Feature parity with the plugin

| Plugin feature | Mac app |
|---|---|
| Focus/Break timer, custom durations (1–90 / 1–30), pause/resume | ✅ |
| Mandatory one-time naming prompt | ✅ |
| Plan screen (daily total 1–20), auto-chain, Entire-complete, Add more / Resume sessions | ✅ |
| "Wrap up today" + "End session early" confirms (0.5 credit) | ✅ |
| Sticker export ("Download Image") | ✅ `ImageRenderer` → 512×512 PNG via `NSSavePanel` |
| Streak bonus + stats streak chip | ✅ |
| Daily encouragement note (bubble under the mouse) | ✅ — **2 lines per pool, not the plugin's 23** |
| Break interactions: tap = hop, feed (3 s), cursor = dance (700 ms) | ✅ (also in compact) |
| Sprite motion (bob/hop/wiggle/pop), sleeping pose when Focus is paused | ✅ ported keyframe-for-keyframe |
| Weekly stats heatmap (13 wk × Mon–Sun), week navigation | ✅ rebuilt to the updated Figma frame |
| Compact mode | ✅ — as a floating panel (plugin: a smaller plugin window) |
| Scenes: office evolution (levels at 0/10/50/250/1000 sessions), seasonal parks, hemisphere by timezone, holiday windows | ✅ |
| Shop (20 cheese/item, level-gated, "N sessions to go"), Green/Pink Studio are **Focus** scenes | ✅ |
| Milestones 10/25/50/100/250/500/1000 with GIFs (m10 is the generic one) | ✅ |
| Cloud sync | ❌ dropped by the plugin's own decision |
| Plugin "break reminder only while Figma is frontmost" gap | ✅ **improved** — real system notifications work from any app |

## Design ↔ code deviations (Mac-specific)

| Where | Plugin / Figma | Mac app | Why |
|---|---|---|---|
| Compact window | Smaller plugin window | Floating draggable panel, no menu bar attachment | Requested; feels native |
| Compact "cheese" strip button | Figma frame 18's lone button icon looks like a pause icon | Expand button | Matches plugin logic; looked like a placeholder |
| Compact Complete text | Figma frame 18 says "Nice effort!" even for +1 | "Nice effort!" only on early end, else "Session complete!" | Plugin logic |
| Weekly-stats intensity | Plugin: 5 buckets (0·1–2·3–4·5–6·7+) | 3 greens: 1–2 · 3–4 · 5+ | New Figma frame has 3 greens + grey |
| Shop buy | Confirm step; separate "Use automatic" | Buys immediately; tapping **In use** again reverts to automatic | Scope; first pass |
| Break footer label | "Pause break" (older frame) | "Pause" | Updated Figma `157:5157` |
| Break dancing | Cursor over the whole screen card | Same (whole card), and whole strip in compact | Plugin behaviour |
| Menu bar time, floating panel, click-to-open notifications | n/a | Mac-only additions | — |
| Settings "Quit" | n/a | Only way to quit | Accessory app has no menu bar menu |

## Gotchas & lessons (read before changing things)

1. **Synthesized `Codable` silently wipes saves.** Swift's synthesized `Decodable` requires every
   non-optional key even if it has a default, so adding a field to `Store` made every existing save fail to
   decode → fell back to defaults → looked like data loss (and made manual test seeding "not work").
   Fixed with a hand-written `init(from:)`. **When adding a field: add it to `CodingKeys` *and* the init.**
   A failed decode now `assertionFailure`s in Debug instead of silently resetting.
2. **`NSPopover` + `NSHostingController` resize race.** Letting the hosting controller auto-size *and*
   setting `popover.contentSize` made the popover crop to a stale viewport when switching compact↔full.
   Fix: `sizingOptions = []`, `animates = false`, and set `contentSize` on the next run-loop turn.
3. **`@Published` sinks fire *before* the value changes.** Reading `engine.x` inside a sink gives the old
   value — pass the emitted values (hence the static `popoverHeight(view:overlay:…)` and
   `menuBarTimeText(view:remaining:enabled:)`).
4. **Stacked `.background()` modifiers**: the second one goes *behind* the first, so an opaque color hid the
   scene image. Use one `.background { if … else … }`.
5. **Notifications need a real signing identity.** Ad-hoc / `CODE_SIGNING_ALLOWED=NO` builds are accepted
   by the OS but notifications never show. Sign into Xcode with a team.
6. **Sandbox entitlements**: `files.user-selected.read-write` is required for the sticker `NSSavePanel`
   (read-only silently fails). Notifications need no entitlement.
7. **Borderless panels** must subclass `NSPanel` with `canBecomeKey = true` or buttons ignore the first click.
8. **`.contentShape`** on icon buttons — template images only hit-test on their opaque pixels otherwise.
9. **Figma screen space**: Figma in fullscreen hides the menu bar and covers the popover, so screenshots of
   the app are useless then — use the offscreen render trick below.

## Testing notes

No test target. Verification so far: manual click-through + two throw-away techniques (neither is in the
repo; both are worth re-creating when needed):

- **Seed state** by writing the JSON blob into the sandboxed defaults, then relaunching (a running instance
  overwrites it on its next save):
  `defaults write com.soheeplays.MousePomodoro mousePomodoroState -data "$(xxd -p state.json | tr -d '\n')"`
  Format traps: `Date`s are **seconds since 2001-01-01** (Swift reference date), not ISO strings;
  `running.view` raw values are `focus` / `breakTime` (not `break`).
  Reset everything: `defaults delete com.soheeplays.MousePomodoro mousePomodoroState`.
- **Offscreen render** (temporary env-var hook in `applicationDidFinishLaunching`, removed after use):
  build an `NSHostingView(rootView: ContentView(engine:))` at the target size, put it in a borderless
  `NSWindow`, `cacheDisplay` into a bitmap rep, write a PNG **inside the app container**
  (`~/Library/Containers/com.soheeplays.MousePomodoro/Data/`; the sandbox blocks `/tmp`), then quit.
  Renders real controls (`ImageRenderer` shows `TextField` as a placeholder). Used to compare layouts
  against Figma frames pixel-for-pixel.
- Screen capture / System Events clicking require Screen Recording / Accessibility permission for the
  terminal; Accessibility was never granted, so clicks were always done by hand.

Re-check after any UI change: popover height per screen, compact ↔ full transition, notification click,
timer freezing behind both confirms, first-run (no name) path, a quit mid-session and relaunch.

## Known gaps / risks

- **App icon is a first pass** — the idle sprite on a white rounded square (see the Oct 8 log entry). Fine
  for dev builds; revisit the artwork (and a 1024 App Store master) before distribution.
- **Not archived / notarized / App Store-ready.** Only Debug builds with an Apple Development signature
  have been run. Sandbox + hardened runtime are on; privacy strings, category, screenshots, versioning
  and an `-exportArchive` pass are all still to do. No IAP and no network by design.
- **No tests**; no launch-at-login; no ⌘Q; Quit lives in Settings.
- **Shop**: no purchase confirm dialog; no explicit "Use automatic" (folded into the In-use toggle).
- **Daily note** has 2 messages per pool (plugin: 23) and no `{name}` substitution.
- **Hemisphere** detection is a shortened IANA-prefix list, not the plugin's full `SOUTH_TZ` regex — the
  occasional wrong season in an unlisted zone is expected (same caveat as the plugin; no override).
- **Weekly stats intensity** thresholds (1–2 · 3–4 · 5+) are my mapping onto Figma's three greens.
- Complete / Entire-complete / naming screens aren't restored across a quit (matches the plugin).
- Compact strip has no Figma frame for Idle or Entire-complete; those follow the plugin's `miniHTML()`.
- Multi-display: the compact panel's *default* position is the main screen's top-right; after that it
  remembers wherever it was dragged (not validated against a since-disconnected display).
- Streak chip lengthens the Weekly-stats popover (496 vs 458) — fine, but it's a special-case height.
- Dev machine state: testing seeded sample days/cheese into the author's sandboxed defaults; none of that is
  in the repo.

## Possible next steps

1. Notarized/archived build (Developer ID or Mac App Store); final icon artwork.
2. Launch at login (`SMAppService`), optional global shortcut to toggle the popover.
3. Right-click menu on the status item (Quit / Settings) and ⌘Q handling.
4. Expand the daily-note pool; add the purchase confirm + "Use automatic" to match the plugin exactly.
5. A small `Tests/` target for `TimerEngine` (inject a clock; the engine reads `Date()` directly today).
6. Re-check the Figma file for any frames added since: Idle / Entire-complete compact, shop UI, milestone screen.

---

## Log (newest first)

### Oct 8 — Design updates, wrap-up
- **End session** confirm uses the danger (red) secondary state (Figma `179:6005`).
- **Break footer** buttons hug their text, space-between; label "Pause" (Figma `157:5157`).
- **Weekly stats rebuilt** to Figma `212:3796`: This/Last week/Week of header, 3 stat columns, 13×7 grid with
  today boxed + selected week outlined, Less/More legend, Back to timer. Restored the plugin's streak chip
  (conditional, grows the popover). "Focused" uses a compact `1h 15m` form (long values were truncating).
- Confirm modals no longer make the screen behind them show "Paused".
- **App icon added** (`AppIcon.appiconset`, 10 PNGs 16–512 @1x/2x): the 128×128 idle sprite upscaled 6×
  with nearest-neighbor (keeps the pixels crisp) on a white macOS-grid rounded square (824 pt of 1024,
  radius 185) with a soft shadow, everything clipped to the rounded shape. Generated with Pillow from the
  supplied image; the 1024 master isn't stored in the repo (re-derive from the sprite if needed).
- Added this log and a `.gitignore`.

### Oct 7 — Notifications, floating compact, Plan inputs, motion, menu bar time
- **Notification click opens the app**; banners shown while frontmost.
- **Compact mode is now a floating, draggable panel** (position remembered) instead of a popover.
- **Plan/Settings use real numeric inputs** (`NumberField`, Figma Input incl. active border); Start button gets
  its play icon; Minimize disabled on Plan.
- **Sprite motion ported** (bob/hop/wiggle/pop) and the **sleeping pose when Focus is paused**; cards are
  top-aligned with Figma gaps (12 Focus/Break, 16 elsewhere) instead of vertically centered.
- **Menu bar timer** next to the icon (Focus/Break only), Settings toggle.
- **Compact strip rebuilt** to the Figma "minimized screens" frames; break pose logic moved into the engine
  so the strip is as interactive as the full Break screen. Daily-note bubble moved below the character.

### Sep 30 – Oct 1 — Build-out to feature parity, then bug hunt
- Project scaffold: hand-written `.xcodeproj` (no XcodeGen/Homebrew on the machine), signing with an Apple
  Development team, menu-bar popover skeleton. Timer engine, persistence, notifications, Settings.
- Art port: sprites (char grids → `Canvas`), 12 SVG icons → asset catalog templates, Pixelify Sans
  (variable woff2 → 4 static TTFs via fontTools), 17 scenes (WebP → PNG), 3 milestone GIFs.
- Figma screens via the Figma MCP: header/bottom/screen components, Idle, Plan, Focus, Complete, Break,
  Entire-complete, naming, confirms, Settings overlay, design-system buttons.
- Plan flow + auto-chain + Entire-complete + sticker export; streak bonus; daily note; break
  interactions; weekly stats; compact mode; Shop + scenes + milestones.
- **Bugs found and fixed:** sandbox entitlement blocked the sticker save panel; scene image hidden by an
  opaque `.background`; popover/hosting-controller sizing race; early-end credit not reflected in the
  currency (made `cheeseCount` fractional); **`Store` decoding wiped saves on every schema change**
  (tolerant decoder); naming flag edge cases; unclamped "Add more sessions"; shop "In use" button
  permanently disabled; weekly-stats cheese truncating `.5`; Complete screen was missing its 5 s
  auto-advance (found by auditing this app against the plugin's dev log).
- Verified the plugin's rule that Green/Pink Studio are **Focus** scenes (everything else paid is Break-only).
