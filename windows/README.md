# Evoo for Windows (preview)

Hold **Ctrl + Win**, speak, let go — the text is typed at the cursor in any app. Speech recognition runs on the PC
(NVIDIA Parakeet TDT 0.6B v3 through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)); the only network use is
the one-time model download (about 670 MB, SHA-256 checked).

**Status: preview.** It builds on GitHub's Windows servers, its rules match the Mac app on the Mac
app's own test cases, and an end-to-end run there turns spoken audio into corrected text. It has **not** been used
by a person on a real Windows PC yet: the hold-to-talk key, the microphone, the floating pill and pasting into other
apps are checked only as far as an automated self-test can. English only; no AI polish or voice commands yet.

## Try it

1. Download [Evoo-windows.zip](https://github.com/chndr-prksh/evoo/releases/download/windows/Evoo-windows.zip)
   and unzip it.
2. Run `Evoo\Evoo.exe`. Windows SmartScreen warns about apps it doesn't know: **More info → Run anyway**
   (the build isn't code-signed).
3. Click **Download** for the speech model, then hold Ctrl + Win in any text box and speak. Esc cancels.

Needs 64-bit Windows 10 or 11. Evoo sits in the notification area (the ^ near the clock); right-click it to quit.

## Layout

- `Evoo.Core` — the dictation rules in plain C#, a port of the Mac app's `DictationRules`. `Evoo.Core.Tests` runs the
  Mac app's own cases (`rules.tsv`, exported by `scripts/export-rule-cases.py`).
- `Evoo.Speech` — the speech model: download, verification, transcription.
- `Evoo.Windows` — the app: keyboard hook, recorder, pill, paste, tray icon, setup window.
- `Evoo.E2E` — the end-to-end check CI runs: a Windows voice speaks, the model listens, the rules clean up.

## Build

```
dotnet test windows/Evoo.Core.Tests
dotnet publish windows/Evoo.Windows -c Release -o out/Evoo
```
