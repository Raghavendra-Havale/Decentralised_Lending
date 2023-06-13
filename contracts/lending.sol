//SPDX-License-Identifier:MIT
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
pragma solidity ^0.8.12;

contract P2Plending {
    using SafeMath for uint256;
    struct loanListings {
        address lenderAddress;
        uint256 loanAmount;
        uint256 roi;
        uint256 collateralRatio;
        uint256 timePeriod;
        uint256 liquidationRatio;
        bool isActive;
        address borrowerAddress;
        uint256 startDate;
        uint256 borrowedDate;
        uint256 collateralReceived;
        uint256 liquidationAmount;
    }
    mapping(uint256 => loanListings) public loan;
    uint256 public loanNo;
    uint256 public protocolFee = 2; //protocol fee is 2%
    address public owner;
    struct TokenPrice {
        AggregatorV3Interface priceFeed;
        string symbol;
    }
    uint256[] public currentPrice;

    TokenPrice[] public tokenD;

    constructor() {
        owner = payable(msg.sender);
        tokenD.push(
            TokenPrice(
                AggregatorV3Interface(
                    0x694AA1769357215DE4FAC081bf1f309aDC325306
                    ),
                "ETH")
        );
        tokenD.push(
            TokenPrice(
                AggregatorV3Interface(
                    0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
                ),
                "BTC"
            )
        );
        tokenD.push(
            TokenPrice(
                AggregatorV3Interface(
                    0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
                ),
                "USDC"
            )
        ); // Add more tokens here
    }

    function getLatestPrice() public {
        for (uint256 i = 0; i < tokenD.length; i++) {
            (, int256 price, , , ) = tokenD[i].priceFeed.latestRoundData();
            currentPrice.push(uint256(price));
        }
    }
   event loanListed(
        uint256 loanNo,
        address lenderAddress,
        uint256 loanAmount,
        uint256 roi,
        uint256 collateralRatio,
        uint256 timePeriod,
        uint256 liquidationRatio
    );
    event loanBorrowed(
        uint256 loanNo,
        address borrowerAddress,
        uint256 collateralAmount,
        uint256 borrowedDate,
        uint256 liquidationAmount
    );
    event loanRepaid(
        uint256 loanNo,
        address borrowerAddress,
        uint256 loanAmount,
        uint256 roiAmount,
        uint256 protocolFeeAmount,
        uint256 totalRepayed
    );
    event ownerChanged(address oldOwner, address newOwner);
    event protocolFeeChanged(uint256 oldFee, uint256 newFee);
    event loanLiquidated(
        uint256 loanNo,
        address liquidatorAddress,
        uint256 liquidationAmount,
        uint256 roiAmount,
        uint256 liquidationDate,
        uint256 liquidatedAmaount
    );
    event collateralWithdrawn(
        uint256 loanNo,
        address borrowerAddress,
        uint256 oldCollateralAmount,
        uint256 withdrawAmount
    );
    event collateralIncreased(
        uint256 loanNo,
        address borrowerAddress,
        uint256 addedCollateral
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    // Maximum number of loans that can be listed
    uint256 constant MAX_LOANS = 50;

    // Current number of loans listed
    uint256 public numLoans;

    function listLoan(
        uint256 _loanAmount,
        uint256 _roi,
        uint256 _collateralRatio,
        uint256 _timePeriod,
        uint256 _liquidationRatio
    ) public payable {
        require(_loanAmount > 0, "Loan amount must be greater than 0");
        require(
            _roi > 0 && _roi < 20,
            "roi must be greater than 0% and less than 20%"
        );
        require(
            _collateralRatio > 100 && _collateralRatio < 200,
            "Collateral Ratio must be greater than 100% and less than 200%"
        );
        require(
            _liquidationRatio < 100,
            "Liquidation Ratio must be less than 100% "
        );
        require(
            _timePeriod > 2629746,
            "Time period should be at least a 30 days"
        );
        require(msg.value == _loanAmount, "Funds should match the loan amount");
        require(numLoans < MAX_LOANS, "Maximum number of loans reached");

        require(msg.value == _loanAmount, "Funds should match the loan amount");

        loan[loanNo] = loanListings(
            msg.sender,
            _loanAmount,
            _roi,
            _collateralRatio,
            _timePeriod,
            _liquidationRatio,
            true,
            address(0),
            block.number,
            0,
            0,
            0
        );
        emit loanListed(
            loanNo,
            msg.sender,
            _loanAmount,
            _roi,
            _collateralRatio,
            _timePeriod,
            _liquidationRatio
        );

        loanNo++;
        numLoans++;
    }

    function borrow(uint256 _loanNo, uint256 range) public payable {
        require(_loanNo >= 0, "Invalid loan number");
        require(msg.value > 0, "Invalid amount entered");
        require(
            msg.sender != loan[_loanNo].lenderAddress,
            "lender can not borrow his loan"
        );
        require(loan[_loanNo].isActive == true, "This loan is already taken");
        uint256 collateralAmount = loan[_loanNo]
            .loanAmount
            .mul(loan[_loanNo].collateralRatio)
            .div(100);
        require(msg.value >= collateralAmount, "Insufficient collateral");
        payable(msg.sender).transfer(loan[_loanNo].loanAmount);
        loan[_loanNo].collateralReceived = msg.value;
        loan[_loanNo].borrowedDate = block.number;

        loan[_loanNo].liquidationAmount = loan[_loanNo]
            .collateralReceived
            .mul(loan[_loanNo].liquidationRatio)
            .div(100)
            .mul(currentPrice[range])
            .div(1e18);
        loan[_loanNo].isActive = false;
        loan[_loanNo].borrowerAddress = msg.sender;
        emit loanBorrowed(
            _loanNo,
            msg.sender,
            msg.value,
            block.number,
            loan[_loanNo].liquidationAmount
        );
    }

    function repay(uint256 _loanNo) public payable {
        uint256 roiAmount = SafeMath.div(
            SafeMath.mul(
                SafeMath.mul(loan[_loanNo].loanAmount, loan[_loanNo].roi),
                SafeMath.div(block.number - loan[loanNo].borrowedDate, 31536000)
            ),
            100
        ); //365 days = 31536000 seconds
        uint256 protocolFeeAmount = SafeMath.div(
            SafeMath.mul(loan[_loanNo].loanAmount, protocolFee),
            100
        );
        require(_loanNo >= 0, "Invalid loan number");
        require(msg.value > 0, "Invalid amount entered");
        require(
            msg.sender == loan[_loanNo].borrowerAddress,
            "You did not borrow this loan"
        );
        require(
            msg.value >=
                loan[_loanNo].loanAmount + (roiAmount) + (protocolFeeAmount),
            "Funds should match the Required amount"
        );

        payable(msg.sender).transfer(loan[_loanNo].collateralReceived);
        loan[_loanNo].isActive = true;
        loan[_loanNo].borrowerAddress = address(0);
        loan[_loanNo].borrowedDate = 0;
        loan[_loanNo].collateralReceived = 0;
        loan[_loanNo].liquidationAmount = 0;
        emit loanRepaid(
            _loanNo,
            msg.sender,
            loan[_loanNo].loanAmount,
            roiAmount,
            protocolFeeAmount,
            msg.value
        );
    }

    function changeOwner(address _newOwner) public onlyOwner {
        require(msg.sender != _newOwner, "You already are the owner");
        owner = _newOwner;
        emit ownerChanged(msg.sender, _newOwner);
    }

    function changeProtocolFee(uint256 _newFee) public onlyOwner {
        require(_newFee >= 0, "Protocol Fee should not be negative");
        protocolFee = _newFee;
        emit protocolFeeChanged(protocolFee, _newFee);
    }

    function liquidate(uint256 _loanNo, uint256 range) public {
        require(_loanNo >= 0, "Invalid loan number");
        // uint currentPrice;
        uint256 currentCollateralPrice = SafeMath.mul(
            loan[loanNo].collateralReceived,
            currentPrice[range]
        );
        uint256 roiAmount = SafeMath.div(
            SafeMath.mul(
                SafeMath.mul(loan[_loanNo].loanAmount, loan[_loanNo].roi),
                SafeMath.div(
                    block.number - loan[_loanNo].borrowedDate,
                    31536000
                )
            ),
            100
        ); //365 days = 31536000 seconds
        require(loan[_loanNo].isActive == false, "Loan is not active.");
        require(
            msg.sender == loan[_loanNo].lenderAddress,
            "Only lender can call this function."
        );

        require(
            currentCollateralPrice <= loan[_loanNo].liquidationAmount,
            "Collateral amount is above liquidation amount."
        );
        require(
            block.number >= loan[_loanNo].startDate + loan[_loanNo].timePeriod,
            "Loan period not over yet."
        );
        payable(loan[_loanNo].lenderAddress).transfer(
            loan[_loanNo].loanAmount + (roiAmount)
        );
        loan[_loanNo].isActive = false;
        loan[_loanNo].borrowerAddress = address(0);
        emit loanLiquidated(
            _loanNo,
            msg.sender,
            loan[_loanNo].liquidationAmount,
            roiAmount,
            block.number,
            loan[_loanNo].loanAmount + (roiAmount)
        );
    }

    function withdrawCollateral(uint256 _loanNo, uint256 range) public payable {
        // uint currentPrice;
        uint256 currentCollateralPrice = SafeMath.mul(
            loan[_loanNo].collateralReceived,
            currentPrice[range]
        );
        require(_loanNo >= 0, "Invalid loan number");
        require(msg.value > 0, "Amount not entered");
        require(loan[_loanNo].isActive == false, "Loan is not active.");
        require(
            msg.sender == loan[_loanNo].borrowerAddress,
            "Only borrower can withdraw his collateral"
        );
        require(
            currentCollateralPrice >= loan[_loanNo].liquidationAmount,
            "Collateral amount is below liquidation amount. Add funds!!"
        );
        require(
            loan[_loanNo].liquidationAmount <=
                currentCollateralPrice.sub(msg.value),
            "Amount is greater than liquidation Amount"
        );

        payable(msg.sender).transfer(msg.value);
        loan[_loanNo].collateralReceived = loan[_loanNo].collateralReceived.sub(
            msg.value
        );
        emit collateralWithdrawn(
            _loanNo,
            msg.sender,
            loan[_loanNo].collateralReceived,
            msg.value
        );
    }

    function increaseCollateral(uint256 _loanNo) public payable {
        require(_loanNo >= 0, "Invalid loan number");
        require(msg.value > 0, "Amount not entered");
        require(loan[_loanNo].isActive == false, "Loan is not active.");
        require(
            msg.sender == loan[_loanNo].borrowerAddress,
            "Only loaned borrower can increase his collateral"
        );
        loan[_loanNo].collateralReceived += msg.value;
        emit collateralIncreased(_loanNo, msg.sender, msg.value);
    }
}
