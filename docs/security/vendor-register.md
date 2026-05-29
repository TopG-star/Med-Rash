# MedRash Vendor & Sub-processor Register

> Slice B5 of [`security-hardening-plan.md`](../security-hardening-plan.md). Single source of truth for every vendor in MedRash's runtime, build, or data path.

**Last reviewed**: 2025-01 (initial draft).
**Owner**: Product.
**Review cadence**: quarterly + on any vendor change.

---

## Risk tiering

- **Critical** — direct access to user personal data or full outage if vendor fails.
- **High** — partial outage or degraded surface if vendor fails; no direct PII access.
- **Medium** — build/deploy pipeline dependency; outage delays releases but does not affect running pilot.
- **Low** — non-runtime, non-build dependency (developer convenience).

---

## Runtime data processors (sub-processors under GDPR Art. 28)

| Vendor | Service | Data processed | Risk | DPA on file | Status page | Support contact | Sub-processors | Renewal |
|---|---|---|---|---|---|---|---|---|
| **Supabase** | Postgres DB, Auth, Storage, Edge functions | Admin emails, hashed passwords/OTPs, participant device IDs, attempt records, session metadata, audit log | **Critical** | Auto-accepted via Supabase ToS (standard DPA) — verify exported PDF at https://supabase.com/legal/dpa | https://status.supabase.com | https://supabase.com/dashboard/support/new (Pro plan) | AWS (us-east, eu-west depending on project region) | Annual; auto-renew |
| **Netlify** | Hosting for `admin/` Next.js + Netlify functions; edge cache; deploy logs | HTTP request metadata, IPs, function logs (may include audit-relevant identifiers) | **Critical** | Netlify standard DPA — request via support if not on file: https://www.netlify.com/gdpr-ccpa/ | https://www.netlifystatus.com | https://www.netlify.com/support/ | AWS, Cloudflare (CDN for some plans) | Annual; auto-renew |
| **Cloudflare Turnstile** | Bot mitigation for `/device-token`, `/login`, `/recover` | IP, browser fingerprint signals at challenge time | **High** | Cloudflare DPA: https://www.cloudflare.com/cloudflare-customer-dpa/ | https://www.cloudflarestatus.com | Free tier; community support | None | Annual |

## Build & deploy dependencies

| Vendor | Service | Data processed | Risk | DPA on file | Status page | Support contact | Renewal |
|---|---|---|---|---|---|---|---|
| **GitHub** | Source code hosting, Actions CI, PR review | Source code, commit metadata, contributor emails, CI build logs | **High** | GitHub DPA: https://docs.github.com/en/site-policy/privacy-policies/global-privacy-practices (auto via ToS for Enterprise/Team; verify per account tier) | https://www.githubstatus.com | https://support.github.com | Annual |
| **npm registry (npmjs.com)** | Package downloads for `admin/` build | Public package metadata only | **Medium** | Covered under GitHub DPA (npm is a GitHub subsidiary) | https://status.npmjs.org | Via GitHub | n/a |
| **pub.dev** | Flutter package registry for `app/` build | Public package metadata only | **Medium** | Google standard terms | https://status.dart.dev (intermittent) | https://github.com/dart-lang/pub-dev/issues | n/a |
| **Flutter SDK (Google)** | Build toolchain for `app/` | Build telemetry (opt-out via `flutter --suppress-analytics`) | **Medium** | Google standard terms | https://status.dart.dev | https://github.com/flutter/flutter/issues | n/a |

## Boot-path third-party content

| Vendor | Service | Data processed | Risk | DPA on file | Notes |
|---|---|---|---|---|---|
| **Google Fonts** (admin only — confirm in `admin/src/app/layout.tsx`) | Font CSS + woff2 served from fonts.googleapis.com / fonts.gstatic.com | IP at fetch time | **High** | Google standard terms; consult ECJ ruling on Google Fonts IP transfer when serving EU users — recommendation: self-host fonts to remove this dependency (action item below) | Already loaded by Next.js `next/font` which by default self-hosts at build time — **VERIFY** in code. If self-hosted, downgrade to Low. |

## Developer-convenience (non-runtime)

| Vendor | Service | Risk | DPA on file |
|---|---|---|---|
| **VS Code + GitHub Copilot** | IDE + AI assist | **Low** | Per-developer agreement |

---

## Action items (open)

- [ ] **Verify Google Fonts is self-hosted** via `next/font` (default Next.js 15 behaviour). If any remote fetch remains, either self-host the woff2 or document as runtime processor and add to the top table. — *Owner: product, due before pilot launch.*
- [ ] **Export & file the Supabase DPA PDF** under `docs/security/dpa/supabase-dpa-YYYYMMDD.pdf` (gitignored or stored in private repo if it contains commercial terms).
- [ ] **Request Netlify DPA** via support portal if no countersigned copy on file; same storage convention.
- [ ] **Confirm GitHub account tier** (Free / Team / Enterprise) and capture the applicable DPA reference.
- [ ] **Quarterly review reminder**: add calendar event to re-read this file every 3 months and refresh `Last reviewed`.

## Standards mapping

- ISO 27001 §A.15 (supplier relationships)
- ISO 27002 §5.19–5.23 (information security in supplier relationships)
- NIST CSF GV.SC (supply chain risk management), ID.SC
- GDPR Art. 28 (processor), Art. 30 (records of processing), Art. 32 (security of processing)
