"""Evoo AI v2 (corrections): the self-corrections Evoo's rules hand to the model.

People correct themselves without the tidy cues the rules know ("Monday, sorry, Tuesday"):
"a day or 2, no no, I think a week", "the best way no a great way", "At 5 PM? I think no 6 PM",
"tomorrow. Like no day after tomorrow". The rules flag these and pass them on, and v1 then keeps both
the wrong and the right value. Here the clean sentence is known, so the target is exact: no teacher.

Each pair is run through Evoo's rules (evoo-cli post) and kept only when the rules leave the correction
unresolved, so the model learns exactly what it will be given. Counter-examples, where "no" or
"I think" carry meaning, teach it to leave those alone.

    python -I datagen/unresolved.py data/everyday/to_read_aloud.jsonl data/pairs/unresolved.jsonl
"""
import json
import os
import random
import re
import subprocess
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_real import TEST_SHARE, as_heard  # noqa: E402
from targeted import another, sentences, values  # noqa: E402

# How people correct themselves in the middle of a sentence, beyond the cues the rules know.
CUES = ["no no", "no no I think", "I think", "no I think", "like no", "or no", "well no", "hmm no",
        "actually I think", "no wait I think", "I guess", "or I mean", "no sorry I think", "nah", "no make it",
        "or actually", "I'd say", "no let me say", "rather", "no no no", "um no", "uh no", "like", "or maybe",
        "no it's", "no I mean", "oh no", "ah no"]
# Words people swap for a better one mid-sentence: "the best way no a great way".
ADJ = ["great", "good", "best", "nice", "big", "small", "quick", "short", "long", "easy", "hard", "simple",
       "important", "useful", "better", "clear", "early", "late", "cheap", "new", "old", "main", "key"]
EVOO_CLI = Path(os.environ.get("EVOO_CLI", "/private/tmp/claude-501/evoo-main/.build/debug/evoo-cli"))


def adjectives(sentence):
    return [(m.start(), m.end(), "adj") for m in re.finditer(rf"\b({'|'.join(ADJ)})\b", sentence)]


def said_with_correction(sentence, rng):
    spans = values(sentence) + adjectives(sentence)
    if not spans:
        return None
    a, b, kind = rng.choice(spans)
    right = sentence[a:b]
    wrong = rng.choice([w for w in ADJ if w != right.lower()]) if kind == "adj" else another(right, kind, rng)
    cue = rng.choice(CUES)
    before = sentence[:a]
    # Sometimes the speaker repeats the word before the value: "a great way no a best way".
    lead = before.split()[-1] if before.split() and rng.random() < 0.35 else ""
    style = rng.random()
    if style < 0.35:
        said = f"{wrong}, {cue}, {lead + ' ' if lead else ''}{right}"
    elif style < 0.6:
        said = f"{wrong} {cue} {lead + ' ' if lead else ''}{right}"
    elif style < 0.8:
        said = f"{wrong}. {cue[0].upper() + cue[1:]} {lead + ' ' if lead else ''}{right}"
    else:
        said = f"{wrong}? {cue[0].upper() + cue[1:]} {lead + ' ' if lead else ''}{right}"
    return before + said + sentence[b:]


def keep_meaning(sentence, rng):
    """'No, I think it's fine' / 'I think a week is enough': cues that are real words and must stay."""
    first = sentence.split()[0].strip(",") if sentence.split() else ""
    if not sentence[:1].isupper() or first.lower() in ("hi", "hello", "hey", "dear", "morning", "good", "thanks", "thank"):
        return None
    body = sentence if first in ("I", "I'm", "I'd", "I'll", "I've") else sentence[0].lower() + sentence[1:]
    if rng.random() < 0.5:
        return f"No, {body}"
    return None if first == "I" else f"I think {body}"


def rules(texts):
    """Evoo's rules on each text, as the app runs them before the model."""
    out = []
    for i in range(0, len(texts), 400):
        chunk = texts[i:i + 400]
        res = subprocess.run([str(EVOO_CLI), "post", *chunk], capture_output=True, text=True, check=True).stdout
        got = [re.sub(r"\s+\[(?:unresolved → LLM|AI polish)\].*$|\s+\(\d[\d,.]*\s*\S+\)$", "", line[5:]).rstrip()
               for line in res.splitlines() if line.startswith("out: ")]
        assert len(got) == len(chunk), (len(got), len(chunk))
        out += got
    return out


def norm(s):
    return " ".join(re.sub(r"[^\w' ]", " ", s.lower()).split())


def main(source, out, seed=23):
    rng = random.Random(seed)
    passages = [json.loads(line) for line in open(source)]
    rng.shuffle(passages)
    rows = []
    for p in passages:
        base = p["id"].split("~")[0]
        split = "test" if zlib.crc32(base.encode()) % 100 < TEST_SHARE * 100 else "train"
        parts = [s for s in sentences(p["text"]) if 5 <= len(s.split()) <= 35]
        for k, s in enumerate(parts):
            r = rng.random()
            if r < 0.5 and (said := said_with_correction(s, rng)):
                ref = s
            elif r < 0.53 and (said := keep_meaning(s, rng)):
                ref = said
            else:
                continue
            # Sometimes with the sentence before it, the way people dictate a few sentences at once.
            if k and rng.random() < 0.3:
                said, ref = f"{parts[k - 1]} {said}", f"{parts[k - 1]} {ref}"
            heard, style = as_heard(said, rng) if rng.random() < 0.6 else (said, "commas")
            rows.append({"id": f"{base}~u{seed}-{len(rows)}", "source": "unresolved:" + ("keep" if ref == said else "correction"),
                         "route": 1, "split": split, "raw": heard, "ref": ref, "raw_style": style,
                         "target": "original text", "license": p["license"]})
    after = rules([r["raw"] for r in rows])
    kept = []
    for row, text in zip(rows, after):
        row["raw"] = text  # what the model will be given in the app
        resolved = norm(text) == norm(row["ref"])
        # Corrections the rules already fix are left to the rules; keep a few so the model leaves good text alone.
        if row["source"] == "unresolved:correction" and resolved and rng.random() > 0.1:
            continue
        kept.append(row)
    with open(out, "w") as f:
        for r in kept:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    counts = {}
    for r in kept:
        counts[(r["source"], r["split"])] = counts.get((r["source"], r["split"]), 0) + 1
    print(f"{len(rows)} generated, {len(kept)} kept:", counts)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 23)
