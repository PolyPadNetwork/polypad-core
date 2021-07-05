// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TierIDOPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each investor
    struct Sale {
        address investor; // Address of user
        uint256 amount; // Amount of tokens purchased
        bool tokensWithdrawn; // Withdrawal status
    }

    struct Investor {
        address investor; // Address of user
        uint256 amount; // Amount of tokens purchased
    }

    // List investors
    Investor[] private investorInfo;
    // Info of each investor that buy tokens.
    mapping(address => Sale) public sales;
    // Round 1 start time
    uint256 public round1Start;
    // Round 1 end time
    uint256 public round1End;
    // Round 2 start time
    uint256 public round2Start;
    // Round 1 end time
    uint256 public round2End;
    // Price of each token
    uint256 public price;
    // Amount of tokens remaining
    uint256 public availableTokens;
    // Total amount of tokens to be sold
    uint256 public totalAmount;
    // Total amount sold
    uint256 public totalAmountSold;
    // Min amount for each sale
    uint256 public minPurchase;
    // Max amount for each sake
    uint256 public maxPurchase;
    // Release time
    uint256 public releaseTime;
    // Whitelist addresses
    mapping(address => uint8) public poolWhiteList;
    address[] private listWhitelists;
    // Number of investors
    uint256 public numberParticipants;
    // Tiers allocations
    mapping(uint8 => uint256) public tierAllocations;

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
        uint256 _round1Start,
        uint256 _round1End,
        uint256 _round2Start,
        uint256 _round2End,
        uint256 _releaseTime,
        uint256 _price,
        uint256 _totalAmount,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) public {
        require(_token != address(0), "Zero token address");
        require(_currency != address(0), "Zero token address");
        require(_round1Start < _round1End, "_round1Start must be < _round1End");
        require(
            _round1End <= _round2Start,
            "_round1End must be <= _round2Start"
        );
        require(_round2Start < _round2End, "_round2Start must be < _round2End");
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
        round1Start = _round1Start;
        round1End = _round1End;
        round2Start = _round2Start;
        round2End = _round2End;
        releaseTime = _releaseTime;
        price = _price;
        totalAmount = _totalAmount;
        availableTokens = _totalAmount;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        numberParticipants = 0;
        totalAmountSold = 0;
        tierAllocations[1] = (_totalAmount * 2) / 100;
        tierAllocations[2] = (_totalAmount * 5) / 100;
        tierAllocations[3] = (_totalAmount * 10) / 100;
        tierAllocations[4] = (_totalAmount * 17) / 100;
        tierAllocations[5] = (_totalAmount * 26) / 100;
        tierAllocations[6] = (_totalAmount * 40) / 100;
    }

    // Buy tokens
    function buy(uint256 amount) external publicSaleActive nonReentrant {
        require(availableTokens > 0, "All tokens were purchased");
        require(amount > 0, "Amount must be > 0");
        uint8 tier = getAddressTier(msg.sender);
        require(tier > 0, "You are not whitelisted");
        uint256 remainingAllocation = tierAllocations[tier];
        if (block.timestamp >= round2Start) {
            remainingAllocation = availableTokens;
        }
        require(
            amount <= remainingAllocation && amount <= availableTokens,
            "Not enough token"
        );
        Sale storage sale = sales[msg.sender];
        require(amount <= maxPurchase.sub(sale.amount), "Exceed amount");
        if (sale.amount == 0) {
            require(
                amount >= minPurchase && amount <= maxPurchase,
                "Have to buy between minPurchase and maxPurchase"
            );
        }
        uint256 currencyAmount = amount.mul(price).div(1e18);
        require(
            currency.balanceOf(msg.sender) >= currencyAmount,
            "Insufficient account balance"
        );
        require(currency.approve(address(this), currencyAmount));
        availableTokens = availableTokens.sub(amount);
        if (block.timestamp <= round1End) {
            tierAllocations[tier] = tierAllocations[tier].sub(amount);
        }
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
        if (sale.amount == 0) {
            sales[msg.sender] = Sale(msg.sender, amount, false);
            numberParticipants += 1;
        } else {
            sales[msg.sender] = Sale(msg.sender, amount + sale.amount, false);
        }
        totalAmountSold += amount;
        investorInfo.push(Investor(msg.sender, amount));
        emit Buy(msg.sender, currencyAmount, amount);
    }

    function getInvestors()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addrs = new address[](numberParticipants);
        uint256[] memory funds = new uint256[](numberParticipants);

        for (uint256 i = 0; i < numberParticipants; i++) {
            Investor storage investor = investorInfo[i];
            addrs[i] = investor.investor;
            funds[i] = investor.amount;
        }

        return (addrs, funds);
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
        if (availableTokens > 0) {
            availableTokens = 0;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, tokenBalance);
        emit Withdraw(msg.sender, tokenBalance);
        uint256 currencyBalance = currency.balanceOf(address(this));
        currency.safeTransfer(msg.sender, currencyBalance);
        emit Withdraw(msg.sender, currencyBalance);
    }

    // Withdraw without caring about progress. EMERGENCY ONLY.
    function emergencyWithdraw() external onlyOwner nonReentrant {
        if (availableTokens > 0) {
            availableTokens = 0;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, tokenBalance);
        emit Withdraw(msg.sender, tokenBalance);
        uint256 currencyBalance = currency.balanceOf(address(this));
        currency.safeTransfer(msg.sender, currencyBalance);
        emit Withdraw(msg.sender, currencyBalance);
    }

    // Add addresses to whitelist
    function addToPoolWhiteList(address[] memory _users, uint8[] memory _tiers)
        public
        onlyOwner
        returns (bool)
    {
        require(_users.length == _tiers.length, "Invalid length");
        for (uint8 i = 0; i < _users.length; i++) {
            poolWhiteList[_users[i]] = _tiers[i];
        }

        return true;
    }

    // Get the whitelist
    function getPoolWhiteLists() public view returns (address[] memory) {
        return listWhitelists;
    }

    // Get user tier
    function getAddressTier(address _user) public view returns (uint8) {
        return poolWhiteList[_user];
    }

    modifier isWhitelisted(address _address) {
        require(getAddressTier(_address) > 0, "You are not whitelisted");
        _;
    }

    modifier publicSaleActive() {
        require(
            (round1Start <= block.timestamp && block.timestamp <= round1End) ||
                (round2Start <= block.timestamp &&
                    block.timestamp <= round2End),
            "Not activated yet"
        );
        _;
    }

    modifier publicSaleNotActive() {
        require(
            block.timestamp < round1Start ||
                (round1End < block.timestamp && block.timestamp < round2Start),
            "Not started yet"
        );
        _;
    }

    modifier publicSaleEnded() {
        require(
            block.timestamp >= round2End || availableTokens == 0,
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
