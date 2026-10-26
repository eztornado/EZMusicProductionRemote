import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/project.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
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
    required this.onBypass,
    required this.onRemove,
  });

  final FxSlot slot;
  final VoidCallback onBypass;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
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
                color: slot.bypass ? AppColors.textFaint : AppColors.warning,
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
                    color: slot.bypass ? AppColors.textFaint : AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  slot.bypass ? l10n.t('bypass') : l10n.t('enabled'),
                  style: TextStyle(
                    fontSize: 9,
                    color:
                        slot.bypass ? AppColors.textFaint : AppColors.success,
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
        ],
      ),
    );
  }
}
