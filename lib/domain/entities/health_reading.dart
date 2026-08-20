// flutter_app/lib/domain/entities/health_reading.dart

class HealthReading {
  final String id;
  final String deviceId;
  final String userId;
  final int timestamp;
  final String isoTimestamp;
  final int heartRate;
  final double spo2;
  final int steps;
  final int stepDelta;
  final int caloriesBurned;
  final int batteryLevel;
  final bool isCharging;
  final int rssi;
  final int rrIntervalMs;
  final String anomaly; // 'none' | 'arrhythmia' | 'hypoxia' | 'tachycardia' | 'bradycardia'
  final bool synced;

  const HealthReading({
    required this.id,
    this.deviceId = 'FITRING-001',
    required this.userId,
    required this.timestamp,
    String? isoTimestamp,
    required this.heartRate,
    required this.spo2,
    required this.steps,
    required this.stepDelta,
    required this.caloriesBurned,
    required this.batteryLevel,
    required this.isCharging,
    required this.rssi,
    required this.rrIntervalMs,
    required this.anomaly,
    this.synced = false,
  }) : isoTimestamp = isoTimestamp ?? '';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deviceId': deviceId,
      'userId': userId,
      'timestamp': timestamp,
      'isoTimestamp': isoTimestamp,
      'heartRate': heartRate,
      'spo2': spo2,
      'steps': steps,
      'stepDelta': stepDelta,
      'caloriesBurned': caloriesBurned,
      'batteryLevel': batteryLevel,
      'isCharging': isCharging ? 1 : 0,
      'rssi': rssi,
      'rrIntervalMs': rrIntervalMs,
      'anomaly': anomaly,
      'synced': synced ? 1 : 0,
    };
  }

  factory HealthReading.fromMap(Map<String, dynamic> map) {
    final ts = map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    return HealthReading(
      id: map['id'] as String,
      deviceId: map['deviceId'] as String? ?? 'FITRING-001',
      userId: map['userId'] as String? ?? 'default_user',
      timestamp: ts,
      isoTimestamp: map['isoTimestamp'] as String? ?? DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String(),
      heartRate: (map['heartRate'] as num).toInt(),
      spo2: (map['spo2'] as num).toDouble(),
      steps: (map['steps'] as num).toInt(),
      stepDelta: (map['stepDelta'] as num?)?.toInt() ?? 0,
      caloriesBurned: (map['caloriesBurned'] as num).toInt(),
      batteryLevel: (map['batteryLevel'] as num).toInt(),
      isCharging: map['isCharging'] == 1 || map['isCharging'] == true,
      rssi: (map['rssi'] as num).toInt(),
      rrIntervalMs: (map['rrIntervalMs'] as num).toInt(),
      anomaly: map['anomaly'] as String? ?? 'none',
      synced: map['synced'] == 1 || map['synced'] == true,
    );
  }
}
