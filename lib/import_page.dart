import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'product_picker.dart';
import 'ui.dart';

/// Conferência de uma NF-e importada antes de lançar: dados da nota,
/// vínculo de cada item a um produto (e lote, quando o estoque usa lote)
/// e parcelas. "Salvar e lançar" segue os mesmos passos da tela web:
/// auto-import → grava cabeçalho e itens → parcelas/contas a pagar →
/// entrada no estoque.
class ImportPage extends StatefulWidget {
  final XmlPreview preview;
  final String supplierName;
  const ImportPage(
      {super.key, required this.preview, required this.supplierName});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ItemState {
  List<Lot> lots = [];
  bool loadingLots = false;
  String? lotsError;
  bool linking = false;
}

class _ImportPageState extends State<ImportPage> {
  final _api = ApiService.instance;
  late final XmlPreview p = widget.preview;

  late final _number = TextEditingController(text: p.number);
  late final _series = TextEditingController(text: p.series);
  late final _issuer = TextEditingController(text: p.issuerTaxId);
  late final _recipient = TextEditingController(text: p.recipientTaxId);
  late final _total = TextEditingController(text: formatDecimal(p.total));
  late String _issueDate = _dateOnly(p.issueDate);
  late String _entryDate = _dateOnly(p.entryDate);

  late final List<Map<String, dynamic>> _items = [
    for (final it in p.items)
      {
        ...it,
        'nf_product_code': it['nf_product_code'],
        'product_code': it['product_code'],
        'product_id': it['product_id'],
        'xml_unit': it['xml_unit'] ?? it['unit'],
        'unit': it['barcode_unit'] ?? it['unit'],
        'conversion_factor': numOf(it['conversion_factor']) == 0
            ? 1
            : numOf(it['conversion_factor']),
      }
  ];
  late final List<_ItemState> _itemStates =
      List.generate(_items.length, (_) => _ItemState());
  late final List<Map<String, dynamic>> _installments = [
    for (final i in p.installments) Map<String, dynamic>.from(i)
  ];

  bool _requireLot = true;
  bool _modeLoaded = false;
  bool _saving = false;

  /// Id da nota já criada no ERP (o passo 1 deu certo); um novo "Salvar"
  /// continua dela em vez de importar de novo.
  int? _invoiceId;
  String? _xmlUrl;
  String? _danfeUrl;

  static String _dateOnly(String s) => s.length >= 10 ? s.substring(0, 10) : '';

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  @override
  void dispose() {
    for (final c in [_number, _series, _issuer, _recipient, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMode() async {
    final requireLot = await _api.stockRequiresLot();
    if (!mounted) return;
    setState(() {
      _requireLot = requireLot;
      _modeLoaded = true;
    });
    if (!requireLot) {
      for (final it in _items) {
        it['lot_id'] = null;
        it['product_grade_id'] = null;
      }
      return;
    }
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].isLinked) _loadLots(i);
    }
  }

  Future<void> _loadLots(int index) async {
    final item = _items[index];
    final st = _itemStates[index];
    final code = item.productCode;
    setState(() {
      st.loadingLots = true;
      st.lotsError = null;
    });
    try {
      final lots = await _api.listLots(code, intOf(item['product_stock_id']));
      if (!mounted || _items[index].productCode != code) return;
      setState(() {
        st.lots = lots;
        var selected = lots.where((l) => l.id == item.lotId).firstOrNull;
        if (selected == null && lots.length == 1) selected = lots.first;
        _applyLot(item, selected);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        st.lots = [];
        st.lotsError = 'Falha ao consultar lotes: $e';
        item['lot_id'] = null;
      });
    } finally {
      if (mounted) setState(() => st.loadingLots = false);
    }
  }

  void _applyLot(Map<String, dynamic> item, Lot? lot) {
    item['lot_id'] = lot?.id;
    item['lot_code'] = lot?.code;
    if (lot != null) {
      item['product_grade_id'] = lot.productGradeId;
      item['grade_id'] = lot.gradeId;
    }
  }

  static String? _barcodeUnit(Map<String, dynamic> product) {
    final list = product['barcodes'] ?? product['product_barcodes'];
    Map? barcode = product['primary_barcode'] is Map
        ? product['primary_barcode'] as Map
        : null;
    if (barcode == null && list is List && list.isNotEmpty) {
      barcode = list.whereType<Map>().firstWhere(
          (b) => b['is_primary'] == true,
          orElse: () => list.whereType<Map>().first);
    }
    final unit = product['barcode_unit'] ??
        barcode?['unit_code'] ??
        barcode?['unit'] ??
        barcode?['sigla'] ??
        product['unit_compra'] ??
        product['unidade_compra'] ??
        product['unit'] ??
        product['unidade'];
    final s = str(unit).trim().toUpperCase();
    return s.isEmpty ? null : s;
  }

  Future<void> _link(int index) async {
    final item = _items[index];
    final barcode = onlyDigits(str(item['barcode']));
    final picked = await Navigator.of(context).push<ProductHit>(
      MaterialPageRoute(
        builder: (_) => ProductPickerPage(
          initialQuery: barcode.length >= 8 ? barcode : '',
          itemLabel: '${item.nfCode} — ${item.nfDescription}',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final st = _itemStates[index];
    setState(() => st.linking = true);
    try {
      final full = await _api.getProduct(picked.code);
      final returned = str(full['product_code']).trim();
      if (returned.isNotEmpty && returned != picked.code) {
        throw ApiException(
            'A API retornou outro SKU ($returned), diferente de ${picked.code}.');
      }
      if (!mounted) return;
      setState(() {
        if (item.productCode != picked.code) {
          item['lot_id'] = null;
          item['lot_code'] = null;
          item['product_grade_id'] = null;
          item['grade_id'] = null;
          st.lots = [];
        }
        item['product_code'] = picked.code;
        item['product_id'] = intOf(full['product_id'] ?? full['id']);
        item['product_stock_id'] = intOf(full['product_stock_id'] ??
            full['stock_id'] ??
            full['productStockId']);
        final desc = str(full['description'] ?? full['descricao']).trim();
        item['product_description'] =
            desc.isEmpty ? picked.description : desc;
        item['product_name'] = item['product_description'];
        final ncm = str(full['ncm'] ?? full['ncm_codigo']).trim();
        if (ncm.isNotEmpty) item['ncm'] = ncm;
        final cfop = str(full['cfop_compra'] ?? full['cfop']).trim();
        if (cfop.isNotEmpty) item['cfop'] = cfop;
        final unit = _barcodeUnit(full);
        if (unit != null) item['unit'] = unit;
      });
      if (_requireLot) await _loadLots(index);
    } catch (e) {
      if (mounted) showSnack(context, 'Erro ao vincular: $e', error: true);
    } finally {
      if (mounted) setState(() => st.linking = false);
    }
  }

  Future<void> _pickDate(bool entry) async {
    final current = DateTime.tryParse(entry ? _entryDate : _issueDate);
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() => entry ? _entryDate = isoDate(d) : _issueDate = isoDate(d));
  }

  Future<void> _editInstallment([int? index]) async {
    final source = index == null ? null : _installments[index];
    final code = TextEditingController(
        text: str(source?['installment_code'] ??
            '${_installments.length + 1}'));
    final amount = TextEditingController(
        text: source == null ? '' : formatDecimal(numOf(source['amount'])));
    var due = _dateOnly(str(source?['due_date']));
    var paid = boolOf(source?['is_paid']);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(index == null ? 'Nova parcela' : 'Parcela'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Código'),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.tryParse(due) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setLocal(() => due = isoDate(d));
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Vencimento'),
                child: Text(due.isEmpty ? 'Escolher' : formatDate(due)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (R\$)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: paid,
              onChanged: (v) => setLocal(() => paid = v ?? false),
              title: const Text('Pago'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('OK')),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final value = parseDecimal(amount.text) ?? 0;
    if (due.isEmpty || value <= 0) {
      showSnack(context, 'Informe vencimento e valor maior que zero.',
          error: true);
      return;
    }
    setState(() {
      final row = {
        ...?source,
        'installment_code': code.text.trim().isEmpty
            ? '${(index ?? _installments.length) + 1}'
            : code.text.trim(),
        'due_date': due,
        'amount': value,
        'is_paid': paid,
      };
      if (index == null) {
        _installments.add(row);
      } else {
        _installments[index] = row;
      }
    });
  }

  // ── Salvar e lançar ─────────────────────────────────────────────────
  String? _validate() {
    if (_items.isEmpty) return 'A nota não tem itens.';
    if (_itemStates.any((s) => s.linking || s.loadingLots)) {
      return 'Aguarde o carregamento dos produtos/lotes.';
    }
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (!it.isLinked) {
        return 'Item ${i + 1} (${it.nfCode}) está sem produto vinculado.';
      }
      if (_requireLot) {
        if (_itemStates[i].lotsError != null) return _itemStates[i].lotsError;
        if (it.lotId == null) {
          return 'Item ${i + 1} (${it.nfCode}) está sem lote.';
        }
      }
    }
    for (final inst in _installments) {
      if (_dateOnly(str(inst['due_date'])).isEmpty) {
        return 'A parcela ${inst['installment_code']} não tem vencimento.';
      }
      if (numOf(inst['amount']) <= 0) {
        return 'A parcela ${inst['installment_code']} tem valor inválido.';
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _itemsPayload() {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final id = intOf(it['inbound_item_id'] ?? it['id'] ?? it['item_id']);
      final seq = intOf(it['nfe_item_seq'] ?? it['xml_item_number'] ??
              it['_index']) ??
          i + 1;
      out.add({
        for (final e in it.entries)
          if (!e.key.startsWith('_')) e.key: e.value,
        'inbound_item_id': id,
        'item_id': id,
        'id': id,
        'product_id': intOf(it['product_id']),
        'product_code': it.productCode,
        'product_sku': it.productCode,
        'product_grade_id': _requireLot ? intOf(it['product_grade_id']) : null,
        'grade_id': _requireLot ? intOf(it['grade_id']) : null,
        'lot_id': _requireLot ? it.lotId : null,
        'lot_code': _requireLot ? it['lot_code'] : null,
        'product_stock_id': intOf(it['product_stock_id']),
        'quantity': it.quantity,
        'unit_price': it.unitPrice,
        'total_price': it.totalPrice,
        'ipi': numOf(it['ipi']),
        'icms': numOf(it['icms']),
        'nfe_item_seq': seq,
        'xml_item_number': seq,
        'sort_order': i + 1,
      });
    }
    return out;
  }

  static String _instCode(dynamic v) =>
      str(v).trim().replaceFirst(RegExp(r'^0+(?=.)'), '');

  /// Mesmo critério da tela web: apaga as parcelas de valor zero criadas
  /// pelo auto-import e cria as do XML que ainda não existem (cada uma
  /// gera a conta a pagar).
  Future<void> _syncInstallments(int id) async {
    if (_installments.isEmpty) return;
    var existing = await _api.listInstallments(id);
    for (final inst in existing.where((x) => numOf(x['amount']) <= 0)) {
      final instId = intOf(inst['inbound_installment_id'] ?? inst['id']);
      if (instId != null) await _api.deleteInstallment(instId);
    }
    existing = existing.where((x) => numOf(x['amount']) > 0).toList();
    final keys = {
      for (final x in existing)
        '${_instCode(x['installment_code'])}|${_dateOnly(str(x['due_date']))}'
    };
    for (var i = 0; i < _installments.length; i++) {
      final inst = _installments[i];
      final code = str(inst['installment_code'] ?? '${i + 1}').trim();
      final due = _dateOnly(str(inst['due_date']));
      final key = '${_instCode(code)}|$due';
      if (keys.contains(key)) continue;
      await _api.createInstallment(id, {
        'installment_code': code,
        'due_date': due,
        'amount': numOf(inst['amount']),
        'is_paid': boolOf(inst['is_paid']),
      });
      keys.add(key);
    }
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      showSnack(context, problem, error: true);
      return;
    }
    final ok = await confirm(context,
        title: 'Salvar e lançar',
        message: 'Gravar a nota ${_number.text}, criar as contas a pagar '
            'das parcelas e dar entrada no estoque?',
        confirmText: 'Lançar');
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    String step = 'importar a NF-e';
    try {
      final message = await withProgress(context, 'Lançando a nota…', () async {
        // Passo 1 — auto-import (cria a nota pendente).
        if (_invoiceId == null) {
          final json = await _api.autoImport(p.accessKey);
          final inv = json['invoice'] is Map
              ? Map<String, dynamic>.from(json['invoice'])
              : <String, dynamic>{};
          final id = intOf(inv['id'] ?? inv['inbound_id'] ?? json['invoiceId']);
          if (id == null) {
            throw ApiException('O ERP não retornou o ID da nota.');
          }
          if (json['alreadyExists'] == true && boolOf(inv['stock_applied'])) {
            throw ApiException('Esta nota já foi lançada no estoque.');
          }
          _invoiceId = id;
          final xml = json['xml'];
          _xmlUrl = str(xml is Map ? xml['xml_url'] : json['xml_url']);
          final danfe = json['danfe'];
          _danfeUrl =
              str(danfe is Map ? danfe['danfe_url'] : json['danfe_url']);
        }
        final id = _invoiceId!;

        // Passo 2 — cabeçalho + itens.
        step = 'gravar a nota';
        try {
          await _api.updateInvoice(id, {
            'access_key': p.accessKey,
            'invoice_number': _number.text.trim(),
            'series': _series.text.trim(),
            'issuer': _issuer.text.trim(),
            'recipient': _recipient.text.trim(),
            if (_issueDate.isNotEmpty) 'issue_date': _issueDate,
            if (_entryDate.isNotEmpty) 'entry_date': _entryDate,
            'total_amount': parseDecimal(_total.text) ?? 0,
            'xml_url': (_xmlUrl ?? '').isEmpty ? null : _xmlUrl,
            'danfe_url': (_danfeUrl ?? '').isEmpty ? null : _danfeUrl,
            'items': _itemsPayload(),
          });
        } on ApiException catch (e) {
          if (e.message.contains('NOT_FOUND')) _invoiceId = null;
          rethrow;
        }

        // Passo 3 — parcelas / contas a pagar.
        step = 'gravar as parcelas';
        await _syncInstallments(id);

        // Passo 4 — entrada no estoque.
        step = 'dar entrada no estoque';
        final inv = await _api.getInvoice(id);
        if (inv.stockApplied) return 'Nota lançada.';
        await _api.postInvoice(id);
        return 'Nota lançada e estoque atualizado.';
      });
      if (!mounted) return;
      showSnack(context, message);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não foi possível lançar'),
          content: Text('Falha ao $step:\n\n$e'
              '${_invoiceId != null ? '\n\nA nota já foi criada no ERP; corrija e toque em "Salvar e lançar" de novo para continuar.' : ''}'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (_saving) return false;
    return confirm(context,
        title: 'Descartar importação?',
        message: _invoiceId == null
            ? 'Nada foi gravado no ERP ainda.'
            : 'A nota já foi criada no ERP como pendente; você pode abri-la '
                'pela lista depois.',
        confirmText: 'Sair');
  }

  // ── Tela ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlinked = _items.where((i) => !i.isLinked).length;
    final noLot =
        _requireLot ? _items.where((i) => i.isLinked && i.lotId == null).length : 0;
    final instTotal =
        _installments.fold<double>(0, (s, i) => s + numOf(i['amount']));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('NF-e ${p.number}'),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.supplierName.isEmpty
                            ? formatTaxId(p.issuerTaxId)
                            : widget.supplierName,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(formatKey(p.accessKey),
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text(
                        '${_items.length} item(ns) • ${formatMoney(parseDecimal(_total.text) ?? 0)}',
                        style: theme.textTheme.bodyMedium),
                    if (unlinked > 0 || noLot > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (unlinked > 0) '$unlinked sem produto vinculado',
                          if (noLot > 0) '$noLot sem lote',
                        ].join(' • '),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ExpansionTile(
              title: const Text('Dados da nota'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _number,
                          decoration:
                              const InputDecoration(labelText: 'Número'))),
                  const SizedBox(width: 10),
                  SizedBox(
                      width: 90,
                      child: TextField(
                          controller: _series,
                          decoration:
                              const InputDecoration(labelText: 'Série'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: _issuer,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Emitente (CNPJ)')),
                const SizedBox(height: 10),
                TextField(
                    controller: _recipient,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Destinatário (CNPJ)')),
                const SizedBox(height: 10),
                TextField(
                    controller: _total,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Valor total (R\$)')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Emissão'),
                        child: Text(formatDate(_issueDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Entrada'),
                        child: Text(formatDate(_entryDate)),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
            SectionTitle('Itens da nota (${_items.length})',
                trailing: !_modeLoaded
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_requireLot ? 'Estoque com lote' : 'Estoque simples',
                        style: theme.textTheme.bodySmall)),
            for (var i = 0; i < _items.length; i++) _itemCard(i),
            SectionTitle(
              'Parcelas (contas a pagar)',
              trailing: TextButton.icon(
                onPressed: _saving ? null : () => _editInstallment(),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ),
            if (_installments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Nenhuma parcela no XML.'),
              ),
            for (var i = 0; i < _installments.length; i++)
              ListTile(
                dense: true,
                title: Text(
                    '${_installments[i]['installment_code'] ?? i + 1} • vence ${formatDate(str(_installments[i]['due_date']))}'),
                subtitle: boolOf(_installments[i]['is_paid'])
                    ? const Text('Paga')
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatMoney(numOf(_installments[i]['amount']))),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editInstallment(i);
                      if (v == 'del') setState(() => _installments.removeAt(i));
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'del', child: Text('Remover')),
                    ],
                  ),
                ]),
              ),
            if (_installments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Total das parcelas: ${formatMoney(instTotal)}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _saving || !_modeLoaded ? null : _save,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Salvar e lançar'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int i) {
    final theme = Theme.of(context);
    final it = _items[i];
    final st = _itemStates[i];
    final lotValue =
        st.lots.any((l) => l.id == it.lotId) ? it.lotId : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i + 1}. ${it.nfDescription}',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              [
                'Cód. NF ${it.nfCode}',
                if (str(it['ncm']).isNotEmpty) 'NCM ${it['ncm']}',
                if (str(it['cfop']).isNotEmpty) 'CFOP ${it['cfop']}',
              ].join(' • '),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${formatQty(it.quantity)} ${it.unit} × ${formatMoney(it.unitPrice)} = ${formatMoney(it.totalPrice)}',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 18),
            Row(children: [
              Icon(it.isLinked ? Icons.link : Icons.link_off,
                  size: 18,
                  color: it.isLinked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  it.isLinked
                      ? '${it.productCode} — ${it.productDescription}'
                      : 'Sem produto vinculado',
                  style: TextStyle(
                      color: it.isLinked ? null : theme.colorScheme.error),
                ),
              ),
              st.linking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(
                      onPressed: _saving ? null : () => _link(i),
                      child: Text(it.isLinked ? 'Trocar' : 'Vincular'),
                    ),
            ]),
            if (_requireLot && it.isLinked) ...[
              const SizedBox(height: 6),
              if (st.loadingLots)
                const LinearProgressIndicator()
              else if (st.lotsError != null)
                Row(children: [
                  Expanded(
                      child: Text(st.lotsError!,
                          style: TextStyle(color: theme.colorScheme.error))),
                  TextButton(
                      onPressed: () => _loadLots(i),
                      child: const Text('Tentar de novo')),
                ])
              else if (st.lots.isEmpty)
                Text('Produto sem lotes cadastrados.',
                    style: TextStyle(color: theme.colorScheme.error))
              else
                DropdownButtonFormField<int>(
                  key: ValueKey('lot-$i-${it.productCode}'),
                  initialValue: lotValue,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Lote'),
                  items: [
                    for (final l in st.lots)
                      DropdownMenuItem(
                          value: l.id,
                          child:
                              Text(l.label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _applyLot(
                          it, st.lots.where((l) => l.id == v).firstOrNull)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
