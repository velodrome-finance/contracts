# Optimism

To address the overflow issue present in `VotingEscrow.split()`, the following has been done. 

- A `RestrictedTeam` contract has been created. This contract contains a single function that allows it to call `VotingEscrow.setArtProxy()`.
- A `Splitter` contract has been created. This contract will act as a wrapper for the function calls to `split` on `VotingEscrow`. It will be the only contract with permissions to call `split()`. 

The following events will take place to ensure that the split issue cannot be abused by `VotingEscrow.team()`:
- The `RestrictedTeam` and `Splitter` contracts will be deployed. 
- The existing `VotingEscrow.team()` will call `toggleSplit(splitter, true)` on `VotingEscrow`, to give permissions to the `Splitter` to call split.
- The existing `VotingEscrow.team()` will call `setTeam(restrictedTeam)` on `VotingEscrow`, to transfer the team role to the `RestrictedTeam` contract. This prevents the previous `VotingEscrow.team()` from calling `setTeam` and `toggleSplit`. The only function that will still be callable via the `restrictedTeam` contract will be `setArtProxy()`. 

Note that the user experience for splitting will be different to before:
- Split will be called on the `Splitter` contract, which requires an approval to do so. 
- As the `Splitter` requires an approval, only the owner of a veNFT or an address that is approved for all can call `split` on `Splitter`. This deviates from the original `split` where a user that was either the owner, approved or approved for all could call `split`. 