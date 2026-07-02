# fable-lean

**Gros cerveau, petites mains.** Routing de modèles optimisé quota pour Claude Code : un modèle frontier (Fable 5) en *orchestrateur*, l'exécution déléguée à des workers moins chers (Sonnet / Haiku).

*English? Read the [README.md](README.md).*

## Le problème

Fable 5 est le modèle le plus capable de Claude Code — et le moyen le plus rapide de cramer une fenêtre d'usage :

- Fable + `ultracode` : une fenêtre de 5 h consommée en **~7 minutes** sur un audit codebase-wide (rapport communautaire, r/ClaudeAI).
- Fable en ultracode observé en train de **spawner 7 agents parallèles pour une petite refacto** ([issue #66867](https://github.com/anthropics/claude-code/issues/66867)).
- Par défaut, chaque subagent hérite du modèle principal : orchestrer avec Fable naïvement = **tous les workers sont aussi Fable**.

Tu n'as pas besoin d'un modèle frontier pour renommer 40 imports. Tu en as besoin pour *planifier* le renommage et *vérifier* qu'il a eu lieu.

## Le pattern

Trois leviers combinés :

1. **`CLAUDE_CODE_SUBAGENT_MODEL`** — force tous les subagents sur un modèle moins cher, quoi que Fable décide de spawner.
2. **`model:` par agent (frontmatter)** — routing fin : Sonnet pour l'implémentation réelle, Haiku pour le mécanique.
3. **Une politique mémoire (`CLAUDE.md`)** — apprend à l'orchestrateur à déléguer, à ne PAS lancer 7 agents pour une tâche d'un seul, et à vérifier (build/typecheck/lint) avant de dire « terminé ».

## Installation (2 min)

```bash
git clone https://github.com/YOUR_USERNAME/fable-lean.git
cd fable-lean
./install.sh
echo 'source ~/.claude/fable-aliases.sh' >> ~/.zshrc && source ~/.zshrc
claude update
```

| Commande | Cerveau | Workers | Quand |
| --- | --- | --- | --- |
| `fable-lean` | Fable 5 @ xhigh | **Sonnet forcé** | 🏆 Défaut quotidien |
| `fable-fine` | Fable 5 @ xhigh | frontmatter (Sonnet/Haiku) | Haiku pour le travail mécanique |
| `fable-ultra` | Fable 5 + ultracode | Sonnet forcé | Gros audits UNIQUEMENT. 🔥 Incinérateur de quota |
| `sonnet-fast` | Sonnet @ high | hérité | Tout ce qui ne mérite pas Fable |

Par défaut, les profils gardent les **prompts de permission standard** (sûr par défaut). Pour aller plus vite en connaissance de cause : [docs/permissions.md](docs/permissions.md). Windows : profils PowerShell inclus (`shell/fable-profiles.ps1`).

En session : `/plan-ship <description de la feature>` déroule plan → délégation → vérification → revue.

## Vérifie que le routing marche vraiment

À faire une fois : lance `fable-lean`, demande une tâche qui délègue, et vérifie dans `/agents` que les workers tournent sur **Sonnet** (pas Fable). Sinon, remplace `sonnet` par l'ID complet (`claude-sonnet-5`) dans `~/.claude/fable-aliases.sh` — un fallback silencieux vers Fable saignerait ton quota sans que tu le voies.

Le détail complet (composants, principes de design, calcul d'économie) est dans le [README.md](README.md) anglais.

## Licence

[MIT](LICENSE)
