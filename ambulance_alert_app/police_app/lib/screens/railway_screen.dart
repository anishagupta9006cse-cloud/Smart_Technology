import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../theme.dart';

/// Railway crossings near the post. Police mark the gate OPEN or CLOSED.
/// Ambulance routes avoid CLOSED gates automatically.
class RailwayScreen extends StatefulWidget {
  final LatLng near;
  final String by;
  const RailwayScreen({super.key, required this.near, required this.by});
  @override
  State<RailwayScreen> createState() => _RailwayScreenState();
}

class _RailwayScreenState extends State<RailwayScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _busy = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Api.I.raw('GET', '/api/railway', query: {
        'lat': widget.near.latitude.toString(),
        'lng': widget.near.longitude.toString(),
      });
      final l = r['crossings'];
      setState(() {
        _list = l is List ? l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
        _err = null;
      });
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(String id, String status) async {
    try {
      await Api.I.raw('POST', '/api/railway/$id/status', body: {'status': status, 'by': widget.by});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _addHere() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add railway crossing'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Name, example: Gate no. 12, Station Road')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('ADD')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await Api.I.raw('POST', '/api/railway',
          body: {'name': name, 'lat': widget.near.latitude, 'lng': widget.near.longitude});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Railway gates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHere,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('ADD AT MY POST'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Ambulance routes avoid CLOSED gates. CLOSED changes back to "unknown" after 12 minutes without an update.',
              style: TextStyle(color: Colors.black54)),
          if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (_err != null) Text(_err!, style: const TextStyle(color: Colors.red)),
          if (!_busy && _list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No railway crossing saved near you yet.')),
          for (final c in _list)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.train),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c['name']?.toString() ?? 'Crossing', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Chip(
                      label: Text((c['status']?.toString() ?? 'unknown').toUpperCase()),
                      backgroundColor: c['status'] == 'closed' ? Colors.red.shade100 : c['status'] == 'open' ? Colors.green.shade100 : Colors.grey.shade200,
                    ),
                  ]),
                  if (c['distance'] is num) Text('${((c['distance'] as num) / 1000).toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: FilledButton(style: solidButton(BtnColors.green), onPressed: () => _set(c['id'].toString(), 'open'), child: const Text('OPEN'))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(style: solidButton(BtnColors.red), onPressed: () => _set(c['id'].toString(), 'closed'), child: const Text('CLOSED'))),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}
