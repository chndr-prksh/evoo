# Evoo

**Open-source voice dictation for macOS that runs entirely on your Mac.**
Hold `fn`, speak, release — clean text appears at your cursor in any app.

- 100% local: speech recognition and text cleanup run on-device. No accounts, no cloud, no API keys.
- Understands what you *meant*: "let's meet tomorrow, no, day after tomorrow" → **"Let's meet day after tomorrow."**
- Works everywhere you can paste: Chrome, Slack, Gmail, Notion, VS Code, Cursor, Terminal, Office…
- English (Hindi/Hinglish are built but switched off for now — `Features.multilingual`). Pluggable speech engines.
- Speculative transcription: Evoo starts transcribing when you pause, so text is usually ready the instant fn goes up.
- Personal dictionary for names and jargon (Divya, Aarav, Kubernetes).
- Voice shortcuts: say "my email" (alone or mid-sentence) and get the full text you set up.
- Voice editing: "replace Tuesday with Wednesday", "delete the last sentence", "make that a list".
- History: search and copy your recent dictations (menu → History…), kept only on your Mac.
- Formats as you speak: "…buy tomorrow bread, eggs, milk" becomes a bulleted list; "first… second… third…"
  becomes numbered steps; "new line", "new paragraph", emails. Markdown in Notion/editors/browsers, • bullets
  elsewhere, and never a line break in Terminal (a pasted newline could run a command).
- Apache-2.0. Every model it uses is open-weight and free.

## Install

**One line** (Apple Silicon Mac, macOS 14+). Paste into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/chndr-prksh/evoo/main/install.sh | bash
```

It downloads the latest release, verifies its checksum, installs `/Applications/Evoo.app`, and opens it.

**Or download** `Evoo.zip` from [Releases](https://github.com/chndr-prksh/evoo/releases/latest), unzip, and drag
Evoo to Applications. Evoo isn't signed with a paid Apple Developer ID, so the first time macOS will say it
"could not verify" Evoo: open **System Settings › Privacy & Security** and click **Open Anyway** (once).

**Updates:** every change pushed to `main` is built and published automatically. Evoo checks every few hours;
when a new build is out, a dot appears by its menu bar icon — choose **Install Update** and it relaunches on the
new version, keeping your settings and permissions.

## How it works

```
fn down ─▶ AudioRecorder (16 kHz mono)
fn up   ─▶ SpeechEngine ─▶ number formatting ─▶ DictationRules ─▶ [LLM, only if needed] ─▶ ⌘V at cursor
           Parakeet/Whisper   NeMo ITN            corrections,       Qwen3 via llama.cpp
           ~110 ms            "four hundred"→400  fillers, stutters  Hinglish / unresolved
```

| Stage | Model / library | License | Where it runs |
|---|---|---|---|
| Speech → text (English) | Parakeet TDT 0.6B v3 via FluidAudio | CC-BY-4.0 / Apache-2.0 | Neural Engine |
| Speech → text (Hindi, Hinglish) | Whisper large-v3 turbo via WhisperKit | MIT / MIT | Neural Engine + GPU |
| Numbers ("four hundred ms" → "400 ms") | NeMo inverse text normalization (text-processing-rs) | Apache-2.0 | CPU, < 1 ms |
| Self-corrections, fillers, stutters | `DictationRules` (built-in, deterministic) | Apache-2.0 | CPU, < 5 ms |
| Lists, line breaks, emails | `DictationFormatter`: bullets, numbered steps, to-do checklists, "new line", "chandra at gmail.com" — styled per app | Apache-2.0 | CPU, < 1 ms |
| Voice commands | `DictationCommands`: "capitalize each word …", "all caps …", "lowercase …", "quote … end quote", "… press enter", "undo that" | Apache-2.0 | CPU, < 1 ms |
| Learning from edits | `EditWatcher` + `EditLearner`: names you correct join the dictionary; per-app habits (no final full stop, lowercase start) after 2 edits — counts only, never text | Apache-2.0 | Accessibility API |
| Names on screen (context awareness) | `ScreenText` + `ContextVocabulary`: names in the focused window (chat header, recipients, text near the cursor) join the dictionary for that dictation — local, never stored | Apache-2.0 | Accessibility API, read while you speak |
| Names & terms ("DeVeo" → "Divya") | `PersonalDictionary`: sound-alike match, never replaces real English words | Apache-2.0 | CPU, < 1 ms |
| Hinglish romanization, tricky corrections | Qwen3 1.7B (Q4_K_M GGUF) via llama.cpp | Apache-2.0 / MIT | GPU (Metal), ~1 s |

English dictation never waits for an LLM: the rules handle "tomorrow, no, day after tomorrow",
"to Rahul, sorry, to Priya", "3:30, actually make it 4", "um", "we could we could" and "scratch that".
The LLM only runs when a correction cue can't be resolved by rules, or for Hinglish/Hindi.

## Using it

| Gesture (default "Hold or double-tap" mode) | Result |
|---|---|
| Hold `fn`, speak, release | Dictate |
| Double-tap `fn` | Hands-free; tap `fn` again to finish |
| `Esc` while recording | Cancel |
| `fn` + any other key | Ignored (so Fn+arrows / F-keys keep working) |

The floating pill at the bottom of the screen shows state; hover it to switch language or start hands-free.

**One-time setup:** System Settings › Keyboard › "Press 🌐 key to" → **Do Nothing**. Then grant Evoo
**Microphone**, **Input Monitoring** (to see `fn`) and **Accessibility** (to paste). Don't run Evoo and
another Fn-based dictation app (e.g. Wispr Flow) at the same time — both will react.

## Build

Requires macOS 14+, Apple Silicon, and the Xcode Command Line Tools (full Xcode not required).

```bash
swift test                  # unit tests (gestures, correction rules, prompt, cleaner)
scripts/bundle.sh           # builds build/Evoo.app
open build/Evoo.app
```

First launch downloads the speech model (~0.5 GB). Download the refinement model from Settings (1.1 GB).
Models live in `~/Library/Application Support/Evoo/Models` and are pinned + SHA-256 verified.

**Permissions across rebuilds:** dev builds are ad-hoc signed with a designated requirement pinned to the
bundle ID, so macOS keeps Microphone / Input Monitoring / Accessibility across rebuilds. If permissions ever
look granted but Fn or pasting doesn't work (stale entries from older builds), quit Evoo and run
`tccutil reset All app.evoo.Evoo`, then relaunch and grant again.

### Benchmark without the app

```bash
swift build -c release --product evoo-cli
say -o /tmp/a.wav --data-format=LEI16@16000 "let's meet tomorrow, no, day after tomorrow"
.build/release/evoo-cli bench /tmp/a.wav                  # audio → text with per-stage timings
.build/release/evoo-cli post "send it to rahul, sorry, to priya"   # rules + numbers only
.build/release/evoo-cli refine --lang hinglish "कल मिलते हैं no sorry परसों"   # LLM only
```

Debug builds can render every pill state to PNGs: `.build/debug/Evoo --snapshot-pill /tmp/pill`.

Set `EVOO_LLAMA_LOG=1` to see llama.cpp's logs.

## Project layout

```
Sources/EvooCore     Pure logic, fully unit-tested: Fn gesture state machine, languages & engine routing,
                     refinement prompt + output guards, transcript cleanup, model catalog.
Sources/EvooRefine   llama.cpp refiner (KV-cached prompt prefix) and verified model downloads.
Sources/EvooSpeech   SpeechEngine protocol, Parakeet + Whisper engines, DictationPipeline (ASR → ITN → rules → LLM).
Sources/Evoo         The menu-bar app: FnKeyMonitor, AudioRecorder, TextInjector, DictationController,
                     pill + settings UI, permissions.
Sources/evoo-cli     Terminal tool: bench (audio → text timings), post (rules only), refine (LLM only).
```

Adding a speech engine = one type conforming to `SpeechEngine` (`load` / `transcribe` / `unload`) plus a case in
`ASREngineID`. Only open-weight models with OSI-approved or CC-BY licenses are accepted — no API keys, no
non-commercial licenses.

## Status & known limitations (v0.1)

Measured on an 8 GB M1 (under memory pressure):

| Case | Result |
|---|---|
| English, fn up → text ready, with a natural pause (≥ 0.35 s) before release | ✅ **1–15 ms** — transcribed speculatively while fn is held |
| English, fn up → text ready, releasing immediately after speaking | ✅ **121–139 ms** (Parakeet 0.6B); ~40–70 ms with the optional 110M model |
| Self-corrections (`Benchmarks/corrections.tsv`, 83 cases) | ✅ 83/83 · holdout of 30 unseen phrasings: 28/30, no false corrections |
| Local LLM for corrections (Qwen3 0.6B / 1.7B, deletion-only) | ❌ evaluated and rejected: 48–65/83 and 100–900 ms slower than rules (`evoo-cli corpus --llm`) |
| LLM path (unresolved corrections, Hinglish) | ~1–4 s on 8 GB M1 — opt-in, only when needed |
| Qwen3 4B | No better on the English set and 3–5× slower on 8 GB; meant for 16 GB+ Macs |
| Hinglish | ⚠️ Mixed. Whisper outputs Devanagari and the 1.7B model sometimes translates or misses corrections when romanizing. Needs a better model — top roadmap item |

Also not handled yet: Secure Input fields (password boxes, Terminal "Secure Keyboard Entry") block `fn` detection;
non-QWERTY layouts may need a different paste key code; keyboards without `fn` need a fallback hotkey; no
signed/notarized release yet.

## License

Apache-2.0. See [NOTICE](NOTICE) for model and library attributions.
