# Evoo for Windows (preview)

Hold **Ctrl + Win**, speak, let go — the text is typed at the cursor in any app. Speech recognition runs on the PC
(NVIDIA Parakeet TDT 0.6B v3 through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)); the only network use is
the one-time model download (about 670 MB, SHA-256 checked).

**What it does**

- **Dictate:** hold Ctrl + Win, speak, let go. Self-corrections, fillers and stutters are cleaned up by the same
  rules as the Mac app.
- **Voice commands:** "new tab", "copy that", "volume thirty", "mute", "open Chrome", "switch to Notepad", "search
  Google for flights to Delhi", "snap this to the left" — and several in one breath: "close the tab and switch to
  Chrome". Add Shift (Ctrl + Win + Shift) so nothing is ever typed.
- **AI polish (optional):** Qwen3 0.6B run by a bundled llama.cpp that listens only on this PC. A one-time 397 MB
  download; if it takes more than 4 seconds the text goes in without it.

**Status: preview.** It builds on GitHub's Windows servers, its rules match the Mac app on the Mac app's own test
cases, and an end-to-end run there turns spoken audio into corrected, polished text. It has **not** been used by a
person on a real Windows PC yet: the hold-to-talk keys, the microphone, pasting into other apps and carrying out
commands are checked only as far as automated tests can. English only.

## Try it

1. Download [Evoo-windows.zip](https://github.com/chndr-prksh/evoo/releases/download/windows/Evoo-windows.zip)
   and unzip it.
2. Run `Evoo\Evoo.exe`. Windows SmartScreen warns about apps it doesn't know: **More info → Run anyway**
   (the build isn't code-signed).
3. Click **Download** for the speech model, then hold Ctrl + Win in any text box and speak. Esc cancels.

Needs 64-bit Windows 10 or 11. Evoo sits in the notification area (the ^ near the clock); right-click it to quit.

## Layout

- `Evoo.Core` — the dictation rules, voice-command parsing, command chains and the polish prompt, in plain C#. `Evoo.Core.Tests` runs the
  Mac app's own cases (`rules.tsv`, exported by `scripts/export-rule-cases.py`).
- `Evoo.Speech` — the speech model (download, verification, transcription) and the polish engine.
- `Evoo.Windows` — the app: keyboard hook, recorder, pill, paste, tray icon, setup window.
- `Evoo.E2E` — the end-to-end check CI runs: a Windows voice speaks, the model listens, the rules clean up.

## Build

```
dotnet test windows/Evoo.Core.Tests
dotnet publish windows/Evoo.Windows -c Release -o out/Evoo
```
