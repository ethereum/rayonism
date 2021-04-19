# Example devnet

The merge is active from genesis; this testnet is to test the Eth1-Eth2 node communication,
and work on stability of the post-merge network.

**This is configuration is just for illustration**

See configs. Summary:
- 3 pre-funded application accounts. `100 million merge-ETH` each.
- Empty deposit contract embedded at `0x4242424242424242424242424242424242424242`
- Eth1 genesis at `1618840800` (`Mon Apr 19 2021 14:00:00 GMT+0000`)
- Eth2 genesis at `eth1 timestamp + GENESIS_DELAY = 1618840800 + 172800 = 1619013600` (`Wed Apr 21 2021 14:00:00 GMT+0000`)
- Genesis validator count: 16384
- Eth1 Chain ID: `500`
- Eth1 Network ID: `500`
- Eth2 fork version: `0x00000500`
- Initial gas limit at `0x400000` (= 4,194,304 gas)
