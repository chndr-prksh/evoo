#!/usr/bin/env python3
"""Scores a model on Tools/data/test.jsonl: how often it calls the right tool(s) with the right arguments.

    python Tools/eval_mlx.py --model unsloth/functiongemma-270m-it [--adapter Tools/out/adapter] [--limit 100]
"""
import argparse, json, re, time
from mlx_lm import load, stream_generate

def parse(output):
    calls = []
    for name, body in re.findall(r"<start_function_call>call:([^{<]*)\{(.*?)\}?<end_function_call>", output, flags=re.S):
        args, rest = {}, body
        while rest:
            m = re.match(r"\s*,?\s*([^:,]+):", rest)
            if not m: break
            key, rest = m.group(1).strip(), rest[m.end():]
            if rest.startswith("<escape>"):
                end = rest.find("<escape>", 8)
                value, rest = (rest[8:end], rest[end + 8:]) if end >= 0 else (rest[8:], "")
            else:
                end = rest.find(",")
                value, rest = (rest[:end], rest[end:]) if end >= 0 else (rest, "")
            args[key] = value.strip(" }")
        calls.append((name.strip(), args))
    return calls

def norm(s):
    return " ".join(re.sub(r"[^a-z0-9 ]", "", str(s).lower()).split())

def same(got, want):
    opens = {"open_app", "open_website"}
    if got[0] in opens and want[0] in opens:
        return norm(got[1].get("name", got[1].get("site", ""))) == norm(want[1].get("name", want[1].get("site", "-")))
    return got[0] == want[0] and set(got[1]) == set(want[1]) and all(norm(v) == norm(want[1][k]) for k, v in got[1].items())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True); ap.add_argument("--adapter"); ap.add_argument("--limit", type=int, default=10**9)
    ap.add_argument("--data", default="Tools/data/test.jsonl"); ap.add_argument("--show", type=int, default=25)
    a = ap.parse_args()
    model, tokenizer = load(a.model, adapter_path=a.adapter)
    rows = [json.loads(l) for l in open(a.data)][: a.limit]
    full = names = shown = 0
    kinds, started = {}, time.time()
    for row in rows:
        ids = [tokenizer.bos_token_id] + tokenizer.encode(row["prompt"], add_special_tokens=False)
        out = []
        for r in stream_generate(model, tokenizer, ids, max_tokens=140):
            out.append(r.token)
            text = tokenizer.decode(out)
            if text.endswith("<start_function_response>") or "<end_of_turn>" in text: break
        text = tokenizer.decode(out)
        got = parse(text)
        want = [(c["name"], {k: str(v) for k, v in c["args"].items()}) for c in row["calls"]]
        ok = len(got) == len(want) and all(same(g, w) for g, w in zip(got, want))
        full += ok; names += [g[0] for g in got] == [w[0] for w in want]
        kind = "chains" if len(want) > 1 else want[0][0]
        k = kinds.setdefault(kind, [0, 0]); k[1] += 1; k[0] += ok
        if not ok and shown < a.show:
            shown += 1
            print(f"MISS {row['user']}\n   want: {want}\n   got:  {got or text[:120]}")
    print()
    for kind, (ok, n) in sorted(kinds.items(), key=lambda kv: kv[1][0] / kv[1][1]): print(f"{kind:18} {ok}/{n}")
    n = len(rows)
    print(f"\nTOOLS fully right {full}/{n} ({full / n * 100:.1f}%) · right tool(s), any arguments {names}/{n} ({names / n * 100:.1f}%) · {(time.time() - started) / n * 1000:.0f} ms avg")

if __name__ == "__main__":
    main()
