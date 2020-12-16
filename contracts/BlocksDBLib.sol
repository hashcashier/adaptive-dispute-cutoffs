pragma solidity >=0.4.21 <0.7.0;
pragma experimental ABIEncoderV2;

import "./TreeLib.sol";

library BlocksDBLib {
  uint256 constant RANGE_MOD = 2 ** 128;
  bytes32 constant ZERO_BYTES = bytes32(0);
  uint256 constant MAX_BLOCKS = 256;

  struct BlocksDB {
    bytes32[] commitments;
    uint256[] blockRanges;
  }

  function init(
    BlocksDB storage self
  )
    public
  {
    uint256 numEntries = self.commitments.length;
    require(numEntries == 0);
    self.commitments.push(ZERO_BYTES);
    self.blockRanges.push(block.number + block.number * RANGE_MOD);
  }

  function saveBlocks(
    BlocksDB storage self
  )
    public
  {
    uint256 numEntries = self.blockRanges.length;
    require(numEntries > 0);

    uint256 startingBlockNum = block.number >= MAX_BLOCKS ? block.number - MAX_BLOCKS : 0;
    uint256 lastBlockStart = self.blockRanges[numEntries - 1] % RANGE_MOD;
    uint256 lastBlockEnd = self.blockRanges[numEntries - 1] / RANGE_MOD;

    if (startingBlockNum <= lastBlockStart) {
      startingBlockNum = lastBlockStart;
      self.commitments[numEntries - 1] = calculateBlockCommitment(startingBlockNum);
    } else {
      if (startingBlockNum <= lastBlockEnd) {
        startingBlockNum = lastBlockEnd;
      }
      self.commitments.push(calculateBlockCommitment(startingBlockNum));
      self.blockRanges.push(uint256(startingBlockNum) + (block.number * RANGE_MOD));
    }
    require(self.commitments.length == self.blockRanges.length, 'BlocksDB Length mismatch.');
  }

  function calculateBlockCommitment(
    uint256 startingBlock
  )
    public
    view
    returns (bytes32)
  {
    int64 minHeight = -1;
    uint64 maxHeight = 0;
    bytes32[32] memory treeRoots;
    for (uint256 blockNum = startingBlock; blockNum < block.number; blockNum++) {
      bytes32 blockHash = blockhash(blockNum);
      require(blockHash != ZERO_BYTES, 'Hash out of lookup range.');
      (minHeight, maxHeight) = TreeLib.bubble_up(treeRoots, maxHeight, 0, blockHash);
    }
    while (minHeight != int64(treeRoots.length) -1) {
      (minHeight, maxHeight) = TreeLib.bubble_up(treeRoots, maxHeight, uint64(minHeight), ZERO_BYTES);
    }
    return treeRoots[treeRoots.length - 1];
  }

  function verifyBlockInclusion(
    BlocksDB storage self,
    // bytes32 blocksDBCommitment,
    bytes memory blockHeader,
    uint256 blockNumber,
    uint256 commitmentNumber,
    // uint256 blocksDBRangeStart,
    bytes32[] memory blockInclusionProof
  )
    internal
    view
    returns (bool)
  {
    bytes32 blockHash = keccak256(blockHeader);
    return TreeLib.verifyTreeMembership(
      self.commitments[commitmentNumber],
      // blocksDBCommitment,
      blockHash,
      blockNumber - (self.blockRanges[commitmentNumber] % RANGE_MOD),
      // blockNumber - blocksDBRangeStart,
      blockInclusionProof);
  }
}
