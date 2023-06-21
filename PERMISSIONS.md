# Velodrome V2 Access Control
## User Roles and Abilities
### Anyone
- Can swap tokens through the Velodrome DEX.
- Can provide liquidity.
- Can create a Normal veNFT.
- Can deposit VELO into an existing Normal veNFT.
- Can poke the balance of an existing veNFT to sync the balance.
- Can bribe a Velodrome liquidity pool through its' linked BribeVotingRewards contract.
- Can skim a stable or volatile liquidity pool to rebalance the reserves.
- Can sync a liquidity pool to record historical price
- Can trigger the emission of VELO at the start of an epoch
- Can create a liquidity pool with two different ERC20 tokens if the pool is not already created
- Can create a gauge for the liquidity pool if the gauge is not already created and the tokens are whitelisted

### Liquidity provider (LP)
- Can deposit their LP token into the Velodrome gauge linked to the liquidity pool
    - Earns VELO emissions

### veNFT Hodler
- For a detailed breakdown refer to [VOTINGESCROW.md](https://github.com/velodrome-finance/contracts/blob/contracts-v2/VOTINGESCROW.md)

#### Normal, Normal Permanent, and Managed veNFT
- Can approve/revoke an address to modify the veNFT
- Can transfer ownership of the veNFT
- Can increase amount locked
- Can vote weekly on pool(s)
    - Earns bribes and trading fees
    - Earns weekly distribution of VELO rebases
- Can vote on VeloGovernor proposals
- Can vote on EpochGovernor proposals

#### Normal veNFT
- Can withdraw the normal veNFT
- Can convert to/from Permanent state
- Can increase the lock time

#### Normal and Normal Permanent veNFT
- Can split the veNFT
- Can merge the veNFT

#### Normal Permanent and Managed veNFT
- Can delegate voting power 

#### Locked veNFT
- Can only withdraw their Locked veNFT from a Managed veNFT

---

## Admin Roles and Abilities
### Who

#### Velodrome Team
 Multisig at [0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5](https://optimistic.etherscan.io/address/0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5)
- Threshold: 3/7
- TODO: Who owns every address?

#### EmergencyCouncil
Multisig at [0x838352F4E3992187a33a04826273dB3992Ee2b3f](https://optimistic.etherscan.io/address/0x838352F4E3992187a33a04826273dB3992Ee2b3f)
- Threshold: 5/6
- TODO: Who owns every address?

#### Vetoer
Velodrome team at deployment of VeloGovernor. At a later date, this role will be renounced.

#### VeloGovernor (aka. Governor)
At first deployment, team. At a later date, this will be set to a lightly modified [Governor](https://docs.openzeppelin.com/contracts/4.x/api/governance#governor) contract from OpenZeppelin, [VeloGovernor](https://github.com/velodrome-finance/contracts/blob/contracts-v2/contracts/VeloGovernor.sol).  

#### EpochGovernor
At first deployment, team. Before the tail rate of emissions is reached, this will be set to [EpochGovernor](https://github.com/velodrome-finance/contracts/blob/contracts-v2/contracts/EpochGovernor.sol).

#### Allowed Manager
At first deployment, team. This role will likely be given to a contract so that it can create managed nfts (e.g. for autocompounders etc)

#### Fee Manager
Velodrome team

#### Pauser
Velodrome team

#### Factory Registry Owner
Velodrome team

#### Sink Manager Owner
Renounced after deployment


## Permissions List
This is an exhaustive list of all admin permissions in Velodrome V2, sorted by the contract they are stored in.

#### [PoolFactory](TODO: live etherscan link)
- Pauser
    - Controls pause state of swaps on UniswapV2 pools created by this factory.  Users are still freely able to add/remove liquidity
    - V1 pools will be pausable by the v1 factory.
    - Can set Pauser role
- FeeManager
    - Controls default and custom fees for stable / volatile pools.

#### [SinkManager](TODO: live etherscan link)
- Owner
    - Used for set up only, renounced when deployment is completed.

#### [FactoryRegistry](TODO: live etherscan link)
- Owner
    - Can approve / unapprove new pool / gauge / reward factory combinations.
    - This is used to add new pools, gauges or reward factory combinations. These new pools / gauges / rewards factories may have different code to existing implementations.

#### [Minter](TODO: live etherscan link)
- EpochGovernor
    - Can nudge the Minter to adjust the VELO emissions rate.

#### [VeloGovernor](TODO: live etherscan link)
- Vetoer
    - Can set vetoer in VeloGovernor.
    - Can veto proposals.
    - Can renounce vetoer role.

#### [Voter](TODO: live etherscan link)
- Governor
    - Can set governor in Voter.
    - Can set epochGovernor in Voter.
    - Can create a gauge for an address that is not a pool.
    - Can set the maximum number of pools that one can vote on.
    - Can whitelist a token to be used as a reward token in voting rewards or in managed free rewards.
    - Can whitelist an NFT to vote during the privileged epoch window.
    - Can create managed NFTs in VotingEscrow.
    - Can set allowedManager in VotingEscrow.
    - Can activate or deactivate managed NFTs in VotingEscrow.
- EpochGovernor
    - Can execute one proposal per epoch to adjust the VELO emission rate after the tail emission rate has been reached in Minter.
- EmergencyCouncil
    - Can set emergencyCouncil in Voter.
    - Can kill a gauge.
    - Can revive a gauge.
    - Can set a custom name or symbol for a Uniswap V2 pool.
    - Can activate or deactivate managed NFTs in VotingEscrow.

#### [VotingEscrow](TODO: live etherscan link)
- Team
    - Can set team in VotingEscrow
    - Can set artProxy in VotingEscrow.
    - Can enable split functionality for a single address.
    - Can enable split functionality for all addresses.
    - Can set proposalNumerator in VeloGovernor.
- AllowedManager
    - Can create managed NFTs in VotingEscrow.


## Contract Roles and Abilities
In addition to defined admin roles, various contracts within Velodrome protocol have unique permissions in calling other contracts.  These permissions are immutable.

#### [Minter](TODO: live etherscan link)
- Can mint VELO and distribute to Voter for gauge emissions and RewardsDistributor for claimable rebases
    - `Minter.updatePeriod()`

#### [SinkManager](TODO: live etherscan link)
- Can mint v2 VELO from the conversion of v1 VELO or a v1 veNFT
    - `SinkManager.convertVELO()`
    - `SinkManager.convertVe()`

#### [Voter](TODO: live etherscan link)
- Can distribute VELO emissions to gauges
    - `Voter.distribute()`
- Can claim fees and rewards earned by Normal veNFTs
    - `Voter.claimFees()`
    - `Voter.claimBribes()`
- Can deposit a Normal veNFT into a Managed veNFT
    - `Voter.depositManaged()`
- Can withdraw a Locked veNFT from a Managed veNFT
    - `Voter.withdrawManaged()`
- Can set voting status of a veNFT
    - `Voter.vote()`
    - `Voter.reset()`
- Can deposit and withdraw balances from `BribeVotingReward` and `FeesVotingReward`
    - `Voter.vote()`
    - `Voter.reset()`

#### [VotingEscrow](TODO: live etherscan link)
- Can deposit balances into `LockedManagedReward`
    - `VotingEscrow.depositManaged()`
- Can deposit balances into `FreeManagedReward`
    - `VotingEscrow.depositManaged()`
- Can withdraw balances from `LockedManagedReward` and `FreeManagedReward`, and rewards earned from `LockedManagedReward`
    - `VotingEscrow.withdrawManaged()`
- Can notify rewards to `LockedManagedReward`. These rewards are always in VELO.
    - `VotingEscrow.increaseAmount()`
    - `VotingEscrow.depositFor()`

#### [Pool](TODO: live etherscan link)
- Can claim the fees accrued from trades
    - `Pool.claimFees()`