import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/cameras/data/services/camera_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mémorise et oublie un jeton sous une clé dérivée', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final credentials = SecureCameraCredentialStore(storage: storage);
    const token = 'camera-application-token-0123456789abcdef';

    await credentials.writeToken(
      cameraId: 'cam-01',
      baseUrl: 'https://hub.example.ts.net:8443/',
      token: token,
    );

    expect(
      await credentials.readToken(
        cameraId: 'cam-01',
        baseUrl: 'https://hub.example.ts.net:8443',
      ),
      token,
    );
    final entries = await storage.readAll();
    expect(entries, hasLength(1));
    expect(entries.keys.single, startsWith('private-camera-token-'));
    expect(entries.keys.single, isNot(contains('cam-01')));
    expect(entries.keys.single, isNot(contains('test-tailnet')));

    await credentials.deleteToken(
      cameraId: 'cam-01',
      baseUrl: 'https://hub.example.ts.net:8443',
    );
    expect(await storage.readAll(), isEmpty);
  });

  test('refuse les identifiants, adresses et jetons invalides', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final credentials = SecureCameraCredentialStore();

    await expectLater(
      credentials.writeToken(
        cameraId: 'other-03',
        baseUrl: 'https://hub.example.ts.net:8443',
        token: 'x' * 40,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      credentials.writeToken(
        cameraId: 'cam-01',
        baseUrl: 'http://hub.example.ts.net:8443',
        token: 'x' * 40,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      credentials.writeToken(
        cameraId: 'cam-01',
        baseUrl: 'https://hub.example.ts.net:8443',
        token: 'trop-court',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('une nouvelle caméra possède sa propre clé sécurisée', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final credentials = SecureCameraCredentialStore(storage: storage);
    const token = 'camera-application-token-0123456789abcdef';

    await credentials.writeToken(
      cameraId: 'cam-03',
      baseUrl: 'https://hub.example.ts.net',
      token: token,
    );

    expect(
      await credentials.readToken(
        cameraId: 'cam-03',
        baseUrl: 'https://hub.example.ts.net',
      ),
      token,
    );
  });
}
