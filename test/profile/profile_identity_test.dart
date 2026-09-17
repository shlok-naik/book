import 'package:book/features/profile/domain/profile_identity.dart';
import 'package:book/features/profile/presentation/profile_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProfileNames', () {
    test('normalizes a username', () {
      expect(ProfileNames.normalizeUsername('  @Book_Worm '), 'book_worm');
    });

    test('checks a username', () {
      expect(ProfileNames.usernameError(''), isNull);
      expect(ProfileNames.usernameError('@reader.one'), isNull);
      expect(ProfileNames.usernameError('ab'), isNotNull);
      expect(ProfileNames.usernameError('has space'), isNotNull);
      expect(ProfileNames.usernameError('.dot'), isNotNull);
      expect(ProfileNames.usernameError('a' * 21), isNotNull);
    });

    test('checks a display name', () {
      expect(ProfileNames.displayNameError('Ada Lovelace'), isNull);
      expect(ProfileNames.displayNameError('x' * 41), isNotNull);
    });
  });

  group('ProfileIdentityController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ProfileIdentityController.reset();
    });

    test('saves normalized names and reads them back', () async {
      expect(
        await ProfileIdentityController.save(
          username: '@Ada',
          displayName: ' Ada L. ',
        ),
        isNull,
      );
      ProfileIdentityController.reset();
      await ProfileIdentityController.initialize();
      final identity = ProfileIdentityController.identity.value;
      expect(identity.handle, '@ada');
      expect(identity.displayName, 'Ada L.');
    });

    test('refuses an invalid username without saving', () async {
      expect(
        await ProfileIdentityController.save(username: 'a b', displayName: ''),
        isNotNull,
      );
      expect(ProfileIdentityController.identity.value.isEmpty, isTrue);
    });
  });
}
