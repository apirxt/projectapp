import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParkingDetail extends StatefulWidget {
  final Map<String, dynamic> parkingData;
  final String docId; // id เอกสาร Firestore ของที่จอดคันนี้

  const ParkingDetail(
      {super.key, required this.parkingData, required this.docId});

  @override
  State<ParkingDetail> createState() => _ParkingDetailState();
}

class _ParkingDetailState extends State<ParkingDetail> {
  int _selectedStars = 0;
  final TextEditingController _commentController = TextEditingController();
  late final PageController _pageController;

  @override
  void dispose() {
    _commentController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  Widget build(BuildContext context) {
    final parkingData = widget.parkingData;
    final location = parkingData['location'];
    // CCTV ถูกย้ายไปแสดงในหน้ารายละเอียดการจองเท่านั้น

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
              // แกลเลอรีภาพ
              Builder(builder: (context) {
                final List<String> imgs = ((parkingData['image_urls'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    <String>[]);
                final String single =
                    (parkingData['image_url'] ?? '').toString();
                if (imgs.isEmpty && single.isNotEmpty) {
                  imgs.add(single);
                }
                if (imgs.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: imgs.length,
                    physics: const PageScrollPhysics(),
                    allowImplicitScrolling: true,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Image.network(
                        imgs[i],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 10),
              Text(
                'ที่จอดรถ: ${parkingData['name'] ?? 'ไม่มีข้อมูล'}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('ประเภท: ${parkingData['type'] ?? 'ไม่มีข้อมูล'}\n'),
              const SizedBox(height: 5),
              Builder(builder: (_) {
                final t = (parkingData['type'] ?? '').toString();
                final List<Widget> children = [];
                if (t.contains('รถยนต์')) {
                  children.add(
                      Text('จำนวนรถยนต์: ${parkingData['car_count'] ?? 0}'));
                  children.add(const SizedBox(height: 5));
                  children.add(Text(
                      'ราคาที่จอดรถยนต์: ${parkingData['car_price'] ?? 0} บาท/ชั่วโมง\n'));
                }
                if (t.contains('มอเตอร์ไซค์')) {
                  children.add(Text(
                      'จำนวนมอเตอร์ไซค์: ${parkingData['bike_count'] ?? 0}'));
                  children.add(const SizedBox(height: 5));
                  children.add(Text(
                      'ราคาที่จอดมอเตอร์ไซค์: ${parkingData['bike_price'] ?? 0} บาท/ชั่วโมง\n'));
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children);
              }),
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
              // เพิ่ม "รายละเอียดเพิ่มเติม" ใต้แผนที่
              const Text(
                'รายละเอียดเพิ่มเติม:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(parkingData['details'] ?? 'ไม่มีข้อมูลเพิ่มเติม'),

              // ย้ายส่วนให้คะแนนขึ้นมาก่อนรายการความคิดเห็น
              const SizedBox(height: 16),
              const Text(
                'แสดงความคิดเห็น/ให้คะแนนดาว',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
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

              const SizedBox(height: 20),
              // สรุปคะแนน + ความคิดเห็น/คะแนนดาว (พร้อมเลื่อนดูได้)
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
                        docs.map((d) => (d['rating'] ?? 0).toDouble()).toList();
                    avg = ratings.reduce((a, b) => a + b) / ratings.length;
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (docs.isNotEmpty)
                        Row(
                          children: [
                            _buildStarRow(avg.round()),
                            const SizedBox(width: 8),
                            Text(
                                '${avg.toStringAsFixed(1)} จาก ${docs.length} รีวิว'),
                          ],
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'ความคิดเห็น/คะแนนดาว',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      if (docs.isEmpty)
                        const Text('ยังไม่มีความคิดเห็น')
                      else
                        SizedBox(
                          height: 240,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: docs.length,
                            itemBuilder: (context, idx) {
                              final d = docs[idx];
                              final rating = (d['rating'] ?? 0).toInt();
                              final comment = (d['comment'] ?? '') as String;
                              final ts =
                                  (d['timestamp'] as Timestamp?)?.toDate();
                              return Card(
                                color: Colors.black12,
                                child: ListTile(
                                  dense: true,
                                  leading: _buildStarRow(rating, size: 16),
                                  title: Text(comment.isEmpty ? '-' : comment),
                                  subtitle: ts != null
                                      ? Text('${ts.toLocal()}')
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
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
      final slots = FirebaseFirestore.instance.collection('parking_slots');
      final slotRef = slots.doc(widget.docId);

      // บันทึกรีวิว (การรวมคะแนนจะทำอัตโนมัติด้วย Cloud Functions trigger)
      await slotRef.collection('reviews').add(review);
      if (!mounted) {
        return; // กันการเรียกเมธอดของ State (เช่น setState) ถ้า widget ถูกถอดแล้ว
      }
      if (!context.mounted) {
        return; // กันการใช้งาน BuildContext ถ้า widget ถูกถอดแล้ว
      }
      _commentController.clear();
      setState(() => _selectedStars = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งรีวิวเรียบร้อย')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถส่งรีวิว: $e')),
        );
      }
    }
  }
}
