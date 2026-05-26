import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/strings.dart';
import '../../../core/ui/widgets/arena_button.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';
import '../qr/join_code_parser.dart';

/// Full-screen camera scanner pushed from [LivePage]. Decodes the first valid
/// QR payload, normalises it via [parseJoinCodeFromQr], and pops the join
/// code back to the caller. Errors surface inline; the user can dismiss them
/// and retry without leaving the screen.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final Barcode barcode in capture.barcodes) {
      final String? code = parseJoinCodeFromQr(barcode.rawValue);
      if (code != null) {
        _handled = true;
        Navigator.of(context).pop<String>(code);
        return;
      }
    }
    setState(() {
      _error = MedRashStrings.liveScanQrUnrecognised;
    });
  }

  void _dismissError() {
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return ArenaScaffold(
      title: MedRashStrings.liveScanQrTitle,
      showClose: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            MedRashStrings.liveScanQrInstruction,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusLarge),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (_, MobileScannerException error) {
                        return Container(
                          color: tokens.surface,
                          alignment: Alignment.center,
                          padding: EdgeInsets.all(tokens.pageMargin),
                          child: Text(
                            _describeError(error),
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                  if (_error != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Material(
                        color: tokens.warningSurface,
                        borderRadius: BorderRadius.circular(tokens.radiusMedium),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: _dismissError,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ArenaButton(
            label: MedRashStrings.liveScanQrCancel,
            icon: Icons.keyboard_rounded,
            backgroundColor: Colors.white,
            onPressed: () => Navigator.of(context).pop<String>(null),
          ),
        ],
      ),
    );
  }

  String _describeError(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return MedRashStrings.liveScanQrPermissionDenied;
      case MobileScannerErrorCode.unsupported:
        return MedRashStrings.liveScanQrUnsupported;
      default:
        return MedRashStrings.liveScanQrGenericError;
    }
  }
}
