# Evoo AI v2 (corrections): experiment, not shipped

Continues [Evoo AI v1](../../docs/evoo-ai.md) on the self-corrections Evoo's rules leave to the model, such as
"a day or 2, no no, I think a week", "the best way no a great way" and "At 5 PM? I think no 6 PM".

These scripts plug into v1's training pipeline (published with the model on
[Hugging Face](https://huggingface.co/e2chndr/evoo-ai-v1/tree/main/training)): copy them into that folder.

| File | What it does |
|---|---|
| `datagen/unresolved.py` | Corrects clean sentences in the loose ways people do, runs Evoo's rules, keeps the ones the rules leave unresolved. The clean sentence is the target, so no teacher model is needed. |
| `08_prepare_corrections.py` | 7,035 corrections + 1,500 "no / I think must stay" + 12,000 replayed v1 pairs. Drops pairs where the rules had already cut words the target needs. |
| `09_eval_corrections.py` | Scores held-out generated corrections and real dictations (`user_corrections.jsonl`). |
| `run_corrections.sh` | Resumable training from v1's adapter (rank 8, 16 layers, lr 5e-5, one pass), then scoring. |

## Results (October 2026)

| | v1 | v2 corrections |
|---|---|---|
| 300 held-out dictations, rules first: exactly right | 78 | **90** |
| Spoken questions with self-corrections (Disfl-QA) | 42 / 107 | **48 / 107** |
| Held-out generated corrections fixed | 17 / 71 | **53 / 71** |
| "No" / "I think" correctly kept | 102 / 129 | **112 / 129** |
| Real dictations (`user_corrections.jsonl`) | 2 / 9 | 2 / 9 |

Not shipped: on the real dictations it twice changed "day after tomorrow" to "tomorrow". Changing what was said
is worse than leaving a correction in. Next round: corrections across a sentence break, soft corrections
("I think 6 PM would be better"), whole-phrase swaps, fixed phrases protected, and a larger real-dictation test set
as the gate.

Found along the way: in about 7% of generated inputs Evoo's rules had already deleted words (a restart rule
firing across sentences), and "ten hours" becomes "10 h". Both are rules bugs to fix.
