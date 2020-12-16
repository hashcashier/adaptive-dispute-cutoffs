var RLP = require('rlp')

const ZERO_BYTES = '0x0000000000000000000000000000000000000000000000000000000000000000';

function hex(x) {
  return '0x' + x.toString('hex');
}

const encodeRLP = input => (input === '0x0')
  ? RLP.encode(Buffer.alloc(0))
  : RLP.encode(input);

function procTrieProof(proof) {
  let result = new Array(proof.length);
  for (let i = 0; i < proof.length; i++) {
    result[i] = hex(RLP.encode(proof[i]));
  }
  return result;
}

function bottomUpTrieProof(proof, key) {
  let leftProofs = new Array(proof.length);
  let rightProofs = new Array(proof.length);
  let nibble = 0;
  // console.log(key);
  for(let i = 0; i < proof.length; i++) {
    // console.log(proof[i]);
    if (proof[i].length == 2) {
      let flags = proof[i][0][0] >> 4;
      let odd = (flags & 1) == 1;
      let fin = (flags & 2) == 2;
      let size = 2*proof[i][0].length - 2 + odd;
      nibble += size;
      if (fin) {
        leftProofs[i] = [proof[i][0]];
      } else {
        leftProofs[i] = proof[i];
      }
      rightProofs[i] = [];
    } else if (proof[i].length == 17) {
      let fin = i == proof.length - 1;
      let pos = fin
        ? 16
        : (nibble%2 == 1)
          ? key[nibble] % 16
          : key[nibble] >> 4;
      leftProofs[i] = proof[i].slice(0, pos);
      rightProofs[i] = proof[i].slice(pos+1);
    } else {
      throw "Invalid node: " + proof[i];
    }
    // console.log(leftProofs);
    // console.log(rightProofs);
  }
  return [leftProofs.reverse(), rightProofs.reverse()];
}

function merkleTree(leaves, map={}, idx=0) {
  let n = leaves.length;
  assert(n>0);
  if (n == 1) {
    let result = {
      node: leaves[0],
      hash: leaves[0],
      index: idx,
      height: 0,
    };
    map[idx] = result;
    return result;
  } else {
    let mid = Math.floor(n/2);
    let left = leaves.slice(0, mid), right = leaves.slice(mid, n);
    let leftChild = merkleTree(left, map, 2*idx);
    let rightChild = merkleTree(right, map, 2*idx+1);
    let internalNode = {
      leftChild: leftChild,
      rightChild: rightChild,
    };
    let result = {
      height: leftChild.height + 1,
      node: internalNode,
      hash: web3.utils.soliditySha3(
        { type: 'uint32', value: internalNode.leftChild.height },
        { type: 'bytes32', value: internalNode.leftChild.hash },
        { type: 'bytes32', value: internalNode.rightChild.hash })
    }
    leftChild.parent = result;
    rightChild.parent = result;
    return result;
  }
}

function membershipProof(leaf, idx) {
  let result = [];
  let index = idx != undefined ? idx : leaf.index;
  let node = leaf;
  while (node.parent != undefined) {
    let nodeLeft = index%2 == 0; // is the current node on the left of the link

    if (nodeLeft) {
      result.push(node.parent.node.rightChild);
    } else {
      result.push(node.parent.node.leftChild);
    }

    node = node.parent;
    index >>= 1;
  }
  return result;
}

function membershipProofSiblings(proof) {
  return proof.map(function(element) {
    return element.hash;
  });
}

function eac(leaves, map = {}, idx = 0) {
  let n = leaves.length;
  assert(n>0);
  if (n == 1) {
    let result = {
      node: leaves[0],
      hash: leaves[0].hash,
      index: idx,
      height: 0,
    };
    map[idx] = result;
    return result;
  } else {
    let mid = Math.floor(n/2);
    let left = leaves.slice(0, mid), right = leaves.slice(mid, n);
    let leftChild = eac(left, map, 2*idx);
    let rightChild = eac(right, map, 2*idx+1);
    let internalNode = {
      left: leaves[0].left,
      leftChild: leftChild,
      mid: leaves[mid].left,
      rightChild: rightChild,
      right: leaves[n-1].right,
    };
    let result = {
      height: leftChild.height + 1,
      node: internalNode,
      hash: web3.utils.soliditySha3(
        { type: 'uint32', value: internalNode.leftChild.height },
        { type: 'uint256', value: internalNode.left },
        { type: 'bytes32', value: web3.utils.soliditySha3(
          { type: 'bytes32', value: internalNode.leftChild.hash },
          { type: 'uint256', value: internalNode.mid },
          { type: 'bytes32', value: internalNode.rightChild.hash })},
        { type: 'uint256', value: internalNode.right }),
    }
    leftChild.parent = result;
    rightChild.parent = result;
    return result;
  }
}

function eacBoundaries(proof, trail) {
  return proof.map(function(element, index) {
    let linkLeft = (trail>>index)%2 == 1;
    return linkLeft ? element.node.left : element.node.right;
  });
}

function bubbleUp(tree, roots, target, commitment) {
  assert(target <= roots.length);
  while (true) {
    if (roots.length == target) {
      roots.push(commitment);
      tree.push([commitment]);
      return target;
    } else if (roots[target] == null) {
      roots[target] = commitment;
      tree[target].push(commitment);
      return target;
    } else {
      tree[target].push(commitment);
      commitment = web3.utils.soliditySha3(
        { type: 'uint64', value: target },
        { type: 'bytes32', value: roots[target] },
        { type: 'bytes32', value: commitment })
      roots[target] = null;
      target += 1;
    }
  }
}

function merkleCommitment(leaves) {
  if (leaves.length == 0) {
    return [[ZERO_BYTES]];
  }
  let tree = [];
  let target = -1;
  let roots = [];
  for (var i = 0; i < leaves.length; i++) {
    target = bubbleUp(tree, roots, 0, leaves[i]);
  }
  while (target != roots.length - 1) {
    target = bubbleUp(tree, roots, target, ZERO_BYTES);
  }
  // return roots[roots.length - 1];
  return tree;
}

function merkleProof(tree, idx) {
  let proof = [];
  for (var i = 0; i < tree.length - 1; i++) {
    if (idx % 2 == 0) {
      proof.push(tree[i][idx + 1]);
    } else {
      proof.push(tree[i][idx - 1]);
    }
    idx = idx >> 1;
  }
  assert(idx == 0);
  return proof;
}

function bubbleUpMSM(tree, roots, target, value, weight) {
  assert(target <= roots.length);
  let minVal = value, maxVal = value;
  let commitment = web3.utils.soliditySha3(
    { type: 'uint256', value: value },
    { type: 'uint256', value: weight },
    { type: 'uint256', value: minVal },
    { type: 'uint256', value: maxVal });
  while (true) {
    if (roots.length == target) {
      roots.push([commitment, weight, minVal, maxVal]);
      tree.push([[commitment, weight, minVal, maxVal]]);
      return target;
    } else if (roots[target] == null) {
      roots[target] = [commitment, weight, minVal, maxVal];
      tree[target].push([commitment, weight, minVal, maxVal]);
      return target;
    } else {
      tree[target].push([commitment, weight, minVal, maxVal]);
      weight += roots[target][1];
      minVal = roots[target][2];
      commitment = web3.utils.soliditySha3(
        { type: 'uint32', value: target },
        { type: 'bytes32', value: web3.utils.soliditySha3(
          { type: 'bytes32', value: roots[target][0] },
          { type: 'bytes32', value: commitment }) },
        { type: 'uint256', value: weight },
        { type: 'uint256', value: minVal },
        { type: 'uint256', value: maxVal });
      roots[target] = null;
      target += 1;
    }
  }
}

function merkleSumMinMaxCommitment(leaves, boundary) {
  if (leaves.length == 0) {
    return [[ZERO_BYTES, 0, 0, 0]];
  }
  let tree = [];
  let target = -1;
  let roots = [];
  for (var i = 0; i < leaves.length; i++) {
    target = bubbleUpMSM(tree, roots, 0, leaves[i][0], leaves[i][1]);
  }
  while (target != roots.length - 1) {
    target = bubbleUpMSM(tree, roots, target, boundary, 0);
  }
  // return roots[roots.length - 1];
  return tree;
}

Object.assign(exports, {
  hex,
  encodeRLP,
  procTrieProof,
  merkleTree,
  membershipProof,
  membershipProofSiblings,
  eac,
  eacBoundaries,
  merkleCommitment,
  merkleProof,
  merkleSumMinMaxCommitment
});
