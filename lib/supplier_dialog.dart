import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';

/// Cadastro rápido de fornecedor, como o da tela web, com CNPJ e razão
/// social já preenchidos pelo XML. Devolve true quando gravou.
Future<bool> showSupplierDialog(BuildContext context,
    {required String taxId, String name = ''}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SupplierDialog(taxId: taxId, name: name),
  );
  return ok == true;
}

class _SupplierDialog extends StatefulWidget {
  final String taxId;
  final String name;
  const _SupplierDialog({required this.taxId, required this.name});

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _form = GlobalKey<FormState>();
  late final _taxId = TextEditingController(text: widget.taxId);
  late final _name = TextEditingController(text: widget.name);
  final _fantasy = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_taxId, _name, _fantasy, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.instance.createSupplier({
        'tax_id': onlyDigits(_taxId.text),
        'name': _name.text.trim(),
        'fantasy_name': _opt(_fantasy),
        'email': _opt(_email),
        'phone': _opt(_phone),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fornecedor não cadastrado'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'O emitente desta NF-e ainda não está no cadastro. '
                  'Cadastre para continuar a importação.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _taxId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CNPJ / CPF'),
                validator: (v) {
                  final d = onlyDigits(v ?? '');
                  return d.length == 11 || d.length == 14
                      ? null
                      : 'Informe 11 dígitos (CPF) ou 14 (CNPJ)';
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Razão social / Nome'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe o nome do fornecedor'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _fantasy,
                decoration: const InputDecoration(labelText: 'Nome fantasia'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
