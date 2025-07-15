// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAaveV3ConfigEngine as IEngine} from 'aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol';
import {IRiskSteward, RiskSteward} from './RiskSteward.sol';

/**
 * @title CollateralRiskSteward
 */
contract CollateralRiskSteward is RiskSteward {
  /**
   * @param pool The aave pool to be controlled by the steward
   * @param engine the config engine to be used by the steward
   * @param riskCouncil the safe address of the council being able to interact with the steward
   * @param owner the owner of the risk steward being able to set configs and mark items as restricted
   * @param riskConfig the risk configuration to setup for each individual risk param
   */
  constructor(
    address pool,
    address engine,
    address riskCouncil,
    address owner,
    Config memory riskConfig
  ) RiskSteward(pool, engine, riskCouncil, owner, riskConfig) {}

  /// @inheritdoc IRiskSteward
  function updateCaps(
    IEngine.CapsUpdate[] calldata capsUpdate
  ) external virtual override onlyRiskCouncil {
    revert UpdateNotAllowed();
  }

  /// @inheritdoc IRiskSteward
  function updateRates(
    IEngine.RateStrategyUpdate[] calldata ratesUpdate
  ) external virtual override onlyRiskCouncil {
    revert UpdateNotAllowed();
  }

  /// @inheritdoc IRiskSteward
  function updateEModeCategories(
    IEngine.EModeCategoryUpdate[] calldata eModeCategoryUpdates
  ) external virtual override onlyRiskCouncil {
    revert UpdateNotAllowed();
  }

  /// @inheritdoc IRiskSteward
  function updateLstPriceCaps(
    PriceCapLstUpdate[] calldata priceCapUpdates
  ) external virtual override onlyRiskCouncil {
    revert UpdateNotAllowed();
  }

  /// @inheritdoc IRiskSteward
  function updateStablePriceCaps(
    PriceCapStableUpdate[] calldata priceCapUpdates
  ) external virtual override onlyRiskCouncil {
    revert UpdateNotAllowed();
  }

  /// @inheritdoc IRiskSteward
  function updatePendleDiscountRates(
    DiscountRatePendleUpdate[] calldata discountRateUpdates
  ) external virtual override onlyRiskCouncil {
    revert UpdateNotAllowed();
  }

  function _updateWithinAllowedRange(
    uint256 from,
    uint256 to,
    uint256 maxPercentChange,
    bool isChangeRelative
  ) internal pure virtual override returns (bool) {
    return true;
  }
}
