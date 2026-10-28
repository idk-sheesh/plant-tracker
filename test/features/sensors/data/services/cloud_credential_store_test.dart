import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/data/services/cloud_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identifiants cloud opt-in dans le coffre et oubli définitif', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final credentials = SecureCloudCredentialStore(storage: storage);
    const saved = CloudCredentials(
      baseUrl: 'https://gateway.example.test',
      username: 'projet',
      password: 'test-password-123',
    );

    await credentials.write(saved);
    final restored = await credentials.read();
    expect(restored?.baseUrl, saved.baseUrl);
    expect(restored?.username, saved.username);
    expect(restored?.password, saved.password);
    expect((await storage.readAll()).keys,
        contains('gardenjournal-cloud-credentials-v1'));

    await credentials.delete();
    expect(await credentials.read(), isNull);
    expect(await storage.readAll(), isEmpty);
  });

  test('refuse une URL non HTTPS et ne persiste rien', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final credentials = SecureCloudCredentialStore(storage: storage);

    await expectLater(
      credentials.write(const CloudCredentials(
        baseUrl: 'http://gateway.example.test',
        username: 'projet',
        password: 'test-password-123',
      )),
      throwsA(isA<FormatException>()),
    );
    expect(await storage.readAll(), isEmpty);
  });
}
