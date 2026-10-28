import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';

void main() {
  test('un groupe ouvert masque les plantes mortes sans les supprimer',
      () async {
    final now = DateTime.utc(2026, 8, 26);
    final active = _plant('active', 'Active', now);
    final dead = _plant('dead', 'Morte', now, isDead: true);
    final provider = PlantProvider(
      repository: _PlantRepository([active, dead]),
    );

    await provider.loadPlants();
    provider.setGroupFilter('group-1');

    expect(provider.plants.map((plant) => plant.id), ['active']);
    expect(provider.allPlants.map((plant) => plant.id),
        containsAll(['active', 'dead']));

    provider.setGroupFilter(null);
    expect(provider.plants.map((plant) => plant.id),
        containsAll(['active', 'dead']));
  });
}

Plant _plant(
  String id,
  String name,
  DateTime now, {
  bool isDead = false,
}) =>
    Plant(
      id: id,
      name: name,
      pottingDate: now,
      cultureType: 'Terre',
      groupId: 'group-1',
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now,
      isDead: isDead,
    );

class _PlantRepository extends PlantRepository {
  final List<Plant> values;

  _PlantRepository(this.values);

  @override
  Future<List<Plant>> getAllPlants() async => values;
}
