import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;

  /// Corpo JSON do erro (ex.: detail.code = DUPLICATE_INBOUND_INVOICE).
  final Map<String, dynamic> body;
  ApiException(this.message, [this.status, this.body = const {}]);

  String? get code {
    final d = body['detail'];
    if (d is Map && d['code'] != null) return d['code'].toString();
    final e = body['error'];
    return e is String && RegExp(r'^[A-Z0-9_]+$').hasMatch(e) ? e : null;
  }

  @override
  String toString() => message;
}

/// Cliente das APIs de notas de entrada do ERP (as mesmas da tela
/// "Notas de Entrada": /api/inbound-invoices, /api/nfe-inbox, etc.).
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const defaultServer = 'https://erp.consart.com.br';
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUserName = 'user_name';

  String serverUrl = '';
  String? token;
  String? userName;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? defaultServer;
    token = p.getString(_kToken);
    userName = p.getString(_kUserName);
  }

  Future<void> logout() async {
    token = null;
    userName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUserName);
  }

  static String normalizeServer(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// URLs que o ERP grava relativas (/painelNotasFiscais/...) viram absolutas.
  String absoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$serverUrl${url.startsWith('/') ? '' : '/'}$url';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (serverUrl.isEmpty) {
      throw ApiException('Configure o endereço do servidor.');
    }
    return Uri.parse('$serverUrl$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final req = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    return _execute(req, timeout: timeout);
  }

  Future<http.Response> _raw(http.BaseRequest req, Duration timeout) async {
    try {
      return await http.Response.fromStream(await req.send().timeout(timeout));
    } on TimeoutException {
      throw ApiException('Servidor não respondeu. Verifique a conexão.');
    } catch (_) {
      throw ApiException('Sem conexão com o servidor ($serverUrl).');
    }
  }

  static ApiException _error(http.Response res, Map<String, dynamic> json) {
    if (res.statusCode == 401) {
      return ApiException('Sessão expirada. Saia e entre novamente.', 401, json);
    }
    var msg = json['message'] ?? json['error'] ?? json['erro'];
    // Algumas rotas mandam o código em "error" e o texto em "message".
    if (msg is String && RegExp(r'^[A-Z0-9_]+$').hasMatch(msg)) {
      final detail = json['detail'];
      if (detail is String && detail.isNotEmpty) msg = '$msg: $detail';
    }
    return ApiException(
      msg is String && msg.isNotEmpty
          ? msg
          : 'Erro na requisição (${res.statusCode}).',
      res.statusCode,
      json,
    );
  }

  Future<dynamic> _execute(
    http.BaseRequest req, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final res = await _raw(req, timeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    final json = decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _error(res, json);
    }
    if (json['ok'] == false || json['success'] == false) {
      throw _error(res, json);
    }
    return decoded;
  }

  // ── Login ────────────────────────────────────────────────────────────
  Future<void> login(String server, String login, String password) async {
    final url = normalizeServer(server);
    serverUrl = url;
    final json = _map(await _send('POST', '/api/login',
        body: {'login': login.trim(), 'password': password}));
    final t = json['token'];
    if (t is! String || t.isEmpty) {
      throw ApiException('Login sem token na resposta.');
    }
    token = t;
    final user = json['user'];
    userName = user is Map ? (user['name']?.toString() ?? login) : login;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, url);
    await p.setString(_kToken, t);
    await p.setString(_kUserName, userName!);
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  /// Aceita lista pura ou {rows|data|items|...: [...]}.
  static List<Map<String, dynamic>> _rows(dynamic json) {
    dynamic raw = json;
    if (json is Map) {
      for (final k in ['rows', 'data', 'items', 'options', 'lots']) {
        final v = json[k];
        if (v is List) {
          raw = v;
          break;
        }
        if (v is Map && v['rows'] is List) {
          raw = v['rows'];
          break;
        }
      }
    }
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  static String _enc(Object v) => Uri.encodeComponent(v.toString().trim());

  // ── Modo de estoque (com lote / simples) ────────────────────────────
  /// Mesmo critério da tela web: na dúvida, exige lote.
  Future<bool> stockRequiresLot() async {
    try {
      final json = _map(await _send(
          'GET', '/api/app-features/PRODUCT_STOCK_MODE/resolve'));
      Map<String, dynamic> f = json;
      for (final k in ['feature', 'data']) {
        if (f[k] is Map) f = _map(f[k]);
      }
      if (f['feature'] is Map) f = _map(f['feature']);
      if (f['enabled'] == false || json['enabled'] == false) return true;
      final option = (f['optionCode'] ?? f['option_code'] ?? f['mode'] ??
              json['optionCode'] ?? json['option_code'] ?? json['mode'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (option == 'STOCK_SIMPLE' || option == 'SIMPLE') return false;
      if (option.isEmpty) {
        final config = _map(f['config'] ?? json['config']);
        final manager = (config['managerMode'] ?? config['manager_mode'] ?? '')
            .toString()
            .toLowerCase();
        if (manager == 'simple') return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  // ── Notas de entrada ────────────────────────────────────────────────
  Future<InvoiceList> listInvoices({
    String search = '',
    String? dateFrom,
    String? dateTo,
    String orderBy = 'created_at',
    bool desc = true,
    int offset = 0,
    int limit = 30,
  }) async {
    final json = _map(await _send('GET', '/api/inbound-invoices', query: {
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      'orderBy': '$orderBy ${desc ? 'DESC' : 'ASC'}',
      'limit': '$limit',
      'offset': '$offset',
    }));
    final rows = _rows(json).map(Invoice.fromJson).toList();
    final total = int.tryParse('${json['total']}') ?? rows.length;
    return InvoiceList(rows, total);
  }

  Future<Invoice> getInvoice(int id) async =>
      Invoice.fromJson(_map(await _send('GET', '/api/inbound-invoices/$id')));

  Future<List<Map<String, dynamic>>> listItems(int id) async =>
      _rows(await _send('GET', '/api/inbound-invoices/$id/items'));

  Future<List<Map<String, dynamic>>> listInstallments(int id) async =>
      _rows(await _send('GET', '/api/inbound-invoices/$id/installments'));

  /// Exclui a nota. O ERP estorna o estoque e as contas a pagar dela.
  Future<void> deleteInvoice(int id) =>
      _send('DELETE', '/api/inbound-invoices/$id');

  /// Prévia do XML (não grava nada). Mesmo endpoint do botão "Importar XML".
  Future<XmlPreview> previewXml(List<int> bytes, String fileName) async {
    final req = http.MultipartRequest(
        'POST', _uri('/api/inbound-invoices/import-xml'))
      ..headers.addAll({
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      })
      ..files.add(http.MultipartFile.fromBytes('xml', bytes,
          filename: fileName.toLowerCase().endsWith('.xml')
              ? fileName
              : '$fileName.xml',
          contentType: MediaType('application', 'xml')));
    final json = _map(
        await _execute(req, timeout: const Duration(seconds: 60)));
    return XmlPreview.fromJson(_map(json['data']));
  }

  /// Passo 1 do "Salvar" da tela web: cria a nota (pendente) com parcelas e
  /// contas a pagar a partir da chave.
  Future<Map<String, dynamic>> autoImport(String accessKey) async =>
      _map(await _send('POST', '/api/inbound/auto-from-dfe',
          query: {'accessKey': accessKey},
          timeout: const Duration(seconds: 90)));

  /// Passo 2: grava cabeçalho e TODOS os itens (o ERP apaga os ausentes).
  Future<void> updateInvoice(int id, Map<String, dynamic> body) =>
      _send('PUT', '/api/inbound-invoices/$id',
          body: body, timeout: const Duration(seconds: 90));

  Future<void> createInstallment(int id, Map<String, dynamic> body) =>
      _send('POST', '/api/inbound-invoices/$id/installments', body: body);

  Future<void> deleteInstallment(int installmentId) =>
      _send('DELETE', '/api/inbound-invoices/installments/$installmentId');

  /// Passo 4: dá entrada no estoque.
  Future<String> postInvoice(int id) async {
    final json = _map(await _send('POST', '/api/inbound-invoices/$id/post',
        timeout: const Duration(seconds: 90)));
    return json['message']?.toString() ?? 'Nota lançada.';
  }

  // ── Caixa de entrada DF-e (SEFAZ) ───────────────────────────────────
  Future<List<DfeNote>> listDfe({String q = '', int offset = 0}) async {
    final json = await _send('GET', '/api/nfe-inbox', query: {
      'limit': '50',
      'offset': '$offset',
      'sort': 'data_autorizacao',
      'order': 'desc',
      if (q.trim().isNotEmpty) 'q': q.trim(),
    });
    return _rows(json).map(DfeNote.fromJson).toList();
  }

  /// XML completo da nota. Lança ApiException com code XML_NOT_AVAILABLE
  /// quando a SEFAZ só liberou o resumo (precisa da ciência).
  Future<String> dfeXml(int id) async {
    final req = http.Request('GET', _uri('/api/nfe-inbox/$id/xml'))
      ..headers.addAll({
        'Accept': 'application/xml, application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      });
    final res = await _raw(req, const Duration(seconds: 60));
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic> json = {};
      try {
        json = _map(jsonDecode(text));
      } catch (_) {}
      throw _error(res, json);
    }
    if (text.trim().length < 50) {
      throw ApiException('O XML retornado está vazio.');
    }
    return text;
  }

  /// Ciência da Operação (evento 210210): só libera o XML completo.
  Future<void> dfeManifest(int id) => _send('POST', '/api/nfe-inbox/$id/manifest',
      body: {'operacao': 'CIENCIA'}, timeout: const Duration(seconds: 60));

  String dfePdfUrl(int id) => '$serverUrl/api/nfe-inbox/$id/pdf';

  // ── Fornecedores ────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> findSupplier(String taxId) async {
    final rows = _rows(await _send('GET', '/api/suppliers/search',
        query: {'q': taxId.replaceAll(RegExp(r'\D'), '')}));
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> createSupplier(Map<String, dynamic> body) =>
      _send('POST', '/api/suppliers', body: body);

  // ── Produtos (vínculo dos itens) ────────────────────────────────────
  Future<List<ProductHit>> searchProducts(String q) async {
    final json = await _send('GET', '/api/products', query: {
      'q': q.trim(),
      'active': 'true',
      'sort': 'description',
      'dir': 'asc',
      'page': '1',
      'limit': '30',
    });
    return _rows(json).map(ProductHit.fromJson).toList();
  }

  Future<Map<String, dynamic>> getProduct(String code) async {
    final json = _map(await _send('GET', '/api/products/${_enc(code)}'));
    final d = json['data'];
    return d is Map ? d.cast<String, dynamic>() : json;
  }

  List<UnitOption>? _unitsCache;

  /// Todas as unidades ativas do cadastro (a mesma lista da tela web).
  Future<List<UnitOption>> listUnits() async {
    if (_unitsCache != null) return _unitsCache!;
    final rows = _rows(await _send('GET', '/api/units',
        query: {'onlyActive': '1', 'limit': '1000'}));
    // Sem códigos repetidos: o seletor não aceita valores duplicados.
    final seen = <String>{};
    final list = rows
        .map((r) => UnitOption.fromJson(r))
        .where((u) => u.unit.isNotEmpty && seen.add(u.unit))
        .toList()
      ..sort((a, b) => a.unit.compareTo(b.unit));
    return _unitsCache = list;
  }

  /// Unidades cadastradas no produto (códigos de barras com fator).
  Future<List<UnitOption>> productUnits(String code) async {
    final rows = _rows(await _send('GET', '/api/products/${_enc(code)}/units'));
    final seen = <String>{};
    final out = <UnitOption>[];
    for (final r in rows) {
      final u = UnitOption.fromJson(r, fromProduct: true);
      if (u.unit.isNotEmpty && seen.add(u.unit)) out.add(u);
    }
    return out;
  }

  /// Lotes do produto (inclusive zerados). Tenta pelo SKU e depois pelo
  /// estoque, como a tela web.
  Future<List<Lot>> listLots(String productCode, int? stockId) async {
    Object? firstError;
    final attempts = <(String, Map<String, String>?)>[
      if (productCode.isNotEmpty)
        ('/api/productsStockLots/by-product-code/${_enc(productCode)}', null),
      if (stockId != null)
        ('/api/productsStockLots/options', {'product_stock_id': '$stockId'}),
    ];
    for (final (path, query) in attempts) {
      try {
        final lots = _rows(await _send('GET', path, query: query))
            .map(Lot.fromJson)
            .whereType<Lot>()
            .toList();
        if (lots.isNotEmpty) return lots;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
    return [];
  }
}
