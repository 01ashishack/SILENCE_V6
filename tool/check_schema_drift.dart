// Schema-drift detector (audit Wave 9).
//
// The workflow is: each change is authored as a migration under
// silence_app/migrations/, applied to the live DB by the user, then FOLDED into
// the canonical silence_app/supabase_schema.sql. It's easy to forget the fold —
// which silently breaks fresh deploys. This script catches that drift in CI.
//
// It scans every migration for the durable objects it introduces
// (CREATE TABLE / CREATE [OR REPLACE] FUNCTION) and asserts each name also
// appears in the canonical schema. Pure text analysis — no DB needed.
//
// Run: `dart run tool/check_schema_drift.dart`  (exit 0 = ok, 1 = drift).

import 'dart:io';

const _schemaPath = 'silence_app/supabase_schema.sql';
const _migrationsDir = 'silence_app/migrations';

// Migrations that intentionally only ALTER/seed/drop or are superseded, so they
// introduce no durable CREATE object to fold. Add filenames here with a reason.
const Set<String> _ignoreFiles = {};

final _tableRe = RegExp(
    r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?"?([a-zA-Z_][a-zA-Z0-9_]*)"?',
    caseSensitive: false);
final _funcRe = RegExp(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?"?([a-zA-Z_][a-zA-Z0-9_]*)"?',
    caseSensitive: false);

void main() {
  final schemaFile = File(_schemaPath);
  if (!schemaFile.existsSync()) {
    stderr.writeln('schema-drift: cannot find $_schemaPath');
    exit(2);
  }
  final schema = schemaFile.readAsStringSync();

  final dir = Directory(_migrationsDir);
  if (!dir.existsSync()) {
    stderr.writeln('schema-drift: cannot find $_migrationsDir');
    exit(2);
  }

  final migrations = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final issues = <String>[];

  for (final mig in migrations) {
    final name = mig.uri.pathSegments.last;
    if (_ignoreFiles.contains(name)) continue;
    final sql = mig.readAsStringSync();

    final objects = <String>{};
    for (final m in _tableRe.allMatches(sql)) {
      objects.add(m.group(1)!.toLowerCase());
    }
    for (final m in _funcRe.allMatches(sql)) {
      objects.add(m.group(1)!.toLowerCase());
    }

    for (final obj in objects) {
      // Look for the same CREATE of this object somewhere in the canonical schema.
      final tableInSchema = RegExp(
              'CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?(?:public\\.)?"?$obj"?',
              caseSensitive: false)
          .hasMatch(schema);
      final funcInSchema = RegExp(
              'CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?"?$obj"?',
              caseSensitive: false)
          .hasMatch(schema);
      if (!tableInSchema && !funcInSchema) {
        issues.add('  • "$obj" (introduced by $name) is NOT in $_schemaPath');
      }
    }
  }

  if (issues.isEmpty) {
    stdout.writeln(
        'schema-drift: OK — every migration object is folded into the canonical schema.');
    exit(0);
  }

  stderr.writeln('schema-drift: DRIFT DETECTED — these objects look unfolded:');
  for (final i in issues) {
    stderr.writeln(i);
  }
  stderr.writeln(
      '\nFold them into $_schemaPath (or add the migration to _ignoreFiles with a reason).');
  exit(1);
}
