pragma solidity >=0.4.21 <0.7.0;
pragma experimental ABIEncoderV2;

import "./SafeMath/SafeMathLib32.sol";
import "./SafeMath/SafeMathLib64.sol";
import "./SafeMath/SafeMathLib256.sol";

import "./RLPReader.sol";
import "./NibbleLib.sol";

library TreeLib {
  bytes32 constant ZERO_BYTES = bytes32(0);

  using SafeMathLib32 for uint32;
  using SafeMathLib64 for uint64;
  using SafeMathLib256 for uint256;

  using RLPReader for RLPReader.RLPItem;
  using RLPReader for RLPReader.Iterator;
  using RLPReader for bytes;

  using NibbleLib for NibbleLib.NibbleList;

  function readNib(
    bytes memory array,
    uint index
  )
    internal
    pure
    returns (uint8 nibble)
  {
    require(index < 2 * array.length, '0');
    if (index % 2 == 1) {
      return uint8(array[index / 2]) % 16;
    } else {
      return uint8(array[index / 2]) / 16;
    }
  }

  function readTrieValue(
    bytes32 root,
    uint256 intKey,
    bytes memory byteKey,
    bytes[] memory proof
  )
    internal
    pure
    returns (bytes memory)
  {
    require(byteKey.toRlpItem().toUint() == intKey, 'a');
    bytes32 node = keccak256(abi.encodePacked(root));
    uint k = 0;
    for (uint i = 0; i < proof.length; i++) {
      require(keccak256(abi.encodePacked(keccak256(proof[i]))) == node, 'b');
      RLPReader.RLPItem[] memory rlpList = proof[i].toRlpItem().toList();

      if (rlpList.length == 2) {
        bytes memory path = rlpList[0].toBytes();
        uint8 flags = readNib(path, 0);
        bool oddLen = flags % 2 == 1;
        if (oddLen) {
          require(readNib(byteKey, k++) == readNib(path, 1), 'c');
        }
        for (uint256 j = 2; j < 2 * path.length; j++) {
          require(readNib(byteKey, k++) == readNib(path, j), 'd');
        }

        bool terminating = flags / 2 == 1;
        if (terminating) {
          require(i == proof.length - 1, 'e');
          require(k == 2 * byteKey.length, 'f');
          return rlpList[1].toBytes();
        }

        node = keccak256(rlpList[1].toBytes());
      } else if (rlpList.length == 17) {
        if (i == proof.length - 1) {
          require(k == 2 * byteKey.length, 'g');
          return rlpList[16].toBytes();
        }

        uint8 index = readNib(byteKey, k++);
        node = keccak256(rlpList[index].toBytes());
      } else {
        require(false, 'h');
      }
    }
  }

  function bubble_up(
    bytes32[32] memory rangeRoots,
    uint64 maxHeight,
    uint64 targetHeight,
    bytes32 targetCommitment
  )
    internal
    pure
    returns (int64, uint64)
  {
    require(targetHeight < rangeRoots.length, 'bad bubble up height');
    while (true) {
      require(maxHeight <= rangeRoots.length, 'bad maxHeight');
      if (targetHeight == maxHeight) {
        rangeRoots[maxHeight++] = targetCommitment;
        return (int64(targetHeight), maxHeight);
      } else if (rangeRoots[targetHeight] == ZERO_BYTES) {
        rangeRoots[targetHeight] = targetCommitment;
        return (int64(targetHeight), maxHeight);
      } else {
        targetCommitment = keccak256(abi.encodePacked(
          targetHeight,
          rangeRoots[targetHeight],
          targetCommitment));
        rangeRoots[targetHeight] = ZERO_BYTES;
        targetHeight += 1;
      }
    }
  }

  function verifyTreeMembership(
    bytes32 root,
    bytes32 commitment,
    uint256 index,
    bytes32[] memory siblings
  )
    internal
    pure
    returns (bool)
  {
    for (uint64 i = 0; i < siblings.length; i++) {
      bool linkLeft = false;
      if (index > 0) {
        linkLeft = index.mod(2) == 1;
        index = index.div(2);
      }
      commitment = keccak256(abi.encodePacked(
        i,
        linkLeft ? siblings[i] : commitment,
        linkLeft ? commitment : siblings[i]
      ));
    }
    require(commitment == root, 'bad tree member');
    return true;
  }


  function openMSMCommitment(
    bytes32 root,
    uint256[2] memory valueWeight,
    uint256[4][] memory siblingsCommitWeightMinMax,
    uint256 boundary
  )
    internal
    pure
    returns (uint256[4] memory prefixMinMaxSum)
  {
    prefixMinMaxSum[1] = valueWeight[0];
    prefixMinMaxSum[2] = valueWeight[0];
    prefixMinMaxSum[3] = valueWeight[1];
    bytes32 commitment = keccak256(abi.encodePacked(
      valueWeight[0], // value (comm)
      valueWeight[1], // weight
      prefixMinMaxSum[1], // min = value
      prefixMinMaxSum[2])); // max = value
    for (uint32 i = 0; i < siblingsCommitWeightMinMax.length; i++) {
      // sanity check
      require(prefixMinMaxSum[1] <= prefixMinMaxSum[2], 'bad minMax');
      require(siblingsCommitWeightMinMax[i][2] <= siblingsCommitWeightMinMax[i][3], 'bad siblingsCommitWeightMinMax[i]');
      // determine pos
      bool linkLeft = siblingsCommitWeightMinMax[i][2] < prefixMinMaxSum[1];
      if (linkLeft) {
        require(siblingsCommitWeightMinMax[i][3] < prefixMinMaxSum[1], 'bad max-min border');
      } else {
        if (siblingsCommitWeightMinMax[i][2] == boundary) {
          require(bytes32(siblingsCommitWeightMinMax[i][0]) == keccak256(abi.encodePacked(boundary, uint256(0), boundary, boundary)));
          require(siblingsCommitWeightMinMax[i][1] == 0);
          require(siblingsCommitWeightMinMax[i][3] == boundary);
        } else {
          require(siblingsCommitWeightMinMax[i][2] > prefixMinMaxSum[2], 'bad min-max border');
        }
      }
      // derive parent node
      valueWeight[1] += siblingsCommitWeightMinMax[i][1];
      if (linkLeft) {
        prefixMinMaxSum[1] = siblingsCommitWeightMinMax[i][2];
      } else {
        prefixMinMaxSum[2] = siblingsCommitWeightMinMax[i][3];
      }
      commitment = keccak256(abi.encodePacked(
        i,
        linkLeft ? keccak256(abi.encodePacked(siblingsCommitWeightMinMax[i][0], commitment))
                 : keccak256(abi.encodePacked(commitment, siblingsCommitWeightMinMax[i][0])),
        valueWeight[1],
        prefixMinMaxSum[1],
        prefixMinMaxSum[2]));
      // calculate prefixSum
      if (linkLeft) {
        prefixMinMaxSum[0] += siblingsCommitWeightMinMax[i][1];
      }
      // calculate totalSum
      prefixMinMaxSum[3] += siblingsCommitWeightMinMax[i][1];
    }
    require(commitment == root, 'bad msm tree member');
    return prefixMinMaxSum;
  }
}
