# Pal 1.2.1 — correctif ciblé de fluidité

## Correction
- Restaure `liteStream = true` par défaut.
- Les préférences anciennes qui ne contiennent pas cette clé retombent sur `true`.
- La migration depuis Pal 1.1.0 ne force plus le rendu riche pendant la génération.

## Pourquoi
Avec `liteStream = false`, `Render.swift` utilise `RichText` pendant le streaming. Ce composant peut retraiter Markdown/LaTeX à chaque mise à jour de texte. Avec `liteStream = true`, Pal affiche du texte simple pendant la génération puis applique le rendu riche une fois la réponse terminée.

## Périmètre
Correctif limité à trois lignes de comportement dans `Library.swift` et `VM.swift`. Aucun changement du moteur llama.cpp, des paramètres d'inférence, des profils CPU/GPU, ni des fonctionnalités.

## Validation requise
Ce correctif source n'a pas été compilé ni mesuré sur iPhone. Après compilation, comparer sur le même iPhone XR, même GGUF, même conversation neuve et mêmes paramètres :
- fluidité du défilement et de la saisie pendant la génération ;
- temps jusqu'au premier token ;
- tokens/s ;
- empreinte mémoire maximale.

Le correctif vise la charge de rendu UI ; il ne promet pas d'augmenter les tokens/s du moteur.
