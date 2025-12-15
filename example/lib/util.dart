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
