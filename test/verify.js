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

  const DUMMY_BLOCKS = 12;
  const TX_PER_DUM_BLOCK = 32;

  const CHALLENGES = 24;

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
    let saveTx = await instance.saveBlocks.sendTransaction();
    lastBlockNumber = (await web3.eth.getBlock("latest")).number;
    res = await instance.getBlocks.call();
    n = res.blockRanges.length;
    assert.equal(n, 1);
    console.log(`saveBlocks ${saveTx.receipt.gasUsed}`)
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
    // for (var i = 0; i < blockHashes.length; i++) {
    //   let res = await instance.verifyTreeMembership(
    //     blockHashTree[blockHashTreeHeight - 1][0],
    //     blockHashes[i],
    //     i,
    //     merkleProof(blockHashTree, i));
    //   assert.equal(res, true);
    // }
    // construct pGas argument
    let pGasLeaves = [];
    for(var blockNum = initialBlockNumber - 1; blockNum < lastBlockNumber; blockNum++) {
      let queriedBlock = await web3.eth.getBlock(blockNum);
      let referenceBlockData = await rpc.eth_getBlockByNumber(blockNum, false);
      let referenceBlockHeader = Header.fromRpc(referenceBlockData).toHex();

      let prevKey = '0x', prevReceiptProof = [];

      if (queriedBlock.transactions.length == 1) {
        continue;
      }

      for(var i = 0; i < queriedBlock.transactions.length; i++) {
        let queriedTransaction = await rpc.eth_getTransactionByHash(queriedBlock.transactions[i]);
        let queriedReceipt = await rpc.eth_getTransactionReceipt(queriedTransaction.hash);
        let value = new BN(blockNum).mul(RANGE_MOD).addn(i);
        let weight = new BN(queriedReceipt.gasUsed.slice(2), 16).toNumber();
        pGasLeaves.push([value, weight]);

        continue;

        let transaction = Transaction.fromRpc(queriedTransaction);
        let transactionProof = await prover.transactionProof(queriedBlock.transactions[i]);
        let receipt = Receipt.fromRpc(queriedReceipt);
        let receiptProof = await prover.receiptProof(queriedBlock.transactions[i]);

        let transactionKey = encodeRLP(transactionProof.txIndex);

        // assert.equal(
        //   await instance.verifyTransactionGas(
        //     referenceBlockHeader,
        //     i,
        //     [transactionKey, prevKey],
        //     queriedTransaction.gasPrice,
        //     queriedReceipt.gasUsed,
        //     procTrieProof(transactionProof.txProof),
        //     procTrieProof(receiptProof.receiptProof),
        //     prevReceiptProof),
        //   true);
        prevKey = transactionKey;
        prevReceiptProof = procTrieProof(receiptProof.receiptProof);
      }
      let value = new BN(blockNum).mul(RANGE_MOD).add(BLOCK_MARKER);
      let weight = queriedBlock.gasLimit - queriedBlock.gasUsed;
      // pGasLeaves.push([value, weight]);

      // assert.equal(
      //   await instance.verifyBlockGas(referenceBlockHeader, weight),
      //   true);
    }
    // console.log(pGasLeaves);
    let pGasTreeBoundary = new BN(lastBlockNumber).mul(RANGE_MOD);
    let pGasTree = merkleSumMinMaxCommitment(pGasLeaves, pGasTreeBoundary);
    let pGasTreeHeight = pGasTree.length;
    let pGasCommitment = pGasTree[pGasTreeHeight - 1][0][0];
    let pGasClaimed = pGasTree[pGasTreeHeight - 1][0][1];

    // let tempPrefixSum = 0;
    // for (var i = 0; i < pGasLeaves.length; i++) {
    //   let proof = merkleProof(pGasTree, i);
    //   let prefixSum = await instance.verifyGasCommitmentOpening(
    //     pGasCommitment,
    //     pGasLeaves[i],
    //     proof,
    //     initialBlockNumber - 1,
    //     lastBlockNumber,
    //     pGasClaimed);
    //   assert.equal(prefixSum, tempPrefixSum);
    //   tempPrefixSum += pGasLeaves[i][1];
    // }

    let pGasChallenges = [];
    let pGasResponses = [];
    let alphasClaimed = [];
    for(var i = 0; i < CHALLENGES; i++) {
      // uint256 g = uint256(keccak256(abi.encodePacked(pGasCommitment, nonce))) % pGasClaimed;
      let hashValue = web3.utils.soliditySha3(
        {type: 'bytes32', value: pGasCommitment},
        {type: 'uint256', value: i},
      )
      let g = new BN(hashValue.slice(2), 16).modn(pGasClaimed);
      // assert.equal(
      //   await instance.calculateChallenge(pGasCommitment, pGasClaimed, i),
      //   g);
      pGasChallenges.push(g);
      let prefixSum = 0;
      let leafSum = 0;
      for(var j = 0; j < pGasLeaves.length; j++) {
        if (prefixSum + pGasLeaves[j][1] >= g) {
          pGasResponses.push(j);
          leafSum = pGasLeaves[j][1];
          break;
        }
        prefixSum += pGasLeaves[j][1];
      }
      // assert.equal(
      //   await instance.verifyGasPosition(pGasCommitment, pGasClaimed, i, prefixSum, leafSum),
      //   true);

      let l = 0, r = 2 ** 20, v = 0;
      while (l < r) {
        let m = (l+r)>>1;
        let alpha = (1.0 * m) / (2.0 ** 20);
        if ((alpha ** i) < (2.0 **-80)) {
          v = m;
          l = m+1;
        } else {
          r = m-1;
        }
      }
      alphasClaimed.push(v);
    }
    console.log(alphasClaimed);

    let msmValueWeights = [];
    let msmOpenings = [];
    let blockHeaders = [];
    let blocksDBCommitmentNumbers = [];
    let blockInclusionProofs = [];
    let txInclusionProofs = [];
    let txNumKeys = [];
    for (var i = 0; i < CHALLENGES; i++) {
      let j = pGasResponses[i];
      msmValueWeights.push(pGasLeaves[j]);
      let pGasProof = merkleProof(pGasTree, j);
      msmOpenings.push(pGasProof);

      let blockNum = pGasLeaves[j][0].div(RANGE_MOD).toNumber();
      let referenceBlockData = await rpc.eth_getBlockByNumber(blockNum, false);
      let referenceBlockHeader = Header.fromRpc(referenceBlockData).toHex();
      blockHeaders.push(referenceBlockHeader);

      blocksDBCommitmentNumbers.push(0);
      let blockIndex = blockNum - (initialBlockNumber - 1);
      blockInclusionProofs.push(merkleProof(blockHashTree, blockIndex));

      let txNum = pGasLeaves[j][0].mod(RANGE_MOD);

      if (txNum.eq(BLOCK_MARKER)) {
        // console.log(`${pGasChallenges[i]} BLOCK_MARKER`)
        txInclusionProofs.push([]);
        txInclusionProofs.push([]);
        txInclusionProofs.push([]);
        txNumKeys.push([[], []]);
      } else {
        txNum = txNum.toNumber();
        // console.log(`${pGasChallenges[i]} ${txNum}`)
        let queriedBlock = await web3.eth.getBlock(blockNum);
        let transactionProof = await prover.transactionProof(queriedBlock.transactions[txNum]);
        let receiptProof = await prover.receiptProof(queriedBlock.transactions[txNum]);

        let transactionKey = encodeRLP(transactionProof.txIndex);
        txInclusionProofs.push(procTrieProof(transactionProof.txProof));
        txInclusionProofs.push(procTrieProof(receiptProof.receiptProof));

        if (txNum == 0) {
          txInclusionProofs.push([]);
          txNumKeys.push([transactionKey, []])
        } else {
          let prevReceiptProof = await prover.receiptProof(queriedBlock.transactions[txNum-1]);

          txInclusionProofs.push(procTrieProof(prevReceiptProof.receiptProof));
          txNumKeys.push([transactionKey, encodeRLP(prevReceiptProof.txIndex)])
        }

      }

      let prefixSum = await instance.verifyGasCommitmentOpening(
        pGasCommitment,
        pGasLeaves[j],
        pGasProof,
        initialBlockNumber - 1,
        lastBlockNumber,
        pGasClaimed);
      // console.log(`${prefixSum} ${parseInt(prefixSum) + pGasLeaves[j][1]} ${pGasChallenges[i]} ${pGasClaimed}`)

      let subStack = [
        30000000000,
        50000,
        initialBlockNumber - 1,
        lastBlockNumber,
        pGasClaimed,
        alphasClaimed[i],
        pGasCommitment
      ];
      // console.log(alphasClaimed[i]);
      // console.log([
      //   subStack,
      //   msmValueWeights,
      //   msmOpenings,
      //   blockHeaders,
      //   blocksDBCommitmentNumbers,
      //   blockInclusionProofs,
      //   txInclusionProofs,
      //   txNumKeys]);

      let verifyCGas = await instance.verifyCGas.sendTransaction(
        subStack,
        msmValueWeights,
        msmOpenings,
        blockHeaders,
        blocksDBCommitmentNumbers,
        blockInclusionProofs,
        txInclusionProofs,
        txNumKeys);
      console.log(`${alphasClaimed[i]}: ${verifyCGas.receipt.gasUsed},`);
    }

    // let queriedBlock = await web3.eth.getBlock(queriedBlockNumber);

    // let cGasVerified = await instance.verifyCGas();
  });
});
