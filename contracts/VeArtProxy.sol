pragma solidity 0.8.13;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {IVeArtProxy} from "./interfaces/IVeArtProxy.sol";

contract VeArtProxy is IVeArtProxy {
    function toString(uint256 _value) internal pure returns (string memory) {
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

    function _tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value
    ) external pure returns (string memory _output) {
        _output = "<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='black' /><text x='10' y='20' class='base'>";
        _output = string(
            abi.encodePacked(_output, "token ", toString(_tokenId), "</text><text x='10' y='40' class='base'>")
        );
        _output = string(
            abi.encodePacked(_output, "balanceOf ", toString(_balanceOf), "</text><text x='10' y='60' class='base'>")
        );
        _output = string(
            abi.encodePacked(_output, "locked_end ", toString(_locked_end), "</text><text x='10' y='80' class='base'>")
        );
        _output = string(abi.encodePacked(_output, "value ", toString(_value), "</text></svg>"));

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        "{'name': 'lock #",
                        toString(_tokenId),
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
