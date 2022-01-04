pragma solidity 0.6.12;

/*
 * Little Baby Dodge
 */

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
import '@pancakeswap/pancake-swap-lib/contracts/utils/ReentrancyGuard.sol';

import "./LBDPuppy.sol";

contract MasterLBD is Ownable, ReentrancyGuard {
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
        uint256 feeBase;
    }

    // The LBD TOKEN!
    IBEP20 public immutable token;
    // The LBD TOKEN!
    LBDPuppy public immutable puppy;
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
    mapping(IBEP20 => bool) public poolExistence;
    // The block number when LBD mining starts.
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public constant DECIMALS = 1e18;
    uint256 public constant FEE_DECIMALS = 1e4;
    uint256 public MAX_EMISSION_RATE = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Add(address indexed pool, uint256 allocPoint);
    event Set(uint256 indexed pid, uint256 allocPoint);
    event SetRewardPB(uint256 rewardPB);
    event SetEndBlock(uint256 endBlock);
    event StopReward(uint256 stopBLock);
    event UpdateDev(address devAddr);
    event EmergencyRewardWithdraw(address sender, uint256 reward);
    event SkimStakeTokenFees(address indexed user, uint256 amount);

    constructor(
        BEP20 _token,
        LBDPuppy _puppy,
        address _devaddr,
        uint256 _lbdPerBlock,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _max_emission_rate
    ) public {
        token = _token;
        puppy = _puppy;
        devaddr = _devaddr;
        lbdPerBlock = _lbdPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        MAX_EMISSION_RATE = _max_emission_rate;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _token,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accLBDPerShare: 0,
            totalStaked: 0,
            feeBase: 0
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


    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicate pool");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint256 _feeBase, bool _withUpdate) external onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }
        require (_feeBase <= 1000, "Fee base: Fee base too high");
        // BEP20 interface check
        _lpToken.balanceOf(address(this));
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLBDPerShare: 0,
            totalStaked: 0,
            feeBase: _feeBase
        }));
        poolExistence[_lpToken] = true;
        updateStakingPool();
        emit Add(address(_lpToken), _allocPoint);
    }

    // Update the given pool's LBD allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _feeBase, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        require (_feeBase <= 1000, "Fee base: Fee base too high");
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].feeBase = _feeBase;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
        emit Set(_pid, _allocPoint);
    }    
    
    function setRewardPerBlock(uint256 _lbdPerBlock) external onlyOwner {
        require(_lbdPerBlock <= MAX_EMISSION_RATE, "Too high");
        lbdPerBlock = _lbdPerBlock;
        emit SetRewardPB(lbdPerBlock);
    }

    function setEndBlock(uint256 _endBlock) external onlyOwner {
        require(_endBlock > endBlock, 'require _endBlock > endBlock');
        endBlock = _endBlock;
        emit SetEndBlock(endBlock);
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
        uint256 lpSupply = pool.totalStaked;
        if (block.number > pool.lastRewardBlock && lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(lbdPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            uint256 devFee = cakeReward.mul(3).div(100);
            accLBDPerShare = accLBDPerShare.add(cakeReward.sub(devFee).mul(DECIMALS).div(lpSupply));
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
        uint256 lpSupply = pool.totalStaked;
        if (lpSupply == 0 || totalAllocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(lbdPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        // 1% dev fee
        uint256 devFee = tokenReward.mul(3).div(100);
        safeLBDTransfer(devaddr, devFee);
        // compute new share deducted by dev fee (3%)
        pool.accLBDPerShare = pool.accLBDPerShare.add(tokenReward.sub(devFee).mul(DECIMALS).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Master LBD for LBD allocation.
    function deposit(uint256 _pid, uint256 _amount) external validatePool(_pid) nonReentrant {

        require (_pid != 0, 'deposit LBD by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 finalDepositAmount = 0;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLBDPerShare).div(DECIMALS).sub(user.rewardDebt);
            if(pending > 0) {
                safeLBDTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 preStakeBalance = totalTokenBalance(_pid);
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            finalDepositAmount = totalTokenBalance(_pid).sub(preStakeBalance);
            user.amount = user.amount.add(finalDepositAmount);
            pool.totalStaked = pool.totalStaked.add(finalDepositAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Master LBD.
    function withdraw(uint256 _pid, uint256 _amount) external validatePool(_pid) nonReentrant {
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
            uint256 penaltyFee = _amount.mul(pool.feeBase).div(FEE_DECIMALS);
            if (penaltyFee > 0)
                pool.lpToken.safeTransfer(devaddr, penaltyFee);
            pool.lpToken.safeTransfer(msg.sender, _amount.sub(penaltyFee));
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        pool.totalStaked = pool.totalStaked.sub(_amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake LBD tokens to Master LBD
    function enterStaking(uint256 _amount) external nonReentrant {
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
            uint256 preStakeBalance = totalTokenBalance(0);
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            finalDepositAmount = totalTokenBalance(0).sub(preStakeBalance);
            user.amount = user.amount.add(finalDepositAmount);
            pool.totalStaked = pool.totalStaked.add(finalDepositAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw LBD tokens from STAKING.
    function leaveStaking(uint256 _amount) external nonReentrant {
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
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLBDPerShare).div(DECIMALS);
        pool.totalStaked = pool.totalStaked.sub(_amount);

        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        // updates total staked balance
        pool.totalStaked = pool.totalStaked.sub(_amount);
        uint256 penaltyFee = 0;
        if (_pid != 0) {
            // staking pool can never have an unstaking fee
            penaltyFee = _amount.mul(pool.feeBase).div(FEE_DECIMALS);
            if (penaltyFee > 0)
                pool.lpToken.safeTransfer(devaddr, penaltyFee);
        }
        // sends token to message sender
        pool.lpToken.safeTransfer(msg.sender, _amount.sub(penaltyFee));
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    /// @dev Obtain the stake token fees (if any) earned by reflect token
    function getTokenFeeBalance(uint256 _pid) public view returns (uint256) {
        return totalTokenBalance(_pid).sub(poolInfo[_pid].totalStaked);
    }

    function totalTokenBalance(uint256 _pid) public view returns (uint256) {
        // Return BEO20 balance
        return poolInfo[_pid].lpToken.balanceOf(address(this));
    }

        /// @dev Remove excess stake tokens earned by reflect fees
    function skimStakeTokenFees(uint256 _pid) external onlyOwner {
        uint256 stakeTokenFeeBalance = getTokenFeeBalance(_pid);
        poolInfo[_pid].lpToken.safeTransfer(msg.sender, stakeTokenFeeBalance);
        emit SkimStakeTokenFees(msg.sender, stakeTokenFeeBalance);
    }

    function getPoolInfo(uint256 _pid) external view
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
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit UpdateDev(devaddr);
    }

    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= token.balanceOf(address(puppy)), "not enough rewards");
        require(endBlock.add(28800 * 30) < block.number, "withdraw not allowed");
        // Withdraw rewards
        safeLBDTransfer(msg.sender, _amount);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }
}
