#!/bin/bash

read -p "Autor: " author
docdate=$(date +%F)
echo "Verwende aktuelles Datum: $docdate"

# Struktur eines Businessplans gemäß Anforderungen
titles=(
  "Executive Summary"
  "Gründungsidee"
  "Produkt und Dienstleistung"
  "Zielgruppe und Marktanalyse"
  "Wettbewerbsanalyse"
  "Marketing und Vertrieb"
  "Rechtsform und Management"
  "Organisation und Personal"
  "Chancen und Risiken"
  "Finanzplanung"
  "Anlagen"
)

# Zielverzeichnis
output_dir="businessplan"
mkdir -p "$output_dir"

resource_dir="$output_dir/resourcen"
mkdir -p "$resource_dir"

# Funktion zur Konvertierung von Titeln in Dateinamen
slugify() {
  echo "$1" | \
  tr '[:upper:]' '[:lower:]' | \
  sed -E 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/ß/ss/g' | \
  sed -E 's/[^a-z0-9]+/-/g' | \
  sed -E 's/^-+|-+$//g'
}

for title in "${titles[@]}"; do
  filename="$(slugify "$title").adoc"
  {
    echo "// tag::main[]"
    echo "== $title"
    echo ""
    echo "// end::main[]"
  } > "$output_dir/$filename"
  mkdir -p "$resource_dir/$(slugify "$title")"
done

index_file="$output_dir/index.adoc"
{
  echo "= Businessplan"
  echo ":author: $author"
  echo ":docdate: $docdate"
  echo ":toc:"
  echo ""
  echo "// Indexdatei für den Businessplan"
  echo ""
  for title in "${titles[@]}"; do
    filename="$(slugify "$title").adoc"
    echo "include::$filename[tag=main]"
  done
} > "$index_file"

echo "Businessplanstruktur erstellt in Verzeichnis: $output_dir"
