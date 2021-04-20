# Rayonism -- The Merge spec ☀️

## Table of contents

<!-- TOC -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Consensus node](#consensus-node)
  - [Consensus messages](#consensus-messages)
- [Execution engine](#execution-engine)
  - [Consensus JSON-RPC](#consensus-json-rpc)
    - [Constant block fields](#constant-block-fields)
    - [Legacy rewards](#legacy-rewards)
    - [Assemble Block](#assemble-block)
      - [Method](#method)
      - [Parameters](#parameters)
      - [Returns](#returns)
      - [Description](#description)
    - [New Block](#new-block)
      - [Method](#method-1)
      - [Parameters](#parameters-1)
      - [Returns](#returns-1)
      - [Description](#description-1)
    - [Set Head](#set-head)
      - [Method](#method-2)
      - [Parameters](#parameters-2)
      - [Return](#return)
      - [Description](#description-2)
    - [Finalise Block](#finalise-block)
      - [Method](#method-3)
      - [Parameters](#parameters-3)
      - [Return](#return-1)
      - [Description](#description-3)
  - [Network](#network)
    - [Disabling block gossip](#disabling-block-gossip)
    - [Block and state sync](#block-and-state-sync)
    - [Transaction pool](#transaction-pool)
    - [Discovery](#discovery)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
<!-- /TOC -->

In general Ethereum client consists of two layers. This separation becomes especially important in the context of the Merge.

- **Consensus-layer.** Responsible for the consensus, i.e. block seal validity, and fork choice rule. The Merge enables PoS consensus driven by the beacon chain hence this layer is represented by modified beacon chain client (e.g. lighthouse, teku, lodestar, prysm, and nimbus).
- **Execution-layer.** Responsible for transaction bundling, execution, and state management. This layer is represented by modified pre-merge PoW clients (eg. geth, nethermind, besu, openethereum, turbogeth, etc).

If these layers are bundled into a single piece of software, then the UX of running a post-merge client would be very similar to running a pre-merge PoW client today.

Though tightly coupling might be a good exercise, this is not the setup we pursue for Rayonism. For the sake of simplicity and code reuse, we are leveraging existing beacon chain and pre-merge PoW clients.

This document specifies the modifications must be made to beacon chain and pre-merge clients to turn them into a post-merge consensus node and execution engine, respectively.

After the merge, we say that an ethereum client consists of two components/layers, consensus node (a.k.a. beacon node) and execution engine (a.k.a. pre-merge PoW client). These counterparties interact via a unidirectional communication protocol, and this interaction is driven by the consensus node.

## Consensus node

In order to turn beacon chain client into consensus node, one must upgrade it to the beacon chain spec denoted by [this commit](https://github.com/ethereum/eth2.0-specs/tree/dev/specs/merge).

Live PoW to PoS transition logic (a.k.a. docking procedure) is not included in the Rayonism project at the start. The docking procedure is described mainly in the [fork-choice.md](https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/fork-choice.md) file and a bit in [validator.md](https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/validator.md). Unless it is explicitly specified all devnets and testnets are starting from the point in time "after the merge", i.e. if the transition had already happened.

One of the dependencies of this part of the spec is to have access to an execution engine endpoint that implements and exposes the [Consensus JSON-RPC](#Consensus-JSON-RPC). Consensus node may provide a new `--execution-engine-url` (or with any other appropriate name) CLI option or reuse already existing one that is used for `Eth1Data` retrieval to establish connection wtih execution engine.

### Consensus messages

Method calls explained in [Consensus JSON-RPC](#Consensus-JSON-RPC) section should have the following originators:

- **AssembleBlock.** Validator code that is responsible for beacon block proposal. See
  [`produce_execution_payload`](https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/validator.md#produce_execution_payload) function call in the spec.
- **NewBlock.** Beacon block processing code (part of beacon state transition function). See [`execution_state_transition`](https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/beacon-chain.md#execution_state_transition) function call in the spec.
- **SetHead.** This call is implementation specific and must be done every time when [`get_head`](https://github.com/ethereum/eth2.0-specs/blob/dev/specs/phase0/fork-choice.md#get_head) function returns new head. The case when the head is transferred from current head block to its child is also implied. The call should not be made if a fork choice event, e.g. attestation processing, hasn't affected current head.
- **FinaliseBlock.** Fork choice code that is responsibled for updating the most recent finalised checkpoint. It's not included in the current spec version, suggested place to make the call is the corresponding branch of [`on_block`](https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/fork-choice.md#on_block) fork choice function.

## Execution engine

There are two steps in modification of ethereum mainnet client to make it Merge compliant.

The first step is implementation of a new JSON-RPC namespace called `consensus` which enables external consensus and fork choice rule support.

The second step is to make corresponding modifications in the network stack.

### Consensus JSON-RPC

For the sake of simplicity we extend existing Ethereum JSON-RPC protocol in Rayonism project rather than implementing something new. Note: it is likely these communications will not use JSON-RPC in the production Merge spec.

Methods described below are compounded with corresponding actions expected to be taken by execution engine. These descriptions constitute the core part of the spec of the execution engine.

It is recommended to process requests coming from consensus node in sequential order. This would ensure that causally dependent messages are produced correctly. An example of such dependency is `SetHead` message that specifies the block sent by the recent `NewBlock` message.

#### Constant block fields

There are a number of current mainnet block fields that are deprecated by the Merge. These fields must be set to the following constants during assembling or processing a block after the Merge.

- **`difficulty = 1`**
- **`nonce = 0`**
- **`extraData = [empty byte string]`**
- **`mixHash = [32-bytes string filled with zeroes]`**
- **`uncles = [empty list]`**

#### Legacy rewards

Uncles validation and block rewards are deprecated. Former PoW (execution) chain no longer issues ETH.

*Note*: Transaction Fees are still processed as per the rules of the execution chain, with non-burnt fees going to the address specified in the **`beneficiary`** (a.k.a. miner, coinbase) field of a block.

#### Assemble Block

##### Method
**`consensus_assembleBlock`**

##### Parameters
1. `Object` - The new block dependencies:
- `parentHash`: `DATA`, 32 Bytes - hash of the parent block.
- `timestamp`: `QUANTITY` - unix timestamp of a new block.

##### Returns

1. `Object` - The execution payload of newly produced block:
- `blockHash`: `DATA`, 32 Bytes - hash of assembled block, i.e. `keccak256(RLP.encode(BlockHeader))`.
- `parentHash`: `DATA`, 32 Bytes - hash of the parent block.
- `miner`: `DATA`, 20 Bytes - the address of the beneficiary to whom transaction fees are given.
- `stateRoot`: `DATA`, 32 Bytes - the root of the final state trie of the block.
- `number`: `QUANTITY` - the block number.
- `gasLimit`: `QUANTITY` - the maximum gas allowed in this block.
- `gasUsed`: `QUANTITY` - the total used gas by all transactions in this block.
- `timestamp`: `QUANTITY` - unix timestamp of the block; must be equal to the value of `timestamp` parameter.
- `receiptsRoot`: `DATA`, 32 Bytes - the root of the receipts trie of the block.
- `logsBloom`: `DATA`, 256 Bytes - the bloom filter for the logs of the block.
- `transactions`: `Array` - Array of encoded transactions, each transaction is a byte list (`DATA`), representing `TransactionType || TransactionPayload` or `LegacyTransaction` as defined in [EIP 2718](https://eips.ethereum.org/EIPS/eip-2718)

##### Description

Grabs a set of transactions from the pool and creates a new block on top of given parent. Very similar to what `eth_getWork` does today.

There might be the case when `parent_hash` does not specify current head. In this case block must be assembled on top of given parent and returned back as usual, no any other action must be taken.

Pay attention to the `timestamp` field passed onto the method call. This is a timestamp of the beginning of beacon slot that the block is being produced.

Transactions use the `OpaqueTransaction` type in the beacon chain to avoid the necessity of supporting different legacy transaction type structures, and enable further transaction type changes Eth1 without changing the Merge specs. The `OpaqueTransaction` encodes an EIP 2718 envelope: a type byte, and further transaction payload. The transaction is encoded in RLP in the case of legacy transactions, please refer to EIP2718.

Future updates of the beacon chain may introduce an `Union` with `OpaqueTransaction` and additional SSZ-structured transaction options, for merkle-proof purposes. This is not part of the Rayonism specification at this moment.

#### New Block

##### Method
**`consensus_newBlock`**

##### Parameters

1. `Object` - The execution payload of new block:
- `blockHash`: `DATA`, 32 Bytes - hash of this block.
- `parentHash`: `DATA`, 32 Bytes - hash of the parent block.
- `miner`: `DATA`, 20 Bytes - the address of the beneficiary to whom transaction fees are given.
- `stateRoot`: `DATA`, 32 Bytes - the root of the final state trie of the block.
- `number`: `QUANTITY` - the block number.
- `gasLimit`: `QUANTITY` - the maximum gas allowed in this block.
- `gasUsed`: `QUANTITY` - the total used gas by all transactions in this block.
- `timestamp`: `QUANTITY` - unix timestamp of the block.
- `receiptsRoot`: `DATA`, 32 Bytes - the root of the receipts trie of the block.
- `logsBloom`: `DATA`, 256 Bytes - the bloom filter for the logs of the block.
- `transactions`: Array of encoded transactions, each transaction is a byte list (`DATA`), representing `TransactionType || TransactionPayload` as defined in [EIP 2718](https://eips.ethereum.org/EIPS/eip-2718)

##### Returns

1. `Object` - The result of processing a new block:
- `valid`: `Boolean` - set to `true` if block is valid, otherwise `false`.

##### Description

Assembles a block, executes transactions and inserts a block into the chain if the block is valid. Returns the result, `valid`, of block processing.

Upon receiving this message, execution engine must take the following actions:
1. Assemble a block from given execution payload and the set of [constants](#Constant-block-fields), and check that `blockHash` equals to `keccak256(RLP.encode(BlockHeader))`. If the check is not passed then the block is considered invalid.
2. Verify pre-conditions (parent block presence, gas limit with respect to the parent, etc). If any of the checks is failed then the block is considered invalid. Following checks must be omitted:
  - ethash seal validity
  - `difficulty` value with respect to the parent
  - `timestamp` value with respect to the parent
3. Execute transactions in a block with running post-condition checks (state root, receipt root, logs bloom, etc). If any of the checks is failed then the block is considered invalid.
4. In-protocol block and uncle rewards must be omitted. While transaction fees must be charged to the `miner` address (as usual).
5. If the block is valid then it must be inserted into the chain.

If a block with the same hash has been processed previously then the engine may take a short path and return the result of the previous execution. Validity condition in step 1. must be checked even in this case.

#### Set Head

##### Method
**`consensus_setHead`**

##### Parameters
1. `blockHash`: `DATA`, 32 Bytes - hash of the head of the chain.

##### Return
1. `Object` - result of an attempt to set the head:
- `success`: `Boolean` - set to `true` if head has been changed successfully, otherwise `false`.

##### Description

Sets the head of the chain to the block specified by the `blockHash` parameter.

An implementation of this method requires decoupling chain management from the current fork choice rule based on total difficulty. This change might require significant re-work of client components responsible for managing and storing the chain.

During transition process the total difficulty rule dictates the fork choice until a certain moment in time when it switches to the new (external/PoS) one. This introduces a certain level of complexity to implementations. Client implementers are encouraged to think about this use case as well and re-design chain managers of their clients appropriately.

The beacon chain fork choice rule isn't self-sufficient with respect to the block tree (unlike the total difficulty rule). This means that a given leaf block may be set as the chain head at any moment in time after the block has been processed and even if no other blocks have been produced thereafter.

This requires the execution engine to strictly follow `SetHead` messages received from consensus and adjust the head accordingly. Implementing a synthetic difficulty in attempt to incorporate a new fork choice rule with the usage of old machinery will result in the engine incorrectly following the head of the chain in some edge cases.

#### Finalise Block

##### Method
**`consensus_finaliseBlock`**

##### Parameters
1. `blockHash`: `DATA`, 32 Bytes - hash of finalised block.

##### Return
1. `Object` - result of an attempt to finalise a block:
- `success`: `Boolean` - set to `true` if block has been finalised successfully, otherwise `false`.

##### Description

Notifies the execution engine that the block identified by `blockHash` has been finalised by consensus-layer.

For Rayonism project we do not specify any particular action that the engine must take upon receiving this message. It could be a stubbed handler that always succeeds.

In the production it might be the case that the notion of finalised block will be exposed by existing JSON RPC and, thus, required to be stored in the database.

The other potential use case for finalised block message is in activating garbage collection cycles, like state trie pruning.

### Network

#### Disabling block gossip

New block propagation must be disabled. Namely, `NewBlock` and `NewBlockHashes` ingress and egress handlers must be dropped.

#### Block and state sync

In early Rayonism devnets and testnets the beacon chain will use its block sync to start up from genesis and send an execution payload of each block to execution engine.

Thus, block and state downloaders should be disabled until another behaviour is explicitly specified.

#### Transaction pool

Transaction pool must operate as usual. Depending on implementation, transaction processing might be tightly coupled to the result of sync process.

For simplicity, it is suggested to bootstrap sync process as if it had been already finished upon startup despite of the actual sync status. Though, it is up to client developers to decide on particular solution.

#### Discovery

Peer discovery must operate as usual with bootnodes set up accordingly. Namely, by default, the unified client operates as two separate nodes in the DHT, one for each layer.

We may experiment with discv5, bootstrap nodes and DHT shared between the layers at the end of hackathon.
