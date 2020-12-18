pragma solidity >=0.4.21 <0.7.0;
pragma experimental ABIEncoderV2;

import "./VerifierLib.sol";
import "./BlocksDBLib.sol";

contract ADC {
  uint256 constant RANGE_MOD = 2 ** 128;

  using BlocksDBLib for BlocksDBLib.BlocksDB;

  BlocksDBLib.BlocksDB internal blocksDB;

  constructor()
    public
  {
    blocksDB.init();
  }

  function saveBlocks()
    public
  {
    blocksDB.saveBlocks();
  }

  function getBlocks()
    public
    view
    returns (bytes32[] memory commitments, uint256[] memory blockRanges)
  {
    return (blocksDB.commitments, blocksDB.blockRanges);
  }

  function getBlockHashes(
    uint256 startingBlock,
    uint256 endingBlock
  )
    public
    view
    returns (bytes32[] memory)
  {
    return BlocksDBLib.getBlockHashes(startingBlock, endingBlock);
  }

  function calculateBlockHashCommitment(
    bytes32[] memory blockHashes
  )
    public
    pure
    returns (bytes32)
  {
    return BlocksDBLib.calculateBlockHashCommitment(blockHashes);
  }

  function verifyTreeMembership(
    bytes32 root,
    bytes32 commitment,
    uint256 index,
    bytes32[] memory siblings
  )
    public
    pure
    returns (bool)
  {
    return TreeLib.verifyTreeMembership(root, commitment, index, siblings);
  }

  function openMSMCommitment(
    bytes32 root,
    uint256[2] memory valueWeight,
    uint256[4][] memory siblingsCommitWeightMinMax,
    uint256 boundary
  )
    public
    pure
    returns (uint256[4] memory prefixMinMaxSum)
  {
    return TreeLib.openMSMCommitment(root, valueWeight, siblingsCommitWeightMinMax, boundary);
  }

  function verifyGasCommitmentOpening(
    bytes32 pGasCommitment,
    uint256[2] memory valueWeight,
    uint256[4][] memory siblingsCommitWeightMinMax,
    uint256 minBlock,
    uint256 maxBlock,
    uint256 totalValue
  )
    public
    pure
    returns (uint256)
  {
    return VerifierLib.verifyGasCommitmentOpening(pGasCommitment, valueWeight, siblingsCommitWeightMinMax, minBlock, maxBlock, totalValue);
  }

  function verifyGasPosition(
    bytes32 pGasCommitment,
    uint256 pGasClaimed,
    uint256 nonce,
    uint256 prefixSum,
    uint256 leafSum
  )
    public
    pure
    returns (bool)
  {
    return VerifierLib.verifyGasPosition(pGasCommitment, pGasClaimed, nonce, prefixSum, leafSum);
  }

  function verifyBlockGas(
    bytes memory blockHeader,
    uint256 unusedGas
  )
    public
    pure
    returns (bool)
  {
    return VerifierLib.verifyBlockGas(blockHeader, unusedGas);
  }

  function verifyPGas(
    uint256 n,
    uint256 pGasClaimed,
    uint256 alphaClaimed
  )
    public
    pure
    returns (uint256)
  {
    return VerifierLib.verifyPGas(n, pGasClaimed, alphaClaimed);
  }

  function minCGas(
    uint256 pGas,
    uint256 disputeGasCost,
    uint256 blocks
  )
    public
    pure
    returns (uint256)
  {
    return VerifierLib.minCGas(pGas, disputeGasCost, blocks);
  }

  function verifyTransactionGas(
    bytes memory blockHeader,
    uint256 transactionNumber,
    bytes[2] memory transactionNumberKey,
    uint256 maxGasPrice,
    uint256 gasClaimed,
    bytes[] memory txInclusionProof,
    bytes[] memory receiptInclusionProof,
    bytes[] memory priorReceiptInclusionProof
  )
    public
    pure
    returns (bool)
  {
    return VerifierLib.verifyTransactionGas(blockHeader, transactionNumber, transactionNumberKey, maxGasPrice, gasClaimed, txInclusionProof, receiptInclusionProof, priorReceiptInclusionProof);
  }

  function calculateChallenge(
    bytes32 pGasCommitment,
    uint256 pGasClaimed,
    uint256 nonce
  )
    public
    pure
    returns (uint256)
  {
    return VerifierLib.calculateChallenge(pGasCommitment, pGasClaimed, nonce);
  }

  // function getCommitmentData(
  //   uint256[] memory blocksDBCommitmentNumbers
  // )
  //   internal
  //   view
  //   returns (uint256[2][] memory blockInclusionCommitmentStart)
  // {
  //   blockInclusionCommitmentStart = new uint256[2][](blocksDBCommitmentNumbers.length);
  //   for (uint256 i = 0; i < blocksDBCommitmentNumbers.length; i++) {
  //     uint256 commitmentNumber = blocksDBCommitmentNumbers[i];
  //     blockInclusionCommitmentStart[i][0] = uint256(blocksDB.commitments[commitmentNumber]);
  //     blockInclusionCommitmentStart[i][1] = blocksDB.blockRanges[commitmentNumber] % RANGE_MOD;
  //   }
  // }

  function verifyCGas(
    uint256[7] memory subStack,
    // uint256 maxGasPrice,
    // uint256 disputeGasCost,
    // uint256 startingBlockNum,
    // uint256 endingBlockNum,
    // uint256 pGasClaimed,
    // uint256 alphaClaimed,
    // bytes32 pGasCommitment,
    uint256[2][] memory msmValueWeights,
    uint256[4][][] memory msmOpenings,
    bytes[] memory blockHeaders,
    uint256[] memory blocksDBCommitmentNumbers,
    bytes32[][] memory blockInclusionProofs,
    bytes[][] memory txInclusionProofs,
    bytes[2][] memory txNumKeys
  )
    public
    view
    returns (uint256)
  {
    // uniform lengths
    uint256 n = msmValueWeights.length;
    require(msmOpenings.length == n, 'bad msmOpenings len');
    require(blockHeaders.length == n, 'bad blockHeaders len');
    require(blocksDBCommitmentNumbers.length == n, 'bad blocksDBCommitmentNumbers len');
    require(blockInclusionProofs.length == n, 'bad blockInclusionProofs len');
    require(txInclusionProofs.length == 3*n, 'bad txInclusionProofs len');
    require(txNumKeys.length == n, 'bad txNumKeys len');
    // known blocks
    for (uint i = 0; i < n; i++) {
      require(blocksDB.verifyBlockInclusion(
        blockHeaders[i],
        msmValueWeights[i][0] / RANGE_MOD, // value / RANGE_MOD = blockNumber
        blocksDBCommitmentNumbers[i],
        blockInclusionProofs[i]), 'bad block inclusion proof');
    }
    return VerifierLib.verifyCGas(
      subStack,
      msmValueWeights,
      msmOpenings,
      blockHeaders,
      txInclusionProofs,
      txNumKeys);
  }
}
