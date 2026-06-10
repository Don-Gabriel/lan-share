import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/services/protocol_service.dart';

void main() {
  test('extracts framed packets from partial buffers', () {
    final packet = ProtocolService.createPacket('message', [1, 2, 3]);
    final buffer = BytesBuilder();

    buffer.add(packet.sublist(0, 5));

    expect(ProtocolService.extractPackets(buffer), isEmpty);

    buffer.add(packet.sublist(5));

    final packets = ProtocolService.extractPackets(buffer);

    expect(packets, hasLength(1));
    expect(packets.single.type, 'message');
    expect(packets.single.payload, [1, 2, 3]);
  });

  test('extracts multiple packets and leaves incomplete tail buffered', () {
    final first = ProtocolService.createPacket('one', [1]);
    final second = ProtocolService.createPacket('two', [2]);
    final third = ProtocolService.createPacket('three', [3, 4]);
    final buffer = BytesBuilder();

    buffer.add([...first, ...second, ...third.sublist(0, 4)]);

    final packets = ProtocolService.extractPackets(buffer);

    expect(packets.map((packet) => packet.type), ['one', 'two']);

    buffer.add(third.sublist(4));

    final tail = ProtocolService.extractPackets(buffer);

    expect(tail.single.type, 'three');
    expect(tail.single.payload, [3, 4]);
  });

  test('rejects payloads above the frame size limit', () {
    expect(
      () => ProtocolService.createPacket(
        'large',
        Uint8List(ProtocolService.maxPayloadLength + 1),
      ),
      throwsArgumentError,
    );
  });
}
