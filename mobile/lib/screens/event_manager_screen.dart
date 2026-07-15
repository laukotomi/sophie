import 'package:flutter/material.dart';
import 'package:sophie/services/base_event.dart';

class EventManagerScreen extends StatefulWidget {
  final List<BaseEvent> events;
  final Future Function(BaseEvent event) onDeleteEvent;

  const EventManagerScreen({
    super.key,
    required this.events,
    required this.onDeleteEvent,
  });

  @override
  State<EventManagerScreen> createState() => _EventManagerScreenState();
}

class _EventManagerScreenState extends State<EventManagerScreen> {
  late final List<BaseEvent> _events;

  @override
  void initState() {
    super.initState();
    _events = [...widget.events]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _deleteEvent(BaseEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event'),
        content: Text('Delete "${event.type}" from pending sync queue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.onDeleteEvent(event);
    if (!mounted) return;
    setState(() {
      _events.removeWhere((e) => e.eventId == event.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Event Manager')),
      body: _events.isEmpty
          ? const Center(child: Text('No pending events.'))
          : ListView.separated(
              itemCount: _events.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final event = _events[index];
                return ListTile(
                  title: Text(event.type),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete event',
                    onPressed: () => _deleteEvent(event),
                  ),
                );
              },
            ),
    );
  }
}
