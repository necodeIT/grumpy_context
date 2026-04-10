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

/// Identifies supported discoverable Grumpy unit types.
enum ProjectUnitKind {
  /// A Flutter app/root module extending `AppModule`.
  appModule,

  /// A feature module extending `Module`.
  module,

  /// A domain service contract.
  domainService,

  /// An infra service implementation.
  infraService,

  /// A domain datasource contract.
  domainDatasource,

  /// An infra datasource implementation.
  infraDatasource,

  /// A presentation repository.
  repo,

  /// A presentation guard.
  guard,

  /// A presentation middleware that is not a guard.
  middleware,

  /// A presentation screen.
  screen,

  /// A presentation component.
  component,

  /// A domain model.
  model,
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
    required this.units,
    required this.diagnostics,
    required this.config,
  });

  /// The package name declared in `pubspec.yaml`.
  final String name;

  /// The direct dependency declarations grouped by pubspec section.
  final ProjectDependencies dependencies;

  /// The discovered modules.
  final List<ProjectModule> modules;

  /// All discovered typed units across all modules.
  final List<ProjectUnit> units;

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
      'units': units.map((unit) => unit.toJson()).toList(),
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

  /// Returns the discovered module with the given [moduleName], if any.
  ProjectModule? moduleByName(String moduleName) {
    for (final module in modules) {
      if (module.name == moduleName) {
        return module;
      }
    }
    return null;
  }

  /// Returns all discovered units of [kind].
  List<ProjectUnit> unitsOfKind(ProjectUnitKind kind) {
    return units.where((unit) => unit.kind == kind).toList(growable: false);
  }

  /// Resolves the preferred output directory for [kind] inside [moduleName].
  String? preferredDirectoryPath(
    String moduleName,
    ProjectUnitKind kind, {
    bool preferExisting = true,
  }) {
    final module = moduleByName(moduleName);
    if (module == null) {
      return null;
    }
    return module.preferredDirectoryPath(
      kind,
      config: config,
      preferExisting: preferExisting,
    );
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
    required List<ProjectUnit> units,
  }) : categories = UnmodifiableMapView<ModuleCategory, ModuleBucket>(
         categories,
       ),
       units = List.unmodifiable(units);

  /// The module identifier, derived from the top-level folder name.
  final String name;

  /// The module root relative to the analyzed project root.
  final String rootPath;

  /// The normalized bucket inventory for this module.
  final Map<ModuleCategory, ModuleBucket> categories;

  /// All discovered typed units within this module.
  final List<ProjectUnit> units;

  /// Converts this module into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'rootPath': rootPath,
      'categories': categories.map(
        (category, bucket) => MapEntry(category.name, bucket.toJson()),
      ),
      'units': units.map((unit) => unit.toJson()).toList(),
    };
  }

  /// Returns all discovered units of [kind] within this module.
  List<ProjectUnit> unitsOfKind(ProjectUnitKind kind) {
    return units.where((unit) => unit.kind == kind).toList(growable: false);
  }

  /// Resolves a preferred output directory for [kind].
  String? preferredDirectoryPath(
    ProjectUnitKind kind, {
    required ResolvedGrumpyConfig config,
    bool preferExisting = true,
  }) {
    final preferredCategories = _categoriesForUnitKind(kind);
    for (final category in preferredCategories) {
      final bucket = categories[category];
      if (bucket != null && preferExisting && bucket.exists) {
        if (category == ModuleCategory.presentationMiddleware) {
          return bucket.preferredDirectoryPathFor(kind);
        }
        return bucket.directoryPath;
      }
    }

    final category = preferredCategories.firstOrNull;
    if (category == null) {
      return null;
    }

    final aliases = config.categoryPaths[category] ?? const <String>[];
    if (aliases.isEmpty) {
      return null;
    }

    final preferredAlias = _preferredAliasFor(kind, aliases);
    return '$rootPath/$preferredAlias';
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

  /// Returns a preferred directory path for [kind] when this bucket has aliases.
  String? preferredDirectoryPathFor(ProjectUnitKind kind) {
    if (!exists) {
      return null;
    }
    if (kind == ProjectUnitKind.guard &&
        directoryPath != null &&
        directoryPath!.endsWith('/presentation/middleware')) {
      return directoryPath!.replaceFirst(
        '/presentation/middleware',
        '/presentation/guards',
      );
    }
    return directoryPath;
  }

  /// Converts this bucket into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{'directoryPath': directoryPath, 'files': files};
  }
}

/// A discovered typed unit within a project module.
class ProjectUnit {
  /// Creates a project unit.
  const ProjectUnit({
    required this.name,
    required this.kind,
    required this.moduleName,
    required this.filePath,
    required this.category,
    required this.isAbstract,
    required this.extendsName,
    required this.mixins,
    required this.genericSignature,
    this.contractName,
    this.configType,
  });

  /// The declared type name.
  final String name;

  /// The normalized unit kind.
  final ProjectUnitKind kind;

  /// The module this unit belongs to.
  final String moduleName;

  /// The relative file path containing the unit.
  final String filePath;

  /// The normalized module category this unit was discovered from.
  final ModuleCategory? category;

  /// Whether the primary declaration is abstract.
  final bool isAbstract;

  /// The extended type name, when present.
  final String? extendsName;

  /// Mixin type names applied to the declaration.
  final List<String> mixins;

  /// The declaration generic signature, for example `<T>` or `<AppConfig>`.
  final String? genericSignature;

  /// The corresponding domain contract for infra units, when resolved.
  final String? contractName;

  /// The discovered config type for modules and app modules.
  final String? configType;

  /// Converts this unit into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'kind': kind.name,
      'moduleName': moduleName,
      'filePath': filePath,
      'category': category?.name,
      'isAbstract': isAbstract,
      'extendsName': extendsName,
      'mixins': mixins,
      'genericSignature': genericSignature,
      'contractName': contractName,
      'configType': configType,
    };
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

List<ModuleCategory> _categoriesForUnitKind(ProjectUnitKind kind) {
  switch (kind) {
    case ProjectUnitKind.appModule:
    case ProjectUnitKind.module:
      return const <ModuleCategory>[];
    case ProjectUnitKind.domainService:
      return const <ModuleCategory>[ModuleCategory.domainServices];
    case ProjectUnitKind.infraService:
      return const <ModuleCategory>[ModuleCategory.infraServices];
    case ProjectUnitKind.domainDatasource:
      return const <ModuleCategory>[ModuleCategory.domainDatasources];
    case ProjectUnitKind.infraDatasource:
      return const <ModuleCategory>[ModuleCategory.infraDatasources];
    case ProjectUnitKind.repo:
      return const <ModuleCategory>[ModuleCategory.presentationRepos];
    case ProjectUnitKind.guard:
    case ProjectUnitKind.middleware:
      return const <ModuleCategory>[ModuleCategory.presentationMiddleware];
    case ProjectUnitKind.screen:
      return const <ModuleCategory>[ModuleCategory.presentationScreens];
    case ProjectUnitKind.component:
      return const <ModuleCategory>[ModuleCategory.presentationComponents];
    case ProjectUnitKind.model:
      return const <ModuleCategory>[ModuleCategory.domainModels];
  }
}

String _preferredAliasFor(ProjectUnitKind kind, List<String> aliases) {
  if (kind == ProjectUnitKind.guard) {
    for (final alias in aliases) {
      if (alias.endsWith('presentation/guards')) {
        return alias;
      }
    }
  }
  if (kind == ProjectUnitKind.middleware) {
    for (final alias in aliases) {
      if (alias.endsWith('presentation/middleware')) {
        return alias;
      }
    }
  }
  return aliases.first;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// The resolved discovery configuration applied to a project analysis.
class ResolvedGrumpyConfig {
  /// Creates a resolved config.
  ResolvedGrumpyConfig({
    required List<String> moduleRoots,
    required Map<ModuleCategory, List<String>> categoryPaths,
    required List<String> barrelFilePatterns,
    required this.generationDefaults,
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

  /// Project-configured generation defaults consumed by Mason hooks.
  final GrumpyGenerationDefaults generationDefaults;

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
      generationDefaults: GrumpyGenerationDefaults.empty(),
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
      'generationDefaults': generationDefaults.toJson(),
    };
  }
}

/// Project-configured defaults applied during brick generation.
class GrumpyGenerationDefaults {
  /// Creates generation defaults.
  GrumpyGenerationDefaults({
    Map<String, Object?> common = const <String, Object?>{},
    Map<String, Map<String, Object?>> unitDefaults =
        const <String, Map<String, Object?>>{},
  }) : common = Map.unmodifiable(_normalizeValueMap(common)),
       unitDefaults = Map.unmodifiable(<String, Map<String, Object?>>{
         for (final entry in unitDefaults.entries)
           entry.key: Map<String, Object?>.unmodifiable(
             _normalizeValueMap(entry.value),
           ),
       });

  /// Shared defaults applied to all unit kinds.
  final Map<String, Object?> common;

  /// Per-unit defaults keyed by brick unit name, for example `repository`.
  final Map<String, Map<String, Object?>> unitDefaults;

  /// Creates an empty defaults set.
  factory GrumpyGenerationDefaults.empty() => GrumpyGenerationDefaults();

  /// Merges [common] and the defaults for [unitKind].
  Map<String, Object?> defaultsForUnit(String unitKind) {
    return <String, Object?>{...common, ...?unitDefaults[unitKind]};
  }

  /// Converts defaults into a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{'common': common, 'unitDefaults': unitDefaults};
  }
}

Map<String, Object?> _normalizeValueMap(Map<String, Object?> input) {
  return input.map((key, value) => MapEntry(key, _normalizeConfigValue(value)));
}

Object? _normalizeConfigValue(Object? value) {
  if (value is List) {
    return List.unmodifiable(value.map(_normalizeConfigValue));
  }
  if (value is Map) {
    return Map.unmodifiable(
      value.map(
        (key, nestedValue) =>
            MapEntry('$key', _normalizeConfigValue(nestedValue)),
      ),
    );
  }
  return value;
}
