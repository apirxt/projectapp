import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParkingDetail extends StatefulWidget {
  final Map<String, dynamic> parkingData;
  final String docId; // Firestore document id for this parking slot

  const ParkingDetail(
      {super.key, required this.parkingData, required this.docId});

  @override
  State<ParkingDetail> createState() => _ParkingDetailState();
}

class _ParkingDetailState extends State<ParkingDetail> {
  int _selectedStars = 0;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parkingData = widget.parkingData;
    final location = parkingData['location'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(parkingData['name'] ?? 'รายละเอียดที่จอดรถ'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parkingData['image_url'] != null &&
                  parkingData['image_url'].isNotEmpty)
                Center(
                  child: Image.network(
                    parkingData['image_url'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'ที่จอดรถ: ${parkingData['name'] ?? 'ไม่มีข้อมูล'}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('ประเภท: ${parkingData['type'] ?? 'ไม่มีข้อมูล'}\n'),
              const SizedBox(height: 5),
              Text('จำนวนรถยนต์: ${parkingData['car_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text(
                  'ราคาที่จอดรถยนต์: ${parkingData['car_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text('จำนวนมอเตอร์ไซค์: ${parkingData['bike_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text(
                  'ราคาที่จอดมอเตอร์ไซค์: ${parkingData['bike_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text(
                  'วันที่เปิดให้บริการ: ${parkingData['service_date'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 5),
              Text(
                  'เวลาที่เปิดให้บริการ: ${parkingData['service_time'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 20),
              if (location != null) ...[
                const Text(
                  'ตำแหน่งที่จอดรถ:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 200,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(location.latitude, location.longitude),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('parking_location'),
                        position: LatLng(location.latitude, location.longitude),
                        infoWindow: InfoWindow(
                            title: parkingData['name'] ?? 'ที่จอดรถ'),
                      ),
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    mapType: MapType.normal,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // เพิ่ม "รายละเอียดเพิ่มเติม" ใต้แผนที่ และก่อนส่วนรีวิว
              const Text(
                'รายละเอียดเพิ่มเติม:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(parkingData['details'] ?? 'ไม่มีข้อมูลเพิ่มเติม'),
              const SizedBox(height: 20),
              // Rating summary (average and count)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('parking_slots')
                    .doc(widget.docId)
                    .collection('reviews')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Text('ไม่สามารถโหลดรีวิวได้');
                  }
                  final docs = snapshot.data?.docs ?? [];
                  double avg = 0;
                  if (docs.isNotEmpty) {
                    final ratings =
                        docs.map((d) => (d["rating"] ?? 0).toDouble()).toList();
                    avg = ratings.reduce((a, b) => a + b) / ratings.length;
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildStarRow(avg.round()),
                          const SizedBox(width: 8),
                          Text(
                            docs.isEmpty
                                ? 'ยังไม่มีการให้คะแนน'
                                : '${avg.toStringAsFixed(1)} จาก ${docs.length} รีวิว',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'รีวิวล่าสุด',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      if (docs.isEmpty)
                        const Text('ยังไม่มีความคิดเห็น')
                      else
                        Column(
                          children: docs.take(5).map((d) {
                            final rating = (d['rating'] ?? 0).toInt();
                            final comment = (d['comment'] ?? '') as String;
                            final ts = (d['timestamp'] as Timestamp?)?.toDate();
                            return Card(
                              color: Colors.black12,
                              child: ListTile(
                                dense: true,
                                leading: _buildStarRow(rating, size: 16),
                                title: Text(comment.isEmpty ? '-' : comment),
                                subtitle:
                                    ts != null ? Text('${ts.toLocal()}') : null,
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),
              const Text(
                'ให้คะแนนและแสดงความคิดเห็น',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // Star rating input
              Row(
                children: List.generate(5, (i) {
                  final starIndex = i + 1;
                  final filled = _selectedStars >= starIndex;
                  return IconButton(
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () => setState(() => _selectedStars = starIndex),
                  );
                }),
              ),
              TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'แสดงความคิดเห็น (ไม่บังคับ)',
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('ส่งรีวิว'),
                  onPressed: _submitReview,
                ),
              ),
              // เดิมส่วน "รายละเอียดเพิ่มเติม" อยู่ท้ายสุด จึงย้ายขึ้นไปแล้ว
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarRow(int stars, {double size = 20}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < stars;
        return Icon(filled ? Icons.star : Icons.star_border,
            color: Colors.amber, size: size);
      }),
    );
  }

  Future<void> _submitReview() async {
    if (_selectedStars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาให้คะแนนอย่างน้อย 1 ดาว')),
      );
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนส่งรีวิว')),
        );
        return;
      }
      final review = {
        'userId': user.uid,
        'rating': _selectedStars,
        'comment': _commentController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      };
      final ref = FirebaseFirestore.instance
          .collection('parking_slots')
          .doc(widget.docId)
          .collection('reviews');
      await ref.add(review);

      _commentController.clear();
      setState(() => _selectedStars = 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งรีวิวเรียบร้อย')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถส่งรีวิว: $e')),
        );
      }
    }
  }
}
