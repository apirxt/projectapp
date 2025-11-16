import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class BookingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> booking;
  const BookingDetailScreen({super.key, required this.booking});

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '-';
    final d = ts.toDate().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final String slotId = booking['slotId'] ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(booking['slotName'] ?? 'รายละเอียดการจอง'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('parking_slots')
            .doc(slotId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('ไม่พบข้อมูลที่จอดรถ'));
          }
          final data = snap.data!.data() as Map<String, dynamic>;
          final imageUrl = (data['image_url'] ?? '') as String;
          final type = (data['type'] ?? '-') as String;
          final carCount = data['car_count'] ?? 0;
          final carPrice = data['car_price'] ?? 0;
          final bikeCount = data['bike_count'] ?? 0;
          final bikePrice = data['bike_price'] ?? 0;
          final serviceDate = (data['service_date'] ?? '-') as String;
          final serviceTime = (data['service_time'] ?? '-') as String;
          final cctvUrl = (data['cctv_url'] ?? '').toString();
          final GeoPoint? gp = data['location'] as GeoPoint?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl.isNotEmpty)
                  Center(
                    child: Image.network(imageUrl,
                        height: 200, width: double.infinity, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 10),
                Text('ที่จอด: ${data['name'] ?? '-'}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('ประเภท: $type'),
                Text('จำนวนรถยนต์: $carCount'),
                Text('ราคาที่จอดรถยนต์: $carPrice บาท/ชั่วโมง'),
                Text('จำนวนมอเตอร์ไซค์: $bikeCount'),
                Text('ราคาที่จอดมอเตอร์ไซค์: $bikePrice บาท/ชั่วโมง'),
                const SizedBox(height: 6),
                Text('วันที่เปิดให้บริการ: $serviceDate'),
                Text('เวลาที่เปิดให้บริการ: $serviceTime'),
                const SizedBox(height: 16),
                if (gp != null) ...[
                  const Text('ตำแหน่งที่จอดรถ:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                          target: LatLng(gp.latitude, gp.longitude), zoom: 15),
                      markers: {
                        Marker(
                          markerId: const MarkerId('parking_location'),
                          position: LatLng(gp.latitude, gp.longitude),
                          infoWindow:
                              InfoWindow(title: data['name'] ?? 'ที่จอดรถ'),
                        )
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // CCTV แสดงเฉพาะในหน้าการจองเท่านั้น
                if (cctvUrl.isNotEmpty) ...[
                  const Text('กล้องวงจรปิด (CCTV):',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final uri = Uri.parse(cctvUrl);
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.videocam),
                      label: const Text('เปิดกล้องวงจรปิด'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Divider(),
                const SizedBox(height: 8),
                const Text('ข้อมูลการจอง',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('ผู้จอง: ${booking['name'] ?? '-'}'),
                Text('โทร: ${booking['phone'] ?? '-'}'),
                if (booking['bookingDate'] != null)
                  Text(
                      'วันที่จอง: ${_fmtTs(booking['bookingDate'] as Timestamp?)}'),
                Text('สถานะ: ${booking['status'] ?? 'pending'}'),
                Text(
                    'สร้างเมื่อ: ${_fmtTs(booking['createdAt'] as Timestamp?)}'),
                const SizedBox(height: 16),
                if ((booking['imageUrl'] ?? '').toString().isNotEmpty) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('สลิปการชำระเงิน',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // แสดงรูปสลิป และให้ซูม/แพนได้
                  Container(
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image.network(
                          booking['imageUrl'],
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
