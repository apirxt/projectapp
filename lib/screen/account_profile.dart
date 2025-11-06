//ส่วนนำเข้าแพ็กเกจ
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:projectapp/screen/home.dart';

//ส่วนหน้าจัดการโปรไฟล์ผู้ใช้ (ชื่อ อีเมล โทรศัพท์ รูปโปรไฟล์)
class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key});

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  //ส่วนตัวควบคุมข้อมูลโปรไฟล์
  final _displayNameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  bool _busy = false;

  User? get user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
  _hydrate(); //ส่วนโหลดข้อมูลผู้ใช้ปัจจุบันใส่ในช่องกรอก
  }

  //ส่วนดึงข้อมูลจาก user ใส่ controller
  void _hydrate() {
    _displayNameCtl.text = user?.displayName ?? '';
    _emailCtl.text = user?.email ?? '';
    _phoneCtl.text = user?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _displayNameCtl.dispose();
    _emailCtl.dispose();
    _phoneCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('บัญชีของฉัน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          //ส่วนภาพโปรไฟล์และปุ่มเปลี่ยนรูป
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage:
                      (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                          ? NetworkImage(user!.photoURL!)
                          : null,
                  child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: _busy ? null : _changePhoto,
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          //ส่วนช่องกรอกชื่อ
          TextField(
            controller: _displayNameCtl,
            decoration: const InputDecoration(
              labelText: 'ชื่อผู้ใช้',
              border: OutlineInputBorder(),
            ),
          ),
          const Divider(height: 32),
          //ส่วนช่องกรอกอีเมล
          TextField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'อีเมล',
              border: OutlineInputBorder(),
            ),
          ),
          const Divider(height: 32),
          //ส่วนช่องกรอกหมายเลขโทรศัพท์
          TextField(
            controller: _phoneCtl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'หมายเลขโทรศัพท์ (+66...)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              //ส่วนปุ่มบันทึกการเปลี่ยนแปลง
              ElevatedButton(
                onPressed: _busy ? null : _saveAll,
                child: const Text('บันทึกการเปลี่ยนแปลง'),
              ),
              const SizedBox(height: 8),
              //ส่วนปุ่มเปลี่ยนรหัสผ่าน
              OutlinedButton(
                onPressed: _busy ? null : _changePassword,
                child: const Text('เปลี่ยนรหัสผ่าน'),
              ),
              const SizedBox(height: 8),
              //ส่วนปุ่มออกจากระบบ
              TextButton(
                onPressed: _busy ? null : _signOut,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('ออกจากระบบ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changePhoto() async {
    try {
      setState(() => _busy = true);
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final file = File(x.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos/${user!.uid}.jpg');
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();
      await user!.updatePhotoURL(url);
      await user!.reload();
      _hydrate();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตรูปโปรไฟล์เรียบร้อย')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('อัปโหลดรูปโปรไฟล์ล้มเหลว: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (user == null) return;
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปลี่ยนรหัสผ่าน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      setState(() => _busy = true);
      final cred = EmailAuthProvider.credential(
          email: user!.email!, password: current.text);
      await user!.reauthenticateWithCredential(cred);
      await user!.updatePassword(next.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปลี่ยนรหัสผ่านเรียบร้อย')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เปลี่ยนรหัสผ่านไม่สำเร็จ: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAll() async {
    if (user == null) return;
    final currentName = user!.displayName ?? '';
    final currentEmail = user!.email ?? '';
    final currentPhone = user!.phoneNumber ?? '';

    final newName = _displayNameCtl.text.trim();
    final newEmail = _emailCtl.text.trim();
    final newPhone = _phoneCtl.text.trim();

    final wantsName = newName.isNotEmpty && newName != currentName;
    final wantsEmail = newEmail.isNotEmpty && newEmail != currentEmail;
    final wantsPhone = newPhone.isNotEmpty && newPhone != currentPhone;

    if (!wantsName && !wantsEmail && !wantsPhone) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีการเปลี่ยนแปลง')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
  //ส่วนขั้นตอน 1: อัปเดตชื่อ (ถ้าเปลี่ยน)
      if (wantsName) {
        await user!.updateDisplayName(newName);
      }

  //ส่วนขั้นตอน 2: อัปเดตอีเมล (ส่งลิงก์ยืนยัน)
      if (wantsEmail) {
        try {
          await user!.verifyBeforeUpdateEmail(newEmail);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ส่งอีเมลยืนยันไปยังอีเมลใหม่แล้ว')),
            );
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            //ส่วนปล่อย busy ชั่วคราวเพื่อเข้า dialog re-auth
            if (mounted) setState(() => _busy = false);
            await _promptReauthAnd(
                () => user!.verifyBeforeUpdateEmail(newEmail));
            if (!mounted) return;
            setState(() => _busy = true);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('อัปเดตอีเมลไม่สำเร็จ: ${e.message}')),
              );
            }
          }
        }
      }

  //ส่วนขั้นตอน 3: อัปเดตหมายเลขโทรศัพท์ (OTP)
      if (wantsPhone) {
        String? verificationId;
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: newPhone,
          verificationCompleted: (cred) async {
            try {
              await user!.updatePhoneNumber(cred);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('อัปเดตหมายเลขโทรศัพท์เรียบร้อย')),
                );
              }
            } catch (_) {}
          },
          verificationFailed: (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('ยืนยันหมายเลขล้มเหลว: ${e.message}')),
              );
            }
          },
          codeSent: (vid, _) async {
            verificationId = vid;
            final codeCtl = TextEditingController();
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('กรอกรหัสยืนยัน (SMS)'),
                content: TextField(
                  controller: codeCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'รหัส 6 หลัก'),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ยกเลิก')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('ยืนยัน')),
                ],
              ),
            );
            if (ok == true && verificationId != null) {
              try {
                final cred = PhoneAuthProvider.credential(
                    verificationId: verificationId!,
                    smsCode: codeCtl.text.trim());
                await user!.updatePhoneNumber(cred);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('อัปเดตหมายเลขโทรศัพท์เรียบร้อย')),
                  );
                }
              } on FirebaseAuthException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('อัปเดตหมายเลขไม่สำเร็จ: ${e.message}')),
                  );
                }
              }
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        );
  // ธง done เป็นการบอกสถานะคร่าวๆ บาง flow อาจเสร็จหลัง callback ได้
      }

      await user!.reload();
      _hydrate();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลเรียบร้อย')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _promptReauthAnd(Future<void> Function() action) async {
    final passCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันตัวตนอีกครั้ง'),
        content: TextField(
          controller: passCtl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      setState(() => _busy = true);
      final cred = EmailAuthProvider.credential(
          email: user!.email!, password: passCtl.text);
      await user!.reauthenticateWithCredential(cred);
      await action();
      await user!.reload();
      _hydrate();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตข้อมูลเรียบร้อย')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('การยืนยันตัวตนล้มเหลว: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
