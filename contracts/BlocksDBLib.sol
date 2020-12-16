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
    self.commitments.push(calculateBlockCommitment(block.number));
    self.blockRanges.push(block.number + block.number * RANGE_MOD);
  }

  function saveBlocks(
    BlocksDB storage self
  )
    public
  {
    uint256 numEntries = self.blockRanges.length;
    require(numEntries > 0, 'uninitialized');

    uint256 startingBlockNum = block.number >= MAX_BLOCKS ? block.number - MAX_BLOCKS : 0;
    uint256 lastBlockStart = self.blockRanges[numEntries - 1] % RANGE_MOD;
    uint256 lastBlockEnd = self.blockRanges[numEntries - 1] / RANGE_MOD;

    if (startingBlockNum <= lastBlockStart) {
      startingBlockNum = lastBlockStart;
      self.commitments[numEntries - 1] = calculateBlockCommitment(startingBlockNum);
      self.blockRanges[numEntries - 1] = startingBlockNum + (block.number * RANGE_MOD);
    } else {
      if (startingBlockNum <= lastBlockEnd) {
        startingBlockNum = lastBlockEnd;
      }
      self.commitments.push(calculateBlockCommitment(startingBlockNum));
      self.blockRanges.push(startingBlockNum + (block.number * RANGE_MOD));
    }
    require(self.commitments.length == self.blockRanges.length, 'BlocksDB Length mismatch.');
  }

  function getBlockHashes(
    uint256 startingBlock,
    uint256 endingBlock
  )
    internal
    view
    returns (bytes32[] memory)
  {
    bytes32[] memory blockHashes = new bytes32[](endingBlock - startingBlock);
    for (uint256 i = 0; startingBlock + i < endingBlock; i++) {
      blockHashes[i] = blockhash(startingBlock + i);
      require(blockHashes[i] != ZERO_BYTES, 'Hash out of lookup range.');
    }
    return blockHashes;
  }

  function calculateBlockHashCommitment(
    bytes32[] memory blockHashes
  )
    internal
    pure
    returns (bytes32)
  {
    int64 minHeight = -1;
    uint64 maxHeight = 0;
    bytes32[32] memory treeRoots;
    for (uint256 i = 0; i < blockHashes.length; i++) {
      (minHeight, maxHeight) = TreeLib.bubble_up(
        treeRoots,
        maxHeight,
        0,
        blockHashes[i]);
    }
    require(minHeight >= 0, 'bad minHeight');
    while (minHeight != int64(maxHeight) - 1) {
      require(minHeight < int64(maxHeight), 'wrong minheight');
      (minHeight, maxHeight) = TreeLib.bubble_up(
        treeRoots,
        maxHeight,
        uint64(minHeight),
        ZERO_BYTES);
    }
    require(maxHeight < treeRoots.length, 'wrong maxHeight');
    return treeRoots[maxHeight - 1];
  }

  function calculateBlockCommitment(
    uint256 startingBlock
  )
    public
    view
    returns (bytes32)
  {
    if (startingBlock == block.number) {
      return ZERO_BYTES;
    }
    require(startingBlock < block.number, 'bad startingBlock');
    bytes32[] memory blockHashes = getBlockHashes(startingBlock, block.number);
    return calculateBlockHashCommitment(blockHashes);
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
