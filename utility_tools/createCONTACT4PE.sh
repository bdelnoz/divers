#!/bin/bash

CONTACTS_CSV="export_ALL_CONTACTS.csv"
OUTPUT_CSV="ProtonMail_Contacts.csv"
OUTPUT_VCF_V4="ProtonMail_Contacts_v4.vcf"

if [[ ! -f "$CONTACTS_CSV" ]]; then
  echo "Erreur : Fichier $CONTACTS_CSV introuvable."
  exit 1
fi

VERSION="$1"  # Optionnel, par défaut génère CSV + VCF v4

generate_csv() {
  echo "Conversion en CSV ProtonMail..."
  awk -F, '
    BEGIN {
      OFS = ","
      print "Name,Email,Phone Number,Address,Notes,Company"
    }
    NR > 1 {
      gsub(/"/, "", $0)
      for (i=1; i<=NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
      name=$1
      email=$2
      phone=$3
      if (email ~ /@/) e=email; else e=""
      if (phone ~ /@/) { e=phone; phone="" }
      gsub(/[[:space:]]/, "", phone)
      print name,e,phone,"","",""
    }
  ' "$CONTACTS_CSV" > "$OUTPUT_CSV"
  echo "✅ CSV généré : $OUTPUT_CSV"
}

generate_vcf_v4() {
  echo "Conversion en VCF version 4.0..."
  rm -f "$OUTPUT_VCF_V4"
  tail -n +2 "$CONTACTS_CSV" | while IFS=, read -r name email phone _
  do
    name=$(echo "$name" | sed 's/^ *//;s/ *$//;s/"//g')
    email=$(echo "$email" | sed 's/^ *//;s/ *$//;s/"//g')
    phone=$(echo "$phone" | sed 's/^ *//;s/ *$//;s/"//g')

    # Si nom vide, remplacer par placeholder
    if [[ -z "$name" ]]; then
      name="Nom Inconnu"
    fi

    if [[ "$email" != *"@"* ]]; then email=""; fi
    if [[ "$phone" == *"@"* ]]; then email="$phone"; phone=""; fi
    phone=$(echo "$phone" | tr -d '[:space:]')

    {
      echo "BEGIN:VCARD"
      echo "VERSION:4.0"
      echo "FN:$name"
      echo "N:$name"
      [[ -n "$email" ]] && echo "EMAIL;TYPE=INTERNET:$email"
      [[ -n "$phone" ]] && echo "TEL;VALUE=uri;TYPE=cell:tel:$phone"
      echo "END:VCARD"
    } >> "$OUTPUT_VCF_V4"
  done
  echo "✅ VCF v4 généré : $OUTPUT_VCF_V4"
}

case "$VERSION" in
  csv)
    generate_csv
    ;;
  vcf)
    generate_vcf_v4
    ;;
  "" )
    generate_csv
    generate_vcf_v4
    ;;
  *)
    echo "Usage : $0 [csv|vcf]"
    exit 1
    ;;
esac
