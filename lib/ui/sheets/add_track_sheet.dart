import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/color_palette.dart';
import '../../widgets/common.dart';

Future<int?> showAddTrackSheet(
  BuildContext context,
  RemoteController controller, {
  String initialType = 'instrument',
}) {
  return showAppSheet<int>(
    context,
    maxWidth: 520,
    heightFactor: 0.85,
    builder:
        (ctx) => _AddTrackSheet(
          controller: controller,
          initialType: initialType == 'audio' ? 'audio' : 'instrument',
        ),
  );
}

class _AddTrackSheet extends StatefulWidget {
  const _AddTrackSheet({required this.controller, required this.initialType});

  final RemoteController controller;
  final String initialType;

  @override
  State<_AddTrackSheet> createState() => _AddTrackSheetState();
}

class _AddTrackSheetState extends State<_AddTrackSheet> {
  late String _type = widget.initialType;
  late final TextEditingController _name;
  late int _colorIndex;
  bool _nameEdited = false;
  bool _saving = false;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final project = _controller.currentProject;
    final existing =
        project?.tracks.where((track) => track.type == _type).length ?? 0;
    _name = TextEditingController(text: _defaultName(existing + 1));
    _colorIndex = (project?.tracks.length ?? 0) % AppColors.trackPalette.length;
    _name.addListener(() {
      final auto = _defaultName(
        (project?.tracks.where((track) => track.type == _type).length ?? 0) + 1,
      );
      _nameEdited = _name.text != auto;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _defaultName(int number) =>
      _type == 'audio' ? 'Audio $number' : 'Instrument $number';

  void _setType(String type) {
    if (_type == type) return;
    final project = _controller.currentProject;
    final existing =
        project?.tracks.where((track) => track.type == type).length ?? 0;
    setState(() {
      _type = type;
      if (!_nameEdited) _name.text = _defaultName(existing + 1);
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    setState(() => _saving = true);
    final id = await _controller.addTrack(
      name: name.isEmpty ? _defaultName(1) : name,
      type: _type,
      colorIndex: _colorIndex,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (id != null) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      children: [
        SheetHeader(
          title: l10n.t('addTrack'),
          icon: Icons.add_circle_outline_rounded,
        ),
        Row(
          children: [
            Expanded(
              child: _TypeCard(
                icon: Icons.piano_rounded,
                title: l10n.t('addInstrumentTrack'),
                subtitle: 'MIDI',
                selected: _type == 'instrument',
                onTap: () => _setType('instrument'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeCard(
                icon: Icons.graphic_eq_rounded,
                title: l10n.t('addAudioTrack'),
                subtitle: 'AUDIO',
                selected: _type == 'audio',
                onTap: () => _setType('audio'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.done,
          maxLength: 40,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.t('trackName'),
            prefixIcon: const Icon(Icons.edit_outlined, size: 18),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel(l10n.t('trackColor')),
        ColorPalettePicker(
          selectedIndex: _colorIndex,
          onSelected: (index) => setState(() => _colorIndex = index),
          size: 30,
          spacing: 10,
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon:
              _saving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.add_rounded, size: 19),
          label: Text(l10n.t('addTrack')),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected
                    ? AppColors.accent.withValues(alpha: 0.7)
                    : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? AppColors.accent : AppColors.textDim,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.text : AppColors.textDim,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
