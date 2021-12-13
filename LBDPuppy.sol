pragma solidity 0.6.12;

/*
 * Little Baby Dodge
 */

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

contract LBDPuppy is BEP20('LBD PUPPY', 'LBD-P') {
    using SafeBEP20 for BEP20;

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from ,uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }

    BEP20 public token;


    constructor(
        BEP20 _token
    ) public {
        token = _token;
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough LBDs.
    function safeLBDTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 lbdBal = token.balanceOf(address(this));
        if (_amount > lbdBal) {
            token.transfer(_to, lbdBal);
        } else {
            token.transfer(_to, _amount);
        }
    }

    function deposit (uint256 _amount) public {
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }
}