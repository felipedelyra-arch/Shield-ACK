/// Result algébrico mínimo. Não é uma biblioteca — são 40 linhas que evitam
/// uma dependência e um `try/catch` espalhado por toda a camada de apresentação.
sealed class Result<F, T> {
  const Result();

  bool get isOk => this is Ok<F, T>;

  T? get valueOrNull => switch (this) { Ok(:final value) => value, _ => null };

  F? get failureOrNull => switch (this) { Err(:final failure) => failure, _ => null };

  R fold<R>(R Function(F failure) onErr, R Function(T value) onOk) => switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  Result<F, R> map<R>(R Function(T value) f) => switch (this) {
        Ok(:final value) => Ok(f(value)),
        Err(:final failure) => Err(failure),
      };

  Future<Result<F, R>> flatMapAsync<R>(Future<Result<F, R>> Function(T value) f) async =>
      switch (this) {
        Ok(:final value) => await f(value),
        Err(:final failure) => Err(failure),
      };
}

final class Ok<F, T> extends Result<F, T> {
  const Ok(this.value);
  final T value;
}

final class Err<F, T> extends Result<F, T> {
  const Err(this.failure);
  final F failure;
}
