import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screen/parking_detail.dart';

class myhome extends StatefulWidget {
  const myhome({super.key});

  @override
  State<myhome> createState() => _myhomeState();
}

class _myhomeState extends State<myhome> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('เลือกที่จอดรถ'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'ค้นหาที่จอดรถ',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('parking_slots')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('เกิดข้อผิดพลาด'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name']?.toString().toLowerCase() ?? '';
                  return name.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อมูลที่จอดรถ'));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.local_parking),
                      title: Text(data['name'] ?? 'ไม่มีชื่อ'),
                      subtitle: Text(
                        'ที่จอดรถยนต์: ${data['car_count'] ?? 0} คัน\nที่จอดมอเตอร์ไซค์: ${data['bike_count'] ?? 0} คัน',
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ParkingDetail(parkingData: data),
                            ),
                          );
                        },
                        child: const Text('เลือก'),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ParkingDetail(parkingData: data),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {},
              child: const Text('เลือกระยะทาง'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
