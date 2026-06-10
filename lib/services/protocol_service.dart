import 'dart:convert';
import 'dart:typed_data';

class ProtocolPacket {
  final String type;
  final Uint8List payload;

  ProtocolPacket({required this.type, required this.payload});
}

class ProtocolService {
  static const String appId = 'lan_share';
  static const int protocolVersion = 1;
  static const int maxTypeLength = 64;
  static const int maxPayloadLength = 8 * 1024 * 1024;

  static Uint8List createPacket(String type, List<int> payload) {
    final typeBytes = utf8.encode(type);

    if (typeBytes.isEmpty || typeBytes.length > maxTypeLength) {
      throw ArgumentError.value(type, 'type', 'Invalid packet type length');
    }

    if (payload.length > maxPayloadLength) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'Packet payload is too large',
      );
    }

    final builder = BytesBuilder();

    builder.addByte(typeBytes.length);

    builder.add(typeBytes);

    final lengthBytes = ByteData(8);

    lengthBytes.setUint64(0, payload.length, Endian.big);

    builder.add(lengthBytes.buffer.asUint8List());

    builder.add(payload);

    return builder.toBytes();
  }

  static List<ProtocolPacket> extractPackets(BytesBuilder buffer) {
    final packets = <ProtocolPacket>[];

    while (true) {
      final bytes = buffer.toBytes();

      if (bytes.length < 9) {
        break;
      }

      final typeLength = bytes[0];

      if (typeLength == 0 || typeLength > maxTypeLength) {
        buffer.clear();
        break;
      }

      if (bytes.length < 1 + typeLength + 8) {
        break;
      }

      final type = utf8.decode(bytes.sublist(1, 1 + typeLength));

      final lengthData = ByteData.sublistView(
        Uint8List.fromList(bytes.sublist(1 + typeLength, 1 + typeLength + 8)),
      );

      final payloadLength = lengthData.getUint64(0, Endian.big);

      if (payloadLength > maxPayloadLength) {
        buffer.clear();
        break;
      }

      final totalPacketSize = 1 + typeLength + 8 + payloadLength;

      if (bytes.length < totalPacketSize) {
        break;
      }

      final payload = Uint8List.fromList(
        bytes.sublist(1 + typeLength + 8, totalPacketSize),
      );

      packets.add(ProtocolPacket(type: type, payload: payload));

      final remaining = bytes.sublist(totalPacketSize);

      buffer.clear();

      buffer.add(remaining);
    }

    return packets;
  }
}
