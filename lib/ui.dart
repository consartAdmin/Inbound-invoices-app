import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';

void showSnack(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirmar',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Mostra um diálogo de "aguarde" enquanto [task] roda.
Future<T> withProgress<T>(
    BuildContext context, String message, Future<T> Function() task) async {
  final status = ValueNotifier(message);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator()),
          const SizedBox(width: 20),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, v, __) => Text(v),
            ),
          ),
        ]),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Abre DANFE/XML no navegador do aparelho.
Future<void> openUrl(BuildContext context, String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(ApiService.instance.absoluteUrl(url));
  final ok = uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showSnack(context, 'Não foi possível abrir o arquivo.', error: true);
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
              child: SelectableText(value.isEmpty ? '—' : value,
                  style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final bool done;
  const StatusChip(this.label, {super.key, required this.done});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: done ? scheme.primaryContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: done
                  ? scheme.onPrimaryContainer
                  : scheme.onTertiaryContainer)),
    );
  }
}
