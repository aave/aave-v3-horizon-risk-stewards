// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console2 as console} from 'forge-std/console2.sol';

import {ReserveConfiguration, DataTypes} from 'aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {IRiskSteward, IEngine, EngineFlags} from 'src/contracts/RiskSteward.sol';
import {CollateralRiskSteward} from 'src/contracts/CollateralRiskSteward.sol';
import {IAaveV3ConfigEngine as IEngine} from 'aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol';
import {DeployHorizonRiskStewards} from '../scripts/deploy/DeployHorizonStewards.s.sol';
import {RiskSteward_Test} from './RiskSteward.t.sol';

contract CollateralRiskSteward_Test is RiskSteward_Test {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  function setUp() public virtual override {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 21974363);
    riskConfig = DeployHorizonRiskStewards._getRiskConfig();
    steward = new CollateralRiskSteward(
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
  function test_updateCaps_revertsWith_UpdateNotAllowed() public virtual {
    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(AaveV3EthereumAssets.DAI_UNDERLYING, 0, 0);

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateCaps(capUpdates);
  }

  /// should revert as UpdateNotAllowed
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

    vm.startPrank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);

    (uint256 daiBorrowCapAfter, uint256 daiSupplyCapAfter) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    CollateralRiskSteward.Debounce memory lastUpdated = steward.getTimelock(
      AaveV3EthereumAssets.DAI_UNDERLYING
    );
    assertNotEq(daiBorrowCapAfter, capUpdates[0].borrowCap);
    assertNotEq(daiSupplyCapAfter, capUpdates[0].supplyCap);
    assertNotEq(lastUpdated.supplyCapLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.borrowCapLastUpdated, vm.getBlockTimestamp());

    // after min time passed test caps decrease
    skip(1);
    (daiBorrowCapBefore, daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      (daiSupplyCapBefore * 90) / 100, // 10% relative decrease
      (daiBorrowCapBefore * 90) / 100 // 10% relative decrease
    );
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);
    vm.stopPrank();

    (daiBorrowCapAfter, daiSupplyCapAfter) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    assertNotEq(daiBorrowCapAfter, capUpdates[0].borrowCap);
    assertNotEq(daiSupplyCapAfter, capUpdates[0].supplyCap);
  }

  /// should revert as UpdateNotAllowed
  function test_updateCaps_outOfRange() public virtual override {
    (uint256 daiBorrowCapBefore, uint256 daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      (daiSupplyCapBefore * 210) / 100, // 110% relative increase (current maxChangePercent configured is 100%)
      (daiBorrowCapBefore * 210) / 100 // 110% relative increase
    );

    vm.prank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);

    IRiskSteward.RiskParamConfig memory newConfig = IRiskSteward.RiskParamConfig({
      minDelay: 3 days,
      maxPercentChange: 10_00
    });
    IRiskSteward.Config memory config = riskConfig;
    config.capConfig.supplyCap = newConfig;
    config.capConfig.borrowCap = newConfig;

    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setRiskConfig(config);

    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      (daiSupplyCapBefore * 80) / 100, // 20% relative decrease
      (daiBorrowCapBefore * 80) / 100 // 20% relative decrease
    );
    vm.prank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);

    vm.stopPrank();
  }

  /// should revert as UpdateNotAllowed
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
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
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

    // expect revert as UpdateNotAllowed
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);
    vm.stopPrank();
  }

  /// should revert as UpdateNotAllowed
  function test_updateCaps_allKeepCurrent() public virtual override {
    (uint256 daiBorrowCapBefore, uint256 daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      EngineFlags.KEEP_CURRENT,
      EngineFlags.KEEP_CURRENT
    );

    vm.startPrank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);

    (uint256 daiBorrowCapAfter, uint256 daiSupplyCapAfter) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    // remains the same as update reverted
    assertEq(daiBorrowCapBefore, daiBorrowCapAfter);
    assertEq(daiSupplyCapBefore, daiSupplyCapAfter);
  }

  /// should revert as UpdateNotAllowed
  function test_updateCaps_sameUpdate() public virtual override {
    (uint256 daiBorrowCapBefore, uint256 daiSupplyCapBefore) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      EngineFlags.KEEP_CURRENT,
      EngineFlags.KEEP_CURRENT
    );

    vm.startPrank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateCaps(capUpdates);

    (uint256 daiBorrowCapAfter, uint256 daiSupplyCapAfter) = AaveV3Ethereum
      .AAVE_PROTOCOL_DATA_PROVIDER
      .getReserveCaps(AaveV3EthereumAssets.DAI_UNDERLYING);

    // remains the same as update reverted
    assertEq(daiBorrowCapBefore, daiBorrowCapAfter);
    assertEq(daiSupplyCapBefore, daiSupplyCapAfter);
  }

  /// should revert as UpdateNotAllowed
  function test_updateCaps_assetUnlisted() public virtual override {
    address unlistedAsset = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(unlistedAsset, 100, 100);

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateCaps(capUpdates);
  }

  /// should revert as UpdateNotAllowed
  function test_updateCaps_assetRestricted() public virtual override {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setAddressRestricted(AaveV3EthereumAssets.GHO_UNDERLYING, true);
    vm.stopPrank();

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(AaveV3EthereumAssets.GHO_UNDERLYING, 100, 100);

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateCaps(capUpdates);
  }

  /// should revert as UpdateNotAllowed
  function test_updateCaps_toValueZeroNotAllowed() public virtual override {
    // set risk config to allow 100% cap change to 0
    IRiskSteward.RiskParamConfig memory capsParamConfig = IRiskSteward.RiskParamConfig({
      minDelay: 3 days,
      maxPercentChange: 100_00 // 100% relative change
    });

    riskConfig.capConfig.supplyCap = capsParamConfig;
    riskConfig.capConfig.borrowCap = capsParamConfig;

    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setRiskConfig(riskConfig);

    IEngine.CapsUpdate[] memory capUpdates = new IEngine.CapsUpdate[](1);
    capUpdates[0] = IEngine.CapsUpdate(
      AaveV3EthereumAssets.DAI_UNDERLYING,
      0, // 100% relative decrease to 0
      0 // 100% relative decrease to 0
    );

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateCaps(capUpdates);
  }

  /* ----------------------------- EMode Category Update Tests ----------------------------- */
  function test_updateEModeCategories_revertsWith_UpdateNotAllowed() public virtual {
    uint8 eModeId = 1;
    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: 0,
      liqThreshold: 0,
      liqBonus: 0,
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /// should revert as UpdateNotAllowed
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
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    CollateralRiskSteward.EModeDebounce memory lastUpdated = steward.getEModeTimelock(eModeId);

    DataTypes.CollateralConfig memory afterEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    string memory afterLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    assertNotEq(afterEmodeConfig.ltv, eModeCategoryUpdates[0].ltv);
    assertNotEq(afterEmodeConfig.liquidationThreshold, eModeCategoryUpdates[0].liqThreshold);
    assertNotEq(afterEmodeConfig.liquidationBonus - 100_00, eModeCategoryUpdates[0].liqBonus);
    assertEq(afterLabel, label); // remains same as original

    assertNotEq(lastUpdated.eModeLtvLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.eModeLiquidationThresholdLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.eModeLiquidationBonusLastUpdated, vm.getBlockTimestamp());

    // after min time passed test eMode update decrease
    skip(1);

    currentEmodeConfig = AaveV3Ethereum.POOL.getEModeCategoryCollateralConfig(eModeId);

    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: currentEmodeConfig.ltv - 50, // 0.5% absolute increase
      liqThreshold: currentEmodeConfig.liquidationThreshold - 10, // 0.1% absolute increase
      liqBonus: (currentEmodeConfig.liquidationBonus - 100_00) - 50, // 0.5% absolute increase
      label: EngineFlags.KEEP_CURRENT_STRING
    });
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    afterEmodeConfig = AaveV3Ethereum.POOL.getEModeCategoryCollateralConfig(eModeId);
    afterLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    assertNotEq(afterEmodeConfig.ltv, eModeCategoryUpdates[0].ltv);
    assertNotEq(afterEmodeConfig.liquidationThreshold, eModeCategoryUpdates[0].liqThreshold);
    assertNotEq(afterEmodeConfig.liquidationBonus - 100_00, eModeCategoryUpdates[0].liqBonus);
    assertEq(afterLabel, label); // remains same as original

    lastUpdated = steward.getEModeTimelock(eModeId);

    assertNotEq(lastUpdated.eModeLtvLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.eModeLiquidationThresholdLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.eModeLiquidationBonusLastUpdated, vm.getBlockTimestamp());
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_outOfRange() public virtual override {
    uint8 eModeId = 1;
    DataTypes.CollateralConfig memory currentEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: currentEmodeConfig.ltv + 51, // 0.5% absolute increase
      liqThreshold: currentEmodeConfig.liquidationThreshold + 11, // 0.11% absolute increase
      liqBonus: (currentEmodeConfig.liquidationBonus - 100_00) + 51, // 0.51% absolute increase
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);

    // after min time passed test eMode update decrease
    skip(1);

    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: currentEmodeConfig.ltv - 51, // 0.51% absolute increase
      liqThreshold: currentEmodeConfig.liquidationThreshold - 11, // 0.11% absolute increase
      liqBonus: (currentEmodeConfig.liquidationBonus - 100_00) - 51, // 0.51% absolute increase
      label: EngineFlags.KEEP_CURRENT_STRING
    });
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /// should revert as UpdateNotAllowed
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

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_eModeDoesNotExist() public virtual override {
    uint8 eModeId = 100;
    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: 50,
      liqThreshold: 50,
      liqBonus: 100_00,
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_eModeRestricted() public virtual override {
    uint8 eModeCategoryId = 1;
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setEModeCategoryRestricted(eModeCategoryId, true);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeCategoryId,
      ltv: 50,
      liqThreshold: 50,
      liqBonus: 100_00,
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_toValueZeroNotAllowed() public virtual override {
    // set risk config to allow 100% collateral param change to 0
    IRiskSteward.RiskParamConfig memory eModeParamConfig = IRiskSteward.RiskParamConfig({
      minDelay: 3 days,
      maxPercentChange: 100_00 // 100% relative change
    });
    IRiskSteward.Config memory config;
    config.eModeConfig.ltv = eModeParamConfig;
    config.eModeConfig.liquidationThreshold = eModeParamConfig;
    config.eModeConfig.liquidationBonus = eModeParamConfig;

    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setRiskConfig(config);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: 1,
      ltv: 0,
      liqThreshold: 0,
      liqBonus: 0,
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_allKeepCurrent() public virtual override {
    uint8 eModeId = 1;
    DataTypes.CollateralConfig memory prevEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    string memory prevLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);
    CollateralRiskSteward.EModeDebounce memory prevLastUpdated = steward.getEModeTimelock(eModeId);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.startPrank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    DataTypes.CollateralConfig memory afterEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    CollateralRiskSteward.EModeDebounce memory afterLastUpdated = steward.getEModeTimelock(eModeId);
    string memory afterLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    assertEq(afterEmodeConfig.ltv, prevEmodeConfig.ltv);
    assertEq(afterEmodeConfig.liquidationThreshold, prevEmodeConfig.liquidationThreshold);
    assertEq(afterEmodeConfig.liquidationBonus, prevEmodeConfig.liquidationBonus);
    assertEq(afterLabel, prevLabel);

    assertEq(prevLastUpdated.eModeLtvLastUpdated, afterLastUpdated.eModeLtvLastUpdated);
    assertEq(
      prevLastUpdated.eModeLiquidationThresholdLastUpdated,
      afterLastUpdated.eModeLiquidationThresholdLastUpdated
    );
    assertEq(
      prevLastUpdated.eModeLiquidationBonusLastUpdated,
      afterLastUpdated.eModeLiquidationBonusLastUpdated
    );
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_sameUpdate() public virtual override {
    uint8 eModeId = 1;
    DataTypes.CollateralConfig memory prevEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    string memory prevLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);
    CollateralRiskSteward.EModeDebounce memory prevLastUpdated = steward.getEModeTimelock(eModeId);

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      label: EngineFlags.KEEP_CURRENT_STRING
    });

    vm.startPrank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);

    DataTypes.CollateralConfig memory afterEmodeConfig = AaveV3Ethereum
      .POOL
      .getEModeCategoryCollateralConfig(eModeId);
    CollateralRiskSteward.EModeDebounce memory afterLastUpdated = steward.getEModeTimelock(eModeId);
    string memory afterLabel = AaveV3Ethereum.POOL.getEModeCategoryLabel(eModeId);

    assertEq(afterEmodeConfig.ltv, prevEmodeConfig.ltv);
    assertEq(afterEmodeConfig.liquidationThreshold, prevEmodeConfig.liquidationThreshold);
    assertEq(afterEmodeConfig.liquidationBonus, prevEmodeConfig.liquidationBonus);
    assertEq(afterLabel, prevLabel);

    assertEq(prevLastUpdated.eModeLtvLastUpdated, afterLastUpdated.eModeLtvLastUpdated);
    assertEq(
      prevLastUpdated.eModeLiquidationThresholdLastUpdated,
      afterLastUpdated.eModeLiquidationThresholdLastUpdated
    );
    assertEq(
      prevLastUpdated.eModeLiquidationBonusLastUpdated,
      afterLastUpdated.eModeLiquidationBonusLastUpdated
    );
  }

  /// should revert as UpdateNotAllowed
  function test_updateEModeCategories_labelChangeNotAllowed() public virtual override {
    uint8 eModeId = 1;
    string memory newLabel = 'NEW_EMODE_LABEL';

    IEngine.EModeCategoryUpdate[] memory eModeCategoryUpdates = new IEngine.EModeCategoryUpdate[](
      1
    );
    eModeCategoryUpdates[0] = IEngine.EModeCategoryUpdate({
      eModeCategory: eModeId,
      ltv: EngineFlags.KEEP_CURRENT,
      liqThreshold: EngineFlags.KEEP_CURRENT,
      liqBonus: EngineFlags.KEEP_CURRENT,
      label: newLabel
    });

    vm.prank(riskCouncil);
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateEModeCategories(eModeCategoryUpdates);
  }

  /* ----------------------------- Rates Tests ----------------------------- */
  function test_updateRates_revertsWith_UpdateNotAllowed() public virtual {
    IEngine.RateStrategyUpdate[] memory rateUpdates = new IEngine.RateStrategyUpdate[](1);
    rateUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3EthereumAssets.WETH_UNDERLYING,
      params: IEngine.InterestRateInputData({
        optimalUsageRatio: 0,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 0,
        variableRateSlope2: 0
      })
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);
  }

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
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateRates(rateUpdates);

    (
      uint256 afterOptimalUsageRatio,
      uint256 afterBaseVariableBorrowRate,
      uint256 afterVariableRateSlope1,
      uint256 afterVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    CollateralRiskSteward.Debounce memory lastUpdated = steward.getTimelock(
      AaveV3EthereumAssets.WETH_UNDERLYING
    );
    // changes are not applied as update reverted
    assertNotEq(afterOptimalUsageRatio, rateUpdates[0].params.optimalUsageRatio);
    assertNotEq(afterBaseVariableBorrowRate, rateUpdates[0].params.baseVariableBorrowRate);
    assertNotEq(afterVariableRateSlope1, rateUpdates[0].params.variableRateSlope1);
    assertNotEq(afterVariableRateSlope2, rateUpdates[0].params.variableRateSlope2);

    assertNotEq(lastUpdated.optimalUsageRatioLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.baseVariableRateLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.variableRateSlope1LastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.variableRateSlope2LastUpdated, vm.getBlockTimestamp());

    // after min time passed test rates decrease
    skip(1);

    (
      beforeOptimalUsageRatio,
      beforeBaseVariableBorrowRate,
      beforeVariableRateSlope1,
      beforeVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    steward.updateRates(rateUpdates);
    vm.stopPrank();

    (
      afterOptimalUsageRatio,
      afterBaseVariableBorrowRate,
      afterVariableRateSlope1,
      afterVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);
    lastUpdated = steward.getTimelock(AaveV3EthereumAssets.WETH_UNDERLYING);

    // changes are not applied as update reverted
    assertNotEq(afterOptimalUsageRatio, rateUpdates[0].params.optimalUsageRatio);
    assertNotEq(afterBaseVariableBorrowRate, rateUpdates[0].params.baseVariableBorrowRate);
    assertNotEq(afterVariableRateSlope1, rateUpdates[0].params.variableRateSlope1);
    assertNotEq(afterVariableRateSlope2, rateUpdates[0].params.variableRateSlope2);

    assertNotEq(lastUpdated.optimalUsageRatioLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.baseVariableRateLastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.variableRateSlope1LastUpdated, vm.getBlockTimestamp());
    assertNotEq(lastUpdated.variableRateSlope2LastUpdated, vm.getBlockTimestamp());
  }

  function test_updateRates_outOfRange() public virtual override {
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
        optimalUsageRatio: beforeOptimalUsageRatio + 12_00, // 12% absolute increase
        baseVariableBorrowRate: beforeBaseVariableBorrowRate + 12_00, // 12% absolute increase
        variableRateSlope1: beforeVariableRateSlope1 + 12_00, // 12% absolute increase
        variableRateSlope2: beforeVariableRateSlope2 + 12_00 // 12% absolute increase
      })
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);
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

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);

    (
      beforeOptimalUsageRatio,
      beforeBaseVariableBorrowRate,
      beforeVariableRateSlope1,
      beforeVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    rateUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3EthereumAssets.WETH_UNDERLYING,
      params: IEngine.InterestRateInputData({
        optimalUsageRatio: beforeOptimalUsageRatio + 1,
        baseVariableBorrowRate: beforeBaseVariableBorrowRate + 1,
        variableRateSlope1: beforeVariableRateSlope1 + 1,
        variableRateSlope2: beforeVariableRateSlope2 + 1
      })
    });

    // reverts due to UpdateNotAllowed, not debounce
    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);
  }

  function test_updateRates_assetUnlisted() public virtual override {
    IEngine.RateStrategyUpdate[] memory rateUpdates = new IEngine.RateStrategyUpdate[](1);
    rateUpdates[0] = IEngine.RateStrategyUpdate({
      asset: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stETH
      params: IEngine.InterestRateInputData({
        optimalUsageRatio: 40_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 2_00,
        variableRateSlope2: 50_00
      })
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);
  }

  function test_updateRates_assetRestricted() public virtual override {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.setAddressRestricted(AaveV3EthereumAssets.GHO_UNDERLYING, true);
    vm.stopPrank();

    IEngine.RateStrategyUpdate[] memory rateUpdates = new IEngine.RateStrategyUpdate[](1);
    rateUpdates[0] = IEngine.RateStrategyUpdate({
      asset: AaveV3EthereumAssets.GHO_UNDERLYING,
      params: IEngine.InterestRateInputData({
        optimalUsageRatio: 40_00,
        baseVariableBorrowRate: 0,
        variableRateSlope1: 2_00,
        variableRateSlope2: 50_00
      })
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);
  }

  function test_updateRates_allKeepCurrent() public virtual override {
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
        optimalUsageRatio: EngineFlags.KEEP_CURRENT,
        baseVariableBorrowRate: EngineFlags.KEEP_CURRENT,
        variableRateSlope1: EngineFlags.KEEP_CURRENT,
        variableRateSlope2: EngineFlags.KEEP_CURRENT
      })
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);

    (
      uint256 afterOptimalUsageRatio,
      uint256 afterBaseVariableBorrowRate,
      uint256 afterVariableRateSlope1,
      uint256 afterVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    // remains the same because update reverted
    assertEq(beforeOptimalUsageRatio, afterOptimalUsageRatio);
    assertEq(beforeBaseVariableBorrowRate, afterBaseVariableBorrowRate);
    assertEq(beforeVariableRateSlope1, afterVariableRateSlope1);
    assertEq(beforeVariableRateSlope2, afterVariableRateSlope2);
  }

  function test_updateRate_sameUpdate() public virtual override {
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
        optimalUsageRatio: beforeOptimalUsageRatio,
        baseVariableBorrowRate: beforeBaseVariableBorrowRate,
        variableRateSlope1: beforeVariableRateSlope1,
        variableRateSlope2: beforeVariableRateSlope2
      })
    });

    vm.expectRevert(IRiskSteward.UpdateNotAllowed.selector);
    vm.prank(riskCouncil);
    steward.updateRates(rateUpdates);

    (
      uint256 afterOptimalUsageRatio,
      uint256 afterBaseVariableBorrowRate,
      uint256 afterVariableRateSlope1,
      uint256 afterVariableRateSlope2
    ) = _getInterestRatesForAsset(AaveV3EthereumAssets.WETH_UNDERLYING);

    // remains the same because update reverted
    assertEq(beforeOptimalUsageRatio, afterOptimalUsageRatio);
    assertEq(beforeBaseVariableBorrowRate, afterBaseVariableBorrowRate);
    assertEq(beforeVariableRateSlope1, afterVariableRateSlope1);
    assertEq(beforeVariableRateSlope2, afterVariableRateSlope2);
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
    steward.updateCollateralSide(collateralUpdates);

    collateralUpdates[0] = IEngine.CollateralUpdate({
      asset: AaveV3EthereumAssets.UNI_UNDERLYING,
      ltv: ltvBefore - 11_00, // 11% absolute decrease
      liqThreshold: ltBefore - 11_00, // 11% absolute decrease
      liqBonus: (lbBefore - 100_00) - 2_50, // 2.5% absolute decrease
      debtCeiling: (debtCeilingBefore * 85) / 100, // 15% relative decrease
      liqProtocolFee: EngineFlags.KEEP_CURRENT
    });

    // with 0 delay, range is satisfied
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

    vm.warp(vm.getBlockTimestamp() + 1 days);

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

    // delay time is 0 so debounce is respected
    steward.updateCollateralSide(collateralUpdates);
    vm.stopPrank();
  }
}
