# AutoCompounder

Introduced in Velodrome V2 is a new type of veNFT called a "managed NFT" (also known as "(m)veNFT").  A (m)veNFT aggregates veNFT voting power into a single NFT, with rewards accrued by the NFT going to the owner of the (m)veNFT.  The (m)veNFT votes for pools in the same way a normal veNFT votes, with the exception that its' voting power is this aggregated voting power.

The challenge arises when a (m)veNFT has earned rewards from a voting period.  Does the (m)veNFT owner keep the rewards for themselves, distribute the rewards back to the veNFT depositors (either as the reward token or as VELO), or do something else with these rewards?  The Velodrome team introduces a working MVP to solve this.

## Challenge
Provide a trusted and automated solution to distribute rewards earned by a (m)veNFT back to its' depositors.

## Solution
An automated compounder contract to convert rewards earned by a (m)veNFT back into VELO which is then deposited into the (m)veNFT.  The (m)veNFT voting power increases from these VELO deposits, further increasing the rewards earned.  When a normal veNFT holder who previously deposited into this (m)veNFT withdraws their veNFT back to their wallet, they receive a percentage of the VELO deposited based on their share of the (m)veNFT.

## Implementation
There are several key components of the `AutoCompounder`:
- Access control / trust levels
- Time windows of functionality
- (m)veNFT design considerations


### Access Control / Trust levels
There are degrees of trust and access given to various groups.  Broken down, there are:
- Velodrome team
- Keepers
- AutoCompounder admins
- Allowed callers
- Public

#### Velodrome team
TODO

#### Keepers
TODO

#### AutoCompounder admins
TODO

#### Allowed callers
TODO

#### Public
TODO


### Time Windows of Functionality
There are time windows within an epoch where different functionality exist:
- The whole duration
- First 24 hours
- Middle 5 days
- Last 24 hours

#### The whole duration
Allowed callers can vote or deposit more VELO into the (m)veNFT, effectively a bribe bonus.  If the (m)veNFT is not whitelisted, it cannot vote within the last hour.

#### First 24 Hours
AutoCompounder admins can claim voting rewards and sweep tokens.

#### Middle 5 days
Trusted keepers can claim voting rewards, swap, and compound tokens.

#### Last 24 Hours
Public can claim voting rewards, swap, and compound tokens.

### (m)veNFT Design Considerations
Anyone with a normal veNFT can deposit into a (m)veNFT.  Therefore, we expect to see (m)veNFTs controlled with the aggregate voting power of hundreds normal veNFTs or more.  The motivation in depositing a normal veNFT is to earn passive rewards, not to delegate voting power for governance.  However, the cumulative voting power of the (m)veNFT could be significant enough to influence Velodrome governance proposals.  Therefore, the AutoCompounder is designed:
- Without governance voting functionality
- No ability to withdraw the (m)veNFT

So, once a (m)veNFT is deposited into an AutoCompounder, it will stay there permanently.  

#### Leaving the (m)veNFT
What happens if a (m)veNFT is deactivated by the team?  What happens if the controllers for the (m)veNFT can no longer be trusted to act in the best interest of the veNFT depositors?  What happens if a veNFT depositor finds a different (m)veNFT to deposit into, or if they decide to vote from their own veNFT again?  The answer to these questions is the same:

**At any time, a normal veNFT can be withdrawn from its' deposited (m)veNFT, as long as it has *not* been deposited within the same epoch**.


#### Additional Notes
The AutoCompounder provided is only one solution for controlling a (m)veNFT.  If you have an alternative implementation you would like to see built out, please reach out to the team on Discord.