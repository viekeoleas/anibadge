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
    navigationBarTheme: const NavigationBarThemeData(
      height: 72,
      backgroundColor: _ZColors.surface,
      indicatorColor: _ZColors.surfaceSelected,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: _ZColors.background,
      indicatorColor: _ZColors.surfaceSelected,
      selectedIconTheme: IconThemeData(color: _ZColors.primary),
      unselectedIconTheme: IconThemeData(color: _ZColors.textMuted),
      selectedLabelTextStyle: TextStyle(
        color: _ZColors.text,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(color: _ZColors.textMuted),
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

enum _FlowStep { media, compose, timeline, publish }

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
  _FlowStep _step = _FlowStep.media;
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
      _step =
          initialProject.clips.isEmpty ? _FlowStep.media : _FlowStep.compose;
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
        _step = project.clips.isEmpty ? _FlowStep.media : _FlowStep.compose;
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

  bool _canOpenStep(_FlowStep step) => true;

  void _selectStep(_FlowStep step) {
    if (!_canOpenStep(step) || step == _step) return;
    setState(() => _step = step);
  }

  void _previousStep() {
    if (_step.index == 0) return;
    _selectStep(_FlowStep.values[_step.index - 1]);
  }

  Future<void> _nextStep() async {
    if (_step == _FlowStep.publish) {
      await _publish();
      return;
    }
    if (_project.clips.isEmpty) {
      await _showAddContentSheet();
      return;
    }
    _selectStep(_FlowStep.values[_step.index + 1]);
  }

  String get _nextStepLabel => switch (_step) {
        _FlowStep.media => 'К кадру',
        _FlowStep.compose => 'К таймлайну',
        _FlowStep.timeline => 'К загрузке',
        _FlowStep.publish => _publishState.stage == PublishStage.failed
            ? 'Повторить'
            : 'Загрузить',
      };

  Future<void> _showAddContentSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _ZColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Добавить',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 8) / 2;
                    Widget choice({
                      required String label,
                      required IconData icon,
                      required VoidCallback onPressed,
                    }) =>
                        SizedBox(
                          width: itemWidth,
                          child: OutlinedButton.icon(
                            onPressed: onPressed,
                            icon: Icon(icon),
                            label: Text(label),
                          ),
                        );
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        choice(
                          label: 'Медиа',
                          icon: Icons.add_photo_alternate_outlined,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(_importMedia());
                          },
                        ),
                        choice(
                          label: 'Текст',
                          icon: Icons.text_fields_outlined,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(_addTextCard());
                          },
                        ),
                        choice(
                          label: 'Логотип',
                          icon: Icons.branding_watermark_outlined,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(_addLogoCard());
                          },
                        ),
                        choice(
                          label: 'Фон',
                          icon: Icons.blur_circular_outlined,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(
                              _addGeneratedMotion(ClipKind.ambient),
                            );
                          },
                        ),
                        choice(
                          label: 'Бегущая строка',
                          icon: Icons.view_headline_outlined,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(
                              _addGeneratedMotion(ClipKind.ticker),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaStep() {
    if (_project.clips.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.video_collection_outlined,
                size: 64,
                color: _ZColors.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Добавьте медиа',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('add-content-empty'),
                onPressed: _showAddContentSheet,
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth > 840
            ? (constraints.maxWidth - 800) / 2
            : 16.0;
        return ListView.separated(
          key: const ValueKey('media-list'),
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 24),
          itemCount: _project.clips.length + 1,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            if (index == _project.clips.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _showAddContentSheet,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              );
            }
            final clip = _project.clips[index];
            final selected = clip.id == _selectedId;
            return ListTile(
              key: ValueKey('media-${clip.id}'),
              selected: selected,
              onTap: () => setState(() => _selectedId = clip.id),
              leading: SizedBox.square(
                dimension: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? _ZColors.primary.withValues(alpha: 0.14)
                        : _ZColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _clipKindIcon(clip.kind),
                    color: selected ? _ZColors.primary : _ZColors.textMuted,
                  ),
                ),
              ),
              title: Text(
                clip.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Удалить ${clip.name}',
                onPressed: () {
                  setState(() => _selectedId = clip.id);
                  _deleteSelected();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClipStrip() {
    return SizedBox(
      height: 66,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        scrollDirection: Axis.horizontal,
        itemCount: _project.clips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final clip = _project.clips[index];
          final selected = clip.id == _selectedId;
          return Semantics(
            button: true,
            selected: selected,
            label: 'Открыть ${clip.name}',
            child: Material(
              color: selected ? _ZColors.surfaceSelected : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected ? _ZColors.primary : _ZColors.border,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedId = clip.id),
                child: SizedBox(
                  width: 142,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          _clipKindIcon(clip.kind),
                          size: 20,
                          color:
                              selected ? _ZColors.primary : _ZColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            clip.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposeStep() {
    final selected = _selectedClip;
    if (selected == null) return _buildMediaStep();

    return Column(
      children: [
        _buildClipStrip(),
        const Divider(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 680, maxHeight: 680),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: KeyedSubtree(
                    key: const ValueKey('compose-canvas'),
                    child: DraftClipCanvas(
                      clip: selected,
                      onChanged: _replaceClip,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(),
        SizedBox(
          height: 62,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            scrollDirection: Axis.horizontal,
            children: [
              SegmentedButton<ClipLayout>(
                segments: const [
                  ButtonSegment(
                    value: ClipLayout.fit,
                    label: Text('Вписать'),
                  ),
                  ButtonSegment(
                    value: ClipLayout.fill,
                    label: Text('Заполнить'),
                  ),
                ],
                selected: {selected.layout},
                showSelectedIcon: false,
                onSelectionChanged: (value) => _replaceClip(
                  selected.copyWith(layout: value.first, scale: 1),
                ),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              _EditorTool(
                label: 'X',
                icon: Icons.align_horizontal_center,
                onPressed: () => _replaceClip(selected.copyWith(offsetX: 0)),
              ),
              _EditorTool(
                label: 'Y',
                icon: Icons.align_vertical_center,
                onPressed: () => _replaceClip(selected.copyWith(offsetY: 0)),
              ),
              _EditorTool(
                label: '0°',
                icon: Icons.straighten,
                onPressed: () => _replaceClip(selected.copyWith(rotation: 0)),
              ),
              _EditorTool(
                label: 'Сброс',
                icon: Icons.restart_alt,
                onPressed: () => _replaceClip(
                  selected.copyWith(
                    layout: ClipLayout.fit,
                    offsetX: 0,
                    offsetY: 0,
                    scale: 1,
                    rotation: 0,
                  ),
                ),
              ),
              if (selected.kind.isGenerated)
                _EditorTool(
                  label: 'Контент',
                  icon: Icons.tune,
                  onPressed: _editGenerated,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStep() {
    if (_project.clips.isEmpty) return _buildMediaStep();
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth > 840
            ? (constraints.maxWidth - 800) / 2
            : 12.0;
        return Column(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                key: const ValueKey('timeline-list'),
                padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 10),
                buildDefaultDragHandles: false,
                itemCount: _project.clips.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final clip = _project.clips[index];
                  final selected = clip.id == _selectedId;
                  final timing = clip.kind.isGeneratedMotion
                      ? '60 FPS'
                      : clip.kind.isMotion
                          ? '${clip.speed}× · ${clip.repeat}×'
                          : '${(clip.durationMs / 1000).toStringAsFixed(1)} с';
                  return DecoratedBox(
                    key: ValueKey(clip.id),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _ZColors.border),
                      ),
                    ),
                    child: ListTile(
                      selected: selected,
                      onTap: () => setState(() => _selectedId = clip.id),
                      leading: Icon(_clipKindIcon(clip.kind)),
                      title: Text(
                        clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        clip.outgoingTransition == TransitionKind.none
                            ? timing
                            : '$timing · ${clip.outgoingTransition.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const SizedBox.square(
                          dimension: 48,
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            SizedBox(
              height: 62,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                scrollDirection: Axis.horizontal,
                children: [
                  _EditorTool(
                    label: 'Тайминг',
                    icon: Icons.timer_outlined,
                    onPressed: _editTiming,
                  ),
                  _EditorTool(
                    label: _selectedClip?.outgoingTransition ==
                            TransitionKind.none
                        ? 'Переход'
                        : _selectedClip?.outgoingTransition.label ?? 'Переход',
                    icon: Icons.auto_awesome_outlined,
                    onPressed:
                        _project.clips.length < 2 ? null : _editTransition,
                  ),
                  _EditorTool(
                    label: 'Копия',
                    icon: Icons.copy_outlined,
                    onPressed: _duplicateSelected,
                  ),
                  _EditorTool(
                    label: 'Удалить',
                    icon: Icons.delete_outline,
                    danger: true,
                    onPressed: _deleteSelected,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPublishStep() {
    final busy = _publishing || _compiling || _clearing;
    final showStatus = busy ||
        _publishState.stage == PublishStage.failed ||
        _publishState.stage == PublishStage.complete;
    return Column(
      children: [
        Expanded(
          child: _project.clips.isEmpty
              ? Center(
                  child: Text(
                    'Нет клипов',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 680, maxHeight: 680),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          key: const ValueKey('publish-preview'),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x382C84D8),
                                blurRadius: 32,
                                spreadRadius: -12,
                              ),
                            ],
                          ),
                          child: ProjectDraftPreview(project: _project),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (busy || _publishState.progress != null)
          LinearProgressIndicator(
            minHeight: 4,
            value: _compiling ? _compileProgress : _publishState.progress,
          ),
        if (showStatus)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Row(
                children: [
                  Icon(
                    _publishState.stage == PublishStage.failed
                        ? Icons.error_outline
                        : _publishState.stage == PublishStage.complete
                            ? Icons.check_circle_outline
                            : Icons.sync,
                    size: 20,
                    color: _publishState.stage == PublishStage.failed
                        ? _ZColors.danger
                        : _ZColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _clearing ? _status : _publishState.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _clearing ? null : _clearDeviceMedia,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Очистить память значка'),
              style: TextButton.styleFrom(foregroundColor: _ZColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStep() => switch (_step) {
        _FlowStep.media => _buildMediaStep(),
        _FlowStep.compose => _buildComposeStep(),
        _FlowStep.timeline => _buildTimelineStep(),
        _FlowStep.publish => _buildPublishStep(),
      };

  @override
  Widget build(BuildContext context) {
    final busy = _publishing || _compiling || _clearing;
    final canContinue = _project.clips.isNotEmpty && !busy;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

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
                'Znachok',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (!_loading &&
              (_step == _FlowStep.media || _step == _FlowStep.compose))
            IconButton(
              key: const ValueKey('add-content'),
              tooltip: 'Добавить',
              onPressed: _showAddContentSheet,
              icon: const Icon(Icons.add),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _ProjectCount(clips: _project.clips.length),
            ),
          ),
        ],
      ),
      body: _loading
          ? const _LoadingStudio()
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  _FlowStepper(
                    current: _step,
                    onSelected: _selectStep,
                  ),
                  const Divider(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: _buildCurrentStep(),
                      ),
                    ),
                  ),
                  const Divider(),
                  _FlowFooter(
                    showBack: _step != _FlowStep.media,
                    onBack: busy ? null : _previousStep,
                    primaryLabel: _nextStepLabel,
                    onPrimary: (_step == _FlowStep.media ? !busy : canContinue)
                        ? _nextStep
                        : null,
                    busy: busy,
                  ),
                ],
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

String _clipCountLabel(int count) {
  final tail = count % 100;
  if (tail >= 11 && tail <= 14) return 'клипов';
  return switch (count % 10) {
    1 => 'клип',
    2 || 3 || 4 => 'клипа',
    _ => 'клипов',
  };
}

class _FlowStepper extends StatelessWidget {
  const _FlowStepper({
    required this.current,
    required this.onSelected,
  });

  final _FlowStep current;
  final ValueChanged<_FlowStep> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Медиа', 'Кадр', 'Таймлайн', 'Загрузка'];
    const icons = [
      Icons.video_library_outlined,
      Icons.crop_free,
      Icons.view_timeline_outlined,
      Icons.rocket_launch_outlined,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            constraints.maxWidth >= 440 ? constraints.maxWidth / 4 : 110.0;
        return SizedBox(
          height: 58,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final step in _FlowStep.values)
                  SizedBox(
                    width: itemWidth,
                    height: 58,
                    child: _StepButton(
                      key: ValueKey('flow-step-${step.name}'),
                      label: labels[step.index],
                      icon: icons[step.index],
                      selected: step == current,
                      enabled: true,
                      onPressed: () => onSelected(step),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: enabled
                        ? selected
                            ? _ZColors.primary
                            : _ZColors.textMuted
                        : _ZColors.borderStrong,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: enabled
                                ? selected
                                    ? _ZColors.text
                                    : _ZColors.textMuted
                                : _ZColors.borderStrong,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
              if (selected)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: 42,
                    height: 3,
                    child: ColoredBox(color: _ZColors.primary),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _FlowFooter extends StatelessWidget {
  const _FlowFooter({
    required this.showBack,
    required this.onBack,
    required this.primaryLabel,
    required this.onPrimary,
    required this.busy,
  });

  final bool showBack;
  final VoidCallback? onBack;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            if (showBack) ...[
              OutlinedButton.icon(
                key: const ValueKey('flow-back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('flow-next'),
                onPressed: onPrimary,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: Text(primaryLabel),
              ),
            ),
          ],
        ),
      );
}

class _EditorTool extends StatelessWidget {
  const _EditorTool({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: danger ? _ZColors.danger : _ZColors.textMuted,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      );
}

class _ProjectCount extends StatelessWidget {
  const _ProjectCount({required this.clips});

  final int clips;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
  Widget build(BuildContext context) => const SafeArea(
        child: Center(child: CircularProgressIndicator()),
      );
}
