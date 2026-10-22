import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'models.dart';
import 'ui.dart';

/// Nota já gravada: só leitura, como na tela web. Permite abrir DANFE/XML
/// e excluir (o ERP estorna estoque e contas a pagar). Devolve true se
/// a nota foi excluída.
class InvoicePage extends StatefulWidget {
  final int invoiceId;
  const InvoicePage({super.key, required this.invoiceId});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _api = ApiService.instance;
  Invoice? _inv;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _installments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = widget.invoiceId;
      final results = await Future.wait([
        _api.getInvoice(id),
        _api.listItems(id).catchError((_) => <Map<String, dynamic>>[]),
        _api
            .listInstallments(id)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _inv = results[0] as Invoice;
        _items = results[1] as List<Map<String, dynamic>>;
        _installments = results[2] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final inv = _inv;
    if (inv == null) return;
    final ok = await confirm(context,
        title: 'Excluir nota de entrada',
        message: 'Excluir a NF-e ${inv.number} de ${inv.supplierLabel}?'
            '${inv.stockApplied ? '\n\nO estoque lançado por ela será estornado e as contas a pagar serão apagadas.' : ''}',
        confirmText: 'Excluir',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await withProgress(
          context, 'Excluindo…', () => _api.deleteInvoice(inv.id));
      if (!mounted) return;
      showSnack(context, 'Nota excluída.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, 'Erro ao excluir: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inv;
    return Scaffold(
      appBar: AppBar(
        title: Text(inv == null ? 'Nota de entrada' : 'NF-e ${inv.number}'),
        actions: [
          if (inv != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'del') _delete();
                if (v == 'key') {
                  Clipboard.setData(ClipboardData(text: inv.accessKey));
                  showSnack(context, 'Chave copiada.');
                }
              },
              itemBuilder: (_) => [
                if (inv.accessKey.isNotEmpty)
                  const PopupMenuItem(value: 'key', child: Text('Copiar chave')),
                const PopupMenuItem(value: 'del', child: Text('Excluir nota')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _load, child: const Text('Tentar de novo')),
                    ]),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _body(inv!)),
    );
  }

  Widget _body(Invoice inv) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(inv.supplierLabel,
                          style: theme.textTheme.titleMedium)),
                  StatusChip(statusLabel(inv.status, inv.stockApplied),
                      done: inv.stockApplied),
                ]),
                const SizedBox(height: 8),
                Text(formatMoney(inv.total),
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                InfoRow('Número / Série', '${inv.number} / ${inv.series}'),
                InfoRow('Chave', formatKey(inv.accessKey)),
                InfoRow('Emitente', formatTaxId(inv.issuer)),
                InfoRow('Destinatário', formatTaxId(inv.recipient)),
                InfoRow('Emissão', formatDate(inv.issueDate)),
                InfoRow('Entrada', formatDate(inv.entryDate)),
                if (inv.stockApplied)
                  InfoRow('Estoque lançado', formatDate(inv.stockAppliedAt)),
                InfoRow('Registro', '#${inv.id} • ${formatDate(inv.createdAt)}'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: inv.danfeUrl.isEmpty
                        ? null
                        : () => openUrl(context, inv.danfeUrl),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('DANFE'),
                  ),
                  OutlinedButton.icon(
                    onPressed: inv.xmlUrl.isEmpty
                        ? null
                        : () => openUrl(context, inv.xmlUrl),
                    icon: const Icon(Icons.code),
                    label: const Text('XML'),
                  ),
                ]),
              ],
            ),
          ),
        ),
        SectionTitle('Itens da nota (${_items.length})'),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Nenhum item.'),
          ),
        for (var i = 0; i < _items.length; i++)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}. ${_items[i].nfDescription}',
                      style: theme.textTheme.titleSmall),
                  Text(
                    [
                      'Cód. NF ${_items[i].nfCode}',
                      if (str(_items[i]['ncm']).isNotEmpty)
                        'NCM ${_items[i]['ncm']}',
                      if (str(_items[i]['cfop']).isNotEmpty)
                        'CFOP ${_items[i]['cfop']}',
                    ].join(' • '),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '${formatQty(_items[i].quantity)} ${_items[i].unit} × ${formatMoney(_items[i].unitPrice)} = ${formatMoney(_items[i].totalPrice)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _items[i].isLinked
                        ? 'Produto: ${_items[i].productCode}'
                            '${_items[i].productDescription.isNotEmpty ? ' — ${_items[i].productDescription}' : ''}'
                        : 'Sem produto vinculado',
                    style: TextStyle(
                        color: _items[i].isLinked
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error),
                  ),
                  if (_items[i].lotId != null)
                    Text(
                        'Lote: ${str(_items[i]['lot_code']).isEmpty ? '#${_items[i].lotId}' : _items[i]['lot_code']}',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        const SectionTitle('Parcelas (contas a pagar)'),
        if (_installments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Nenhuma parcela.'),
          ),
        for (final inst in _installments)
          ListTile(
            dense: true,
            title: Text(
                '${str(inst['installment_code'])} • vence ${formatDate(str(inst['due_date']))}'),
            subtitle: Text(boolOf(inst['is_paid']) ||
                    str(inst['status']).toUpperCase() == 'PAID'
                ? 'Paga'
                : 'Em aberto'),
            trailing: Text(formatMoney(numOf(inst['amount']))),
          ),
      ],
    );
  }
}
