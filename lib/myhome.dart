import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'screen/parking_detail.dart';

class myhome extends StatefulWidget {
  const myhome({super.key});

  @override
  State<myhome> createState() => _myhomeState();
}

class _myhomeState extends State<myhome> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Position? _currentPosition;
  double? _radiusMeters; // null = no radius filter
  bool _isGettingLocation = false;

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
            if (_radiusMeters != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.radar, size: 18),
                    const SizedBox(width: 6),
                    Text(
                        'กรองระยะทาง: ${((_radiusMeters! >= 1000) ? (_radiusMeters! / 1000).toStringAsFixed(1) + ' กม.' : _radiusMeters!.toStringAsFixed(0) + ' ม.')}')
                  ],
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
                  final matchesText = name.contains(_searchQuery);

                  // If radius filter is not set, only use text filter
                  if (_radiusMeters == null || _currentPosition == null) {
                    return matchesText;
                  }

                  // Apply radius filter if location data exists on the document
                  final GeoPoint? gp = data['location'] as GeoPoint?;
                  if (gp == null)
                    return false; // exclude docs without location when filtering by radius

                  final distance = Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    gp.latitude,
                    gp.longitude,
                  );
                  return matchesText && distance <= _radiusMeters!;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อมูลที่จอดรถ'));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.local_parking),
                      title: Text(data['name'] ?? 'ไม่มีชื่อ'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ที่จอดรถยนต์: ${data['car_count'] ?? 0} คัน\nที่จอดมอเตอร์ไซค์: ${data['bike_count'] ?? 0} คัน',
                          ),
                          const SizedBox(height: 4),
                          // Rating summary (avg and count)
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('parking_slots')
                                .doc(doc.id)
                                .collection('reviews')
                                .snapshots(),
                            builder: (context, snap) {
                              if (!snap.hasData) return const SizedBox.shrink();
                              final rdocs = snap.data!.docs;
                              if (rdocs.isEmpty) {
                                return const Text('ยังไม่มีการให้คะแนน');
                              }
                              final ratings = rdocs
                                  .map((d) => (d['rating'] ?? 0).toDouble())
                                  .toList();
                              final avg = ratings.reduce((a, b) => a + b) /
                                  ratings.length;
                              final stars = avg.round().clamp(0, 5);
                              return Row(
                                children: [
                                  ...List.generate(
                                      5,
                                      (i) => Icon(
                                            i < stars
                                                ? Icons.star
                                                : Icons.star_border,
                                            color: Colors.amber,
                                            size: 16,
                                          )),
                                  const SizedBox(width: 6),
                                  Text(
                                      '${avg.toStringAsFixed(1)} (${rdocs.length})'),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ParkingDetail(
                                  parkingData: data, docId: doc.id),
                            ),
                          );
                        },
                        child: const Text('เลือก'),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ParkingDetail(parkingData: data, docId: doc.id),
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
              onPressed: _isGettingLocation ? null : _openRadiusPicker,
              child: _isGettingLocation
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('เลือกระยะทาง'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openRadiusPicker() async {
    setState(() {
      _isGettingLocation = true;
    });

    // Ensure location permission & current position
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isGettingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('โปรดเปิดบริการระบุตำแหน่ง (GPS)')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() => _isGettingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('แอปไม่มีสิทธิ์เข้าถึงตำแหน่ง')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = pos;
      });
    } catch (e) {
      setState(() => _isGettingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถดึงตำแหน่งปัจจุบัน: $e')),
        );
      }
      return;
    }

    setState(() => _isGettingLocation = false);

    if (!mounted) return;

    double tempRadiusMeters = _radiusMeters ?? 2000; // default 2 กม.

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('เลือกระยะรัศมีการค้นหา'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'ตำแหน่งปัจจุบัน: '
                          '${_currentPosition!.latitude.toStringAsFixed(4)}, '
                          '${_currentPosition!.longitude.toStringAsFixed(4)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    min: 200, // 200 เมตร
                    max: 20000, // 20 กม.
                    divisions: 198, // step ~100m
                    value: tempRadiusMeters.clamp(200, 20000),
                    label: tempRadiusMeters >= 1000
                        ? '${(tempRadiusMeters / 1000).toStringAsFixed(1)} กม.'
                        : '${tempRadiusMeters.toStringAsFixed(0)} ม.',
                    onChanged: (v) {
                      setStateDialog(() {
                        tempRadiusMeters = v;
                      });
                    },
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      tempRadiusMeters >= 1000
                          ? '≈ ${(tempRadiusMeters / 1000).toStringAsFixed(1)} กิโลเมตร'
                          : '≈ ${tempRadiusMeters.toStringAsFixed(0)} เมตร',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _radiusMeters = tempRadiusMeters;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
