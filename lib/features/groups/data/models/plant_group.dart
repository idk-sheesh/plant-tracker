import 'package:flutter/material.dart';

class PlantGroup {
  final String id;
  final String name;
  final String? description;
  final Color color;
  final DateTime createdAt;
  final String? parentGroupId;
  const PlantGroup(
      {required this.id,
      required this.name,
      this.description,
      required this.color,
      required this.createdAt,
      this.parentGroupId});
  PlantGroup copyWith(
          {String? id,
          String? name,
          String? description,
          Color? color,
          DateTime? createdAt,
          String? parentGroupId}) =>
      PlantGroup(
          id: id ?? this.id,
          name: name ?? this.name,
          description: description ?? this.description,
          color: color ?? this.color,
          createdAt: createdAt ?? this.createdAt,
          parentGroupId: parentGroupId ?? this.parentGroupId);
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'color': color.toARGB32(),
        'created_at': createdAt.toIso8601String(),
        'parent_group_id': parentGroupId
      };
  factory PlantGroup.fromMap(Map<String, dynamic> map) => PlantGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: Color(map['color'] as int),
      createdAt: DateTime.parse(map['created_at'] as String),
      parentGroupId: map['parent_group_id'] as String?);
}
