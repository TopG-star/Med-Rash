# MedRash Developer Environment

## Purpose
This guide installs local tools required for full MedRash runtime validation and database migration workflows.

## Required Tools
- Flutter SDK
- Supabase CLI
- Node.js and npm (already present)

## Automated Setup (Windows)
Run PowerShell as Administrator from repository root and execute:

```powershell
.\scripts\setup-dev-tools.ps1 -All
```

If you only need one tool:

```powershell
.\scripts\setup-dev-tools.ps1 -InstallFlutter
.\scripts\setup-dev-tools.ps1 -InstallSupabase
```

If you do not have Administrator access, install Supabase CLI in user scope:

```powershell
.\scripts\setup-dev-tools.ps1 -InstallSupabase -UserScope
```

If you do not have Administrator access, install Flutter in user scope:

```powershell
.\scripts\setup-dev-tools.ps1 -InstallFlutter -UserScope
```

## What the script does
- installs Flutter through Chocolatey (admin mode) or official user-scope SDK download
- downloads latest Supabase CLI Windows binary from GitHub
- places supabase.exe in C:\tools\supabase (or user-local path when -UserScope is used)
- appends install path to machine PATH (or user PATH with -UserScope)

## Post-install checks
Open a fresh terminal and run:

```powershell
flutter --version
supabase --version
node --version
npm --version
```

If PATH has not refreshed yet in your current shell, verify Supabase directly:

```powershell
& "$env:LOCALAPPDATA\medrash\supabase\supabase.exe" --version
```

If PATH has not refreshed yet in your current shell, verify Flutter directly:

```powershell
& "$env:LOCALAPPDATA\medrash\flutter\bin\flutter.bat" --version
```

## Suggested project checks after setup
### Full repeatable verification
From repository root:

```powershell
.\scripts\verify.ps1
```

Supabase verification modes:

```powershell
# Default: code checks are strict, local Supabase runtime checks are optional (SKIP on failure)
.\scripts\verify.ps1 -SupabaseMode auto

# Strict local mode: fail if local Supabase start/reset fails
.\scripts\verify.ps1 -SupabaseMode local

# Hosted mode: skip local Docker/Supabase runtime and validate hosted env vars instead
.\scripts\verify.ps1 -SupabaseMode hosted
```

The script runs checks in this order:
- flutter version
- dart version
- flutter pub get
- flutter analyze
- flutter test

Supabase checks vary by mode:
- `auto`: supabase version + docker version + local start/reset are optional and reported as `SKIP` if unstable
- `local`: supabase version + docker version + local start/reset are required and fail verification on error
- `hosted`: local supabase/docker checks are skipped; requires `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`, then runs hosted connectivity and required-schema smoke checks

## Pilot readiness definition
- Must pass: `.\scripts\verify.ps1 -SupabaseMode hosted`
- Must pass: Netlify deploy preview checks
- Optional: `.\scripts\verify.ps1 -SupabaseMode local` (developer convenience)

### Participant app
```powershell
Set-Location .\app
flutter pub get
flutter analyze
```

### Admin app
```powershell
Set-Location .\admin
npm ci
npm run lint
npm run typecheck
```

### Supabase SQL
```powershell
Set-Location ..
supabase init
supabase db reset
```

Docker Desktop is required for local Supabase commands such as db reset.

## Privileged Gate Environment Variables
Set these for Netlify functions (admin project):
- MEDRASH_GATE_API_KEY: shared gate secret expected in x-medrash-gate-key header
- SUPABASE_URL: project URL
- SUPABASE_SERVICE_ROLE_KEY: service-role key (server-only)

Set these for Flutter app startup (for gate calls):
- MEDRASH_FUNCTIONS_BASE_URL
- MEDRASH_GATE_API_KEY

## Notes
- If company policy blocks machine-level PATH writes, add C:\tools\supabase manually to your user PATH.
- User-scope Flutter installation is supported through the setup script.
- If Flutter is not in PATH, verify can still discover it from common user-scope install locations under LOCALAPPDATA.

