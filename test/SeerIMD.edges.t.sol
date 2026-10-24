// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SeerIMD} from "src/SeerIMD.sol";

/// @dev Complements the deployment/basic ERC-20 tests with allowance boundaries and recovery
/// after failure. All balances are obtained by real transfers from the constructor's allocation.
/// forge-config: default.fuzz.runs = 1024
contract SeerIMDEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    SeerIMD private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new SeerIMD();
        holder = makeAddr("edge holder");
        recipient = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function testOneWeiDirectAndDelegatedRoundTrip() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, address(this), 1));

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFullSupplyDelegatedSpendExhaustsBalanceAndApproval() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaxMinusOneApprovalIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
    }

    function testMaximumAmountRevertsWithInfiniteApproval() public {
        uint256 amount = type(uint256).max;
        token.approve(spender, amount);
        bytes memory expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount
        );

        vm.expectRevert(expected);
        token.transfer(recipient, amount);
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, amount);

        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteApprovalCanBeReplacedThenRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), 1);
        token.approve(spender, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(recipient), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testInfiniteApprovalDoesNotBypassEmptyBalanceAndWorksAfterRefill() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);

        token.transfer(holder, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 2);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalIsScopedToItsOwner() public {
        token.transfer(holder, 10);
        token.approve(spender, 10);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testSpenderCannotGrantItselfAccessToAnotherOwnersBalance() public {
        vm.prank(spender);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(spender, spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testSelfTransferFromWithApprovalStillRequiresBalance() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(spender, 2);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2)
        );
        vm.prank(spender);
        token.transferFrom(holder, holder, 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroApprovalCannotAuthorizeZeroSpender() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testZeroDelegatedTransferToZeroStillReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzFailedSpendPreservesApprovalAndCanBeRetried(
        uint256 balance,
        uint256 excess,
        bool infinite
    ) public {
        balance = bound(balance, 1, SUPPLY);
        uint256 requested = balance + bound(excess, 1, type(uint256).max - balance);
        uint256 approved = infinite ? type(uint256).max : requested;
        token.transfer(holder, balance);
        vm.prank(holder);
        token.approve(spender, approved);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, requested
            )
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, requested);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), approved);

        // The original approval must still authorize a valid spend after the failed transaction.
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, balance));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), balance);
        assertEq(
            token.allowance(holder, spender),
            approved == type(uint256).max ? approved : approved - balance
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInvalidRecipientPreservesApproval(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : amount;
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApprovalReplacementIsIdempotentAndIsolated(uint256 first, uint256 second)
        public
    {
        token.approve(otherSpender, first);
        token.approve(spender, first);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.allowance(address(this), otherSpender), first);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTwoSpendersHaveIndependentBudgets(uint256 first, uint256 second) public {
        first = bound(first, 1, SUPPLY - 1);
        second = bound(second, 1, SUPPLY - first);
        token.approve(spender, first);
        token.approve(otherSpender, second);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), otherSpender), second);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);
        assertEq(token.allowance(address(this), otherSpender), second);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(address(this), recipient, second));
        assertEq(token.allowance(address(this), otherSpender), 0);
        assertEq(token.balanceOf(holder), first);
        assertEq(token.balanceOf(recipient), second);
        assertEq(token.balanceOf(address(this)), SUPPLY - first - second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplitTransfersAndRoundTripHaveNoFeeOrDust(uint256 amount, uint256 split)
        public
    {
        amount = bound(amount, 1, SUPPLY);
        split = bound(split, 0, amount);
        token.approve(spender, amount);
        token.transfer(holder, amount);
        vm.startPrank(holder);
        assertTrue(token.transfer(recipient, split));
        assertTrue(token.transfer(recipient, amount - split));
        vm.stopPrank();
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);

        vm.prank(recipient);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
