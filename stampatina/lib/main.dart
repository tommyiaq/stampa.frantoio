import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: BluetoothPrinterApp(),
    );
  }
}

class BluetoothPrinterApp extends StatefulWidget {
  const BluetoothPrinterApp({super.key});

  @override
  State<BluetoothPrinterApp> createState() => _BluetoothPrinterAppState();
}

class _BluetoothPrinterAppState extends State<BluetoothPrinterApp> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  void _initBluetooth() async {
    await _requestPermissions();
    bool isOn = await bluetooth.isOn ?? false;
    if (!isOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable Bluetooth manually.')),
      );
    }
    _getBondedDevices();
    bluetooth.onStateChanged().listen((state) async {
      if (state == BlueThermalPrinter.CONNECTED) {
        setState(() {
          _isConnected = true;
        });
      } else {
        setState(() {
          _isConnected = false;
        });
      }
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  void _getBondedDevices() async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      setState(() {
        _devicesList = devices;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting bonded devices: $e')),
      );
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _selectedDevice = device;
    });
    try {
      await bluetooth.connect(device);
      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot connect: $e')),
      );
    }
  }

  void _printHelloWorld() async {
    if (!_isConnected || _selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to any device')),
      );
      return;
    }
    try {
      await bluetooth.printNewLine();
      await bluetooth.printCustom("Hello World!", 2, 1);
      await bluetooth.printNewLine();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hello World sent to printer!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e')),
      );
    }
  }

  void _disconnect() async {
    await bluetooth.disconnect();
    setState(() {
      _isConnected = false;
      _selectedDevice = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Printer'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bluetooth status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Bluetooth Status: ${_isConnected ? "Connected" : "Disconnected"}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Connection status
            if (_isConnected && _selectedDevice != null)
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Connected to ${_selectedDevice!.name}',
                        style: const TextStyle(fontSize: 16, color: Colors.green),
                      ),
                      ElevatedButton(
                        onPressed: _disconnect,
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
                ),
              ),
            // Print button
            if (_isConnected && _selectedDevice != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _printHelloWorld,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text(
                  'Print Hello World!',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Bonded Devices:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Device list
            Expanded(
              child: _devicesList.isEmpty
                  ? const Center(
                      child: Text(
                        'No bonded devices found.\nPair your printer in Android Bluetooth settings first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _devicesList.length,
                      itemBuilder: (context, index) {
                        BluetoothDevice device = _devicesList[index];
                        return Card(
                          child: ListTile(
                            title: Text(device.name ?? 'Unknown Device'),
                            subtitle: Text(device.address ?? ''),
                            trailing: _isConnecting
                                ? const CircularProgressIndicator()
                                : ElevatedButton(
                                    onPressed: !_isConnected
                                        ? () => _connectToDevice(device)
                                        : null,
                                    child: const Text('Connect'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    bluetooth.disconnect();
    super.dispose();
  }
}
