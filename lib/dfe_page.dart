import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'import_flow.dart';
import 'models.dart';
import 'ui.dart';

/// Caixa de entrada DF-e: NF-e emitidas contra a empresa (vindas da SEFAZ).
/// Devolve true se alguma nota foi lançada.
class DfePage extends StatefulWidget {
  const DfePage({super.key});

  @override
  State<DfePage> createState() => _DfePageState();
}

class _DfePageState extends State<DfePage> {
  final _api = ApiService.instance;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<DfeNote> _rows = [];
  bool _onlyPending = true;
  bool _loading = false;
  bool _hasMore = true;
  bool _imported = false;
  String? _error;
  int _seq = 0;

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
    if (more && (_loading || !_hasMore)) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _rows = [];
        _hasMore = true;
      }
    });
    try {
      final page = await _api.listDfe(
          q: _search.text, offset: more ? _rawCount : 0);
      if (seq != _seq || !mounted) return;
      setState(() {
        _rawCount = (more ? _rawCount : 0) + page.length;
        _hasMore = page.length >= 50;
        _rows = [..._rows, ...page];
      });
    } catch (e) {
      if (seq == _seq && mounted) setState(() => _error = e.toString());
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  /// Quantas linhas o servidor já devolveu (o filtro de pendentes é local).
  int _rawCount = 0;

  List<DfeNote> get _visible =>
      _onlyPending ? _rows.where((r) => !r.imported).toList() : _rows;

  Future<void> _open(DfeNote note) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(note.issuerName.isEmpty
                ? formatTaxId(note.issuerTaxId)
                : note.issuerName),
            subtitle: Text(
                'NF-e ${note.number} • ${formatMoney(note.total)}\n${formatKey(note.key)}'),
            isThreeLine: true,
          ),
          const Divider(),
          if (!note.imported)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(note.needsManifest
                  ? 'Manifestar ciência e importar'
                  : 'Importar'),
              onTap: () => Navigator.of(ctx).pop('import'),
            ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Ver DANFE'),
            onTap: () => Navigator.of(ctx).pop('pdf'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'pdf') {
      await openUrl(context, _api.dfePdfUrl(note.id));
      return;
    }
    final saved = await importFromDfe(context, note);
    if (!mounted) return;
    if (saved) {
      _imported = true;
      _load();
    } else {
      setState(() {}); // needsManifest/manifested podem ter mudado
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _visible;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_imported);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Importar do DF-e')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), _load);
              },
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Chave, número ou emitente',
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
          SwitchListTile(
            dense: true,
            title: const Text('Somente pendentes de entrada'),
            value: _onlyPending,
            onChanged: (v) => setState(() => _onlyPending = v),
          ),
          if (_loading && _rows.isEmpty) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Não foi possível carregar a caixa DF-e.\n$_error',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: rows.isEmpty && !_loading
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Nenhuma NF-e encontrada na caixa DF-e.',
                            textAlign: TextAlign.center),
                      ),
                    ])
                  : ListView.separated(
                      controller: _scroll,
                      itemCount: rows.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        if (i >= rows.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final n = rows[i];
                        return ListTile(
                          onTap: () => _open(n),
                          title: Text(
                            n.issuerName.isEmpty
                                ? formatTaxId(n.issuerTaxId)
                                : n.issuerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                              'NF-e ${n.number} • ${formatDate(n.date)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatMoney(n.total)),
                              const SizedBox(height: 4),
                              StatusChip(
                                n.imported
                                    ? 'Já lançada'
                                    : n.manifested
                                        ? 'Ciência enviada'
                                        : 'Pendente',
                                done: n.imported,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
