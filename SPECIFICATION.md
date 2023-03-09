# Velodrome Finance Specification

Velodrome V2 is a partial rewrite and redesign of the Solidly architecture.

Velodrome V2 will be operating in parallel with V1, this is necessary to not
disrupt any existing operations and allow a smooth transition for existing
protocol users.

## Definitions

- VELO: The native token in the Velodrome ecosystem. It is emitted by the Minter and is an ERC-20 compliant token.
- Epoch: An epoch is one week in length, beginning at Thursday midnight UTC time. After 4 years, the day of the week it resets on will shift. 
- Pool: AMM constant-product implementation similar to Uniswap V2 liquidity pools.


## Permissions

The following roles are granted various positions in the protocol:
- Governor: Governance contract for most issues around governance.
- EpochGovernor: Epoch governance contract for minter emissions governance. 
- Emergency Council: A Curve-esque emergency DAO consisting of seven members from both the Velodrome team and prominent figures within the Optimism community. 

## Protocol Upgradability

Velodrome V2 is immutable, just like V1. To allow improving the protocol, V2
factories are all upgradable. This means we can release new versions of
factories for our pairs and gauges, and leave it up to the users to decide if
they want to migrate their positions.

## AMM

### Pair

AMM constant-product implementation similar to Uniswap V2 liquidity pools. 

Lightly modified to allow for the following:
- Support for both stable and volatile pools. Stable pools use a different formula which assumes little to no volatility. The formula used for pricing the assets allows for low slippage even on large traded volumes. Volatile pools use the standard constant product formula. 
- Custom fees per pool.
- Modifying a pool's name and symbol (requires `emergencyCouncil` permissions).

Stable pairs use the `x^3 * y + y^3 * x` curve, which may have a larger
rounding error when calculating the invariant `K` when compared to Uniswap
V2's constant product formula. The invariant `K` can temporarily decrease
when a user performs certain actions like depositing liquidity, doing
a swap and withdrawing liquidity. This means that the ratio of `K` to the
total supply of the pool is not monotonically increasing. This temporary decrease 
is negligible and the ratio will eventually increase again. In most cases, this issue
is not critical. This is mentioned as a courtesy to integrators that may depend
 on the ratio of `K` to `totalSupply`as a way of measuring the value of LP tokens.

### PairFees

Pair helper contract that stores pool trading fees to keep them separate from the liquidity pool. 

### Router

Standard UniswapV2-like Router interface. Supports multi-pool swaps, lp deposits and withdrawals. All functions support both V1 / V2 pools EXCEPT `addLiquidity` and `removeLiquidity`. These support V2 pools only.

In addition, the router also supports:
- Swapping and lp depositing/withdrawing of fee-on-transfer tokens.
- Zapping in and out of a pool from any token (i.e. A->(B,C) or (B,C) -> A). A can be the same as B or C.
- Zapping and staking into a pool from any token. 

### FactoryRegistry

Registry of pair, gauge, bribe and managed rewards factories. Contains a default list of factories so swaps via the router will always work. 


## Token

### Velo

Standard ERC20 token. Minting permissions granted to both Minter and Sink Manager.

### VotingEscrow

The VotingEscrow contracts allow users to escrow their VELO tokens in an veVELO NFT. The (ERC-721 compliant) NFT has a balance which represents the voting weight of the escrowed tokens, which decays linearly over time. Tokens can be locked for a maximum of four years. veVELO NFT vote weights can be used to vote for pools, which in turn determines the proportion of weekly emissions that go to each pool. VotingEscrow's clock mode is timestamps (see EIP-6372).

There are three states that veVELO NFTs can be in: `NORMAL`, `LOCKED`, `MANAGED`. `NORMAL` NFTs are the NFTs that users are familiar with. `Managed` NFTs are a new type of NFT (see below). When a user deposits a normal NFT into a managed NFT, it becomes a `LOCKED` NFT. `NORMAL` NFTs are not restricted in functionality whereas `LOCKED` NFTs have extremely restricted functionality and `MANAGED` NFTs have limited functionality. Managed NFT deposits and withdrawals are handled by `Voter`.

Standard Operations:
All of these operations require ownership of the underlying NFT or tokens being escrowed. 
- Can create a NFT by escrowing VELO tokens and "locking" them for a time period.
- Can do anything with the NFT as supported by the ERC-721 interface (requires normal or managed NFT).
- Can merge one NFT into another (requires normal NFT).
- Can split a single NFT into two NFTs (requires normal NFT). This function is initially permissioned by tokenId (requires team). 
- Can disable permissions for split (requires team).
- Can withdraw escrowed VELO tokens once the NFT lock expires (requires normal NFT). 
- Can add to an existing NFT position by escrowing additional VELO tokens (requires normal or managed NFT).
- Can increase the lock duration of an NFT (and thus increasing voting power, requires normal or managed NFT).
- Can delegate votes for use in Velodrome governance to other addresses based on voting power (requires normal or managed NFT). The balances in this method do not reflect real coins, they are used only for voting.

In addition, Velodrome supports "managed NFTs" which aggregates NFT voting power whilst perpetually locking the underlying tokens. These NFTs function as a single NFT, with rewards accrued by the NFT going to the manager, who can then distribute (net of fees) to the depositors. 
- NFTs can exist in one of three states: normal, locked or managed. By default, they are in normal state.
- Only governance or an allowed manager can create managed NFTs, special NFTs in the managed state.
- Managed NFTs can be deactivated, a process which prevents the NFT from voting and from receiving deposits (requires emergency council).
- An NFT can deposit into one managed NFT at a time, converting it from normal state to locked state. 
- The deposited NFT can be withdrawn at any time, with its balance restored and locktime extended to the maximum (4 years). Any rebases collected by the manager will be distributed pro-rata to the user. 

### Minter

The minting contract handles emissions for the Velodrome protocol. Emissions start at 15m per epoch, decaying at a rate of 1% per epoch. Rebases (which are sent to `RewardsDistributor`) are added on top of the base emissions to produce the total emission. 

The minter has a modified emissions schedule that turns on once emissions fall below 5m per epoch (~110 epochs). After it turns on, weekly emissions will become a percentage of circulating supply, with the initial percentage starting at 30 basis points (i.e. 0.003). Every epoch, the emissions can be modified by one basis point with a vote conducted by `EpochGovernor`. See `EpochGovernor` for information on the vote. 

## RewardsDistributor

Standard Curve-fee distribution contract, modified for use with rebases. Rebase claims against expired veNFTs will be distributed as unlocked VELO to the owner of the veNFT.

## VeArtProxy

ve(NFT) art proxy contract, exists for upgradability purposes.

## Protocol

### Voter

The `Voter` contract is in charge of managing votes, emission distribution
as well as gauge creation in the Velodrome ecosystem. Votes can be cast once 
per epoch via Voter, with the votes earning NFT owners both bribes and fees 
from the pool they voted for. Voting can take place at any time during an epoch
except during the first and last hour of that epoch. Distributions to gauges will 
take place at the beginning of every epoch. In the last hour prior to epoch flip, 
only approved NFTs can vote. 

In addition, `Voter` also provides support for depositing and withdrawing from 
managed NFTs. Voting and depositing into a managed NFT are mutually exclusive 
(i.e. you may only do one per epoch). In the same way you cannot reset your NFT 
in the same epoch that you vote, you also cannot withdraw your NFT in the same 
epoch that you deposited. For more information about managed NFTs, see the 
`VotingEscrow` section. 

`Voter` is in charge of creating and mantaining gauge liveness states. Gauges that 
are killed will not receive emissions. Once per epoch, the corresponding gauge for 
a pool will receive emissions from `Voter` proportionate to the amount of votes they 
receive. Voter also contains several utility functions that make claiming rewards or 
distributing emissions easier. 

Standard Operations:
- Can vote with an NFT once per epoch if you did not deposit into a managed NFT that epoch. For regular users, the epoch voting window ends an hour prior to epoch flip. Certain privileged NFTs can continue to vote in this one hour window.
- Can deposit into a managed NFT once per epoch if you did not vote that epoch (requires normal NFT). Depositing into a managed NFT is disabled in the last hour prior to epoch flip.
- Can reset an NFT at any time after the epoch that you voted. Your ability to vote or deposit into a managed NFT in the week that you reset is preserved.
- Can withdraw from a managed NFT at any time after the epoch that you deposited into a managed NFT (requires locked NFT). Your ability to vote or deposit into a managed NFT is preserved. 
- Can poke an NFT. This updates the balance of that NFT in the rewards contracts. 
- Can bulk claim rewards (i.e. bribes + fees), bribes or fees. 
- Can distribute that epoch's emissions to pools.
- Can create gauge and reward contracts for a pool (must be a pool created as a part of Velodrome).

Permissioned Operations:
- Can set `governor` (requires `governor` permissions).
- Can set `emergencyCouncil` (requires `emergencyCouncil` permissions).
- Can whitelist a token for use in bribe contracts (requires `governor` permissions).
- Can whitelist an NFT for voting in the restricted window prior to epoch flip (requires `governor` permissions).
- Can create gauge and reward contracts for a pool (pool address can be any address, requires `governor` permissions).
- Can kill a gauge (requires `emergencyCouncil` permissions).
- Can revive a gauge (requires `emergencyCouncil` persmissions).
- Can add emissions to Voter (requires `Minter`).

### Gauge

The gauge contract is a standard rewards contract in charge of distributing emissions to LP depositors. Users that deposit LP tokens can forgo their fee reward in exchange for a proportional distribution of emissions (proportional to their share of LP deposits in the gauge). The fee rewards that the LP depositors forgo are transferred to the `FeeVotingReward` contract. 

Standard Operations:
- Can deposit LP tokens.
- Can deposit LP tokens for another receipient. 
- Can withdraw LP tokens. 
- Can get emission rewards for an account. 
- Can deposit emissions into gauge (requires `Voter`).

### Reward

The base reward contract for all reward contracts. Individual voting balance checkpoints and total supply checkpoints are created in a reward contract whenever a user votes for a pool. Checkpoints do not automatically update when voting power decays (requires `Voter.poke`). Rewards in these contracts are distributed proportionally to an NFT's voting power contribution to a pool. An NFT is distributed rewards in each epoch proportional to its voting power contribution in that epoch. 

### VotingReward

Voting rewards are rewards that accrue to users that vote for a specific pool. They can be broken down into fees and bribes.

### FeesVotingReward

The fee voting reward derives from the fees relinquished by LP depositors 
depositing their LP token in to the gauge. Note that in V1, fees begin accruing
immediately from when you vote for pool. In V2, fees are synchronized with bribes
and accrue in the same way. Thus, fees that accrue during epoch `n` will be 
distributed to voters of that pool in epoch `n+1`.

### BribeVotingReward

Bribe voting rewards are externally deposited rewards of whitelisted tokens (see `Voter`) used to incentivize users to vote for a given pool. 

### ManagedReward

Managed rewards are rewards that accrue to users that deposited their voting power into a managed NFT. 

### LockedManagedReward

Locked rewards are VELO token rewards that have been compounded into the managed NFT (usually rebases but can also include non-VELO rewards that have converted to VELO to be compounded into the NFT). This contract functions similar to `PairFees`, as it separates "reward" VELO from the "locked" VotingEscrow VELO. These rewards are not distributed and are returned to `VotingEscrow` when a user withdraws their NFT from a managed NFT. 

### FreeManagedReward

Free rewards are rewards that have been distributed to users depositing into a managed NFT. Any rewards earned by a managed NFT that a manager passes on will be distributed to the users that deposited into the managed NFT.


## V2 Migration

Velodrome V2 is designed to eventually replace the V1 token. To achieve that,
V2 Minter was designed to respect the schedule of V1 and provide a solution to
automatically convert the V1 emissions into V2 tokens. This is done by the Sink
Manager, Drainer and Converter.

For existing LPs/stake the V2 gauges will be provided for V1 pools, allowing
those users to switch to V2 by simply re-staking their LPs. Any new liquidity
pools, will be using V2 Pair Factory after the V1 release.

The V2 Router allows swaps between V1 and V2 pairs. Swapping V1 tokens into any
other tokens on V2 will automatically route through the right pairs seamlessly.

The V2 UI will allow converting an existing V1 veNFT into a V2 veNFT. The user
will have to reset their V1 veNFT to allow the operation to succeed, but they
can use the V2 veNFT right away.

### Sink Manager

The sink manager has helper functions that allow users to convert v1 assets to v2 assets. The sink manager also manages a veNFT which it uses to absorb and compound v1 VELO, ensuring that v1 emissions will be locked up over time.

Users can:
- Convert v1 VELO to v2 VELO.
- Convert v1 NFTs to an equivalent v2 NFT (lock time will not be exactly the same, but rounded to the nearest week).

v1 VELO that is converted will be added to the sink manager's veNFT, while v1 NFTs will be merged into the sink manager's ve NFT. Any v1 VELO captured via the `SinkConverter` will also be added to the sink manager's veNFT. Rebases and emissions will be compounded weekly to ensure emissions are captured.

### Sink Drain

A "fake" pair used solely for the purpose of collecting gauge emissions from V1. LP tokens for the Sink Drain are minted only to the Sink Manager. 

### Sink Converter

A "fake" pair used to provide liquidity to routers for routes going from v1 VELO to any other token (via v2 pools). Any VELO captured in this way ends up in the `SinkDrain`.


## Governance

### VeloGovernor

Lightly modified from OpenZeppelin's Governor contract. Enables governance by using 
timestamp based voting power from VotingEscrow NFTs. Includes support for vetoing of 
proposals as mitigation against 51% attacks. `proposalHash` has also been modified to 
include the `proposer` to prevent griefing attacks from proposal frontrunning. 

### EpochGovernor

An epoch based governance contract modified lightly from OpenZeppelin's Governor
contract to exclude the `cancel` function. It has been modified in such a way 
that it continues to adhere with OpenZeppelin's `IGovernor` interface. Once tail
emissions in the `Minter` are turned on, every epoch a proposal can be created
to either increase, hold or decrease the Minter's emission for the following 
epoch. The winning decision is selected via simple majority (also known as [plurality](https://en.wikipedia.org/wiki/Plurality_(voting))). Also uses timestamp based voting power 
from VotingEscrow NFTs. Note that the very first nudge proposal must be initiated in 
the epoch prior to the tail emission schedule starting. 

Notable changes:
- No quorum.
- No proposal threshold.
- Cannot relay via the governor. 
- Can only make a single proposal per epoch, to adjust the emissions in Minter once tail emissions have turned on. 
- A proposal created in epoch `n` will be executable in epoch `n+1` once the proposal voting period has gone through.
- Has three options (similar to Governor Bravo). The winner is selected based on which option has the most absolute votes at the end of the voting period. 
- The proposer of a proposal cannot cancel the proposal.