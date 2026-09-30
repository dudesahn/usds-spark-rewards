// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {BitMath} from "v4-core/libraries/BitMath.sol";
import {LiquidityMath} from "v4-core/libraries/LiquidityMath.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {SwapMath} from "v4-core/libraries/SwapMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

/// @notice Read-only exact-input swap simulation for hookless Uniswap V4 pools.
library UniswapV4SwapSimulator {
    using ProtocolFeeLibrary for uint16;
    using ProtocolFeeLibrary for uint24;

    uint256 internal constant MAX_SWAP_STEPS = 128;

    struct State {
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
    }

    struct Preview {
        State state;
        uint256 amountIn;
        uint256 amountOut;
        bool valid;
        bool fullyFilled;
    }

    struct Step {
        uint160 sqrtPriceStartX96;
        int24 tickNext;
        bool initialized;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    function loadState(
        IUniswapV4StateView stateView,
        bytes32 poolId,
        bool zeroForOne
    )
        internal
        view
        returns (State memory state, uint24 swapFee, bool initialized)
    {
        uint24 packedProtocolFee;
        uint24 lpFee;
        (state.sqrtPriceX96, state.tick, packedProtocolFee, lpFee) = stateView
            .getSlot0(poolId);
        if (state.sqrtPriceX96 == 0 || lpFee > SwapMath.MAX_SWAP_FEE)
            return (state, 0, false);

        state.liquidity = stateView.getLiquidity(poolId);

        uint16 protocolFee = zeroForOne
            ? packedProtocolFee.getZeroForOneFee()
            : packedProtocolFee.getOneForZeroFee();
        swapFee = protocolFee == 0
            ? lpFee
            : protocolFee.calculateSwapFee(lpFee);
        initialized = swapFee < SwapMath.MAX_SWAP_FEE;
    }

    function previewExactInput(
        IUniswapV4StateView stateView,
        bytes32 poolId,
        int24 tickSpacing,
        bool zeroForOne,
        uint256 amountIn,
        uint24 swapFee,
        State memory state
    ) internal view returns (Preview memory preview) {
        if (amountIn == 0 || amountIn > uint256(type(int256).max))
            return preview;

        // The upper bound above makes this conversion lossless.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 amountSpecifiedRemaining = -int256(amountIn);
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? TickMath.MIN_SQRT_PRICE + 1
            : TickMath.MAX_SQRT_PRICE - 1;

        for (uint256 i; i < MAX_SWAP_STEPS; ++i) {
            if (amountSpecifiedRemaining == 0) {
                preview.state = state;
                preview.amountIn = amountIn;
                preview.valid = true;
                preview.fullyFilled = true;
                return preview;
            }
            if (state.sqrtPriceX96 == sqrtPriceLimitX96) {
                return
                    _finishPartial(
                        preview,
                        state,
                        amountIn,
                        amountSpecifiedRemaining
                    );
            }

            // Every Step field is assigned below before its first read.
            // slither-disable-next-line uninitialized-local
            Step memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;
            (
                step.tickNext,
                step.initialized
            ) = _nextInitializedTickWithinOneWord(
                stateView,
                poolId,
                state.tick,
                tickSpacing,
                zeroForOne
            );

            if (step.tickNext <= TickMath.MIN_TICK)
                step.tickNext = TickMath.MIN_TICK;
            if (step.tickNext >= TickMath.MAX_TICK)
                step.tickNext = TickMath.MAX_TICK;

            step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);
            (
                state.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                SwapMath.getSqrtPriceTarget(
                    zeroForOne,
                    step.sqrtPriceNextX96,
                    sqrtPriceLimitX96
                ),
                state.liquidity,
                amountSpecifiedRemaining,
                swapFee
            );

            amountSpecifiedRemaining += int256(step.amountIn + step.feeAmount);
            preview.amountOut += step.amountOut;

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    (, int128 liquidityNet) = stateView.getTickLiquidity(
                        poolId,
                        step.tickNext
                    );
                    if (zeroForOne) liquidityNet = -liquidityNet;
                    state.liquidity = LiquidityMath.addDelta(
                        state.liquidity,
                        liquidityNet
                    );
                }
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            } else {
                return
                    _finishPartial(
                        preview,
                        state,
                        amountIn,
                        amountSpecifiedRemaining
                    );
            }
        }

        // The amount can be fully consumed by the final permitted step. Finalize
        // here because the loop's leading completion check will not run again.
        if (amountSpecifiedRemaining == 0) {
            preview.state = state;
            preview.amountIn = amountIn;
            preview.valid = true;
            preview.fullyFilled = true;
            return preview;
        }

        return
            _finishPartial(preview, state, amountIn, amountSpecifiedRemaining);
    }

    function _finishPartial(
        Preview memory preview,
        State memory state,
        uint256 requested,
        int256 remaining
    ) private pure returns (Preview memory) {
        preview.state = state;
        // Exact-input remaining amounts stay nonpositive throughout the simulation.
        // forge-lint: disable-next-line(unsafe-typecast)
        preview.amountIn = requested - uint256(-remaining);
        preview.valid = true;
        return preview;
    }

    function _nextInitializedTickWithinOneWord(
        IUniswapV4StateView stateView,
        bytes32 poolId,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) private view returns (int24 next, bool initialized) {
        unchecked {
            int24 compressed = _compress(tick, tickSpacing);

            if (lte) {
                (int16 wordPosition, uint8 bitPosition) = _position(compressed);
                uint256 mask = type(uint256).max >>
                    (uint256(type(uint8).max) - bitPosition);
                uint256 masked = stateView.getTickBitmap(poolId, wordPosition) &
                    mask;

                initialized = masked != 0;
                next = initialized
                    ? (compressed -
                        int24(
                            uint24(
                                bitPosition - BitMath.mostSignificantBit(masked)
                            )
                        )) * tickSpacing
                    : (compressed - int24(uint24(bitPosition))) * tickSpacing;
            } else {
                (int16 wordPosition, uint8 bitPosition) = _position(
                    ++compressed
                );
                uint256 mask = ~((uint256(1) << bitPosition) - 1);
                uint256 masked = stateView.getTickBitmap(poolId, wordPosition) &
                    mask;

                initialized = masked != 0;
                next = initialized
                    ? (compressed +
                        int24(
                            uint24(
                                BitMath.leastSignificantBit(masked) -
                                    bitPosition
                            )
                        )) * tickSpacing
                    : (compressed +
                        int24(uint24(type(uint8).max - bitPosition))) *
                        tickSpacing;
            }
        }
    }

    function _compress(
        int24 tick,
        int24 tickSpacing
    ) private pure returns (int24 compressed) {
        compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) --compressed;
    }

    function _position(
        int24 tick
    ) private pure returns (int16 wordPosition, uint8 bitPosition) {
        // A valid Uniswap tick is bounded tightly enough for its bitmap word index.
        // forge-lint: disable-next-line(unsafe-typecast)
        wordPosition = int16(tick >> 8);
        // Modulo 256 defines the bitmap position and intentionally wraps negative remainders.
        // forge-lint: disable-next-line(unsafe-typecast)
        bitPosition = uint8(int8(tick % 256));
    }
}
