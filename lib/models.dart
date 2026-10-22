// Modelos usados pelo app. Espelham as respostas de /api/inbound-invoices,
// /api/nfe-inbox, /api/products e /api/productsStockLots do ERP.
// Itens e parcelas ficam como Map para devolver ao ERP todos os campos
// fiscais que vieram dele (o PUT regrava o item inteiro).

String str(dynamic v) => v == null ? '' : v.toString();

double numOf(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(str(v).replaceAll(',', '.')) ?? 0;
}

int? intOf(dynamic v) {
  if (v is int) return v > 0 ? v : null;
  final n = num.tryParse(str(v));
  return n != null && n > 0 && n == n.roundToDouble() ? n.toInt() : null;
}

bool boolOf(dynamic v) {
  if (v is bool) return v;
  final s = str(v).toLowerCase();
  return s == 'true' || s == '1' || s == 't';
}

String onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

String formatQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
}

/// 1234.5 → "1.234,50"
String formatDecimal(double v, [int digits = 2]) {
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(digits).split('.');
  final buf = StringBuffer();
  final intPart = parts[0];
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  final dec = parts.length > 1 ? ',${parts[1]}' : '';
  return '${neg ? '-' : ''}$buf$dec';
}

String formatMoney(double v) => 'R\$ ${formatDecimal(v)}';

/// Aceita "1.234,56", "1234,56" ou "1234.56".
double? parseDecimal(String text) {
  var t = text.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// "2026-10-22T00:00:00.000Z" → "22/10/2026"
String formatDate(String? iso) {
  if (iso == null || iso.length < 10) return iso ?? '';
  final d = iso.substring(0, 10).split('-');
  if (d.length != 3) return iso;
  return '${d[2]}/${d[1]}/${d[0]}';
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// CNPJ/CPF formatado quando tem 14/11 dígitos.
String formatTaxId(String v) {
  final d = onlyDigits(v);
  if (d.length == 14) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
  }
  if (d.length == 11) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }
  return v;
}

/// Chave de 44 dígitos em blocos de 4, como na DANFE.
String formatKey(String key) {
  final d = onlyDigits(key);
  if (d.length != 44) return key;
  return [for (var i = 0; i < 44; i += 4) d.substring(i, i + 4)].join(' ');
}

String statusLabel(String status, bool stockApplied) {
  final s = status.toUpperCase();
  if (stockApplied || s == 'POSTED') return 'Lançada';
  if (s == 'PENDING') return 'Pendente';
  if (s.isEmpty) return '—';
  return status;
}

class Invoice {
  final int id;
  final String accessKey;
  final String number;
  final String series;
  final String issuer;
  final String recipient;
  final String supplierName;
  final String issueDate;
  final String entryDate;
  final double total;
  final String createdAt;
  final String status;
  final bool stockApplied;
  final String stockAppliedAt;
  final String xmlUrl;
  final String danfeUrl;

  Invoice({
    required this.id,
    required this.accessKey,
    required this.number,
    required this.series,
    required this.issuer,
    required this.recipient,
    required this.supplierName,
    required this.issueDate,
    required this.entryDate,
    required this.total,
    required this.createdAt,
    required this.status,
    required this.stockApplied,
    required this.stockAppliedAt,
    required this.xmlUrl,
    required this.danfeUrl,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: intOf(j['inbound_id'] ?? j['id']) ?? 0,
        accessKey: str(j['access_key']),
        number: str(j['invoice_number']),
        series: str(j['series']),
        issuer: str(j['issuer']),
        recipient: str(j['recipient']),
        supplierName: str(j['supplier_name']),
        issueDate: str(j['issue_date']),
        entryDate: str(j['entry_date']),
        total: numOf(j['total_amount']),
        createdAt: str(j['created_at']),
        status: str(j['status']),
        stockApplied: boolOf(j['stock_applied']),
        stockAppliedAt: str(j['stock_applied_at']),
        xmlUrl: str(j['xml_url']),
        danfeUrl: str(j['danfe_url']),
      );

  String get supplierLabel => supplierName.isNotEmpty &&
          supplierName != 'Fornecedor não cadastrado'
      ? supplierName
      : (issuer.isNotEmpty ? formatTaxId(issuer) : 'Fornecedor não cadastrado');
}

class InvoiceList {
  final List<Invoice> rows;
  final int total;
  InvoiceList(this.rows, this.total);
}

/// Resultado de POST /api/inbound-invoices/import-xml.
class XmlPreview {
  final String accessKey;
  final String number;
  final String series;
  final String issuerTaxId;
  final String issuerName;
  final String recipientTaxId;
  final String issueDate;
  final String entryDate;
  final double total;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> installments;
  final int mapped;
  final int unmapped;

  XmlPreview({
    required this.accessKey,
    required this.number,
    required this.series,
    required this.issuerTaxId,
    required this.issuerName,
    required this.recipientTaxId,
    required this.issueDate,
    required this.entryDate,
    required this.total,
    required this.items,
    required this.installments,
    required this.mapped,
    required this.unmapped,
  });

  static List<Map<String, dynamic>> _list(dynamic v) => (v is List ? v : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  factory XmlPreview.fromJson(Map<String, dynamic> j) {
    final mapping = j['productMapping'] is Map ? j['productMapping'] as Map : {};
    final items = _list(j['items']);
    return XmlPreview(
      accessKey: str(j['accessKey']),
      number: str(j['invoiceNumber']),
      series: str(j['series']),
      issuerTaxId: str(j['issuerCnpj']),
      issuerName: str(j['issuerName']),
      recipientTaxId: str(j['recipientCnpj']),
      issueDate: str(j['issueDate']),
      entryDate: str(j['entryDate']),
      total: numOf(j['totalAmount']),
      items: items,
      installments: _list(j['installments']),
      mapped: intOf(mapping['mapped']) ?? 0,
      unmapped: intOf(mapping['unmapped']) ??
          items.where((i) => !boolOf(i['lm_ref_found'])).length,
    );
  }
}

/// Linha da caixa de entrada DF-e (notas emitidas contra a empresa).
class DfeNote {
  final int id;
  final String key;
  final String number;
  final String issuerName;
  final String issuerTaxId;
  final double total;
  final String date;
  final bool imported;
  bool manifested;
  bool needsManifest = false;

  DfeNote({
    required this.id,
    required this.key,
    required this.number,
    required this.issuerName,
    required this.issuerTaxId,
    required this.total,
    required this.date,
    required this.imported,
    required this.manifested,
  });

  factory DfeNote.fromJson(Map<String, dynamic> j) {
    final m = j['manifestacao'];
    return DfeNote(
      id: intOf(j['id']) ?? 0,
      key: str(j['chave_nfe']).trim(),
      number: str(j['numero']),
      issuerName: str(j['emitente_razao']),
      issuerTaxId: str(j['emitente_cnpj']),
      total: numOf(j['valor_total']),
      date: str(j['data_autorizacao'] ?? j['data_emissao']),
      imported: j['entrada_criada'] == true,
      manifested: m is Map && str(m['operacao']).isNotEmpty,
    );
  }
}

class ProductHit {
  final String code;
  final String description;
  final String barcode;
  final String manufacturerRef;

  ProductHit(this.code, this.description, this.barcode, this.manufacturerRef);

  factory ProductHit.fromJson(Map<String, dynamic> j) => ProductHit(
        str(j['product_code'] ?? j['code']).trim(),
        str(j['description'] ?? j['descricao']),
        str(j['barcode']),
        str(j['manufacturer_ref'] ?? j['ref_fabricante']),
      );
}

class Lot {
  final int id;
  final String code;
  final String expiresAt;
  final double available;
  final String gradeName;
  final int? productGradeId;
  final int? gradeId;

  Lot(this.id, this.code, this.expiresAt, this.available, this.gradeName,
      this.productGradeId, this.gradeId);

  static Lot? fromJson(Map<String, dynamic> j) {
    final id = intOf(j['lot_id'] ?? j['id'] ?? j['product_stock_lot_id']);
    if (id == null) return null;
    return Lot(
      id,
      str(j['lot_code'] ?? j['code']),
      str(j['expires_at'] ?? j['expiration_date']),
      numOf(j['qty_available'] ?? j['qty_on_hand']),
      str(j['grade_name'] ?? j['product_grade_name'] ?? j['grade']),
      intOf(j['product_grade_id'] ?? j['grade_id']),
      intOf(j['grade_id'] ?? j['product_grade_id']),
    );
  }

  String get label => [
        if (gradeName.isNotEmpty) gradeName,
        code.isNotEmpty ? 'Lote $code' : 'Lote #$id',
        'Val: ${expiresAt.isEmpty ? '—' : formatDate(expiresAt)}',
        'Disp: ${formatQty(available)}',
      ].join(' • ');
}

/// Leitura dos campos de um item da nota (Map vindo do ERP).
extension InvoiceItem on Map<String, dynamic> {
  String get nfCode => str(this['nf_product_code']);
  String get nfDescription => str(this['description']);
  String get productCode => str(this['product_code']).trim();
  String get productDescription =>
      str(this['product_description'] ?? this['product_name']);
  bool get isLinked => productCode.isNotEmpty;
  double get quantity => numOf(this['quantity']);
  double get unitPrice => numOf(this['unit_price']);
  double get totalPrice => numOf(this['total_price'] ?? this['total']);
  String get unit => str(this['unit']);
  int? get lotId => intOf(this['lot_id']);
}
