import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int _selectedIndex = 0; // Print page is now home

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
    await _getBondedDevices();
    await _tryAutoConnect();
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
      setState(() {}); // Force UI refresh after state change
    });
  }

  Future<void> _tryAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAddress = prefs.getString('last_device_address');
    if (lastAddress != null && _devicesList.isNotEmpty) {
      final device = _devicesList.firstWhere(
        (d) => d.address == lastAddress,
        orElse: () => _devicesList.first,
      );
      try {
        bool isConnected = await bluetooth.isConnected ?? false;
        if (!isConnected) {
          await bluetooth.connect(device);
        }
        // After connect, check again
        isConnected = await bluetooth.isConnected ?? false;
        if (mounted) {
          setState(() {
            _selectedDevice = isConnected ? device : null;
            _isConnected = isConnected;
            _isConnecting = false;
          });
          // Workaround: after a short delay, re-check connection and update UI
          Future.delayed(const Duration(milliseconds: 500), () async {
            bool reallyConnected = await bluetooth.isConnected ?? false;
            if (mounted) {
              setState(() {
                _isConnected = reallyConnected;
                if (!reallyConnected) _selectedDevice = null;
              });
              // Extra setState to force UI update after delayed check
              setState(() {});
            }
          });
          if (isConnected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Auto-connected to ${device.name}')),
              );
            });
          } else {
            // Clear saved device if not connected
            await prefs.remove('last_device_address');
            print('DEBUG: Autoconnect failed, cleared saved device');
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _selectedDevice = null;
          });
          await prefs.remove('last_device_address');
          print('DEBUG: Autoconnect failed: $e, cleared saved device');
        }
      }
    } else {
      print('DEBUG: No lastAddress or no devices to autoconnect');
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _getBondedDevices() async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      setState(() {
        _devicesList = devices;
      });
      setState(() {}); // Force UI refresh
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
      bool isConnected = await bluetooth.isConnected ?? false;
      if (isConnected) {
        // Already connected, just update UI
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _selectedDevice = device;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_device_address', device.address ?? '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Already connected to ${device.name}')),
        );
        return;
      }
      await bluetooth.connect(device);
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _selectedDevice = device;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_device_address', device.address ?? '');
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

  void _onNavTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildBluetoothPage() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 16),
          const Text(
            'Bonded Devices:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
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
    );
  }

  Widget _buildPrintPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isConnected && _selectedDevice != null
                ? 'Connected to: ${_selectedDevice!.name ?? 'Unknown'}'
                : 'Not connected',
            style: TextStyle(
              fontSize: 18,
              color: _isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: (_isConnected == true && _selectedDevice != null) ? _printHelloWorld : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(24),
            ),
            child: const Text(
              'Print Hello World!',
              style: TextStyle(fontSize: 22),
            ),
          ),
        ],
      ),
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
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildPrintPage(), // Print page is now first
          _buildBluetoothPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.print),
            label: 'Print',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Bluetooth',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    bluetooth.disconnect();
    super.dispose();
  }
}
