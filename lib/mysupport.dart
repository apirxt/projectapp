import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:projectapp/screen/home.dart';
import 'package:projectapp/screen/account_profile.dart';

class mysupport extends StatefulWidget {
  const mysupport({super.key});

  @override
  State<mysupport> createState() => _mysupportState();
}

class _mysupportState extends State<mysupport> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Support'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account summary card
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
                if (mounted) setState(() {}); // refresh after return
              },
            ),
          ),

          const SizedBox(height: 16),
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
