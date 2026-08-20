# PulseSync: Wearable Health Platform & Flutter Architecture

PulseSync is a wearable health telemetry and biometrics application designed with Clean Architecture, an offline-first sync engine, and a hardware interface bridge.

---

## 1. Application Layer Separation (Current Architecture)

The application separates presentation and domain logic from the underlying hardware implementation via the `IWearableService` contract:

```
+-------------------------------------------------------------+
|                     Flutter Application                     |
|           (UI Widgets, State Management, Views)             |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|                Wearable Service / Interface                 |
|                     (IWearableService)                      |
|       - connectionStateStream, telemetryStream, scan()      |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|                 Mock Wearable Implementation                |
|                    (MockWearableService)                    |
|   - Real-time HR, SpO2, Step generation                     |
|   - Exponential backoff reconnect simulation                |
|   - Fault injection (Arrhythmia, Hypoxia, Link-drop)        |
+-------------------------------------------------------------+
```

---

## 2. Replacing Mock Implementation with Real Hardware / SDK

To swap the mock implementation with a real hardware peripheral (such as a **Smart Ring**, ECG patch, or Smartwatch), the architecture replaces `MockWearableService` with a **Native Bridge** (`PlatformChannelWearableService`) that delegates BLE GATT commands to native Android and iOS SDKs:

```
+-------------------------------------------------------------+
|                     Flutter Application                     |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|                        Native Bridge                        |
|   MethodChannel ('io.pulsesync/methods')                    |
|   EventChannel  ('io.pulsesync/telemetry_stream')           |
+-------------------------------------------------------------+
                              |
              +---------------+---------------+
              |                               |
              v                               v
+---------------------------+   +---------------------------+
|        Android SDK        |   |          iOS SDK          |
|   (BluetoothGattCallback) |   |  (CBCentralManager /      |
|                           |   |   CBPeripheralDelegate)   |
+---------------------------+   +---------------------------+
              |                               |
              v                               v
+---------------------------+   +---------------------------+
|        Kotlin/Java        |   |        Swift/Obj-C        |
|  - Nordic BLE / Android   |   |  - CoreBluetooth          |
|  - GATT Standard Services |   |  - GATT Standard Services |
|    (0x180D, 0x1822, 0x180F) |  |    (0x180D, 0x1822, 0x180F)|
+---------------------------+   +---------------------------+
              \                               /
               \                             /
                v                           v
+-------------------------------------------------------------+
|                         Smart Ring                          |
|         (PPG Photoplethysmography Sensor & Accel)           |
+-------------------------------------------------------------+
```

### Step-by-Step Migration Guide

1. **Step 1: Implement Dart Contract**  
   Create `PlatformChannelWearableService` implementing `IWearableService` using `MethodChannel` for commands (`connect`, `disconnect`, `scan`) and `EventChannel` for continuous streams (`telemetryStream`, `connectionStateStream`).

2. **Step 2: Implement Android Kotlin Bridge**  
   In `android/app/src/main/kotlin/io/pulsesync/WearablePlugin.kt`:
   - Initialize `BluetoothManager` and `BluetoothAdapter`.
   - Implement `BluetoothGattCallback` to subscribe to Heart Rate (`0x2A37`), SpO2 (`0x2A5E`), and Battery (`0x2A19`).
   - Pipe raw bytes parsed from the Smart Ring into `EventSink.success(map)`.

3. **Step 3: Implement iOS Swift Bridge**  
   In `ios/Runner/WearablePlugin.swift`:
   - Conform to `CBCentralManagerDelegate` and `CBPeripheralDelegate`.
   - In `peripheral(_:didUpdateValueFor:error:)`, unpack PPG packet bytes into structured telemetry maps.
   - Stream telemetry to Flutter via `FlutterEventSink`.

4. **Step 4: Swap Dependency Injection Binding**  
   In your Service Locator (`get_it` or Provider):
   ```dart
   // Debug / Testing Mode:
   // locator.registerLazySingleton<IWearableService>(() => MockWearableService());

   // Production Real Device Mode:
   locator.registerLazySingleton<IWearableService>(() => PlatformChannelWearableService());
   ```

---

## 3. Reconnection Strategy (Exponential Backoff with Jitter)

When unexpected radio link-loss occurs, the reconnection engine automatically triggers an exponential backoff sequence to preserve power and prevent radio packet collisions:

$$\text{Delay} = \min(T_{\text{max}}, T_{\text{base}} \times 1.6^{\text{attempt} - 1}) + \text{UniformRandom}(0, \text{Jitter}_{\text{ms}})$$

- **Base Delay ($T_{\text{base}}$)**: 1,200 ms
- **Multiplier**: 1.6x exponential progression
- **Maximum Delay ($T_{\text{max}}$)**: 10,000 ms ceiling
- **Randomized Jitter**: 0 to 400 ms
- **Max Retry Threshold**: 5 attempts before transitioning to terminal `failed` state with user prompt.

---

## 4. Offline-First Write-Ahead Sync Engine

- **Write-Ahead Logging (WAL)**: Telemetry frames are committed to local storage (SQLite / IndexedDB) before network transmission is initiated.
- **FIFO Offline Buffer**: If internet connectivity is lost, readings queue locally with `synced: false`.
- **Automatic Background Sync**: A background worker monitors network availability and flushes batches (up to 50 readings) upon network reconnection.
- **Idempotency & Deduplication**: Each batch item carries a unique signature `idemp_{reading.id}_{timestamp}`. If a network timeout occurs after backend receipt, duplicates are discarded safely.

---

## 5. Local Data Aggregation & Pagination

- **Time-Bucket Aggregations**: Computes hourly, daily, and weekly averages, minimums, maximums, and anomaly counts locally on device.
- **Paginated History Queries**: Prevents UI lag when rendering thousands of historical biometric data points.
