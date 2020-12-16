pragma solidity >=0.4.21 <0.7.0;
pragma experimental ABIEncoderV2;

import "./ABDKMathQuad.sol";
import "./DecodeLib.sol";
import "./TreeLib.sol";

library VerifierLib {
  uint256 constant RANGE_MOD = 2 ** 128;
  uint256 constant ALPHA_DENOM = 2 ** 20;
  int256 constant ERR_PROB_EXPON = -80;

  function minCGas(
    uint256 pGas,
    uint256 disputeGasCost,
    uint256 blocks
  )
    public
    pure
    returns (uint256)
  {
    require(disputeGasCost > 0);
    uint256 incompleteSegments = pGas / (disputeGasCost - 1);
    uint256 remainder = pGas % (disputeGasCost - 1);
    uint256 m1 = blocks * (incompleteSegments / blocks - 1);
    uint256 m2 = incompleteSegments % blocks;
    if (incompleteSegments < blocks) {
      return 0;
    } else if (remainder == 0) {
      return m1 + m2;
    } else {
      return m1 + m2 + 1;
    }
  }

  function verifyPGas(
    uint256 n,
    uint256 pGasClaimed,
    uint256 alphaClaimed,
    uint256 confidence
  )
    public
    pure
    returns (uint256)
  {
    require(alphaClaimed < ALPHA_DENOM);
    bytes16 alpha = ABDKMathQuad.div(ABDKMathQuad.fromUInt(alphaClaimed), ABDKMathQuad.fromUInt(ALPHA_DENOM));
    bytes16 alpha_n = ABDKMathQuad.fromUInt(1);
    for (uint256 i = 0; i < n; i++) {
      alpha_n = ABDKMathQuad.mul(alpha, alpha_n);
    }
    require(confidence < 100);
    bytes16 lambda = ABDKMathQuad.pow_2(ABDKMathQuad.fromInt(ERR_PROB_EXPON));
    require(ABDKMathQuad.cmp(alpha_n, lambda) < 0);
    return pGasClaimed * alphaClaimed / ALPHA_DENOM;
  }

  function verifyBlockGas(
    bytes memory blockHeader,
    uint256 unusedGas
  )
    internal
    pure
    returns (bool)
  {
    (uint256 blockGasLimit, uint256 blockGasUsage) = DecodeLib.decodeBlockGasUsed(blockHeader);
    return unusedGas == (blockGasLimit - blockGasUsage);
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
    internal
    pure
    returns (bool)
  {
    // verify transaction gas
    bytes32[2] memory roots = DecodeLib.decodeTxReceiptRoots(blockHeader);
    // read from transactionRoot
    bytes memory transaction = TreeLib.readTrieValue(
      roots[0],
      transactionNumber,
      transactionNumberKey[0],
      txInclusionProof);
      // txGasPrice <= maxGasPrice
    if (DecodeLib.decodeGasPrice(transaction) > maxGasPrice) {
      return false;
    }
    // read from receiptsRoot
    bytes memory receipt = TreeLib.readTrieValue(
      roots[1],
      transactionNumber,
      transactionNumberKey[0],
      receiptInclusionProof);
    uint256 gasUsed = DecodeLib.decodeGasUsed(receipt);
    if (transactionNumber > 0) {
      bytes memory receiptPrior = TreeLib.readTrieValue(
        roots[1],
        transactionNumber - 1,
        transactionNumberKey[1],
        priorReceiptInclusionProof);
      gasUsed = gasUsed - DecodeLib.decodeGasUsed(receiptPrior);
    }
    return gasClaimed == gasUsed;
  }

  function verifyBlockInclusion(
    //BlocksDB storage self,
    bytes32 blocksDBCommitment,
    bytes memory blockHeader,
    uint256 blockNumber,
    //uint256 commitmentNumber,
    uint256 blocksDBRangeStart,
    bytes32[] memory blockInclusionProof
  )
    internal
    pure
    returns (bool)
  {
    bytes32 blockHash = keccak256(blockHeader);
    return TreeLib.verifyTreeMembership(
      //self.commitments[commitmentNumber],
      blocksDBCommitment,
      blockHash,
      //blockNumber - (self.blockRanges[commitmentNumber] % RANGE_MOD),
      blockNumber - blocksDBRangeStart,
      blockInclusionProof);
  }

  function verifyGasPosition(
    bytes32 pGasCommitment,
    uint256 pGasClaimed,
    uint256 nonce,
    uint256 prefixSum,
    uint256 leafSum
  )
    internal
    pure
    returns (bool)
  {
    uint256 g = uint256(keccak256(abi.encodePacked(pGasCommitment, nonce))) % pGasClaimed;
    return prefixSum < g && g <= prefixSum + leafSum && prefixSum + leafSum <= pGasClaimed;
  }

  function verifyGasCommitmentOpening(
    bytes32 pGasCommitment,
    uint256[2] memory valueWeight,
    uint256[4][] memory siblingsCommitWeightMinMax,
    uint256 minBlock,
    uint256 maxBlock,
    uint256 totalValue
  )
    internal
    pure
    returns (uint256)
  {
    uint256 boundary = (maxBlock) * RANGE_MOD;
    uint256[4] memory prefixMinMaxSum = TreeLib.openMSMCommitment(
      pGasCommitment,
      valueWeight,
      siblingsCommitWeightMinMax,
      boundary);
    require(minBlock <= prefixMinMaxSum[1], 'minBlock <= prefixMinMax[1]');
    require(prefixMinMaxSum[2] <= boundary, 'prefixMinMax[2] <= maxBlock');
    require(prefixMinMaxSum[3] == totalValue, 'prefixMinMaxSum[3] == totalValue');
    return prefixMinMaxSum[0];
  }

  function verifyCGas(
    //BlocksDB storage self,
    uint256[8] memory subStack,
    // uint256 maxGasPrice,
    // uint256 disputeGasCost,
    // uint256 startingBlockNum,
    // uint256 endingBlockNum,
    // uint256 pGasClaimed,
    // uint256 alphaClaimed,
    // uint256 confidence,
    // bytes32 pGasCommitment,
    // uint256 boundary,
    uint256[2][] memory msmValueWeights,
    uint256[4][][] memory msmOpenings,
    bytes[] memory blockHeaders,
    // uint256[2][] memory blockInclusionCommitmentStart,
    // bytes32[][] memory blockInclusionProofs,
    bytes[][] memory txInclusionProofs,
    bytes[2][] memory txNumKeys
  )
    public
    pure
    returns (uint256)
  {
    for (uint256 i = 0; i < msmOpenings.length; i++) {
      uint256 prefixSum = verifyGasCommitmentOpening(
        bytes32(subStack[7]),
        msmValueWeights[i],
        msmOpenings[i],
        subStack[2], // startingBlockNum
        subStack[3], // endingBlockNum
        subStack[4]); // pGasClaimed
      require(verifyGasPosition(
        bytes32(subStack[7]),
        subStack[4], // pGasClaimed
        i, // nonce
        prefixSum, // prefixSum
        msmValueWeights[i][1] // leafSum
      ), 'g out of range');
      uint256 txNum = msmValueWeights[i][0] % RANGE_MOD; // value % RANGE_MOD = txNum
      if (txNum == RANGE_MOD - 1) {
        require(verifyBlockGas(
          blockHeaders[i],
          msmValueWeights[i][1] // leafSum
        ), 'bad unused block gas');
      } else {
        require(verifyTransactionGas(
          blockHeaders[i],
          txNum,
          txNumKeys[i],
          subStack[0], // maxGasPrice
          msmValueWeights[i][1], // leafSum
          txInclusionProofs[3*i], // tx inclusion proof
          txInclusionProofs[3*i+1], // receipt inclusion proof
          txInclusionProofs[3*i+2])); // prior receipt inclusion proof
      }
    }
    uint256 pGasVerified = verifyPGas(
      msmOpenings.length,
      subStack[4], // pGasClaimed
      subStack[6], // confidence
      subStack[5]); // alphaClaimed
    return minCGas(
      pGasVerified,
      subStack[1], // disputeGasCost
      subStack[3] - subStack[2]); // endingBlockNum - startingBlockNum
  }
}
