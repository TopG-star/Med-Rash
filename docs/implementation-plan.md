# MedRash Foundations Implementation Plan

Status note (2026-05-26): this file is the original foundation bootstrap plan.
For current rollout status and shipped-slice tracking, use:
- `docs/implementation-roadmap.md`
- `docs/admin-surfaces.md`

**Goal:** Establish MedRash’s design-token system, scaffold the participant and admin application shells, and add the first production-grade Supabase schema and reporting queries.

**Architecture:** The participant app uses Flutter with an Achieve-style structure: Model -> Repository -> Screen -> Route, plus shared infrastructure for DI, events, overlay, and page lifecycle. The admin panel uses Next.js on Netlify with a shared token system and a stable shell layout. The data layer uses Supabase Postgres with server-enforced ranked-attempt rules and analytics-ready answer capture.

**Tech Stack:** Flutter Web, Next.js, Netlify, Netlify Functions, Supabase Postgres, get_it, go_router, freezed, json_serializable.

**Files to create/modify:**
- Create: `docs/implementation-plan.md`
- Create: `app/pubspec.yaml`
- Create: `app/lib/main.dart`
- Create: `app/lib/core/di/get_it.dart`
- Create: `app/lib/core/di/init_core.dart`
- Create: `app/lib/core/theme/app_theme.dart`
- Create: `app/lib/core/theme/design_tokens.dart`
- Create: `app/lib/core/theme/theme_extensions.dart`
- Create: `app/lib/core/ui/arena_app.dart`
- Create: `app/lib/core/ui/widgets/arena_scaffold.dart`
- Create: `app/lib/core/ui/widgets/arena_button.dart`
- Create: `app/lib/core/ui/widgets/arena_card.dart`
- Create: `app/lib/core/ui/widgets/arena_chip.dart`
- Create: `app/lib/core/ui/widgets/arena_bottom_nav.dart`
- Create: `app/lib/core/ui/widgets/quiz_progress_bar.dart`
- Create: `app/lib/core/routing/app_router.dart`
- Create: `app/lib/core/routing/guest_router.dart`
- Create: `app/lib/core/routing/user_router.dart`
- Create: `app/lib/core/infra/event_bus.dart`
- Create: `app/lib/core/infra/device_identity_service.dart`
- Create: `app/lib/core/infra/auth_state_manager.dart`
- Create: `app/lib/core/infra/overlay_manager.dart`
- Create: `app/lib/core/infra/repository_mixin.dart`
- Create: `app/lib/core/ui/data_page.dart`
- Create: `app/lib/core/ui/operation_runner_state.dart`
- Create: `app/lib/features/profile/screens/quick_join_page.dart`
- Create: `app/lib/features/profile/screens/profile_page.dart`
- Create: `app/lib/features/quiz/screens/home_page.dart`
- Create: `app/lib/features/quiz/screens/quiz_detail_page.dart`
- Create: `app/lib/features/session/screens/session_join_page.dart`
- Create: `app/lib/features/quiz/screens/quiz_runner_page.dart`
- Create: `app/lib/features/quiz/screens/quiz_result_page.dart`
- Create: `app/lib/features/leaderboard/screens/world_rank_page.dart`
- Create: `app/lib/features/profile/models/user_profile.dart`
- Create: `app/lib/features/quiz/models/quiz.dart`
- Create: `app/lib/features/quiz/models/question.dart`
- Create: `app/lib/features/quiz/models/attempt.dart`
- Create: `app/lib/features/session/models/session_info.dart`
- Create: `app/lib/features/leaderboard/models/leaderboard_row.dart`
- Create: `admin/package.json`
- Create: `admin/tsconfig.json`
- Create: `admin/next.config.ts`
- Create: `admin/app/layout.tsx`
- Create: `admin/app/page.tsx`
- Create: `admin/app/dashboard/page.tsx`
- Create: `admin/app/quiz-bank/page.tsx`
- Create: `admin/app/sessions/page.tsx`
- Create: `admin/app/reports/page.tsx`
- Create: `admin/app/intelligence/page.tsx`
- Create: `admin/app/globals.css`
- Create: `admin/lib/design-tokens.ts`
- Create: `admin/components/admin-shell.tsx`
- Create: `admin/components/admin-sidebar.tsx`
- Create: `admin/components/metric-card.tsx`
- Create: `admin/components/panel-card.tsx`
- Create: `admin/netlify/functions/health.ts`
- Create: `supabase/migrations/001_initial_schema.sql`
- Create: `supabase/migrations/002_leaderboard_and_analytics.sql`
- Create: `supabase/queries/leaderboards.sql`
- Create: `supabase/queries/analytics.sql`
- Create: `supabase/seed/pilot_seed.sql`

---

### Task 1: Lock design tokens and component inventory

**Files:**
- Create: `docs/implementation-plan.md`
- Create: `app/lib/core/theme/design_tokens.dart`
- Create: `app/lib/core/theme/theme_extensions.dart`
- Create: `app/lib/core/theme/app_theme.dart`
- Create: `admin/lib/design-tokens.ts`
- Create: `admin/app/globals.css`

- [ ] **Step 1: Define the token groups from the approved design architecture**
- [ ] **Step 2: Encode the light Neo-Medical Academy theme as the default token set**
- [ ] **Step 3: Reserve the dark cyber-brutalist variant as a secondary token set, without blocking MVP**
- [ ] **Step 4: Standardize shared primitives: cards, buttons, chips, progress bars, app bars, sidebar panels**
- [ ] **Step 5: Validate that participant and admin shells consume the same abstract token model**

### Task 2: Scaffold Flutter participant shell

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/lib/main.dart`
- Create: `app/lib/core/di/get_it.dart`
- Create: `app/lib/core/di/init_core.dart`
- Create: `app/lib/core/ui/arena_app.dart`
- Create: `app/lib/core/routing/app_router.dart`
- Create: `app/lib/core/routing/guest_router.dart`
- Create: `app/lib/core/routing/user_router.dart`
- Create: `app/lib/core/infra/event_bus.dart`
- Create: `app/lib/core/infra/device_identity_service.dart`
- Create: `app/lib/core/infra/auth_state_manager.dart`
- Create: `app/lib/core/infra/overlay_manager.dart`
- Create: `app/lib/core/infra/repository_mixin.dart`
- Create: `app/lib/core/ui/data_page.dart`
- Create: `app/lib/core/ui/operation_runner_state.dart`
- Create: `app/lib/core/ui/widgets/arena_scaffold.dart`
- Create: `app/lib/core/ui/widgets/arena_button.dart`
- Create: `app/lib/core/ui/widgets/arena_card.dart`
- Create: `app/lib/core/ui/widgets/arena_chip.dart`
- Create: `app/lib/core/ui/widgets/arena_bottom_nav.dart`
- Create: `app/lib/core/ui/widgets/quiz_progress_bar.dart`
- Create: `app/lib/features/profile/screens/quick_join_page.dart`
- Create: `app/lib/features/profile/screens/profile_page.dart`
- Create: `app/lib/features/quiz/screens/home_page.dart`
- Create: `app/lib/features/quiz/screens/quiz_detail_page.dart`
- Create: `app/lib/features/session/screens/session_join_page.dart`
- Create: `app/lib/features/quiz/screens/quiz_runner_page.dart`
- Create: `app/lib/features/quiz/screens/quiz_result_page.dart`
- Create: `app/lib/features/leaderboard/screens/world_rank_page.dart`

- [ ] **Step 1: Create a compile-ready Flutter app shell with the agreed folder structure**
- [ ] **Step 2: Add the theme layer and branded reusable widgets before screen assembly**
- [ ] **Step 3: Add guest and user routing shells matching quick join and logged-in flows**
- [ ] **Step 4: Add placeholder but styled participant screens for the pilot inventory**
- [ ] **Step 5: Run Flutter analysis or an equivalent compile check**

### Task 3: Scaffold Next.js admin shell

**Files:**
- Create: `admin/package.json`
- Create: `admin/tsconfig.json`
- Create: `admin/next.config.ts`
- Create: `admin/app/layout.tsx`
- Create: `admin/app/page.tsx`
- Create: `admin/app/dashboard/page.tsx`
- Create: `admin/app/quiz-bank/page.tsx`
- Create: `admin/app/sessions/page.tsx`
- Create: `admin/app/reports/page.tsx`
- Create: `admin/app/intelligence/page.tsx`
- Create: `admin/components/admin-shell.tsx`
- Create: `admin/components/admin-sidebar.tsx`
- Create: `admin/components/metric-card.tsx`
- Create: `admin/components/panel-card.tsx`
- Create: `admin/netlify/functions/health.ts`

- [ ] **Step 1: Create a minimal compile-ready Next.js admin workspace**
- [ ] **Step 2: Apply the shared design tokens and sidebar shell**
- [ ] **Step 3: Add the dashboard, quiz bank, sessions, reports, and intelligence pages**
- [ ] **Step 4: Add a simple Netlify Function health endpoint to establish the functions surface**
- [ ] **Step 5: Run a TypeScript or Next.js validation command**

### Task 4: Add Supabase schema and reporting queries

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`
- Create: `supabase/migrations/002_leaderboard_and_analytics.sql`
- Create: `supabase/queries/leaderboards.sql`
- Create: `supabase/queries/analytics.sql`
- Create: `supabase/seed/pilot_seed.sql`

- [ ] **Step 1: Create the base tables for users, devices, quizzes, questions, sessions, attempts, and answers**
- [ ] **Step 2: Add ranked-attempt uniqueness and analytics indexes**
- [ ] **Step 3: Add leaderboard views or functions for all-time and monthly rank plus self-rank**
- [ ] **Step 4: Add analytics queries for knowledge gaps, facility performance, and treatment perception signals**
- [ ] **Step 5: Add pilot seed data shaped around mixed-use sessions and self-paced play**

### Task 5: Verify the foundations

**Files:**
- Modify: `docs/implementation-plan.md`
- Verify: `app/`
- Verify: `admin/`
- Verify: `supabase/`

- [ ] **Step 1: Confirm the file structure matches the approved architecture**
- [ ] **Step 2: Run the narrowest available checks for Flutter, Next.js, and SQL file presence**
- [ ] **Step 3: Read the outputs and record any blockers explicitly**
- [ ] **Step 4: Preserve scope and stop before business logic implementation beyond the agreed foundations**

