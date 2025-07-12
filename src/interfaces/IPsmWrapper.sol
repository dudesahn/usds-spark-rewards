// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface IPsmWrapper {
    function sellGem(address, uint256) external returns (uint256);
}
