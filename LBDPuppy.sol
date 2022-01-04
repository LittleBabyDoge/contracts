pragma solidity 0.6.12;

/*
 * Little Baby Dodge
 */

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

contract LBDPuppy is Ownable {
    using SafeBEP20 for BEP20;

    BEP20 public immutable token;


    constructor(
        BEP20 _token
    ) public {
        token = _token;
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough LBDs.
    function safeLBDTransfer(address _to, uint256 _amount) external onlyOwner {
        uint256 lbdBal = token.balanceOf(address(this));
        if (_amount > lbdBal) {
            if (lbdBal > 0)
                // 0 transfers not supported by LBD contract
                token.safeTransfer(_to, lbdBal);
        } else {
            if (_amount > 0)
                // 0 transfers not supported by LBD contract
                token.safeTransfer(_to, _amount);
        }
    }

    function deposit (uint256 _amount) external {
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }
}