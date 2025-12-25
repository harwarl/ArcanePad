// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct VestingSchedule {
        // beneficiary of the tokens
        address beneficiary;
        // cliff time of the vesting start in seconds since Unix EPOCH
        uint256 cliff;
        // start time of the vesting period in seconds since Unix EPOCH
        uint256 start;
        // duration of the vesting in seconds
        uint256 duration;
        // duration of the slice period of the vesting in seconds
        uint256 slicePeriodSeconds;
        // whether or not the vesting is revocable
        bool revocable;
        // total amount of token to be released at the end of vesting
        uint256 amountTotal;
        // total amount released
        uint256 released;
        // whether or not vesting is revoked
        bool revoked;
    }

    // Address of the ERC20 token
    IERC20 private immutable _token;

    // Array of the vesting scheduleIds
    bytes32[] private vestingScheduleIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;
    mapping(address => uint256) private holdersVestingCount;

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(!vestingSchedules[vestingScheduleId].revoked);
        _;
    }

    /**
     * @dev create the vesting contract
     * @param token_ address of the ERC20 token contract
     */
    constructor(address token_) {
        // Check that the token address is not 0x0
        require(token_ != address(0));
        // Set the token address
        _token = IERC20(token_);
    }

    /**
     * @dev This function is called for plain Ether transfers.
     */
    receive() external payable {}

    /**
     * @dev Fallback fucntion is executed if none of the other functions match the function
     * identifier or no data was provided with the function call
     */
    fallback() external payable {}

    /**
     * @notice Creates a new vesting schedule for a beneficiary
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _start start time of the vesting period
     * @param _duration duration in seconds of the period for the vesting in seconds
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocable whether the vesting is revocable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _cliff,
        uint256 _start,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revocable,
        uint256 _amount
    ) external onlyOwner {
        require(
            getWithdrawableAmount() >= _amount,
            "TokenVesting: Cannot create vesting schedule because not sufficient tokens"
        );
        require(_duration > 0, "TokenVesting: duration must be > 0");
        require(_amount > 0, "TokenVesting: amount must be > 0");
        require(_slicePeriodSeconds >= 1, "TokenVesting: slicePeriodSeconds must be >= 1");
        require(_duration >= _cliff, "TokenVesting: duration must be >= cliff");

        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(_beneficiary);
        uint256 cliff = _start.add(_cliff);

        vestingSchedules[vestingScheduleId] =
            VestingSchedule(_beneficiary, cliff, _start, _duration, _slicePeriodSeconds, _revocable, _amount, 0, false);

        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        vestingScheduleIds.push(vestingScheduleId);
        uint256 currentVestingCount = holdersVestingCount[_beneficiary];
        holdersVestingCount[_beneficiary] = currentVestingCount.add(1);
    }

    /**
     * @notice Revokes the vesting schedule for given identifier
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(bytes32 vestingScheduleId) external onlyOwner onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];

        require(vestingSchedule.revocable, "TokenVesting: vesting is not revocable");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);

        // If the amount is more than 0, release to the beneficiary
        if (vestedAmount > 0) {
            release(vestingScheduleId, vestedAmount);
        }
        uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(unreleased);
        vestingSchedule.revoked = true;
    }

    /**
     * @notice Withdraw the specified amount if possible
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyOwner {
        require(getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");
        _token.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice release vested amountof tokens
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the maount to release
     */
    function release(bytes32 vestingScheduleId, uint256 amount)
        public
        nonReentrant
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = _msgSender() == vestingSchedule.beneficiary;
        bool isReleasor = _msgSender() == owner();

        require(isBeneficiary || isReleasor, "TokenVesting: only beneficiary or owner can release vested tokens");

        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "TokenVesting: cannot release tokens, not enough vested tokens");

        // Add ammount to the amount released
        vestingSchedule.released = vestingSchedule.released.add(amount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);

        // Deduct from the total vested amount
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(amount);
        // Transfer Amount to the user
        _token.safeTransfer(beneficiaryPayable, amount);
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(bytes32 vestingScheduleId)
        external
        view
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
        returns (uint256)
    {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    // getters
    /**
     * @dev returns the number of vesting schedules associated to a beneficiary
     * @return the number of vesting schedules
     */
    function getVestingScheduleCountByBeneficiary(address _beneficiary) external view returns (uint256) {
        return holdersVestingCount[_beneficiary];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index)
        external
        view
        returns (VestingSchedule memory)
    {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(bytes32 vestingScheduleId) public view returns (VestingSchedule memory) {
        return vestingSchedules[vestingScheduleId];
    }

    /**
     * @dev Returns the vesting schedule id at the given index
     * @return the vesting id
     */
    function getVestingIdByIndex(uint256 _index) external view returns (bytes32) {
        require(_index < getVestingScheduleCount(), "TokenVesting: index out of bounds");
        return vestingScheduleIds[_index];
    }

    /**
     * @dev returns the number of vesting schedules managed by this contract
     * @return the number of vestign schedules
     */
    function getVestingScheduleCount() public view returns (uint256) {
        return vestingScheduleIds.length;
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return _token.balanceOf(address(this)).sub(vestingSchedulesTotalAmount);
    }

    /**
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder]);
    }

    /**
     * @dev computes the vesting schedule identifier for an address and an index
     */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    // Internals
    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        // retrive the current time
        uint256 currentTime = getCurrentTime();

        // If the current time is before the cliff, no tokens are releasable
        if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked) {
            return 0;
        }
        // If the current time is after the cliff and the vesting duration
        else if (currentTime >= vestingSchedule.cliff.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            // compute the number of ful vesting periods that have elasped
            uint256 timeFromStart = currentTime.sub(vestingSchedule.cliff);
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicedPeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicedPeriods.mul(secondsPerSlice);

            // COmpute the amount of tokens that are vested
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            // subtract the amount already released and return
            return vestedAmount.sub(vestingSchedule.released);
        }
    }

    function getCurrentTime() internal view returns (uint256) {
        return block.timestamp;
    }
}
