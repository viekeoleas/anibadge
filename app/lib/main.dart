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
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0066B1),
        useMaterial3: true,
      ),
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
      final compiled = await compileProjectInBackground(
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedClip;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066B1),
        title: const Text('Znachok — редактор'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selected == null)
                          const _EmptyProject()
                        else ...[
                          SizedBox(
                            height: 360,
                            child: DraftClipCanvas(
                              clip: selected,
                              onChanged: _replaceClip,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selected.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _replaceClip(selected.copyWith(
                                  layout: ClipLayout.fit,
                                  scale: 1,
                                )),
                                child: const Text('Fit'),
                              ),
                              OutlinedButton(
                                onPressed: () => _replaceClip(selected.copyWith(
                                  layout: ClipLayout.fill,
                                  scale: 1,
                                )),
                                child: const Text('Fill'),
                              ),
                              OutlinedButton(
                                onPressed: () => _replaceClip(selected.copyWith(
                                  offsetX: 0,
                                  offsetY: 0,
                                )),
                                child: const Text('Center'),
                              ),
                              OutlinedButton(
                                onPressed: () => _replaceClip(selected.copyWith(
                                  layout: ClipLayout.fit,
                                  offsetX: 0,
                                  offsetY: 0,
                                  scale: 1,
                                  rotation: 0,
                                )),
                                child: const Text('Reset'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _editTiming,
                                icon: const Icon(Icons.timer),
                                label: const Text('Тайминг'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _project.clips.length < 2
                                    ? null
                                    : _editTransition,
                                icon: const Icon(Icons.auto_awesome),
                                label: Text(
                                  selected.outgoingTransition ==
                                          TransitionKind.none
                                      ? 'Переход'
                                      : selected.outgoingTransition.label,
                                ),
                              ),
                              if (selected.kind.isGenerated)
                                OutlinedButton.icon(
                                  onPressed: _editGenerated,
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Контент'),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _importMedia,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Добавить PNG, JPEG, GIF или MP4'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _addTextCard,
                                icon: const Icon(Icons.text_fields),
                                label: const Text('Text-card'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _addLogoCard,
                                icon: const Icon(Icons.branding_watermark),
                                label: const Text('Logo-card'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _addGeneratedMotion(ClipKind.ambient),
                                icon: const Icon(Icons.blur_circular),
                                label: const Text('Ambient'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _addGeneratedMotion(ClipKind.ticker),
                                icon: const Icon(Icons.view_headline),
                                label: const Text('Ticker'),
                              ),
                            ),
                          ],
                        ),
                        if (_project.clips.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Порядок клипов',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _project.clips.length,
                            onReorderItem: _reorder,
                            itemBuilder: (context, index) {
                              final clip = _project.clips[index];
                              return ListTile(
                                key: ValueKey(clip.id),
                                selected: clip.id == _selectedId,
                                onTap: () =>
                                    setState(() => _selectedId = clip.id),
                                leading: Icon(switch (clip.kind) {
                                  ClipKind.image => Icons.image,
                                  ClipKind.gif => Icons.gif_box,
                                  ClipKind.mp4 => Icons.movie,
                                  ClipKind.textCard => Icons.text_fields,
                                  ClipKind.logoCard => Icons.branding_watermark,
                                  ClipKind.ambient => Icons.blur_circular,
                                  ClipKind.ticker => Icons.view_headline,
                                }),
                                title: Text(
                                  clip.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text([
                                  if (clip.kind.isGeneratedMotion)
                                    '60 FPS · зациклено'
                                  else if (!clip.kind.isMotion)
                                    '${(clip.durationMs / 1000).toStringAsFixed(1)} сек'
                                  else
                                    '${clip.speed}× · ${clip.repeat} повтор(а)',
                                  if (clip.outgoingTransition !=
                                      TransitionKind.none)
                                    '→ ${clip.outgoingTransition.label}',
                                ].join(' · ')),
                                trailing: const Icon(Icons.drag_handle),
                              );
                            },
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _duplicateSelected,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Дублировать'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _deleteSelected,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Удалить'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Живое превью проекта',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: SizedBox.square(
                              dimension: 360,
                              child: ProjectDraftPreview(project: _project),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Превью воспроизводится напрямую из исходных клипов. '
                            'JPEG для значка готовится только перед загрузкой.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed:
                                _publishing || _compiling ? null : _publish,
                            icon: _publishing || _compiling
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.publish),
                            label: Text(
                                _publishState.stage == PublishStage.failed
                                    ? 'Повторить загрузку'
                                    : 'Подготовить и загрузить на значок'),
                          ),
                          if (_compiling ||
                              _publishing ||
                              _publishState.progress != null) ...[
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: _compiling
                                  ? _compileProgress
                                  : _publishState.progress,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            _publishState.message,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _clearing ? null : _clearDeviceMedia,
                          icon: _clearing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Очистить память значка'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF90CAF9)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _EmptyProject extends StatelessWidget {
  const _EmptyProject();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Column(
          children: [
            Icon(Icons.video_collection_outlined,
                size: 88, color: Colors.white38),
            SizedBox(height: 16),
            Text(
              'Добавьте картинки, GIF или MP4 — приложение само подготовит их для значка',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
