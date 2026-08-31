# Nuvo Web Preview in GitHub Codespaces

Work on Nuvo UI from any browser — no Android Studio, Xcode, Flutter, or emulator needed on your computer.

---

## Codespaces quick start (recommended for shared/library computers)

1. Open the GitHub repo page.
2. Click **Code**.
3. Click the **Codespaces** tab.
4. Click **Create codespace on main** (or the current branch).
5. Wait for setup to finish — Flutter installs automatically (takes 3–5 minutes on first run).
6. Open the **Terminal** panel inside the Codespace.
7. Run:
   ```bash
   ./scripts/run_web_preview.sh
   ```
8. When Codespaces shows a notification for port **8080**, click **Open in Browser**.
9. Nuvo opens as a mobile-sized app preview in your browser.

**Or use the VS Code task:** `Terminal → Run Task → Run Nuvo Web Preview`

---

## Local quick start (if Flutter is already installed)

```bash
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Then open `http://localhost:8080` in your browser.

---

## Important rules for shared/library computers

- **Do not** use `flutter run -d chrome` in Codespaces — it opens a desktop Chrome window, which doesn't exist in a cloud environment. Use `web-server` instead.
- Log out of Nuvo when done.
- Log out of GitHub and close the Codespace when done.
- Do not save passwords in the browser on a library or shared computer.
- Do not leave the Codespace running — it uses your GitHub free-tier hours.

---

## What works in the browser preview

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
| AI Motion Proof | ⚠️ Placeholder — mobile only (see below) |

---

## AI Motion Proof on web

Camera and ML Kit are mobile-only. On web, the AI Motion Proof screen shows a placeholder:

> **"AI verification runs on the mobile app"**
> Use the Nuvo mobile app to record verified reps. You can still preview the rest of the proof UI here.

Mobile behavior is completely unchanged.

---

## Desktop browser layout

On screens wider than 600 px the app renders inside a 430 px phone-width column, centered on a soft background. On actual mobile viewports (≤ 600 px) the app fills the screen normally.

---

## Troubleshooting

**Setup didn't finish / Flutter not found:**
```bash
flutter doctor -v
flutter pub get
```

**Port 8080 isn't showing:**
- Open the **Ports** tab at the bottom of the Codespace.
- Find port 8080 and click the globe icon to open it.

**Auth acts weird after opening in browser:**
- Clear browser site data for the Codespaces preview URL and log in again.
- This happens if an old encrypted token from a previous session is in storage — logging in fresh clears it.

**`flutter: command not found`:**
- The PATH wasn't set yet. Run:
  ```bash
  export PATH="$HOME/flutter/bin:$PATH"
  ./scripts/run_web_preview.sh
  ```

---

## Build (static output)

```bash
flutter build web
```

Output is in `build/web/`. Serve with any static file server.

---

## VS Code shortcuts

- **F5** or **Run > Start Debugging > Nuvo – Web Preview** — launches via `launch.json`
- **Terminal > Run Task > Run Nuvo Web Preview** — launches via `tasks.json`
