export class ExchangeTestContext {
  public deployer: string;
  public transactionOrigin: string;
  public feeRecipient: string;
  public miner: string;
  public orderOwners: string[];
  public orderDualAuthAddrs: string[];
  public allOrderTokenRecipients: string[];
  public wallets: string[];
  public brokers: string[];

  public tokenSymbolAddrMap: Map<string, string>; // key: symbol, value: addr
  public tokenAddrSymbolMap: Map<string, string>; // key: addr, value: symbol
  public tokenAddrInstanceMap: Map<string, any>;
  public allTokens: any[];

  constructor(
    deployer: string,
    transactionOrigin: string,
    feeRecipient: string,
    miner: string,
    orderOwners: string[],
    orderDualAuthAddrs: string[],
    allOrderTokenRecipients: string[],
    wallets: string[],
    brokers: string[],
    tokenSymbolAddrMap: Map<string, string>,
    tokenAddrSymbolMap: Map<string, string>,
    tokenAddrInstanceMap: Map<string, any>,
    allTokens: any[]) {
    this.deployer = deployer;
    this.transactionOrigin = transactionOrigin;
    this.feeRecipient = feeRecipient;
    this.miner = miner;
    this.orderOwners = orderOwners;
    this.orderDualAuthAddrs = orderDualAuthAddrs;
    this.allOrderTokenRecipients = allOrderTokenRecipients;
    this.wallets = wallets;
    this.brokers = brokers;
    this.tokenSymbolAddrMap = tokenSymbolAddrMap;
    this.tokenAddrSymbolMap = tokenAddrSymbolMap;
    this.tokenAddrInstanceMap = tokenAddrInstanceMap;
    this.allTokens = allTokens;
  }
}
