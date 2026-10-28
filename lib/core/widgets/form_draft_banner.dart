import 'package:flutter/material.dart';

class FormDraftBanner extends StatelessWidget {
  final bool restored;
  final bool containsSensitiveField;

  const FormDraftBanner({
    super.key,
    this.restored = false,
    this.containsSensitiveField = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: restored ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: restored ? const Color(0xFFA5D6A7) : const Color(0xFF90CAF9),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              restored ? Icons.restore : Icons.save_outlined,
              size: 20,
              color:
                  restored ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                restored
                    ? 'Brouillon restauré. Votre saisie précédente a été récupérée.'
                    : containsSensitiveField
                        ? 'Brouillon local automatique. Les mots de passe et jetons ne sont jamais enregistrés.'
                        : 'Brouillon local automatique : la saisie reste protégée si le téléphone se verrouille.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
}
