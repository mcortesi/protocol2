/*

  Copyright 2017 Loopring Project Ltd (Loopring Foundation).

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

pragma solidity 0.4.24;
pragma experimental "v0.5.0";
pragma experimental "ABIEncoderV2";

import "../iface/Errors.sol";
import "../iface/IFeeHolder.sol";
import "../iface/IOrderbook.sol";
import "../lib/BurnableERC20.sol";
import "../lib/ERC20.sol";
import "../lib/MathUint.sol";
import "../lib/NoDefaultFunc.sol";

/// @author Brecht Devos - <brecht@loopring.org>
contract BurnManager is NoDefaultFunc, Errors {
    using MathUint for uint;



    address public feeHolderAddress = 0x0;
    address public lrcAddress = 0x0;
    address public orderbookAddress = 0x0;
    address public tradeDelegate = 0x0;

    mapping(address => bytes32) currentOrders;

    constructor(
        address _feeHolderAddress,
        address _lrcAddress,
        address _orderbookAddress,
        address _tradeDelegate
        )
        public
    {
        require(_feeHolderAddress != 0x0, ZERO_ADDRESS);
        require(_lrcAddress != 0x0, ZERO_ADDRESS);
        require(_orderbookAddress != 0x0, ZERO_ADDRESS);
        require(_tradeDelegate != 0x0, ZERO_ADDRESS);
        feeHolderAddress = _feeHolderAddress;
        lrcAddress = _lrcAddress;
        orderbookAddress = _orderbookAddress;
        tradeDelegate = _tradeDelegate;
    }

    function updateTokenOrder(address token, uint price) external {
        require(token != lrcAddress, INVALID_VALUE);

        IFeeHolder feeHolder = IFeeHolder(feeHolderAddress);

        // Withdraw the complete token balance
        uint balance = feeHolder.feeBalances(token, feeHolderAddress);
        bool success = feeHolder.withdrawBurned(token, balance);
        require(success, WITHDRAWAL_FAILURE);

        IOrderBook orderbook = IOrderBook(orderbookAddress);

        // we have an order, cancel it and create a new one
        if (currentOrders[token] != bytes32(0)) {
            orderbook.removeOrder(currentOrders[token]);
            balance = ERC20(token).balanceOf(address(this));
        }

        // approve tradeDelegate to trade on our behalf
        require(ERC20(token).approve(tradeDelegate, balance));

        // create order
        bytes32[] memory order = new bytes32[](18);
        order[0] = bytes32(address(this)); // owner
        order[1] = bytes32(token); // tokenS
        order[2] = bytes32(lrcAddress); // tokenB
        order[3] = bytes32(balance); // amountS
        order[4] = bytes32(price * balance); // amountB
        // order[5] = bytes32(0); // validSince
        // order[6] = bytes32(0); // broker
        // order[7] = bytes32(0); // orderInterceptor
        // order[8] = bytes32(0); // wallet
        // order[9] = bytes32(0); // validUtil
        order[10] = bytes32(lrcAddress); // feeToken
        // order[11] = bytes32(0); // feeAmount
        // order[12] = bytes32(0); // feePercentage
        // order[13] = bytes32(0); // tokenSFeePercentage
        // order[14] = bytes32(0); // tokenBFeePercentage
        // order[15] = bytes32(0); // tokenRecipient
        // order[16] = bytes32(0); // walletSplitPercentage

        bytes32 orderHash = orderbook.submitOrder(order);
        currentOrders[token] = orderHash;
    }

    function burnLRC()
        external
        returns (bool)
    {
        IFeeHolder feeHolder = IFeeHolder(feeHolderAddress);

        // Withdraw the complete token balance
        uint balance = feeHolder.feeBalances(lrcAddress, feeHolderAddress);
        bool success = feeHolder.withdrawBurned(lrcAddress, balance);
        require(success, WITHDRAWAL_FAILURE);


        // Burn the LRC
        BurnableERC20 LRC = BurnableERC20(lrcAddress);

        // Add extra LRC from order fills
        balance = LRC.balanceOf(address(this));

        success = LRC.burn(balance);
        require(success, BURN_FAILURE);



        return true;
    }


}
