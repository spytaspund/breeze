#!/bin/bash

WIDGET_DIR="/var/mobile/Library/iWidgets/Weather-iWidgets"
cd "$WIDGET_DIR" || exit 1

PLIST_FILE="Options.plist"

get_plist_value() {
    local search_key="$1"
    local found_key=0
    local found_default=0

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == *"<string>$search_key</string>"* ]]; then
            found_key=1
        elif [[ $found_key -eq 1 && "$line" == *"<key>default</key>"* ]]; then
            found_default=1
        elif [[ $found_default -eq 1 && "$line" == *"<string>"* ]]; then
            local value="${line#*<string>}"
            value="${value%%</string>*}"
            echo "$value"
            return
        fi
    done < "$PLIST_FILE"
}

LAT=$(get_plist_value "lat")
LON=$(get_plist_value "lon")
API_KEY=$(get_plist_value "apiKey")

LAT=${LAT:-"0.0000"}
LON=${LON:-"0.0000"}
API_KEY=${API_KEY:-""}

FINAL_FILE="weather.js"
URL="https://api.weather.yandex.ru/v2/forecast?lat=$LAT&lon=$LON"

echo -n "var weatherData = " > "$FINAL_FILE"
curl -s "$URL" -H "X-Yandex-Weather-Key: $API_KEY" >> "$FINAL_FILE"