# Contributing

## Repository Model
This repository is a single monorepo and should contain:
- app/
- admin/
- supabase/
- scripts/
- docs/

Do not reintroduce nested git repositories inside the monorepo.

## Branch Naming (Required)
Use one of these branch prefixes:
- feat/<short-scope>
- fix/<short-scope>
- chore/<short-scope>

Examples:
- feat/session-qr-join
- fix/ranked-unique-guard
- chore/verify-hosted-mode

## Commit Messages (Required)
Use Conventional Commits:
- feat(scope): ...
- fix(scope): ...
- chore(scope): ...
- docs(scope): ...
- test(scope): ...

Scope examples:
- app
- admin
- supabase
- verify
- gate
- session
- quiz
- leaderboard

## Pull Request Discipline (Required)
Every PR must include:
- verify.ps1 output and mode used
- summary of what changed
- env var changes (if any)

If there are no env var changes, write: "No env var changes".
