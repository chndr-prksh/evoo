# Evoo

**Open-source voice dictation for macOS that runs entirely on your Mac.**
Hold `fn`, speak, release — clean text appears at your cursor in any app.

- 100% local: speech recognition and text cleanup run on-device. No accounts, no cloud, no API keys.
- Understands what you *meant*: "let's meet tomorrow, no, day after tomorrow" → **"Let's meet day after tomorrow."**
- Works everywhere you can paste: Chrome, Slack, Gmail, Notion, VS Code, Cursor, Terminal, Office…
- English, Hinglish and Hindi. Pluggable speech engines.
- Apache-2.0. Every model it uses is open-weight and free.

## How it works

```
fn down ─▶ AudioRecorder (16 kHz mono)
fn up   ─▶ SpeechEngine ──▶ TextCleaner ──▶ LlamaRefiner ──▶ TextInjector ─▶ ⌘V at cursor
            Parakeet / Whisper   rules         Qwen3 (local)    clipboard, restored after
            (CoreML, on-device)
```

| Stage | Model / library | License | Where it runs |
|---|---|---|---|
| Speech → text (English) | Parakeet TDT 0.6B v3 via FluidAudio | CC-BY-4.0 / Apache-2.0 | Neural Engine |
| Speech → text (Hindi, Hinglish) | Whisper large-v3 turbo via WhisperKit | MIT / MIT | Neural Engine + GPU |
| Refinement (self-corrections, fillers, punctuation) | Qwen3 1.7B (Q4_K_M GGUF) via llama.cpp | Apache-2.0 / MIT | GPU (Metal) |

Clean English dictation with no fillers or corrections skips the LLM entirely (ASR already punctuates),
so most dictations paste immediately. The LLM runs only when there is something to fix.

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
swift test                  # unit tests (gesture state machine, prompt, cleaner)
scripts/bundle.sh           # builds build/Evoo.app
open build/Evoo.app
```

First launch downloads the speech model (~0.5 GB). Download the refinement model from Settings (1.1 GB).
Models live in `~/Library/Application Support/Evoo/Models` and are pinned + SHA-256 verified.

**Keep permissions across rebuilds:** ad-hoc signed builds get a new identity each time, so macOS forgets
granted permissions. Create a self-signed code-signing certificate named "Evoo Dev" in Keychain Access
(Certificate Assistant › Create a Certificate › Code Signing) and build with
`EVOO_SIGN_IDENTITY="Evoo Dev" scripts/bundle.sh`.

### Benchmark refinement without the app

```bash
swift build -c release --product evoo-cli
.build/release/evoo-cli refine "let's meet tomorrow, no, day after tomorrow"
.build/release/evoo-cli refine --lang hinglish --model qwen3_4b "कल मिलते हैं no sorry परसों"
```

Set `EVOO_LLAMA_LOG=1` to see llama.cpp's logs.

## Project layout

```
Sources/EvooCore     Pure logic, fully unit-tested: Fn gesture state machine, languages & engine routing,
                     refinement prompt + output guards, transcript cleanup, model catalog.
Sources/EvooRefine   llama.cpp refiner (KV-cached prompt prefix) and verified model downloads.
Sources/Evoo         The menu-bar app: FnKeyMonitor, AudioRecorder, SpeechEngine (Parakeet/Whisper),
                     TextInjector, DictationController, pill + settings UI, permissions.
Sources/evoo-cli     Terminal tool for benchmarking refinement.
```

Adding a speech engine = one type conforming to `SpeechEngine` (`load` / `transcribe` / `unload`) plus a case in
`ASREngineID`. Only open-weight models with OSI-approved or CC-BY licenses are accepted — no API keys, no
non-commercial licenses.

## Status & known limitations (v0.1)

Measured on an 8 GB M1 (under memory pressure):

| Case | Result |
|---|---|
| Self-corrections, fillers, questions left as questions | ✅ correct on the test set |
| Refinement latency, English | ~1–2 s when the LLM runs; ~0 s on the fast path |
| Qwen3 4B | No better on the English set and 3–5× slower on 8 GB; meant for 16 GB+ Macs |
| Hinglish | ⚠️ Mixed. Whisper outputs Devanagari and the 1.7B model sometimes translates or misses corrections when romanizing. Needs a better model — top roadmap item |

Also not handled yet: Secure Input fields (password boxes, Terminal "Secure Keyboard Entry") block `fn` detection;
non-QWERTY layouts may need a different paste key code; keyboards without `fn` need a fallback hotkey; no
signed/notarized release yet.

## License

Apache-2.0. See [NOTICE](NOTICE) for model and library attributions.
