// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";

/// @notice Abstract contract for implementing ERC20 fungible tokens
abstract contract FungibleToken is IERC20, IERC165 {
    struct OwnerData {
        uint256 balance;
        mapping(address => uint256) allowances;
    }

    /// @inheritdoc IERC20
    string public name;
    /// @inheritdoc IERC20
    string public symbol;
    /// @inheritdoc IERC20
    uint8 public decimals;

    uint256 private s_totalSupply;
    mapping(address => OwnerData) private s_ownerData;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) public returns (bool) {
        s_ownerData[msg.sender].allowances[spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);

        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = s_ownerData[from].allowances[msg.sender];

        // do not reduce if given unlimited allowance
        if (currentAllowance != type(uint256).max) {
            s_ownerData[from].allowances[msg.sender] = currentAllowance - amount; // underflow protection
        }
        _transfer(from, to, amount);

        return true;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return s_totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address owner) public view returns (uint256) {
        return s_ownerData[owner].balance;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view returns (uint256) {
        return s_ownerData[owner].allowances[spender];
    }

    /// @notice Mints new tokens and assigns them to an address
    /// @param to the address to mint tokens to
    /// @param amount The amount of tokens to mint
    function _mint(address to, uint256 amount) internal {
        _transfer(address(0), to, amount);
    }

    /// @notice Burns tokens from an address
    /// @param from the address to burn tokens from
    /// @param amount The amount of tokens to burn
    function _burn(address from, uint256 amount) internal {
        _transfer(from, address(0), amount);
    }

    /// @notice Transfers tokens between addresses
    /// @param from the address to transfer tokens from
    /// @param to the address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            s_totalSupply += amount; // overflow protection
        } else {
            s_ownerData[from].balance -= amount; // underflow protection
        }

        // over/underflow protection
        unchecked {
            if (to == address(0)) {
                s_totalSupply -= amount;
            } else {
                s_ownerData[to].balance += amount;
            }
        }

        emit Transfer(from, to, amount);
    }
}
