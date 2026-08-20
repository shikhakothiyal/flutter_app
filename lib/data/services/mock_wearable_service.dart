// flutter_app/lib/data/services/mock_wearable_service.dart
import 'dart:async';
import 'dart:math';
import '../../domain/entities/health_reading.dart';
import '../../domain/entities/wearable_device_info.dart';
import '../../domain/services/i_wearable_service.dart';

/// Architecture Tier:
/// Flutter Application -> Wearable Service Interface -> Mock Wearable Implementation
class MockWearableService implements IWearableService {
  final _connectionStateController = StreamController<DeviceConnectionState>.broadcast();
  final _telemetryController = StreamController<HealthReading>.broadcast();
  final _batteryController = StreamController<int>.broadcast();

  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  WearableDeviceInfo? _device;
  Timer? _telemetryTimer;
  Timer? _batteryTimer;
  final Random _random = Random();

  int _currentHeartRate = 72;
  double _currentSpo2 = 98.4;
  int _totalSteps = 6420;
  int _calories = 280;
  int _batteryLevel = 88;
  int _reconnectAttempts = 0;

  @override
  DeviceConnectionState get connectionState => _state;

  @override
  WearableDeviceInfo? get activeDevice => _device;

  @override
  Stream<DeviceConnectionState> get connectionStateStream => _connectionStateController.stream;

  @override
  Stream<HealthReading> get telemetryStream => _telemetryController.stream;

  @override
  Stream<int> get batteryStream => _batteryController.stream;

  @override
  Future<List<WearableDeviceInfo>> scanForDevices({Duration timeout = const Duration(seconds: 2)}) async {
    _updateState(DeviceConnectionState.scanning);
    await Future.delayed(timeout);
    _updateState(DeviceConnectionState.disconnected);

    return [
      WearableDeviceInfo(
        id: 'smart-ring-pro-9a1b',
        name: 'PulseSync Smart Ring v2',
        model: 'SR-200-BLE',
        macAddress: 'C4:7D:E2:89:9A:1B',
        firmwareVersion: 'v2.4.1-ring',
        hardwareRevision: 'REV-B',
        batteryLevel: _batteryLevel,
        isCharging: false,
        rssi: -58,
        state: DeviceConnectionState.disconnected,
      ),
      WearableDeviceInfo(
        id: 'pulse-band-pro-8f2a',
        name: 'PulseSync Band Pro',
        model: 'PB-500-HR',
        macAddress: 'F2:8B:C1:3D:8F:2A',
        firmwareVersion: 'v3.4.1-ble',
        hardwareRevision: 'REV-A',
        batteryLevel: 94,
        isCharging: false,
        rssi: -66,
        state: DeviceConnectionState.disconnected,
      ),
    ];
  }

  @override
  Future<bool> connect(String deviceId) async {
    _updateState(DeviceConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 1200));

    _device = WearableDeviceInfo(
      id: deviceId,
      name: deviceId.contains('ring') ? 'PulseSync Smart Ring v2' : 'PulseSync Band Pro',
      model: 'SR-200-BLE',
      macAddress: 'C4:7D:E2:89:9A:1B',
      firmwareVersion: 'v2.4.1-ring',
      hardwareRevision: 'REV-B',
      batteryLevel: _batteryLevel,
      isCharging: false,
      rssi: -58 + _random.nextInt(6),
      state: DeviceConnectionState.connected,
    );

    _updateState(DeviceConnectionState.connected);
    _reconnectAttempts = 0;
    _startTelemetry();
    return true;
  }

  @override
  Future<void> disconnect({String? reason}) async {
    _stopTelemetry();
    _device = null;
    _updateState(DeviceConnectionState.disconnected);
  }

  @override
  Future<bool> reconnect() async {
    _stopTelemetry();
    _reconnectAttempts++;
    _updateState(DeviceConnectionState.reconnecting);

    // Exponential backoff formula: min(10s, 1.2s * 1.6^(attempt-1)) + jitter
    final backoffMs = min(10000, (1200 * pow(1.6, _reconnectAttempts - 1)).toInt()) + _random.nextInt(400);
    await Future.delayed(Duration(milliseconds: backoffMs));

    if (_reconnectAttempts <= 5) {
      return connect(_device?.id ?? 'smart-ring-pro-9a1b');
    } else {
      _updateState(DeviceConnectionState.failed);
      return false;
    }
  }

  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_state != DeviceConnectionState.connected) return;

      // Realistic random-walk physiological signal simulation
      final hrDelta = _random.nextInt(5) - 2;
      _currentHeartRate = (_currentHeartRate + hrDelta).clamp(55, 175);
      
      final stepDelta = _random.nextInt(4);
      _totalSteps += stepDelta;
      _calories += (stepDelta > 0 ? 1 : 0);

      final now = DateTime.now();
      final reading = HealthReading(
        id: 'reading_${now.millisecondsSinceEpoch}_${_random.nextInt(9999)}',
        deviceId: _device?.id ?? 'FITRING-001',
        userId: 'user_active',
        timestamp: now.millisecondsSinceEpoch,
        isoTimestamp: now.toUtc().toIso8601String(),
        heartRate: _currentHeartRate,
        spo2: _currentSpo2,
        steps: _totalSteps,
        stepDelta: stepDelta,
        caloriesBurned: _calories,
        batteryLevel: _batteryLevel,
        isCharging: false,
        rssi: -58 + _random.nextInt(6) - 3,
        rrIntervalMs: (60000 / _currentHeartRate).round(),
        anomaly: 'none',
        synced: false,
      );

      _telemetryController.add(reading);
    });
  }

  void _stopTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void _updateState(DeviceConnectionState newState) {
    _state = newState;
    _connectionStateController.add(newState);
  }

  @override
  void dispose() {
    _stopTelemetry();
    _batteryTimer?.cancel();
    _connectionStateController.close();
    _telemetryController.close();
    _batteryController.close();
  }
}
