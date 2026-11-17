#!/usr/bin/env julia
"""
SwarTernaryKernel.jl
Zero-dependency, zero-allocation (0 B) Julia twin of `8b-is/ultra-graph@918ef67`
(`ternary_dot_packed`), packing 8 balanced ternary lanes {-1, 0, +1} into one Int64
machine word and computing inner products via bitmasks + hardware `count_ones` (POPCNT).
Includes a fail-closed continuous-to-SWAR ingress seam (`quantize_to_swar_word`).
"""

module SwarTernaryKernel

using Test

export LANE_ONE,
       PACKED_LANES,
       is_ternary_packed,
       pack_ternary,
       unpack_ternary,
       quantize_to_swar_word,
       ternary_dot_packed

const PACKED_LANES = 8
const LANE_ONE = 0x0101_0101_0101_0101

"""
    is_ternary_packed(word::Int64) -> Bool

Verify every byte lane in `word` is strictly `0x00` (0), `0x01` (+1), or `0xFF` (-1).
"""
@inline function is_ternary_packed(word::Int64)::Bool
    u = reinterpret(UInt64, word)
    @inbounds for lane in 0:(PACKED_LANES - 1)
        byte = UInt8((u >> (8 * lane)) & 0xFF)
        if byte != 0x00 && byte != 0x01 && byte != 0xFF
            return false
        end
    end
    return true
end

"""
    pack_ternary(lanes) -> Int64

Pack up to 8 ternary integers `{-1, 0, +1}` into one `Int64` machine word
(two's-complement byte lanes; unused upper lanes zero-padded with `0x00`).
Throws `ArgumentError` if length > 8 or any lane is outside `{-1, 0, +1}`.
"""
function pack_ternary(lanes)::Int64
    n = length(lanes)
    if n > PACKED_LANES
        throw(ArgumentError("Expected at most $PACKED_LANES lanes, got $n"))
    end
    word = UInt64(0)
    for (idx, val) in enumerate(lanes)
        v = Int64(val)
        if v != -1 && v != 0 && v != 1
            throw(ArgumentError("Lane $idx out of ternary range {-1, 0, +1}: got $val"))
        end
        byte = reinterpret(UInt64, v) & 0xFF
        word |= byte << (8 * (idx - 1))
    end
    return reinterpret(Int64, word)
end

"""
    unpack_ternary(word::Int64) -> NTuple{8, Int8}

Unpack all 8 two's-complement byte lanes from `word` into an `NTuple{8, Int8}`.
"""
@inline function unpack_ternary(word::Int64)::NTuple{8, Int8}
    u = reinterpret(UInt64, word)
    return ntuple(Val(8)) do i
        signed(UInt8((u >> (8 * (i - 1))) & 0xFF))
    end
end

"""
    quantize_to_swar_word(v::NTuple{8, Float64}, threshold::Float64 = 0.25) -> Int64

Ingress seam adapter that projects 8 continuous values into a packed 64-bit
SWAR ternary word (`-1`, `0`, `+1` per byte lane) using a symmetric dead-zone
threshold (`|x| <= threshold` maps to `0`). Fails closed on non-finite (`NaN`/`Inf`)
floats or negative thresholds.
"""
@inline function quantize_to_swar_word(v::NTuple{8, Float64}, threshold::Float64 = 0.25)::Int64
    if !isfinite(threshold) || threshold < 0.0
        throw(ArgumentError("Threshold must be finite and non-negative, got $threshold"))
    end
    word = UInt64(0)
    @inbounds for idx in 1:PACKED_LANES
        val = v[idx]
        if !isfinite(val)
            throw(ArgumentError("Non-finite float at lane $idx rejected at SWAR seam: $val"))
        end
        trit = val > threshold ? Int64(1) : (val < -threshold ? Int64(-1) : Int64(0))
        byte = reinterpret(UInt64, trit) & 0xFF
        word |= byte << (8 * (idx - 1))
    end
    return reinterpret(Int64, word)
end

"""
    ternary_dot_packed(a::Int64, b::Int64) -> Int64

Multiplier-free 8-lane ternary inner product using two AND-mask pairs and two
hardware population counts (`count_ones`). Clears negative sign bits (`0xFF`)
before testing `+1` lanes so `-1` never aliases as `+1`.
"""
@inline function ternary_dot_packed(a::Int64, b::Int64)::Int64
    @assert is_ternary_packed(a) "word `a` contains non-ternary byte lane"
    @assert is_ternary_packed(b) "word `b` contains non-ternary byte lane"

    a_neg = (a >> 7) & LANE_ONE
    b_neg = (b >> 7) & LANE_ONE
    a_one = a & LANE_ONE & ~a_neg
    b_one = b & LANE_ONE & ~b_neg

    positive = (a_one & b_one) | (a_neg & b_neg)
    negative = (a_one & b_neg) | (a_neg & b_one)
    return Int64(count_ones(positive)) - Int64(count_ones(negative))
end

# ============================================================================
# BUILT-IN PARITY & ZERO-ALLOCATION VERIFICATION SUITE
# ============================================================================

function run_parity_tests()
    @testset "SwarTernaryKernel Bit-Exact Parity with ultra-graph@918ef67" begin
        # 1. Round-trip & validation boundaries
        sample = (1, 0, -1, 1, -1, 0, 1, -1)
        packed = pack_ternary(sample)
        @test is_ternary_packed(packed)
        @test unpack_ternary(packed) == Int8.(sample)
        @test !is_ternary_packed(Int64(0x03))
        @test !is_ternary_packed(Int64(0x80))
        @test_throws ArgumentError pack_ternary((1, 2))
        @test_throws ArgumentError pack_ternary(ntuple(_ -> 1, 9))

        # 2. All 16 golden vectors from `rust/zerocpu/tests/fixtures/trit_vectors.txt` [packed]
        golden_vectors = [
            ((0, 0, 0, 0, 0, 0, 0, 0), (0, 0, 0, 0, 0, 0, 0, 0), 0),
            ((1, 1, 1, 1, 1, 1, 1, 1), (1, 1, 1, 1, 1, 1, 1, 1), 8),
            ((-1, -1, -1, -1, -1, -1, -1, -1), (-1, -1, -1, -1, -1, -1, -1, -1), 8),
            ((1, 1, 1, 1, 1, 1, 1, 1), (-1, -1, -1, -1, -1, -1, -1, -1), -8),
            ((1, -1, 1, 0, -1, 1, 1, -1), (1, 1, -1, 0, -1, 1, -1, 1), -1),
            ((1, 0, 0, 0, 0, 0, 0, 0), (0, -1, 0, 0, 0, 0, 0, 0), 0),
            ((-1, 0, 1, 0, -1, 0, 1, 0), (-1, 0, -1, 0, 1, 0, 1, 0), 0),
            ((0, 1, 0, 0, 1, 1, -1, -1), (1, 0, 1, 1, -1, -1, 0, 0), -2),
            ((-1, -1, 1, 1, 1, -1, 1, 0), (0, 1, 1, 1, 1, -1, 1, -1), 4),
            ((1, -1, -1, -1, -1, -1, 1, -1), (0, 0, 0, 1, -1, 1, -1, 1), -3),
            ((0, 0, -1, 1, -1, 0, 1, 0), (0, 1, -1, 1, 0, 0, -1, 1), 1),
            ((0, -1, -1, 1, -1, 0, -1, 0), (0, -1, -1, 1, -1, -1, -1, -1), 5),
            ((0, 0, 1, 0, 0, -1, 1, 1), (-1, 1, 0, 0, -1, 0, 0, -1), -1),
            ((0, -1, -1, -1, 1, -1, -1, -1), (0, 0, -1, 1, 1, -1, 0, 1), 1),
            ((-1, 1, -1, 0, 1, 0, -1, 0), (0, -1, -1, 0, 1, 0, -1, -1), 2),
            ((-1, 0, 1, 1, 1, -1, -1, -1), (-1, 0, 0, -1, 1, 0, 0, 0), 1),
        ]
        for (a_vec, b_vec, expected) in golden_vectors
            wa = pack_ternary(a_vec)
            wb = pack_ternary(b_vec)
            @test ternary_dot_packed(wa, wb) == expected
            @test ternary_dot_packed(wa, wb) == sum(a_vec .* b_vec)
        end

        # 3. 10,000 deterministic LCG fuzz trials (zero external Random dependency)
        seed = UInt64(0x5EED_918E_F670_0001)
        trit_pool = (-1, 0, 1)
        for _ in 1:10_000
            a_tup = ntuple(Val(8)) do _
                seed = seed * 6364136223846793005 + 1442695040888963407
                trit_pool[Int((seed >> 61) % 3) + 1]
            end
            b_tup = ntuple(Val(8)) do _
                seed = seed * 6364136223846793005 + 1442695040888963407
                trit_pool[Int((seed >> 61) % 3) + 1]
            end
            @test ternary_dot_packed(pack_ternary(a_tup), pack_ternary(b_tup)) == sum(a_tup .* b_tup)
        end

        # 4. Continuous-to-SWAR ingress seam & fail-closed NaN/Inf guards
        vec_f64 = (0.85, -0.10, -0.72, 0.25, 0.90, 0.0, -0.30, 0.40)
        q_word = quantize_to_swar_word(vec_f64, 0.25)
        @test is_ternary_packed(q_word)
        @test unpack_ternary(q_word) == Int8.((1, 0, -1, 0, 1, 0, -1, 1))
        @test_throws ArgumentError quantize_to_swar_word((NaN, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), 0.25)
        @test_throws ArgumentError quantize_to_swar_word((Inf, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), 0.25)
        @test_throws ArgumentError quantize_to_swar_word((0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), -0.1)

        # 5. Zero-allocation (0 B) verification after JIT warmup
        wa = pack_ternary((1, -1, 1, 0, -1, 1, 1, -1))
        wb = pack_ternary((1, 1, -1, 0, -1, 1, -1, 1))
        ternary_dot_packed(wa, wb)
        quantize_to_swar_word(vec_f64, 0.25)
        @test (@allocated ternary_dot_packed(wa, wb)) == 0
        @test (@allocated quantize_to_swar_word(vec_f64, 0.25)) == 0
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_parity_tests()
end

end # module
