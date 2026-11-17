# 🔗 Cross-Ecosystem Parity Note: Bridging Continuous Spectral Enclaves (`NDH`) to 8-Lane SWAR Ternary Silicon (`8b-is/ultra-graph@918ef67`)

**Repository:** `Borealiscodes/ultra-graph-specimen`  
**Author:** Borealis S. Hedling (`NDH-RESEARCH-PILOT`)  
**Date:** November 17, 2026  
**Location:** Dublin, Ireland  
**Companion Artifacts:**  
* `SwarTernaryKernel.jl` (Zero-dependency, zero-allocation Julia `Int64` SWAR twin)  
* `8b-is/ultra-graph` Commit `918ef67` (`v0.29.0` / `zerocpu` `v0.6.0`, `rust/zerocpu/src/ternary.rs`)  
* `SpectralHumorKernel.jl` & `ManifoldPerturbationInstruments.jl` (`StaticArrays` QR enclaves)  

---

## 1. Purpose: Three-Runtime Bit-Exact Witness Parity

In `8b-is/ultra-graph`, deterministic kernel correctness is established by cross-language witness parity (`Python` ↔ `Rust`) pinned against committed golden fixtures (`rust/zerocpu/tests/fixtures/trit_vectors.txt`). Adding **`SwarTernaryKernel.jl`** introduces a **third independent compiler witness (`Julia / LLVM`)** using only base primitives (`Int64`, bitwise masks, and hardware `count_ones` / `POPCNT`) with zero external dependencies and **`0 B` dynamic heap allocation**.

---

## 2. How `SwarTernaryKernel.jl` Connects the Two Ecosystems

| Architectural Layer | NDH Spectral Enclave (`Julia`) | Seam Adapter (`SwarTernaryKernel.jl`) | `8b-is` Integer Substrate (`Rust` / `Python`) |
| :--- | :--- | :--- | :--- |
| **Continuous Eigenspace** | Computes sign-normalized QR bases ($P_{\text{iso}}$) and modal eigenvectors ($v_k \in \mathbb{R}^8$) in `StaticArrays`. | `quantize_to_swar_word(v, threshold)` projects 8 `Float64` lanes into `{-1, 0, +1}` via symmetric dead-zone clamping (`\|x\| <= threshold` $\to 0$). | Receives a packed 64-bit `i64` word (`0x00`, `0x01`, `0xFF` per byte lane) with zero floating-point leakage. |
| **Fail-Closed Edge Guard** | Rejects singular or non-orthonormal projections before crossing boundaries. | Rejects `NaN`, `Inf`, and negative thresholds (`ArgumentError`) before packing bits; validates lanes via `is_ternary_packed`. | Enforces strict byte-lane invariants (`0x00`, `0x01`, `0xFF`) prior to `ternary_dot_packed` execution. |
| **Multiplier-Free Inner Product** | Evaluates continuous modal overlap $\langle v_a, v_b \rangle$. | `ternary_dot_packed(a, b)` clears `0xFF` sign bits (`~a_neg`) before masking `+1` lanes, computing `count_ones(P_+) - count_ones(P_-)`. | Matches `zerocpu::ternary::ternary_dot_packed` (44 `x86-64` instructions, zero `unsafe`, zero branches) bit-for-bit. |

---

## 3. Verified Parity & Hardening Findings

1. **Golden Fixture & Fuzz Agreement:** `SwarTernaryKernel.run_parity_tests()` passes all **16** `[packed]` vectors from `trit_vectors.txt` plus **10,000** deterministic LCG randomized trials, confirming identical arithmetic-shift and `POPCNT` behavior across `rustc` and Julia's `LLVM` backend.
2. **Zero-Allocation (`0 B`) Register Execution:** Both `ternary_dot_packed` and `quantize_to_swar_word` execute with `@allocated == 0` after JIT warmup, allowing continuous spectral eigenvectors to be quantized and dotted inside the same stack-allocated loop.
3. **Release-Mode Validation Caveat:** Because `8b-is`'s Rust implementation checks `is_ternary_packed` via `debug_assert!`, callers crossing from continuous Julia enclaves into `--release` Rust binaries must validate untrusted `i64` words at the ingestion boundary (`is_ternary_packed(word) == true`) to prevent non-ternary bytes (`0x03`, `0x80`) from silently aliasing as `+1` or `-1`.

---

## 4. Non-Activation & Sovereignty Clause

> This parity note and `SwarTernaryKernel.jl` are descriptive, comparative, and non-activating. They verify cross-runtime bitwise equivalence between `NDH-RESEARCH-PILOT` spectral kernels and `8b-is/ultra-graph@918ef67` without activating live routing engines or governance altitude.
