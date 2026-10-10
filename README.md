# Strata setup on this PC — state & findings (CHECKPOINT)

Setup of [Strata](https://github.com/Niko1221/Strata) v0.1.41 per `docs/AI_SETUP.md`, on a
**NixOS 26.11** machine (devenv sandbox). This file is the single source of truth for
resuming — updated as each discovery is made. **Read top to bottom before acting.**

## Mission & choices

- Goal (superseded — see §"TARGET configuration" below): Strata **Coder IQ1_M** (~58 GB, coding-focused per user)
  running locally at `http://127.0.0.1:8080`, then verify `/health` + a test chat.
- Server stays bound to 127.0.0.1; prefer user-level changes (no sudo available).

## TARGET configuration — what the user wants the server running with (2026-10-11 00:1x)

**The user's requested run, verbatim — this is the configuration to end up with:**

```sh
./setup.sh --gpus 0,1 --family qwen --model IQ3_XXS --kv int8 --vision no --context 131072 --experimental-speed-projection off
```

Meaning of every flag, as setup reads it:

| Flag | Value | Effect on this PC |
|---|---|---|
| `--gpus 0,1` | nvidia-smi numbering | **both** cards, layers split across them: GPU 0 = RTX 5060 Ti (sm_120, 16 GB) + GPU 1 = RTX 4060 (sm_89, 8 GB) |
| `--family qwen` | full Qwen3.8-Flash-Next | **not** the `coder` family used by the run that is live now |
| `--model IQ3_XXS` | 3-bit i-quant | download **76 GB**, uses ~**43 GB RAM** (step 1 menu text) |
| `--kv int8` | 8-bit KV cache | same as the live config |
| `--vision no` | images off | no vision encoder compiled (`BUILD.json "vision": "none"`) |
| `--context 131072` | 128 k ctx | **double** the live config's 65536 |
| `--experimental-speed-projection off` | — | no experimental speed projection |

That run reached Step 4 and stopped there (CUDA toolkit not found — see §"the segfault on the last run").
Everything already done is kept, so re-running with the right env resumes at Step 4.

Consequences of this target that the rest of the file does **not** yet reflect:
- It replaces the live IQ1_M/coder/1-GPU/65536 pair — the target config's own config file is
  `Strata/strata-qwen-iq3_xxs.json`, a **new** file that needs the manual patches re-applied (fix #7 `lib_dirs`,
  `fit_max_tokens`).
- `--gpus 0,1` forces a **full engine rebuild** for `-DCMAKE_CUDA_ARCHITECTURES=120;89` (BUILD.json currently
  `"archs": [120]`, no PTX). The Hardware table's "GPU 2 … too small to share (< 12 GB min)" verdict was for the
  IQ1_M run; with this command setup printed `[ok] GPUs: GPU 0 … + GPU 1 … together`, so the 4060 is admitted here.
- ~43 GB RAM for the model + the live pair's 29 GB RSS does not fit in 63 GB: the old pair must be stopped first.
- RAM right now: 30.5 GB available of 63 GB (`free -b`), GPU 0 at 15640/16311 MiB.

## Hardware (verified)

| Item | Value | Verdict |
|---|---|---|
| GPU 1 | RTX 5060 Ti, 16 GB VRAM, **sm_120** | primary card |
| GPU 2 | RTX 4060, 8 GB (sm_89) | too small to share (< 12 GB min) |
| Driver | 615.71.09 | OK (≥ 580 for RTX 50) |
| RAM | ~62 GB | fits the model |
| Disk | ~684 GB free NVMe | plenty |
| CPU | Ryzen 9 3900X, AVX2 | OK |

## Layout

- `Strata/` — repo v0.1.41, `.venv/`, `setup.log`, `server.log`, `build/` (CMake build dir),
  `engine/strata` (built engine), `run-coder-iq1_m.sh` (start script, env baked in),
  `strata-coder-iq1_m.json` (server config)
- `Strata-data/` — model files: **download complete** (both shards + `.done` markers,
  58.4 GB); MTP draft layer extracted to `Strata-data/mtp/rt`
- `~/cuda-13.0/` — CUDA Toolkit 13.0, installed locally from NVIDIA debs (no sudo)
- `~/cuda-13.0/nvcc.sh` — nvcc wrapper (now **plain passthrough**; the rsqrt fix lives in a patched CUDA header — see §"Current blocker")
- `~/.local/bin/{cmake,ninja}` — absolute symlinks into the venv (fix #6)
- `/tmp/cudatest/` — minimal `.cu` repro files from earlier diagnosis (may still exist)

## NixOS problems found → fixes applied (all verified working)

This box: `/lib64/ld-linux-x86-64.so.2` is a **musl stub** and `ldconfig -p` is
**empty**. Every dynamically linked "generic Linux" binary fails until patched.

1. **uv managed Python** — patchelf'd with glibc 2.44 loader:
   `patchelf --set-interpreter /nix/store/h4wfwic161kxrr74jlzla5lsm28hgary-glibc-2.44-25/lib/ld-linux-x86-64.so.2 --set-rpath /nix/store/h4wfwic161kxrr74jlzla5lsm28hgary-glibc-2.44-25/lib ~/.local/share/uv/python/cpython-3.12.14-linux-x86_64-gnu/bin/python3.12`
   (`.venv/bin/python` resolves there.)
2. **pip wheels' .so deps** — empty linker cache ⇒ export `LD_LIBRARY_PATH` with 9
   64-bit Nix store libs (zlib, gcc-15 lib, bzip2, xz, zstd, libpng, libjpeg-turbo,
   libwebp, libffi). **Baked into `Strata/.venv/bin/activate`.**
   ⚠️ glibc's own lib dir must NOT be in it (shadowed system glibc once, broke nohup).
3. **Python TLS** — `export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt` (also in activate).
4. **No Linux prebuilt engine** — v0.1.41 GitHub release has Windows assets only;
   `strata-linux-x64.zip` 404s ⇒ must compile locally ⇒ needs CUDA ≥ 13 for sm_120.
5. **CUDA 13.0 without sudo** — downloaded NVIDIA ubuntu2404 `.deb`s, extracted with
   `ar`/`tar` into `~/cuda-13.0/usr/local/cuda-13.0/`: nvcc 13.0.88, cudart 13.0.96,
   cublas 13.0.2.14 (== Strata's pip wheel), nvrtc, crt, cccl, driver-dev, nvjitlink,
   nvfatbin, culibos, cuobjdump, nvtx, **libnvvm (cicc — separate package in CUDA 13!)**.
   All toolkit executables patchelf'd with the glibc 2.44 loader (re-run that loop if
   you add more debs).
6. **cmake/ninja relative path** — `setup.sh` runs python via a relative path, so
   `find_tool()` returned `.venv/bin/ninja` (relative) → CMake's scratch-dir try_compile
   failed. Fixed: absolute symlinks in `~/.local/bin` (already on PATH), which
   `shutil.which` finds first.
7. **libcuda.so.1 not found at runtime** — no system linker cache (`ldconfig -p`
   empty) and no `/usr/lib*` entry for the NVIDIA driver ⇒ the engine's cudart
   `dlopen("libcuda.so.1")` fails, and cudart reports that as
   **`CUDA driver version is insufficient for CUDA runtime version`
   (`cudaErrorInsufficientDriver`)** — misleading: it means "driver library not
   found", not "too old" (the store's libcuda is 615.71.09 / UMD 13.4, verified via
   `cuDriverGetVersion` → 13040 ≥ CUDA 13.0's requirement). Symptom: engine died at
   `native embedding: cannot pin 322 MiB: ... nor place it in VRAM`, with
   `PCIe probe failed` just before (same root cause). Fixed: added
   `/nix/store/pd39xk8fwx0sk2ay4spk8gvlgsqxbxkx-nvidia-x11-615.71.09/lib` to
   `lib_dirs` in `strata-coder-iq1_m.json` — server.py's `child_env()` prepends
   `lib_dirs` to the engine's `LD_LIBRARY_PATH`. Verified: engine now passes the PCIe
   probe (14.5 GB/s → pcie_frac 0.40) and pins the 322 MiB embedding, then proceeds to
   weight upload (OOM there only while llama-server still holds ~13.3 GB VRAM).

## Environment for running setup (canonical resume command)

```sh
cd /home/ivan/strata-install/Strata
export LD_LIBRARY_PATH="/nix/store/wgw25d181h0qks7qsfp1bh7c5nd3f0s7-zlib-1.3.2/lib:/nix/store/604gsr59rj7dzd0nrhp143rpvf7gyiaz-gcc-15.3.0-lib/lib:/nix/store/l509wk1p0c5sh0i4pvfd9d018pzmjnd8-bzip2-1.0.8/lib:/nix/store/cjippm7n89ac2z3rxdghns4p02s6g09m-xz-5.8.3/lib:/nix/store/8ik1d1r4l2jzm9mjh6bc0a13yczx62wg-zstd-1.5.7/lib:/nix/store/qc7wwg64ggan8nzgrlal5dy16gyx6c1l-libpng-apng-1.6.58/lib:/nix/store/wfg9zbfa46hjr2qa7zb8yc7909si2w5l-libjpeg-turbo-3.1.4.1/lib:/nix/store/4ag6jkbsdwq78jh74qidn7crm68cnwdp-libwebp-1.6.0/lib:/nix/store/3r5wfb1dl3sfknvy1yringvmap0hxj4r-libffi-3.8.0/lib"
export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
export STRATA_NVCC=/home/ivan/cuda-13.0/nvcc.sh
nohup ./setup.sh --yes --family coder --model IQ1_M --no-start > setup.log 2>&1 &
```

(`LD_LIBRARY_PATH` + `SSL_CERT_FILE` are already in `.venv/bin/activate`; the command
above is the canonical one. Setup is resumable — finished steps skip.)

## Progress so far (latest run)

- [x] CMake configure succeeds; **full build done: 109/109 targets**, engine linked.
- [x] Strata's own `.cu` files now compile (rsqrt fix applied — see "Current blocker").
- [x] Model download complete: both shards + `.done` markers (58.4 GB); MTP draft layer
      extracted to `Strata-data/mtp/rt`.
- [x] Engine binary `Strata/engine/strata` runs as-is: its interpreter is the Nix-store
      glibc 2.42 loader (`/nix/store/lm3pknxi0ipypy3lxh1wmm8wvvavdwrn-glibc-2.42-84/lib/ld-linux-x86-64.so.2`),
      a real loader, not the musl stub ⇒ **no patchelf needed**. `strata-vision` does not
      exist (BUILD.json: `"vision": "none"`).
- [x] Edited generated `Strata/run-coder-iq1_m.sh`: added the two exports
      (LD_LIBRARY_PATH + SSL_CERT_FILE) before the exec line (server.py itself prepends
      CUDA lib dirs to LD_LIBRARY_PATH from config `lib_dirs`, so no CUDA paths needed there).
- [x] Engine starts and initialises CUDA after fix #7 (libcuda on the engine's
      library path); it loads the native embedding + pack and proceeds to weight
      upload — only remaining blocker is llama-server's VRAM.
- [x] **Server started, `/health` ok, chat works — DONE (2026-10-10 21:33).** llama-server
      was stopped by hand, then `./run-coder-iq1_m.sh` started: server.py PID 74241 →
      engine PID 74287, bound to 127.0.0.1:8080. `/health` →
      `{"status":"ok","model":"qwen3.8-flash-next-coder-iq1_m","loaded":true}`; test chat
      and this agent session now run ON Strata (~19.5 tok/s decode, prefill ~1513 tok/s,
      expert-cache 51.4% hits, engine uses ~9 GB VRAM of the 5060 Ti). ⚠️ Stopping the
      engine now kills this agent session. (Started twice by accident; the orphan pair
      killed — see Pitfalls.)
- [x] **Live pair 2026-10-10 22:20: server.py 85701 → engine 85748** (started 22:14:08, owns
      :8080, serves this session) with `--max-context 65536 --kv int8 --kv-resident 32768` and
      `"fit_max_tokens": true` now LIVE. Restart issues found and documented — see §"Issues
      found on the 2026-10-10 22:14 restart". **Superseded by the 22:34 restart — see §"Restart
      2026-10-10 22:34".**

## Current blocker — RESOLVED (fix applied & verified)

**RESOLVED.** Applied exactly the recommended fix below:
1. Patched `~/cuda-13.0/usr/local/cuda-13.0/targets/x86_64-linux/include/crt/math_functions.h`:
   `rsqrt`/`rsqrtf` are now declared
   `extern "C" __DEVICE_FUNCTIONS_DECL__ __device_builtin__ ... noexcept(true)`
   (matches glibc's IEC_60559_FUNCS_EXT_C23 decl; `__THROW` == `noexcept(true)` in C++17).
2. Reverted `~/cuda-13.0/nvcc.sh` to plain passthrough (`_GNU_SOURCE` restored).
3. Verified: `/tmp/cudatest/test_fix.cu` (includes cuda_runtime.h, cmath, cwchar, mutex,
   atomic; calls rsqrt/rsqrtf host+device) compiles clean with
   `nvcc.sh -std=c++17 -arch=sm_120`.
4. Full Strata build then succeeded: 109/109 targets, engine linked and runs (`--help` OK).

Extra verification done while patching (refines the diagnosis below):
- glibc 2.42's C23 guard declares scalar `rsqrt` (bits/mathcalls.h:206) — the **only**
  real conflict. `sinpi/cospi/tanpi` are declared there as SIMD vector variants only
  (`__MATHCALL_VEC`), so CUDA's scalar versions never conflict; glibc 2.42 declares no
  `rsqrtf` at all; `compoundn/pown/powr/rootn` are glibc-only (CUDA never declares them).
- If the CUDA debs are ever re-extracted, re-apply the header patch (two lines, marked
  "NixOS patch" in math_functions.h).

Diagnosis below kept for reference.

### Error class 1 — rsqrt conflict (fixed by `-U_GNU_SOURCE`, but that fix is wrong)

With plain nvcc (which force-injects `-D_GNU_SOURCE` into the host compile):
```
bits/mathcalls.h(206): error: exception specification is incompatible with that of
previous function "rsqrt" (declared at line 629 of .../crt/math_functions.h)
```
Root cause chain (verified):
- nvcc force-includes `cuda_runtime.h` → CUDA's `crt/math_functions.h` declares
  `rsqrt`/`rsqrtf` in **global scope, C++ linkage, no exception spec** (lines 629/653).
- nvcc passes `-D_GNU_SOURCE` to the host compiler.
- `_GNU_SOURCE` makes glibc 2.42's `bits/mathcalls.h` (line 192:
  `#if __GLIBC_USE(IEC_60559_FUNCS_EXT_C23)`) declare `rsqrt`/`rsqrtf` in **extern "C",
  with `__THROW`** (line 206). → incompatible redeclaration, hard error under GCC 15.
- CUDA's other math fns (sqrt, fabs, …) are declared inside `namespace std { }` in
  math_functions.h, so they never conflict — **only global-scope rsqrt/rsqrtf do**.
- On Ubuntu this never triggers (older glibc / no `_GNU_SOURCE` by default).

### Error class 2 — `-U_GNU_SOURCE` breaks libstdc++ POSIX declarations (NEW)

Removing `_GNU_SOURCE` fixed class 1 but Strata's `.cu` files then fail with:
```
cwchar(150): the global scope has no "fwide" / "fwscanf" / "swscanf" / "wscanf"
bits/c++locale.h(52): identifier "uselocale" is undefined / "__locale_t"
gthr-default.h(815): "pthread_mutex_timedlock" / "PTHREAD_MUTEX_RECURSIVE" /
                     "pthread_mutexattr_settype" undefined
bits/std_mutex.h: "clockid_t" / "pthread_cond_clockwait" undefined
bits/atomic_wait.h(114): "syscall" is undefined
pinned.cu(714): "fseeko" is undefined
```
Root cause: nvcc uses strict `-std=c++17` (no `_DEFAULT_SOURCE`), and with
`_GNU_SOURCE` removed, glibc's feature-test guards declare almost nothing, so libstdc++
headers reference undeclared POSIX identifiers. Note `syscall` is **GNU-only** in
glibc (`__USE_GNU`), so plain `_POSIX_C_SOURCE`/`_XOPEN_SOURCE` likely won't cover it —
a partial feature-macro fix is probably insufficient.

### Key structural facts (for the fix)

CUDA header: `~/cuda-13.0/usr/local/cuda-13.0/targets/x86_64-linux/include/crt/math_functions.h`
- Line ~120–130: `__NV_GLIBC_PROVIDES_IEC_60559_FUNCS` = 1 only if
  `__GNUC_PREREQ(2,41) && (__GLIBC_USE_ISOC23 || __STDC_WANT_IEC_60559_FUNCS_EXT__)`.
  In our C++ build both are false ⇒ macro = **0** (so its existing guards don't help us).
- Line 158: `extern "C" {` … closes line 289 (only a small section).
- Line 629: `extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ double rsqrt(double x);`
- Line 653: `extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ float rsqrtf(float x);`
- Line 2567: macro used to give sinpi/cospi a `__THROW` spec when glibc provides them.
- `__DEVICE_FUNCTIONS_DECL__` = `__host__ __device__` (non-RTC, line ~5465).

glibc headers (read-only Nix store): `/nix/store/lbjwxax9n0457lgd83rqwpd1l9lgfl7r-glibc-2.42-84-dev/include/`
- `bits/mathcalls.h` line 192: `#if __GLIBC_USE (IEC_60559_FUNCS_EXT_C23)` … line 206:
  `__MATHCALL (rsqrt,, (_Mdouble_ __x));` (extern "C", `__THROW`).
- Exact expansion of `__GLIBC_USE(IEC_60559_FUNCS_EXT_C23)` in features.h **not yet
  verified** — empirically `_GNU_SOURCE` triggers it.

### Recommended fix (APPLIED — see note at top of this section)

1. **Patch the local CUDA header** (writable copy!) `math_functions.h`: make lines 629
   and 653 compatible with glibc's declaration, e.g.:
   ```c
   extern "C" __host__ __device__ __device_builtin__ double rsqrt(double x) noexcept(true);
   extern "C" __host__ __device__ __device_builtin__ float  rsqrtf(float x) noexcept(true);
   ```
   (matches glibc's C linkage + `__THROW`; keeps `__device__` for device code).
   Alternative: wrap both in `#if !defined(_GNU_SOURCE)` and rely on glibc's own
   declaration (slightly riskier for device-code builtin mapping — try the first form).
2. **Revert the wrapper** `~/cuda-13.0/nvcc.sh` to plain passthrough (remove
   `-Xcompiler -U_GNU_SOURCE`) so `_GNU_SOURCE` is back and libstdc++ works:
   ```sh
   #!/bin/sh
   exec /home/ivan/cuda-13.0/usr/local/cuda-13.0/bin/nvcc "$@"
   ```
3. **Verify** with a minimal `.cu` that includes `<cuda_runtime.h>`, `<cwchar>`,
   `<mutex>`, `<cmath>` and calls `rsqrt(1.0)` — must compile cleanly (check the .o
   exists; nvcc flag syntax is `-std=c++17`, NOT `--c++17`).
4. **Resume setup** with the canonical command above. If further `.cu` files fail with
   new error classes, append them to this README and iterate — only Strata's own `.cu`
   files are affected so far; ggml (C/C++) compiles fine.

Fallbacks if the header patch misbehaves:
- Copy glibc's include tree to a writable dir, remove rsqrt/rsqrtf from
  `bits/mathcalls.h`, add `-Xcompiler -isystem <that-dir>` in the wrapper.
- Or use an older glibc dev package (e.g. 2.39) headers via `-isystem` if its math.h
  lacks the C23 rsqrt declaration (unverified which version added it).

## Starting the server (DONE — restart recipe)

The server is RUNNING (see §"Progress so far"). To restart it (e.g. after a reboot, or to
change args): stop the current pair first — ⚠️ that ends any agent session running on it —
then:

```sh
# 1. stop the running pair BY PID (server.py first: it owns :8080 and restarts a dead
#    engine on its own, so killing the engine alone can bring a new one back)
ss -ltnp | grep ':8080'                 # the LISTEN line names the server.py PID
ps -eo pid,ppid,args | grep -E 'serve/server\.py|engine/strata' | grep -v grep   # pair + PPID
kill <server_py_pid>; sleep 2; kill <engine_pid>; sleep 3
kill -9 <server_py_pid> <engine_pid> 2>/dev/null

# 2. wait until the VRAM is actually back (-d is a DISPLAY keyword, not a GPU selector:
#    `nvidia-smi -d <gpu name>` errors "Invalid combination of input arguments"; one line per GPU
nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits   # → "0" / "13"
#    who still holds it, if it will not drop:
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# 3. start ONLY when the port is free (a second pair steals no port but steals VRAM:
#    its engine dies with "cudaMalloc(...) for the weight arena failed")
ss -ltnp | grep ':8080' || echo free
cd /home/ivan/strata-install/Strata
nohup ./run-coder-iq1_m.sh > server-$(date +%H%M).log 2>&1 </dev/null &
tail -f server-*.log          # cold first load: minutes. warm (58 GB in page cache):
                              # ~20 s — the engine says "loaded 23.42 GiB at 2.93 GiB/s"

# 4. verify
curl -s http://127.0.0.1:8080/health        # → {"status":"ok","max_context":65536,...}
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"coder","messages":[{"role":"user","content":"Reply with exactly: OK"}]}'
```

Notes:
- `./setup.sh` (no flags) also just starts the server — same as the run script.
- API endpoints: OpenAI-compatible `http://127.0.0.1:8080/v1`, Anthropic-style
  `http://127.0.0.1:8080/v1/messages`; any API key, model name can be anything.
- If the PC freezes / screen goes black once when the model loads (#779): re-run setup
  with `--vram-reserve-mib 1500`.
- Several concurrent agents/clients: add `--conversation-cache-mib 8192` to the config's
  args (otherwise each re-reads ~90% of its prompts; #882 #440).
- The `"fit_max_tokens": true` now in `strata-coder-iq1_m.json` only takes effect from the NEXT
  start (the run config is read once, when `serve/server.py` builds the `Service`) — restarting
  is the only way to apply it, and it ends the session running on the server. It has been applied
  this way since 2026-10-10 22:14; see §"Request-level fix" and §"Issues found on the 2026-10-10
  22:14 restart".

## Request-level fix — 400 `prompt + max tokens exceeds the context` (fixed 2026-10-10 21:58)

The agent session running on this server (pi, `llama-cpp/qwen3.8-flash-next-coder-iq1_m`) got:

```
Error: 400: {"type":"invalid_request_error","message":"prompt (51198 tokens) + max tokens (16384)
exceeds the context (65536); requests are never truncated. Send a smaller max_tokens (at most 14330 here),
or add \"fit_max_tokens\": true to the model's strata-<model>.json to shorten it to the room left (#545)"}
```

**Cause** — pi's llama.cpp extension always asks for `max_tokens = min(16384, n_ctx)` = 16384
(`DEFAULT_MAX_TOKENS` in `/tmp/jiti/pi-llama-index.*.mjs`), and Strata refuses instead of truncating
(`serve/server.py` `prepare()`, #545). Once a session's prompt passes `65536 - CTX_SLACK - 16384` ≈ 49 k
 tokens, every request is refused — the session looks alive but stalls. pi's compaction
(`triggerThreshold: 0.75` → 49152 tokens) runs between turns, not inside a long tool-heavy turn, so the
prompt can pass the threshold before the next compaction.

**Fix applied** — added `"fit_max_tokens": true` to `Strata/strata-coder-iq1_m.json`: the server clamps the
requested output cap to the room left (`room = max_context - CTX_SLACK - prompt`) instead of answering 400.
It is a `runconfig.EDITABLE` key (Strata's Settings page `POST /config` and a re-run of `setup.py` both keep
it); `--fit-max-tokens` is the CLI equivalent, and `serve/test_server.py` (PR #24) covers the clamp. A prompt
that leaves **no** room at all is still refused — that is the honest answer (compact or restart the session).

**Takes effect at the NEXT start only** — the file was patched at 21:58 while the old pair (server.py 76675
→ engine 76721) still refused; the 22:14 restart made it live (pair 85701/85748 — see §"Issues found on
the 2026-10-10 22:14 restart"). Do NOT restart while an agent session is still running on the server: it
ends that session (this one runs on Strata).

Alternatives, if ever preferred: raise `--max-context` (more KV RAM), or make the client ask for less
(`max_tokens ≤ room`, e.g. a `modelOverrides` `maxTokens` for this model in `~/.pi/agent/models.json`).
`fit_max_tokens` is preferred: server-wide, client-agnostic, and it never truncates a reply that fits.

## Issues found on the 2026-10-10 22:14 restart (all verified, none open)

Restarting to make `fit_max_tokens` live surfaced five things worth keeping:

1. **Two pairs raced.** The user's restart (server.py **85701** → engine **85748**, started
   22:14:08) and my scripted one (server.py 85139 → engine at engine-log line 385, 22:14:27)
   overlapped by ~19 s. Mine lost: its engine printed
   `cudaMalloc(1475120640) for the weight arena failed (out of memory): 681 MiB of 15938 MiB
   VRAM free on this GPU. The arena is allocated first, before the KV and expert caches:
   another program (or an engine that is still exiting) holds the rest`, then server.py raised
   inside `StrataEngine(...)` (server.py:5720) and exited. The user's pair loaded fine
   (`loaded 23.42 GiB at 2.93 GiB/s`, expert cache 4257 slots / 8.10 GiB, `394 MiB of VRAM
   free with everything loaded`) and is what serves this session now. **Check `ss -ltnp | grep
   :8080` and the VRAM query before starting, not after.**
2. **`nvidia-smi -d <gpu name>` is not a GPU selector** (driver 615.71.09): it prints
   `Invalid combination of input arguments. Specify -q/--query and -d/--display to run a filtered
   query.` — `-d` is a *display* keyword, not a GPU selector, so a `while` loop built on it never
   breaks and just stalls ~2 min. Use `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`
   (one line per GPU, 5060 Ti first: `15544` / `13` while the engine runs, `0` when its VRAM is gone)
   or `--query-compute-apps=pid,process_name,used_memory` to see who holds it.
3. **server.py auto-restarts its engine** — `restart()` (serve/server.py:845) with
   `RESTART_RETRY_S = 15.0`, commented "a dying engine's VRAM may take a while to come back".
   So killing only the engine can bring a new one back; kill **server.py first** (it owns :8080),
   then its engine child.
4. **Two processes writing the same `server.log` interleave mid-line** — the traceback from the
   dead pair and the live pair's `ready: http://127.0.0.1:8080/v1` spliced into one line. Give
   each start its own log name (`server-$(date +%H%M).log`) when restarting from a script.
5. **`/health` reports more than the README claimed:**
   `{"status":"ok","max_context":65536,"model":"qwen3.8-flash-next-coder-iq1_m","images":false,
   "api_key":false,"loaded":true,"service":"strata"}` — `max_context` is the live ctx, so a
   client can size its `max_tokens` from it instead of guessing.

Cheap way to test `fit_max_tokens` **without** restarting: ask for more than the context —
`{"model":"coder","messages":[{"role":"user","content":"Reply with exactly: OK"}],"max_tokens":65530}`
→ 400 `prompt (57 tokens) + max tokens (65530) exceeds the context (65536)` before the fix, 200
`"content":"OK"` after it (clamped to the room left). No 50 k-token prompt needed.

Also seen while restarting (harmless, engine self-reports): `PCIe probe failed -> pcie_frac
0.55` on a start whose libcuda was missing (fix #7), `this CPU has no AVX-512: the expert
kernels run on AVX-2`, `MAP_HUGETLB unavailable ... transparent huge pages requested`, and
`prefill: the CPU share is ON ... answers can differ slightly from 0.1.40.3` — all expected on
this box; `STRATA_PREFILL_CPU_SHARE=0` turns the last one off.

## Restart 2026-10-10 22:34 — the user rebooted the server; state re-verified (all healthy)

The user stopped the 22:14 pair and started a new one at **22:34:01**: **server.py 92970 → engine 93016**
(`ps -o lstart` shows both at 22:34:01, engine PPID 92970). This agent session (pi session
`01a125d1-0689-76c6-896c-e8500cee636c`, started 22:36:58) is a **fresh** session running on that pair —
the restart ended the previous one, exactly as the warning above says. The **machine** was not rebooted
then (`last -x`: last reboot `Sat Oct 10 09:02`, uptime 13:36 at 22:38) — only the Strata pair.

Verified after the restart (all OK, nothing needed re-applying):
- `ss -ltnp | grep :8080` → exactly ONE LISTEN, `127.0.0.1:8080`, pid **92970**; no orphan pair, no
  second engine anywhere in `ps`.
- Warm reload: `loaded 23.42 GiB at 2.90 GiB/s` (15 s — the 58 GB was still in the page cache from the
  previous run; `Cached: 26 GB` now), PCIe probe 14.5 GB/s → `pcie_frac 0.40` (fix #7 still working),
  expert arena `cudaHostRegister PORTABLE ok`, expert cache **4211 slots / 8.02 GiB** pre-filled in 0.6 s,
  `428 MiB of VRAM free with everything loaded` (then 221–395 MiB across the 1–6-token verify windows).
- GPU: 5060 Ti `15566/16311 MiB` used, `--query-compute-apps` → engine 93016 holds `14576 MiB` (+ nautilus
  73 MiB), 4060 idle (13 MiB). Engine RSS 29.0 GB.
- `/health` → `{"status":"ok","max_context":65536,"model":"qwen3.8-flash-next-coder-iq1_m",…, "loaded":true,
  "service":"strata"}`; test chat 200 `"content":"OK"`.
- `fit_max_tokens` still LIVE (re-tested with the cheap recipe): `max_tokens: 65530` on a 57-token prompt →
  **200** `"content":"OK"`. `strata-coder-iq1_m.json` mtime 22:02, `fit_max_tokens = True`, `lib_dirs` still
  lists the nvidia-x11 dir.
- All NixOS fixes survived: glibc-2.44 / nvidia-x11-615.71.09 / glibc-2.42 store dirs present, `ldconfig -p`
  still **empty (0 lines)**, engine interpreter still the 2.42 loader, uv python still patchelf'd to the 2.44
  loader, `~/.local/bin/{cmake,ninja}` symlinks intact, `.venv/bin/activate` exports intact, `nvcc.sh` still
  plain passthrough, `math_functions.h` "NixOS patch" lines still at 629/657. `/tmp/cudatest/test_fix.cu`
  + `test_fix.o` still there (/tmp was not touched by a server restart — only by a machine reboot).
- Steady state on this session: prefill 1160–1330 tok/s (11.7 k of 14.1 k prompt tokens reused), decode
  **36–38 tok/s**, expert-cache hit 78–85%, KV streaming 99.3–99.7% VRAM hits, suffix drafts ~6/8 accepted.

**NEW neighbour on this box** (found while re-checking the port): **open_webui** runs as root (PID 2137,
started at boot 09:02:14, `uvicorn open_webui.main:app --host 0.0.0.0 --port 8080`). It holds **no** :8080
socket now (`ss -ltnp` has no `0.0.0.0:8080` line), but it is a boot-time service on the same port — after a
real machine reboot it may bind :8080 before Strata. Never assume the port is Strata's: after every start
check `curl -s http://127.0.0.1:8080/health` returns Strata's **JSON** (open_webui answers HTML/404 there)
and `ss -ltnp | grep 8080` shows which PID owns it.

## 2026-10-11 00:0x — the segfault on the last run: it was PI, not Strata

The user's last agent run died with a SIGSEGV. **Strata did not crash** — the agent process (`pi`) did.

Evidence (`coredumpctl`):
```
Sun 2026-10-11 00:02:00 AEST  PID 104363  UID 1000  SIGSEGV  present  /nix/store/...-nodejs-slim-24.20.0/bin/node  24.9M
```
`coredumpctl info 104363`: `Command Line: pi`, `Control Group: .../app-niri-alacritty-103901.scope`,
core `core.pi.1000.8bad9d4c….104363….zst` (24.9 MB). Stack of the faulting thread, innermost first:
`v8::GlobalHandles::Destroy` ← `ManagedObjectFinalizer::WeakCallbackInfo` ← `GlobalHandles::InvokeFirstPassWeakCallbacks`
← `Heap::PerformGarbageCollection` ← `Heap::CollectGarbage` ← `PushAllRegistersAndIterateStack` ← `MinorGCJob::Task::RunInternal`
← `node::PerIsolatePlatformData::RunForegroundTask` ← `uv__async_io` / `uv__io_poll`.
So it died **inside node's own minor-GC global-handle teardown**, reached from a libuv callback — the usual signature of
a native addon holding a bad `v8::GlobalHandle`. The core's module list includes `clipboard.linux-x64-gnu.node`
(a native addon pi loads); everything else listed is node's own deps. Nothing Strata-related.

- No `strata` / `server.py` core anywhere near that time: the only `core.llama-server.*` cores are from **Oct 4**
  (old llama.cpp experiments); the rest on this box are brave / codium / Discord / krita / nautilus.
- The crashed session is pi session `01a12611-cd34-779c-bbbe-dbd6653e06f0` (started 2026-10-10 23:47:43 local,
  105 messages, last entry 14:01:50Z = **00:01:50 local**, 9 s before the core's timestamp 00:01:59).
- The Strata pair **103575 (server.py) → 103621 (engine)**, started 23:47:17, survived the crash and is still
  serving: `ss -ltnp` → one LISTEN on `127.0.0.1:8080` pid 103575; `/health` → `{"status":"ok",…,"loaded":true}`;
  both logs still being written at 00:11. Engine RSS 29.1 GB, GPU 0 `15640/16311 MiB`, GPU 1 idle (13 MiB).
- Practical lesson: a pi/node segfault ends the **session**, not the **server**. Check the pair before doing
  anything — here nothing had to be restarted, only the session was lost.

### What that crashed session was doing (recovered from its jsonl tail)

Its last ~10 minutes were probing the **TARGET** setup invocation above, and it never got past Step 4:

```
=== Step 4: the Strata engine ===
  [ok] llama.cpp 3cf0325 (gguf-py, ggml, mtmd)
  The engine has to be compiled for your PC, which needs: the NVIDIA CUDA Toolkit 13.0.
  [X]  missing: the NVIDIA CUDA Toolkit 13.0 (the automatic install is only done on Ubuntu/Debian)
Setup stopped. Fix the item above and run it again - everything already done is kept and skipped.
```

**Root cause** (`Strata/setup.py`: `install_build_tools` ~3026, `find_nvcc` ~1235): with no `STRATA_NVCC` in the
environment, `find_nvcc()` only tries `shutil.which("nvcc")`, then `$CUDA_PATH/bin/nvcc` and `$CUDA_HOME/bin/nvcc`,
then `/usr/local/cuda*/bin/nvcc` and `/opt/cuda*/bin/nvcc`. Our toolkit lives at
`~/cuda-13.0/usr/local/cuda-13.0/bin/nvcc` — a **home** directory, matched by none of those globs — so `nvcc is None`,
`missing` gets "the NVIDIA CUDA Toolkit 13.0", and since `shutil.which("apt-get") is None` on NixOS it hard-fails
with exactly that message. Nothing is broken; the env exports from §"Environment for running setup" were simply
missing in that shell.

**Fix (verified, not yet re-run)**: re-run the same command with the canonical exports —
`STRATA_NVCC=/home/ivan/cuda-13.0/nvcc.sh` is the only nvcc considered, and
`/home/ivan/cuda-13.0/nvcc.sh --version` prints `Cuda compilation tools, release 13.0, V13.0.88`,
which is what `find_nvcc` greps (`release (\d+)\.(\d+)` → (13,0)); build 88 also clears `CUDA_SM120_FIXED_BUILD = 86`.
(`CUDA_HOME=/home/ivan/cuda-13.0/usr/local/cuda-13.0` would work too, but `STRATA_NVCC` is the documented, proven path.)

**Three things that run will do, all of which conflict with the live pair — read before starting it:**
1. **Full engine rebuild.** `engine/BUILD.json` has `"archs": [120]` and no `ptx`; `--gpus 0,1` adds the 4060
   (sm_89), so `new_arch = local and not set(archs) <= built` is True → cmake is re-run with
   `-DCMAKE_CUDA_ARCHITECTURES=120;89` (10–20 min) and `Strata/engine/strata` is **overwritten** while the
   IQ1_M pair still runs on the old inode. `toolkit_root_defs(nvcc)` will also pass
   `-DCUDAToolkit_ROOT=/home/ivan` (`Path(nvcc).resolve().parent.parent` of `cuda-13.0/nvcc.sh`) — that is what
   the 20:29 build already did and it linked fine, so it is cosmetic, not a blocker.
2. **VRAM/RAM.** The live pair holds 15.6 GB of 16.3 GB on GPU 0 and 29.1 GB RSS; `free -b` now shows only
   **30.5 GB available** of 63 GB. IQ3_XXS is quoted at ~43 GB RAM, so the old pair **must be stopped first**
   (by PID, server.py first — see the restart recipe), which ends this agent session.
3. **It will start a server.** The command has no `--no-start`, so the last step binds :8080 and starts a second
   pair; with the old pair still loaded that engine dies on the weight-arena `cudaMalloc`. Add `--no-start`, then
   start deliberately once the port and VRAM are free.

Also note the new config file will be `Strata/strata-qwen-iq3_xxs.json` (a **new** file, not the existing
`strata-coder-iq1_m.json`), so the two manual patches from §"NixOS problems found" have to be re-applied to it
once setup writes it: `lib_dirs` + the nvidia-x11 dir (fix #7) and `fit_max_tokens = true`.

Disk is fine: 617 GB free on `/`, `Strata-data/models` is 55 GB, IQ3_XXS downloads 76 GB.

## Pitfalls / notes for resuming

- Don't start the server twice: you get TWO server.py + TWO engine processes; only one
  pair binds 8080, the orphan pair silently burns ~20 GB RAM + ~6 GB VRAM. Find the owner
  with `ss -ltnp | grep 8080` (server.py PID) and its engine child (PPID), then `kill`
  the ORPHAN pair by explicit PID — server.py first, then its engine (else server.py may
  respawn one). Never blind-`pkill -f 'serve/server.py'` while an agent session runs on
  the server: it kills the serving one too.

- A second pair started while the first still holds VRAM dies with
  `cudaMalloc(...) for the weight arena failed ... another program (or an engine that is
  still exiting) holds the rest` — that is the VRAM message above, not a model problem.
  Free the port and the VRAM **before** starting, and never assume `pkill` finished.

- `nvidia-smi -d <gpu name>` is not a GPU selector (driver 615.71.09): it errors
  `Invalid combination of input arguments ... Specify -q/--query and -d/--display`. A wait
  loop built on it never terminates. Use `--query-gpu=...` / `--query-compute-apps=...` instead.

- The old `-U_GNU_SOURCE` wrapper hack is gone (it broke libstdc++, error class 2);
  the permanent fix is the patched CUDA header. `_GNU_SOURCE` is back and fine now.
- Don't wipe `Strata/build/`; setup re-passes all `-D` flags each run, overriding stale
  CMake cache values.
- Watch progress: `tail -f Strata/setup.log`. Silence during compile is normal (ninja +
  cicc are slow); don't kill it.
- If a new "cannot run dynamically linked executable" / stub-ld error appears for some
  binary, the fix is always: patchelf with the glibc 2.44 loader + rpath (fix #1).
- Model download ~58 GB; resumable if interrupted.
- GPU selection should default to the RTX 5060 Ti (most VRAM); images off; ctx 65536;
  KV cache 8-bit (setup defaults, already accepted with --yes).
- CMake build command (setup.py ~line 3221): `cmake -G Ninja -DCMAKE_MAKE_PROGRAM=<ninja>
  -S <Strata> -B <build> -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON
  -DSTRATA_BUILD_TESTS=OFF -DCMAKE_CUDA_ARCHITECTURES=120 -DCMAKE_CUDA_COMPILER=<nvcc>
  -DCUDAToolkit_ROOT=<toolkit> -DSTRATA_GGML_DIR=<llama.cpp>`.
- Engine binary: `Strata/engine/strata` (EXE="strata"); no vision encoder in this build
  (BUILD.json `"vision": "none"`). **No patchelf needed** — its interpreter is the
  Nix-store glibc 2.42 loader, which works (verified with `--help`).
- `serve/server.py` `child_env()` prepends `cfg["lib_dirs"]` to LD_LIBRARY_PATH for the
  engine process — CUDA lib paths handled at runtime by the server itself.
- Real g++ (bypassing NixOS wrapper): `/nix/store/8sjgd7q3mdks1rb7rbcv0sallhvrhai5-gcc-15.3.0/bin/g++`.
- glibc 2.44 store path: `/nix/store/h4wfwic161kxrr74jlzla5lsm28hgary-glibc-2.44-25`.

Live pair as of 2026-10-11 00:15: server.py **103575** → engine **103621** (both started 2026-10-10 23:47:17,
ownes :8080, serving this session; RSS 29.1 GB, GPU 0 15640/16311 MiB). That pair still runs the **old** config
(coder IQ1_M, one GPU, ctx 65536) — the **TARGET** config in §"TARGET configuration" is not up yet: its setup run
stopped at Step 4 (CUDA toolkit not found). The pi session that ran on this pair (`01a12611…`, 23:47:43) died of a
**node/pi SIGSEGV at 00:01:59** — see §"the segfault on the last run" — the pair itself stayed healthy. The 22:34
pair (92970/93016) was stopped by the user's restart at 23:47; the 22:14 pair (85701/85748) by the one before it.
