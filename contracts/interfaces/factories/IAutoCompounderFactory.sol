pragma solidity ^0.8.0;

interface IAutoCompounderFactory {
    error AmountOutOfAcceptableRange();
    error AmountSame();
    error NotTeam();
    error TokenIdNotApproved();
    error TokenIdNotManaged();
    error TokenIdZero();

    event CreateAutoCompounder(address indexed _from, address indexed _admin, address indexed _autoCompounder);
    event SetRewardAmount(uint256 _rewardAmount);

    function rewardAmount() external view returns (uint256);

    function createAutoCompounder(address _admin, uint256 _tokenId) external returns (address autoCompounder);

    function setRewardAmount(uint256 _rewardAmount) external;
}
