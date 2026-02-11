// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

/*
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

/**
As a User, I want to:
1. Deposit ETH/BTC as collateral
2. Mint DSC stablecoins against it
3. Check my health factor
4. Add more collateral if needed
5. Repay DSC to get my collateral back
6. Liquidate others if they're undercollateralized
 */

pragma solidity ^0.8.20;


import { ERC20,ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DecentralisedStableCoin } from "./DecentralisedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
contract DSCEngine is ReentrancyGuard{
    ///////////////////////
    //////////////////////
    ///// ERRORS ////////
    ////////////////////
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakedHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__RedeemCollateralFailed();
    //error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsOkay();
    error DSCEngine__HealthFactorNotImproved();


    using OracleLib for AggregatorV3Interface;

    ///////////////////////
    //////////////////////
    ///// STATE VARIABLEs /////
    ////////////////////
    ///////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted)private s_dscMinted;
    address[] private s_collateralTokens;
    DecentralisedStableCoin private immutable i_dsc;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION=100;
    uint256 private constant MIN_HEALTH_FACTOR=1e18;
    uint256 private constant LIQUADATION_BONUS = 10;

    ///////////////////////
    //////////////////////
    ///// EVENTS /////
    ////////////////////
    ///////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemedTo,address indexed token);
    ///////////////////////
    //////////////////////
    ///// MODIFIERS /////
    ////////////////////
    ///////////////////
    modifier moreThanZero(uint256 _amount){
        if (_amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token){
        if(s_priceFeeds[_token]==address(0)){
            revert DSCEngine__TokenNotAllowed();

        }
        _;
    }


    ///////////////////////
    //////////////////////
    ///// FUNCTIONS /////
    ////////////////////
    ///////////////////




    ///////////////////////////////
    ///////////////////////////////
    ///// EXTERNAL FUNCTION ///////
    /////////////////////////////
    /////////////////////////////

    
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress){
        if(tokenAddresses.length != priceFeedAddresses.length){
            revert DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
        }

        //We need USD Price feeds
        //Example: ETH/USD, BTC/USD etc etc.
        for(uint256 i = 0 ;i<tokenAddresses.length;i++){
            s_priceFeeds[tokenAddresses[i]]=priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralisedStableCoin(dscAddress);
    }





    function depositCollateralAndMintDSC(address tokenCollateralAddress, uint256 amountCollateral,uint256 amountDscToMint)
    public
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }


    //check first if collateral value>dsc amount
    /**
    *@notice follows CEI
    *@param amountDscToMint the amount of dsc to mint
    *@notice they must have more collateral value than minting
     */

    function mintDsc(uint256 amountDscToMint) public
    moreThanZero(amountDscToMint)
    nonReentrant
    {
        s_dscMinted[msg.sender] += amountDscToMint;
        //check
        _revertIfHealthFactorIsBroken(msg.sender);


        //effects
        bool minted = i_dsc.mint(amountDscToMint, msg.sender);
        if(!minted){
            revert DSCEngine__MintFailed();
        }

    }









    /*
    *@notice follows CEI
    *@param tokenCollateralAddress The address of the token to deposit as a collateral
    *@param amountCollateral the amount to be deposited as a collateral
    *This modifier-->nonReentrant is from Reentrancy Guard of openzeppelin
    */
    function depositCollateral
    (address tokenCollateralAddress,
    uint256 amountCollateral
    ) 
    public 
    moreThanZero(amountCollateral)
    isAllowedToken(tokenCollateralAddress)
    nonReentrant
    {   
        s_collateralDeposited[msg.sender][tokenCollateralAddress]+=amountCollateral;
        //we are updating state-->so lets emit an event now
        emit CollateralDeposited(msg.sender,tokenCollateralAddress, amountCollateral);

        //Transfer the collateral amount from msg.sender to this contract's address and wrap it as a ERC20 version of it.
        //transferFrom requires allowance permission first--->Isiliye test mei pehle allow kara hai.
        (bool success)=IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }


    }



    //In order to redeem collateral:
    //1. health factor should be above 1 after collateral is pulled out
    //CEI-->Check, Effects,Interactions

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
    public
    moreThanZero(amountCollateral)
    nonReentrant
    {
        _redeeemCollateral(tokenCollateralAddress,amountCollateral,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //$100 ETH -> $20 DSC
    //100 out (breaks the health factor)
    //1. burn dsc
    //2. redeem ETH
    function redeemCollateralForDSC(address tokenCollateralAddress,uint256 amountCollateral,uint256 amountToBurnDsc)
    public
    {
        burnDSC(tokenCollateralAddress,amountCollateral);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral already checks health factor so no need to do it again.
    }

    function burnDSC(address tokenCollateralAddress, uint256 amount)
    public
    moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    //If we do start nearing undercollateralized--> Wohi liquadation wala logic hai bas
    //IF someone is almost undercollateralized we will pay you to liquadate them.
    //lets say price goes down from 100$ eth backing to 75$ eth backing 50$ dsc
    //liquadator will take this 75$ backing and burns off 50$ dsc
    /**
    * @param collateral The ERC20 collateral address to liquadate from the user
    * @param user The user who has broken the health factor.Their health factor should be below MIN_HEALTH_FACTOR
    * @param debtToCover The amount of DSC you want to burn to improve user's health factor
    * @notice You can partially liquadate a user and will get a liq bonus for taking user's funds
    * @notice this function working assumes protocol will be roughly 200% over collateralized fro this to work.
     */
    function liquidate(address collateral,address user,uint256 debtToCover)
    external
    nonReentrant
    moreThanZero(debtToCover) {
        //CEI
        uint256 startingUserHealthFactor=_healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
                revert DSCEngine__HealthFactorIsOkay();
        }

        //we want to now burn their dsc "debt" and take their collateral
        //Bad USer-->140$ eth deposited and 100$ dsc
        //debtToCover=100$
        //So 100$ of DSC = how much of ETH?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral,debtToCover);
        //give the liq 10% of incentive i.e $110 of weth for 100DSC
        //we should implement a feature to liq in the event the protocol is insolvant
        //and sweep extra amount into a trasury
        uint256 bonusCollateral = ((tokenAmountFromDebtCovered)*LIQUADATION_BONUS)/LIQUIDATION_PRECISION;
        uint256 totalCollateralToLiq = bonusCollateral + tokenAmountFromDebtCovered;
        _redeeemCollateral(collateral,totalCollateralToLiq,user,msg.sender);
        //we have to burn the dsc as well
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor =     _healthFactor(user);
        if(endingUserHealthFactor<=startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
        
    }

    function getHealthFactor() external view {}
    ///////////////////////////////
    ///////////////////////////////
    ///// Private & INTERNAL FUNCTION ///////
    /////////////////////////////
    /////////////////////////////

    function _getAccountInfo(address user)
    private
    view 
    returns(uint256 totalDscMinted,uint256 collateralValueInUsd)
    {
        //lets first get the totaldsc minted which is very straight forward
        totalDscMinted=s_dscMinted[user];

        collateralValueInUsd = getAccountCollateralValue(user);

    }





    function _healthFactor(address user)private view returns(uint256){
        //returns how close to liquadation a user is
        //if user < 1-->they can't liquadate
        (uint256 totalDscMinted ,uint256 collateralValueInUsd) =  _getAccountInfo(user);
        if(totalDscMinted==0){
            return type(uint256).max;
        }

        // return (collateralValueInUsd/totalDscMinted)
        // (150/100)1.5-->1 only so we will adjust it using a threshold

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold*PRECISION)/totalDscMinted;
    }




    function _revertIfHealthFactorIsBroken(address user)
    internal view
    {
        //1. check health factor--> do they have enough collateral?-->revert if not
        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreakedHealthFactor(healthFactor);
        }


    }

    function _redeeemCollateral(address tokenCollateralAddress, uint256 amountCollateral,address from, address to)public {


        if(s_collateralDeposited[from][tokenCollateralAddress]<amountCollateral){
            return;
        }
        s_collateralDeposited[from][tokenCollateralAddress]-=amountCollateral;

        //uint256 will never be negative.
        //we need to check before.
        // if(s_collateralDeposited[from][tokenCollateralAddress]<0){
        //     return;
        // }
        //since we have updating a state, we're going to emit
        emit CollateralRedeemed(from , to , tokenCollateralAddress);
        

        //transfer-->Then check later and revert it if needed
        (bool success)=IERC20(tokenCollateralAddress).transfer(from,amountCollateral);
        if(!success){
            revert DSCEngine__RedeemCollateralFailed();
        }
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf,address dscFrom) private{
        s_dscMinted[onBehalfOf]-=amountDscToBurn;
        (bool success)= i_dsc.transferFrom(onBehalfOf,address(this),amountDscToBurn);
        if(!success){
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountDscToBurn);
    }

    function getAccountCollateralValue( address user) public view returns(uint256 totalCollateralValueInUsd){
        //loop through each collateral token , get the amount and map it to their usd value
        for(uint256 i=0;i<s_collateralTokens.length;i++){
            address token=s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token,amount);
        }

        return totalCollateralValueInUsd;

    }


    function getUsdValue(address token,uint256 amount)public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,)=priceFeed.stalePriceCheck();


        // 1ETH=$1000
        // The returned value from chainlink will be 1000*1e8
        return ((uint256(price )* ADDITIONAL_FEED_PRECISION)*amount)/PRECISION;   //(1000 * 1e8) * (1000 * 1e18;)--> for same precision, multiply 1000*1e8 with 1e10;

    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountinWei)public view returns(uint256){
        //we've say pricing of $/ETH and given the dollar which is how many eths?
        //so, say its $/ETH is 2000 and $1000
        //ETH=1000/2000--> 0.5 ETH
        AggregatorV3Interface priceFeed =  AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.stalePriceCheck();

        return ((usdAmountinWei)*PRECISION)/((uint256)(price) *ADDITIONAL_FEED_PRECISION);
    }
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInfo(user);
    }

    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }
    function getCollateralBalanceOfUser(address user,address token)public returns(uint256){
        return  s_collateralDeposited[user][token];
    }

    function getTokenCollateralPriceFeed(address token)
    public returns(address){
        return s_priceFeeds[token];
    }
}