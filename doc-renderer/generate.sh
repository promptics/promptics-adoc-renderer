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
error() { echo -e "[ERROR] $1"; exit 1; }

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

normalize_and_validate_input_dir() {
  # resolve to absolute path
  if [[ ! "$INPUT_DIR" = /* ]]; then
    INPUT_DIR="$(cd "$(dirname "$0")/$INPUT_DIR" && pwd)"
  fi
  if [[ ! -d "$INPUT_DIR" ]]; then
    error "Input directory does not exist: $INPUT_DIR"
  fi
  $DEBUG && log "Using input directory: $INPUT_DIR"
}

### --- Check required tools ---
check_tools() {
  require_tool ruby "" true
  require_tool gem "" true
  require_tool curl "" true
  require_tool java "" true
  require_tool asciidoctor-pdf "" false
  require_tool asciidoctor "" false
  # Temporarily disabled for testing: require_tool asciidoctor-diagram "" false
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
    local files=($(find "$INPUT_DIR" -maxdepth 1 -name '*.adoc'))
    local count=${#files[@]}
    if [[ "$count" -eq 0 ]]; then
      error "No AsciiDoc files found in: $INPUT_DIR"
    elif [[ "$count" -eq 1 ]]; then
      MAIN="${files[0]}"
    else
      error "Multiple AsciiDoc files found. Please specify the main file with --index."
    fi
  fi
  [[ -f "$MAIN" ]] || error "Main file not found: $MAIN"
  $DEBUG && log "Detected main file: $MAIN"
}

### --- Check fonts referenced in theme ---
verify_fonts() {
  local FONT_DIR="$(cd "$(dirname "$0")/../fonts" && pwd)"
  local missing_fonts=()
  local system_fonts_available=()

  # Check what fonts the theme requires (both .ttf and .ttc)
  grep -Eo '[^"]+\.tt[cf]' "$THEME_FILE" | while read -r fontfile; do
    local fontname=$(basename "$fontfile" .ttf | basename "$fontfile" .ttc)
    local base_font=$(echo "$fontname" | cut -d- -f1)

    if [[ ! -f "$FONT_DIR/$fontfile" ]]; then
      missing_fonts+=("$fontfile")

      # Enhanced system font detection using fc-list
      if fc-list | grep -i "$base_font" > /dev/null; then
        if [[ ! " ${system_fonts_available[*]} " =~ " ${base_font} " ]]; then
          system_fonts_available+=("$base_font")
        fi
        warn "Font '$fontfile' not found locally, but '$base_font' exists system-wide."
      else
        warn "Font missing: $fontfile"
      fi
    elif [[ ! -s "$FONT_DIR/$fontfile" ]]; then
      warn "Font file '$fontfile' exists but is empty (0 bytes)"
    else
      $DEBUG && log "Font available: $fontfile"
    fi
  done

  if [[ ${#missing_fonts[@]} -gt 0 ]]; then
    warn "Missing fonts may cause PDF generation to fail."
    warn "To fix: Install Inter fonts or update theme.yml to use available fonts."

    if [[ ${#system_fonts_available[@]} -gt 0 ]]; then
      warn "System fonts detected: ${system_fonts_available[*]}"
      warn "System fonts will be automatically used as fallback during PDF generation"
      warn "Available system font directories:"
      for font_dir in "/System/Library/Fonts" "/System/Library/Fonts/Supplemental" "/Library/Fonts" "$HOME/Library/Fonts"; do
        if [[ -d "$font_dir" ]]; then
          local font_count=$(find "$font_dir" -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" 2>/dev/null | wc -l)
          warn "  $font_dir ($font_count fonts)"
          if [[ -n "$(find "$font_dir" -name "*inter*" -o -name "*Inter*" 2>/dev/null)" ]]; then
            warn "    → Contains Inter font family"
          fi
        fi
      done
    fi

    warn "Available fonts in ../fonts/: $(ls "$FONT_DIR"/*.{ttf,ttc} 2>/dev/null | xargs basename -a 2>/dev/null || echo 'none')"
  fi
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

  # Check if we need to use system fonts
  local system_font_dirs=""
  if [[ "$FORMAT" == "pdf" ]] && command -v fc-list > /dev/null; then
    local fonts_missing=false

    # Check if required fonts are missing from local directory
    grep -Eo '[^"]+\.tt[cf]' "$THEME_FILE" | while read -r fontfile; do
      if [[ ! -f "../fonts/$fontfile" ]] || [[ ! -s "../fonts/$fontfile" ]]; then
        fonts_missing=true
        break
      fi
    done

    # Add system font directories if fonts are missing
    if [[ "$fonts_missing" == "true" ]]; then
      for font_dir in "/System/Library/Fonts" "/System/Library/Fonts/Supplemental" "/Library/Fonts" "$HOME/Library/Fonts"; do
        if [[ -d "$font_dir" ]]; then
          system_font_dirs="$system_font_dirs -a pdf-fontsdir=\"$font_dir\""
        fi
      done

      if [[ -n "$system_font_dirs" ]]; then
        log "Using system fonts as fallback"
      fi
    fi
  fi

  if [[ "$FORMAT" == "pdf" ]]; then
    log "Generating PDF ..."
    # Temporarily disable asciidoctor-diagram for testing
    asciidoctor-pdf \
      -a pdf-theme="$THEME_FILE" \
      -a pdf-themesdir="." \
      -a pdf-fontsdir="../fonts" $system_font_dirs \
      "$MAIN" -o "$out"
    local exit_code=$?
  else
    log "Generating HTML ..."
    asciidoctor "$MAIN" -o "$out"
    local exit_code=$?
  fi

  # Verify output was created successfully
  if [[ $exit_code -eq 0 ]] && [[ -f "$out" ]] && [[ -s "$out" ]]; then
    log "Output written to: $out"
  else
    if [[ $exit_code -ne 0 ]]; then
      error "Failed to generate $FORMAT (exit code: $exit_code). Check for missing fonts or other dependencies."
    elif [[ ! -f "$out" ]]; then
      error "Output file was not created: $out"
    elif [[ ! -s "$out" ]]; then
      error "Output file is empty: $out"
    else
      error "Output generation failed for unknown reason"
    fi
  fi
}

### --- Main entry point ---
main() {
  parse_args "$@"
  normalize_and_validate_input_dir
  check_tools
  download_plantuml
  detect_main_adoc
  [[ "$DRY_RUN" == "true" ]] && log "Dry-run complete." && exit 0
  verify_fonts
  render_diagrams
  run_linter
  check_images
  generate_output
  log "Rendering complete."
}


main "$@"