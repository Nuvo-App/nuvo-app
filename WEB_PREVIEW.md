# Nuvo – Web Preview

Browser-based UI preview for Nuvo. Designed for GitHub Codespaces, Windows library computers, or any environment without Android Studio, Xcode, or an emulator.

---

## Quick start

```bash
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Then open the **Ports** tab in Codespaces (or your browser IDE) and forward port **8080**. Click the forwarded URL to open the preview.

---

## Build

```bash
flutter build web
```

Output is in `build/web/`. Serve with any static file server.

---

## In GitHub Codespaces

1. Open this repo in a Codespace.
2. In the terminal, run:
   ```bash
   flutter pub get
   flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
   ```
3. Codespaces will auto-detect port 8080. Click **Open in Browser**.
4. The app opens centered in a 430 px phone column.

---

## What works in the browser

| Screen | Web preview |
|---|---|
| Splash / Auth | ✅ |
| Onboarding | ✅ |
| Arena | ✅ |
| Race Detail | ✅ |
| Create Race | ✅ |
| Join Race | ✅ |
| Submit Proof (manual) | ✅ |
| Invite Crew | ✅ |
| Crew / Pass | ✅ |
| Compete | ✅ |
| Profile / Edit Profile | ✅ |
| AI Motion Proof | ⚠️ Placeholder (see below) |

---

## AI Motion Proof on web

Camera and MLKit are mobile-only and cannot run in a browser. On web, the AI Motion Proof screen shows a placeholder instead of crashing:

> **"AI verification runs on the mobile app"**
> Use the Nuvo mobile app to record verified reps. You can still preview the rest of the proof UI here.

The placeholder has two actions: **Back to proof** and **Log manually**.

Mobile behavior is completely unchanged — the camera and pose detection code is not affected.

---

## Desktop browser layout

On screens wider than 600 px the app renders inside a 430 px phone-width column, centered on a soft background. This prevents the UI from stretching into a tablet/website layout.

On actual mobile-sized viewports (≤ 600 px) the app fills the screen normally.

---

## Limitations

- **AI Motion Proof camera** — Not available in browser. Use the mobile app for camera/AI rep verification.
- **CORS** — The Nuvo API uses Cloudflare Workers. If you see network errors in the browser console, the API endpoint may need CORS headers configured for the preview origin.
- **Google Sign-In on web** — Requires additional setup (a web client ID in `index.html`). Email-based auth works without extra setup.
- **Secure storage** — On web, `flutter_secure_storage` uses `localStorage`. Tokens are cleared on logout. Do not use shared computers for real accounts.
- **Web preview is for UI work only.** Use a physical device or simulator for final camera/AI testing.

---

## VS Code task

A `.vscode/launch.json` task is included. In VS Code, press **F5** or select **Run > Start Debugging** and choose **"Nuvo – Web Preview"**.
