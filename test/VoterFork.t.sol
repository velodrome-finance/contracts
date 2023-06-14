// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract VoterForkTest is BaseTest {
    constructor() {
        deploymentType = Deployment.FORK;
    }

    function testCannotCreateGaugeWithV1FactoryIfNotGovernor() public {
        address _pool = vFactory.getPair(address(USDC), address(WETH), false);

        vm.expectRevert(IVoter.NotGovernor.selector);
        vm.prank(address(owner2));
        voter.createGauge(address(vFactory), _pool);
    }

    function testCreateGaugeWithV1Factory() public {
        address _pool = vFactory.getPair(address(USDC), address(WETH), false);

        vm.prank(address(governor));
        address _gauge = voter.createGauge(address(vFactory), _pool);

        assertTrue(voter.gaugeToFees(_gauge) != address(0));
        assertTrue(voter.gaugeToBribe(_gauge) != address(0));
        assertEq(voter.gauges(_pool), _gauge);
        assertEq(voter.poolForGauge(_gauge), _pool);
        assertTrue(voter.isGauge(_gauge));
        assertTrue(voter.isAlive(_gauge));
        uint256 length = voter.length();
        assertEq(voter.pools(length - 1), _pool);
    }
}
