import 'package:book/features/profile/domain/profile_identity.dart';
import 'package:book/features/profile/presentation/profile_identity_controller.dart';
import 'package:book/features/settings/data/profile_repository.dart';
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

  group('account sync', () {
    late _FakeProfiles profiles;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ProfileIdentityController.reset();
      profiles = _FakeProfiles();
      ProfileIdentityController.attach(
        repository: profiles,
        userId: () => 'user-1',
      );
    });

    tearDown(ProfileIdentityController.reset);

    test('a saved name is written to the account too', () async {
      await ProfileIdentityController.save(displayName: ' Ada ');
      expect(profiles.name, 'Ada');
    });

    test("an account's name wins on a new device", () async {
      profiles.name = 'Grace';
      await ProfileIdentityController.syncWithAccount();
      expect(ProfileIdentityController.identity.value.displayName, 'Grace');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('profile.display_name'), 'Grace');
    });

    test("this device's name fills an account that has none", () async {
      ProfileIdentityController.identity.value = const ProfileIdentity(
        displayName: 'Ada',
      );
      await ProfileIdentityController.syncWithAccount();
      expect(profiles.name, 'Ada');
    });

    test(
      'an unreachable account keeps the local name and never throws',
      () async {
        profiles.fail = true;
        expect(
          await ProfileIdentityController.save(displayName: 'Ada'),
          isNull,
        );
        await ProfileIdentityController.syncWithAccount();
        expect(ProfileIdentityController.identity.value.displayName, 'Ada');
      },
    );
  });
}

class _FakeProfiles extends ProfileRepository {
  String? name;
  bool fail = false;

  @override
  Future<String?> fetchDisplayName(String userId) async {
    if (fail) throw StateError('offline');
    return name;
  }

  @override
  Future<void> saveDisplayName(String userId, String value) async {
    if (fail) throw StateError('offline');
    name = value;
  }
}
