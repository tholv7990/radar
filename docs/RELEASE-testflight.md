# Radar → iPhone via TestFlight (from Windows, no Mac)

You're on Windows and iOS builds require macOS, so we build in the cloud with **Codemagic**
(it runs the Mac, signs, and uploads to TestFlight). This is a one-time setup; after it,
every push to GitHub can produce a new TestFlight build.

Repo-side prep is already done: bundle id `com.tholv7990.radar`, home-screen name "Radar",
and [`codemagic.yaml`](../codemagic.yaml). You do the account steps below.

---

## 0. What it costs / needs
- **Apple Developer Program — $99/year** (required for TestFlight). Enroll first; activation takes ~24–48h.
- Codemagic **free tier** (500 macOS build-minutes/month) — plenty for a personal app.
- An **iPhone** with the free **TestFlight** app installed (from the App Store).

---

## 1. Enroll in the Apple Developer Program
1. Go to <https://developer.apple.com/programs/enroll/> and sign in with your Apple ID.
2. Enroll as an **Individual** ($99/yr). Wait for the confirmation email (can be a day or two).

## 2. Create the app record in App Store Connect
1. Go to <https://appstoreconnect.apple.com> → **My Apps** → **＋** → **New App**.
2. Platform **iOS**, Name **Radar**, primary language, and **Bundle ID**:
   - If `com.tholv7990.radar` isn't in the dropdown, first register it at
     <https://developer.apple.com/account/resources/identifiers/list> → **＋** → **App IDs** →
     **App**, description "Radar", Bundle ID (explicit) `com.tholv7990.radar`.
3. SKU: anything (e.g. `radar`).
4. After the app is created, open **App Information** and copy the **Apple ID** (a ~10-digit number).
   → Put it in `codemagic.yaml` as `APP_STORE_APPLE_ID` (replace the `0000000000` placeholder), commit, push.

## 3. Create an App Store Connect API key (lets Codemagic sign + upload)
1. App Store Connect → **Users and Access** → **Integrations** tab → **App Store Connect API**.
2. **Generate API Key** (or the ＋). Access role: **App Manager**. Name it e.g. `codemagic`.
3. Download the **`.p8`** file (you can only download it once) and note the **Issuer ID** and **Key ID**.

## 4. Set up Codemagic
1. Sign up at <https://codemagic.io> with your GitHub account.
2. **Add application** → authorize GitHub → pick the **`tholv7990/radar`** repo.
3. Add the App Store Connect integration: Codemagic → **Teams** (or the app's settings) →
   **Integrations** → **App Store Connect** → **Connect**, and upload the `.p8` +
   paste the Issuer ID and Key ID. **Name this integration `codemagic`** (must match
   `integrations.app_store_connect` in `codemagic.yaml`).
4. Codemagic auto-detects `codemagic.yaml` in the repo root. Select the **`ios-testflight`** workflow.

## 5. Build + ship
1. In Codemagic, click **Start new build** → workflow **ios-testflight**.
   - Codemagic will (via the API key) auto-create the signing certificate + provisioning
     profile for `com.tholv7990.radar`, build the `.ipa`, and upload it to TestFlight.
2. First build takes ~10–20 min. If it fails, read the log — the usual first-iOS-build fixes
   are a missing icon or a CocoaPods version bump; tell me the error and I'll patch the repo.

## 6. Install on your iPhone
1. In App Store Connect → your app → **TestFlight** tab: once the build finishes **processing**
   (a few min after upload), add yourself under **Internal Testing** (create a group, add your
   Apple ID email). **Internal testers get builds immediately — no Apple review.**
2. On the iPhone, open **TestFlight**, accept the invite (email), and **Install Radar**.

Done — Radar is on your phone. Tap a repo to trigger a live deep-dive (the Edge Function is
already deployed and working).

---

## Notes
- **Nothing secret ships in the app.** Only the public Supabase anon key is compiled in (RLS
  protects your data). The shopaikey LLM key lives server-side in the Edge Function, never in the app.
- **Builds expire after 90 days.** To refresh, start a new Codemagic build (bump happens automatically).
- **New versions:** bump `version:` in `radar_app/pubspec.yaml`, push, start a build.
- **Android (free, today, no Mac):** `cd radar_app && flutter build apk --release` →
  `build/app/outputs/flutter-apk/app-release.apk`, sideload to any Android phone.
