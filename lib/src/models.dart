import 'dart:collection';

/// Identifies the source type used by a dependency declaration.
enum DependencySource {
  /// A hosted package from a package registry.
  hosted,

  /// An SDK-backed dependency such as Flutter.
  sdk,

  /// A dependency resolved from a Git repository.
  git,

  /// A dependency resolved from a local filesystem path.
  path,

  /// A dependency specification that does not match a known source shape.
  unknown,
}

/// Identifies the supported module buckets returned by the analyzer.
enum ModuleCategory {
  /// The `domain/models` bucket.
  domainModels,

  /// The `domain/services` bucket.
  domainServices,

  /// The `domain/datasources` bucket.
  domainDatasources,

  /// The `utils` bucket.
  utils,

  /// The `infra/services` bucket.
  infraServices,

  /// The `infra/datasources` bucket.
  infraDatasources,

  /// The `presentation/components` bucket.
  presentationComponents,

  /// The `presentation/screens` bucket.
  presentationScreens,

  /// The `presentation/repos` bucket.
  presentationRepos,

  /// The `presentation/middleware` bucket, including `presentation/guards` aliases.
  presentationMiddleware,
}

/// Describes the severity of a diagnostic emitted during analysis.
enum DiagnosticSeverity {
  /// Informational output that does not imply a problem.
  info,

  /// A non-fatal issue or ambiguity was detected.
  warning,

  /// A fatal or invalid condition was detected.
  error,
}

/// The full analysis result for a project root.
class ProjectContext {
  /// Creates a project context.
  const ProjectContext({
    required this.name,
    required this.dependencies,
    required this.modules,
    required this.diagnostics,
    required this.config,
  });

  /// The package name declared in `pubspec.yaml`.
  final String name;

  /// The direct dependency declarations grouped by pubspec section.
  final ProjectDependencies dependencies;

  /// The discovered modules.
  final List<ProjectModule> modules;

  /// Diagnostics emitted while reading config, pubspec, and modules.
  final List<ProjectDiagnostic> diagnostics;

  /// The resolved discovery configuration used for this analysis.
  final ResolvedGrumpyConfig config;

  /// Converts this context into a JSON-compatible map.
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

  /// Returns whether the project appears to use `grumpy_flutter`.
  bool get isFlutterProject {
    return dependencies.dependencies.any((dep) => dep.name == 'grumpy_flutter');
  }
}

/// The direct dependency declarations grouped by pubspec section.
class ProjectDependencies {
  /// Creates grouped project dependencies.
  const ProjectDependencies({
    required this.dependencies,
    required this.devDependencies,
    required this.dependencyOverrides,
  });

  /// Dependencies declared under `dependencies`.
  final List<ProjectDependency> dependencies;

  /// Dependencies declared under `dev_dependencies`.
  final List<ProjectDependency> devDependencies;

  /// Dependencies declared under `dependency_overrides`.
  final List<ProjectDependency> dependencyOverrides;

  /// An empty dependency grouping.
  static const empty = ProjectDependencies(
    dependencies: <ProjectDependency>[],
    devDependencies: <ProjectDependency>[],
    dependencyOverrides: <ProjectDependency>[],
  );

  /// Converts this dependency grouping into a JSON-compatible map.
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

/// A normalized dependency declaration.
class ProjectDependency {
  /// Creates a project dependency.
  const ProjectDependency({
    required this.name,
    required this.source,
    required this.constraint,
    this.details = const <String, Object?>{},
  });

  /// The dependency name.
  final String name;

  /// The type of dependency source.
  final DependencySource source;

  /// The declared version constraint, when available.
  final String? constraint;

  /// Additional normalized dependency metadata.
  final Map<String, Object?> details;

  /// Converts this dependency into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'source': source.name,
      'constraint': constraint,
      'details': details,
    };
  }
}

/// A discovered top-level module and its categorized file inventory.
class ProjectModule {
  /// Creates a project module.
  ProjectModule({
    required this.name,
    required this.rootPath,
    required Map<ModuleCategory, ModuleBucket> categories,
  }) : categories = UnmodifiableMapView<ModuleCategory, ModuleBucket>(
         categories,
       );

  /// The module identifier, derived from the top-level folder name.
  final String name;

  /// The module root relative to the analyzed project root.
  final String rootPath;

  /// The normalized bucket inventory for this module.
  final Map<ModuleCategory, ModuleBucket> categories;

  /// Converts this module into a JSON-compatible map.
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

/// A file inventory bucket within a module category.
class ModuleBucket {
  /// Creates a module bucket.
  const ModuleBucket({required this.directoryPath, required this.files});

  /// The relative directory path for the bucket, if it exists.
  final String? directoryPath;

  /// The relative `.dart` file paths found in this bucket.
  final List<String> files;

  /// Whether the bucket exists on disk.
  bool get exists => directoryPath != null;

  /// Converts this bucket into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{'directoryPath': directoryPath, 'files': files};
  }
}

/// A diagnostic emitted during analysis.
class ProjectDiagnostic {
  /// Creates a project diagnostic.
  const ProjectDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.path,
  });

  /// A stable machine-readable diagnostic code.
  final String code;

  /// The severity of the diagnostic.
  final DiagnosticSeverity severity;

  /// A human-readable description of the issue.
  final String message;

  /// The relative path associated with the diagnostic, when available.
  final String? path;

  /// Converts this diagnostic into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'severity': severity.name,
      'message': message,
      'path': path,
    };
  }
}

/// The resolved discovery configuration applied to a project analysis.
class ResolvedGrumpyConfig {
  /// Creates a resolved config.
  ResolvedGrumpyConfig({
    required List<String> moduleRoots,
    required Map<ModuleCategory, List<String>> categoryPaths,
    required List<String> barrelFilePatterns,
  }) : moduleRoots = List.unmodifiable(moduleRoots),
       categoryPaths = UnmodifiableMapView<ModuleCategory, List<String>>(
         categoryPaths.map(
           (category, paths) => MapEntry(category, List.unmodifiable(paths)),
         ),
       ),
       barrelFilePatterns = List.unmodifiable(barrelFilePatterns);

  /// The module roots that will be scanned.
  final List<String> moduleRoots;

  /// The configured discovery paths for each supported category.
  final Map<ModuleCategory, List<String>> categoryPaths;

  /// Basename patterns used to hide barrel files from bucket inventories.
  final List<String> barrelFilePatterns;

  /// Returns the built-in default discovery configuration.
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
      barrelFilePatterns: const <String>['{folder}.dart'],
    );
  }

  /// Converts this config into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'moduleRoots': moduleRoots,
      'categoryPaths': categoryPaths.map(
        (category, paths) => MapEntry(category.name, paths),
      ),
      'barrelFilePatterns': barrelFilePatterns,
    };
  }
}
