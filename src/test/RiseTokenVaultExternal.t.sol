// SPDX-License-Identifier: GPL-3.0-or-later

// Risedle's Vault External Test
// Test & validate user/contract interaction with Risedle's Vault

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "lib/ds-test/src/test.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Hevm } from "./Hevm.sol";
import { RiseTokenVault } from "../RiseTokenVault.sol";
import { RisedleERC20 } from "../tokens/RisedleERC20.sol";

import { USDCToTokenSwap } from "../swaps/USDCToTokenSwap.sol";

import { USDC_ADDRESS, WETH_ADDRESS, UNI_ADDRESS } from "chain/Constants.sol";

/// @notice Dummy oracle contract that implement IRisedleOracle interface used for testing
contract Oracle {
    uint256 private currentPrice;

    constructor() {
        currentPrice = 0;
    }

    function setPrice(uint256 price) public {
        currentPrice = price;
    }

    function getPrice() external view returns (uint256 price) {
        return currentPrice;
    }
}

/// @title DummyUser
/// @author bayu (github.com/pyk)
/// @dev Contract to simulate user interactions
contract DummyUser {
    using SafeERC20 for IERC20;

    RiseTokenVault private _vault;

    constructor(RiseTokenVault vault) {
        _vault = vault;
    }

    /// @notice Mint TOKENRISE using ETH
    function mintWithETH(address token) public payable {
        // Mint TOKENRISE using ETH
        _vault.mint{ value: msg.value }(token);
    }

    function mintWithERC20(address token, uint256 collateralAmount) public {
        // Approve to spend the collateral token
        address collateralToken = _vault.getMetadata(token).collateral;
        IERC20(collateralToken).safeApprove(address(_vault), collateralAmount);

        // Mint RISE token
        _vault.mint(token, collateralAmount);

        // Reset the approval
        IERC20(collateralToken).safeApprove(address(_vault), 0);
    }
}

/// @title RiseTokenVault External test
/// @author bayu (github.com/pyk)
contract RiseTokenVaultExternalTest is DSTest {
    using SafeERC20 for IERC20;
    Hevm hevm;

    /// @notice Run the test setup
    function setUp() public {
        hevm = new Hevm();
    }

    // Test TOKENRISE minting process
    // 1. User should receive TOKENRISE worth more than their collateral value minus 0.1% fee and 1% (max slippage) and less than their collateral value
    // 2. Subsquent minting:
    //    If price is same, nav same, user should receive equal amount of TOKENRISE
    //    If price is up, nav up, user should receive less TOKENRISE
    //    If price is down, nav down, user should receive more TOKENRISE

    /// @notice Make sure it fails when user tryin to mint ERC20RISE token with ETH
    function testFail_UserCannotMintERC20RISEWithETH() public {
        // Update the contract balance to 100K USDC; We use this to supply the vault
        uint256 vaultSupplyAmount = 100000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract with ERC20
        hevm.setUNIBalance(address(swap), 1_000_000 ether); // 1M UNI token

        // Create new UNIRISE
        uint256 initialPrice = 10 * 1e6; // 10 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        RisedleERC20 unirise = new RisedleERC20("UNI 2x Long Risedle", "UNIRISE", address(vault), IERC20Metadata(UNI_ADDRESS).decimals());
        vault.create(
            false,
            address(unirise),
            UNI_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            initialPrice, // Initial price
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        DummyUser user = new DummyUser(vault);

        // Set the price oracle
        uint256 collateralPrice = 15 * 1e6; // 15 USDC
        oracle.setPrice(collateralPrice);

        // Mint the UNIRISE token with ETH, it should be failed
        uint256 depositAmount = 1 ether;
        user.mintWithETH{ value: depositAmount }(address(unirise));
    }

    /// @notice Make sure it fails when user trying to mint ETHRISE with zero ETH
    function testFail_UserCannotMintETHRISEWithZeroETH() public {
        // Update the contract balance to 100K USDC; We use this to supply the vault
        uint256 vaultSupplyAmount = 100000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract with WETH
        hevm.setWETHBalance(address(swap), 1_000 ether); // 1K WETH

        // Create new UNIRISE
        uint256 initialPrice = 100 * 1e6; // 100 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        RisedleERC20 ethrise = new RisedleERC20("ETH 2x Long Risedle", "ETHRISE", address(vault), IERC20Metadata(UNI_ADDRESS).decimals());
        vault.create(
            true,
            address(ethrise),
            WETH_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            initialPrice, // Initial price
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        DummyUser user = new DummyUser(vault);

        // Set the price oracle
        uint256 collateralPrice = 4_000 * 1e6; // 4K USDC
        oracle.setPrice(collateralPrice);

        // Mint the ETHRISE token with zero ETH, it should be failed
        uint256 depositAmount = 0 ether;
        user.mintWithETH{ value: depositAmount }(address(ethrise));
    }

    /// @notice Make sure it fails when user trying to mint and high slippage happen
    function test_UserCannotMintERC20RISEWhenHighSlippage() public {
        // Update the contract balance to 100K USDC; We use this to supply the vault
        uint256 vaultSupplyAmount = 100_000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 10%
        uint256 slippage = 0.1 ether; // 10% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract with UNI
        hevm.setUNIBalance(address(swap), 1_000_000 ether); // 1M UNI token

        // Create new UNIRISE
        uint256 initialPrice = 10 * 1e6; // 10 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        RisedleERC20 unirise = new RisedleERC20("UNI 2x Long Risedle", "UNIRISE", address(vault), IERC20Metadata(UNI_ADDRESS).decimals());
        vault.create(
            false,
            address(unirise),
            UNI_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            initialPrice, // Initial price
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        uint256 depositAmount = 10 ether; // 10 UNI token
        DummyUser user = new DummyUser(vault);

        // Fund the user
        hevm.setUNIBalance(address(user), depositAmount);

        // Set the price oracle
        uint256 collateralPrice = 15 * 1e6; // 15 USDC
        oracle.setPrice(collateralPrice);

        // Mint the UNIRISE; due to high slippage it should be failed
        user.mintWithERC20(address(unirise), depositAmount);
    }

    /// @notice Make sure the ETHRISE minting process works correctly
    function test_MintETHRISE() public {
        // Update the contract balance to 100K USDC
        uint256 vaultSupplyAmount = 100000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract
        hevm.setWETHBalance(address(swap), 100 ether);

        // Create new TOKENRISE  as owner
        uint256 initialPrice = 100 * 1e6; // 100 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        // Create new ETHRISE token
        RisedleERC20 ethrise = new RisedleERC20("ETH 2x Long Risedle", "ETHRISE", address(vault), IERC20Metadata(WETH_ADDRESS).decimals());
        vault.create(
            true,
            address(ethrise),
            WETH_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            100 * 1e6, // Initial price 100 USDC
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        DummyUser user = new DummyUser(vault);

        // Set the price oracle
        uint256 collateralPrice = 4000 * 1e6; // 4000 USDC
        oracle.setPrice(collateralPrice);

        // Mint the token
        uint256 depositAmount = 1 ether;
        // user.mint(address(ethrise), depositAmount);

        // Calculate the expected value
        // uint256 feeAmount = (0.001 ether * depositAmount) / 1 ether; // 0.1% fee
        // uint256 collateralAmount = depositAmount - feeAmount; // collateral minus fee
        // uint256 borrowAmount = collateralPrice + ((collateralPrice * slippage) / 1 ether); // Collateral price + slippage
        // uint256 expectedTotalCollateral = (2 * collateralAmount) + feeAmount; // 2x leverage + pending fees
        // uint256 expectedTotalPendingFees = feeAmount;
        // uint256 expectedTotalDebt = borrowAmount;
        // uint256 totalInvestment = (((2 * collateralAmount) * collateralPrice) / 1 ether) - borrowAmount; // 2x leverage minus borrow amount
        // uint256 expectedMintedAmount = (totalInvestment * 1 ether) / initialPrice; // Convert USDC 6 decimals to WETH 18 decimals

        // Validate the expected values
        // RISE token should be transfered to the user
        uint256 riseTokenBalance = IERC20(address(ethrise)).balanceOf(address(user));
        assertEq(riseTokenBalance, 39764215980000000000, "Wrong balance");
        assertEq((riseTokenBalance * initialPrice) / 1 ether, 3976421598, "RISE token worth value is not as described"); // Based on totalInvestment (fee and slippage)

        // The WETH token should be transfered to the RISE token vault
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(user)), 0, "Investor WETH balance is not transfered");
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(vault)), 1999000000000000000, "Vault WETH balance is not updated"); // Deposit from user + swapped amount

        // Make sure the RISE token vault states is correct
        RiseTokenVault.RiseTokenMetadata memory riseTokenMetadata = vault.getMetadata(address(ethrise));

        // Make sure the totalCollateral and totalPendingFees is correct
        assertEq(riseTokenMetadata.totalCollateral, 1999000000000000000, "RISE token totalCollateral is wrong"); // 2x collateralAmount + fees
        assertEq(riseTokenMetadata.totalPendingFees, 0.001 ether, "RISE token totalPendingFees is invalid"); // 0.1% from deposit amount

        // Make sure the totalDebt of the RISE token is correct
        assertEq(vault.getOutstandingDebt(address(ethrise)), 4015578402, "Borrow amount is invalid"); // Bought 4000 USDC with ~0.5% slippage

        // Make sure the total available cash is correct
        assertEq(vault.getTotalAvailableCash(), vaultSupplyAmount - 4015578402, "Total available cash is invalid");

        // Make sure the NAV doesn't change
        assertEq(vault.getNAV(address(ethrise)), initialPrice);

        // Second user with same deposit amount should have the same amount of minted token
        DummyUser secondUser = new DummyUser(vault);
        hevm.setWETHBalance(address(secondUser), depositAmount);
        // secondUser.mint(address(ethrise), depositAmount);
        riseTokenBalance = IERC20(address(ethrise)).balanceOf(address(secondUser));
        assertEq(riseTokenBalance, 39764215980000000000, "2: Wrong balance");
        assertEq((riseTokenBalance * initialPrice) / 1 ether, 3976421598, "2: RISE token worth value is not as described"); // Based on totalInvestment (fee and slippage)

        // Third user, collateral price go up, nav go up, should receive less amount of ETHRISE token
        oracle.setPrice(4200 * 1e6);
        assertEq(vault.getNAV(address(ethrise)), 110049236, "3: NAV invalid"); // ~110 USDC
        DummyUser thirdUser = new DummyUser(vault);
        hevm.setWETHBalance(address(thirdUser), depositAmount);
        // thirdUser.mint(address(ethrise), depositAmount);
        riseTokenBalance = IERC20(address(ethrise)).balanceOf(address(thirdUser));
        assertEq(riseTokenBalance, 37939769777229530244, "3: Wrong RISE token balance");

        // Fourth user, collateral price go down, nav go down, should receive more amount of ETHRISE token
        oracle.setPrice(4100 * 1e6);
        assertEq(vault.getNAV(address(ethrise)), 104946579, "4: NAV invalid"); // ~104 USDC
        DummyUser fourthUser = new DummyUser(vault);
        hevm.setWETHBalance(address(fourthUser), depositAmount);
        // fourthUser.mint(address(ethrise), depositAmount);
        riseTokenBalance = IERC20(address(ethrise)).balanceOf(address(fourthUser));
        assertEq(riseTokenBalance, 38837208195228545753, "4: Wrong RISE token balance");

        // Validate the RISE token states
        riseTokenMetadata = vault.getMetadata(address(ethrise));
        assertEq(riseTokenMetadata.totalCollateral, 7996000000000000000, "RISE token totalCollateral is wrong"); // 2x4 WETH minus fee
        assertEq(riseTokenMetadata.totalPendingFees, 0.004 ether, "RISE token totalPendingFees is invalid"); // 4x mint of 1 WETH
        assertEq(vault.getOutstandingDebt(address(ethrise)), 16363481988, "Borrow amount is invalid"); // 4 times borrow with WETH price around 4000
        assertEq(vault.getTotalAvailableCash(), 83636518012, "Total available cash is invalid"); // 100K - (total borrow + collected fees)
    }

    /// @notice Scenario 1: User mint token below the NAV price
    function test_MintRISETokenBelowNAVPrice() public {
        // Update the contract balance to 100K USDC
        uint256 vaultSupplyAmount = 100000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new RISE token vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract
        hevm.setWETHBalance(address(swap), 100 ether);

        // Create new RISE token as owner
        uint256 initialPrice = 100 * 1e6; // 100 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        // Create new ETHRISE token
        RisedleERC20 ethrise = new RisedleERC20("ETH 2x Long Risedle", "ETHRISE", address(vault), IERC20Metadata(WETH_ADDRESS).decimals());
        vault.create(
            true,
            address(ethrise),
            WETH_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            initialPrice, // Initial price 100 USDC
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        DummyUser user = new DummyUser(vault);

        // Set the user WETH balance
        uint256 depositAmount = 0.0225 ether;
        hevm.setWETHBalance(address(user), depositAmount);

        // Set the price oracle
        uint256 collateralPrice = 4000 * 1e6; // 4000 USDC
        oracle.setPrice(collateralPrice);

        // Mint the token
        // user.mint(address(ethrise), depositAmount);

        // Check the collateral per RISE token and debt per RISE token
        assertEq(vault.getCollateralPerRiseToken(address(ethrise)), 50246181139343977); // Should be 0.05 ether but due to slippage it got less amount of RISE token, hence the mint amount is less
        assertEq(vault.getDebtPerRiseToken(address(ethrise)), 100984724); // Should be $100 but due to slippage, the borrow amount is larger, hence the mint amount is less
    }

    /// @notice Scenario 2: User mint token equal to the NAV price
    function test_MintRISETokenEqualNAVPrice() public {
        // Update the contract balance to 100K USDC
        uint256 vaultSupplyAmount = 100000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new RISE token vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract
        hevm.setWETHBalance(address(swap), 100 ether);

        // Create new RISE token as owner
        uint256 initialPrice = 100 * 1e6; // 100 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        // Create new ETHRISE token
        RisedleERC20 ethrise = new RisedleERC20("ETH 2x Long Risedle", "ETHRISE", address(vault), IERC20Metadata(WETH_ADDRESS).decimals());
        vault.create(
            true,
            address(ethrise),
            WETH_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            initialPrice, // Initial price 100 USDC
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        DummyUser user = new DummyUser(vault);

        // Set the user WETH balance
        uint256 depositAmount = 0.0250 ether;
        hevm.setWETHBalance(address(user), depositAmount);

        // Set the price oracle
        uint256 collateralPrice = 4000 * 1e6; // 4000 USDC
        oracle.setPrice(collateralPrice);

        // Mint the token
        // user.mint(address(ethrise), depositAmount);

        // Check the collateral per RISE token and debt per RISE token
        assertEq(vault.getCollateralPerRiseToken(address(ethrise)), 50246181139343977);
        assertEq(vault.getDebtPerRiseToken(address(ethrise)), 100984724);
    }

    /// @notice Scenario 3: User mint token above to the NAV price
    function test_MintRISETokenAboveNAVPrice() public {
        // Update the contract balance to 100K USDC
        uint256 vaultSupplyAmount = 100000 * 1e6; // 100K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);

        // Create new RISE token vault first; by default the deployer is the owner
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Add supply to the vault
        IERC20(USDC_ADDRESS).safeApprove(address(vault), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle for the collateral
        Oracle oracle = new Oracle();

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Fund the swap contract
        hevm.setWETHBalance(address(swap), 100 ether);

        // Create new RISE token as owner
        uint256 initialPrice = 100 * 1e6; // 100 USDC
        uint256 feeInEther = 0.001 ether; // 0.1%
        // Create new ETHRISE token
        RisedleERC20 ethrise = new RisedleERC20("ETH 2x Long Risedle", "ETHRISE", address(vault), IERC20Metadata(WETH_ADDRESS).decimals());
        vault.create(
            true,
            address(ethrise),
            WETH_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            initialPrice, // Initial price 100 USDC
            feeInEther, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Create new dummy user
        DummyUser user = new DummyUser(vault);

        // Set the user WETH balance
        uint256 depositAmount = 0.0375 ether;
        hevm.setWETHBalance(address(user), depositAmount);

        // Set the price oracle
        uint256 collateralPrice = 4000 * 1e6; // 4000 USDC
        oracle.setPrice(collateralPrice);

        // Mint the token
        // user.mint(address(ethrise), depositAmount);

        // Check the collateral per RISE token and debt per RISE token
        assertEq(vault.getCollateralPerRiseToken(address(ethrise)), 50246181139343977);
        assertEq(vault.getDebtPerRiseToken(address(ethrise)), 100984724);
    }

    // Leverage ratio behaviours
    // 1. When collateral price go up:
    //    - nav go up
    //    - leverage ratio go down
    //    - when rebalacne executed:
    //        - the leverage ratio should be increased
    //        - totalCollateral should be increased
    //        - totalDebt should be increased
    // 2. When collateral price go down:
    //    - nav go down
    //    - leverage ratio go up
    //    - when rebalacne executed:
    //        - the leverage ratio should be decreased
    //        - totalCollateral should be descreased
    //        - totalDebt should be decreased
    //
    // Rebalancing rules:
    // 1. When leverage ratio x < 2: leveraging up
    // 2. When leverage ratio x > 3: leveraging down
    // 3. When leverage ratio 2 < x < 3: revert, dont do anything

    function test_DailyRebalancingTimestampLessThan24HourAndPartialRebalancingIsFalse() public {
        // Deploy the RISE token vault
        RiseTokenVault vault = new RiseTokenVault("Risedle USDC Vault", "rvUSDC", USDC_ADDRESS);

        // Supply USDC
        uint256 vaultSupplyAmount = 400000 * 1e6; // 400K USDC
        hevm.setUSDCBalance(address(this), vaultSupplyAmount);
        vault.addSupply(vaultSupplyAmount);

        // Create new price oracle contract
        Oracle oracle = new Oracle();

        // Set WETH price to 4000 USDC
        oracle.setPrice(4000 * 1e6);

        // Create new swap contract, with artificial slippage 0.5%
        uint256 slippage = 0.005 ether; // 0.5% slippage to buy more collateral
        USDCToTokenSwap swap = new USDCToTokenSwap(address(oracle), slippage);

        // Create new ETHRISE token
        RisedleERC20 ethrise = new RisedleERC20("ETH 2x Long Risedle", "ETHRISE", address(vault), IERC20Metadata(WETH_ADDRESS).decimals());

        // Add ETHRISE token to the vault
        vault.create(
            true,
            address(ethrise),
            WETH_ADDRESS,
            address(oracle),
            address(swap),
            0.05 ether, // Max 5% slippage for mint, redeem and rebalance
            100 * 1e6, // Initial price 100 USDC
            0.001 ether, // creation and redemption fees is 0.1%
            1.7 ether, // Min leverage ratio is 1.7x
            2.3 ether, // Max leverage ratio is 2.3x
            250000 * 1e6, // Max value of sell/buy is 250K USDC
            0.2 ether // Rebalancing step is 0.2x
        );

        // Mint some ETHRISE
        uint256 mintAmount = 2 ether; // 2 WETH converted to ETHRISE
        hevm.setWETHBalance(address(this), mintAmount);
        vault.mint(address(ethrise), mintAmount);

        // Execute the rebalance; should be failed coz the timestamp is not more than 24 hours and the partial rebalance is not set to true
        vault.rebalance(address(ethrise));
    }

    // Test Redeem
    // mint, no price change, then redeem, User should receive their collateral back minus 0.2% fee
    // mint, price go up, then redeem, User should receive their collateral back plus their profit
    // mint, price go down, then redeem, User should receive less than their collateral
}
