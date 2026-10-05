# Evoo

**Open-source voice dictation for macOS that runs entirely on your Mac.**
Hold `fn`, speak, release — clean text appears at your cursor in any app.

<p>
  <a href="https://chndr-prksh.github.io/evoo/"><b>🌐 Website: chndr-prksh.github.io/evoo</b></a>
</p>

<p>
  <a href="https://github.com/chndr-prksh/evoo/releases/latest/download/Evoo.zip">
    <img alt="Download for Mac" src="https://img.shields.io/badge/Download%20for%20Mac-free-2ea44f?style=for-the-badge&logo=apple&logoColor=white" height="44">
  </a>
</p>

Apple Silicon Mac (M1 or newer), macOS 14+. After downloading: unzip, drag **Evoo** to Applications, open it.
The first time, macOS says it "could not verify" Evoo (it isn't signed with a paid Apple certificate) — open
**System Settings › Privacy & Security** and click **Open Anyway**, once. Or skip that step entirely with the
one-line install below. Evoo updates itself after that.

- 100% local: speech recognition and text cleanup run on-device. No accounts, no cloud, no API keys.
- Understands what you *meant*: "let's meet tomorrow, no, day after tomorrow" → **"Let's meet day after tomorrow."**
- Works everywhere you can paste: Chrome, Slack, Gmail, Notion, VS Code, Cursor, Terminal, Office…
- **24 more European languages (beta)** from the same built-in speech model (Parakeet TDT v3) — Spanish, French, German, Italian, Portuguese, Dutch, Polish, Russian, Ukrainian and others: pick one in Settings › Language. They get the speech model's text as heard; Evoo's rules, voice commands and AI polish are English-only for now.
- English, plus a **Hinglish add-on (beta)**: download it from Settings (133 MB) and switch languages on the pill. It uses its own model (Oriserve Whisper-Hindi2Hinglish, Apache-2.0), writes Roman Hinglish ("kal meeting hai, please confirm kar dena"), and handles Hinglish self-corrections; English keeps its own model and is unaffected.
- Speculative transcription: Evoo starts transcribing when you pause, so text is usually ready the instant fn goes up.
- Personal dictionary for names and jargon (Divya, Aarav, Kubernetes).
- Voice shortcuts: say "my email" (alone or mid-sentence) and get the full text you set up.
- Voice editing: "replace Tuesday with Wednesday", "delete the last sentence", "make that a list".
- History: search and copy your recent dictations (menu → History…), kept only on your Mac.
- **Welcome tour** on first launch: privacy & offline, what you can do, and a step-by-step permissions guide
  that ticks off each step live. Afterwards, a small tip by the pill now and then introduces one feature at a time.
- **Class Notes** (🎓 on the pill, or say "start class notes"): pick the subject and start the class. Evoo
  listens and jots down only what matters — definitions, formulas (LaTeX), key numbers, what the professor
  stresses — in short fragments, like a sharp classmate, typed into your notes word by word. Edit the notes any
  time, even while it's writing. Flag moments (★ Important, ❓ Confusing, 🎯 Exam — ⌘1–3) to steer it. After
  class: a one-screen study sheet (summary, key formulas, terms, practice questions), flashcards, and Q&A about
  the lecture. No audio is kept. Classes are grouped by subject; say "search note Bayes theorem" to find
  something. Export to PDF or Markdown.
- **Desktop app:** Evoo sits in the Dock; click it for Home (words dictated, speaking speed, time saved, streak, recent dictations), History, Dictionary, Class Notes and Settings. Prefer menu bar only? Settings › Show Evoo in the Dock.
- **Instant start:** the pill appears the moment you press fn. Optional *Keep the microphone ready* (Settings) keeps
  the mic on between dictations, holding only the last 0.3 s in memory, so recording starts instantly and includes
  the moment before the press. Drag the pill anywhere along the bottom or up the left/right side (it stands upright
  there), or pick a spot in Settings › Pill position.
- **Long dictations stay fast:** while you speak, finished sentences are transcribed and, if they need it, polished
  in the background — a 42 s filler-heavy dictation is ready ~0.3 s after release on an 8 GB M1.
- **Learns how you write** (all on your Mac): Evoo keeps what it typed next to what you actually sent. Word swaps
  you keep making in an app ("going to" → "gonna") are applied instantly; once you have ~150 edits, it fine-tunes a
  small add-on for its AI overnight (MLX LoRA, while plugged in), tests it on edits it hasn't seen, and only uses it
  if it's clearly closer to you. On a test persona: plain model 0/28 messages written their way, personal add-on
  24/28. Settings › Your writing style / Personal model — view, turn off, or erase any time.
- **Voice commands** (say the whole command as one dictation; anything else is typed as usual):
  - Apps & web: "open Slack", "switch to Chrome", "open github.com", "search Google for …", "ask ChatGPT …",
    "YouTube …", "new Google doc", "new email about …" — every installed app, plus your own in Settings → Apps
  - Your Mac: "search my Mac for …" (Spotlight), "run shortcut Morning Routine" (Apple Shortcuts), "volume 30",
    "volume thirty", "press space bar", "mute", "next song", "dark mode", "take a screenshot", "lock screen"
  - Keys: "new tab", "reopen tab", "refresh", "copy", "paste", "save", "scroll down", "press command shift T"
  - Windows & buttons: "move this to the left half", "maximize this window", "full screen", "click Send"
  - Assistant: "remind me to call Divya tomorrow at 5", "schedule lunch with Raj Friday at 1 PM",
    "note: …", "what did I say about the invoice?" (searches by meaning, on-device)
  - Audio: "read this aloud", "stop reading", "transcribe a file" (→ text + .srt subtitles)
- **16 GB Macs — Smart cleanup (local AI):** a local model (Qwen3 4B, Apache-2.0) polishes each dictation after
  the rules — grammar, messy phrasing, "can u" → "can you" — and powers **rewrite by voice**: select text, hold fn,
  say "make this more formal", "shorten this", "translate to Hindi". Off by default; download from Settings.
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

The floating pill at the bottom of the screen shows state; hover it to start hands-free or open Class Notes. Drag it left or right to move it along the bottom of the screen (or Settings › Pill position).

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
