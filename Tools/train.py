#!/usr/bin/env python3
"""Fine-tunes FunctionGemma 270M on Evoo's tools with mlx-lm (LoRA), on the data from build_dataset.py.

    python Tools/train.py --config Tools/lora.yaml

The prompts are already in FunctionGemma's exact format, so they are tokenized as they are (no chat template),
and only the answer — the tool call — is learned.
"""
import sys
from functools import partial

import mlx.core as mx
import mlx.nn as nn
import mlx_lm.tuner.datasets as datasets
import mlx_lm.tuner.trainer as trainer
from mlx_lm import lora


# The tool list at the top of every prompt is the same ~2,000 tokens. Word scores are only needed for the few
# tokens after it; computing them for the whole prompt (262k-word vocabulary) needs gigabytes for nothing.
PREFIX = open("Tools/prefix.txt").read()
start = 0


def process(self, d):
    global start
    bos = [self.tokenizer.bos_token_id] if self.tokenizer.bos_token_id is not None else []
    if not start and d[self.prompt_key].startswith(PREFIX):
        start = max(len(bos + self.tokenizer.encode(PREFIX, add_special_tokens=False)) - 8, 0)
    prompt = bos + self.tokenizer.encode(d[self.prompt_key], add_special_tokens=False)
    completion = self.tokenizer.encode(d[self.completion_key], add_special_tokens=False)
    return (prompt + completion, len(prompt))


def loss(model, batch, lengths):
    inputs, targets = batch[:, :-1], batch[:, 1:]
    if not hasattr(model, "lm_head") or not hasattr(model, "model"):
        return trainer.default_loss(model, batch, lengths)
    hidden = model.model(inputs)[:, start:]
    logits = model.lm_head(hidden)
    steps = mx.arange(start + 1, targets.shape[1] + 1)
    mask = mx.logical_and(steps >= lengths[:, 0:1], steps <= lengths[:, 1:])
    ce = nn.losses.cross_entropy(logits, targets[:, start:]) * mask
    ntoks = mask.sum()
    return ce.astype(mx.float32).sum() / ntoks, ntoks


datasets.CompletionsDataset.process = process
lora.train = partial(trainer.train, loss=loss)
lora.evaluate = partial(trainer.evaluate, loss=loss)

if __name__ == "__main__":
    sys.argv = ["mlx_lm.lora"] + sys.argv[1:]
    lora.main()
