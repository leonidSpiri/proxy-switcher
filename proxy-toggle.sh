#!/usr/bin/env bash
set -Eeuo pipefail

PROXY_PROFILE="/etc/profile.d/99-system-proxy.sh"
APT_PROXY_FILE="/etc/apt/apt.conf.d/95proxy"
SUDOERS_PROXY_FILE="/etc/sudoers.d/proxy-env"

trap 'echo "Ошибка: выполнение прервано." >&2' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Запусти скрипт от root: sudo bash $0"
    exit 1
  fi
}

ask_nonempty() {
  local prompt="$1"
  local value=""
  while true; do
    read -r -p "$prompt" value
    if [[ -n "${value// }" ]]; then
      printf '%s' "$value"
      return 0
    fi
    echo "Поле не должно быть пустым."
  done
}

ask_yes_no() {
  local prompt="$1"
  local answer=""
  while true; do
    read -r -p "$prompt [y/n]: " answer
    case "${answer,,}" in
      y|yes|д|да) return 0 ;;
      n|no|н|нет) return 1 ;;
      *) echo "Введи y или n." ;;
    esac
  done
}

urlencode() {
  local s="$1"
  local out=""
  local i c hex
  for ((i=0; i<${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *)
        printf -v hex '%%%02X' "'$c"
        out+="$hex"
        ;;
    esac
  done
  printf '%s' "$out"
}

write_proxy_profile() {
  local proxy_url="$1"
  local no_proxy_value="$2"

  cat > "$PROXY_PROFILE" <<EOF
# Created by proxy toggle script
export http_proxy="$proxy_url"
export https_proxy="$proxy_url"
export HTTP_PROXY="$proxy_url"
export HTTPS_PROXY="$proxy_url"
export no_proxy="$no_proxy_value"
export NO_PROXY="$no_proxy_value"
EOF

  chmod 0644 "$PROXY_PROFILE"
}

write_apt_proxy() {
  local proxy_url="$1"

  cat > "$APT_PROXY_FILE" <<EOF
// Created by proxy toggle script
Acquire::http::Proxy "$proxy_url/";
Acquire::https::Proxy "$proxy_url/";
EOF

  chmod 0644 "$APT_PROXY_FILE"
}

write_sudoers_proxy() {
  local tmp_file
  tmp_file="$(mktemp)"

  cat > "$tmp_file" <<'EOF'
Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
EOF

  chmod 0440 "$tmp_file"

  if command -v visudo >/dev/null 2>&1; then
    visudo -cf "$tmp_file" >/dev/null
  fi

  install -m 0440 "$tmp_file" "$SUDOERS_PROXY_FILE"
  rm -f "$tmp_file"
}

enable_proxy() {
  local scheme host port username password no_proxy_value proxy_url auth_enabled
  local default_no_proxy="localhost,127.0.0.1,::1,.local"

  echo
  echo "Настройка proxy"
  echo "Поддерживается стандартный HTTP/HTTPS proxy для исходящих подключений."
  echo

  read -r -p "Схема proxy [http]: " scheme
  scheme="${scheme:-http}"

  case "$scheme" in
    http|https) ;;
    *)
      echo "Поддерживаются только http или https."
      exit 1
      ;;
  esac

  host="$(ask_nonempty "Адрес proxy (host/IP): ")"
  port="$(ask_nonempty "Порт proxy: ")"

  if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( port < 1 || port > 65535 )); then
    echo "Некорректный порт: $port"
    exit 1
  fi

  auth_enabled=0
  if ask_yes_no "Нужна авторизация на proxy?"; then
    auth_enabled=1
    username="$(ask_nonempty "Логин: ")"
    read -r -s -p "Пароль: " password
    echo
  fi

  read -r -p "NO_PROXY [$default_no_proxy]: " no_proxy_value
  no_proxy_value="${no_proxy_value:-$default_no_proxy}"

  if [[ "$auth_enabled" -eq 1 ]]; then
    proxy_url="${scheme}://$(urlencode "$username"):$(urlencode "$password")@${host}:${port}"
  else
    proxy_url="${scheme}://${host}:${port}"
  fi

  write_proxy_profile "$proxy_url" "$no_proxy_value"
  write_apt_proxy "$proxy_url"
  write_sudoers_proxy

  echo
  echo "Proxy включен."
  echo "Файлы:"
  echo "  - $PROXY_PROFILE"
  echo "  - $APT_PROXY_FILE"
  echo "  - $SUDOERS_PROXY_FILE"
  echo
  echo "Что важно:"
  echo "  - для apt настройки начнут работать сразу"
  echo "  - для текущей shell-сессии выполни:"
  echo "      source $PROXY_PROFILE"
  echo "  - для уже запущенных сервисов может потребоваться restart"
}

disable_proxy() {
  rm -f "$PROXY_PROFILE" "$APT_PROXY_FILE" "$SUDOERS_PROXY_FILE"

  echo
  echo "Proxy отключен."
  echo "Удалены файлы:"
  echo "  - $PROXY_PROFILE"
  echo "  - $APT_PROXY_FILE"
  echo "  - $SUDOERS_PROXY_FILE"
  echo
  echo "Что важно:"
  echo "  - новые shell-сессии будут уже без proxy"
  echo "  - в текущей shell-сессии можно вручную выполнить:"
  echo '      unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY'
  echo "  - для уже запущенных сервисов может потребоваться restart"
}

show_menu() {
  echo "Выбери действие:"
  echo "1) Включить proxy"
  echo "2) Отключить proxy"
  echo "3) Выход"
  echo
  read -r -p "Номер действия: " choice

  case "$choice" in
    1) enable_proxy ;;
    2) disable_proxy ;;
    3) exit 0 ;;
    *) echo "Некорректный выбор."; exit 1 ;;
  esac
}

main() {
  require_root
  show_menu
}

main "$@"
