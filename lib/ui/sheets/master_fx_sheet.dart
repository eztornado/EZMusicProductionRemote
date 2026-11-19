import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/project.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/parameter_controls.dart';
import 'plugin_picker_sheet.dart';

Future<void> showMasterFxSheet(
  BuildContext context,
  RemoteController controller,
) {
  return showAppSheet<void>(
    context,
    maxWidth: 600,
    heightFactor: 0.86,
    builder: (ctx) => _MasterFxSheet(controller: controller),
  );
}

class _MasterFxSheet extends StatelessWidget {
  const _MasterFxSheet({required this.controller});

  final RemoteController controller;

  Future<void> _add(BuildContext context) async {
    final plugin = await showPluginPicker(
      context,
      controller,
      title: context.l10n.t('addEffect'),
    );
    if (plugin == null) return;
    await controller.addMasterFx(plugin.index);
  }

  Future<void> _remove(BuildContext context, FxSlot slot) async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('removeEffect'),
      message: l10n.t('removeEffectConfirm', {'name': slot.name}),
      confirmLabel: l10n.t('remove'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (ok) await controller.removeMasterFx(slot.index);
  }

  Future<void> _openParams(BuildContext context, FxSlot slot) {
    return showAppSheet<void>(
      context,
      maxWidth: 580,
      heightFactor: 0.9,
      builder: (ctx) => _MasterFxParamPane(controller: controller, slot: slot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: controller.project,
      builder: (context, project, _) {
        final slots = project?.masterFx ?? const <FxSlot>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            SheetHeader(
              title: l10n.t('masterFxTitle'),
              subtitle: l10n.t('masterFxNoParams'),
              icon: Icons.surround_sound_rounded,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                CountBadge(l10n.t('fxSlots', {'count': slots.length})),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.t('addEffect')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (slots.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 34,
                  horizontal: 20,
                ),
                decoration: panelDecoration(),
                child: EmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: l10n.t('noEffects'),
                  message: l10n.t('masterFxNoParams'),
                  compact: true,
                ),
              )
            else
              for (final slot in slots) ...[
                _MasterFxRow(
                  slot: slot,
                  onTap: () => _openParams(context, slot),
                  onBypass:
                      () => controller.setMasterFxBypass(
                        slot.index,
                        !slot.bypass,
                      ),
                  onRemove: () => _remove(context, slot),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _MasterFxRow extends StatelessWidget {
  const _MasterFxRow({
    required this.slot,
    required this.onTap,
    required this.onBypass,
    required this.onRemove,
  });

  final FxSlot slot;
  final VoidCallback onTap;
  final VoidCallback onBypass;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 7, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color:
                  slot.bypass
                      ? AppColors.border
                      : AppColors.warning.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      slot.bypass
                          ? AppColors.panelAlt
                          : AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${slot.index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color:
                        slot.bypass ? AppColors.textFaint : AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color:
                            slot.bypass ? AppColors.textFaint : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slot.bypass ? l10n.t('bypass') : l10n.t('enabled'),
                      style: TextStyle(
                        fontSize: 9,
                        color:
                            slot.bypass
                                ? AppColors.textFaint
                                : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              ToggleTag(
                label: 'B',
                active: slot.bypass,
                width: 26,
                height: 22,
                activeColor: AppColors.warning,
                tooltip: l10n.t('bypass'),
                onTap: onBypass,
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: l10n.t('removeEffect'),
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                color: AppColors.textFaint,
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Master inserts are addressed with `slotKind: 2` and `trackId: 0`, matching
/// the desktop remote protocol.
class _MasterFxParamPane extends StatefulWidget {
  const _MasterFxParamPane({required this.controller, required this.slot});

  final RemoteController controller;
  final FxSlot slot;

  @override
  State<_MasterFxParamPane> createState() => _MasterFxParamPaneState();
}

class _MasterFxParamPaneState extends State<_MasterFxParamPane> {
  int _refreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.surround_sound_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.slot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n.t('masterBus')} · ${l10n.t('parameters')}'
                      '${widget.slot.bypass ? ' · ${l10n.t('bypass')}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.t('reloadPlugins'),
                onPressed: () => setState(() => _refreshToken++),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              ToggleTag(
                label: 'B',
                active: widget.slot.bypass,
                width: 26,
                height: 22,
                activeColor: AppColors.warning,
                tooltip: l10n.t('bypass'),
                onTap:
                    () => widget.controller.setMasterFxBypass(
                      widget.slot.index,
                      !widget.slot.bypass,
                    ),
              ),
              IconButton(
                tooltip: l10n.t('close'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: FxParameterView(
            controller: widget.controller,
            trackId: 0,
            slotKind: 2,
            slotIndex: widget.slot.index,
            color: AppColors.warning,
            bypass: widget.slot.bypass,
            compact: true,
            refreshToken: _refreshToken,
          ),
        ),
      ],
    );
  }
}
