pragma solidity 0.8.13;

library VelodromeTimeLibrary {
    uint256 internal constant WEEK = 7 days;

    /// @dev Returns start of epoch based on current timestamp
    function epochStart(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % WEEK);
    }

    /// @dev Returns unrestricted voting window
    function epochEnd(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % WEEK) + WEEK - 1 hours;
    }
}
