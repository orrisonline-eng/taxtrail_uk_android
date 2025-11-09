// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const TaxTrailApp());
}

class TaxTrailApp extends StatelessWidget {
  const TaxTrailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'TaxTrail',
      home: TaxTrailHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TaxTrailHome extends StatefulWidget {
  const TaxTrailHome({super.key});

  @override
  State<TaxTrailHome> createState() => _TaxTrailHomeState();
}

class _TaxTrailHomeState extends State<TaxTrailHome> {
  final TextEditingController _labelController = TextEditingController();
  String? _lastSavedImagePath;

  @override
  void initState() {
    super.initState();
    _lastSavedImagePath = null; // Ensures no image is preloaded
  }

  Future<void> _captureAndSaveImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile == null) return;

    final now = DateTime.now();
    final fiscalInfo = _getFiscalQuarter(now);
    final label = _labelController.text.trim().isEmpty
        ? 'receipt'
        : _labelController.text.trim();
    final fileName =
        '${label}_${DateFormat("yyyy-MM-ddTHH-mm-ss").format(now)}.png';

    final dir =
        await getApplicationDocumentsDirectory(); // Even safer, works on Android and iOS
    final saveDir = Directory(
        '${dir.path}/UK/${fiscalInfo['quarter']} ${fiscalInfo['year']}');

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final savedImage =
        await File(pickedFile.path).copy('${saveDir.path}/$fileName');

    setState(() {
      _lastSavedImagePath = savedImage.path;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to: ${savedImage.path}')),
    );
  }

  Map<String, dynamic> _getFiscalQuarter(DateTime date) {
    int year = date.year;
    final int month = date.month;
    final int day = date.day;

    // Adjust for UK fiscal year starting April 6
    if (month < 4 || (month == 4 && day < 6)) {
      year -= 1;
    }

    late String quarter;
    if (month >= 4 && month <= 6 && !(month == 4 && day < 6)) {
      quarter = 'QTR 1';
    } else if (month >= 7 && month <= 9) {
      quarter = 'QTR 2';
    } else if (month >= 10 && month <= 12) {
      quarter = 'QTR 3';
    } else {
      quarter = 'QTR 4';
    }

    return {'year': year, 'quarter': quarter};
  }

  Future<void> _shareLastImage() async {
    if (_lastSavedImagePath != null) {
      await Share.shareXFiles(
  [XFile(_lastSavedImagePath!, mimeType: 'image/png')],
);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image to share.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: const Text('TaxTrail'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Enter a label',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _captureAndSaveImage,
              child: const Text('Capture & Save'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _shareLastImage,
              child: const Text('Share Last Image'),
            ),
          ],
        ),
      ),
    );
  }
}
