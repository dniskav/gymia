import 'package:flutter/material.dart';
import '../data/chat_archive_store.dart';
import '../data/ai_client.dart';
import 'chat_message.dart';

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({
    super.key,
    required this.store,
    required this.entries,
  });
  final ChatArchiveStore store;
  final List<Map<String, dynamic>> entries;
  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  String query = '';
  String? error;
  Future<void> open(Map<String, dynamic> entry) async {
    try {
      final document = await widget.store.read(entry['id'] as String);
      if (!mounted) return;
      final selected = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => _ArchiveDetail(document: document)),
      );
      if (selected != null && mounted) Navigator.pop(context, selected);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo recuperar el chat. El archivo se conserva.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chats archivados')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por título o resumen',
            ),
            onChanged: (text) => setState(() => query = text.toLowerCase()),
          ),
        ),
        if (error != null) Text(error!),
        Expanded(
          child: ListView(
            children: [
              if (widget.entries.isEmpty)
                const ListTile(title: Text('Todavía no hay chats archivados.')),
              for (final entry in widget.entries.reversed)
                if ('${entry['title']} ${entry['summary']}'
                    .toLowerCase()
                    .contains(query))
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(entry['title'] as String),
                    subtitle: Text(
                      '${(entry['createdAt'] as String).substring(0, 10)} · ${entry['messageCount']} mensajes${entry['automatic'] == true ? ' · archivado por el asistente' : ''}',
                    ),
                    onTap: () => open(entry),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ArchiveDetail extends StatelessWidget {
  const _ArchiveDetail({required this.document});
  final Map<String, dynamic> document;
  @override
  Widget build(BuildContext context) {
    final rows = document['messages'] as List;
    return Scaffold(
      appBar: AppBar(title: Text(document['title'] as String)),
      body: Column(
        children: [
          if ((document['summary'] as String).isNotEmpty)
            ExpansionTile(
              title: const Text('Resumen de continuidad'),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .25,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      '${document['summary']}${document['automatic'] == true ? '\n\nMotivo del asistente: ${document['reason']}' : ''}',
                    ),
                  ),
                ),
              ],
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, document['id'] as String),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Consultar desde el chat'),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final message = AiMessage.fromStorage(
                  Map<String, dynamic>.from(rows[index] as Map),
                );
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.role == 'user' ? 'Tú' : 'Asistente',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ChatMessageBody(
                          text: message.text,
                          assistant: message.role == 'assistant',
                        ),
                        if (message.attachment != null)
                          Text(
                            'Adjunto conservado: ${message.attachment!.name}',
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
