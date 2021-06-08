// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IDOPoolPublic.sol";

contract PoolFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public nextPoolId;

    struct IDOPoolInfo {
        address contractAddr;
        address currency;
        address token;
    }

    event PoolCreated(address pool, address creator);

    IDOPoolInfo[] public pools;

    function createPoolPublic(
        address _token,
        address _currency,
        uint256 _start,
        uint256 _end,
        uint256 _lockDuration,
        uint256 _price,
        uint256 _totalAmount,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) external onlyOwner() returns (address _pool) {
        require(_token != _currency, "Currency and Token can not be the same");
        require(_token != address(0));
        require(_currency != address(0));

        _pool = address(
            new IDOPoolPublic(
                _token,
                _currency,
                _start,
                _end,
                _lockDuration,
                _price,
                _totalAmount,
                _minPurchase,
                _maxPurchase
            )
        );

        pools.push(IDOPoolInfo(_pool, _currency, _token));
        emit PoolCreated(_pool, msg.sender);
    }
}
