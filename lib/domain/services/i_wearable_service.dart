// flutter_app/lib/domain/services/i_wearable_service.dart
import 'dart:async';
import '../entities/health_reading.dart';
import '../entities/wearable_device_info.dart';

/// Architecture Tier:
/// -------------------------------------------------------------
/// Flutter Application
///         |
/// Wearable Service / Interface (IWearableService)
///         |
/// Mock Wearable Implementation OR Real Native SDK Platform Channel
/// -------------------------------------------------------------
abstract class IWearableService {
  /// Current connection status of the wearable peripheral.
  DeviceConnectionState get connectionState;

  /// Active connected hardware info metadata.
  WearableDeviceInfo? get activeDevice;

  /// Scans for nearby BLE wearables / Smart Rings.
  Future<List<WearableDeviceInfo>> scanForDevices({Duration timeout = const Duration(seconds: 4)});

  /// Initiates BLE GATT connection to a peripheral.
  Future<bool> connect(String deviceId);

  /// Disconnects from current peripheral.
  Future<void> disconnect({String? reason});

  /// Reconnection policy execution (Exponential backoff).
  Future<bool> reconnect();

  /// Reactive stream of device connection state transitions.
  Stream<DeviceConnectionState> get connectionStateStream;

  /// High-frequency real-time stream of sensor telemetry frames (HR, SpO2, Steps, RR).
  Stream<HealthReading> get telemetryStream;

  /// Reactive stream of battery percentage and charging state changes.
  Stream<int> get batteryStream;

  /// Disposes open streams and resources.
  void dispose();
}
