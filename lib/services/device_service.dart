import '../models/device.dart';

class DeviceService {
  List<Device> getDevices() {
    return [
      Device(name: 'Windows PC', ip: '192.168.1.10'),
      Device(name: 'Android Phone', ip: '192.168.1.20'),
    ];
  }
}
