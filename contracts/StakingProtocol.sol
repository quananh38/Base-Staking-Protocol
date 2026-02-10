// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingProtocol is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken;

    mapping(address => uint256) public staked;

    event Staked(address indexed user, uint256 amount);

    constructor(address _stakeToken) Ownable(msg.sender) {
        require(_stakeToken != address(0), "zero");
        stakeToken = IERC20(_stakeToken);
    }

    function stake(uint256 amount) public nonReentrant {
        require(amount > 0, "amount=0");
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function stakeWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC20Permit(address(stakeToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        stake(amount);
    }
}
