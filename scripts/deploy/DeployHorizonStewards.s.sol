// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'solidity-utils/contracts/utils/ScriptUtils.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';
import {RiskSteward, IRiskSteward} from '../../src/contracts/RiskSteward.sol';

library DeployHorizonRiskStewards {
  function _deployRiskStewards(
    address pool,
    address configEngine,
    address riskCouncil,
    address governance
  ) internal returns (address) {
    address riskSteward = address(
      new RiskSteward(pool, configEngine, riskCouncil, governance, _getRiskConfig())
    );
    return riskSteward;
  }

  function _getRiskConfig() internal pure returns (IRiskSteward.Config memory) {
    // only collateralConfig will be applied; other config changes will be reverted by the CollateralRiskSteward
    return
      IRiskSteward.Config({
        collateralConfig: IRiskSteward.CollateralConfig({
          ltv: IRiskSteward.RiskParamConfig({minDelay: 0, maxPercentChange: type(uint256).max}),
          liquidationThreshold: IRiskSteward.RiskParamConfig({
            minDelay: 0,
            maxPercentChange: type(uint256).max
          }),
          liquidationBonus: IRiskSteward.RiskParamConfig({
            minDelay: 0,
            maxPercentChange: type(uint256).max
          }),
          debtCeiling: IRiskSteward.RiskParamConfig({
            minDelay: 0,
            maxPercentChange: type(uint256).max
          })
        }),
        eModeConfig: IRiskSteward.EmodeConfig({
          ltv: IRiskSteward.RiskParamConfig({minDelay: 3 days, maxPercentChange: 50}),
          liquidationThreshold: IRiskSteward.RiskParamConfig({
            minDelay: 3 days,
            maxPercentChange: 10
          }),
          liquidationBonus: IRiskSteward.RiskParamConfig({minDelay: 3 days, maxPercentChange: 50})
        }),
        rateConfig: IRiskSteward.RateConfig({
          baseVariableBorrowRate: IRiskSteward.RiskParamConfig({
            minDelay: 3 days,
            maxPercentChange: 1_00
          }),
          variableRateSlope1: IRiskSteward.RiskParamConfig({
            minDelay: 3 days,
            maxPercentChange: 1_00
          }),
          variableRateSlope2: IRiskSteward.RiskParamConfig({
            minDelay: 3 days,
            maxPercentChange: 20_00
          }),
          optimalUsageRatio: IRiskSteward.RiskParamConfig({
            minDelay: 3 days,
            maxPercentChange: 3_00
          })
        }),
        capConfig: IRiskSteward.CapConfig({
          supplyCap: IRiskSteward.RiskParamConfig({minDelay: 3 days, maxPercentChange: 100_00}),
          borrowCap: IRiskSteward.RiskParamConfig({minDelay: 3 days, maxPercentChange: 100_00})
        }),
        priceCapConfig: IRiskSteward.PriceCapConfig({
          priceCapLst: IRiskSteward.RiskParamConfig({minDelay: 3 days, maxPercentChange: 5_00}),
          priceCapStable: IRiskSteward.RiskParamConfig({minDelay: 3 days, maxPercentChange: 50}),
          discountRatePendle: IRiskSteward.RiskParamConfig({
            minDelay: 2 days,
            maxPercentChange: 0.025e18
          })
        })
      });
  }
}

// make deploy-ledger contract=scripts/deploy/DeployStewards.s.sol:DeployEthereum chain=mainnet
contract DeployEthereum is EthereumScript {
  function run() external {
    vm.startBroadcast();
    DeployHorizonRiskStewards._deployRiskStewards(
      address(AaveV3Ethereum.POOL),
      AaveV3Ethereum.CONFIG_ENGINE,
      address(1), // TODO: advanced multisig
      address(1) // TODO: advanced multisig
    );
    vm.stopBroadcast();
  }
}
