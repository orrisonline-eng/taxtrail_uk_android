import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Purchases.configure(
    PurchasesConfiguration(
      "test_PKlicjFvyfeLnhrqqYsutzEyIzd", // Your RevenueCat API key
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaxTrail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Welcome to Taxtrail'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class Receipt {
  final String filename;
  final String receiptType;
  final String amount;
  final String date;
  final String otherInfo;
  final String taxReference;

  Receipt({
    required this.filename,
    required this.receiptType,
    required this.amount,
    required this.date,
    required this.otherInfo,
    this.taxReference = '',
  });
}

class _MyHomePageState extends State<MyHomePage> {
  final ImagePicker _picker = ImagePicker();
  String? _lastSavedImagePath;
  final List<Receipt> _receipts = [];
  final TextEditingController _taxRefController = TextEditingController();

  bool _isProUser = false;
  bool _checkedProStatus = false;

  @override
  void initState() {
    super.initState();
    _initializeRevenueCat();
    _loadTaxReference();
    _checkProStatus();
  }

  Future<void> _initializeRevenueCat() async {
    try {
      await Purchases.setLogLevel(LogLevel.debug);
      _fetchOfferings();
    } catch (e) {
      print('RevenueCat initialization failed: $e');
    }
  }

  Future<void> _fetchOfferings() async {
    try {
      Offerings offerings = await Purchases.getOfferings();
      if (offerings.current != null &&
          offerings.current!.availablePackages.isNotEmpty) {
        Package package = offerings.current!.availablePackages[0];
        print('Package identifier: ${package.identifier}');
        print('Price: ${package.storeProduct.priceString}');
      } else {
        print('No available packages');
      }
    } catch (e) {
      print('Error fetching offerings: $e');
    }
  }

  Future<void> _checkProStatus() async {
    try {
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      setState(() {
        _isProUser =
            customerInfo.entitlements.all['taxtrail_pro']?.isActive == true;
        _checkedProStatus = true;
      });
    } catch (e) {
      setState(() {
        _isProUser = false;
        _checkedProStatus = true;
      });
    }
  }

  Future<void> _purchasePackage(Package package) async {
    try {
      await Purchases.purchasePackage(package);
      await _checkProStatus();
      if (_isProUser && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Purchase successful! Taxtrail Pro activated!')),
        );
      }
    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Purchase failed: ${e.message}')),
          );
        }
      } else {
        print('Purchase was cancelled by user');
      }
    } catch (e) {
      print('Purchase error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: $e')),
        );
      }
    }
  }

  Future<void> _triggerPurchase() async {
    try {
      Offerings offerings = await Purchases.getOfferings();
      if (offerings.current != null &&
          offerings.current!.availablePackages.isNotEmpty) {
        Package package = offerings.current!.availablePackages[0];
        await _purchasePackage(package);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No packages available for purchase')),
          );
        }
      }
    } catch (e) {
      print('Error triggering purchase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting purchase: $e')),
        );
      }
    }
  }

  Future<void> _restorePurchases() async {
    try {
      await Purchases.restorePurchases();
      await _checkProStatus();
      if (_isProUser && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases restored! Taxtrail Pro is active.')),
        );
      } else if (!_isProUser && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous purchases to restore.')),
        );
      }
    } catch (e) {
      print('Restore purchases error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }

  Future<void> _loadTaxReference() async {
    final prefs = await SharedPreferences.getInstance();
    _taxRefController.text = prefs.getString('tax_reference') ?? '';
  }

  void _saveTaxReference(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tax_reference', value);
  }

  Future<void> _captureAndSaveImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      Map<String, String>? labelData = await _showLabelDialog();
      if (labelData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image capture cancelled')),
          );
        }
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final receiptType = labelData['receiptType']!.replaceAll(' ', '_');
      final fileName = '${receiptType}_$timestamp.jpg';

      final directory = await getApplicationDocumentsDirectory();
      final savedImagePath = '${directory.path}/$fileName';
      await File(pickedFile.path).copy(savedImagePath);
      print('Saved to: $savedImagePath');

      final receipt = Receipt(
        filename: fileName,
        receiptType: labelData['receiptType']!,
        amount: labelData['amount']!,
        date: labelData['date']!,
        otherInfo: labelData['otherInfo']!,
        taxReference: _taxRefController.text,
      );

      setState(() {
        _lastSavedImagePath = savedImagePath;
        _receipts.add(receipt);
      });

      await _exportToCSV();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image saved: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<Map<String, String>?> _showLabelDialog() async {
    final typeController = TextEditingController();
    final amountController = TextEditingController();
    final dateController = TextEditingController(
      text: DateTime.now().toString().split(' ')[0],
    );
    final otherController = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Receipt Information'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(
                    labelText: 'Receipt Type',
                    hintText: 'e.g., Meal, Transport, Office',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: 'e.g., 25.50',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: otherController,
                  decoration: const InputDecoration(
                    labelText: 'Other Info',
                    hintText: 'Notes, vendor, etc.',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'receiptType': typeController.text.isEmpty
                      ? 'unlabeled'
                      : typeController.text,
                  'amount': amountController.text,
                  'date': dateController.text,
                  'otherInfo': otherController.text,
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportToCSV() async {
    try {
      List<List<dynamic>> rows = [
        [
          'Tax Reference',
          'Filename',
          'Receipt_Type',
          'Amount',
          'Date',
          'Other Info'
        ]
      ];

      for (var receipt in _receipts) {
        rows.add([
          receipt.taxReference,
          receipt.filename,
          receipt.receiptType,
          receipt.amount,
          receipt.date,
          receipt.otherInfo,
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      final directory = await getApplicationDocumentsDirectory();
      final csvPath = '${directory.path}/taxtrail_receipts.csv';

      await File(csvPath).writeAsString(csv);
    } catch (e) {
      print('CSV Export Error: $e');
    }
  }

  Future<void> _shareLastImage() async {
    if (_lastSavedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image to share')),
      );
      return;
    }

    await Share.shareXFiles([XFile(_lastSavedImagePath!)]);
  }

  Future<void> _openLastImage() async {
    if (_lastSavedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image to open')),
      );
      return;
    }

    await OpenFile.open(_lastSavedImagePath!);
  }

  Future<void> _shareCSV() async {
    final directory = await getApplicationDocumentsDirectory();
    final csvPath = '${directory.path}/taxtrail_receipts.csv';
    final file = File(csvPath);

    if (await file.exists()) {
      await Share.shareXFiles([XFile(csvPath)]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV file not found')),
      );
    }
  }

  Future<void> _shareLastImageAndCSV() async {
    if (_lastSavedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image to share')),
      );
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final csvPath = '${directory.path}/taxtrail_receipts.csv';
    final csvFile = File(csvPath);
    if (!await csvFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV file not found')),
      );
      return;
    }

    await Share.shareXFiles(
      [XFile(_lastSavedImagePath!), XFile(csvPath)],
      text: 'Here is my latest receipt image and CSV export.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // While loading status, show progress spinner
    if (!_checkedProStatus) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // If not Pro, show paywall
    if (!_isProUser) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('TaxTrail'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.workspace_premium, size: 70, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  'Unlock TaxTrail Pro to use the app!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _triggerPurchase,
                  icon: const Icon(Icons.payment),
                  label: const Text('Purchase TaxTrail Pro'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _restorePurchases,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restore Purchases'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Already purchased? Tap "Restore Purchases".',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Pro user: main UI
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _taxRefController,
                decoration: const InputDecoration(
                  labelText: 'Tax Reference',
                  hintText: 'Enter your tax reference',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _saveTaxReference(value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Taxtrail Record Manager',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _captureAndSaveImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture and Save Image'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _shareLastImage,
              icon: const Icon(Icons.share),
              label: const Text('Share Last Image'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openLastImage,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Last Image'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _shareCSV,
              icon: const Icon(Icons.table_chart),
              label: const Text('Share CSV File'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _shareLastImageAndCSV,
              icon: const Icon(Icons.attach_file),
              label: const Text('Share Last Image + CSV'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const Divider(),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: _receipts.isEmpty
                  ? const Center(
                      child: Text('No receipts yet. Tap "Capture" to add one!'),
                    )
                  : ListView.builder(
                      itemCount: _receipts.length,
                      itemBuilder: (context, index) {
                        final receipt = _receipts[index];
                        return ListTile(
                          title: Text(receipt.filename),
                          subtitle: Text('${receipt.amount} - ${receipt.date}'),
                          leading: const Icon(Icons.receipt),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
