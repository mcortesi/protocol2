import ABI = require("ethereumjs-abi");
import { expectThrow } from "protocol2-js";
import { Artifacts } from "../util/Artifacts";
import { FeePayments } from "./feePayments";

const {
  BurnManager,
  FeeHolder,
  TradeDelegate,
  DummyExchange,
  DummyToken,
  LRCToken,
  WETHToken,
  OrderBook,
} = new Artifacts(artifacts);

async function getEventsFromContract(contract: any, eventName: string, fromBlock: number) {
  return new Promise((resolve, reject) => {
    if (!contract[eventName]) {
      throw Error("TypeError: contract[eventName] is not a function: " + eventName);
    }

    const events = contract[eventName]({}, { fromBlock, toBlock: "latest" });
    events.watch();
    events.get((error: any, event: any) => {
      if (!error) {
        resolve(event);
      } else {
        throw Error("Failed to find filtered event: " + error);
      }
    });
    events.stopWatching();
  });
}

contract("BurnManager", (accounts: string[]) => {
  const deployer = accounts[0];
  const user1 = accounts[1];

  let tradeDelegate: any;
  let orderBook: any;
  let feeHolder: any;
  let dummyExchange: any;
  let burnManager: any;
  let tokenLRC: string;
  let tokenWETH: string;

  const authorizeAddressChecked = async (address: string, transactionOrigin: string) => {
    await tradeDelegate.authorizeAddress(address, { from: transactionOrigin });
    await assertAuthorized(address);
  };

  const assertAuthorized = async (address: string) => {
    const isAuthorizedInDelegate = await tradeDelegate.isAddressAuthorized(address);
    assert.equal(isAuthorizedInDelegate, true, "exchange not authorized.");
  };

  before(async () => {
    tokenLRC = LRCToken.address;
    tokenWETH = WETHToken.address;

    tradeDelegate = await TradeDelegate.deployed();
    orderBook = await OrderBook.deployed();
  });

  beforeEach(async () => {
    // Fresh FeeHolder for each test
    feeHolder = await FeeHolder.new(tradeDelegate.address);
    burnManager = await BurnManager.new(feeHolder.address, tokenLRC, orderBook.address, tradeDelegate.address);
    dummyExchange = await DummyExchange.new(tradeDelegate.address, feeHolder.address, "0x0");
    await authorizeAddressChecked(dummyExchange.address, deployer);
    await authorizeAddressChecked(burnManager.address, deployer);
  });

  describe("user", () => {
    it("should be able to burn LRC deposited as burned in the FeeHolder contract", async () => {
      const amount = 1e18;

      // Deposit some LRC in the fee holder contract
      const LRC = DummyToken.at(tokenLRC);
      await LRC.transfer(feeHolder.address, amount, { from: deployer });
      const feePayments = new FeePayments();
      feePayments.add(feeHolder.address, tokenLRC, amount);
      await dummyExchange.batchAddFeeBalances(feePayments.getData());

      // Burn all LRC
      const balanceFeeHolderBefore = (await LRC.balanceOf(feeHolder.address)).toNumber();
      const burnBalanceBefore = (await feeHolder.feeBalances(tokenLRC, feeHolder.address)).toNumber();
      const totalLRCSupplyBefore = await LRC.totalSupply();

      // Burn
      const success = await burnManager.burnLRC({ from: user1 });
      assert(success, "Burn needs to succeed");

      const balanceFeeHolderAfter = (await LRC.balanceOf(feeHolder.address)).toNumber();
      const burnBalanceAfter = (await feeHolder.feeBalances(tokenLRC, feeHolder.address)).toNumber();
      const totalLRCSupplyAfter = await LRC.totalSupply();
      assert.equal(balanceFeeHolderAfter, balanceFeeHolderBefore - amount, "Contract balance should be reduced.");
      assert.equal(burnBalanceAfter, burnBalanceBefore - amount, "Withdrawal amount not correctly updated.");

      assert.equal(
        totalLRCSupplyAfter,
        totalLRCSupplyBefore - amount,
        "Total LRC supply should have been decreased by all LRC burned",
      );
    });

    it("should be able to create onchain orders to sell non-LRC tokens for LRC", async () => {
      const amount = 1e18;

      // Deposit some LRC in the fee holder contract
      const WETH = DummyToken.at(tokenWETH);
      await WETH.transfer(feeHolder.address, amount, { from: deployer });
      const feePayments = new FeePayments();
      feePayments.add(feeHolder.address, tokenWETH, amount);
      await dummyExchange.batchAddFeeBalances(feePayments.getData());

      const fromBlock = web3.eth.blockNumber;
      const x = await burnManager.updateTokenOrder(tokenWETH, 500, { from: user1 });

      const events: any = await getEventsFromContract(orderBook, "OrderSubmitted", fromBlock);
      assert.equal(events.length, 1, "No order was created");
      const orderHash = events[0].args.orderHash;

      const orderData = await orderBook.getOrderData(orderHash);

      // const order = {
      //   owner: ABI.rawDecode(["address"], orderData[0]),
      //   tokenS: ABI.rawDecode(["address"], orderData[1]),
      //   tokenB: ABI.rawDecode(["address"], orderData[2]),
      //   amountS: ABI.rawDecode(["uint256"], orderData[3]),
      //   amountB: ABI.rawDecode(["uint256"], orderData[4]),
      // };
    });

    it("for non-LRC tokens the selling order is updated when price changes", async () => {
      const amount = 1e18;

      // Deposit some LRC in the fee holder contract
      const WETH = DummyToken.at(tokenWETH);
      await WETH.transfer(feeHolder.address, amount, { from: deployer });
      const feePayments = new FeePayments();
      feePayments.add(feeHolder.address, tokenWETH, amount);
      await dummyExchange.batchAddFeeBalances(feePayments.getData());

      const fromBlock = web3.eth.blockNumber;
      await burnManager.updateTokenOrder(tokenWETH, 500, { from: user1 });

      const events1: any = await getEventsFromContract(orderBook, "OrderSubmitted", fromBlock);
      assert.equal(events1.length, 1, "No order was created");
      const orderHash1 = events1[0].args.orderHash;

      // update price!!
      await burnManager.updateTokenOrder(tokenWETH, 400, { from: user1 });

      // check first order was deleted
      const order1Exists = await orderBook.orderSubmitted(orderHash1);
      assert(!order1Exists);

      // const order = {
      //   owner: ABI.rawDecode(["address"], orderData[0]),
      //   tokenS: ABI.rawDecode(["address"], orderData[1]),
      //   tokenB: ABI.rawDecode(["address"], orderData[2]),
      //   amountS: ABI.rawDecode(["uint256"], orderData[3]),
      //   amountB: ABI.rawDecode(["uint256"], orderData[4]),
      // };
    });
  });
});
