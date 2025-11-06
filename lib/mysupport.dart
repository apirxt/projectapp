//ส่วนนำเข้าแพ็กเกจ
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:projectapp/screen/account_profile.dart';
import 'package:url_launcher/url_launcher.dart';

//ส่วนหน้าฟีเจอร์ Support/สิทธิ์ปล่อยเช่า
class MySupport extends StatefulWidget {
  const MySupport({super.key});

  @override
  State<MySupport> createState() => _MySupportState();
}

class _MySupportState extends State<MySupport> {
  //ส่วนตัวแปรสถานะสิทธิ์ host และเวลาคงเหลือ
  String? _hostStatus; // สถานะ: none | payment_pending | active | expired | rejected
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

  //ส่วนเปิด Stripe Checkout สำหรับลงทะเบียนสิทธิ์ปล่อยเช่า
  Future<void> _startRegistration() async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('createHostRegistration');
      final res = await callable.call();
      final url = Uri.parse(res.data['url'] as String);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('ไม่สามารถเปิดหน้า Checkout ได้');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'เปิดหน้า Checkout แล้ว ถ้าชำระสำเร็จระบบจะเปิดสิทธิ์อัตโนมัติ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
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
                          onPressed: _startRegistration,
                          child: const Text('ลงทะเบียน (100 บาท)'),
                        ),
                      if (!_loadingStatus && _hostStatus == 'payment_pending')
                        ElevatedButton(
                          onPressed: _startRegistration,
                          child: const Text('ไปชำระเงิน'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                      'หลังชำระเงินสำเร็จ ระบบจะเปิดสิทธิ์อัตโนมัติ และหมดอายุใน 5 นาที'),
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
