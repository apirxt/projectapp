import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screen/account_profile.dart';

class MySupport extends StatefulWidget {
  const MySupport({super.key});

  @override
  State<MySupport> createState() => _MySupportState();
}

class _MySupportState extends State<MySupport> {
  bool _canHost = false;

  @override
  void initState() {
    super.initState();
    _refreshClaims();
  }

  Future<void> _refreshClaims() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdTokenResult(true);
      setState(() {
        _canHost = token.claims?['canHostParking'] == true;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Support'),
      ),
      body: user == null
          ? const Center(
              child: Text('กรุณาเข้าสู่ระบบเพื่อใช้งานหน้าช่วยเหลือ'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data();
                final hostUntil = (userData?['hostActiveUntil']) as Timestamp?;
                final activeUntil = hostUntil?.toDate();
                final now = DateTime.now();
                final bool approved = _canHost ||
                    (activeUntil != null && activeUntil.isAfter(now));

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    children: [
                      _buildProfileHeader(user),
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.black12,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('สิทธิ์ปล่อยเช่าที่จอดรถ',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      approved
                                          ? (activeUntil != null
                                              ? 'สถานะ: อนุมัติแล้ว (หมดอายุ: ${_fmtDate(activeUntil)})'
                                              : 'สถานะ: อนุมัติแล้ว')
                                          : 'สถานะ: ยังไม่ได้ลงทะเบียน',
                                    ),
                                  ),
                                  if (!approved)
                                    ElevatedButton(
                                      onPressed: () => _openRegisterDialog(),
                                      child: const Text('ลงทะเบียน'),
                                    )
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                  'หลังส่งคำขอ แอดมินจะตรวจสอบและอนุมัติให้ใช้งาน'),
                              if (!approved)
                                StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('host_rights_requests')
                                      .where('userId', isEqualTo: user.uid)
                                      .orderBy('createdAt', descending: true)
                                      .limit(1)
                                      .snapshots(),
                                  builder: (context, rs) {
                                    final waiting =
                                        (rs.data?.docs.isNotEmpty ?? false);
                                    return waiting
                                        ? Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6.0),
                                            child: Row(
                                              children: const [
                                                Icon(Icons.hourglass_top,
                                                    size: 16,
                                                    color: Colors.orange),
                                                SizedBox(width: 6),
                                                Text('สถานะคำขอ: กำลังตรวจสอบ'),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink();
                                  },
                                )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('ติดต่อเรา',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _contactTile(
                        icon: Icons.email,
                        label: 'support@projectapp.com',
                        onTap: () =>
                            _launch(Uri.parse('mailto:support@projectapp.com')),
                      ),
                      _contactTile(
                        icon: Icons.phone,
                        label: '+66 123 456 789',
                        onTap: () => _launch(Uri.parse('tel:+66123456789')),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfileHeader(User user) {
    final email = user.email ?? '-';
    final displayName =
        user.displayName ?? (email.isNotEmpty ? email.split('@').first : '-');
    return Card(
      color: Colors.black12,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(displayName),
        subtitle: Text(email),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountProfileScreen()),
          );
        },
      ),
    );
  }

  Widget _contactTile(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _fmtDate(DateTime d) {
    final dt = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
  }

  Future<void> _openRegisterDialog() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    String? imageUrl;
    bool busy = false;

    bool isValid() {
      final name = nameCtl.text.trim();
      final phone = phoneCtl.text.trim();
      final validPhone = RegExp(r'^\d{9,10}$').hasMatch(phone);
      return name.isNotEmpty && validPhone && imageUrl != null && !busy;
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
              final ImagePicker picker = ImagePicker();
              final XFile? img =
                  await picker.pickImage(source: ImageSource.gallery);
              if (img == null) {
                setD(() => busy = false);
                return;
              }
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) throw Exception('กรุณาเข้าสู่ระบบ');
              final path =
                  'host_rights/$uid/${DateTime.now().millisecondsSinceEpoch}_${img.name}';
              final ref = FirebaseStorage.instance.ref(path);
              final task = await ref.putFile(
                File(img.path),
                SettableMetadata(customMetadata: {'ownerUid': uid}),
              );
              final url = await task.ref.getDownloadURL();
              setD(() {
                imageUrl = url;
                busy = false;
              });
            } catch (e) {
              setD(() => busy = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')),
                );
              }
            }
          }

          Future<void> submit() async {
            try {
              setD(() => busy = true);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) throw Exception('กรุณาเข้าสู่ระบบ');
              await FirebaseFirestore.instance
                  .collection('host_rights_requests')
                  .add({
                'userId': uid,
                'name': nameCtl.text.trim(),
                'phone': phoneCtl.text.trim(),
                'imageUrl': imageUrl,
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('ส่งคำขอลงทะเบียนเรียบร้อย')),
                );
              }
            } catch (e) {
              setD(() => busy = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $e')),
                );
              }
            }
          }

          const String appAccountNo = '054-8-52216-1';

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
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'เบอร์โทร (9–10 หลัก)'),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 12),
                  // ส่วนแสดงบัญชีของทางแอป (ตำแหน่งเดียวกับหน้าต่างจอง)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('ธนาคาร : กสิกร'),
                            Text('ชื่อบัญชี : อภิรัตน์ โอชา'),
                            Text('เลขบัญชี : 054-8-52216-1',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                await Clipboard.setData(
                                    const ClipboardData(text: appAccountNo));
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text('คัดลอกเลขบัญชีแล้ว')),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('คัดลอก'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(imageUrl!,
                          height: 120, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    onPressed: busy ? null : pickAndUpload,
                    icon: const Icon(Icons.image),
                    label: Text(
                        imageUrl == null ? 'แนบรูปสลิป' : 'เปลี่ยนรูปสลิป'),
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
                onPressed: isValid() ? submit : null,
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
}
