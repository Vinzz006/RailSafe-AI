class AppError implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  AppError(this.message, {this.code, this.details});

  @override
  String toString() => code != null ? "[$code] $message" : message;
}

class BleConnectionException extends AppError {
  BleConnectionException(super.message, {super.code, super.details});
}

class BlePermissionException extends AppError {
  BlePermissionException(super.message, {super.code, super.details});
}

class MalformedDataException extends AppError {
  MalformedDataException(super.message, {super.code, super.details});
}

class AuthException extends AppError {
  AuthException(super.message, {super.code, super.details});
}

class SyncException extends AppError {
  SyncException(super.message, {super.code, super.details});
}
