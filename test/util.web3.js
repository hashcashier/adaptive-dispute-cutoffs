async function mineBlocks(count) {
  for (let i = 0; i < count; i++) {
    await new Promise((resolve, reject) => web3.currentProvider.send({
      jsonrpc: "2.0",
      method: "evm_mine",
      id: 12345,
      params: [],
    }, (err, res) => {return err ? reject(err) : resolve(res)}));
  }
};

async function minerStop() {
  await new Promise((resolve, reject) => web3.currentProvider.send({
    jsonrpc: "2.0",
    method: "miner_stop",
  }, (err, res) => {return err ? reject(err) : resolve(res)}));
};

async function minerStart() {
  await new Promise((resolve, reject) => web3.currentProvider.send({
    jsonrpc: "2.0",
    method: "miner_start",
  }, (err, res) => {return err ? reject(err) : resolve(res)}));
};

function sleepMs(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}


Object.assign(exports, {
  mineBlocks,
  minerStop,
  minerStart,
  sleepMs
});
