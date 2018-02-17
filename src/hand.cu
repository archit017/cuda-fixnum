#pragma once

#include "primitives.cu"
#include "subwarp.cu"

/*
 * A "hand" encapsulates our notion of a fixed collection of digits in
 * a multiprecision number.
 *
 * A hand is stored in a warp register, and so implicitly consumes 32
 * times the size of the register.  The interface can support
 * different underlying representations however, including a "full
 * utilisation always handle carries" implementation, a "avoid carries
 * with nail bits" implementation, as well as more exotic
 * implementations using floating-point registers.
 *
 * A limb is an array of digits stored in memory. Chunks of digits are
 * loaded into hands in order for arithmetic to be performed on
 * numbers. So a limb can be thought of as a sequence of hands.
 *
 * The interface to hands and the interface to limbs is (largely) the
 * same. The interface for limbs is defined in terms of the one for
 * hands.
 */

// A hand implementation
//
// Normally a hand_implementation will not be templatised by digit
// type, but in this case it works with uint32_t and uint64_t.
template< typename digit_tp, int WIDTH = WARPSIZE >
class full_hand {
    typedef subwarp<WIDTH> subwarp;

public:
    static constexpr int SLOT_WIDTH = WIDTH;
    static constexpr int NSLOTS = WARPSIZE / WIDTH;

    typedef digit_tp digit;
    static constexpr int DIGIT_BYTES = sizeof(digit);
    static constexpr int DIGIT_BITS = DIGIT_BYTES * 8;
    static constexpr int DIGITS_PER_HAND = WARPSIZE;
    static constexpr int HAND_BYTES = DIGITS_PER_HAND * DIGIT_BYTES;
    static constexpr int HAND_BITS = DIGITS_PER_HAND * DIGIT_BITS;
    static constexpr int FIXNUM_BYTES = SLOT_WIDTH * DIGIT_BYTES;

    //  +=  +  -  <<  >>  &=
    //  <  >

    // multiply-by-zero-or-one

    template< typename Func, typename... Args >
    static __device__ void call(Func fn, int fn_idx, Args... args) {
        int off = fn_idx * SLOT_WIDTH + subwarp::laneIdx();
        // FIXME: Work out how to return the return value properly
        (void) fn.call(args[off]...);
    }


    struct sub_br {
    private:
        __device__ int resolve_borrows(digit &r, int cy) const {
            // FIXME: This is at best a half-baked attempt to adapt
            // the carry propagation code above to the case of
            // subtraction.
            // FIXME: Use std::numeric_limits<digit>::min
            constexpr digit DIGIT_MIN = 0;
            int L = subwarp::laneIdx();
            uint32_t allcarries, p, g;
            int cy_hi;

            g = ~subwarp::ballot(cy);                  // carry generate
            p = ~subwarp::ballot(r == DIGIT_MIN);      // carry propagate
            allcarries = (p & g) - g;                 // propagate all carries
            // FIXME: This is not correct when WIDTH != warpSize
            cy_hi = allcarries > g;                   // detect final underflow
            allcarries = (allcarries ^ p) | (g >> 1); // get effective carries
            r -= (allcarries >> L) & 1;

            // return highest carry
            return cy_hi;
        }

    public:
        __device__ int call(digit &r, digit a, digit b) const {
            int br;

            r = a - b;
            br = r > a;
            return resolve_borrows(r, br);
        }
    };
};
