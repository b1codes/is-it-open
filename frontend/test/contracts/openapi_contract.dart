import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// The API contract the backend serves, `contracts/openapi.json` (see
/// contracts/README.md), with just enough JSON Schema support to check
/// requests against it and generate responses from it.
class OpenApiContract {
  OpenApiContract(this.document);

  /// Reads the committed contract. `flutter test` runs from `frontend/`.
  factory OpenApiContract.load() => OpenApiContract(
    jsonDecode(File('../contracts/openapi.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  final Map<String, dynamic> document;

  late final List<Operation> operations = [
    for (final MapEntry(key: path, value: methods)
        in (document['paths'] as Map<String, dynamic>).entries)
      for (final MapEntry(key: method, value: details)
          in (methods as Map<String, dynamic>).entries)
        Operation(
          this,
          method.toUpperCase(),
          path,
          details as Map<String, dynamic>,
        ),
  ];

  /// The operation a request for `METHOD /path` is routed to, if any.
  Operation? match(String method, String path) {
    for (final operation in operations) {
      if (operation.method == method && operation.matches(path)) {
        return operation;
      }
    }
    return null;
  }

  /// [schema] with a top-level `$ref` followed.
  Map<String, dynamic> resolve(Map<String, dynamic> schema) {
    final ref = schema[r'$ref'] as String?;
    if (ref == null) return schema;
    final name = ref.split('/').last;
    return resolve(document['components']['schemas'][name]);
  }

  /// Every way [value] breaks [schema], as `location: problem`. Unless
  /// [allowUnknown] lists them, object properties the schema doesn't define
  /// are errors too: the backend silently drops them, so a misspelled field
  /// would never arrive.
  List<String> validate(
    Map<String, dynamic> schema,
    Object? value, {
    String at = r'$',
    Set<String> allowUnknown = const {},
  }) {
    schema = resolve(schema);
    final anyOf = schema['anyOf'] as List?;
    if (anyOf != null) {
      final ok = anyOf.any(
        (option) =>
            validate(option, value, at: at, allowUnknown: allowUnknown).isEmpty,
      );
      return ok ? [] : ['$at: ${_describe(value)} matches no allowed type'];
    }

    final type = schema['type'] as String?;
    final errors = <String>[];
    switch (type) {
      case 'object':
        if (value is! Map) return ['$at: expected an object, got $value'];
        final properties = (schema['properties'] ?? {}) as Map;
        for (final name in (schema['required'] ?? []) as List) {
          if (!value.containsKey(name)) errors.add('$at.$name: missing');
        }
        for (final MapEntry(:key, value: field) in value.entries) {
          final fieldSchema = properties[key];
          if (fieldSchema == null) {
            if (!allowUnknown.contains(key)) {
              errors.add('$at.$key: not in the contract');
            }
            continue;
          }
          errors.addAll(validate(fieldSchema, field, at: '$at.$key'));
        }
      case 'array':
        if (value is! List) return ['$at: expected an array, got $value'];
        for (final (i, item) in value.indexed) {
          errors.addAll(validate(schema['items'], item, at: '$at[$i]'));
        }
      case 'string':
        if (value is! String) return ['$at: expected a string, got $value'];
        final pattern = schema['pattern'] as String?;
        if (pattern != null && !RegExp(pattern).hasMatch(value)) {
          errors.add('$at: "$value" does not match $pattern');
        }
        if (value.length < (schema['minLength'] ?? 0)) {
          errors.add('$at: "$value" is too short');
        }
      case 'integer':
        if (value is! int) return ['$at: expected an integer, got $value'];
        errors.addAll(_bounds(schema, value, at));
      case 'number':
        if (value is! num) return ['$at: expected a number, got $value'];
        errors.addAll(_bounds(schema, value, at));
      case 'boolean':
        if (value is! bool) return ['$at: expected a boolean, got $value'];
      case 'null':
        if (value != null) return ['$at: expected null, got $value'];
      case null:
        break; // any value
      default:
        throw UnsupportedError('Schema type $type at $at');
    }
    return errors;
  }

  List<String> _bounds(Map<String, dynamic> schema, num value, String at) => [
    if (schema['minimum'] case final num min when value < min)
      '$at: $value is below $min',
    if (schema['maximum'] case final num max when value > max)
      '$at: $value is above $max',
  ];

  static String _describe(Object? value) =>
      value is String ? '"$value"' : '$value';

  /// A value [schema] allows. [full] fills every property with a non-null
  /// value; otherwise only required properties are present and nullable
  /// values are null. Arrays get one item either way.
  Object? example(Map<String, dynamic> schema, {required bool full}) {
    schema = resolve(schema);
    if (schema['examples'] case [final first, ...]) return first;

    final anyOf = schema['anyOf'] as List?;
    if (anyOf != null) {
      final options = anyOf.cast<Map<String, dynamic>>();
      final nullable = options.any((o) => o['type'] == 'null');
      if (nullable && !full) return null;
      return example(
        options.firstWhere((o) => o['type'] != 'null'),
        full: full,
      );
    }

    switch (schema['type']) {
      case 'object':
        final properties = (schema['properties'] ?? {}) as Map<String, dynamic>;
        final required = ((schema['required'] ?? []) as List).toSet();
        return {
          for (final MapEntry(:key, :value) in properties.entries)
            if (full || required.contains(key)) key: example(value, full: full),
        };
      case 'array':
        return [example(schema['items'], full: full)];
      case 'string':
        if (schema['pattern'] != null) {
          throw StateError(
            'Add `examples` to the backend field with pattern '
            '${schema['pattern']} so a valid value can be generated.',
          );
        }
        return 'text';
      case 'integer':
        return (schema['minimum'] as num?)?.toInt() ?? 1;
      case 'number':
        // Not a whole number, so a model that casts it to int fails.
        final min = (schema['minimum'] as num?) ?? -1000;
        final max = (schema['maximum'] as num?) ?? 1000;
        return (min + max) / 2 + 0.5;
      case 'boolean':
        // Differs from the models' usual default (false) only when full.
        return full;
      case 'null':
        return null;
    }
    throw UnsupportedError('Cannot generate an example of $schema');
  }
}

class Operation {
  Operation(this.contract, this.method, this.path, this.details);

  final OpenApiContract contract;
  final String method;

  /// The path template, e.g. `/api/places/bookmarks/{tomtom_id}`.
  final String path;
  final Map<String, dynamic> details;

  String get label => '$method $path';

  late final RegExp _route = RegExp(
    '^${path.splitMapJoin(RegExp(r'\{[^}]+\}'), onMatch: (_) => '[^/]+', onNonMatch: RegExp.escape)}\$',
  );

  bool matches(String requestPath) => _route.hasMatch(requestPath);

  bool get needsAuth => (details['security'] as List?)?.isNotEmpty ?? false;

  List<Map<String, dynamic>> get queryParameters => [
    for (final p in (details['parameters'] ?? []) as List)
      if (p['in'] == 'query') p as Map<String, dynamic>,
  ];

  Map<String, dynamic>? get requestBody =>
      details['requestBody']?['content']?['application/json']?['schema'];

  Map<String, dynamic> get _responses => details['responses'];

  Iterable<int> get statuses => _responses.keys.map(int.parse);

  int get successStatus => statuses.firstWhere((s) => s >= 200 && s < 300);

  Iterable<int> get errorStatuses => statuses.where((s) => s >= 400);

  /// The media type and body schema documented for [status] (both null for
  /// a response without a body).
  (String?, Map<String, dynamic>?) response(int status) {
    final content = _responses['$status']['content'] as Map<String, dynamic>?;
    if (content == null) return (null, null);
    final MapEntry(key: mediaType, :value) = content.entries.single;
    return (mediaType, value['schema'] as Map<String, dynamic>);
  }
}

/// A Dio transport that plays the backend as the contract describes it. It
/// records every way a request departs from the contract in [violations] and
/// answers with a body generated from the documented response.
class ContractAdapter implements HttpClientAdapter {
  ContractAdapter(this.contract, {this.allowUnknownFields = const {}});

  final OpenApiContract contract;

  /// Body fields the app sends that the contract doesn't define, by
  /// operation label. The backend ignores them.
  final Map<String, Set<String>> allowUnknownFields;

  /// Generate every response field ([OpenApiContract.example]'s `full`).
  bool full = true;

  /// Answer with this documented status instead of the success one.
  int? status;

  final List<String> violations = [];

  /// Labels of the operations requested.
  final Set<String> called = {};

  /// The body of the last response, as sent.
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = '${options.method} ${options.uri.path}';
    final operation = contract.match(options.method, options.uri.path);
    if (operation == null) {
      violations.add('$request: not in the contract');
      return ResponseBody.fromString('', 404);
    }
    called.add(operation.label);
    _checkRequest(operation, options, request);

    final status = this.status ?? operation.successStatus;
    if (!operation.statuses.contains(status)) {
      throw ArgumentError('${operation.label} never returns $status');
    }
    final (mediaType, schema) = operation.response(status);
    if (schema == null) {
      lastBody = null;
      return ResponseBody.fromString('', status);
    }
    final body = contract.example(schema, full: full);
    final problems = contract.validate(schema, body, at: 'generated');
    if (problems.isNotEmpty) throw StateError(problems.join('\n'));
    lastBody = body;
    return ResponseBody.fromString(
      mediaType == Headers.jsonContentType ? jsonEncode(body) : body as String,
      status,
      headers: {
        Headers.contentTypeHeader: [mediaType!],
      },
    );
  }

  void _checkRequest(
    Operation operation,
    RequestOptions options,
    String request,
  ) {
    void violation(String problem) => violations.add('$request: $problem');

    final auth = options.headers['Authorization'] as String?;
    if (operation.needsAuth && !(auth?.startsWith('Bearer ') ?? false)) {
      violation('needs a bearer token');
    }

    final query = Map.of(options.uri.queryParameters);
    for (final parameter in operation.queryParameters) {
      final name = parameter['name'] as String;
      final raw = query.remove(name);
      if (raw == null) {
        if (parameter['required'] == true) violation('missing ?$name');
        continue;
      }
      final value = _parseQueryValue(parameter['schema'], raw);
      for (final problem in contract.validate(
        parameter['schema'],
        value,
        at: '?$name',
      )) {
        violation(problem);
      }
    }
    for (final name in query.keys) {
      violation('?$name is not in the contract');
    }

    final bodySchema = operation.requestBody;
    if (bodySchema == null) {
      if (options.data != null) violation('sends a body it does not take');
      return;
    }
    for (final problem in contract.validate(
      bodySchema,
      options.data,
      at: 'body',
      allowUnknown: allowUnknownFields[operation.label] ?? const {},
    )) {
      violation(problem);
    }
  }

  /// A query string value as the JSON type its schema expects, so it can be
  /// validated like a body value. Unparseable values stay strings and fail.
  Object? _parseQueryValue(Map<String, dynamic> schema, String raw) {
    schema = contract.resolve(schema);
    final types = [
      schema['type'],
      for (final option in (schema['anyOf'] ?? []) as List) option['type'],
    ];
    if (types.contains('integer')) return int.tryParse(raw) ?? raw;
    if (types.contains('number')) return num.tryParse(raw) ?? raw;
    if (types.contains('boolean')) {
      return switch (raw) {
        'true' => true,
        'false' => false,
        _ => raw,
      };
    }
    return raw;
  }

  @override
  void close({bool force = false}) {}
}
