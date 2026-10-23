# Changelog

## 1.0.0 (2026-10-23)

- Première version, basée sur cursor-accent 1.1.0.
- Sélecteur graphique : couleurs du thème, palette de 16 couleurs, couleurs
  récentes, code hex et pipette (`hyprpicker`).
- Le mode thème peut suivre n'importe quelle couleur du `colors.toml`
  (accent par défaut).
- Suivi du thème par le service du shell (surveillance de `colors.toml`),
  sans hook `theme-set` / `post-boot` à installer.
- Style *Contour* ou *Rempli*, en plus de la forme arrondie / pointue.
- Pas de recompilation quand les couleurs n'ont pas changé.
