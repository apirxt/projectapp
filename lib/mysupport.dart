//ส่วนนำเข้าแพ็กเกจ
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:projectapp/screen/account_profile.dart';

//ส่วนหน้าฟีเจอร์ Support/สิทธิ์ปล่อยเช่า
class MySupport extends StatefulWidget {
  const MySupport({super.key});

  @override
  State<MySupport> createState() => _MySupportState();
}

class _MySupportState extends State<MySupport> {
  //ส่วนตัวแปรสถานะสิทธิ์ host และเวลาคงเหลือ
  String?
      _hostStatus; // สถานะ: none | payment_pending | active | expired | rejected
  Timestamp? _hostActiveUntil;
  bool _loadingStatus = false;
  Timer? _tick;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _listenHostStatus(); //ส่วนเริ่มฟังสถานะจาก Firestore
  }

  //ส่วนฟังสถานะ Host จาก Firestore และตั้ง countdown
  void _listenHostStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loadingStatus = true);
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen(
        (snap) {
      final v = snap.data();
      setState(() {
        _hostStatus =
            (v != null ? (v['hostStatus'] as String?) : null) ?? 'none';
        _hostActiveUntil =
            v != null ? v['hostActiveUntil'] as Timestamp? : null;
        _setupCountdown();
        _loadingStatus = false;
      });
    }, onError: (_) {
      setState(() => _loadingStatus = false);
    });
  }

  //ส่วนตั้งตัวจับเวลานับถอยหลังสิทธิ์ปล่อยเช่า
  void _setupCountdown() {
    _tick?.cancel();
    if (_hostStatus == 'active' && _hostActiveUntil != null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        final now = DateTime.now();
        final end = _hostActiveUntil!.toDate();
        final diff = end.difference(now);
        if (diff.isNegative) {
          _tick?.cancel();
          setState(() => _remaining = Duration.zero);
        } else {
          setState(() => _remaining = diff);
        }
      });
      //ส่วนรีเฟรช claims เผื่อกรณีสิทธิ์เปลี่ยนแบบเรียลไทม์
      FirebaseAuth.instance.currentUser?.getIdToken(true);
    } else {
      _remaining = Duration.zero;
    }
  }

  // ฟอร์มลงทะเบียนใหม่: กรอกชื่อ-นามสกุล, เบอร์โทร และแนบรูปสลิป
  Future<void> _openRegistrationDialog() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    String? slipUrl;
    bool busy = false;

    bool valid() {
      final name = nameCtl.text.trim();
      final phone = phoneCtl.text.trim();
      final isDigits = RegExp(r'^\d{9,10}$').hasMatch(phone);
      return name.isNotEmpty && isDigits && slipUrl != null && !busy;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          Future<void> pickAndUpload() async {
            try {
              setD(() => busy = true);
              final picker = ImagePicker();
              final XFile? img =
                  await picker.pickImage(source: ImageSource.gallery);
              if (img == null) {
                setD(() => busy = false);
                return;
              }
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) throw Exception('กรุณาเข้าสู่ระบบ');
              final path =
                  'registration_slips/$uid/${DateTime.now().millisecondsSinceEpoch}_${img.name}';
              final ref = FirebaseStorage.instance.ref(path);
              final meta = SettableMetadata(customMetadata: {'ownerUid': uid});
              final task = await ref.putFile(File(img.path), meta);
              final url = await task.ref.getDownloadURL();
              setD(() {
                slipUrl = url;
                busy = false;
              });
            } on FirebaseException catch (e) {
              setD(() => busy = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: ${e.code}')),
                );
              }
            } catch (e) {
              setD(() => busy = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')),
                );
              }
            }
          }

          Future<void> submit() async {
            try {
              setD(() => busy = true);
              final callable = FirebaseFunctions.instance
                  .httpsCallable('submitHostRegistration');
              await callable.call({
                'fullName': nameCtl.text.trim(),
                'phone': phoneCtl.text.trim(),
                'slipUrl': slipUrl,
              });
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('ส่งคำขอเรียบร้อย รอแอดมินตรวจสอบ')),
              );
            } on FirebaseFunctionsException catch (e) {
              setD(() => busy = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: ${e.code}')),
                );
              }
            } catch (e) {
              setD(() => busy = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $e')),
                );
              }
            }
          }

          return AlertDialog(
            title: const Text('ลงทะเบียนสิทธิ์ปล่อยเช่า'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtl,
                    decoration:
                        const InputDecoration(labelText: 'ชื่อ-นามสกุล'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtl,
                    decoration: const InputDecoration(
                        labelText: 'เบอร์โทร (9–10 หลัก)'),
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 12),
                  if (slipUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(slipUrl!,
                          height: 140, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: busy ? null : pickAndUpload,
                    icon: const Icon(Icons.image),
                    label:
                        Text(slipUrl == null ? 'แนบรูปสลิป' : 'เปลี่ยนรูปสลิป'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: valid() ? submit : null,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ส่งคำขอ'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Support'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          //ส่วนบัตรสรุปบัญชีผู้ใช้
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                radius: 28,
                backgroundImage:
                    (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                        ? NetworkImage(user.photoURL!)
                        : null,
                child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                    ? const Icon(Icons.person, size: 28)
                    : null,
              ),
              title: Text(user?.displayName ?? 'ไม่ระบุชื่อผู้ใช้'),
              subtitle: Text(user?.email ?? 'ไม่ระบุอีเมล'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountProfileScreen()),
                );
                if (mounted) setState(() {}); //ส่วนรีเฟรชหลังกลับมา
              },
            ),
          ),

          const SizedBox(height: 16),
          //ส่วนสิทธิ์ปล่อยเช่า (Host Permission)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('สิทธิ์ปล่อยเช่าที่จอดรถ',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _loadingStatus
                              ? 'กำลังโหลดสถานะ…'
                              : () {
                                  switch (_hostStatus) {
                                    case 'active':
                                      final mm = _remaining.inMinutes
                                          .remainder(60)
                                          .toString()
                                          .padLeft(2, '0');
                                      final ss = _remaining.inSeconds
                                          .remainder(60)
                                          .toString()
                                          .padLeft(2, '0');
                                      return 'สถานะ: ได้รับสิทธิ์แล้ว (เหลือเวลา $mm:$ss นาที)';
                                    case 'payment_pending':
                                      return 'สถานะ: รอชำระเงิน';
                                    case 'rejected':
                                      return 'สถานะ: ถูกปฏิเสธ (สามารถส่งคำขอใหม่)';
                                    default:
                                      return 'สถานะ: ยังไม่ได้ลงทะเบียน';
                                  }
                                }(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_loadingStatus &&
                          (_hostStatus == null ||
                              _hostStatus == 'none' ||
                              _hostStatus == 'expired' ||
                              _hostStatus == 'rejected'))
                        ElevatedButton(
                          onPressed: _openRegistrationDialog,
                          child: const Text('ลงทะเบียน'),
                        ),
                      if (!_loadingStatus && _hostStatus == 'requested')
                        const Chip(label: Text('รอตรวจสอบ')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('หลังส่งคำขอ แอดมินจะตรวจสอบและอนุมัติให้ใช้งาน'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          //ส่วนติดต่อเรา
          const Text(
            'ติดต่อเรา',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'หากคุณมีคำถามหรือปัญหาเกี่ยวกับการใช้งานแอปพลิเคชัน สามารถติดต่อเราได้ที่:',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Icon(Icons.email, color: Colors.blue),
              SizedBox(width: 8),
              Text('support@projectapp.com', style: TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(Icons.phone, color: Colors.green),
              SizedBox(width: 8),
              Text('+66 123 456 789', style: TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }
}
