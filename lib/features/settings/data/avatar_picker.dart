import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// The bytes [AvatarPicker.pickFromGallery] read back, plus the picked
/// file's own extension — [ProfileRepository.uploadAvatar] needs both.
typedef PickedAvatar = ({Uint8List bytes, String extension});

/// Thin wrapper over `image_picker`'s [ImagePicker], narrowed to exactly
/// what [MembershipCard] needs. Exists so a test can substitute a fake
/// without reaching the real platform channel — the same role
/// `PurchasesService`/`SessionService` play for their own SDKs.
class AvatarPicker {
  const AvatarPicker();

  /// Opens the photo library and reads the picked image's bytes, or
  /// returns null if the reader backed out without choosing one.
  /// Gallery only — this app never asks for the camera.
  Future<PickedAvatar?> pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return null;
    return (
      bytes: await picked.readAsBytes(),
      extension: _extensionOf(picked.name),
    );
  }

  /// The picked file's own extension, lowercased and without the dot —
  /// `jpg` when there isn't one to read, since that's the common case
  /// for a photo library selection either way.
  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1 || dot == filename.length - 1) return 'jpg';
    return filename.substring(dot + 1).toLowerCase();
  }
}
