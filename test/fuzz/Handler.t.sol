//SPDX// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
import { Test } from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";




contract Handler is Test {
    uint256 MAX_DEPOSIT_SIZE = 1e24;
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    address USER = makeAddr("USER");
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    address[] public usersWithCollateralDeposited;
    uint256 public timesMintIsCalled ;
    constructor(DSCEngine _dscEngine, DecentralisedStableCoin _dsc){
        dscEngine=_dscEngine;
        dsc=_dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc =  ERC20Mock(collateralTokens[1]);
       ethUsdPriceFeed= MockV3Aggregator(dscEngine.getTokenCollateralPriceFeed(address(weth)));
    }

    //redeem collateral.
    //cal this only ehen you have collateral
    function depositCollateral( uint256 collateralSeed, uint256 amountCollateral)
    public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral =  bound(amountCollateral,1,MAX_DEPOSIT_SIZE);

        
     
        collateral.mint(msg.sender, amountCollateral);
        vm.startPrank(msg.sender);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
        
    }
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral ) public {
        ERC20Mock collateral =  _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral,0,maxCollateralToRedeem);
        if(amountCollateral==0){
            return;
        }
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount,uint256 addressSeed) public{
        if(usersWithCollateralDeposited.length==0){
            return;
        }
        addressSeed = addressSeed % usersWithCollateralDeposited.length;
         address sender = usersWithCollateralDeposited[addressSeed];   
        amount = bound(amount,1,MAX_DEPOSIT_SIZE);
        
        vm.startPrank(sender);
        
        (uint256 totalDscMinted , uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        if(collateralValueInUsd==0){
            return;
        }
        uint256 maxDscToMint = (collateralValueInUsd/2)-totalDscMinted;
        
        if(maxDscToMint==0){
            return;
        }
        
        amount = bound( amount,1,maxDscToMint);
        
        if(amount==0){
            return;
        }
      
        dscEngine.mintDsc(amount);
        vm.stopPrank(); 
          timesMintIsCalled++;
        
    }

    
    //This breaks our invariant test suite.
    // function updateColalteralPrice(uint96 newPrice)public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);

    // }

    //helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed%2 ==0){
            return weth;
        }

        return wbtc;
    }
}