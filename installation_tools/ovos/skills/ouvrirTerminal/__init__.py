from ovos_bus_client.skills.ovos import OVOSSkill

class OuvrirTerminalSkill(OVOSSkill):
    def __init__(self):
        super().__init__()

    def initialize(self):
        @self.intent_handler("ouvrirTerminal.intent")
        def handle_intent(_):
            self.log.info("Commande reçue : lancement de gnome-terminal")
            import subprocess
            subprocess.Popen(["gnome-terminal"])
