// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IUniswapV4StateView {
    function getSlot0(bytes32 poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

    function getLiquidity(bytes32 poolId) external view returns (uint128 liquidity);

    function getTickLiquidity(bytes32 poolId, int24 tick)
        external
        view
        returns (uint128 liquidityGross, int128 liquidityNet);

    function getTickBitmap(bytes32 poolId, int16 wordPosition) external view returns (uint256 tickBitmap);
}
