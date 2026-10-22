import 'package:consart_entradas/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatKey e formatTaxId', () {
    final key = '3' * 44;
    expect(formatKey(key).split(' ').length, 11);
    expect(formatTaxId('12345678000190'), '12.345.678/0001-90');
  });

  test('XmlPreview lê a resposta do import-xml', () {
    final p = XmlPreview.fromJson({
      'accessKey': '1' * 44,
      'invoiceNumber': '123',
      'issuerCnpj': '12345678000190',
      'totalAmount': 10.5,
      'items': [
        {'nf_product_code': 'A1', 'lm_ref_found': true, 'product_code': '55'},
        {'nf_product_code': 'B2', 'lm_ref_found': false},
      ],
      'installments': [
        {'installment_code': '1', 'due_date': '2026-11-01', 'amount': 10.5}
      ],
    });
    expect(p.items.length, 2);
    expect(p.unmapped, 1);
    expect(p.items.first.isLinked, isTrue);
    expect(p.items.last.isLinked, isFalse);
    expect(p.installments.single['amount'], 10.5);
  });

  test('Lot aceita id em campos diferentes', () {
    expect(Lot.fromJson({'product_stock_lot_id': 7, 'lot_code': 'L1'})?.id, 7);
    expect(Lot.fromJson({'lot_code': 'sem id'}), isNull);
  });

  test('parseDecimal', () {
    expect(parseDecimal('1.234,56'), 1234.56);
    expect(parseDecimal('1234.56'), 1234.56);
  });

  test('UnitOption lê unidade do produto com fator', () {
    final u = UnitOption.fromJson(
        {'unit': 'cx', 'unit_description': 'Caixa', 'fator': '12'},
        fromProduct: true);
    expect(u.unit, 'CX');
    expect(u.factor, 12);
    expect(u.label, 'CX — Caixa — × 12');
  });
}
