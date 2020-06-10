pragma solidity >=0.4.24 <0.6.0;

import "../libs/Roles.sol";

contract SetterRole {
    using Roles for Roles.Role;

    event SetterAdded(address indexed account);
    event SetterRemoved(address indexed account);

    Roles.Role private _setters;

    constructor () internal {
        _addSetter(msg.sender);
    }

    modifier onlySetter() {
        require(isSetter(msg.sender));
        _;
    }

    function isSetter(address account) public view returns (bool) {
        return _setters.has(account);
    }

    function addSetter(address account) public onlySetter {
        _addSetter(account);
    }

    function _addSetter(address account) internal {
        _setters.add(account);
        emit SetterAdded(account);
    }

    function removeSetter(address account) public onlySetter {
        _removeSetter(account);
    }

    function _removeSetter(address account) internal {
        _setters.remove(account);
        emit SetterRemoved(account);
    }
}
