# Orientation

Target worktree: `/private/tmp/usds-grove-pashov-f8f796d-20260721T194201Z`

Target commit: `f8f796db93c52432cca0ed26861e94f5aaf20975`

Primary audit scope:

- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

Supporting context in the source bundle:

- `src/interfaces/IStaking.sol`
- `src/interfaces/IPsmWrapper.sol`
- `src/interfaces/IUniswapV4StateView.sol`
- `src/libraries/UniswapV3SwapSimulator.sol`
- `src/libraries/UniswapV3SwapSimulatorCore.sol`
- selected fork-test context from `src/test/utils/Setup.sol`, `src/test/Operation.t.sol`, and `src/test/Oracle.t.sol`

X-ray artifacts are available at:

- `x-ray/x-ray.md`
- `x-ray/entry-points.md`
- `x-ray/invariants.md`
- `x-ray/architecture.svg`
- `x-ray/git-security-analysis.json`

Use the x-ray artifacts only for orientation: scope, entry points, invariants, dependency map, and live-environment notes. Do not treat x-ray statements as evidence. Every finding or lead must be supported by source code, concrete execution reasoning, or a local validation artifact.

Reporting rule for this run: output both validated FINDING blocks and plausible LEAD blocks. Do not include style notes, gas notes, admin-only-functions-do-admin-things, generic trusted-admin-can-rug claims, or unsupported speculation.
# Source Bundle

Target commit: f8f796db93c52432cca0ed26861e94f5aaf20975
Primary scope: src/GroveCompounder.sol and src/periphery/GroveCompounderAprOracle.sol
Supporting context is included after the primary scope and should not expand finding scope unless a primary-scope attack path depends on it.

## File: src/GroveCompounder.sol
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

## File: src/periphery/GroveCompounderAprOracle.sol
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

## File: src/interfaces/IStaking.sol
```solidity
// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface IStaking {
    function stakingToken() external view returns (address);

    function rewardsToken() external view returns (address);

    function rewardsDistribution() external view returns (address);

    function paused() external view returns (bool);

    function balanceOf(address) external view returns (uint256);

    function earned(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function periodFinish() external view returns (uint256);

    function stake(uint256 _amount, uint16 _referral) external;

    function withdraw(uint256 _amount) external;

    function notifyRewardAmount(uint256 _amount) external;

    function setPaused(bool _paused) external;

    function getReward() external;
}
```

## File: src/interfaces/IPsmWrapper.sol
```solidity
// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface IPsmWrapper {
    function sellGem(address, uint256) external returns (uint256);

    function tin() external view returns (uint256);

    function usds() external view returns (address);

    function gem() external view returns (address);
}
```

## File: src/interfaces/IUniswapV4StateView.sol
```solidity
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IUniswapV4StateView {
    function getSlot0(bytes32 poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

    function getLiquidity(bytes32 poolId) external view returns (uint128 liquidity);
}
```

## File: src/libraries/UniswapV3SwapSimulator.sol
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

## File: src/libraries/UniswapV3SwapSimulatorCore.sol
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

## File: src/test/utils/Setup.sol
```solidity
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {GroveCompounder, ERC20, Auction, IStaking} from "src/GroveCompounder.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is Test, IEvents {
    address public constant GROVE_USDC_V3_POOL = 0x5D23797587B2c17414384384098291c0B1Fe1362;
    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    bytes32 public constant GROVE_USDC_V4_POOL_ID = 0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 public constant GROVE_USDC_V4_POOL_ID_TWO =
        0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 public constant GROVE_USDC_V4_POOL_ID_THREE =
        0xb557b2447a4723741959fe7ebd5a37375023931d19f6383cc83bd0d9c8397bb9;
    bytes32 public constant GROVE_USDC_V4_POOL_ID_FOUR =
        0x2e53ef1a957f41bfba562bac317881d6f0ef2d6c217c7279c11b0878f9791ad5;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 public constant MIN_REWARD_POOL_LIQUIDITY = 1e12;
    uint256 public constant MIN_REWARD_POOL_USDC_BALANCE = 1_000e6;

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    // auction to be used by our strategy
    Auction public auction;
    AuctionFactory public auctionFactory = AuctionFactory(0xCfA510188884F199fcC6e750764FAAbE6e56ec40);

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the staking contract
    address public staking;

    // Address of the real deployed Factory
    address public factory;

    bool public defaultedToAuction;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz deposit sizes that keep live-fork reward accounting manageable.
    uint256 public maxFuzzAmount = 10_000e18;
    uint256 public minFuzzAmount = 10_000;

    // use this as a cutoff to expect when deposits/withdrawals won't cause detectable APR differences
    uint256 public constant ORACLE_FUZZ_MIN = 1e15;

    // use this as a cutoff to expect when we won't generate meaningful profit
    uint256 public constant PROFIT_FUZZ_MIN = 10_000e18;

    // set profit max unlock time for 1 days since rewards are paid weekly
    uint256 public profitMaxUnlockTime = 1 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["USDS"]);

        // Set decimals
        decimals = asset.decimals();
        staking = 0x4E41488C19cD35EB4de3083Fc3e204854c75c86a;

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // setup our auction with our rewards token to sell
        setUpAuction(strategy.REWARDS_TOKEN());

        // set min amount to sell super low for testing ~($1.50)
        vm.prank(management);
        strategy.setMinAmountToSell(50e18);

        defaultToAuction();

        factory = strategy.FACTORY();

        // manually top-up rewards so we don't run into EOW with no rewards
        uint256 periodFinish = IStaking(staking).periodFinish();
        uint256 timeLeft = periodFinish > block.timestamp ? periodFinish - block.timestamp : 0;
        uint256 week = 86400 * 7;
        uint256 toSend = timeLeft < week ? IStaking(staking).rewardRate() * (week - timeLeft) : 0; // use current rewardRate, scaled by week time elapsed
        if (toSend > 0) {
            airdrop(ERC20(strategy.REWARDS_TOKEN()), staking, toSend * 2); // add rewards without clobbering already-funded emissions
            vm.prank(IStaking(staking).rewardsDistribution());
            IStaking(staking).notifyRewardAmount(toSend);
        }

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        vm.startPrank(management);
        IStrategyInterface _strategy = IStrategyInterface(address(new GroveCompounder()));

        // setup the strategy
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _strategy.setKeeper(keeper);
        _strategy.setEmergencyAdmin(emergencyAdmin);
        _strategy.setProfitMaxUnlockTime(profitMaxUnlockTime);

        // check that deposits are closed
        assertEq(_strategy.availableDepositLimit(user), 0, "!deposit");
        _strategy.setAllowed(user, true);
        assertGt(_strategy.availableDepositLimit(user), 0, "!deposit");
        _strategy.setAllowed(user, false);
        vm.stopPrank();

        // prank owner of staking contract to make sure deposit limit is zero when paused
        vm.startPrank(0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB);
        IStaking(_strategy.STAKING()).setPaused(true);
        assertEq(_strategy.availableDepositLimit(user), 0, "!deposit");
        IStaking(_strategy.STAKING()).setPaused(false);
        vm.stopPrank();

        // turn on open deposits
        vm.prank(management);
        _strategy.setOpen(true);

        return address(_strategy);
    }

    function setUpAuction(address _token) public {
        // deploy auction for the strategy
        auction = Auction(auctionFactory.createNewAuction(address(asset), address(strategy), management));

        // enable reward token on our auction
        vm.prank(management);
        auction.enable(_token);
    }

    function rewardSalePoolHasUsableLiquidity() public view returns (bool) {
        return IUniswapV3Pool(GROVE_USDC_V3_POOL).liquidity() >= MIN_REWARD_POOL_LIQUIDITY
            && ERC20(USDC).balanceOf(GROVE_USDC_V3_POOL) >= MIN_REWARD_POOL_USDC_BALANCE;
    }

    function rewardV4PoolHasUsableLiquidity() public view returns (bool) {
        return _v4PoolHasUsableLiquidity(GROVE_USDC_V4_POOL_ID) || _v4PoolHasUsableLiquidity(GROVE_USDC_V4_POOL_ID_TWO)
            || _v4PoolHasUsableLiquidity(GROVE_USDC_V4_POOL_ID_THREE)
            || _v4PoolHasUsableLiquidity(GROVE_USDC_V4_POOL_ID_FOUR);
    }

    function _v4PoolHasUsableLiquidity(bytes32 _poolId) internal view returns (bool) {
        try UNISWAP_V4_STATE_VIEW.getLiquidity(_poolId) returns (uint128 liquidity) {
            return liquidity >= MIN_REWARD_POOL_LIQUIDITY;
        } catch {
            return false;
        }
    }

    function rewardPricingHasUsableLiquidity() public view returns (bool) {
        return rewardSalePoolHasUsableLiquidity() || rewardV4PoolHasUsableLiquidity();
    }

    function defaultToAuction() internal {
        vm.startPrank(management);
        strategy.setAuction(address(auction));
        if (!strategy.useAuction()) {
            strategy.setUseAuction(true);
        }
        vm.stopPrank();

        defaultedToAuction = true;
    }

    function simulateAuction(uint256 _profitAmount) public {
        // cache our rewards token
        address rewardsToken = strategy.REWARDS_TOKEN();

        // kick the auction
        vm.prank(keeper);
        strategy.kickAuction(rewardsToken);

        // check for reward token balance in auction
        uint256 rewardBalance = ERC20(rewardsToken).balanceOf(address(auction));
        uint256 strategyBalance = ERC20(rewardsToken).balanceOf(address(auction));
        console2.log("Reward token sitting in our strategy", strategyBalance / 1e18, "* 1e18");

        // if we have reward tokens, sweep it out, and send back our designated profitAmount
        if (rewardBalance > 0) {
            console2.log("Reward token sitting in our auction", rewardBalance / 1e18, "* 1e18");

            vm.prank(address(auction));
            ERC20(rewardsToken).transfer(user, rewardBalance);
            airdrop(asset, address(strategy), _profitAmount);
            rewardBalance = ERC20(rewardsToken).balanceOf(address(auction));
        }

        // confirm that we swept everything out
        assertEq(rewardBalance, 0, "!rewardBalance");
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["USDS"] = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    }
}
```

## File: src/test/Operation.t.sol
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "src/test/utils/Setup.sol";

contract OperationTest is Setup {
    address internal constant PSM_WRAPPER =
        0xA188EEC8F81263234dA3622A406892F3D630f98c;

    function setUp() public virtual override {
        super.setUp();
    }

    function enableAuction() internal {
        if (strategy.useAuction()) return;

        vm.startPrank(management);
        strategy.setAuction(address(auction));
        strategy.setUseAuction(true);
        vm.stopPrank();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.referral(), 2009);
        // TODO: add additional check on strat params
    }

    function test_rewardSaleModeDefaultsToAuction() public {
        assertTrue(strategy.useAuction());
        assertEq(strategy.auction(), address(auction));
    }

    function test_swapPathRequiresZeroPsmFee() public {
        uint256 _amount = 10_000e18;

        mintAndDepositIntoStrategy(strategy, user, _amount);
        skip(strategy.profitMaxUnlockTime());

        vm.prank(management);
        strategy.setUseAuction(false);

        vm.mockCall(
            PSM_WRAPPER,
            abi.encodeWithSelector(bytes4(keccak256("tin()"))),
            abi.encode(uint256(1))
        );

        vm.prank(keeper);
        vm.expectRevert("!psmFee");
        strategy.report();
    }

    function test_auctionPathIgnoresPsmFee() public {
        uint256 _amount = 10_000e18;

        mintAndDepositIntoStrategy(strategy, user, _amount);
        skip(strategy.profitMaxUnlockTime());

        enableAuction();

        vm.mockCall(
            PSM_WRAPPER,
            abi.encodeWithSelector(bytes4(keccak256("tin()"))),
            abi.encode(uint256(1))
        );

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 rewardBalance = ERC20(strategy.REWARDS_TOKEN()).balanceOf(
            address(auction)
        );
        assertGt(rewardBalance, 0, "!auction");
    }

    // test a fixed deposit amount so we can see our logs through the active reward sale mode
    function test_operation_fixed() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        uint256 claimable = strategy.claimableRewards();
        assertGt(claimable, 0, "!rewards");
        console2.log("Claimable rewards:", claimable / 1e18, "* 1e18");

        if (!defaultedToAuction) {
            // can't kick auction if useAuction is false
            vm.prank(management);
            vm.expectRevert("!useAuction");
            strategy.kickAuction(address(asset));
        }

        enableAuction();

        // Report rewards into the auction.
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from auction report:",
            profit / 1e18,
            "* 1e18 USDS"
        );
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 rewardBalance = ERC20(strategy.REWARDS_TOKEN()).balanceOf(
            address(auction)
        );
        assertGt(rewardBalance, 0, "!auction");

        // simulate our auction process
        uint256 simulatedProfit = _amount / 200; // 0.5% profit
        simulateAuction(simulatedProfit);

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from auction report:",
            profitTwo / 1e18,
            "* 1e18 USDS"
        );
        assertGt(profitTwo, 0, "!profit");
        assertEq(lossTwo, 0, "!loss");

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // manually claim some rewards
        vm.startPrank(management);
        assertEq(strategy.balanceOfRewards(), 0, "!rewards");
        strategy.claimRewards();
        assertGt(strategy.balanceOfRewards(), 0, "!rewards");
        // also do other setters (uniV3 fees, referral)
        strategy.setUniV3Fees(100);
        strategy.setReferral(6969);
        vm.stopPrank();

        // airdrop some USDS to the strategy to test our revert
        airdrop(asset, address(strategy), 100e18);
        vm.prank(management);
        vm.expectRevert("!asset");
        strategy.kickAuction(address(asset));

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGt(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operation_auction_extra() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        uint256 claimable = strategy.claimableRewards();
        assertGt(claimable, 0, "!rewards");
        console2.log("Claimable rewards:", claimable / 1e18, "* 1e18");

        enableAuction();

        // Report profit, should come through our auction
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from auction report:",
            profit / 1e18,
            "* 1e18 USDS"
        );
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // even though we don't get profit, we should have rewards in the auction contract
        uint256 rewardBalance = ERC20(strategy.REWARDS_TOKEN()).balanceOf(
            address(auction)
        );
        assertGt(rewardBalance, 0, "!auction");

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // check some of our views
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.balanceOfAsset(), 0, "!asset");
        assertEq(strategy.balanceOfStake(), _amount, "!stake");
        assertEq(strategy.claimableRewards(), 0, "!rewards");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // make sure we have some claimable profit
        assertGt(strategy.claimableRewards(), 0, "!rewards");

        enableAuction();

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        if (_amount < PROFIT_FUZZ_MIN) {
            assertGe(profit, 0, "!profit");
        } else {
            assertGt(profit, 0, "!profit");
        }
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        if (_amount < PROFIT_FUZZ_MIN) {
            assertGe(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        } else {
            assertGt(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        }
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_000));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        enableAuction();

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_000));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        enableAuction();

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        enableAuction();

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}
```

## File: src/test/Oracle.t.sol
```solidity
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "src/test/utils/Setup.sol";

import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";

interface IUniV3Router {
    function factory() external view returns (address);
}

interface IUniV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

contract OracleTest is Setup {
    GroveCompounderAprOracle public oracle;

    uint256 public fuzzAmount;

    function setUp() public override {
        super.setUp();
        oracle = new GroveCompounderAprOracle();
    }

    function test_oracleDefaults() public {
        assertEq(oracle.management(), address(this));
        assertEq(oracle.rewardToBaseUniV3Fee(), oracle.DEFAULT_REWARD_TO_BASE_UNI_V3_FEE());
        assertEq(oracle.uniV3Pool(), GROVE_USDC_V3_POOL);
        assertEq(oracle.uniV4PoolCount(), 4);
        assertEq(oracle.groveUsdcV4PoolId(), GROVE_USDC_V4_POOL_ID);
        assertTrue(!oracle.v4GroveIsToken0());

        (bytes32 poolId, bool groveIsToken0) = oracle.uniV4Pool(0);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID);
        assertTrue(!groveIsToken0);

        (poolId, groveIsToken0) = oracle.uniV4Pool(1);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_TWO);
        assertTrue(!groveIsToken0);

        (poolId, groveIsToken0) = oracle.uniV4Pool(2);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_THREE);
        assertTrue(!groveIsToken0);

        (poolId, groveIsToken0) = oracle.uniV4Pool(3);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_FOUR);
        assertTrue(!groveIsToken0);
    }

    function test_managementCanUpdateUniV3Fee() public {
        uint24 newFee = 500;
        address factory = IUniV3Router(oracle.UNISWAP_V3_ROUTER()).factory();

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setUniV3Fee(newFee);

        vm.expectRevert("!pool");
        oracle.setUniV3Fee(newFee);

        vm.mockCall(
            factory,
            abi.encodeWithSelector(IUniV3Factory.getPool.selector, oracle.GROVE(), oracle.USDC(), newFee),
            abi.encode(GROVE_USDC_V3_POOL)
        );

        oracle.setUniV3Fee(newFee);

        assertEq(oracle.rewardToBaseUniV3Fee(), newFee);
        assertEq(oracle.uniV3Pool(), GROVE_USDC_V3_POOL);
    }

    function test_managementCanUpdateUniV4Pool() public {
        bytes32 newPoolId = keccak256("new grove/usdc v4 pool");

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setUniV4Pool(newPoolId, true);

        oracle.setUniV4Pool(newPoolId, true);

        assertEq(oracle.uniV4PoolCount(), 1);
        assertEq(oracle.groveUsdcV4PoolId(), newPoolId);
        assertTrue(oracle.v4GroveIsToken0());
    }

    function test_managementCanSetUniV4Pools() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = GROVE_USDC_V4_POOL_ID_TWO;
        poolIds[1] = GROVE_USDC_V4_POOL_ID_THREE;

        bool[] memory groveIsToken0 = new bool[](2);
        groveIsToken0[0] = false;
        groveIsToken0[1] = true;

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        bool[] memory shortDirections = new bool[](1);
        vm.expectRevert("length");
        oracle.setUniV4Pools(poolIds, shortDirections);

        poolIds[1] = bytes32(0);
        vm.expectRevert("!pool");
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        poolIds[1] = poolIds[0];
        vm.expectRevert("duplicate");
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        poolIds[1] = GROVE_USDC_V4_POOL_ID_THREE;
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        assertEq(oracle.uniV4PoolCount(), 2);

        (bytes32 poolId, bool isToken0) = oracle.uniV4Pool(0);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_TWO);
        assertTrue(!isToken0);

        (poolId, isToken0) = oracle.uniV4Pool(1);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_THREE);
        assertTrue(isToken0);
    }

    function test_managementCanAddAndRemoveUniV4Pool() public {
        bytes32 newPoolId = keccak256("new grove/usdc v4 pool");

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.addUniV4Pool(newPoolId, true);

        oracle.addUniV4Pool(newPoolId, true);

        assertEq(oracle.uniV4PoolCount(), 5);
        (bytes32 poolId, bool isToken0) = oracle.uniV4Pool(4);
        assertEq(poolId, newPoolId);
        assertTrue(isToken0);

        vm.expectRevert("duplicate");
        oracle.addUniV4Pool(newPoolId, true);

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.removeUniV4Pool(3);

        oracle.removeUniV4Pool(4);
        assertEq(oracle.uniV4PoolCount(), 4);

        vm.expectRevert("!index");
        oracle.removeUniV4Pool(4);

        oracle.setUniV4Pool(newPoolId, true);
        vm.expectRevert("!pool");
        oracle.removeUniV4Pool(0);
    }

    function test_oracleSelectsMostLiquidConfiguredV4PoolNearMedian() public {
        bytes32[] memory poolIds = new bytes32[](3);
        poolIds[0] = GROVE_USDC_V4_POOL_ID;
        poolIds[1] = GROVE_USDC_V4_POOL_ID_TWO;
        poolIds[2] = GROVE_USDC_V4_POOL_ID_FOUR;

        bool[] memory groveIsToken0 = new bool[](3);
        groveIsToken0[0] = false;
        groveIsToken0[1] = false;
        groveIsToken0[2] = false;

        oracle.setUniV4Pools(poolIds, groveIsToken0);

        uint128 outlierLiquidity = 10e12;
        uint128 selectedLiquidity = 5e12;

        _mockV4Pool(poolIds[0], outlierLiquidity, 453061755611786389487367678109067002);
        _mockV4Pool(poolIds[1], selectedLiquidity, 487958752947811275626586785558519091);
        _mockV4Pool(poolIds[2], 3e12, 490481118378931851683740558437355049);

        (bytes32 bestPoolId, bool isToken0, uint128 liquidity) = oracle.bestUniV4Pool();

        assertEq(bestPoolId, poolIds[1]);
        assertTrue(!isToken0);
        assertEq(liquidity, selectedLiquidity);

        uint256 price;
        (bestPoolId, isToken0, liquidity, price) = oracle.selectedUniV4Pool();

        assertEq(bestPoolId, poolIds[1]);
        assertTrue(!isToken0);
        assertEq(liquidity, selectedLiquidity);
        assertEq(price, 26_362_000_000_000_000);
    }

    function test_oracleCanUseConfiguredV4PoolTwo() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_TWO);
    }

    function test_oracleCanUseConfiguredV4PoolThree() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_THREE);
    }

    function test_oracleCanUseConfiguredV4PoolFour() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_FOUR);
    }

    function testSimpleOracleCheck() public {
        if (!rewardPricingHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console2.log("currentAPR:", currentApr);
        _assertReasonableApr(currentApr);
    }

    function test_oracleCanUseV4Backup() public {
        _forceV4Pricing();

        if (!rewardV4PoolHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        _assertReasonableApr(currentApr);
    }

    function test_oracleRevertsWhenAprAboveCap() public {
        bytes32 poolId = keccak256("mock grove/usdc v4 pool");
        oracle.setUniV4Pool(poolId, false);

        _forceV4Pricing();
        _mockV4Pool(poolId, 5e12, 487958752947811275626586785558519091);

        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.totalSupply.selector), abi.encode(1e18));
        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.rewardRate.selector), abi.encode(1e18));
        vm.mockCall(
            oracle.STAKING(),
            abi.encodeWithSelector(IStaking.periodFinish.selector),
            abi.encode(block.timestamp + 1 weeks)
        );

        vm.expectRevert("apr too high");
        oracle.aprAfterDebtChange(address(strategy), 0);
    }

    function _checkConfiguredV4Pool(bytes32 _poolId) internal {
        oracle.setUniV4Pool(_poolId, false);
        assertEq(oracle.uniV4PoolCount(), 1);
        assertEq(oracle.groveUsdcV4PoolId(), _poolId);
        assertTrue(!oracle.v4GroveIsToken0());

        _forceV4Pricing();

        if (!_v4PoolHasUsableLiquidity(_poolId)) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        _assertReasonableApr(currentApr);
    }

    function _forceV4Pricing() internal {
        vm.mockCall(
            oracle.uniV3Pool(), abi.encodeWithSelector(bytes4(keccak256("liquidity()"))), abi.encode(uint128(0))
        );
    }

    function _mockV4Pool(bytes32 _poolId, uint128 _liquidity) internal {
        _mockV4Pool(_poolId, _liquidity, uint160(1 << 96));
    }

    function _mockV4Pool(bytes32 _poolId, uint128 _liquidity, uint160 _sqrtPriceX96) internal {
        vm.mockCall(
            address(UNISWAP_V4_STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getLiquidity.selector, _poolId),
            abi.encode(_liquidity)
        );

        vm.mockCall(
            address(UNISWAP_V4_STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, _poolId),
            abi.encode(_sqrtPriceX96, int24(0), uint24(0), uint24(0))
        );
    }

    function checkOracle(address _strategy, uint256 _delta) public {
        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        _assertReasonableApr(currentApr);

        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(_strategy, -int256(_delta));
        _assertReasonableApr(negativeDebtChangeApr);

        // The apr should go up if deposits go down
        if (fuzzAmount < ORACLE_FUZZ_MIN) {
            assertLe(currentApr, negativeDebtChangeApr, "negative change");
        } else {
            assertLt(currentApr, negativeDebtChangeApr, "negative change");
        }

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(_strategy, int256(_delta));
        _assertReasonableApr(positiveDebtChangeApr);

        // The apr should go down if deposits go up
        if (fuzzAmount < ORACLE_FUZZ_MIN) {
            assertGe(currentApr, positiveDebtChangeApr, "positive change");
        } else {
            assertGt(currentApr, positiveDebtChangeApr, "positive change");
        }
    }

    function _assertReasonableApr(uint256 _apr) internal {
        assertGt(_apr, 0, "ZERO");
        assertLe(_apr, oracle.MAX_EXPECTED_APR(), "+50%");
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        if (!rewardPricingHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        fuzzAmount = _amount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}
```
# Senior Auditor's Mindset

This is how a senior auditor thinks. Pattern-matching catches the obvious bugs — your specialty file teaches that. The high-value bugs, the ones everyone else misses, come from HOW you reason about code, not from WHAT bugs you know.

The senior auditor's edge is not "knowing more bug patterns" — it is having internalized mental tools they reach for instinctively when something feels off, when a path seems clean, or when a conclusion comes too quickly.

This file gives you three tools. They are not steps. You reach for the right one the moment the trigger fires — see `shared-rules.md` for the binding trigger→tool protocol. Use them. Trust your discomfort.

A finding is not real until you've traced the attack with concrete values. You are an attacker, not a defender — when you find a bug, deepen the attack; never argue yourself out of one.

---

## 1. The Feynman test (FIRST — use it before anything else)

**This is the first tool. Apply it the moment you open any new function or contract — before you reason about anything else.** Code you have not Feynman'd is code you have not actually understood.

When you read code, STOP and ask: "Can I explain what this function does to someone who doesn't know Solidity?"

Try it. In plain words. The places where your explanation gets fuzzy — where you reach for Solidity jargon instead of plain meaning — are where you're papering over an assumption. That's where bugs hide.

Example: you read `_handleFeeTransfer(zrc20, fee)` and your explanation comes out as "it transfers the fee." That's not Feynman. Feynman is: "it picks up the protocol's commission off the user's payment and moves it to the treasury wallet." Now keep going: what if the payment is in ETH and the function uses an ERC20 method? Your plain-English explanation breaks. Bug.

A senior auditor doesn't trust their understanding until they can explain it without the safety net of technical vocabulary.

---

## 2. Socratic questioning

For every line of code, ask: why is this here? What does it assume? What happens if the assumption breaks?

Don't accept "because that's how it's written" as an answer. Don't accept "the function name says so" as an answer. Drill until you reach the implicit belief the code rests on. The first answer is usually a restatement. The actual assumption is two or three "whys" deeper.

Example: `if (zrc20 != _ETH_ADDRESS_) IERC20(zrc20).transferFrom(msg.sender, address(this), amount);`
- Why is `zrc20 != _ETH_ADDRESS_` checked? → because ETH isn't transferable via transferFrom.
- Why is there no else branch? → because the developer assumed ETH arrives via `msg.value`.
- Where is `msg.value` enforced to equal `amount` for the ETH path? → **nowhere**. Bug.

A senior auditor accepts no "because" without examining it.

---

## 3. Inversion

Every clean path gets a backward pass. After you understand what the code IS supposed to do, ask: how would I make it NOT do that?

Same code, attacker's eye instead of developer's eye. The developer asks "does this work?" The attacker asks "how do I break this?" Read every check and ask "what value slips past it?" Read every state update and ask "what state am I in just before this?"

A senior auditor never reads code only forward.

---

## When to reach for which tool

You don't apply these in order — except Feynman, which is always first. You reach for what the moment calls for:

- Opening any new function or contract → **Feynman** (always — before anything else)
- Trying to understand a line you don't yet → **Socratic**
- Something looks too clean → **Inversion**
- You reached a "bug" conclusion → amplify the attack (chain it, find more victims, lower the precondition cost — do NOT refute it)

The tools are how you keep yourself honest. Without them, you fall into the trap of every junior auditor: trusting your first read, accepting code that "looks right," moving on when something feels off.

Trust your discomfort. Reach for the tool. Don't stop until the discomfort has a name.
# First Principles Agent

You are an attacker that exploits what others can't even name. Ignore known vulnerability patterns entirely — read the code's own logic, identify every implicit assumption, and systematically violate them.

Other agents scan for known patterns, arithmetic, access control, economics, state transitions, and data flow. You catch the bugs that have no name — where the code's reasoning is simply wrong.

## How to attack

**Do not pattern-match.** Forget "reentrancy" and "oracle manipulation." For every line, ask: "this assumes X — break X."

For every state-changing function:

1. **Extract every assumption.** Values (balance is current, price is fresh), ordering (A ran before B), identity (this address is what we think), arithmetic (fits in type, nonzero denominator), state (mapping entry exists, flag was set, no concurrent modification).

2. **Violate it.** Find who controls the inputs. Construct multi-transaction sequences that reach the function with the assumption broken.

3. **Exploit the break.** Trace execution with the violated assumption. Identify corrupted storage and extract value from it.

## Focus areas

- **Stale reads.** Read a value, modify state, reuse the now-stale value — exploit the inconsistency.
- **Desynchronized coupling.** Two storage variables must stay in sync. Find the writer that updates one but not the other.
- **Boundary abuse.** Zero, max, first call, last item, empty array, supply of 1 — find where the code degenerates.
- **Cross-function breaks.** Function A leaves state in configuration X. Find where function B mishandles X.
- **Assumption chains.** A assumes B validates. B assumes A pre-validated. Neither checks — exploit the gap.

Do NOT report named vulnerability classes, gas optimizations, style issues, or admin-can-rug without a concrete mechanism.

## Output fields

Add to FINDINGs:
```
assumption: the specific assumption you violated
violation: how you broke it
proof: concrete trace showing the broken assumption and the extracted value
```
# Shared Scan Rules

## Bundle contents

Your bundle is four concatenated files: all in-scope source code, the SOP (HOW to think), your specialty agent (WHAT to look for), and these shared rules (output format, dedup tags, AND mandatory mental tool protocol).

Read the whole bundle once at the start. The bundle contains all in-scope source. Use Read/Grep only for cross-file searches or out-of-scope context (interfaces/, lib/, mocks/, test/) — do not re-read in-scope files for the initial scan.

**The protocol below applies continuously during source reading — not just before it.** The "read source" phase does not turn off the protocol; every trigger condition fires the moment it occurs, throughout your entire review.

When matching function names, check both `functionName` and `_functionName` (Solidity convention).

## Mental tool protocol — MANDATORY

The three tools in `senior-auditor-sop.md` are NOT optional. Each tool has a specific trigger. **When the trigger fires, you MUST emit the corresponding marker in your output stream BEFORE continuing.** No skipping. The markers live in your working text — they do NOT go into the FINDING/LEAD output blocks.

### Triggers → required markers

| Trigger (the condition) | Marker (required immediately, literal `[Tool: ...]` syntax) | Content |
|---|---|---|
| You open a new function or contract to read | `[Feynman: <name>]` | Explain what it does in plain English — no Solidity jargon, no `mload`/`assembly`/`mstore`/`safeTransfer`/etc. Use as many sentences as you need until the explanation is solid. If your wording slips back to jargon, you're papering over an assumption — keep going. Wherever your plain-English explanation gets fuzzy or you have to reach for a Solidity term to keep it accurate, mark that spot — that is where bugs hide. |
| You stop on a line whose purpose isn't immediately clear | `[Socratic: <file:line> — why?]` | A one-line question that drills past "because that's how it's written." If your first answer is a restatement of the code, ask again. Stop when the answer exposes the implicit belief the code rests on — don't pad with extra steps just to hit a quota. |
| A code path reads as clean / a check looks sufficient / a guard looks correct | `[Inversion: <function>]` | Three concrete attacker moves that attempt to defeat the path. Specific addresses/values/states, not abstractions. |

### Rules

1. **Triggers are not optional.** If the condition fires, the marker follows. Always. No skipping.
2. **Use the literal `[Tool: ...]` syntax.** The orchestrator greps your output for these tags after the run.
3. **You may emit a marker without a trigger.** Extra Feynman / Inversion markers are fine. You may NOT skip a marker after its trigger fired.
4. **The protocol applies to reasoning depth, not output volume.** Heavy use of these tools is what produces the audit work. Skipping them = surface-level scanning, which is the failure mode of every junior auditor.

The orchestrator verifies marker counts after every run. Skipped markers downgrade the value of your findings and are recorded as workflow violations.

## Cross-contract patterns

When you find a bug in one contract, **weaponize that pattern across every other contract in the bundle.** Search by function name AND by code pattern. Finding native/ERC20 confusion in `ContractA.onRevert` means you check every other contract's `onRevert` — missing a repeat instance is an audit failure.

After scanning: escalate every finding to its worst exploitable variant (DoS may hide fund theft). Then revisit every function where you found something and attack the other branches.

## Do not report

Admin-only functions doing admin things. Standard DeFi tradeoffs (MEV, rounding dust, first-depositor with MINIMUM_LIQUIDITY). Self-harm-only bugs. "Admin can rug" without a concrete mechanism.

## Output

Return findings as structured blocks:

FINDINGs have concrete, unguarded, exploitable attack paths. LEADs have real code smells with partial paths — default to LEAD over dropping.

**Every FINDING must have a `proof:` field** — concrete values, traces, or state sequences from the actual code. No proof = LEAD, no exceptions.

**One vulnerability per item.** Same root cause = one item. Different fixes needed = separate items.

```
FINDING | contract: Name | function: func | bug_class: kebab-tag | group_key: Contract | function | bug-class
path: caller → function → state change → impact
proof: concrete values/trace demonstrating the bug
description: one sentence
fix: one-sentence suggestion

LEAD | contract: Name | function: func | bug_class: kebab-tag | group_key: Contract | function | bug-class
code_smells: what you found
description: one sentence explaining trail and what remains unverified
```

The `group_key` enables deduplication: `ContractName | functionName | bug_class`. Agents may add custom fields.
