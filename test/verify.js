const { GetProof } = require("eth-proof");
const prover = new GetProof("http://localhost:8545");
const Rpc = require('isomorphic-rpc');
let rpc = new Rpc('http://localhost:8545');
const { Account, Header, Log, Proof, Receipt, Transaction } = require('eth-object');
var RLP = require('rlp');
const EthereumTx = require('ethereumjs-tx').Transaction;
const MPT = require('merkle-patricia-tree');
const ADC = artifacts.require("ADC");
const {mineBlocks, minerStop, minerStart, sleepMs} = require('./util.web3');
const {hex,
encodeRLP,
procTrieProof,
merkleTree,
membershipProof,
membershipProofSiblings,
eac,
eacBoundaries,
merkleCommitment,
merkleProof,
merkleSumMinMaxCommitment} = require('./util.tree');

contract("ADC", async accounts => {

  var BN = web3.utils.BN;

  const RANGE_MOD = new BN(1).shln(128);
  const BLOCK_MARKER = RANGE_MOD.subn(1);

  const DUMMY_BLOCKS = 4;
  const TX_PER_DUM_BLOCK = 32;

  var initialBlockNumber;
  var lastBlockNumber;

  before(async () => {
    console.log('Transacting');
    initialBlockNumber = (await web3.eth.getBlock("latest")).number;
    for (var i = 0; i < DUMMY_BLOCKS; i++) {
      console.log(`Block ${i}`);
      await minerStop();
      const batch = new web3.BatchRequest();
      for (var j = 0; j < TX_PER_DUM_BLOCK; j++) {
        batch.add(web3.eth.sendTransaction.request({from: accounts[0], to: accounts[1], value: 123}));
      }
      batch.execute();
      await minerStart();
      await sleepMs(250);
    }
    console.log('Done');
  });

  it('should save blocks', async () => {
    let instance = await ADC.deployed();
    // verify initialization
    res = await instance.getBlocks.call();
    var n = res.blockRanges.length;
    assert.equal(n, 1);
    // for (var i = 0; i < n; i++) {
    //   console.log(`${res.commitments[i]}: ${res.blockRanges[i].mod(RANGE_MOD)}, ${res.blockRanges[i].div(RANGE_MOD)}`)
    // }
    // verify override
    await instance.saveBlocks();
    lastBlockNumber = (await web3.eth.getBlock("latest")).number;
    res = await instance.getBlocks.call();
    n = res.blockRanges.length;
    assert.equal(n, 1);
    // for (var i = 0; i < n; i++) {
    //   console.log(`${res.commitments[i]}: ${res.blockRanges[i].mod(RANGE_MOD)}, ${res.blockRanges[i].div(RANGE_MOD)}`)
    // }
  });

  it('should...', async () => {
    let instance = await ADC.deployed();
    let blockHashes = [];
    for(var i = initialBlockNumber - 1; i < lastBlockNumber; i++) {
      const block = await web3.eth.getBlock(i);
      blockHashes.push(block.hash);
    }
    // correct block hashes derived
    assert.deepEqual(
      await instance.getBlockHashes(initialBlockNumber - 1, lastBlockNumber),
      blockHashes);
    // calculate same block merkle root
    let blockCommitments = await instance.getBlocks.call();
    let blockCommitmentCount = blockCommitments.blockRanges.length;
    assert.equal(blockCommitmentCount, 1);
    let blockHashTree = merkleCommitment(blockHashes);
    let blockHashTreeHeight = blockHashTree.length;
    assert.equal(
      // await instance.calculateBlockHashCommitment(blockHashes),
      blockCommitments.commitments[0],
      blockHashTree[blockHashTreeHeight - 1][0]);
    // verify all block inclusion proofs will pass
    for (var i = 0; i < blockHashes.length; i++) {
      let res = await instance.verifyTreeMembership(
        blockHashTree[blockHashTreeHeight - 1][0],
        blockHashes[i],
        i,
        merkleProof(blockHashTree, i));
      assert.equal(res, true);
    }
    // construct pGas argument
    let pGasLeaves = [];
    for(var blockNum = initialBlockNumber - 1; blockNum < lastBlockNumber; blockNum++) {
      let queriedBlock = await web3.eth.getBlock(blockNum);
      for(var i = 0; i < queriedBlock.transactions.length; i++) {
        let queriedTransaction = await rpc.eth_getTransactionByHash(queriedBlock.transactions[i]);
        let queriedReceipt = await rpc.eth_getTransactionReceipt(queriedTransaction.hash);
        // let receipt = Receipt.fromRpc(queriedReceipt);
        // let transaction = Transaction.fromRpc(queriedTransaction);
        // console.log(queriedTransaction);
        // console.log(transaction);
        // console.log(queriedReceipt);
        // console.log(receipt);
        // console.log(await prover.transactionProof(block.transactions[i]))
        let value = new BN(blockNum).mul(RANGE_MOD).addn(i);
        let weight = new BN(queriedReceipt.gasUsed.slice(2), 16).toNumber();
        pGasLeaves.push([value, weight]);
      }
      let value = new BN(blockNum).mul(RANGE_MOD).add(BLOCK_MARKER);
      let weight = queriedBlock.gasLimit - queriedBlock.gasUsed;
      pGasLeaves.push([value, weight]);
    }
    // console.log(pGasLeaves);
    let pGasTreeBoundary = new BN(lastBlockNumber).mul(RANGE_MOD);
    let pGasTree = merkleSumMinMaxCommitment(pGasLeaves, pGasTreeBoundary);
    let pGasTreeHeight = pGasTree.length;
    console.log([pGasTree[0].length, pGasTree.length, pGasTree[pGasTree.length - 1].length]);
    for (var i = 0; i < pGasLeaves.length; i++) {
      let proof = merkleProof(pGasTree, i);
      let res = await instance.openMSMCommitment(
        pGasTree[pGasTreeHeight - 1][0][0],
        pGasLeaves[i],
        proof,
        pGasTreeBoundary);
      // assert.equal(res, true);
      console.log(res);
    }

    // let queriedBlock = await web3.eth.getBlock(queriedBlockNumber);

    // let cGasVerified = await instance.verifyCGas();
  });
});
