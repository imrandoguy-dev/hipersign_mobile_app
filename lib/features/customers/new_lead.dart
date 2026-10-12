import 'package:flutter/material.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';

/// Asks for the business / person name (pre-filled from Google when found) and creates a
/// CRM Lead for [phone]. Returns the lead, or null if cancelled or it failed.
Future<Party?> askNewLead(BuildContext context, Repository repo, String phone, {GooglePlace? google}) async {
  final controller = TextEditingController(text: google?.name ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New lead'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(phone, style: const TextStyle(color: HsColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Business or person name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        if (google?.address != null) ...[
          const SizedBox(height: 10),
          Text('From Google: ${google!.address}', style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create lead')),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return null;
  try {
    final lead = await repo.createLead(phone: phone, name: name, google: google);
    showSnack('Lead saved: ${lead.name}');
    return lead;
  } on ApiException catch (e) {
    showSnack(e.message, error: true);
    return null;
  }
}
