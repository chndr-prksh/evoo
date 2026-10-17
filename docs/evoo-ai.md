# Evoo AI v1: how we fine-tuned Evoo's own polish model

Evoo AI v1 is a small language model trained for one job: turning what the speech model wrote into what you
meant to type. It is [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B) fine-tuned on 43,000 dictations, and it
runs on your Mac after Evoo's rules. Weights, examples and every test result:
[huggingface.co/e2chndr/evoo-ai-v1](https://huggingface.co/e2chndr/evoo-ai-v1).

## Why fine-tune

Stock Qwen3-0.6B, asked with Evoo's full prompt (nine rules and fifteen worked examples), polished well enough
to help, but it sometimes answered a dictated question instead of typing it, and changed little on most
dictations. A model fine-tuned on dictation needs a one-line instruction, never answers, and edits what really
needs editing.

## The data

The model has to see what Parakeet, Evoo's speech model, really writes. So the training pairs come from:

1. **Real speech with a human edit.** Podcasts and earnings calls that professionals transcribed twice, word
   for word and lightly edited (Rev16, Earnings-22).
2. **Real recogniser mistakes.** Output of four commercial recognisers next to the human transcript
   (Earnings-21), and Common Voice recognition errors (HyPoradise). Only corrections that can be made from the
   text alone were kept: teaching a text model to turn "two" into "three" because the audio said so would teach
   it to invent.
3. **Real speech polished by a teacher.** Meetings (AMI, ICSI), earnings calls and voice-assistant commands
   (MASSIVE) were polished by Claude Haiku 5.5 following Evoo's own polish prompt, so the targets follow Evoo's
   rules. Every answer was checked automatically: nothing added, nothing large dropped, no number or currency
   symbol invented, no second attempt.
4. **Everyday text, read aloud.** About 40,000 messages, notes and prompts (real prompts from OpenAssistant,
   Dolly and WildChat, plus messages the teacher wrote) were given a speaker's fillers, restarts and
   self-corrections, read aloud by 26 macOS voices (US, UK, Indian, Irish, Australian, South African) and
   transcribed by Parakeet through `evoo-cli transcribe`, then Evoo's rules through `evoo-cli post`.

The teacher was chosen by a test: on 300 dictations a person had already polished, Haiku 5.5 matched Opus 5.5
(median word error 0.117 for both) at about a fiftieth of the cost. All teacher work cost about $2, plus about $1.40 for the comparison with Opus.

## The training

LoRA with [mlx-lm](https://github.com/ml-explore/mlx-lm): rank 8 on 16 of the 28 layers (0.5% of the weights),
one pass over 43,429 pairs, batches of 2 up to 256 tokens, learning rate 1e-4, about 6 hours on an 8 GB M1
MacBook. macOS cancels GPU work that keeps the screen waiting, so training saved a checkpoint every 100 steps and
resumed by itself. The adapter was then merged into the base model and converted to GGUF (Q8_0) for llama.cpp.

## The results

All test sentences were held out. Rules run first in every row. "Evoo today" calls stock Qwen3-0.6B only
where the rules flag something; the other rows call the model on every dictation.

| | Exactly right, 300 held-out dictations | Median word error | Run-on punctuation |
|---|---|---|---|
| Evoo today | 36 | 0.24 | 10 / 10 |
| Evoo rules + stock Qwen3-0.6B | 43 | 0.24 | 5 / 10 |
| **Evoo rules + Evoo AI v1** | **78** | **0.14** | **10 / 10** |

In Evoo's own engine (`evoo-cli`, llama.cpp, 8 GB M1), rules first: self-corrections 82 / 85 against 80 / 85
for stock Qwen3-0.6B, held-out corrections 28 / 30 for both, the golden set 68 / 69 for both, and about 0.3 s
per dictation.

## What did not work (yet)

- **Replacing the rules.** A version trained to do everything alone, from raw recogniser output, reached
  only 36 of 85 self-corrections, and a top-up on targeted examples 47 of 85, while hurting other dictation.
  The rules resolve "Monday, sorry, Tuesday" almost perfectly in microseconds, so v1 runs after them.
- **Sound-alike words** ("their going", "meat you") are still mostly left as heard.

## Next

Evoo AI v2: use Evoo's rules plus v1 as the teacher for a model that sees only raw recogniser output, and
remove the rules only when that model alone matches them on Evoo's benchmark files.
