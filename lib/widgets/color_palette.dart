import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ColorPalettePicker extends StatelessWidget {
  const ColorPalettePicker({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.size = 28,
    this.spacing = 8,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double size;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (var index = 0; index < AppColors.trackPalette.length; index++)
          Semantics(
            button: true,
            selected: selectedIndex == index,
            child: InkWell(
              onTap: () => onSelected(index),
              borderRadius: BorderRadius.circular(size),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppColors.track(index),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        selectedIndex == index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.12),
                    width: selectedIndex == index ? 2.2 : 1,
                  ),
                  boxShadow:
                      selectedIndex == index
                          ? [
                            BoxShadow(
                              color: AppColors.track(
                                index,
                              ).withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ]
                          : null,
                ),
                child:
                    selectedIndex == index
                        ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                        : null,
              ),
            ),
          ),
      ],
    );
  }
}
