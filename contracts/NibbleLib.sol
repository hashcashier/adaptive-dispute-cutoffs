pragma solidity >=0.4.21 <0.7.0;

library NibbleLib {
  enum Direction {
    LeftToRight, RightToLeft
  }
  struct NibbleList {
    uint8[] nibbles;
    uint32 len;
  }

  function push(
    NibbleList memory self,
    uint8 nibble
  )
    internal
    pure
  {
    require(nibble < 2 ** 4);
    self.nibbles[self.len++] = nibble;
  }

  function push(
    NibbleList memory self,
    byte nibble
  )
    internal
    pure
  {
    push(self, uint8(nibble));
  }

  function pushDouble(
    NibbleList memory self,
    uint8 double,
    Direction direction
  )
    internal
    pure
  {
    if (direction == Direction.RightToLeft) {
      push(self, double % 16);
      push(self, double / 16);
    } else {
      push(self, double / 16);
      push(self, double % 16);
    }
  }

  function pushDouble(
    NibbleList memory self,
    byte double,
    Direction direction
  )
    internal
    pure
  {
    pushDouble(self, uint8(double), direction);
  }

  function fromBytes(
    bytes memory value,
    Direction direction
  )
    internal
    pure
    returns (NibbleList memory)
  {
    NibbleList memory result = NibbleList(new uint8[](value.length), 0);
    for (uint i = 0; i < value.length; i++) {
      if (direction == Direction.RightToLeft) {
        pushDouble(result, value[value.length - i - 1], direction);
      } else {
        pushDouble(result, value[i], direction);
      }
    }
    return result;
  }

  function toBytes(
    NibbleList memory self,
    Direction direction
  )
    internal
    pure
    returns (bytes memory)
  {
    uint len = self.len;
    bytes memory result = new bytes(len / 2 + len % 2);
    for (uint i = 0; i < len / 2; i++) {
      if (direction == Direction.RightToLeft) {
        result[i] = byte(self.nibbles[len - 2*i - 1] << 4 + self.nibbles[len - 2*i - 2]);
      } else {
        result[i] = byte(self.nibbles[2*i] << 4 + self.nibbles[2*i+1]);
      }
    }
    if (len % 2 == 1) {
      if (direction == Direction.RightToLeft) {
        result[result.length - 1] = byte(self.nibbles[0]);
      } else {
        result[result.length - 1] = byte(self.nibbles[len - 1] << 4);
      }
    }
    return result;
  }
}
