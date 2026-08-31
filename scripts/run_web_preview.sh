#!/usr/bin/env bash
# Run Nuvo as a Flutter web-server preview on port 8080.
# Use this in Codespaces (or any headless Linux) — do NOT use flutter run -d chrome.
set -e

export PATH="$HOME/flutter/bin:$PATH"

flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
