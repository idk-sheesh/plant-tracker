# Architecture

## Application

```text
lib/main.dart -> AppShell
screens / widgets -> providers (ChangeNotifier)
providers -> repositories -> DatabaseHelper / services
```

Les modules fonctionnels sont dans `lib/features/` : plantes, groupes, actions,
observations, espaces, capteurs, caméras, scanner et réglages.
`lib/core/` rassemble la base, les exports, les brouillons et les services partagés.

## Persistance

SQLite via `sqflite` est la source de vérité locale. Le schéma version 25 possède
des migrations transactionnelles, des clés étrangères et des tests de création et
de mise à niveau. Les observations sont dans `observation_assessments` et le repère
facultatif d'une plante dans `observation_code`.

Les actions manuelles et les mesures capteurs sont séparées. Chaque placement et
mesure conserve son espace historique. Les photos utilisent un stockage applicatif
géré ; les jetons sont exclus des sauvegardes. Les imports sont validés avant
transaction avec sauvegarde de secours et contrôle d'intégrité.

## Réseau facultatif

Le capteur ESP32 fournit des mesures locales avec reprise incrémentale. L'API Python
peut recevoir la télémétrie et une projection du journal pour consultation.
La caméra utilise une passerelle authentifiée et des aperçus temporaires.
Les passerelles HTTP/MQTT dédupliquent les messages. Les commandes sont expirables,
les mises à jour OTA vérifient une signature Ed25519 et les règles restent bornées.

Les tests utilisent des clients simulés et des bases temporaires. La validation
radio, des coupures et du matériel reste nécessaire avant une utilisation réelle.
