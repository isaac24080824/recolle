# Contribuer à Recolle

Les signalements de bugs et les propositions d’amélioration sont les bienvenus dans les [issues](https://github.com/isaac24080824/recolle/issues).

Indiquez votre version de macOS, le modèle de Mac et les étapes pour reproduire le problème. Utilisez des exemples fictifs : ne joignez pas votre historique du presse-papier, vos mots de passe ou votre base personnelle.

## Modifier le code

1. Créez un fork et une branche dédiée à votre modification.
2. Installez les outils développeur Apple récents.
3. Exécutez `./build.sh`, puis `./test.sh`.
4. Vérifiez les interactions dans l’application si vous avez modifié l’interface.
5. Ouvrez une pull request qui explique le problème, la correction et les vérifications.

Le projet utilise Swift, SwiftUI, AppKit et SQLite fournis avec macOS. Aucune dépendance externe n’est nécessaire. L’interface est actuellement en français.

Les tests utilisent des données fictives et un presse-papier nommé distinct ; ils ne lisent ni ne modifient votre presse-papier personnel. Le script `./measure.sh` crée un historique temporaire de 5 000 éléments pour mesurer les opérations de stockage et de recherche.

Pour une vérification visuelle dans un historique isolé, lancez l’application construite avec :

```sh
open dist/Recolle.app --args --verification-directory "$PWD/.build/verification" -paused YES -retention 0
```

Fermez cette instance avant de relancer l’application normalement. La pause passée en argument concerne uniquement ce lancement.

En contribuant, vous acceptez que vos contributions soient distribuées sous la licence MIT du projet.
