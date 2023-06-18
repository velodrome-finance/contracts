# VotingEscrow

## State Transitions

This table has functions along the rows, with the state required to call the function. Side effects and the output of the function are listed in the boxes. An empty box means that that state cannot be used as an input into that function. 

For example, if we take "Empty State" and `createLock`, this means that given no input, a call to `createManagedLockFor` will create a managed permanent nft. 

- Mint refers to the mint event. Burn refers to the burn event. Convert implies state transition from one state to another (e.g. normal to normal permanent).
- Increases/decreases amount refers to `LockedBalance.amount` being increased/decreased. 
- Extends locktime refers to `LockedBalance.end` being extended.
- Delegating involves modifying the `delegatee` field in the latest `tokenId`'s checkpoint, as well as incrementing the `delegatee`'s `delegatedBalance` field in the `delegatee`'s latest checkpoint.
- Dedelegating involves deleting the `delegatee` field in the latest `tokenId`'s checkpoint, as well as decrementing the prior `delegatee`'s `delegatedBalance` field in the `delegatee`'s latest checkpoint.
- Note that for `merge`, only the `to` NFT is allowed to be of type normal permanent.
- The last two rows refer to functions that exist in `RewardsDistributor`.

| Function | Empty State | Normal | Normal Permanent | Locked | Managed Permanent |
| --- | --- | --- | --- | --- | --- |
| `createLock` | - Mints normal. | | | | |
| `createLockFor` | - Mints normal. | | | | |
| `createManagedLockFor` | - Mints managed permanent.|  | | | |
| `depositManaged`  | | - Converts to locked. </br> - Increases managed amount. </br> - Increases (managed) delegatee balance. | - Dedelegates. </br> - Converts to locked. </br> - Increases managed amount. </br> - Increases (managed) delegatee balance. | | |
| `withdrawManaged` | | | | - Converts to normal. </br> - May increase amount (locked rewards). </br> - Extends locktime to maximum. </br> - Decreases managed balance. </br> - Decreases (managed) delegatee balance. | |
| `depositFor` | | - Increases amount. | - Increases amount. </br> - Increases delegatee balance. | | - Increases amount. </br> - Deposits into LMR. </br> - Increases delegatee balance. |
| `increaseAmount` | | - Increases amount. | - Increases amount. </br> - Increases delegatee balance. | | - Increases amount. </br> - Increases delegatee balance. |
| `increaseUnlockTime` | | - Extends locktime. | | | |
| `withdraw` | | - Burns normal. | | | |
| `merge` | | - Burns `from` normal. </br> - Increases `to` amount. | - Burns `from` normal. </br> - Increases `to` amount. </br> - Increases delegatee balance.  | | |
| `split` | | - Burns normal. </br> - Mints two normal. | - Dedelegates </br> - Burns normal. </br> - Mints two normal. | | |
| `lockPermanent` | | - Converts to normal permanent. | | | |
| `unlockPermanent` | | | - Dedelegates </br> - Converts to normal. | | |
| `delegate` | | | - Dedelegates. </br> - Delegates. | | - Dedelegates. </br> - Delegates. |
| `delegateBySig` | | | - Dedelegates. </br> - Delegates. | | - Dedelegates. </br> - Delegates. |
| `distributor.claim` | | - Collect rebases. | - Collect rebases. | | - Collect rebases. |
| `distributor.claimMany` | | - Collect rebases. | - Collect rebases. | | - Collect rebases. |

Note that when a normal nft calls functions like `depositFor`, `increaseAmount` etc, dedelegation still occurs but is skipped as the `tokenId` has no delegatee. 

## Valid States

LockedBalance has several valid states:
- `LockedBalance(amount, locktime, false)` when an nft is in normal state. `locktime` is at most `block.timestamp + MAXTIME`.
- `LockedBalance(amount, 0, true)`when an nft is in normal permanent.
- `LockedBalance(0, 0, true)` when a managed nft has no deposits.
- `LockedBalance(0, 0, false)` when an nft is burnt or in locked state.

A token's `LockedBalance` is updated whenever `amount`, `end` or `isPermanent` changes. 

UserPoint has several valid states:
- `UserPoint(slope, bias, ts, blk, 0)` when an nft is in normal state.
- `UserPoint(0, 0, ts, blk, permanent)` when an nft is in permanent state, with the value of `permanent` equal to the nft's `LockedBalance.amount`.
- `UserPoint(0, 0, ts, blk, 0)` when an nft is burnt.

A token's UserPoint is updated whenever `LockedBalance` changes. The global point is also updated at the 
same time. If there are multiple writes to a token's UserPoint or the GlobalPoint in one block, it will 
overwrite the prior point. Points retrieved from the user point history and global point history will always
have unique timestamps. For user points and global points, the first checkpoint at index 0 is always empty.
The first point is written to index 1. A UserPoints for a certain `tokenId` will always have a unique
timestamp and block number. The same is true for GlobalPoints.

(Voting) checkpoints have several valid states:
- `Checkpoint(ts, owner, 0, 0)` when an nft is not delegating (i.e. in normal / normal permanent / locked / managed permanent state and is not delegating) and has not been delegated to.
- `Checkpoint(ts, owner, delegatedBalance, 0)`when an nft is not delegating (i.e. in normal / normal permanent / locked / managed permanent state and is not delegating) but has been delegated to.
- `Checkpoint(ts, owner, 0, delegatee)` when an nft is delegating (permanent locks only) and has not received any delegations.
- `Checkpoint(ts, owner, delegatedBalance, delegatee)` when an nft is delegating (permanent locks only) and has received delegations.
- `Checkpoint(ts, 0, delegatedBalance, 0)` when an nft is burnt. `delegatedBalance` may be non-zero as this nft may still be delegated to. But it cannot vote as it has no owner. 

The initial voting checkpoint is created on the minting of a token. Subsequent voting checkpoints are
created whenever the `owner`, `delegatedBalance` or `delegatee` changes. Ownership can change from 
transfers, or from burn (e.g. merge, split, withdraw). `delegatee` can change from delegation / dedelegation.
`delegatedBalance` is updated on the delegatee whenever a delegation / dedelegation takes place. If there are 
multiple writes to a token's voting checkpoints in one block, it will overwrite the prior point. Points 
retrieved from the checkpoint history will always have unique timestamps. For voting checkpoints, the first 
checkpoint is written to index 0.