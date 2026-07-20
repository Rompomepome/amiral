# ⚓ amiral

**L'amiral ne rame pas.** Routing orchestrateur/workers pour Claude Code : un cerveau cher (Fable 5, Opus) planifie, délègue et vérifie — des mains pas chères (Sonnet, Haiku) exécutent le gros des tokens.

*English? Read the [README.md](README.md).*

## Le cliff de Fable 5

Conditions officielles du redéploiement : Fable 5 était inclus dans les plans Pro/Max/Team (50% des limites hebdo) **seulement jusqu'au 11 juillet 2026** (Anthropic a prolongé la date initiale du 7). Depuis le 12, chaque token Fable est facturé en usage credits ($10/$50 par MTok), sans bascule automatique. amiral est la réponse directe : cerveau Fable en credits + mains pas chères = tu ne paies le tarif frontier que pour la planification. Ou `AMIRAL_BRAIN=opus amiral` pour rester 100% dans ton abonnement.

## Le problème

Les modèles frontier dans Claude Code sont le moyen le plus rapide de cramer une fenêtre d'usage : fenêtre de 5 h consommée en ~7 min (Fable + ultracode, rapport communautaire), 7 agents parallèles spawnés pour une petite refacto ([issue #66867](https://github.com/anthropics/claude-code/issues/66867)). Et par défaut, chaque subagent hérite du modèle principal : orchestrer naïvement = tous les workers facturés au prix frontier.

Tu n'as pas besoin d'un modèle frontier pour renommer 40 imports. Tu en as besoin pour *planifier* le renommage et *vérifier* qu'il a eu lieu.


> Nouveau : le **butin** (`amiral-butin`) prouve le ROI depuis TES taches routees — economie contrefactuelle nette (escalades et surcout cerveau deduits), couverture affichee, 100% local (`amiral-butin init` pour demarrer). Le **journal de bord** (`amiral-journal`) signe tes commits d'une provenance vérifiable (Route + Diff-Digest recalculable). La **statusline** (opt-in, `amiral statusline install`) affiche en direct tes économies nettes butin dans la barre d'état de Claude Code, 100% local. La politique de flotte se versionne dans le repo (FLEET.md).

## La flotte

| Commande | Cerveau | Workers | Quand |
| --- | --- | --- | --- |
| `amiral` | `$AMIRAL_BRAIN` @ xhigh | **`$AMIRAL_HANDS` forcé** | 🏆 Défaut quotidien |
| `amiral-fine` | `$AMIRAL_BRAIN` @ xhigh | frontmatter (Sonnet/Haiku) | Haiku sur le mécanique |
| `amiral-ultra` | `$AMIRAL_BRAIN` + ultracode | `$AMIRAL_HANDS` forcé | Gros audits UNIQUEMENT 🔥 |
| `matelot` | — | `$AMIRAL_HANDS` @ high | Tout le reste |

Défauts : **cerveau = Opus** (inclus dans Max ; sur Pro, Claude Code sert Sonnet dans ton plan — rien à payer, rien à configurer), **mains = Sonnet**. Sur Pro et tu veux le plus léger ? `amiral-solo` (tout-Sonnet). Tu veux le cerveau premium de planification ? `AMIRAL_BRAIN=fable amiral` (facturé en credits depuis le 12 juillet).

## Installation

**Option plugin (natif) :**
```
/plugin marketplace add Rompomepome/amiral
/plugin install amiral@amiral-marketplace
```
Donne uniquement les agents + `/amiral:plan-ship`. Le butin, le journal, la statusline, `amiral-doctor` et les profils shell nécessitent `./install.sh`.

**Option installeur (tout, y compris la politique globale) :**
```bash
git clone https://github.com/Rompomepome/amiral.git && cd amiral && ./install.sh
echo 'source ~/.claude/amiral-profiles.sh' >> ~/.zshrc && source ~/.zshrc
claude update
```

Windows : profils PowerShell inclus (`shell/amiral-profiles.ps1`).

Par défaut, prompts de permission standard (sûr par défaut) — le spectre complet vitesse/sécurité est dans [docs/permissions.md](docs/permissions.md). En session : `/plan-ship <feature>` déroule plan → délégation → vérification → revue. Et pour tout ce qui est risqué ou vibe-codé : le **corsaire** (l'adversaire sous licence) et l'**advisor** — le cerveau consulté à la demande par un exécuteur léger, la forme exacte mesurée par Anthropic (~2,5x moins cher). La flotte compte 5 agents. Bonus : `amiral-savings` chiffre ton économie en local, et `amiral-report` te fait partager tes benchmarks sans télémétrie (issue pré-remplie que tu postes toi-même). Le corsaire, l'adversaire sous licence — il part du principe que le feature a déjà échoué en prod et remonte les causes (pré-mortem appliqué au code, rapport gravité × probabilité, lecture seule).

**Au-delà de Claude Code** : l'implémentation est Claude Code, mais le pattern et la discipline sont portables. [`PATTERN.md`](PATTERN.md) = la spec agnostique (Aider fait du brain/hands nativement via `--architect`) ; [`ports/AGENTS.md`](ports/AGENTS.md) = **la discipline du matelot** au standard AGENTS.md (Linux Foundation, lu par 25+ outils : Codex, Aider, OpenCode, Cursor, Gemini CLI...). L'amiral est spécifique à Claude Code ; le matelot est universel.

**Pas un framework** : là où le leader du secteur pèse 250 000+ lignes et est bloqué sur les abonnements Pro/Max (API only), amiral c'est 7 fichiers markdown et des primitives natives — ça marche sur ton abonnement. Comparatif honnête : [docs/landscape.md](docs/landscape.md).

**À faire une fois** : lance `amiral-doctor`, puis : vérifie dans `/agents` que les workers tournent sur Sonnet (pas le cerveau). Sinon : `export AMIRAL_HANDS=claude-sonnet-5`.

Le détail complet (composants, principes, benchmarks, comparatif) est dans le [README.md](README.md).

## Licence

[MIT](LICENSE)

---

*Fait partie d'une petite flotte : ⛵ Voile · 🗼 Phare · ⚓ amiral.*
