// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (governance/IGovernor.sol)

pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @dev Taken from OpenZeppelin's IGovernor. Excludes `cancel`.
 *
 * NOTE: Event parameters lack the `indexed` keyword for compatibility with GovernorBravo events.
 * Making event parameters `indexed` affects how events are decoded, potentially breaking existing indexers.
 */
interface IGovernor is IERC165, IERC6372 {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued, // unused, required for backwards compatibility
        Expired,
        Executed
    }

    /**
     * @dev Empty proposal or a mismatch between the parameters length for a proposal call.
     */
    error GovernorInvalidProposalLength(uint256 _targets, uint256 _calldatas, uint256 _values);

    /**
     * @dev The vote was already cast.
     */
    error GovernorAlreadyCastVote(uint256 _tokenId);

    /**
     * @dev Token deposits are disabled in this contract.
     */
    error GovernorDisabledDeposit();

    /**
     * @dev The `account` is not a proposer.
     */
    error GovernorOnlyProposer(address _account);

    /**
     * @dev The `account` is not the governance executor.
     */
    error GovernorOnlyExecutor(address _account);

    /**
     * @dev The `proposalId` doesn't exist.
     */
    error GovernorNonexistentProposal(uint256 _proposalId);

    /**
     * @dev The current state of a proposal is not the required for performing an operation.
     * The `expectedStates` is a bitmap with the bits enabled for each ProposalState enum position
     * counting from right to left.
     *
     * NOTE: If `expectedState` is `bytes32(0)`, the proposal is expected to not be in any state (i.e. not exist).
     * This is the case when a proposal that is expected to be unset is already initiated (the proposal is duplicated).
     *
     * See {Governor-_encodeStateBitmap}.
     */
    error GovernorUnexpectedProposalState(uint256 _proposalId, ProposalState _current, bytes32 _expectedStates);

    /**
     * @dev The voting period set is not a valid period.
     */
    error GovernorInvalidVotingPeriod(uint256 _votingPeriod);

    /**
     * @dev The `proposer` does not have the required votes to create a proposal.
     */
    error GovernorInsufficientProposerVotes(address _proposer, uint256 _votes, uint256 _threshold);

    /**
     * @dev The `proposer` is not allowed to create a proposal.
     */
    error GovernorRestrictedProposer(address _proposer);

    /**
     * @dev The vote type used is not valid for the corresponding counting module.
     */
    error GovernorInvalidVoteType();

    /**
     * @dev The provided params buffer is not supported by the counting module.
     */
    error GovernorInvalidVoteParams();

    /**
     * @dev Queue operation is not implemented for this governor. Execute should be called directly.
     */
    error GovernorQueueNotImplemented();

    /**
     * @dev The provided signature is not valid for the expected `voter`.
     * If the `voter` is a contract, the signature is not valid using {IERC1271-isValidSignature}.
     */
    error GovernorInvalidSignature(address _voter);

    /**
     * @dev The target is not minter or calldata is not the nudge function
     */
    error GovernorInvalidTargetOrCalldata(address _target, bytes4 _callData);

    /**
     * @dev Not enough voting power to comment
     */
    error GovernorInsufficientVotingPower(uint256 _weight, uint256 _minimumWeight);

    /**
     * @dev Emitted when a proposal is created.
     */
    event ProposalCreated(
        uint256 _proposalId,
        address _proposer,
        address[] _targets,
        uint256[] _values,
        string[] _signatures,
        bytes[] _calldatas,
        uint256 _voteStart,
        uint256 _voteEnd,
        string _description
    );

    /**
     * @dev Emitted when a proposal is queued.
     */
    event ProposalQueued(uint256 _proposalId, uint256 _etaSeconds);

    /**
     * @dev Emitted when a proposal is executed.
     */
    event ProposalExecuted(uint256 _proposalId);

    /**
     * @dev Emitted when a vote is cast without params.
     *
     * Note: `support` values should be seen as buckets. Their interpretation depends on the voting module used.
     */
    event VoteCast(
        address indexed _voter,
        uint256 indexed _tokenId,
        uint256 _proposalId,
        uint8 _support,
        uint256 _weight,
        string _reason
    );

    /**
     * @dev Emitted when a vote is cast with params.
     *
     * Note: `support` values should be seen as buckets. Their interpretation depends on the voting module used.
     * `params` are additional encoded parameters. Their interpretation  also depends on the voting module used.
     */
    event VoteCastWithParams(
        address indexed _voter,
        uint256 indexed _tokenId,
        uint256 _proposalId,
        uint8 _support,
        uint256 _weight,
        string _reason,
        bytes _params
    );

    /**
     * @dev Emitted when a comment is cast on a certain proposal.
     */
    event Comment(uint256 indexed _proposalId, address indexed _account, uint256 indexed _tokenId, string _comment);

    /**
     * @notice module:core
     * @dev Name of the governor instance (used in building the EIP-712 domain separator).
     */
    function name() external view returns (string memory);

    /**
     * @notice module:core
     * @dev Version of the governor instance (used in building the EIP-712 domain separator). Default: "1"
     */
    function version() external view returns (string memory);

    /**
     * @notice module:voting
     * @dev A description of the possible `support` values for {castVote} and the way these votes are counted, meant to
     * be consumed by UIs to show correct vote options and interpret the results. The string is a URL-encoded sequence of
     * key-value pairs that each describe one aspect, for example `support=bravo&quorum=for,abstain`.
     *
     * There are 2 standard keys: `support` and `quorum`.
     *
     * - `support=bravo` refers to the vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=bravo` means that only For votes are counted towards quorum.
     * - `quorum=for,abstain` means that both For and Abstain votes are counted towards quorum.
     *
     * If a counting module makes use of encoded `params`, it should  include this under a `params` key with a unique
     * name that describes the behavior. For example:
     *
     * - `params=fractional` might refer to a scheme where votes are divided fractionally between for/against/abstain.
     * - `params=erc721` might refer to a scheme where specific NFTs are delegated to vote.
     *
     * NOTE: The string can be decoded by the standard
     * https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams[`URLSearchParams`]
     * JavaScript class.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() external view returns (string memory);

    /**
     * @notice module:core
     * @dev Hashing function used to (re)build the proposal id from the proposal details..
     */
    function hashProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) external pure returns (uint256);

    /**
     * @notice module:core
     * @dev Current state of a proposal, following Compound's convention
     */
    function state(uint256 _proposalId) external view returns (ProposalState);

    /**
     * @notice module:core
     * @dev The number of votes required in order for a voter to become a proposer.
     */
    function proposalThreshold() external view returns (uint256);

    /**
     * @notice module:core
     * @dev Timepoint used to retrieve user's votes and quorum. If using block number (as per Compound's Comp), the
     * snapshot is performed at the end of this block. Hence, voting for this proposal starts at the beginning of the
     * following block.
     */
    function proposalSnapshot(uint256 _proposalId) external view returns (uint256);

    /**
     * @notice module:core
     * @dev Timepoint at which votes close. If using block number, votes close at the end of this block, so it is
     * possible to cast a vote during this block.
     */
    function proposalDeadline(uint256 _proposalId) external view returns (uint256);

    /**
     * @notice module:core
     * @dev The account that created a proposal.
     */
    function proposalProposer(uint256 _proposalId) external view returns (address);

    /**
     * @notice module:user-config
     * @dev Delay, between the proposal is created and the vote starts. The unit this duration is expressed in depends
     * on the clock (see ERC-6372) this contract uses.
     *
     * This can be increased to leave time for users to buy voting power, or delegate it, before the voting of a
     * proposal starts.
     *
     * NOTE: While this interface returns a uint256, timepoints are stored as uint48 following the ERC-6372 clock type.
     * Consequently this value must fit in a uint48 (when added to the current clock). See {IERC6372-clock}.
     */
    function votingDelay() external view returns (uint256);

    /**
     * @notice module:user-config
     * @dev Delay between the vote start and vote end. The unit this duration is expressed in depends on the clock
     * (see ERC-6372) this contract uses.
     *
     * NOTE: The {votingDelay} can delay the start of the vote. This must be considered when setting the voting
     * duration compared to the voting delay.
     *
     * NOTE: This value is stored when the proposal is submitted so that possible changes to the value do not affect
     * proposals that have already been submitted. The type used to save it is a uint32. Consequently, while this
     * interface returns a uint256, the value it returns should fit in a uint32.
     */
    function votingPeriod() external view returns (uint256);

    /**
     * @notice module:user-config
     * @dev Minimum number of cast voted required for a proposal to be successful.
     *
     * NOTE: The `timepoint` parameter corresponds to the snapshot used for counting vote. This allows to scale the
     * quorum depending on values such as the totalSupply of a token at this timepoint (see {ERC20Votes}).
     */
    function quorum(uint256 _timepoint) external view returns (uint256);

    /**
     * @notice module:reputation
     * @dev Voting power of an `tokenId` at a specific `timepoint`.
     *
     * Note: this can be implemented in a number of ways, for example by reading the delegated balance from one (or
     * multiple), {ERC20Votes} tokens.
     */
    function getVotes(address _account, uint256 _tokenId, uint256 _timepoint) external view returns (uint256);

    /**
     * @notice module:reputation
     * @dev Voting power of an `tokenId` at a specific `timepoint` given additional encoded parameters.
     */
    function getVotesWithParams(address _account, uint256 _tokenId, uint256 _timepoint, bytes memory _params)
        external
        view
        returns (uint256);

    /**
     * @notice module:voting
     * @dev Returns whether `tokenId` has cast a vote on `proposalId`.
     */
    function hasVoted(uint256 _proposalId, uint256 _tokenId) external view returns (bool);

    /**
     * @dev Create a new proposal. Vote start after a delay specified by {IGovernor-votingDelay} and lasts for a
     * duration specified by {IGovernor-votingPeriod}.
     *
     * Emits a {ProposalCreated} event.
     *
     * NOTE: The state of the Governor and `targets` may change between the proposal creation and its execution.
     * This may be the result of third party actions on the targeted contracts, or other governor proposals.
     * For example, the balance of this contract could be updated or its access control permissions may be modified,
     * possibly compromising the proposal's ability to execute successfully (e.g. the governor doesn't have enough
     * value to cover a proposal with multiple transfers).
     */
    function propose(
        uint256 _tokenId,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) external returns (uint256 _proposalId);

    /**
     * @dev Execute a successful proposal. This requires the quorum to be reached, the vote to be successful, and the
     * deadline to be reached. Depending on the governor it might also be required that the proposal was queued and
     * that some delay passed.
     *
     * Emits a {ProposalExecuted} event.
     *
     * NOTE: Some modules can modify the requirements for execution, for example by adding an additional timelock.
     */
    function execute(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) external payable returns (uint256 _proposalId);

    /**
     * @dev Cast a vote
     *
     * Emits a {VoteCast} event.
     */
    function castVote(uint256 _proposalId, uint256 _tokenId, uint8 _support) external returns (uint256 _balance);

    /**
     * @dev Cast a vote with a reason
     *
     * Emits a {VoteCast} event.
     */
    function castVoteWithReason(uint256 _proposalId, uint256 _tokenId, uint8 _support, string calldata _reason)
        external
        returns (uint256 _balance);

    /**
     * @dev Cast a vote with a reason and additional encoded parameters
     *
     * Emits a {VoteCast} or {VoteCastWithParams} event depending on the length of params.
     */
    function castVoteWithReasonAndParams(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        string calldata _reason,
        bytes memory _params
    ) external returns (uint256 _balance);

    /**
     * @dev Cast a vote using the voter's signature, including ERC-1271 signature support.
     *
     * Emits a {VoteCast} event.
     */
    function castVoteBySig(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        address _voter,
        bytes memory _signature
    ) external returns (uint256 _balance);

    /**
     * @dev Cast a vote with a reason and additional encoded parameters using the voter's signature,
     * including ERC-1271 signature support.
     *
     * Emits a {VoteCast} or {VoteCastWithParams} event depending on the length of params.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 _proposalId,
        uint256 _tokenId,
        uint8 _support,
        address _voter,
        string calldata _reason,
        bytes memory _params,
        bytes memory _signature
    ) external returns (uint256 _balance);
}
