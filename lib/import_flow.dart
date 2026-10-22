import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'import_page.dart';
import 'invoice_page.dart';
import 'models.dart';
import 'scanner_page.dart';
import 'supplier_dialog.dart';
import 'ui.dart';

/// Os três jeitos de começar uma entrada (XML do aparelho, DF-e, DANFE)
/// terminam aqui: prévia do XML → fornecedor → tela de conferência.
/// Devolve true quando uma nota foi gravada.
Future<bool> importXml(
    BuildContext context, List<int> bytes, String fileName) async {
  final api = ApiService.instance;
  XmlPreview preview;
  try {
    preview = await withProgress(
        context, 'Lendo o XML…', () => api.previewXml(bytes, fileName));
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (e.code == 'DUPLICATE_INBOUND_INVOICE') {
      final detail = e.body['detail'];
      final id = detail is Map ? intOf(detail['inbound_id']) : null;
      final open = await confirm(context,
          title: 'Nota já lançada',
          message:
              'Esta nota fiscal de entrada já foi importada anteriormente.',
          confirmText: id != null ? 'Abrir nota' : 'OK');
      if (open && id != null && context.mounted) {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => InvoicePage(invoiceId: id)));
      }
      return false;
    }
    showSnack(context, 'Erro ao importar: $e', error: true);
    return false;
  }

  if (!context.mounted) return false;
  if (preview.issuerTaxId.isEmpty) {
    showSnack(context, 'XML inválido: fornecedor não identificado.',
        error: true);
    return false;
  }

  // Mesmo cuidado da tela web: o emitente precisa existir em Fornecedores.
  Map<String, dynamic>? supplier;
  try {
    supplier = await api.findSupplier(preview.issuerTaxId);
  } catch (_) {}
  if (supplier == null) {
    if (!context.mounted) return false;
    final created = await showSupplierDialog(context,
        taxId: preview.issuerTaxId, name: preview.issuerName);
    if (!created) {
      if (context.mounted) {
        showSnack(context,
            'Importação cancelada. Cadastre o fornecedor para continuar.');
      }
      return false;
    }
    try {
      supplier = await api.findSupplier(preview.issuerTaxId);
    } catch (_) {}
  }

  if (!context.mounted) return false;
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => ImportPage(
      preview: preview,
      supplierName: str(supplier?['name'] ?? preview.issuerName),
    ),
  ));
  return saved == true;
}

Future<bool> pickXmlFile(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    withData: true,
  );
  final file = result?.files.single;
  if (file == null || file.bytes == null) return false;
  if (!file.name.toLowerCase().endsWith('.xml')) {
    if (context.mounted) {
      showSnack(context, 'Escolha um arquivo .xml de NF-e.', error: true);
    }
    return false;
  }
  if (!context.mounted) return false;
  return importXml(context, file.bytes!, file.name);
}

/// Baixa o XML de uma nota da caixa DF-e; se a SEFAZ só liberou o resumo,
/// oferece enviar a Ciência da Operação e tenta de novo.
Future<bool> importFromDfe(BuildContext context, DfeNote note) async {
  final api = ApiService.instance;
  String xml;
  try {
    xml = await withProgress(
        context, 'Baixando XML da NF-e…', () => api.dfeXml(note.id));
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (e.code != 'XML_NOT_AVAILABLE') {
      showSnack(context, 'XML indisponível: $e', error: true);
      return false;
    }
    if (note.manifested) {
      showSnack(
          context,
          'Ciência já registrada, mas a SEFAZ ainda não liberou o XML. '
          'Tente novamente em alguns minutos.',
          error: true);
      return false;
    }
    note.needsManifest = true;
    final ok = await confirm(context,
        title: 'Manifestar ciência',
        message: 'Só o resumo desta NF-e está disponível.\n\n'
            'Enviar à SEFAZ a "Ciência da Operação"? Ela apenas registra que '
            'a empresa tomou conhecimento da nota e libera o XML completo. '
            'Não confirma nem recusa a operação.',
        confirmText: 'Enviar ciência');
    if (!ok || !context.mounted) return false;
    try {
      await withProgress(context, 'Enviando Ciência da Operação…',
          () => api.dfeManifest(note.id));
      note.manifested = true;
      note.needsManifest = false;
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Falha ao manifestar: $e', error: true);
      }
      return false;
    }
    if (!context.mounted) return false;
    try {
      xml = await withProgress(
          context, 'Buscando o XML completo…', () => api.dfeXml(note.id));
    } on ApiException catch (e) {
      if (context.mounted) {
        showSnack(
            context,
            e.code == 'XML_NOT_AVAILABLE'
                ? 'Ciência registrada. A SEFAZ ainda não liberou o XML; '
                    'tente novamente em alguns minutos.'
                : 'XML indisponível: $e',
            error: true);
      }
      return false;
    }
  }
  if (!context.mounted) return false;
  return importXml(
      context, utf8.encode(xml), '${note.key.isEmpty ? note.id : note.key}.xml');
}

/// Lê o código de barras da DANFE (chave de 44 dígitos) e abre a nota:
/// se já foi lançada mostra a nota; senão procura na caixa DF-e.
Future<bool> scanDanfe(BuildContext context) async {
  final code = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const ScannerPage(title: 'Ler código da DANFE')));
  if (code == null || !context.mounted) return false;
  final key = onlyDigits(code);
  if (key.length != 44) {
    showSnack(context,
        'Código lido não é uma chave de NF-e (44 dígitos): $code',
        error: true);
    return false;
  }
  final api = ApiService.instance;
  try {
    final (existing, dfe) = await withProgress(context, 'Procurando a nota…',
        () async {
      final list = await api.listInvoices(search: key, limit: 5);
      final inv = list.rows.where((r) => onlyDigits(r.accessKey) == key);
      if (inv.isNotEmpty) return (inv.first, null);
      final notes = await api.listDfe(q: key);
      final hit = notes.where((n) => onlyDigits(n.key) == key);
      return (null, hit.isEmpty ? null : hit.first);
    });
    if (!context.mounted) return false;
    if (existing != null) {
      showSnack(context, 'Esta nota já foi lançada.');
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvoicePage(invoiceId: existing.id)));
      return false;
    }
    if (dfe == null) {
      showSnack(
          context,
          'Nota não encontrada na caixa DF-e. Se ela acabou de ser emitida, '
          'aguarde a sincronização com a SEFAZ ou importe o XML.',
          error: true);
      return false;
    }
    return importFromDfe(context, dfe);
  } catch (e) {
    if (context.mounted) showSnack(context, '$e', error: true);
    return false;
  }
}
