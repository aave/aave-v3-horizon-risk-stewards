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
          ltv: IRiskSteward.RiskParamConfig({minDelay: 0, maxPercentChange: type(uint128).max}),
          liquidationThreshold: IRiskSteward.RiskParamConfig({
            minDelay: 0,
            maxPercentChange: type(uint128).max
          }),
          liquidationBonus: IRiskSteward.RiskParamConfig({
            minDelay: 0,
            maxPercentChange: type(uint128).max
          }),
          debtCeiling: IRiskSteward.RiskParamConfig({
            minDelay: 0,
            maxPercentChange: type(uint128).max
          })
        }),
        eModeConfig: IRiskSteward.EmodeConfig({
          ltv: IRiskSteward.RiskParamConfig({minDelay: type(uint40).max, maxPercentChange: 0}),
          liquidationThreshold: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          liquidationBonus: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          })
        }),
        rateConfig: IRiskSteward.RateConfig({
          baseVariableBorrowRate: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          variableRateSlope1: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          variableRateSlope2: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          optimalUsageRatio: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          })
        }),
        capConfig: IRiskSteward.CapConfig({
          supplyCap: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          borrowCap: IRiskSteward.RiskParamConfig({minDelay: type(uint40).max, maxPercentChange: 0})
        }),
        priceCapConfig: IRiskSteward.PriceCapConfig({
          priceCapLst: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          priceCapStable: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          }),
          discountRatePendle: IRiskSteward.RiskParamConfig({
            minDelay: type(uint40).max,
            maxPercentChange: 0
          })
        })
      });
  }
}

// make deploy-ledger contract=scripts/deploy/DeployHorizonStewards.s.sol:DeployEthereum chain=mainnet
// dry run: make deploy-pk contract=scripts/deploy/DeployHorizonStewards.s.sol:DeployEthereum chain=mainnet dry=1
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
