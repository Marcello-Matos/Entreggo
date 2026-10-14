import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

/// Dados do comprovante coletados na confirmação de entrega/tentativa.
class ProofData {
  const ProofData({
    this.recipientName,
    this.deliveryMethod,
    this.note,
    this.photo,
    this.photoName,
  });

  final String? recipientName;
  final String? deliveryMethod;
  final String? note;
  final Uint8List? photo;
  final String? photoName;
}

/// Como a entrega foi concluída (vai para o comprovante).
const deliveryMethods = [
  (label: 'Cliente assinou', icon: Icons.draw_outlined),
  (label: 'Porteiro', icon: Icons.door_front_door_outlined),
  (label: 'Caixa de correio', icon: Icons.markunread_mailbox_outlined),
  (label: 'Vizinho', icon: Icons.people_outline),
  (label: 'Recepção', icon: Icons.desk_outlined),
  (label: 'Outro', icon: Icons.more_horiz),
];

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
  String? _method;

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
      deliveryMethod: _method,
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
            if (_photo == null)
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
                  child: const Column(
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
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  _photo!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.green.shade600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Foto adicionada',
                      style: TextStyle(color: Colors.green.shade700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Tirar novamente'),
                  ),
                  IconButton(
                    tooltip: 'Remover foto',
                    onPressed: () => setState(() => _photo = null),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (delivered) ...[
              TextField(
                controller: _recipient,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Recebido por (opcional)',
                  hintText: 'Ex.: Cliente, Porteiro, Vizinho...',
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Como foi a entrega?',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in deliveryMethods)
                    ChoiceChip(
                      avatar: Icon(m.icon, size: 18),
                      label: Text(m.label),
                      selected: _method == m.label,
                      onSelected: (_) => setState(() => _method = m.label),
                    ),
                ],
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
