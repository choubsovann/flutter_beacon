import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beacon_example/controller/requirement_state_controller.dart';
import 'package:flutter_beacon_example/view/home_page.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:flu_wake_lock/flu_wake_lock.dart';
import 'package:permission_handler/permission_handler.dart';

enum SignalLevel { veryStrong, strong, medium, weak, lost }

SignalLevel rssiToLevel(int rssi) {
  if (rssi >= -55) return SignalLevel.veryStrong;
  if (rssi >= -65) return SignalLevel.strong;
  if (rssi >= -75) return SignalLevel.medium;
  if (rssi >= -85) return SignalLevel.weak;
  return SignalLevel.lost;
}

extension SignalLevelExtension on SignalLevel {
  String get str {
    switch (this) {
      case SignalLevel.veryStrong:
        return 'Very Strong';
      case SignalLevel.strong:
        return 'Strong';
      case SignalLevel.medium:
        return 'Medium';
      case SignalLevel.weak:
        return 'Weak';
      case SignalLevel.lost:
        return 'Lost';
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.remove();
  FluWakeLock().enable();

  Future.microtask(() async {
    if (Platform.isAndroid) {
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
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
          actionsIconTheme: themeData.primaryIconTheme.copyWith(
            color: primary,
          ),
          iconTheme: themeData.primaryIconTheme.copyWith(
            color: primary,
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: primary,
      ),
      home: MyWidgetScreen(),
    );
  }
}

class MyWidgetScreen extends StatefulWidget {
  const MyWidgetScreen({Key? key}) : super(key: key);

  @override
  State<MyWidgetScreen> createState() => _MyWidgetScreenState();
}

class _MyWidgetScreenState extends State<MyWidgetScreen> {
  StreamSubscription? _sub;
  final distanceNotifier = ValueNotifier<double>(0);
  final rssiNotifier = ValueNotifier<int>(0);
  final statusNotifier = ValueNotifier<bool>(false);
  final double inThreshold = 2.0;

  @override
  void initState() {
    super.initState();

    final regions = [
      Region(
        identifier: 'branch-101',
        proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
        major: 10001,
        minor: 26247,
      ),
    ];

    Future.microtask(() async {
      await flutterBeacon.initializeScanning;
      _sub = flutterBeacon.ranging(regions).listen((RangingResult result) {
        if (result.beacons.isEmpty) {
          return;
        }

        final beacon = result.beacons.first;
        distanceNotifier.value = beacon.accuracy;
        rssiNotifier.value = beacon.rssi;
        statusNotifier.value =
            beacon.accuracy >= 0 && beacon.accuracy <= inThreshold;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Widget Screen'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status Indicator
              ValueListenableBuilder(
                valueListenable: statusNotifier,
                builder: (_, bool status, w) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: status ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status ? Icons.check_circle : Icons.cancel,
                          color: Colors.white,
                          size: 32,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Status: $status',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              SizedBox(height: 32),
              ValueListenableBuilder(
                  valueListenable: distanceNotifier,
                  builder: (_, double v, w) {
                    return Center(
                      child: Text(
                        'Distance: ${v.toStringAsFixed(2)} m\n',
                        style: TextStyle(fontSize: 18),
                      ),
                    );
                  }),
              ValueListenableBuilder(
                  valueListenable: rssiNotifier,
                  builder: (_, int v, w) {
                    return Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(child: signalBars(rssiToLevel(v))),
                          SizedBox(width: 16),
                          Expanded(
                              child: Text(
                            'RSSI: $v dBm (${rssiToLevel(v).str})',
                            style: TextStyle(fontSize: 16),
                          )),
                        ],
                      ),
                    );
                  }),
            ],
          ),
        ),
      ),
    );
  }

  Widget signalBars(SignalLevel level) {
    int activeBars;
    switch (level) {
      case SignalLevel.veryStrong:
        activeBars = 4;
        break;
      case SignalLevel.strong:
        activeBars = 3;
        break;
      case SignalLevel.medium:
        activeBars = 2;
        break;
      case SignalLevel.weak:
        activeBars = 1;
        break;
      default:
        activeBars = 0;
    }

    return Row(
      children: List.generate(4, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 8,
          height: (i + 1) * 10,
          decoration: BoxDecoration(
            color: i < activeBars ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
