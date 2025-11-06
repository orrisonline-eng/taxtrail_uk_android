// lib/main.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

void main() {
  runApp(MediaSorterApp());
}

class MediaSorterApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Sorter',
      home: MediaSorterScreen(),
    );
  }
}

class MediaSorterScreen extends StatefulWidget {
  @override
  _MediaSorterScreenState createState() => _MediaSorterScreenState();
}

class _MediaSorterScreenState extends State<MediaSorterScreen> {
  final TextEditingController _labelController = TextEditingController();
  final GlobalKey _previewContainer = GlobalKey();
  String? _lastSavedImagePath;

  @override
  void initState() {
    super.initState();
    _requestStoragePermission();
  }

  Future<void> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      await Permission.manageExternalStorage.request();
      await Permission.storage.request();
    }
  }

  String _getUKFiscalQuarterFolderName(DateTime now) {
    int fiscalYear = now.year;
    if (now.isBefore(DateTime(now.year, 4, 6))) {
      fiscalYear--; // UK tax year starts April 6
    }

    int month = now.month;
    int day = now.day;
    int adjustedMonth =
        (month < 4 || (month == 4 && day < 6)) ? month + 12 : month;

    int quarter = ((adjustedMonth - 4) ~/ 3) + 1;
    return 'Q${quarter}_$fiscalYear';
  }

  Future<void> _captureAndSaveImage() async {
    try {
      RenderRepaintBoundary boundary = _previewContainer.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      var image = await boundary.toImage();
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      DateTime now = DateTime.now();
      String fiscalFolder = _getUKFiscalQuarterFolderName(now);
      String label = _labelController.text.trim().replaceAll(' ', '_');
      String fileName =
          'receipt_${label}_${now.toIso8601String().replaceAll(':', '-')}.png';

      Directory baseDir;

      if (Platform.isAndroid) {
        baseDir = Directory('/storage/emulated/0/Download');
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final saveDir = Directory('${baseDir.path}/$fiscalFolder');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final file = File('${saveDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);
      setState(() {
        _lastSavedImagePath = file.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to: ${file.path}')),
      );
    } catch (e) {
      print('Error capturing and saving image: $e');
    }
  }

  Future<void> _shareLastImage() async {
    if (_lastSavedImagePath != null) {
      await Share.shareXFiles([XFile(_lastSavedImagePath!)]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No image to share yet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Media Sorter')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _labelController,
              decoration: InputDecoration(labelText: 'Enter a label'),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 20),
            RepaintBoundary(
              key: _previewContainer,
              child: Container(
                padding: EdgeInsets.all(16),
                color: Colors.amber,
                child: Text(
                  _labelController.text,
                  style: TextStyle(fontSize: 24),
                ),
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _captureAndSaveImage,
                  child: Text('Capture & Save'),
                ),
                ElevatedButton(
                  onPressed: _shareLastImage,
                  child: Text('Share Last Image'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
