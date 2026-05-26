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

### Slice 1c — Motion primitives *(not started)*

**Goal:** Reusable widgets + helpers that consume the `motion*` / `curve*` tokens from 1a. Still no screen migrations.

- [ ] `app/lib/core/motion/press_scale.dart` — wrapper widget that scales child to 0.97 on tap-down, springs back on release. Honors `MediaQuery.disableAnimationsOf`.
- [ ] `app/lib/core/motion/count_up_number.dart` — `TweenAnimationBuilder<int>` wrapper for score/XP reveals.
- [ ] `app/lib/core/motion/stagger_list.dart` — entrance stagger for list children (leaderboard rows, badge grid).
- [ ] `app/lib/core/motion/shared_axis_page.dart` — `CustomTransitionPage` factory for go_router (replaces default slide).
- [ ] `app/lib/core/motion/haptics.dart` — thin wrapper: `Haptics.selection()` / `.submit()` / `.celebrate()` mapping to light/medium/heavy.

#### Verification

- [ ] Widget tests for each primitive (pump animation, assert final scale/value).
- [ ] `prefers-reduced-motion` honoured (verified via test override).

---

### Slice 1d — Icon family pass *(not started)*

**Goal:** Decide and apply one icon family across the participant app for visual consistency with the reference (which uses rounded outline icons).

- [ ] Decision: Material Symbols Rounded (built-in) vs Phosphor (`phosphor_flutter`) vs lucide. **Tentative recommendation:** Material Symbols Rounded — zero new deps, full Flutter integration, matches reference rounded-cap look.
- [ ] Pick icon-size scale: `iconSm: 16`, `iconMd: 20`, `iconLg: 24`, `iconXl: 32`. Add as constants in `arena_design_tokens.dart`.
- [ ] Sweep all icon callsites; replace per-screen `Icons.X` with the rounded variant. (Mechanical — `Icons.account_circle` → `Icons.account_circle_rounded`, etc.)

#### Verification

- [ ] `flutter analyze` clean.
- [ ] Visual smoke on 8 screens.

---

## 3. Participant pillar — Slice 2

> Mobile-first. Depends on Slice 1 foundation. Each screen ships its share of motion + state + a11y work.

- [ ] **2a. Quick-Join / Onboarding** — login-card pattern, nickname preview chip, focus-purple inputs, gold CTA.
- [ ] **2b. Home / Mode-selection** — hero featured card, "My Stats" KPI tiles (streak + ranked-points), mode tile grid.
- [ ] **2c. Session-join lobby** — session hero card, host-mode-aware single primary CTA (already correct from Gap 6; just reskin).
- [ ] **2d. Quiz Runner** — top gradient progress, category chip, letter-badge option cards, press-scale + haptics, correct/wrong flash.
- [ ] **2e. Result + post-quiz** — score reveal with count-up, XP bar fill, "what's next" CTAs.
- [ ] **2f. Leaderboard (World Rank)** — podium top-3 with monogram circles (gold ring on rank 1), scrollable list with stagger-in, sticky "You" row.
- [ ] **2g. Profile** — monogram header, stats tiles, recent attempts, edit form, sign-out modal.
- [ ] **2h. Badges & Achievements** — design-only placeholder (no schema yet); collection grid + tier rings + locked states with "Coming soon" framing on real entries.

---

## 4. Host live-session pillar — Slice 3

> Tablet/desktop primary, mobile fallback. This is **new functionality**, not a reskin — MedRash currently has no host-live presenter surface.

- [ ] **3a. Host control room** — dark theme, live audience count, real-time per-option distribution bars, question broadcast, timer.
- [ ] **3b. QR / share panel** — large QR, copyable join code, deep link.
- [ ] **3c. End-of-session recap** — final standings, knowledge-gap highlights, export CTA.
- [ ] Dark theme `AppTheme.dark()` wired through (depends on Slice 1a tokens having a dark counterpart — add a Slice 3 sub-step to extend tokens for dark mode).

---

## 5. Admin Next.js pillar — Slice 4

> Desktop primary, responsive down to tablet. Lower visual playfulness than participant surfaces (denser, more functional).

- [ ] **4a. Admin token foundation** — Next.js mirror of Slice 1a (CSS vars in `globals.css`, JS tokens in `lib/design-tokens.ts`).
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
