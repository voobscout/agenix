{writeShellScriptBin, runtimeShell, age, yq-go} :
writeShellScriptBin "agenix" ''
set -euo pipefail
PACKAGE="agenix"

function show_help () {
  echo "$PACKAGE - edit and rekey age secret files"
  echo " "
  echo "$PACKAGE -e FILE"
  echo "$PACKAGE -r"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  echo '-e, --edit FILE           edits FILE using $EDITOR'
  echo '-r, --rekey               re-encrypts all secrets with specified recipients'
  echo ' '
  echo 'FILE an age-encrypted file'
  echo ' '
  echo 'EDITOR environment variable of editor to use when editing FILE'
  echo ' '
  echo 'RULES environment variable with path to YAML file specifying recipient public keys.'
  echo "Defaults to 'secrets.yaml'"
}

test $# -eq 0 && (show_help && exit 1)

REKEY=0

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -e|--edit)
      shift
      if test $# -gt 0; then
        export FILE=$1
      else
        echo "no file specified"
        exit 1
      fi
      shift
      ;;
    -r|--rekey)
      shift
      REKEY=1
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
done

RULES=''${RULES:-secrets.yaml}

function cleanup {
    if [ ! -z ''${CLEARTEXT_DIR+x} ]
    then
        rm -rf "$CLEARTEXT_DIR"
    fi
    if [ ! -z ''${REENCRYPTED_DIR+x} ]
    then
        rm -rf "$REENCRYPTED_DIR"
    fi
}
trap "cleanup" 0 2 3 15

function edit {
    FILE=$1
    KEYS=$(${yq-go}/bin/yq r "$RULES" "secrets.(name==$FILE).public_keys.**")
    if [ -z "$KEYS" ]
    then
        >&2 echo "There is no rule for $FILE in $RULES."
        exit 1
    fi

    CLEARTEXT_DIR=$(mktemp -d)
    CLEARTEXT_FILE="$CLEARTEXT_DIR/$(basename "$FILE")"

    if [ -f "$FILE" ]
    then
        DECRYPT=(--decrypt)
        while IFS= read -r key
        do
            DECRYPT+=(--identity "$key")
        done <<<$(find ~/.ssh -maxdepth 1 -type f -not -name "*pub" -not -name "config" -not -name "authorized_keys" -not -name "known_hosts")
        DECRYPT+=(-o "$CLEARTEXT_FILE" "$FILE")
        ${age}/bin/age "''${DECRYPT[@]}"
    fi

    $EDITOR "$CLEARTEXT_FILE"

    ENCRYPT=()
    while IFS= read -r key
    do
        ENCRYPT+=(--recipient "$key")
    done <<< "$KEYS"

    REENCRYPTED_DIR=$(mktemp -d)
    REENCRYPTED_FILE="$REENCRYPTED_DIR/$(basename "$FILE")"

    ENCRYPT+=(-o "$REENCRYPTED_FILE")

    cat "$CLEARTEXT_FILE" | ${age}/bin/age "''${ENCRYPT[@]}"

    mv -f "$REENCRYPTED_FILE" "$1"
}

function rekey {
    echo "rekeying..."
    FILES=$(${yq-go}/bin/yq r "$RULES" "secrets.*.name")
    for FILE in $FILES
    do
        EDITOR=: edit $FILE
    done
}

[ $REKEY -eq 1 ] && rekey && exit 0
edit $FILE && exit 0
''