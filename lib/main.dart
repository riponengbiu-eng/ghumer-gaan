import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.ghumer_gaan.audio',
    androidNotificationChannelName: 'ঘুমের গান',
    androidNotificationOngoing: true,
  );
  runApp(const GhumerGaanApp());
}

class GhumerGaanApp extends StatelessWidget {
  const GhumerGaanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ঘুমের গান',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF101A33),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF3D98B),
            onPrimary: Color(0xFF1B2240),
            surface: Color(0xFF1A2748),
          ),
        ),
        home: const HomePage(),
      );
}

String bn(Object n) {
  const d = '০১২৩৪৫৬৭৮৯';
  return n.toString().replaceAllMapped(RegExp(r'\d'), (m) => d[int.parse(m[0]!)]);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _audioQuery = OnAudioQuery();
  final _player = AudioPlayer();
  List<SongModel> _songs = [];
  bool _loading = true, _denied = false;

  Timer? _ticker;
  DateTime? _endAt;
  int _left = 0;
  String _msg = '';
  static const _fadeSeconds = 10;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    var ok = await _audioQuery.permissionsStatus();
    if (!ok) ok = await _audioQuery.permissionsRequest();
    if (!ok) {
      setState(() { _loading = false; _denied = true; });
      return;
    }
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    _songs = songs.where((s) => (s.duration ?? 0) > 30000 && s.isMusic == true).toList();
    final sources = _songs
        .map((s) => AudioSource.uri(
              Uri.parse(s.uri!),
              tag: MediaItem(id: '${s.id}', title: s.title, artist: s.artist ?? ''),
            ))
        .toList();
    if (sources.isNotEmpty) {
      await _player.setAudioSource(ConcatenatingAudioSource(children: sources));
      await _player.setLoopMode(LoopMode.all);
    }
    setState(() { _loading = false; _denied = false; });
  }

  void _startTimer(int minutes) {
    _stopTimer();
    _endAt = DateTime.now().add(Duration(minutes: minutes));
    _msg = '${bn(minutes)} মিনিট পরে গান বন্ধ হবে';
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final left = _endAt!.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        _player.pause();
        _player.setVolume(1);
        _stopTimer();
        setState(() => _msg = 'গান বন্ধ হয়েছে। শুভ রাত্রি!');
        return;
      }
      if (left <= _fadeSeconds) _player.setVolume(left / _fadeSeconds);
      setState(() => _left = left);
    });
    if (!_player.playing && _songs.isNotEmpty) _player.play();
    setState(() => _left = minutes * 60);
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _endAt = null;
    _left = 0;
    _player.setVolume(1);
  }

  String _fmt(int s) {
    String p(int n) => n.toString().padLeft(2, '0');
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return bn('${h > 0 ? '${p(h)}:' : ''}${p(m)}:${p(sec)}');
  }

  Future<void> _customTimer() async {
    final c = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('কত মিনিট?'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'যেমন 25'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
            child: const Text('সেট করুন'),
          ),
        ],
      ),
    );
    if (v != null && v > 0) _startTimer(v);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ঘুমের গান'), backgroundColor: Colors.transparent),
      body: Column(children: [
        Expanded(child: _body()),
        _panel(cs),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_denied) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('গান দেখাতে অনুমতি দরকার'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _loadSongs, child: const Text('অনুমতি দিন')),
        ]),
      );
    }
    if (_songs.isEmpty) return const Center(child: Text('ফোনে কোনো গান পাওয়া যায়নি'));
    return StreamBuilder<int?>(
      stream: _player.currentIndexStream,
      builder: (context, snap) {
        final cur = snap.data;
        return ListView.builder(
          itemCount: _songs.length,
          itemBuilder: (_, i) => ListTile(
            leading: Icon(i == cur ? Icons.graphic_eq : Icons.music_note),
            title: Text(_songs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_songs[i].artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: i == cur,
            onTap: () async {
              await _player.setVolume(1);
              await _player.seek(Duration.zero, index: i);
              _player.play();
            },
          ),
        );
      },
    );
  }

  Widget _panel(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(iconSize: 32, onPressed: _player.seekToPrevious, icon: const Icon(Icons.skip_previous)),
            StreamBuilder<bool>(
              stream: _player.playingStream,
              builder: (_, s) {
                final playing = s.data ?? false;
                return IconButton.filled(
                  iconSize: 40,
                  onPressed: () {
                    if (playing) {
                      _player.pause();
                    } else {
                      _player.setVolume(1);
                      _player.play();
                    }
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                );
              },
            ),
            IconButton(iconSize: 32, onPressed: _player.seekToNext, icon: const Icon(Icons.skip_next)),
          ]),
          const SizedBox(height: 8),
          if (_endAt != null) ...[
            Text(_fmt(_left),
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: cs.primary)),
            TextButton(
              onPressed: () => setState(() { _stopTimer(); _msg = 'টাইমার বাতিল হয়েছে'; }),
              child: const Text('টাইমার বাতিল'),
            ),
          ],
          if (_msg.isNotEmpty) Text(_msg, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in [15, 20, 30, 45, 60])
              ActionChip(
                label: Text(m == 60 ? '১ ঘণ্টা' : '${bn(m)} মিনিট'),
                onPressed: () => _startTimer(m),
              ),
            ActionChip(label: const Text('নিজে দিন'), onPressed: _customTimer),
          ]),
        ]),
      ),
    );
  }
}
