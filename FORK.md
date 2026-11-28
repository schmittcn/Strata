# FORK.md: notes for anyone (human or LLM) merging or maintaining this fork

This is `schmittcn/Strata`, a personal fork of `Niko1221/Strata` for one machine: an RX 6900 XT (gfx1030, 16 GB) with
a Ryzen 9 5950X on Linux, using ROCm. Upstream's own docs (`AGENTS.md`, `docs/`) still apply; this file only adds
what is different here. It exists only in the fork. Never send it upstream, and never edit `AGENTS.md` for fork
matters (upstream rewrites it every release).

## Branches

- `upstream/main` is the source of truth. `local` is the fork's work branch: upstream plus the patches below.
- **Update by merging:** `git merge upstream/main` into `local`. Never rebase `local` and never force-push it.
- Every patch has its own branch:
  - `pr/<name>` for patches offered upstream, branched from `upstream/main` with only their own commits;
  - `fork/<name>` for patches that stay in the fork.
  Each is merged into `local` with `--no-ff` ("Merge pr/<name> (...) into local").
- When upstream merges a `pr/` branch, there is nothing to undo: the next upstream merge brings the same change in.
  Then delete the branch and its entry below.

## Rules for fork patches

- **Keep them small and modular.** New code goes in a new file. The upstream file gets only a short hook (an include,
  a member, one call) behind a `STRATA_*` env switch that is off by default, so upstream changes near the hook rarely
  conflict.
- **A patch must pay off.** It needs an interleaved A/B on the same binary that beats noise, with identical greedy
  output. Small wins inside busy upstream files are not worth carrying.
- **Files to avoid:** `terminal/data/settings-register.json` (rewritten upstream almost daily),
  `engine/src/program/generate.cpp` (66 upstream commits in 30 days) and `AGENTS.md`. `pr/` branches still need
  their register entry, because upstream's check runs in its CI; `fork/` branches leave the register alone (the
  fork's update path does not run the check).
- Live tuning (flags, `--expert-vram`, which binary a model uses) is not in git. It lives in
  `~/.config/strata/patches.json` and is applied with `strata-switch apply`.

## What the fork carries (2026-11-28)

| Patch | Branch / commit | Status | Recheck after an upstream merge |
|---|---|---|---|
| `--kv fp8` decode attention per KV-head group (`k_attn_part8g`) | `pr/q36-attn8-gqa` | upstream PR #7397, open | Ornith 40K decode |
| strata-inkling on RDNA2: rocBLAS prompt route, tiled attention, KV splits | `pr/ink-rdna2-prompt` | upstream PR #7335, open | Inkling prompt tok/s |
| int8 expert kernels: IQ4_XS as a down format | `fa969cfd8` | upstream PR #6197, open | - |
| llama.cpp MMQ build path (reverts upstream's removal, #6269; about 30K lines of vendored `ggml-cuda`) | `5476349c4`, `3f2318154` | fork-only: Ornith prompt +40%. **The largest maintenance cost.** | Every release: does stock's prompt path match the MMQ build on Ornith? If yes, drop the revert |
| `STRATA_Q36_ROUTE_SIDE`: hybrid routing copies on a side stream (`engine/src/qwen35/q36_route_side.cuh` + 7 lines in `q36_engine.cu`) | `fork/q36-route-side` | fork-only: Ornith +4..6%, official Qwen3.6 UD-Q4_K_XL −2.3% | If `moe_hybrid_gpu` changed: Ornith on/off A/B, greedy md5 must match |
| `tools/local/strata-switch` and local setup fixes | various | fork-only tooling | - |

## How to recheck a patch

- A/B tool: `/home/chris/LLM/strata-bench/ktrace-2026-11-28/abflags.py MODEL PATCHKEY NAME=ENV[,ENV..] ...`.
  - It patches `~/.config/strata/patches.json` per arm and starts the model with `strata-switch`.
  - Each arm gets a greedy md5 and 3× 400-token decode, and patches.json is restored afterwards.
  - `EXE=<binary>` and `--arg=value` entries select the binary and its arguments.
- Kernel trace: `ktrace.c` in the same folder (an `LD_PRELOAD` roctracer shim). `rocprofv3` kernel trace works too,
  but its counter collection hangs the engine.
- Start models with `strata-switch <id>`, never with `strata-profiles start` (that runs an old installed server).
- Ornith's binary is built from `local` in `build-ornith/` and copied to `terminal/engine/strata-ornith`. Keep a
  `.bak-<date>` of the old binary.
- More measured lessons: `/home/chris/LLM/LEARNINGS.md`.
