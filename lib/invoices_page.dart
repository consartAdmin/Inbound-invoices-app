import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'dfe_page.dart';
import 'import_flow.dart';
import 'invoice_page.dart';
import 'login_page.dart';
import 'models.dart';
import 'ui.dart';

/// Lista de notas de entrada (mesma listagem da tela web), com busca,
/// período, ordenação e os caminhos para lançar uma nota nova.
class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

const _sortOptions = {
  'created_at': 'Data de cadastro',
  'issue_date': 'Data de emissão',
  'invoice_number': 'Número',
  'supplier_name': 'Fornecedor',
  'total_amount': 'Valor total',
};

class _InvoicesPageState extends State<InvoicesPage> {
  final _api = ApiService.instance;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<Invoice> _rows = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  DateTimeRange? _period;
  String _orderBy = 'created_at';
  bool _desc = true;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _load(more: true);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _rows.length >= _total)) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.listInvoices(
        search: _search.text,
        dateFrom: _period == null ? null : isoDate(_period!.start),
        dateTo: _period == null ? null : isoDate(_period!.end),
        orderBy: _orderBy,
        desc: _desc,
        offset: more ? _rows.length : 0,
        limit: _pageSize,
      );
      if (seq != _seq || !mounted) return;
      setState(() {
        _rows = more ? [..._rows, ...page.rows] : page.rows;
        _total = page.total;
      });
    } on ApiException catch (e) {
      if (seq != _seq || !mounted) return;
      if (e.status == 401) return _logout();
      setState(() => _error = e.toString());
    } catch (e) {
      if (seq == _seq && mounted) setState(() => _error = e.toString());
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _period,
      helpText: 'Período de cadastro',
    );
    if (r == null) return;
    setState(() => _period = r);
    _load();
  }

  Future<void> _pickSort() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in _sortOptions.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == _orderBy
                  ? Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward)
                  : null,
              onTap: () => Navigator.of(ctx).pop(e.key),
            ),
        ]),
      ),
    );
    if (v == null) return;
    setState(() {
      if (v == _orderBy) {
        _desc = !_desc;
      } else {
        _orderBy = v;
        _desc = true;
      }
    });
    _load();
  }

  Future<void> _newEntry() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Importar do DF-e'),
            subtitle: const Text('Notas emitidas para a empresa (SEFAZ)'),
            onTap: () => Navigator.of(ctx).pop('dfe'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Ler código da DANFE'),
            subtitle: const Text('Câmera no código de barras da chave'),
            onTap: () => Navigator.of(ctx).pop('scan'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Importar arquivo XML'),
            subtitle: const Text('XML da NF-e salvo no aparelho'),
            onTap: () => Navigator.of(ctx).pop('xml'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    final Future<bool?> task = switch (choice) {
      'dfe' => Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const DfePage())),
      'scan' => scanDanfe(context),
      _ => pickXmlFile(context),
    };
    final saved = await task == true;
    if (saved && mounted) _load();
  }

  Future<void> _openInvoice(Invoice inv) async {
    final deleted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => InvoicePage(invoiceId: inv.id)));
    if (deleted == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas de Entrada'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout' &&
                  await confirm(context,
                      title: 'Sair',
                      message: 'Sair do usuário ${_api.userName ?? ''}?',
                      confirmText: 'Sair')) {
                _logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(_api.userName ?? '', style: theme.textTheme.bodySmall),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newEntry,
        icon: const Icon(Icons.add),
        label: const Text('Nova entrada'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), _load);
            },
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Chave, número, CNPJ ou fornecedor',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _load();
                      },
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            InputChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(_period == null
                  ? 'Período'
                  : '${formatDate(isoDate(_period!.start))} – ${formatDate(isoDate(_period!.end))}'),
              onPressed: _pickPeriod,
              onDeleted: _period == null
                  ? null
                  : () {
                      setState(() => _period = null);
                      _load();
                    },
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 18),
              label: Text(_sortOptions[_orderBy]!),
              onPressed: _pickSort,
            ),
            const SizedBox(width: 8),
            Text('$_total nota(s)', style: theme.textTheme.bodySmall),
          ]),
        ),
        if (_loading && _rows.isEmpty) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _rows.isEmpty && !_loading
                ? ListView(children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Nenhuma nota de entrada encontrada.',
                          textAlign: TextAlign.center),
                    ),
                  ])
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount:
                        _rows.length + (_rows.length < _total ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i >= _rows.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final inv = _rows[i];
                      return ListTile(
                        onTap: () => _openInvoice(inv),
                        title: Text(inv.supplierLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            'NF-e ${inv.number}${inv.series.isEmpty ? '' : '/${inv.series}'} • '
                            'emissão ${formatDate(inv.issueDate)}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatMoney(inv.total)),
                            const SizedBox(height: 4),
                            StatusChip(
                                statusLabel(inv.status, inv.stockApplied),
                                done: inv.stockApplied),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
