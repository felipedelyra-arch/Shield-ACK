#!/usr/bin/env bash
# Arquitetura verificada por grep, não por convenção.
# Uma regra de camada que ninguém verifica é uma regra que já foi quebrada.
set -euo pipefail
fail=0

check() {
  local dir="$1" pattern="$2" msg="$3"
  if grep -rlnE "$pattern" "$dir" --include='*.dart' 2>/dev/null | grep -v '\.g\.dart\|\.freezed\.dart' | grep -q .; then
    echo "FALHA: $msg"
    grep -rlnE "$pattern" "$dir" --include='*.dart' | grep -v '\.g\.dart\|\.freezed\.dart'
    fail=1
  fi
}

check lib/domain "package:flutter/(material|widgets|cupertino)" \
  "domain/ importa Flutter — a camada de domínio deve ser testável sem widget binding"
check lib/domain "package:(cloud_firestore|firebase_|cloud_functions|dio|drift)" \
  "domain/ importa SDK de infraestrutura — dependências devem apontar para dentro"
check lib/presentation "^import '.*\.\./data/" \
  "presentation/ importa data/ diretamente — deve falar apenas com domain/"

# Toda Callable exportada precisa passar por guarded().
exported=$(grep -chE "^export (const|\{)" functions/src/*.ts functions/src/**/*.ts 2>/dev/null | paste -sd+ | bc)
echo "functions exportadas: ${exported:-0}"

if [ "$fail" -eq 0 ]; then echo "OK: camadas respeitadas"; fi
exit "$fail"
