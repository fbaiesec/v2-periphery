pragma solidity =0.6.6;

// 导入Uniswap V2工厂接口
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
// 导入安全转账辅助库
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

// 导入Uniswap V2库
import './libraries/UniswapV2Library.sol';
// 导入Uniswap V2路由接口
import './interfaces/IUniswapV2Router01.sol';
// 导入ERC20接口
import './interfaces/IERC20.sol';
// 导入WETH接口
import './interfaces/IWETH.sol';

// 定义Uniswap V2路由合约，继承接口IUniswapV2Router01
contract UniswapV2Router01 is IUniswapV2Router01 {
    // 工厂合约地址，声明为不可变
    address public immutable override factory;
    // WETH合约地址，声明为不可变
    address public immutable override WETH;

    // 确保截止时间没有过期的修饰符
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    // 构造函数，初始化工厂和WETH合约地址
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    // 接收ETH的回退函数，确保只能从WETH合约接收ETH
    receive() external payable {
        assert(msg.sender == WETH); // 只接受来自WETH合约的ETH
    }

    // **** 添加流动性相关函数 ****
    //计算流动性两种token的数量
    function _addLiquidity(
        address tokenA, 
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,    //这个最小是干嘛用的
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // 如果交易对不存在则创建交易对
        // 创建了新的交易对合约，但并未返回合约地址
        // 为什么不在这里获取交易对合约地址，而是在后面重新计算交易对合约地址呢？
        //  为了节省gas，跨合约调用的gas消耗，大于计算的gas消耗，具体原因不清楚
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        // 获取储备量，当前池子里两种token的数量
        //两种可能：
        //1.池子还没创建，返回值都是0
        //2.池子已创建，返回当前两种token的数量
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        //情况一：池子还未创建
        //初始池子里的代币数量，是第一个创建池子的人添加的数量
        if (reserveA == 0 && reserveB == 0) {
            // 初始创建交易对时，使用所需的数量
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
        //情况二：池子已创建，里面已有token
            // 计算最优B数量
            //根据当前池子里两种token的数量之比，来计算添加流动性的两种token的数量
            //本质在于，添加流动性，不能引起汇率变化
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            //情况一：用户添加的比率不对
            //tokenB添加的刚好，或者多了
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                //更新token比例，保持不变
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                //tokenB添加的少了，意味着tokenA添加的多了
                //则根据tokenB为基准
                // 计算最优A数量
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                //
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // 用户调用的添加流动性函数
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,   
        uint deadline
    ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        // 计算实际要添加的数量
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将代币转移到交易对
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // 铸造流动性代币
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    // 添加ETH流动性的方法
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        //这个to地址是接收lptoken的地址
        address to,
        uint deadline
    ) external override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        // 计算实际要添加的代币和ETH数量
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            //msg.value 是调用该合约的账户，发送到该合约的eth的数量
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        // 获取交易对地址
        // 
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 将代币转移到交易对
        //msg.sender 当前调用智能合约的地址
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // 将ETH转换为WETH
        IWETH(WETH).deposit{value: amountETH}();
        // 将WETH转移到交易对
        assert(IWETH(WETH).transfer(pair, amountETH));
        // 铸造流动性代币
        liquidity = IUniswapV2Pair(pair).mint(to);
        // 如果有多余的ETH，退回给发送者
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // 如果有多余的ETH，退回给发送者
    }

    // **** 移除流动性相关函数 ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountA, uint amountB) {
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将流动性代币转移到交易对
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        // 销毁流动性代币，并获取代币数量
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        // 确定输出代币的顺序
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        // 确保输出的代币数量满足最小要求
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    // 移除ETH流动性的方法
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountToken, uint amountETH) {
        // 移除流动性
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 转移代币和ETH到指定地址
        TransferHelper.safeTransfer(token, to, amountToken);
        // 将WETH转换为ETH
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // 使用许可进行移除流动性
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountA, uint amountB) {
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 判断是否授权最大值
        uint value = approveMax ? uint(-1) : liquidity;
        // 使用许可进行授权
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 移除流动性
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // 使用许可移除ETH流动性的方法
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountToken, uint amountETH) {
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 判断是否授权最大值
        uint value = approveMax ? uint(-1) : liquidity;
        // 使用许可进行授权
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 移除ETH流动性
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** 交换代币相关函数 ****
    //按照路径进行swap
    //_to是目标代币的pair 地址
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            //确认pair中token的顺序
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            //临时目标token的数量
            uint amountOut = amounts[i + 1];
            // 确定输出金额分配
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            // 确定下一个交易对地址
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 执行交换
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    // 精确输入交换代币
    //返回一组数量
    function swapExactTokensForTokens(
        uint amountIn,              //输入的代币数量
        uint amountOutMin,          //输出的最少目标代币数量
        address[] calldata path,    //兑换路径
        address to,                 //什么？接收目标代币的地址，这里为什么不用msg.sender？
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        // 计算输出代币数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 确保输出代币数量满足最小值要求
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 执行安全转账
        // 从msg.sender账户，转token到pair
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 执行交换
        _swap(amounts, path, to);
    }

    // 精确输出交换代币
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        // 计算输入代币数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 确保输入代币数量不超过最大值
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 执行安全转账
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 执行交换
        _swap(amounts, path, to);
    }

    // 精确输入ETH交换代币
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径起点为WETH
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 计算输出代币数量
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        // 确保输出代币数量满足最小值
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将ETH转换为WETH
        IWETH(WETH).deposit{value: amounts[0]}();
        // 转移WETH到交易对
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 执行交换
        _swap(amounts, path, to);
    }

    // 精确输出ETH交换代币
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径终点为WETH
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 计算输入代币数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 确保输入代币数量不超过最大值
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 执行安全转账
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 执行交换
        _swap(amounts, path, address(this));
        // 将WETH转换为ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 转移ETH到指定地址
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 精确输入代币交换ETH
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径终点为WETH
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 计算输出ETH数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 确保输出ETH数量满足最小值
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 执行安全转账
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 执行交换
        _swap(amounts, path, address(this));
        // 将WETH转换为ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 转移ETH到指定地址
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 精确输出代币交换ETH
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径起点为WETH
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 计算输入ETH数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 确保输入ETH数量不超过最大值
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将ETH转换为WETH
        IWETH(WETH).deposit{value: amounts[0]}();
        // 转移WETH到交易对
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 执行交换
        _swap(amounts, path, to);
        // 如果有多余的ETH，退回给发送者
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // 如果有多余的ETH，退回给发送者
    }

    // 获取报价
    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    // 根据输入量和储备量，计算输出量
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure override returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    // 根据输出量和储备量，计算输入量
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return UniswapV2Library.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    // 根据输入量和路径，获取所有输出量
    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    // 根据输出量和路径，获取所有输入量
    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}