/// Central feature-flag configuration.
///
/// To switch the advisory "portfolio" card between Smallcase and Model Portfolios:
///   - Set [advisoryMode] to [AdvisoryPortfolioMode.smallcase]   → shows Smallcase card
///   - Set [advisoryMode] to [AdvisoryPortfolioMode.modelPortfolio] → shows Model Portfolios card
enum AdvisoryPortfolioMode { smallcase, modelPortfolio }

class AppConfig {
  // ── Advisory tab third card ──────────────────────────────────────────────
  static const AdvisoryPortfolioMode advisoryMode =
      AdvisoryPortfolioMode.smallcase;

  /// Smallcase gateway URL used when [advisoryMode] == [AdvisoryPortfolioMode.smallcase]
  static const String smallcaseUrl = 'https://tidiwealth.smallcase.com/';

  // ── In-app update prompt ─────────────────────────────────────────────────
  /// When true the update sheet cannot be dismissed (mandatory update).
  /// When false the user can tap "Maybe Later" to skip.
  static const bool forceUpdate = false;
}
