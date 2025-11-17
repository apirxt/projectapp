import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'booking_detail.dart';

class BookingListScreen extends StatelessWidget {
  const BookingListScreen({super.key});

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '-';
    final d = ts.toDate().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtDateOnly(Timestamp? ts) {
    if (ts == null) return '-';
    final d = ts.toDate().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _statusTh(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'pending':
        return 'รอตรวจสอบ';
      case 'approved':
      case 'confirmed':
        return 'อนุมัติ';
      case 'rejected':
        return 'ปฎิเสธ';
      default:
        return '-';
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'pending':
        return Colors.orange.shade300;
      case 'approved':
      case 'confirmed':
        return Colors.green.shade400;
      case 'rejected':
        return Colors.red.shade300;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('กรุณาเข้าสู่ระบบ')),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('user_bookings')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('จองที่จอดรถของฉัน'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // แสดงรายละเอียด error เพื่อช่วยสร้างดัชนีหรือแก้สิทธิ์
            final err = snapshot.error;
            // ignore: avoid_print
            print('BOOKINGS STREAM ERROR: $err');
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('เกิดข้อผิดพลาด', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 8),
                  Text('หากมีลิงก์สร้างดัชนี (index) ใน Log ให้กดเพื่อสร้าง',
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีการจอง'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data() as Map<String, dynamic>;
              final slotName = (d['slotName'] ?? '-') as String;
              final name = (d['name'] ?? '-') as String;
              final phone = (d['phone'] ?? '-') as String;
              final status = (d['status'] ?? 'pending') as String;
              final imageUrl = (d['imageUrl'] ?? '') as String;
              final createdAt = d['createdAt'] as Timestamp?;
              final bookingDate = d['bookingDate'] as Timestamp?;
              final vehicleType = (d['vehicleType'] ?? '-') as String;
              final vehicleLabel = vehicleType == 'car'
                  ? 'รถยนต์'
                  : vehicleType == 'bike'
                      ? 'รถมอเตอร์ไซค์'
                      : '-';

              return ListTile(
                leading: imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(imageUrl,
                            width: 48, height: 48, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.receipt_long),
                title: Text(slotName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'ผู้จอง: $name\nโทร: $phone\nประเภทรถ: $vehicleLabel\nวันที่จอง: ${_fmtDateOnly(bookingDate)}\nสร้างเมื่อ: ${_fmtTs(createdAt)}'),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusTh(status),
                    style: const TextStyle(color: Colors.black, fontSize: 12),
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BookingDetailScreen(booking: d, bookingId: doc.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
