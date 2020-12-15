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
    public
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
    require(targetHeight <= rangeRoots.length);
    while (true) {
      if (rangeRoots.length == targetHeight) {
        rangeRoots[maxHeight++] = targetCommitment;
        return (int64(targetHeight), maxHeight);
      } else if (rangeRoots[targetHeight] == ZERO_BYTES) {
        rangeRoots[targetHeight] = targetCommitment;
        return (int64(targetHeight), maxHeight);
      } else {
        targetCommitment = keccak256(abi.encodePacked(targetHeight, rangeRoots[targetHeight], targetCommitment));
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
    public
    pure
    returns (bool)
  {
    for (uint32 i = 0; i < siblings.length; i++) {
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
    return commitment == root;
  }


  function openMSMCommitment(
    bytes32 commitment,
    uint256 sum,
    uint256 minimum,
    uint256 maximum,
    bytes32[] memory opening
  )
    public
    returns (uint256[3] memory prefixLeafVal)
  {
    return prefixLeafVal;
  }
}
