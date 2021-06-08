// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PoolFactory.sol";

contract IDOPoolPublic is Ownable {
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
    // List admins
    mapping(address => bool) private admins;
    // Number of investors
    uint256 public numberParticipants;

    IERC20 public token;
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
        uint256 _lockDuration,
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
        releaseTime = start + _lockDuration;
        price = _price;
        totalAmount = _totalAmount;
        availableTokens = _totalAmount;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
    }

    // Buy tokens
    function buy(uint256 amount)
        external
        poolActive()
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
        numberParticipants.add(1);
        emit Buy(msg.sender, currencyAmount, amount);
    }

    // Withdraw purchased tokens
    function claimTokens() external canClaim() {
        Sale storage sale = sales[msg.sender];
        require(sale.amount > 0, "Only investors");
        require(sale.tokensWithdrawn == false, "Already withdrawn");
        sale.tokensWithdrawn = true;
        token.transfer(sale.investor, sale.amount);
        emit Claim(msg.sender, sale.amount);
    }

    // Admin withdraw after the sale ends
    function withdraw() external onlyAdmins() poolEnded() {
        uint256 amount = currency.balanceOf(address(this));
        currency.safeTransfer(factoryOwner(), amount);
        emit Withdraw(owner(), amount);
        if (availableTokens > 0) {
            token.transfer(factoryOwner(), availableTokens);
        }
    }

    // Withdraw without caring about progress. EMERGENCY ONLY.
    function emergencyWithdraw() external onlyAdmins() {
        uint256 currencyBalance = currency.balanceOf(address(this));
        if (currencyBalance > 0) {
            currency.safeTransfer(factoryOwner(), currencyBalance);
            emit Withdraw(factoryOwner(), currencyBalance);
        }
        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance > 0) {
            token.transfer(factoryOwner(), tokenBalance);
            emit EmergencyWithdraw(factoryOwner(), tokenBalance);
        }
    }

    modifier poolActive() {
        require(
            start <= block.timestamp &&
                block.timestamp <= end &&
                availableTokens > 0,
            "Pool is not active"
        );
        _;
    }

    modifier poolNotActive() {
        require(block.timestamp < start, "Not activated yet");
        _;
    }

    modifier poolEnded() {
        require(
            block.timestamp >= end || availableTokens == 0,
            "Not ended yet"
        );
        _;
    }

    // Add addresses to whitelist
    function addToPoolWhiteList(address[] memory _users)
        public
        onlyFactoryOwner()
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

    // Add addresses to admin list
    function addToPoolAdmins(address[] memory _users)
        public
        onlyFactoryOwner()
        returns (bool)
    {
        for (uint256 i = 0; i < _users.length; i++) {
            admins[_users[i]] = true;
        }
        return true;
    }

    // Remove addresses from admin list
    function removeFromPoolAdmins(address[] memory _users)
        public
        onlyFactoryOwner()
        returns (bool)
    {
        for (uint256 i = 0; i < _users.length; i++) {
            admins[_users[i]] = false;
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

    function isPoolAdmins(address _user) public view returns (bool) {
        return admins[_user];
    }

    modifier onlyAdmins() {
        require(
            isPoolAdmins(msg.sender) ||
                msg.sender == PoolFactory(owner()).owner(),
            "you are not admin"
        );
        _;
    }

    modifier onlyFactoryOwner() {
        require(msg.sender == PoolFactory(owner()).owner());
        _;
    }

    function factoryOwner() private view returns (address) {
        return PoolFactory(owner()).owner();
    }

    modifier canClaim() {
        require(block.timestamp >= releaseTime, "You can not claim token");
        _;
    }
}
