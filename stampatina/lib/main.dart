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
  // Removed duplicate declarations (already defined below)
  List<TextEditingController> _addendControllers = [TextEditingController(text: '')];
  // _totalSum getter removed (inlined in usage)
  String _currentDateTime = '';
  final TextEditingController _textController = TextEditingController();
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _selectedIndex = 0; // Print page is now home

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _initBluetooth();
    // Update the datetime every second
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      _updateDateTime();
      return true;
    });
  }

  void _updateDateTime() {
    final now = DateTime.now();
    final formatted = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _currentDateTime = formatted;
    });
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
    String name = _textController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter text to print.')),
      );
      return;
    }
    List<double> addends = _addendControllers.map((c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0).toList();
    double total = addends.fold(0.0, (sum, v) => sum + v);
    try {
      await bluetooth.printNewLine();
      await bluetooth.printCustom(_currentDateTime, 1, 1);
      await bluetooth.printCustom(name, 2, 1);
      await bluetooth.printNewLine();
      for (int i = 0; i < addends.length; i++) {
        await bluetooth.printCustom('Pesata ${i + 1}: ${addends[i].toStringAsFixed(1)}', 1, 1);
      }
      await bluetooth.printCustom('--------------------------', 1, 1);
      await bluetooth.printCustom('Totale: ${total.toStringAsFixed(1)}', 2, 1);
      await bluetooth.printNewLine();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text sent to printer!')),
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
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top: Connection status
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Text(
              _isConnected && _selectedDevice != null
                  ? 'Connected to: ${_selectedDevice!.name ?? 'Unknown'}'
                  : 'Not connected',
              style: TextStyle(
                fontSize: 18,
                color: _isConnected ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Show current date/time
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Text(
              _currentDateTime,
              style: const TextStyle(fontSize: 18, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
          // Name input
          SizedBox(
            width: 350,
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nome Cognome',
                hintText: 'Nome Cognome',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 24),
          // Addends list
          Expanded(
            child: Column(
              children: [
                // Addends fields
                Expanded(
                  child: ListView.builder(
                    itemCount: _addendControllers.length,
                    itemBuilder: (context, idx) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _addendControllers[idx],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Pesata ${idx + 1}',
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            if (_addendControllers.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _addendControllers[idx].dispose();
                                    _addendControllers.removeAt(idx);
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Add button
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('aggiungi pesata'),
                    onPressed: () {
                      setState(() {
                        _addendControllers.add(TextEditingController(text: ''));
                      });
                    },
                  ),
                ),
                // Horizontal line
                const Divider(thickness: 2),
                // Total sum
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Totale:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Builder(
                        builder: (context) {
                          double total = _addendControllers.fold(0.0, (sum, c) {
                            final v = double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
                            return sum + v;
                          });
                          return Text(total.toStringAsFixed(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Bottom: Print button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isConnected == true && _selectedDevice != null) ? _printHelloWorld : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 24),
                textStyle: const TextStyle(fontSize: 22),
              ),
              child: const Text('Print'),
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
    _textController.dispose();
    for (final c in _addendControllers) {
      c.dispose();
    }
    bluetooth.disconnect();
    super.dispose();
  }
}
