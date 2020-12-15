pragma solidity >=0.4.21 <0.7.0;
pragma experimental ABIEncoderV2;

import "./RLPReader.sol";

library DecodeLib {
  using RLPReader for RLPReader.RLPItem;
  using RLPReader for RLPReader.Iterator;
  using RLPReader for bytes;

  function decodeTxReceiptRoots(
    bytes memory blockHeader
  )
    public
    pure
    returns(bytes32[2] memory)
  {
    RLPReader.RLPItem[] memory rlpList = blockHeader.toRlpItem().toList();
    // (bytes32 parentsHash, bytes32 ommersHash, address beneficiary, bytes32 stateRoot, bytes32 transactionsRoot, bytes32 receiptsRoot) = abi.decode(blockHeader, (bytes32, bytes32, address, bytes32, bytes32, bytes32));
    // return (transactionsRoot, receiptsRoot);
    return [bytes32(rlpList[4].toUint()), bytes32(rlpList[5].toUint())];
  }

  function decodeBlockGasUsed(
    bytes memory blockHeader
  )
    public
    pure
    returns(uint256 limit, uint256 used)
  {
    RLPReader.RLPItem[] memory rlpList = blockHeader.toRlpItem().toList();
    // (bytes32 parentsHash, bytes32 ommersHash, address beneficiary, bytes32 stateRoot, bytes32 transactionsRoot, bytes32 receiptsRoot) = abi.decode(blockHeader, (bytes32, bytes32, address, bytes32, bytes32, bytes32));
    // return (transactionsRoot, receiptsRoot);
    return (rlpList[9].toUint(), rlpList[10].toUint());
  }

  function decodeGasPrice(
    bytes memory transaction
  )
    internal
    pure
    returns(uint256)
  {
    RLPReader.RLPItem[] memory rlpList = transaction.toRlpItem().toList();
    // (uint256 nonce, uint256 gasPrice) = abi.decode(transaction, (uint256, uint256));
    return rlpList[1].toUint();
  }

  function decodeGasUsed(
    bytes memory receipt
  )
    internal
    pure
    returns(uint256)
  {
    RLPReader.RLPItem[] memory rlpList = receipt.toRlpItem().toList();
    // (bytes32 pts, uint256 gasUsed) = abi.decode(receipt, (bytes32, uint256));
    return rlpList[1].toUint();
  }

}
