# 🧮 Standalone Mathematical & Computational Audit: Multiplier-Free 8-Lane SWAR Ternary Dot Product (`8b-is/ultra-graph@918ef67`)

**Author:** Borealis S. Hedling (`NDH-RESEARCH-PILOT`)  
**Date:** November 17, 2026  
**Location:** Dublin, Ireland  
**Audited Target:** `8b-is/ultra-graph` Commit `918ef67` (`v0.29.0` / `zerocpu` `v0.6.0`)  
**Audited Files:** `rust/zerocpu/src/ternary.rs`, `ultragraph/zerocpu/trit.py`, `rust/zerocpu/tests/trit_parity.rs`, `tests/test_trit.py`  
**Classification:** Bitwise Formal Verification • SWAR Kernel Audit • Cross-Language Parity  

---

## 1. Executive Summary

Commit `918ef67` (`8b-is/ultra-graph`) introduces a multiplier-free, 8-lane SWAR (SIMD Within A Register) ternary dot product (`ternary_dot_packed`) over 64-bit signed integers (`i64`). By packing eight balanced ternary values $t_i \in \{-1, 0, +1\}$ as two's-complement bytes into a single machine word, the kernel eliminates architecture-specific SIMD slice dependencies (`NEON`) while maintaining bit-exact parity between Python and Rust. The implementation compiles to **44 assembly instructions** with zero floating-point operations, zero lookup tables, and zero `unsafe` blocks, verified against **50,000** randomized Rust fuzz trials, **2,000** Python trials, and **16** golden fixture vectors.

---

## 2. Mathematical & Bitwise Proof of Correctness

### 2.1 Byte-Lane Encoding
Each ternary lane $i \in \{0, \dots, 7\}$ occupies byte $i$ (bits $8i \dots 8i+7$) of a 64-bit signed integer (`i64`) using standard two's-complement byte representations:
* $0 \mapsto \texttt{0x00} = 0000\,0000_2$
* $+1 \mapsto \texttt{0x01} = 0000\,0001_2$
* $-1 \mapsto \texttt{0xFF} = 1111\,1111_2$

### 2.2 Orthogonal Sign-Indicator Extraction
Define the byte-broadcast unit mask $M_1 = \texttt{0x0101\_0101\_0101\_0101}$ (`LANE_ONE`). For an input word $a \in \mathbb{Z}_{2^{64}}$, the kernel extracts two orthogonal 1-bit-per-byte indicator masks:

$$a_{\text{neg}} = (a \gg 7) \land M_1, \qquad a_{\text{one}} = a \land M_1 \land \neg a_{\text{neg}}$$

#### Truth Table Per Byte Lane ($x \in \{0, +1, -1\}$)

| Value $x$ | Hex Byte | Binary | $(x \gg 7) \land 1$ ($a_{\text{neg}}$) | $x \land 1$ (Naive LSB) | $x \land 1 \land \neg a_{\text{neg}}$ ($a_{\text{one}}$) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **$0$** | `0x00` | `00000000` | `0` | `0` | `0` |
| **$+1$** | `0x01` | `00000001` | `0` | `1` | `1` |
| **$-1$** | `0xFF` | `11111111` | `1` | `1` *(Collision)* | `0` *(Cleared)* |

### 2.3 Key Bitwise Invariants
1. **Resolution of the `0xFF` Low-Bit Collision:** Because $-1$ is encoded as `0xFF`, its least-significant bit is `1`. Computing $a \land M_1$ alone sets bit $8i$ for both $+1$ and $-1$, causing every $-1$ lane to register simultaneously as positive and negative. Masking with $\neg a_{\text{neg}}$ restores strict mutual exclusion ($a_{\text{one}} \land a_{\text{neg}} = 0$).
2. **Arithmetic Right-Shift Invariance:** Although `a >> 7` on signed `i64` executes an arithmetic right shift (replicating the sign bit of lane 7 across bits $57 \dots 63$), the subsequent bitwise AND with $M_1$ clears bits $1 \dots 7$ of every byte, making signed arithmetic shifts bit-identical to logical shifts.
3. **Multiplier-Free Inner Product via Population Count:** Given orthogonal indicator masks for words $a$ and $b$, the lane-wise ternary product $a_i \cdot b_i \in \{-1, 0, +1\}$ reduces to two bitwise expressions and two hardware population counts (`POPCNT`):

$$P_+ = (a_{\text{one}} \land b_{\text{one}}) \lor (a_{\text{neg}} \land b_{\text{neg}}), \qquad P_- = (a_{\text{one}} \land b_{\text{neg}}) \lor (a_{\text{neg}} \land b_{\text{one}})$$

$$\langle a, b \rangle = \operatorname{popcount}(P_+) - \operatorname{popcount}(P_-)$$

---

## 3. Computational & Engineering Audit

* **Instruction & Portability Profile:** Compiles to **44 assembly instructions** with zero floating-point operations, zero lookup tables, zero data-dependent branches, and zero `unsafe` Rust blocks. Removing slice lifetimes and `NEON` intrinsics allows direct verification inside the `x86-64` `g8t` equivalence capsule harness.
* **Storage Density vs. Register Parallelism Trade-Off:** Packing 8 trits into 64 bits uses **8.0 bits/trit**, compared to the information-theoretic bound of $\log_2(3) \approx 1.585\text{ bits/trit}$ achieved by `ultra-graph`'s base-243 5-trit/byte `SPQT` codec. Byte alignment prevents cross-lane carry propagation during parallel bitwise operations.
* **Fuzzing & Cross-Language Parity:**
  * The initial naive mask failed **11,376 / 20,000** randomized fuzz cases due to the `0xFF` low-bit collision.
  * The repaired kernel passes **50,000** randomized Rust fuzz trials, **2,000** randomized Python trials, **16** golden vectors in `trit_vectors.txt` (`[packed]`), and an explicit mixed-sign regression test (`test_packed_dot_handles_the_mixed_sign_case_that_breaks_naive_bits`).

---

## 4. Edge-Boundary & Defensive Caveats

* **Release-Mode Input Contract (`debug_assert!` Only):** In `rust/zerocpu/src/ternary.rs`, `ternary_dot_packed(a: i64, b: i64)` validates byte lanes (`0x00`, `0x01`, `0xFF`) exclusively via `debug_assert!(is_ternary_packed(...))`. External Rust callers passing unvalidated `i64` words in `--release` builds will encounter silent bitwise misinterpretation (for example, `0x03` evaluates as $+1$, and `0x80` evaluates as $-1$). Callers must validate untrusted inputs via `is_ternary_packed` at the ingestion seam.
* **Zero-Padding Invariance:** Partial vectors of length $k < 8$ zero-pad upper lanes with `0x00`. Because `0x00` yields `0` in both $a_{\text{one}}$ and $a_{\text{neg}}$, padded lanes contribute identically `0` to both `positive` and `negative` masks, preserving exact inner-product linearity without requiring length metadata inside the dot kernel.

---

## 5. Non-Activation & Provenance Clause

> This standalone mathematical and computational audit is descriptive, comparative, and non-activating. It verifies the bitwise mechanics of `8b-is/ultra-graph@918ef67` without activating NDH geometry, constellation routing, or governance altitude.
