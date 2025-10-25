#!/bin/bash
set -e

### --- Configurable parameters with defaults ---
INPUT_DIR="../docs"
THEME_FILE="theme.yml"
OUTPUT_FILE=""
MAIN_FILE=""
FORMAT="pdf"
DRY_RUN=false
DEBUG=false

### --- Logging ---
log()   { echo -e "[INFO] $1"; }
warn()  { echo -e "\033[33m[WARN]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

### --- Tool presence check ---
require_tool() {
  local tool="$1"
  local fallback="$2"
  local required="$3"
  if command -v "$tool" > /dev/null; then
    $DEBUG && log "Tool available: $tool"
    return 0
  elif [ -n "$fallback" ] && command -v "$fallback" > /dev/null; then
    warn "Tool '$tool' not found, using fallback '$fallback'"
    return 0
  else
    if [[ "$required" == "true" ]]; then
      error "Required tool '$tool' (or fallback '$fallback') not found."
    else
      warn "Optional tool '$tool' not found. Some functionality may be limited."
      return 1
    fi
  fi
}

### --- Parse CLI arguments ---
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -i|--input)  INPUT_DIR="$2"; shift ;;
      -t|--theme)  THEME_FILE="$2"; shift ;;
      -o|--output) OUTPUT_FILE="$2"; shift ;;
      -x|--index)  MAIN_FILE="$2"; shift ;;
      --format)    FORMAT="$2"; shift ;;
      --dry-run)   DRY_RUN=true ;;
      --debug)     DEBUG=true ;;
      -h|--help)
        echo "Usage: $0 [-i dir] [-t theme.yml] [--format pdf|html] [--dry-run]"; exit 0 ;;
      *) error "Unknown parameter: $1" ;;
    esac
    shift
  done
}

### --- Check required tools ---
check_tools() {
  require_tool ruby "" true
  require_tool gem "" true
  require_tool curl "" true
  require_tool java "" true
  require_tool asciidoctor-pdf "" false
  require_tool asciidoctor "" false
  require_tool asciidoctor-diagram "" false
  require_tool mmdc "" false
  require_tool fc-list "" false
  require_tool asciidoctor-lint "" false
}

### --- Download PlantUML JAR if needed ---
download_plantuml() {
  PLANTUML_JAR="./plantuml.jar"
  export PLANTUML_JAR
  if [[ ! -f "$PLANTUML_JAR" ]]; then
    log "Downloading PlantUML jar ..."
    curl -L -o "$PLANTUML_JAR" https://github.com/plantuml/plantuml/releases/latest/download/plantuml.jar || {
      error "Failed to download PlantUML jar"
    }
  else
    $DEBUG && log "PlantUML jar already exists."
  fi
}

### --- Determine main .adoc file ---
detect_main_adoc() {
  if [[ -n "$MAIN_FILE" ]]; then
    MAIN="$INPUT_DIR/$MAIN_FILE"
  elif [[ -f "$INPUT_DIR/index.adoc" ]]; then
    MAIN="$INPUT_DIR/index.adoc"
  else
    local count
    count=$(find "$INPUT_DIR" -maxdepth 1 -name '*.adoc' | wc -l)
    if [[ "$count" -eq 1 ]]; then
      MAIN=$(find "$INPUT_DIR" -maxdepth 1 -name '*.adoc')
    else
      error "Cannot determine main AsciiDoc file. Please specify using --index."
    fi
  fi
  [[ -f "$MAIN" ]] || error "Main file not found: $MAIN"
  $DEBUG && log "Detected main file: $MAIN"
}

### --- Check fonts referenced in theme ---
verify_fonts() {
  local FONT_DIR="$(cd "$(dirname "$0")/../fonts" && pwd)"
  grep -Eo '[^"]+\.ttf' "$THEME_FILE" | while read -r fontfile; do
    if [[ ! -f "$FONT_DIR/$fontfile" ]]; then
      if fc-list | grep -i "$(basename "$fontfile")" > /dev/null; then
        warn "Font '$fontfile' not found locally, but exists system-wide."
      else
        warn "Font missing: $fontfile"
      fi
    fi
  done
}

### --- Render embedded diagrams ---
render_diagrams() {
  find "$INPUT_DIR" -name '*.mmd' | while read -r f; do
    out="${f%.mmd}.png"
    log "Rendering Mermaid: $f → $out"
    mmdc -i "$f" -o "$out"
  done
  find "$INPUT_DIR" -name '*.puml' -o -name '*.plantuml' -o -name 'plant.yml' | while read -r f; do
    log "Rendering PlantUML: $f"
    java -jar "$PLANTUML_JAR" -tpng "$f"
  done
}

### --- Run linter if available ---
run_linter() {
  if command -v asciidoctor-lint > /dev/null; then
    log "Linting $MAIN ..."
    asciidoctor-lint "$MAIN" || warn "Linter reported warnings."
  fi
}

### --- Check for broken image references ---
check_images() {
  grep -Eo 'image::[^[]+' "$MAIN" | cut -d: -f2- | while read -r path; do
    if [[ ! -f "$INPUT_DIR/$path" ]]; then
      warn "Image not found: $path"
    fi
  done
}

### --- Generate output (PDF or HTML) ---
generate_output() {
  local base="$(basename "$MAIN" .adoc)"
  local out="${OUTPUT_FILE:-output/$base.$FORMAT}"
  mkdir -p "$(dirname "$out")"

  if [[ "$FORMAT" == "pdf" ]]; then
    log "Generating PDF ..."
    asciidoctor-pdf -r asciidoctor-diagram \
      -a pdf-theme="$THEME_FILE" \
      -a pdf-themesdir="." \
      -a pdf-fontsdir="../fonts" \
      "$MAIN" -o "$out"
  else
    log "Generating HTML ..."
    asciidoctor -r asciidoctor-diagram "$MAIN" -o "$out"
  fi
  log "Output written to: $out"
}

### --- Main entry point ---
main() {
  parse_args "$@"
  check_tools
  download_plantuml
  detect_main_adoc
  [[ "$DRY_RUN" == "true" ]] && log "Dry-run complete." && exit 0
  verify_fonts
  render_diagrams
  run_linter
  check_images
  generate_output
}

main "$@"