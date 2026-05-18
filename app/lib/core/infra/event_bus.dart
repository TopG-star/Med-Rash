import 'dart:async';

class EventBus {
  final StreamController<Object> _controller =
      StreamController<Object>.broadcast();

  Stream<T> on<T>() => _controller.stream.where((Object event) => event is T).cast<T>();

  void emit(Object event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}