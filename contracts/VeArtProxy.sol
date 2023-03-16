pragma solidity 0.8.13;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {IVeArtProxy} from "./interfaces/IVeArtProxy.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

contract VeArtProxy is IVeArtProxy {
    IVotingEscrow public immutable ve;

    constructor(address _ve) public {
        ve = IVotingEscrow(_ve);
    }

    function _toString(uint256 _value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }

    function tokenURI(uint256 _tokenId) external view returns (string memory _output) {
        uint256 _balanceOf = ve.balanceOfNFTAt(_tokenId, block.timestamp);
        IVotingEscrow.LockedBalance memory _locked = ve.locked(_tokenId);
        uint256 _lockedEnd = _locked.end;
        uint256 _lockedAmount = uint256(int256(_locked.amount));

        _output = "<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='black' /><text x='10' y='20' class='base'>";
        _output = string(
            abi.encodePacked(_output, "token ", _toString(_tokenId), "</text><text x='10' y='40' class='base'>")
        );
        _output = string(
            abi.encodePacked(_output, "balanceOf ", _toString(_balanceOf), "</text><text x='10' y='60' class='base'>")
        );
        _output = string(
            abi.encodePacked(_output, "locked_end ", _toString(_lockedEnd), "</text><text x='10' y='80' class='base'>")
        );
        _output = string(abi.encodePacked(_output, "value ", _toString(_lockedAmount), "</text></svg>"));

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        "{'name': 'lock #",
                        _toString(_tokenId),
                        "', 'description': 'Velodrome locks, can be used to boost gauge yields, vote on token emission, and receive bribes', 'image': 'data:image/svg+xml;base64,",
                        Base64.encode(bytes(_output)),
                        "'}"
                    )
                )
            )
        );
        _output = string(abi.encodePacked("data:application/json;base64,", json));
    }
}
