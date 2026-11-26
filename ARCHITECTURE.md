# mSOUND — architecture proposée (à valider avant tout code)

Design : Flat Round, arrondi 4, sombre / clair sable. Langage : Swift natif (proposition, à confirmer).

## Modules
- **mSOUNDApp** (SwiftUI + AppKit) : fenêtre éditeur, réglages, À propos, mise à jour auto (modèle mBACKUP `Updater.swift`), 4 langues (clés `upd.*`, `about.*`).
- **AudioEngine** (Swift, Core Audio / AVFoundation / AudioToolbox) : lecture temps réel (AVAudioEngine), enregistrement, effets (normaliser, fondus, EQ, compresseur, réduction de bruit via AUs), mesure crête / LUFS.
- **WaveformStore** : pyramide de crêtes (min/max par niveaux de zoom) calculée en arrière-plan et mise en cache sur disque : ouverture instantanée, zoom fluide même sur 1 h de WAV.
- **EditModel** : liste d'édition non destructive (EDL : segments d'un fichier source), annuler/rétablir illimité ; le fichier d'origine n'est écrit qu'à l'export.
- **Converter** : conversion et découpe. Sans perte quand c'est possible (copie de paquets pour découpe M4A/MP3/FLAC sans ré-encodage ; WAV/AIFF/FLAC/ALAC par ré-échantillonnage nul). Encodeurs : AudioToolbox (AAC, ALAC, MP3 lecture seule → MP3 écriture via libmp3lame embarquée), FLAC (libFLAC), Opus/OGG (libopus + libogg embarquées). Étiquettes et pochette conservées (AVMetadata).
- **BatchQueue** : file de conversions par lot, parallélisme limité aux cœurs, annulation, avertissements (ex. MP3 → FLAC sans gain).
- **FinderExtension** (FinderSync, Swift) : entrées de menu plates au premier niveau, une par format actif + « Éditer avec mSOUND » ; envoie les fichiers à l'appli (XPC / URL scheme `msound://convert?format=flac`), qui travaille en arrière-plan sans prendre le focus (petite fenêtre de progression).
- **Settings** : formats affichés dans le menu Finder, qualité, dossier de sortie, écrasement, thème, langue.

## Flux
Clic droit sur des fichiers → FinderExtension → URL/XPC → BatchQueue → Converter → fichier à côté de l'original → pastille / fenêtre de progression.
Ouverture d'un fichier → WaveformStore (cache) + EditModel → AudioEngine (lecture) → Export via Converter.

## Données
- Réglages : UserDefaults (suite partagée App Group avec l'extension Finder).
- Cache de formes d'onde : `~/Library/Caches/mSOUND/` ; aucune donnée utilisateur ailleurs.

## Contraintes
- App signée avec le certificat local, bundle dev `….dev` pour les essais, installée dans Applications Personnelles (DESKTOP MAC TOOLKIT).
- Extension Finder : à activer une fois dans Réglages Système > Extensions (le dire dans l'appli au premier lancement).
- Encodeurs tiers : MP3, FLAC, Opus, OGG demandent des bibliothèques embarquées (LAME LGPL, libFLAC, libopus : licences compatibles avec distribution publique).

## Étapes proposées
1. Moteur : Converter + BatchQueue + tests (sans interface). 2. FinderExtension + fenêtre de progression. 3. Éditeur (forme d'onde, sélection, lecture, EDL). 4. Effets et enregistrement. 5. Réglages, À propos, mise à jour auto, 4 langues, icône.
