#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Nom du script : chatgptcreationtitlefromcontent_loop.py
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Target usage : Extraction et mise à jour des titres de chats ChatGPT via Brave avec profil copié, gestion complète du traitement en boucle.
Version : v9.8 - Date : 2025-07-18

Fonctionnalités :
- Chargement règles depuis fichier configurable
- Options --exec (exécution réelle), --test (simulation), --rulesfile, --numchats, --help, --delete
- Initialisation WebDriver Brave avec profil copié local dans ./brave_profile_selenium
- Navigation complète sur les chats : extraction, modification des titres, passage au suivant
- Logs détaillés dans ./chatgptcreationtitlefromcontent_loop.log
- Suppression propre du profil temporaire via --delete
- Prérequis vérifiés sans sudo
"""

import os
import sys
import shutil
import logging
import time
import re
import psutil
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import WebDriverException, NoSuchElementException

SCRIPT_NAME = os.path.basename(__file__).replace('.py', '')
LOG_FILE = f"{SCRIPT_NAME}.log"
DEFAULT_RULES_FILE = "RuleCreationTitre.txt"
BRAVE_PROFILE_ORIG = os.path.expanduser("~/.config/BraveSoftware/Brave-Browser/Default")
BRAVE_PROFILE_TEMP = os.path.join(os.getcwd(), "brave_profile_selenium")
BRAVE_BINARY_PATH = "/usr/bin/brave-browser"  # Adapter si besoin

logging.basicConfig(filename=LOG_FILE, level=logging.DEBUG,
                    format='%(asctime)s - %(levelname)s - %(message)s')

def show_help():
    help_text = f"""
Usage: ./{SCRIPT_NAME}.py [--exec|--test] [--rulesfile=FILE] [--numchats=NUMBER|ALL] [--delete] [--help]

Arguments:
  --exec                  Lance l'exécution réelle (modifie les titres).
  --test                  Mode test : simule sans modifier les titres.
  --rulesfile=FILE        Chemin vers le fichier de règles (défaut : {DEFAULT_RULES_FILE}).
  --numchats=NUMBER|ALL   Nombre de chats à traiter (défaut : 3).
  --delete                Supprime proprement le profil Brave temporaire créé.
  --help                  Affiche cette aide.

Exemples :
  ./{SCRIPT_NAME}.py --exec --numchats=5
  ./{SCRIPT_NAME}.py --test --rulesfile=RuleCreationTitre.txt --numchats=ALL
"""
    print(help_text)

def check_prerequisites():
    logging.info("Vérification des prérequis...")
    if not os.path.exists(BRAVE_BINARY_PATH):
        logging.error(f"Navigateur Brave non trouvé à : {BRAVE_BINARY_PATH}")
        print(f"Erreur : Brave browser non trouvé à {BRAVE_BINARY_PATH}")
        sys.exit(1)
    try:
        import psutil
    except ImportError:
        logging.error("Module psutil manquant.")
        print("Erreur : module psutil manquant.")
        sys.exit(1)
    logging.info("Tous les prérequis sont présents.")

def copy_profile():
    if os.path.exists(BRAVE_PROFILE_TEMP):
        logging.info(f"Profil Brave temporaire déjà existant : {BRAVE_PROFILE_TEMP}")
        return
    logging.info(f"Copie profil Brave de {BRAVE_PROFILE_ORIG} vers {BRAVE_PROFILE_TEMP}")
    shutil.copytree(BRAVE_PROFILE_ORIG, BRAVE_PROFILE_TEMP, dirs_exist_ok=True)

def delete_profile():
    if os.path.exists(BRAVE_PROFILE_TEMP):
        logging.info(f"Suppression du profil temporaire : {BRAVE_PROFILE_TEMP}")
        shutil.rmtree(BRAVE_PROFILE_TEMP)
        print(f"Profil temporaire supprimé : {BRAVE_PROFILE_TEMP}")
    else:
        print("Aucun profil temporaire à supprimer.")

def init_webdriver():
    logging.info("Initialisation WebDriver Brave...")
    options = Options()
    options.binary_location = BRAVE_BINARY_PATH
    options.add_argument(f"--user-data-dir={BRAVE_PROFILE_TEMP}")
    options.add_argument("--disable-extensions")
    options.add_argument("--start-maximized")
    try:
        driver = webdriver.Chrome(options=options)
        logging.info(f"WebDriver Brave initialisé avec profil {BRAVE_PROFILE_TEMP}")
        driver.get("https://chat.openai.com/")
        time.sleep(5)
        if not driver.current_url.startswith("https://chat.openai.com/"):
            logging.error("ChatGPT non accessible, redirection échouée.")
            sys.exit(1)
        logging.info("ChatGPT chargé avec succès.")
        return driver
    except WebDriverException as e:
        logging.error(f"Erreur WebDriver : {str(e)}")
        print("Erreur lors de l'initialisation WebDriver.")
        sys.exit(1)

def load_rules(rulesfile):
    if not os.path.exists(rulesfile):
        logging.error(f"Fichier de règles manquant : {rulesfile}")
        print(f"Erreur : fichier de règles manquant ({rulesfile})")
        sys.exit(1)
    with open(rulesfile, 'r', encoding='utf-8') as f:
        rules = f.read()
    logging.info(f"Règles chargées depuis {rulesfile}")
    return rules

def get_chat_list(driver):
    try:
        chats_list = driver.find_elements("css selector", "div[class*='chatListItem']")  # Selector à adapter
        logging.info(f"{len(chats_list)} chats détectés.")
        return chats_list
    except Exception as e:
        logging.error(f"Erreur récupération liste chats : {str(e)}")
        return []

def extract_title_from_chat(driver):
    try:
        title_element = driver.find_element("css selector", "h1[class*='chatTitle']")
        title = title_element.text.strip()
        logging.debug(f"Titre extrait : {title}")
        return title
    except NoSuchElementException:
        logging.error("Titre chat non trouvé.")
        return None

def apply_new_title(driver, new_title, test_mode):
    if test_mode:
        logging.info(f"[TEST] Nouveau titre à appliquer : {new_title}")
        print(f"[TEST] Nouveau titre à appliquer : {new_title}")
        return True
    try:
        edit_button = driver.find_element("css selector", "button[class*='editTitle']")
        edit_button.click()
        time.sleep(1)
        input_title = driver.find_element("css selector", "input[class*='titleInput']")
        input_title.clear()
        input_title.send_keys(new_title)
        save_button = driver.find_element("css selector", "button[class*='saveTitle']")
        save_button.click()
        logging.info(f"Titre modifié en : {new_title}")
        print(f"Titre modifié en : {new_title}")
        time.sleep(2)
        return True
    except Exception as e:
        logging.error(f"Erreur modification titre : {str(e)}")
        print("Erreur lors de la modification du titre.")
        return False

def go_to_next_chat(driver, current_index, chats_count):
    if current_index + 1 >= chats_count:
        logging.info("Dernier chat atteint, fin de traitement.")
        return False
    try:
        next_chat_selector = f"div[class*='chatListItem']:nth-child({current_index + 2})"
        next_chat = driver.find_element("css selector", next_chat_selector)
        next_chat.click()
        time.sleep(3)
        logging.info(f"Passage au chat index {current_index + 1}")
        return True
    except Exception as e:
        logging.error(f"Erreur passage chat suivant : {str(e)}")
        return False

def process_chats(driver, rules, numchats, test_mode):
    logging.info("Début du traitement des chats...")
    chats_list = get_chat_list(driver)
    if not chats_list:
        print("Aucun chat trouvé.")
        return

    total_to_process = numchats if isinstance(numchats, int) else len(chats_list)
    total_to_process = min(total_to_process, len(chats_list))

    for i in range(total_to_process):
        logging.info(f"Traitement du chat {i+1}/{total_to_process}")
        try:
            chats_list[i].click()
            time.sleep(3)
        except Exception as e:
            logging.error(f"Erreur ouverture chat index {i} : {str(e)}")
            continue

        old_title = extract_title_from_chat(driver)
        if old_title is None:
            logging.warning(f"Chat {i+1} titre introuvable, saut.")
            continue

        new_title = old_title
        for rule_line in rules.splitlines():
            if "prefix:" in rule_line:
                prefix = rule_line.split("prefix:")[1].strip()
                new_title = f"{prefix} {new_title}"
                break  # Extrait uniquement premier prefix

        if new_title != old_title:
            success = apply_new_title(driver, new_title, test_mode)
            if not success:
                logging.error(f"Échec modification titre chat {i+1}")
        else:
            logging.info(f"Aucune modification pour chat {i+1}")

        if i + 1 < total_to_process:
            if not go_to_next_chat(driver, i, total_to_process):
                logging.info("Impossible de passer au chat suivant.")
                break

    logging.info("Traitement complet des chats terminé.")

def parse_args():
    exec_mode = False
    test_mode = False
    rulesfile = DEFAULT_RULES_FILE
    numchats = 3
    delete_flag = False

    for arg in sys.argv[1:]:
        if arg == "--help":
            show_help()
            sys.exit(0)
        elif arg == "--exec":
            exec_mode = True
        elif arg == "--test":
            test_mode = True
        elif arg.startswith("--rulesfile="):
            rulesfile = arg.split("=",1)[1]
        elif arg.startswith("--numchats="):
            val = arg.split("=",1)[1]
            if val.upper() == "ALL":
                numchats = "ALL"
            else:
                try:
                    numchats = int(val)
                except ValueError:
                    print("Erreur : --numchats doit être un entier ou ALL.")
                    sys.exit(1)
        elif arg == "--delete":
            delete_flag = True
        else:
            print(f"Argument inconnu : {arg}")
            show_help()
            sys.exit(1)

    if exec_mode and test_mode:
        print("Erreur : ne pas utiliser --exec et --test simultanément.")
        sys.exit(1)

    if numchats == "ALL":
        numchats = sys.maxsize

    return exec_mode, test_mode, rulesfile, numchats, delete_flag

def main():
    exec_mode, test_mode, rulesfile, numchats, delete_flag = parse_args()

    if delete_flag:
        delete_profile()
        sys.exit(0)

    check_prerequisites()
    copy_profile()
    driver = init_webdriver()
    rules = load_rules(rulesfile)

    if exec_mode or test_mode:
        process_chats(driver, rules, numchats, test_mode)
        driver.quit()
        sys.exit(0)
    else:
        show_help()
        driver.quit()
        sys.exit(1)

if __name__ == "__main__":
    main()
