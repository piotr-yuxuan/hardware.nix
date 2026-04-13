# shellcheck disable=SC2154
# Variables jq_cmd and ollama_home are set by the Nix wrapper.
#
# Resolve an Ollama model tag to its GGUF blob path.
#
# Usage (from Nix wrapper):
#   model_tag=qwen3.5:35b
#   <this script>
#
# Prints the absolute path to the GGUF blob on stdout.
# Exits non-zero with an error message on stderr if the model
# is not found or the manifest cannot be parsed.

registry="${ollama_home}/models/manifests/registry.ollama.ai"

# Split model_tag into library/name and tag (e.g. "qwen3.5:35b"
# becomes name="qwen3.5", tag="35b").
name="${model_tag%%:*}"
tag="${model_tag#*:}"

manifest="${registry}/library/${name}/${tag}"

if [ ! -f "$manifest" ]; then
	printf 'llama-server-resolve-model: manifest not found: %s\n' "$manifest" >&2
	printf 'Run: ollama pull %s\n' "$model_tag" >&2
	exit 1
fi

# The GGUF blob is the layer with mediaType
# "application/vnd.ollama.image.model".
digest=$("$jq_cmd" -r \
	'.layers[] | select(.mediaType == "application/vnd.ollama.image.model") | .digest' \
	"$manifest")

if [ -z "$digest" ]; then
	printf 'llama-server-resolve-model: no model layer in manifest: %s\n' "$manifest" >&2
	exit 1
fi

# Ollama stores blobs as sha256-<hex> (digest format is "sha256:<hex>").
blob_name="${digest//:/-}"
blob_path="${ollama_home}/models/blobs/${blob_name}"

if [ ! -f "$blob_path" ]; then
	printf 'llama-server-resolve-model: blob not found: %s\n' "$blob_path" >&2
	printf 'Run: ollama pull %s\n' "$model_tag" >&2
	exit 1
fi

printf '%s' "$blob_path"
