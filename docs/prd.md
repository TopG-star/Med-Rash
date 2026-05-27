# MedRash Pilot PRD

## Product Summary
MedRash is a lightweight, mobile-first gamified medical learning and engagement platform for healthcare professionals in Ghana. It is designed for use during medical presentations, detailing sessions, and CME activities through QR-based access, while also supporting open access outside live sessions. The pilot focuses on short quiz-based interactions that improve attention and recall while generating actionable field intelligence on product awareness, knowledge gaps, and treatment understanding.

The design direction for the pilot is **Vibrant Pulse** — a light, purple-led visual system that deliberately avoids generic clinical software patterns while staying readable under real clinic conditions. The default visual system ships in both light and dark variants (selected by OS preference). The earlier neo-brutalist "Neo-Medical Academy" direction is retired as the default and preserved only as historical context for the pre-May-2026 reference set.

## Problem Statement
Most medical presentation sessions are passive. Speakers present slides, participants listen, and engagement is difficult to measure. As a result:
- attention drops during sessions
- product and disease knowledge retention is inconsistent
- companies do not capture structured insight from participant understanding and misconceptions
- follow-up strategy relies on anecdotal feedback rather than measurable intelligence

MedRash addresses this by converting passive sessions into short, interactive quiz experiences that provide both learning reinforcement and analytics.

## Pilot Goal
Validate that a short, gamified quiz experience can improve engagement during medical presentations and produce useful analytics for a one-month pilot in Ghana.

## Business Goals
- transform passive presentations and CME sessions into interactive engagement
- increase recall of approved product and scientific information
- identify knowledge gaps by facility, specialty, and session
- capture measurable engagement data for sales, medical, and management teams
- establish an architecture that supports future expansion into additional game modes

## Pilot Context Fit
The Ghana pilot is anchored in real medical-representative field workflows: CMEs, presentations, master classes, and roundtables with healthcare professionals. Initial quiz content and analytics segmentation should align to this portfolio and disease mapping:
- Tavanic: UTI and infections
- Clexane: VTE including DVT and PE
- Aprovel: Hypertension
- Lantus: Diabetes
- Ortacta: VTE
- Utrogestan: hormonal imbalances and fertility support context
- Androgel: testosterone deficiency

The pilot must support both live QR session participation and post-session self-paced retries, while preserving analytics outputs on knowledge gaps, region awareness, facility activity, and completion behavior.

## Success Metrics
### Primary KPIs
- join rate: percentage of users who scan or open a session and complete quick join
- completion rate: percentage of quiz starters who finish the quiz
- median time to finish: target 90 to 180 seconds, hard cap 5 minutes
- average score per quiz
- learning lift: change between first performance and improved learning attempts, or pre- versus post-session where configured
- repeat plays: percentage of users who retry a quiz in learning mode or return within 7 days
- feedback score: lightweight post-quiz satisfaction or usefulness rating

### Strategic Intelligence Outputs
- most missed questions by quiz, session, facility, and specialty
- product awareness gaps
- topic misunderstanding patterns
- comparative engagement by facility and specialty
- session-level participation and completion trends

## Target Users
### End Users
Healthcare professionals and related medical stakeholders in Ghana, including:
- doctors
- pharmacists
- nurses
- medical sales representatives
- other approved healthcare participants

### Administrative Users
Separate web admin users, including:
- sales reps
- medical reps
- managers
- medical affairs teams
- platform admins

## Compliance And Security Constraints
- no physical prizes are awarded
- only in-game recognition and points are used
- full names are stored privately
- public leaderboard displays nickname only — this is a hard contract; no surface (admin, host, exports, intelligence views) may render a full name in any public or shared context
- profile photos are not collected during the pilot; a curated avatar-pack (no user uploads) is on the future parking lot to give users self-expression without introducing photo-PII or moderation surface
- nickname is auto-generated at join and editable later
- facility and specialty are mandatory
- content must be approved externally before admin upload
- content is expected to be on-label or guideline-based
- implementation should align with ISO/IEC 27001 intent for access control, encryption, auditability, backups, and least privilege

## Product Scope For Pilot
### Included In MVP
- instant quick join with silent account creation
- profile capture: full name, facility, specialty, nickname
- topic and product quiz selection
- QR-based session entry
- open access anytime play
- quiz engine for short multiple-choice quizzes
- learning mode with unlimited retries
- ranked mode with one ranked attempt per quiz ever
- score and explanation review after completion
- all-time leaderboard
- monthly leaderboard
- admin panel for quizzes, sessions, analytics, and exports
- answer capture for knowledge-gap analysis
- shared participant and admin design system based on the referenced design architecture

### Excluded From MVP
- physical rewards or monetary incentives
- multiplayer or team battle modes
- CPD point integration
- advanced adaptive quizzes
- offline-first synchronization
- native iOS release for the pilot unless later required

## User Roles And Permissions
### Participant
- complete quick join
- play quizzes in learning and ranked modes
- view results and leaderboards
- edit nickname later

### Admin
- create and edit quizzes
- upload and manage questions
- create sessions and generate QR links
- view analytics dashboards
- export attempt and answer data

## Core User Stories
### Quick Join
As a participant, I want to join quickly without a password so that I can start a quiz during a presentation in under 20 seconds.

### Silent Account Creation
As the system, I want to create a lightweight account automatically after quick join so that users can participate immediately and retain continuity on that device.

### Open Access Play
As a participant, I want to access quizzes outside live sessions so that I can learn or replay when convenient.

### Session Join
As a participant, I want to scan a QR code that opens the relevant session quiz directly so that joining a live presentation is frictionless.

### Quiz Play
As a participant, I want to answer a short sequence of predefined questions and get a score at the end so that the experience is quick and rewarding.

### Learning Retry
As a participant, I want unlimited retries in learning mode so that I can improve until I master the quiz.

### Ranked Attempt
As a participant, I want one ranked attempt per quiz so that leaderboard rankings remain fair.

### Leaderboard View
As a participant, I want to view all-time and monthly rankings and see my own highlighted position so that I stay motivated.

### Admin Content Management
As an admin, I want to upload approved content and activate quizzes so that sessions can be launched quickly.

### Analytics And Intelligence
As an admin or manager, I want analytics by session, facility, and specialty so that I can identify knowledge gaps and engagement trends.

## Functional Requirements
### Onboarding
- user enters full name, facility, and specialty
- system auto-generates a nickname and allows optional edit
- no password is required for pilot participation
- system creates a lightweight user profile and binds it to a device identity
- onboarding screen uses a single dominant CTA and a low-friction card layout consistent with the design system

### Quiz Access
- users can access quizzes from open menu or session QR link
- active quizzes are visible in the app menu
- session links route users to the specific quiz associated with the session

### Quiz Engine
- quiz format is multiple choice only for MVP
- default quiz length is 5 questions
- maximum quiz length for pilot is 10 questions
- each question has 4 options
- answers are recorded per question
- results include final score and answer explanations
- question screens use large, stacked option cards with high-contrast selected states and minimal distraction

### Modes
- learning mode allows unlimited retries
- ranked mode allows exactly one ranked attempt per user per quiz ever
- ranked mode feeds leaderboard calculations
- learning mode does not affect leaderboard ranking

### Leaderboards
- all-time leaderboard sums ranked scores across quizzes
- monthly leaderboard sums ranked scores within the current season key
- top ranks are shown prominently
- user row is highlighted even when outside visible top list
- rank 1, rank 2, and rank 3 use fixed visual color semantics for instant recognition
- leaderboard includes a monthly versus all-time toggle as part of the MVP participant experience

### Admin Panel
- create and edit quizzes
- create and edit questions
- upload questions in bulk via CSV
- create sessions with join codes and QR links
- view KPI dashboard
- export attempts and answers
- admin pages use a consistent sidebar-plus-canvas layout aligned with the MedRash visual system

## Non-Functional Requirements
- mobile-first UI
- fast initial load suitable for QR-based session entry
- clear visual hierarchy and playful game-like presentation
- robust data capture for future analytics
- maintainable architecture for future game modes
- server-side enforcement of ranked-attempt rules
- deployable on Netlify for pilot operations

## Design Requirements
- the default participant and admin theme is the Vibrant Pulse light system, with a first-class Vibrant Pulse dark companion that flips on by OS preference
- the UI must use soft 1px outlines, low-opacity elevation, generous radii (20dp cards, 999dp pills), and ≥ 44pt tap targets — no thick borders, no hard offset shadows
- the canvas is an off-white tinted background (`#F9F9FB`) with no decorative dot-grid pattern
- brand purple (`#5300B7`) signals primary action and identity; amber gold (`#FFC329`) signals celebration and top-rank emphasis; success green and danger red are used as borders + badge fills on their tinted surfaces (never as small body text)
- the participant experience must feel competitive and polished without becoming visually noisy or toy-like
- the admin experience must inherit the same brand system while prioritizing operational clarity over playfulness
- the dark Vibrant Pulse companion is a supported first-class mode — not an experimental campaign theme — and must keep contrast ≥ WCAG AA across every token pairing
- full token contract, motion primitives, and accessibility test references live in `docs/design-architecture.md`

## UX Principles
- 1 to 3 minute interaction target
- low friction onboarding
- clear next action at every screen
- playful but credible design suitable for healthcare professionals
- leaderboard and score visibility as motivation loops
- minimal cognitive load

## Screen Architecture
### Participant Screens
- quick join
- home or quiz menu
- quiz detail
- session join
- quiz runner
- quiz result
- world rank leaderboard
- profile

### Admin Screens
- dashboard overview
- quiz bank management
- sessions
- reports or exports
- intelligence or analytics

## Acceptance Criteria
- a new participant can scan a QR code, complete quick join, and reach the first quiz question within 20 seconds on a stable connection
- a participant can complete a 5-question quiz and see score and explanations
- a participant can retry in learning mode without restriction
- a participant cannot submit more than one ranked attempt for the same quiz
- a participant can view all-time and monthly leaderboards with their own rank highlighted
- an admin can create a quiz, upload questions, create a session, and export attempt data
- analytics can identify the most missed questions by quiz and segment results by facility and specialty
- participant and admin screens remain visually consistent with the documented design architecture

## Pilot Rollout Plan
### Week 1
- finalize approved question bank
- configure pilot quizzes and session templates
- internal QA and dry run

### Weeks 2 To 4
- run live sessions
- monitor join rate, completion rate, and time to finish
- review analytics weekly
- refine content and UX issues without changing core rules

## Risks And Mitigations
- low adoption due to friction: keep quick join minimal and QR flow fast
- inconsistent facility naming: allow free text in pilot and normalize later in reporting
- poor credibility from weak questions: enforce admin upload of only pre-approved content
- leaderboard abuse: enforce ranked-attempt uniqueness at database level
- future feature sprawl: keep MVP limited to quiz mode and preserve extensible engine boundaries

