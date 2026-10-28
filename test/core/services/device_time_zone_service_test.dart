import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/services/device_time_zone_service.dart';
import 'package:timezone/timezone.dart' as tz;

class _FakeResolver implements TimeZoneResolver {
  final String name;

  const _FakeResolver(this.name);

  @override
  Future<String> getLocalTimeZone() async => name;
}

void main() {
  test('configure UTC sans décalage', () async {
    final location = await DeviceTimeZoneService.refreshLocalLocation(
      const _FakeResolver('UTC'),
    );
    final date = tz.TZDateTime(location, 2026, 1, 15, 12);
    expect(location.name, 'Etc/UTC');
    expect(date.timeZoneOffset, Duration.zero);
    expect(tz.local.name, 'Etc/UTC');
  });

  test('respecte le changement heure été/hiver Europe/Rome', () async {
    final location = await DeviceTimeZoneService.refreshLocalLocation(
      const _FakeResolver('Europe/Rome'),
    );
    final winter = tz.TZDateTime(location, 2026, 1, 15, 12);
    final summer = tz.TZDateTime(location, 2026, 7, 15, 12);
    expect(winter.timeZoneOffset, const Duration(hours: 1));
    expect(summer.timeZoneOffset, const Duration(hours: 2));
    expect(tz.local.name, 'Europe/Rome');
  });

  test('rejette un identifiant IANA inconnu', () async {
    expect(
      DeviceTimeZoneService.refreshLocalLocation(
        const _FakeResolver('Mars/Olympus'),
      ),
      throwsA(isA<tz.LocationNotFoundException>()),
    );
  });
}
