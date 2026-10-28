import 'package:flutter/material.dart';

import '../../../../core/utils/app_utils.dart';
import '../../domain/entities/cutting_protocol.dart';

class GardenCuttingProtocolButton extends StatelessWidget {
  final DateTime startDate;
  final int? cuttingCount;
  final int? Function()? cuttingCountProvider;

  const GardenCuttingProtocolButton({
    super.key,
    required this.startDate,
    this.cuttingCount,
    this.cuttingCountProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE0F2F1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('open-garden-cutting-protocol'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CuttingProtocolScreen(
              startDate: startDate,
              cuttingCount: cuttingCountProvider?.call() ?? cuttingCount,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF80CBC4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.fact_check_outlined, color: Color(0xFF00796B)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protocole Jardin — dôme adapté',
                      style: TextStyle(
                        color: Color(0xFF00695C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Voir l’étape du jour et le calendrier J0–J14+',
                      style: TextStyle(
                        color: Color(0xFF00796B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Color(0xFF00796B)),
            ],
          ),
        ),
      ),
    );
  }
}

class CuttingProtocolScreen extends StatelessWidget {
  final DateTime startDate;
  final int? cuttingCount;
  final DateTime? referenceDate;

  const CuttingProtocolScreen({
    super.key,
    required this.startDate,
    this.cuttingCount,
    this.referenceDate,
  });

  @override
  Widget build(BuildContext context) {
    final today = referenceDate ?? DateTime.now();
    final day = GardenCuttingProtocol.dayNumber(startDate, today);
    final currentStep = GardenCuttingProtocol.stepForDay(day);
    final wiltedThreshold =
        GardenCuttingProtocol.wiltedCuttingThreshold(cuttingCount);

    return Scaffold(
      appBar: AppBar(title: const Text('Protocole Jardin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(context, day, currentStep),
          if (wiltedThreshold != null) ...[
            const SizedBox(height: 12),
            _lotRule(wiltedThreshold),
          ],
          const SizedBox(height: 20),
          const Text(
            'Calendrier du dôme',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Adapte toujours l’ouverture à la réaction réelle des boutures.',
            style: TextStyle(color: Color(0xFF616161)),
          ),
          const SizedBox(height: 10),
          ...GardenCuttingProtocol.steps.map(
            (step) => _stepCard(
              step,
              day,
              wiltedThreshold: wiltedThreshold,
            ),
          ),
          const SizedBox(height: 8),
          _finalReminder(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context,
    int day,
    CuttingProtocolStep? currentStep,
  ) {
    final dateLabel = AppUtils.formatDate(startDate);
    final status = day < 0
        ? 'Début prévu dans ${-day} jour${day == -1 ? '' : 's'}'
        : 'Jour $day${currentStep == null ? '' : ' — ${currentStep.title}'}';
    final progress = day < 0 ? 0.0 : day.clamp(0, 14) / 14;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF80CBC4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.call_split, color: Color(0xFF00796B)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  GardenCuttingProtocol.name,
                  style: TextStyle(
                    color: Color(0xFF00695C),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status,
            key: const ValueKey('garden-current-day'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'Bouturage démarré le $dateLabel'
            '${cuttingCount == null ? '' : ' · $cuttingCount boutures'}',
            style: const TextStyle(color: Color(0xFF616161)),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Colors.white,
            color: const Color(0xFF00897B),
          ),
        ],
      ),
    );
  }

  Widget _lotRule(int wiltedThreshold) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFFF57C00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pour $cuttingCount boutures : à J11, remets le dôme dès '
              '$wiltedThreshold boutures flétris (plus de 20 % du lot).',
              key: const ValueKey('garden-lot-threshold'),
              style: const TextStyle(color: Color(0xFF795548)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard(
    CuttingProtocolStep step,
    int currentDay, {
    required int? wiltedThreshold,
  }) {
    final isCurrent = step.containsDay(currentDay);
    final isPast = step.endDay != null && currentDay > step.endDay!;
    final color = isCurrent
        ? const Color(0xFF00897B)
        : isPast
            ? const Color(0xFF2E7D32)
            : const Color(0xFF757575);

    return Card(
      key: ValueKey('garden-step-${step.startDay}'),
      margin: const EdgeInsets.only(bottom: 10),
      color: isCurrent ? const Color(0xFFE0F2F1) : Colors.white,
      elevation: isCurrent ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent ? const Color(0xFF4DB6AC) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                step.dayLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isCurrent)
                        const Icon(
                          Icons.arrow_left,
                          color: Color(0xFF00897B),
                        )
                      else if (isPast)
                        const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF2E7D32),
                          size: 19,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ...step.instructions.map(
                    (instruction) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('• $instruction'),
                    ),
                  ),
                  if (step.startDay == 11 && wiltedThreshold != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Pour ce lot : seuil atteint à $wiltedThreshold boutures.',
                        style: const TextStyle(
                          color: Color(0xFFF57C00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _finalReminder() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.eco_outlined, color: Color(0xFF2E7D32)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'J14 est un repère, pas une obligation : retire le dôme et '
              'repique seulement quand les boutures restent stables et que '
              'des racines saines sont visibles.',
              style: TextStyle(color: Color(0xFF33691E)),
            ),
          ),
        ],
      ),
    );
  }
}
