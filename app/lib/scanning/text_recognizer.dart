import 'package:flutter/services.dart';

/// Lê o texto de uma foto de etiqueta usando o reconhecimento nativo do aparelho
/// (Vision no iOS). Retorna as linhas de cima para baixo.
class LabelTextRecognizer {
  static const _channel = MethodChannel('entreggo/text_recognition');

  static Future<List<String>> recognize(String imagePath) async {
    try {
      final lines = await _channel.invokeListMethod<String>('recognize', {
        'path': imagePath,
      });
      return lines ?? const [];
    } on MissingPluginException {
      throw const LabelReadException(
        'Leitura de etiqueta ainda não disponível neste aparelho. Digite o endereço.',
      );
    } on PlatformException catch (e) {
      throw LabelReadException(
        'Não foi possível ler a etiqueta (${e.message})',
      );
    }
  }
}

class LabelReadException implements Exception {
  const LabelReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
