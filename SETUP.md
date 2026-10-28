# Installation et vérification

## Application Android

Prérequis : Flutter avec Dart >=3.3.0 <4.0.0, SDK Android et Java 17.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

L'identifiant de démonstration est `org.example.gardenjournal`.
Le dépôt ne contient ni projet iOS complet ni application de bureau.
Utiliser un émulateur ou un appareil de développement sans données personnelles.

## Services facultatifs

Python 3.11 ou supérieur, sans dépendance externe :

```sh
python -m unittest discover -s cloud_api/tests
python -m unittest discover -s camera_gateway/tests
```

Les modèles `config/cloud.env.template.txt` et `config/camera.env.template.txt` décrivent la configuration
Docker. Copier le modèle vers le fichier local correspondant et créer de nouveaux
secrets avant un déploiement. Les secrets et les données d'exécution restent hors Git.
Les services exposent HTTP derrière un proxy TLS à configurer ; ils ne doivent pas
être publiés directement sur Internet. Les valeurs `.invalid` sont des exemples.

## ESP32

Les sketches sont sous `firmware/`. Copier `sensor-config.template.txt` vers
`secrets.h` pour le capteur, `storage-config.template.txt` vers `secrets.storage.h`
pour le profil conservation, ou `camera-config.template.txt` vers `config.h`
pour la caméra. Ces en-têtes sont créés uniquement en local et ignorés par Git.
Renseigner localement le Wi-Fi et les jetons. Le capteur utilise Arduino ESP32,
RTClib et les bibliothèques intégrées HTTP, Wi-Fi et LittleFS ; la caméra utilise
Arduino ESP32 avec le support caméra. Les profils et broches doivent être adaptés
au montage. Le contrat capteur comprend `GET /status`, `GET /readings?since=...`
et `POST /config`. Le mode debug accepte HTTP local ; la release exige HTTPS.

## Signature Android

Les builds release exigent une clé personnelle indépendante et un fichier local
`android/key.properties`, à créer depuis `android/signing.template.properties`.
Ne jamais publier le keystore ou ses mots de passe. Un build release n'installe rien.

## Données

La base `garden_journal.db` est créée au premier usage. Les sauvegardes locales
contiennent les photos choisies et ne sont pas chiffrées. Les identifiants cloud et
caméra sont gardés en mémoire ou dans le coffre sécurisé de la plateforme.
