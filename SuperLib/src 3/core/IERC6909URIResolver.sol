// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IERC6909URIResolver
/// @notice External resolver interface
interface IERC6909URIResolver {
    function resolveURI(uint256 id) external view returns (string memory);
}
