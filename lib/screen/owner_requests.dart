import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class OwnerRequestsScreen extends StatefulWidget {
  const OwnerRequestsScreen({super.key});

  @override
  State<OwnerRequestsScreen> createState() => _OwnerRequestsScreenState();
}

class _OwnerRequestsScreenState extends State<OwnerRequestsScreen> {
  String _status = 'pending';
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int? _nextCursor;

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (reset) _nextCursor = null;
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('listOwnerBookings');
      final resp = await fn.call({
        'status': _status,
        'limit': 20,
        if (_nextCursor != null) 'cursor': _nextCursor,
      });
      final data = (resp.data as Map?) ?? {};
      final List list = (data['bookings'] as List?) ?? [];
      setState(() {
        if (reset) _items = [];
        _items.addAll(list
            .cast<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList());
        _nextCursor = data['nextCursor'] as int?;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดคำขอไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _viewSlip(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.all(8),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.9,
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(String bookingId, bool approve) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('decideBooking');
      await fn.call({'bookingId': bookingId, 'approve': approve});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'อนุมัติแล้ว' : 'ปฏิเสธแล้ว')),
        );
      }
      await _load(reset: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ทำรายการไม่สำเร็จ: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser != null) {
      _load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('คำขอจองจากผู้ใช้'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(reset: true),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('คำขอใหม่'),
                  selected: _status == 'pending',
                  onSelected: (v) {
                    setState(() => _status = 'pending');
                    _load(reset: true);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('ทั้งหมด'),
                  selected: _status == 'all',
                  onSelected: (v) {
                    setState(() => _status = 'all');
                    _load(reset: true);
                  },
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length + (_nextCursor != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  // load more
                  _load();
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final b = _items[index];
                final String slotName = (b['slotName'] ?? '-') as String;
                final String renter = (b['name'] ?? '-') as String;
                final String phone = (b['phone'] ?? '-') as String;
                final String status = (b['status'] ?? 'pending') as String;
                final String vehicleType = (b['vehicleType'] ?? '-') as String;
                final String vehicleLabel = vehicleType == 'car'
                    ? 'รถยนต์'
                    : vehicleType == 'bike'
                        ? 'รถมอเตอร์ไซค์'
                        : '-';
                final String? imageUrl = b['imageUrl'] as String?;
                final DateTime? day = b['bookingDate'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(b['bookingDate'])
                        .toLocal()
                    : null;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text(slotName),
                    subtitle: Text(
                        'ผู้จอง: $renter  โทร: $phone\nประเภทรถ: $vehicleLabel\nวันที่: ${day != null ? '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}' : '-'}\nสถานะ: $status'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          TextButton(
                            onPressed: () => _viewSlip(imageUrl),
                            child: const Text('ดูสลิป'),
                          ),
                        if (status == 'pending') ...[
                          TextButton(
                            onPressed: () => _decide(b['id'] as String, false),
                            child: const Text('ปฏิเสธ'),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () => _decide(b['id'] as String, true),
                            child: const Text('อนุมัติ'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
