// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVotingRewardsFactory} from "./interfaces/IVotingRewardsFactory.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IGaugeFactory} from "./interfaces/IGaugeFactory.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IReward} from "./interfaces/IReward.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IFactoryRegistry} from "./interfaces/IFactoryRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VelodromeTimeLibrary} from "./libraries/VelodromeTimeLibrary.sol";

contract Voter is IVoter, Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /// @notice The ve token that governs these contracts
    address public immutable ve;
    /// @notice Factory registry for valid pair / gauge / rewards factories
    address public immutable factoryRegistry;
    /// @notice Base token of ve contract
    address internal immutable rewardToken;
    /// @notice Rewards are released over 7 days
    uint256 internal constant DURATION = 7 days;
    address public minter;
    /// @notice Standard OZ IGovernor using ve for vote weights.
    address public governor;
    /// @notice Custom Epoch Governor using ve for vote weights.
    address public epochGovernor;
    /// @notice credibly neutral party similar to Curve's Emergency DAO
    address public emergencyCouncil;

    /// @dev Total Voting Weights
    uint256 public totalWeight;

    /// @dev All pools viable for incentives
    address[] public pools;
    /// @dev Pool => Gauge
    mapping(address => address) public gauges;
    /// @dev Gauge => Pool
    mapping(address => address) public poolForGauge;
    /// @dev Gauge => Fees Voting Reward
    mapping(address => address) public gaugeToFees;
    /// @dev Gauge => Bribes Voting Reward
    mapping(address => address) public gaugeToBribe;
    /// @dev Pool => Weights
    mapping(address => uint256) public weights;
    /// @dev NFT => Pool => Votes
    mapping(uint256 => mapping(address => uint256)) public votes;
    /// @dev NFT => List of pools voted for by NFT
    mapping(uint256 => address[]) public poolVote;
    /// @dev NFT => Total voting weight of NFT
    mapping(uint256 => uint256) public usedWeights;
    /// @dev Nft => Timestamp of last vote (ensures single vote per epoch)
    mapping(uint256 => uint256) public lastVoted;
    /// @dev Address => Gauge
    mapping(address => bool) public isGauge;
    /// @dev Token => Whitelisted status
    mapping(address => bool) public isWhitelistedToken;
    /// @dev TokenId => Whitelisted status
    mapping(uint256 => bool) public isWhitelistedNFT;
    /// @dev Gauge => Liveness status
    mapping(address => bool) public isAlive;

    constructor(address _ve, address _factoryRegistry) {
        ve = _ve;
        factoryRegistry = _factoryRegistry;
        rewardToken = IVotingEscrow(_ve).token();
        minter = msg.sender;
        governor = msg.sender;
        epochGovernor = msg.sender;
        emergencyCouncil = msg.sender;
    }

    modifier onlyNewEpoch(uint256 _tokenId) {
        // ensure new epoch since last vote
        require((block.timestamp / DURATION) * DURATION > lastVoted[_tokenId], "Voter: already voted this epoch");
        _;
    }

    function epochStart(uint256 _timestamp) external pure returns (uint256) {
        return VelodromeTimeLibrary.epochStart(_timestamp);
    }

    function epochEnd(uint256 _timestamp) external pure returns (uint256) {
        return VelodromeTimeLibrary.epochEnd(_timestamp);
    }

    /// @dev requires initialization with at least rewardToken
    function initialize(address[] memory _tokens, address _minter) external {
        require(_msgSender() == minter);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _whitelistToken(_tokens[i]);
        }
        minter = _minter;
    }

    /// @inheritdoc IVoter
    function setGovernor(address _governor) public {
        require(_msgSender() == governor, "Voter: not governor");
        governor = _governor;
    }

    /// @inheritdoc IVoter
    function setEpochGovernor(address _epochGovernor) public {
        require(_msgSender() == governor, "Voter: not governor");
        epochGovernor = _epochGovernor;
    }

    /// @inheritdoc IVoter
    function setEmergencyCouncil(address _council) public {
        require(_msgSender() == emergencyCouncil, "Voter: not emergency council");
        emergencyCouncil = _council;
    }

    /// @inheritdoc IVoter
    function reset(uint256 _tokenId) external onlyNewEpoch(_tokenId) nonReentrant {
        require(IVotingEscrow(ve).isApprovedOrOwner(msg.sender, _tokenId));
        _reset(_tokenId);
        IVotingEscrow(ve).abstain(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                _updateFor(gauges[_pool]);
                weights[_pool] -= _votes;
                votes[_tokenId][_pool] -= _votes;
                IReward(gaugeToFees[gauges[_pool]])._withdraw(uint256(_votes), _tokenId);
                IReward(gaugeToBribe[gauges[_pool]])._withdraw(uint256(_votes), _tokenId);
                _totalWeight += _votes;
                emit Abstained(_tokenId, _votes);
            }
        }
        totalWeight -= uint256(_totalWeight);
        usedWeights[_tokenId] = 0;
        delete poolVote[_tokenId];
    }

    /// @inheritdoc IVoter
    function poke(uint256 _tokenId) external {
        address[] memory _poolVote = poolVote[_tokenId];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint256 i = 0; i < _poolCnt; i++) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
    }

    function _vote(
        uint256 _tokenId,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal nonReentrant {
        _reset(_tokenId);
        uint256 _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(ve).balanceOfNFT(_tokenId);
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge]) {
                uint256 _poolWeight = (_weights[i] * _weight) / _totalVoteWeight;
                require(votes[_tokenId][_pool] == 0);
                require(_poolWeight != 0);
                _updateFor(_gauge);

                poolVote[_tokenId].push(_pool);

                weights[_pool] += _poolWeight;
                votes[_tokenId][_pool] += _poolWeight;
                IReward(gaugeToFees[_gauge])._deposit(uint256(_poolWeight), _tokenId);
                IReward(gaugeToBribe[_gauge])._deposit(uint256(_poolWeight), _tokenId);
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(_msgSender(), _tokenId, _poolWeight);
            }
        }
        if (_usedWeight > 0) IVotingEscrow(ve).voting(_tokenId);
        totalWeight += uint256(_totalWeight);
        usedWeights[_tokenId] = uint256(_usedWeight);
    }

    /// @inheritdoc IVoter
    function vote(
        uint256 _tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(_tokenId) {
        address _sender = _msgSender();
        require(IVotingEscrow(ve).isApprovedOrOwner(_sender, _tokenId));
        require(_poolVote.length == _weights.length);
        require(!IVotingEscrow(ve).deactivated(_tokenId), "Voter: inactive managed nft");
        uint256 _timestamp = block.timestamp;
        if (_timestamp > VelodromeTimeLibrary.epochEnd(_timestamp)) {
            require(isWhitelistedNFT[_tokenId], "Voter: nft not whitelisted");
        }
        lastVoted[_tokenId] = _timestamp;
        _vote(_tokenId, _poolVote, _weights);
    }

    /// @inheritdoc IVoter
    function whitelistToken(address _token) external {
        require(_msgSender() == governor, "Voter: not governor");
        _whitelistToken(_token);
    }

    function _whitelistToken(address _token) internal {
        require(!isWhitelistedToken[_token], "Voter: token already whitelisted");
        isWhitelistedToken[_token] = true;
        emit WhitelistToken(_msgSender(), _token);
    }

    /// @inheritdoc IVoter
    function whitelistNFT(uint256 _tokenId) external {
        address _sender = _msgSender();
        require(_sender == governor, "Voter: not governor");
        require(!isWhitelistedNFT[_tokenId], "Voter: nft already whitelisted");
        isWhitelistedNFT[_tokenId] = true;
        emit WhitelistNFT(_sender, _tokenId);
    }

    /// @inheritdoc IVoter
    function createGauge(
        address _pairFactory,
        address _votingRewardsFactory,
        address _gaugeFactory,
        address _pool
    ) external nonReentrant returns (address) {
        address sender = _msgSender();
        require(gauges[_pool] == address(0x0), "Voter: gauge already exists");
        address[] memory rewards = new address[](2);
        bool isPair = IPairFactory(_pairFactory).isPair(_pool);
        address tokenA;
        address tokenB;

        if (isPair) {
            (tokenA, tokenB) = IPair(_pool).tokens();
            rewards[0] = tokenA;
            rewards[1] = tokenB;
        }

        if (sender != governor) {
            require(isPair, "Voter: not a pool");
            require(isWhitelistedToken[tokenA] && isWhitelistedToken[tokenB], "Voter: not whitelisted");
        }

        require(
            IFactoryRegistry(factoryRegistry).isApproved(_pairFactory, _votingRewardsFactory, _gaugeFactory),
            "Voter: factory path not approved"
        );
        (address _feeVotingReward, address _bribeVotingReward) = IVotingRewardsFactory(_votingRewardsFactory)
            .createRewards(rewards);

        address _gauge = IGaugeFactory(_gaugeFactory).createGauge(_pool, _feeVotingReward, rewardToken, isPair);

        IERC20(rewardToken).approve(_gauge, type(uint256).max);
        gaugeToFees[_gauge] = _feeVotingReward;
        gaugeToBribe[_gauge] = _bribeVotingReward;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        _updateFor(_gauge);
        pools.push(_pool);

        // TODO: add factories as args
        emit GaugeCreated(_gauge, sender, _feeVotingReward, _bribeVotingReward, _pool);
        return _gauge;
    }

    /// @inheritdoc IVoter
    function killGauge(address _gauge) external {
        require(_msgSender() == emergencyCouncil, "Voter: not emergency council");
        require(isAlive[_gauge], "Voter: gauge already dead");
        isAlive[_gauge] = false;
        claimable[_gauge] = 0;
        emit GaugeKilled(_gauge);
    }

    /// @inheritdoc IVoter
    function reviveGauge(address _gauge) external {
        require(_msgSender() == emergencyCouncil, "Voter: not emergency council");
        require(!isAlive[_gauge], "Voter: gauge already alive");
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    function length() external view returns (uint256) {
        return pools.length;
    }

    uint256 internal index;
    mapping(address => uint256) internal supplyIndex;
    mapping(address => uint256) public claimable;

    /// @inheritdoc IVoter
    function notifyRewardAmount(uint256 _amount) external {
        address sender = _msgSender();
        require(sender == minter, "Voter: only minter can deposit reward");
        IERC20(rewardToken).safeTransferFrom(sender, address(this), _amount); // transfer the distribution in
        uint256 _ratio = (_amount * 1e18) / totalWeight; // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index += _ratio;
        }
        emit NotifyReward(sender, rewardToken, _amount);
    }

    /// @inheritdoc IVoter
    function updateFor(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            _updateFor(_gauges[i]);
        }
    }

    /// @inheritdoc IVoter
    function updateFor(uint256 start, uint256 end) external {
        for (uint256 i = start; i < end; i++) {
            _updateFor(gauges[pools[i]]);
        }
    }

    /// @inheritdoc IVoter
    function updateFor(address _gauge) external {
        _updateFor(_gauge);
    }

    function _updateFor(address _gauge) internal {
        address _pool = poolForGauge[_gauge];
        uint256 _supplied = weights[_pool];
        if (_supplied > 0) {
            uint256 _supplyIndex = supplyIndex[_gauge];
            uint256 _index = index; // get global index0 for accumulated distribution
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint256 _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0) {
                uint256 _share = (uint256(_supplied) * _delta) / 1e18; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    /// @inheritdoc IVoter
    function claimRewards(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(_msgSender());
        }
    }

    /// @inheritdoc IVoter
    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        require(IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId));
        for (uint256 i = 0; i < _bribes.length; i++) {
            IReward(_bribes[i]).getReward(_tokenId, _tokens[i]);
        }
    }

    /// @inheritdoc IVoter
    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        require(IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId));
        for (uint256 i = 0; i < _fees.length; i++) {
            IReward(_fees[i]).getReward(_tokenId, _tokens[i]);
        }
    }

    function distributeFees(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            if (IGauge(_gauges[i]).isForPair()) {
                IGauge(_gauges[i]).claimFees();
            }
        }
    }

    /// @inheritdoc IVoter
    function distribute(address _gauge) public nonReentrant {
        IMinter(minter).update_period();
        _updateFor(_gauge); // should set claimable to 0 if killed
        uint256 _claimable = claimable[_gauge];
        if (_claimable > IGauge(_gauge).left() && _claimable / DURATION > 0) {
            claimable[_gauge] = 0;
            IGauge(_gauge).notifyRewardAmount(_claimable);
            emit DistributeReward(_msgSender(), _gauge, _claimable);
        }
    }

    /// @inheritdoc IVoter
    function distribute(uint256 _start, uint256 _finish) public {
        for (uint256 x = _start; x < _finish; x++) {
            distribute(gauges[pools[x]]);
        }
    }

    /// @inheritdoc IVoter
    function distribute(address[] memory _gauges) external {
        for (uint256 x = 0; x < _gauges.length; x++) {
            distribute(_gauges[x]);
        }
    }
}
