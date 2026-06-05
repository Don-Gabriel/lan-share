import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;

  Future<void> startListening({
    required Function(Map<String, dynamic>) onDeviceFound,
  }) async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45454);

    print('Listening on port 45454');

    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();

        if (datagram == null) return;

        try {
          final message = utf8.decode(datagram.data);

          final data = jsonDecode(message) as Map<String, dynamic>;

          onDeviceFound(data);
        } catch (_) {}
      }
    });
  }

  void startBroadcasting({required String name, required String ip}) {
    _broadcastTimer?.cancel();

    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      socket.broadcastEnabled = true;

      final packet = jsonEncode({'name': name, 'ip': ip});

      socket.send(
        utf8.encode(packet),
        InternetAddress('255.255.255.255'),
        45454,
      );

      socket.close();

      print('Broadcasted: $packet');
    });
  }

  void dispose() {
    _broadcastTimer?.cancel();
    _socket?.close();
  }
}
