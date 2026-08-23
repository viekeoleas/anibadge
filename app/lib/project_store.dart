import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'project_model.dart';

class ProjectStore {
  ProjectStore(this.root);

  final Directory root;
  final Uuid _uuid = const Uuid();

  File get _projectFile => File(path.join(root.path, 'project.json'));
  Directory get _assets => Directory(path.join(root.path, 'assets'));
  Directory get _normalized => Directory(path.join(root.path, 'normalized'));
  Directory get _generated => Directory(path.join(root.path, 'generated'));
  Directory get compilerCacheDirectory =>
      Directory(path.join(root.path, 'compiled-cache-v1'));

  static Future<ProjectStore> open() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(path.join(documents.path, 'znachok-project'));
    await root.create(recursive: true);
    return ProjectStore(root);
  }

  Future<ShowProject> load() async {
    if (!await _projectFile.exists()) return const ShowProject();
    return ShowProject.decode(await _projectFile.readAsString());
  }

  Future<void> save(ShowProject project) async {
    await root.create(recursive: true);
    await _projectFile.writeAsString(project.encode(), flush: true);
  }

  Future<ShowClip> importMedia({
    required String originalName,
    required Uint8List bytes,
    required ClipKind kind,
  }) async {
    await _assets.create(recursive: true);
    final id = _uuid.v4();
    final extension = path.extension(originalName).toLowerCase();
    final asset = File(path.join(_assets.path, '$id$extension'));
    await asset.writeAsBytes(bytes, flush: true);
    return ShowClip(
      id: id,
      name: originalName,
      assetPath: asset.path,
      kind: kind,
    );
  }

  Future<ShowClip> importMediaFile({
    required String originalName,
    required String sourcePath,
    required ClipKind kind,
  }) async {
    await _assets.create(recursive: true);
    final id = _uuid.v4();
    final extension = path.extension(originalName).toLowerCase();
    final asset = File(path.join(_assets.path, '$id$extension'));
    await File(sourcePath).copy(asset.path);
    return ShowClip(
      id: id,
      name: originalName,
      assetPath: asset.path,
      kind: kind,
    );
  }

  Future<void> discardImport(ShowClip clip) async {
    final asset = File(clip.assetPath);
    if (await asset.exists()) await asset.delete();
    final normalized = normalizedDirectory(clip.id);
    if (await normalized.exists()) await normalized.delete(recursive: true);
  }

  ShowClip duplicate(ShowClip clip) => clip.copyWith(
        id: _uuid.v4(),
        name: '${clip.name} — копия',
      );

  Directory normalizedDirectory(String clipId) =>
      Directory(path.join(_normalized.path, clipId));

  Future<ShowClip> createGeneratedClip({
    required ClipKind kind,
    required String name,
    required GeneratedClipConfig config,
  }) async {
    if (!kind.isGenerated) {
      throw ArgumentError.value(kind, 'kind', 'Expected generated clip kind');
    }
    await _generated.create(recursive: true);
    final id = _uuid.v4();
    final isMotion = kind.isGeneratedMotion;
    return ShowClip(
      id: id,
      name: name,
      assetPath: isMotion
          ? generatedMotionFramePath(id, config.revision, 0)
          : generatedRasterPath(id, config.revision),
      kind: kind,
      normalizedPath:
          isMotion ? generatedMotionManifestPath(id, config.revision) : null,
      generated: config,
      durationMs: isMotion ? 0 : 3000,
    );
  }

  String generatedRasterPath(String clipId, int revision) =>
      path.join(_generated.path, '$clipId-$revision.png');

  Directory generatedMotionDirectory(String clipId, int revision) =>
      Directory(path.join(_generated.path, '$clipId-$revision'));

  String generatedMotionManifestPath(String clipId, int revision) => path.join(
        generatedMotionDirectory(clipId, revision).path,
        'manifest.json',
      );

  String generatedMotionFramePath(String clipId, int revision, int index) =>
      path.join(
        generatedMotionDirectory(clipId, revision).path,
        'frame-${index.toString().padLeft(5, '0')}.jpg',
      );

  Future<String> importGeneratorSource({
    required String originalName,
    String? sourcePath,
    Uint8List? bytes,
  }) async {
    await _assets.create(recursive: true);
    final id = _uuid.v4();
    final extension = path.extension(originalName).toLowerCase();
    final asset = File(path.join(_assets.path, '$id-logo$extension'));
    if (sourcePath != null) {
      await File(sourcePath).copy(asset.path);
    } else if (bytes != null) {
      await asset.writeAsBytes(bytes, flush: true);
    } else {
      throw ArgumentError('Logo source is missing');
    }
    return asset.path;
  }
}
