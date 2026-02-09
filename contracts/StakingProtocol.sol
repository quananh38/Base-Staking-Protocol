// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 Base staking:
  - lock duration
  - early withdraw penalty (sent to treasury)
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken;
    address public treasury;

    uint256 public penaltyBps = 500; // 5%
    uint256 public lockDuration = 7 days;

    struct Position {
        uint256 amount;
        uint256 start;
    }

    mapping(address => Position) public pos;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 penalty);
    event ParamsUpdated(uint256 lockDuration, uint256 penaltyBps, address treasury);

    constructor(address _stakeToken, address _treasury) Ownable(msg.sender) {
        require(_stakeToken != address(0) && _treasury != address(0), "zero");
        stakeToken = IERC20(_stakeToken);
        treasury = _treasury;
    }

    function setParams(uint256 _lockDuration, uint256 _penaltyBps, address _treasury) external onlyOwner {
        require(_penaltyBps <= 2000, "too high");
        require(_treasury != address(0), "treasury=0");
        lockDuration = _lockDuration;
        penaltyBps = _penaltyBps;
        treasury = _treasury;
        emit ParamsUpdated(_lockDuration, _penaltyBps, _treasury);
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        Position storage p = pos[msg.sender];
        if (p.amount == 0) p.start = block.timestamp;

        p.amount += amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        Position storage p = pos[msg.sender];
        require(amount > 0 && p.amount >= amount, "bad amount");

        p.amount -= amount;

        uint256 penalty;
        if (block.timestamp < p.start + lockDuration) {
            penalty = (amount * penaltyBps) / 10000;
            if (penalty > 0) stakeToken.safeTransfer(treasury, penalty);
        }

        stakeToken.safeTransfer(msg.sender, amount - penalty);

        if (p.amount == 0) p.start = 0;

        emit Unstaked(msg.sender, amount, penalty);
    }
}
