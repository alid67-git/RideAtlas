import 'dart:async';

import 'package:flutter/material.dart';

import '../insta360/client.dart';
import '../insta360/models.dart';

/// View / select / delete / add saved Insta360 cameras.
class InstaDevicesPage extends StatefulWidget {
  const InstaDevicesPage({super.key, required this.client});

  final Insta360Client client;

  @override
  State<InstaDevicesPage> createState() => _InstaDevicesPageState();
}

class _InstaDevicesPageState extends State<InstaDevicesPage> {
  Insta360Client get _client => widget.client;
  bool _busy = false;
  String? _message;
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClient);
    unawaited(_client.ensurePrefsLoaded());
  }

  void _onClient() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _client.removeListener(_onClient);
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    _client.beginOperation();
    try {
      await action();
    } on Insta360CancelledException {
      if (mounted) setState(() => _message = 'İptal edildi');
    } catch (e) {
      final raw = e.toString();
      setState(() {
        _message = raw.startsWith('Bad state: ')
            ? raw.substring('Bad state: '.length)
            : raw;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget(SavedInsta360Device device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kamerayı sil'),
        content: Text('${device.name} (${device.serial}) kaldırılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _client.forgetDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = _client.savedDevices;
    final selected = _client.selectedSerial;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insta360 kameralar'),
        actions: [
          if (_busy)
            IconButton(
              tooltip: 'İptal',
              onPressed: () => _client.cancelOperation(),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Uyandırma için kameranın 6 karakterlik seri numarası gerekir '
            '(ör. ekrandaki ad: X4 34UQG5 → 34UQG5).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 16),
          Text(
            'Kayıtlı',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (saved.isEmpty)
            Text(
              'Henüz kamera yok.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
            )
          else
            ...saved.map((d) {
              final isSel = d.serial == selected;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: const Color(0xFF4CC9F0),
                ),
                title: Text(d.name),
                subtitle: Text('Seri ${d.serial}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _forget(d),
                ),
                onTap: _busy
                    ? null
                    : () async {
                        await _client.selectDevice(d);
                        if (context.mounted) Navigator.pop(context);
                      },
              );
            }),
          const SizedBox(height: 20),
          Text(
            'Manuel ekle',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _manualCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'X4 34UQG5 veya 34UQG5',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await _client.saveManual(nameOrSerial: _manualCtrl.text);
                      if (context.mounted) Navigator.pop(context);
                    }),
            icon: const Icon(Icons.add),
            label: const Text('Kaydet'),
          ),
          const SizedBox(height: 24),
          Text(
            'Yakındakiler (kamera açıkken tara)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      setState(() => _message = 'Taranıyor…');
                      await _client.startScan();
                      setState(() {
                        _message = _client.discovered.isEmpty
                            ? 'Kamera bulunamadı (açık ve BLE görünür olmalı).'
                            : null;
                      });
                    }),
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Tara'),
          ),
          const SizedBox(height: 8),
          ..._client.discovered.map((hit) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.videocam_outlined,
                  color: Color(0xFF4CC9F0)),
              title: Text(hit.name),
              subtitle: Text('Seri ${hit.serial} · ${hit.rssi ?? '—'} dBm'),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await _client.saveFromScan(hit);
                          if (context.mounted) Navigator.pop(context);
                        }),
                child: const Text('Ekle'),
              ),
            );
          }),
        ],
      ),
    );
  }
}
