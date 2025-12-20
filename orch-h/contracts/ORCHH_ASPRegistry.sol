// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ORCH-H ASP Registry (Chain-Local)
contract ORCHH_ASPRegistry {
    error InvalidASPByte();
    error ZeroAddress();
    error OutOfDomain();
    error WrongExecutor();

    uint8 internal constant LSP_START  = 0x20;
    uint8 internal constant LSP_END    = 0x27;
    uint8 internal constant ASPA_START = 0x28;
    uint8 internal constant ASPA_END   = 0x2F;
    uint8 internal constant XSP_START  = 0x30;
    uint8 internal constant XSP_END    = 0x37;
    uint8 internal constant GSP_START  = 0x38;
    uint8 internal constant GSP_END    = 0x3F;

    mapping(uint8 => address) internal asp;

    address public immutable admin;
    address public immutable executor;
    uint256 public immutable chainId;

    constructor(address _admin, address _executor) {
        if (_admin == address(0) || _executor == address(0)) revert ZeroAddress();
        admin = _admin;
        executor = _executor;
        chainId = block.chainid;
    }

    function setASP(uint8 key, address target) external {
        if (msg.sender != admin) revert InvalidASPByte();
        if (target == address(0)) revert ZeroAddress();

        if (
            !(
                (key >= LSP_START  && key <= LSP_END)  ||
                (key >= ASPA_START && key <= ASPA_END) ||
                (key >= XSP_START  && key <= XSP_END)  ||
                (key >= GSP_START  && key <= GSP_END)
            )
        ) revert OutOfDomain();

        asp[key] = target;
    }

    function resolve(uint8 key) external view returns (address target) {
        target = asp[key];
        if (target == address(0)) revert InvalidASPByte();
    }

    function resolveForExec(uint8 key) external view returns (address target) {
        if (msg.sender != executor) revert WrongExecutor();
        target = asp[key];
        if (target == address(0)) revert InvalidASPByte();
    }
}
