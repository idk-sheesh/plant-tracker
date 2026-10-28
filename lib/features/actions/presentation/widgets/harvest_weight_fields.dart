import 'package:flutter/material.dart';

typedef HarvestFieldDecorationBuilder = InputDecoration Function(
  String label,
  IconData icon,
);

class HarvestWeightFields extends StatelessWidget {
  final TextEditingController wetController;
  final TextEditingController dryController;
  final TextEditingController wasteController;
  final HarvestFieldDecorationBuilder decorationBuilder;
  final String helperText;

  const HarvestWeightFields({
    super.key,
    required this.wetController,
    required this.dryController,
    required this.wasteController,
    required this.decorationBuilder,
    required this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth >= 600
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _field(width, wetController, 'Récolté (g)', Icons.water_drop,
                'ex: 120,5'),
            _field(
                width, dryController, 'Conservé (g)', Icons.scale, 'ex: 42,5'),
            _field(width, wasteController, 'Écarté (g)', Icons.content_cut,
                'ex: 8'),
          ],
        );
      }),
      const SizedBox(height: 8),
      Text(
        helperText,
        style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
      ),
    ]);
  }

  Widget _field(
    double width,
    TextEditingController controller,
    String label,
    IconData icon,
    String hint,
  ) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: decorationBuilder(label, icon).copyWith(hintText: hint),
      ),
    );
  }
}
