mixin RepositoryMixin {
  Future<T> runOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      throw RepositoryFailure(error.toString());
    }
  }
}

class RepositoryFailure implements Exception {
  RepositoryFailure(this.message);

  final String message;

  @override
  String toString() => message;
}