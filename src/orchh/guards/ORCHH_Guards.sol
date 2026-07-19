// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

library ORCHH_Guards {
    error Reentrancy();

    function pre() internal pure {
        // placeholder for reentrancy lock
    }

    function post() internal pure {
        // placeholder for post-condition checks
    }
}
