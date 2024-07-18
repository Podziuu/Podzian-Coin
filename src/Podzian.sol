// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StableCoin
 * @author Bartosz Podemski
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * This is the contract meant to be governed by PDNEngine. 
 * This contract is just the ERC20 implementation of our stablecoin system.
 */
contract Podzian is ERC20Burnable, Ownable {
    /**
     * Errors
     */
    error Podzian__MustBeMoreThanZero();
    error Podzian__BurnAmountExceedsBalance();
    error Podzian__NotZeroAddress();

    constructor() ERC20("Podzian", "PDN") Ownable(msg.sender) {}

    /**
     * Functions
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0 ) {
            revert Podzian__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert Podzian__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert Podzian__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert Podzian__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}