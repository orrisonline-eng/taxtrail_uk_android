import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:csv/csv.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaxTrail',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'TaxTrail Receipt Manager'),
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

      final directory = Directory('/storage/emulated/0/Download');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      final savedImagePath = '${directory.path}/$fileName';
      await File(pickedFile.path).copy(savedImagePath);

      final receipt = Receipt(
        filename: fileName,
        receiptType: labelData['receiptType']!,
        amount: labelData['amount']!,
        date: labelData['date']!,
        otherInfo: labelData['otherInfo']!,
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
      final directory = Directory('/storage/emulated/0/Download');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
          ],
        ),
      ),
    );
  }
}
