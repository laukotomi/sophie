import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/screens/notes_screen.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/services/storage.dart';

class _TestNoteEvent extends NoteEvent {
  _TestNoteEvent({this.syncDelay = Duration.zero, this.syncError});

  final Duration syncDelay;
  final Object? syncError;
  int applyCalls = 0;
  int syncCalls = 0;

  @override
  String get type => 'test_note_event';

  @override
  Future onApply(List<Note> items, Function setState) async {
    applyCalls++;
  }

  @override
  Future onSync(List<Note> items, Function setState) async {
    syncCalls++;
    if (syncDelay > Duration.zero) {
      await Future<void>.delayed(syncDelay);
    }
    if (syncError != null) {
      throw syncError!;
    }
  }
}

Widget _buildScreen() {
  return MaterialApp(
    home: NotesScreen(
      notes: [],
      offlineMode: false,
      usingCache: false,
      isActive: true,
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    NoteEventBus.instance.handlers.clear();
  });

  tearDown(() {
    NoteEventBus.instance.handlers.clear();
  });

  testWidgets('shows a green success icon briefly after successful sync', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScreen());

    final event = _TestNoteEvent(syncDelay: const Duration(milliseconds: 80));

    await NoteEventBus.instance.emit(event);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));

    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows sync error and does not show success icon on failure', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScreen());

    final event = _TestNoteEvent(syncError: Exception('boom'));

    await NoteEventBus.instance.emit(event);
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.textContaining('Error syncing note changes:'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('offline_note_events'),
      isNotNull,
    );
  });

  testWidgets('same event object syncs only once even if emitted twice', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScreen());

    final event = _TestNoteEvent(syncDelay: const Duration(milliseconds: 20));

    await NoteEventBus.instance.emit(event);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    await NoteEventBus.instance.emit(event);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(event.applyCalls, 1);
    expect(event.syncCalls, 1);
  });
}
