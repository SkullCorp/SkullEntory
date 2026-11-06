# SkullWidgets – widgets iOS pour tes web apps

App iOS (SwiftUI + WidgetKit, iOS 17+) qui fait le pont entre ton iPhone et tes web apps :

- **Lire** : tes web apps renvoient un petit JSON, que SkullWidgets affiche dans des widgets
  (écran d'accueil petit/moyen/grand, écran verrouillé circulaire/rectangulaire/en ligne).
- **Envoyer** : les widgets ont des **boutons interactifs** qui envoient une requête HTTP à ta web app
  (POST/PUT/GET…, avec un corps JSON). Pas besoin d'ouvrir l'app.
- **Raccourcis / Siri** : action « Envoyer à une web app » (méthode, chemin, corps → renvoie la réponse),
  et « Rafraîchir les widgets ». Tu peux l'enchaîner avec un scan de QR code, une localisation, une automatisation NFC…
- **Home Assistant** : type de source natif. SkullWidgets rend ton template Jinja via `/api/template`, et les
  boutons appellent `/api/services/...` ou envoient un événement.

Pas besoin de compte développeur payant : l'IPA est compilée par GitHub Actions et installée avec
**SideStore** ou **AltStore** et ton Apple ID gratuit.

---

## 1. Obtenir l'IPA

Le workflow `.github/workflows/ios.yml` compile l'app sur un runner macOS GitHub (gratuit pour un dépôt public) :

| Déclencheur | Résultat |
|---|---|
| push sur `main` ou une branche `claude/**` | artefact `SkullWidgets-ipa` (onglet **Actions** → le run → *Artifacts*) |
| tag `v1.0.0`, `v1.1.0`… | **Release** GitHub avec `SkullWidgets.ipa` + `altstore-source.json` |

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Tu n'as besoin d'aucun Mac : le projet Xcode est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen)
à partir de `project.yml`.

## 2. Installer sur l'iPhone (sans compte payant)

### Option A – SideStore (recommandé : pas d'ordinateur au quotidien)

1. Installe SideStore en suivant <https://docs.sidestore.io> (une seule fois avec un ordi, pour générer le fichier de pairing).
2. Ajoute la source : **Sources → +** →
   `https://github.com/SkullCorp/SkullEntory/releases/latest/download/altstore-source.json`
   (ou télécharge `SkullWidgets.ipa` et ouvre-le avec SideStore via « Partager »).
3. Installe **SkullWidgets**, puis ajoute le widget : appui long sur l'écran d'accueil → **+** → *SkullWidgets*.
4. SideStore re-signe l'app tous les 7 jours tout seul (il faut que son VPN local soit actif de temps en temps).

### Option B – AltStore classique

Même principe, mais le rafraîchissement hebdomadaire passe par AltServer (Mac/PC sur le même Wi-Fi).

> **AltStore PAL (UE)** ne convient pas : il n'installe que des apps notariées par Apple, ce qui demande un compte
> développeur payant.

### Limites du compte Apple gratuit

- L'app expire au bout de **7 jours** si elle n'est pas rafraîchie. Les widgets cessent alors de marcher jusqu'au rafraîchissement suivant.
  → Pense à **Importer / exporter** (menu ⋯) pour sauvegarder ta config.
- Au maximum **3 apps sideloadées** actives, et **10 App IDs** par semaine (SkullWidgets en consomme 2 : l'app et le widget).
- **Pas de notifications push** (APNs) : une web app ne peut pas « pousser » vers le widget. C'est le widget
  qui va chercher les données (voir §4).

## 3. Configurer une web app

Dans l'app : **+** →

| Champ | Exemple |
|---|---|
| Type | `JSON (URL)` ou `Home Assistant (template)` |
| URL | `https://mon-app.fr/api/widget` / `http://homeassistant.local:8123` |
| Jeton | envoyé en `Authorization: Bearer <jeton>` (ou dans le header de ton choix, ex. `X-Api-Key`) |

Le bouton **Tester la connexion** affiche l'aperçu avant d'enregistrer. Ensuite, sur le widget :
appui long → **Modifier le widget** → choisis la web app. Tu peux mettre plusieurs widgets pour plusieurs web apps.

**Lien d'ajout en un clic**, à mettre dans ta web app :

```
skullwidgets://add?name=Inventaire&url=https%3A%2F%2Fmon-app.fr%2Fapi%2Fwidget&token=XXX
```

(paramètres optionnels : `kind=homeAssistant`, `header=X-Api-Key`, `template=...`)

Autres liens : `skullwidgets://refresh` (tout rafraîchir), `skullwidgets://source?id=<uuid>`.

## 4. Le format JSON

Tous les champs sont optionnels. Les nombres et booléens sont acceptés partout où un texte est attendu
(pratique avec les templates HA).

```json
{
  "title": "Inventaire",
  "subtitle": "Atelier",
  "icon": "shippingbox.fill",
  "tint": "#FF9534",
  "url": "https://mon-app.fr",
  "refresh": 900,
  "value": 128,
  "unit": "articles",
  "gauge": { "value": 72, "min": 0, "max": 100, "label": "Stock" },
  "items": [
    { "label": "Stock bas", "value": 3, "icon": "exclamationmark.triangle.fill", "color": "#FF3B30" },
    { "label": "Commandes", "value": 5, "icon": "cart.fill" }
  ],
  "actions": [
    {
      "id": "sync",
      "label": "Synchro",
      "icon": "arrow.triangle.2.circlepath",
      "color": "green",
      "method": "POST",
      "url": "/api/sync",
      "body": { "source": "widget" },
      "headers": { "X-Extra": "1" }
    }
  ]
}
```

| Champ | Rôle |
|---|---|
| `icon` | nom de [SF Symbol](https://developer.apple.com/sf-symbols/) |
| `tint` / `color` | `#RRGGBB`, `#RRGGBBAA` ou `red`, `green`, `orange`, `blue`, `yellow`, `purple`, `indigo`, `gray`… |
| `url` | ouverte quand on touche le widget (en dehors des boutons) |
| `refresh` | intervalle souhaité en secondes (minimum 300). iOS garde la main : compte environ 40 à 70 rafraîchissements par jour et par widget |
| `value` / `unit` | grosse valeur mise en avant |
| `gauge` | jauge (barre sur l'écran d'accueil, cercle sur l'écran verrouillé) |
| `items` | lignes libellé / valeur (jusqu'à 7 sur le grand widget) |
| `actions` | boutons : 1 sur le petit widget, 3 sur le moyen, 4 sur le grand. `method` vaut `POST` par défaut. `url` est absolue ou **relative à l'URL de la source** |

**Astuce temps réel** : si la réponse d'une action est elle-même un JSON SkullWidgets, le widget l'affiche
immédiatement, sans attendre le prochain rafraîchissement (voir `examples/node-server.mjs`).

**Sécurité** : le jeton n'est envoyé qu'aux URL du **même hôte** que la source. La config est stockée dans
l'App Group de l'app (pas dans le trousseau, qui pose problème en sideload). L'HTTP en clair est autorisé
pour les apps sur le réseau local.

## 5. Exemples

- `examples/node-server.mjs` : web app de démo (inventaire avec des boutons +1/-1). Lance `node examples/node-server.mjs`, puis dans l'app : URL `http://<ip-du-pc>:3000/api/widget`, jeton `secret`.
- `examples/home-assistant.jinja` : template HA complet (température, lumières, alarme, jauge batterie, boutons « toggle » et « script »).
- `examples/home-assistant-automation.yaml` : automatisation qui réagit à un bouton du widget (événement `skullwidgets_widget`).

### Raccourcis : envoyer n'importe quoi à une web app

Dans Raccourcis, ajoute l'action **Envoyer à une web app** :

- Web app : *Inventaire*
- Chemin : `/api/scan`
- Méthode : `POST`
- Corps : `{"code": "<variable Résultat du scan>"}`

La réponse est renvoyée sous forme de texte. Si c'est un JSON SkullWidgets, les widgets se mettent à jour.
Avec Home Assistant : chemin `/api/events/mon_evenement` ou `/api/services/script/turn_on`.

## 6. Développement

```
project.yml              # XcodeGen : app + extension widget, App Group
App/                     # app SwiftUI (liste, édition, test, import/export, liens skullwidgets://)
Widget/                  # extension WidgetKit (timeline, vues par taille, boutons interactifs)
Shared/                  # modèles, réseau, stockage partagé, App Intents (compilés dans les 2 cibles)
scripts/make_source.py   # génère la source AltStore/SideStore
```

Avec un Mac : `brew install xcodegen && xcodegen generate && open SkullWidgets.xcodeproj`.

**Note sideload** : AltStore et SideStore renomment l'App Group (suffixe avec ton Team ID) et l'indiquent
dans `ALTAppGroups` de l'Info.plist. `AppGroup.identifier` le détecte automatiquement. Le workflow injecte
les entitlements dans l'IPA non signée avec `ldid`, pour que SideStore et AltStore sachent qu'il faut créer l'App Group.
