// ignore: deprecated_member_use
import 'dart:cli';

T waitOn<T>(Future<T> future, {Duration? timeout}) {
  // ignore: deprecated_member_use
  return waitFor(future, timeout: timeout);
}
