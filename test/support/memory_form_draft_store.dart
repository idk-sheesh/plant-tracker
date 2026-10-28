import 'dart:convert';
import 'package:garden_journal/core/services/form_draft_store.dart';

/// Keeps widget tests isolated from the user's application support directory.
class MemoryFormDraftStore extends FormDraftStore {
  final _values = <String, String>{};
  @override
  Future<Map<String, dynamic>?> load(String key) async => _values[key] == null
      ? null
      : jsonDecode(_values[key]!) as Map<String, dynamic>;
  @override
  Future<void> save(String key, Map<String, dynamic> data) async {
    _values[key] = jsonEncode(data);
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
