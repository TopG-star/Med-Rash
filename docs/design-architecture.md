# MedRash Design Architecture

## Purpose
This document defines the global design architecture for MedRash based on the attached design reference set. It serves as the source of truth for the participant experience, the admin experience, and the shared visual language that should remain consistent as the product expands.

The design direction is not generic healthcare SaaS. It intentionally combines educational credibility, competitive energy, and strong tap-friendly structure. The result is a branded gamified medical platform that feels fast, memorable, and operationally clear.

## Design System Decision
### Default Theme
The default product theme is the light neo-brutalist system referred to in the reference files as Neo-Medical Academy.

This is the system that should define the MVP visual baseline for both the participant app and the admin panel because it best matches the attached screen set and the intended pilot experience.

### Secondary Theme
The dark cyber-brutalist system should be treated as a supported brand variant for later rollout, theme switching, campaigns, or premium seasonal events. It should not be the default MVP theme unless the product deliberately ships a dual-theme experience.

### Current Pilot UI Mode (May 2026 lock)
For the active pilot rollout, admin surfaces are using the **Option A visual lift** direction (Vibrant Pulse) while preserving MedRash information architecture and clinical copy.

Locked constraints for this mode:
- keep participant-facing privacy model unchanged (nickname-only in public contexts)
- keep existing IA and route structure; no broad navigation reshuffle
- treat this as a visual + interaction uplift, not a product-scope rewrite
- preserve intentional exceptions (for example, the host control room dark visual language)

## Brand Expression
MedRash should feel like:
- a medical learning arena, not a hospital record system
- a high-confidence educational product, not a casual trivia toy
- a competitive but professional experience for Ghanaian healthcare users
- a modern field-intelligence platform for sales, medical, and management teams

The UI should communicate speed, clarity, and reward. The visual identity should make participants feel they are entering a meaningful challenge while keeping the experience short and usable under real work pressure.

## Core Visual Principles
- high-contrast hierarchy over subtle polish
- mobile-first composition with large tap targets
- thick borders and hard shadows instead of soft depth
- strong color semantics for rank, action, and category
- minimal cognitive load with one dominant action per screen
- consistent card-based surfaces across participant and admin flows
- playful competition without losing scientific credibility

## Theme Foundations
### Light Theme: Neo-Medical Academy
Use this as the primary production theme.

Characteristics:
- off-white background with subtle dot-grid pattern
- black structural borders and hard shadow offsets
- yellow for primary action and first-place emphasis
- cyan for secondary emphasis, category chips, and supporting actions
- pink for tertiary emphasis, alerts, and third-place states
- bold editorial headlines with clean readable body text

### Dark Theme: Cyber-Clinical Brutalism
Use this as an optional future theme variant.

Characteristics:
- charcoal and near-black surfaces
- electric violet as primary brand energy
- cyber green and neon cyan for system states and technical accents
- sharper, more experimental command-center feel

## Design Tokens
### Color Roles
#### Participant And Admin Shared Roles
- primary action and high-achievement: yellow
- secondary action and topical tags: cyan
- tertiary ranking and alerts: pink
- structural border and hard shadow: black in light mode, dark outline in dark mode
- background canvas: off-white with dot grid in light mode, charcoal with dot grid in dark mode

#### Rank Semantics
- rank 1: yellow
- rank 2: cyan
- rank 3: pink
- current user highlight: yellow by default in light theme, violet/lilac in dark theme

### Typography
#### Light Theme
- display and headline: Anybody
- body and labels: Hanken Grotesk

#### Dark Theme
- display and headline: Space Grotesk
- body: Inter
- meta labels and timers: Space Mono

#### Typographic Rules
- use uppercase for major headers, score titles, and leaderboard headings
- use bold, condensed visual weight for ranks and primary calls to action
- keep body copy readable and uncompressed for medical explanations
- keep labels short and scannable

### Spacing
- base unit: 8px
- mobile horizontal margin: 20px in the light theme reference set
- stack spacing: 8px, 16px, and 24px tiers
- desktop should preserve the same rhythm while moving into wider multi-column layouts

### Borders, Radius, And Shadows
- default border width: 3px
- default hard shadow offset: 4px in light mode MVP
- shared surface radius: 16px for primary cards and inputs in the light theme
- chips and smaller controls: 12px radius
- avatars: circular with visible border
- pressed state: element moves into its shadow rather than fading opacity only

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
- primary button uses yellow in the light theme
- secondary button uses white or cyan depending on priority
- destructive or alert actions should use pink or red only when meaningfully needed
- pressed states should collapse the hard shadow

### Inputs
- large bordered text fields
- strong placeholder contrast
- minimum tap-friendly height
- editable nickname affordance should be icon-supported where used

### Category Chips
- small capsule tags with strong contrast
- used for specialties, quiz categories, difficulty labels, and session labels

### Progress Bar
- thick outlined track
- flat fill color
- no gradients
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

The active item should use filled color and hard-shadow emphasis.

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
- preferred interaction pattern is physical press simulation via shadow collapse and position shift
- avoid decorative animation that slows quiz flow
- reserve animated emphasis for state change moments such as rank reveal, score reveal, or CTA confirmation

## Accessibility And Usability
- maintain strong text contrast in both themes
- support large tap targets for busy healthcare users
- do not rely on color alone to communicate correctness, rank, or urgency
- ensure all leaderboard and KPI information is text-readable in addition to color-coded
- preserve readability for longer medical explanations and facility names

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
