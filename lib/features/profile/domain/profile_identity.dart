/// How the reader is named in cactus: a display name. Asked for in
/// onboarding's first question and edited from the profile screen.
class ProfileIdentity {
  const ProfileIdentity({this.displayName});

  static const empty = ProfileIdentity();

  final String? displayName;

  bool get isEmpty => displayName == null;

  @override
  bool operator ==(Object other) =>
      other is ProfileIdentity && other.displayName == displayName;

  @override
  int get hashCode => displayName.hashCode;
}

/// The rule a name follows — shared by onboarding and the profile editor so
/// the two can't disagree. Messages are short, like every message in the app.
abstract final class ProfileNames {
  static const displayNameMax = 40;

  /// Null when [raw] is a usable name. A name is required.
  static String? displayNameError(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Enter your name.';
    if (value.length > displayNameMax) {
      return 'At most $displayNameMax characters.';
    }
    return null;
  }
}
