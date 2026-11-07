# Pal 1.1.0 — vitesse, stabilité, fluidité

## Vitesse
- **Cache KV réutilisé** : Pal ne retraite plus tout l'historique à chaque message, seulement les nouveaux tokens (cause principale de la lenteur sur LFM 2.5 1.2B). Le jeton de fin est aussi inscrit dans le cache pour réutiliser le tour précédent en entier.
- **GPU Metal automatique** : activé par défaut si l'appareil le permet (iOS 18+, puce A14+), avec **repli automatique sur CPU** si le chargement échoue.
- **Flash Attention** (Auto / Activée / Désactivée), **cache K/V compact q8** (~2× moins de RAM) et **micro-batch** réglables.
- Nouveaux profils : Équilibré = contexte 2048, batch 512 (comme PocketPal) ; les anciens profils sont migrés au premier lancement.
- Protection thermique moins agressive (état « tiède » = plus de bridage).
- Pénalité de répétition ignorée quand elle vaut 1.0.

## Stabilité
- **Contexte plein** : les plus anciens tours sont retirés du prompt (prompt système et dernier message conservés) au lieu de planter, avec un message d'information.
- Une erreur de décodage en cours de génération est signalée (« génération interrompue ») et le cache est réinitialisé.
- Réglages enregistrés tolérants aux nouvelles options (aucune perte au passage 1.0.x → 1.1.0).

## Fluidité
- Affichage en **texte simple pendant la génération**, rendu Markdown/LaTeX complet à la fin (option « Affichage fluide »).
- Rafraîchissement du flux à 80 ms au lieu de 50 ms.

## Build
- Le workflow contrôle l'API du XCFramework et la présence de Metal (résumé du run GitHub Actions).
