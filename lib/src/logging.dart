import 'package:logging/logging.dart';

/// Returns a namespaced logger for an internal analyzer subsystem.
Logger grumpyLogger(String subsystem) => Logger('grumpy_context.$subsystem');
