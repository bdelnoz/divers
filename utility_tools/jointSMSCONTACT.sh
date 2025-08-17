#!/bin/bash

CONTACTS_CSV="export_ALL_CONTACTS.csv"
SMS_CSV="export_ALL_SMS.csv"
OUTPUT_CSV="export_ALL_SMS_with_contacts.csv"

if [[ ! -f "$CONTACTS_CSV" || ! -f "$SMS_CSV" ]]; then
  echo "Erreur : Fichiers $CONTACTS_CSV ou $SMS_CSV introuvables."
  exit 1
fi

echo "Fusion SMS + Contacts en cours..."

awk -F, '
  BEGIN { OFS="," }

  function clean_num(num) {
    gsub(/"/, "", num)
    gsub(/ /, "", num)
    if (num ~ /^0[1-9]/) { return "+32" substr(num,2) }
    else { return num }
  }

  NR==FNR && FNR>1 {
    num = clean_num($3)
    first[num] = $1
    last[num] = $2
    info[num] = $3
    contact_name[num] = $1 " " $2
    next
  }

  FNR==1 {
    print "date","direction","first_name","last_name","contact_info","contact_name","phone_number","message"
    next
  }

  {
    num_sms = $3
    cnum = clean_num(num_sms)
    fn = (cnum in first) ? first[cnum] : ""
    ln = (cnum in last) ? last[cnum] : ""
    ci = (cnum in info) ? info[cnum] : ""
    cn = (cnum in contact_name) ? contact_name[cnum] : ""
    print $1,$2,fn,ln,ci,cn,num_sms,$4
  }
' "$CONTACTS_CSV" "$SMS_CSV" > "$OUTPUT_CSV"

echo "✅ Fusion terminée : $OUTPUT_CSV"
libreoffice "$OUTPUT_CSV" &

