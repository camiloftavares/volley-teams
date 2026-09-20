import 'failure.dart';

/// Success value or [Failure]. Use cases and repositories return this instead
/// of throwing.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The success value. Only call after checking [isOk].
  T get value => (this as Ok<T>).data;

  /// The failure. Only call after checking [isErr].
  Failure get failure => (this as Err<T>).error;

  /// Re-wraps this failure for a different success type (early-return helper).
  Err<R> castErr<R>() => Err<R>(failure);

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final data) => onOk(data),
        Err<T>(:final error) => onErr(error),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.data);

  final T data;
}

final class Err<T> extends Result<T> {
  const Err(this.error);

  final Failure error;
}
