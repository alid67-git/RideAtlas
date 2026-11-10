import 'dart:async';

import 'package:flutter/material.dart';

import '../gopro/client.dart';
import '../gopro/models.dart';

/// View / select / delete / add saved GoPro cameras.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.client});

  final GoProBleClient client;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  GoProBleClient get _client => widget.client;
  bool _busy = false;
  String? _message;

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
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
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

  Future<void> _forget(SavedGoProDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kamerayı sil'),
        content: Text(
          '${device.name} kayıtlardan kaldırılsın mı?\n'
          'Bluetooth eşleştirmesi de silinmeye çalışılır.',
        ),
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
    if (ok != true || !mounted) return;
    await _run(() => _client.forgetSavedDevice(device.remoteId));
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF151920),
      builder: (ctx) {
        return _AddCameraSheet(
          client: _client,
          onSaved: () {
            Navigator.pop(ctx);
            setState(() => _message = 'Kamera eklendi');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = _client.savedDevices;
    final selectedId = _client.selectedSaved?.remoteId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kameralar'),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _openAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('Kamera ekle'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _message!,
                style: TextStyle(color: cs.primary),
              ),
            ),
          Expanded(
            child: saved.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Kayıtlı kamera yok.\n'
                        '“Kamera ekle” ile yakındaki GoPro’yu tara.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: saved.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final device = saved[index];
                      final selected = device.remoteId == selectedId;
                      return Material(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.14)
                            : const Color(0xFF1A1F27),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _busy
                              ? null
                              : () => _run(
                                    () => _client
                                        .selectSavedDevice(device.remoteId),
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: selected
                                      ? cs.primary
                                      : cs.onSurface.withValues(alpha: 0.45),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selected
                                            ? 'Seçili · ${device.remoteId}'
                                            : device.remoteId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurface
                                                  .withValues(alpha: 0.55),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Sil',
                                  onPressed:
                                      _busy ? null : () => _forget(device),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: cs.error.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
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

class _AddCameraSheet extends StatefulWidget {
  const _AddCameraSheet({
    required this.client,
    required this.onSaved,
  });

  final GoProBleClient client;
  final VoidCallback onSaved;

  @override
  State<_AddCameraSheet> createState() => _AddCameraSheetState();
}

class _AddCameraSheetState extends State<_AddCameraSheet> {
  GoProBleClient get _client => widget.client;
  bool _scanning = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClient);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScan());
    });
  }

  void _onClient() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_client.stopScan());
    _client.removeListener(_onClient);
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _client.ensureAdapterOn();
      await _client.startScan(timeout: const Duration(seconds: 8));
      // Keep sheet "scanning" until timeout / stop.
      await Future<void>.delayed(const Duration(seconds: 8));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _save(GoProDeviceInfo info) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.stopScan();
      await _client.saveDevice(
        remoteId: info.remoteId,
        name: info.name,
        select: true,
      );
      // Connect once while adding so Android completes pairing before KAYIT.
      // Ignore shutter — user only asked to register the camera.
      try {
        await _client.connect(
          info,
          retries: 4,
          fastRecord: true,
          shutterOnConnect: false,
        );
      } catch (e) {
        // Still keep the saved entry; user can retry from the home screen.
        debugPrint('add-connect: $e');
        if (mounted) {
          final msg = _client.error ??
              (e.toString().startsWith('Bad state: ')
                  ? e.toString().substring('Bad state: '.length)
                  : e.toString());
          setState(() {
            _error =
                'Kaydedildi. İlk bağlanma olmadı — ana ekranda KAYIT veya '
                '“Sadece bağlan” dene.\n$msg';
          });
        }
        // Close after a beat so the list shows the new saved camera.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) widget.onSaved();
        return;
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final found = _client.discovered;
    final height = MediaQuery.sizeOf(context).height * 0.62;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Yakındaki kameralar',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _scanning
                  ? 'Taranıyor… GoPro’yu aç / yakına getir.'
                  : 'Seçince kaydedilir ve eşleştirme için bağlanır.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: found.isEmpty
                  ? Center(
                      child: _scanning
                          ? const CircularProgressIndicator()
                          : Text(
                              'GoPro bulunamadı.\nTekrar dene.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                    )
                  : ListView.separated(
                      itemCount: found.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final d = found[index];
                        final already = _client.savedDevices
                            .any((s) => s.remoteId == d.remoteId);
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: const Color(0xFF1A1F27),
                          leading: const Icon(Icons.videocam_outlined),
                          title: Text(d.name),
                          subtitle: Text(
                            [
                              if (d.rssi != null) '${d.rssi} dBm',
                              d.remoteId,
                              if (already) 'zaten kayıtlı',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  already ? Icons.check : Icons.add,
                                  color: cs.primary,
                                ),
                          onTap: _saving ? null : () => _save(d),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _scanning || _saving ? null : _startScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden tara'),
            ),
          ],
        ),
      ),
    );
  }
}
