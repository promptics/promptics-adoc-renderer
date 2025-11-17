#!/bin/bash

### --- Configurable parameters with defaults ---
INPUT_DIR="../docs"
THEME_FILE="theme.yml"
OUTPUT_FILE=""
MAIN_FILE=""
FORMAT="pdf"
DRY_RUN=false
DEBUG=false

# Derived paths
FONTS_DIR="$(cd "$(dirname "$0")/../fonts" && pwd)"
MISSING_TOOLS=()
INSTALLABLE_TOOLS=()
PACKAGE_MANAGER=""

### --- Logging ---
log()   { echo -e "[INFO] $1"; }
warn()  { echo -e "\033[33m[WARN]\033[0m $1"; }
error() { echo -e "[ERROR] $1"; exit 1; }

### --- Detect package manager ---
detect_package_manager() {
  if command -v brew > /dev/null; then
    PACKAGE_MANAGER="brew"
    log "Detected Homebrew package manager"
  elif command -v apt > /dev/null; then
    PACKAGE_MANAGER="apt"
    log "Detected apt package manager"
  elif command -v yum > /dev/null; then
    PACKAGE_MANAGER="yum"
    log "Detected yum package manager"
  elif command -v pacman > /dev/null; then
    PACKAGE_MANAGER="pacman"
    log "Detected pacman package manager"
  else
    warn "No supported package manager found (brew, apt, yum, pacman)"
    PACKAGE_MANAGER="manual"
  fi
}

### --- Installation commands ---
get_install_command() {
  local tool="$1"
  case "$tool" in
    "ruby")
      case "$PACKAGE_MANAGER" in
        "brew") echo "brew install ruby" ;;
        "apt") echo "sudo apt update && sudo apt install ruby-full" ;;
        "yum") echo "sudo yum install ruby" ;;
        "pacman") echo "sudo pacman -S ruby" ;;
        *) echo "Install Ruby from https://ruby-lang.org" ;;
      esac ;;
    "java")
      case "$PACKAGE_MANAGER" in
        "brew") echo "brew install openjdk" ;;
        "apt") echo "sudo apt update && sudo apt install default-jre" ;;
        "yum") echo "sudo yum install java-11-openjdk" ;;
        "pacman") echo "sudo pacman -S jre-openjdk" ;;
        *) echo "Install Java from https://adoptium.net" ;;
      esac ;;
    "asciidoctor")
      echo "gem install asciidoctor" ;;
    "asciidoctor-pdf")
      echo "gem install asciidoctor-pdf" ;;
    "asciidoctor-diagram")
      echo "gem install asciidoctor-diagram" ;;
    "mmdc")
      echo "npm install -g @mermaid-js/mermaid-cli" ;;
    "asciidoctor-lint")
      echo "gem install asciidoctor-lint" ;;
    *)
      echo "Manual installation required for $tool" ;;
  esac
}

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
      warn "Required tool '$tool' (or fallback '$fallback') not found."
      MISSING_TOOLS+=("$tool")
      INSTALLABLE_TOOLS+=("$tool")
      return 1
    else
      warn "Optional tool '$tool' not found. Some functionality may be limited."
      return 1
    fi
  fi
}

### --- Interactive installation ---
offer_installation() {
  if [[ ${#MISSING_TOOLS[@]} -eq 0 ]]; then
    return 0
  fi

  echo ""
  echo "=== Missing Required Tools ==="
  for i in "${!MISSING_TOOLS[@]}"; do
    tool="${MISSING_TOOLS[$i]}"
    echo "  $((i+1)). $tool"
  done

  echo ""
  echo "These tools are required for the script to work properly."
  echo "Would you like me to attempt to install them? (y/n)"
  read -r response

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    error "Cannot continue without required tools. Please install them manually or run with --help for more information."
  fi

  echo ""
  echo "=== Installation Commands ==="
  echo "The following commands will be executed:"
  echo ""

  for tool in "${MISSING_TOOLS[@]}"; do
    cmd=$(get_install_command "$tool")
    echo "  $cmd"
  done

  echo ""
  echo "Proceed with installation? (y/n)"
  read -r confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    error "Installation cancelled. Please install tools manually."
  fi

  echo ""
  log "Installing missing tools..."
  for tool in "${MISSING_TOOLS[@]}"; do
    cmd=$(get_install_command "$tool")
    log "Executing: $cmd"
    if eval "$cmd"; then
      log "Successfully installed $tool"
    else
      error "Failed to install $tool. Please install it manually."
    fi
  done

  log "Installation complete. You may need to restart your terminal or source your shell profile."
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
        echo "Usage: $0 [-i dir] [-t theme.yml] [--format pdf|html] [--dry-run]"
        echo ""
        echo "This script converts AsciiDoc files to PDF or HTML with diagram support."
        echo ""
        echo "Required tools will be automatically detected and installation will be offered."
        echo ""
        echo "Options:"
        echo "  -i, --input <dir>    Input directory (default: ../docs)"
        echo "  -t, --theme <file>   Theme file (default: theme.yml)"
        echo "  -o, --output <file>  Output file path (default: <main_file>.<format> in current directory)"
        echo "  -x, --index <file>   Main AsciiDoc file"
        echo "  --format <format>    Output format: pdf or html (default: pdf)"
        echo "  --dry-run           Check setup without generating output"
        echo "  --debug             Enable verbose output"
        echo "  -h, --help          Show this help message"
        exit 0 ;;
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
  detect_package_manager

  # Check for required tools
  require_tool ruby "" true
  require_tool gem "" true
  require_tool curl "" true
  require_tool java "" true

  # Check for Ruby gems (these require tool checking first)
  if command -v ruby > /dev/null && command -v gem > /dev/null; then
    require_tool asciidoctor "" true
    require_tool asciidoctor-pdf "" true
    # Note: asciidoctor-diagram is loaded as a Ruby library, not a command
    if ! ruby -c -e "require 'asciidoctor-diagram'" 2>/dev/null; then
      warn "Required gem 'asciidoctor-diagram' not found."
      MISSING_TOOLS+=("asciidoctor-diagram")
      INSTALLABLE_TOOLS+=("asciidoctor-diagram")
    fi
  fi

  # Check for other optional tools
  require_tool mmdc "" false
  require_tool fc-list "" false
  require_tool asciidoctor-lint "" false

  # Offer installation if tools are missing
  offer_installation
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
  log "Verifying fonts..."
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  local theme_file="$script_dir/$THEME_FILE"

  if [ ! -f "$theme_file" ]; then
    warn "Theme file not found: $theme_file"
    return 1
  fi

  # Get configured font family from theme
  local font_family=$(grep -A 1 '^font:' "$theme_file" | grep 'family:' | awk '{print $2}' | tr -d "'\"")
  [ -z "$font_family" ] && font_family="Inter"  # Default font

  # Check if font is available in system
  local font_available=false

  # Check system fonts first
  if command -v fc-list >/dev/null; then
    if fc-list | grep -qi "^/.*$font_family" 2>/dev/null; then
      log "Found system font: $font_family"
      font_available=true
    fi
  fi

  # If not found in system, check local fonts directory
  if [ "$font_available" = false ] && [ -d "$FONTS_DIR" ]; then
    if find "$FONTS_DIR" -type f \( -name "${font_family,,}*.ttf" -o -name "${font_family,,}*.otf" -o -name "${font_family}*.ttf" -o -name "${font_family}*.otf" \) | grep -q .; then
      log "Found font in local directory: $font_family"
      font_available=true
    fi
  fi

  # If font not found anywhere, use Arial as fallback
  if [ "$font_available" = false ]; then
    warn "Font '$font_family' not found in system or local directory. Falling back to Arial."

    # Update theme file to use Arial
    if grep -q '^font:' "$theme_file"; then
      sed -i '' -e "s/^  family:.*/  family: Arial/" "$theme_file"
      sed -i '' -e "s/^    Inter:/    Arial:/" "$theme_file"
      log "Updated theme to use Arial as fallback font"
    fi

    # Check if Arial is available
    if ! fc-list | grep -qi arial 2>/dev/null; then
      warn "Arial font not found. The PDF may have font rendering issues."
    fi
  fi

  # Update font catalog in theme to use actual font files found in system
  log "Updating theme font catalog with system font names..."
  local theme_updated=false

  # Update Inter fonts if available
  if fc-list | grep -qi "Inter" 2>/dev/null; then
    local inter_files=$(fc-list | grep -i "Inter" | head -1 | cut -d: -f1)
    if [[ -n "$inter_files" ]]; then
      log "Found Inter font: $inter_files"
      # Update theme to use the actual Inter font file
      if [[ "$inter_files" == *.ttc ]]; then
        sed -i '' -e "s|normal: Inter[^.]*\.ttf|normal: $(basename "$inter_files")|g" "$theme_file"
        sed -i '' -e "s|bold: Inter[^.]*\.ttf|bold: $(basename "$inter_files")|g" "$theme_file"
        sed -i '' -e "s|italic: Inter[^.]*\.ttf|italic: $(basename "$inter_files")|g" "$theme_file"
        sed -i '' -e "s|bold_italic: Inter[^.]*\.ttf|bold_italic: $(basename "$inter_files")|g" "$theme_file"
        theme_updated=true
      fi
    fi
  fi

  # Update Arial fonts if available
  if fc-list | grep -qi "Arial" 2>/dev/null; then
    local arial_normal=$(fc-list | grep -i "Arial.*Regular" | head -1 | cut -d: -f1)
    local arial_bold=$(fc-list | grep -i "Arial.*Bold" | head -1 | cut -d: -f1)
    local arial_italic=$(fc-list | grep -i "Arial.*Italic" | head -1 | cut -d: -f1)
    local arial_bold_italic=$(fc-list | grep -i "Arial.*Bold.*Italic" | head -1 | cut -d: -f1)

    if [[ -n "$arial_normal" ]]; then
      sed -i '' -e "s|normal: Arial[^.]*\.ttf|normal: $(basename "$arial_normal")|g" "$theme_file"
      theme_updated=true
    fi
    if [[ -n "$arial_bold" ]]; then
      sed -i '' -e "s|bold: Arial[^.]*\.ttf|bold: $(basename "$arial_bold")|g" "$theme_file"
      theme_updated=true
    fi
    if [[ -n "$arial_italic" ]]; then
      sed -i '' -e "s|italic: Arial[^.]*\.ttf|italic: $(basename "$arial_italic")|g" "$theme_file"
      theme_updated=true
    fi
    if [[ -n "$arial_bold_italic" ]]; then
      sed -i '' -e "s|bold_italic: Arial[^.]*\.ttf|bold_italic: $(basename "$arial_bold_italic")|g" "$theme_file"
      theme_updated=true
    fi
  fi

  if [ "$theme_updated" = true ]; then
    log "Updated theme.yml with correct system font file names"
  fi

  # Verify that the fonts referenced in the theme actually exist in system
  local font_issues=0
  grep -A 10 "catalog:" "$theme_file" | grep -E "(normal|bold|italic|bold_italic):" | while read -r line; do
    font_file=$(echo "$line" | awk '{print $2}' | tr -d '"')
    if [[ -n "$font_file" && "$font_file" != *.ttc && "$font_file" != *.ttf ]]; then
      continue
    fi

    # Check if font exists in system directories
    font_found=false
    for font_dir in "/System/Library/Fonts" "/System/Library/Fonts/Supplemental" "/Library/Fonts" "$HOME/Library/Fonts"; do
      if [[ -f "$font_dir/$font_file" ]]; then
        font_found=true
        break
      fi
    done

    if [ "$font_found" = false ]; then
      warn "Font file not found in system: $font_file"
      ((font_issues++))
    fi
  done

  if [ "$font_issues" -gt 0 ]; then
    warn "Theme references $font_issues font files that are not available in the system."
    warn "PDF generation may fail. Consider updating the theme.yml with available fonts."
  fi
}
### --- Render embedded diagrams ---
render_diagrams() {
  log "Rendering diagrams..."
  local input_dirname="$(dirname "$MAIN")"

  # Change to input directory so relative paths work correctly
  (cd "$input_dirname" && find . -name '*.mmd' | while read -r f; do
    out="${f%.mmd}.png"
    log "Rendering Mermaid: $f → $out"
    mmdc -i "$f" -o "$out"
  done)

  (cd "$input_dirname" && find . -name '*.puml' -o -name '*.plantuml' -o -name 'plant.yml' | while read -r f; do
    log "Rendering PlantUML: $f"
    java -jar "$PLANTUML_JAR" -tpng "$f"
  done)
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
  log "Checking image references..."
  grep -Eo 'image::[^[]+' "$MAIN" | cut -d: -f2- | while read -r path; do
    # Convert relative paths to absolute paths relative to input directory
    if [[ "$path" != /* ]]; then
      local input_dirname="$(dirname "$MAIN")"
      path="$input_dirname/$path"
    fi

    if [[ ! -f "$path" ]]; then
      warn "Image not found: $path"
    else
      $DEBUG && log "Found image: $path"
    fi
  done
}

### --- Generate output (PDF or HTML) ---
generate_output() {
  local base="$(basename "$MAIN" .adoc)"
  # Output to current working directory (where script was called from)
  local out="${OUTPUT_FILE:-$base.$FORMAT}"

  if [[ "$FORMAT" == "pdf" ]]; then
    log "Generating PDF ..."

    # Change to input directory and generate PDF
    # The output will be in the current working directory
    if (cd "$(dirname "$MAIN")" && asciidoctor-pdf -r asciidoctor-diagram \
      -o "../doc-renderer/$out" \
      "$(basename "$MAIN")") 2>/dev/null; then

      log "PDF generated successfully: $out"
    else
      warn "PDF generation failed. Trying with system fonts..."

      # Try with system font directories
      local system_font_dirs=""
      for font_dir in "/System/Library/Fonts" "/System/Library/Fonts/Supplemental" "/Library/Fonts" "$HOME/Library/Fonts"; do
        if [[ -d "$font_dir" ]]; then
          system_font_dirs="$system_font_dirs -a pdf-fontsdir=\"$font_dir\""
        fi
      done

      if (cd "$(dirname "$MAIN")" && asciidoctor-pdf -r asciidoctor-diagram \
        $system_font_dirs \
        -o "../doc-renderer/$out" \
        "$(basename "$MAIN")") 2>/dev/null; then

        log "PDF generated successfully with system fonts: $out"
      else
        error "Failed to generate PDF. Check dependencies and font availability."
      fi
    fi
  else
    log "Generating HTML ..."
    # Change to input directory so relative image paths work correctly
    (cd "$(dirname "$MAIN")" && asciidoctor -r asciidoctor-diagram \
      -o "../doc-renderer/$out" \
      "$(basename "$MAIN")")
  fi
  log "Output written to: $out"
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
