import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

/// Dados do comprovante coletados na confirmação de entrega/tentativa.
class ProofData {
  const ProofData({this.recipientName, this.note, this.photo, this.photoName});

  final String? recipientName;
  final String? note;
  final Uint8List? photo;
  final String? photoName;
}

const failureReasons = [
  'Destinatário ausente',
  'Endereço não localizado',
  'Endereço incorreto ou incompleto',
  'Recusado pelo recebedor',
  'Local fechado',
  'Outro motivo',
];

/// Abre o formulário de comprovante. `null` se o usuário cancelar.
Future<ProofData?> showProofSheet(
  BuildContext context, {
  required bool delivered,
}) => showModalBottomSheet<ProofData>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _ProofSheet(delivered: delivered),
  ),
);

class _ProofSheet extends StatefulWidget {
  const _ProofSheet({required this.delivered});

  final bool delivered;

  @override
  State<_ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<_ProofSheet> {
  final _recipient = TextEditingController();
  final _note = TextEditingController();
  Uint8List? _photo;
  String? _photoName;
  String? _reason;

  @override
  void dispose() {
    _recipient.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() {
        _photo = bytes;
        _photoName = file.name;
      });
    }
  }

  void _confirm() => Navigator.pop(
    context,
    ProofData(
      recipientName: _recipient.text.trim().isEmpty
          ? null
          : _recipient.text.trim(),
      note: [
        ?_reason,
        if (_note.text.trim().isNotEmpty) _note.text.trim(),
      ].join(' — '),
      photo: _photo,
      photoName: _photoName,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final delivered = widget.delivered;
    final canConfirm = delivered || _reason != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              delivered ? 'Confirmar entrega' : 'Entrega não realizada',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _takePhoto,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: EntreggoColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo != null
                    ? Image.memory(_photo!, fit: BoxFit.cover)
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 34,
                            color: EntreggoColors.primary,
                          ),
                          SizedBox(height: 6),
                          Text('Foto do pacote no local (opcional)'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            if (delivered) ...[
              TextField(
                controller: _recipient,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Recebido por (opcional)',
                  hintText: 'Nome de quem recebeu',
                ),
              ),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Motivo',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in failureReasons)
                    ChoiceChip(
                      label: Text(reason),
                      selected: _reason == reason,
                      onSelected: (_) => setState(() => _reason = reason),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Detalhes da tentativa',
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.my_location, size: 16, color: EntreggoColors.slate),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Localização e horário registrados automaticamente',
                    style: TextStyle(fontSize: 12, color: EntreggoColors.slate),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: delivered
                    ? Colors.green.shade600
                    : Colors.orange.shade800,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: canConfirm ? _confirm : null,
              child: Text(delivered ? 'Confirmar entrega' : 'Registrar motivo'),
            ),
          ],
        ),
      ),
    );
  }
}
