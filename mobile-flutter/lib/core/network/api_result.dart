import 'api_exception.dart';

/// Hasil operasi lapisan data — sukses [Ok] atau gagal [Err].
/// Menghindari lempar exception ke lapisan presentation (aliran eksplisit).
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(ApiException error) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>() => ok(self.value),
      Err<T>() => err(self.error),
    };
  }

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.error);
  final ApiException error;
}
