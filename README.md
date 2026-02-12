# Stablecoin-Fi

---

## Overview

Stablecoin-Fi is a decentralized, overcollateralized stablecoin protocol inspired by MakerDAO. Users deposit WETH or WBTC as collateral to mint DSC, a USD-pegged stablecoin.

The protocol maintains its peg through overcollateralization (150% minimum), real-time price feeds from Chainlink, and automated liquidations of undercollateralized positions.

**Tech Stack:** Solidity, Foundry, Chainlink, OpenZeppelin

---

## Core Contracts

| Contract | Purpose |
|----------|---------|
| DSCEngine.sol | Core protocol logic - handles deposits, minting, liquidations, health factors |
| DecentralisedStableCoin.sol | DSC token contract - ERC20 implementation |

---

## How It Works

**For Users:**
1. Deposit WETH/WBTC as collateral
2. Mint DSC tokens against deposited collateral
3. Maintain health factor above 1.0 to avoid liquidation
4. Repay DSC to redeem collateral

**For Liquidators:**
- When a user's health factor drops below 1.0, liquidators can repay the user's debt
- Liquidators receive the user's collateral with a 10% bonus
- This incentive ensures the protocol remains fully collateralized

---

## Testing

- Unit Tests: Individual function correctness
- Fuzzing: Random input edge cases
- Stateful Invariants: Protocol properties always hold

**Key Invariant:** Total collateral value always exceeds total DSC supply.

---

## About

This project was built to demonstrate deep understanding of DeFi primitives, stablecoin mechanisms, and secure smart contract development practices.
