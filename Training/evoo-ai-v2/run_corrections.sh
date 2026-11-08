#!/bin/zsh
# Evoo AI v2 (corrections): continue v1 on the self-corrections Evoo's rules leave unresolved, with a replay
# of v1's training set, then score it against v1. Run it again after any interruption and it carries on.
#
#   caffeinate -is zsh run_corrections.sh
set -u
cd "$(dirname "$0")"
PY=.venv/bin/python
ADAPTER=adapters/evoo-ai-v2c
START_FROM=adapters/evoo-polish-v1/adapters.safetensors
STEPS_DONE=out/corrections_steps_done
SAVE_EVERY=100
BATCH=2
DATA_DIR=data/train_corrections
LR=5e-5   # lower than v1's, so what v1 learned is kept
mkdir -p out adapters

log() { echo "[$(date '+%m-%d %H:%M')] $*" | tee -a out/overnight.log }
source ./train_lib.sh

if [ ! -f $ADAPTER/complete ]; then
  [ -f $DATA_DIR/train.jsonl ] || $PY 08_prepare_corrections.py >> out/overnight.log 2>&1
  PAIRS=$(wc -l < $DATA_DIR/train.jsonl | tr -d ' ')
  log "v2 corrections: continuing v1 on $PAIRS pairs"
  for attempt in {1..200}; do
    train $((PAIRS / BATCH)) && { touch $ADAPTER/complete; break }
    log "   attempt $attempt stopped ($(grep -h -o 'RuntimeError.*' out/train_full.log | tail -1 | cut -c1-70)); resuming"
    sleep 20
  done
  [ -f $ADAPTER/complete ] || { log "   training did not finish; run this script again to continue"; exit 1 }
fi

log "scoring v2 corrections against v1"
for A in adapters/evoo-polish-v1 $ADAPTER; do
  $PY 09_eval_corrections.py --adapter $A 2>/dev/null | tee -a out/overnight.log
  $PY 05_eval.py --adapter $A --app --always --n 300 2>/dev/null | tail -2 | tee -a out/overnight.log
done
$PY 06_evoo_benchmarks.py --adapter $ADAPTER --app --always 2>/dev/null | tee -a out/overnight.log
log "done"
