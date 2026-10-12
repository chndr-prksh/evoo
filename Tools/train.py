#!/usr/bin/env python3
"""Fine-tunes FunctionGemma 270M on Evoo's tools with mlx-lm (LoRA), on the data from build_dataset.py.

    python Tools/train.py --config Tools/lora.yaml

The prompts are already in FunctionGemma's exact format, so they are tokenized as they are (no chat template),
and only the answer — the tool call — is learned.
"""
import sys

import mlx_lm.tuner.datasets as datasets
from mlx_lm import lora


def process(self, d):
    bos = [self.tokenizer.bos_token_id] if self.tokenizer.bos_token_id is not None else []
    prompt = bos + self.tokenizer.encode(d[self.prompt_key], add_special_tokens=False)
    completion = self.tokenizer.encode(d[self.completion_key], add_special_tokens=False)
    return (prompt + completion, len(prompt))


datasets.CompletionsDataset.process = process

if __name__ == "__main__":
    sys.argv = ["mlx_lm.lora"] + sys.argv[1:]
    lora.main()
