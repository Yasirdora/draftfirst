# eDraft — App Store Readiness Audit (macOS first)

**Verdict: NO — eDraft would not pass review today. One item BLOCKS SUBMISSION (no hosted privacy policy / support URL, and a literal `[SUPPORT EMAIL]` placeholder), and five SHOULD FIX items stand between here and a clean upload. Nothing found is architecturally wrong — every gap is a known, bounded task. With the checklist at the end executed, this app is a credible yes.**

Audit measured at HEAD `df9e670` on branch `rename/edraft`, 2026-09-22. Read-only: no file outside this document changed. Every finding cites its evidence; anything that could not be measured from the repo is labelled *unverified*. iOS is covered only where it shares a setting with macOS.

---

## BLOCKS SUBMISSION

### B1. No hosted Privacy Policy URL or Support URL — and a live `[SUPPORT EMAIL]` placeholder
- **Guideline:** 5.1.1 (privacy policy), App Store Connect requirements (Support URL and Privacy Policy URL are mandatory fields).
- **Evidence:** `docs/privacy-policy.html:48` contains the literal `[SUPPORT EMAIL]` twice (`mailto:` href and link text); the same placeholder is in `docs/privacy-policy.txt:35`. The policy is **not hosted anywhere**: `src/routes/` has no `/privacy` route (only `+page.svelte` and `screenplay/`); the site's "Privacy" link (`src/routes/+page.svelte:29,145`) is an in-page marketing anchor, not the policy; `static/` holds no policy file; `wrangler.toml` deploys the site but maps no policy route; no GitHub Pages config exists. The only public support surface is GitHub Issues, linked from the landing page.
- **Remedy:** (1) Choose the support contact address and replace both placeholders. (2) Host the policy at a stable public URL (e.g. `edraft.xyz/privacy` via the existing Cloudflare Pages deploy, or any permanent host). (3) Create a Support URL (a simple page with contact + FAQ, or the GitHub Issues page while volume is low). (4) Enter both URLs in App Store Connect. The policy's content itself is accurate — the iCloud section matches the implementation exactly — so this is plumbing, not rewriting.

---

## SHOULD FIX

### S1. Dead "eDraft Help" menu item
- **Guideline:** 2.1 (app completeness — a menu item that visibly does nothing is a rejection trigger reviewers do use).
- **Evidence:** `apple/macOS/MainMenu.swift:34` registers `item("eDraft Help", #selector(NSApplication.showHelp(_:)), "?")`. No help book exists: `CFBundleHelpBookName` / `CFBundleHelpBookFolder` appear nowhere in `apple/`, so `showHelp` is a silent no-op.
- **Remedy:** Cheapest correct fix: remove the menu item. Better fix: ship a small help book or point the item at the hosted support page via `NSWorkspace.open`. Decide at submission time; do not ship the dead item.

### S2. Version numbers still read 0.1.0
- **Guideline:** 2.3 (accurate metadata — store listing, binary version and screenshots must agree).
- **Evidence:** `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1` for both targets, both configurations — iOS at `apple/eDraft.xcodeproj/project.pbxproj:477,485,501,509`, macOS at `:570,577,599,606`. `DEVELOPMENT_TEAM = Z77253BSS4` is set on all four app configurations and confirmed correct.
- **Remedy:** Set `MARKETING_VERSION = 1.0` (both targets if iOS follows soon; macOS alone if not). Keep `CURRENT_PROJECT_VERSION` monotonically increasing for every upload of each bundle ID.

### S3. `ITSAppUsesNonExemptEncryption` missing from both plists
- **Guideline:** 2.5 / export compliance (App Store Connect will ask on every upload if the plist doesn't answer).
- **Evidence:** The key is absent from `apple/macOS/Info.plist` and `apple/eDraft/Resources/Info.plist`. Code audit confirms the app uses **no encryption**: no CryptoKit, CommonCrypto, or SecKey anywhere; the only crypto-adjacent code rejects encrypted ZIP members on import (`Zip.swift:197`) and uses the Compression framework for decompression only (`Zip.swift:237`).
- **Remedy:** Add `ITSAppUsesNonExemptEncryption = NO` to both Info.plists. Then export compliance is answered once, in the plist, not per upload.

### S4. Omitted-scene bodies leak into Print and PDF export
- **Guideline:** 2.1 (wrong output from a shipped feature) — and it violates the app's own contract, RFC-DRAFT-PRODUCTION §7.3 ("an omitted scene does not print").
- **Evidence:** Print (`ScreenplayDocument.printDocument` → `ScreenplayPageRenderer.runPrint`, `apple/macOS/ScreenplayDocument.swift:92-94`) and PDF export (`ScreenplayExportWriter.data`, `:160`) both paginate `screenplay.engineModel` (`EDraftCore/ScreenplayExporter.swift:106-108`), a projection that carries **all** elements including omitted bodies and drops the omission metadata (`EDraftCore/ScreenplayModels.swift:258-272`). The only omission-aware filter, `Omissions.paginable` (`Omissions.swift:237-254`), is used by the stats path and tests — never by print or export. Fountain and plain-text exports include the bodies too; iOS has the same leak (`apple/eDraft/Views/EditorChrome.swift:389,598`). The deferral is documented in `docs/MACOS-EXECUTION.md` §9 (lines 851-856).
- **Remedy:** Route print/PDF/Fountain/plain-text export through the omission-aware element list (the pattern already exists: `Omissions.paginable`). The OMITTED card itself must still print — only the cut body is excluded. Needs a seam into `ScreenplayPageRenderer`'s callers; own it as its own lock before submission.

### S5. No documented release process
- **Guideline:** process risk, not a guideline — but submission day is the wrong time to discover it.
- **Evidence:** `RELEASING.md` documents only the npm package (`@edraft/core`). For the app: both targets use `CODE_SIGN_STYLE = Automatic` with no pinned identity or profile; `ENABLE_HARDENED_RUNTIME = YES` is correctly set on macOS (required for notarisation). What a Release archive needs that Debug doesn't: an **Apple Distribution** identity plus a Mac App Store provisioning profile for `xyz.edraft.mac` carrying the iCloud + sandbox entitlements (or, for direct distribution, Developer ID Application + `xcrun notarytool` + stapling). Whether team `Z77253BSS4` already has these profiles is *unverified* — it can only be checked in the Apple Developer account / App Store Connect.
- **Remedy:** Before submission: confirm the bundle IDs and profiles exist in the developer account, do one trial `xcodebuild archive` for the macOS scheme, and write the archive → validate → upload flow into `RELEASING.md`.

### S6. Store-facing material does not exist yet
- **Guideline:** 2.3 (accurate metadata).
- **Evidence:** No App Store description, subtitle, keyword set or promotional text is drafted anywhere in the repo. No screenshot exists at an accepted App Store size: current captures are 2186×1000 (`docs/images/macos-window-dark-page-2026-09-08.png`), 984×1368 (root `screenshot.png`) and web-OG images — none at 1280×800 / 1440×900 / 2560×1600 / 2880×1800. The web copy (`src/routes/+page.svelte`) is reusable raw material but describes the browser editor, not the native app.
- **Remedy:** Draft the listing (description, 100-char keyword field, 170-char promotional text, subtitle) with the native-app facts: plain-text screenplays you own, faithful Final Draft (.fdx) import/export with notes, no accounts, no subscription, sync via the user's iCloud. Shoot macOS screenshots at an accepted size from a current build. Note for consistency: the README positions eDraft as a browser engine with an app — phrase store claims as app capabilities.

---

## POLISH

### P1. Minimum system version is macOS 26
`LSMinimumSystemVersion = $(MACOSX_DEPLOYMENT_TARGET)` → **26.0** (`project.pbxproj:576,605`). If deliberate (Tahoe-only features), fine; know that it excludes every pre-26 Mac and shrinks the launch audience. A one-line change if reconsidered; a real test matrix if lowered.

### P2. Document-type asymmetry between platforms
macOS declares `xyz.edraft.screenplay` (`.draft`, Owner/Editor), `public.plain-text`, and imports `com.finaldraft.fdx` (`.fdx`) — all consistent between `apple/macOS/Info.plist` (lines 51-146) and the project. iOS additionally imports `org.fountain-lang.fountain` (`.fountain`) and a PDF viewer type; macOS has neither. If macOS should open `.fountain` files directly, add the import; otherwise the asymmetry is acceptable.

### P3. Stale `#if EDITOR_PREVIEW` code in the iOS surface
`apple/EDraftUIKitSurface/Sources/EDraftUIKitSurface/ScriptTextView.swift:853-1162` sits inside `#if EDITOR_PREVIEW`, a flag no build configuration defines. Dead code, never compiled; remove when convenient.

### P4. iOS camera usage description
`NSCameraUsageDescription` is declared (`apple/eDraft/Resources/Info.plist:90`) though the scan feature uses VisionKit's document camera, which manages its own permission UI. Harmless over-declaration; iOS-only; revisit at iOS submission.

---

## Per-guideline record

**2.1 App Completeness.** First-five-minutes walkthrough measured on a build proven current (binary timestamp checked against build time): launch lands on a finished library window — recents grid/list with search, a toolbar "+" menu (New Screenplay / Open…), a designed empty state with guidance (`LaunchWindow.swift:280-299`), and a complete Settings window (⌘,). New document → type → save into the iCloud eDraft folder works (previously verified interactively). No placeholder UI, no reachable `fatalError`/`#warning`, no "coming soon". The only Debug/Release divergence is an experimental spread editor gated behind an environment variable, hard-off in Release — unreachable by a reviewer. **Two defects:** the dead Help item (S1) and the print/PDF omission leak (S4).

**2.3 Accurate Metadata.** Version is 0.1.0 (S2); no store copy exists yet (S6). The feature claims intended for the listing are all verifiable in code: plain-text/Fountain editing, faithful .fdx round-trip including notes, .draft container, iCloud sync (mechanism verified, see 5.1), no accounts.

**2.4 Hardware Compatibility.** macOS-only target reviewed; no hardware-specific requirements beyond the OS floor (P1). No external-hardware dependencies.

**2.5 Software Requirements.** Sandboxed (`com.apple.security.app-sandbox = true`, `apple/macOS/eDraft.entitlements:19`) with **no** `sandbox-temporary-exception` keys anywhere. Entitlements asked-vs-used cross-checked: sandbox ✓, user-selected file access ✓ (document app), print ✓ (`NSPrintOperation` used), iCloud container `iCloud.xyz.edraft` + CloudDocuments ✓ (used at `ScreenplayDocument.swift:52`, `EDraftMacApp.swift:68`). Nothing requested-but-unused; nothing used-but-unrequested. No network entitlement and no network code — no `URLSession`/`NWConnection`/`WKWebView` anywhere in `apple/`. No private APIs: the only swizzle is in a test target on a public method and does not ship. No third-party SDKs; all Swift packages are local-path dependencies. `ITSAppUsesNonExemptEncryption` absent (S3). Hardened runtime on for notarisation.

**3.1 Business.** No StoreKit, no IAP, no subscriptions, no accounts, no sign-in anywhere in the codebase. Nothing engages 3.1. The business model question (paid up front vs free) is a store decision, not a code one.

**5.1 Privacy.** `PrivacyInfo.xcprivacy` exists, is bundled in **both** app targets, and is accurate: `NSPrivacyTracking = false`, empty collected-data array, one required-reason entry — UserDefaults (CA92.1), matching actual usage (page format, paper, layout prefs). No analytics, telemetry, or crash-reporting SDKs. iCloud sync is OS-mediated through the public-document-scope ubiquity container `iCloud.xyz.edraft` (`NSUbiquitousContainers`, both plists); no custom sync server, no CloudKit. The privacy policy's content matches this implementation precisely — but it is unhosted and carries the `[SUPPORT EMAIL]` placeholder (B1). The one outbound affordance in the UI is a `mailto:` feedback link. Age rating exposure: no UGC, no web content; expected 4+.

---

## Answers App Store Connect will ask

- **Export compliance:** No encryption. Answered in-plist once S3 lands (`ITSAppUsesNonExemptEncryption = NO`).
- **Privacy nutrition label:** No data collected; no tracking. Matches `PrivacyInfo.xcprivacy` and the code.
- **Content rights / age rating:** 4+, all "no" answers; original document editor, no UGC.
- **Support URL / Privacy Policy URL:** do not exist yet — B1.
- **Version / build:** 1.0 / next integer — S2.
- **Localizations:** English (U.S.) only — `developmentRegion = en`, no `.strings`/`.xcstrings` files.
- **Sign-in required:** No.

## Named suspects, confirmed or refuted

| Suspect | Verdict |
|---|---|
| `[SUPPORT EMAIL]` placeholder in `docs/privacy-policy.html` | **Confirmed** (line 48; also `.txt:35`) — B1 |
| Support/privacy URLs don't exist | **Confirmed** — no host, no route — B1 |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | **Confirmed** 0.1.0 / 1, both targets — S2 |
| `ITSAppUsesNonExemptEncryption` absent | **Confirmed** absent; crypto audit clean — S3 |
| `showHelp` dead Help item | **Confirmed** — no help book registered — S1 |
| Entitlements asked-vs-used | **Refuted as a problem** — exact match, sandbox clean, no exceptions |
| `.fountain` / `.fdx` / `.draft` document types | **Refuted as a problem** on macOS — declared and consistent; iOS asymmetry is P2 |
| Release signing / notarisation readiness | **Partially confirmed** — hardened runtime on, automatic signing; profiles and process undoc­umented and account-side state *unverified* — S5 |
| First-five-minutes walkthrough | **Refuted as a problem** — finished launch experience measured on a current build |

## Submission checklist (execution order)

1. **B1** — Choose the support contact; replace both `[SUPPORT EMAIL]` placeholders; host the policy at a stable URL; create the Support URL; enter both in App Store Connect.
2. **S1** — Remove or genuinely implement "eDraft Help".
3. **S4** — Exclude omitted-scene bodies from Print/PDF/text export (own lock; card still prints).
4. **S3** — Add `ITSAppUsesNonExemptEncryption = NO` to both plists.
5. **S2** — Set `MARKETING_VERSION = 1.0`.
6. **S5** — Verify `xyz.edraft.mac` registration, distribution identity and App Store profile in the developer account (team `Z77253BSS4`); trial archive; document the flow in `RELEASING.md`.
7. **S6** — Draft listing copy (description, subtitle, keywords, promotional text); shoot macOS screenshots at 1280×800 or 2560×1600 from a current build; prepare the 1024×1024 icon from the existing artwork.
8. Final smoke: fresh Mac user story — launch → new → type → save → open an .fdx → print to PDF → quit.
9. Archive → validate → upload → fill App Store Connect (privacy label "no data collected", age rating 4+, English only) → submit.

*Unchecked, by design: App Store Connect account-side state (bundle IDs, profiles, agreements) cannot be verified from the repo; the interactive walkthrough was verified against a build proven current at audit time, not re-driven through UI scripting (no Accessibility permission in this session).*
