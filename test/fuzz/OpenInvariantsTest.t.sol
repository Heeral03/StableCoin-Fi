//SPDX// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {Handler} from "../../test/fuzz/Handler.t.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
//What are our Invariants???
//1. total supply of dsc should be less than that of collateral
//2. getter view functions should never revert

contract InvariantsTest is Test {
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig helperconfig;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperconfig) = deployer.run();
        (,, weth, wbtc,) = helperconfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        //don't call redeem collateral unless there is collateral to redeem
        // targetContract(address(dscEngine));
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
        //get the value of total collateral in protocol
        //compare it to all the debt
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log(wethValue);
        console.log(wbtcValue);
        console.log(totalSupply);
        console.log(handler.timesMintIsCalled());
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
