# MedRash Pilot Delivery Roadmap

## Objective
Ship a one-month MedRash pilot for Ghana using Flutter Web for participants, a separate Netlify-hosted admin panel, and a backend model that preserves future extensibility for additional game modes.

The delivery plan assumes the visual system is defined up front and implemented as shared design infrastructure rather than left for late-stage polish.

## Naming And Verification Guardrails
- canonical product and workspace name is MedRash
- do not use legacy naming aliases in code, docs, scripts, or status reporting
- when reporting verification status, cite the exact command and repository path used
- do not claim full-green verification unless scripts/verify.ps1 finishes successfully in the MedRash workspace

## Delivery Principles
- keep pilot scope narrow and polished
- prioritize low-friction session access
- enforce leaderboard fairness on the backend
- capture answer-level analytics from day one
- build architecture once so future modes do not require rewrites

## Phase 0: Project Setup And Decision Lock
### Outcomes
- architecture decisions are frozen for pilot
- app, admin, and backend repos or folders are scaffold-ready
- operating rules for content and analytics are documented
- the design system is documented and accepted as the visual baseline

### Deliverables
- finalized PRD
- finalized technical blueprint
- finalized design architecture document
- screen inventory and user flow map
- database schema draft
- KPI definitions for pilot reporting

## Phase 1: Core Platform Spine
### Participant App
- initialize Flutter app structure
- add get_it, go_router, freezed, and core dependencies
- implement initCore and service registration
- implement device identity generation and persistence
- implement quick join flow and user-device binding
- implement central theme tokens and branded participant components

### Backend
- create Supabase project
- add base tables for users, user_devices, quizzes, questions, sessions, attempts, and answers
- add ranked-attempt unique index
- add row-level security policies for participant data

### Admin
- initialize Netlify-hosted admin app
- configure Netlify Functions for privileged operations
- add secure environment-variable handling
- implement shared admin shell, sidebar, metric cards, and panel primitives

## Phase 2: Quiz And Session Flow
### Participant App
- implement home quiz menu
- implement session join route using QR deep link
- implement quiz start page with mode selection
- implement quiz runner with answer capture
- implement result page with explanations and retry action
- align all participant flows to the same design-token system and branded interaction states

### Backend
- implement session resolution query
- implement start attempt and finish attempt workflows
- compute season_key in Africa/Accra timezone
- persist answer records for every question

## Phase 3: Leaderboards And Analytics
### Participant App
- implement all-time leaderboard page
- implement monthly leaderboard toggle
- highlight current user rank outside the top list
- componentize podium cards, rank rows, and segmented controls for reuse

### Backend
- add leaderboard SQL views or RPC functions for top rows and self rank
- add analytics queries for most-missed questions and quiz performance
- add session and segment metrics by facility and specialty

## Phase 4: Admin Operations
### Admin Panel
- quiz CRUD
- question CRUD
- CSV question import
- session creation and QR generation
- KPI dashboard
- CSV export for attempts and answers
- intelligence views for knowledge gaps, facility patterns, and treatment perception trends

## Phase 5: Pilot Hardening
### Quality
- test live QR join flow in representative network conditions
- validate ranked attempt enforcement
- validate analytics accuracy against seeded attempts
- confirm export correctness
- verify visual consistency against the documented design architecture across participant and admin surfaces

### Operations
- prepare first content batch
- run internal mock session
- run pilot and review metrics weekly

## Recommended Build Order
1. shared design tokens, shells, and core branded components
2. app shell, DI, and device identity
3. quick join and user persistence
4. session join and quiz flow
5. answer capture and scoring
6. leaderboard logic and UI
7. admin workflows and reporting
8. QA and pilot operations

## Immediate Next Actions
1. create the repo structure for app, admin, and supabase assets
2. convert the design architecture into theme tokens and a component inventory
3. scaffold the Flutter participant app with the Achieve-style core primitives
4. scaffold the admin panel and Netlify Functions
5. write the initial SQL migration for core tables and ranked constraints
6. build quick join end to end before any leaderboard work
7. test the QR session flow before expanding feature scope

## Pilot Exit Criteria
- users can join from QR and finish a 5-question quiz quickly
- all ranked-attempt rules are enforced server-side
- all-time and monthly leaderboards are visible and accurate
- answers are captured and analytics can identify most-missed questions
- admins can create quizzes, sessions, and exports without developer intervention

