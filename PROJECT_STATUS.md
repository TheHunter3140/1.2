# PROJECT STATUS — Pal 1.2.0

États : Prévu · En développement · Implémenté · Compilé · Testé · Validé appareil.
**Aucune des modifications 1.2.0 (C-01 à C-13) n'est compilée ni testée à ce jour.** Ce qui est marqué « Validé appareil » provient des captures de l'utilisateur sur iPhone XR (iOS 18.7.9), avec la 1.1.0.

## Mesures validées sur appareil (1.1.0, LFM2.5-VL Q4_K_M, 0,73 Go)
| Configuration | pp | tg | 1er token |
|---|---|---|---|
| Équilibré, CPU | 18 t/s | 19,5 t/s | 1,41 s |
| Éco, CPU | 10 t/s | 14,0 t/s | 2,52 s |
| Équilibré + Metal seul | 15 t/s | 4,6 t/s | 1,62 s |
| Max (Metal, ctx 4096, K/V q8) | 7 t/s | 4,6 t/s | 3,49 s |

Conclusion mesurée : sur cet appareil et ce modèle, Metal ralentit la génération d'environ 4×. Une mesure par configuration, un seul modèle.

## Fonctionnalités
| Fonction | État | Remarque |
|---|---|---|
| Cache KV réutilisé | Validé appareil | « cache 79/90 », « 190/205 » observés. Ne réduit pas le 1er token sur des messages très courts. |
| Repli GPU → CPU au chargement | Compilé (1.1.0) | Non déclenché dans les tests. |
| Contexte plein (retrait des anciens tours) | Compilé (1.1.0) | Non testé. |
| Flash Attention / K/V q8 / micro-batch | Compilé (1.1.0) | Réglages disponibles. |
| Vérification moteur des GGUF (C-03) | Implémenté | À compiler et tester. |
| Taille finale des téléchargements (C-02) | Implémenté | À tester. |
| Pas de copie silencieuse (C-04) | Implémenté | À tester. |
| iCloud (C-05) | Implémenté | À tester avec un fichier réellement évincé. |
| Profils cohérents (C-06, C-07) | Implémenté | À mesurer (voir plan de test). |
| Réflexion désactivée par format de prompt (C-08) | Implémenté | À tester sur Qwen 3.x et DeepSeek R1. |
| Prompt vide, apparence de référence (C-09, C-12) | Implémenté | À tester sur installation neuve et sur mise à jour. |
| Réglages rapides, recommandations (C-10, C-11) | Implémenté | À tester. |
| Vision native (MTMD) | Prévu | Aucun appel dans le moteur ; l'association mmproj n'active rien. |
| Mémoire locale, RAG, recherche Web fiable | Prévu | — |
| Cible 2,7–3B | Prévu | À mesurer avant toute modification (RAM app 118–163 Mo observée avec un modèle de 0,73 Go). |

## Plan de test 1.2.0 (à faire dans cet ordre, citer l'ID en cas de problème)
1. **T-01 Build** : le workflow réussit ; lire le résumé « Contrôle du XCFramework ».
2. **T-02 Mise à jour sur la 1.1.0** : l'apparence (police, cyan, tailles) est conservée ; le prompt système est vide ; si Max/Ultra étaient forcés en GPU, ils passent en CPU (C-06, C-09, C-12, C-13).
3. **T-03 Installation neuve** : police à empattements, cyan, textes minimum (C-12).
4. **T-04 Benchmark** : Éco, Équilibré, Max ; relever pp/tg/1er token. Max ne doit plus afficher « Metal » sur cet appareil (C-06).
5. **T-05 Téléchargement** : télécharger le Qwen 3.5 0.8B ; le message final doit dire « reconnu » ou « non reconnu » (C-03).
6. **T-06 Réflexion** : Qwen 3.x ou DeepSeek R1, réflexion désactivée puis autorisée ; le texte envoyé n'est pas modifié (C-08).
7. **T-07 Accès aux fichiers** : ajouter un GGUF depuis Fichiers ; aucune copie ne doit apparaître sans clic sur « Copier dans Pal » (C-04, C-05).
8. **T-08 Réglages rapides** : bouton dans la discussion, sans perdre la saisie (C-10).
9. **T-09 Recommandations** : Réglages › Performance ; vérifier que les messages sont neutres et cohérents (C-11).

## Points de compilation à surveiller
`llama_model_desc`, `llama_model_n_ctx_train`, champ `vocab_only` (Advisor.swift) ; `ubiquitousItemDownloadingStatus` (VM.swift) ; `sysctlbyname` (Advisor.swift). Les autres appels llama.cpp ont compilé dans la 1.1.0.
