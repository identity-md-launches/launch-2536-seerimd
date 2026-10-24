# SeerIMD (SEER)

SeerIMD is a fixed-supply ERC-20. Its constructor mints exactly **1,000,000,000 SEER**
with **18 decimals** to its immediate deployer. The supply in base units is
**1000000000000000000000000000** (`10^27`).

## Contract and assumptions

- Deployable contract: `src/SeerIMD.sol:SeerIMD`.
- Name: `SeerIMD`; symbol: `SEER`; decimals: `18`.
- `INITIAL_SUPPLY` is the named constant for the one-time constructor mint.
- The constructor has **no arguments**, is nonpayable, and makes no external calls.
- A direct deployment credits the deploying account. A factory deployment credits
  the factory (`msg.sender`), not the transaction origin or a separately configured owner.
- There are no application contracts, owner, roles, initialization calls, upgrade
  mechanism, pause, blacklist, transfer restrictions, fees, rebases, or public mint/burn
  functions. Supply remains fixed after construction.
- Every successful transfer delivers its full amount. Zero-value transfers and
  self-transfers are supported; insufficient balances or allowances revert.
- Transfers to the zero address and approvals to a zero spender revert. The zero
  address appears only as the sender of the constructor's mint event.
- `approve` replaces an allowance. Finite allowances decrease on `transferFrom`;
  `type(uint256).max` is treated as unlimited and does not decrease. Even a holder
  using `transferFrom` on its own balance needs an allowance; `transfer` does not.
- Explicit approvals emit `Approval`. Transfers, including zero-value transfers,
  emit `Transfer`. The vendored OpenZeppelin implementation does not emit another
  `Approval` when `transferFrom` spends an allowance.

The contract inherits the unmodified ERC-20 implementation from
[OpenZeppelin Contracts v5.4.0](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.4.0/contracts/token/ERC20/ERC20.sol).
Its interface follows [ERC-20](https://eips.ethereum.org/EIPS/eip-20).

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x98e12f99a057fecf63f5881b85c2ab0a4f9f105da74dd8e06ffe7dc69f3ec17a forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files in `lib/`; no
network, submodules, package installation, RPC, fork, environment configuration,
or wallet is needed to build and test once the pinned compiler is installed.
The command above supplies the requested fuzz seed to Foundry; tests themselves
neither read nor write environment variables. `dependencies.lock.json` records
the exact release archives and SHA-256 checksums of the vendored files.

`foundry.toml` pins Solidity 0.8.26, optimizer runs to 200, and
`bytecode_hash = "none"`. The EVM target is Paris to avoid requiring newer
opcodes; the token uses no chain-specific features, block numbers, timestamps,
or external infrastructure. FFI and filesystem permissions are not enabled.

Unit and fuzz tests cover metadata, one constructor mint, direct and factory
deployment, complete transfers, zero/self transfers, events, approval replacement
and revocation, finite/unlimited allowances, authorization, invalid recipients,
insufficient balances/allowances, atomic failure, and rejection of mint/admin/
upgrade calls. Stateful invariant tests compare every tracked balance and
allowance with an independent accounting model across transfers, approvals,
delegated transfers, and rejected operations. The default configuration runs
1,024 cases per fuzz test and 128 invariant sequences of up to 64 operations.

The launch-flow unit test checks full-value distribution, claims, and transfers
to/from a pool-manager actor. It is an accounting test, not a real Uniswap swap.
The supplied protected launch checks reference IdentityMD's separate factory,
pool, owner-check harness and launch configuration, which are not part of this
repository. Their end-to-end admission run remains with IdentityMD's verifier.

## Deployment parameters and responsibilities

The intended launch chain is **Robinhood Chain, chain ID 4663**, as specified by
the assignment. Deploy the compiled `SeerIMD` creation bytecode with no appended
constructor arguments and no native currency. There are no linked libraries.
The factory must receive all `10^27` base units before distributing any tokens.
No owner/recipient address, external contract address, or secret is required by
this token's constructor.

IdentityMD's deployment process creates the launch manifest separately and
performs deployment, source verification, allocation and pool creation. No
manifest or transaction-broadcasting script is included here. The task's launch
parameters are recorded below for handoff; they are not token-level settings:

| Parameter | Assignment value |
| --- | --- |
| Paired currency | IMD at `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` (18 decimals) |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Provenance initial price | `79228162514264337593543950336` |
| Pool allocation | `8000` bps of the full supply (800,000,000 SEER) |
| Initial market cap | `5000000000000000000000` IMD base units (5,000 IMD) |
| Factory-managed swarm allocation | 10% (100,000,000 SEER) to its MerkleDistributor |
| Remaining allocation | 10% (100,000,000 SEER) to `0x6bf192ebef135e0f645e99d59d9bf44e7711606c` |

The launch process derives the actual opening price from the market cap, supply,
and deployed token address. The token does not perform allocation, create a
distributor, seed a pool, or retain any reserved share.

## After launch

No token configuration or privileged operator is required. The launch operator
is responsible for checking the deployed bytecode, name, symbol, decimals,
supply, mint recipient and final factory distributions, and for publishing the
verified source and token address. The separate factory and liquidity protocols
remain responsible for their own operations.

Holders control their balances and spender approvals. When changing an existing
nonzero allowance, revoke it first and wait for confirmation before granting the
replacement; a spender may use an existing allowance before revocation confirms.
Unlimited approvals remain usable until revoked and can expose future balances.
Wallets and integrations should query `allowance` rather than infer every change
from `Approval` events.

There is no rescue function: tokens sent to this token contract or to an address
that cannot transfer them are inaccessible, although they remain part of supply.
Direct native-currency payments revert; any native currency forced into the
contract is also unrecoverable. There is no administrator able to recover a lost
key, reverse transfers, freeze balances, or upgrade this deployment.

The local tests and source review are not an independent security audit.
IdentityMD's independent review and deployment checks remain release responsibilities.

## Dependencies and license

- Production: the required ERC-20 source subset of OpenZeppelin Contracts v5.4.0,
  MIT, under `lib/openzeppelin-contracts/`.
- Tests: forge-std v1.9.7 source, Apache-2.0/MIT, under `lib/forge-std/`.
- Project source and tests: MIT; see `LICENSE`.
