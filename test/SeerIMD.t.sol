// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SeerIMD} from "../src/SeerIMD.sol";

/// @dev Test-only deployer; demonstrates that CREATE credits the contract, not the transaction sender.
contract TokenFactoryFixture {
    function deploy() external returns (SeerIMD) {
        return new SeerIMD();
    }
}

contract SeerIMDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    SeerIMD private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;
    address private stranger;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        stranger = makeAddr("stranger");
        vm.prank(deployer);
        token = new SeerIMD();
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "SeerIMD");
        assertEq(token.symbol(), "SEER");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function testConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(deployer);
        SeerIMD created = new SeerIMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(created));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(deployer))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testFactoryReceivesEntireSupply() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice);
        SeerIMD created = factory.deploy();

        assertEq(created.balanceOf(address(factory)), SUPPLY);
        assertEq(created.balanceOf(alice), 0);
        assertEq(created.balanceOf(address(this)), 0);
        assertEq(created.totalSupply(), SUPPLY);
    }

    /// @dev Tests token accounting on the launch paths; this is not a Uniswap pool simulation.
    function testLaunchDistributionClaimsAndPoolTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        SeerIMD launched = factory.deploy();
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainder = makeAddr("remainder");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainderShare = SUPPLY - swarmShare - poolShare;

        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarmShare));
        assertTrue(launched.transfer(poolManager, poolShare));
        assertTrue(launched.transfer(remainder, remainderShare));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(poolManager), poolShare);
        assertEq(launched.balanceOf(remainder), remainderShare);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarmShare);

        uint256 traded = 125 ether;
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, traded));
        assertEq(launched.balanceOf(bob), traded);
        assertEq(launched.balanceOf(poolManager), poolShare - traded);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, traded));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 17 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 17 ether));

        assertEq(token.balanceOf(deployer), SUPPLY - 17 ether);
        assertEq(token.balanceOf(alice), 17 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testEntireSupplyCanMove() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testSelfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferToTokenContractIsOrdinaryTransfer() public {
        vm.prank(deployer);
        assertTrue(token.transfer(address(token), 1 ether));
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferAboveBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1
            )
        );
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testSelfTransferStillRequiresBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function testTransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(alice);
        token.transfer(address(0), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApproveEmitsEventAndDoesNotMoveBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 27 ether);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 27 ether));

        assertEq(token.allowance(deployer, spender), 27 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function testApprovalCanBeReplacedAndRevoked() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100 ether));
        assertTrue(token.approve(spender, 5 ether));
        assertEq(token.allowance(deployer, spender), 5 ether);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function testTransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 15 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 10 ether));
        assertEq(token.allowance(deployer, spender), 5 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 5 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(bob), 5 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteAllowanceIsNotDecreased() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 10 ether));
        assertTrue(token.transferFrom(deployer, bob, 5 ether));
        vm.stopPrank();

        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY - 15 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);
    }

    function testTransferFromSelfConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(deployer);
        token.approve(spender, 7 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 7 ether));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function testZeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferFromWithoutAllowanceRevertsEvenForDeployer() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1)
        );
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function testHolderUsingTransferFromAlsoNeedsAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1)
        );
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    function testAllowanceCannotBeUsedByAnotherSpender() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1)
        );
        vm.prank(stranger);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 10 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function testTransferFromAboveAllowanceRevertsWithoutStateChange() public {
        vm.prank(deployer);
        token.approve(spender, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5 ether, 5 ether + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, 5 ether + 1);

        assertEq(token.allowance(deployer, spender), 5 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferFromFailureRestoresAllowanceWhenBalanceIsInsufficient() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10 ether
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);

        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferFromToZeroRevertsAndRestoresAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 10 ether);

        assertEq(token.allowance(deployer, spender), 10 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromZeroSenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testNoMintBurnAdminOrUpgradeEntryPoints() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);

        bytes[] memory calls = new bytes[](23);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", stranger, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("setOwner(address)", stranger);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", stranger);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", stranger);
        calls[7] = abi.encodeWithSignature("initialize(address)", stranger);
        calls[8] = abi.encodeWithSignature("unpause()");
        calls[9] = abi.encodeWithSignature("setMinter(address)", stranger);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[12] = abi.encodeWithSignature("blocklist(address)", alice);
        calls[13] = abi.encodeWithSignature("freeze(address)", alice);
        calls[14] = abi.encodeWithSignature("freezeAccount(address)", alice);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[16] = abi.encodeWithSignature("setBlocked(address,bool)", alice, true);
        calls[17] = abi.encodeWithSignature("lock(address)", alice);
        calls[18] = abi.encodeWithSignature("disableTransfers()");
        calls[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[20] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 100 ether);
        calls[21] = abi.encodeWithSignature("seize(address)", alice);
        calls[22] = abi.encodeWithSignature("burn(uint256)", 100 ether);

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unexpected entry point");
            vm.prank(stranger);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached an unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100 ether);
            assertEq(token.balanceOf(stranger), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function testRejectsNativeCurrencyAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool received,) = address(token).call{value: 1 ether}("");
        assertFalse(received);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzConstructorCreditsImmediateDeployer(address account) public {
        vm.assume(account != address(0));
        vm.prank(account);
        SeerIMD created = new SeerIMD();
        assertEq(created.balanceOf(account), SUPPLY);
        assertEq(created.totalSupply(), SUPPLY);
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, SUPPLY);
        uint256 beforeRecipient = token.balanceOf(recipient);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));

        if (recipient == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), beforeRecipient + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzOverspendingTransferIsAtomic(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount
            )
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApproveSupportsAllAmounts(uint256 amount) public {
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromTracksAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));

        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(
            token.allowance(deployer, spender),
            approved == type(uint256).max ? type(uint256).max : approved - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromInsufficientAllowanceIsAtomic(uint256 approved, uint256 amount)
        public
    {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);

        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
