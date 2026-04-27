import 'dart:async';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_beacon_example/util.dart';

class IBeaconTestScreen extends StatefulWidget {
  final List<Region> regions;
  const IBeaconTestScreen({required this.regions, Key? key}) : super(key: key);

  @override
  State<IBeaconTestScreen> createState() => _IBeaconTestScreenState();
}

class _IBeaconTestScreenState extends State<IBeaconTestScreen> {
  StreamSubscription? _sub;
  StreamSubscription? _monitorSub;
  final _beaconNotifier = ValueNotifier<List<Beacon>>([]);
  final _monitorNotifier = ValueNotifier<MonitoringState>(
    MonitoringState.outside,
  );

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await flutterBeacon.initializeScanning;
      _monitorSub = flutterBeacon.monitoring(widget.regions).listen((
        MonitoringResult result,
      ) {
        if (result.monitoringState == null) return;

        _monitorNotifier.value =
            result.monitoringState ?? MonitoringState.outside;

        if (result.monitoringState == MonitoringState.outside) {
          _beaconNotifier.value = [];
        }
      });
      _sub = flutterBeacon.ranging(widget.regions).listen((
        RangingResult result,
      ) {
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
              StreamBuilder(
                stream: flutterBeacon.bluetoothStateChanged(),
                builder: (_, s) {
                  return Text('${s.connectionState}');
                },
              ),

              StreamBuilder(
                stream: flutterBeacon.authorizationStatusChanged(),
                builder: (_, s) {
                  return Text('${s.connectionState}');
                },
              ),

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
                      if (beacons.isEmpty) {
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
                                        fontWeight: FontWeight.bold,
                                      ),
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
                        }),
                      );
                    },
                  ),
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
