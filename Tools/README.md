# Evoo's tool-calling model

A small on-device model (FunctionGemma 270M, fine-tuned) that turns a spoken request into actions:

    "can you make it a bit louder and bring up my email"
    → change_volume{direction: up} → open_app{name: Mail}

| File | What it is |
| --- | --- |
| `tools.json` | Every action Evoo can take, as tools. The one source of truth. |
| `build_dataset.py` | Writes the training and test examples. The test set uses phrasings, apps and names the training set never sees. |
| `train.py`, `lora.yaml` | Fine-tuning (mlx-lm LoRA). |
| `eval_mlx.py` | Scores a model on the test set. |
| `prefix.txt` | The start of every prompt (must equal `ToolCall.prefix` in the app; a unit test checks). |

Training runs on GitHub's Mac servers, not on your Mac:

```bash
gh workflow run tools-train.yml -f iters=2500             # model kept as a run artifact
gh workflow run tools-train.yml -f iters=2500 -f version=v1   # also published as release tools-model-v1
```

Try it without doing anything on the Mac (prints the planned steps only):

```bash
swift run evoo-cli tools "close this tab and switch to Slack"
swift run evoo-cli tools-eval --gguf path/to/evoo-tools-q8_0.gguf --show
```

In the app the model runs in command mode (fn + Control) when no fixed phrase matched, and only if
`~/Library/Application Support/Evoo/Models/tools/evoo-tools-q8_0.gguf` exists.

To add a tool: add it to `tools.json`, add phrasings (train and test) in `build_dataset.py`, map it to an action in
`Sources/EvooCore/ToolPlan.swift`, add its name to `ToolCall.toolNames`, and retrain.

The base model, google/functiongemma-270m-it, is provided under the Gemma Terms of Use (ai.google.dev/gemma/terms).
