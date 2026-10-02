#!/bin/bash
# Packages the benchmark tool for other Macs: build/evoo-bench.tar.gz (evoo-cli + llama.framework + test data).
# Used by scripts/benchmark.sh (which people run on their own Mac).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product evoo-cli
BIN="$(swift build -c release --show-bin-path)"
rm -rf build/evoo-bench && mkdir -p build/evoo-bench/Benchmarks
cp "$BIN/evoo-cli" build/evoo-bench/
ditto "$BIN/llama.framework" build/evoo-bench/llama.framework
cp Benchmarks/golden.tsv Benchmarks/passages.txt Benchmarks/misheard.tsv build/evoo-bench/Benchmarks/
codesign --force --sign - build/evoo-bench/llama.framework
codesign --force --sign - build/evoo-bench/evoo-cli
tar -czf build/evoo-bench.tar.gz -C build evoo-bench
echo "Packaged build/evoo-bench.tar.gz ($(du -h build/evoo-bench.tar.gz | cut -f1))"
