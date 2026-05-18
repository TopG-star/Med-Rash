class AppConfig {
  const AppConfig._();

  static const String functionsBaseUrl = String.fromEnvironment(
    'MEDRASH_FUNCTIONS_BASE_URL',
    defaultValue: 'http://localhost:8888/.netlify/functions/',
  );

  static const String gateApiKey = String.fromEnvironment(
    'MEDRASH_GATE_API_KEY',
    defaultValue: '',
  );
}

