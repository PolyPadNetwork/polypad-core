pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PoolFactory.sol";

contract IDOPoolPublic is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Sale {
        address investor;
        uint256 amount;
        bool tokensWithdrawn;
    }

    mapping(address => Sale) public sales;
    address public factory;
    uint256 public start;
    uint256 public end;
    uint256 public price;
    uint256 public availableTokens;
    uint256 public totalAmount;
    uint256 public minPurchase;
    uint256 public maxPurchase;
    uint256 public releaseTime;
    mapping(address => bool) public poolWhiteList;
    address[] private listWhitelists;

    IERC20 public token;
    IERC20 public currency;

    event PoolCreated();
    event Buy(address indexed _user, uint256 _amount, uint256 _tokenAmount);
    event Claim(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event Burn(address indexed _burnAddress, uint256 _amount);

    constructor(
        address _factory,
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
        factory = _factory;
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
        emit PoolCreated();
    }

    function buy(uint256 amount)
        external
        poolActive()
        checkPoolWhiteList(msg.sender)
    {
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

    function claimTokens() external canClaim() {
        Sale storage sale = sales[msg.sender];
        require(sale.amount > 0, "Only investors");
        require(sale.tokensWithdrawn == false, "Already withdrawn");
        sale.tokensWithdrawn = true;
        token.transfer(sale.investor, sale.amount);
        emit Claim(msg.sender, sale.amount);
    }

    function withdraw() external onlyFactoryOwner() poolEnded() {
        uint256 amount = currency.balanceOf(address(this));
        currency.safeTransfer(owner(), amount);
        emit Withdraw(owner(), amount);
        if (availableTokens > 0) {
            token.transfer(owner(), availableTokens);
        }
    }

    function emergencyWithdraw() public onlyFactoryOwner() {
        currency.safeTransfer(msg.sender, currency.balanceOf(address(this)));
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
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

    function addToPoolWhiteList(address[] memory _users) public returns (bool) {
        for (uint256 i = 0; i < _users.length; i++) {
            if (poolWhiteList[_users[i]] != true) {
                poolWhiteList[_users[i]] = true;
                listWhitelists.push(address(_users[i]));
            }
        }
        return true;
    }

    function getPoolWhiteLists() public view returns (address[] memory) {
        return listWhitelists;
    }

    function isPoolWhiteListed(address _user) public view returns (bool) {
        return poolWhiteList[_user];
    }

    modifier checkPoolWhiteList(address _address) {
        require(isPoolWhiteListed(_address), "You are not whitelisted");
        _;
    }

    modifier onlyFactoryOwner() {
        require(msg.sender == PoolFactory(factory).owner());
        _;
    }

    modifier canClaim() {
        require(block.timestamp >= releaseTime, "You can not claim token");
        _;
    }
}
