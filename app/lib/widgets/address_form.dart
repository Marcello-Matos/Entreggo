import 'package:flutter/material.dart';

import '../api/models.dart';
import '../scanning/label_parser.dart';

/// Folha para confirmar/corrigir o endereço (lido da etiqueta ou digitado).
Future<AddressInput?> showAddressForm(
  BuildContext context, {
  String title = 'Confirmar endereço',
  ParsedLabel? label,
  Package? package,
}) => showModalBottomSheet<AddressInput>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _AddressForm(title: title, label: label, package: package),
);

class _AddressForm extends StatefulWidget {
  const _AddressForm({required this.title, this.label, this.package});

  final String title;
  final ParsedLabel? label;
  final Package? package;

  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  final _formKey = GlobalKey<FormState>();
  late final _address = TextEditingController(
    text: widget.label?.address ?? widget.package?.addressText,
  );
  late final _city = TextEditingController(
    text: widget.label?.city ?? widget.package?.city,
  );
  late final _state = TextEditingController(
    text: widget.label?.state ?? widget.package?.state,
  );
  late final _cep = TextEditingController(
    text: widget.label?.postalCode ?? widget.package?.postalCode,
  );
  late final _notes = TextEditingController(
    text: widget.label?.complement ?? widget.package?.deliveryNotes,
  );

  @override
  void dispose() {
    for (final c in [_address, _city, _state, _cep, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _value(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      AddressInput(
        address: _address.text.trim(),
        city: _value(_city),
        state: _value(_state)?.toUpperCase(),
        postalCode: _value(_cep),
        notes: _value(_notes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readFromLabel = widget.label != null && !widget.label!.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                readFromLabel
                    ? 'Lido da etiqueta. Confira antes de salvar.'
                    : widget.label != null
                    ? 'Não consegui ler o endereço. Digite abaixo.'
                    : 'Rua, número e bairro.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _address,
                autofocus: !readFromLabel,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                  hintText: 'Rua, número, bairro',
                ),
                validator: (v) => v == null || v.trim().length < 3
                    ? 'Informe o endereço'
                    : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _state,
                      maxLength: 2,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'UF',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cep,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: const InputDecoration(
                        labelText: 'CEP',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _notes,
                      decoration: const InputDecoration(
                        labelText: 'Complemento',
                        hintText: 'Apto, bloco...',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: const Text('Salvar')),
            ],
          ),
        ),
      ),
    );
  }
}
