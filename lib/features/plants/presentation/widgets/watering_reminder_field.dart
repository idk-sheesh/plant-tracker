import 'package:flutter/material.dart';

class WateringReminderField extends StatelessWidget {
  final String location;
  final String containerType;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const WateringReminderField({
    super.key,
    required this.location,
    required this.containerType,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rappel d’arrosage'),
          subtitle: Text(value == null
              ? location == 'outdoor'
                  ? 'Désactivé par défaut dehors : la pluie peut suffire.'
                  : containerType == 'plein_sol'
                      ? 'Désactivé par défaut en pleine terre.'
                      : 'Signale les plantes sans arrosage récent.'
              : 'Choix personnalisé pour cette plante.'),
          value:
              value ?? (location != 'outdoor' && containerType != 'plein_sol'),
          onChanged: onChanged,
        ),
        if (value != null)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onChanged(null),
                child: const Text('Utiliser le réglage selon l’emplacement'),
              )),
      ]);
}
