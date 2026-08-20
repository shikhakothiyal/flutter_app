// flutter_app/lib/data/services/platform_channel_wearable_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import '../../domain/entities/health_reading.dart';
import '../../domain/entities/wearable_device_info.dart';
import '../../domain/services/i_wearable_service.dart';

/// Architecture Tier:
/// -------------------------------------------------------------------
/// Flutter Application
///         |
/// Native Bridge (Platform Channels)
///         |
/// Android SDK (Kotlin/Java)      iOS SDK (Swift/Obj-C)
///         |                               |
/// -------------------------------------------------------------------
///                         Smart Ring / BLE
/// -------------------------------------------------------------------
class PlatformChannelWearableService implements IWearableService {
  // Method channel for RPC commands (connect, disconnect, scan, startStream)
  static const MethodChannel _methodChannel =
      MethodChannel('io.pulsesync.wearable/methods');

  // Event channels for continuous reactive hardware streaming
  static const EventChannel _telemetryEventChannel =
      EventChannel('io.pulsesync.wearable/telemetry_stream');
  static const EventChannel _stateEventChannel =
      EventChannel('io.pulsesync.wearable/state_stream');
  static const EventChannel _batteryEventChannel =
      EventChannel('io.pulsesync.wearable/battery_stream');

  final _telemetryController = StreamController<HealthReading>.broadcast();
  final _stateController = StreamController<DeviceConnectionState>.broadcast();
  final _batteryController = StreamController<int>.broadcast();

  StreamSubscription? _telemetrySub;
  StreamSubscription? _stateSub;
  StreamSubscription? _batterySub;

  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  WearableDeviceInfo? _deviceInfo;

  PlatformChannelWearableService() {
    _initNativeEventChannels();
  }

  void _initNativeEventChannels() {
    // 1. Listen for continuous heart rate, SpO2 & steps from native Android/iOS SDK
    _telemetrySub = _telemetryEventChannel
        .receiveBroadcastStream()
        .listen((dynamic rawData) {
      if (rawData is Map) {
        final reading = HealthReading.fromMap(Map<String, dynamic>.from(rawData));
        _telemetryController.add(reading);
      }
    }, onError: (err) {
      print('Native Telemetry Stream Error: $err');
    });

    // 2. Listen for Bluetooth peripheral state transitions (Connected, Link Loss, Reconnecting)
    _stateSub = _stateEventChannel
        .receiveBroadcastStream()
        .listen((dynamic rawState) {
      final stateStr = rawState.toString();
      final newState = DeviceConnectionState.values.firstWhere(
        (e) => e.name == stateStr,
        orElse: () => DeviceConnectionState.disconnected,
      );
      _state = newState;
      _stateController.add(newState);
    });

    // 3. Listen for battery notifications (GATT 0x180F)
    _batterySub = _batteryEventChannel
        .receiveBroadcastStream()
        .listen((dynamic rawBattery) {
      if (rawBattery is int) {
        _batteryController.add(rawBattery);
      }
    });
  }

  @override
  DeviceConnectionState get connectionState => _state;

  @override
  WearableDeviceInfo? get activeDevice => _deviceInfo;

  @override
  Stream<DeviceConnectionState> get connectionStateStream => _stateController.stream;

  @override
  Stream<HealthReading> get telemetryStream => _telemetryController.stream;

  @override
  Stream<int> get batteryStream => _batteryController.stream;

  @override
  Future<List<WearableDeviceInfo>> scanForDevices({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final List<dynamic>? result = await _methodChannel.invokeMethod('scanForDevices', {
        'timeoutMs': timeout.inMilliseconds,
      });

      if (result == null) return [];

      return result.map((item) {
        return WearableDeviceInfo.fromMap(Map<String, dynamic>.from(item as Map));
      }).toList();
    } on PlatformException catch (e) {
      print('BLE Scan Failed: \${e.message}');
      return [];
    }
  }

  @override
  Future<bool> connect(String deviceId) async {
    try {
      final Map<dynamic, dynamic>? result = await _methodChannel.invokeMethod('connect', {
        'deviceId': deviceId,
      });

      if (result != null) {
        _deviceInfo = WearableDeviceInfo.fromMap(Map<String, dynamic>.from(result));
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      print('BLE Connect Failed: \${e.message}');
      return false;
    }
  }

  @override
  Future<void> disconnect({String? reason}) async {
    try {
      await _methodChannel.invokeMethod('disconnect', {
        'reason': reason ?? 'User initiated',
      });
      _deviceInfo = null;
    } on PlatformException catch (e) {
      print('BLE Disconnect Failed: \${e.message}');
    }
  }

  @override
  Future<bool> reconnect() async {
    try {
      final bool? success = await _methodChannel.invokeMethod('reconnect');
      return success ?? false;
    } on PlatformException catch (e) {
      print('BLE Reconnect Failed: \${e.message}');
      return false;
    }
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _stateSub?.cancel();
    _batterySub?.cancel();
    _telemetryController.close();
    _stateController.close();
    _batteryController.close();
  }
}
