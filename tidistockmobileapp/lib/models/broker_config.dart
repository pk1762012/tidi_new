enum BrokerAuthType { oauth, hybrid, credential }

class BrokerFieldConfig {
  final String label;
  final String key; // Used as the API body parameter key
  final bool isSecret;
  final String placeholder;

  const BrokerFieldConfig({
    required this.label,
    required this.key,
    this.isSecret = false,
    this.placeholder = '',
  });
}

class BrokerConfig {
  final String name;
  final String key;
  final String logoAsset;
  final BrokerAuthType authType;
  final List<BrokerFieldConfig> fields;
  final String? youtubeVideoId;
  final List<String> instructionSteps;
  final String? instructionNote;
  final String? redirectUrl;

  const BrokerConfig({
    required this.name,
    required this.key,
    required this.logoAsset,
    required this.authType,
    this.fields = const [],
    this.youtubeVideoId,
    this.instructionSteps = const [],
    this.instructionNote,
    this.redirectUrl,
  });

  String get iconLetter => name.isNotEmpty ? name[0] : '?';
}

class BrokerRegistry {
  static const List<BrokerConfig> brokers = [
    // ── Zerodha ─────────────────────────────────────────────────────────
    // Publisher login (pure OAuth) — uses company API key, no user credentials.
    BrokerConfig(
      name: 'Zerodha',
      key: 'zerodha',
      logoAsset: 'assets/images/brokers/zerodha.png',
      authType: BrokerAuthType.oauth,
      fields: [],
      instructionSteps: [],
    ),

    // ── Angel One ───────────────────────────────────────────────────────
    BrokerConfig(
      name: 'Angel One',
      key: 'angelone',
      logoAsset: 'assets/images/brokers/angelone.png',
      authType: BrokerAuthType.oauth,
      // Pure OAuth — no credential form. Handled by BrokerAuthPage.
      fields: [],
      instructionSteps: [],
    ),

    // ── Groww ───────────────────────────────────────────────────────────
    // OAuth via CCXT — no user credentials needed.
    BrokerConfig(
      name: 'Groww',
      key: 'groww',
      logoAsset: 'assets/images/brokers/groww.png',
      authType: BrokerAuthType.oauth,
      fields: [],
      instructionSteps: [],
    ),

    // ── Upstox ──────────────────────────────────────────────────────────
    BrokerConfig(
      name: 'Upstox',
      key: 'upstox',
      logoAsset: 'assets/images/brokers/upstox.png',
      authType: BrokerAuthType.hybrid,
      youtubeVideoId: 'yfTXrjl0k3E',
      fields: [
        BrokerFieldConfig(
          label: 'API Key',
          key: 'apiKey',
          placeholder: 'Enter API key',
        ),
        BrokerFieldConfig(
          label: 'Secret Key',
          key: 'secretKey',
          isSecret: true,
          placeholder: 'Enter secret key',
        ),
      ],
      instructionSteps: [
        'Visit https://shorturl.at/plWYJ and log in using your phone number. Verify with OTP.',
        'Enter your 6-digit PIN and continue.',
        'Click "New App", fill in "App Name". Enter the "Redirect URL" shown below. Skip Postback URL and Description. Accept Terms & Conditions and click "Continue".',
        'Review details (make sure you don\'t have more than 2 apps) and click "Confirm Plan". Click "Done".',
        'Click on the newly created app, copy your API and Secret Key, and enter them below.',
      ],
    ),

    // ── ICICI Direct ────────────────────────────────────────────────────
    BrokerConfig(
      name: 'ICICI Direct',
      key: 'icicidirect',
      logoAsset: 'assets/images/brokers/icici.png',
      authType: BrokerAuthType.hybrid,
      youtubeVideoId: 'XFLjL8hOctI',
      fields: [
        BrokerFieldConfig(
          label: 'API Key',
          key: 'apiKey',
          placeholder: 'Enter API key',
        ),
        BrokerFieldConfig(
          label: 'Secret Key',
          key: 'secretKey',
          isSecret: true,
          placeholder: 'Enter secret key',
        ),
      ],
      instructionSteps: [
        'Visit https://api.icicidirect.com/apiuser/home and log in with your username and password. Verify with OTP.',
        'Click on "Register an App", fill in "App Name". Enter the "Redirect URL" shown below and click "Submit".',
        'Navigate to "View Apps" tab, copy your API and Secret Key, and enter them below.',
      ],
    ),

    // ── Hdfc Securities ─────────────────────────────────────────────────
    BrokerConfig(
      name: 'Hdfc Securities',
      key: 'hdfc',
      logoAsset: 'assets/images/brokers/hdfc.png',
      authType: BrokerAuthType.hybrid,
      youtubeVideoId: 'iziwR2zLLvk',
      fields: [
        BrokerFieldConfig(
          label: 'API Key',
          key: 'apiKey',
          placeholder: 'Enter API key',
        ),
        BrokerFieldConfig(
          label: 'Secret Key',
          key: 'secretKey',
          isSecret: true,
          placeholder: 'Enter secret key',
        ),
      ],
      instructionSteps: [
        'Go to https://developer.hdfcsec.com/',
        'Log in with your ID, password, and OTP.',
        'Accept the Risk Disclosure.',
        'Click "Create" to make a new app. Enter app name, Redirect URL (shown below), and description. Then click "Create".',
        'Copy the API and Secret Key, and paste them below.',
      ],
    ),

    // ── Fyers ───────────────────────────────────────────────────────────
    BrokerConfig(
      name: 'Fyers',
      key: 'fyers',
      logoAsset: 'assets/images/brokers/fyers.png',
      authType: BrokerAuthType.hybrid,
      youtubeVideoId: 'blhTiePBIg0',
      fields: [
        BrokerFieldConfig(
          label: 'App ID',
          key: 'clientCode',
          placeholder: 'Enter App ID',
        ),
        BrokerFieldConfig(
          label: 'Secret ID',
          key: 'secretKey',
          isSecret: true,
          placeholder: 'Enter Secret ID',
        ),
      ],
      instructionSteps: [
        'Visit Fyers API Dashboard at myapi.fyers.in/dashboard',
        'Log in using your phone number, TOTP, and 4-digit PIN.',
        'Create a new app:\n'
            '  - Click "Create App"\n'
            '  - Set Redirect URL (shown below)\n'
            '  - Grant all app permissions and accept terms',
        'Copy App ID and Secret ID from the newly created app.',
        'Paste credentials below to connect.',
      ],
    ),

    // ── Motilal Oswal ───────────────────────────────────────────────────
    BrokerConfig(
      name: 'Motilal Oswal',
      key: 'motilal',
      logoAsset: 'assets/images/brokers/motilal.png',
      authType: BrokerAuthType.hybrid,
      youtubeVideoId: 'gGKedxU-sQ0',
      redirectUrl: 'https://ccxt.alphaquark.in/motilal-oswal/callback',
      fields: [
        BrokerFieldConfig(
          label: 'Client Code',
          key: 'clientCode',
          placeholder: 'Enter client code',
        ),
        BrokerFieldConfig(
          label: 'API Key',
          key: 'apiKey',
          placeholder: 'Enter API key',
        ),
      ],
      instructionSteps: [
        'Visit https://www.motilaloswal.com',
        'Login: Click "Customer Login" → Select "Older Version" to log in.',
        'Get Client Code: Click the Profile Icon at the top to find your Client Code.',
        'Navigate to Trading API: Click hamburger menu (☰) → "Trading API".',
        'Create API Key:\n'
            '  - Click "Create an API Key"\n'
            '  - Set Redirect URL: https://ccxt.alphaquark.in/motilal-oswal/callback\n'
            '  - Click "Create"',
        'Copy your API Key and Client Code, and paste them below.',
      ],
    ),

    // ── Dhan ────────────────────────────────────────────────────────────
    BrokerConfig(
      name: 'Dhan',
      key: 'dhan',
      logoAsset: 'assets/images/brokers/dhan.png',
      authType: BrokerAuthType.credential,
      youtubeVideoId: 'MhAfqNQKSrQ',
      fields: [
        BrokerFieldConfig(
          label: 'Client ID',
          key: 'clientCode',
          placeholder: 'Enter client ID',
        ),
        BrokerFieldConfig(
          label: 'Access Token',
          key: 'jwtToken',
          isSecret: true,
          placeholder: 'Enter access token',
        ),
      ],
      instructionSteps: [
        'Login to Dhan at login.dhan.co\n'
            '  Use the QR code option to log in.',
        'Open in desktop view (not available in mobile app).',
        'Find your Client ID:\n'
            '  Click your profile picture → "My Profile on Dhan" → Copy the Client ID.',
        'Navigate to Trading APIs:\n'
            '  Select "Dhan HQ Trading APIs" from the menu.',
        'Generate Access Token:\n'
            '  - Click "+ New Token"\n'
            '  - Enter app name\n'
            '  - Set validity to 30 days\n'
            '  - Click "Generate Token"',
        'Copy the Access Token and paste it below.',
      ],
    ),

    // ── AliceBlue ───────────────────────────────────────────────────────
    BrokerConfig(
      name: 'AliceBlue',
      key: 'aliceblue',
      logoAsset: 'assets/images/brokers/aliceblue.png',
      authType: BrokerAuthType.credential,
      youtubeVideoId: 'YaONYqsiwGQ',
      fields: [
        BrokerFieldConfig(
          label: 'User ID',
          key: 'clientCode',
          placeholder: 'Enter User ID',
        ),
        BrokerFieldConfig(
          label: 'API Key',
          key: 'apiKey',
          placeholder: 'Enter API key',
        ),
      ],
      instructionSteps: [
        'Login to Alice Blue at ant.aliceblueonline.com\n'
            '  Use your phone number, password, and TOTP/OTP.',
        'Accept Risk Disclosure: If prompted, click "Proceed".',
        'Get API Key: Go to "Apps" tab → Select "API Key" → Copy it.',
        'Get User ID: Click profile icon → "Your Profile/Settings" → Copy Client ID.',
      ],
      instructionNote:
          'Note: API Key is valid for 24 hours only. You will need to generate a new one daily.',
    ),

    // ── Kotak ───────────────────────────────────────────────────────────
    BrokerConfig(
      name: 'Kotak',
      key: 'kotak',
      logoAsset: 'assets/images/brokers/kotak.png',
      authType: BrokerAuthType.credential,
      fields: [
        BrokerFieldConfig(
          label: 'Unique Client Code',
          key: 'ucc',
          placeholder: 'Enter UCC',
        ),
        BrokerFieldConfig(
          label: 'Consumer Key',
          key: 'apiKey',
          placeholder: 'Enter consumer key',
        ),
        BrokerFieldConfig(
          label: 'Consumer Secret',
          key: 'secretKey',
          isSecret: true,
          placeholder: 'Enter consumer secret',
        ),
        BrokerFieldConfig(
          label: 'Mobile Number',
          key: 'mobileNumber',
          placeholder: 'Enter 10-digit mobile number',
        ),
        BrokerFieldConfig(
          label: 'M-PIN',
          key: 'mpin',
          isSecret: true,
          placeholder: 'Enter 6-digit M-PIN',
        ),
        BrokerFieldConfig(
          label: 'TOTP',
          key: 'totp',
          placeholder: 'Enter 6-digit TOTP',
        ),
      ],
      instructionSteps: [
        'Step 1 — NEO Trade API Access:\n'
            '  - Login to https://www.kotaksecurities.com/platform/kotak-neo-trade-api/\n'
            '  - Register for Kotak Neo Trade API with your Client ID\n'
            '  - You will receive User ID, password, and Neo Finkey via email',
        'Step 2 — Getting Consumer Keys:\n'
            '  - Log into https://napi.kotaksecurities.com/devportal/apis\n'
            '  - Create a new Application\n'
            '  - Subscribe to all available APIs\n'
            '  - Go to "Production Keys" → "Generate Keys"\n'
            '  - Copy Consumer Key and Consumer Secret',
        'Step 3 — TOTP Registration:\n'
            '  - Go to https://www.kotaksecurities.com/platform/kotak-neo-trade-api/totp-registration/\n'
            '  - Verify mobile number with OTP\n'
            '  - Scan QR code with authenticator app (e.g., Google Authenticator)',
        'Step 4 — Enter credentials below.',
      ],
      instructionNote:
          'Validation: Mobile must be 10 digits. M-PIN and TOTP must be 6 digits each.',
    ),

    // ── IIFL Securities ─────────────────────────────────────────────────
    BrokerConfig(
      name: 'IIFL Securities',
      key: 'iifl',
      logoAsset: 'assets/images/brokers/iifl.png',
      authType: BrokerAuthType.credential,
      fields: [
        BrokerFieldConfig(
          label: 'Client Code',
          key: 'clientCode',
          placeholder: 'Enter client code',
        ),
        BrokerFieldConfig(
          label: 'API Key',
          key: 'apiKey',
          placeholder: 'Enter API key',
        ),
      ],
      instructionSteps: [
        'Login to your IIFL Securities account.',
        'Navigate to API settings and copy your Client Code and API Key.',
        'Paste the credentials below to connect.',
      ],
    ),
  ];

  static BrokerConfig? getByKey(String key) {
    final lowerKey = key.toLowerCase().replaceAll(' ', '');
    try {
      return brokers.firstWhere(
        (b) =>
            b.key == lowerKey ||
            b.name.toLowerCase().replaceAll(' ', '') == lowerKey,
      );
    } catch (_) {
      return null;
    }
  }

  static BrokerConfig? getByName(String name) {
    try {
      return brokers.firstWhere(
        (b) => b.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}
