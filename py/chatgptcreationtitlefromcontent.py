#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Nom du script : chatgptcreationtitlefromcontent.py
Target usage : Automatiser la création et modification de titre d'un chat ChatGPT via Selenium selon règles strictes.
Version : v1.0 - Date : 2025-07-17
"""

import sys
import time
import argparse
import logging
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.common.exceptions import NoSuchElementException, TimeoutException
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# Définition du chemin par défaut du fichier de règles
DEFAULT_RULES_FILE = "RuleCreationTitre.txt"

# Configuration du logger
logger = logging.getLogger("chatgptcreationtitlefromcontent")
logger.setLevel(logging.DEBUG)
fh = logging.FileHandler("chatgptcreationtitlefromcontent.log")
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
fh.setFormatter(formatter)
logger.addHandler(fh)

def parse_args():
    parser = argparse.ArgumentParser(
        description="Script Selenium pour envoyer message à ChatGPT et changer titre du chat automatiquement selon règles.",
        add_help=False)
    parser.add_argument('--help', action='help', help='Affiche ce message et quitte.')
    parser.add_argument('--exec', action='store_true', help='Lance l\'exécution principale du script.')
    parser.add_argument('--chat-title', type=str, required=True, help='Titre actuel du chat ChatGPT à cibler.')
    parser.add_argument('--rulesfile', type=str, default=DEFAULT_RULES_FILE,
                        help='Chemin vers fichier texte contenant les règles de création de titre (défaut: RuleCreationTitre.txt).')
    return parser.parse_args()

def load_rules(rulesfile):
    try:
        with open(rulesfile, 'r', encoding='utf-8') as f:
            rules = f.read()
            logger.info(f"Règles chargées depuis {rulesfile}")
            return rules
    except Exception as e:
        logger.error(f"Erreur lecture fichier règles : {e}")
        sys.exit(1)

def init_driver():
    # Init Selenium WebDriver sans sudo, Chrome par défaut, adapter si besoin
    options = webdriver.ChromeOptions()
    options.add_argument("--start-maximized")
    driver = webdriver.Chrome(options=options)
    logger.info("WebDriver initialisé")
    return driver

def find_chat_by_title(driver, title):
    try:
        # Trouve l'élément chat avec titre exact (exemple d'implémentation, adapter au DOM réel)
        chat_elem = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.XPATH, f"//div[contains(@class,'chat-item')]//span[text()='{title}']")))
        logger.info(f"Chat trouvé avec titre : {title}")
        return chat_elem
    except TimeoutException:
        logger.error(f"Chat avec titre '{title}' non trouvé.")
        sys.exit(1)

def send_message_to_chat(driver, chat_elem, message):
    # Cliquer sur le chat pour l'ouvrir
    chat_elem.click()
    logger.info(f"Ouverture chat '{chat_elem.text}'")
    # Trouver la zone de saisie message
    try:
        input_box = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.TAG_NAME, "textarea")))
    except TimeoutException:
        logger.error("Zone de saisie message introuvable.")
        sys.exit(1)
    # Envoyer message
    input_box.clear()
    input_box.send_keys(message)
    input_box.send_keys(Keys.ENTER)
    logger.info("Message envoyé à ChatGPT")

def wait_for_response(driver):
    # Attendre que la réponse apparaisse (basique, adapter selon DOM réel)
    try:
        # Supposons que la réponse soit dans un élément ayant class 'chat-response'
        response_elem = WebDriverWait(driver, 60).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, ".chat-response:last-child")))
        time.sleep(1)  # Petit délai pour fin de chargement
        response_text = response_elem.text
        logger.info("Réponse reçue de ChatGPT")
        return response_text
    except TimeoutException:
        logger.error("Temps d'attente réponse dépassé.")
        sys.exit(1)

def change_chat_title(driver, old_title, new_title):
    try:
        # Cliquer sur le chat pour sélectionner
        chat_elem = find_chat_by_title(driver, old_title)
        chat_elem.click()
        # Cliquer sur le bouton de modification de titre (adapter au DOM)
        edit_button = WebDriverWait(driver, 10).until(
            EC.element_to_be_clickable((By.CSS_SELECTOR, ".edit-chat-title-button")))
        edit_button.click()
        # Trouver champ de saisie du titre et modifier
        title_input = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, ".chat-title-input")))
        title_input.clear()
        title_input.send_keys(new_title)
        title_input.send_keys(Keys.ENTER)
        logger.info(f"Titre du chat modifié de '{old_title}' à '{new_title}'")
    except Exception as e:
        logger.error(f"Erreur modification titre : {e}")
        sys.exit(1)

def main():
    args = parse_args()
    if not args.exec:
        print("Utiliser --exec pour lancer l'exécution du script.")
        sys.exit(0)
    # Chargement règles
    rules_text = load_rules(args.rulesfile)
    # Initialisation driver
    driver = init_driver()
    # URL ChatGPT Web (adapter selon besoin)
    driver.get("https://chat.openai.com/")
    time.sleep(10)  # Attendre login manuel ou adapter si session active
    # Trouver chat cible
    chat_elem = find_chat_by_title(driver, args.chat_title)
    # Construire message complet avec règles
    message = f"Voici les règles de création de titre:\n{rules_text}"
    # Envoyer message
    send_message_to_chat(driver, chat_elem, message)
    # Attendre réponse
    response = wait_for_response(driver)
    # Extraire le titre généré dans la réponse (ici on prend la première ligne ou tout, à adapter)
    new_title = response.strip().split('\n')[0]
    # Modifier titre chat
    change_chat_title(driver, args.chat_title, new_title)
    # Fin propre
    driver.quit()
    print("Actions réalisées :\n1) Chargé règles\n2) Trouvé chat\n3) Envoyé message\n4) Reçu réponse\n5) Modifié titre\n")
    logger.info("Exécution terminée")

if __name__ == "__main__":
    main()
