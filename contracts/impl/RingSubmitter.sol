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
import "../iface/IBrokerRegistry.sol";
import "../iface/IRingSubmitter.sol";
import "../iface/IFeeHolder.sol";
import "../iface/IOrderRegistry.sol";
import "../iface/ITradeDelegate.sol";
import "../iface/IOrderBook.sol";
import "../iface/IBurnRateTable.sol";

import "../lib/BytesUtil.sol";
import "../lib/MathUint.sol";
import "../lib/NoDefaultFunc.sol";

import "../spec/EncodeSpec.sol";
import "../spec/MiningSpec.sol";
import "../spec/OrderSpecs.sol";
import "../spec/RingSpecs.sol";

import "../helper/InputsHelper.sol";
import "../helper/MiningHelper.sol";
import "../helper/OrderHelper.sol";
import "../helper/RingHelper.sol";

import "./Data.sol";
import "./ExchangeDeserializer.sol";


/// @title An Implementation of IRingSubmitter.
/// @author Daniel Wang - <daniel@loopring.org>,
/// @author Kongliang Zhong - <kongliang@loopring.org>
/// @author Brechtpd - <brecht@loopring.org>
/// Recognized contributing developers from the community:
///     https://github.com/rainydio
///     https://github.com/BenjaminPrice
///     https://github.com/jonasshen
///     https://github.com/Hephyrius
contract RingSubmitter is IRingSubmitter, NoDefaultFunc, Errors {
    using MathUint      for uint;
    using BytesUtil     for bytes;
    using MiningSpec    for uint16;
    using EncodeSpec    for uint16[];
    using OrderSpecs    for uint16[];
    using RingSpecs     for uint8[][];
    using OrderHelper     for Data.Order;
    using RingHelper      for Data.Ring;
    using InputsHelper    for Data.Inputs;
    using MiningHelper    for Data.Mining;

    address public  lrcTokenAddress             = 0x0;
    address public  wethTokenAddress            = 0x0;
    address public  delegateAddress             = 0x0;
    address public  orderBrokerRegistryAddress  = 0x0;
    address public  orderRegistryAddress        = 0x0;
    address public  feeHolderAddress            = 0x0;
    address public  orderBookAddress            = 0x0;
    address public  burnRateTableAddress        = 0x0;

    uint64  public  ringIndex                   = 0;

    uint    public constant MAX_RING_SIZE       = 8;

    struct SubmitRingsParam {
        uint16[]    encodeSpecs;
        uint16      miningSpec;
        uint16[]    orderSpecs;
        uint8[][]   ringSpecs;
        address[]   addressList;
        uint[]      uintList;
        bytes[]     bytesList;
    }

    constructor(
        address _lrcTokenAddress,
        address _wethTokenAddress,
        address _delegateAddress,
        address _orderBrokerRegistryAddress,
        address _orderRegistryAddress,
        address _feeHolderAddress,
        address _orderBookAddress,
        address _burnRateTableAddress
        )
        public
    {
        require(_lrcTokenAddress != 0x0, ZERO_ADDRESS);
        require(_wethTokenAddress != 0x0, ZERO_ADDRESS);
        require(_delegateAddress != 0x0, ZERO_ADDRESS);
        require(_orderBrokerRegistryAddress != 0x0, ZERO_ADDRESS);
        require(_orderRegistryAddress != 0x0, ZERO_ADDRESS);
        require(_feeHolderAddress != 0x0, ZERO_ADDRESS);
        require(_orderBookAddress != 0x0, ZERO_ADDRESS);
        require(_burnRateTableAddress != 0x0, ZERO_ADDRESS);

        lrcTokenAddress = _lrcTokenAddress;
        wethTokenAddress = _wethTokenAddress;
        delegateAddress = _delegateAddress;
        orderBrokerRegistryAddress = _orderBrokerRegistryAddress;
        orderRegistryAddress = _orderRegistryAddress;
        feeHolderAddress = _feeHolderAddress;
        orderBookAddress = _orderBookAddress;
        burnRateTableAddress = _burnRateTableAddress;
    }

    function submitRings(
        bytes data
        )
        external
    {
        uint i;
        bytes32[] memory tokenBurnRates;
        Data.Context memory ctx = Data.Context(
            lrcTokenAddress,
            ITradeDelegate(delegateAddress),
            IBrokerRegistry(orderBrokerRegistryAddress),
            IOrderRegistry(orderRegistryAddress),
            IFeeHolder(feeHolderAddress),
            IOrderBook(orderBookAddress),
            IBurnRateTable(burnRateTableAddress),
            ringIndex,
            FEE_PERCENTAGE_BASE,
            tokenBurnRates,
            0,
            0,
            0,
            0
        );

        // Check if the highest bit of ringIndex is '1'
        require((ctx.ringIndex >> 63) == 0, REENTRY);

        // Set the highest bit of ringIndex to '1' (IN STORAGE!)
        ringIndex = ctx.ringIndex | (1 << 63);

        (
            Data.Mining  memory mining,
            Data.Order[] memory orders,
            Data.Ring[]  memory rings
        ) = ExchangeDeserializer.deserialize(lrcTokenAddress, data);

        // Allocate memory that is used to batch things for all rings
        setupLists(ctx, orders, rings);

        for (i = 0; i < orders.length; i++) {
            orders[i].validateInfo(ctx);
            orders[i].checkP2P();
            orders[i].updateHash();
            orders[i].updateBrokerAndInterceptor(ctx);
        }
        batchGetFilledAndCheckCancelled(ctx, orders);
        updateBrokerSpendables(orders);
        for (i = 0; i < orders.length; i++) {
            orders[i].checkBrokerSignature(ctx);
        }

        for (i = 0; i < rings.length; i++) {
            rings[i].updateHash();
        }

        mining.updateHash(rings);
        mining.updateMinerAndInterceptor();
        require(mining.checkMinerSignature(), INVALID_SIG);

        for (i = 0; i < orders.length; i++) {
            // We don't need to verify the dual author signature again if it uses the same
            // dual author address as the previous order (the miner can optimize the order of the orders
            // so this happens as much as possible). We don't need to check if the signature is the same
            // because the same mining hash is signed for all orders.
            if(i > 0 && orders[i].dualAuthAddr == orders[i - 1].dualAuthAddr) {
                continue;
            }
            orders[i].checkDualAuthSignature(mining.hash);
        }

        for (i = 0; i < rings.length; i++) {
            Data.Ring memory ring = rings[i];
            ring.checkOrdersValid();
            ring.checkForSubRings();
            ring.calculateFillAmountAndFee(ctx);
            if (ring.valid) {
                ring.adjustOrderStates();
            }
        }

        bool reevaluateRings = false;
        for (i = 0; i < orders.length; i++) {
            bool validBefore = orders[i].valid;
            orders[i].validateAllOrNone();
            reevaluateRings = reevaluateRings || (validBefore != orders[i].valid);
        }

        for (i = 0; i < rings.length; i++) {
            Data.Ring memory ring = rings[i];
            bool validBefore = ring.valid;
            if (reevaluateRings) {
                ring.checkOrdersValid();
            }
            if (ring.valid) {
                // Only settle rings we have checked to be valid
                ring.doPayments(ctx, mining);
                IRingSubmitter.Fill[] memory fills = ring.generateFills();
                emit RingMined(
                    ctx.ringIndex++,
                    ring.hash,
                    mining.feeRecipient,
                    fills
                );
            } else {
                // If the ring was valid before the completely filled check we have to revert the filled amountS
                // of the orders in the ring. This is a bit awkward so maybe there's a better solution.
                if (validBefore) {
                    ring.revertOrderStats();
                }
                emit InvalidRing(ring.hash);
            }
        }

        // Do all token transfers for all rings
        batchTransferTokens(ctx);
        // Do all fee payments for all rings
        batchPayFees(ctx);
        // Update all order stats
        updateOrdersStats(ctx, orders);

        ringIndex = ctx.ringIndex;
    }

    function updateBrokerSpendables(
        Data.Order[] orders
        )
        internal
        pure
    {
        // Spendables for brokers need to be setup just right for the allowances to work, we cannot trust
        // the miner to do this for us. Spendables for tokens don't need to be correct, if they are incorrect
        // the transaction will fail, so the miner will want to send those correctly.
        uint data;
        uint ptr;
        assembly {
            data := mload(0x40)
            ptr := data
        }
        for (uint i = 0; i < orders.length; i++) {
            if (orders[i].brokerInterceptor != 0) {
                uint brokerSpendableS;
                (ptr, brokerSpendableS) = addBrokerSpendable(
                    data,
                    ptr,
                    orders[i].broker,
                    orders[i].owner,
                    orders[i].tokenS
                );
                uint brokerSpendableFee;
                (ptr, brokerSpendableFee) = addBrokerSpendable(
                    data,
                    ptr,
                    orders[i].broker,
                    orders[i].owner,
                    orders[i].feeToken
                );
                // Store the spendables in the order
                assembly {
                    let order := mload(add(orders, mul(add(1, i), 32)))             // orders[i]
                    mstore(add(order, 320), brokerSpendableS)                       // order.brokerSpendableS
                    mstore(add(order, 352), brokerSpendableFee)                     // order.brokerSpendableFee
                }
            }
        }
        assembly {
            mstore(0x40, ptr)
        }
    }

    function addBrokerSpendable(
        uint data,
        uint ptr,
        address broker,
        address owner,
        address token
        )
        internal
        pure
        returns (uint newPtr, uint spendable)
    {
        assembly {
            // Try to find the spendable for the same (broker, owner, token) set
            let addNew := 1
            for { let p := data } and(lt(p, ptr), eq(addNew, 1)) { p := add(p, 192) } {
                let dataBroker := mload(add(p,  0))
                let dataOwner := mload(add(p, 32))
                let dataToken := mload(add(p, 64))
                // if(broker == dataBroker && owner == dataOwner && token == dataToken)
                if and(and(eq(broker, dataBroker), eq(owner, dataOwner)), eq(token, dataToken)) {
                    spendable := add(p, 96)
                    addNew := 0
                }
            }
            if eq(addNew, 1) {
                mstore(add(ptr,  0), broker)
                mstore(add(ptr, 32), owner)
                mstore(add(ptr, 64), token)
                // Initialize spendable
                mstore(add(ptr, 96), 0)
                mstore(add(ptr, 128), 0)
                mstore(add(ptr, 160), 0)

                spendable := add(ptr, 96)
                ptr := add(ptr, 192)
            }
            newPtr := ptr
        }
    }

    function setupLists(
        Data.Context ctx,
        Data.Order[] orders,
        Data.Ring[] rings
        )
        internal
        pure
    {
        setupTokenBurnRateList(ctx, orders);
        setupFeePaymentList(ctx, rings);
        setupTokenTransferList(ctx, rings);
    }

    function setupTokenBurnRateList(
        Data.Context ctx,
        Data.Order[] orders
        )
        internal
        pure
    {
        // Allocate enough memory to store burn rates for all tokens even
        // if every token is unique (max 2 unique tokens / order)
        uint maxNumTokenBurnRates = orders.length * 2;
        bytes32[] memory tokenBurnRates;
        assembly {
            tokenBurnRates := mload(0x40)
            mstore(tokenBurnRates, 0)                               // Length
            mstore(0x40, add(
                tokenBurnRates,
                add(32, mul(maxNumTokenBurnRates, 64))
            ))
        }
        ctx.tokenBurnRates = tokenBurnRates;
    }

    function setupFeePaymentList(
        Data.Context ctx,
        Data.Ring[] rings
        )
        internal
        pure
    {
        uint totalMaxSizeFeePayments = 0;
        for (uint i = 0; i < rings.length; i++) {
            // Up to (ringSize + 3) * 3 payments per order (because of fee sharing by miner)
            uint ringSize = rings[i].size;
            uint maxSize = (ringSize + 3) * 3 * ringSize * 3;
            totalMaxSizeFeePayments += maxSize;
        }
        bytes4 batchAddFeeBalancesSelector = ctx.feeHolder.batchAddFeeBalances.selector;
        uint ptr;
        assembly {
            let data := mload(0x40)
            mstore(data, batchAddFeeBalancesSelector)
            mstore(add(data, 4), 32)
            ptr := add(data, 68)
            mstore(0x40, add(ptr, mul(totalMaxSizeFeePayments, 32)))
        }
        ctx.feeData = ptr;
        ctx.feePtr = ptr;
    }

    function setupTokenTransferList(
        Data.Context ctx,
        Data.Ring[] rings
        )
        internal
        pure
    {
        uint totalMaxSizeTransfers = 0;
        for (uint i = 0; i < rings.length; i++) {
            // Up to 3 transfers per order
            uint maxSize = 3 * rings[i].size * 4;
            totalMaxSizeTransfers += maxSize;
        }
        bytes4 batchTransferSelector = ctx.delegate.batchTransfer.selector;
        uint ptr;
        assembly {
            let data := mload(0x40)
            mstore(data, batchTransferSelector)
            mstore(add(data, 4), 32)
            ptr := add(data, 68)
            mstore(0x40, add(ptr, mul(totalMaxSizeTransfers, 32)))
        }
        ctx.transferData = ptr;
        ctx.transferPtr = ptr;
    }

    function updateOrdersStats(
        Data.Context ctx,
        Data.Order[] orders
        )
        internal
    {
        bytes4 batchUpdateFilledSelector = ctx.delegate.batchUpdateFilled.selector;
        address tradeDelegateAddress = address(ctx.delegate);
        assembly {
            let data := mload(0x40)
            mstore(data, batchUpdateFilledSelector)
            mstore(add(data, 4), 32)
            let ptr := add(data, 68)
            let size := 0
            for { let i := 0 } lt(i, mload(orders)) { i := add(i, 1) } {
                let order := mload(add(orders, mul(add(i, 1), 32)))
                // if (order.valid)
                if gt(mload(add(order, 960)), 0) {                          // order.valid
                    mstore(add(ptr,   0), mload(add(order, 864)))           // order.hash
                    mstore(add(ptr,  32), mload(add(order, 928)))           // order.filledAmountS

                    ptr := add(ptr, 64)
                    size := add(size, 2)
                }
            }
            mstore(add(data, 36), size)             // length

            let success := call(
                gas,                                // forward all gas
                tradeDelegateAddress,               // external address
                0,                                  // wei
                data,                               // input start
                sub(ptr, data),                     // input length
                data,                               // output start
                32                                  // output length
            )
            if eq(success, 0) {
                revert(0, 0)
            }
        }
    }

    function batchGetFilledAndCheckCancelled(
        Data.Context ctx,
        Data.Order[] orders
        )
        internal
    {
        bytes4 batchGetFilledAndCheckCancelledSelector = ctx.delegate.batchGetFilledAndCheckCancelled.selector;
        address tradeDelegateAddress = address(ctx.delegate);
        assembly {
            let data := mload(0x40)
            mstore(data, batchGetFilledAndCheckCancelledSelector)
            mstore(add(data,  4), 32)
            mstore(add(data, 36), mul(mload(orders), 5))                // orders.length
            let ptr := add(data, 68)
            for { let i := 0 } lt(i, mload(orders)) { i := add(i, 1) } {
                let order := mload(add(orders, mul(add(i, 1), 32)))     // orders[i]
                mstore(add(ptr,   0), mload(add(order, 288)))           // order.broker
                mstore(add(ptr,  32), mload(add(order,   0)))           // order.owner
                mstore(add(ptr,  64), mload(add(order, 864)))           // order.hash
                mstore(add(ptr,  96), mload(add(order, 160)))           // order.validSince
                // bytes20(order.tokenS) ^ bytes20(order.tokenB)        // tradingPair
                mstore(add(ptr, 128), mul(
                    xor(
                        mload(add(order, 32)),                 // order.tokenS
                        mload(add(order, 64))                  // order.tokenB
                    ),
                    0x1000000000000000000000000)               // shift left 12 bytes (bytes20 is padded on the right)
                )
                ptr := add(ptr, 160)                                    // 5 * 32
            }
            // Return data is stored just like the call data without the signature:
            // 0x00: Offset to data
            // 0x20: Array length
            // 0x40: Array data
            let returnDataSize := mul(add(2, mload(orders)), 32)
            let success := call(
                gas,                                // forward all gas
                tradeDelegateAddress,               // external address
                0,                                  // wei
                data,                               // input start
                sub(ptr, data),                     // input length
                data,                               // output start
                returnDataSize                      // output length
            )
            // Check if the call was successful and the return data is the expected size
            if or(eq(success, 0), sub(1, eq(returndatasize(), returnDataSize)))  {
                revert(0, 0)
            }
            for { let i := 0 } lt(i, mload(orders)) { i := add(i, 1) } {
                let order := mload(add(orders, mul(add(i, 1), 32)))     // orders[i]
                let fill := mload(add(data,  mul(add(i, 2), 32)))       // fills[i]
                mstore(add(order, 928), fill)                           // order.filledAmountS
                // order.valid = order.valid && (order.filledAmountS != ~uint(0))
                mstore(add(order, 960),                                 // order.valid
                    and(
                        gt(mload(add(order, 960)), 0),                  // order.valid
                        sub(1, eq(fill, not(0)))                        // fill != ~uint(0
                    )
                )
            }
        }
    }

    function batchTransferTokens(
        Data.Context ctx
        )
        internal
    {
        address _tradeDelegateAddress = address(ctx.delegate);
        uint data = ctx.transferData - 68;
        uint ptr = ctx.transferPtr;
        assembly {
            mstore(add(data, 36), div(sub(ptr, add(data, 68)), 32))             // length

            let success := call(
                gas,                                // forward all gas
                _tradeDelegateAddress,              // external address
                0,                                  // wei
                data,                               // input start
                sub(ptr, data),                     // input length
                data,                               // output start
                32                                  // output length
            )
            if eq(success, 0) {
                revert(0, 0)
            }
        }
    }

    function batchPayFees(
        Data.Context ctx
        )
        internal
    {
        address _feeHolderAddress = address(ctx.feeHolder);
        uint data = ctx.feeData - 68;
        uint ptr = ctx.feePtr;
        assembly {
            mstore(add(data, 36), div(sub(ptr, add(data, 68)), 32))             // length

            let success := call(
                gas,                                // forward all gas
                _feeHolderAddress,                  // external address
                0,                                  // wei
                data,                               // input start
                sub(ptr, data),                     // input length
                data,                               // output start
                32                                  // output length
            )
            if eq(success, 0) {
                revert(0, 0)
            }
        }
    }

}
