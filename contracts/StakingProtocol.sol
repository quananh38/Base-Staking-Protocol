// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingProtocol is Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public stakeToken;

    mapping(address => uint256) public staked;

    event Staked(address user, uint256 amount);
    event Unstaked(address user, uint256 amount);
    event StakedFor(address payer, address beneficiary, uint256 amount);

    constructor(address _token) {
        stakeToken = IERC20(_token);
    }

    function stake(uint256 amount) external whenNotPaused {
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function stakeFor(address user, uint256 amount) external whenNotPaused {
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        staked[user] += amount;
        emit StakedFor(msg.sender, user, amount);
    }

    function unstake(uint256 amount) external {
        require(staked[msg.sender] >= amount, "too much");
        staked[msg.sender] -= amount;
        stakeToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
