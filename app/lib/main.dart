import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble.dart';
import 'imaging.dart';

void main() => runApp(const ZnachokApp());

List<Object> _convertPickedFile(List<Object> args) {
  final raw = args[0] as Uint8List;
  final base = args[1] as String;
  final isGif = args[2] as bool;
  final converted = isGif ? convertGif(raw, base) : convertStill(raw, base);
  return [converted.name, converted.bytes];
}

List<Object> _convertStillFile(List<Object> args) {
  final raw = args[0] as Uint8List;
  final base = args[1] as String;
  final converted = convertStill(raw, base);
  return [converted.name, converted.bytes];
}

class SceneDraft {
  SceneDraft({
    required this.deviceName,
    this.bytes,
    this.preview,
    this.transition = 'fade',
    this.durationMs = 3000,
    this.loops = 1, // для динамики: полных циклов (0 = бесконечно)
  });

  final String deviceName;
  final Uint8List? bytes;
  final Uint8List? preview;
  String transition;
  int durationMs;
  int loops;

  bool get isFx => deviceName.startsWith('FX:');

  /// динамика (FX/анимация) играет целыми циклами, без таймера
  bool get isDynamic => isFx || deviceName.endsWith('.mjpg');
}

class ZnachokApp extends StatelessWidget {
  const ZnachokApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Znachok BMW',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0066B1), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _maxPickedBytes = 50 * 1024 * 1024;
  static const Map<String, String> _fxScenes = {
    'particles': 'Частицы → значок',
    'comet': 'Неоновая комета',
    'holo': 'Голограмма',
    'vdraw': '✏️ Векторное рисование',
    'vkin': '🧲 Кинетическая сборка',
    'vportal': 'Portal forge',
    'vblade': 'Blade assembly',
    'vneon': 'Neon heartbeat',
    'vorbit': 'Orbit lock',
    'vprism': 'Prism sweep',
  };
  // векторные сцены работают с нарисованными лого, а не картинками
  static const Map<String, String> _vectorLogos = {
    '@bmw': 'BMW (вектор)',
    '@toyota': 'Toyota (вектор)',
    '@audi': 'Audi (vector)',
    '@mercedes': 'Mercedes (vector)',
    '@tesla': 'Tesla (vector)',
  };
  static const Set<String> _vectorFx = {
    'vdraw',
    'vkin',
    'vportal',
    'vblade',
    'vneon',
    'vorbit',
    'vprism',
  };

  final _z = Znachok();
  final _picker = ImagePicker();
  String _status = 'Не подключено';
  bool _busy = false;
  double? _progress;
  List<String> _items = [];
  final List<SceneDraft> _scenes = [];

  bool get _connected => _z.connected;

  void _set(String s) {
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final loc = await Permission.locationWhenInUse
        .request(); // нужно только до Android 12
    // Android 12+: достаточно scan+connect; на старых версиях — геолокация
    return (scan.isGranted && connect.isGranted) || loc.isGranted;
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      if (!await _ensurePermissions()) {
        _set('Нет разрешений Bluetooth');
        return;
      }
      await _z.connect(onState: _set);
      await _refresh();
    } catch (e) {
      _set('Ошибка: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await _z.disconnect();
    setState(() {
      _status = 'Не подключено';
      _items = [];
    });
  }

  Future<void> _refresh({String? expectedName, String? deletedName}) async {
    if (!_connected) return;
    try {
      List<String> latest = _items;
      final attempts = expectedName == null && deletedName == null ? 1 : 8;
      for (int i = 0; i < attempts; i++) {
        latest = await _z.list();
        final hasExpected =
            expectedName == null || latest.contains(expectedName);
        final deletedGone =
            deletedName == null || !latest.contains(deletedName);
        if (hasExpected && deletedGone) break;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted) return;
      setState(() {
        _items = latest;
        if (expectedName != null && !_items.contains(expectedName)) {
          _items = [..._items, expectedName];
        }
        if (deletedName != null) {
          _items = _items.where((item) => item != deletedName).toList();
        }
      });
    } catch (e) {
      _set('Список: $e');
    }
  }

  bool _looksLikeGif(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.gif')) return true;
    if (bytes.length < 6) return false;
    final header = String.fromCharCodes(bytes.take(6));
    return header == 'GIF87a' || header == 'GIF89a';
  }

  bool _isSupportedImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.gif') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  String _baseName(String name) {
    var base = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    base = base.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (base.length > 24) base = base.substring(0, 24);
    return base.isEmpty ? 'img' : base;
  }

  Future<SceneDraft> _makeScene(String name, Uint8List raw) async {
    final stamp = DateTime.now().millisecondsSinceEpoch % 1000000;
    final base = '${_baseName(name)}_$stamp';
    final converted = await compute(_convertStillFile, [raw, base]);
    return SceneDraft(
      deviceName: converted[0] as String,
      bytes: converted[1] as Uint8List,
      preview: raw,
    );
  }

  Future<void> _addSceneFromGallery() async {
    final XFile? x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    if (await x.length() > _maxPickedBytes) {
      _set('Файл слишком большой');
      return;
    }
    setState(() => _busy = true);
    try {
      final scene = await _makeScene(x.name, await x.readAsBytes());
      if (!mounted) return;
      setState(() => _scenes.add(scene));
      _set('Сцена добавлена');
    } catch (e) {
      _set('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSceneFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
      withData: false,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (file.size > _maxPickedBytes || file.path == null) {
      _set('Файл слишком большой');
      return;
    }
    setState(() => _busy = true);
    try {
      final scene =
          await _makeScene(file.name, await File(file.path!).readAsBytes());
      if (!mounted) return;
      setState(() => _scenes.add(scene));
      _set('Сцена добавлена');
    } catch (e) {
      _set('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFxScene() async {
    // шаг 1: какой эффект
    final fx = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _fxScenes.entries
              .map(
                (e) => ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(e.value),
                  subtitle: Text('FX:${e.key}'),
                  onTap: () => Navigator.pop(context, e.key),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (fx == null) return;
    if (!mounted) return;

    // шаг 2: с каким значком.
    // Векторные сцены -> нарисованные лого; остальные -> картинки с платы.
    final isVector = _vectorFx.contains(fx);
    final images = _items
        .where((n) => n.endsWith('.jpg') || n.endsWith('.bin'))
        .toList();
    final img = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: isVector
              ? _vectorLogos.entries
                  .map((e) => ListTile(
                        leading: const Icon(Icons.gesture),
                        title: Text(e.value),
                        onTap: () => Navigator.pop(context, e.key),
                      ))
                  .toList()
              : [
                  ListTile(
                    leading: const Icon(Icons.verified),
                    title: const Text('Встроенный логотип BMW'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  ...images.map(
                    (n) => ListTile(
                      leading: const Icon(Icons.image),
                      title: Text(n),
                      onTap: () => Navigator.pop(context, n),
                    ),
                  ),
                ],
        ),
      ),
    );
    if (img == null) return;

    setState(() {
      _scenes.add(SceneDraft(
        deviceName: img.isEmpty ? 'FX:$fx' : 'FX:$fx:$img',
        durationMs: 8000,
        transition: 'fade',
      ));
    });
    _set('FX-сцена добавлена');
  }

  /// Сцена из файла, уже лежащего на плате (картинка или анимация) —
  /// заливать заново не нужно, в сценарий идёт только имя.
  Future<void> _addSceneFromDevice() async {
    final files = _items
        .where((n) =>
            (n.endsWith('.jpg') || n.endsWith('.mjpg')) && n != 'show.zpl')
        .toList();
    if (files.isEmpty) {
      _set('На плате нет картинок/анимаций');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: files
              .map((n) => ListTile(
                    leading: Icon(
                        n.endsWith('.mjpg') ? Icons.movie : Icons.image),
                    title: Text(n),
                    onTap: () => Navigator.pop(context, n),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _scenes.add(SceneDraft(deviceName: picked)));
    _set('Сцена с платы добавлена');
  }

  Uint8List _buildShowScript() {
    final b = StringBuffer('ZPL1\n');
    for (final s in _scenes) {
      // динамика: число циклов (<10, 0=бесконечно); статика: миллисекунды
      final second = s.isDynamic ? s.loops : s.durationMs;
      b.writeln('${s.deviceName}|$second|${s.transition}');
    }
    return Uint8List.fromList(b.toString().codeUnits);
  }

  Future<void> _uploadShow() async {
    if (!_connected || _scenes.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final total = _scenes.length + 1;
      for (int i = 0; i < _scenes.length; i++) {
        final scene = _scenes[i];
        if (scene.bytes == null) {
          // FX-сцены и файлы, уже лежащие на плате, заливать не нужно
          if (mounted) setState(() => _progress = (i + 1) / total);
          continue;
        }
        _set('Отправка сцены ${i + 1}/${_scenes.length}');
        await _z.upload(scene.deviceName, scene.bytes!, onProgress: (p) {
          if (mounted) setState(() => _progress = (i + p) / total);
        });
      }
      _set('Отправка сценария');
      await _z.upload('show.zpl', _buildShowScript(), onProgress: (p) {
        if (mounted) setState(() => _progress = (_scenes.length + p) / total);
      });
      _set('Шоу загружено ✓');
      await _refresh(expectedName: 'show.zpl');
    } catch (e) {
      _set('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _uploadPickedFile(String name, Uint8List raw) async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final base = _baseName(name);
      final isGif = _looksLikeGif(name, raw);

      _set('Обработка…');
      final converted = await compute(_convertPickedFile, [raw, base, isGif]);
      final conv = Converted(
        converted[0] as String,
        converted[1] as Uint8List,
      );

      _set('Отправка по Bluetooth…');
      await _z.upload(conv.name, conv.bytes, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      _set('Готово ✓  (${conv.name})');
      await _refresh(expectedName: conv.name);
    } catch (e) {
      _set('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    if (await x.length() > _maxPickedBytes) {
      _set('Файл слишком большой');
      return;
    }
    await _uploadPickedFile(x.name, await x.readAsBytes());
  }

  Future<void> _pickFromCamera() async {
    final XFile? x = await _picker.pickImage(source: ImageSource.camera);
    if (x == null) return;
    await _uploadPickedFile(x.name, await x.readAsBytes());
  }

  Future<void> _pickGifOrImageFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true, // важно: гарантированно вернуть байты (content-URI без пути)
    );
    final file = result?.files.single;
    if (file == null) return;
    if (!_isSupportedImageFile(file.name)) {
      _set('Выбери GIF или картинку');
      return;
    }
    if (file.size > _maxPickedBytes) {
      _set('Файл слишком большой');
      return;
    }
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      _set('Не удалось прочитать файл');
      return;
    }
    await _uploadPickedFile(file.name, bytes);
  }

  Widget _buildConstructor() {
    const transitions = ['fade', 'circle', 'push', 'none'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Конструктор шоу',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Добавить из галереи',
                  onPressed: _busy ? null : _addSceneFromGallery,
                  icon: const Icon(Icons.add_photo_alternate),
                ),
                IconButton(
                  tooltip: 'Добавить файл',
                  onPressed: _busy ? null : _addSceneFromFile,
                  icon: const Icon(Icons.create_new_folder),
                ),
                IconButton(
                  tooltip: 'Добавить FX',
                  onPressed: _busy ? null : _addFxScene,
                  icon: const Icon(Icons.auto_awesome),
                ),
                IconButton(
                  tooltip: 'С платы (картинки и анимации)',
                  onPressed: _busy || !_connected ? null : _addSceneFromDevice,
                  icon: const Icon(Icons.sd_storage),
                ),
                IconButton(
                  tooltip: 'Загрузить шоу',
                  onPressed: _busy || _scenes.isEmpty ? null : _uploadShow,
                  icon: const Icon(Icons.upload),
                ),
              ],
            ),
            if (_scenes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Добавь картинки и загрузи шоу',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              SizedBox(
                height: 190,
                child: ListView.separated(
                  itemCount: _scenes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _scenes[i];
                    return Row(
                      children: [
                        ClipOval(
                          child: s.preview == null
                              ? Container(
                                  width: 56,
                                  height: 56,
                                  color: const Color(0xFF101820),
                                  child: const Icon(Icons.auto_awesome,
                                      color: Color(0xFF58B8FF)),
                                )
                              : Image.memory(s.preview!,
                                  width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.deviceName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              Row(
                                children: [
                                  DropdownButton<String>(
                                    value: s.transition,
                                    items: transitions
                                        .map((t) => DropdownMenuItem(
                                            value: t, child: Text(t)))
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(
                                            () => s.transition = v ?? 'fade'),
                                  ),
                                  const SizedBox(width: 12),
                                  if (s.isDynamic)
                                    // динамика: целые циклы, без таймера
                                    DropdownButton<int>(
                                      value: s.loops,
                                      items: const [
                                        DropdownMenuItem(
                                            value: 1, child: Text('×1')),
                                        DropdownMenuItem(
                                            value: 2, child: Text('×2')),
                                        DropdownMenuItem(
                                            value: 3, child: Text('×3')),
                                        DropdownMenuItem(
                                            value: 0, child: Text('∞')),
                                      ],
                                      onChanged: _busy
                                          ? null
                                          : (v) =>
                                              setState(() => s.loops = v ?? 1),
                                    )
                                  else
                                    DropdownButton<int>(
                                      value: s.durationMs,
                                      items: const [1500, 3000, 5000, 8000]
                                          .map((d) => DropdownMenuItem(
                                              value: d,
                                              child: Text('${d ~/ 1000}s')))
                                          .toList(),
                                      onChanged: _busy
                                          ? null
                                          : (v) => setState(
                                              () => s.durationMs = v ?? 3000),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _busy || i == 0
                              ? null
                              : () => setState(() {
                                    final item = _scenes.removeAt(i);
                                    _scenes.insert(i - 1, item);
                                  }),
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          onPressed: _busy || i == _scenes.length - 1
                              ? null
                              : () => setState(() {
                                    final item = _scenes.removeAt(i);
                                    _scenes.insert(i + 1, item);
                                  }),
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        IconButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _scenes.removeAt(i)),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066B1),
        title: const Text('🔵 Znachok BMW'),
        actions: [
          if (_connected)
            IconButton(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_connected)
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Подключиться'),
              )
            else
              Row(children: [
                Expanded(
                  child: Wrap(spacing: 8, children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Галерея'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickGifOrImageFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Файл/GIF'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickFromCamera,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Камера'),
                    ),
                  ]),
                ),
                IconButton(
                    onPressed: _busy ? null : _disconnect,
                    icon: const Icon(Icons.bluetooth_disabled)),
              ]),
            if (_connected) ...[
              const SizedBox(height: 12),
              _buildConstructor(),
            ],
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(color: Color(0xFF7FD17F))),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Text(_connected ? 'Пусто — загрузи картинку' : '',
                          style: const TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        final anim = n.endsWith('.gif') ||
                            n.endsWith('.anm') ||
                            n.endsWith('.mjpg');
                        return Card(
                          child: ListTile(
                            leading: Icon(anim ? Icons.movie : Icons.image),
                            title: Text(n),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await _z.show(n);
                                          _set('Показываю: $n');
                                        },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Color(0xFFD06060)),
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await _z.remove(n);
                                          if (!context.mounted) return;
                                          setState(() {
                                            _items = _items
                                                .where((item) => item != n)
                                                .toList();
                                          });
                                          await _refresh(deletedName: n);
                                        },
                                ),
                              ],
                            ),
                          ),
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
