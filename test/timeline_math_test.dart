import 'package:ezmusicproduction_remote/core/timeline_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dragClip', () {
    const original = ClipGeometry(start: 1, length: 2, offset: 0.5);

    test('moves a clip and snaps to the grid', () {
      final result = dragClip(
        original: original,
        mode: ClipDragMode.move,
        deltaSeconds: 0.4,
        snap: true,
        gridSeconds: 0.5,
      );

      expect(result.start, 1.5);
      expect(result.length, 2);
      expect(result.offset, 0.5);
    });

    test('keeps a free move when snapping is disabled', () {
      final result = dragClip(
        original: original,
        mode: ClipDragMode.move,
        deltaSeconds: 0.4,
        snap: false,
        gridSeconds: 0.5,
      );

      expect(result.start, closeTo(1.4, 0.0001));
    });

    test('trim start moves offset and preserves the clip end', () {
      final result = dragClip(
        original: original,
        mode: ClipDragMode.trimStart,
        deltaSeconds: 0.4,
        snap: true,
        gridSeconds: 0.5,
      );

      expect(result.start, 1.5);
      expect(result.length, 1.5);
      expect(result.offset, closeTo(1.0, 0.0001));
      expect(result.start + result.length, 3);
    });

    test('trim end never shrinks below the minimum length', () {
      final result = dragClip(
        original: original,
        mode: ClipDragMode.trimEnd,
        deltaSeconds: -5,
        snap: false,
        gridSeconds: 0.5,
        minLength: 0.25,
      );

      expect(result.length, 0.25);
      expect(result.start, 1);
    });

    test('never moves a clip before zero', () {
      final result = dragClip(
        original: original,
        mode: ClipDragMode.move,
        deltaSeconds: -20,
        snap: false,
        gridSeconds: 0.5,
      );

      expect(result.start, 0);
    });
  });

  test('timelineGridSeconds switches from beats to bars when zoomed out', () {
    expect(
      timelineGridSeconds(
        bpm: 120,
        numerator: 4,
        denominator: 4,
        pixelsPerSecond: 10,
      ),
      2,
    );
    expect(
      timelineGridSeconds(
        bpm: 120,
        numerator: 4,
        denominator: 4,
        pixelsPerSecond: 40,
      ),
      0.5,
    );
  });
}
