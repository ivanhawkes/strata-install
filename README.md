# Strata setup on this PC — state & findings (CHECKPOINT)

Setup of [Strata](https://github.com/Niko1221/Strata) v0.1.41 per `docs/AI_SETUP.md`, on a
**NixOS 26.11** machine (devenv sandbox). This file is the single source of truth for
resuming — it is updated as each discovery is made.

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
- `Strata-data/` — model files (created by setup; ~58 GB download not started yet)
- `~/cuda-13.0/` — CUDA Toolkit 13.0, installed locally from NVIDIA debs (no sudo)
- `~/cuda-13.0/nvcc.sh` — **nvcc wrapper (use this as STRATA_NVCC)**
- `~/.local/bin/{cmake,ninja}` — absolute symlinks into the venv (see fix #6)

## NixOS problems found → fixes applied

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
   failed ("no such file or directory"). Fixed: absolute symlinks in `~/.local/bin`
   (already on PATH), which `shutil.which` finds first.
7. **rsqrt header conflict (the big one)** — nvcc's host compile of any `.cu` file
   fails with GCC 15 + glibc 2.42 headers:
   ```
   bits/mathcalls.h(206): error: exception specification is incompatible with that of
   previous function "rsqrt" (declared at line 629 of .../crt/math_functions.h)
   ```
   Root cause chain (fully diagnosed, repro in `/tmp/cudatest`):
   - nvcc force-includes `cuda_runtime.h` → CUDA's `crt/math_functions.h` declares
     `rsqrt/rsqrtf` **without** noexcept;
   - nvcc passes **`-D_GNU_SOURCE`** to the host compiler (verified: it appears as a
     `<command-line>` define in the preprocessed stream);
   - `_GNU_SOURCE` enables glibc's `IEC_60559_FUNCS_EXT_C23` guard, which declares
     `rsqrt/rsqrtf` **with** `noexcept(true)` → incompatible redeclaration, hard error.
     (On Ubuntu this never triggers — that's why Strata builds there.)
   - **Fix: `-Xcompiler -U_GNU_SOURCE`.** Verified: minimal `.cu` compiles cleanly with it.
   - Applied via wrapper `~/cuda-13.0/nvcc.sh`:
     `exec /home/ivan/cuda-13.0/usr/local/cuda-13.0/bin/nvcc -Xcompiler -U_GNU_SOURCE "$@"`
     → **`STRATA_NVCC=/home/ivan/cuda-13.0/nvcc.sh`** (setup.py passes it as
     `-DCMAKE_CUDA_COMPILER`, so every CUDA compile gets the flag).

## Environment for running setup (all verified)

```sh
cd /home/ivan/strata-install/Strata
export LD_LIBRARY_PATH="/nix/store/wgw25d181h0qks7qsfp1bh7c5nd3f0s7-zlib-1.3.2/lib:/nix/store/604gsr59rj7dzd0nrhp143rpvf7gyiaz-gcc-15.3.0-lib/lib:/nix/store/l509wk1p0c5sh0i4pvfd9d018pzmjnd8-bzip2-1.0.8/lib:/nix/store/cjippm7n89ac2z3rxdghns4p02s6g09m-xz-5.8.3/lib:/nix/store/8ik1d1r4l2jzm9mjh6bc0a13yczx62wg-zstd-1.5.7/lib:/nix/store/qc7wwg64ggan8nzgrlal5dy16gyx6c1l-libpng-apng-1.6.58/lib:/nix/store/wfg9zbfa46hjr2qa7zb8yc7909si2w5l-libjpeg-turbo-3.1.4.1/lib:/nix/store/4ag6jkbsdwq78jh74qidn7crm68cnwdp-libwebp-1.6.0/lib:/nix/store/3r5wfb1dl3sfknvy1yringvmap0hxj4r-libffi-3.8.0/lib"
export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
export STRATA_NVCC=/home/ivan/cuda-13.0/nvcc.sh
nohup ./setup.sh --yes --family coder --model IQ1_M --no-start > setup.log 2>&1 &
```

(`LD_LIBRARY_PATH` + `SSL_CERT_FILE` are already in `.venv/bin/activate`; the resume
command above is the canonical one.)

## Current state (checkpoint)

- [x] Repo cloned, venv + Python deps OK (numpy verified)
- [x] CUDA 13.0 toolkit complete at `~/cuda-13.0` (incl. cicc), all executables patched
- [x] rsqrt conflict diagnosed and fixed (nvcc wrapper); minimal `.cu` compiles
- [ ] **NEXT: resume setup** with the env above → engine compile for sm_120 (10–40 min)
      → ~58 GB model download into `Strata-data/`. Setup is resumable; finished steps skip.
- [ ] After build: patchelf the engine binary `Strata/engine/strata` (generic Linux ELF,
      would hit the stub loader) — same command as fix #1.
- [ ] Edit generated `Strata/run-coder-iq1_m.sh`: it only does `cd` + `exec .venv/bin/python
      serve/server.py --engine strata --config ... --port 8080`; add the two exports from
      the env block above (server.py itself prepends the CUDA lib dirs to LD_LIBRARY_PATH
      from the config's `lib_dirs`, so no CUDA paths needed there).
- [ ] Start server, poll `http://127.0.0.1:8080/health`, send a test chat.

## Pitfalls / notes for resuming

- **nvcc flag syntax**: `-std=c++17`, NOT `--c++17` (an early "passing" test was bogus
  because of this — always check the object file exists).
- Don't wipe `Strata/build/` unnecessarily; setup re-passes all `-D` flags each run,
  which override stale CMake cache values.
- Watch progress: `tail -f Strata/setup.log`. Silence during compile is normal (ninja +
  cicc are slow); don't kill it.
- If a new "cannot run dynamically linked executable" / stub-ld error appears for some
  binary, the fix is always: patchelf with the glibc 2.44 loader + rpath (fix #1).
- Model download ~58 GB; resumable if interrupted.
- GPU selection should default to the RTX 5060 Ti (most VRAM); images off; ctx 65536;
  KV cache 8-bit (setup defaults, already accepted with --yes).
