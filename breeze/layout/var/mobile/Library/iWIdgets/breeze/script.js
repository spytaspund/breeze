var interval = (typeof UPDATE_INTERVAL !== 'undefined') ? UPDATE_INTERVAL : 5000;
var lang = (typeof LANGUAGE !== 'undefined' && LANGUAGE) ? LANGUAGE : 'ru_RU';
var widgetTitle = (typeof WIDGET_TITLE !== 'undefined' && WIDGET_TITLE) ? WIDGET_TITLE : null;

var translations = window.translations || {};

function t(key) {
    var dict = translations[lang] ? translations[lang] : translations['ru_RU'];
    return dict[key] || translations['ru_RU'][key] || key;
}

var labelEl = document.getElementById("widget-label");
if (labelEl) {
    labelEl.innerText = widgetTitle ? widgetTitle : t('defaultTitle');
}
document.getElementById("condition").innerText = t('loading');

var iconPack = {
    clearDay: '<img class="raw-icon weather-icon" src="icons/sun-max-fill.svg">',
    clearNight: '<img class="raw-icon weather-icon" src="icons/moon-stars-fill.svg">',
    pCloudyDay: '<img class="raw-icon weather-icon" src="icons/cloud-sun-fill.svg">',
    pCloudyNight: '<img class="raw-icon weather-icon" src="icons/cloud-moon-fill.svg">',
    cloudy: '<img class="raw-icon weather-icon" src="icons/cloud-fill.svg">',
    drizzle: '<img class="raw-icon weather-icon" src="icons/cloud-rain-fill.svg">',
    rainDay: '<img class="raw-icon weather-icon" src="icons/cloud-sun-rain-fill.svg">',
    rainNight: '<img class="raw-icon weather-icon" src="icons/cloud-moon-rain-fill.svg">',
    heavyRain: '<img class="raw-icon weather-icon" src="icons/cloud-heavyrain-fill.svg">',
    thunderstorms: '<img class="raw-icon weather-icon" src="icons/cloud-bolt-rain-fill.svg">',
    snow: '<img class="raw-icon weather-icon" src="icons/cloud-snow-fill.svg">',
    sleet: '<img class="raw-icon weather-icon" src="icons/cloud-sleet-fill.svg">',
    fog: '<img class="raw-icon weather-icon" src="icons/cloud-fog-fill.svg">'
};

function getWeatherData(condCode, isDay) {
    if (!isDay) {
        if (condCode === 'clear') return { text: t('clear'), bg: 'bg-night', icon: iconPack.clearNight };
        if (condCode === 'partly-cloudy') return { text: t('partlyCloudy'), bg: 'bg-night', icon: iconPack.pCloudyNight };
        if (condCode === 'rain' || condCode === 'light-rain') return { text: t('rain'), bg: 'bg-night', icon: iconPack.rainNight };
    }
    if (condCode === 'partly-cloudy') return { text: t('partlyCloudy'), bg: 'bg-dusk', icon: iconPack.pCloudyDay };
    if (condCode === 'clear') return { text: t('clear'), bg: 'bg-sunny', icon: iconPack.clearDay };
    if (condCode === 'cloudy' || condCode === 'overcast') return { text: t('cloudy'), bg: 'bg-cloudy', icon: iconPack.cloudy };
    if (condCode === 'rain' || condCode === 'light-rain') return { text: t('rain'), bg: 'bg-rain', icon: iconPack.rainDay };
    if (condCode.indexOf('heavy') !== -1 || condCode === 'showers') return { text: t('heavyRain'), bg: 'bg-rain', icon: iconPack.heavyRain };
    if (condCode === 'drizzle') return { text: t('drizzle'), bg: 'bg-rain', icon: iconPack.drizzle };
    if (condCode.indexOf('snow') !== -1) { 
        if (condCode === 'wet-snow') return { text: t('wetSnow'), bg: 'bg-rain', icon: iconPack.sleet }; 
        return { text: t('snow'), bg: 'bg-rain', icon: iconPack.snow }; 
    }
    if (condCode.indexOf('thunderstorm') !== -1) return { text: t('thunderstorm'), bg: 'bg-night', icon: iconPack.thunderstorms };
    if (condCode === 'fog') return { text: t('fog'), bg: 'bg-cloudy', icon: iconPack.fog };
    return { text: t('overcast'), bg: 'bg-rain', icon: iconPack.cloudy };
}

function fetchCityName(lat, lon) {
    var langCode = lang.split('_')[0];
    var xhr = new XMLHttpRequest();
    var url = "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=" + lat + "&longitude=" + lon + "&localityLanguage=" + langCode;
    
    xhr.open("GET", url, true);
    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    var city = response.locality || "???";
                    document.getElementById("loc-display").innerText = city;
                } catch (e) {
                    document.getElementById("loc-display").innerText = t('geoError');
                }
            } else {
                document.getElementById("loc-display").innerText = t('netError');
            }
        }
    };
    xhr.send();
}

function loadDynamicScript(src, scriptId, onLoadCallback) {
    var oldScript = document.getElementById(scriptId);
    if (oldScript) {
        oldScript.remove();
    }

    var script = document.createElement('script');
    script.id = scriptId;
    script.src = src + '?_ts=' + new Date().getTime();
    
    script.onload = onLoadCallback;
    script.onerror = function() {
        if (typeof apiKey === 'undefined' || !apiKey || apiKey === "default") {
            document.getElementById("condition").innerText = t('specifyKey');
            document.getElementById("loc-display").innerText = t('error');
        }
    };

    document.body.appendChild(script);
}

function loadAndParseWeather() {
    if (typeof apiKey === 'undefined' || !apiKey || apiKey === "default") {
        document.getElementById("condition").innerText = t('specifyKey');
        return;
    }

    loadDynamicScript('weather.js', 'weather-data-script', function() {
        try {
            if (typeof weatherData !== 'undefined' && weatherData.fact) {
                var data = weatherData;
                
                if (data.info && data.info.lat && data.info.lon) {
                    fetchCityName(data.info.lat, data.info.lon);
                } else {
                    document.getElementById("loc-display").innerText = t('noCoords');
                }

                document.getElementById("temp").innerHTML = data.fact.temp + "&deg;";
                
                var isDay = data.fact.daytime === 'd';
                var matched = getWeatherData(data.fact.condition, isDay);
                
                document.getElementById("condition").innerText = matched.text;
                document.getElementById("card").className = "weather-card " + matched.bg;
                document.getElementById("icon-wrapper").innerHTML = matched.icon;
                
                if (data.forecasts && data.forecasts[0] && data.forecasts[0].parts) {
                    var parts = data.forecasts[0].parts;
                    var minTemp = parts.night_short ? parts.night_short.temp : (parts.night ? parts.night.temp_min : 0);
                    var maxTemp = parts.day_short ? parts.day_short.temp : (parts.day ? parts.day.temp_max : 0);
                    
                    if (minTemp === undefined || maxTemp === undefined) {
                        minTemp = parts.day ? parts.day.temp_min : 0; 
                        maxTemp = parts.day ? parts.day.temp_max : 0;
                    }

                    document.getElementById("forecast").innerHTML = 
                        '<img class="arrow-icon raw-icon" src="icons/arrow-down.svg">' + minTemp + '&deg;' + 
                        '<img class="arrow-icon arrow-up raw-icon" src="icons/arrow-up.svg">' + maxTemp + '&deg;';
                }
            }
        } catch (e) {
            console.log("Weather.js parse error: ", e);
        }
    });
}

loadAndParseWeather();
setInterval(loadAndParseWeather, interval);