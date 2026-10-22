import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Abre a câmera e devolve (Navigator.pop) o primeiro código lido.
/// Retorna null se o usuário voltar sem ler nada.
class ScannerPage extends StatefulWidget {
  final String title;
  const ScannerPage({super.key, this.title = 'Ler código de barras'});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.qrCode,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  Future<void> _typeCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Digitar código'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Código de barras ou SKU'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    _done = true;
    Navigator.of(context).pop(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 60),
      width: size.width * 0.8,
      height: 160,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Trocar câmera',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Não foi possível abrir a câmera.\nPermita o acesso à câmera nas configurações.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: window,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Container(height: 2, color: Colors.redAccent),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: window.top - 40,
            child: const Text(
              'Posicione o código dentro do quadro',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: SafeArea(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _typeCode,
                icon: const Icon(Icons.keyboard),
                label: const Text('Digitar código'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
