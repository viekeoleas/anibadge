import 'dart:convert';

enum ClipKind { image, gif, mp4, textCard, logoCard, ambient, ticker }

extension ClipKindCapabilities on ClipKind {
  bool get isMotion =>
      this == ClipKind.gif ||
      this == ClipKind.mp4 ||
      this == ClipKind.ambient ||
      this == ClipKind.ticker;
  bool get isImportedMotion => this == ClipKind.gif || this == ClipKind.mp4;
  bool get isGeneratedMotion =>
      this == ClipKind.ambient || this == ClipKind.ticker;
  bool get isGenerated =>
      this == ClipKind.textCard ||
      this == ClipKind.logoCard ||
      isGeneratedMotion;
}

enum ClipLayout { fit, fill }

enum TransitionKind { none, dissolve, radialBloom, lightSweep, depthFlow }

extension TransitionKindLabel on TransitionKind {
  String get label => switch (this) {
        TransitionKind.none => 'Без перехода',
        TransitionKind.dissolve => 'Растворение',
        TransitionKind.radialBloom => 'Световой круг',
        TransitionKind.lightSweep => 'Световая волна',
        TransitionKind.depthFlow => 'Глубина',
      };
}

enum GeneratedFont { clean, bold, condensed, mono }

enum CardTextAlignment { left, center, right }

enum TickerDirection { rightToLeft, leftToRight }

class GeneratedClipConfig {
  const GeneratedClipConfig({
    this.text = 'ZNACHOK',
    this.font = GeneratedFont.bold,
    this.fontSize = 96,
    this.foregroundColor = 0xFFFFFFFF,
    this.backgroundColor = 0xFF0066B1,
    this.alignment = CardTextAlignment.center,
    this.logoSourcePath,
    this.logoScale = 0.72,
    this.secondaryColor = 0xFF6C4DFF,
    this.glowColor = 0xFF00A8E8,
    this.pulseStrength = 0.55,
    this.tickerDirection = TickerDirection.rightToLeft,
    this.tickerSpeed = 220,
    this.revision = 0,
  });

  final String text;
  final GeneratedFont font;
  final double fontSize;
  final int foregroundColor;
  final int backgroundColor;
  final CardTextAlignment alignment;
  final String? logoSourcePath;
  final double logoScale;
  final int secondaryColor;
  final int glowColor;
  final double pulseStrength;
  final TickerDirection tickerDirection;
  final double tickerSpeed;
  final int revision;

  GeneratedClipConfig copyWith({
    String? text,
    GeneratedFont? font,
    double? fontSize,
    int? foregroundColor,
    int? backgroundColor,
    CardTextAlignment? alignment,
    String? logoSourcePath,
    double? logoScale,
    int? secondaryColor,
    int? glowColor,
    double? pulseStrength,
    TickerDirection? tickerDirection,
    double? tickerSpeed,
    int? revision,
  }) =>
      GeneratedClipConfig(
        text: text ?? this.text,
        font: font ?? this.font,
        fontSize: fontSize ?? this.fontSize,
        foregroundColor: foregroundColor ?? this.foregroundColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        alignment: alignment ?? this.alignment,
        logoSourcePath: logoSourcePath ?? this.logoSourcePath,
        logoScale: logoScale ?? this.logoScale,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        glowColor: glowColor ?? this.glowColor,
        pulseStrength: pulseStrength ?? this.pulseStrength,
        tickerDirection: tickerDirection ?? this.tickerDirection,
        tickerSpeed: tickerSpeed ?? this.tickerSpeed,
        revision: revision ?? this.revision,
      );

  Map<String, Object> toJson() => {
        'text': text,
        'font': font.name,
        'fontSize': fontSize,
        'foregroundColor': foregroundColor,
        'backgroundColor': backgroundColor,
        'alignment': alignment.name,
        if (logoSourcePath != null) 'logoSourcePath': logoSourcePath!,
        'logoScale': logoScale,
        'secondaryColor': secondaryColor,
        'glowColor': glowColor,
        'pulseStrength': pulseStrength,
        'tickerDirection': tickerDirection.name,
        'tickerSpeed': tickerSpeed,
        'revision': revision,
      };

  factory GeneratedClipConfig.fromJson(Map<String, dynamic> json) =>
      GeneratedClipConfig(
        text: json['text'] as String? ?? 'ZNACHOK',
        font: GeneratedFont.values.byName(
          json['font'] as String? ?? GeneratedFont.bold.name,
        ),
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 96,
        foregroundColor:
            (json['foregroundColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        backgroundColor:
            (json['backgroundColor'] as num?)?.toInt() ?? 0xFF0066B1,
        alignment: CardTextAlignment.values.byName(
          json['alignment'] as String? ?? CardTextAlignment.center.name,
        ),
        logoSourcePath: json['logoSourcePath'] as String?,
        logoScale: (json['logoScale'] as num?)?.toDouble() ?? 0.72,
        secondaryColor: (json['secondaryColor'] as num?)?.toInt() ?? 0xFF6C4DFF,
        glowColor: (json['glowColor'] as num?)?.toInt() ?? 0xFF00A8E8,
        pulseStrength: (json['pulseStrength'] as num?)?.toDouble() ?? 0.55,
        tickerDirection: TickerDirection.values.byName(
          json['tickerDirection'] as String? ??
              TickerDirection.rightToLeft.name,
        ),
        tickerSpeed: (json['tickerSpeed'] as num?)?.toDouble() ?? 220,
        revision: (json['revision'] as num?)?.toInt() ?? 0,
      );
}

class ShowClip {
  const ShowClip({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.kind,
    this.normalizedPath,
    this.generated,
    this.durationMs = 3000,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.speed = 1,
    this.repeat = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1,
    this.rotation = 0,
    this.layout = ClipLayout.fit,
    this.outgoingTransition = TransitionKind.none,
    this.transitionDurationMs = 500,
  });

  final String id;
  final String name;
  final String assetPath;
  final ClipKind kind;
  final String? normalizedPath;
  final GeneratedClipConfig? generated;
  final int durationMs;
  final int trimStartMs;
  final int trimEndMs;
  final double speed;
  final int repeat;
  final double offsetX;
  final double offsetY;
  final double scale;
  final double rotation;
  final ClipLayout layout;
  final TransitionKind outgoingTransition;
  final int transitionDurationMs;

  ShowClip copyWith({
    String? id,
    String? name,
    String? assetPath,
    ClipKind? kind,
    String? normalizedPath,
    GeneratedClipConfig? generated,
    int? durationMs,
    int? trimStartMs,
    int? trimEndMs,
    double? speed,
    int? repeat,
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotation,
    ClipLayout? layout,
    TransitionKind? outgoingTransition,
    int? transitionDurationMs,
  }) =>
      ShowClip(
        id: id ?? this.id,
        name: name ?? this.name,
        assetPath: assetPath ?? this.assetPath,
        kind: kind ?? this.kind,
        normalizedPath: normalizedPath ?? this.normalizedPath,
        generated: generated ?? this.generated,
        durationMs: durationMs ?? this.durationMs,
        trimStartMs: trimStartMs ?? this.trimStartMs,
        trimEndMs: trimEndMs ?? this.trimEndMs,
        speed: speed ?? this.speed,
        repeat: repeat ?? this.repeat,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        layout: layout ?? this.layout,
        outgoingTransition: outgoingTransition ?? this.outgoingTransition,
        transitionDurationMs: transitionDurationMs ?? this.transitionDurationMs,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'assetPath': assetPath,
        'kind': kind.name,
        if (normalizedPath != null) 'normalizedPath': normalizedPath!,
        if (generated != null) 'generated': generated!.toJson(),
        'durationMs': durationMs,
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        'speed': speed,
        'repeat': repeat,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'scale': scale,
        'rotation': rotation,
        'layout': layout.name,
        'outgoingTransition': outgoingTransition.name,
        'transitionDurationMs': transitionDurationMs,
      };

  factory ShowClip.fromJson(Map<String, dynamic> json) => ShowClip(
        id: json['id'] as String,
        name: json['name'] as String,
        assetPath: json['assetPath'] as String,
        kind: ClipKind.values.byName(json['kind'] as String),
        normalizedPath: json['normalizedPath'] as String?,
        generated: json['generated'] == null
            ? null
            : GeneratedClipConfig.fromJson(
                json['generated'] as Map<String, dynamic>,
              ),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 3000,
        trimStartMs: (json['trimStartMs'] as num?)?.toInt() ?? 0,
        trimEndMs: (json['trimEndMs'] as num?)?.toInt() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 1,
        repeat: (json['repeat'] as num?)?.toInt() ?? 1,
        offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
        offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        layout: ClipLayout.values.byName(
          json['layout'] as String? ?? ClipLayout.fit.name,
        ),
        outgoingTransition: TransitionKind.values.firstWhere(
          (value) => value.name == json['outgoingTransition'],
          orElse: () => TransitionKind.none,
        ),
        transitionDurationMs:
            (json['transitionDurationMs'] as num?)?.toInt() ?? 500,
      );
}

class ShowProject {
  const ShowProject({
    this.version = 1,
    this.name = 'Моё шоу',
    this.clips = const [],
  });

  final int version;
  final String name;
  final List<ShowClip> clips;

  ShowProject copyWith({String? name, List<ShowClip>? clips}) => ShowProject(
        version: version,
        name: name ?? this.name,
        clips: clips ?? this.clips,
      );

  Map<String, Object> toJson() => {
        'version': version,
        'name': name,
        'clips': clips.map((clip) => clip.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  factory ShowProject.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Неподдерживаемая версия проекта');
    }
    return ShowProject(
      name: json['name'] as String? ?? 'Моё шоу',
      clips: (json['clips'] as List<dynamic>? ?? const [])
          .map((item) => ShowClip.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
