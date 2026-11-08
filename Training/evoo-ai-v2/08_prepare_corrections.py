"""Evoo AI v2 (corrections): a top-up set for continuing from v1.

The self-corrections Evoo's rules leave unresolved (datagen/unresolved.py), plus a replay of v1's own
training set so nothing v1 learned is lost. Writes data/train_corrections/{train,valid}.jsonl.

    python 08_prepare_corrections.py
"""
import importlib
import json
import random
from collections import Counter
from pathlib import Path

DATA = Path(__file__).parent / "data"
CAPS = {"unresolved:correction": 9_000, "unresolved:keep": 1_500}
REPLAY = 12_000
VALID = 300

chat = importlib.import_module("04_prepare_training").chat

if __name__ == "__main__":
    rng = random.Random(1)
    rows = [json.loads(line) for line in open(DATA / "pairs" / "unresolved.jsonl")]

    def words(t):
        return [w for w in "".join(c if c.isalnum() or c == "'" else " " for c in t.lower()).split() if not w.isdigit()]

    def covered(r):
        """Every word of the target was said: the rules must not have cut text the model would have to invent."""
        have = set(words(r["raw"]))
        need = words(r["ref"])
        return not need or sum(w in have for w in need) / len(need) >= 0.92

    before = len(rows)
    rows = [r for r in rows if covered(r)]
    print(f"dropped {before - len(rows)} pairs where the rules had cut words the target needs")
    rng.shuffle(rows)
    taken, train, held = Counter(), [], []
    for r in rows:
        if r["split"] == "test":
            held.append(chat(r))
        elif taken[r["source"]] < CAPS[r["source"]]:
            taken[r["source"]] += 1
            train.append(chat(r))
    replay = [json.loads(line) for line in open(DATA / "train" / "train.jsonl")]
    train += rng.sample(replay, REPLAY)
    rng.shuffle(train)
    valid = rng.sample(held, VALID // 2) + rng.sample([json.loads(l) for l in open(DATA / "train" / "valid.jsonl")], VALID // 2)
    out = DATA / "train_corrections"
    out.mkdir(exist_ok=True)
    for name, part in (("train", train), ("valid", valid)):
        with open(out / f"{name}.jsonl", "w") as f:
            for row in part:
                f.write(json.dumps({"messages": row["messages"]}, ensure_ascii=False) + "\n")
    # The held-out corrections, as raw/ref pairs, for 09_eval_corrections.py.
    with open(out / "test_pairs.jsonl", "w") as f:
        for r in rows:
            if r["split"] == "test":
                f.write(json.dumps({"raw": r["raw"], "ref": r["ref"], "source": r["source"]}, ensure_ascii=False) + "\n")
    print(f"train {len(train)} pairs: {dict(taken)} + {REPLAY} replayed; valid {len(valid)}")
