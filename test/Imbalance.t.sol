// 1:1 with Hardhat test
pragma solidity 0.8.13;

import './BaseTest.sol';

contract ImbalanceTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    Gauge gauge;
    InternalBribe bribe;

    function deployBaseCoins() public {
        deployProxyAdmin();
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e25;
        mintVara(owners, amounts);
        VeArtProxy artProxy = new VeArtProxy();

        VotingEscrow implEscrow = new VotingEscrow();
        proxy = new TransparentUpgradeableProxy(address(implEscrow), address(admin), abi.encodeWithSelector(VotingEscrow.initialize.selector, address(VARA), address(artProxy)));
        escrow = VotingEscrow(address(proxy));
    }

    function createLock() public {
        deployBaseCoins();

        VARA.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, 4 * 365 * 86400);
        vm.warp(1);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VARA.balanceOf(address(escrow)), TOKEN_1);
    }

    function votingEscrowMerge() public {
        createLock();

        VARA.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, 4 * 365 * 86400);
        assertGt(escrow.balanceOfNFT(2), 995063075414519385);
        assertEq(VARA.balanceOf(address(escrow)), 2 * TOKEN_1);
        escrow.merge(2, 1);
        assertGt(escrow.balanceOfNFT(1), 1990039602248405587);
        assertEq(escrow.balanceOfNFT(2), 0);
    }

    function confirmTokensForFraxUsdc() public {
        votingEscrowMerge();
        deployPairFactoryAndRouter();
        deployPairWithOwner(address(owner));

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq(pair.token0(), token0);
        assertEq(pair.token1(), token1);
    }

    function mintAndBurnTokensForPairFraxUsdc() public {
        confirmTokensForFraxUsdc();

        USDC.transfer(address(pair), USDC_1);
        FRAX.transfer(address(pair), TOKEN_1);
        pair.mint(address(owner));
        assertEq(pair.getAmountOut(USDC_1, address(USDC)), 945128557522723966);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPairFraxUsdc();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);
        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(address(FRAX), address(USDC), false, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);
        DAI.approve(address(router), TOKEN_100M);
        FRAX.approve(address(router), TOKEN_100M);
        router.addLiquidity(address(FRAX), address(DAI), true, TOKEN_100M, TOKEN_100M, 0, 0, address(owner), block.timestamp);
    }

    function deployVoter() public {
        routerAddLiquidity();

        Gauge implGauge = new Gauge();
        GaugeFactory implGaugeFactory = new GaugeFactory();
        proxy = new TransparentUpgradeableProxy(address(implGaugeFactory), address(admin), abi.encodeWithSelector(GaugeFactory.initialize.selector, address(implGauge)));
        gaugeFactory = GaugeFactory(address(proxy));

        InternalBribe implInternalBribe = new InternalBribe();
        ExternalBribe implExternalBribe = new ExternalBribe();
        BribeFactory implBribeFactory = new BribeFactory();
        proxy = new TransparentUpgradeableProxy(address(implBribeFactory), address(admin), abi.encodeWithSelector(BribeFactory.initialize.selector, address(implInternalBribe), address(implExternalBribe)));
        bribeFactory = BribeFactory(address(proxy));

        Voter implVoter = new Voter();
        proxy = new TransparentUpgradeableProxy(address(implVoter), address(admin), abi.encodeWithSelector(Voter.initialize.selector, address(escrow), address(factory), address(gaugeFactory), address(bribeFactory)));
        voter = Voter(address(proxy));

        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(VARA);
        voter.init(tokens, address(owner));

        assertEq(voter.length(), 0);
    }

    function deployPairFactoryGauge() public {
        deployVoter();

        VARA.approve(address(gaugeFactory), 5 * TOKEN_100K);
        voter.createGauge(address(pair3));
        assertFalse(voter.gauges(address(pair3)) == address(0));

        address gaugeAddr3 = voter.gauges(address(pair3));

        Gauge gauge3 = Gauge(gaugeAddr3);

        uint256 total = pair3.balanceOf(address(owner));
        pair3.approve(address(gauge3), total);
        gauge3.deposit(total, 0);
        assertEq(gauge3.totalSupply(), total);
        assertEq(gauge3.earned(address(escrow), address(owner)), 0);
    }

    function testRouterPair3GetAmountsOutAndSwapExactTokensForTokens() public {
        deployPairFactoryGauge();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(FRAX), address(DAI), true);
        Router.route[] memory routes2 = new Router.route[](1);
        routes2[0] = Router.route(address(DAI), address(FRAX), true);

        uint256 fb = FRAX.balanceOf(address(owner));
        uint256 db = DAI.balanceOf(address(owner));

        uint256 i;
        for (i = 0; i < 10; i++) {
            assertEq(router.getAmountsOut(1e25, routes)[1], pair3.getAmountOut(1e25, address(FRAX)));

            uint256[] memory expectedOutput = router.getAmountsOut(1e25, routes);
            FRAX.approve(address(router), 1e25);
            router.swapExactTokensForTokens(1e25, expectedOutput[1], routes, address(owner), block.timestamp);
        }

        DAI.approve(address(router), TOKEN_10B);
        FRAX.approve(address(router), TOKEN_10B);
        uint256 pairBefore = pair3.balanceOf(address(owner));
        router.addLiquidity(address(FRAX), address(DAI), true, TOKEN_10B, TOKEN_10B, 0, 0, address(owner), block.timestamp);
        uint256 pairAfter = pair3.balanceOf(address(owner));
        uint256 LPBal = pairAfter - pairBefore;

        for (i = 0; i < 10; i++) {
            assertEq(router.getAmountsOut(1e25, routes2)[1], pair3.getAmountOut(1e25, address(DAI)));

            uint256[] memory expectedOutput2 = router.getAmountsOut(1e25, routes2);
            DAI.approve(address(router), 1e25);
            router.swapExactTokensForTokens(1e25, expectedOutput2[1], routes2, address(owner), block.timestamp);
        }
        pair3.approve(address(router), LPBal);
        router.removeLiquidity(address(FRAX), address(DAI), true, LPBal, 0, 0, address(owner), block.timestamp);

        uint256 fa = FRAX.balanceOf(address(owner));
        uint256 da = DAI.balanceOf(address(owner));

        uint256 netAfter = fa + da;
        uint256 netBefore = db + fb;

        assertGt(netBefore, netAfter);
    }
}
