//SPDX// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
import {Test} from "../../lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address USER = makeAddr("user");
    uint256 public constant ETH_AMOUNT = 15e18;
    uint256 public constant ETH_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant USD_AMOUNT_IN_WEI = 100 ether;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenAndPriceFeedsAreNotEqualLength() public {
        tokenAddresses.push(weth);

        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUsdValue() public {
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ETH_AMOUNT);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        //get the priceFeed address of the token-->Aggregator V3 Interface andget int256 version of the price
        //do calculations here and then compare eventually
        AggregatorV3Interface priceFeed = AggregatorV3Interface(ethUsdPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 tokenAmount = (USD_AMOUNT_IN_WEI * PRECISION) / ((uint256)(price) * ADDITIONAL_FEED_PRECISION);

        uint256 tokenAmountFromUsd = dscEngine.getTokenAmountFromUsd(weth, USD_AMOUNT_IN_WEI);
        assertEq(tokenAmountFromUsd, tokenAmount);
    }

    function testRevertsIfColalteralIsZero() public {
        vm.startPrank(USER);

        //Cast weth Address to ERC20Mock contract type
        //call approve function on it
        //give permission to dscEngine contract to take upto 10 ether from USER.
        //This function call is essential bcz in depositCollateral()--->transferFrom is there
        //and that my friend, requires allowance/approval first.
        ERC20Mock(weth).approve(address(dscEngine), ETH_COLLATERAL);

        //Every function/error in Solidity has a unique 4-byte identifier called a selector.
        //Error Name: DSCEngine__NeedsMoreThanZero
        //Keccak256 Hash: keccak256("DSCEngine__NeedsMoreThanZero()")
        //First 4 bytes: 0xf2b5e03b (Example)
        //This is the SELECTOR!
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapporvedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("Random", "Ran", USER, ETH_COLLATERAL);
        vm.prank(USER);
        //ERC20Mock(randomToken).approve(address(dscEngine), ETH_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(randomToken), ETH_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), ETH_COLLATERAL);
        dscEngine.depositCollateral(weth, ETH_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 colalteralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedMinted = 0;
        uint256 expectedCollateralValueInUsd = dscEngine.getTokenAmountFromUsd(weth, colalteralValueInUsd);
        assertEq(totalDscMinted, expectedMinted);
        assertEq(expectedCollateralValueInUsd, ETH_COLLATERAL);
    }
}
