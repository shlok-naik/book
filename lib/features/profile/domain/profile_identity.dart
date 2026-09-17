/// How the reader is named in cactus: an `@username` and a display name.
/// Asked for (optionally) in onboarding's "make your profile" and edited
/// from the profile tab.
class ProfileIdentity {
  const ProfileIdentity({this.username, this.displayName});

  static const empty = ProfileIdentity();

  /// Lowercase, without the `@`.
  final String? username;
  final String? displayName;

  bool get isEmpty => username == null && displayName == null;

  /// `@username`, or null.
  String? get handle => username == null ? null : '@$username';

  @override
  bool operator ==(Object other) =>
      other is ProfileIdentity &&
      other.username == username &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(username, displayName);
}

/// The rules a username and display name follow — shared by onboarding and
/// the profile editor so the two can't disagree. Messages are short, like
/// every message in the app.
abstract final class ProfileNames {
  static const usernameMin = 3;
  static const usernameMax = 20;
  static const displayNameMax = 40;

  static final _usernameChars = RegExp(r'^[a-z0-9_.]+$');

  /// [raw] as it's stored: trimmed, lowercase, without a leading `@`.
  static String normalizeUsername(String raw) {
    var value = raw.trim().toLowerCase();
    while (value.startsWith('@')) {
      value = value.substring(1);
    }
    return value;
  }

  /// Null when [raw] is a usable username (or empty, which means "none").
  static String? usernameError(String raw) {
    final value = normalizeUsername(raw);
    if (value.isEmpty) return null;
    if (value.length < usernameMin) return 'At least $usernameMin characters.';
    if (value.length > usernameMax) return 'At most $usernameMax characters.';
    if (!_usernameChars.hasMatch(value)) {
      return 'Letters, numbers, _ and . only.';
    }
    if (value.startsWith('.') || value.endsWith('.')) {
      return "Can't start or end with a dot.";
    }
    return null;
  }

  /// Null when [raw] is a usable display name (or empty).
  static String? displayNameError(String raw) {
    if (raw.trim().length > displayNameMax) {
      return 'At most $displayNameMax characters.';
    }
    return null;
  }
}
