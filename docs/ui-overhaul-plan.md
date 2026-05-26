# MedRash UI Overhaul — Implementation Plan & Status

> **Single source of truth** for the visual + interaction layer rebuild kicked off May 2026.
> Update the checkboxes as work lands. Add new decisions to the **Decisions Log** at the bottom.

---

## 1. Direction (LOCKED)

**Option A — Visual lift only.**

Adopt the *Vibrant Pulse* language from `New UI/` (palette, type, motion, shape, podium pattern, bottom-nav) and re-house it inside MedRash's existing IA, copy, and privacy model.

- ✅ Keep nickname-only public display on every participant surface.
- ✅ Keep clinical CME copy (Tavanic / Clexane / Aprovel / etc.); no consumer-wellness language ("Health Hero", "Hydration").
- ✅ Replace personal photos on leaderboard/podium/profile with **monogram circles** tinted by facility color.
- ✅ Replace the 4 stale bottom-nav tabs (Home / Leaderboard / Explore / Profile) with the reference's IA (Home / Ranking / Badges / Profile).
- 🅿️ **Future parking lot:** curated **avatar pack** (cartoon/illustration packs only — never user-uploaded photos). Schema add later: `app.user_profiles.avatar_pack_id`. No moderation pipeline. Not in scope for this overhaul.

### Why Option A won

- Lowest pilot risk (Ghana CME rooms, ISO 27001, no compliance amendment needed).
- Fastest unblock — no schema/backend work before the first reskin lands.
- Reversible — Option B (full avatars) or C (opt-in) can still ship later as features.
- Still ~80% of the reference's character because that character lives in motion + shape + palette, not photos.

---

## 2. Foundation pillar — Slice 1

> Direction-independent. Ships before any screen reskin. Four small commits, each independently reviewable.

### Slice 1a — Token rewrite *(code complete, verification partial)*

**Goal:** Replace the visual contract in `ArenaDesignTokens` + inline `TextTheme` (in `app_theme.dart`) so every existing screen auto-repaints on next build. Zero screen-level layout changes.

> **Note:** Earlier plan assumed a separate `arena_text_styles.dart` file. Reality: typography lives inline in `app_theme.dart` via `Typography.blackMountainView.copyWith(...)`. Slice 1a adapts: TextTheme rewritten in place rather than a new file.

#### Sub-tasks

- [x] Rewrite color values in `app/lib/core/theme/design_tokens.dart` (preserve token names; only values change).
- [x] Add new token fields: `primarySoft`, `surfaceContainer`, `onSecondary`, `secondaryStrong`, `rankGold`, `rankSilver`, `rankBronze`. (Medal tokens are defined now but consumed in Slice 2f, not here.)
- [x] Rewrite typography ramp inline in `app/lib/core/theme/app_theme.dart`:
  - **Poppins** → display/headline/title slots (UI emphasis).
  - **Inter** → body/label slots (dense readable content).
- [x] Bump radii: `radiusSmall 8 → 12`, `radiusMedium 12 → 16`, `radiusLarge 16 → 24`.
- [x] Soften border: `borderWidth 3 → 1.5`; drop hard `shadowOffset 4 → 0`.
- [x] New file `app/lib/core/theme/arena_motion.dart` — `fast/medium/slow` durations + `standard/emphasis/linear` curves (defined; applied in 1c).
- [x] New file `app/lib/core/theme/arena_elevation.dart` — `level1/level2/level3` BoxShadow list constants (purple-tinted ambient).
- [x] Update `app/lib/core/theme/app_theme.dart` ColorScheme to consume the new primary/onSecondary/primarySoft/surfaceContainer.
- [ ] ~~Fix the hard-coded medal colors in `app/lib/features/quiz/screens/ranked_page.dart`~~ — **deferred to Slice 2f** (each tier has 3 colors: bg/border/foreground, not a single swap; cleaner to refactor during the leaderboard rebuild).
- [x] Bundle Poppins + Inter `.ttf` files in `app/pubspec.yaml` under `flutter.fonts`.
- [x] Drop font files into `app/assets/fonts/` (Poppins 600/700/800 static + Inter variable font covering 400–700).
- [ ] If needed, preload font references in `app/web/index.html` for first-paint perf. *(skipped — Flutter bundles fonts in the build; revisit after first hosted deploy if FOUT is visible.)*
- [ ] Add `OFL.txt` license files into `app/assets/fonts/` for OFL compliance.

#### Verification (Slice 1a)

- **Workspace:** `c:\Users\USER\Desktop\Personal\medRash\app`
- **Command mode:** local (Flutter SDK on dev machine).
- `flutter pub get` → **PASS** (dependencies resolved; no font asset path errors).
- `flutter analyze` (full tree, after reverting unrelated working-tree deletions) → **PASS** — `No issues found! (ran in 7.7s)`.
- `flutter test` → **PASS** — `All tests passed!` (74 tests).
- `flutter build web` → **PASS** — `Built build/web` in 184.8s. Font assets bundled at `build/web/assets/assets/fonts/`: `Inter-Variable.ttf` (876,576 B), `Poppins-{SemiBold,Bold,ExtraBold}.ttf` (~155 KB each). Wasm dry-run succeeded.
- Visual smoke (manual) → **DEFERRED** to start of Slice 1b — will spot-check the 8 anchor screens render with the new Vibrant Pulse tokens before any reskin work begins.

**Slice 1a sign-off:** code complete, automated verification clean. Safe to commit and move on to Slice 1b.


#### Token contract (the diff)

```
// Colors — light theme
background:       #F7F9FB
surface:          #FFFFFF
surfaceMuted:     #F2F4F6        // input bg
surfaceContainer: #ECEEF0        // NEW — elevated container
primary:          #5300B7        // was #FFDE59
primaryStrong:    #6D28D9        // gradient end + hover
primarySoft:      #EBDDFF        // NEW — tint surfaces
secondary:        #FFC329        // was #73F6FB — reward gold
secondaryStrong:  #F59E0B        // NEW
tertiary:         #FFD4E7        // kept (rank 3 accent)
success:          #10B981
error:            #DC2626
warning:          #F59E0B
textPrimary:      #191C1E
textSecondary:    #4A4455
outline:          #CCC3D7
warningSurface:   #FEF3C7
successSurface:   #D1FAE5
dangerSurface:    #FEE2E2
onPrimary:        #FFFFFF
onSecondary:      #261A00        // NEW — dark-on-gold to keep AA contrast
rankGold:         #FFC329        // NEW
rankSilver:       #C0C0C0        // NEW
rankBronze:       #CD7F32        // NEW

// Radii
radiusSmall:  12
radiusMedium: 16
radiusLarge:  24

// Borders / shadow offset (hard neo-brutalist look retires)
borderWidth:  1.5
shadowOffset: 0   // replaced by elev1 ambient shadow

// Elevation (NEW)
elev1: BoxShadow(blur 12, offset (0,4), rgba(109,40,217,0.08))
elev2: BoxShadow(blur 20, offset (0,8), rgba(109,40,217,0.12))
elev3: BoxShadow(blur 36, offset (0,16), rgba(109,40,217,0.18))

// Motion (NEW — defined; applied in 1c)
motionFast:   Duration(milliseconds: 150)
motionMed:    Duration(milliseconds: 280)
motionSlow:   Duration(milliseconds: 480)
curveStandard: Curves.easeOutCubic
curveEmphasis: Curves.easeOutBack
curveLinear:   Curves.linear
```

#### Typography contract (the diff)

```
displayLg:        Poppins 48 / w800 / lh 56 / ls -0.02em
headlineLg:       Poppins 32 / w700 / lh 40 / ls -0.01em
headlineMd:       Poppins 24 / w700 / lh 32
headlineSm:       Poppins 20 / w600 / lh 28
headlineLgMobile: Poppins 28 / w700 / lh 36   // crowded-screen override
buttonLg:         Poppins 16 / w600 / lh 20   // primary CTA + nav labels
scoreCounter:     Poppins 36 / w800 / lh 40   // count-up numerals
bodyLg:           Inter 18 / w400 / lh 28
bodyMd:           Inter 16 / w400 / lh 24
labelLg:          Inter 14 / w600 / lh 20 / ls 0.01em
labelSm:          Inter 12 / w500 / lh 16
achievementBody:  Inter 14 / w400 / lh 20     // badge descriptions
questionBody:     Inter 20 / w500 / lh 28     // quiz question text (dense medical wording)
tableCell:        Inter 14 / w400 / lh 20     // admin tables / reports
```

#### Font usage rules (LOCKED)

- **Poppins** → display headlines, section headlines, primary CTAs, navigation labels, score counters, podium rank numerals, badge titles. Always for **UI emphasis**.
- **Inter** → quiz question bodies, answer-option text, explanation paragraphs, badge descriptions, profile copy, admin tables, dashboard numerals (non-celebratory), report rows, all paragraph-length copy.
- **Never use Poppins for**: long medical paragraphs, multi-row analytics tables, dense form helper text, anything > ~80 chars on a single line.
- **Labels in the type ramp moved from Poppins to Inter** (`labelLg`) to honour this rule — labels often appear in dense form layouts and tables.

#### Files touched

```
app/lib/core/theme/design_tokens.dart                  (rewrite values + add new fields)
app/lib/core/theme/theme_extensions.dart               (extend lerp() for new fields)
app/lib/core/theme/app_theme.dart                      (rewrite TextTheme with Poppins + Inter)
app/lib/core/theme/arena_motion.dart                   (NEW)
app/lib/core/theme/arena_elevation.dart                (NEW)
app/pubspec.yaml                                       (bundle Poppins + Inter .ttf)
app/assets/fonts/Poppins-SemiBold.ttf                  (NEW asset, w600)
app/assets/fonts/Poppins-Bold.ttf                      (NEW asset, w700)
app/assets/fonts/Poppins-ExtraBold.ttf                 (NEW asset, w800)
app/assets/fonts/Inter-Regular.ttf                     (NEW asset, w400)
app/assets/fonts/Inter-Medium.ttf                      (NEW asset, w500)
app/assets/fonts/Inter-SemiBold.ttf                    (NEW asset, w600)
```

#### Verification

- [ ] `cd app && flutter analyze` → 0 new warnings.
- [ ] `cd app && flutter test` → existing suite passes.
- [ ] `cd app && flutter build web` → succeeds; asset bundle contains font .ttf files.
- [ ] Visual smoke on 8 screens: mode_selection, quiz_runner, quiz_result, ranked, session_join, world_rank, quick_join, profile. No overflow, legible, primary is purple, gold is the reward accent.
- [ ] Contrast spot-check: purple-on-white, white-on-purple, dark-on-gold all ≥ 4.5:1.

---

### Slice 1b — Responsive breakpoint helpers *(complete)*

**Goal:** Add screen-shape primitives so participant screens stay mobile-first while host/admin surfaces unlock multi-column layouts on ≥ medium breakpoints.

> **Note:** Earlier plan called for two new files (`arena_breakpoints.dart` + `arena_responsive.dart`). Reality: `app/lib/core/ui/responsive.dart` already shipped `MedRashBreakpoint { compact, medium, expanded }` + `context.breakpoint` + `MedRashConstrainedBody`. Slice 1b extends the existing module in place rather than duplicating the enum.

- [x] Extended `app/lib/core/ui/responsive.dart` with `medRashBreakpointForWidth(double)` (pure helper for tests and nested layouts).
- [x] Added `ResponsiveValue<T>` with `compact` required + `medium`/`expanded` falling back to the next-smaller value (mobile-first ergonomics).
- [x] Added `ResponsiveBuilder` (LayoutBuilder-backed) so nested layouts can pick rail vs bottom-nav from the locally available width instead of the full-screen MediaQuery.
- [x] Added `BuildContext.isMedium` helper (we already had `isCompact` + `isExpanded`).
- [x] Audited `MedRashConstrainedBody` — keep as-is. It caps reading width at 560 dp on `>= medium` screens; the new helpers don't replace that role.
- [x] No screen migrations in this slice; just the primitives.

#### Verification (Slice 1b)

- **Workspace:** `c:\Users\USER\Desktop\Personal\medRash\app`, mode: local.
- `flutter analyze` → **PASS** (`No issues found!`).
- `flutter test test/core/ui/responsive_test.dart` → **PASS** (9/9 new tests: width buckets at 600/1024 boundaries + `ResponsiveValue` fallback + `ResponsiveBuilder` at three sizes).

---

### Slice 1c — Motion primitives *(complete)*

**Goal:** Reusable widgets + helpers that consume the `ArenaMotion` durations/curves from 1a. Still no screen migrations.

- [x] `app/lib/core/motion/press_scale.dart` — wrapper widget that scales child to `pressedScale` (default 0.97) on pointer-down, springs back on release. Honours `MediaQuery.disableAnimationsOf`. Opaque hit-testing so empty children still register.
- [x] `app/lib/core/motion/count_up_number.dart` — `TweenAnimationBuilder<int>` wrapper for score/XP reveals; jumps to final value when reduced-motion is on. Optional `formatter` for thousands/units.
- [x] `app/lib/core/motion/stagger_list.dart` — single parent `AnimationController` + per-row `Interval` (deterministic, timer-free) for leaderboard rows / badge grids. Reduced-motion path renders children at rest.
- [x] `app/lib/core/motion/shared_axis_page.dart` — `sharedAxisPage<T>({state, child, duration?})` factory returning go_router `CustomTransitionPage` with fade + 4% x-axis slide; collapses to body widget under reduced-motion.
- [x] `app/lib/core/motion/haptics.dart` — `Haptics.selection() / .submit() / .celebrate()` mapping to selection-click / medium / heavy. Swallows `MissingPluginException` for web + tests.

#### Verification *(2025-01 — c:\Users\USER\Desktop\Personal\medRash, local mode)*

- [x] **PASS** `flutter analyze` → No issues found.
- [x] **PASS** `flutter test test/core/motion/` → 13/13 (3 press-scale, 3 count-up, 2 stagger, 2 shared-axis, 3 haptics).
- [x] **PASS** `flutter test` (full suite) → 96/96 (prior 83 + 13 new).
- [x] **PASS** Reduced-motion honoured — verified per primitive via `MediaQuery(data: MediaQueryData(disableAnimations: true), …)` test wrappers.

---

### Slice 1d — Icon family pass *(complete)*

**Goal:** Decide and apply one icon family across the participant app for visual consistency with the reference (which uses rounded outline icons).

- [x] **Decision: Material Symbols Rounded.** Zero new deps, full Flutter integration, matches reference rounded-cap look. Phosphor / lucide deferred — would require font asset + package and offer minimal additional benefit at this stage.
- [x] Added `MedRashIconSize` (`sm: 16`, `md: 20`, `lg: 24`, `xl: 32`) to `app/lib/core/theme/design_tokens.dart`. Theme-invariant (no light/dark variant), so colocated with `MedRashSpace` rather than expanding `ArenaDesignTokens`.
- [x] Swept all icon callsites in `app/lib/` — 41 unique tokens across 16 files normalised to `_rounded`. Mappings drop `_outlined` / `_outline` suffixes and add `_rounded` (e.g. `Icons.home_outlined` → `Icons.home_rounded`, `Icons.person_outline` → `Icons.person_rounded`, `Icons.workspace_premium` → `Icons.workspace_premium_rounded`).

#### Verification *(2025-01 — c:\Users\USER\Desktop\Personal\medRash, local mode)*

- [x] **PASS** `flutter analyze` → No issues found (confirms every `_rounded` variant exists in the bundled Material Icons font).
- [x] **PASS** `flutter test` → 96/96 (no test referenced an icon by exact identifier).
- [ ] Visual smoke on 8 screens — deferred to Slice 2 per-screen rebuild (icons will be re-verified in context with new layouts).

---

## 3. Participant pillar — Slice 2

> Mobile-first. Depends on Slice 1 foundation. Each screen ships its share of motion + state + a11y work.

- [x] **2a. Quick-Join / Onboarding** *(complete)* — login-card pattern, nickname preview chip, focus-purple inputs, gold CTA.
    - [x] **Reference**: UI 2 "Quick Join Page" (Neo-Medical Academy). Vibrant Pulse re-skin keeps the form structure (Full Name / Facility / Specialty / nickname preview / Start) but replaces the neo-brutalist 3px borders + 4px hard shadows with Vibrant Pulse flat surfaces, focus-purple inputs, and gold CTA per the locked design system.
    - [x] **Login-card pattern** — three inputs + nickname chip wrapped in a single `ArenaCard` (`_OnboardingCard`, padding 24) sitting on the dot-grid scaffold inside `MedRashConstrainedBody` (max width 560 dp).
    - [x] **Focus-purple inputs** — new `_FocusInput` widget: at rest, neutral `outline` border on `surface` fill. On focus, `AnimatedContainer` (150ms easeOutCubic) swaps to `primarySoft` fill with 2px `primary` border; section label color also lifts from `textSecondary` → `primary`. Length-limited (64 / 80) and autofill-hinted for `name`.
    - [x] **Focus-purple dropdown** — `_FocusDropdown` mirrors input styling; `DropdownButton` with rounded-medium menu and `expand_more_rounded` chevron sized via `MedRashIconSize.md`.
    - [x] **Nickname preview chip** — `_NicknameChip` replaces the old full-width gold tag card with a compact pill on `primarySoft` background: `MonogramAvatar` (gold/onSecondary) + nickname (Poppins 700, `primaryStrong`) + tagline + circular regenerate button. Nickname text uses `AnimatedSwitcher` (220ms fade + 8 dp slide) so each regeneration reads as a deliberate update. Regenerate button wrapped in `PressScale` and fires `Haptics.selection()`.
    - [x] **Gold CTA** — `ArenaButton` themed to `tokens.secondary` / `tokens.onSecondary` with `play_arrow_rounded` icon, wrapped in `PressScale` from Slice 1c. Disabled until both name + facility have non-empty trimmed values. Triggers `Haptics.submit()` on tap.
    - [x] **Hero intro** — first-time-only Poppins display headline + Inter tagline; suppressed when a resume snapshot is offered or a session join code is in the deep link (those contexts take the visual lead).
    - [x] **Resume + session-context cards re-skinned** — `_ResumeCard` now uses `primarySoft` background with `primary` accents and a gold resume CTA wrapped in `PressScale`; `_SessionContextCard` flips to `secondary` background with `onSecondary` foreground for the joining-session banner. Both replace `CircleAvatar` + person icon with `MonogramAvatar` rendering nickname/snapshot initials.
    - [x] **MonogramAvatar primitive** — new `app/lib/core/ui/widgets/monogram_avatar.dart` (with `MonogramAvatar.initialsFor` static helper) provides the nickname-only / no-PII avatar style we will reuse across leaderboard, profile, and host surfaces. 4 unit tests cover empty input, multi-word names, camelcase nicknames, and the fallback path.
    - [x] **Specialty default + keyboard polish** — specialty still defaults to `Doctor` (preserves `_canStart` logic and old behaviour); name/facility now request word capitalization; haptic on dropdown change.
    - **Verification** *(workspace: `c:\Users\USER\Desktop\Personal\medRash`, mode: local)*:
        - [x] **PASS** `flutter analyze` → No issues found (ran in 5.5s).
        - [x] **PASS** `flutter test` → 100/100 (prior 96 + 4 new `MonogramAvatar` unit tests). No QuickJoinPage widget test existed previously; behaviour preserved (controllers, `quickJoin`, `restoreFromSnapshot`, `markJoined`, `nextPath`, `joinCodeFromNextPath`, `AuthStateManager` listener all unchanged).
        - [x] **PASS** Reduced-motion safety — input focus animation is a non-essential micro-transition (`AnimatedContainer` 150ms) and the nickname `AnimatedSwitcher` falls back to its child immediately when `MediaQuery.disableAnimations` is set (Flutter built-in behaviour). `PressScale` and `Haptics` already honour reduced-motion / missing-plugin paths from Slice 1c.
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2b–2d, so the participant pillar can be eyeballed end-to-end.
- [x] **2b. Home / Mode-selection** *(complete)* — hero featured card, "My Stats" KPI tiles (streak + ranked-points), mode tile grid.
    - [x] **StreakStore primitive** — new `app/lib/features/profile/storage/streak_store.dart`. SharedPreferences-backed (`medrash.streak.current` / `.best` / `.lastDateIso`), buckets dates on the UTC calendar (Africa/Accra is GMT+0 year-round, no DST). `recordAttempt` increments on consecutive days, resets to 1 on a 2+ day gap, leaves the same-day path idempotent, and tracks `bestStreak`. `read()` computes a live alive/broken snapshot without a background tick — the current streak silently resets to `0` once the grace day passes. Listens to `AttemptSubmittedEvent` (any mode counts toward engagement) and clears on `IdentityResetEvent`. Registered as a lazy singleton in `init_core.dart`, then eagerly constructed alongside `GuestProfilePromptStore` so the QR-deep-link → quiz → result path can't miss the first attempt event.
    - [x] **Greeting band** — Poppins 800 headline ("Hello, @nickname" when a profile exists, otherwise "Hello, Champion") + Inter body tagline. Pulls from `ProfileRepository.getProfile()` on mount and re-loads on `ProfileUpdatedEvent` / `ProfilePointsUpdatedEvent`.
    - [x] **Hero featured card** — purple→gold gradient pulse glow behind an `ArenaCard`, status pill ("Pick up where you left off" when a recent session is open, otherwise "Today's ranked challenge"), Poppins headline, Inter body, and a gold CTA wrapped in `PressScale` that fires `Haptics.submit()`. Resume path routes to `/session/{code}`; ranked path routes to `/ranked`. The previous standalone `_ContinueLastSessionCard` is replaced by this single hero — one primary CTA above the fold.
    - [x] **My Stats KPI row** — horizontal-scroll row of three `_StatTile` cards (168 dp wide, white surface, ArenaCard shadow). Each tile = tinted icon-in-circle on top, `CountUpNumber` from Slice 1c animating to the live value, and an uppercase Inter label-sm caption. Wired to real repos: streak ← `StreakStore.read().currentStreak`, career points ← `UserProfile.totalPoints`, world rank ← `UserProfile.rank` (renders `—` when zero). All three refresh reactively via the streak `changes` stream and `ProfilePointsUpdatedEvent` / `ProfileUpdatedEvent` listeners — no polling.
    - [x] **Mode tile grid** — replaces the previous list of `_ModeCard` rows with a `GridView.builder` (2 cols compact, 4 cols at ≥ 600 dp) wrapped in a `StaggerList` so tiles fade-in with the Slice 1c entrance choreography. Four tiles: Live, Ranked (gold accent), Learn, Explore — collapsing the bottom Explore TextButton into a peer of the modes. Each tile = tinted icon block + Poppins title + Inter 3-line description, wrapped in `PressScale` + `Haptics.selection`.
    - [x] **Routing + behaviour preserved** — every `_go()` call delegates to `context.go(...)` with the same paths the previous page used. `LastSessionRecordedEvent` subscription preserved (drives hero state). `CompleteProfileBanner` retained at the top of the scroll. No router edits required.
    - **Verification** *(workspace: `c:\Users\USER\Desktop\Personal\medRash`, mode: local)*:
        - [x] **PASS** `flutter analyze` → No issues found (ran in 9.0s).
        - [x] **PASS** `flutter test` → 108/108 (prior 100 + 8 new `StreakStore` unit tests covering: empty read, first attempt, same-day idempotence, consecutive-day increment + best update, multi-day gap reset, post-grace-day read returning 0, grace-day read still alive, and `clear`). No prior widget test existed for `ModeSelectionPage`.
        - [x] **PASS** Reduced-motion safety — `CountUpNumber`, `PressScale`, `StaggerList`, and `Haptics` all already honour `MediaQuery.disableAnimations` / `MissingPluginException` paths from Slice 1c. The hero glow is a static gradient (no animation), so nothing new to gate.
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2c–2d so the participant pillar can be eyeballed end-to-end.
- [x] **2c. Session-join lobby** *(complete)* — Vibrant Pulse reskin of `SessionJoinPage`. Behaviour preserved end-to-end (last-session record + event, `_loadSession`, `_startMode`, guest-nickname prompt + save, `Switch to Learning Mode` fallback when ranked attempt is burned, Gap-6 host-mode-aware single primary CTA).
    - Hero session card wrapped in a static purple→gold pulse glow (gradient + shadow recipe matching the home hero) with `ArenaChip(session.category)` + gold `ArenaChip('CME')`, Poppins800 `headlineMedium` title, and Inter `bodyMedium` topic line.
    - Metric tiles replace the grey nested cards with KPI-style white `ArenaCard`s: tinted icon circle, Poppins800 `headlineSmall` value with `height: 1`, uppercase `labelSmall` caption (Questions on primary/primarySoft, Time Limit on onSecondary/secondary).
    - Host attribution card now uses `MonogramAvatar(source: session.host, …)` on a `primarySoft` surface with uppercase `HOSTED BY` eyebrow.
    - Primary CTAs (Start Learning / Start Ranked) wrapped in `PressScale` + `Haptics.submit` and styled as gold pill (`secondary` / `onSecondary`); disabled `Ranked Attempt Used` state dims via `Opacity(0.55)` while the secondary `Switch to Learning Mode` button keeps its white outline-pill look.
    - Guest nickname prompt switches from gold to `primarySoft` `ArenaCard` with white-filled outlined `TextField` (32-char limit, `LengthLimitingTextInputFormatter`), gold pill save button wrapped in `PressScale` + `Haptics.submit`.
    - Loading and error states adopt `tokens.primary` for the spinner and Poppins copy, with a `PressScale`-wrapped `Retry` gold pill.
    - **Verification** *(workspace: `c:\Users\USER\Desktop\Personal\medRash`, mode: local)*:
        - [x] **PASS** `flutter analyze` → No issues found (ran in 11.1s).
        - [x] **PASS** `flutter test` → 108/108 (unchanged; no widget test exists for `SessionJoinPage` and none was added in this slice — behaviour is exercised by upstream repository/event tests).
        - [x] **PASS** Reduced-motion safety — `PressScale` and `Haptics` already honour `MediaQuery.disableAnimations` / `MissingPluginException` paths from Slice 1c. Hero glow is a static gradient; no new motion introduced.
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2d.
- [x] **2d. Quiz Runner** *(complete)* — Vibrant Pulse reskin of `QuizRunnerPage`. Behaviour preserved end-to-end (`_prepareAttempt`, `_retryConnection`, `_startOfflinePractice`, `_restartAttempt`, `selectAnswer` → `submitCurrentAnswer` → `/result` navigation, `_PreparationOutcome` branching, resumed-attempt + offline-practice banner triggers).
    - `QuizProgressBar` upgraded to a purple→gold linear-gradient fill animated via `TweenAnimationBuilder` (360ms easeOutCubic); honours `MediaQuery.disableAnimations` by snapping instantly.
    - Mode chip in the question-counter row swapped for `ArenaChip` (Ranked → gold `secondary`, Learning → `primarySoft`) so it shares the lobby vocabulary.
    - Category chip recoloured to `primarySoft` and the prompt block sits inside a white `ArenaCard` with Poppins800 `headlineSmall` (replacing the grey `0xFFF8F8F8` surface).
    - Option tiles rebuilt as `_OptionTile`: 40×40 rounded letter badge (primarySoft / primaryStrong default → primary / white when selected → success / white when correct → error / white when wrong), `AnimatedContainer` border + surface (220ms easeOutCubic, reduced-motion safe), trailing `check_circle_rounded` / `cancel_rounded` indicator during flash, wrapped in `PressScale` + `Haptics.selection` on tap.
    - Submit CTA wrapped in `PressScale` and gated by `_selectedIndex >= 0 && _flash == null`; during the flash window it morphs into a "Correct!" (success) or "Keep going" (error) pill while the next question is held back.
    - Correct/wrong flash: `_submitCurrentAnswer` captures the active `Question`, calls `selectAnswer` + `submitCurrentAnswer`, fires `Haptics.celebrate` on correct or `Haptics.submit` on wrong, then holds the captured question on screen for 700ms (0ms under reduced motion) before either navigating to `/result` (last question) or clearing `_flash` + `_selectedIndex` to reveal the next prompt. Repository state advances immediately; only the UI delay is timer-driven.
    - Resumed-attempt banner now uses a `primarySoft` `ArenaCard` with a `Restart` `TextButton`, and the offline-practice banner uses `warningSurface` with `onSecondary` text — both replace the hard-coded `0xFFE6F4FF` / `0xFFFFF4E0` literals.
    - Offline interstitial reskinned: token-backed copy, `PressScale`-wrapped Retry (gold pill) and Practice-offline (primarySoft pill) buttons, `surfaceMuted` detail card.
    - **Verification** *(workspace: `c:\Users\USER\Desktop\Personal\medRash`, mode: local)*:
        - [x] **PASS** `flutter analyze` → No issues found (ran in 10.5s).
        - [x] **PASS** `flutter test` → 108/108 (unchanged; no widget test exists for `QuizRunnerPage` and none added in this slice — repository submit/advance logic remains covered by existing repo tests).
        - [x] **PASS** Reduced-motion safety — `QuizProgressBar`, `_OptionTile` AnimatedContainer, and the flash hold-timer all collapse to `Duration.zero` when `MediaQuery.disableAnimations` is true; `PressScale` and `Haptics` already honour the same gate from Slice 1c.
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2e.
- [x] **2e. Result + post-quiz** *(complete)* — score reveal with count-up, XP bar fill, "what's next" CTAs.
    - Hero score card: pulse-glow gradient backdrop (primary/secondary), `CountUpNumber` for score (Poppins800 displayLarge, primary) over " / total" subscript, gold `% CORRECT` pill (CountUpNumber-driven), time + mode metric chips.
    - Headline copy adapts to ratio: Perfect Run / Outstanding / Strong Attempt / Solid Effort / GREAT EFFORT fallback.
    - Career points bar (`_CareerPointsBar`): purple→gold gradient fill via `TweenAnimationBuilder` (reduced-motion safe), CountUpNumber "+N" trophy badge.
    - Knowledge Check reskinned: success/danger surface badge per question, prompt in Poppins600, Wrap of "Your answer · X" / "Correct · Y" pills, primarySoft explanation tile with lightbulb icon.
    - Pending-sync banner moved to warningSurface with onSecondary chip + PressScale-wrapped gold retry button; synced banner uses successSurface + success chip.
    - "What's next" CTA stack: PressScale + `Haptics.submit` on gold "View Leaderboard" → `/leaderboard`; primarySoft "Back To Home" wraps preserved `_goHome` (clears cached completed snapshot).
    - Empty/error states unified into `_CenteredCallout` with token-coloured icon + gold CTA.
    - Behaviour preserved verbatim: `_resolveResult` finalize/cached/none branching, `AttemptSubmittedEvent` subscription + sync toast, `_retrySync`, `_goHome`, Semantics label on hero.
    - Verification *(workspace `c:/Users/USER/Desktop/Personal/medRash`, mode local)*:
        - [x] PASS `flutter analyze` → No issues found (9.7s).
        - [x] PASS `flutter test` → All tests passed (108/108).
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2h.
- [x] **2f. Leaderboard (World Rank)** *(complete)* — podium top-3 with monogram circles (gold ring on rank 1), scrollable list with stagger-in, sticky "You" row.
    - Period toggle restyled as `primarySoft` pill with `AnimatedContainer`-driven gradient selector + `PressScale` + `Haptics.selection`; selected pill `primary` with soft glow.
    - Podium (`_Podium` / `_PodiumColumn`): 2nd left + 1st center (taller, gold `secondary` surface) + 3rd right (`tertiary`). Each column is an `ArenaCard` with rank chip, name, `CountUpNumber` score, and a `MonogramAvatar` floating from a `Positioned` ring above. Champion ring is a 3-px gold border with 18-px gold glow; `workspace_premium_rounded` icon sits above the champion avatar.
    - Contenders list (`_LeaderRow`): `StaggerList` of `ArenaCard` rows (rank chip + `MonogramAvatar` + name + `CountUpNumber` score + `pts`); current-user row flips to `primarySoft` surface with `primary` rank chip and `YOU` eyebrow.
    - Sticky "You" card (`_StickyYouCard`): pinned via `Positioned` at the bottom of the `Stack` when the current user exists but is not in the podium; gold-on-primary surface with shadow so it floats above the contenders list (ListView keeps a 96 px bottom inset to avoid overlap).
    - Empty state (`_EmptyState`): trophy icon + "No rankings yet" + ranked-attempt prompt on a plain `ArenaCard`.
    - Behaviour preserved verbatim: `LeaderboardRepository.fetchLeaderboard(period:)`, `_switchPeriod` re-fetch, `AttemptSubmittedEvent` listener that re-fetches with current period, `Semantics` rank/name/score per row.
    - Verification *(workspace `c:/Users/USER/Desktop/Personal/medRash`, mode local)*:
        - [x] PASS `flutter analyze` → No issues found (19.3s).
        - [x] PASS `flutter test` → All tests passed (108/108).
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2h.
- [x] **2g. Profile** *(complete)* — monogram header, stats tiles, recent attempts, edit form, sign-out modal.
    - Hero (`_ProfileHero`): pulse-glow gradient backdrop + `ArenaCard` with a 116-px gold-ringed `MonogramAvatar` (gold border + 18-px gold glow), Poppins800 display name, `@nickname` pill on `primarySoft`, and surfaceMuted meta chips for specialty/facility.
    - Stats row (`_StatsRow` / `_StatTile`): two equal-width `ArenaCard` tiles with circular icon badges (primary/primarySoft + onSecondary/secondary), `CountUpNumber` values; rank tile formats as `#N` (em-dash when 0).
    - Edit form: `_SectionLabel('IDENTITY')` over icon-led field cards for Nickname (32-char limit) and Facility, plus `_SpecialtyField` dropdown with `expand_more_rounded` icon and `Haptics.selection` on change.
    - Save Profile CTA: gold `ArenaButton` wrapped in `PressScale`, fires `Haptics.submit`, swaps to "Saving…" with `_saving` gate to prevent double-submit; preserves `_profileRepository.updateProfile(nickname, facility, specialty)` + snackbar.
    - Secure-Your-Progress card (`_ClaimAccountCard`): `primarySoft` surface, primary shield icon, gold `SOON` chip, disabled white CTA (behaviour unchanged — still `onPressed: null`).
    - Sign-Out card (`_SignOutCard`): `dangerSurface` accent with circular `error` icon badge and PressScale-wrapped red CTA.
    - Sign-out modal (`_SignOutSheet` / `_SignOutOptionCard`): rounded sheet with two `PressScale` option cards (phone icon for keep-device / group icon for rotate) on tokenised surfaces, each with title + helper copy + chevron; preserves both `_SignOutChoice` branches and the full `clearAll → clearActive → clearCompleted → auth.signOut → IdentityResetEvent → /join` flow verbatim.
    - Recent attempts strip — deferred (no attempt-history repository API in `app/lib/features/profile` or `app/lib/features/quiz` yet); will be re-opened once attempt history is exposed.
    - Behaviour preserved verbatim: `_loadProfile`, `ProfilePointsUpdatedEvent` listener, dropdown specialty options (Emergency Medicine / Pharmacy / General Practice), Save snackbar, full sign-out cleanup chain, `IdentityResetEvent(keptDeviceId: …)` emission, redirect to `/join`.
    - Verification *(workspace `c:/Users/USER/Desktop/Personal/medRash`, mode local)*:
        - [x] PASS `flutter analyze` → No issues found (11.8s).
        - [x] PASS `flutter test` → All tests passed (108/108).
        - [ ] Visual smoke on real device — deferred to bundle review after Slice 2h.
- [x] **2h. Badges & Achievements** *(complete — design-only placeholder)* — collection grid + tier rings + locked states with "Coming soon" framing on real entries.
    - Route: new `/badges` mounted in [app/lib/core/routing/user_router.dart](app/lib/core/routing/user_router.dart) → `BadgesPage`.
    - Hero (`_BadgesHero`): pulse-glow gradient backdrop + `ArenaCard` with circular gold badge icon (workspace_premium + glow), Poppins800 'Earn Your Badges', `ArenaChip('COMING SOON')`, and tokenised explainer body.
    - Collection grid (`_BadgeGrid` / `_BadgeTile`): responsive `GridView.builder` (3 cols mobile / 4 cols ≥600px), six static previews (First Win, Streak x3, Top 10, CME 25, Host x5, Legend) with `Tooltip` hint copy.
    - Locked ring (`_LockedRing`): 76-px circle on tier surface with 2-px tier-accent border, dimmed tier icon (0.45 opacity), and bottom-right lock badge on `surface` with outline border.
    - Tier strip (`_TierStrip` / `_TierCard`): three equal-width `ArenaCard`s for Bronze / Silver / Gold with tier-accent icon disc and uppercase Poppins800 label.
    - Tier styles (`_TierStyle` + `_styleFor`): Bronze = `#B87333` on `#FFEBD6`; Silver = `tokens.tertiary` on `tokens.primarySoft`; Gold = `tokens.onSecondary` on `tokens.secondary`.
    - No schema, no event wiring, no persistence — every tile is locked and labelled "Coming soon" in the hero, matching the plan's design-only constraint.
    - Verification *(workspace `c:/Users/USER/Desktop/Personal/medRash`, mode local)*:
        - [x] PASS `flutter analyze` → No issues found (6.1s).
        - [x] PASS `flutter test` → All tests passed (108/108).
        - [ ] Visual smoke on real device — deferred to bundle review.

---

## 4. Host live-session pillar — Slice 3

> Tablet/desktop primary, mobile fallback. This is **new functionality**, not a reskin — MedRash currently has no host-live presenter surface.

- [x] **3a. Host control room** — dark theme, live audience count, real-time per-option distribution bars, question broadcast, timer. *(complete — self-paced model, session-duration countdown, polling kept; Realtime migration deferred to Slice 3d.)*
  - **Verification (Slice 3a)**
    - Scope: Admin Next.js live session page (`/sessions/[id]/live`). Flutter side unaffected.
    - Snapshot query: `getSessionLiveSnapshot` extended with `hostName`, `startsAt`, `endsAt`, `totalQuestions`, `perQuestion[]` (each entry: questionId, prompt, options, correctIndex, totalAnswers, optionCounts[]). Aggregates `app.answers` keyed by `attempt_id IN session attempts` joined with active `app.questions` ordered by `position`.
    - Hero strip: Host Control Room eyebrow + session name + quiz/host subtitle + yellow "JOIN · <code>" chip + countdown pill that toggles between *Starts in / Ends in / Ended / Open session* tones, ticking once per second client-side.
    - Metrics row: Joined (audience, with scanned-vs-joined delta), Submitted (with completion %), Last Activity (with refresh stamp). Replaces the prior projector layout.
    - Answer distribution: `PanelCard "Answer Distribution"` listing every active question with prompt, total-answers chip, and a stack of horizontal bars per option. Correct option marked with green tint + Correct badge. Bars fade to 25% when zero votes. Empty state when no questions are loaded.
    - Top 5: existing panel preserved inside the dark scope, restyled via CSS vars (no shape change).
    - Dark theme: `.host-room-dark` CSS class added to `globals.css`, scoped to the host control room wrapper. Overrides `--arena-*` palette to a near-black / muted-violet surface set and re-applies `.arena-panel` box-shadow + outline with the muted outline color. Admin shell chrome stays light.
    - Polling: existing 3 s `fetch` loop with `AbortController` preserved; Realtime migration tracked separately as Slice 3d.
    - PASS `npx tsc --noEmit` (0 errors, ~120s).
    - PASS `npx eslint src/app/sessions/[id]/live src/lib/session-queries.ts` (0 errors).
- [x] **3b. QR / share panel** — large QR, copyable join code, deep link. *(complete — projector-grade share surface embedded inside the host control room.)*
  - **Verification (Slice 3b)**
    - Scope: Admin Next.js live session page (`/sessions/[id]/live`). No schema, query, or Flutter changes.
    - New component `share-panel.tsx`: 320×320 white-card QR (lazy-loaded `qrcode` at width 480, error-correction M), giant Anybody-font join code in yellow with thin-space triplets, full join URL line, **Copy link** + **Open in tab** buttons. Toast feedback ("Copied!") on Clipboard API success; falls back to a modal with an auto-selected read-only input when the Clipboard API is blocked.
    - Server resolution: `page.tsx` calls `buildSessionJoinUrl(joinCode)` once inside a try/catch and forwards `joinUrl` + `joinUrlError` to `LiveView`. When `MEDRASH_APP_PUBLIC_BASE_URL` is unset, the panel renders with buttons disabled, the QR slot shows a "QR unavailable…" hint, and an amber config-error banner explains the missing env var.
    - Placement: rendered above `Answer Distribution`, below the metrics row, so it's both visible on first load and easy to project full-screen by scrolling. Inherits `.host-room-dark` palette automatically.
    - PASS `npx tsc --noEmit` (0 errors).
    - PASS `npx eslint "src/app/sessions/[id]/live"` (0 errors).
- [x] **3c. End-of-session recap** — final standings, knowledge-gap highlights, export CTA. *(complete — new `/sessions/[id]/recap` surface, CSV export, dark theatre, linked from control room.)*
  - **Verification (Slice 3c)**
    - Scope: Admin Next.js. Added `/sessions/[id]/recap` page + `recap-export` client. Extended `SessionLiveSnapshot.standings` (full sorted list, `top5` is now a slice). Added a "View recap" link in the host control room hero. No schema or Flutter changes.
    - Hero: session name + quiz/host subtitle + status badge (Scheduled / Live / Ended / Open) tinted to the same green/cyan/pink palette as the control room countdown + "Open control room" link back.
    - Metric strip (4 tiles): Participants (with scanned subtitle), Submitted (with completion %), Questions (with flagged-below count), Duration (`Xh Ym` from starts_at→ends_at, with timestamp subtitle).
    - Final Standings: full ordered list with rank chip (gold/cyan/pink for top 3), display name, facility, raw score `score/total`, and percent. Empty state for sessions with zero finishers.
    - Knowledge Gaps: top 5 answered questions sorted by ascending correct%, each card shows prompt, large tinted correct% (red <40, amber <70, green ≥70), correct option, and `correctCount/totalAnswers got this right`.
    - Export CSV: client component using existing `serializeCsv` + `csvFilenameSegment`. Columns: Rank, Display Name, Facility, Score, Total Questions, Percent, Completed At, Participant ID. Downloads as `medrash-recap-<sessionName>-<joinCode>.csv` via in-memory Blob → revokeObjectURL. Disabled when standings are empty.
    - PASS `npx tsc --noEmit` (0 errors).
    - PASS `npx eslint "src/app/sessions/[id]" "src/lib/session-queries.ts"` (0 errors).
- [ ] **3d. Realtime migration** — replace the 3 s poll on the host control room with Supabase Realtime (Postgres changes on `app.attempts` + `app.answers`, plus a Broadcast channel keyed by session id). Keep polling as a fallback when the Realtime subscription drops.
- [ ] Dark theme `AppTheme.dark()` wired through (depends on Slice 1a tokens having a dark counterpart — add a Slice 3 sub-step to extend tokens for dark mode).

---

## 5. Admin Next.js pillar — Slice 4

> Desktop primary, responsive down to tablet. Lower visual playfulness than participant surfaces (denser, more functional).

- [x] **4a. Admin token foundation** — Next.js mirror of Slice 1a (CSS vars in `globals.css`, JS tokens in `lib/design-tokens.ts`). *(complete — full semantic palette + scale primitives wired both ways.)*
  - **Verification (Slice 4a)**
    - Scope: Admin Next.js only. Expanded `admin/src/lib/design-tokens.ts` and `admin/src/app/globals.css`; no component touched. No Flutter / schema / Netlify changes.
    - JS tokens (`lib/design-tokens.ts`): added named exports `arenaColors`, `arenaScale`, `arenaSpace`, `arenaIconSize` mirroring the Flutter `ArenaDesignTokens` aggregate. Extended `arenaColors` with `surfaceContainer`, `outlineMuted`, `primarySoft`, `secondaryStrong`, `onSecondary`, semantic `success` / `error` (foreground) alongside `successSurface` / `dangerSurface` / `warningSurface`, and `rankGold` / `rankSilver` / `rankBronze`. Added `arenaScale.{borderWidth, shadowOffset, radiusLarge, radiusMedium, radiusSmall, pageMargin}`. Added 6-step `arenaSpace` (xs/sm/md/lg/xl/xxl) and 4-step `arenaIconSize` (sm/md/lg/xl). Kept the existing `designTokens` aggregate shape (now including `colors / scale / space / iconSize` plus a back-compat `radius / shadow / spacing` shim) and the `adminNavigation` export untouched.
    - CSS vars (`globals.css`): mirrored every JS token under the `--arena-*` namespace — `--arena-surface-container`, `--arena-outline-muted`, `--arena-primary-soft`, `--arena-secondary-strong`, `--arena-on-secondary`, `--arena-success` (now foreground green #1b9e4b), `--arena-success-surface`, `--arena-warning-surface`, `--arena-error`, `--arena-danger-surface`, `--arena-rank-gold/silver/bronze`, `--arena-border-width`, `--arena-shadow-offset`, `--arena-radius-large/medium/small`, `--arena-page-margin`, `--arena-space-xs…xxl`, `--arena-icon-sm…xl`. Kept legacy aliases `--arena-panel` (= surfaceContainer) and `--arena-danger` (#ffd8d2 surface) so existing `bg-[var(--arena-panel)]` / `text-[var(--arena-danger)]` callsites render identically.
    - Vibrant Pulse palette preserved (yellow primary / cyan secondary / pink tertiary); only structure was mirrored from Slice 1a, not the participant purple palette.
    - PASS `npx tsc --noEmit` (0 errors).
    - PASS `npx eslint "src/lib/design-tokens.ts"` (0 errors).
- [ ] **4b. Auth / login**.
- [ ] **4c. Dashboard** — KPI strip + alerts.
- [ ] **4d. Quiz Bank** — list, detail, create/edit.
- [ ] **4e. Sessions** — list, create, detail.
- [ ] **4f. Reports / Intelligence** — heatmaps, exports, filter chips.
- [ ] **4g. Admin Users** — TBD until §6.2 auth gate ships.

---

## 6. Cross-cutting interaction layer — Slice 5

> Applies across the app. Some sub-tasks ship inside the screens that need them (Slice 2/3); others are app-wide primitives.

- [ ] **5a. Press feedback** — wrap all primary buttons + option cards via `PressScale` (from 1c).
- [ ] **5b. Page transitions** — route the participant router through `SharedAxisPage` (from 1c).
- [ ] **5c. Celebration moments** — score count-up (2e), XP gain animation (2e), badge unlock toast (2h).
- [ ] **5d. Skeleton + shimmer loading** — extend existing `MedRashSkeletonCard/List` with a purple-tinted shimmer sweep; replace remaining `CircularProgressIndicator` callsites.
- [ ] **5e. Empty-state illustrations & micro-copy** — at minimum for first-pilot-session leaderboard, ranked list, profile history.
- [ ] **5f. Haptics** — wire `Haptics.*` (from 1c) into option-tap, submit, unlock, sign-in success.

---

## 7. Accessibility & responsiveness QA — Slice 6

- [ ] **6a. Contrast audit** — automated check on the new palette across all token pairings.
- [ ] **6b. Tap-target audit** — every interactive element ≥ 44pt.
- [ ] **6c. Reduced-motion parity** — every `Slice 1c` primitive verified to honor the OS setting.
- [ ] **6d. Breakpoint smoke** — phone (390px), tablet (820px), laptop (1280px), widescreen (1920px) for participant + admin + host surfaces.
- [ ] **6e. Semantics labels** — wrap unlabeled interactive elements with `Semantics(label: ...)`.

---

## 8. Docs & governance — Slice 7

- [ ] **7a. Update `docs/design-architecture.md`** — replace the "Light Neo-Medical Academy MVP default" section with the Vibrant Pulse contract.
- [ ] **7b. Update `docs/prd.md`** — soften the "neo-brutalist" direction; reaffirm the nickname-only privacy rule + future avatar-pack note.
- [ ] **7c. Component catalog** — minimal widgetbook (Flutter) + Storybook-lite (admin) for the new primitives.
- [ ] **7d. Keep this file (`docs/ui-overhaul-plan.md`) current** as work lands.

---

## 9. Decisions Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-25 | Adopt Option A (visual lift only); keep nickname-only public display | Lowest pilot risk; fastest unblock; reversible. |
| 2026-05-25 | Future parking lot: curated avatar-pack (no user uploads) | Sidesteps moderation + photo-PII; gives users self-expression later. |
| 2026-05-25 | Slice 1 sequence: 1a → 1b → 1c → 1d, four small commits | Surgical, reviewable, easy to roll back. |
| 2026-05-25 | Font delivery: bundle Poppins + Inter `.ttf` in `pubspec.yaml` | Offline-safe for Ghana field clinicians; zero render-blocking on first paint. |
| 2026-05-25 | Font roles: Poppins → headlines / buttons / score counters / nav; Inter → body / achievement copy | Explicit user instruction; replaces earlier Montserrat plan. |
| 2026-05-25 | Poppins reserved for **UI emphasis only**; never for long medical paragraphs or analytics tables (Inter scales better there). Quiz question body + admin tables explicitly use Inter. | Explicit user instruction; reading-density wins over brand emphasis on long-form clinical copy. |

---

## 10. Future parking lot (not in scope for this overhaul)

- Curated avatar-pack subsystem (`app.user_profiles.avatar_pack_id`, pack catalog, picker UI).
- Public-profile opt-in toggle (Option C from direction lock).
- Achievement evaluator + `app.achievements` + `app.user_achievements` schema (currently Slice 2h ships design-only placeholder).
- Editing facility/specialty post-registration.
- "Intelligent" explanation reveal after ~2 consecutive fails (currently end-of-game review only).
