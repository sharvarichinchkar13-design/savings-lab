
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SavingsPool} from "./SavingsPool.sol";

contract SavingsPoolTest is Test {
    SavingsPool pool;

    address owner;
    address alice;
    address bob;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.deal(owner, 100 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        vm.prank(owner);
        pool = new SavingsPool(100);
    }

    function test_DepositCreditsSender() public {
        vm.prank(alice);
        pool.deposit{value: 2 ether}();

        assertEq(pool.balanceOf(alice), 2 ether);
        assertEq(address(pool).balance, 2 ether);
    }

    function test_RevertWhen_DepositIsZero() public {
        vm.prank(alice);
        vm.expectRevert(SavingsPool.ZeroAmount.selector);
        pool.deposit{value: 0}();
    }

    function test_WithdrawChargesOnePercentFee() public {
        vm.prank(alice);
        pool.deposit{value: 1 ether}();

        uint256 beforeBalance = alice.balance;

        vm.prank(alice);
        pool.withdraw(1 ether);

        assertEq(alice.balance, beforeBalance + 0.99 ether);
        assertEq(pool.collectedFees(), 0.01 ether);
        assertEq(pool.balanceOf(alice), 0);
    }

    function test_PartialWithdrawLeavesRemainder() public {
        vm.prank(alice);
        pool.deposit{value: 2 ether}();

        uint256 beforeBalance = alice.balance;

        vm.prank(alice);
        pool.withdraw(0.5 ether);

        assertEq(pool.balanceOf(alice), 1.5 ether);
        assertEq(alice.balance, beforeBalance + 0.495 ether);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        vm.prank(alice);
        pool.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(SavingsPool.InsufficientBalance.selector);
        pool.withdraw(2 ether);
    }

    function test_WithdrawAllPaysOnceAndZeroes() public {
        vm.prank(alice);
        pool.deposit{value: 3 ether}();

        uint256 beforeBalance = alice.balance;

        vm.prank(alice);
        pool.withdrawAll();

        assertEq(pool.balanceOf(alice), 0);
        assertEq(alice.balance, beforeBalance + 2.97 ether);
        assertEq(pool.collectedFees(), 0.03 ether);
    }

    function test_RevertWhen_ConstructorFeeTooHigh() public {
        vm.expectRevert(SavingsPool.FeeTooHigh.selector);
        new SavingsPool(501);
    }

    function test_OwnerClaimsFees() public {
        vm.prank(alice);
        pool.deposit{value: 1 ether}();

        vm.prank(alice);
        pool.withdraw(1 ether);

        uint256 beforeBalance = owner.balance;

        vm.prank(owner);
        pool.claimFees();

        assertEq(owner.balance, beforeBalance + 0.01 ether);
        assertEq(pool.collectedFees(), 0);
    }

    function test_Invariant_PoolHoldsBalancesPlusFees() public {
        vm.prank(alice);
        pool.deposit{value: 4 ether}();

        vm.prank(bob);
        pool.deposit{value: 2 ether}();

        vm.prank(alice);
        pool.withdraw(1 ether);

        assertEq(
            address(pool).balance,
            pool.balanceOf(alice)
                + pool.balanceOf(bob)
                + pool.collectedFees()
        );
    }

    function test_RevertWhen_NonOwnerClaimsFees() public {
        vm.prank(bob);
        vm.expectRevert(SavingsPool.NotOwner.selector);
        pool.claimFees();
    }

    // Demonstrates the access-control vulnerability.
    // This test passes because the vulnerable contract
    // incorrectly allows a non-owner to change the fee.
    function test_Exploit_NonOwnerCanSetFee() public {
        vm.prank(bob);
        pool.setFee(200);

        assertEq(pool.feeBps(), 200);
    }

    function test_Exploit_AnyoneRaisesFee() public {
        // Bob can increase the fee to 5%.
        vm.prank(bob);
        pool.setFee(500);

        vm.prank(alice);
        pool.deposit{value: 1 ether}();

        uint256 beforeBalance = alice.balance;

        vm.prank(alice);
        pool.withdraw(1 ether);

        assertEq(alice.balance, beforeBalance + 0.95 ether);
        assertLt(alice.balance, beforeBalance + 0.99 ether);
    }
}
