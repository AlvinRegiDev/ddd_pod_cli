import 'package:path/path.dart' as p;

class ImportCycleDetector {
  /// Detect cycles in import graph of the given files.
  /// Map keys are absolute file paths, values are file contents.
  static List<List<String>> detect(Map<String, String> files) {
    // 1. Build adjacency list of files -> imported files
    final graph = <String, List<String>>{};

    // Helper to resolve imports (including package imports and relative imports)
    for (final entry in files.entries) {
      final filePath = entry.key;
      final content = entry.value;
      final imports = <String>[];

      // Extract import directives using a simple regex
      final regex = RegExp(r'''import\s+['"]([^'"]+)['"]''');
      for (final match in regex.allMatches(content)) {
        final importedUri = match.group(1);
        if (importedUri == null) continue;

        String? resolvedPath;
        if (importedUri.startsWith('package:')) {
          // E.g., package:my_project/features/my_feature/domain/my_model.dart
          // maps to lib/features/my_feature/domain/my_model.dart.
          final packagePathPart =
              importedUri.replaceFirst(RegExp(r'^package:[^/]+/'), '');
          final targetSuffix = p.join('lib', packagePathPart);

          for (final path in files.keys) {
            if (path.endsWith(targetSuffix) ||
                path
                    .replaceAll('\\', '/')
                    .endsWith(targetSuffix.replaceAll('\\', '/'))) {
              resolvedPath = path;
              break;
            }
          }
        } else if (!importedUri.startsWith('dart:') &&
            !importedUri.startsWith('package:')) {
          // Relative import
          final directory = p.dirname(filePath);
          resolvedPath = p.normalize(p.join(directory, importedUri));
        }

        if (resolvedPath != null && files.containsKey(resolvedPath)) {
          imports.add(resolvedPath);
        }
      }
      graph[filePath] = imports;
    }

    // 2. DFS to detect cycles
    final cycles = <List<String>>[];
    final visited = <String, int>{}; // 0 = unvisited, 1 = visiting, 2 = visited

    for (final node in graph.keys) {
      visited[node] = 0;
    }

    void dfs(String node, List<String> path) {
      visited[node] = 1; // visiting
      path.add(node);

      for (final neighbor in graph[node] ?? const <String>[]) {
        final state = visited[neighbor] ?? 0;
        if (state == 1) {
          final cycleStartIdx = path.indexOf(neighbor);
          if (cycleStartIdx != -1) {
            cycles.add(List<String>.from(path.sublist(cycleStartIdx)));
          }
        } else if (state == 0) {
          dfs(neighbor, path);
        }
      }

      path.removeLast();
      visited[node] = 2; // visited
    }

    for (final node in graph.keys) {
      if (visited[node] == 0) {
        dfs(node, []);
      }
    }

    return cycles;
  }
}
