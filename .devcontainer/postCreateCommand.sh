#!/usr/bin/env bash
set -e

echo "=== Nuvo Flutter Web – Codespaces setup ==="

# ── System packages ────────────────────────────────────────────────────────────
sudo apt-get update -q
sudo apt-get install -y -q curl git unzip xz-utils zip libglu1-mesa

# ── Flutter ────────────────────────────────────────────────────────────────────
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Cloning Flutter stable (shallow)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
else
  echo "Flutter already present at $FLUTTER_DIR — skipping clone."
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# Persist PATH for all future terminals in this Codespace.
if ! grep -q 'flutter/bin' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.bashrc"
fi
if ! grep -q 'flutter/bin' "$HOME/.profile"; then
  echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.profile"
fi

# ── Flutter web ────────────────────────────────────────────────────────────────
flutter config --enable-web --no-analytics
flutter precache --web

# ── Project dependencies ───────────────────────────────────────────────────────
flutter pub get

# ── Diagnostics ───────────────────────────────────────────────────────────────
flutter doctor -v || true   # print but don't fail on missing Android/iOS tools

echo ""
echo "=== Setup complete ==="
echo "Run the web preview with:"
echo ""
echo "    ./scripts/run_web_preview.sh"
echo ""
echo "Or from VS Code: Terminal → Run Task → Run Nuvo Web Preview"
echo ""
echo "Then open the Ports tab and click the forwarded port 8080 URL."
