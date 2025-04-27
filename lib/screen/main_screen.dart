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

  static const List<Widget> _widgetOptions = <Widget>[
    myhome(),
    mymember(),
    mysupport(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.blue,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.local_parking),
            label: 'หาเช่าที่จอดรถ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'ปล่อยเช่าที่จอดรถ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.support_agent),
            label: 'Support',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color.fromARGB(255, 0, 0, 0),
        onTap: _onItemTapped,
      ),
    );
  }
}
