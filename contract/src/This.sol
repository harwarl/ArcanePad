// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// import "@openzeppelin/contracts/access/AccessControl.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/access/Ownable2Step.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import {Vesting} from "./vesting/Vesting.sol";

// contract IDOPool is AccessControl, Ownable2Step, Pausable, ReentrancyGuard {
//     using SafeMath for uint256;
//     using SafeERC20 for IERC20;

//     bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

//     // user address => whitelisted status
//     mapping(address => bool) public whitelist;
//     // user address => purchased token amount
//     mapping(address => uint256) public purchasedAmounts;
//     // whitelisted Users Array, even removed users will remain
//     address[] private _whitelistedUsers;
//     // Token to buy the IDO Token with
//     IERC20 public purchaseToken;
//     // IDO Token (to be bought token)
//     IERC20 public ido;
//     // Date timestamp when token sale starts
//     uint256 public startTime;
//     // Date timestamp when token sale ends
//     uint256 public endTime;
//     // requires account whitelist
//     bool public isWhitelistEnabled;
//     // The total purchased IDO amount
//     uint256 public totalPurchasedAmount;
//     // The total Invested USDT
//     uint256 public totalInvested;
//     // Vesting Contract
//     Vesting public vestingContract;

//     // Fin info of the IDo Token
//     struct FinInfo {
//         // IDO Token Price
//         uint256 idoPrice;
//         // Soft Cap to be considered successfull
//         uint256 softCap;
//         // Max Cap to be reached
//         uint256 hardCap;
//         // The cap amount each user can purchase IDO up to
//         uint256 purchaseCap;
//         // Min amount of purchase Token that can buy
//         uint256 minPayment;
//     }
//     // // Max amount of purchase token that can buy
//     // uint256 maxPayment;

//     // Used for returning purchase history
//     struct Purchase {
//         // Account that bought IDo token
//         address account;
//         // Amount of IDO token purchased
//         uint256 amount;
//     }

//     // ERC20 Permit
//     struct PermitRequest {
//         uint256 nonce;
//         uint256 deadline;
//         uint8 v;
//         bytes32 r;
//         bytes32 s;
//     }

//     FinInfo public finInfo;
//     Purchase[] public purchases;

//     // events
//     event IdoPriceChanged(uint256 idoPrice);
//     event PurchaseCapChanged(uint256 purchaseCap);
//     event WhiteListAdded(address indexed account);
//     event WhiteListRemoved(address indexed account);
//     event Deposited(address indexed account, uint256 amount);
//     event Purchased(address indexed buyer, uint256 idoAmount, uint256 paidAmount);
//     event Claimed(address indexed account, uint256 amount);

//     // errors
//     error IDOPool__ZeroAddress();
//     error IDOPool__PurchaseTokenZeroAddress();
//     error IDOPool__InvalidTimeStamp();
//     error IDOPool__InvalidPurchaseCap();
//     error IDOPool__InvalidTokenPrice();
//     error IDOPool__InvalidSoftCap();
//     error IDOPool__InvalidHardCap();
//     error IDOPool__NotOperator();
//     error IDOPool__IsOperator();
//     error IDOPool__DepositAmountInvalid();
//     error IDOPool__InvalidPurchaseAmount();
//     error IDOPool__SaleAlreadyEnded();
//     error IDOPool__SaleNotStarted();
//     error IDOPool__CallerNotWhitelisted();
//     error IDOPool_PurchaseCapExceeded();
//     error IDOPool__InsufficientIDOBalance();
//     error IDOPool__InsufficientFunds();
//     error IDOPool__Overfilled();
//     error IDOPool__BelowMinPayment();
//     error IDOPool__VestingContractZeroAddress();
//     error IDOPool__SaleNotEnded();
//     error IDOPool__NothingToClaim();
//     error IDOPool__AlreadyClaimed();

//     constructor(
//         IERC20 _purchaseToken,
//         IERC20 _ido,
//         FinInfo memory _finInfo,
//         uint256 _startTime,
//         uint256 _endTime,
//         bool _isWhitelistEnabled,
//         address _vestingContract
//     ) {
//         if (address(_ido) == address(0)) revert IDOPool__ZeroAddress();
//         if (address(_purchaseToken) == address(0)) revert IDOPool__PurchaseTokenZeroAddress();
//         if (address(_vestingContract) == address(0)) revert IDOPool__VestingContractZeroAddress();
//         if (block.timestamp > _startTime || _startTime >= _endTime) revert IDOPool__InvalidTimeStamp();
//         if (_finInfo.purchaseCap <= 0) revert IDOPool__InvalidPurchaseCap();
//         if (_finInfo.idoPrice <= 0) revert IDOPool__InvalidTokenPrice();
//         if (_finInfo.hardCap <= 0) revert IDOPool__InvalidHardCap();
//         if (_finInfo.softCap <= 0) revert IDOPool__InvalidSoftCap();

//         finInfo = _finInfo;
//         ido = _ido;
//         purchaseToken = _purchaseToken;
//         startTime = _startTime;
//         endTime = _endTime;
//         isWhitelistEnabled = _isWhitelistEnabled;
//         vestingContract = Vesting(payable(_vestingContract));
//     }

//     // ========================================= MODIFIERS =========================================
//     /**
//      */
//     modifier onlyOperator() {
//         if (!hasRole(OPERATOR_ROLE, msg.sender)) revert IDOPool__NotOperator();
//         _;
//     }

//     /*//////////////////////////////////////////////////////////////
//                                 SETTERS
//     //////////////////////////////////////////////////////////////*/
//     /**
//      * @dev set Ido token price in purchaseToken
//      * * @param _idoPrice The new price for the Ido Token
//      */
//     function setIdoPrice(uint256 _idoPrice) external onlyOwner {
//         if (_idoPrice <= 0) revert IDOPool__InvalidTokenPrice();
//         finInfo.idoPrice = _idoPrice;
//         // emit
//         emit IdoPriceChanged(_idoPrice);
//     }

//     /**
//      * @dev Set purchase cap for each user
//      * @param _purchaseCap the new purchase cap for the ido token
//      */
//     function setPurchaseCap(uint256 _purchaseCap) external onlyOwner {
//         if (_purchaseCap <= 0) revert IDOPool__InvalidPurchaseCap();
//         finInfo.purchaseCap = _purchaseCap;
//         // emit event
//         emit PurchaseCapChanged(_purchaseCap);
//     }

//     /*//////////////////////////////////////////////////////////////
//                                  ROLES
//     //////////////////////////////////////////////////////////////*/
//     /**
//      * @dev Add an account to the operator role.
//      * @param account address
//      */
//     function addOperator(address account) public onlyOwner {
//         if (hasRole(OPERATOR_ROLE, account)) revert IDOPool__IsOperator();
//         grantRole(OPERATOR_ROLE, account);
//     }

//     /**
//      * @dev Remove an account from the operator role.
//      * @param account address
//      */
//     function removeOperator(address account) public onlyOwner {
//         if (!hasRole(OPERATOR_ROLE, account)) revert IDOPool__NotOperator();
//         revokeRole(OPERATOR_ROLE, account);
//     }

//     /**
//      * @dev Check if an account is operator.
//      * @param account address
//      */
//     function checkOperator(address account) public view returns (bool) {
//         return hasRole(OPERATOR_ROLE, account);
//     }

//     /*//////////////////////////////////////////////////////////////
//                                 PAUSABLE
//     //////////////////////////////////////////////////////////////*/
//     /**
//      * @dev pause the sale
//      */
//     function pause() external onlyOperator {
//         super._pause();
//     }

//     /**
//      * @dev unpause the sale
//      */
//     function unpause() external onlyOperator {
//         super._unpause();
//     }

//     /*//////////////////////////////////////////////////////////////
//                                WHITELIST
//     //////////////////////////////////////////////////////////////*/
//     /**
//      * @dev returns a list of whitelisted addresses
//      */
//     function whitelistedUsers() external view returns (address[] memory) {
//         uint256 count = 0;
//         for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
//             if (whitelist[_whitelistedUsers[i]]) {
//                 count++;
//             }
//         }

//         // Create a new array of active counted whitelists
//         address[] memory active = new address[](count);
//         uint256 index = 0;
//         for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
//             if (whitelist[_whitelistedUsers[i]]) {
//                 active[index] = _whitelistedUsers[i];
//                 index++;
//             }
//         }

//         return active;
//     }

//     /**
//      * @dev Adds wallets to whitelist
//      * @param accounts The array of addresses to be added to whitelist
//      */
//     function addWhiteList(address[] memory accounts) external onlyOperator whenNotPaused {
//         for (uint256 i = 0; i < accounts.length; i++) {
//             if (accounts[i] == address(0)) revert IDOPool__ZeroAddress();
//             if (!whitelist[accounts[i]]) {
//                 whitelist[accounts[i]] = true;
//                 _whitelistedUsers.push(accounts[i]);
//                 emit WhiteListAdded(accounts[i]);
//             }
//         }
//     }

//     /**
//      * @dev Removes wallets to whitelist
//      * @param accounts The array of addresses to be removed from whitelist
//      * address remains in the "whitelisted users array"
//      */
//     function removeWhitelist(address[] memory accounts) external onlyOperator whenNotPaused {
//         for (uint256 i = 0; i < accounts.length; i++) {
//             if (accounts[i] == address(0)) revert IDOPool__ZeroAddress();
//             if (whitelist[accounts[i]]) {
//                 whitelist[accounts[i]] = false;
//                 emit WhiteListRemoved(accounts[i]);
//             }
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                             PURCHASE HISTORY
//     //////////////////////////////////////////////////////////////*/
//     // /**
//     //  * @dev Returns purchase history (wallet address, amount)
//     //  * The result array can include zero amount item
//     //  */
//     // function purchaseHistory() external view returns (Purchase memory) {
//     //     if( isWhitelistEnabled){
//     //         Purchase[] memory purchases = new Purchase[](_whitelistedUsers.length);
//     //         for(uint256 i = 0; i < _whitelistedUsers.length; i++){
//     //             purchases[i].account = _whitelistedUsers[i];
//     //             purchases[i].amount = purchasedAmounts[_whitelistedUsers[i]];
//     //         }
//     //         return purchases;
//     //     } else {
//     //     }
//     // }

//     /**
//      * @dev deposit IDO token to the sale contract
//      * @param amount of the ido
//      */
//     function depositTokens(uint256 amount) external onlyOperator whenNotPaused {
//         if (amount <= 0) revert IDOPool__DepositAmountInvalid();
//         ido.safeTransferFrom(_msgSender(), address(this), amount);
//         emit Deposited(_msgSender(), amount);
//     }

//     /**
//      * @dev Permit and deposit IDO token to the sale contract
//      * If token does not have `permit` function, this function does not work
//      */
//     function permitAndDepositTokens(uint256 amount, PermitRequest calldata permitOptions)
//         external
//         onlyOperator
//         whenNotPaused
//     {
//         if (amount <= 0) revert IDOPool__DepositAmountInvalid();
//         // Permit
//         IERC20Permit(address(ido)).permit(
//             _msgSender(),
//             address(this),
//             amount,
//             permitOptions.deadline,
//             permitOptions.v,
//             permitOptions.r,
//             permitOptions.s
//         );
//         ido.safeTransferFrom(_msgSender(), address(this), amount);
//         emit Deposited(_msgSender(), amount);
//     }

//     /**
//      * @dev Purchase IDO token
//      * @param amount The amount of IDO token to buy
//      * works for whitelisted enabled tokens and Public tokens
//      */
//     function purchase(uint256 amount) external nonReentrant whenNotPaused {
//         if (startTime > block.timestamp) revert IDOPool__SaleNotStarted();
//         if (block.timestamp >= endTime) revert IDOPool__SaleAlreadyEnded();
//         if (amount <= 0) revert IDOPool__InvalidPurchaseAmount();
//         address buyer = _msgSender();

//         if (isWhitelistEnabled) {
//             if (!whitelist[buyer]) revert IDOPool__CallerNotWhitelisted();
//         }

//         if (purchasedAmounts[buyer] + amount > finInfo.purchaseCap) revert IDOPool_PurchaseCapExceeded();

//         uint256 newPurchasedAmount = totalPurchasedAmount.add(amount);
//         if (newPurchasedAmount > ido.balanceOf(address(this))) revert IDOPool__InsufficientIDOBalance();

//         uint256 paidAmount = amount.mul(finInfo.idoPrice).div(10 ** 18);
//         if (paidAmount < finInfo.minPayment) revert IDOPool__BelowMinPayment();

//         uint256 newTotalInvested = totalInvested.add(paidAmount);
//         if (newTotalInvested > finInfo.hardCap) revert IDOPool__Overfilled();

//         // update state
//         purchasedAmounts[buyer] += amount;
//         totalPurchasedAmount = newPurchasedAmount;
//         totalInvested = newTotalInvested;

//         purchaseToken.safeTransferFrom(buyer, address(this), paidAmount);
//         emit Purchased(buyer, amount, paidAmount);
//     }

//     /**
//      * @dev Purchase IDO token
//      * @param amount The amount of IDO token to buy
//      * works for whitelisted enabled tokens and Public tokens
//      */
//     function permitAndPurchase(uint256 amount, PermitRequest calldata permitOptions)
//         external
//         nonReentrant
//         whenNotPaused
//     {
//         if (startTime > block.timestamp) revert IDOPool__SaleNotStarted();
//         if (block.timestamp >= endTime) revert IDOPool__SaleAlreadyEnded();
//         if (amount <= 0) revert IDOPool__InvalidPurchaseAmount();
//         address buyer = _msgSender();

//         if (isWhitelistEnabled) {
//             if (!whitelist[buyer]) revert IDOPool__CallerNotWhitelisted();
//         }

//         if (purchasedAmounts[buyer] + amount > finInfo.purchaseCap) revert IDOPool_PurchaseCapExceeded();

//         uint256 newPurchasedAmount = totalPurchasedAmount.add(amount);
//         if (newPurchasedAmount > ido.balanceOf(address(this))) revert IDOPool__InsufficientIDOBalance();

//         uint256 paidAmount = amount.mul(finInfo.idoPrice).div(10 ** 18);
//         if (paidAmount < finInfo.minPayment) revert IDOPool__BelowMinPayment();

//         uint256 newTotalInvested = totalInvested.add(paidAmount);
//         if (newTotalInvested > finInfo.hardCap) revert IDOPool__Overfilled();

//         // update state
//         purchasedAmounts[buyer] += amount;
//         totalPurchasedAmount = newPurchasedAmount;
//         totalInvested = newTotalInvested;
//         IERC20Permit(address(purchaseToken)).permit(
//             buyer, address(this), paidAmount, permitOptions.deadline, permitOptions.v, permitOptions.r, permitOptions.s
//         );

//         purchaseToken.safeTransferFrom(buyer, address(this), paidAmount);
//         emit Purchased(buyer, amount, paidAmount);
//     }

//     /*//////////////////////////////////////////////////////////////
//                                  CLAIM
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @dev this is the first claim by the user, This sends the token to the vesting contract and allows the user to claim the particular percentage available at TGE. Note, gas fee will be high
//      */
//     function claim() external nonReentrant whenNotPaused {
//         // Check endtime
//         if (endTime > block.timestamp) revert IDOPool__SaleNotEnded();
//         uint256 entitled = purchasedAmounts[_msgSender()];
//         if (entitled <= 0) revert IDOPool__InsufficientFunds();

//         uint256 vestingCount = vestingContract.getVestingScheduleCountByBeneficiary(_msgSender());

//         if(vestingCount == 0){
//             // transfer funds to the vesting contract
//             ido.safeTransfer(address(vestingContract), entitled);

//             // Create vesting schedule for the user
//             vestingContract.createVestingSchedule(
//                 _msgSender(),
//                 0,
//                 endTime,
//                 180 days,
//                 1 days,
//                 false,
//                 entitled
//             );
//         }

//         // If Schedule already exists i.e future claims, just release
//         bytes32 scheduleId = vestingContract.computeVestingScheduleIdForAddressAndIndex(_msgSender(), 0);
//         uint256 releasable = vestingContract.computeReleasableAmount(scheduleId);

//         if (releasable > 0) {
//             vestingContract.release(scheduleId, releasable);
//         }

//         emit Claimed(msg.sender, releasable);
//     }

//     function sweep() external onlyOwner() {}
// }
