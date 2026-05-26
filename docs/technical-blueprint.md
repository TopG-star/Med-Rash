# MedRash Technical Blueprint

## Architecture Summary
MedRash should be built as a Flutter-based client application with a separate web admin panel. The app architecture follows the Achieve-style pattern:

Model -> Repository -> Screen -> Route

The architecture goal is consistency, clear boundaries, and future-proofing for additional game modes beyond quizzes. Cross-cutting concerns such as loading states, error handling, refresh behavior, analytics hooks, and device-bound identity should be handled by shared architecture primitives instead of individual screens.

The visual architecture should follow the dedicated design system documented in docs/design-architecture.md. That design system is part of the technical baseline, not an optional styling pass.

## Technology Stack
### Participant App
- Flutter Web for pilot deployment on Netlify
- optional Flutter Android build for field distribution if required
- go_router with go_router_builder for typed navigation
- get_it for dependency injection
- freezed and json_serializable for models
- shared_preferences for persisted local state
- flutter_secure_storage for sensitive local data if needed later

### Backend And Data
- Supabase Postgres as primary data store
- Supabase row-level security for participant data access control
- Supabase storage only if asset upload is later required
- SQL views or RPC functions for leaderboard and analytics queries

### Admin Platform
- Next.js web admin hosted on Netlify
- Netlify Functions for privileged admin operations
- service-role access kept server-side only

## Deployment Topology
### Netlify Sites
- app site: Flutter Web participant app
- admin site: Next.js admin panel

### Server-Side Functions
Netlify Functions should be used for:
- admin-only create, update, and delete actions
- CSV import processing
- export generation
- privileged analytics aggregation

For participant attempt operations, Netlify Functions are also the privileged gate between client and Supabase:
- client never uses service-role access directly
- ranked eligibility checks run through a signed gate endpoint
- attempt submissions are written server-side and map participant identity to platform user rows
- ranked unique-constraint conflicts are normalized into stable API error codes

## Project Structure
```text
medRash/
  docs/
  app/
    lib/
      core/
        di/
        infra/
        routing/
        theme/
        ui/
        analytics/
      features/
        profile/
        quiz/
        session/
        leaderboard/
        game_engine/
    test/
  admin/
    app/
    components/
    lib/
    netlify/functions/
  supabase/
    migrations/
    seed/
    functions/
```

## Design System Architecture
### Source Of Truth
The default design system is the light Neo-Medical Academy theme derived from the referenced design assets. A dark cyber-brutalist theme is documented as a secondary variant and should be implemented in a way that does not complicate MVP delivery.

### Token Categories
The participant app and admin panel should share the same abstract token model:
- color roles
- typography roles
- spacing scale
- border widths
- radius scale
- hard-shadow offsets
- semantic rank colors

### Theme Implementation Strategy
#### Flutter
- define a central theme layer under core/theme
- use ThemeData plus custom ThemeExtension classes for brutalist tokens that are not covered by stock Material tokens
- create reusable branded widgets for app bar, card surface, primary button, secondary button, chip, progress bar, option row, podium card, leaderboard row, KPI card, and empty state

#### Admin Web
- define the same tokens in CSS variables or a design-token module
- use a shared shell layout for sidebar navigation, page header, and content canvas
- avoid page-specific styling drift by composing from the same metric cards, bordered panels, and action-button primitives

### Default Token Guidance
- default background: off-white with subtle dot grid
- default border width: 3px
- default hard shadow offset: 4px in the light MVP theme
- primary action color: yellow
- secondary emphasis color: cyan
- tertiary and alert accent: pink
- participant headers use bold editorial display styling
- medical explanations and admin detail text use highly readable body styling

### Component Library Requirement
Do not implement screens as isolated one-off layouts. The codebase should ship a small branded component library that all participant and admin screens consume.

Minimum participant components:
- MedRashAppBar
- ArenaCard
- ArenaButton
- ArenaSecondaryButton
- CategoryChip
- QuizProgressBar
- QuizOptionCard
- ResultExplanationCard
- PodiumCard
- LeaderboardRow
- ProfileSummaryCard

Minimum admin components:
- AdminShell
- AdminSidebar
- AdminUserMenu
- ScopeToggle
- PanelCard (legacy compatibility wrapper)
- EmptyState (legacy compatibility wrapper)
- vp-scoped primitives for panels, KPI tiles, tables, form controls, banners, and row actions

## Client App Core Modules
### Core DI
A single initCore function registers repositories, services, event bus, analytics, device identity service, and router dependencies in get_it.

The theme registry and component-level style dependencies should also be initialized centrally so screens do not own styling rules.

### Device Identity Service
This service generates and persists a device_install_id on first launch. It supports the two-layer onboarding model by binding a lightweight user profile to the current device before the user claims a full account later.

### Identity Spine
The Identity Spine is the canonical participant identity tuple used across app and backend gate layers:
- participant_id: stable local participant identifier
- device_install_id: install-level identity key
- has_bound_profile: local quick-join bind state

The app must initialize Identity Spine during startup and include its values in privileged gate requests. Netlify functions should resolve or create user rows from this identity tuple before any ranked eligibility or attempt insertion logic.

### Repository Mixin
A shared mixin should provide:
- runPersistedQuery for locally cached reads
- runSecureQuery for sensitive persisted reads if later needed
- runEphemeralQuery for in-memory only reads
- runOperation for mutations with uniform failure mapping

For the pilot, persisted and operation flows are the critical pieces.

### DataPage
A shared page base class should manage:
- first-load lifecycle
- refresh on focus or resume
- loading state
- retry on failure
- emission of page refresh events for child widgets

DataPage should expose a content area that works cleanly with the branded app bar, dot-grid background, and page-level card stacking conventions.

### OperationRunnerState
A shared state base class should wrap user-triggered mutations and provide:
- blocking overlay while saving or submitting
- unified failure handling
- optional analytics event emission

### OverlayManager
A top-level overlay manager should sit above the app router and respond to busy-state events, preventing duplicated per-screen loaders.

### EventBus
A typed event bus should provide decoupled communication for:
- overlay busy state
- page reload events
- profile changes
- session or network-level state changes when needed later

## Feature Architecture
### Profile Feature
Responsibilities:
- quick join
- retrieve and update profile
- nickname management
- future account claim flow

Suggested files:
- profile models
- profile repository interface and implementation
- quick join page
- profile page

Design notes:
- quick join and profile screens should share the same form field and profile-summary primitives
- claim account should appear as a distinct protected-progress card rather than a neutral inline link

### Session Feature
Responsibilities:
- resolve join code
- load session metadata
- route users into the linked quiz
- capture session_id on attempts

Suggested files:
- session models
- session repository
- session landing page

Design notes:
- the session page should visually separate ranked mode and learning mode with two clear stacked call-to-action cards
- session metadata should be summarized in a strong hero card before mode selection

### Quiz Feature
Responsibilities:
- fetch available quizzes
- fetch question set
- start attempt
- submit answer selections
- finish attempt
- render explanations and results

Suggested files:
- quiz, question, attempt, answer models
- quiz repository
- quiz menu page
- quiz start page
- quiz runner page
- quiz result page

Design notes:
- quiz runner must maintain low-distraction composition with one primary action per question
- quiz result page must support explanation cards, score summary, and replay actions without visual clutter

### Leaderboard Feature
Responsibilities:
- fetch all-time leaderboard
- fetch monthly leaderboard
- fetch participant rank row
- render world-rank UI with highlighted current user

Suggested files:
- leaderboard models
- leaderboard repository
- leaderboard page

Design notes:
- podium treatment for ranks 1 to 3 is part of the product identity and should be componentized rather than hand-built in the page
- the monthly and all-time switch should be implemented as a branded segmented control, not a browser-default tab pattern

### Game Engine Feature
Responsibilities:
- define reusable game mode abstraction
- run quiz mode as the first implementation
- standardize telemetry across future modes

Suggested files:
- GameMode interface
- QuizMode implementation
- GameSessionRunner
- GameRunResult model

## Routing Model
The app should use two router configurations:
- guest router for quick join and public entry screens
- user router for authenticated or device-bound participant flows

Important routes:
- /join
- /home
- /quiz/:quizId/start
- /quiz/:quizId/run
- /quiz/:quizId/result/:attemptId
- /leaderboard
- /profile
- /s/:joinCode

The app shell should swap routers based on whether the device has an active bound user identity.

The bottom navigation pattern should live in the user shell only and remain visually stable across home, leaderboard, academy, and profile sections.

## Data Model
### users
- id uuid primary key
- full_name text not null
- nickname text not null
- facility text not null
- specialty text not null
- profession text nullable
- created_at timestamptz default now()
- claimed_auth_user_id uuid nullable
- last_seen_at timestamptz nullable

### user_devices
- id uuid primary key
- user_id uuid references users(id)
- device_install_id text unique not null
- created_at timestamptz default now()

### quizzes
- id uuid primary key
- title text not null
- category text not null
- is_active boolean default true
- question_count_default integer default 5
- created_at timestamptz default now()
- updated_at timestamptz default now()

### questions
- id uuid primary key
- quiz_id uuid references quizzes(id)
- prompt text not null
- options jsonb not null
- correct_index integer not null
- explanation text not null
- is_active boolean default true
- created_at timestamptz default now()

### sessions
- id uuid primary key
- quiz_id uuid references quizzes(id)
- name text not null
- join_code text unique not null
- starts_at timestamptz nullable
- ends_at timestamptz nullable
- metadata jsonb nullable
- created_at timestamptz default now()

### attempts
- id uuid primary key
- user_id uuid references users(id)
- quiz_id uuid references quizzes(id)
- session_id uuid nullable references sessions(id)
- mode text check in learning or ranked
- score integer not null
- total_questions integer not null
- time_taken_ms integer not null
- season_key text not null
- created_at timestamptz default now()

### answers
- id uuid primary key
- attempt_id uuid references attempts(id) on delete cascade
- question_id uuid references questions(id)
- selected_index integer not null
- is_correct boolean not null
- answered_at timestamptz default now()

## Database Constraints
### Ranked Attempt Enforcement
Use a partial unique index to enforce one ranked attempt per user per quiz.

```sql
create unique index attempts_ranked_once_per_quiz_idx
on attempts (user_id, quiz_id)
where mode = 'ranked';
```

### Recommended Indexes
```sql
create index attempts_user_created_idx on attempts (user_id, created_at desc);
create index attempts_quiz_mode_created_idx on attempts (quiz_id, mode, created_at desc);
create index attempts_season_mode_idx on attempts (season_key, mode);
create index answers_question_correct_idx on answers (question_id, is_correct);
```

## Season Logic
Monthly leaderboard season_key must be computed using Africa/Accra timezone and stored at attempt completion time. This prevents client timezone drift from corrupting monthly ranking.

## Leaderboard Logic
### All-Time Leaderboard
- source: ranked attempts only
- score: sum of ranked quiz scores across all quizzes

### Monthly Leaderboard
- source: ranked attempts only
- score: sum of ranked quiz scores where season_key equals current Ghana month

### Required UI Payload
Each row should include:
- rank_position
- user_id
- nickname
- avatar_seed
- total_score

The API should return both:
- top N rows
- current participant row even if outside top N

## Analytics Model
### Events And Facts To Capture
- quick join completed
- session resolved from QR
- quiz started
- question answered
- quiz completed
- learning retry started
- leaderboard viewed
- feedback submitted

### Design Telemetry
Track lightweight UI funnel signals that support design iteration during the pilot:
- quick join abandonment
- mode selection split between ranked and learning
- leaderboard view-through after quiz completion
- explanation review depth if expandable answer review is later added

### Derived Intelligence Outputs
- most missed questions overall
- most missed questions by facility
- most missed questions by specialty
- most missed questions by session
- average score by quiz and segment
- completion rate by session and quiz
- repeat play by quiz

## Security Model
### Participant Access
Use row-level security policies to ensure participants can only read and mutate their own profile, attempts, and answer records via the device-bound identity mapping.

### Admin Access
Admin operations should not rely on browser-exposed service credentials. Admin UI should call Netlify Functions, and those functions should perform privileged Supabase operations server-side.

### Privacy
- full name remains private
- nickname is the only public identifier on leaderboards
- exports intended for admins should be role-restricted and audited

## Admin Panel Modules
### Quiz Management
- create quiz
- edit quiz metadata
- activate or deactivate quiz

### Question Management
- add and edit individual questions
- CSV bulk import
- validation for option count, correct index, and explanation presence

### Session Management
- create session
- generate join code
- render downloadable QR
- tag metadata such as facility, region, and presenter where needed

### Analytics Dashboard
- join rate
- completion rate
- median finish time
- average score
- repeat plays
- knowledge gaps by question

### Export Tools
- attempts CSV export
- answers CSV export
- aggregate report export later if needed

## Screen Inventory
### Participant
- quick join
- quiz menu
- quiz detail
- session join
- quiz runner
- quiz result
- leaderboard
- profile

### Admin
- dashboard overview
- quiz bank management
- sessions
- reports
- intelligence analytics

## API And Repository Boundaries
### ProfileRepository
- quickJoin
- getMyProfile
- updateNickname
- claimAccount later

### SessionRepository
- resolveJoinCode
- getSessionSummary

### QuizRepository
- fetchActiveQuizzes
- fetchQuestions
- startAttempt
- submitAnswer
- finishAttempt
- fetchAttemptReview

### LeaderboardRepository
- fetchTopAllTime
- fetchTopMonthly
- fetchMyAllTimeRank
- fetchMyMonthlyRank

## Future-Proofing For Additional Game Modes
The game engine should abstract game execution away from quiz-specific UI and persistence rules.

Recommended interfaces:
- GameMode
- GameSessionRunner
- GameRunResult
- GameTelemetryEvent

QuizMode should be the first implementation. Future modes such as puzzles, speed rounds, or team competitions should plug into the same runner and reporting model.

## Recommended Delivery Sequence
1. establish core architecture and device-bound identity
2. establish shared design tokens and branded components
2. implement quick join and profile persistence
3. implement session join and quiz engine
4. implement answer capture and result review
5. implement leaderboard queries and UI
6. implement admin content workflows and analytics
7. pilot hardening and operational reporting

