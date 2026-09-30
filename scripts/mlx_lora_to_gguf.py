#!/usr/bin/env python3
"""Convert an MLX (mlx-lm) LoRA adapter to a llama.cpp GGUF LoRA adapter.

    python scripts/mlx_lora_to_gguf.py <adapter_dir> <out.gguf> [--arch qwen3]

mlx-lm stores lora_a as (in, r) and lora_b as (r, out) and adds `scale * (x @ a) @ b`.
llama.cpp expects lora_a as (r, in), lora_b as (out, r) and scales by alpha / r, so alpha = scale * r.
Needs: mlx, numpy, gguf (pip install mlx gguf numpy).
"""
import json
import re
import sys
from pathlib import Path

import gguf
import mlx.core as mx
import numpy as np

NAMES = {
    "self_attn.q_proj": "attn_q", "self_attn.k_proj": "attn_k", "self_attn.v_proj": "attn_v",
    "self_attn.o_proj": "attn_output", "mlp.gate_proj": "ffn_gate", "mlp.up_proj": "ffn_up",
    "mlp.down_proj": "ffn_down",
}


def main():
    adapter_dir, out = Path(sys.argv[1]), sys.argv[2]
    arch = sys.argv[sys.argv.index("--arch") + 1] if "--arch" in sys.argv else "qwen3"
    config = json.loads((adapter_dir / "adapter_config.json").read_text())
    params = config.get("lora_parameters", {})
    rank, scale = int(params.get("rank", 8)), float(params.get("scale", 20.0))
    weights = mx.load(str(adapter_dir / "adapters.safetensors"))

    writer = gguf.GGUFWriter(out, arch=arch)
    writer.add_string("general.type", "adapter")
    writer.add_string("adapter.type", "lora")
    writer.add_float32("adapter.lora.alpha", scale * rank)
    count = 0
    for key in sorted(weights):
        m = re.match(r"model\.layers\.(\d+)\.(.+)\.lora_([ab])$", key)
        if not m:
            raise SystemExit(f"unexpected tensor {key}")
        layer, module, which = m.groups()
        if module not in NAMES:
            raise SystemExit(f"no llama.cpp name for {module}")
        base = f"blk.{layer}.{NAMES[module]}.weight"
        t = np.array(weights[key].astype(mx.float32)).T.copy()  # (in,r)->(r,in) / (r,out)->(out,r)
        writer.add_tensor(f"{base}.lora_{which}", t.astype(np.float16))
        count += 1
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_tensors_to_file()
    writer.close()
    print(f"wrote {out}: {count} tensors, rank {rank}, alpha {scale * rank}")


if __name__ == "__main__":
    main()
