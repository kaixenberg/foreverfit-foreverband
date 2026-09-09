import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Truncation cap for extracted PDF text. The AI assistant's chat session
/// has a small `maxTokens` budget shared across system prompt + full
/// conversation history + this message + the reply — a whole multi-page
/// report would blow past that instantly, so this keeps the excerpt to a
/// size that leaves real room for everything else. Good enough for a demo
/// document (a short report, a prescription); not meant for long PDFs.
const pdfExtractLengthCap = 3000;

/// Extracts (and caps) the text content of a PDF picked via file_picker.
/// Runs entirely on-device (syncfusion_flutter_pdf is a pure-Dart parser,
/// no network calls) — consistent with this feature's offline-first rule.
String extractPdfText(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    final text = PdfTextExtractor(document).extractText();
    final trimmed = text.trim();
    if (trimmed.length <= pdfExtractLengthCap) return trimmed;
    return '${trimmed.substring(0, pdfExtractLengthCap)}\n…[truncated]';
  } finally {
    document.dispose();
  }
}
