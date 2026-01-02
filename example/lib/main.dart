import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_beacon_example/controller/requirement_state_controller.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
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
  StreamSubscription? _monitorSub;
  final _beaconNotifier = ValueNotifier<List<Beacon>>([]);
  final _monitorNotifier =
      ValueNotifier<MonitoringState>(MonitoringState.outside);
      List<Region> regions = [
      Region(
        identifier: 'branch-101',
        proximityUUID: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
        major: 10001,
        minor: 26247,
      ),
    ];

  @override
  void initState() {
    super.initState();

    

    Future.microtask(() async {
      await flutterBeacon.initializeScanning;
      _monitorSub =
          flutterBeacon.monitoring(regions).listen((MonitoringResult result) {
        if (result.monitoringState == null) return;

        _monitorNotifier.value =
            result.monitoringState ?? MonitoringState.outside;

        if (result.monitoringState == MonitoringState.outside) {
          _beaconNotifier.value = [];
        }
      });
      _sub = flutterBeacon.ranging(regions).listen((RangingResult result) {
        if (result.beacons.isEmpty) return;

        _beaconNotifier.value = result.beacons;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _monitorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('iBeacon')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status Indicator
              StreamBuilder(stream: flutterBeacon.bluetoothStateChanged(), builder: (_, s){
                return Text('${s.connectionState}');
              }),

               StreamBuilder(stream: flutterBeacon.authorizationStatusChanged(), builder: (_, s){
                return Text('${s.connectionState}');
              }),

              SizedBox(height: 10),

              ValueListenableBuilder(
                valueListenable: _monitorNotifier,
                builder: (_, MonitoringState status, w) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: status == MonitoringState.inside
                          ? Colors.green
                          : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status == MonitoringState.inside
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: Colors.white,
                          size: 32,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Status: ${status == MonitoringState.inside ? 'Inside' : 'Outside'}',
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
              Expanded(
                child: SingleChildScrollView(
                  child: ValueListenableBuilder(
                      valueListenable: _beaconNotifier,
                      builder: (_, List<Beacon> beacons, w) {
                        if(beacons.isEmpty){
                          return Center(child: Text('No iBeacon detected'));
                        }

                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(beacons.length, (i) {
                              final v = beacons[i];

                              return Container(
                                width: MediaQuery.of(context).size.width,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text.rich(
                                    TextSpan(
                                      style: TextStyle(fontSize: 12),
                                      children: [
                                        TextSpan(
                                          text: '${v.proximityUUID}\n',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        TextSpan(
                                          text:
                                              'Major: ${v.major}\nMinor: ${v.minor}\nRSSI: ${v.rssi} dBm (${rssiToLevel(v.rssi).str})',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }));
                      }),
                ),
              ),
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
