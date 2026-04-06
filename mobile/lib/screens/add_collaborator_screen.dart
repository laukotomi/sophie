import 'package:flutter/material.dart';
import 'package:sophie/models.dart';

class AddCollaboratorScreen extends StatefulWidget {
  final List<AppUser> users;

  const AddCollaboratorScreen({super.key, required this.users});

  @override
  State<AddCollaboratorScreen> createState() => _AddCollaboratorScreenState();
}

class _AddCollaboratorScreenState extends State<AddCollaboratorScreen> {
  final _formKey = GlobalKey<FormState>();
  AppUser? _selectedUser;
  String _right = 'view';

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((_selectedUser!, _right));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Collaborator'),
        actions: [TextButton(onPressed: _confirm, child: const Text('Add'))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<AppUser>(
                decoration: const InputDecoration(
                  labelText: 'User',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedUser,
                items: widget.users
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text('${u.name} (${u.email})'),
                      ),
                    )
                    .toList(),
                onChanged: (u) => setState(() => _selectedUser = u),
                validator: (value) =>
                    value == null ? 'Please select a user.' : null,
              ),
              const SizedBox(height: 24),
              Text('Rights', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'view',
                    label: Text('View'),
                    icon: Icon(Icons.visibility),
                  ),
                  ButtonSegment(
                    value: 'edit',
                    label: Text('Edit'),
                    icon: Icon(Icons.edit),
                  ),
                ],
                selected: {_right},
                onSelectionChanged: (s) => setState(() => _right = s.first),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
