import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

abstract interface class TimeZoneResolver {
  Future<String> getLocalTimeZone();
}

class PlatformTimeZoneResolver implements TimeZoneResolver {
  static const _channel = MethodChannel('gardenjournal/platform');

  const PlatformTimeZoneResolver();

  @override
  Future<String> getLocalTimeZone() async {
    final value = await _channel.invokeMethod<String>('getLocalTimeZone');
    if (value == null || value.trim().isEmpty) {
      throw const FormatException('Fuseau horaire local indisponible');
    }
    return value.trim();
  }
}

class DeviceTimeZoneService {
  static bool _initialized = false;

  static Future<tz.Location> refreshLocalLocation(
    TimeZoneResolver resolver,
  ) async {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
    final name = await resolver.getLocalTimeZone();
    final normalized = name.trim();
    final upper = normalized.toUpperCase();
    final location = upper == 'UTC' ||
            upper == 'GMT' ||
            upper == 'ETC/UTC' ||
            upper == 'ETC/GMT'
        ? tz.UTC
        : tz.getLocation(normalized);
    tz.setLocalLocation(location);
    return location;
  }
}
