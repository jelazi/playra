import 'package:flutter_test/flutter_test.dart';
import 'package:playra/services/lan_sync_service.dart';

void main() {
  test('start binds the sync sockets on the host platform', () async {
    await expectLater(LanSyncService.instance.start(), completes);
  });

  test('start can be called repeatedly and concurrently', () async {
    await expectLater(Future.wait([LanSyncService.instance.start(), LanSyncService.instance.start()]), completes);
    await expectLater(LanSyncService.instance.start(), completes);
  });
}
