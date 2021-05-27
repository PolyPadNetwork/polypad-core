pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MpadPublicSale is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Sale {
        address investor;
        uint256 amount;
        bool tokensWithdrawn;
    }

    mapping(address => Sale) public sales;

    uint256 public start;
    uint256 public end;
    uint256 public price;
    uint256 public availableTokens;
    uint256 public totalAmount;
    uint256 public minPurchase;
    uint256 public maxPurchase;

    IERC20 public mpadToken;
    IERC20 public currency;

    event Buy(address indexed _user, uint256 _amount, uint256 _tokenAmount);
    event Claim(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event Burn(address indexed _burnAddress, uint256 _amount);
    event EmergencyWithdrawal(address indexed _user, uint256 _amount);

    constructor(
        address _mpadToken,
        address _currency,
        uint256 _start,
        uint256 _end,
        uint256 _price,
        uint256 _totalAmount,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) public {
        require(_mpadToken != address(0), "Zero token address");
        require(_currency != address(0), "Zero token address");
        require(_start < _end, "_start must be < _end");
        require(_totalAmount > 0, "_totalAmount must be > 0");
        require(_minPurchase > 0, "_minPurchase must > 0");
        require(
            _minPurchase <= _maxPurchase,
            "_minPurchase must be <= _maxPurchase"
        );
        require(
            _maxPurchase <= _totalAmount,
            "_maxPurchase must be <= _totalAmount"
        );
        mpadToken = IERC20(_mpadToken);
        currency = IERC20(_currency);
        start = _start;
        end = _end;
        price = _price;
        totalAmount = _totalAmount;
        availableTokens = _totalAmount;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
    }

    function buy(uint256 amount) external publicSaleActive() {
        Sale storage sale = sales[msg.sender];
        require(sale.amount == 0, "Already purchased");
        require(
            amount >= minPurchase && amount <= maxPurchase,
            "Have to buy between minPurchase and maxPurchase"
        );
        require(amount <= availableTokens, "Not enough tokens to sell");
        uint256 currencyAmount = amount.mul(price).div(1e18);
        require(
            currency.balanceOf(msg.sender) >= currencyAmount,
            "Insufficient account balance"
        );
        require(currency.approve(address(this), currencyAmount));
        availableTokens = availableTokens.sub(amount);
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        sales[msg.sender] = Sale(msg.sender, amount, false);
        emit Buy(msg.sender, currencyAmount, amount);
    }

    function claimTokens() external publicSaleEnded() {
        Sale storage sale = sales[msg.sender];
        require(sale.amount > 0, "Only investors");
        require(sale.tokensWithdrawn == false, "Already withdrawn");
        sale.tokensWithdrawn = true;
        mpadToken.transfer(sale.investor, sale.amount);
        emit Claim(msg.sender, sale.amount);
    }

    function withdraw() external onlyOwner() publicSaleEnded() {
        uint256 currencyBalance = currency.balanceOf(address(this));
        require(currencyBalance > 0, "Nothing to withdraw");
        currency.safeTransfer(owner(), currencyBalance);
        emit Withdraw(owner(), currencyBalance);
        if (availableTokens > 0) {
            mpadToken.transfer(
                address(0x000000000000000000000000000000000000dEaD),
                availableTokens
            );
            emit Burn(
                0x000000000000000000000000000000000000dEaD,
                availableTokens
            );
        }
    }

    function emergencyWithdrawal() external onlyOwner() {
        if (availableTokens > 0) {
            availableTokens = 0;
        }

        uint256 mpadBalance = mpadToken.balanceOf(address(this)); // avoid wrong transfer amount from creator
        if (mpadBalance > 0) {
            mpadToken.transfer(owner(), mpadBalance);
            emit EmergencyWithdrawal(owner(), mpadBalance);
        }

        uint256 currencyBalance = currency.balanceOf(address(this));
        if (currencyBalance > 0) {
            currency.safeTransferFrom(address(this), owner(), currencyBalance);
            emit Withdraw(owner(), currencyBalance);
        }
    }

    modifier publicSaleActive() {
        require(
            start <= block.timestamp &&
                block.timestamp <= end &&
                availableTokens > 0,
            "Not activated yet"
        );
        _;
    }

    modifier publicSaleNotActive() {
        require(block.timestamp < start, "Not started yet");
        _;
    }

    modifier publicSaleEnded() {
        require(
            block.timestamp >= end || availableTokens == 0,
            "Not ended yet"
        );
        _;
    }
}
