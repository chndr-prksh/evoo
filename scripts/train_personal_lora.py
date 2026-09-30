#!/usr/bin/env python3
"""Train a personal polish adapter with mlx-lm on data from `evoo-cli export-train`.

The prompts are already in Evoo's exact ChatML form, so they're tokenized as-is (no chat template), and
only the completion (what the person sent) is learned.

    python scripts/train_personal_lora.py --config lora.yaml
"""
import sys

import mlx_lm.tuner.datasets as datasets
from mlx_lm import lora


def process(self, d):
    prompt = self.tokenizer.encode(d[self.prompt_key], add_special_tokens=False)
    completion = self.tokenizer.encode(d[self.completion_key], add_special_tokens=False)
    return (prompt + completion, len(prompt))


datasets.CompletionsDataset.process = process

if __name__ == "__main__":
    sys.argv = ["mlx_lm.lora"] + sys.argv[1:]
    lora.main()
