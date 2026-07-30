import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() => runApp(const EnglishSongTrainerApp());

class EnglishSongTrainerApp extends StatelessWidget {
  const EnglishSongTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'English Song Trainer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457A6)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: const SongTrainerPage(),
    );
  }
}

class SongTrainerPage extends StatefulWidget {
  const SongTrainerPage({super.key});

  @override
  State<SongTrainerPage> createState() => _SongTrainerPageState();
}

class _SongTrainerPageState extends State<SongTrainerPage> {
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _pdfName = 'Noch keine PDF ausgewählt';
  String _language = 'en-GB';
  double _speechRate = 0.20;
  double _pauseSeconds = 4;

  List<String> _lines = [];
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isSpeaking = false;
  bool _autoMode = false;

  @override
  void initState() {
    super.initState();
    _configureTts();
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });

    _tts.setCompletionHandler(() {
      if (mounted && !_autoMode) setState(() => _isSpeaking = false);
    });

    _tts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _autoMode = false;
        });
      }
    });

    _tts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _autoMode = false;
      });
      _message('Fehler beim Vorlesen: $message');
    });
  }

  Future<void> _selectPdf() async {
    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Englischen Liedtext auswählen',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );

      if (result == null) return;

      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Die PDF-Datei konnte nicht geladen werden.');
      }

      final document = PdfDocument(inputBytes: bytes);
      try {
        final text = PdfTextExtractor(document).extractText().trim();

        if (!mounted) return;
        setState(() {
          _pdfName = file.name;
          _textController.text = text;
        });
        _prepareLines();

        _message(
          text.isEmpty
              ? 'Kein auswählbarer Text gefunden. Die PDF ist eventuell eingescannt.'
              : 'PDF wurde erfolgreich eingelesen.',
        );
      } finally {
        document.dispose();
      }
    } catch (error) {
      if (mounted) _message('PDF konnte nicht geöffnet werden: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prepareLines() {
    final lines = _textController.text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    setState(() {
      _lines = lines;
      _currentIndex = 0;
    });

    if (lines.isNotEmpty) {
      _message('${lines.length} Liedzeilen wurden vorbereitet.');
    }
  }

  String get _currentLine =>
      _lines.isEmpty ? '' : _lines[_currentIndex.clamp(0, _lines.length - 1)];

  Future<void> _speakCurrentLine() async {
    if (_lines.isEmpty) {
      _message('Bitte zuerst Text eingeben oder eine PDF auswählen.');
      return;
    }

    await _tts.stop();
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);

    setState(() => _isSpeaking = true);
    await _tts.speak(_currentLine);

    if (mounted && !_autoMode) setState(() => _isSpeaking = false);
  }

  Future<void> _startAutoMode() async {
    if (_lines.isEmpty) {
      _message('Bitte zuerst Liedzeilen vorbereiten.');
      return;
    }

    await _tts.stop();
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);

    setState(() {
      _autoMode = true;
      _isSpeaking = true;
    });

    while (_autoMode && _currentIndex < _lines.length) {
      _scrollToCurrentLine();
      await _tts.speak(_currentLine);

      if (!_autoMode) break;

      await Future.delayed(
        Duration(milliseconds: (_pauseSeconds * 1000).round()),
      );

      if (!_autoMode) break;

      if (_currentIndex < _lines.length - 1) {
        setState(() => _currentIndex++);
      } else {
        break;
      }
    }

    if (mounted) {
      setState(() {
        _autoMode = false;
        _isSpeaking = false;
      });
    }
  }

  Future<void> _speakWholeText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _message('Bitte zuerst Text eingeben oder eine PDF auswählen.');
      return;
    }

    await _stopSpeaking();
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);

    setState(() => _isSpeaking = true);
    await _tts.speak(text);
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _stopSpeaking() async {
    setState(() {
      _autoMode = false;
      _isSpeaking = false;
    });
    await _tts.stop();
  }

  void _previousLine() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _scrollToCurrentLine();
    }
  }

  void _nextLine() {
    if (_currentIndex < _lines.length - 1) {
      setState(() => _currentIndex++);
      _scrollToCurrentLine();
    }
  }

  void _selectLine(int index) {
    setState(() => _currentIndex = index);
    _scrollToCurrentLine();
  }

  void _scrollToCurrentLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || _lines.isEmpty) return;

      final target = (_currentIndex * 64.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearText() async {
    await _stopSpeaking();
    if (!mounted) return;

    setState(() {
      _pdfName = 'Noch keine PDF ausgewählt';
      _textController.clear();
      _lines = [];
      _currentIndex = 0;
    });
  }

  String _rateLabel(double value) {
    if (value <= 0.10) return 'Extrem langsam';
    if (value <= 0.20) return 'Sehr langsam';
    if (value <= 0.35) return 'Langsam';
    if (value <= 0.50) return 'Mittel';
    return 'Normal';
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('English Song Trainer – Teil 2'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Text löschen',
            onPressed: _textController.text.isEmpty ? null : _clearText,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1250),
                  child: wide
                      ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 340, child: _controlPanel()),
                      const SizedBox(width: 16),
                      Expanded(child: _learningArea()),
                    ],
                  )
                      : Column(
                    children: [
                      _controlPanel(),
                      const SizedBox(height: 16),
                      _learningArea(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _learningArea() {
    return Column(
      children: [
        _currentLineCard(),
        const SizedBox(height: 16),
        _lineListCard(),
        const SizedBox(height: 16),
        _textCard(),
      ],
    );
  }

  Widget _controlPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.library_music_rounded, size: 54),
            const SizedBox(height: 10),
            Text(
              'Englische Liedtexte lernen',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Lies Liedtexte als PDF ein und übe sie langsam Zeile für Zeile.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isLoading ? null : _selectPdf,
              icon: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_isLoading ? 'PDF wird gelesen …' : 'PDF auswählen'),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.description_outlined),
              title: Text(
                _pdfName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _prepareLines,
              icon: const Icon(Icons.format_list_numbered),
              label: const Text('Zeilen aktualisieren'),
            ),
            const SizedBox(height: 20),
            Text('Englische Stimme',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                  value: 'en-GB',
                  child: Text('Englisch – Großbritannien'),
                ),
                DropdownMenuItem(
                  value: 'en-US',
                  child: Text('Englisch – USA'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _language = value);
                await _tts.setLanguage(value);
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Geschwindigkeit'),
                const Spacer(),
                Text(_rateLabel(_speechRate)),
              ],
            ),
            Slider(
              value: _speechRate,
              min: 0.05,
              max: 0.60,
              divisions: 11,
              label: _rateLabel(_speechRate),
              onChanged: (value) => setState(() => _speechRate = value),
              onChangeEnd: _tts.setSpeechRate,
            ),
            Row(
              children: [
                const Text('Nachsprechpause'),
                const Spacer(),
                Text('${_pauseSeconds.toStringAsFixed(0)} Sek.'),
              ],
            ),
            Slider(
              value: _pauseSeconds,
              min: 2,
              max: 10,
              divisions: 8,
              label: '${_pauseSeconds.toStringAsFixed(0)} Sekunden',
              onChanged: (value) => setState(() => _pauseSeconds = value),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _isSpeaking ? null : _speakCurrentLine,
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Aktuelle Zeile vorlesen'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _isSpeaking ? null : _startAutoMode,
              icon: const Icon(Icons.school_rounded),
              label: const Text('Automatischer Lernmodus'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isSpeaking ? _stopSpeaking : null,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Vorlesen stoppen'),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _isSpeaking ? null : _speakWholeText,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Gesamten Text vorlesen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentLineCard() {
    final hasLines = _lines.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasLines
                  ? 'Zeile ${_currentIndex + 1} von ${_lines.length}'
                  : 'Aktuelle Liedzeile',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(minHeight: 110),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  hasLines ? _currentLine : 'Noch keine Liedzeile vorbereitet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                    hasLines && _currentIndex > 0 ? _previousLine : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                    label: const Text('Vorherige'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                    hasLines && !_isSpeaking ? _speakCurrentLine : null,
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('Vorlesen'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasLines && _currentIndex < _lines.length - 1
                        ? _nextLine
                        : null,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Nächste'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineListCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Liedzeilen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Text eingeben und anschließend auf '
                        '„Zeilen aktualisieren“ tippen.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SizedBox(
                height: 320,
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: _lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final selected = index == _currentIndex;

                    return ListTile(
                      selected: selected,
                      selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(_lines[index]),
                      trailing:
                      selected ? const Icon(Icons.volume_up_rounded) : null,
                      onTap: () => _selectLine(index),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Liedtext bearbeiten',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Jede Textzeile wird als eigene Lernzeile verwendet.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _textController,
              minLines: 14,
              maxLines: 28,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText:
                'Hier erscheint der Text aus der PDF. Du kannst auch '
                    'direkt einen englischen Liedtext eingeben.',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}
