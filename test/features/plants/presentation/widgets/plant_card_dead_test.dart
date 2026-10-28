import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/groups/data/models/plant_group.dart';
import 'package:garden_journal/features/groups/data/repositories/group_repository.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/widgets/plant_card.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('une plante morte affiche son statut plutot que son groupe',
      (tester) async {
    final now = DateTime.utc(2026, 8, 26);
    final groups = GroupProvider(
      repository: _GroupRepository([
        PlantGroup(
          id: 'group-1',
          name: 'Groupe actif',
          color: Colors.green,
          createdAt: now,
        ),
      ]),
    );
    await groups.loadGroups();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: groups,
        child: MaterialApp(
          home: Scaffold(
            body: PlantCard(
              plant: Plant(
                id: 'dead',
                name: 'Plante morte',
                pottingDate: now,
                cultureType: 'Terre',
                groupId: 'group-1',
                qrCode: 'plant:dead',
                createdAt: now,
                updatedAt: now,
                isDead: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Morte'), findsNWidgets(2));
    expect(find.text('Groupe actif'), findsNothing);
  });
}

class _GroupRepository extends GroupRepository {
  final List<PlantGroup> values;

  _GroupRepository(this.values);

  @override
  Future<List<PlantGroup>> getAllGroups() async => values;
}
