import 'package:book/features/profile/domain/profile_identity.dart';
import 'package:book/features/profile/presentation/profile_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProfileNames', () {
    test('requires a name', () {
      expect(ProfileNames.displayNameError(''), isNotNull);
      expect(ProfileNames.displayNameError('   '), isNotNull);
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

    test('saves a trimmed name and reads it back', () async {
      expect(
        await ProfileIdentityController.save(displayName: ' Ada L. '),
        isNull,
      );
      ProfileIdentityController.reset();
      await ProfileIdentityController.initialize();
      expect(ProfileIdentityController.identity.value.displayName, 'Ada L.');
    });

    test('refuses an empty name without saving', () async {
      expect(await ProfileIdentityController.save(displayName: ' '), isNotNull);
      expect(ProfileIdentityController.identity.value.isEmpty, isTrue);
    });

    test('drops a username an earlier build stored', () async {
      SharedPreferences.setMockInitialValues({
        'profile.username': 'ada',
        'profile.display_name': 'Ada',
      });
      await ProfileIdentityController.initialize();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('profile.username'), isFalse);
      expect(ProfileIdentityController.identity.value.displayName, 'Ada');
    });
  });
}
