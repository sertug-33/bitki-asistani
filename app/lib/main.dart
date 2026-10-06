import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// USB ile test ederken: Mac'te "adb reverse tcp:8000 tcp:8000" çalıştırılınca
// telefon, Mac'teki sunucuya localhost:8000 üzerinden ulaşır.
const String kDefaultServerUrl = 'http://localhost:8000';
const int kMaxPhotos = 4;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BitkiApp());
}

// ---------------------------------------------------------------- ayarlar

class AppSettings {
  static String serverUrl = kDefaultServerUrl;
  static String token = '';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString('serverUrl') ?? kDefaultServerUrl;
    token = p.getString('token') ?? '';
  }

  static Future<void> save(String url, String tok) async {
    serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    token = tok.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('serverUrl', serverUrl);
    await p.setString('token', token);
  }

  static Map<String, String> get headers =>
      token.isEmpty ? {} : {'X-App-Token': token};
}

// ---------------------------------------------------------------- veri

class Crop {
  final String name;
  final String? variant;
  final String label;
  Crop(this.name, this.variant, this.label);

  factory Crop.fromJson(Map<String, dynamic> j) =>
      Crop(j['name'] as String, j['variant'] as String?, j['label'] as String);
}

Future<Map<String, List<Crop>>> loadCrops() async {
  final raw = await rootBundle.loadString('assets/crops.json');
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final districts = data['districts'] as Map<String, dynamic>;
  return districts.map((k, v) => MapEntry(
      k,
      (v as List)
          .map((e) => Crop.fromJson(e as Map<String, dynamic>))
          .toList()));
}

// ---------------------------------------------------------------- uygulama

class BitkiApp extends StatelessWidget {
  const BitkiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bitki Asistanı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------- ana ekran

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  final _noteCtrl = TextEditingController();

  Map<String, List<Crop>> _crops = {};
  String? _district;
  Crop? _crop;
  final List<XFile> _photos = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await AppSettings.load();
    final crops = await loadCrops();
    final prefs = await SharedPreferences.getInstance();
    final savedDistrict = prefs.getString('district');
    final savedCrop = prefs.getString('crop');
    String? district;
    Crop? crop;
    if (savedDistrict != null && crops.containsKey(savedDistrict)) {
      district = savedDistrict;
      for (final c in crops[district]!) {
        if (c.label == savedCrop) crop = c;
      }
    }
    if (!mounted) return;
    setState(() {
      _crops = crops;
      _district = district;
      _crop = crop;
      _loading = false;
    });
  }

  Future<void> _remember() async {
    final prefs = await SharedPreferences.getInstance();
    if (_district != null) await prefs.setString('district', _district!);
    if (_crop != null) await prefs.setString('crop', _crop!.label);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= kMaxPhotos) {
      _snack('En fazla $kMaxPhotos fotoğraf eklenebilir');
      return;
    }
    final x = await _picker.pickImage(
        source: ImageSource.camera, maxWidth: 2560, imageQuality: 92);
    if (x != null) setState(() => _photos.add(x));
  }

  Future<void> _pickGallery() async {
    final xs = await _picker.pickMultiImage(maxWidth: 2560, imageQuality: 92);
    if (xs.isEmpty) return;
    setState(() {
      for (final x in xs) {
        if (_photos.length < kMaxPhotos) _photos.add(x);
      }
    });
    if (_photos.length >= kMaxPhotos && xs.length > 1) {
      _snack('En fazla $kMaxPhotos fotoğraf kullanılır');
    }
  }

  Future<void> _analyze() async {
    if (_district == null || _crop == null) {
      _snack('Önce ilçe ve ürün seçin');
      return;
    }
    if (_photos.isEmpty) {
      _snack('En az bir fotoğraf ekleyin');
      return;
    }
    setState(() => _busy = true);
    try {
      final req = http.MultipartRequest(
          'POST', Uri.parse('${AppSettings.serverUrl}/analyze'));
      req.headers.addAll(AppSettings.headers);
      req.fields['district'] = _district!;
      req.fields['crop'] = _crop!.name;
      req.fields['variant'] = _crop!.variant ?? '';
      req.fields['note'] = _noteCtrl.text.trim();
      for (final p in _photos) {
        req.files.add(await http.MultipartFile.fromPath('photos', p.path));
      }
      final streamed = await req.send().timeout(const Duration(seconds: 180));
      final res = await http.Response.fromStream(streamed);
      final body = utf8.decode(res.bodyBytes);
      if (res.statusCode != 200) {
        String detail = body;
        try {
          detail = (jsonDecode(body)['detail'] ?? body).toString();
        } catch (_) {}
        throw Exception('Sunucu hatası (${res.statusCode}): $detail');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultScreen(
          recordId: data['id'] as String,
          demo: data['demo'] == true,
          result: data['result'] as Map<String, dynamic>,
          cropLabel: _crop!.label,
          district: _district!,
        ),
      ));
      if (!mounted) return;
      setState(() {
        _photos.clear();
        _noteCtrl.clear();
      });
    } on SocketException {
      _snack('Sunucuya ulaşılamadı. Sunucu açık mı, adres doğru mu? (Ayarlar)');
    } on http.ClientException {
      _snack('Sunucuya ulaşılamadı. Sunucu açık mı, adres doğru mu? (Ayarlar)');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    final urlCtrl = TextEditingController(text: AppSettings.serverUrl);
    final tokCtrl = TextEditingController(text: AppSettings.token);
    String status = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Sunucu ayarları'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'Sunucu adresi',
                    hintText: 'http://localhost:8000'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tokCtrl,
                decoration: const InputDecoration(
                    labelText: 'Uygulama anahtarı (varsa)'),
              ),
              const SizedBox(height: 12),
              if (status.isNotEmpty) Text(status),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await AppSettings.save(urlCtrl.text, tokCtrl.text);
                setD(() => status = 'Deneniyor...');
                try {
                  final r = await http
                      .get(Uri.parse('${AppSettings.serverUrl}/health'))
                      .timeout(const Duration(seconds: 6));
                  final j = jsonDecode(r.body) as Map<String, dynamic>;
                  setD(() => status = j['demo'] == true
                      ? 'Bağlandı (DEMO modu: API anahtarı yok)'
                      : 'Bağlandı (gerçek analiz açık)');
                } catch (_) {
                  setD(() => status = 'Bağlanılamadı');
                }
              },
              child: const Text('Bağlantıyı dene'),
            ),
            FilledButton(
              onPressed: () async {
                await AppSettings.save(urlCtrl.text, tokCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    urlCtrl.dispose();
    tokCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bitki Asistanı'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('1. Nerede ve hangi ürün?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownMenu<String>(
                  key: const ValueKey('district'),
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('İlçe'),
                  initialSelection: _district,
                  dropdownMenuEntries: _crops.keys
                      .map((d) => DropdownMenuEntry(value: d, label: d))
                      .toList(),
                  onSelected: (d) {
                    setState(() {
                      _district = d;
                      _crop = null;
                    });
                    _remember();
                  },
                ),
                const SizedBox(height: 12),
                DropdownMenu<Crop>(
                  key: ValueKey('crop-$_district'),
                  expandedInsets: EdgeInsets.zero,
                  enabled: _district != null,
                  label: const Text('Ürün'),
                  initialSelection: _crop,
                  dropdownMenuEntries: (_district == null
                          ? <Crop>[]
                          : _crops[_district]!)
                      .map((c) => DropdownMenuEntry(value: c, label: c.label))
                      .toList(),
                  onSelected: (c) {
                    setState(() => _crop = c);
                    _remember();
                  },
                ),
                const SizedBox(height: 24),
                Text('2. Fotoğraf (en fazla $kMaxPhotos)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Yakından, iyi ışıkta çekin. Mümkünse yaprağın üstünü, altını '
                  've hasta ile sağlıklı bölgeyi birlikte gösterin.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (_photos.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _photos.length; i++)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(_photos[i].path),
                                  width: 100, height: 100, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _photos.removeAt(i)),
                                child: Container(
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(Icons.close,
                                      size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _takePhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Fotoğraf çek'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galeriden'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('3. Not (isteğe bağlı)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Örn: 3 gündür yayılıyor, sera, damla sulama, geçen hafta ilaçlandı',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _analyze,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: Text(_busy ? 'Analiz ediliyor...' : 'Analiz et'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- sonuç ekranı

const Map<String, String> kTurAd = {
  'hastalik': 'Hastalık',
  'zararli': 'Zararlı',
  'besin_eksikligi': 'Besin eksikliği',
  'fizyolojik': 'Fizyolojik / çevresel',
  'saglikli': 'Sağlıklı görünüyor',
  'belirsiz': 'Belirsiz',
};

class ResultScreen extends StatefulWidget {
  final String recordId;
  final bool demo;
  final Map<String, dynamic> result;
  final String cropLabel;
  final String district;

  const ResultScreen({
    super.key,
    required this.recordId,
    required this.demo,
    required this.result,
    required this.cropLabel,
    required this.district,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  String? _verdict; // dogru | yanlis | belirsiz
  final _correctCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _correctCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveFeedback() async {
    if (_verdict == null) return;
    if (_verdict == 'yanlis' && _correctCtrl.text.trim().isEmpty) {
      _snack('Doğru teşhisi yazın');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await http
          .post(
            Uri.parse('${AppSettings.serverUrl}/feedback/${widget.recordId}'),
            headers: {
              'Content-Type': 'application/json',
              ...AppSettings.headers,
            },
            body: jsonEncode({
              'verdict': _verdict,
              'correct_diagnosis': _correctCtrl.text.trim(),
              'note': _noteCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('Kaydedilemedi (${res.statusCode})');
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      _snack('Kaydedilemedi: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final uyum = r['urun_uyumu'] as Map<String, dynamic>?;
    final foto = r['foto_kalitesi'] as Map<String, dynamic>?;
    final belirtiler = (r['gozlenen_belirtiler'] as List? ?? []).cast<dynamic>();
    final teshisler =
        (r['teshisler'] as List? ?? []).whereType<Map<String, dynamic>>().toList();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.cropLabel} • ${widget.district}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.demo)
            _banner(cs.tertiaryContainer, cs.onTertiaryContainer, Icons.science,
                'DEMO modu: bu sonuç sahtedir. Sunucuya API anahtarı eklenince gerçek analiz gelir.'),
          if (r['hata'] != null)
            _banner(cs.errorContainer, cs.onErrorContainer, Icons.error_outline,
                '${r['hata']}\n${r['ham_cevap'] ?? ''}'),
          if (r['acil'] == true)
            _banner(cs.errorContainer, cs.onErrorContainer, Icons.warning_amber,
                'Acil müdahale gerektirebilir.'),
          if (uyum != null && uyum['uyumlu'] == false)
            _banner(cs.errorContainer, cs.onErrorContainer, Icons.help_outline,
                'Fotoğraftaki bitki seçilen ürünle uyuşmuyor olabilir: ${uyum['not'] ?? ''}'),
          if (foto != null && foto['yeterli'] == false)
            _banner(
                cs.secondaryContainer,
                cs.onSecondaryContainer,
                Icons.photo_size_select_large,
                'Fotoğraf yetersiz olabilir: ${foto['not'] ?? ''}'
                '${(foto['ek_foto_onerisi'] ?? '').toString().isEmpty ? '' : '\nÖneri: ${foto['ek_foto_onerisi']}'}'),
          if (belirtiler.isNotEmpty) ...[
            Text('Gözlenen belirtiler', style: tt.titleMedium),
            const SizedBox(height: 4),
            for (final b in belirtiler)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $b'),
              ),
            const SizedBox(height: 16),
          ],
          Text('Olası teşhisler', style: tt.titleMedium),
          const SizedBox(height: 8),
          for (final t in teshisler) _diagnosisCard(t),
          if (teshisler.isEmpty) const Text('Teşhis üretilemedi.'),
          const SizedBox(height: 8),
          Text(
            'Bu sonuç yapay zekâ tahminidir; kesin teşhis yerine geçmez. '
            'Son karar uzmana aittir.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Divider(height: 32),
          Text('Uzman değerlendirmesi', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text('Bu kayıt ileride modeli geliştirmek için kullanılacak.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_saved) ...[
            _banner(cs.primaryContainer, cs.onPrimaryContainer, Icons.check_circle,
                'Kaydedildi, teşekkürler.'),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Yeni analiz'),
            ),
          ] else ...[
            SegmentedButton<String>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'dogru', label: Text('Doğru')),
                ButtonSegment(value: 'yanlis', label: Text('Yanlış')),
                ButtonSegment(value: 'belirsiz', label: Text('Emin değilim')),
              ],
              selected: _verdict == null ? <String>{} : {_verdict!},
              onSelectionChanged: (s) =>
                  setState(() => _verdict = s.isEmpty ? null : s.first),
            ),
            if (_verdict == 'yanlis') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _correctCtrl,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Doğru teşhis'),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: 'Not (isteğe bağlı)'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_verdict == null || _saving) ? null : _saveFeedback,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Değerlendirmeden geç'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _banner(Color bg, Color fg, IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ],
      ),
    );
  }

  Widget _diagnosisCard(Map<String, dynamic> t) {
    final guven = ((t['guven'] as num?)?.toDouble() ?? 0).clamp(0, 100).toDouble();
    final tur = kTurAd[t['tur']] ?? (t['tur']?.toString() ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t['ad'] ?? ''}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(tur, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                      value: guven / 100, minHeight: 8,
                      borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 10),
                Text('%${guven.round()}'),
              ],
            ),
            if ((t['gerekce'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Neden: ${t['gerekce']}'),
            ],
            if ((t['oneri'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Öneri: ${t['oneri']}'),
            ],
          ],
        ),
      ),
    );
  }
}
