# Bash Script — Wi-Fi Analysis with airodump-ng

This script launches a Wi-Fi scan using `airodump-ng` in monitor mode on a given wireless interface, for a defined duration. It automatically generates `.csv` and `.pcap` files in a local subdirectory (`./Sniffing`) with logs in `./Logs`.

## Features

- Automatically switches the network interface to monitor mode
- Scans using `airodump-ng` (`--gpsd`, `--manufacturer`, etc.)
- Results stored in a clean local directory
- Automatic cleanup: restores interface to managed mode
- Handles interruptions (Ctrl+C)
- Assigns generated files to the current user

## Created directories

- `./Sniffing/` : stores `.csv` and `.pcap` files
- `./Logs/` : reserved for future use

## Usage

```bash
./script_name.sh [interface] [duration_in_seconds]
```

- **interface**: name of the Wi-Fi interface (e.g. `wlan1`)
- **duration_in_seconds**: scan duration

### Examples

```bash
./scan-wifi.sh wlan1 30
./scan-wifi.sh
```

## Requirements

- `sudo` access
- `aircrack-ng` installed
- Network interface compatible with monitor mode

## Automatic cleanup

- Restores interface to `managed` mode
- Properly handles Ctrl+C
- Changes ownership of generated files to the current user

## License

This script is released under the **MIT** license.  
Feel free to use, modify, and redistribute it with author attribution.

## Author

Bruno DELNOZ  
Rochefort, Belgium  
Security expert, integration specialist, Wi-Fi sniffing
