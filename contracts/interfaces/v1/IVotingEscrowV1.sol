// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVotingEscrowV1 {
    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    function getApproved(uint256 _tokenId) external view returns (address);

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external returns (bool);

    function locked__end(uint256 _tokenId) external view returns (uint256 _locked);

    function locked(uint256 _tokenId) external view returns (int128 _amount, uint256 _end);

    function ownerOf(uint256 _tokenId) external view returns (address _owner);

    function increase_amount(uint256 _tokenId, uint256 _amount) external;

    function increase_unlock_time(uint256 _tokenId, uint256 _duration) external;

    function create_lock(uint256 _amount, uint256 _end) external returns (uint256 tokenId);

    function create_lock_for(uint256 _amount, uint256 _end, address _to) external returns (uint256 tokenId);

    function approve(address who, uint256 tokenId) external;

    function balanceOfNFT(uint256) external view returns (uint256 amount);

    function user_point_epoch(uint256) external view returns (uint256);

    function user_point_history(uint256, uint256) external view returns (Point memory);

    function merge(uint256 _from, uint256 _to) external;

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external;
}
