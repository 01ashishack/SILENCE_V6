import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  try {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'library_id',
      value: 'some-uuid',
    );
    print('Filter type: ${filter.type}');
    print('Filter column: ${filter.column}');
    print('Filter value: ${filter.value}');
  } catch (e) {
    print('Error: $e');
  }
}
