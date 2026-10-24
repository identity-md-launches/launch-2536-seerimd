// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SeerIMD
/// @notice Fixed-supply SEER token with 18 decimals and standard ERC-20 transfers.
/// @dev The immediate deployer receives the entire supply. There are no administrative powers.
contract SeerIMD is ERC20 {
    /// @notice One billion SEER expressed in the smallest token unit (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev During an IdentityMD launch, msg.sender is the deploying factory.
    constructor() ERC20("SeerIMD", "SEER") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
