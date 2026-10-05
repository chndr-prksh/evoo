# Evoo for Android (preview)

A voice keyboard: tap the mic, speak, tap again — the text goes in at the cursor, in any app. Speech recognition
runs on the phone (NVIDIA Parakeet TDT 0.6B v3 through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)); the
only network use is the one-time model download (≈670 MB, SHA-256 checked).

**Status: preview.** It builds and its rules pass the Mac app's test cases, but it has not been run on a real
phone yet. English only; no AI polish yet.

## Install

1. On the phone, download `Evoo-android.apk` from the
   [android-preview release](https://github.com/chndr-prksh/evoo/releases/tag/android-preview) and open it
   (Android asks to allow installs from your browser).
2. Open Evoo and follow the three steps: microphone, speech model, keyboard.
3. In any app, switch to the Evoo keyboard (the 🌐 / keyboard icon) and tap the mic.

Preview builds are signed with a temporary key: uninstall the old preview before installing a new one.
Needs Android 8+ on a 64-bit ARM phone, and realistically 6 GB of memory or more (the model uses ~700 MB).

## Layout

- `core/` — Evoo's rules in plain Kotlin: a port of the Mac app's `DictationRules` and `TextCleaner`. The test
  runs the Mac app's own cases (`src/test/resources/rules.tsv`, exported by `scripts/export-rule-cases.py`), so
  both apps correct speech the same way.
- `app/` — the keyboard (`EvooKeyboardService`), setup screen, recorder, speech engine and model download.

## Build

CI does it (`.github/workflows/android.yml`). Locally, with the Android SDK and Gradle 8.10+:

```bash
curl -fsSL -o app/libs/sherpa-onnx.aar https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-1.13.8.aar
gradle :core:test :app:assembleRelease
```
