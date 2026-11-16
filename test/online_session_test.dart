import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shine/online/active_room_store.dart';
import 'package:shine/online/room_revision_tracker.dart';

void main() {
  const roomId = '12345678-1234-1234-1234-123456789abc';
  const playerId = 'guest-account-123';
  const session = ActiveOnlineRoom(
    roomId: roomId, roomCode: 'ABC123', playerId: playerId,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Room survives SharedPreferences reload and is tied to owner', () async {
    await ActiveOnlineRoomStore.save(session);
    final restored = await ActiveOnlineRoomStore.read();
    expect(restored?.roomId, roomId);
    expect(restored?.roomCode, 'ABC123');
    expect(restored?.playerId, playerId);
    expect(restored!.mayResume(playerId, {
      'id': roomId, 'host_id': 'host-account', 'guest_id': playerId,
      'status': 'waiting',
    }), isTrue);
    expect(restored.mayResume(playerId, {
      'id': roomId, 'host_id': 'host-account', 'guest_id': playerId,
      'status': 'playing',
    }), isTrue);
    expect(restored.mayResume('another-browser-account', {
      'id': roomId, 'host_id': 'host-account', 'guest_id': playerId,
      'status': 'playing',
    }), isFalse);
    expect(restored.mayResume(playerId, {
      'id': roomId, 'host_id': 'host-account', 'guest_id': playerId,
      'status': 'finished',
    }), isFalse);
  });

  test('Cannot reopen room when logged in user is not a participant', () {
    expect(session.mayResume(playerId, {
      'id': roomId, 'host_id': 'host-account', 'guest_id': 'other-account',
      'status': 'playing',
    }), isFalse);
  });

  test('Explicit exit clears the auto-resume hint', () async {
    await ActiveOnlineRoomStore.save(session);
    await ActiveOnlineRoomStore.clear();
    expect(await ActiveOnlineRoomStore.read(), isNull);
  });

  test('Closing a stale tab never clears a newer active room', () async {
    await ActiveOnlineRoomStore.save(session);
    await ActiveOnlineRoomStore.clearIfRoom('00000000-0000-0000-0000-000000000000');
    expect((await ActiveOnlineRoomStore.read())?.roomId, roomId);
    await ActiveOnlineRoomStore.clearIfRoom(roomId);
    expect(await ActiveOnlineRoomStore.read(), isNull);
  });

  test('Corrupted persisted hint does not crash startup', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ActiveOnlineRoomStore.key, 'bad JSON {');
    expect(await ActiveOnlineRoomStore.read(), isNull);
  });

  test('A guest sees reveal and playing revisions; stale HTTP is ignored', () {
    final revisions = RoomRevisionTracker();
    expect(revisions.accept({'revision': 7, 'status': 'waiting',
      'lobby_phase': 'draft'}), isTrue);
    expect(revisions.accept({'revision': 8, 'status': 'waiting',
      'lobby_phase': 'reveal'}), isTrue);
    expect(revisions.accept({'revision': 9, 'status': 'playing',
      'lobby_phase': 'reveal'}), isTrue);
    expect(revisions.accept({'revision': 8, 'status': 'waiting',
      'lobby_phase': 'reveal'}), isFalse);
    expect(revisions.accept({'revision': 9, 'status': 'playing',
      'lobby_phase': 'reveal'}), isFalse);
  });
}
