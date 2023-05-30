//SPDX-License-Identifier:MIT
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
pragma solidity ^0.8.4;
contract P2Plending{
    struct loanListings {
    address lenderAddress;
    uint loanAmount;
    uint roi;
    uint collateralRatio;
    uint timePeriod;
    uint liquidationRatio;
    bool isActive;
    address borrowerAddress;
    uint startDate;
    uint borrowedDate;
    uint collateralReceived;
    uint liquidationAmount;
}
mapping (uint=>loanListings) public loan;
uint loanNo;
uint protocolFee;
address public owner;
uint currentPrice;
uint currentCollateralPrice = SafeMath.mul(loan[loanNo].collateralReceived, currentPrice);
uint collateralAmount = SafeMath.div(SafeMath.mul(loan[loanNo].loanAmount, loan[loanNo].collateralRatio), 100);
uint roiAmount = SafeMath.div(SafeMath.mul(SafeMath.mul(loan[loanNo].loanAmount, loan[loanNo].roi), SafeMath.div(block.number - loan[loanNo].borrowedDate, 31536000)), 100); //365 days = 31536000 seconds
uint protocolFeeAmount = SafeMath.div(SafeMath.mul(loan[loanNo].loanAmount, protocolFee), 100);
event loanListed(uint loanNo, address lenderAddress, uint loanAmount, uint roi, uint collateralRatio, uint timePeriod, uint liquidationRatio);
event loanBorrowed(uint  loanNo, address borrowerAddress, uint collateralAmount, uint borrowedDate, uint liquidationAmount);
event loanRepaid(uint  loanNo, address  borrowerAddress, uint loanAmount, uint roiAmount, uint protocolFeeAmount, uint totalRepayed);
event ownerChanged(address  oldOwner, address  newOwner);
event protocolFeeChanged(uint oldFee, uint newFee);
event loanLiquidated(uint  loanNo, address  liquidatorAddress, uint liquidationAmount, uint roiAmount, uint liquidationDate, uint liquidatedAmaount);
event collateralWithdrawn(uint  loanNo, address  borrowerAddress, uint oldCollateralAmount, uint withdrawAmount);
event collateralIncreased(uint  loanNo, address  borrowerAddress, uint addedCollateral);
constructor() payable {
    owner = msg.sender;
    protocolFee = msg.value;
}
modifier onlyOwner {
    require(msg.sender == owner, "Only owner can call this function.");
    _;
}
// Maximum number of loans that can be listed
uint constant MAX_LOANS = 50;

// Current number of loans listed
uint public numLoans;
function listLoan(uint _loanAmount,uint _roi,uint _collateralRatio,uint _timePeriod,uint _liquidationRatio) public payable{
    require(_loanAmount > 0, "Loan amount must be greater than 0");
    require(_roi > 0 && _roi < 20, "roi must be greater than 0% and less than 20%");
    require(_collateralRatio > 100 && _collateralRatio < 200, "Collateral Ratio must be greater than 100% and less than 200%");
    require(_liquidationRatio < 100, "Liquidation Ratio must be less than 100% ");
    require(_timePeriod > 2629746, "Time period should be at least a 30 days");
    require(msg.value == _loanAmount, "Funds should match the loan amount");
    require(numLoans < MAX_LOANS, "Maximum number of loans reached");

    loan[loanNo] = loanListings(msg.sender, _loanAmount, _roi, _collateralRatio, _timePeriod, _liquidationRatio, true, address(0), block.number, 0, 0, 0);
    loanNo++;
    numLoans++;
    emit loanListed(loanNo-1, msg.sender, _loanAmount, _roi, _collateralRatio, _timePeriod, _liquidationRatio);
}
function borrow(uint _loanNo) public payable{
    require(_loanNo >= 0, "Invalid loan number");
    require(msg.value > 0, "Invalid amount entered");
    require(msg.sender != loan[_loanNo].lenderAddress, "lender can not borrow his loan");
    require(loan[_loanNo].isActive == true, "This loan is already taken");
    require(msg.value>= collateralAmount,"Insufficient collateral");
    payable(msg.sender).transfer(loan[_loanNo].loanAmount);
    loan[_loanNo].collateralReceived = msg.value;
    loan[_loanNo].borrowedDate = block.number;
    loan[_loanNo].liquidationAmount = msg.value * loan[_loanNo].liquidationRatio / 100 * currentPrice;
    loan[_loanNo].isActive = false;
    loan[_loanNo].borrowerAddress = msg.sender;
    emit loanBorrowed(_loanNo, msg.sender, msg.value, block.number, loan[_loanNo].liquidationAmount);
}
function repay(uint _loanNo) public payable {
    require(_loanNo >= 0, "Invalid loan number");
    require(msg.value > 0, "Invalid amount entered");
    require(msg.sender==loan[_loanNo].borrowerAddress,"You did not borrow this loan");
    require(msg.value== loan[_loanNo].loanAmount+(roiAmount)+(protocolFeeAmount),"Funds should match the Required amount");
    
    payable(msg.sender).transfer(loan[_loanNo].collateralReceived);
    loan[_loanNo].isActive=true;
    loan[_loanNo].borrowerAddress=address(0);
    loan[_loanNo].borrowedDate = 0;
    loan[_loanNo].collateralReceived =0;
    loan[_loanNo].liquidationAmount = 0;
    emit loanRepaid(_loanNo, msg.sender, loan[_loanNo].loanAmount, roiAmount, protocolFeeAmount, msg.value);
}
function changeOwner(address _newOwner) public onlyOwner {
    require(msg.sender != _newOwner, "You already are the owner");
    owner = _newOwner;
    emit ownerChanged( msg.sender, _newOwner);
}
function changeProtocolFee(uint _newFee) public onlyOwner {
    require(_newFee >= 0, "Protocol Fee should not be negative");
    protocolFee = _newFee;
    emit protocolFeeChanged(protocolFee, _newFee);
}
function liquidate(uint _loanNo) public {
    require(_loanNo >= 0, "Invalid loan number");
    
    require(loan[_loanNo].isActive == false, "Loan is not active.");
    require(msg.sender == loan[_loanNo].lenderAddress, "Only lender can call this function.");
    
    require(currentCollateralPrice <= loan[_loanNo].liquidationAmount, "Collateral amount is above liquidation amount.");
    require(block.number >= loan[_loanNo].startDate + loan[_loanNo].timePeriod, "Loan period not over yet.");
    payable(loan[_loanNo].lenderAddress).transfer(loan[_loanNo].loanAmount + (roiAmount));
    loan[_loanNo].isActive = false;
    loan[_loanNo].borrowerAddress = address(0);
    emit loanLiquidated(_loanNo, msg.sender, loan[_loanNo].liquidationAmount, roiAmount, block.number, loan[_loanNo].loanAmount + (roiAmount) );
}
using SafeMath for uint256;
function withdrawCollateral(uint _loanNo) public payable {
    require(_loanNo >= 0, "Invalid loan number");
    require(msg.value > 0, "Amount not entered");
    require(loan[_loanNo].isActive == false, "Loan is not active.");
    require(msg.sender == loan[_loanNo].borrowerAddress, "Only borrower can withdraw his collateral");
    require(currentCollateralPrice >= loan[_loanNo].liquidationAmount, "Collateral amount is below liquidation amount. Add funds!!");
    require(loan[_loanNo].liquidationAmount <= currentCollateralPrice .sub( msg.value), "Amount is greater than liquidation Amount");
    
    payable(msg.sender).transfer(msg.value);
    loan[_loanNo].collateralReceived = loan[_loanNo].collateralReceived.sub(msg.value);
    emit collateralWithdrawn(_loanNo, msg.sender, loan[_loanNo].collateralReceived, msg.value);
}
function increaseCollateral(uint _loanNo) public payable {
    require(_loanNo >= 0, "Invalid loan number");
    require(msg.value > 0, "Amount not entered");
    require(loan[_loanNo].isActive == false, "Loan is not active.");
    require(msg.sender == loan[_loanNo].borrowerAddress, "Only loaned borrower can increase his collateral");
    loan[_loanNo].collateralReceived += msg.value;
    emit collateralIncreased(_loanNo, msg.sender, msg.value);
}
}