# shellcheck disable=SC2154
# Variables resolve and llama_server are set by the Nix wrapper.
#
# Resolve Ollama model blobs and start llama-server with speculative
# decoding.  Called as ExecStart by the llama-server systemd service.

main_tag="qwen3.5:35b"
draft_tag="qwen3.5:0.8b"

main_path=$("$resolve" "$main_tag") || exit 1
draft_path=$("$resolve" "$draft_tag") || exit 1

printf 'Main model : %s -> %s\n' "$main_tag" "$main_path"
printf 'Draft model: %s -> %s\n' "$draft_tag" "$draft_path"

exec "$llama_server" \
	--model "$main_path" \
	--model-draft "$draft_path" \
	--draft 16 \
	--draft-p-min 0.75 \
	--gpu-layers 99 \
	--gpu-layers-draft 99 \
	--ctx-size 8192 \
	--cache-type-k q8_0 \
	--cache-type-v q8_0 \
	--host 127.0.0.1 \
	--port 8081 \
	--flash-attn
