# MedRash Design Architecture

## Purpose
This document defines the global design architecture for MedRash based on the attached design reference set. It serves as the source of truth for the participant experience, the admin experience, and the shared visual language that should remain consistent as the product expands.

The design direction is not generic healthcare SaaS. It intentionally combines educational credibility, competitive energy, and strong tap-friendly structure. The result is a branded gamified medical platform that feels fast, memorable, and operationally clear.

## Design System Decision
### Default Theme
The default product theme is **Vibrant Pulse** — a light, purple-led system tuned for clinical reading density and competitive energy. It is the MVP visual baseline for the participant app and the admin panel.

The earlier "Neo-Medical Academy" light brutalist direction is retired as the default; it is preserved only as historical context for the pre-May-2026 reference screens.

### Secondary Theme
A dark companion mode (same token contract, brightness-flipped accents) ships alongside the light default and is selected by the OS preference. It is not an experimental campaign theme — it is a first-class supported mode.

### Current Pilot UI Mode (May 2026 lock)
For the active pilot rollout, every participant + admin surface uses the Vibrant Pulse contract end-to-end while preserving MedRash information architecture and clinical copy.

Locked constraints for this mode:
- keep participant-facing privacy model unchanged (nickname-only in public contexts)
- keep existing IA and route structure; no broad navigation reshuffle
- treat this as a visual + interaction uplift, not a product-scope rewrite
- preserve intentional exceptions (for example, the host control-room dark visual language)

## Brand Expression
MedRash should feel like:
- a medical learning arena, not a hospital record system
- a high-confidence educational product, not a casual trivia toy
- a competitive but professional experience for Ghanaian healthcare users
- a modern field-intelligence platform for sales, medical, and management teams

The UI should communicate speed, clarity, and reward. The visual identity should make participants feel they are entering a meaningful challenge while keeping the experience short and usable under real work pressure.

## Core Visual Principles
- high-contrast hierarchy via type weight + a single saturated accent, not heavy chrome
- mobile-first composition with tap targets ≥ 44pt (WCAG 2.5.5)
- soft 1px outlines + low-opacity elevation instead of hard offset shadows
- 16dp / 20dp radii for cards and inputs; 999dp pills for chips and progress
- strong color semantics: purple = identity / primary action, gold = celebration / secondary, green = correct, red = wrong, neutral text on tinted surfaces
- minimal cognitive load with one dominant action per screen
- consistent card-based surfaces across participant and admin flows
- playful competition without losing scientific credibility — Vibrant Pulse motion is short, spring-eased, and honors `prefers-reduced-motion`

## Theme Foundations
### Light Theme: Vibrant Pulse (default)
The primary production theme. Encoded as `ArenaDesignTokens.light` in [app/lib/core/theme/design_tokens.dart](../app/lib/core/theme/design_tokens.dart) and mirrored as CSS variables in the admin panel.

Characteristics:
- off-white canvas (`#F9F9FB`) on pure white card surfaces (`#FFFFFF`)
- soft tinted muted surface (`#F5F3FA`) for grouped containers
- saturated brand purple (`#5300B7`) as the dominant action / identity accent
- darker purple (`#3D0085`) for press, focus, and high-emphasis fills against light text
- lilac (`#EBDDFF`) for selected-state surfaces and badge backgrounds
- amber gold (`#FFC329`) for celebration, top-rank emphasis, and the secondary CTA fill
- success green (`#128A3E`) and danger red (`#DC2626`) used as borders + badge fills on tinted success / danger surfaces, never as small body text on those surfaces
- text primary `#1E1A2E`, text secondary `#5C5470` — Poppins for emphasis, Inter for body

### Dark Theme: Vibrant Pulse Night
First-class companion. Same token contract, brightness-aware accents.

Characteristics:
- deep neutral surfaces with lifted primary tinting for elevation
- light lilac primary (`#DDB7FF`) for icon glyphs and accent text
- dark purple (`#3D2B5C`) for filled actions paired with white foreground — this is the dark-mode equivalent of the light-mode `primaryStrong` fill (the contract is encoded as `brightness == dark ? primarySoft : primaryStrong` in toast + empty-state CTA code)
- gold secondary keeps its identity, paired with `onSecondary` (`#261A00`) for body text
- success / danger surfaces are deep saturated tints (`#153D24`, `#3D1515`) with their light accent counterparts for icon glyphs

## Design Tokens
### Color Roles
#### Participant And Admin Shared Roles
- primary action and identity: brand purple (`primary` / `primaryStrong` for press)
- selected-state surface + badge background: lilac (`primarySoft`)
- secondary action, celebration, top-rank emphasis: amber gold (`secondary`, paired with `onSecondary` for text)
- correctness signaling: success green as border + badge fill on `successSurface`
- error / alert signaling: danger red as border + badge fill on `dangerSurface`
- structural outline: 1px hairline (`outline`) — replaces the previous 3px black border
- elevation: low-opacity drop shadow + outline; pressed state collapses via `PressScale` (scale 0.97) not by erasing a hard shadow
- background canvas: off-white in light mode (`#F9F9FB`), deep neutral in dark mode

#### Rank Semantics
- rank 1: amber gold
- rank 2: lilac / brand purple
- rank 3: muted bronze (derived from `secondary` desaturated)
- current user highlight: filled purple row in both light and dark modes

### Typography
Both themes share the same family contract — Poppins for UI emphasis and Inter for reading-dense content. Bundled offline as `.ttf` weights in `app/pubspec.yaml` so first paint never blocks on the network (critical for Ghanaian field clinics with patchy connectivity).

#### Roles
- display and headline: **Poppins** (weights 600 / 700 / 800)
- buttons, score counters, navigation labels: **Poppins**
- body, quiz question stem, medical explanations, admin tables: **Inter** (variable font)
- meta labels, timers, leaderboard ranks: Poppins 700

Poppins is reserved for UI emphasis only. Long-form clinical paragraphs and analytics tables explicitly use Inter — reading-density wins over brand emphasis on long-form copy.

#### Typographic Rules
- use uppercase for major screen titles and leaderboard headers
- use Poppins 800 for ranks and primary CTAs
- keep body copy readable and uncompressed for medical explanations
- keep labels short and scannable

### Spacing
- base unit: 8px
- mobile horizontal margin: 20px in the light theme reference set
- stack spacing: 8px, 16px, and 24px tiers
- desktop should preserve the same rhythm while moving into wider multi-column layouts

### Borders, Radius, And Elevation
- default border width: 1px hairline (`outline`)
- elevation: 8–16dp soft shadow at 8–12% opacity; never a hard offset block
- shared surface radius: 20dp for primary cards, 16dp for inputs, 999dp for pills + chips
- avatars: circular with `outline` hairline ring
- pressed state: `PressScale` collapses the element to 0.97 with spring ease (honors `disableAnimations`); no shadow toggling

## Shared Component Architecture
### App Bar
- centered uppercase screen title
- left navigation affordance or close affordance
- minimal chrome, strong border separation

### Card Surface
- heavy border
- hard shadow
- clear internal spacing
- one dominant content purpose per card

### Buttons
- primary button (`ArenaButton`) uses brand purple in light mode and dark purple (`primarySoft`) in dark mode, both with white foreground (`Colors.white`)
- secondary button uses amber gold with `onSecondary` text
- ghost / tertiary action uses an outlined pill on the canvas
- destructive actions use the danger red palette and only when destructive intent is real
- pressed state: `PressScale` (0.97 spring) — never a shadow-collapse

### Inputs
- large bordered text fields
- strong placeholder contrast
- minimum tap-friendly height
- editable nickname affordance should be icon-supported where used

### Category Chips
- small capsule tags with strong contrast
- used for specialties, quiz categories, difficulty labels, and session labels

### Progress Bar
- outlined pill track (`surface` fill, 1px `outline`)
- gradient fill: brand purple → amber gold, left-to-right
- tween settles in 360ms cubic-out (zero duration under `MediaQuery.disableAnimations`)
- rank or quiz state should be understood at a glance

### Avatar Pattern
- generated avatar or profile image in circular frame
- nickname always paired visually with avatar in public ranking contexts
- full name never exposed on public leaderboards

## Participant Experience Screen Architecture
### 1. Quick Join
Purpose:
Capture the minimum onboarding data needed to start immediately.

Required fields:
- full name
- facility
- specialty

UI behavior:
- auto-generated nickname shown as a preview card
- nickname edit affordance present but optional
- one dominant CTA: Start Playing
- screen must feel calm, direct, and low-friction

### 2. Home Or Quiz Menu
Purpose:
Allow participants to discover active quizzes and disease or product topics.

UI behavior:
- card-based list of topics or modules
- each card should show estimated time, difficulty, and question count where relevant
- navigation should make the next action obvious without overload

### 3. Quiz Detail
Purpose:
Let the participant understand what they are about to play before choosing mode.

Content blocks:
- module or category tag
- time estimate
- quiz title and short description
- objectives
- top scorers preview
- primary action buttons for learning mode and ranked mode

### 4. Session Join
Purpose:
Present the specific live session after QR resolution and clarify the choice between ranked and learning play.

Content blocks:
- session title
- quiz topic
- question count
- time limit if applicable
- host information
- ranked mode CTA
- learning mode CTA

### 5. Quiz Runner
Purpose:
Optimize for answer speed and focus.

Required visual elements:
- progress indicator with question count
- timer where applicable
- category chip
- large question card
- answer options as clear, pressable stacked cards
- one bottom action to submit or advance

Rules:
- only one primary action visible at a time
- answer states must be obvious before submission
- reading load should remain low even for medical wording

### 6. Quiz Result
Purpose:
Reward the participant and reinforce learning.

Content blocks:
- large score summary
- time taken
- explanation block for wrong answers
- retry learning CTA
- leaderboard CTA

Rules:
- explanation design should feel educational, not punitive
- wrong-answer review must remain visually easy to scan

### 7. World Rank
Purpose:
Close the motivation loop.

Content blocks:
- monthly and all-time toggle
- podium treatment for top 3
- list for the remaining ranks
- highlighted current user row
- bottom navigation support for app-wide continuity

Rules:
- podium colors follow the shared rank semantics
- user row must remain visible even if outside the top visible entries
- nickname and score should be legible at a glance

### 8. Profile
Purpose:
Let the participant manage public identity and account continuity.

Content blocks:
- avatar and nickname
- total points and rank summary
- editable nickname, facility, and specialty
- claim account panel
- save profile action

Rules:
- claim account should feel like value protection, not setup friction
- profile editing should preserve the same card language as the rest of the app

### 9. Bottom Navigation
Participant navigation should be limited and stable.

Recommended tabs:
- home
- leaderboard
- academy or modules
- profile

The active item should use a filled purple pill background with white foreground; inactive items use `textSecondary` glyphs on the canvas — no hard-shadow emphasis.

## Admin Experience Design Architecture
The admin interface should share MedRash brand DNA but shift from gameplay emphasis to operational clarity.

### Admin Personality
- structured
- analytical
- credible
- still brand-consistent with the participant experience

### Admin Layout Pattern
- persistent left sidebar navigation on desktop
- content canvas on the right
- strong header title per page
- modular cards for metrics, forms, and tables

### Admin Navigation Areas
- dashboard
- users
- quiz bank
- sessions
- analytics or intelligence
- settings
- reports or exports

### Admin Pages
#### Dashboard Overview
- top KPI cards for join rate, completion rate, and average score
- alerts panel for operational signals
- visual summary of knowledge gaps

#### Quiz Bank Management
- accordion or grouped list of quizzes
- question rows with edit and delete affordances
- create quiz and bulk upload actions near the top

#### Sessions
- session creation form
- quiz selector
- date fields
- QR preview area
- active and ended sessions list

#### Reports
- export configuration with format and date range
- previous exports list
- strong separation between generation and retrieval actions

#### Intelligence
- deeper insight page for knowledge gaps, facility heatmaps, and treatment perception trends
- intended for management and medical strategy use, not just raw exports

## Responsive Strategy
### Participant App
- optimize for phone-first vertical interaction
- keep one-column composition as the primary pattern
- preserve border weight and hard shadow language on smaller screens without crowding content

### Admin Panel
- desktop-first for pilot
- tablet support acceptable
- mobile admin support can be limited to basic viewing unless explicitly prioritized later

## Motion And Interaction
- keep motion short and purposeful
- the canonical press feedback is `PressScale` (scale 0.97, spring ease) — never a shadow-collapse
- screen transitions use `sharedAxisPage`; lists fade-in via `StaggerList`; numbers tick up via `CountUpNumber`; skeletons shimmer via `MedRashSkeleton`
- every motion primitive honors `MediaQuery.disableAnimations` (covered by [reduced_motion_parity_test.dart](../app/test/core/ui/reduced_motion_parity_test.dart))
- avoid decorative animation that slows quiz flow
- reserve animated emphasis for state-change moments: rank reveal, score reveal, badge unlock, CTA confirmation

## Accessibility And Usability
- WCAG AA contrast verified across every token pairing in both themes by [design_tokens_contrast_test.dart](../app/test/core/theme/design_tokens_contrast_test.dart) (4.5:1 body text, 3.0:1 large text / non-text)
- tap targets ≥ 44pt guarded by [tap_target_test.dart](../app/test/core/a11y/tap_target_test.dart) (theme leaves `MaterialTapTargetSize.padded`)
- icon-only controls expose a `tooltip` (e.g. `ArenaScaffold` back / close) so screen readers announce their purpose — covered by [semantics_labels_test.dart](../app/test/core/a11y/semantics_labels_test.dart)
- never rely on color alone to communicate correctness, rank, or urgency — pair every signal with text, icon, or position
- ensure all leaderboard and KPI information is text-readable in addition to color-coded
- preserve readability for longer medical explanations and facility names — Inter handles density; Poppins is never used for paragraphs

## Implementation Guidance
### Flutter Participant App
- encode design tokens as a central theme layer and custom component library
- implement shared primitives for app bars, cards, buttons, chips, progress bars, option cards, and leaderboard rows
- keep all screens built from reusable branded components rather than bespoke layouts

### Admin Web App
- implement the same token system in CSS variables or theme constants
- keep tables, forms, metric cards, and export panels visually aligned with the participant brand
- use a consistent sidebar and page-shell pattern across all admin pages

## Source Reference Mapping
The attached design reference set covers these major surfaces:
- quick join
- quiz detail
- quiz runner
- quiz result
- world rank leaderboard
- profile
- session join
- admin dashboard
- admin sessions
- admin reports
- admin quiz bank
- admin intelligence

These screens are sufficient to define the initial global design architecture for the pilot.

## Documentation Relationship
This document should be read alongside:
- the PRD for product intent and scope
- the technical blueprint for implementation structure
- the implementation roadmap for delivery order

All future screens should extend this design system unless there is a deliberate and documented reason to introduce a new pattern.
