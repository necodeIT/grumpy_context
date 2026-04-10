import 'dart:io';

import 'package:grumpy_context/grumpy_context.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() async {
  group('analyzeProject', () {
    test('analyzes a module under lib with grouped dependencies', () async {
      final project = await _createProject(
        pubspec: _pubspecWithDependencies,
        files: <String, String>{
          'lib/auth/domain/models/user.dart': 'class User {}',
          'lib/auth/presentation/screens/login_screen.dart':
              'class LoginScreen {}',
        },
      );

      final context = await analyzeProject(project.path);
      final module = context.modules.singleWhere((item) => item.name == 'auth');

      expect(context.name, 'sample_app');
      expect(
        context.dependencies.dependencies.map((item) => item.name),
        containsAll(<String>[
          'flutter',
          'git_pkg',
          'hosted_pkg',
          'http',
          'local_pkg',
        ]),
      );
      expect(context.dependencies.devDependencies.single.name, 'test');
      expect(
        context.dependencies.dependencyOverrides.single.name,
        'override_pkg',
      );
      expect(
        module.categories[ModuleCategory.domainModels]!.files,
        contains('lib/auth/domain/models/user.dart'),
      );
      expect(
        module.categories[ModuleCategory.presentationScreens]!.directoryPath,
        'lib/auth/presentation/screens',
      );
      expect(
        context.diagnostics.any((item) => item.code == 'partial_module'),
        isTrue,
      );
    });

    test('analyzes a module under lib/src', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/src/billing/domain/services/billing_service.dart':
              'abstract class BillingService {}',
        },
      );

      final context = await analyzeProject(project.path);
      final module = context.modules.singleWhere(
        (item) => item.name == 'billing',
      );

      expect(module.rootPath, 'lib/src/billing');
      expect(
        module.categories[ModuleCategory.domainServices]!.files,
        contains('lib/src/billing/domain/services/billing_service.dart'),
      );
    });

    test('discovers typed units, contracts, and module config types', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/src/app/app.dart': '''
import 'package:grumpy_flutter/grumpy_flutter.dart';

class App extends AppModule<AppConfig> {
  App(super.cfg);

  @override
  Screen get notFoundScreen => NotFoundScreen();

  @override
  Widget buildApp() => throw UnimplementedError();
}
''',
          'lib/src/app/domain/models/app_config.dart': '''
class AppConfig {}
''',
          'lib/src/app/presentation/screens/not_found_screen.dart': '''
class NotFoundScreen {}
''',
          'lib/src/auth/auth.dart': '''
import 'package:grumpy_flutter/grumpy_flutter.dart';

class Auth extends Module<AppConfig> {
  @override
  List<FlutterRoute<AppConfig>> get routes => const [];

  @override
  String get logTag => 'Auth';
}
''',
          'lib/src/auth/domain/services/auth_service.dart': '''
import 'package:grumpy/grumpy.dart';

abstract class AuthService extends Service {
  factory AuthService() {
    return Service.get<AuthService>();
  }

  @override
  String get group => '\${super.group}.AuthService';
}
''',
          'lib/src/auth/infra/services/local_auth_service.dart': '''
import 'package:grumpy/grumpy.dart';

class LocalAuthService extends AuthService {
  @override
  String get logTag => 'LocalAuthService';
}
''',
          'lib/src/auth/presentation/guards/auth_guard.dart': '''
import 'package:grumpy_flutter/grumpy_flutter.dart';

class AuthGuard extends Guard<AppConfig> {
  const AuthGuard({super.redirectTo});

  @override
  Future<bool> canActivate(RouteContext context) async => true;

  @override
  String get logTag => 'AuthGuard';

  @override
  String toString() => logTag;
}
''',
          'lib/src/auth/presentation/middleware/session_middleware.dart': '''
import 'package:flutter/widgets.dart';
import 'package:grumpy_flutter/grumpy_flutter.dart';

class SessionMiddleware extends Middleware<Widget, AppConfig> {
  const SessionMiddleware();

  @override
  Future<RouteContext> call(RouteContext context) async => context;

  @override
  String get logTag => 'SessionMiddleware';

  @override
  String toString() => logTag;
}
''',
        },
      );

      final context = await analyzeProject(project.path);

      final appUnit = context.units.singleWhere(
        (unit) => unit.kind == ProjectUnitKind.appModule,
      );
      final moduleUnit = context.units.singleWhere(
        (unit) => unit.kind == ProjectUnitKind.module,
      );
      final domainService = context.units.singleWhere(
        (unit) => unit.name == 'AuthService',
      );
      final infraService = context.units.singleWhere(
        (unit) => unit.name == 'LocalAuthService',
      );
      final guard = context.units.singleWhere(
        (unit) => unit.name == 'AuthGuard',
      );
      final middleware = context.units.singleWhere(
        (unit) => unit.name == 'SessionMiddleware',
      );

      expect(appUnit.configType, 'AppConfig');
      expect(moduleUnit.configType, 'AppConfig');
      expect(domainService.kind, ProjectUnitKind.domainService);
      expect(infraService.kind, ProjectUnitKind.infraService);
      expect(infraService.contractName, 'AuthService');
      expect(infraService.moduleName, 'auth');
      expect(guard.kind, ProjectUnitKind.guard);
      expect(middleware.kind, ProjectUnitKind.middleware);
    });

    test(
      'resolves preferred output directories for guards and middleware',
      () async {
        final project = await _createProject(
          files: <String, String>{
            'lib/src/auth/auth.dart': '''
import 'package:grumpy_flutter/grumpy_flutter.dart';

class Auth extends Module<AppConfig> {
  @override
  String get logTag => 'Auth';
}
''',
            'lib/src/auth/presentation/guards/auth_guard.dart':
                'class AuthGuard extends Guard<AppConfig> { @override Future<bool> canActivate(RouteContext context) async => true; @override String get logTag => "AuthGuard"; @override String toString() => logTag; }',
            'lib/src/auth/presentation/middleware/session_middleware.dart':
                'class SessionMiddleware extends Middleware<Object, AppConfig> { @override Future<RouteContext> call(RouteContext context) async => context; @override String get logTag => "SessionMiddleware"; @override String toString() => logTag; }',
          },
        );

        final context = await analyzeProject(project.path);

        expect(
          context.preferredDirectoryPath('auth', ProjectUnitKind.guard),
          'lib/src/auth/presentation/guards',
        );
        expect(
          context.preferredDirectoryPath('auth', ProjectUnitKind.middleware),
          'lib/src/auth/presentation/middleware',
        );
      },
    );

    test('merges duplicate module roots and emits a warning', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/auth/domain/models/user.dart': 'class User {}',
          'lib/src/auth/infra/services/auth_service_impl.dart':
              'class AuthServiceImpl {}',
        },
      );

      final context = await analyzeProject(project.path);
      final module = context.modules.singleWhere((item) => item.name == 'auth');

      expect(context.modules, hasLength(1));
      expect(
        module.categories[ModuleCategory.domainModels]!.files,
        contains('lib/auth/domain/models/user.dart'),
      );
      expect(
        module.categories[ModuleCategory.infraServices]!.files,
        contains('lib/src/auth/infra/services/auth_service_impl.dart'),
      );
      expect(
        context.diagnostics.any((item) => item.code == 'duplicate_module_root'),
        isTrue,
      );
    });

    test(
      'normalizes presentation guards into presentation middleware',
      () async {
        final project = await _createProject(
          files: <String, String>{
            'lib/auth/presentation/guards/auth_guard.dart':
                'class AuthGuard {}',
          },
        );

        final context = await analyzeProject(project.path);
        final module = context.modules.singleWhere(
          (item) => item.name == 'auth',
        );
        final bucket =
            module.categories[ModuleCategory.presentationMiddleware]!;

        expect(bucket.directoryPath, 'lib/auth/presentation/guards');
        expect(
          bucket.files,
          contains('lib/auth/presentation/guards/auth_guard.dart'),
        );
      },
    );

    test(
      'merges multiple configured directories for one category and warns',
      () async {
        final project = await _createProject(
          files: <String, String>{
            'lib/auth/presentation/guards/auth_guard.dart':
                'class AuthGuard {}',
            'lib/auth/presentation/middleware/session_guard.dart':
                'class SessionGuard {}',
          },
        );

        final context = await analyzeProject(project.path);
        final module = context.modules.singleWhere(
          (item) => item.name == 'auth',
        );
        final bucket =
            module.categories[ModuleCategory.presentationMiddleware]!;

        expect(
          bucket.files,
          containsAll(<String>[
            'lib/auth/presentation/guards/auth_guard.dart',
            'lib/auth/presentation/middleware/session_guard.dart',
          ]),
        );
        expect(
          context.diagnostics.any(
            (item) => item.code == 'merged_category_aliases',
          ),
          isTrue,
        );
      },
    );

    test('uses defaults when grumpy.yaml is absent', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/auth/utils/date_time.dart': 'String now() => "now";',
        },
      );

      final context = await analyzeProject(project.path);

      expect(context.config.moduleRoots, <String>['lib', 'lib/src']);
      expect(context.config.barrelFilePatterns, <String>['{folder}.dart']);
      expect(
        context.diagnostics.where((item) => item.path == 'grumpy.yaml'),
        isEmpty,
      );
    });

    test('uses grumpy.yaml to override roots and layers', () async {
      final project = await _createProject(
        grumpyYaml: '''
module_roots:
  - src/modules
barrel_file_patterns:
  - "{folder}.dart"
layers:
  utils:
    - helpers
  domain:
    models:
      - entities
''',
        files: <String, String>{
          'src/modules/payments/helpers/format_money.dart':
              'String formatMoney() => "";',
          'src/modules/payments/entities/invoice.dart': 'class Invoice {}',
        },
      );

      final context = await analyzeProject(project.path);
      final module = context.modules.singleWhere(
        (item) => item.name == 'payments',
      );

      expect(context.config.moduleRoots, <String>['src/modules']);
      expect(context.config.barrelFilePatterns, <String>['{folder}.dart']);
      expect(module.rootPath, 'src/modules/payments');
      expect(
        module.categories[ModuleCategory.utils]!.files,
        contains('src/modules/payments/helpers/format_money.dart'),
      );
      expect(
        module.categories[ModuleCategory.domainModels]!.files,
        contains('src/modules/payments/entities/invoice.dart'),
      );
    });

    test('loads generation defaults from grumpy.yml', () async {
      final project = await _createProject(
        grumpyYaml: '''
defaults:
  common:
    update_barrels: true
  repository:
    repo_mixins:
      - UseRepoMixin
      - TransactionalMutationMixin
    state_type: RepoState
  model:
    fields:
      id:
        type: String
      displayName:
        type: String
        nullable: true
        default: "'anonymous'"
''',
        grumpyConfigName: 'grumpy.yml',
        files: <String, String>{'lib/auth/auth.dart': 'class Auth {}'},
      );

      final context = await analyzeProject(project.path);

      expect(
        context.config.generationDefaults.common['update_barrels'],
        isTrue,
      );
      expect(
        context
            .config
            .generationDefaults
            .unitDefaults['repository']!['repo_mixins'],
        <Object?>['UseRepoMixin', 'TransactionalMutationMixin'],
      );
      expect(
        context.config.generationDefaults.defaultsForUnit(
          'repository',
        )['state_type'],
        'RepoState',
      );
      expect(
        context.config.generationDefaults.unitDefaults['model']!['fields'],
        <String, Object?>{
          'id': <String, Object?>{'type': 'String'},
          'displayName': <String, Object?>{
            'type': 'String',
            'nullable': true,
            'default': "'anonymous'",
          },
        },
      );
    });

    test('falls back to defaults on non-fatal grumpy config errors', () async {
      final project = await _createProject(
        grumpyYaml: '''
module_roots: nope
''',
        files: <String, String>{
          'lib/auth/domain/models/user.dart': 'class User {}',
        },
      );

      final context = await analyzeProject(project.path);

      expect(context.modules.map((item) => item.name), contains('auth'));
      expect(
        context.diagnostics.any(
          (item) => item.code == 'invalid_config_module_roots',
        ),
        isTrue,
      );
    });

    test('hides folder-name barrel files by default', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/auth/domain/models/models.dart': "export 'user.dart';",
          'lib/auth/domain/models/user.dart': 'class User {}',
        },
      );

      final context = await analyzeProject(project.path);
      final bucket = context.modules
          .singleWhere((item) => item.name == 'auth')
          .categories[ModuleCategory.domainModels]!;

      expect(bucket.directoryPath, 'lib/auth/domain/models');
      expect(bucket.files, <String>['lib/auth/domain/models/user.dart']);
    });

    test('keeps a bucket when only barrel files are filtered', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/auth/domain/models/models.dart': "export 'user.dart';",
        },
      );

      final context = await analyzeProject(project.path);
      final bucket = context.modules
          .singleWhere((item) => item.name == 'auth')
          .categories[ModuleCategory.domainModels]!;

      expect(bucket.directoryPath, 'lib/auth/domain/models');
      expect(bucket.files, isEmpty);
    });

    test('uses custom barrel file patterns from grumpy.yaml', () async {
      final project = await _createProject(
        grumpyYaml: '''
barrel_file_patterns:
  - "{folder}.dart"
  - "*.exports.dart"
''',
        files: <String, String>{
          'lib/auth/domain/models/models.dart': "export 'user.dart';",
          'lib/auth/domain/models/model.exports.dart': "export 'user.dart';",
          'lib/auth/domain/models/user.dart': 'class User {}',
        },
      );

      final context = await analyzeProject(project.path);
      final bucket = context.modules
          .singleWhere((item) => item.name == 'auth')
          .categories[ModuleCategory.domainModels]!;

      expect(context.config.barrelFilePatterns, <String>[
        '{folder}.dart',
        '*.exports.dart',
      ]);
      expect(bucket.files, <String>['lib/auth/domain/models/user.dart']);
    });

    test(
      'falls back to default barrel patterns on invalid config values',
      () async {
        final project = await _createProject(
          grumpyYaml: '''
barrel_file_patterns:
  - ""
''',
          files: <String, String>{
            'lib/auth/domain/models/models.dart': "export 'user.dart';",
            'lib/auth/domain/models/user.dart': 'class User {}',
          },
        );

        final context = await analyzeProject(project.path);
        final bucket = context.modules
            .singleWhere((item) => item.name == 'auth')
            .categories[ModuleCategory.domainModels]!;

        expect(context.config.barrelFilePatterns, <String>['{folder}.dart']);
        expect(bucket.files, <String>['lib/auth/domain/models/user.dart']);
        expect(
          context.diagnostics.any(
            (item) => item.code == 'invalid_config_barrel_file_patterns',
          ),
          isTrue,
        );
      },
    );

    test('stops module discovery on fatal grumpy config errors', () async {
      final project = await _createProject(
        grumpyYaml: 'layers: []\n',
        files: <String, String>{
          'lib/auth/domain/models/user.dart': 'class User {}',
        },
      );

      final context = await analyzeProject(project.path);

      expect(context.modules, isEmpty);
      expect(
        context.diagnostics.any((item) => item.code == 'invalid_config_layers'),
        isTrue,
      );
    });

    test(
      'excludes non-module folders and keeps returned paths relative',
      () async {
        final project = await _createProject(
          files: <String, String>{
            'lib/common/plain.dart': 'void helper() {}',
            'lib/auth/domain/models/user.dart': 'class User {}',
          },
        );

        final context = await analyzeProject(project.path);

        expect(context.modules.map((item) => item.name), <String>['auth']);
        expect(
          context
              .modules
              .single
              .categories[ModuleCategory.domainModels]!
              .files
              .single,
          'lib/auth/domain/models/user.dart',
        );
      },
    );

    test('emits logging records without installing its own handlers', () async {
      final project = await _createProject(
        files: <String, String>{
          'lib/auth/domain/models/models.dart': "export 'user.dart';",
          'lib/auth/domain/models/user.dart': 'class User {}',
        },
      );
      final previousLevel = Logger.root.level;
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final subscription = Logger.root.onRecord.listen(records.add);

      try {
        await analyzeProject(project.path);
      } finally {
        await subscription.cancel();
        Logger.root.level = previousLevel;
      }

      expect(
        records.any((record) => record.loggerName == 'grumpy_context.config'),
        isTrue,
      );
      expect(
        records.any((record) => record.loggerName == 'grumpy_context.scanner'),
        isTrue,
      );
      expect(
        records.any(
          (record) =>
              record.loggerName == 'grumpy_context.scanner' &&
              record.message.contains('Filtered barrel file'),
        ),
        isTrue,
      );
    });
  });
}

const _pubspecWithDependencies = '''
name: sample_app
description: Sample app
version: 0.1.0

environment:
  sdk: ^3.11.4

dependencies:
  http: ^1.2.0
  flutter:
    sdk: flutter
  local_pkg:
    path: ../local_pkg
  git_pkg:
    git:
      url: https://example.com/repo.git
      ref: main
  hosted_pkg:
    hosted: hosted_pkg
    version: ^2.0.0

dev_dependencies:
  test: ^1.25.6

dependency_overrides:
  override_pkg:
    path: ../override_pkg
''';

Future<Directory> _createProject({
  String pubspec = '''
name: sample_app
description: Sample app
version: 0.1.0

environment:
  sdk: ^3.11.4
''',
  String? grumpyYaml,
  String grumpyConfigName = 'grumpy.yaml',
  Map<String, String> files = const <String, String>{},
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'grumpy_context_test_',
  );
  addTearDown(() => directory.delete(recursive: true));

  await _writeFile(directory, 'pubspec.yaml', pubspec);
  if (grumpyYaml != null) {
    await _writeFile(directory, grumpyConfigName, grumpyYaml);
  }
  for (final entry in files.entries) {
    await _writeFile(directory, entry.key, entry.value);
  }

  return directory;
}

Future<void> _writeFile(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File('${root.path}${Platform.pathSeparator}$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}
