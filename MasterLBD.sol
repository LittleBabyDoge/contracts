pragma solidity 0.6.12;

/*
 * Little Baby Dodge
 */

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./LBDPuppy.sol";

contract MasterLPD is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of LBDs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLBDPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLBDPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. LBDs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that LBDs distribution occurs.
        uint256 accLBDPerShare; // Accumulated LBDs per share, times DECIMALS. See below.
        uint256 totalStaked;    // total staked tokens
    }

    // The LBD TOKEN!
    IBEP20 public token;
    // The LBD TOKEN!
    LBDPuppy public puppy;
    // Dev address.
    address public devaddr;
    // LBD tokens created per block.
    uint256 public lbdPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when LBD mining starts.
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public DECIMALS = 1e12;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        BEP20 _token,
        LBDPuppy _puppy,
        address _devaddr,
        uint256 _lbdPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public {
        token = _token;
        puppy = _puppy;
        devaddr = _devaddr;
        lbdPerBlock = _lbdPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _token,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accLBDPerShare: 0,
            totalStaked: 0
        }));

        totalAllocPoint = 1000;

    }

    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "validatePool: pool exists?");
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Detects whether the given pool already exists
    function checkPoolDuplicate(IBEP20 _lpToken) public view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        checkPoolDuplicate(_lpToken);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLBDPerShare: 0,
            totalStaked: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's LBD allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }    
    
    function setRewardPerBlock(uint256 _lbdPerBlock) external onlyOwner {
        lbdPerBlock = _lbdPerBlock;
    }

    function setEndBlock(uint256 _endBlock) external onlyOwner {
        require(_endBlock > endBlock, 'require _endBlock > endBlock');
        endBlock = _endBlock;
    }

    function stopReward() external onlyOwner {
        endBlock = block.number;
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= endBlock) {
            return _to.sub(_from);
        } else if (_from >= endBlock) {
            return 0;
        } else {
            return endBlock.sub(_from);
        }
    }

    // View function to see pending LBDs on frontend.
    function pendingCake(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLBDPerShare = pool.accLBDPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(lbdPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accLBDPerShare = accLBDPerShare.add(cakeReward.mul(DECIMALS).div(lpSupply));
        }
        return user.amount.mul(accLBDPerShare).div(DECIMALS).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(lbdPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accLBDPerShare = pool.accLBDPerShare.add(tokenReward.mul(DECIMALS).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Master LBD for LBD allocation.
    function deposit(uint256 _pid, uint256 _amount) public validatePool(_pid) {

        require (_pid != 0, 'deposit LBD by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLBDPerShare).div(DECIMALS).sub(user.rewardDebt);
            if(pending > 0) {
                safeLBDTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);

        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Master LBD.
    function withdraw(uint256 _pid, uint256 _amount) public validatePool(_pid) {
        require (_pid != 0, 'withdraw LBD by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accLBDPerShare).div(DECIMALS).sub(user.rewardDebt);
        if(pending > 0) {
            safeLBDTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake LBD tokens to Master LBD
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        uint256 finalDepositAmount = 0;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLBDPerShare).div(DECIMALS).sub(user.rewardDebt);
            if(pending > 0) {
                safeLBDTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            uint256 preStakeBalance = totalLBDTokenBalance();
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            finalDepositAmount = totalLBDTokenBalance().sub(preStakeBalance);
            user.amount = user.amount.add(finalDepositAmount);
            pool.totalStaked = pool.totalStaked.add(finalDepositAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);

        puppy.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw LBD tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accLBDPerShare).div(DECIMALS).sub(user.rewardDebt);
        if(pending > 0) {
            safeLBDTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        pool.totalStaked = pool.totalStaked.sub(_amount);

        puppy.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        puppy.burn(msg.sender, user.amount);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /// @dev Obtain the stake token fees (if any) earned by reflect token
    function getLBDTokenFeeBalance() public view returns (uint256) {
        return totalLBDTokenBalance().sub(poolInfo[0].totalStaked);
    }

    function totalLBDTokenBalance() public view returns (uint256) {
        // Return BEO20 balance
        return token.balanceOf(address(this));
    }

    function getPoolInfo(uint256 _pid) public view
    returns(address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accLBDPerShare) {
        return (address(poolInfo[_pid].lpToken),
            poolInfo[_pid].allocPoint,
            poolInfo[_pid].lastRewardBlock,
            poolInfo[_pid].accLBDPerShare);
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough LBDs.
    function safeLBDTransfer(address _to, uint256 _amount) internal {
        puppy.safeLBDTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
