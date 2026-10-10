# Strata setup on this PC — state & findings (CHECKPOINT)

Setup of [Strata](https://github.com/Niko1221/Strata) v0.1.41 per `docs/AI_SETUP.md`, on a
**NixOS 26.11** machine (devenv sandbox). This file is the single source of truth for
resuming — updated as each discovery is made. **Read top to bottom before acting.**

## Mission & choices

- Goal: Strata **Coder IQ1_M** (~58 GB, coding-focused per user) running locally at
  `http://127.0.0.1:8080`, then verify `/health` + a test chat.
- Server stays bound to 127.0.0.1; prefer user-level changes (no sudo available).

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

- `Strata/` — repo v0.1.41, `.venv/`, `setup.log`, `build/` (CMake build dir)
- `Strata-data/` — model files (~58 GB download **not started yet**; build fails first)
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
- [ ] Model download (~58 GB into `Strata-data/`) — **in progress** (file 1/2 ≈ 29.6 GB,
      then file 2/2; resumable).
- [x] Engine binary `Strata/engine/strata` runs as-is: its interpreter is the Nix-store
      glibc 2.42 loader (`/nix/store/lm3pknxi0ipypy3lxh1wmm8wvvavdwrn-glibc-2.42-84/lib/ld-linux-x86-64.so.2`),
      a real loader, not the musl stub ⇒ **no patchelf needed**. `strata-vision` does not
      exist (BUILD.json: `"vision": "none"`).
- [ ] Edit generated `Strata/run-coder-iq1_m.sh`: it only does `cd` +
      `exec .venv/bin/python serve/server.py --engine strata --config ... --port 8080`;
      add the two exports from the env block above (server.py itself prepends CUDA lib
      dirs to LD_LIBRARY_PATH from config `lib_dirs`, so no CUDA paths needed there).
- [ ] Start server, poll `http://127.0.0.1:8080/health`, send a test chat.

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

## Pitfalls / notes for resuming

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
- Engine binary: `Strata/engine/strata` (EXE="strata"), vision encoder
  `Strata/engine/strata-vision` (VEXE="strata-vision"). Both need patchelf after build.
- `serve/server.py` `child_env()` prepends `cfg["lib_dirs"]` to LD_LIBRARY_PATH for the
  engine process — CUDA lib paths handled at runtime by the server itself.
- Real g++ (bypassing NixOS wrapper): `/nix/store/8sjgd7q3mdks1rb7rbcv0sallhvrhai5-gcc-15.3.0/bin/g++`.
- glibc 2.44 store path: `/nix/store/h4wfwic161kxrr74jlzla5lsm28hgary-glibc-2.44-25`.
