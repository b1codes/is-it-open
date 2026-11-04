import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A canned response, or an error to fail the request with.
class FakeResponse {
  const FakeResponse(this.statusCode, [this.body]) : error = null;

  /// Fails the request at the transport level (no response), e.g. a
  /// [DioExceptionType.connectionTimeout].
  const FakeResponse.error(DioExceptionType this.error)
    : statusCode = 0,
      body = null;

  final int statusCode;
  final Object? body;
  final DioExceptionType? error;
}

/// A Dio transport that records each request and answers from a route table
/// keyed by `METHOD /path` (path relative to the base URL, no query string).
/// Unrouted requests get a 404, so a typo shows up as a test failure.
class FakeHttpAdapter implements HttpClientAdapter {
  final Map<String, FakeResponse> routes = {};
  final List<RequestOptions> requests = [];

  void on(String method, String path, FakeResponse response) {
    routes['${method.toUpperCase()} $path'] = response;
  }

  RequestOptions get last => requests.last;

  /// The decoded JSON body of the last request.
  Object? get lastBody => last.data;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path.replaceFirst(
      Uri.parse(options.baseUrl).path,
      '',
    );
    final response = routes['${options.method} $path'];
    if (response == null) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'Not routed: ${options.method} $path'}),
        404,
        headers: _json,
      );
    }
    if (response.error != null) {
      throw DioException(
        requestOptions: options,
        type: response.error!,
        message: 'Simulated ${response.error!.name}',
      );
    }
    final body = response.body;
    if (body is String) {
      return ResponseBody.fromString(
        body,
        response.statusCode,
        headers: {
          Headers.contentTypeHeader: ['text/calendar'],
        },
      );
    }
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      response.statusCode,
      headers: _json,
    );
  }

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}
