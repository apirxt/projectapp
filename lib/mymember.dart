import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'screen/owner_requests.dart';

class MyMember extends StatefulWidget {
  const MyMember({super.key});

  @override
  State<MyMember> createState() => _MyMemberState();
}

class _MyMemberState extends State<MyMember> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController carCountController = TextEditingController();
  final TextEditingController bikeCountController = TextEditingController();
  final TextEditingController carPriceController = TextEditingController();
  final TextEditingController bikePriceController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();
  final TextEditingController detailsController =
      TextEditingController(); // ตัวควบคุมข้อความสำหรับรายละเอียดเพิ่มเติม
  final TextEditingController cctvUrlController =
      TextEditingController(); // URL กล้องวงจรปิด
  // ข้อมูลบัญชีรับเงินของผู้ปล่อยเช่า
  final TextEditingController bankNameController = TextEditingController();
  final TextEditingController accountNameController = TextEditingController();
  final TextEditingController bankAccountController = TextEditingController();
  String vehicleType = '';
  bool _isImagePickerActive = false; // ธงสำหรับกันกดซ้อนขณะเลือกภาพ
  String? nameError; // เก็บข้อความแจ้งเตือนข้อผิดพลาดของชื่อ
  LatLng? selectedLocation; // เก็บพิกัดที่ผู้ใช้เลือก
  bool _isAdmin = false; // แอดมินสามารถจัดการประกาศทั้งหมด
  Timestamp? _hostActiveUntil; // เวลาใบอนุญาตปล่อยเช่าหมดอายุของผู้ใช้ปัจจุบัน

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _adminDeleteByUrl(String url) async {
    if (!_isAdmin) return;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminDeleteImage');
      await fn.call({'url': url});
    } catch (_) {}
  }

  Future<void> _adminDeleteByPath(String path) async {
    if (!_isAdmin) return;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminDeleteImage');
      await fn.call({'path': path});
    } catch (_) {}
  }

  Future<void> _loadClaims() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final result = await user.getIdTokenResult(true);
      final isAdmin = (result.claims?["isAdmin"] == true);
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
      });
    } catch (_) {
      // ข้ามได้
    }
  }

  // ฟอร์แมตวันที่แบบง่าย ๆ เป็น dd/MM/yyyy HH:mm:ss (ตามเครื่องผู้ใช้)
  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  // เข้ารหัส geohash แบบง่าย ใช้สำหรับบันทึกลงเอกสาร เพื่อรองรับการ query ในอนาคต
  // อ้างอิงรูปแบบ geohash base32 "0123456789bcdefghjkmnpqrstuvwxyz"
  String _encodeGeohash(double latitude, double longitude,
      {int precision = 9}) {
    const String base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    double latMin = -90.0, latMax = 90.0;
    double lonMin = -180.0, lonMax = 180.0;
    bool isLon = true;
    int bit = 0;
    int ch = 0;
    StringBuffer hash = StringBuffer();

    while (hash.length < precision) {
      double mid;
      if (isLon) {
        mid = (lonMin + lonMax) / 2;
        if (longitude > mid) {
          ch = (ch << 1) + 1;
          lonMin = mid;
        } else {
          ch = (ch << 1);
          lonMax = mid;
        }
      } else {
        mid = (latMin + latMax) / 2;
        if (latitude > mid) {
          ch = (ch << 1) + 1;
          latMin = mid;
        } else {
          ch = (ch << 1);
          latMax = mid;
        }
      }
      isLon = !isLon;
      bit++;
      if (bit == 5) {
        hash.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return hash.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('ปล่อยเช่าที่จอดรถ'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.inbox),
                label: const Text('คำขอจองจากผู้ใช้'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerRequestsScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            // ฟังเอกสารผู้ใช้ปัจจุบันเพื่อดึงเวลาหมดอายุสิทธิ์ปล่อยเช่า
            child: Builder(builder: (context) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              final userStream = uid == null
                  ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: userStream,
                builder: (context, userSnap) {
                  final userData = userSnap.data?.data();
                  _hostActiveUntil = (userData != null
                      ? userData['hostActiveUntil']
                      : null) as Timestamp?;

                  // จากนั้นฟังรายการประกาศ โดยจำกัดให้เห็นเฉพาะของตัวเอง (ยกเว้นแอดมิน)
                  final base =
                      FirebaseFirestore.instance.collection('parking_slots');
                  final Stream<QuerySnapshot> itemsStream = _isAdmin
                      ? base.orderBy('timestamp', descending: false).snapshots()
                      : base.where('ownerId', isEqualTo: uid).snapshots();

                  return StreamBuilder<QuerySnapshot>(
                    stream: itemsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(child: Text('เกิดข้อผิดพลาด'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                            child: Text('ยังไม่มีข้อมูลที่จอดรถ'));
                      }

                      final currentUid = FirebaseAuth.instance.currentUser?.uid;
                      final DateTime? exp =
                          _hostActiveUntil?.toDate().toLocal();
                      final String expiryText = exp != null
                          ? 'สิทธิ์หมดอายุ: ${_fmtDate(exp)}'
                          : 'สิทธิ์หมดอายุ: -';

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final docSnap = docs[index];
                          final data = docSnap.data() as Map<String, dynamic>;
                          final isOwner = (currentUid != null &&
                              data['ownerId'] == currentUid);
                          final canManage = isOwner || _isAdmin;
                          return ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((data['type'] ?? '')
                                    .toString()
                                    .contains('รถยนต์'))
                                  const Icon(Icons.directions_car),
                                if ((data['type'] ?? '')
                                    .toString()
                                    .contains('มอเตอร์ไซค์'))
                                  const Icon(Icons.motorcycle),
                              ],
                            ),
                            title: Text(
                              data['name'] ?? 'ไม่มีชื่อ',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'จำนวนรถยนต์: ${data['car_count'] ?? 0}\nจำนวนมอเตอร์ไซค์: ${data['bike_count'] ?? 0}${isOwner ? '\n$expiryText' : ''}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color.fromARGB(255, 175, 175, 175),
                              ),
                            ),
                            trailing: canManage
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        tooltip: 'แก้ไขข้อมูล',
                                        onPressed: () async {
                                          await showDialog(
                                            context: context,
                                            builder: (ctx) => _buildEditDialog(
                                                ctx, docSnap.id, data),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'ลบประกาศ',
                                        onPressed: () async {
                                          await _confirmAndDelete(
                                              context, docSnap.id, data);
                                        },
                                      ),
                                    ],
                                  )
                                : null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ParkingDetailScreen(data: data),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => _buildAddDialog(context),
                );
              },
              child: const Text('เพิ่มที่จอดรถ'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(
      BuildContext context, String docId, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text(
            'คุณต้องการลบประกาศนี้หรือไม่? การลบไม่สามารถย้อนกลับได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // พยายามลบรูปทั้งหมดที่เคยผูกกับประกาศนี้ก่อน (ลบทุกรูปของประกาศนี้เท่านั้น)
      final paths =
          ((data['image_paths'] as List?)?.map((e) => e.toString()).toSet()) ??
              <String>{};
      final imageUrl = data['image_url'] as String?;
      // ลบจาก URL ล่าสุดด้วย (เผื่อยังไม่มีใน paths)
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(imageUrl);
          await ref.delete();
        } catch (_) {
          // ถ้าลบไม่ได้ (เช่น สิทธิ์ไม่พอ) และเป็นแอดมิน ให้ลองลบผ่าน Cloud Function
          await _adminDeleteByUrl(imageUrl);
        }
      }
      for (final p in paths) {
        try {
          final ref = FirebaseStorage.instance.ref(p);
          await ref.delete();
        } catch (_) {
          await _adminDeleteByPath(p);
        }
      }

      // ลบเอกสาร Firestore หลังจากจัดการรูปแล้ว
      await FirebaseFirestore.instance
          .collection('parking_slots')
          .doc(docId)
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบประกาศเรียบร้อย')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ลบประกาศล้มเหลว: $e')),
        );
      }
    }
  }

  Widget _buildAddDialog(BuildContext context) {
    // ตัวแปรเฉพาะภายใน dialog สำหรับจัดการสถานะ
    String localVehicleType = vehicleType;
    String?
        localImageUrlInDialog; // เก็บ URL รูปที่อัปโหลดไว้ชั่วคราวจนกว่าจะกดบันทึก
    final List<String> localImagePathsInDialog =
        <String>[]; // เก็บ path ของรูปใน Storage เพื่อไว้ลบภายหลัง

    // ตัวเลือกวันช่วงให้บริการ และเวลาเปิด-ปิด
    TimeOfDay? openTime;
    TimeOfDay? closeTime;
    // ตัวเลือกธนาคาร (dropdown)
    String? selectedBankName;

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        return AlertDialog(
          title: const Text('เพิ่มที่จอดรถ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'ตั้งชื่อที่จอดรถ',
                    errorText: nameError, // แสดงข้อความ error ถ้ามี
                  ),
                ),
                CheckboxListTile(
                  title: const Text('รถยนต์'),
                  value: localVehicleType.contains('รถยนต์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('รถยนต์')) {
                          localVehicleType += 'รถยนต์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('รถยนต์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('รถยนต์')) ...[
                  TextField(
                    controller: carCountController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'จำนวนที่จอดรถยนต์'),
                  ),
                  TextField(
                    controller: carPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดรถยนต์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                CheckboxListTile(
                  title: const Text('มอเตอร์ไซค์'),
                  value: localVehicleType.contains('มอเตอร์ไซค์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('มอเตอร์ไซค์')) {
                          localVehicleType += 'มอเตอร์ไซค์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('มอเตอร์ไซค์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('มอเตอร์ไซค์')) ...[
                  TextField(
                    controller: bikeCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'จำนวนที่จอดมอเตอร์ไซค์'),
                  ),
                  TextField(
                    controller: bikePriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดมอเตอร์ไซค์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                // เลือกช่วงวันที่ให้บริการ
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'ช่วงวันที่เปิดให้บริการ (เริ่ม - สิ้นสุด)'),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        String two(int v) => v.toString().padLeft(2, '0');
                        final s = picked.start;
                        final e = picked.end;
                        dateController.text =
                            '${two(s.day)}/${two(s.month)}/${s.year} - ${two(e.day)}/${two(e.month)}/${e.year}';
                      });
                    }
                  },
                ),
                // เลือกเวลาเปิด-ปิดที่ให้บริการจริง ๆ
                TextField(
                  controller: timeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'เวลาเปิดให้บริการ (เช่น 08:00-20:00)'),
                  onTap: () async {
                    final ot = await showTimePicker(
                      context: context,
                      initialTime: openTime ?? TimeOfDay(hour: 8, minute: 0),
                    );
                    if (ot == null) return;
                    if (!context.mounted) return;
                    final ct = await showTimePicker(
                      context: context,
                      initialTime: closeTime ?? TimeOfDay(hour: 20, minute: 0),
                    );
                    if (ct == null) return;
                    if (!context.mounted) return;
                    setDialogState(() {
                      openTime = ot;
                      closeTime = ct;
                      String two(int v) => v.toString().padLeft(2, '0');
                      timeController.text =
                          '${two(ot.hour)}:${two(ot.minute)}-${two(ct.hour)}:${two(ct.minute)}';
                    });
                  },
                ),
                const Divider(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ข้อมูลบัญชีรับเงิน',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedBankName ??
                      (bankNameController.text.isNotEmpty
                          ? bankNameController.text
                          : null),
                  items: [
                    DropdownMenuItem(value: 'กสิกร', child: Text('กสิกร')),
                    DropdownMenuItem(
                        value: 'ไทยพาณิชย์', child: Text('ไทยพาณิชย์')),
                    DropdownMenuItem(value: 'กรุงไทย', child: Text('กรุงไทย')),
                    DropdownMenuItem(value: 'กรุงเทพ', child: Text('กรุงเทพ')),
                    DropdownMenuItem(value: 'กรุงศรี', child: Text('กรุงศรี')),
                    DropdownMenuItem(
                        value: 'ทหารไทยธนชาต', child: Text('ทหารไทยธนชาต')),
                    DropdownMenuItem(value: 'ออมสิน', child: Text('ออมสิน')),
                  ],
                  onChanged: (v) {
                    setDialogState(() {
                      selectedBankName = v;
                      bankNameController.text = v ?? '';
                    });
                  },
                  decoration: const InputDecoration(labelText: 'ชื่อธนาคาร'),
                ),
                TextField(
                  controller: accountNameController,
                  decoration: const InputDecoration(labelText: 'ชื่อบัญชี'),
                ),
                TextField(
                  controller: bankAccountController,
                  decoration: const InputDecoration(labelText: 'เลขบัญชี'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: cctvUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL กล้องวงจรปิด',
                    hintText: 'เช่น http://... หรือ rtsp://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    hintText: 'กรอกรายละเอียดเพิ่มเติมเกี่ยวกับที่จอดรถ',
                  ),
                  maxLines: null, // ให้พิมพ์หลายบรรทัดได้
                ),
                if (localImageUrlInDialog != null &&
                    localImageUrlInDialog!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Image.network(localImageUrlInDialog!,
                        height: 120, fit: BoxFit.cover),
                  ),
                ElevatedButton(
                  onPressed: _isImagePickerActive
                      ? null // ปิดปุ่มชั่วคราวระหว่างเลือกภาพ
                      : () async {
                          setState(() {
                            _isImagePickerActive = true;
                          });

                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                              source: ImageSource.gallery);

                          if (image != null) {
                            try {
                              // อัปโหลดรูปไป Firebase Storage
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              final storageRef = FirebaseStorage.instance
                                  .ref()
                                  .child(
                                      'parking_images/${DateTime.now().millisecondsSinceEpoch}_${image.name}');
                              // ignore: avoid_print
                              print(
                                  'UPLOAD parking_images path=${storageRef.fullPath} uid=$uid');
                              final uploadTask = await storageRef.putFile(
                                File(image.path),
                                SettableMetadata(customMetadata: {
                                  if (uid != null) 'ownerUid': uid,
                                }),
                              );

                              // ดึงลิงก์สำหรับดาวน์โหลด แล้วเก็บไว้ชั่วคราวจนกว่าจะบันทึก
                              final imageUrl =
                                  await uploadTask.ref.getDownloadURL();

                              setDialogState(() {
                                localImageUrlInDialog = imageUrl;
                                // บันทึก path ของรูปไว้ เพื่อลบเมื่อมีการลบประกาศ
                                if (!localImagePathsInDialog
                                    .contains(storageRef.fullPath)) {
                                  localImagePathsInDialog
                                      .add(storageRef.fullPath);
                                }
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('อัปโหลดรูปภาพเรียบร้อย')),
                                );
                              }
                            } on FirebaseException catch (e) {
                              // ignore: avoid_print
                              print(
                                  'UPLOAD ERROR code=${e.code} message=${e.message}');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'อัปโหลดรูปภาพล้มเหลว: ${e.code}')),
                                );
                              }
                            } catch (e) {
                              // แจ้งเตือนเมื่อเกิดข้อผิดพลาด
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('อัปโหลดรูปภาพล้มเหลว: $e')),
                                );
                              }
                            } finally {
                              setState(() {
                                _isImagePickerActive = false;
                              });
                            }
                          } else {
                            setState(() {
                              _isImagePickerActive = false;
                            });
                          }
                        },
                  child: const Text('เพิ่มรูปภาพ'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final LatLng? result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MapScreen(),
                      ),
                    );
                    if (result != null) {
                      selectedLocation = result;
                      setDialogState(() {}); // รีเฟรช state ของ dialog
                    }
                  },
                  child: const Text('เลือกปักหมุดสถานที่'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    (carCountController.text.isNotEmpty ||
                        bikeCountController.text.isNotEmpty)) {
                  setState(() {
                    vehicleType = localVehicleType.trim();
                  });

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('กรุณาเข้าสู่ระบบก่อนบันทึก')),
                      );
                    }
                    return;
                  }

                  // เช็กว่ามีชื่อที่จอดซ้ำอยู่แล้วหรือไม่
                  final existingDocs = await FirebaseFirestore.instance
                      .collection('parking_slots')
                      .where('name', isEqualTo: nameController.text)
                      .get();

                  if (existingDocs.docs.isNotEmpty) {
                    // แสดงคำเตือนใต้ช่องกรอก
                    setDialogState(() {
                      nameError = 'ชื่อที่จอดรถนี้มีอยู่แล้ว กรุณาตั้งชื่อใหม่';
                    });
                    return;
                  }

                  try {
                    await FirebaseFirestore.instance
                        .collection('parking_slots')
                        .add({
                      'name': nameController.text,
                      'type': localVehicleType.trim(),
                      'car_count': int.tryParse(carCountController.text) ?? 0,
                      'bike_count': int.tryParse(bikeCountController.text) ?? 0,
                      'car_price': int.tryParse(carPriceController.text) ?? 0,
                      'bike_price': int.tryParse(bikePriceController.text) ?? 0,
                      'service_date': dateController.text,
                      'service_time': timeController.text,
                      'bankName': bankNameController.text.trim(),
                      'accountName': accountNameController.text.trim(),
                      'bankAccount': bankAccountController.text.trim(),
                      'details':
                          detailsController.text, // บันทึกรายละเอียดเพิ่มเติม
                      'cctv_url': cctvUrlController.text.trim(),
                      if (localImageUrlInDialog != null)
                        'image_url': localImageUrlInDialog,
                      if (localImagePathsInDialog.isNotEmpty)
                        'image_paths': localImagePathsInDialog,
                      'location': selectedLocation != null
                          ? GeoPoint(selectedLocation!.latitude,
                              selectedLocation!.longitude)
                          : null,
                      if (selectedLocation != null)
                        'geohash': _encodeGeohash(selectedLocation!.latitude,
                            selectedLocation!.longitude,
                            precision: 9),
                      'ownerId': uid,
                      'timestamp': FieldValue.serverTimestamp(),
                    });

                    // ล้างช่องกรอกแล้วปิด dialog
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    nameController.clear();
                    carCountController.clear();
                    bikeCountController.clear();
                    carPriceController.clear();
                    bikePriceController.clear();
                    dateController.clear();
                    timeController.clear();
                    detailsController.clear(); // เคลียร์ช่องรายละเอียดเพิ่มเติม
                    cctvUrlController.clear();
                    bankNameController.clear();
                    accountNameController.clear();
                    bankAccountController.clear();
                    vehicleType = '';
                    selectedLocation = null; // ล้างค่าพิกัดที่เลือก
                  } catch (e) {
                    // แจ้งเตือนเมื่อเกิดข้อผิดพลาด
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                      );
                    }
                  }
                } else {
                  setDialogState(() {
                    nameError = 'กรุณากรอกข้อมูลให้ครบถ้วน';
                  });
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditDialog(
      BuildContext context, String docId, Map<String, dynamic> data) {
    // สถานะและ controller ที่ตั้งค่าเริ่มจากข้อมูลเดิม
    final nameCtl = TextEditingController(text: data['name'] ?? '');
    final carCountCtl =
        TextEditingController(text: (data['car_count']?.toString() ?? ''));
    final bikeCountCtl =
        TextEditingController(text: (data['bike_count']?.toString() ?? ''));
    final carPriceCtl =
        TextEditingController(text: (data['car_price']?.toString() ?? ''));
    final bikePriceCtl =
        TextEditingController(text: (data['bike_price']?.toString() ?? ''));
    final dateCtl = TextEditingController(text: data['service_date'] ?? '');
    final timeCtl = TextEditingController(text: data['service_time'] ?? '');
    final detailsCtl = TextEditingController(text: data['details'] ?? '');
    final cctvUrlCtl = TextEditingController(text: data['cctv_url'] ?? '');
    final bankNameCtl = TextEditingController(text: data['bankName'] ?? '');
    final accountNameCtl =
        TextEditingController(text: data['accountName'] ?? '');
    final bankAccountCtl = TextEditingController(
        text: data['bankAccount'] ?? data['accountNumber'] ?? '');

    String localVehicleType = (data['type'] ?? '').toString();
    GeoPoint? gp = data['location'] as GeoPoint?;
    LatLng? localSelectedLocation =
        gp != null ? LatLng(gp.latitude, gp.longitude) : null;
    String? localImageUrl = data['image_url'] as String?;
    final List<String> originalImagePaths =
        (data['image_paths'] as List?)?.map((e) => e.toString()).toList() ??
            <String>[];
    final List<String> localImagePaths = List<String>.from(originalImagePaths);
    String? localNameError;
    bool busy = false;
    // เวลาเปิด-ปิด และธนาคารสำหรับแก้ไข
    TimeOfDay? editOpenTime;
    TimeOfDay? editCloseTime;
    String? editSelectedBank;

    // พยายามแปลงค่าเวลาเดิมเป็น TimeOfDay
    void initTimeFromText() {
      final t = timeCtl.text.trim();
      if (t.contains('-')) {
        final parts = t.split('-');
        TimeOfDay? parseTime(String s) {
          final seg = s.split(':');
          if (seg.length != 2) return null;
          final h = int.tryParse(seg[0]);
          final m = int.tryParse(seg[1]);
          if (h == null || m == null) return null;
          return TimeOfDay(hour: h, minute: m);
        }

        editOpenTime = parseTime(parts[0].trim());
        editCloseTime = parseTime(parts[1].trim());
      }
      if ((bankNameCtl.text).isNotEmpty) {
        editSelectedBank = bankNameCtl.text;
      }
    }

    initTimeFromText();

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        return AlertDialog(
          title: const Text('แก้ไขที่จอดรถ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(
                    labelText: 'ชื่อที่จอดรถ',
                    errorText: localNameError,
                  ),
                ),
                CheckboxListTile(
                  title: const Text('รถยนต์'),
                  value: localVehicleType.contains('รถยนต์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('รถยนต์')) {
                          localVehicleType += 'รถยนต์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('รถยนต์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('รถยนต์')) ...[
                  TextField(
                    controller: carCountCtl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'จำนวนที่จอดรถยนต์'),
                  ),
                  TextField(
                    controller: carPriceCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดรถยนต์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                CheckboxListTile(
                  title: const Text('มอเตอร์ไซค์'),
                  value: localVehicleType.contains('มอเตอร์ไซค์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('มอเตอร์ไซค์')) {
                          localVehicleType += 'มอเตอร์ไซค์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('มอเตอร์ไซค์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('มอเตอร์ไซค์')) ...[
                  TextField(
                    controller: bikeCountCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'จำนวนที่จอดมอเตอร์ไซค์'),
                  ),
                  TextField(
                    controller: bikePriceCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดมอเตอร์ไซค์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                TextField(
                  controller: dateCtl,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'ช่วงวันที่เปิดให้บริการ (เริ่ม - สิ้นสุด)'),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) {
                      String two(int v) => v.toString().padLeft(2, '0');
                      final s = picked.start;
                      final e = picked.end;
                      setDialogState(() {
                        dateCtl.text =
                            '${two(s.day)}/${two(s.month)}/${s.year} - ${two(e.day)}/${two(e.month)}/${e.year}';
                      });
                    }
                  },
                ),
                TextField(
                  controller: timeCtl,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'เวลาเปิดให้บริการ (เช่น 08:00-20:00)'),
                  onTap: () async {
                    final ot = await showTimePicker(
                      context: context,
                      initialTime:
                          editOpenTime ?? const TimeOfDay(hour: 8, minute: 0),
                    );
                    if (ot == null) return;
                    if (!context.mounted) return;
                    final ct = await showTimePicker(
                      context: context,
                      initialTime:
                          editCloseTime ?? const TimeOfDay(hour: 20, minute: 0),
                    );
                    if (ct == null) return;
                    if (!context.mounted) return;
                    setDialogState(() {
                      editOpenTime = ot;
                      editCloseTime = ct;
                      String two(int v) => v.toString().padLeft(2, '0');
                      timeCtl.text =
                          '${two(ot.hour)}:${two(ot.minute)}-${two(ct.hour)}:${two(ct.minute)}';
                    });
                  },
                ),
                const Divider(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ข้อมูลบัญชีรับเงิน',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                DropdownButtonFormField<String>(
                  initialValue: editSelectedBank ??
                      (bankNameCtl.text.isNotEmpty ? bankNameCtl.text : null),
                  items: [
                    DropdownMenuItem(value: 'กสิกร', child: Text('กสิกร')),
                    DropdownMenuItem(
                        value: 'ไทยพาณิชย์', child: Text('ไทยพาณิชย์')),
                    DropdownMenuItem(value: 'กรุงไทย', child: Text('กรุงไทย')),
                    DropdownMenuItem(value: 'กรุงเทพ', child: Text('กรุงเทพ')),
                    DropdownMenuItem(value: 'กรุงศรี', child: Text('กรุงศรี')),
                    DropdownMenuItem(
                        value: 'ทหารไทยธนชาต', child: Text('ทหารไทยธนชาต')),
                    DropdownMenuItem(value: 'ออมสิน', child: Text('ออมสิน')),
                  ],
                  onChanged: (v) {
                    setDialogState(() {
                      editSelectedBank = v;
                      bankNameCtl.text = v ?? '';
                    });
                  },
                  decoration: const InputDecoration(labelText: 'ชื่อธนาคาร'),
                ),
                TextField(
                  controller: accountNameCtl,
                  decoration: const InputDecoration(labelText: 'ชื่อบัญชี'),
                ),
                TextField(
                  controller: bankAccountCtl,
                  decoration: const InputDecoration(labelText: 'เลขบัญชี'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: cctvUrlCtl,
                  decoration: const InputDecoration(
                    labelText: 'URL กล้องวงจรปิด',
                    hintText: 'เช่น http://... หรือ rtsp://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
                TextField(
                  controller: detailsCtl,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    hintText: 'แก้ไขรายละเอียดเกี่ยวกับที่จอดรถ',
                  ),
                  maxLines: null,
                ),
                if (localImageUrl != null && localImageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Image.network(localImageUrl!,
                        height: 120, fit: BoxFit.cover),
                  ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setDialogState(() => busy = true);
                          try {
                            final ImagePicker picker = ImagePicker();
                            final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery);
                            if (image != null) {
                              final storageRef = FirebaseStorage.instance
                                  .ref()
                                  .child(
                                      'parking_images/${DateTime.now().millisecondsSinceEpoch}_${image.name}');
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              // ignore: avoid_print
                              print(
                                  'UPLOAD parking_images path=${storageRef.fullPath} uid=$uid');
                              final uploadTask = await storageRef.putFile(
                                File(image.path),
                                SettableMetadata(customMetadata: {
                                  if (uid != null) 'ownerUid': uid,
                                }),
                              );
                              final url = await uploadTask.ref.getDownloadURL();
                              setDialogState(() {
                                localImageUrl = url;
                                if (!localImagePaths
                                    .contains(storageRef.fullPath)) {
                                  localImagePaths.add(storageRef.fullPath);
                                }
                              });
                            }
                          } on FirebaseException catch (e) {
                            // ignore: avoid_print
                            print(
                                'UPLOAD ERROR code=${e.code} message=${e.message}');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'อัปโหลดรูปภาพล้มเหลว: ${e.code}')));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('อัปโหลดรูปภาพล้มเหลว: $e')));
                            }
                          } finally {
                            setDialogState(() => busy = false);
                          }
                        },
                  child: const Text('เปลี่ยนรูปภาพ'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final LatLng? result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MapScreen()),
                    );
                    if (result != null) {
                      localSelectedLocation = result;
                      setDialogState(() {});
                    }
                  },
                  child: const Text('แก้ไขปักหมุดสถานที่'),
                ),
                if (localSelectedLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                        'ตำแหน่งใหม่: ${localSelectedLocation!.latitude.toStringAsFixed(6)}, ${localSelectedLocation!.longitude.toStringAsFixed(6)}'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      // ตรวจสอบเบื้องต้น
                      if (nameCtl.text.trim().isEmpty ||
                          (carCountCtl.text.trim().isEmpty &&
                              bikeCountCtl.text.trim().isEmpty)) {
                        setDialogState(() {
                          localNameError =
                              'กรุณากรอกชื่อ และจำนวนที่จอดอย่างน้อย 1 ประเภท';
                        });
                        return;
                      }

                      setDialogState(() => busy = true);
                      try {
                        // ถ้าชื่อถูกแก้ ต้องเช็กว่าไม่ซ้ำ
                        if (nameCtl.text.trim() != (data['name'] ?? '')) {
                          final dup = await FirebaseFirestore.instance
                              .collection('parking_slots')
                              .where('name', isEqualTo: nameCtl.text.trim())
                              .get();
                          final existsOther =
                              dup.docs.any((d) => d.id != docId);
                          if (existsOther) {
                            setDialogState(() {
                              localNameError =
                                  'ชื่อที่จอดรถนี้มีอยู่แล้ว กรุณาตั้งชื่อใหม่';
                              busy = false;
                            });
                            return;
                          }
                        }

                        final update = <String, dynamic>{
                          'name': nameCtl.text.trim(),
                          'type': localVehicleType.trim(),
                          'car_count': int.tryParse(carCountCtl.text) ?? 0,
                          'bike_count': int.tryParse(bikeCountCtl.text) ?? 0,
                          'car_price': int.tryParse(carPriceCtl.text) ?? 0,
                          'bike_price': int.tryParse(bikePriceCtl.text) ?? 0,
                          'service_date': dateCtl.text,
                          'service_time': timeCtl.text,
                          'details': detailsCtl.text,
                          'cctv_url': cctvUrlCtl.text.trim(),
                          'bankName': bankNameCtl.text.trim(),
                          'accountName': accountNameCtl.text.trim(),
                          'bankAccount': bankAccountCtl.text.trim(),
                        };
                        if (localImageUrl != null) {
                          update['image_url'] = localImageUrl;
                        }
                        // เพิ่ม path ที่เพิ่มใหม่ (ถ้ามี) โดยไม่ซ้ำกับของเดิม
                        final List<String> newPaths = localImagePaths
                            .where((p) => !originalImagePaths.contains(p))
                            .toList();
                        if (newPaths.isNotEmpty) {
                          update['image_paths'] =
                              FieldValue.arrayUnion(newPaths);
                        }
                        if (localSelectedLocation != null) {
                          update['location'] = GeoPoint(
                              localSelectedLocation!.latitude,
                              localSelectedLocation!.longitude);
                          update['geohash'] = _encodeGeohash(
                              localSelectedLocation!.latitude,
                              localSelectedLocation!.longitude,
                              precision: 9);
                        }

                        await FirebaseFirestore.instance
                            .collection('parking_slots')
                            .doc(docId)
                            .update(update);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('อัปเดตข้อมูลเรียบร้อย')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('อัปเดตล้มเหลว: $e')));
                        }
                      } finally {
                        setDialogState(() => busy = false);
                      }
                    },
              child: const Text('บันทึกการแก้ไข'),
            ),
          ],
        );
      },
    );
  }
}

class ParkingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const ParkingDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final GeoPoint? location = data['location'] as GeoPoint?;
    final String cctvUrl = (data['cctv_url'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(data['name'] ?? 'รายละเอียดที่จอดรถ'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data['image_url'] != null && data['image_url'].isNotEmpty)
                Center(
                  child: Image.network(
                    data['image_url'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'ที่จอดรถ: ${data['name'] ?? 'ไม่มีชื่อ'}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('ประเภท: ${data['type'] ?? 'ไม่มีข้อมูล'}\n'),
              const SizedBox(height: 5),
              Text('จำนวนรถยนต์: ${data['car_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text('ราคาที่จอดรถยนต์: ${data['car_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text('จำนวนมอเตอร์ไซค์: ${data['bike_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text(
                  'ราคาที่จอดมอเตอร์ไซค์: ${data['bike_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text(
                  'วันที่เปิดให้บริการ: ${data['service_date'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 5),
              Text(
                  'เวลาที่เปิดให้บริการ: ${data['service_time'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 20),
              if (cctvUrl.isNotEmpty) ...[
                const Text(
                  'กล้องวงจรปิด (CCTV):',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final uri = Uri.parse(cctvUrl);
                      if (!await launchUrl(uri,
                          mode: LaunchMode.externalApplication)) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('ไม่สามารถเปิดลิงก์กล้องได้')),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ลิงก์ไม่ถูกต้อง: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.videocam),
                  label: const Text('เปิดกล้องวงจรปิด'),
                ),
                const SizedBox(height: 20),
              ],
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
                        infoWindow:
                            InfoWindow(title: data['name'] ?? 'ที่จอดรถ'),
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
              Text(
                'รายละเอียดเพิ่มเติม:',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('${data['details'] ?? 'ไม่มีข้อมูล'}'),
            ],
          ),
        ),
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _controller;
  final TextEditingController _searchController = TextEditingController();
  final Set<Marker> _markers = {};
  LatLng? _selectedLocation;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(13.7563, 100.5018), // พิกัดกรุงเทพฯ
    zoom: 11,
  );

  void _addMarker(LatLng position) {
    setState(() {
      _markers.clear(); // ลบหมุดเดิมก่อน
      _selectedLocation = position;
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          infoWindow: const InfoWindow(title: 'ตำแหน่งที่เลือก'),
        ),
      );
    });
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาพิมพ์สถานที่ที่ต้องการค้นหา')),
      );
      return;
    }
    try {
      final results = await geocoding.locationFromAddress(query);
      if (results.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบสถานที่ที่ค้นหา')),
        );
        return;
      }
      final first = results.first;
      final target = LatLng(first.latitude, first.longitude);
      _addMarker(target);
      await _controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ค้นหาสถานที่ล้มเหลว: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกตำแหน่งที่จอดรถ'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _searchPlace(),
              decoration: InputDecoration(
                hintText: 'ค้นหาสถานที่...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchPlace,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              onMapCreated: (GoogleMapController controller) {
                _controller = controller;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapType: MapType.normal,
              markers: _markers,
              onTap: _addMarker,
            ),
          ),
          if (_selectedLocation != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'ละติจูด: ${_selectedLocation!.latitude.toStringAsFixed(6)}\nลองจิจูด: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // ส่งค่าตำแหน่งที่เลือกกลับไปหน้าก่อนหน้า
                      Navigator.pop(context, _selectedLocation);
                    },
                    child: const Text('ยืนยันตำแหน่ง'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
