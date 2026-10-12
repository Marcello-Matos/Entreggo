/// Configuração injetada em build/run via `--dart-define` (ou `--dart-define-from-file`).
/// As credenciais do Firebase ficam em `firebase_options.dart` (gerado pelo `flutterfire configure`).
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
}
