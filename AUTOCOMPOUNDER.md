# AutoCompounder

Introduced in Velodrome V2 is a new type of veNFT called a "managed NFT" (also known as "(m)veNFT").  A (m)veNFT aggregates veNFT voting power into a single NFT, with rewards accrued by the NFT going to the owner of the (m)veNFT.  The (m)veNFT votes for pools in the same way a normal veNFT votes, with the exception that its' voting power is this aggregated voting power.

The challenge arises when a (m)veNFT has earned rewards from a voting period.  Does the (m)veNFT owner keep the rewards for themselves, distribute the rewards back to the veNFT depositors (either as the reward token or as VELO), or do something else with these rewards?  The Velodrome team provides a working MVP to solve this.

## Challenge
Provide a trusted and automated solution to distribute rewards earned by a (m)veNFT back to its' depositors.

## Solution
An automated compounder contract to convert rewards earned by a (m)veNFT back into VELO which is then deposited into the (m)veNFT.  The (m)veNFT voting power increases from these VELO deposits, further increasing the rewards earned.  When a normal veNFT holder who previously deposited into this (m)veNFT withdraws their veNFT back to their wallet, they receive their initial deposit back, as well as their proportional share of all compounded rewards.

## Implementation
There are several key components of the `AutoCompounder`:
- Access control / trust levels
- Time windows of access
- (m)veNFT design considerations

## Access Control / Trust levels
There are degrees of trust and access given to various groups.  The groups are:
- Public
- Keepers
- Allowed callers
- AutoCompounder admins
- Velodrome team

### Public
Can be any EOA or contract.  Are allowed to claim rewards and compound within the last 24 hours of an epoch.  Swap routes are determined using a fixed optimizer contract, although callers can provide their own custom route provided there is a better return.  The optional swap route provided must only route through high liquidity tokens, as added by team.  Public callers are rewarded based on the amount compounded - they receive a minimum of either (a) 1% of the VELO converted from swaps (rounded down) or (b) the constant VELO reward set by the team.

### Keepers
Addresses authorized by Velodrome team to claim rewards and compound after the 24 hours of an epoch flip.  Keepers are trusted to swap rewarded tokens into VELO using the amounts and routes they determine, assumed to be the best rate, which is then deposited into the (m)veNFT.

### Allowed Callers
Addresses authorized by the AutoCompounder admin to vote for gauges and send additional VELO rewards to the (m)veNFT to be distributed among veNFTs who have locked into the (m)veNFT.

### AutoCompounder Admins
An initial admin is set on AutoCompounder creation who can then add/remove other admins, as well as revoke their own admin role.  Admins can also add/remove Allowed Callers.  Within the first 24 hours after an epoch flip, an admin can claim and sweep reward tokens to any recipients as long as the tokens swept are not deemed high liquidity tokens.

### Velodrome Team
See PERMISSIONS.md for additional clarity.  The team can set the VELO reward amount for public callers, add high liquidity tokens, and add/remove keepers.

## Roles
| | Public | Keeper | Allowed Caller | Admin | Velodrome Team |
| --- | --- | --- | --- | --- | --- |
| Claim Rewards | Yes | Yes | | Yes  |  |
| Swap and Compound | - Use auto-generated optimal route or provide a better route </br> - Swaps full balance held| - Can provide any route </br> - Can swap any amount
| Reward paid to caller | Yes | | | |
| Sweep tokens | | | | Yes (if not a high liquidity token)| |
| Vote & increase rewards | | | Yes | |
| Set caller reward amount | | | | | Yes |
| Add high liquidity tokens | | | | | Yes |
| Add/remove Keepers | | | | | Yes|

## Time Windows of Access
| Who | First 24 hours | Middle 5 days |  Last 24 Hours
|---|---|---|---|
| Public | | | X | | X |
| Keeper | | X | X |
| Allowed Callers | X | X | X |
| Admin | X |  |  |
| Team | X | X | X


## (m)veNFT Design Considerations

### Who can create an AutoCompounder?
Anyone who owns a (m)veNFT can create an AutoCompounder.  Only the `allowedManager` role within VotingEscrow and the `governor` role within Voter have permission to create a (m)veNFT.  The (m)veNFT is sent to the AutoCompounder in creation where it will permanently reside.

### Lack of Governance voting ability
Anyone with a normal veNFT can deposit into a (m)veNFT.  Therefore, we expect to see (m)veNFTs controlled with the aggregate voting power of hundreds normal veNFTs or more.  The motivation in depositing a normal veNFT is to earn passive rewards, not to delegate voting power for governance.  However, the cumulative voting power of the (m)veNFT could be significant enough to influence Velodrome governance proposals.  Therefore, the AutoCompounder is designed:
- Without governance voting functionality
- No ability to withdraw the (m)veNFT

So, once a (m)veNFT is deposited into an AutoCompounder, it will stay there permanently.  

### Leaving the (m)veNFT
What happens if a (m)veNFT is deactivated by the team?  What happens if the controllers for the (m)veNFT can no longer be trusted to act in the best interest of the veNFT depositors?  What happens if a veNFT depositor finds a different (m)veNFT to deposit into, or if they decide to vote from their own veNFT again?  The answer to these questions is the same:

**At any time, a normal veNFT can be withdrawn from its' deposited (m)veNFT, as long as it has *not* been deposited within the same epoch**.

### What if Keepers compound using less-than-optimal routes to extract value?
Trust in this scenario is given to the Velodrome team, whose responsibility is to add and remove trusted keepers.  The Velodrome teams' best interest is in the protocol and the team's reputation is at stake.  Keepers will be actively monitored by the Velodrome Team to ensure they behave as intended, and will be removed immediately if needed.

### Can I trust the Admin in sweeping tokens?
The intention of sweep is solely to allow pulling of low liquidity tokens earned by the (m)veNFT, to prevent compounding the tokens with high slippage.  The admin can revoke their own access if desired.

### Why different time windows of access?
The first 24 hours after an epoch flip are given solely to the Admin in the case a token sweep is needed.  Afer this privileged access, the Keeper can claim and compound tokens as desired.  This prevents a race to sweep if the keepers are automated or compound as soon as they are able to.  The following five days are given solely to keepers to compound rewards.  Then, within the last 24 hours, everyone is incentivized to claim and compound any remaining rewards, including keepers.  This guarantees that rewards of high liquidity tokens will always be claimed and compounded, even without active keepers.

### Current list of high liquidity tokens
These tokens exist within Velodrome with at least $1M+ liquidity or $250k+ VELO liquidity in two or more pools:
- [USDC](https://optimistic.etherscan.io/token/0x7f5c764cbc14f9669b88837ca1490cca17c31607)
- [DOLA](https://optimistic.etherscan.io/token/0x8ae125e8653821e851f12a49f7765db9a9ce7384)
- [WETH](https://optimistic.etherscan.io/token/0x4200000000000000000000000000000000000006)
- [USD+](https://optimistic.etherscan.io/token/0x73cb180bf0521828d8849bc8cf2b920918e23032)
- [OP](https://optimistic.etherscan.io/address/0x4200000000000000000000000000000000000042)
- [MAI](https://optimistic.etherscan.io/token/0xdfa46478f9e5ea86d57387849598dbfb2e964b02?a=0x1ae4f1a178abfc6b7c90da19917676b82c698e4b)
- [wstETH](https://optimistic.etherscan.io/address/0x1f32b1c2345538c0c6f582fcb022739c4a194ebb)
- [DAI](https://optimistic.etherscan.io/token/0xda10009cbd5d07dd0cecc66161fc93d7c9000da1)
- [LUSD](https://optimistic.etherscan.io/address/0xc40f949f8a4e094d1b49a23ea9241d289b7b2819)
- [FRAX](https://optimistic.etherscan.io/token/0x2e3d870790dc77a83dd1d18184acc7439a53f475)
- [frxETH](https://optimistic.etherscan.io/token/0x6806411765af15bddd26f8f544a34cc40cb9838b)