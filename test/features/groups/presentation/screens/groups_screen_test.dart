import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/groups/data/models/plant_group.dart';
import 'package:garden_journal/features/groups/data/repositories/group_repository.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/groups/presentation/screens/groups_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('n’affiche que le niveau courant et ouvre les sous-dossiers',
      (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    final provider = GroupProvider(
      repository: _InMemoryGroupRepository([
        PlantGroup(
          id: 'year-2026',
          name: '2026',
          color: Colors.green,
          createdAt: now,
        ),
        PlantGroup(
          id: 'year-2025',
          name: '2025',
          color: Colors.blue,
          createdAt: now,
        ),
        PlantGroup(
          id: 'indoor',
          name: 'Indoor',
          color: Colors.orange,
          createdAt: now,
          parentGroupId: 'year-2026',
        ),
        PlantGroup(
          id: 'week-1',
          name: 'Semaine 1',
          color: Colors.purple,
          createdAt: now,
          parentGroupId: 'indoor',
        ),
      ]),
    );
    await provider.loadGroups();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: GroupsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('Indoor'), findsNothing);

    await tester.tap(find.text('2026'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Indoor'), findsOneWidget);
    expect(find.text('2025'), findsNothing);
    expect(find.text('Semaine 1'), findsNothing);

    await tester.tap(find.text('Indoor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Semaine 1'), findsOneWidget);
  });
}

class _InMemoryGroupRepository extends GroupRepository {
  final List<PlantGroup> values;

  _InMemoryGroupRepository(this.values);

  @override
  Future<List<PlantGroup>> getAllGroups() async => values;
}
