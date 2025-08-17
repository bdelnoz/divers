
# README - cmd.airmon-dos.sh

---

## 📋 Usage

./cmd.airmon-dos.sh [interface] [scan_duration_sec] [dos_interval_sec]

- interface : Interface WiFi à utiliser (ex: wlan1)  
- scan_duration_sec : Durée du scan WiFi en secondes (par défaut 600 = 10 minutes)  
- dos_interval_sec : Intervalle en secondes entre attaques DOS (par défaut 30)  

Si aucun paramètre n’est fourni, les valeurs par défaut sont utilisées.

---

## ⚙️ Fonctionnement

1. Passage en mode monitor sur l’interface WiFi spécifiée.  
2. Scan WiFi pendant la durée définie.  
3. Attaques DOS répétées toutes les dos_interval_sec secondes pendant la durée totale.  
4. Logs complets stockés dans le dossier airmon-dos/.  
5. Rapport final affichant :  
   - Nombre total de clients détectés  
   - Nombre de clients attaqués  
   - Nombre de clients ignorés (exclusions)  
   - Détails des attaques (BSSID, MAC client, date/heure)  

---

## 🎯 Paramètres conseillés

| Paramètre          | Valeur par défaut | Conseils                             |  
|--------------------|-------------------|------------------------------------|  
| scan_duration_sec  | 600 (10 minutes)  | Bon compromis entre exhaustivité et rapidité |  
| dos_interval_sec   | 30                | Intervalle raisonnable pour ne pas saturer le réseau |  

Tu peux ajuster selon tes besoins.

---

## ⚠️ Notes importantes

- Le script vérifie que l’interface est UP avant de lancer.  
- En cas d’interface DOWN persistante, il stoppe pour éviter erreurs.  
- Les logs sont sauvegardés avec timestamp et droits utilisateur pour un suivi clair.  
- Utilisation sous sudo recommandée.

---

## 💡 Astuces

- Pour un scan plus rapide, réduire scan_duration_sec.  
- Pour une attaque DOS plus agressive, diminuer dos_interval_sec (avec prudence).  
- Exclure certaines adresses MAC/BSSID dans le script pour éviter des cibles légitimes.

---

## 👋 Bon usage !

---

### Exemple de lancement :

sudo ./cmd.airmon-dos.sh wlan1 600 30

---

*Ce README est généré pour faciliter la prise en main rapide du script cmd.airmon-dos.sh.*
