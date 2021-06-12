// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MpadPublicSale is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each investor
    struct Sale {
        address investor; // Address of user
        uint256 amount; // Amount of tokens purchased
        bool tokensWithdrawn; // Withdrawal status
    }

    // Info of each investor that buy tokens.
    mapping(address => Sale) public sales;
    // Start time
    uint256 public start;
    // End time
    uint256 public end;
    // Price of each token
    uint256 public price;
    // Amount of tokens remaining
    uint256 public availableTokens;
    // Total amount of tokens to be sold
    uint256 public totalAmount;
    // Min amount for each sale
    uint256 public minPurchase;
    // Max amount for each sake
    uint256 public maxPurchase;
    // Release time
    uint256 public releaseTime;
    // Whitelist addresses
    mapping(address => bool) public poolWhiteList;
    address[] private listWhitelists;
    // Number of investors
    uint256 public numberParticipants;

    // Token for sale
    IERC20 public token;
    // Token used to buy
    IERC20 public currency;

    event Buy(address indexed _user, uint256 _amount, uint256 _tokenAmount);
    event Claim(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event EmergencyWithdraw(address indexed _user, uint256 _amount);
    event Burn(address indexed _burnAddress, uint256 _amount);

    constructor(
        address _token,
        address _currency,
        uint256 _start,
        uint256 _end,
        uint256 _releaseTime,
        uint256 _price,
        uint256 _totalAmount,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) public {
        require(_token != address(0), "Zero token address");
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
        token = IERC20(_token);
        currency = IERC20(_currency);
        start = _start;
        end = _end;
        releaseTime = _releaseTime;
        price = _price;
        totalAmount = _totalAmount;
        availableTokens = _totalAmount;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        numberParticipants = 0;
    }

    // Buy tokens
    function buy(uint256 amount)
        external
        publicSaleActive
        nonReentrant
        checkPoolWhiteList(msg.sender)
    {
        Sale storage sale = sales[msg.sender];
        require(sale.amount == 0, "Already purchased"); // Each address in whitelist can only be purchased once
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
        numberParticipants += 1;
        emit Buy(msg.sender, currencyAmount, amount);
    }

    // Withdraw purchased tokens after release time
    function claimTokens() external canClaim nonReentrant {
        Sale storage sale = sales[msg.sender];
        require(sale.amount > 0, "Only investors");
        require(sale.tokensWithdrawn == false, "Already withdrawn");
        sale.tokensWithdrawn = true;
        token.transfer(sale.investor, sale.amount);
        emit Claim(msg.sender, sale.amount);
    }

    // Admin withdraw after the sale ends
    // The remaining tokens will be burned
    function withdraw() external onlyOwner publicSaleEnded nonReentrant {
        uint256 currencyBalance = currency.balanceOf(address(this));
        currency.safeTransfer(msg.sender, currencyBalance);
        emit Withdraw(msg.sender, currencyBalance);
        if (availableTokens > 0) {
            uint256 burnTokens = availableTokens;
            availableTokens = 0;
            token.transfer(
                address(0x000000000000000000000000000000000000dEaD),
                burnTokens
            );
            emit Burn(0x000000000000000000000000000000000000dEaD, burnTokens);
        }
    }

    // Withdraw without caring about progress. EMERGENCY ONLY.
    function emergencyWithdraw() external onlyOwner nonReentrant {
        if (availableTokens > 0) {
            availableTokens = 0;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance > 0) {
            token.transfer(msg.sender, tokenBalance);
            emit EmergencyWithdraw(msg.sender, tokenBalance);
        }

        uint256 currencyBalance = currency.balanceOf(address(this));
        if (currencyBalance > 0) {
            currency.safeTransfer(msg.sender, currencyBalance);
            emit Withdraw(msg.sender, currencyBalance);
        }
    }

    // Add addresses to whitelist
    function addToPoolWhiteList(address[] memory _users)
        public
        onlyOwner
        returns (bool)
    {
        for (uint256 i = 0; i < _users.length; i++) {
            if (poolWhiteList[_users[i]] != true) {
                poolWhiteList[_users[i]] = true;
                listWhitelists.push(address(_users[i]));
            }
        }
        return true;
    }

    // Get the whitelist
    function getPoolWhiteLists() public view returns (address[] memory) {
        return listWhitelists;
    }

    // Check if the address is in the list
    function isPoolWhiteListed(address _user) public view returns (bool) {
        return poolWhiteList[_user];
    }

    modifier checkPoolWhiteList(address _address) {
        require(isPoolWhiteListed(_address), "You are not whitelisted");
        _;
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

    modifier canClaim() {
        require(
            block.timestamp >= releaseTime,
            "Please wait until release time"
        );
        _;
    }
}
