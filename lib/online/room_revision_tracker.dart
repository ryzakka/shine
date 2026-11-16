/// Ensures a late HTTP poll cannot overwrite a newer Realtime snapshot.
/// Also avoids rebuilding the arena when no room data has changed.
class RoomRevisionTracker {
  int? _revision;
  bool get hasSnapshot => _signature != null;
  String? _signature;

  bool accept(Map<String, dynamic>? room) {
    if (room == null) {
      if (_signature == 'absent') return false;
      _signature = 'absent';
      return true;
    }
    final rev = (room['revision'] as num?)?.toInt();
    if (rev != null && _revision != null && rev < _revision!) return false;
    final signature = '${rev ?? ''}|${room['status']}|${room['lobby_phase']}';
    if (signature == _signature) return false;
    _signature = signature;
    if (rev != null) _revision = rev;
    return true;
  }
}
