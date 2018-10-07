import axios from "axios";
import * as fs from "fs";
import * as path from "path";
// @ts-ignore
import Web3 = require("web3");
import { Artifacts } from "../util/Artifacts";

interface PriceQuote {
  symbol: string;
  price: number;
}

interface TokenInfo {
  protocol: string;
  symbol: string;
  source: string;
  deny: boolean;
  decimals: number;
  isMarket: boolean;
}

const POLL_TIME = 12 * 60 * 60 * 1000; // every 12 hours
const CONTRACTS_PATH = path.join(__dirname, "../build/contracts");

const web3Provider = new Web3.providers.HttpProvider("http://localhost:7545");
const web3: any = new Web3(web3Provider);

function loadContract(name: string) {
  const buildFile = JSON.parse(fs.readFileSync(path.join(CONTRACTS_PATH, `${name}.json`)).toString());
  const Contract = new web3.eth.contract(buildFile.abi);
  return Contract;
}

async function getSupportedTokens(): Promise<TokenInfo[]> {
  const res = await axios.post("http://relay1.loopr.io/rpc/v2", {
    method: "loopring_getSupportedTokens",
    params: [{}],
    id: "903bd8bd8a2214ff",
    jsonrpc: "2.0",
  });
  return res.data.result;
}

async function getPriceQuote(currency: string): Promise<PriceQuote[]> {
  const res = await axios.post("http://relay1.loopr.io/rpc/v2", {
    method: "loopring_getPriceQuote",
    params: [{ currency }],
    id: "903bd8bd8a2214d8",
    jsonrpc: "2.0",
  });
  return res.data.result.tokens;
}

async function getTokenPricesInLRC() {
  const usdPrices = await getPriceQuote("USD");
  // const tokens = await getSupportedTokens();
  // console.log(tokens);

  const LRCPrice = usdPrices.find((t) => t.symbol === "LRC").price;
  const tokenPrices = usdPrices.filter((t) => t.symbol !== "LRC").map((t) => ({
    symbol: t.symbol,
    // address: tokens.find((token) => token.symbol === t.symbol).protocol,
    price: LRCPrice / t.price,
  }));
  return tokenPrices;
}

// async function updatePrices() {
//   const prices = await getTokenPricesInLRC();
//   const ERC20 = loadContract("ERC20");
//   for (const tp of prices) {
//     const erc20 = ERC20.at(tp.address);
//   }
// }

async function main() {
  const tokenPrices = await getTokenPricesInLRC();

  console.log(JSON.stringify(tokenPrices, null, 2));
}

main().catch((err) => {
  console.error(err);
});
