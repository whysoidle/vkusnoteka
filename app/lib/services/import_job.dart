class ImportCancelled implements Exception {
  const ImportCancelled();
}

class ImportJob {
  bool cancelled = false;
  final List<void Function()> _listeners = [];
  void check() {
    if (cancelled) throw const ImportCancelled();
  }

  /// Returns a registration remover so completed stages do not retain resources.
  void Function() onCancel(void Function() listener) {
    if (cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      // One failed cleanup must not prevent the remaining resources closing.
      try {
        listener();
      } catch (_) {}
    }
  }
}
