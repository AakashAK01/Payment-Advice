import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';

import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Payment Advice Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const PaymentAdviceGenerator(),
    );
  }
}

class PaymentAdviceGenerator extends StatefulWidget {
  const PaymentAdviceGenerator({super.key});

  @override
  _PaymentAdviceGeneratorState createState() => _PaymentAdviceGeneratorState();
}

class _PaymentAdviceGeneratorState extends State<PaymentAdviceGenerator> {
  List<Map<String, dynamic>> transactions = [];
  bool isGenerating = false;
  int currentIndex = 0;
  final GlobalKey _globalKey = GlobalKey();
  String statusMessage = '';
  bool isFileLoaded = false;
  int successCount = 0;
  int failedCount = 0;

  @override
  void initState() {
    super.initState();
  }

  Future<void> pickAndLoadCSV() async {
    try {
      final html.FileUploadInputElement uploadInput =
          html.FileUploadInputElement();
      uploadInput.accept = '.csv';
      uploadInput.click();

      await uploadInput.onChange.first;
      final files = uploadInput.files;

      if (files == null || files.isEmpty) {
        setState(() {
          statusMessage = 'No file selected';
        });
        return;
      }

      final file = files[0];
      final reader = html.FileReader();

      reader.onLoadEnd.listen((e) {
        final csvContent = reader.result as String;
        parseCSV(csvContent);
      });

      reader.onError.listen((e) {
        setState(() {
          statusMessage = 'Error reading file';
        });
      });

      reader.readAsText(file);

      setState(() {
        statusMessage = 'Loading CSV...';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error: $e';
      });
      print('Error picking file: $e');
    }
  }

  void parseCSV(String csvContent) {
    try {
      final lines = csvContent
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        setState(() {
          statusMessage = 'CSV file is empty';
        });
        return;
      }

      // Parse header
      final headers = lines[0]
          .split(',')
          .map((h) => h.trim().replaceAll('"', ''))
          .toList();

      // Parse data rows
      final List<Map<String, dynamic>> parsedTransactions = [];

      for (int i = 1; i < lines.length; i++) {
        final values = lines[i]
            .split(',')
            .map((v) => v.trim().replaceAll('"', ''))
            .toList();

        if (values.length != headers.length) continue;

        final Map<String, dynamic> transaction = {};
        for (int j = 0; j < headers.length; j++) {
          // Try to parse as number, otherwise keep as string
          final value = values[j];
          if (int.tryParse(value) != null) {
            transaction[headers[j]] = int.parse(value);
          } else if (double.tryParse(value) != null) {
            transaction[headers[j]] = double.parse(value);
          } else {
            transaction[headers[j]] = value;
          }
        }
        parsedTransactions.add(transaction);
      }

      setState(() {
        transactions = parsedTransactions;
        currentIndex = 0;
        isFileLoaded = true;
        statusMessage = 'Loaded ${transactions.length} transactions from CSV';
      });

      // Clear status message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            statusMessage = '';
          });
        }
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error parsing CSV: $e';
      });
      print('Error parsing CSV: $e');
    }
  }

  Future<void> generateAllScreenshots() async {
    if (!mounted) return;

    setState(() {
      isGenerating = true;
      currentIndex = 0;
      successCount = 0;
      failedCount = 0;
      statusMessage = 'Starting generation...';
    });

    try {
      // Capture and download each screenshot individually
      for (int i = 0; i < transactions.length; i++) {
        if (!mounted) break;

        setState(() {
          currentIndex = i;
          statusMessage =
              'Processing ${i + 1} of ${transactions.length}... (Success: $successCount, Failed: $failedCount)';
        });

        await Future.delayed(const Duration(milliseconds: 1500));

        if (!mounted) break;

        // Try to capture with retry
        Uint8List? image;
        int retries = 0;
        const maxRetries = 3;

        while (retries < maxRetries && image == null) {
          image = await captureWidget();

          if (image == null) {
            retries++;
            print(
              '⚠ Retry $retries/$maxRetries for: ${transactions[i]['Transaction ID']}',
            );
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }

        if (image != null) {
          // Download immediately
          downloadImage(image, i);
          successCount++;
          print(
            '✓ Downloaded [${i + 1}/${transactions.length}]: ${transactions[i]['Transaction ID']} (${(image.length / 1024).toStringAsFixed(1)} KB)',
          );
        } else {
          failedCount++;
          print(
            '✗ Failed after $maxRetries retries: ${transactions[i]['Transaction ID']}',
          );
        }

        // Small delay before next capture
        await Future.delayed(const Duration(milliseconds: 500));

        // Update progress
        if (mounted) {
          setState(() {
            statusMessage =
                'Processing ${i + 1} of ${transactions.length}... (Success: $successCount, Failed: $failedCount)';
          });
        }
      }

      if (mounted) {
        setState(() {
          if (failedCount == 0) {
            statusMessage =
                '✓ Successfully downloaded all $successCount files!';
          } else {
            statusMessage =
                '⚠ Downloaded $successCount files. Failed: $failedCount (Check console)';
          }
        });
      }
    } catch (e) {
      print('Error generating screenshots: $e');
      if (mounted) {
        setState(() {
          statusMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });

        // Clear status after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              statusMessage = '';
            });
          }
        });
      }
    }
  }

  void downloadImage(Uint8List imageData, int index) {
    try {
      final transactionId =
          transactions[index]['Transaction ID']?.toString() ??
          'transaction_$index';
      final fileName = 'payment_advice_$transactionId.png';

      // Create a Blob and download
      final blob = html.Blob([imageData], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..style.display = 'none';

      html.document.body?.append(anchor);
      anchor.click();

      // Clean up after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        html.Url.revokeObjectUrl(url);
        anchor.remove();
      });
    } catch (e) {
      print('✗ Error downloading image $index: $e');
    }
  }

  Future<Uint8List?> captureWidget() async {
    try {
      if (!mounted) {
        print('Widget not mounted');
        return null;
      }

      final RenderObject? renderObject = _globalKey.currentContext
          ?.findRenderObject();

      if (renderObject == null) {
        print('RenderObject is null');
        return null;
      }

      if (renderObject is! RenderRepaintBoundary) {
        print('RenderObject is not a RenderRepaintBoundary');
        return null;
      }

      final RenderRepaintBoundary boundary = renderObject;

      // Capture at 2x pixel ratio
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        print('ByteData is null');
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e) {
      print('Error capturing widget: $e');
      return null;
    }
  }

  String getBankId(String transactionId) {
    final parts = transactionId.split('000');
    return parts.length > 1 ? parts[1] : '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Advice Generator'),
        backgroundColor: Colors.blue,
        actions: [
          if (isFileLoaded && !isGenerating && transactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: generateAllScreenshots,
                icon: const Icon(Icons.download, color: Colors.white),
                label: Text(
                  'Download All (${transactions.length})',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (isGenerating)
            LinearProgressIndicator(
              value: (currentIndex + 1) / transactions.length,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          if (statusMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: isGenerating
                  ? Colors.blue[50]
                  : (failedCount > 0 ? Colors.orange[50] : Colors.green[50]),
              child: Text(
                statusMessage,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isGenerating
                      ? Colors.blue[900]
                      : (failedCount > 0
                            ? Colors.orange[900]
                            : Colors.green[900]),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (!isFileLoaded)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 24),
                    const Text(
                      'Upload CSV File',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'CSV should contain: Transaction ID, Bank Reference ID,\nUTR, Payment Remark, Beneficiary Name,\nBeneficiary UPI ID, Amount',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: pickAndLoadCSV,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Choose CSV File'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Preview ${currentIndex + 1} of ${transactions.length}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (!isGenerating && transactions.length > 1)
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: currentIndex > 0
                                        ? () {
                                            setState(() {
                                              currentIndex--;
                                            });
                                          }
                                        : null,
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                  IconButton(
                                    onPressed:
                                        currentIndex < transactions.length - 1
                                        ? () {
                                            setState(() {
                                              currentIndex++;
                                            });
                                          }
                                        : null,
                                    icon: const Icon(Icons.arrow_forward),
                                  ),
                                ],
                              ),
                            const SizedBox(width: 16),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  transactions = [];
                                  isFileLoaded = false;
                                  currentIndex = 0;
                                  statusMessage = '';
                                  successCount = 0;
                                  failedCount = 0;
                                });
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Load New File'),
                            ),
                          ],
                        ),
                      ),
                      RepaintBoundary(
                        key: _globalKey,
                        child: PaymentAdviceWidget(
                          transaction: transactions[currentIndex],
                          getBankId: getBankId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PaymentAdviceWidget extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final String Function(String) getBankId;

  const PaymentAdviceWidget({
    super.key,
    required this.transaction,
    required this.getBankId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      width: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Advice',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Montserrat',
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              children: [
                _buildRow(
                  'Transaction ID',
                  transaction['Transaction ID']?.toString() ?? '--',
                ),
                const SizedBox(height: 12),
                _buildRow(
                  'Bank ID',
                  getBankId(transaction['Transaction ID']?.toString() ?? ''),
                ),
                const SizedBox(height: 12),
                _buildRow(
                  'Payment Amount',
                  '₹ ${transaction['Amount']?.toString() ?? '--'}',
                  isAmount: true,
                ),
                const SizedBox(height: 12),
                _buildRow('UTR', transaction['UTR']?.toString() ?? '-'),
                const SizedBox(height: 12),
                _buildRow('Mode', 'UPI'),
                const SizedBox(height: 12),
                _buildRow(
                  'Remark',
                  transaction['Payment Remark']?.toString() ?? '',
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.grey),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Text(
                      'Beneficiary Detail',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Montserrat',
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildRow(
                  'Beneficiary Name',
                  transaction['Beneficiary Name']?.toString() ?? '',
                ),
                const SizedBox(height: 12),
                _buildRow(
                  'UPI ID',
                  transaction['Beneficiary UPI ID']?.toString() ?? '',
                ),
                const SizedBox(height: 12),
                _buildRow('Account Number', "--"),
                const SizedBox(height: 12),
                _buildRow('IFSC', "--"),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isAmount = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w400,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Montserrat',
              fontWeight: isAmount ? FontWeight.bold : FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}
