// flutter_app/lib/domain/entities/wearable_device_info.dart

enum DeviceConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
  failed,
}

class WearableDeviceInfo {
  final String id;
  final String name;
  final String model;
  final String macAddress;
  final String firmwareVersion;
  final String hardwareRevision;
  final int batteryLevel;
  final bool isCharging;
  final int rssi;
  final DeviceConnectionState state;

  const WearableDeviceInfo({
    required this.id,
    required this.name,
    required this.model,
    required this.macAddress,
    required this.firmwareVersion,
    required this.hardwareRevision,
    required this.batteryLevel,
    required this.isCharging,
    required this.rssi,
    required this.state,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'model': model,
      'macAddress': macAddress,
      'firmwareVersion': firmwareVersion,
      'hardwareRevision': hardwareRevision,
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'rssi': rssi,
      'state': state.name,
    };
  }

  factory WearableDeviceInfo.fromMap(Map<String, dynamic> map) {
    return WearableDeviceInfo(
      id: map['id'] as String,
      name: map['name'] as String,
      model: map['model'] as String? ?? 'Smart Ring v2',
      macAddress: map['macAddress'] as String,
      firmwareVersion: map['firmwareVersion'] as String? ?? '1.0.0',
      hardwareRevision: map['hardwareRevision'] as String? ?? 'REV-B',
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? 100,
      isCharging: map['isCharging'] == true,
      rssi: (map['rssi'] as num?)?.toInt() ?? -60,
      state: DeviceConnectionState.values.firstWhere(
        (e) => e.name == map['state'],
        orElse: () => DeviceConnectionState.disconnected,
      ),
    );
  }
}
