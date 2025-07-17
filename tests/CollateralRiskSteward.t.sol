// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ReserveConfiguration, DataTypes} from 'aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {RiskSteward, IRiskSteward, IEngine, EngineFlags} from 'src/contracts/RiskSteward.sol';
import {DeployHorizonRiskStewards} from '../scripts/deploy/DeployHorizonStewards.s.sol';
import {RiskSteward_Test} from './RiskSteward.t.sol';

contract CollateralRiskSteward_Test is RiskSteward_Test {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  uint40 public constant MIN_DELAY = type(uint40).max;

  function setUp() public virtual override {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 21974363);
    riskConfig = DeployHorizonRiskStewards._getRiskConfig();
    steward = new RiskSteward(
      address(AaveV3Ethereum.POOL),
      AaveV3Ethereum.CONFIG_ENGINE,
      riskCouncil,
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      riskConfig
    );

    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    AaveV3Ethereum.ACL_MANAGER.addRiskAdmin(address(steward));
  }

  /* ----------------------------- Caps Tests ----------------------------- */
  /// should revert due to config
  function test_updateCaps() public virtual override {
    (uint256 daiBorrowCapBefore, uint256 daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      (daiSupplyCapBefore * 110) / 100, // 10% relative increase
      (daiBorrowCapBefore * 110) / 100 // 10% relative increase
    );

    // without adhering to minDelay, DebounceNotRespected
    vm.startPrank(riskCouncil);
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateCaps(capUpdates);

    (uint256 daiBorrowCapAfter, uint256 daiSupplyCapAfter) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    RiskSteward.Debounce memory lastUpdated = steward.getTimelock(
      AaveV3EthereumAssets.DAI_UNDERLYING
    );
    assertEq(daiBorrowCapAfter, daiBorrowCapBefore);
    assertEq(daiSupplyCapAfter, daiSupplyCapBefore);
    assertEq(lastUpdated.supplyCapLastUpdated, 0);
    assertEq(lastUpdated.borrowCapLastUpdated, 0);

    // after min time passed test caps decrease
    vm.warp(MIN_DELAY);
    (daiBorrowCapBefore, daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      (daiSupplyCapBefore * 90) / 100, // 10% relative decrease
      (daiBorrowCapBefore * 90) / 100 // 10% relative decrease
    );
    // after adhering to minDelay, UpdateNotInRange
    vm.expectRevert(IRiskSteward.UpdateNotInRange.selector);
    steward.updateCaps(capUpdates);
    vm.stopPrank();

    (daiBorrowCapAfter, daiSupplyCapAfter) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    assertEq(daiBorrowCapAfter, daiBorrowCapBefore);
    assertEq(daiSupplyCapAfter, daiSupplyCapBefore);
  }

  function test_updateCaps_outOfRange() public virtual override {
    vm.warp(MIN_DELAY);
    super.test_updateCaps_outOfRange();
  }

  function test_updateCaps_debounceNotRespected() public virtual override {
    (uint256 daiBorrowCapBefore, uint256 daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      (daiSupplyCapBefore * 110) / 100, // 10% relative increase
      (daiBorrowCapBefore * 110) / 100 // 10% relative increase
    );

    vm.startPrank(riskCouncil);
    // expect revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateCaps(capUpdates);

    (daiBorrowCapBefore, daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      daiSupplyCapBefore + 1,
      daiBorrowCapBefore + 1
    );

    vm.warp(MIN_DELAY - 1);

    // expect revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateCaps(capUpdates);
    vm.stopPrank();
  }

  /// should revert due to config
  function test_updateCaps_sameUpdate() public virtual override {
    vm.warp(MIN_DELAY);
    super.test_updateCaps_sameUpdate();
  }

  function test_updateCaps_assetUnlisted() public virtual override {
    address unlistedAsset = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(unlistedAsset, 100, 100);

    vm.warp(MIN_DELAY);

    vm.prank(riskCouncil);
    // as the update is from value 0
    vm.expectRevert(IRiskSteward.UpdateNotInRange.selector);
    steward.updateCaps(capUpdates);
  }

  /* ----------------------------- Rates Tests ----------------------------- */

  /// should revert due to config
  function test_updateRates() public virtual override {
    (
      uint256 beforeOptimalUsageRatio,
      uint256 beforeBaseVariableBorrowRate,
      uint256 beforeVariableRateSlope1,
      uint256 beforeVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    IEngine.RateStrategyUpdate[] memory rateUpdates = new IEngine.RateStrategyUpdate[](1);
    rateUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3EthereumAssets.WETH_UNDERLYING,
      params: IEngine.InterestRateInputData({
        optimalUsageRatio: beforeOptimalUsageRatio + 3_00, // 3% absolute increase
        baseVariableBorrowRate: beforeBaseVariableBorrowRate + 1_00, // 1% absolute increase
        variableRateSlope1: beforeVariableRateSlope1 + 1_00, // 1% absolute increase
        variableRateSlope2: beforeVariableRateSlope2 + 20_00 // 20% absolute increase
      })
    });

    vm.startPrank(riskCouncil);
    // expect revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateRates(rateUpdates);

    (
      uint256 afterOptimalUsageRatio,
      uint256 afterBaseVariableBorrowRate,
      uint256 afterVariableRateSlope1,
      uint256 afterVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    RiskSteward.Debounce memory lastUpdated = steward.getTimelock(
      AaveV3EthereumAssets.WETH_UNDERLYING
    );
    assertEq(afterOptimalUsageRatio, beforeOptimalUsageRatio);
    assertEq(afterBaseVariableBorrowRate, beforeBaseVariableBorrowRate);
    assertEq(afterVariableRateSlope1, beforeVariableRateSlope1);
    assertEq(afterVariableRateSlope2, beforeVariableRateSlope2);

    assertEq(lastUpdated.optimalUsageRatioLastUpdated, 0);
    assertEq(lastUpdated.baseVariableRateLastUpdated, 0);
    assertEq(lastUpdated.variableRateSlope1LastUpdated, 0);
    assertEq(lastUpdated.variableRateSlope2LastUpdated, 0);

    // after min time passed
    vm.warp(MIN_DELAY);

    // should still revert due to UpdateNotInRange
    vm.expectRevert(IRiskSteward.UpdateNotInRange.selector);
    steward.updateRates(rateUpdates);
    vm.stopPrank();

    (
      afterOptimalUsageRatio,
      afterBaseVariableBorrowRate,
      afterVariableRateSlope1,
      afterVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);
    lastUpdated = steward.getTimelock(AaveV3EthereumAssets.WETH_UNDERLYING);

    assertEq(afterOptimalUsageRatio, beforeOptimalUsageRatio);
    assertEq(afterBaseVariableBorrowRate, beforeBaseVariableBorrowRate);
    assertEq(afterVariableRateSlope1, beforeVariableRateSlope1);
    assertEq(afterVariableRateSlope2, beforeVariableRateSlope2);

    assertEq(lastUpdated.optimalUsageRatioLastUpdated, 0);
    assertEq(lastUpdated.baseVariableRateLastUpdated, 0);
    assertEq(lastUpdated.variableRateSlope1LastUpdated, 0);
    assertEq(lastUpdated.variableRateSlope2LastUpdated, 0);
  }

  function test_updateRates_outOfRange() public virtual override {
    vm.warp(MIN_DELAY);
    super.test_updateRates_outOfRange();
  }

  function test_updateRates_debounceNotRespected() public virtual override {
    (
      uint256 beforeOptimalUsageRatio,
      uint256 beforeBaseVariableBorrowRate,
      uint256 beforeVariableRateSlope1,
      uint256 beforeVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    IEngine.RateStrategyUpdate[] memory rateUpdates = new IEngine.RateStrategyUpdate[](1);
    rateUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3EthereumAssets.WETH_UNDERLYING,
      params: IEngine.InterestRateInputData({
        optimalUsageRatio: beforeOptimalUsageRatio + 3_00, // 3% absolute increase
        baseVariableBorrowRate: beforeBaseVariableBorrowRate + 1_00, // 1% absolute increase
        variableRateSlope1: beforeVariableRateSlope1 + 1_00, // 1% absolute increase
        variableRateSlope2: beforeVariableRateSlope2 + 20_00 // 20% absolute increase
      })
    });

    vm.startPrank(riskCouncil);
    // should revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateRates(rateUpdates);

    vm.warp(MIN_DELAY - 1);

    // should revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateRates(rateUpdates);
    vm.stopPrank();
  }

  function test_updateRate_sameUpdate() public virtual override {
    vm.warp(MIN_DELAY);
    super.test_updateRate_sameUpdate();
  }

  /* ----------------------------- EMode Category Update Tests ----------------------------- */
  /// should revert due to config
  function test_updateEModeCategories() public virtual override {
    uint8 eModeId = 1;
    DataTypes.CollateralConfig memory currentEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    string memory label = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: currentEmodeConfig.ltv + 50, // 0.5% absolute increase
      liqThreshold: currentEmodeConfig.liquidationThreshold + 10, // 0.1% absolute increase
      liqBonus: (currentEmodeConfig.liquidationBonus - 100_00) + 50, // 0.5% absolute increase
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.startPrank(riskCouncil);
    // expect revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    RiskSteward.EModeDebounce memory lastUpdated = steward.getEModeTimelock(eModeId);

    DataTypes.CollateralConfig memory afterEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    string memory afterLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    assertEq(afterEmodeConfig.ltv, currentEmodeConfig.ltv);
    assertEq(afterEmodeConfig.liquidationThreshold, currentEmodeConfig.liquidationThreshold);
    assertEq(afterEmodeConfig.liquidationBonus, currentEmodeConfig.liquidationBonus);
    assertEq(afterLabel, label);

    assertEq(lastUpdated.eModeLtvLastUpdated, 0);
    assertEq(lastUpdated.eModeLiquidationThresholdLastUpdated, 0);
    assertEq(lastUpdated.eModeLiquidationBonusLastUpdated, 0);

    // after min time passed test eMode update decrease
    vm.warp(MIN_DELAY);

    currentEmodeConfig = AaveV3Ethereum.POOL.getEModeCategoryCollateralConfig(eModeId);

    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: currentEmodeConfig.ltv - 50, // 0.5% absolute increase
      liqThreshold: currentEmodeConfig.liquidationThreshold - 10, // 0.1% absolute increase
      liqBonus: (currentEmodeConfig.liquidationBonus - 100_00) - 50, // 0.5% absolute increase
      label: EngineFlags.KEEP_CURRENT_STRING
    });
    // expect revert as UpdateNotInRange
    vm.expectRevert(IRiskSteward.UpdateNotInRange.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    afterEmodeConfig = AaveV3Ethereum.POOL.getEModeCategoryCollateralConfig(eModeId);
    afterLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    assertEq(afterEmodeConfig.ltv, currentEmodeConfig.ltv);
    assertEq(afterEmodeConfig.liquidationThreshold, currentEmodeConfig.liquidationThreshold);
    assertEq(afterEmodeConfig.liquidationBonus, currentEmodeConfig.liquidationBonus);
    assertEq(afterLabel, label);

    lastUpdated = steward.getEModeTimelock(eModeId);

    assertEq(lastUpdated.eModeLtvLastUpdated, 0);
    assertEq(lastUpdated.eModeLiquidationThresholdLastUpdated, 0);
    assertEq(lastUpdated.eModeLiquidationBonusLastUpdated, 0);
  }

  function test_updateEModeCategories_outOfRange() public virtual override {
    vm.warp(MIN_DELAY);
    super.test_updateEModeCategories_outOfRange();
  }

  function test_updateEModeCategories_debounceNotRespected() public virtual override {
    uint8 eModeId = 1;
    DataTypes.CollateralConfig memory currentEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: currentEmodeConfig.ltv + 50, // 0.5% absolute increase
      liqThreshold: currentEmodeConfig.liquidationThreshold + 10, // 0.1% absolute increase
      liqBonus: (currentEmodeConfig.liquidationBonus - 100_00) + 50, // 0.5% absolute increase
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.startPrank(riskCouncil);
    // expect revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    vm.warp(MIN_DELAY - 1);

    // expect revert as minimum time has not passed for next update
    vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  function test_updateEModeCategories_sameUpdate() public virtual override {
    vm.warp(MIN_DELAY);
    super.test_updateEModeCategories_sameUpdate();
  }

  /* ----------------------------- Collateral Tests ----------------------------- */
  function test_updateCollateralSide_outOfRange() public virtual override {
    (, uint256 ltvBefore, uint256 ltBefore, uint256 lbBefore, , , , , , ) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveConfigurationData(AaveV3EthereumAssets.UNI_UNDERLYING);

    // as the definition is with 2 decimals, and config engine does not take the decimals into account, so we divide by 100.
    uint256 debtCeilingBefore = AaveV3Ethereum.AAVE_PROTOCOL_DATA_PROVIDER.getDebtCeiling(
      AaveV3EthereumAssets.UNI_UNDERLYING
    ) / 100;

    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);
    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3EthereumAssets.UNI_UNDERLYING,
      ltv: ltvBefore + 12_00, // 12% absolute increase
      liqThreshold: ltBefore + 11_00, // 11% absolute increase
      liqBonus: (lbBefore - 100_00) + 3_00, // 3% absolute increase
      debtCeiling: (debtCeilingBefore * 112) / 100, // 12% relative increase
      liqProtocolFee: EngineFlags.KEEP_CURRENT
    });

    vm.startPrank(riskCouncil);
    // should not revert, as allowable range is set to max uint128 percent change
    steward.updateCollateralSide(collateralUpdates);

    // no time needs to pass to update again as delay is set to 0

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3EthereumAssets.UNI_UNDERLYING,
      ltv: ltvBefore - 11_00, // 11% absolute decrease
      liqThreshold: ltBefore - 11_00, // 11% absolute decrease
      liqBonus: (lbBefore - 100_00) - 2_50, // 2.5% absolute decrease
      debtCeiling: (debtCeilingBefore * 85) / 100, // 15% relative decrease
      liqProtocolFee: EngineFlags.KEEP_CURRENT
    });

    // should not revert, as allowable range is set to max uint128 percent change
    steward.updateCollateralSide(collateralUpdates);
    vm.stopPrank();
  }

  function test_updateCollateralSide_debounceNotRespected() public virtual override {
    (, uint256 ltvBefore, , , , , , , , ) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveConfigurationData(AaveV3EthereumAssets.UNI_UNDERLYING);

    IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);
    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3EthereumAssets.UNI_UNDERLYING,
      ltv: ltvBefore + 25,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT
    });

    vm.startPrank(riskCouncil);
    steward.updateCollateralSide(collateralUpdates);

    (, ltvBefore, , , , , , , , ) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveConfigurationData(AaveV3EthereumAssets.UNI_UNDERLYING);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3EthereumAssets.UNI_UNDERLYING,
      ltv: ltvBefore + 1,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      debtCeiling: EngineFlags.KEEP_CURRENT,
      liqProtocolFee: EngineFlags.KEEP_CURRENT
    });

    // will not revert as delay config is 0
    steward.updateCollateralSide(collateralUpdates);
    vm.stopPrank();
  }
}
