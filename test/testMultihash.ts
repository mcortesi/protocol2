import ABI = require("ethereumjs-abi");
import { Bitstream, expectThrow, MultiHashUtil, SignAlgorithm } from "protocol2-js";

const MultihashUtilProxy = artifacts.require("MultihashUtilProxy");

contract("Multihash", (accounts: string[]) => {

  const emptyAddr = "0x0000000000000000000000000000000000000000";

  const signer1 = accounts[1];
  const signer2 = accounts[2];
  const hash1 = "0x" + "A1".repeat(32);
  const hash2 = "0x" + "B2".repeat(32);

  const util = new MultiHashUtil();

  let multihash: any;

  before(async () => {
    multihash = await MultihashUtilProxy.new();
  });

  describe("General", () => {

    it("should not be able to verify unknown signature types", async () => {
      const sig = new Bitstream();
      sig.addNumber(111, 1);
      sig.addNumber(48, 1);
      sig.addNumber(123, 24);
      sig.addNumber(456, 24);
      // Should not throw
      const success = await multihash.verifySignature(signer1, hash1, sig.getData());
      assert(!success, "Signature should not be valid");
    });

    it("should not be able to verify invalid multihash data", async () => {
      const sig = new Bitstream();
      sig.addNumber(1, 1);
      await expectThrow(multihash.verifySignature(signer1, hash1, sig.getData()));
    });

    it("should not be able to verify multihash data with incorrect length", async () => {
      const sig = new Bitstream();
      sig.addNumber(111, 1);
      sig.addNumber(24 + 2, 1);
      sig.addNumber(123, 24);
      await expectThrow(multihash.verifySignature(signer1, hash1, sig.getData()));
    });

  });

  describe("Standard Ethereum signing", () => {

    it("should be able to verify signed data", async () => {
      const multiHashData = await util.signAsync(SignAlgorithm.Ethereum, new Buffer(hash1.slice(2), "hex"), signer1);
      const success = await multihash.verifySignature(signer1, hash1, multiHashData);
      assert(success, "Signature should be valid");
    });

    it("should not be able to verify wrongly signed data", async () => {
      {
        // Different hash
        const multiHashData = await util.signAsync(SignAlgorithm.Ethereum, new Buffer(hash2.slice(2), "hex"), signer1);
        const success = await multihash.verifySignature(signer1, hash1, multiHashData);
        assert(!success, "Signature should not be valid");
      }
      {
        // Different signer
        const multiHashData = await util.signAsync(SignAlgorithm.Ethereum, new Buffer(hash1.slice(2), "hex"), signer1);
        const success = await multihash.verifySignature(signer2, hash1, multiHashData);
        assert(!success, "Signature should not be valid");
      }
    });

    it("should not be able to verify signed data for invalid addresses", async () => {
      const multiHashData = await util.signAsync(SignAlgorithm.Ethereum, new Buffer(hash1.slice(2), "hex"), signer1);
      await expectThrow(multihash.verifySignature(emptyAddr, hash1, multiHashData));
    });

    it("should not be able to verify signed data with incorrect signature data length", async () => {
      let multiHashData = await util.signAsync(SignAlgorithm.Ethereum, new Buffer(hash1.slice(2), "hex"), signer1);
      const prefix = new Bitstream();
      prefix.addNumber(SignAlgorithm.Ethereum, 1);
      prefix.addNumber(65 + 1, 1);
      multiHashData = prefix.getData() + multiHashData.slice(2 + 4);
      await expectThrow(multihash.verifySignature(signer1, hash1, multiHashData));
    });

  });

});
