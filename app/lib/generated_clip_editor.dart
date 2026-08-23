import 'dart:io';

import 'package:flutter/material.dart';

import 'project_model.dart';

const Map<int, String> _cardColors = {
  0xFF000000: 'Чёрный',
  0xFFFFFFFF: 'Белый',
  0xFF0066B1: 'BMW Blue',
  0xFF00A8E8: 'Голубой',
  0xFFFF3B30: 'Красный',
  0xFFFFC107: 'Янтарный',
  0xFF38D996: 'Мятный',
  0xFF6C4DFF: 'Фиолетовый',
};

Future<GeneratedClipConfig?> showTextCardEditor(
  BuildContext context,
  GeneratedClipConfig initial,
) async {
  var text = initial.text;
  var font = initial.font;
  var fontSize = initial.fontSize;
  var foreground = initial.foregroundColor;
  var background = initial.backgroundColor;
  var alignment = initial.alignment;
  return showDialog<GeneratedClipConfig>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Text-card'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: text,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Текст'),
                onChanged: (value) => setDialogState(() => text = value),
              ),
              DropdownButtonFormField<GeneratedFont>(
                initialValue: font,
                decoration: const InputDecoration(labelText: 'Шрифт'),
                items: GeneratedFont.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_fontLabel(value)),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => font = value!),
              ),
              const SizedBox(height: 10),
              Text('Размер: ${fontSize.round()}'),
              Slider(
                value: fontSize.clamp(32, 160),
                min: 32,
                max: 160,
                divisions: 32,
                onChanged: (value) => setDialogState(() => fontSize = value),
              ),
              _ColorField(
                label: 'Цвет текста',
                value: foreground,
                onChanged: (value) => setDialogState(() => foreground = value),
              ),
              _ColorField(
                label: 'Фон',
                value: background,
                onChanged: (value) => setDialogState(() => background = value),
              ),
              DropdownButtonFormField<CardTextAlignment>(
                initialValue: alignment,
                decoration: const InputDecoration(labelText: 'Выравнивание'),
                items: CardTextAlignment.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_alignmentLabel(value)),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => alignment = value!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      initial.copyWith(
                        text: text.trim(),
                        font: font,
                        fontSize: fontSize,
                        foregroundColor: foreground,
                        backgroundColor: background,
                        alignment: alignment,
                      ),
                    ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Future<GeneratedClipConfig?> showLogoCardEditor(
  BuildContext context,
  GeneratedClipConfig initial,
) async {
  var background = initial.backgroundColor;
  var logoScale = initial.logoScale;
  return showDialog<GeneratedClipConfig>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Logo-card'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (initial.logoSourcePath != null)
                SizedBox.square(
                  dimension: 140,
                  child: Image.file(
                    File(initial.logoSourcePath!),
                    fit: BoxFit.contain,
                  ),
                ),
              _ColorField(
                label: 'Фон',
                value: background,
                onChanged: (value) => setDialogState(() => background = value),
              ),
              const SizedBox(height: 10),
              Text('Масштаб логотипа: ${(logoScale * 100).round()}%'),
              Slider(
                value: logoScale.clamp(0.1, 1.2),
                min: 0.1,
                max: 1.2,
                divisions: 22,
                onChanged: (value) => setDialogState(() => logoScale = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              initial.copyWith(
                backgroundColor: background,
                logoScale: logoScale,
              ),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Future<GeneratedClipConfig?> showAmbientEditor(
  BuildContext context,
  GeneratedClipConfig initial,
) async {
  var first = initial.backgroundColor;
  var second = initial.secondaryColor;
  var glow = initial.glowColor;
  var pulse = initial.pulseStrength;
  return showDialog<GeneratedClipConfig>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Ambient'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ColorField(
                label: 'Цвет градиента 1',
                value: first,
                onChanged: (value) => setDialogState(() => first = value),
              ),
              _ColorField(
                label: 'Цвет градиента 2',
                value: second,
                onChanged: (value) => setDialogState(() => second = value),
              ),
              _ColorField(
                label: 'Цвет свечения',
                value: glow,
                onChanged: (value) => setDialogState(() => glow = value),
              ),
              const SizedBox(height: 10),
              Text('Пульсация: ${(pulse * 100).round()}%'),
              Slider(
                value: pulse.clamp(0, 1),
                min: 0,
                max: 1,
                divisions: 10,
                onChanged: (value) => setDialogState(() => pulse = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              initial.copyWith(
                backgroundColor: first,
                secondaryColor: second,
                glowColor: glow,
                pulseStrength: pulse,
              ),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Future<GeneratedClipConfig?> showTickerEditor(
  BuildContext context,
  GeneratedClipConfig initial,
) async {
  var text = initial.text;
  var font = initial.font;
  var fontSize = initial.fontSize;
  var foreground = initial.foregroundColor;
  var background = initial.backgroundColor;
  var direction = initial.tickerDirection;
  var speed = initial.tickerSpeed;
  return showDialog<GeneratedClipConfig>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Ticker'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: text,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Текст строки'),
                onChanged: (value) => setDialogState(() => text = value),
              ),
              DropdownButtonFormField<GeneratedFont>(
                initialValue: font,
                decoration: const InputDecoration(labelText: 'Шрифт'),
                items: GeneratedFont.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_fontLabel(value)),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => font = value!),
              ),
              Text('Размер: ${fontSize.round()}'),
              Slider(
                value: fontSize.clamp(32, 160),
                min: 32,
                max: 160,
                divisions: 32,
                onChanged: (value) => setDialogState(() => fontSize = value),
              ),
              _ColorField(
                label: 'Цвет текста',
                value: foreground,
                onChanged: (value) => setDialogState(() => foreground = value),
              ),
              _ColorField(
                label: 'Фон',
                value: background,
                onChanged: (value) => setDialogState(() => background = value),
              ),
              DropdownButtonFormField<TickerDirection>(
                initialValue: direction,
                decoration: const InputDecoration(labelText: 'Направление'),
                items: const [
                  DropdownMenuItem(
                    value: TickerDirection.rightToLeft,
                    child: Text('Справа налево'),
                  ),
                  DropdownMenuItem(
                    value: TickerDirection.leftToRight,
                    child: Text('Слева направо'),
                  ),
                ],
                onChanged: (value) => setDialogState(() => direction = value!),
              ),
              Text('Скорость: ${speed.round()} px/с'),
              Slider(
                value: speed.clamp(100, 600),
                min: 100,
                max: 600,
                divisions: 10,
                onChanged: (value) => setDialogState(() => speed = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      initial.copyWith(
                        text: text.trim(),
                        font: font,
                        fontSize: fontSize,
                        foregroundColor: foreground,
                        backgroundColor: background,
                        tickerDirection: direction,
                        tickerSpeed: speed,
                      ),
                    ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        initialValue: _cardColors.containsKey(value) ? value : 0xFFFFFFFF,
        decoration: InputDecoration(labelText: label),
        items: _cardColors.entries
            .map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Color(entry.key),
                          border: Border.all(color: Colors.white38),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(entry.value),
                    ],
                  ),
                ))
            .toList(),
        onChanged: (value) => onChanged(value!),
      );
}

String _fontLabel(GeneratedFont font) => switch (font) {
      GeneratedFont.clean => 'Clean',
      GeneratedFont.bold => 'Bold',
      GeneratedFont.condensed => 'Condensed',
      GeneratedFont.mono => 'Mono',
    };

String _alignmentLabel(CardTextAlignment alignment) => switch (alignment) {
      CardTextAlignment.left => 'Слева',
      CardTextAlignment.center => 'По центру',
      CardTextAlignment.right => 'Справа',
    };
