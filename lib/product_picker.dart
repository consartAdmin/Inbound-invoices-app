import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'scanner_page.dart';

/// Busca de produto do cadastro para vincular a um item da nota.
/// Devolve o [ProductHit] escolhido (Navigator.pop).
class ProductPickerPage extends StatefulWidget {
  final String initialQuery;
  final String itemLabel;
  const ProductPickerPage(
      {super.key, this.initialQuery = '', this.itemLabel = ''});

  @override
  State<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends State<ProductPickerPage> {
  late final _query = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<ProductHit> _rows = [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() {
        _rows = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ApiService.instance.searchProducts(q);
      if (seq != _seq || !mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (seq != _seq || !mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (code == null || !mounted) return;
    _query.text = code;
    await _search();
    if (!mounted) return;
    final exact = _rows.where((p) => p.code == code || p.barcode == code);
    if (exact.length == 1) Navigator.of(context).pop(exact.first);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular produto')),
      body: Column(
        children: [
          if (widget.itemLabel.isNotEmpty)
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text('Item da NF-e: ${widget.itemLabel}',
                  style: theme.textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: widget.initialQuery.isEmpty,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Descrição, SKU ou código de barras',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _query.clear();
                              _search();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Ler código de barras',
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: _rows.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _query.text.trim().isEmpty
                          ? 'Digite para buscar no cadastro'
                          : 'Nenhum produto encontrado',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _rows[i];
                      return ListTile(
                        title: Text(p.description),
                        subtitle: Text([
                          'SKU ${p.code}',
                          if (p.barcode.isNotEmpty) p.barcode,
                          if (p.manufacturerRef.isNotEmpty)
                            'Ref ${p.manufacturerRef}',
                        ].join(' • ')),
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
