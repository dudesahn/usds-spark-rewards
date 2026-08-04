### src/GroveCompounder.sol
```solidity
// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenizedStrategyLib as TokenizedStrategy} from "@tokenized-strategy/libraries/TokenizedStrategyLib.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IPsmWrapper} from "src/interfaces/IPsmWrapper.sol";

contract GroveCompounder is UniswapV3Swapper, BaseHealthCheck {
    using SafeERC20 for ERC20;

    /// @notice yearn's referral code
    uint16 public referral = 2009;

    /// @notice Address of the specific Auction this strategy uses.
    address public auction;

    /// @notice True if we should use auctions, if false use UniV3
    bool public useAuction = true;

    /// @notice Reward token we get for staking
    address public immutable REWARDS_TOKEN;

    /// @notice Staking contract we use
    IStaking public constant STAKING =
        IStaking(0x4E41488C19cD35EB4de3083Fc3e204854c75c86a);

    /// @notice Wrapper for PSM with USDS
    IPsmWrapper internal constant PSM_WRAPPER =
        IPsmWrapper(0xA188EEC8F81263234dA3622A406892F3D630f98c);

    /// @notice Don't bother spending the gas to stake dust
    uint256 internal constant DUST = 1e18;

    constructor() BaseHealthCheck(PSM_WRAPPER.usds(), "Grove USDS Compounder") {
        require(!STAKING.paused(), "!paused");
        require(PSM_WRAPPER.usds() == STAKING.stakingToken(), "!stakingToken");
        REWARDS_TOKEN = STAKING.rewardsToken();

        // approve staking contract and our PSM wrapper
        asset.forceApprove(address(STAKING), type(uint256).max);

        // use USDC for our UniV3 swaps and then send it through the PSM for USDS
        address usdc = PSM_WRAPPER.gem();
        ERC20(usdc).forceApprove(address(PSM_WRAPPER), type(uint).max); //approve the PSM

        // Set the min amount for the swapper/auction to sell
        base = usdc; // use USDC as base in UniV3
        _setMinAmountToSell(REWARDS_TOKEN, 5_000e18);
        _setUniFees(REWARDS_TOKEN, usdc, 10_000); // GROVE-USDC pool is 1%. uniV3 fees in 1/100 of bps
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        return STAKING.balanceOf(address(this));
    }

    function balanceOfRewards() public view returns (uint256) {
        return ERC20(REWARDS_TOKEN).balanceOf(address(this));
    }

    function claimableRewards() external view returns (uint256) {
        return STAKING.earned(address(this));
    }

    /* ========== CORE STRATEGY FUNCTIONS ========== */

    function _deployFunds(uint256 _amount) internal override {
        STAKING.stake(_amount, referral);
    }

    function _freeFunds(uint256 _amount) internal override {
        STAKING.withdraw(_amount);
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // get our rewards. if no rewards is a noop so no worries about reverts
        _claimRewards();

        // store in memory to save gas
        uint256 toSwap = balanceOfRewards();
        uint256 minRewardAmountToSell = minAmountToSell[REWARDS_TOKEN];

        if (!useAuction) {
            if (toSwap > minRewardAmountToSell) {
                require(PSM_WRAPPER.tin() == 0, "!psmFee");
                // swap if using UniV3 to sell rewards
                _swapFrom(REWARDS_TOKEN, base, toSwap, 0);
                // use PSM to go from USDC to USDS for free
                PSM_WRAPPER.sellGem(
                    address(this),
                    ERC20(base).balanceOf(address(this))
                );
            }
        } else if (toSwap > minRewardAmountToSell) {
            _kickAuction(REWARDS_TOKEN, toSwap);
        }

        uint256 balance = balanceOfAsset();
        if (!TokenizedStrategy.isShutdown()) {
            if (balance > DUST) {
                _deployFunds(balance);
            }
        }
        _totalAssets = balanceOfStake() + balanceOfAsset();
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, balanceOfStake());
        _freeFunds(_amount);
    }

    function availableDepositLimit(
        address _receiver
    ) public view override returns (uint256) {
        if (STAKING.paused()) {
            return 0;
        }

        return super.availableDepositLimit(_receiver);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /* ========== REWARD & AUCTION FUNCTIONS ========== */

    /**
     * @notice Manually claim rewards from staking contract.
     * @dev Can only be called by management.
     */
    function claimRewards() external onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal {
        STAKING.getReward();
    }

    /**
     * @notice Kick an auction to sell rewards to more asset.
     * @dev Can only be called by keepers. useAuction must be set to true. Can't kick asset.
     * @param _token Token to kick the auction for.
     */
    function kickAuction(address _token) external onlyKeepers {
        require(useAuction, "!useAuction");
        uint256 rewardsBalance;

        if (_token == REWARDS_TOKEN) {
            _claimRewards();
            rewardsBalance = balanceOfRewards();
        } else {
            rewardsBalance = ERC20(_token).balanceOf(address(this));
        }

        if (rewardsBalance > minAmountToSell[REWARDS_TOKEN]) {
            _kickAuction(_token, rewardsBalance);
        }
    }

    function _kickAuction(address _token, uint256 _balance) internal {
        require(_token != address(asset), "!asset");
        address _auction = auction;
        require(_auction != address(0), "!auction");
        ERC20(_token).safeTransfer(_auction, _balance);
        Auction(_auction).kick(_token);
    }

    /* ========== PERMISSIONED SETTER FUNCTIONS ========== */

    /**
     * @notice Set the minimum amount of rewardsToken to sell.
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei.
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        _setMinAmountToSell(REWARDS_TOKEN, _minAmountToSell);
    }

    /**
     * @notice Set fees for UniswapV3 to sell rewardsToken.
     * @dev Can only be called by management.
     * @param _rewardToBase fee reward to base (grove/usdc)
     */
    function setUniV3Fees(uint24 _rewardToBase) external onlyManagement {
        _setUniFees(REWARDS_TOKEN, base, _rewardToBase);
    }

    /**
     * @notice Set address for our auction contract.
     * @dev Can only be called by management.
     * @param _auction Address of the auction to use.
     */
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(Auction(_auction).receiver() == address(this), "receiver");
            require(Auction(_auction).want() == address(asset), "want");
        } else {
            require(!useAuction, "!auction");
        }
        auction = _auction;
    }

    /**
     * @notice Set whether to use auction or UniV3 for rewards selling.
     * @dev Can only be called by management.
     * @param _useAuction Use auction to sell rewards (true) or UniV3 (false).
     */
    function setUseAuction(bool _useAuction) external onlyManagement {
        if (_useAuction) require(auction != address(0), "!auction");
        useAuction = _useAuction;
    }

    /**
     * @notice Set the referral code for staking.
     * @dev Can only be called by management.
     * @param _referral Referral code for deposits in the staking contract.
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }
}
```

### src/libraries/UniswapV3SwapSimulator.sol
```solidity
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {Simulate, TickMath} from "./UniswapV3SwapSimulatorCore.sol";
import {ISwapRouter} from "@periphery/interfaces/Uniswap/V3/ISwapRouter.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface ISwapRouterWithFactory is ISwapRouter {
    function factory() external view returns (address);
}

/// @title Library for simulating swaps on Uniswap V3
/// @notice Provides functions to simulate swap outcomes without executing actual transactions
/// @dev Uses Uniswap v3 concentrated liquidity pools for price calculations
library UniswapV3SwapSimulator {
    /// @notice Simulates a single exact input swap without executing the actual swap
    /// @param router The swap router contract to use for the simulation
    /// @param params The parameters for the exact input single swap
    /// @return amountOut The expected output amount from the simulated swap
    /// @dev Uses the pool's current state to calculate the expected output amount
    function simulateExactInputSingle(
        ISwapRouter router,
        ISwapRouter.ExactInputSingleParams memory params
    ) external view returns (uint256 amountOut) {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = getPool(
            router,
            params.tokenIn,
            params.tokenOut,
            params.fee
        );
        (int256 _amount0, int256 _amount1) = Simulate.simulateSwap(
            pool,
            zeroForOne,
            int256(params.amountIn),
            params.sqrtPriceLimitX96 == 0
                ? (
                    zeroForOne
                        ? TickMath.MIN_SQRT_RATIO + 1
                        : TickMath.MAX_SQRT_RATIO - 1
                )
                : params.sqrtPriceLimitX96
        );
        return uint256(-(zeroForOne ? _amount1 : _amount0));
    }

    function getPool(
        ISwapRouter router,
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
                IUniswapV3Factory(
                    ISwapRouterWithFactory(address(router)).factory()
                ).getPool(tokenA, tokenB, fee)
            );
    }
}
```

### src/libraries/UniswapV3SwapSimulatorCore.sol
```solidity
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SwapMath} from "@uniswap-v3-core/libraries/SwapMath.sol";
import {SafeCast} from "@uniswap-v3-core/libraries/SafeCast.sol";
import {TickMath} from "@uniswap-v3-core/libraries/TickMath.sol";
import {TickBitmap} from "@uniswap-v3-core/libraries/TickBitmap.sol";
import {BitMath} from "@uniswap-v3-core/libraries/BitMath.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";

/// @title Library for simulating swaps.
/// @notice By fully replicating the swap logic, we can make a static call to get a quote.
library Simulate {
    using SafeCast for uint256;

    struct Cache {
        // price at the beginning of the swap
        uint160 sqrtPriceX96Start;
        // tick at the beginning of the swap
        int24 tickStart;
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the lp fee of the pool
        uint24 fee;
        // the tick spacing of the pool
        int24 tickSpacing;
    }

    struct State {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the current liquidity in range
        uint128 liquidity;
    }

    // copied from UniswapV3Pool to avoid pragma issues associated with importing it
    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    // slither-disable-next-line cyclomatic-complexity
    function simulateSwap(
        IUniswapV3Pool pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal view returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "AS");

        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        require(
            zeroForOne
                ? sqrtPriceLimitX96 < sqrtPriceX96 &&
                    sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > sqrtPriceX96 &&
                    sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            "SPL"
        );

        Cache memory cache = Cache({
            sqrtPriceX96Start: sqrtPriceX96,
            tickStart: tick,
            liquidityStart: pool.liquidity(),
            fee: pool.fee(),
            tickSpacing: pool.tickSpacing()
        });

        bool exactInput = amountSpecified > 0;

        State memory state = State({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: cache.sqrtPriceX96Start,
            tick: cache.tickStart,
            liquidity: cache.liquidityStart
        });

        while (
            state.amountSpecifiedRemaining != 0 &&
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            // slither-disable-next-line uninitialized-local
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (
                step.tickNext,
                step.initialized
            ) = nextInitializedTickWithinOneWord(
                pool.tickBitmap,
                state.tick,
                cache.tickSpacing,
                zeroForOne
            );

            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            (
                state.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                cache.fee
            );

            if (exactInput) {
                unchecked {
                    state.amountSpecifiedRemaining -= (step.amountIn +
                        step.feeAmount).toInt256();
                }
                state.amountCalculated -= step.amountOut.toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining += step.amountOut.toInt256();
                }
                state.amountCalculated += (step.amountIn + step.feeAmount)
                    .toInt256();
            }

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    (, int128 liquidityNet, , , , , , ) = pool.ticks(
                        step.tickNext
                    );
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }

                    state.liquidity = liquidityNet < 0
                        ? state.liquidity - uint128(-liquidityNet)
                        : state.liquidity + uint128(liquidityNet);
                }

                unchecked {
                    state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
                }
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (
                amountSpecified - state.amountSpecifiedRemaining,
                state.amountCalculated
            )
            : (
                state.amountCalculated,
                amountSpecified - state.amountSpecifiedRemaining
            );
    }

    // This function replicates TickBitmap, but accepts a function pointer argument.
    // It's private because it's messy, and shouldn't be re-used.
    function nextInitializedTickWithinOneWord(
        function(int16) external view returns (uint256) self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) private view returns (int24 next, bool initialized) {
        unchecked {
            int24 compressed = tick / tickSpacing;
            if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

            if (lte) {
                (int16 wordPos, uint8 bitPos) = tickBitmapPosition(compressed);
                // all the 1s at or to the right of the current bitPos
                uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
                uint256 masked = self(wordPos) & mask;

                // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                next = initialized
                    ? (compressed -
                        int24(
                            uint24(bitPos - BitMath.mostSignificantBit(masked))
                        )) * tickSpacing
                    : (compressed - int24(uint24(bitPos))) * tickSpacing;
            } else {
                // start from the word of the next tick, since the current tick state doesn't matter
                (int16 wordPos, uint8 bitPos) = tickBitmapPosition(
                    compressed + 1
                );
                // all the 1s at or to the left of the bitPos
                uint256 mask = ~((1 << bitPos) - 1);
                uint256 masked = self(wordPos) & mask;

                // if there are no initialized ticks to the left of the current tick, return leftmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                next = initialized
                    ? (compressed +
                        1 +
                        int24(
                            uint24(BitMath.leastSignificantBit(masked) - bitPos)
                        )) * tickSpacing
                    : (compressed +
                        1 +
                        int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
            }
        }
    }

    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function tickBitmapPosition(
        int24 tick
    ) private pure returns (int16 wordPos, uint8 bitPos) {
        unchecked {
            wordPos = int16(tick >> 8);
            bitPos = uint8(int8(tick % 256));
        }
    }
}
```

### src/periphery/GroveCompounderAprOracle.sol
```solidity
// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {UniswapV3SwapSimulator, ISwapRouter, ISwapRouterWithFactory} from "src/libraries/UniswapV3SwapSimulator.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "@uniswap-v3-core/libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GroveCompounderAprOracle {
    event ManagementTransferred(address indexed management);
    event UniV3FeeSet(uint24 indexed rewardToBaseUniV3Fee);
    event UniV4PoolSet(bytes32 indexed poolId, bool indexed groveIsToken0);
    event UniV4PoolAdded(bytes32 indexed poolId, bool indexed groveIsToken0);
    event UniV4PoolRemoved(bytes32 indexed poolId);
    event UniV4PoolsSet(bytes32[] poolIds, bool[] groveIsToken0);

    struct UniV4PoolConfig {
        bytes32 poolId;
        bool groveIsToken0;
    }

    struct UniV4PoolQuote {
        bytes32 poolId;
        bool groveIsToken0;
        uint128 liquidity;
        uint256 price;
    }

    /// @notice Sky Rewards staking contract
    address public constant STAKING = 0x4E41488C19cD35EB4de3083Fc3e204854c75c86a;

    /// @notice Grove governance token
    /// @dev Reward token for staking
    address public constant GROVE = 0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406;

    /// @notice Token to stake for GROVE rewards
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice GROVE is paired with USDC in UniV3 pool
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Uniswap V3 Router address
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /// @notice Default GROVE/USDC 1% UniV3 pool
    address public constant DEFAULT_GROVE_USDC_V3_POOL = 0x5D23797587B2c17414384384098291c0B1Fe1362;

    /// @notice Default GROVE/USDC 1% UniV3 fee
    uint24 public constant DEFAULT_REWARD_TO_BASE_UNI_V3_FEE = 10_000;

    /// @notice UniV4 StateView lens
    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);

    /// @notice UniV4 USDC/GROVE pool key:
    /// currency0 = USDC, currency1 = GROVE, hooks = address(0)
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID =
        0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_TWO =
        0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_THREE =
        0xb557b2447a4723741959fe7ebd5a37375023931d19f6383cc83bd0d9c8397bb9;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_FOUR =
        0x2e53ef1a957f41bfba562bac317881d6f0ef2d6c217c7279c11b0878f9791ad5;

    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    uint256 internal constant Q192 = 1 << 192;
    uint256 internal constant MAX_BPS = 10_000;
    uint256 public constant MIN_REWARD_POOL_LIQUIDITY = 1e12;
    uint256 public constant MIN_REWARD_POOL_USDC_BALANCE = 1_000e6;
    uint256 public constant MAX_V4_POOL_PRICE_DEVIATION_BPS = 1_000;
    uint256 public constant MAX_EXPECTED_APR = 5e17;

    /// @notice Address allowed to update oracle pool configuration
    address public management;

    /// @notice UniV3 fee used for quoting GROVE -> USDC
    uint24 public rewardToBaseUniV3Fee = DEFAULT_REWARD_TO_BASE_UNI_V3_FEE;

    /// @notice UniV4 pools used as fallback pricing candidates
    UniV4PoolConfig[] internal v4Pools;

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    function _onlyManagement() internal view {
        require(msg.sender == management, "!management");
    }

    constructor() {
        management = msg.sender;
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID, groveIsToken0: false}));
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID_TWO, groveIsToken0: false}));
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID_THREE, groveIsToken0: false}));
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID_FOUR, groveIsToken0: false}));
        emit ManagementTransferred(msg.sender);
    }

    /**
     * @param _strategy The strategy to get the apr for. Not a used variable in this case.
     * @param _delta The difference in debt.
     * @return oracleApr The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(address _strategy, int256 _delta) external view returns (uint256 oracleApr) {
        // pull total staked and reward rate from staking contract
        uint256 assets = IStaking(STAKING).totalSupply();
        uint256 rewardRate = IStaking(STAKING).rewardRate(); // tokens per second

        if (block.timestamp > IStaking(STAKING).periodFinish()) {
            return 0;
        }

        uint256 price = _grovePrice();

        // adjust for ∆ assets
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        // Don't divide by 0. With no staked assets, the implied APR is outside the sane oracle range.
        if (assets == 0) revert("apr too high");

        // price is returned as 1e18 USDS per GROVE
        oracleApr = (rewardRate * SECONDS_PER_YEAR * price) / (assets);
        require(oracleApr <= MAX_EXPECTED_APR, "apr too high");
    }

    function setManagement(address _management) external onlyManagement {
        require(_management != address(0), "!management");
        management = _management;
        emit ManagementTransferred(_management);
    }

    function setUniV3Fee(uint24 _rewardToBaseUniV3Fee) external onlyManagement {
        require(_uniV3PoolForFee(_rewardToBaseUniV3Fee) != address(0), "!pool");
        rewardToBaseUniV3Fee = _rewardToBaseUniV3Fee;
        emit UniV3FeeSet(_rewardToBaseUniV3Fee);
    }

    function setUniV4Pool(bytes32 _poolId, bool _groveIsToken0) external onlyManagement {
        require(_poolId != bytes32(0), "!pool");
        delete v4Pools;
        v4Pools.push(UniV4PoolConfig({poolId: _poolId, groveIsToken0: _groveIsToken0}));
        emit UniV4PoolSet(_poolId, _groveIsToken0);
    }

    function setUniV4Pools(bytes32[] calldata _poolIds, bool[] calldata _groveIsToken0) external onlyManagement {
        _setUniV4Pools(_poolIds, _groveIsToken0);
    }

    function addUniV4Pool(bytes32 _poolId, bool _groveIsToken0) external onlyManagement {
        require(_poolId != bytes32(0), "!pool");
        require(!_hasUniV4Pool(_poolId), "duplicate");

        v4Pools.push(UniV4PoolConfig({poolId: _poolId, groveIsToken0: _groveIsToken0}));
        emit UniV4PoolAdded(_poolId, _groveIsToken0);
    }

    function removeUniV4Pool(uint256 _index) external onlyManagement {
        uint256 length = v4Pools.length;
        require(length > 1, "!pool");
        require(_index < length, "!index");

        bytes32 removedPoolId = v4Pools[_index].poolId;
        v4Pools[_index] = v4Pools[length - 1];
        v4Pools.pop();

        emit UniV4PoolRemoved(removedPoolId);
    }

    function uniV3Pool() external view returns (address) {
        return _uniV3Pool();
    }

    function uniV4PoolCount() external view returns (uint256) {
        return v4Pools.length;
    }

    function uniV4Pool(uint256 _index) external view returns (bytes32 poolId, bool groveIsToken0) {
        UniV4PoolConfig memory pool = v4Pools[_index];
        return (pool.poolId, pool.groveIsToken0);
    }

    function groveUsdcV4PoolId() external view returns (bytes32) {
        return v4Pools[0].poolId;
    }

    function v4GroveIsToken0() external view returns (bool) {
        return v4Pools[0].groveIsToken0;
    }

    function bestUniV4Pool() external view returns (bytes32 poolId, bool groveIsToken0, uint128 liquidity) {
        (poolId, groveIsToken0, liquidity,) = _selectedV4Pool();
    }

    function selectedUniV4Pool()
        external
        view
        returns (bytes32 poolId, bool groveIsToken0, uint128 liquidity, uint256 price)
    {
        return _selectedV4Pool();
    }

    function _grovePrice() internal view returns (uint256) {
        if (_v3PoolHasUsableLiquidity()) {
            try UniswapV3SwapSimulator.simulateExactInputSingle(
                ISwapRouter(UNISWAP_V3_ROUTER),
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: GROVE,
                    tokenOut: USDC,
                    fee: rewardToBaseUniV3Fee,
                    recipient: address(0),
                    deadline: block.timestamp,
                    amountIn: 1e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) returns (
                uint256 output
            ) {
                if (output > 0) return output * 1e12;
            } catch {}
        }

        (,,, uint256 price) = _selectedV4Pool();

        if (price > 0) return price;

        revert("insufficient pool liquidity");
    }

    function _v3PoolHasUsableLiquidity() internal view returns (bool) {
        address pool = _uniV3Pool();
        if (pool == address(0)) return false;

        return IUniswapV3Pool(pool).liquidity() >= MIN_REWARD_POOL_LIQUIDITY
            && IERC20(USDC).balanceOf(pool) >= MIN_REWARD_POOL_USDC_BALANCE;
    }

    function _v4GrovePrice(uint160 sqrtPriceX96, bool groveIsToken0) internal pure returns (uint256) {
        if (groveIsToken0) {
            return _quoteToken1ForToken0(sqrtPriceX96, 1e18) * 1e12;
        }

        return _quoteToken0ForToken1(sqrtPriceX96, 1e18) * 1e12;
    }

    function _selectedV4Pool()
        internal
        view
        returns (bytes32 poolId, bool groveIsToken0, uint128 liquidity, uint256 price)
    {
        uint256 length = v4Pools.length;
        UniV4PoolQuote[] memory quotes = new UniV4PoolQuote[](length);
        uint256 quoteCount;

        for (uint256 i; i < length; ++i) {
            UniV4PoolConfig memory pool = v4Pools[i];

            try UNISWAP_V4_STATE_VIEW.getLiquidity(pool.poolId) returns (uint128 poolLiquidity) {
                if (poolLiquidity < MIN_REWARD_POOL_LIQUIDITY) continue;

                try UNISWAP_V4_STATE_VIEW.getSlot0(pool.poolId) returns (
                    uint160 poolSqrtPriceX96, int24, uint24, uint24
                ) {
                    if (poolSqrtPriceX96 == 0) continue;

                    uint256 poolPrice = _v4GrovePrice(poolSqrtPriceX96, pool.groveIsToken0);
                    if (poolPrice == 0) continue;

                    quotes[quoteCount++] = UniV4PoolQuote({
                        poolId: pool.poolId,
                        groveIsToken0: pool.groveIsToken0,
                        liquidity: poolLiquidity,
                        price: poolPrice
                    });
                } catch {}
            } catch {}
        }

        if (quoteCount == 0) return (bytes32(0), false, 0, 0);

        uint256 medianPrice = _medianPrice(quotes, quoteCount);
        uint256 selectedIndex = type(uint256).max;

        for (uint256 i; i < quoteCount; ++i) {
            if (!_withinV4PriceDeviation(quotes[i].price, medianPrice)) continue;

            if (selectedIndex == type(uint256).max || quotes[i].liquidity > quotes[selectedIndex].liquidity) {
                selectedIndex = i;
            }
        }

        if (selectedIndex == type(uint256).max) return (bytes32(0), false, 0, 0);

        UniV4PoolQuote memory selected = quotes[selectedIndex];
        return (selected.poolId, selected.groveIsToken0, selected.liquidity, selected.price);
    }

    function _medianPrice(UniV4PoolQuote[] memory quotes, uint256 quoteCount) internal pure returns (uint256) {
        uint256[] memory prices = new uint256[](quoteCount);

        for (uint256 i; i < quoteCount; ++i) {
            prices[i] = quotes[i].price;
        }

        for (uint256 i = 1; i < quoteCount; ++i) {
            uint256 price = prices[i];
            uint256 j = i;

            while (j > 0 && prices[j - 1] > price) {
                prices[j] = prices[j - 1];
                --j;
            }

            prices[j] = price;
        }

        uint256 mid = quoteCount / 2;
        if (quoteCount % 2 == 1) return prices[mid];

        uint256 lower = prices[mid - 1];
        return lower + ((prices[mid] - lower) / 2);
    }

    function _withinV4PriceDeviation(uint256 price, uint256 referencePrice) internal pure returns (bool) {
        uint256 deviation = price > referencePrice ? price - referencePrice : referencePrice - price;
        return deviation <= FullMath.mulDiv(referencePrice, MAX_V4_POOL_PRICE_DEVIATION_BPS, MAX_BPS);
    }

    function _setUniV4Pools(bytes32[] calldata _poolIds, bool[] calldata _groveIsToken0) internal {
        uint256 length = _poolIds.length;
        require(length > 0 && length == _groveIsToken0.length, "length");

        delete v4Pools;
        for (uint256 i; i < length; ++i) {
            bytes32 poolId = _poolIds[i];
            require(poolId != bytes32(0), "!pool");

            for (uint256 j; j < i; ++j) {
                require(poolId != _poolIds[j], "duplicate");
            }

            v4Pools.push(UniV4PoolConfig({poolId: poolId, groveIsToken0: _groveIsToken0[i]}));
        }

        emit UniV4PoolsSet(_poolIds, _groveIsToken0);
    }

    function _hasUniV4Pool(bytes32 _poolId) internal view returns (bool) {
        uint256 length = v4Pools.length;
        for (uint256 i; i < length; ++i) {
            if (v4Pools[i].poolId == _poolId) return true;
        }

        return false;
    }

    function _uniV3Pool() internal view returns (address) {
        return _uniV3PoolForFee(rewardToBaseUniV3Fee);
    }

    function _uniV3PoolForFee(uint24 _fee) internal view returns (address) {
        return IUniswapV3Factory(ISwapRouterWithFactory(UNISWAP_V3_ROUTER).factory()).getPool(GROVE, USDC, _fee);
    }

    function _quoteToken1ForToken0(uint160 sqrtPriceX96, uint256 baseAmount) internal pure returns (uint256) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return FullMath.mulDiv(ratioX192, baseAmount, Q192);
        }

        uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        return FullMath.mulDiv(ratioX128, baseAmount, 1 << 128);
    }

    function _quoteToken0ForToken1(uint160 sqrtPriceX96, uint256 baseAmount) internal pure returns (uint256) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return FullMath.mulDiv(Q192, baseAmount, ratioX192);
        }

        uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        return FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
    }
}
```
