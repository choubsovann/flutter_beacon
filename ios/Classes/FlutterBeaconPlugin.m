#import "FlutterBeaconPlugin.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import "FBUtils.h"
#import "FBBluetoothStateHandler.h"
#import "FBRangingStreamHandler.h"
#import "FBMonitoringStreamHandler.h"
#import "FBAuthorizationStatusHandler.h"

@interface FlutterBeaconPlugin() <CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralManagerDelegate>

@property (assign, nonatomic) CLAuthorizationStatus defaultLocationAuthorizationType;
@property (assign) BOOL shouldStartAdvertise;

@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CBCentralManager *bluetoothManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSMutableArray *regionRanging;
@property (strong, nonatomic) NSMutableArray *regionMonitoring;
@property (strong, nonatomic) NSDictionary *beaconPeripheralData;

@property (strong, nonatomic) FBRangingStreamHandler* rangingHandler;
@property (strong, nonatomic) FBMonitoringStreamHandler* monitoringHandler;
@property (strong, nonatomic) FBBluetoothStateHandler* bluetoothHandler;
@property (strong, nonatomic) FBAuthorizationStatusHandler* authorizationHandler;

@property FlutterResult flutterResult;
@property FlutterResult flutterBluetoothResult;
@property FlutterResult flutterBroadcastResult;

// Background task management
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTask;

@end

@implementation FlutterBeaconPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel methodChannelWithName:@"flutter_beacon"
                                                                binaryMessenger:[registrar messenger]];
    FlutterBeaconPlugin* instance = [[FlutterBeaconPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    
    instance.rangingHandler = [[FBRangingStreamHandler alloc] initWithFlutterBeaconPlugin:instance];
    FlutterEventChannel* streamChannelRanging =
    [FlutterEventChannel eventChannelWithName:@"flutter_beacon_event"
                              binaryMessenger:[registrar messenger]];
    [streamChannelRanging setStreamHandler:instance.rangingHandler];
    
    instance.monitoringHandler = [[FBMonitoringStreamHandler alloc] initWithFlutterBeaconPlugin:instance];
    FlutterEventChannel* streamChannelMonitoring =
    [FlutterEventChannel eventChannelWithName:@"flutter_beacon_event_monitoring"
                              binaryMessenger:[registrar messenger]];
    [streamChannelMonitoring setStreamHandler:instance.monitoringHandler];
    
    instance.bluetoothHandler = [[FBBluetoothStateHandler alloc] initWithFlutterBeaconPlugin:instance];
    FlutterEventChannel* streamChannelBluetooth =
    [FlutterEventChannel eventChannelWithName:@"flutter_bluetooth_state_changed"
                              binaryMessenger:[registrar messenger]];
    [streamChannelBluetooth setStreamHandler:instance.bluetoothHandler];
    
    instance.authorizationHandler = [[FBAuthorizationStatusHandler alloc] initWithFlutterBeaconPlugin:instance];
    FlutterEventChannel* streamChannelAuthorization =
    [FlutterEventChannel eventChannelWithName:@"flutter_authorization_status_changed"
                              binaryMessenger:[registrar messenger]];
    [streamChannelAuthorization setStreamHandler:instance.authorizationHandler];
    
    // Register for app lifecycle notifications
    [[NSNotificationCenter defaultCenter] addObserver:instance
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:instance
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (id)init {
    self = [super init];
    if (self) {
        // Earlier versions of flutter_beacon only supported "always" permission,
        // so set this as the default to stay backwards compatible.
        self.defaultLocationAuthorizationType = kCLAuthorizationStatusAuthorizedAlways;
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"initialize" isEqualToString:call.method]) {
        [self initializeLocationManager];
        [self initializeCentralManager];
        result(@(YES));
        return;
    }
    
    if ([@"initializeAndCheck" isEqualToString:call.method]) {
        [self initializeWithResult:result];
        return;
    }
    
    if ([@"setLocationAuthorizationTypeDefault" isEqualToString:call.method]) {
        if (call.arguments != nil && [call.arguments isKindOfClass:[NSString class]]) {
            NSString *argumentAsString = (NSString*)call.arguments;
            if ([@"ALWAYS" isEqualToString:argumentAsString]) {
                self.defaultLocationAuthorizationType = kCLAuthorizationStatusAuthorizedAlways;
                result(@(YES));
                return;
            }
            if ([@"WHEN_IN_USE" isEqualToString:argumentAsString]) {
                self.defaultLocationAuthorizationType = kCLAuthorizationStatusAuthorizedWhenInUse;
                result(@(YES));
                return;
            }
        }
        result(@(NO));
        return;
    }

    if ([@"authorizationStatus" isEqualToString:call.method]) {
        [self initializeLocationManager];
        
        switch ([CLLocationManager authorizationStatus]) {
            case kCLAuthorizationStatusNotDetermined:
                result(@"NOT_DETERMINED");
                break;
            case kCLAuthorizationStatusRestricted:
                result(@"RESTRICTED");
                break;
            case kCLAuthorizationStatusDenied:
                result(@"DENIED");
                break;
            case kCLAuthorizationStatusAuthorizedAlways:
                result(@"ALWAYS");
                break;
            case kCLAuthorizationStatusAuthorizedWhenInUse:
                result(@"WHEN_IN_USE");
                break;
        }
        return;
    }
    
    if ([@"checkLocationServicesIfEnabled" isEqualToString:call.method]) {
        result(@([CLLocationManager locationServicesEnabled]));
        return;
    }
    
    if ([@"bluetoothState" isEqualToString:call.method]) {
        self.flutterBluetoothResult = result;
        [self initializeCentralManager];
        
        // Delay 2 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.flutterBluetoothResult) {
                switch(self.bluetoothManager.state) {
                    case CBManagerStateUnknown:
                        self.flutterBluetoothResult(@"STATE_UNKNOWN");
                        break;
                    case CBManagerStateResetting:
                        self.flutterBluetoothResult(@"STATE_RESETTING");
                        break;
                    case CBManagerStateUnsupported:
                        self.flutterBluetoothResult(@"STATE_UNSUPPORTED");
                        break;
                    case CBManagerStateUnauthorized:
                        self.flutterBluetoothResult(@"STATE_UNAUTHORIZED");
                        break;
                    case CBManagerStatePoweredOff:
                        self.flutterBluetoothResult(@"STATE_OFF");
                        break;
                    case CBManagerStatePoweredOn:
                        self.flutterBluetoothResult(@"STATE_ON");
                        break;
                }
                self.flutterBluetoothResult = nil;
            }
        });
        return;
    }
    
    if ([@"requestAuthorization" isEqualToString:call.method]) {
        if (self.locationManager) {
            self.flutterResult = result;
            [self requestDefaultLocationManagerAuthorization];
        } else {
            result(@(YES));
        }
        return;
    }
    
    if ([@"openBluetoothSettings" isEqualToString:call.method]) {
        // do nothing - private API
        result(@(YES));
        return;
    }
    
    if ([@"openLocationSettings" isEqualToString:call.method]) {
        // do nothing - private API
        result(@(YES));
        return;
    }

    if ([@"setScanPeriod" isEqualToString:call.method]) {
        // do nothing
        result(@(YES));
        return;
    }

    if ([@"setBetweenScanPeriod" isEqualToString:call.method]) {
        // do nothing
        result(@(YES));
        return;
    }
    
    if ([@"openApplicationSettings" isEqualToString:call.method]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        result(@(YES));
        return;
    }
    
    if ([@"close" isEqualToString:call.method]) {
        [self stopRangingBeacon];
        [self stopMonitoringBeacon];
        result(@(YES));
        return;
    }
    
    if ([@"startBroadcast" isEqualToString:call.method]) {
        self.flutterBroadcastResult = result;
        [self startBroadcast:call.arguments];
        return;
    }
    
    if ([@"stopBroadcast" isEqualToString:call.method]) {
        if (self.peripheralManager) {
            [self.peripheralManager stopAdvertising];
        }
        result(nil);
        return;
    }
    
    if ([@"isBroadcasting" isEqualToString:call.method]) {
        if (self.peripheralManager) {
            result(@([self.peripheralManager isAdvertising]));
        } else {
            result(@(NO));
        }
        return;
    }
    
    if ([@"isBroadcastSupported" isEqualToString:call.method]) {
        result(@(YES));
        return;
    }
    
    result(FlutterMethodNotImplemented);
}

///------------------------------------------------------------
#pragma mark - App Lifecycle Management
///------------------------------------------------------------

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    NSLog(@"App entering background - ensuring beacon monitoring continues");
    
    // Request extended background execution time
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
    }
    
    self.backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"Background task expired");
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }];
    
    // Verify monitoring is active
    if (self.regionMonitoring && self.regionMonitoring.count > 0) {
        NSLog(@"Active monitoring regions: %lu", (unsigned long)self.regionMonitoring.count);
        for (CLBeaconRegion *region in self.regionMonitoring) {
            // Request state update for each region
            [self.locationManager requestStateForRegion:region];
        }
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    NSLog(@"App entering foreground");
    
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
    
    // Request state update for all monitored regions
    if (self.regionMonitoring && self.regionMonitoring.count > 0) {
        for (CLBeaconRegion *region in self.regionMonitoring) {
            [self.locationManager requestStateForRegion:region];
        }
    }
}

///------------------------------------------------------------
#pragma mark - Initialization
///------------------------------------------------------------

- (void) initializeCentralManager {
    if (!self.bluetoothManager) {
        // initialize central manager if it isn't
        self.bluetoothManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    }
}

- (void) initializeLocationManager {
    if (!self.locationManager) {
        // initialize location manager if it isn't
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        
        // CRITICAL: Enable background location updates for real-time monitoring
        self.locationManager.allowsBackgroundLocationUpdates = YES;
        self.locationManager.pausesLocationUpdatesAutomatically = NO;
        
        // CRITICAL: Set desired accuracy for better beacon detection
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        
        // CRITICAL: Set distance filter to receive updates more frequently
        self.locationManager.distanceFilter = kCLDistanceFilterNone;
        
        NSLog(@"Location Manager initialized with background updates enabled");
    }
}

- (void) startBroadcast:(id)arguments {
    NSDictionary *dict = arguments;
    NSNumber *measuredPower = nil;
    if (dict[@"txPower"] != [NSNull null]) {
        measuredPower = dict[@"txPower"];
    }
    CLBeaconRegion *region = [FBUtils regionFromDictionary:dict];
    
    self.shouldStartAdvertise = YES;
    self.beaconPeripheralData = [region peripheralDataWithMeasuredPower:measuredPower];
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
}

///------------------------------------------------------------
#pragma mark - Flutter Beacon Ranging
///------------------------------------------------------------

- (void) startRangingBeaconWithCall:(id)arguments {
    if (self.regionRanging) {
        [self.regionRanging removeAllObjects];
    } else {
        self.regionRanging = [NSMutableArray array];
    }
    
    NSArray *array = arguments;
    for (NSDictionary *dict in array) {
        CLBeaconRegion *region = [FBUtils regionFromDictionary:dict];
        
        if (region) {
            [self.regionRanging addObject:region];
        }
    }
    
    for (CLBeaconRegion *r in self.regionRanging) {
        NSLog(@"START RANGING: %@", r);
        [self.locationManager startRangingBeaconsInRegion:r];
    }
}

- (void) stopRangingBeacon {
    for (CLBeaconRegion *region in self.regionRanging) {
        NSLog(@"STOP RANGING: %@", region);
        [self.locationManager stopRangingBeaconsInRegion:region];
    }
    self.flutterEventSinkRanging = nil;
}

///------------------------------------------------------------
#pragma mark - Flutter Beacon Monitoring
///------------------------------------------------------------

- (void) startMonitoringBeaconWithCall:(id)arguments {
    if (self.regionMonitoring) {
        // Stop existing monitoring
        for (CLBeaconRegion *region in self.regionMonitoring) {
            [self.locationManager stopMonitoringForRegion:region];
        }
        [self.regionMonitoring removeAllObjects];
    } else {
        self.regionMonitoring = [NSMutableArray array];
    }
    
    NSArray *array = arguments;
    for (NSDictionary *dict in array) {
        CLBeaconRegion *region = [FBUtils regionFromDictionary:dict];
        
        if (region) {
            // CRITICAL FIX: Enable real-time notifications
            region.notifyOnEntry = YES;
            region.notifyOnExit = YES;
            region.notifyEntryStateOnDisplay = YES;
            
            [self.regionMonitoring addObject:region];
        }
    }
    
    // CRITICAL: Start location updates to keep monitoring active in background
    [self.locationManager startUpdatingLocation];
    
    for (CLBeaconRegion *r in self.regionMonitoring) {
        NSLog(@"START MONITORING: %@ (UUID: %@)", r.identifier, r.proximityUUID.UUIDString);
        [self.locationManager startMonitoringForRegion:r];
        
        // CRITICAL FIX: Request immediate state determination
        [self.locationManager requestStateForRegion:r];
    }
    
    NSLog(@"Total monitored regions: %lu", (unsigned long)[self.locationManager monitoredRegions].count);
}

- (void) stopMonitoringBeacon {
    for (CLBeaconRegion *region in self.regionMonitoring) {
        NSLog(@"STOP MONITORING: %@", region);
        [self.locationManager stopMonitoringForRegion:region];
    }
    
    // Stop location updates
    [self.locationManager stopUpdatingLocation];
    
    self.flutterEventSinkMonitoring = nil;
}

///------------------------------------------------------------
#pragma mark - Flutter Beacon Initialize
///------------------------------------------------------------

- (void) initializeWithResult:(FlutterResult)result {
    self.flutterResult = result;
    
    [self initializeLocationManager];
    [self initializeCentralManager];
}

///------------------------------------------------------------
#pragma mark - Bluetooth Manager Delegate
///------------------------------------------------------------

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    NSString *message = nil;
    NSString *stateString = nil;
    
    switch(central.state) {
        case CBManagerStateUnknown:
            stateString = @"STATE_UNKNOWN";
            message = @"CBManagerStateUnknown";
            break;
        case CBManagerStateResetting:
            stateString = @"STATE_RESETTING";
            message = @"CBManagerStateResetting";
            break;
        case CBManagerStateUnsupported:
            stateString = @"STATE_UNSUPPORTED";
            message = @"CBManagerStateUnsupported";
            break;
        case CBManagerStateUnauthorized:
            stateString = @"STATE_UNAUTHORIZED";
            message = @"CBManagerStateUnauthorized";
            break;
        case CBManagerStatePoweredOff:
            stateString = @"STATE_OFF";
            message = @"CBManagerStatePoweredOff";
            break;
        case CBManagerStatePoweredOn:
            stateString = @"STATE_ON";
            if ([CLLocationManager locationServicesEnabled]) {
                if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
                    [self requestDefaultLocationManagerAuthorization];
                    return;
                } else if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied) {
                    message = @"CLAuthorizationStatusDenied";
                } else if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusRestricted) {
                    message = @"CLAuthorizationStatusRestricted";
                } else {
                    // Authorization granted
                    message = nil;
                }
            } else {
                message = @"LocationServicesDisabled";
            }
            break;
    }
    
    NSLog(@"Bluetooth state changed: %@", stateString);
    
    if (self.flutterBluetoothResult) {
        self.flutterBluetoothResult(stateString);
        self.flutterBluetoothResult = nil;
        return;
    }
    
    if (self.flutterEventSinkBluetooth) {
        self.flutterEventSinkBluetooth(stateString);
    }
    
    if (self.flutterResult) {
        if (message) {
            self.flutterResult([FlutterError errorWithCode:@"Beacon" message:message details:nil]);
        } else {
            self.flutterResult(nil);
        }
    }
}

///------------------------------------------------------------
#pragma mark - Location Manager Delegate
///------------------------------------------------------------

- (void)requestDefaultLocationManagerAuthorization {
    switch (self.defaultLocationAuthorizationType) {
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            NSLog(@"Requesting When In Use authorization");
            [self.locationManager requestWhenInUseAuthorization];
            break;
        case kCLAuthorizationStatusAuthorizedAlways:
        default:
            NSLog(@"Requesting Always authorization");
            [self.locationManager requestAlwaysAuthorization];
            break;
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    NSString *message = nil;
    NSString *statusString = nil;
    
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways:
            statusString = @"ALWAYS";
            NSLog(@"Location authorization: Always");
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            statusString = @"WHEN_IN_USE";
            NSLog(@"Location authorization: When In Use");
            break;
        case kCLAuthorizationStatusDenied:
            statusString = @"DENIED";
            message = @"CLAuthorizationStatusDenied";
            NSLog(@"Location authorization: Denied");
            break;
        case kCLAuthorizationStatusRestricted:
            statusString = @"RESTRICTED";
            message = @"CLAuthorizationStatusRestricted";
            NSLog(@"Location authorization: Restricted");
            break;
        case kCLAuthorizationStatusNotDetermined:
            statusString = @"NOT_DETERMINED";
            message = @"CLAuthorizationStatusNotDetermined";
            NSLog(@"Location authorization: Not Determined");
            break;
    }
    
    if (self.flutterEventSinkAuthorization) {
        self.flutterEventSinkAuthorization(statusString);
    }
    
    if (self.flutterResult) {
        if (message) {
            self.flutterResult([FlutterError errorWithCode:@"Beacon" message:message details:nil]);
        } else {
            self.flutterResult(nil);
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // This keeps the location manager active and improves beacon detection
    // Particularly important for background monitoring
    if (locations.count > 0) {
        CLLocation *location = locations.lastObject;
        NSLog(@"Location update: %@", location);
    }
}

- (void)locationManager:(CLLocationManager*)manager didRangeBeacons:(NSArray*)beacons inRegion:(CLBeaconRegion*)region {
    if (self.flutterEventSinkRanging) {
        NSDictionary *dictRegion = [FBUtils dictionaryFromCLBeaconRegion:region];
        
        NSMutableArray *array = [NSMutableArray array];
        for (CLBeacon *beacon in beacons) {
            NSDictionary *dictBeacon = [FBUtils dictionaryFromCLBeacon:beacon];
            [array addObject:dictBeacon];
        }
        
        NSLog(@"Ranged %lu beacons in region: %@", (unsigned long)beacons.count, region.identifier);
        
        self.flutterEventSinkRanging(@{
            @"region": dictRegion,
            @"beacons": array
        });
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    NSLog(@"[ENTER] Region: %@", region.identifier);
    
    // CRITICAL: Start ranging immediately upon entry for better real-time detection
    if ([region isKindOfClass:[CLBeaconRegion class]]) {
        CLBeaconRegion *beaconRegion = (CLBeaconRegion *)region;
        [manager startRangingBeaconsInRegion:beaconRegion];
        NSLog(@"Started ranging beacons in region: %@", region.identifier);
    }
    
    if (self.flutterEventSinkMonitoring) {
        CLBeaconRegion *reg = nil;
        for (CLBeaconRegion *r in self.regionMonitoring) {
            if ([region.identifier isEqualToString:r.identifier]) {
                reg = r;
                break;
            }
        }
        
        if (reg) {
            NSDictionary *dictRegion = [FBUtils dictionaryFromCLBeaconRegion:reg];
            self.flutterEventSinkMonitoring(@{
                @"event": @"didEnterRegion",
                @"region": dictRegion
            });
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    NSLog(@"[EXIT] Region: %@", region.identifier);
    
    // Stop ranging when exiting region
    if ([region isKindOfClass:[CLBeaconRegion class]]) {
        CLBeaconRegion *beaconRegion = (CLBeaconRegion *)region;
        [manager stopRangingBeaconsInRegion:beaconRegion];
        NSLog(@"Stopped ranging beacons in region: %@", region.identifier);
    }
    
    if (self.flutterEventSinkMonitoring) {
        CLBeaconRegion *reg = nil;
        for (CLBeaconRegion *r in self.regionMonitoring) {
            if ([region.identifier isEqualToString:r.identifier]) {
                reg = r;
                break;
            }
        }
        
        if (reg) {
            NSDictionary *dictRegion = [FBUtils dictionaryFromCLBeaconRegion:reg];
            self.flutterEventSinkMonitoring(@{
                @"event": @"didExitRegion",
                @"region": dictRegion
            });
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
    NSString *stateString = nil;
    
    switch (state) {
        case CLRegionStateInside:
            stateString = @"INSIDE";
            NSLog(@"[STATE] INSIDE - %@", region.identifier);
            
            // Start ranging if we're inside the region
            if ([region isKindOfClass:[CLBeaconRegion class]]) {
                [manager startRangingBeaconsInRegion:(CLBeaconRegion *)region];
            }
            break;
        case CLRegionStateOutside:
            stateString = @"OUTSIDE";
            NSLog(@"[STATE] OUTSIDE - %@", region.identifier);
            
            // Stop ranging if we're outside the region
            if ([region isKindOfClass:[CLBeaconRegion class]]) {
                [manager stopRangingBeaconsInRegion:(CLBeaconRegion *)region];
            }
            break;
        default:
            stateString = @"UNKNOWN";
            NSLog(@"[STATE] UNKNOWN - %@", region.identifier);
            break;
    }
    
    if (self.flutterEventSinkMonitoring) {
        CLBeaconRegion *reg = nil;
        for (CLBeaconRegion *r in self.regionMonitoring) {
            if ([region.identifier isEqualToString:r.identifier]) {
                reg = r;
                break;
            }
        }
        
        if (reg) {
            NSDictionary *dictRegion = [FBUtils dictionaryFromCLBeaconRegion:reg];
            self.flutterEventSinkMonitoring(@{
                @"event": @"didDetermineStateForRegion",
                @"region": dictRegion,
                @"state": stateString
            });
        }
    }
}

// CRITICAL FIX: Handle monitoring failures
- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(nullable CLRegion *)region withError:(NSError *)error {
    NSLog(@"[ERROR] MONITORING FAILED for region: %@ - %@", region.identifier, error.localizedDescription);
    
    if (self.flutterEventSinkMonitoring) {
        CLBeaconRegion *reg = nil;
        for (CLBeaconRegion *r in self.regionMonitoring) {
            if ([region.identifier isEqualToString:r.identifier]) {
                reg = r;
                break;
            }
        }
        
        if (reg) {
            NSDictionary *dictRegion = [FBUtils dictionaryFromCLBeaconRegion:reg];
            self.flutterEventSinkMonitoring(@{
                @"event": @"monitoringDidFail",
                @"region": dictRegion,
                @"error": error.localizedDescription
            });
        }
    }
}

// CRITICAL FIX: Handle ranging failures
- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error {
    NSLog(@"[ERROR] RANGING FAILED for region: %@ - %@", region.identifier, error.localizedDescription);
    
    // Retry ranging after a short delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [manager startRangingBeaconsInRegion:region];
        NSLog(@"Retrying ranging for region: %@", region.identifier);
    });
}

// Handle location errors
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"[ERROR] Location Manager failed: %@", error.localizedDescription);
}

///------------------------------------------------------------
#pragma mark - Peripheral Manager Delegate
///------------------------------------------------------------

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    switch (peripheral.state) {
        case CBPeripheralManagerStatePoweredOn:
            NSLog(@"Peripheral Manager: Powered On");
            if (self.shouldStartAdvertise) {
                [peripheral startAdvertising:self.beaconPeripheralData];
                
                if (self.flutterBroadcastResult) {
                    self.flutterBroadcastResult(nil);
                    self.flutterBroadcastResult = nil;
                }
            }
            break;
        case CBPeripheralManagerStatePoweredOff:
            NSLog(@"Peripheral Manager: Powered Off");
            if (self.flutterBroadcastResult) {
                self.flutterBroadcastResult([FlutterError errorWithCode:@"Bluetooth"
                                                                message:@"Bluetooth is powered off"
                                                                details:nil]);
                self.flutterBroadcastResult = nil;
            }
            break;
        case CBPeripheralManagerStateUnsupported:
            NSLog(@"Peripheral Manager: Unsupported");
            if (self.flutterBroadcastResult) {
                self.flutterBroadcastResult([FlutterError errorWithCode:@"Bluetooth"
                                                                message:@"Bluetooth LE is not supported"
                                                                details:nil]);
                self.flutterBroadcastResult = nil;
            }
            break;
        case CBPeripheralManagerStateUnauthorized:
            NSLog(@"Peripheral Manager: Unauthorized");
            if (self.flutterBroadcastResult) {
                self.flutterBroadcastResult([FlutterError errorWithCode:@"Bluetooth"
                                                                message:@"Bluetooth is not authorized"
                                                                details:nil]);
                self.flutterBroadcastResult = nil;
            }
            break;
        default:
            break;
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    if (error) {
        NSLog(@"Failed to advertise beacon: %@", error.localizedDescription);
        if (self.flutterBroadcastResult) {
            self.flutterBroadcastResult([FlutterError errorWithCode:@"Broadcast"
                                                            message:error.localizedDescription
                                                            details:nil]);
            self.flutterBroadcastResult = nil;
        }
    } else {
        NSLog(@"Successfully started advertising beacon");
    }
}

@end