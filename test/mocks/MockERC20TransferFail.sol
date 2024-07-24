// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20TransferFail is ERC20 {
    constructor() ERC20("ERC20", "ERC") {}

    function transfer(address /*to*/, uint256 /*amount*/) public pure override returns (bool) {
        return false;
    }

    // function transferFrom(address /*from*/, address /*to*/, uint256 /*amount*/) public pure override returns (bool) {
    //     return false;
    // }
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    // function approve(address spender, uint256 amount) public override returns (bool) {
    //     return false;
    // }
}