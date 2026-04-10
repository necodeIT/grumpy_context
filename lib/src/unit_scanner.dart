import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'logging.dart';
import 'models.dart';

/// Discovers typed units for a previously discovered module.
Future<List<ProjectUnit>> discoverUnits({
  required String projectRoot,
  required ProjectModuleSeed module,
}) async {
  final logger = grumpyLogger('units');
  final units = <ProjectUnit>[];

  for (final entry in module.categories.entries) {
    final category = entry.key;
    final bucket = entry.value;
    for (final filePath in bucket.files) {
      final parsed = await _parseUnitFile(
        projectRoot: projectRoot,
        moduleName: module.name,
        filePath: filePath,
        category: category,
        logger: logger,
      );
      if (parsed != null) {
        units.add(parsed);
      }
    }
  }

  final moduleFilePath = p.join(module.rootPath, '${module.name}.dart');
  final moduleUnit = await _parseModuleFile(
    projectRoot: projectRoot,
    moduleName: module.name,
    filePath: moduleFilePath,
    logger: logger,
  );
  if (moduleUnit != null) {
    units.add(moduleUnit);
  }

  final resolved = _resolveInfraContracts(units);
  resolved.sort((left, right) {
    final pathCompare = left.filePath.compareTo(right.filePath);
    if (pathCompare != 0) {
      return pathCompare;
    }
    return left.name.compareTo(right.name);
  });
  return resolved;
}

/// Lightweight module data used during unit discovery.
class ProjectModuleSeed {
  /// Creates a lightweight module seed for unit discovery.
  const ProjectModuleSeed({
    required this.name,
    required this.rootPath,
    required this.categories,
  });

  /// The discovered module name.
  final String name;

  /// The module root path relative to the project root.
  final String rootPath;

  /// The discovered category buckets for the module.
  final Map<ModuleCategory, ModuleBucket> categories;
}

Future<ProjectUnit?> _parseUnitFile({
  required String projectRoot,
  required String moduleName,
  required String filePath,
  required ModuleCategory category,
  required Logger logger,
}) async {
  final source = await File(p.join(projectRoot, filePath)).readAsString();
  final declaration = _parseFirstDeclaration(source);
  if (declaration == null) {
    logger.fine('No primary declaration found in $filePath.');
    return null;
  }

  final kind = _kindForCategory(
    category,
    declaration: declaration,
    filePath: filePath,
  );
  if (kind == null) {
    return null;
  }

  return ProjectUnit(
    name: declaration.name,
    kind: kind,
    moduleName: moduleName,
    filePath: filePath,
    category: category,
    isAbstract: declaration.isAbstract,
    extendsName: declaration.extendsName,
    mixins: declaration.mixins,
    genericSignature: declaration.genericSignature,
  );
}

Future<ProjectUnit?> _parseModuleFile({
  required String projectRoot,
  required String moduleName,
  required String filePath,
  required Logger logger,
}) async {
  final file = File(p.join(projectRoot, filePath));
  if (!await file.exists()) {
    return null;
  }

  final source = await file.readAsString();
  final declaration = _parseFirstDeclaration(source);
  if (declaration == null) {
    logger.fine('No primary declaration found in $filePath.');
    return null;
  }

  final extendsBaseName = _baseTypeName(declaration.extendsName);
  ProjectUnitKind? kind;
  if (extendsBaseName == 'AppModule') {
    kind = ProjectUnitKind.appModule;
  } else if (extendsBaseName == 'Module') {
    kind = ProjectUnitKind.module;
  }

  if (kind == null) {
    return null;
  }

  return ProjectUnit(
    name: declaration.name,
    kind: kind,
    moduleName: moduleName,
    filePath: filePath,
    category: null,
    isAbstract: declaration.isAbstract,
    extendsName: declaration.extendsName,
    mixins: declaration.mixins,
    genericSignature: declaration.genericSignature,
    configType: _extractConfigType(declaration.extendsName),
  );
}

List<ProjectUnit> _resolveInfraContracts(List<ProjectUnit> units) {
  final domainContracts = <String, ProjectUnit>{
    for (final unit in units)
      if (unit.kind == ProjectUnitKind.domainService ||
          unit.kind == ProjectUnitKind.domainDatasource)
        unit.name: unit,
  };

  return units
      .map((unit) {
        if (unit.kind != ProjectUnitKind.infraService &&
            unit.kind != ProjectUnitKind.infraDatasource) {
          return unit;
        }

        final extendsBase = _baseTypeName(unit.extendsName);
        if (extendsBase == null) {
          return unit;
        }
        final contract = domainContracts[containsTypeSuffix(extendsBase)];
        if (contract == null) {
          return unit;
        }
        return ProjectUnit(
          name: unit.name,
          kind: unit.kind,
          moduleName: contract.moduleName,
          filePath: unit.filePath,
          category: unit.category,
          isAbstract: unit.isAbstract,
          extendsName: unit.extendsName,
          mixins: unit.mixins,
          genericSignature: unit.genericSignature,
          contractName: contract.name,
          configType: unit.configType,
        );
      })
      .toList(growable: false);
}

/// Normalizes a discovered type name for contract matching.
String containsTypeSuffix(String value) => value.trim();

ProjectUnitKind? _kindForCategory(
  ModuleCategory category, {
  required _ParsedDeclaration declaration,
  required String filePath,
}) {
  switch (category) {
    case ModuleCategory.domainModels:
      return ProjectUnitKind.model;
    case ModuleCategory.domainServices:
      return ProjectUnitKind.domainService;
    case ModuleCategory.domainDatasources:
      return ProjectUnitKind.domainDatasource;
    case ModuleCategory.utils:
      return null;
    case ModuleCategory.infraServices:
      return ProjectUnitKind.infraService;
    case ModuleCategory.infraDatasources:
      return ProjectUnitKind.infraDatasource;
    case ModuleCategory.presentationComponents:
      return ProjectUnitKind.component;
    case ModuleCategory.presentationScreens:
      return ProjectUnitKind.screen;
    case ModuleCategory.presentationRepos:
      return ProjectUnitKind.repo;
    case ModuleCategory.presentationMiddleware:
      final extendsBaseName = _baseTypeName(declaration.extendsName);
      if (extendsBaseName == 'Guard' ||
          declaration.name.endsWith('Guard') ||
          filePath.contains('/presentation/guards/')) {
        return ProjectUnitKind.guard;
      }
      return ProjectUnitKind.middleware;
  }
}

String? _extractConfigType(String? extendsName) {
  if (extendsName == null) {
    return null;
  }

  final start = extendsName.indexOf('<');
  final end = extendsName.lastIndexOf('>');
  if (start == -1 || end == -1 || end <= start) {
    return null;
  }

  final arguments = extendsName.substring(start + 1, end);
  final parts = _splitGenericArguments(arguments);
  if (parts.isEmpty) {
    return null;
  }
  return parts.last.trim();
}

List<String> _splitGenericArguments(String input) {
  final parts = <String>[];
  var depth = 0;
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    if (char == '<') {
      depth++;
      buffer.write(char);
      continue;
    }
    if (char == '>') {
      depth--;
      buffer.write(char);
      continue;
    }
    if (char == ',' && depth == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    parts.add(buffer.toString());
  }
  return parts;
}

String? _baseTypeName(String? type) {
  if (type == null) {
    return null;
  }
  final normalized = type.trim();
  final withoutGenerics = normalized.contains('<')
      ? normalized.substring(0, normalized.indexOf('<'))
      : normalized;
  final segments = withoutGenerics.split('.');
  return segments.last.trim();
}

_ParsedDeclaration? _parseFirstDeclaration(String source) {
  final sanitized = _stripComments(source);
  final match = _declarationPattern.firstMatch(sanitized);
  if (match == null) {
    return null;
  }

  final prefix = match.namedGroup('prefix') ?? '';
  final declarationType = match.namedGroup('type') ?? 'class';
  final name = match.namedGroup('name');
  if (name == null) {
    return null;
  }

  final extendsName = match.namedGroup('extends')?.trim();
  final mixins =
      match
          .namedGroup('with')
          ?.split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false) ??
      const <String>[];

  return _ParsedDeclaration(
    name: name,
    declarationType: declarationType,
    isAbstract: prefix.contains('abstract'),
    genericSignature: match.namedGroup('generics')?.trim(),
    extendsName: extendsName,
    mixins: mixins,
  );
}

String _stripComments(String input) {
  final withoutBlockComments = input.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return withoutBlockComments.replaceAll(RegExp(r'//.*'), '');
}

final RegExp _declarationPattern = RegExp(
  r'^\s*(?<prefix>(?:abstract|base|sealed|final|interface)\s+)*(?<type>class|mixin(?:\s+class)?)\s+(?<name>[A-Z][A-Za-z0-9_]*)'
  r'(?<generics><[^>{;=]*>)?'
  r'(?:\s+extends\s+(?<extends>[A-Z_][A-Za-z0-9_<>, .?&]*))?'
  r'(?:\s+with\s+(?<with>[A-Z_][A-Za-z0-9_<>, .?&]*(?:\s*,\s*[A-Z_][A-Za-z0-9_<>, .?&]*)*))?',
  multiLine: true,
);

final class _ParsedDeclaration {
  const _ParsedDeclaration({
    required this.name,
    required this.declarationType,
    required this.isAbstract,
    required this.genericSignature,
    required this.extendsName,
    required this.mixins,
  });

  final String name;
  final String declarationType;
  final bool isAbstract;
  final String? genericSignature;
  final String? extendsName;
  final List<String> mixins;
}
