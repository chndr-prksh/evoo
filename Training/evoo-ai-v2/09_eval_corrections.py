"""Score a model on corrections the rules leave unresolved: held-out generated pairs and real dictations.

    python 09_eval_corrections.py [--adapter adapters/evoo-ai-v2c] [--n 200]
Prints how many come out exactly right (ignoring case and punctuation) and the median word error.
"""
import argparse
import json
import re
import statistics
from pathlib import Path

from mlx_polish import load_polisher
from textscore import wer

ROOT = Path(__file__).parent


def norm(s):
    return " ".join(re.sub(r"[^\w' ]", " ", s.lower()).split())


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--show", action="store_true")
    a = ap.parse_args()
    polish = load_polisher(a.adapter)
    name = Path(a.adapter).name if a.adapter else "stock"
    sets = {"your dictations": [json.loads(l) for l in open(ROOT / "data/user_corrections.jsonl")],
            "held-out corrections": [json.loads(l) for l in open(ROOT / "data/train_corrections/test_pairs.jsonl")][: a.n]}
    for title, rows in sets.items():
        right, errs = 0, []
        by = {}
        for r in rows:
            out = polish(r["raw"])
            ok = norm(out) == norm(r["ref"])
            right += ok
            errs.append(wer(r["ref"], out))
            k = r.get("source", "real")
            by.setdefault(k, [0, 0]); by[k][0] += ok; by[k][1] += 1
            if a.show or title == "your dictations":
                print(("✓ " if ok else "✗ ") + r["raw"][:110] + "\n    → " + out[:160])
        print(f"{name} · {title}: exactly right {right}/{len(rows)} · median word error {statistics.median(errs):.2f} · " +
              " · ".join(f"{k} {v[0]}/{v[1]}" for k, v in by.items()) + "\n")
