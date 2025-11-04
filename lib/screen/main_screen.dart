import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:projectapp/myhome.dart';
import 'package:projectapp/mymember.dart';
import 'package:projectapp/mysupport.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _canHostParking = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdTokenResult(true);
    setState(() {
      final claims = token.claims ?? {};
      _canHostParking = claims['canHostParking'] == true;
      _isAdmin = claims['isAdmin'] == true;
      if (!(_canHostParking || _isAdmin) && _selectedIndex == 1) {
        _selectedIndex = 0; // fallback to first tab if member tab hidden
      }
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const MyHome(),
      if (_canHostParking || _isAdmin) const MyMember(),
      const MySupport(),
    ];

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.local_parking),
        label: 'หาเช่าที่จอดรถ',
      ),
      if (_canHostParking || _isAdmin)
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'ปล่อยเช่าที่จอดรถ',
        ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.support_agent),
        label: 'Support',
      ),
    ];

    final maxIndex = pages.length - 1;
    final currentIndex = _selectedIndex.clamp(0, maxIndex);
    return Scaffold(
      body: pages.elementAt(currentIndex),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.blue,
        items: navItems,
        currentIndex: currentIndex,
        selectedItemColor: const Color.fromARGB(255, 0, 0, 0),
        onTap: _onItemTapped,
      ),
    );
  }
}
