# Script Bash — Analyse Wi-Fi avec airodump-ng

Ce script lance un scan Wi-Fi via `airodump-ng` en mode moniteur sur une interface sans fil donnée, pendant une durée définie. Il génère automatiquement des fichiers `.csv` et `.pcap`, dans un sous-répertoire local (`./Sniffing`) avec des logs dans `./Logs`.

## Fonctionnalités

- Bascule l'interface réseau en mode moniteur automatiquement
- Scan avec `airodump-ng` (`--gpsd`, `--manufacturer`, etc.)
- Résultats enregistrés dans un répertoire local propre
- Nettoyage automatique : retour en mode managed
- Gestion de l’interruption (Ctrl+C)
- Attribution des fichiers à l’utilisateur courant

## Répertoires créés

- `./Sniffing/` : fichiers `.csv` et `.pcap`
- `./Logs/` : réservé à un usage futur

## Utilisation

```bash
./nom_du_script.sh [interface] [durée_en_secondes]
```

- **interface** : nom de l’interface Wi-Fi (ex. `wlan1`)
- **durée_en_secondes** : durée du scan

### Exemples

```bash
./scan-wifi.sh wlan1 30
./scan-wifi.sh
```

## Prérequis

- Accès `sudo`
- `aircrack-ng` installé
- Interface réseau compatible avec le mode moniteur

## Nettoyage automatique

- Restaure l’interface en mode `managed`
- Gère Ctrl+C proprement
- Change les permissions des fichiers générés vers l’utilisateur courant

## Licence

Ce script est publié sous licence **MIT**.  
Libre de l’utiliser, modifier et redistribuer avec mention de l’auteur.

## Auteur

Bruno DELNOZ  
Rochefort, Belgique  
Expert en sécurité, intégration, Wi-Fi sniffing
