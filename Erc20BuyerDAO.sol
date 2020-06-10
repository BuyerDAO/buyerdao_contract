pragma solidity >=0.4.24 <0.6.0;

import "./interface/Erc20StdI.sol";
import "./libs/SafeMath.sol";
import "./base/SetterRole.sol";
import "./base/MinterRole.sol";
import "./interface/IUniswapV2Pair.sol";


contract Erc20BuyerDAO is Erc20StdI, MinterRole {
    using SafeMath for uint256;

    string constant public  name = "BuyerDAO";
    string constant public  symbol = "BDT";
    uint8  constant public  decimals = 18;
    address public team;
    uint public factor = 10 ** 18;
    uint public totalSupply = 0;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;// WETH
    uint8 public rateDecimal = 6;//support 2 ~ 9

    struct PairRate {
        uint priceCumulativeLast;
        uint blockTimestampLast;
        uint rate;
    }

    mapping(address => PairRate) public pairRates;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    event Mint(address indexed beneficiary, uint cost, uint amount);
    event Withdraw(address indexed holder, uint amount, uint divs);
    event SetPair(address indexed token, address tokenEthPair);


    constructor() public{
        team = msg.sender;
    }

    function() payable external {

    }

    function mint(address _beneficiary, uint _txAmount, address _pairAddress) public onlyMinter {
        uint _miningRevenue = 0;
        if (_txAmount > 0) {
            //non-ETH，Convert to ETH exchange rate value.
            if (_pairAddress != address(0)) {
                _txAmount = _txAmount * getRealTimeTokenRate(_pairAddress) / (10 ** uint(rateDecimal));
            }

            if (factor > 0) {
                _miningRevenue = _txAmount * factor / (10 ** 18);
                factor = factor * 9999999 / 10000000;
            }

            if (_miningRevenue > 0) {
                balances[_beneficiary] = balances[_beneficiary].add(_miningRevenue);
                balances[team] = balances[team].add(_miningRevenue);
                totalSupply = _miningRevenue.mul(2).add(totalSupply);

                emit Transfer(address(0), _beneficiary, _miningRevenue);
                emit Transfer(address(0), team, _miningRevenue);
            }
        }

        emit Mint(_beneficiary, _txAmount, _miningRevenue);
    }

    /**
     * @dev Burns the specified amount of tokens and exchange for the corresponding amount of ether.
     * @param value The amount of token to be burned.
     */
    function withdraw(uint value) public returns (uint divs){
        require(value > 0 && balances[msg.sender] >= value);
        require(address(this).balance > 0);

        divs = address(this).balance * value / totalSupply;
        _burn(msg.sender, value);
        msg.sender.transfer(divs);

        emit Withdraw(msg.sender, value, divs);
    }

    /**
     * @dev Get real-time token rate, this will update the rate.
     */
    function getRealTimeTokenRate(address _pairAddress) internal returns (uint rate) {
        PairRate storage pairRate = pairRates[_pairAddress];
        IUniswapV2Pair ethTokenPair = IUniswapV2Pair(_pairAddress);

        uint _blockTimestampLast1 = pairRate.blockTimestampLast;
        uint _priceCumulativeLast1 = pairRate.priceCumulativeLast;
        (, , uint _blockTimestampLast2) = ethTokenPair.getReserves();
        uint _priceCumulativeLast2;

        if (_blockTimestampLast2 > _blockTimestampLast1) {
            _priceCumulativeLast2 = ethTokenPair.token0() == WETH ? ethTokenPair.price1CumulativeLast() : ethTokenPair.price0CumulativeLast();
            pairRate.rate = (_priceCumulativeLast2 - _priceCumulativeLast1) / (_blockTimestampLast2 - _blockTimestampLast1) * (10 ** uint(rateDecimal)) / (2 ** 112);
            pairRate.priceCumulativeLast = _priceCumulativeLast2;
            pairRate.blockTimestampLast = _blockTimestampLast2;
        }

        rate = pairRate.rate;
    }


    /**
    * @dev Setup token and decentralized exchange
    **/
    function setTokenAndEthPair(address _tokenEthPairAddress) public onlySetter returns (uint rate){
        IUniswapV2Pair _tokenEthPair = IUniswapV2Pair(_tokenEthPairAddress);
        address _tokenAddress = _tokenEthPair.token0() == WETH ? _tokenEthPair.token1() : _tokenEthPair.token0();

        require(_tokenAddress != address(0), "_tokenAddress is invalid.");
        require(_tokenEthPairAddress != address(0), "_ethTokenPairAddress is invalid.");

        PairRate storage pairRate = pairRates[_tokenEthPairAddress];

        uint _ethReserve = Erc20StdI(WETH).balanceOf(_tokenEthPairAddress);
        uint _tokenReserve = Erc20StdI(_tokenAddress).balanceOf(_tokenEthPairAddress);

        require(_ethReserve > 0 && _tokenReserve > 0, "_ethTokenPairAddress is invalid");

        (,, pairRate.blockTimestampLast) = _tokenEthPair.getReserves();
        pairRate.priceCumulativeLast = _tokenAddress < WETH ? _tokenEthPair.price0CumulativeLast() : _tokenEthPair.price1CumulativeLast();
        pairRate.rate = _ethReserve * (10 ** uint(rateDecimal)) / _tokenReserve;

        emit SetPair(_tokenAddress, _tokenEthPairAddress);

        return pairRate.rate;
    }

    /**
    * Setting rate decimal
    **/
    function setRateDecimal(uint8 _decimal) public onlySetter {
        require(_decimal >= 2 && _decimal < 10, "decimal value is too small.");
        rateDecimal = _decimal;
    }

    function setTeamAddr(address _team) public onlySetter {
        require(_team != address(0), "_team is invalid.");
        team = _team;
    }

    /**************ERC20 Function*****************/

    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]);
        require(_to != address(0));
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(balances[_from] >= _value && allowed[_from][msg.sender] >= _value);
        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    /**
     * @dev Internal function that burns an amount of the token of a given
     * account.
     * @param account The account whose tokens will be burnt.
     * @param value The amount that will be burnt.
     */
    function _burn(address account, uint256 value) internal {
        require(account != address(0));

        totalSupply = totalSupply.sub(value);
        balances[account] = balances[account].sub(value);
        emit Transfer(account, address(0), value);
    }
}
