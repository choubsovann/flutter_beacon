import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_beacon_example/controller/requirement_state_controller.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_beacon_example/ibeacon.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:flu_wake_lock/flu_wake_lock.dart';
import 'package:permission_handler/permission_handler.dart';
import 'util.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FluWakeLock().enable();

  FlutterNativeSplash.remove();
  await Future.microtask(() async {
    if (Platform.isAndroid) {
      await Permission.locationWhenInUse.request();
      await Permission.bluetooth.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
    } else if (Platform.isIOS) {
      await Permission.locationWhenInUse.request();
      await Permission.bluetooth.request();
    }
  });
  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Get.put(RequirementStateController());

    final themeData = Theme.of(context);
    final primary = Colors.blue;

    return GetMaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: primary,
        appBarTheme: themeData.appBarTheme.copyWith(
          elevation: 0.5,
          color: Colors.white,
          actionsIconTheme: themeData.primaryIconTheme.copyWith(color: primary),
          iconTheme: themeData.primaryIconTheme.copyWith(color: primary),
        ),
      ),
      darkTheme: ThemeData(brightness: Brightness.dark, primarySwatch: primary),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Region> regions = [
    Region(
      identifier: 'branch-101',
      proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
      major: 10001,
      minor: 26247,
    ),
    Region(
      identifier: 'F01204B01CB3',
      proximityUUID: 'FFFE2D12-1E4B-0FA4-994E-CEB531F40545',
      major: 45852,
      minor: 45161,
    ),
    Region(
      identifier: 'F01204B0086D',
      proximityUUID: 'FFFE2D12-1E4B-0FA4-994E-CEB531F40545',
      major: 27912,
      minor: 45060,
    ),
    Region(
      identifier: 'F01204B00866',
      proximityUUID: 'FFFE2D12-1E4B-0FA4-994E-CEB531F40545',
      major: 26120,
      minor: 45060,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: regions
              .map(
                (e) => ListTile(
                  title: Text(e.identifier),
                  subtitle: Text(
                    'UUID: ${e.proximityUUID}\nmajor: ${e.major}\nminor: ${e.minor}',
                  ),
                  onTap: () => Get.to(() => IBeaconTestScreen(regions: [e])),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
