#!/bin/bash

# Skript bricht bei jedem Fehler ab, um unerwartete Zustände zu vermeiden
set -e

if [ ! -d "businessplan" ]; then
  read -p "Autor: " author
  docdate=$(date +%F)
  echo "Verwende aktuelles Datum: $docdate"

  output_dir="businessplan"
  mkdir -p "$output_dir"

  resource_dir="$output_dir/resourcen"
  mkdir -p "$resource_dir"

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
    echo "[.pagebreak]"
    echo "<<<"
    echo ""
    echo "// Indexdatei für den Businessplan"
    echo ""
    for title in "${titles[@]}"; do
      filename="$(slugify "$title").adoc"
      echo "include::$filename[tag=main]"
    done
  } > "$index_file"

  echo "Businessplanstruktur erstellt in Verzeichnis: $output_dir"
fi

docdate=$(date +%F)
echo "Verwende aktuelles Datum: $docdate"

# --- Prüfe und installiere Ruby, Bundler und benötigte Gems ---

# Prüfe ob Ruby installiert ist
if ! command -v ruby &> /dev/null; then
  echo "Ruby ist nicht installiert. Bitte installiere Ruby manuell."
  exit 1
fi

# Prüfe ob gem installiert ist
if ! command -v gem &> /dev/null; then
  echo "RubyGems (gem) ist nicht installiert. Bitte prüfe deine Ruby-Installation."
  exit 1
fi

# Prüfe ob bundler installiert ist
if ! gem list bundler -i > /dev/null; then
  echo "Bundler wird installiert ..."
  gem install bundler
fi

# Installiere erforderliche Gems nur wenn nicht vorhanden
install_gem_if_missing() {
  local gem_name=$1
  if ! gem list "$gem_name" -i > /dev/null; then
    echo "Installiere Ruby Gem: $gem_name"
    gem install "$gem_name"
  else
    echo "$gem_name ist bereits installiert."
  fi
}

install_gem_if_missing asciidoctor-pdf
install_gem_if_missing asciidoctor-diagram
install_gem_if_missing rouge

THEME_DIR="businessplan"
FONT_DIR="$THEME_DIR/fonts"
mkdir -p "$FONT_DIR"

download_font() {
  local url=$1
  local dest=$2
  if [ ! -f "$dest" ]; then
    echo "Lade Schriftart $dest ..."
    curl -L -o "$dest" "$url"
  fi
}

# --- Prüfe custom-theme.yml auf Font-Referenzen, lade sie ggf. herunter ---
CUSTOM_THEME="$THEME_DIR/custom-theme.yml"
FONT_DIR="$THEME_DIR/fonts"
mkdir -p "$FONT_DIR"

if [ -f "$CUSTOM_THEME" ]; then
  grep -E '\.ttf' "$CUSTOM_THEME" | grep -o '[^/ ]*\.ttf' | sort -u | while read -r fontfile; do
    case "$fontfile" in
      SourceSerifPro-*.ttf)
        url="https://github.com/adobe-fonts/source-serif-pro/raw/release/TTF/$fontfile"
        ;;
      NotoSans-*.ttf)
        url="https://github.com/notofonts/noto-fonts/raw/main/hinted/ttf/NotoSans/$fontfile"
        ;;
      *)
        echo "ERROR: URL for $fontfile not defined."
        exit 1
        ;;
    esac

    dest="$FONT_DIR/$fontfile"
    if curl --output /dev/null --silent --head --fail "$url"; then
      if [ ! -f "$dest" ]; then
        echo "Downloading font $fontfile ..."
        curl -L -o "$dest" "$url" || { echo "ERROR: Failed to download $fontfile"; exit 1; }
      fi
    else
      echo "ERROR: Font $fontfile not found at $url."
      exit 1
    fi
  done
fi

# --- PlantUML Integration ---
export PLANTUML_JAR=$(pwd)/plantuml.jar
if [ ! -f "$PLANTUML_JAR" ]; then
  echo "Lade plantuml.jar ..."
  curl -L -o "$PLANTUML_JAR" https://github.com/plantuml/plantuml/releases/latest/download/plantuml.jar
fi

# Generate Gantt chart PNG from Mermaid
echo "🛠 Generating Gantt chart..."
mmdc -i businessplan/gantt.mmd -o businessplan/gantt.png

# Erzeuge das finale PDF aus der AsciiDoc-Datei mit benutzerdefiniertem Theme und Schriftarten
echo "Erzeuge PDF aus $THEME_DIR/index.adoc ..."
asciidoctor-pdf -r asciidoctor-diagram -a pdf-theme=custom-theme.yml -a pdf-themesdir="." -a pdf-fontsdir="$FONT_DIR" "$THEME_DIR/index.adoc" -o "Businessplan.pdf"
echo "PDF wurde erstellt: Businessplan.pdf"