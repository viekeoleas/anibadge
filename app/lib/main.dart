import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'clip_preview.dart';
import 'generated_clip_editor.dart';
import 'generated_clip_renderer.dart';
import 'mp4_normalizer.dart';
import 'project_model.dart';
import 'project_store.dart';
import 'show_compiler.dart';
import 'show_device_http.dart';
import 'show_publisher.dart';

void main() => runApp(const ZnachokApp());

abstract final class _ZColors {
  static const background = Color(0xFF090D12);
  static const surface = Color(0xFF111720);
  static const surfaceRaised = Color(0xFF171F2A);
  static const surfaceSelected = Color(0xFF172A3E);
  static const border = Color(0xFF293545);
  static const borderStrong = Color(0xFF3A4A5E);
  static const primary = Color(0xFF56A9FF);
  static const onPrimary = Color(0xFF001B30);
  static const text = Color(0xFFF2F6FA);
  static const textMuted = Color(0xFFAAB7C7);
  static const danger = Color(0xFFFF6B75);
}

ThemeData _buildZnachokTheme() {
  const scheme = ColorScheme.dark(
    primary: _ZColors.primary,
    onPrimary: _ZColors.onPrimary,
    secondary: _ZColors.primary,
    onSecondary: _ZColors.onPrimary,
    error: _ZColors.danger,
    onError: Color(0xFF3B050B),
    surface: _ZColors.surface,
    onSurface: _ZColors.text,
    outline: _ZColors.borderStrong,
    outlineVariant: _ZColors.border,
  );
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: _ZColors.background,
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: _ZColors.text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: _ZColors.text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: _ZColors.text,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: _ZColors.textMuted,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: _ZColors.textMuted,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _ZColors.background,
      foregroundColor: _ZColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 72,
      titleSpacing: 20,
    ),
    cardTheme: const CardThemeData(
      color: _ZColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: _ZColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: _ZColors.border,
      space: 1,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _ZColors.primary,
        foregroundColor: _ZColors.onPrimary,
        disabledBackgroundColor: _ZColors.surfaceRaised,
        disabledForegroundColor: _ZColors.textMuted,
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _ZColors.text,
        side: const BorderSide(color: _ZColors.borderStrong),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _ZColors.primary,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: _ZColors.textMuted,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _ZColors.textMuted,
      textColor: _ZColors.text,
      selectedColor: _ZColors.text,
      selectedTileColor: _ZColors.surfaceSelected,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: _ZColors.surfaceRaised,
      labelStyle: TextStyle(color: _ZColors.textMuted),
      helperStyle: TextStyle(color: _ZColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _ZColors.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _ZColors.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _ZColors.primary, width: 2),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: _ZColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _ZColors.primary,
      linearTrackColor: _ZColors.surfaceRaised,
      circularTrackColor: _ZColors.surfaceRaised,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: _ZColors.primary,
      inactiveTrackColor: _ZColors.borderStrong,
      thumbColor: _ZColors.primary,
      overlayColor: _ZColors.primary.withValues(alpha: 0.14),
    ),
  );
}

class ZnachokApp extends StatelessWidget {
  const ZnachokApp({
    super.key,
    this.device,
    this.store,
    this.initialProject,
    this.mp4Normalizer,
  });

  final ShowDevice? device;
  final ProjectStore? store;
  final ShowProject? initialProject;
  final Mp4Normalizer? mp4Normalizer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Znachok',
      theme: _buildZnachokTheme(),
      home: HomePage(
        device: device,
        store: store,
        initialProject: initialProject,
        mp4Normalizer: mp4Normalizer,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.device,
    this.store,
    this.initialProject,
    this.mp4Normalizer,
  });

  final ShowDevice? device;
  final ProjectStore? store;
  final ShowProject? initialProject;
  final Mp4Normalizer? mp4Normalizer;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ShowDevice _device;
  late final ShowPublisher _publisher;
  late final Mp4Normalizer _mp4Normalizer;
  ProjectStore? _store;
  ShowProject _project = const ShowProject();
  String? _selectedId;
  CompiledShow? _compiled;
  bool _loading = true;
  bool _compiling = false;
  double? _compileProgress;
  bool _publishing = false;
  bool _clearing = false;
  Timer? _saveDebounce;
  String _status = 'Загрузка проекта…';
  PublishState _publishState = const PublishState(
    PublishStage.idle,
    'Добавьте медиа и проверьте живое превью',
  );

  @override
  void initState() {
    super.initState();
    _device = widget.device ?? HttpShowDevice();
    _publisher = ShowPublisher(_device);
    _mp4Normalizer = widget.mp4Normalizer ?? AndroidMp4Normalizer();
    final initialProject = widget.initialProject;
    if (initialProject == null) {
      unawaited(_initialize());
    } else {
      _store = widget.store;
      _project = initialProject;
      _selectedId = initialProject.clips.firstOrNull?.id;
      _loading = false;
      _status = initialProject.clips.isEmpty
          ? 'Добавьте PNG, JPEG, GIF или MP4'
          : 'Локальный проект восстановлен';
    }
  }

  Future<void> _initialize() async {
    try {
      final store = widget.store ?? await ProjectStore.open();
      final project = await store.load();
      if (!mounted) return;
      setState(() {
        _store = store;
        _project = project;
        _selectedId = project.clips.isEmpty ? null : project.clips.first.id;
        _loading = false;
        _status = project.clips.isEmpty
            ? 'Добавьте PNG, JPEG, GIF или MP4'
            : 'Локальный проект восстановлен';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Не удалось открыть локальный проект: $error';
      });
    }
  }

  ShowClip? get _selectedClip {
    for (final clip in _project.clips) {
      if (clip.id == _selectedId) return clip;
    }
    return null;
  }

  Future<void> _save() async {
    final store = _store;
    if (store != null) await store.save(_project);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_save());
    });
  }

  void _invalidatePreview() {
    _compiled = null;
    _publishState = const PublishState(
      PublishStage.idle,
      'Изменения видны в превью — перед загрузкой подготовим только нужные кадры',
    );
  }

  void _replaceClip(ShowClip changed) {
    final clips = [
      for (final clip in _project.clips)
        if (clip.id == changed.id) changed else clip,
    ];
    setState(() {
      _project = _project.copyWith(clips: clips);
      _invalidatePreview();
    });
    _scheduleSave();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _importMedia() async {
    final store = _store;
    if (store == null) {
      setState(() => _status = 'Локальное хранилище приложения недоступно');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'mp4'],
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      setState(() => _status = 'Импорт медиа…');
      final imported = <ShowClip>[];
      for (final file in result.files) {
        final lowerName = file.name.toLowerCase();
        final kind = lowerName.endsWith('.gif')
            ? ClipKind.gif
            : lowerName.endsWith('.mp4')
                ? ClipKind.mp4
                : ClipKind.image;
        ShowClip clip;
        if (file.path != null) {
          clip = await store.importMediaFile(
            originalName: file.name,
            sourcePath: file.path!,
            kind: kind,
          );
        } else {
          final bytes = file.bytes;
          if (bytes == null) {
            throw Exception('Не удалось прочитать ${file.name}');
          }
          clip = await store.importMedia(
            originalName: file.name,
            bytes: bytes,
            kind: kind,
          );
        }
        if (kind == ClipKind.gif) {
          clip = clip.copyWith(durationMs: 0);
        } else if (kind == ClipKind.mp4) {
          if (mounted) {
            setState(() => _status = 'Декодируем видео ${file.name}…');
          }
          try {
            final manifest = await _mp4Normalizer.normalize(
              sourcePath: clip.assetPath,
              outputDirectory: store.normalizedDirectory(clip.id).path,
            );
            clip = clip.copyWith(durationMs: 0, normalizedPath: manifest);
          } catch (_) {
            await store.discardImport(clip);
            rethrow;
          }
        }
        imported.add(clip);
      }
      if (!mounted || imported.isEmpty) return;
      setState(() {
        _project = _project.copyWith(clips: [..._project.clips, ...imported]);
        _selectedId = imported.last.id;
        _invalidatePreview();
        _status = 'Добавлено файлов: ${imported.length}';
      });
      await _save();
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка импорта: $error');
    }
  }

  Future<void> _addTextCard() async {
    final store = _store;
    if (store == null) return;
    final config = await showTextCardEditor(
      context,
      const GeneratedClipConfig(),
    );
    if (config == null) return;
    try {
      final clip = await store.createGeneratedClip(
        kind: ClipKind.textCard,
        name: 'Text-card',
        config: config,
      );
      await renderGeneratedClip(clip);
      if (!mounted) return;
      setState(() {
        _project = _project.copyWith(clips: [..._project.clips, clip]);
        _selectedId = clip.id;
        _invalidatePreview();
        _status = 'Text-card добавлена';
      });
      await _save();
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка text-card: $error');
    }
  }

  Future<void> _addLogoCard() async {
    final store = _store;
    if (store == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final source = picked?.files.single;
    if (source == null) return;
    try {
      final sourcePath = await store.importGeneratorSource(
        originalName: source.name,
        sourcePath: source.path,
        bytes: source.bytes,
      );
      if (!mounted) return;
      final config = await showLogoCardEditor(
        context,
        GeneratedClipConfig(logoSourcePath: sourcePath),
      );
      if (config == null) return;
      final clip = await store.createGeneratedClip(
        kind: ClipKind.logoCard,
        name: 'Logo-card · ${source.name}',
        config: config,
      );
      await renderGeneratedClip(clip);
      if (!mounted) return;
      setState(() {
        _project = _project.copyWith(clips: [..._project.clips, clip]);
        _selectedId = clip.id;
        _invalidatePreview();
        _status = 'Logo-card добавлена';
      });
      await _save();
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка logo-card: $error');
    }
  }

  Future<void> _addGeneratedMotion(ClipKind kind) async {
    final store = _store;
    if (store == null || !kind.isGeneratedMotion) return;
    final initial = kind == ClipKind.ambient
        ? const GeneratedClipConfig(
            backgroundColor: 0xFF0066B1,
            secondaryColor: 0xFF6C4DFF,
            glowColor: 0xFF00A8E8,
          )
        : const GeneratedClipConfig(text: 'ZNACHOK', fontSize: 112);
    final config = kind == ClipKind.ambient
        ? await showAmbientEditor(context, initial)
        : await showTickerEditor(context, initial);
    if (config == null) return;
    final label = kind == ClipKind.ambient ? 'Ambient' : 'Ticker';
    setState(() => _status = 'Рендерим $label в 60 FPS…');
    try {
      final clip = await store.createGeneratedClip(
        kind: kind,
        name: label,
        config: config,
      );
      await renderGeneratedClip(clip);
      if (!mounted) return;
      setState(() {
        _project = _project.copyWith(clips: [..._project.clips, clip]);
        _selectedId = clip.id;
        _invalidatePreview();
        _status = '$label добавлен · 60 FPS';
      });
      await _save();
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка $label: $error');
    }
  }

  Future<void> _editGenerated() async {
    final clip = _selectedClip;
    final store = _store;
    final initial = clip?.generated;
    if (clip == null || store == null || initial == null) return;
    final editor = switch (clip.kind) {
      ClipKind.textCard => showTextCardEditor(context, initial),
      ClipKind.logoCard => showLogoCardEditor(context, initial),
      ClipKind.ambient => showAmbientEditor(context, initial),
      ClipKind.ticker => showTickerEditor(context, initial),
      _ => Future<GeneratedClipConfig?>.value(),
    };
    final edited = await editor;
    if (edited == null) return;
    try {
      final config = edited.copyWith(revision: initial.revision + 1);
      final changed = clip.kind.isGeneratedMotion
          ? clip.copyWith(
              assetPath: store.generatedMotionFramePath(
                clip.id,
                config.revision,
                0,
              ),
              normalizedPath: store.generatedMotionManifestPath(
                clip.id,
                config.revision,
              ),
              generated: config,
            )
          : clip.copyWith(
              assetPath: store.generatedRasterPath(clip.id, config.revision),
              generated: config,
            );
      await renderGeneratedClip(changed);
      if (!mounted) return;
      _replaceClip(changed);
      setState(() => _status = 'Контент обновлён');
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка карточки: $error');
    }
  }

  void _deleteSelected() {
    final selected = _selectedClip;
    if (selected == null) return;
    final clips =
        _project.clips.where((clip) => clip.id != selected.id).toList();
    setState(() {
      _project = _project.copyWith(clips: clips);
      _selectedId = clips.isEmpty ? null : clips.first.id;
      _invalidatePreview();
      _status = 'Клип удалён';
    });
    unawaited(_save());
  }

  void _duplicateSelected() {
    final selected = _selectedClip;
    final store = _store;
    if (selected == null || store == null) return;
    final duplicate = store.duplicate(selected);
    final index = _project.clips.indexOf(selected);
    final clips = [..._project.clips]..insert(index + 1, duplicate);
    setState(() {
      _project = _project.copyWith(clips: clips);
      _selectedId = duplicate.id;
      _invalidatePreview();
      _status = 'Клип продублирован';
    });
    unawaited(_save());
  }

  void _reorder(int oldIndex, int newIndex) {
    final clips = [..._project.clips];
    clips.insert(newIndex, clips.removeAt(oldIndex));
    setState(() {
      _project = _project.copyWith(clips: clips);
      _invalidatePreview();
    });
    unawaited(_save());
  }

  Future<void> _editTiming() async {
    final clip = _selectedClip;
    if (clip == null) return;
    var durationMs = clip.durationMs;
    var trimStartMs = clip.trimStartMs;
    var trimEndMs = clip.trimEndMs;
    var speed = clip.speed;
    var repeat = clip.repeat;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(switch (clip.kind) {
            ClipKind.image ||
            ClipKind.textCard ||
            ClipKind.logoCard =>
              'Длительность',
            ClipKind.gif => 'Тайминг GIF',
            ClipKind.mp4 => 'Тайминг MP4',
            ClipKind.ambient || ClipKind.ticker => 'Тайминг генератора',
          }),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!clip.kind.isImportedMotion) ...[
                  Text('${(durationMs / 1000).toStringAsFixed(1)} сек'),
                  Slider(
                    value: durationMs.toDouble().clamp(500, 10000),
                    min: 500,
                    max: 10000,
                    divisions: 19,
                    onChanged: (value) =>
                        setDialogState(() => durationMs = value.round()),
                  ),
                ] else ...[
                  DropdownButtonFormField<double>(
                    initialValue: speed,
                    decoration: const InputDecoration(labelText: 'Скорость'),
                    items: const [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value×'),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() => speed = value!),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: repeat,
                    decoration: const InputDecoration(labelText: 'Повторы'),
                    items: List.generate(10, (index) => index + 1)
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() => repeat = value!),
                  ),
                  TextFormField(
                    initialValue: '$trimStartMs',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Обрезать начало, мс',
                    ),
                    onChanged: (value) =>
                        trimStartMs = int.tryParse(value) ?? 0,
                  ),
                  TextFormField(
                    initialValue: '$trimEndMs',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Конец, мс (0 = до конца)',
                    ),
                    onChanged: (value) => trimEndMs = int.tryParse(value) ?? 0,
                  ),
                  TextFormField(
                    initialValue: '$durationMs',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Итоговая длительность, мс (0 = естественная)',
                    ),
                    onChanged: (value) => durationMs = int.tryParse(value) ?? 0,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (changed == true) {
      _replaceClip(clip.copyWith(
        durationMs: durationMs.clamp(0, 600000),
        trimStartMs: trimStartMs.clamp(0, 600000),
        trimEndMs: trimEndMs.clamp(0, 600000),
        speed: speed,
        repeat: repeat,
      ));
    }
  }

  Future<void> _editTransition() async {
    final clip = _selectedClip;
    if (clip == null) return;
    if (_project.clips.length < 2) {
      setState(() => _status = 'Для перехода нужно минимум два клипа');
      return;
    }
    final clipIndex = _project.clips.indexWhere((item) => item.id == clip.id);
    final incoming = _project.clips[(clipIndex + 1) % _project.clips.length];
    var transition = clip.outgoingTransition;
    var durationMs = clip.transitionDurationMs.clamp(200, 1500);
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final previewClip = clip.copyWith(
            outgoingTransition: transition,
            transitionDurationMs: durationMs,
          );
          return AlertDialog(
            title: Text('Переход к ${incoming.name}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<TransitionKind>(
                      initialValue: transition,
                      decoration: const InputDecoration(
                        labelText: 'Эффект после клипа',
                      ),
                      items: TransitionKind.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(
                        () => transition = value ?? TransitionKind.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Длительность: $durationMs мс'),
                    Slider(
                      value: durationMs.toDouble(),
                      min: 200,
                      max: 1500,
                      divisions: 13,
                      onChanged: transition == TransitionKind.none
                          ? null
                          : (value) => setDialogState(
                                () => durationMs = value.round(),
                              ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Точный стык на экране значка',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox.square(
                      dimension: 280,
                      child: TransitionJoinPreview(
                        outgoing: previewClip,
                        incoming: incoming,
                        cacheDirectory: _store?.compilerCacheDirectory.path,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
    if (changed == true) {
      _replaceClip(clip.copyWith(
        outgoingTransition: transition,
        transitionDurationMs: durationMs,
      ));
      if (mounted) {
        setState(() => _status = transition == TransitionKind.none
            ? 'Переход отключён'
            : '${transition.label} · $durationMs мс');
      }
    }
  }

  Future<CompiledShow?> _prepareForPublish() async {
    final ready = _compiled;
    if (ready != null) return ready;
    if (_project.clips.isEmpty || _compiling) return null;
    await _save();
    setState(() {
      _compiling = true;
      _compileProgress = 0;
      _status = 'Подготавливаем изменённые кадры для значка…';
    });
    try {
      final compiled = await compileProjectFast(
        _project,
        cacheDirectory: _store?.compilerCacheDirectory.path,
        onProgress: (progress) {
          if (!mounted) return;
          final withinClip = progress.totalFrames <= 0
              ? 0.0
              : progress.completedFrames / progress.totalFrames;
          setState(() {
            _compileProgress =
                (progress.clipIndex + withinClip) / progress.clipCount;
            _status =
                'Подготовка: клип ${progress.clipIndex + 1}/${progress.clipCount} · '
                'кадр ${progress.completedFrames}/${progress.totalFrames}';
          });
        },
      );
      if (!mounted) return null;
      final cached = compiled.cacheHits;
      final rebuilt = compiled.cacheMisses;
      setState(() {
        _compiled = compiled;
        _compiling = false;
        _compileProgress = null;
        _status =
            'Подготовлено: ${compiled.frames.length} кадров, ${(compiled.package.length / 1048576).toStringAsFixed(2)} МБ'
            '${cached > 0 ? ' · кеш $cached' : ''}'
            '${rebuilt > 0 ? ' · собрано $rebuilt' : ''}';
        _publishState = const PublishState(
          PublishStage.idle,
          'Кадры подготовлены, начинаем загрузку',
        );
      });
      return compiled;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _compiling = false;
        _compileProgress = null;
        _status = 'Не удалось подготовить шоу: $error';
      });
      return null;
    }
  }

  Future<void> _publish() async {
    if (_publishing || _compiling) return;
    final compiled = await _prepareForPublish();
    if (compiled == null || !mounted) return;
    setState(() => _publishing = true);
    await _publisher.publish(
      compiled.package,
      onState: (state) {
        if (mounted) setState(() => _publishState = state);
      },
    );
    if (mounted) setState(() => _publishing = false);
  }

  Future<void> _clearDeviceMedia() async {
    if (_clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить память значка?'),
        content: const Text(
          'Опубликованное шоу и временные медиа будут удалены с платы. '
          'Прошивка, настройки значка и проекты на телефоне останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _clearing = true;
      _status = 'Подключаемся для очистки памяти…';
    });
    try {
      await _device.connect();
      if (mounted) setState(() => _status = 'Очищаем медиа на значке…');
      await _device.clearMedia();
      final status = await _device.status();
      if (status.installed) {
        throw const ShowPublishException(
          'Плата всё ещё сообщает об установленном шоу',
        );
      }
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _status = 'Память значка очищена · проекты на телефоне сохранены';
        _publishState = const PublishState(
          PublishStage.idle,
          'Можно собрать и загрузить новое шоу',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _status = 'Не удалось очистить память: $error';
      });
    } finally {
      try {
        await _device.disconnect();
      } catch (_) {}
    }
  }

  Widget _buildWorkspace(ShowClip? selected) {
    return Column(
      children: [
        _StudioPanel(
          title: selected == null ? 'Холст' : 'Холст клипа',
          subtitle: selected == null
              ? 'Здесь появится выбранный клип'
              : 'Перемещайте, масштабируйте и вращайте медиа жестами',
          child: selected == null
              ? const _EmptyProject()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DraftClipCanvas(
                            clip: selected,
                            onChanged: _replaceClip,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ClipKindBadge(kind: selected.kind),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<ClipLayout>(
                      segments: const [
                        ButtonSegment(
                          value: ClipLayout.fit,
                          icon: Icon(Icons.fit_screen_outlined),
                          label: Text('Вписать'),
                        ),
                        ButtonSegment(
                          value: ClipLayout.fill,
                          icon: Icon(Icons.crop_free),
                          label: Text('Заполнить'),
                        ),
                      ],
                      selected: {selected.layout},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) => _replaceClip(
                        selected.copyWith(layout: value.first, scale: 1),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _replaceClip(selected.copyWith(
                            offsetX: 0,
                            offsetY: 0,
                          )),
                          icon: const Icon(Icons.center_focus_strong_outlined),
                          label: const Text('По центру'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _replaceClip(selected.copyWith(
                            layout: ClipLayout.fit,
                            offsetX: 0,
                            offsetY: 0,
                            scale: 1,
                            rotation: 0,
                          )),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Сбросить'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _editTiming,
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text('Тайминг'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _project.clips.length < 2
                              ? null
                              : _editTransition,
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: Text(
                            selected.outgoingTransition == TransitionKind.none
                                ? 'Переход'
                                : selected.outgoingTransition.label,
                          ),
                        ),
                        if (selected.kind.isGenerated)
                          OutlinedButton.icon(
                            onPressed: _editGenerated,
                            icon: const Icon(Icons.tune),
                            label: const Text('Контент'),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        if (_project.clips.isNotEmpty) ...[
          const SizedBox(height: 16),
          _StudioPanel(
            title: 'Живое превью проекта',
            subtitle: 'Воспроизведение всех клипов и переходов по порядку',
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF030507),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x452C84D8),
                              blurRadius: 36,
                              spreadRadius: -14,
                            ),
                          ],
                        ),
                        child: ProjectDraftPreview(project: _project),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Превью работает напрямую с исходными клипами. JPEG для значка создаётся только перед загрузкой.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMediaLibrary() {
    return _StudioPanel(
      title: 'Добавить контент',
      subtitle: 'Импортируйте медиа или создайте клип внутри приложения',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _importMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Добавить PNG, JPEG, GIF или MP4'),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: OutlinedButton.icon(
                      onPressed: _addTextCard,
                      icon: const Icon(Icons.text_fields_outlined),
                      label: const Text('Text-card'),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: OutlinedButton.icon(
                      onPressed: _addLogoCard,
                      icon: const Icon(Icons.branding_watermark_outlined),
                      label: const Text('Logo-card'),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: OutlinedButton.icon(
                      onPressed: () => _addGeneratedMotion(ClipKind.ambient),
                      icon: const Icon(Icons.blur_circular_outlined),
                      label: const Text('Ambient'),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: OutlinedButton.icon(
                      onPressed: () => _addGeneratedMotion(ClipKind.ticker),
                      icon: const Icon(Icons.view_headline_outlined),
                      label: const Text('Ticker'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return _StudioPanel(
      title: 'Порядок клипов',
      subtitle:
          '${_project.clips.length} ${_clipCountLabel(_project.clips.length)}',
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _project.clips.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final clip = _project.clips[index];
              final selected = clip.id == _selectedId;
              return Padding(
                key: ValueKey(clip.id),
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  selected: selected,
                  onTap: () => setState(() => _selectedId = clip.id),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? _ZColors.primary.withValues(alpha: 0.16)
                          : _ZColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _clipKindIcon(clip.kind),
                      color: selected ? _ZColors.primary : _ZColors.textMuted,
                      size: 21,
                    ),
                  ),
                  title: Text(
                    clip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (clip.kind.isGeneratedMotion)
                        '60 FPS · зациклено'
                      else if (!clip.kind.isMotion)
                        '${(clip.durationMs / 1000).toStringAsFixed(1)} сек'
                      else
                        '${clip.speed}× · ${clip.repeat} повтор(а)',
                      if (clip.outgoingTransition != TransitionKind.none)
                        '→ ${clip.outgoingTransition.label}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Semantics(
                    button: true,
                    label: 'Изменить позицию клипа ${clip.name}',
                    child: ReorderableDragStartListener(
                      index: index,
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Icon(Icons.drag_handle_rounded),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final duplicate = OutlinedButton.icon(
                onPressed: _duplicateSelected,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Дублировать'),
              );
              final delete = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ZColors.danger,
                  side: BorderSide(
                    color: _ZColors.danger.withValues(alpha: 0.55),
                  ),
                ),
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить'),
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    duplicate,
                    const SizedBox(height: 8),
                    delete,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: duplicate),
                  const SizedBox(width: 8),
                  Expanded(child: delete),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPublishPanel() {
    final busy = _publishing || _compiling;
    return _StudioPanel(
      title: 'Публикация',
      subtitle: 'Подготовка кадров и передача шоу на устройство',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_project.clips.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: busy ? null : _publish,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text(
                _publishState.stage == PublishStage.failed
                    ? 'Повторить загрузку'
                    : 'Подготовить и загрузить на значок',
              ),
            ),
            if (busy || _publishState.progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: _compiling ? _compileProgress : _publishState.progress,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _publishState.stage == PublishStage.failed
                      ? Icons.error_outline
                      : Icons.info_outline,
                  size: 19,
                  color: _publishState.stage == PublishStage.failed
                      ? _ZColors.danger
                      : _ZColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_publishState.message)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(),
            ),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _ZColors.danger,
              side: BorderSide(
                color: _ZColors.danger.withValues(alpha: 0.45),
              ),
            ),
            onPressed: _clearing ? null : _clearDeviceMedia,
            icon: _clearing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
            label: const Text('Очистить память значка'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedClip;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _ZColors.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.motion_photos_auto_outlined,
                color: _ZColors.onPrimary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Znachok — редактор',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: _ProjectCount(clips: _project.clips.length),
            ),
          ),
        ],
      ),
      body: _loading
          ? const _LoadingStudio()
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final horizontalPadding = wide ? 28.0 : 16.0;
                  final sidePanel = Column(
                    children: [
                      _buildMediaLibrary(),
                      if (_project.clips.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildTimeline(),
                      ],
                      const SizedBox(height: 16),
                      _buildPublishPanel(),
                    ],
                  );
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _EditorHeading(clips: _project.clips.length),
                            const SizedBox(height: 16),
                            _StatusNotice(
                              message: _status,
                              busy: _compiling || _publishing || _clearing,
                              failed: _status.startsWith('Ошибка') ||
                                  _status.startsWith('Не удалось'),
                            ),
                            const SizedBox(height: 16),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 7,
                                    child: _buildWorkspace(selected),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(width: 420, child: sidePanel),
                                ],
                              )
                            else ...[
                              _buildWorkspace(selected),
                              const SizedBox(height: 16),
                              sidePanel,
                            ],
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
}

IconData _clipKindIcon(ClipKind kind) => switch (kind) {
      ClipKind.image => Icons.image_outlined,
      ClipKind.gif => Icons.gif_box_outlined,
      ClipKind.mp4 => Icons.movie_outlined,
      ClipKind.textCard => Icons.text_fields_outlined,
      ClipKind.logoCard => Icons.branding_watermark_outlined,
      ClipKind.ambient => Icons.blur_circular_outlined,
      ClipKind.ticker => Icons.view_headline_outlined,
    };

String _clipKindName(ClipKind kind) => switch (kind) {
      ClipKind.image => 'IMAGE',
      ClipKind.gif => 'GIF',
      ClipKind.mp4 => 'MP4',
      ClipKind.textCard => 'TEXT',
      ClipKind.logoCard => 'LOGO',
      ClipKind.ambient => 'AMBIENT',
      ClipKind.ticker => 'TICKER',
    };

String _clipCountLabel(int count) {
  final tail = count % 100;
  if (tail >= 11 && tail <= 14) return 'клипов';
  return switch (count % 10) {
    1 => 'клип',
    2 || 3 || 4 => 'клипа',
    _ => 'клипов',
  };
}

class _StudioPanel extends StatelessWidget {
  const _StudioPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final String title;
  final String subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: padding == const EdgeInsets.all(20)
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      );
}

class _EditorHeading extends StatelessWidget {
  const _EditorHeading({required this.clips});

  final int clips;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Редактор шоу',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              clips == 0
                  ? 'Добавьте первый клип и соберите шоу для круглого дисплея.'
                  : 'Настройте композицию, порядок и загрузите готовое шоу на значок.',
            ),
          ],
        ),
      );
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({
    required this.message,
    required this.busy,
    required this.failed,
  });

  final String message;
  final bool busy;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final tone = failed ? _ZColors.danger : _ZColors.primary;
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.09),
          border: Border.all(color: tone.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                failed ? Icons.error_outline : Icons.info_outline,
                size: 19,
                color: tone,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: _ZColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipKindBadge extends StatelessWidget {
  const _ClipKindBadge({required this.kind});

  final ClipKind kind;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _ZColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _ZColors.border),
        ),
        child: Text(
          _clipKindName(kind),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _ZColors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
        ),
      );
}

class _ProjectCount extends StatelessWidget {
  const _ProjectCount({required this.clips});

  final int clips;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: _ZColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ZColors.border),
        ),
        child: Text(
          '$clips ${_clipCountLabel(clips)}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _ZColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class _LoadingStudio extends StatelessWidget {
  const _LoadingStudio();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(minHeight: 5),
                  const SizedBox(height: 18),
                  Text(
                    'Открываем проект',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Восстанавливаем клипы и настройки редактора…',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _EmptyProject extends StatelessWidget {
  const _EmptyProject();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
        decoration: BoxDecoration(
          color: _ZColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _ZColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _ZColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_collection_outlined,
                size: 34,
                color: _ZColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Начните с первого клипа',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте картинки, GIF или MP4 — приложение само подготовит их для значка',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
