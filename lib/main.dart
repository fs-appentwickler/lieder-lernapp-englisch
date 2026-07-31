import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const EnglishSongTrainerApp());
}

class EnglishSongTrainerApp extends StatelessWidget {
  const EnglishSongTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'English Song Trainer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2457A6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: const SongTrainerPage(),
    );
  }
}

class SongAsset {
  const SongAsset({
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;
}

class SongTrainerPage extends StatefulWidget {
  const SongTrainerPage({super.key});

  @override
  State<SongTrainerPage> createState() => _SongTrainerPageState();
}

class _SongTrainerPageState extends State<SongTrainerPage> {
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _lineScrollController = ScrollController();

  static const List<SongAsset> _includedSongs = [
    SongAsset(
      title: 'Home from the Sea',
      assetPath: 'assets/songs/home_from_the_sea.pdf',
    ),
    SongAsset(
      title: 'Cornwall My Home',
      assetPath: 'assets/songs/cornwall_my_home.pdf',
    ),
  ];

  String _documentName = 'Noch kein Lied ausgewählt';
  String _language = 'en-GB';

  double _speechRate = 0.20;
  double _pauseSeconds = 4.0;
  int _repeatCount = 1;

  bool _isLoading = false;
  bool _isSpeaking = false;
  bool _isAutoMode = false;
  bool _practiceOnlyUnlearned = false;

  List<String> _songLines = [];
  final Set<int> _learnedLineIndexes = <int>{};
  int _currentLineIndex = 0;
  int _countdown = 0;

  String get _currentLineText {
    if (_songLines.isEmpty) return '';
    return _songLines[_currentLineIndex];
  }

  String get _followingLineText {
    if (_songLines.isEmpty || _currentLineIndex >= _songLines.length - 1) {
      return '';
    }
    return _songLines[_currentLineIndex + 1];
  }

  double get _learningProgress {
    if (_songLines.isEmpty) return 0;
    return _learnedLineIndexes.length / _songLines.length;
  }

  @override
  void initState() {
    super.initState();
    _configureTts();
  }

  Future<void> _configureTts() async {
    await _flutterTts.setLanguage(_language);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setStartHandler(() {
      if (mounted) {
        setState(() => _isSpeaking = true);
      }
    });

    _flutterTts.setCompletionHandler(() {
      if (mounted && !_isAutoMode) {
        setState(() => _isSpeaking = false);
      }
    });

    _flutterTts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isAutoMode = false;
          _countdown = 0;
        });
      }
    });

    _flutterTts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _isAutoMode = false;
        _countdown = 0;
      });
      _showMessage('Fehler beim Vorlesen: $message');
    });
  }

  Future<void> _loadIncludedSong(SongAsset song) async {
    setState(() => _isLoading = true);

    try {
      final ByteData data = await rootBundle.load(song.assetPath);
      final Uint8List bytes = data.buffer.asUint8List();

      await _extractPdfText(
        bytes: bytes,
        documentName: song.title,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Das Lied konnte nicht geladen werden: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectOwnPdf() async {
    setState(() => _isLoading = true);

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Englischen Liedtext auswählen',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );

      if (result == null) return;

      final PlatformFile file = result.files.single;
      final Uint8List? bytes = file.bytes;

      if (bytes == null) {
        throw Exception('Die PDF-Datei konnte nicht geladen werden.');
      }

      await _extractPdfText(
        bytes: bytes,
        documentName: file.name,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('PDF konnte nicht geöffnet werden: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _extractPdfText({
    required Uint8List bytes,
    required String documentName,
  }) async {
    await _stopSpeaking();

    final PdfDocument document = PdfDocument(inputBytes: bytes);

    try {
      final String extractedText =
          PdfTextExtractor(document).extractText().trim();

      if (!mounted) return;

      setState(() {
        _documentName = documentName;
        _textController.text = extractedText;
        _learnedLineIndexes.clear();
      });

      _prepareSongLines();

      if (extractedText.isEmpty) {
        _showMessage(
          'In dieser PDF wurde kein auswählbarer Text gefunden. '
          'Möglicherweise ist sie eingescannt.',
        );
      } else {
        _showMessage('$documentName wurde geladen.');
      }
    } finally {
      document.dispose();
    }
  }

  void _prepareSongLines() {
    final String text = _textController.text.trim();

    final List<String> preparedLines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    setState(() {
      _songLines = preparedLines;
      _currentLineIndex = 0;
      _learnedLineIndexes.clear();
    });

    if (_songLines.isNotEmpty) {
      _showMessage('${_songLines.length} Lernzeilen wurden vorbereitet.');
    }
  }

  Future<void> _speakCurrentLine() async {
    if (_songLines.isEmpty) {
      _showMessage('Bitte zuerst ein Lied auswählen.');
      return;
    }

    await _flutterTts.stop();
    await _flutterTts.setLanguage(_language);
    await _flutterTts.setSpeechRate(_speechRate);

    setState(() => _isSpeaking = true);

    for (int repeat = 0; repeat < _repeatCount; repeat++) {
      await _flutterTts.speak(_currentLineText);
    }

    if (mounted && !_isAutoMode) {
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _startAutoLearning() async {
    if (_songLines.isEmpty) {
      _showMessage('Bitte zuerst ein Lied auswählen.');
      return;
    }

    await _stopSpeaking();
    await _flutterTts.setLanguage(_language);
    await _flutterTts.setSpeechRate(_speechRate);

    setState(() {
      _isAutoMode = true;
      _isSpeaking = true;
    });

    while (_isAutoMode && _currentLineIndex < _songLines.length) {
      if (_practiceOnlyUnlearned &&
          _learnedLineIndexes.contains(_currentLineIndex)) {
        final bool moved = _moveToNextPracticeLine();
        if (!moved) break;
        continue;
      }

      _scrollToCurrentLine();

      for (int repeat = 0; repeat < _repeatCount; repeat++) {
        if (!_isAutoMode) break;
        await _flutterTts.speak(_currentLineText);
      }

      if (!_isAutoMode) break;

      await _runCountdown();

      if (!_isAutoMode) break;

      final bool moved = _moveToNextPracticeLine();
      if (!moved) break;
    }

    if (mounted) {
      setState(() {
        _isAutoMode = false;
        _isSpeaking = false;
        _countdown = 0;
      });
    }
  }

  Future<void> _runCountdown() async {
    final int totalSeconds = _pauseSeconds.round();

    for (int seconds = totalSeconds; seconds > 0; seconds--) {
      if (!_isAutoMode) return;

      setState(() => _countdown = seconds);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() => _countdown = 0);
    }
  }

  bool _moveToNextPracticeLine() {
    if (_songLines.isEmpty) return false;

    int candidate = _currentLineIndex + 1;

    while (candidate < _songLines.length) {
      if (!_practiceOnlyUnlearned ||
          !_learnedLineIndexes.contains(candidate)) {
        setState(() => _currentLineIndex = candidate);
        _scrollToCurrentLine();
        return true;
      }
      candidate++;
    }

    return false;
  }

  Future<void> _stopSpeaking() async {
    if (mounted) {
      setState(() {
        _isAutoMode = false;
        _isSpeaking = false;
        _countdown = 0;
      });
    }

    await _flutterTts.stop();
  }

  void _goToPreviousLine() {
    if (_songLines.isEmpty || _currentLineIndex == 0) return;

    setState(() => _currentLineIndex--);
    _scrollToCurrentLine();
  }

  void _goToNextLine() {
    if (_songLines.isEmpty ||
        _currentLineIndex >= _songLines.length - 1) {
      return;
    }

    setState(() => _currentLineIndex++);
    _scrollToCurrentLine();
  }

  void _selectLine(int index) {
    setState(() => _currentLineIndex = index);
    _scrollToCurrentLine();
  }

  void _toggleCurrentLineLearned() {
    if (_songLines.isEmpty) return;

    setState(() {
      if (_learnedLineIndexes.contains(_currentLineIndex)) {
        _learnedLineIndexes.remove(_currentLineIndex);
      } else {
        _learnedLineIndexes.add(_currentLineIndex);
      }
    });
  }

  void _scrollToCurrentLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_lineScrollController.hasClients || _songLines.isEmpty) return;

      final double target = (_currentLineIndex * 66.0).clamp(
        0.0,
        _lineScrollController.position.maxScrollExtent,
      );

      _lineScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearSong() async {
    await _stopSpeaking();

    if (!mounted) return;

    setState(() {
      _documentName = 'Noch kein Lied ausgewählt';
      _textController.clear();
      _songLines = [];
      _learnedLineIndexes.clear();
      _currentLineIndex = 0;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _rateLabel(double value) {
    if (value <= 0.10) return 'Extrem langsam';
    if (value <= 0.20) return 'Sehr langsam';
    if (value <= 0.35) return 'Langsam';
    if (value <= 0.50) return 'Mittel';
    return 'Normal';
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _textController.dispose();
    _lineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('English Song Trainer – Teil 3'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Lied löschen',
            onPressed: _textController.text.isEmpty ? null : _clearSong,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth >= 920;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 350,
                              child: _buildControlPanel(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  _buildKaraokePanel(),
                                  const SizedBox(height: 16),
                                  _buildProgressPanel(),
                                  const SizedBox(height: 16),
                                  _buildLineListPanel(),
                                  const SizedBox(height: 16),
                                  _buildTextPanel(),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildControlPanel(),
                            const SizedBox(height: 16),
                            _buildKaraokePanel(),
                            const SizedBox(height: 16),
                            _buildProgressPanel(),
                            const SizedBox(height: 16),
                            _buildLineListPanel(),
                            const SizedBox(height: 16),
                            _buildTextPanel(),
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

  Widget _buildControlPanel() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.library_music_rounded, size: 54),
            const SizedBox(height: 10),
            Text(
              'Lied auswählen',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 14),
            ..._includedSongs.map(
              (song) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.tonalIcon(
                  onPressed:
                      _isLoading ? null : () => _loadIncludedSong(song),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(song.title),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _selectOwnPdf,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: const Text('Eigene PDF auswählen'),
            ),
            const SizedBox(height: 12),
            Text(
              _documentName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Divider(height: 30),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(
                labelText: 'Englische Stimme',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'en-GB',
                  child: Text('Großbritannien'),
                ),
                DropdownMenuItem(
                  value: 'en-US',
                  child: Text('USA'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _language = value);
                await _flutterTts.setLanguage(value);
              },
            ),
            const SizedBox(height: 18),
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
              onChanged: (value) {
                setState(() => _speechRate = value);
              },
              onChangeEnd: _flutterTts.setSpeechRate,
            ),
            Row(
              children: [
                const Text('Nachsprechpause'),
                const Spacer(),
                Text('${_pauseSeconds.round()} Sek.'),
              ],
            ),
            Slider(
              value: _pauseSeconds,
              min: 2,
              max: 10,
              divisions: 8,
              label: '${_pauseSeconds.round()} Sekunden',
              onChanged: (value) {
                setState(() => _pauseSeconds = value);
              },
            ),
            Row(
              children: [
                const Text('Wiederholungen'),
                const Spacer(),
                Text('$_repeatCount×'),
              ],
            ),
            Slider(
              value: _repeatCount.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_repeatCount Wiederholungen',
              onChanged: (value) {
                setState(() => _repeatCount = value.round());
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur ungelernte Zeilen'),
              value: _practiceOnlyUnlearned,
              onChanged: (value) {
                setState(() => _practiceOnlyUnlearned = value);
              },
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _songLines.isEmpty || _isSpeaking
                  ? null
                  : _speakCurrentLine,
              icon: const Icon(Icons.volume_up),
              label: const Text('Aktuelle Zeile vorlesen'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _songLines.isEmpty || _isSpeaking
                  ? null
                  : _startAutoLearning,
              icon: const Icon(Icons.school),
              label: const Text('Lernmodus starten'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isSpeaking ? _stopSpeaking : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stoppen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKaraokePanel() {
    final bool hasLines = _songLines.isNotEmpty;
    final bool learned =
        hasLines && _learnedLineIndexes.contains(_currentLineIndex);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasLines
                  ? 'Zeile ${_currentLineIndex + 1} von ${_songLines.length}'
                  : 'Karaoke-Lernmodus',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(minHeight: 130),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  hasLines
                      ? _currentLineText
                      : 'Bitte eines der beiden Lieder auswählen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            if (_countdown > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Jetzt nachsprechen: $_countdown',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
            if (_followingLineText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Nächste Zeile: $_followingLineText',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: hasLines && _currentLineIndex > 0
                      ? _goToPreviousLine
                      : null,
                  icon: const Icon(Icons.skip_previous),
                  label: const Text('Vorherige'),
                ),
                FilledButton.icon(
                  onPressed:
                      hasLines && !_isSpeaking ? _speakCurrentLine : null,
                  icon: const Icon(Icons.replay),
                  label: const Text('Wiederholen'),
                ),
                OutlinedButton.icon(
                  onPressed: hasLines &&
                          _currentLineIndex < _songLines.length - 1
                      ? _goToNextLine
                      : null,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Nächste'),
                ),
                FilledButton.tonalIcon(
                  onPressed: hasLines ? _toggleCurrentLineLearned : null,
                  icon: Icon(
                    learned ? Icons.check_circle : Icons.check_circle_outline,
                  ),
                  label: Text(
                    learned ? 'Als ungelernt markieren' : 'Zeile gelernt',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressPanel() {
    final int percent = (_learningProgress * 100).round();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lernfortschritt: $percent %',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _learningProgress),
            const SizedBox(height: 8),
            Text(
              '${_learnedLineIndexes.length} von ${_songLines.length} '
              'Zeilen gelernt',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineListPanel() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alle Liedzeilen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (_songLines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text('Noch kein Lied ausgewählt.'),
                ),
              )
            else
              SizedBox(
                height: 330,
                child: ListView.separated(
                  controller: _lineScrollController,
                  itemCount: _songLines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final bool selected = index == _currentLineIndex;
                    final bool learned =
                        _learnedLineIndexes.contains(index);

                    return ListTile(
                      selected: selected,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: CircleAvatar(
                        child: Text('${index + 1}'),
                      ),
                      title: Text(_songLines[index]),
                      trailing: learned
                          ? const Icon(Icons.check_circle)
                          : null,
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

  Widget _buildTextPanel() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Erkannter PDF-Text',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _textController,
              minLines: 12,
              maxLines: 24,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Hier erscheint der Text des ausgewählten Liedes.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed:
                  _textController.text.trim().isEmpty ? null : _prepareSongLines,
              icon: const Icon(Icons.refresh),
              label: const Text('Lernzeilen aktualisieren'),
            ),
          ],
        ),
      ),
    );
  }
}
