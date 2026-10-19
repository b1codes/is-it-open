// Fixture data and the in-memory app scope, shared with the Widgetbook
// catalog so tests and previews render the same places, users and events.
//
// They live in the widgetbook package, which depends on this one, so they
// are imported by relative path rather than as a package (that would be a
// dependency cycle). Everything they import is also a dependency of this
// package.
export '../../widgetbook/lib/mocks/fake_api_service.dart';
export '../../widgetbook/lib/mocks/mock_app_scope.dart';
export '../../widgetbook/lib/mocks/sample_data.dart';
export '../../widgetbook/lib/mocks/seeded_blocs.dart';
