#!/bin/bash

# Skript bricht bei jedem Fehler ab, um unerwartete Zustände zu vermeiden
set -e

DEFAULT_DIR="$(cd "$(dirname "$0")/../docs" && pwd)"
INPUT_DIR="${1:-$DEFAULT_DIR}"

slugify() {
  echo "$1" | \
  tr '[:upper:]' '[:lower:]' | \
  sed -E 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/ß/ss/g' | \
  sed -E 's/[^a-z0-9]+/-/g' | \
  sed -E 's/^-+|-+$//g'
}

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

THEME_DIR="$INPUT_DIR"
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

# --- Prüfe promptics-theme.yml auf Font-Referenzen, lade sie ggf. herunter ---
CUSTOM_THEME="$THEME_DIR/promptics-theme.yml"
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

echo "🛠 Suche nach Mermaid-Diagrammen..."
find "$INPUT_DIR" -type f -name '*.mmd' | while read -r mmd_file; do
  png_file="${mmd_file%.mmd}.png"
  echo "Render: $mmd_file → $png_file"
  mmdc -i "$mmd_file" -o "$png_file"
done

echo "🛠 Suche nach PlantUML-Dateien..."
find "$INPUT_DIR" -type f -name 'plant.yml' | while read -r yml_file; do
  echo "Render PlantUML: $yml_file"
  java -jar "$PLANTUML_JAR" -tpng "$yml_file"
done

echo "Erzeuge PDF aus $INPUT_DIR/index.adoc ..."
asciidoctor-pdf -r asciidoctor-diagram -a pdf-theme=promptics-theme.yml -a pdf-themesdir="." -a pdf-fontsdir="$FONT_DIR" "$INPUT_DIR/index.adoc" -o "${INPUT_DIR}.pdf"
echo "PDF wurde erstellt: ${INPUT_DIR}.pdf"