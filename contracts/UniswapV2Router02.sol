pragma solidity =0.6.6;

// 导入Uniswap V2核心工厂接口
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
// 导入用于安全转账的辅助库
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

// 导入Uniswap V2路由器02接口
import './interfaces/IUniswapV2Router02.sol';
// 导入Uniswap V2库
import './libraries/UniswapV2Library.sol';
// 导入安全数学库以避免溢出
import './libraries/SafeMath.sol';
// 导入ERC20接口
import './interfaces/IERC20.sol';
// 导入IWETH接口，用于与ETH交互
import './interfaces/IWETH.sol';

// 定义UniswapV2Router02合约，实现IUniswapV2Router02接口
contract UniswapV2Router02 is IUniswapV2Router02 {
    // 使用SafeMath库进行uint类型的安全数学运算
    using SafeMath for uint;

    // 定义不可变的工厂和WETH地址
    address public immutable override factory;
    address public immutable override WETH;

    // 修改器用于确保调用的截止日期没有过期
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    // 合约构造函数，传入工厂地址和WETH地址
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    // 接收ETH的回退函数，仅从WETH合约接收ETH
    receive() external payable {
        assert(msg.sender == WETH);
    }

    // **** 增加流动性 ****
    // 内部函数，用于添加流动性
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired, // 希望添加的tokenA数量
        uint amountBDesired, // 希望添加的tokenB数量
        uint amountAMin, // 最小tokenA数量
        uint amountBMin // 最小tokenB数量
    ) internal virtual returns (uint amountA, uint amountB) {
        // 如果交易对不存在就创建它
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        // 获取储备金
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            // 如果储备金为0，直接使用期望的数量
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 根据期望的tokenA数量，计算理想的tokenB数量
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                // 检查B的数量是否大于或等于最小值
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // 否则计算tokenA的理想数量
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                // 检查A的数量是否大于或等于最小值
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // 外部函数，通过传入的参数添加流动性
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        // 调用内部函数添加流动性
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将tokenA和tokenB转移到交易对地址
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // 铸造流动性代币并转移给接收者
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    // 添加ETH流动性的方法
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        // 调用内部函数添加流动性
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 将token转移到交易对地址
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // 存入ETH到WETH合约
        IWETH(WETH).deposit{value: amountETH}();
        // 确保WETH转移到交易对
        assert(IWETH(WETH).transfer(pair, amountETH));
        // 铸造流动性代币并转移给接收者
        liquidity = IUniswapV2Pair(pair).mint(to);
        // 如果多余，则退还ETH
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** 移除流动性 ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将流动性代币转移到交易对合约
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        // 燃烧流动性代币并获得token金额
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        // 确定token0和token1的排序
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        // 确定最终的amountA和amountB
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        // 确保最终的token数量不低于最小值
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
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        // 调用移除流动性方法
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 转移token到接收者
        TransferHelper.safeTransfer(token, to, amountToken);
        // 从WETH中提取ETH
        IWETH(WETH).withdraw(amountETH);
        // 转移ETH到接收者
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 根据approveMax设置授权的数量
        uint value = approveMax ? uint(-1) : liquidity;
        // 使用permit进行授权
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 执行移除流动性操作
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        // 获取交易对地址
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 根据approveMax设置授权的数量
        uint value = approveMax ? uint(-1) : liquidity;
        // 使用permit进行授权
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 移除支持手续费传输的ETH流动性
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    // 需要初始金额已经发送到第一个交易对
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 执行交换操作
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    // 知道输入算输出
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 根据输入数量和路径获取输出数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 检查输出数量不低于最小值
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将输入代币转移到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 执行交换
        _swap(amounts, path, to);
    }

    // 知道输出算输入
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 根据输出数量和路径获取输入数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 检查输入数量不超过最大值
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将输入代币转移到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 执行交换
        _swap(amounts, path, to);
    }

    // 交换ETH以获得确切数量的代币
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径是以WETH开始
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 根据输入的ETH金额和路径获取输出数量
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        // 检查输出数量不低于最小值
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 存入ETH到WETH合约
        IWETH(WETH).deposit{value: amounts[0]}();
        // 确保WETH转移到交易对
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 执行交换
        _swap(amounts, path, to);
    }

    // 交换代币以获得确切数量的ETH
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径是以WETH结束
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 根据输出ETH数量和路径获取输入数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 检查输入数量不超过最大值
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将输入代币转移到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 执行交换
        _swap(amounts, path, address(this));
        // 从WETH中提取ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 转移ETH到接收者
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 交换确切数量的代币以换取ETH
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径是以WETH结束
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 根据输入代币数量和路径获取输出数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 检查输出数量不低于最小值
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将输入代币转移到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 执行交换
        _swap(amounts, path, address(this));
        // 从WETH中提取ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 转移ETH到接收者
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 交换ETH以获得确切数量的代币
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 确保路径是以WETH开始
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 根据输出代币数量和路径获取输入数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 检查输入的ETH数量不超过最大值
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 存入ETH到WETH合约
        IWETH(WETH).deposit{value: amounts[0]}();
        // 确保WETH转移到交易对
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 执行交换
        _swap(amounts, path, to);
        // 如果多余，则退还ETH
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (支持手续费传输的代币) ****
    // 需要初始金额已经发送到第一个交易对
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // 作用域以避免堆栈过深错误
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            // 确定输出数量
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            // 确定下一个接收者
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 执行交换
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    // 交换确切数量的代币以换取代币，同时支持手续费传输
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        // 将输入代币转移到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        // 获取交换前的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        // 执行支持手续费传输的交换
        _swapSupportingFeeOnTransferTokens(path, to);
        // 检查交换后的余额增加是否满足最小输出
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    // 交换ETH以获得代币，同时支持手续费传输
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        // 确保路径是以WETH开始
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 将ETH存入WETH合约
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        // 确保WETH转移到交易对
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        // 获取交换前的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        // 执行支持手续费传输的交换
        _swapSupportingFeeOnTransferTokens(path, to);
        // 检查交换后的余额增加是否满足最小输出
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    // 交换确切数量的代币以换取ETH，同时支持手续费传输
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        // 确保路径是以WETH结束
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 将输入代币转移到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        // 执行支持手续费传输的交换
        _swapSupportingFeeOnTransferTokens(path, address(this));
        // 获取WETH合约中的余额
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        // 检查输出数量不低于最小值
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 从WETH中提取ETH
        IWETH(WETH).withdraw(amountOut);
        // 转移ETH到接收者
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** 库函数 ****
    // 根据数量A、储备A和储备B计算数量B
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    // 根据输入量、输入储备和输出储备计算输出量
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    // 根据输出量、输入储备和输出储备计算输入量
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    // 根据输入量和路径获取输出量
    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    // 根据输出量和路径获取输入量
    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}