import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key});

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  final _displayNameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  bool _busy = false;

  User? get user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

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
          TextField(
            controller: _displayNameCtl,
            decoration: const InputDecoration(
              labelText: 'ชื่อผู้ใช้',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _saveDisplayName,
            child: const Text('บันทึกชื่อผู้ใช้'),
          ),
          const Divider(height: 32),
          TextField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'อีเมล',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _saveEmail,
            child: const Text('บันทึกอีเมล'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _changePassword,
            child: const Text('เปลี่ยนรหัสผ่าน'),
          ),
          const Divider(height: 32),
          TextField(
            controller: _phoneCtl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'หมายเลขโทรศัพท์ (+66...)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _updatePhone,
            child: const Text('อัปเดตหมายเลขโทรศัพท์'),
          ),
        ],
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

  Future<void> _saveDisplayName() async {
    if (user == null) return;
    try {
      setState(() => _busy = true);
      await user!.updateDisplayName(_displayNameCtl.text.trim());
      await user!.reload();
      _hydrate();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกชื่อผู้ใช้เรียบร้อย')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกชื่อผู้ใช้ไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEmail() async {
    if (user == null) return;
    try {
      setState(() => _busy = true);
      await user!.updateEmail(_emailCtl.text.trim());
      await user!.reload();
      _hydrate();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตอีเมลเรียบร้อย')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (!mounted) return;
        _promptReauthAnd(() => user!.updateEmail(_emailCtl.text.trim()));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('อัปเดตอีเมลไม่สำเร็จ: ${e.message}')),
          );
        }
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

  Future<void> _updatePhone() async {
    if (user == null) return;
    final phone = _phoneCtl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกหมายเลขโทรศัพท์')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      String? verificationId;
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (cred) async {
          try {
            await user!.updatePhoneNumber(cred);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('อัปเดตหมายเลขโทรศัพท์เรียบร้อย')),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
