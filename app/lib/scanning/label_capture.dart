import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'label_parser.dart';
import 'text_recognizer.dart';

/// Fotografa (ou escolhe da galeria) uma etiqueta e extrai o endereço.
/// Retorna `null` se o usuário cancelar; `ParsedLabel` vazio se não conseguir ler.
Future<ParsedLabel?> captureLabel(
  BuildContext context, {
  ImageSource source = ImageSource.camera,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final XFile? photo;
  try {
    photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2200,
      imageQuality: 92,
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Não foi possível abrir a câmera: $e')),
    );
    return null;
  }
  if (photo == null || !context.mounted) return null;

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Lendo etiqueta...')),
          ],
        ),
      ),
    ),
  );
  try {
    return parseLabel(await LabelTextRecognizer.recognize(photo.path));
  } on LabelReadException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return const ParsedLabel();
  } finally {
    navigator.pop();
  }
}
