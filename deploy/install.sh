#!/usr/bin/env bash
# Установка бота на VPS (Ubuntu 22.04+ / Debian 12+) одной командой:
#   curl -fsSL https://raw.githubusercontent.com/reshatmemetov01/-/claude/epic-fermat-yuhupj/deploy/install.sh | sudo bash
# Повторный запуск безопасен: обновит код и перезапустит бота, настройки (.env) не трогает.
set -euo pipefail

REPO="https://github.com/reshatmemetov01/-.git"
BRANCH="${BRANCH:-claude/epic-fermat-yuhupj}"
DIR="/opt/pdd-bot"
SERVICE="pdd-bot"
BOT_USER="pddbot"

if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root: sudo bash install.sh"; exit 1
fi

ask() {  # ask "Вопрос" "значение по умолчанию" → ответ
  local answer
  read -r -p "$1${2:+ [$2]}: " answer < /dev/tty
  echo "${answer:-$2}"
}

echo "==> Устанавливаю Python и git"
apt-get update -qq
apt-get install -y -qq python3 python3-venv git > /dev/null

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  echo "Нужен Python 3.10 или новее (сейчас: $(python3 --version)). Поставь Ubuntu 22.04+ или Debian 12+."
  exit 1
fi

id "$BOT_USER" &> /dev/null || useradd --system --home "$DIR" --shell /usr/sbin/nologin "$BOT_USER"

echo "==> Скачиваю код"
if [[ -d "$DIR/.git" ]]; then
  git -c safe.directory="$DIR" -C "$DIR" fetch -q origin "$BRANCH"
  git -c safe.directory="$DIR" -C "$DIR" checkout -q "$BRANCH"
  git -c safe.directory="$DIR" -C "$DIR" reset -q --hard "origin/$BRANCH"
else
  mkdir -p "$DIR"
  git clone -q --branch "$BRANCH" "$REPO" "$DIR"
fi

echo "==> Ставлю зависимости"
[[ -d "$DIR/venv" ]] || python3 -m venv "$DIR/venv"
"$DIR/venv/bin/pip" install -q --upgrade pip
"$DIR/venv/bin/pip" install -q -r "$DIR/requirements.txt"

if [[ ! -f "$DIR/.env" ]]; then
  echo
  echo "==> Настройка (Enter — оставить значение в скобках)"
  BOT_TOKEN=$(ask "Токен бота от @BotFather" "")
  while [[ -z "$BOT_TOKEN" ]]; do BOT_TOKEN=$(ask "Токен обязателен" ""); done
  ADMIN_IDS=$(ask "Твой Telegram ID (админ)" "8439460659")
  MANAGER=$(ask "Username для поддержки, без @" "nothing409")
  CHANNEL_URL=$(ask "Ссылка на Telegram-канал (необязательно)" "https://t.me/+BvlfDRKRVh1mYmRi")
  ACCESS_LINK=$(ask "Запасная ссылка на закрытую группу" "https://t.me/+HDj18NGLc3I2OGNi")
  PAYMENT=$(ask "Реквизиты СБП (перенос строки — \\n)" "")
  cat > "$DIR/.env" <<ENV
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
MANAGER_USERNAME=$MANAGER
CHANNEL_URL=$CHANNEL_URL
ACCESS_LINK=$ACCESS_LINK
PRIVATE_CHANNEL_ID=
PRICE=1490
OLD_PRICE=
PAYMENT_DETAILS=$PAYMENT
DB_PATH=$DIR/pdd_bot.db
QUESTIONS_PATH=data/questions.json
TIMEZONE=Europe/Moscow
FOLLOWUP_DELAY_SCALE=1
ENV
  echo "Настройки сохранены в $DIR/.env (поменять: sudo nano $DIR/.env)"
fi

chown -R "$BOT_USER:$BOT_USER" "$DIR"
chmod 600 "$DIR/.env"

echo "==> Включаю автозапуск"
sed -e "s|/opt/pdd-bot|$DIR|g" -e "s|User=pddbot|User=$BOT_USER|" "$DIR/deploy/pdd-bot.service" \
  > "/etc/systemd/system/$SERVICE.service"
systemctl daemon-reload
systemctl enable -q "$SERVICE"
systemctl restart "$SERVICE"
sleep 3

if systemctl is-active -q "$SERVICE"; then
  echo
  echo "✅ Бот запущен и будет сам стартовать после перезагрузки сервера."
  echo "   Логи:        sudo journalctl -u $SERVICE -f"
  echo "   Обновление:  sudo bash $DIR/deploy/update.sh"
else
  echo "❌ Бот не запустился. Последние строки лога:"
  journalctl -u "$SERVICE" -n 30 --no-pager
  exit 1
fi
