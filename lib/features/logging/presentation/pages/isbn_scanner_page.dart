import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';

/// Opens the camera to scan a book's ISBN barcode for `start isbn` —
/// pushed the same way every other page in the app is, a named
/// `MaterialPageRoute` so it shows up in analytics. Resolves to the
/// scanned digits, or null if the reader backed out via the header's
/// back chevron.
Future<String?> scanIsbn(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<String>(
      settings: const RouteSettings(name: 'isbn_scanner'),
      builder: (_) => const IsbnScannerPage(),
    ),
  );
}

/// A full-bleed camera preview with a viewfinder frame over it. Only
/// barcode formats an ISBN is actually printed as (EAN-13, and the UPC-A
/// some older US editions carry) are recognized — the camera never
/// bothers trying to read a QR code or anything else pointed at it. The
/// header's back chevron pops with no argument, which [scanIsbn]'s
/// caller reads the same as a cancel.
class IsbnScannerPage extends StatefulWidget {
  const IsbnScannerPage({super.key});

  @override
  State<IsbnScannerPage> createState() => _IsbnScannerPageState();
}

class _IsbnScannerPageState extends State<IsbnScannerPage> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
    ],
  );

  /// Set the instant a barcode resolves, so the handful of frames still
  /// in flight while the pop animates can't fire a second one.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: _ScannerHeader(),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) =>
                        _CameraError(error: error),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 260,
                        height: 160,
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.accent, width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.xl,
                    right: AppSpacing.xl,
                    bottom: AppSpacing.xxl,
                    child: Text(
                      "point your camera at the book's barcode",
                      textAlign: TextAlign.center,
                      style: context.fonts.interface(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [SettingsHeader]'s own layout (title flush left, a back chevron in the
/// same top-right slot the gear occupies elsewhere), reproduced in white
/// rather than reused: this is the one screen in the app with a black
/// background behind it, since the camera preview needs the room, and
/// [SettingsHeader] hardcodes the light/dark theme's own text colors.
class _ScannerHeader extends StatelessWidget {
  const _ScannerHeader();

  static const _tapTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _tapTarget,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'scan isbn',
              style: context.fonts.interface(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            onTap: Navigator.of(context).pop,
            child: SizedBox(
              width: _tapTarget,
              height: _tapTarget,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: Navigator.of(context).pop,
                    ),
                  ),
                  InkResponse(
                    onTap: Navigator.of(context).pop,
                    radius: _tapTarget / 2,
                    child: const Icon(
                      Icons.chevron_left,
                      size: 24,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the preview when the camera can't be used —
/// permission denied, no camera on this device, or another app is
/// already holding it. Never a raw exception message: [MobileScannerException]
/// text is written for a plugin author debugging, not the reader.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'cactus needs camera access to scan a barcode. enable it for '
            'cactus in your device settings, then come back here.',
      _ => "your camera isn't available.",
    };

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: context.fonts.interface(
              fontSize: 14,
              height: 1.6,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
