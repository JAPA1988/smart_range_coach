import 'package:flutter/material.dart';

import '../models/reference_swing.dart';
import '../services/reference_swing_service.dart';

class ReferenceSwingsScreen extends StatefulWidget {
  const ReferenceSwingsScreen({super.key});

  @override
  State<ReferenceSwingsScreen> createState() => _ReferenceSwingsScreenState();
}

class _ReferenceSwingsScreenState extends State<ReferenceSwingsScreen> {
  final _service = ReferenceSwingService();
  List<ReferenceSwing>? _swings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSwings();
  }

  Future<void> _loadSwings() async {
    setState(() => _loading = true);
    try {
      final swings = await _service.loadAllSwings();
      setState(() {
        _swings = swings;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Reference Swings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _swings == null || _swings!.isEmpty
              ? const Center(child: Text('No swings loaded'))
              : ListView.builder(
                  itemCount: _swings!.length,
                  itemBuilder: (context, index) {
                    final swing = _swings![index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(swing.golferName[0]),
                      ),
                      title: Text(swing.golferName),
                      subtitle: Text(swing.clubType),
                      trailing: Text('${swing.keyPositions.length} positions'),
                    );
                  },
                ),
    );
  }
}
