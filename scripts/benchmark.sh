#!/bin/bash
# Evoo speed benchmark for this Mac. Paste into Terminal:
#   curl -fsSL https://raw.githubusercontent.com/chndr-prksh/evoo/main/scripts/benchmark.sh | bash
# Takes ~15-20 minutes. Downloads the test tool (16 MB) and any AI models Evoo doesn't have yet (up to ~4.5 GB,
# kept for Evoo to use). Speaks test sentences with macOS text-to-speech (turn the volume down if you like).
# Nothing is uploaded: the results are saved to ~/evoo-bench/results.txt and copied to the clipboard.
set -euo pipefail

DIR="$HOME/evoo-bench"
OUT="$DIR/results.txt"
[ "$(uname -m)" = "arm64" ] || { echo "Evoo needs an Apple Silicon Mac (M1 or newer)."; exit 1; }

echo "==> Downloading the Evoo benchmark tool..."
mkdir -p "$DIR"
cd "$DIR"
curl -fsSL "https://github.com/chndr-prksh/evoo/releases/latest/download/evoo-bench.tar.gz" | tar -xz --strip-components 1

# Evoo holds an AI model in memory; close it so it doesn't skew the numbers (it's reopened at the end).
WAS_RUNNING=0
if pgrep -x Evoo >/dev/null; then WAS_RUNNING=1; osascript -e 'quit app "Evoo"' >/dev/null; sleep 3; fi

echo "==> Getting the AI models (skipped if already on this Mac)..."
./evoo-cli download qwen3_0_6b qwen3_1_7b qwen3_4b | grep -E "done|already" || true

FILLER="Um, so I wanted to, like, give you a quick update on the launch. Uh, basically the design team finished the, the onboarding screens last night. You know, we still need to, um, review the copy on the pricing page. Like, engineering fixed most of the bugs, but, uh, there is one issue left with notifications. So, basically, Priya is looking into it, and, you know, she expects a fix by tomorrow."

echo "==> Running the tests (about 5 minutes per model)..."
{
  echo "Evoo benchmark · $(date '+%Y-%m-%d %H:%M')"
  echo "Mac: $(sysctl -n machdep.cpu.brand_string) · $(( $(sysctl -n hw.memsize) / 1073741824 )) GB · macOS $(sw_vers -productVersion)"
  for m in qwen3_0_6b qwen3_1_7b qwen3_4b; do
    echo
    echo "== $m"
    echo "-- one sentence at a time (first one includes loading the model):"
    ./evoo-cli refine --model "$m" \
      "So I wanted to like give you a quick update on the launch." \
      "Basically the design team finished the onboarding screens last night." \
      "I think we should, like, give ourselves two extra days just to be safe." \
      "There is one issue left with notifications on older phones, you know." 2>&1 | grep -E "^out|ms\)" || true
    echo "-- every feature (golden set):"
    ./evoo-cli golden --parakeet v3 --polish --polish-model "$m" 2>&1 | grep "^PASSED" || true
    echo "-- misheard words (contextual polish):"
    ./evoo-cli misheard --model "$m" 2>&1 | grep "^misheard" || true
    echo "-- real-time dictations, fn up -> text:"
    ./evoo-cli stress --parakeet v3 --polish --polish-model "$m" --sentences 1,5,10 --modes stream 2>&1 | grep "^stream" || true
    [ "$m" != qwen3_0_6b ] && { ./evoo-cli stress --parakeet v3 --polish --polish-model "$m" --contextual --sentences 1,5,10 --modes stream 2>&1 | grep "^stream" | sed 's/^stream/context/' || true; }
    ./evoo-cli stress --parakeet v3 --polish --polish-model "$m" --modes stream --text "$FILLER" 2>&1 | grep "^stream" | sed 's/^stream/filler/' || true
  done
} 2>&1 | tee "$OUT"

[ "$WAS_RUNNING" = 1 ] && open -a Evoo || true
pbcopy < "$OUT"
echo
echo "Done. The results are copied to your clipboard (and saved in $OUT) — paste them back to the Evoo developer."
