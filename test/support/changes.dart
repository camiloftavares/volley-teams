import 'dart:async';

/// Lets in-memory fakes offer `watch*` streams: each subscriber immediately
/// gets the current value and a new one after every [notify].
class Changes {
  final _controller = StreamController<void>.broadcast(sync: true);

  void notify() => _controller.add(null);

  Stream<T> watch<T>(T Function() read) {
    late final StreamController<T> out;
    StreamSubscription<void>? subscription;
    out = StreamController<T>(
      onListen: () {
        out.add(read());
        subscription = _controller.stream.listen((_) => out.add(read()));
      },
      onCancel: () => subscription?.cancel(),
    );
    return out.stream;
  }
}
