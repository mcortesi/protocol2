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


/// @title IOrderBook
/// @author Daniel Wang - <daniel@loopring.org>.
/// @author Kongliang Zhong - <kongliang@loopring.org>.
contract IOrderBook {
    mapping(bytes32 => bool) public orderSubmitted;

    mapping(bytes32 => bytes32[]) public orders;

    struct OrderData {
        /// contains all fields that used for order hash calculation.
        /// @see OrderHelper.updateHash() for detailed information.
        bytes32[] dataArray;
    }

    event OrderSubmitted(address owner, bytes32 orderHash);

    /// @dev   Submits an order to the on-chain order book.
    ///        No signature is needed. The order can only be sumbitted by its
    ///        owner of its broker (the owner can be the address of a contract).
    /// @param dataArray The data of the order.
    ///        see OrderData
    function submitOrder(
        bytes32[] dataArray
        )
        external
        returns (bytes32);

    function removeOrder(bytes32 orderHash) external;

    /// @dev   Returns the order data of an order submitted in the order book.
    /// @param orderHash The hash of the order to return the data for.
    /// @return The order data
    ///         see OrderData
    function getOrderData(bytes32 orderHash)
        view
        external
        returns (bytes32[]);
}
