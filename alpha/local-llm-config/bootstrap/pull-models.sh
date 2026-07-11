#!/bin/sh
# Provisions models declaratively:
#   1. pulls every model listed in models.txt
#   2. builds every modelfiles/*.Modelfile (filename becomes the model name)
# Runs against the ollama server named by $OLLAMA_HOST, then exits.
set -eu

echo "==> Waiting for Ollama at ${OLLAMA_HOST} ..."
until ollama list >/dev/null 2>&1; do
  sleep 2
done
echo "==> Ollama is up."

if [ -f /models.txt ]; then
  # Drop comments/blank lines; trim whitespace and Windows CR from each entry.
  grep -vE '^[[:space:]]*(#|$)' /models.txt | while IFS= read -r line; do
    model=$(printf '%s' "$line" | tr -d '\r' | xargs)
    [ -z "$model" ] && continue
    echo "==> Pulling $model"
    ollama pull "$model"
  done
fi

# Custom models built on top of a base (see modelfiles/assistant.Modelfile for the pattern).
for mf in /modelfiles/*.Modelfile; do
  [ -e "$mf" ] || continue
  name=$(basename "$mf" .Modelfile)
  echo "==> Creating custom model: $name"
  ollama create "$name" -f "$mf"
done

echo "==> Done. Currently available models:"
ollama list
