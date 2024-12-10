pragma solidity =0.6.6;

// 导入必要的库和接口
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

// 导入Uniswap V1工厂接口
import './interfaces/IUniswapV2Migrator.sol';
import './interfaces/V1/IUniswapV1Factory.sol';
// 导入Uniswap V1交易接口
import './interfaces/V1/IUniswapV1Exchange.sol';
// 导入Uniswap V2路由器接口
import './interfaces/IUniswapV2Router01.sol';
// 导入ERC20接口
import './interfaces/IERC20.sol';

// 定义一个合约UniswapV2Migrator实现IUniswapV2Migrator接口
//迁移，似乎是兼容v1
contract UniswapV2Migrator is IUniswapV2Migrator {
    // 声明一个不可变的Uniswap V1工厂变量
    IUniswapV1Factory immutable factoryV1;
    // 声明一个不可变的Uniswap V2路由器变量
    IUniswapV2Router01 immutable router;

    // 构造函数，传入V1工厂和V2路由器的地址
    constructor(address _factoryV1, address _router) public {
        // 初始化V1工厂
        factoryV1 = IUniswapV1Factory(_factoryV1);
        // 初始化V2路由器
        router = IUniswapV2Router01(_router);
    }

    // 合约需要接受来自任何V1交易所和路由器的ETH
    // 理想情况下，可以像在路由器中那样强制执行，但不可能，因为这需要调用V1工厂，这会消耗过多的gas
    receive() external payable {}

    // 定义迁移函数，用于从V1迁移到V2
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline)
        external
        override
    {
        // 获取对应代币的V1交易所
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(token));
        // 获取用户在V1交易所的流动性
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        // 验证并从用户账户转移V1流动性到本合约
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        // 从V1移除流动性并获取ETH和代币数量
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        // 授权V2路由器可以使用V1的代币数量
        TransferHelper.safeApprove(token, address(router), amountTokenV1);
        // 添加流动性到V2,并获取V2中的代币和ETH数量
        (uint amountTokenV2, uint amountETHV2,) = router.addLiquidityETH{value: amountETHV1}(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
        // 如果V1的代币数量大于V2，用途多余的部分退还给用户
        if (amountTokenV1 > amountTokenV2) {
            TransferHelper.safeApprove(token, address(router), 0); // 良好实践，重置授权为0
            TransferHelper.safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH保证会使用所有的amountETHV1或amountTokenV1，所以这部分是安全的
            TransferHelper.safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}