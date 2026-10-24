// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SeerIMD} from "../src/SeerIMD.sol";

/// @dev Test-only actors and an independent accounting model. Amounts are bounded using the model,
///      so a defect in the token's reported balance cannot silently narrow subsequent test inputs.
contract SeerIMDHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    SeerIMD public immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(address[4] memory actors_) {
        actors = actors_;
        token = new SeerIMD();
        require(token.transfer(actors[0], SUPPLY), "initial distribution failed");
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount;
        if (amountSeed % 4 == 1) {
            amount = type(uint256).max;
        } else if (amountSeed % 4 > 1) {
            amount = bound(amountSeed, 0, SUPPLY);
        }
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        uint256 amount = bound(amountSeed, 0, maximum);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] = approved - amount;
        }
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excessSeed, 1, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount
            )
        );
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectUnapprovedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }
}

contract SeerIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    address[4] private actors;
    SeerIMD private token;
    SeerIMDHandler private handler;

    function setUp() public {
        actors =
            [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        handler = new SeerIMDHandler(actors);
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectOverspend.selector;
        selectors[4] = handler.rejectUnapprovedSpend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariantAllowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j])
                );
            }
        }
    }
}
