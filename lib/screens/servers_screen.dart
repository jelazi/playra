import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/servers/servers_cubit.dart';
import '../models/server_connection.dart';
import 'server_browser_screen.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('servers.title'.tr())),
      floatingActionButton: FloatingActionButton(onPressed: () => _editServer(context, null), child: const Icon(Icons.add)),
      body: BlocBuilder<ServersCubit, ServersState>(
        builder: (context, state) {
          if (state.servers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.dns, size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('servers.empty'.tr(), textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: state.servers.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final s = state.servers[i];
              return ListTile(
                leading: Icon(_iconFor(s.type)),
                title: Text(s.name),
                subtitle: Text('${s.type.name.toUpperCase()} · ${s.host}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _editServer(context, s);
                    if (v == 'delete') context.read<ServersCubit>().delete(s.id);
                  },
                  itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text('servers.edit'.tr())), PopupMenuItem(value: 'delete', child: Text('servers.delete'.tr()))],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ServerBrowserScreen(server: s))),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(ServerType t) {
    switch (t) {
      case ServerType.smb:
        return Icons.lan;
      case ServerType.http:
        return Icons.public;
      case ServerType.ftp:
        return Icons.cloud;
    }
  }

  Future<void> _editServer(BuildContext context, ServerConnection? existing) async {
    final cubit = context.read<ServersCubit>();
    final result = await showDialog<ServerConnection>(
      context: context,
      builder: (_) => _ServerEditDialog(initial: existing),
    );
    if (result != null) {
      await cubit.save(result);
    }
  }
}

class _ServerEditDialog extends StatefulWidget {
  final ServerConnection? initial;
  const _ServerEditDialog({this.initial});

  @override
  State<_ServerEditDialog> createState() => _ServerEditDialogState();
}

class _ServerEditDialogState extends State<_ServerEditDialog> {
  late ServerType _type;
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _share = TextEditingController();
  final _path = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _type = i?.type ?? ServerType.smb;
    _name.text = i?.name ?? '';
    _host.text = i?.host ?? '';
    _port.text = i?.port?.toString() ?? '';
    _share.text = i?.share ?? '';
    _path.text = i?.path ?? '';
    _user.text = i?.username ?? '';
    _pass.text = i?.password ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'servers.add'.tr() : 'servers.edit'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ServerType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: 'servers.type'.tr()),
              items: ServerType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(),
              onChanged: (v) => setState(() => _type = v ?? ServerType.smb),
            ),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: 'servers.name'.tr()),
            ),
            TextField(
              controller: _host,
              decoration: InputDecoration(labelText: 'servers.host'.tr()),
            ),
            TextField(
              controller: _port,
              decoration: InputDecoration(labelText: 'servers.port'.tr()),
              keyboardType: TextInputType.number,
            ),
            if (_type == ServerType.smb)
              TextField(
                controller: _share,
                decoration: InputDecoration(labelText: 'servers.share'.tr()),
              ),
            TextField(
              controller: _path,
              decoration: InputDecoration(labelText: 'servers.path'.tr()),
            ),
            TextField(
              controller: _user,
              decoration: InputDecoration(labelText: 'servers.username'.tr()),
            ),
            TextField(
              controller: _pass,
              decoration: InputDecoration(labelText: 'servers.password'.tr()),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('common.cancel'.tr())),
        FilledButton(
          onPressed: () {
            if (_host.text.trim().isEmpty || _name.text.trim().isEmpty) return;
            final id = widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
            Navigator.of(context).pop(
              ServerConnection(
                id: id,
                name: _name.text.trim(),
                type: _type,
                host: _host.text.trim(),
                port: int.tryParse(_port.text.trim()),
                share: _share.text.trim().isEmpty ? null : _share.text.trim(),
                path: _path.text.trim().isEmpty ? null : _path.text.trim(),
                username: _user.text.trim().isEmpty ? null : _user.text.trim(),
                password: _pass.text.isEmpty ? null : _pass.text,
              ),
            );
          },
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
