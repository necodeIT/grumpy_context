import 'dart:collection';

enum DependencySource { hosted, sdk, git, path, unknown }

enum ModuleCategory {
  domainModels,
  domainServices,
  domainDatasources,
  utils,
  infraServices,
  infraDatasources,
  presentationComponents,
  presentationScreens,
  presentationRepos,
  presentationMiddleware,
}

enum DiagnosticSeverity { info, warning, error }

class ProjectContext {
  const ProjectContext({
    required this.name,
    required this.dependencies,
    required this.modules,
    required this.diagnostics,
    required this.config,
  });

  final String name;
  final ProjectDependencies dependencies;
  final List<ProjectModule> modules;
  final List<ProjectDiagnostic> diagnostics;
  final ResolvedGrumpyConfig config;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'dependencies': dependencies.toJson(),
      'modules': modules.map((module) => module.toJson()).toList(),
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(),
      'config': config.toJson(),
    };
  }
}

class ProjectDependencies {
  const ProjectDependencies({
    required this.dependencies,
    required this.devDependencies,
    required this.dependencyOverrides,
  });

  final List<ProjectDependency> dependencies;
  final List<ProjectDependency> devDependencies;
  final List<ProjectDependency> dependencyOverrides;

  static const empty = ProjectDependencies(
    dependencies: <ProjectDependency>[],
    devDependencies: <ProjectDependency>[],
    dependencyOverrides: <ProjectDependency>[],
  );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'dependencies': dependencies.map((item) => item.toJson()).toList(),
      'devDependencies': devDependencies.map((item) => item.toJson()).toList(),
      'dependencyOverrides': dependencyOverrides
          .map((item) => item.toJson())
          .toList(),
    };
  }
}

class ProjectDependency {
  const ProjectDependency({
    required this.name,
    required this.source,
    required this.constraint,
    this.details = const <String, Object?>{},
  });

  final String name;
  final DependencySource source;
  final String? constraint;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'source': source.name,
      'constraint': constraint,
      'details': details,
    };
  }
}

class ProjectModule {
  ProjectModule({
    required this.name,
    required this.rootPath,
    required Map<ModuleCategory, ModuleBucket> categories,
  }) : categories = UnmodifiableMapView<ModuleCategory, ModuleBucket>(
         categories,
       );

  final String name;
  final String rootPath;
  final Map<ModuleCategory, ModuleBucket> categories;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'rootPath': rootPath,
      'categories': categories.map(
        (category, bucket) => MapEntry(category.name, bucket.toJson()),
      ),
    };
  }
}

class ModuleBucket {
  const ModuleBucket({required this.directoryPath, required this.files});

  final String? directoryPath;
  final List<String> files;

  bool get exists => directoryPath != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{'directoryPath': directoryPath, 'files': files};
  }
}

class ProjectDiagnostic {
  const ProjectDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.path,
  });

  final String code;
  final DiagnosticSeverity severity;
  final String message;
  final String? path;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'severity': severity.name,
      'message': message,
      'path': path,
    };
  }
}

class ResolvedGrumpyConfig {
  ResolvedGrumpyConfig({
    required List<String> moduleRoots,
    required Map<ModuleCategory, List<String>> categoryPaths,
  }) : moduleRoots = List.unmodifiable(moduleRoots),
       categoryPaths = UnmodifiableMapView<ModuleCategory, List<String>>(
         categoryPaths.map(
           (category, paths) => MapEntry(category, List.unmodifiable(paths)),
         ),
       );

  final List<String> moduleRoots;
  final Map<ModuleCategory, List<String>> categoryPaths;

  factory ResolvedGrumpyConfig.defaults() {
    return ResolvedGrumpyConfig(
      moduleRoots: const <String>['lib', 'lib/src'],
      categoryPaths: <ModuleCategory, List<String>>{
        ModuleCategory.domainModels: const <String>['domain/models'],
        ModuleCategory.domainServices: const <String>['domain/services'],
        ModuleCategory.domainDatasources: const <String>['domain/datasources'],
        ModuleCategory.utils: const <String>['utils'],
        ModuleCategory.infraServices: const <String>['infra/services'],
        ModuleCategory.infraDatasources: const <String>['infra/datasources'],
        ModuleCategory.presentationComponents: const <String>[
          'presentation/components',
        ],
        ModuleCategory.presentationScreens: const <String>[
          'presentation/screens',
        ],
        ModuleCategory.presentationRepos: const <String>['presentation/repos'],
        ModuleCategory.presentationMiddleware: const <String>[
          'presentation/middleware',
          'presentation/guards',
        ],
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'moduleRoots': moduleRoots,
      'categoryPaths': categoryPaths.map(
        (category, paths) => MapEntry(category.name, paths),
      ),
    };
  }
}
