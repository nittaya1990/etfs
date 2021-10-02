// SPDX-License-Identifier: GPL-3.0-or-later

// Risedle's ETF External Test
// Test & validate user/contract interaction with Risedle's ETF
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "lib/ds-test/src/test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// chain/* is replaced by DAPP_REMAPPINGS at compile time,
// this allow us to use custom address on specific chain
// See .dapprc
import {WETH_ADDRESS, USDT_ADDRESS} from "chain/Constants.sol";

import {Hevm} from "./Hevm.sol";
import {RisedleVault} from "../RisedleVault.sol";
import {RisedleETF} from "../RisedleETF.sol";

contract RisedleETFAccessControlTest is DSTest {
    IERC20 constant USDT = IERC20(USDT_ADDRESS);
    IERC20 constant WETH = IERC20(WETH_ADDRESS);

    // HEVM
    Hevm hevm;

    /// @notice Run the test setup
    function setUp() public {
        hevm = new Hevm();
    }

    /// @notice Utility function to create new vault
    function createNewVault() internal returns (RisedleVault) {
        // Create new vault
        RisedleVault vault = new RisedleVault(
            "Risedle USDT Vault",
            "rvUSDT",
            USDT_ADDRESS,
            6
        );
        return vault;
    }

    /// @notice Utility function to create new ETF
    function createNewETF(address feeReceiver, uint256 initialPrice)
        internal
        returns (RisedleETF)
    {
        // Create new ETF
        RisedleETF etf = new RisedleETF(
            "ETH 2x Leverage Risedle",
            "ETHRISE",
            WETH_ADDRESS,
            feeReceiver,
            initialPrice
        );
        return etf;
    }

    /// @notice Make sure we can call setVault after deployment
    /// @dev This is by design and the setVault only called once after deployment
    function test_AnyoneCanSetVaultAfterDeployment() public {
        // Set random address as governor and fee receiver
        address governor = hevm.addr(1);
        address feeReceiver = hevm.addr(2);

        // Create new vault
        RisedleVault vault = createNewVault();

        // Create new ETF
        uint256 initialPrice = 100 * 1e6; // 100 USDT
        RisedleETF etf = createNewETF(feeReceiver, initialPrice);
        etf.transferOwnership(governor);

        // Run the setVault function as public user
        etf.setVault(address(vault));

        // Make sure the vault is updated
        (, , address etfVault, , ) = etf.getETFInformation();
        assertEq(etfVault, address(vault));
    }

    /// @notice Make sure setVault can only called once
    function testFail_SetVaultOnlyCalledOnce() public {
        // Set random address as governor and fee receiver
        address governor = hevm.addr(1);
        address feeReceiver = hevm.addr(2);

        // Create new vault
        RisedleVault vault = createNewVault();

        // Create new ETF
        uint256 initialPrice = 100 * 1e6; // 100 USDT
        RisedleETF etf = createNewETF(feeReceiver, initialPrice);
        etf.transferOwnership(governor);

        // Run the setVault function as public user
        etf.setVault(address(vault));

        // Run once again, it should be failed
        etf.setVault(address(vault));
    }

    /// @notice Make sure non-governor account cannot update the fee receiver address
    function testFail_NonGovernorCannotsetFeeReceiver() public {
        // Set random address as governor and fee receiver
        address governor = hevm.addr(1);
        address feeReceiver = hevm.addr(2);

        // Create new vault
        RisedleVault vault = createNewVault();
        // Create new ETF
        uint256 initialPrice = 100 * 1e6; // 100 USDT
        RisedleETF etf = createNewETF(feeReceiver, initialPrice);
        etf.transferOwnership(governor);
        etf.setVault(address(vault));

        // Run the setFeeReceiver function as public user; should be failed
        address newFeeReceiver = hevm.addr(3);
        etf.setFeeReceiver(newFeeReceiver);
    }

    /// @notice Make sure Governor account can update the fee receiver address
    function test_GovernorCanUpdateFreeReceiver() public {
        // Set this contract as the governor
        address feeReceiver = hevm.addr(2);

        // Create new vault
        RisedleVault vault = createNewVault();

        // Create new ETF
        uint256 initialPrice = 100 * 1e6; // 100 USDT
        RisedleETF etf = createNewETF(feeReceiver, initialPrice); // This contract as the governor
        etf.setVault(address(vault));

        // Get the ETF information
        address etfFeeReceiver;
        (, etfFeeReceiver, , , ) = etf.getETFInformation();

        // Make sure the free receiver is correct
        assertEq(etfFeeReceiver, feeReceiver);

        // Run the setFeeReceiver function as governor
        address newFeeReceiver = hevm.addr(3);
        etf.setFeeReceiver(newFeeReceiver);

        // Get the ETF information after update receiver
        (, etfFeeReceiver, , , ) = etf.getETFInformation();

        // The free receiver address should be updated
        assertEq(etfFeeReceiver, newFeeReceiver);
    }
}