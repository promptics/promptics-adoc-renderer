#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

### --- Configurable parameters with defaults ---
INPUT_DIR="../docs"
THEME_FILE="promptics-theme.yml"
OUTPUT_FILE=""
MAIN_FILE=""
FORMAT="pdf"
DRY_RUN=false
DEBUG=false

# Derived paths
FONTS_DIR="$SCRIPT_DIR/fonts"
FONT_RELEASE_URL=""
FONT_ARCHIVE_NAME=""
FONT_ARCHIVE_PATH=""
DEFAULT_REQUIRED_FONTS=()
declare -a REQUIRED_FONTS=("${DEFAULT_REQUIRED_FONTS[@]}")
declare -a FONT_ARCHIVE_ENTRIES=()
declare -a FONT_DIRECT_URLS=()
declare -a FONT_DIRECT_URL_MAP=()
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
    INPUT_DIR="$(cd "$SCRIPT_DIR/$INPUT_DIR" && pwd)"
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

map_font_to_archive_entry() {
  local font_file="$1"
  case "$font_file" in
    InterVariable.ttf|InterVariable-Italic.ttf)
      echo "$font_file"
      ;;
    Inter-*.ttf|InterDisplay-*.ttf)
      echo "extras/ttf/$font_file"
      ;;
    *)
      echo ""
      ;;
  esac
}

map_font_to_direct_url() {
  local font_file="$1"
  case "$font_file" in
    RedHatDisplay-*.ttf)
      echo "https://raw.githubusercontent.com/RedHatOfficial/RedHatFont/master/fonts/Proportional/RedHatDisplay/ttf/$font_file"
      ;;
    *)
      echo ""
      ;;
  esac
}

load_theme_fonts() {
  local theme_file="$1"
  local fonts_output=""

  if command -v ruby > /dev/null; then
    fonts_output=$(ruby -ryaml - "$theme_file" <<'RUBY' 2>/dev/null | tr -d '\r'
require 'yaml'
theme = YAML.load_file(ARGV.shift) rescue nil
fonts = []
if theme && theme['font']
  catalog = theme['font']['catalog'] || {}
  catalog.each_value do |faces|
    next unless faces.is_a?(Hash)
    faces.each_value do |path|
      fonts << path if path.is_a?(String)
    end
  end
end
fonts.uniq.each { |f| puts f }
RUBY
)
  fi

  if [[ -n "$fonts_output" ]]; then
    REQUIRED_FONTS=()
    while IFS= read -r font; do
      [[ -z "$font" ]] && continue
      REQUIRED_FONTS+=("$font")
    done <<< "$fonts_output"
  else
    REQUIRED_FONTS=("${DEFAULT_REQUIRED_FONTS[@]}")
  fi

  FONT_ARCHIVE_ENTRIES=()
  FONT_DIRECT_URLS=()
  FONT_DIRECT_URL_MAP=()
  local archive_required=false
  local direct_urls=()
  local direct_url_map=()

  for font_file in "${REQUIRED_FONTS[@]}"; do
    local archive_entry="$(map_font_to_archive_entry "$font_file")"
    local direct_url="$(map_font_to_direct_url "$font_file")"
    FONT_ARCHIVE_ENTRIES+=("$archive_entry")
    direct_urls+=("$direct_url")
    direct_url_map+=("$font_file:$direct_url")
    if [[ -n "$archive_entry" ]]; then
      archive_required=true
    fi
  done

  if [[ "$archive_required" == true ]]; then
    FONT_RELEASE_URL="https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
    FONT_ARCHIVE_NAME="Inter-4.1.zip"
    FONT_ARCHIVE_PATH="$SCRIPT_DIR/$FONT_ARCHIVE_NAME"
  else
    FONT_RELEASE_URL=""
    FONT_ARCHIVE_NAME=""
    FONT_ARCHIVE_PATH=""
  fi

  FONT_DIRECT_URLS=("${direct_urls[@]}")
  FONT_DIRECT_URL_MAP=("${direct_url_map[@]}")
}

### --- Ensure bundled fonts are available ---
ensure_bundled_fonts() {
  mkdir -p "$FONTS_DIR"

  local missing_fonts=()
  for font_file in "${REQUIRED_FONTS[@]}"; do
    if [[ ! -f "$FONTS_DIR/$font_file" ]]; then
      missing_fonts+=("$font_file")
    fi
  done

  if [[ ${#missing_fonts[@]} -eq 0 ]]; then
    $DEBUG && log "Bundled fonts already present."
    return 0
  fi

  local need_archive=false
  for i in "${!missing_fonts[@]}"; do
    local entry="${FONT_ARCHIVE_ENTRIES[$i]}"
    if [[ -n "$entry" ]]; then
      need_archive=true
      break
    fi
  done

  if [[ "$need_archive" == true && -n "$FONT_RELEASE_URL" ]]; then
    log "Downloading bundled fonts archive..."
    if curl -fsSL "$FONT_RELEASE_URL" -o "$FONT_ARCHIVE_PATH"; then
      $DEBUG && log "Downloaded font archive to $FONT_ARCHIVE_PATH"
      for i in "${!missing_fonts[@]}"; do
        local font_file="${missing_fonts[$i]}"
        local entry="${FONT_ARCHIVE_ENTRIES[$i]}"
        if [[ -z "$entry" ]]; then
          warn "No bundled source known for $font_file. Please provide it manually."
          continue
        fi
        if unzip -j -o "$FONT_ARCHIVE_PATH" "$entry" -d "$FONTS_DIR" >/dev/null 2>&1; then
          mv "$FONTS_DIR/$(basename "$entry")" "$FONTS_DIR/$font_file" 2>/dev/null || true
          $DEBUG && log "Extracted $font_file"
        else
          warn "Failed to extract $font_file from archive entry $entry"
        fi
      done
      rm -f "$FONT_ARCHIVE_PATH"
    else
      warn "Failed to download fonts archive from $FONT_RELEASE_URL"
    fi
  fi

  # Download fonts via direct URLs if still missing
  for font_file in "${missing_fonts[@]}"; do
    if [[ -f "$FONTS_DIR/$font_file" ]]; then
      continue
    fi
    local direct_url=""
    for mapping in "${FONT_DIRECT_URL_MAP[@]}"; do
      local name="${mapping%%:*}"
      local url="${mapping#*:}"
      if [[ "$name" == "$font_file" ]]; then
        direct_url="$url"
        break
      fi
    done
    if [[ -n "$direct_url" ]]; then
      log "Downloading $font_file from upstream repository..."
      if curl -fsSL "$direct_url" -o "$FONTS_DIR/$font_file"; then
        $DEBUG && log "Downloaded $font_file"
      else
        warn "Failed to download $font_file from $direct_url"
      fi
    fi
  done
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
  local theme_file="$THEME_FILE"
  if [[ "$theme_file" != /* ]]; then
    theme_file="$SCRIPT_DIR/$THEME_FILE"
  fi

  if [ ! -f "$theme_file" ]; then
    warn "Theme file not found: $theme_file"
    return 1
  fi

  load_theme_fonts "$theme_file"
  ensure_bundled_fonts

  if [[ ! -d "$FONTS_DIR" ]]; then
    warn "Bundled fonts directory not found: $FONTS_DIR"
  else
    log "Using bundled fonts from: $FONTS_DIR"
    local missing_fonts=0

    for font_file in "${REQUIRED_FONTS[@]}"; do
      if [[ ! -f "$FONTS_DIR/$font_file" ]]; then
        warn "Missing bundled font: $font_file"
        ((missing_fonts++))
      fi
    done

    if [[ $missing_fonts -eq 0 ]]; then
      log "All bundled theme fonts are present."
    else
      warn "Found $missing_fonts missing bundled fonts. PDF output may fall back to system fonts."
    fi
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
  local theme_path="$THEME_FILE"
  if [[ "$theme_path" != /* ]]; then
    theme_path="$SCRIPT_DIR/$THEME_FILE"
  fi

  local theme_args=()
  if [[ -f "$theme_path" ]]; then
    local theme_dir="$(dirname "$theme_path")"
    local theme_file_name="$(basename "$theme_path")"
    local theme_base="${theme_file_name%.*}"
    local theme_name="$theme_base"
    if [[ "$theme_base" == *"-theme" ]]; then
      theme_name="${theme_base%-theme}"
    fi
    theme_args=(-a "pdf-themesdir=$theme_dir" -a "pdf-theme=$theme_name")
  else
    warn "Theme file not found when generating output: $theme_path"
  fi

  local fonts_dirs=""
  if [[ -d "$FONTS_DIR" ]]; then
    fonts_dirs="$FONTS_DIR"
  fi

  local fonts_args=()
  if [[ -n "$fonts_dirs" ]]; then
    fonts_args=(-a "pdf-fontsdir=$fonts_dirs")
  fi

  if [[ "$FORMAT" == "pdf" ]]; then
    log "Generating PDF ..."

    # Change to input directory and generate PDF
    # The output will be in the current working directory
    if (cd "$(dirname "$MAIN")" && asciidoctor-pdf -r asciidoctor-diagram \
      "${theme_args[@]}" \
      "${fonts_args[@]}" \
      -o "../doc-renderer/$out" \
      "$(basename "$MAIN")") 2>/dev/null; then

      log "PDF generated successfully: $out"
    else
      warn "PDF generation failed. Trying with system fonts..."

      # Try with system font directories
      local fallback_font_dirs="$fonts_dirs"
      for font_dir in "/System/Library/Fonts" "/System/Library/Fonts/Supplemental" "/Library/Fonts" "$HOME/Library/Fonts"; do
        if [[ -d "$font_dir" ]]; then
          if [[ -n "$fallback_font_dirs" ]]; then
            fallback_font_dirs="$fallback_font_dirs:$font_dir"
          else
            fallback_font_dirs="$font_dir"
          fi
        fi
      done

      local fallback_fonts_args=()
      if [[ -n "$fallback_font_dirs" ]]; then
        fallback_fonts_args=(-a "pdf-fontsdir=$fallback_font_dirs")
      fi

      if (cd "$(dirname "$MAIN")" && asciidoctor-pdf -r asciidoctor-diagram \
        "${theme_args[@]}" \
        "${fallback_fonts_args[@]}" \
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
