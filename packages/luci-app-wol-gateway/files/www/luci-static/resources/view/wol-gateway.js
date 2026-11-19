'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'luci.wol-gateway', method: 'status', expect: {} });
var callConfig = rpc.declare({ object: 'luci.wol-gateway', method: 'get_config', expect: {} });
var callSave = rpc.declare({
	object: 'luci.wol-gateway', method: 'save_config',
	params: [ 'BOT_TOKEN', 'ALLOWED_USER_IDS', 'TARGET_NAMES', 'TARGET_LABELS',
		'TARGET_MACS', 'TARGET_IPS', 'DEFAULT_TARGETS', 'NETWORK_INTERFACE' ],
	expect: {}
});
var callService = rpc.declare({ object: 'luci.wol-gateway', method: 'service', params: [ 'action' ], expect: {} });
var callLogging = rpc.declare({ object: 'luci.wol-gateway', method: 'set_logging', params: [ 'enabled' ], expect: {} });
var callLogs = rpc.declare({ object: 'luci.wol-gateway', method: 'logs', expect: {} });
var callTelegramTest = rpc.declare({ object: 'luci.wol-gateway', method: 'test_telegram', expect: {} });

return view.extend({
	load: function() {
		return Promise.all([ callStatus(), callConfig(), callLogs() ]);
	},

	render: function(data) {
		var status = data[0] || {};
		var config = data[1] || {};
		var fields = {};
		var logBox;

		function notify(message, type) {
			ui.addNotification(null, E('p', message), type || 'info');
		}

		function checked(promise) {
			return promise.then(function(result) {
				if (!result || !result.ok)
					throw new Error(result && result.error ? result.error : 'Операция не выполнена');
				return result;
			}).catch(function(err) {
				notify(err.message || 'Ошибка RPC', 'error');
				throw err;
			});
		}

		function updateStatus(next) {
			status = next || status;
			var running = document.getElementById('wg-running');
			var autostart = document.getElementById('wg-autostart');
			var logging = document.getElementById('wg-logging-state');
			if (running) running.textContent = status.running ? 'Работает' : 'Остановлена';
			if (autostart) autostart.textContent = status.autostart ? 'Включён' : 'Выключен';
			if (logging) logging.textContent = status.logging ? 'Включено' : 'Выключено';
			var toggle = document.getElementById('wg-log-toggle');
			if (toggle) toggle.checked = !!status.logging;
		}

		function serviceButton(label, action) {
			return E('button', {
				'class': 'btn cbi-button',
				'click': function(ev) {
					ev.preventDefault();
					checked(callService(action)).then(function(result) {
						notify(result.message || 'Команда выполнена');
						return callStatus();
					}).then(updateStatus).catch(function() {});
				}
			}, label);
		}

		function field(key, label, hint, value, type) {
			var attrs = {
				'id': 'wg-' + key,
				'class': 'form-control',
				'autocomplete': key === 'BOT_TOKEN' ? 'new-password' : 'off'
			};
			if (type === 'password') {
				attrs.type = 'password';
				attrs.placeholder = config.token_configured ?
					'Токен уже сохранён. Заполните только для замены.' : 'Введите токен BotFather';
			}
			else if (type === 'textarea') {
				attrs.rows = 2;
			}
			else {
				attrs.type = 'text';
				attrs.value = value || '';
			}
			var input = E(type === 'textarea' ? 'textarea' : 'input', attrs,
				type === 'textarea' ? (value || '') : null);
			fields[key] = input;
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title', 'for': attrs.id }, label),
				E('div', { 'class': 'cbi-value-field' }, [
					input,
					E('div', { 'class': 'cbi-value-description' }, hint)
				])
			]);
		}

		function refreshLogs() {
			return callLogs().then(function(result) {
				if (logBox)
					logBox.textContent = result.logs || 'Записей пока нет.';
			}).catch(function() {});
		}

		var save = E('button', {
			'class': 'btn cbi-button cbi-button-positive',
			'click': function(ev) {
				ev.preventDefault();
				var values = {};
				Object.keys(fields).forEach(function(key) {
					values[key] = fields[key].value.trim();
				});
				checked(callSave(values.BOT_TOKEN, values.ALLOWED_USER_IDS, values.TARGET_NAMES,
					values.TARGET_LABELS, values.TARGET_MACS, values.TARGET_IPS,
					values.DEFAULT_TARGETS, values.NETWORK_INTERFACE)).then(function(result) {
					fields.BOT_TOKEN.value = '';
					notify(result.message || 'Настройки сохранены');
				}).catch(function() {});
			}
		}, 'Сохранить настройки');

		var configSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', 'Конфигурация'),
			field('BOT_TOKEN', 'Telegram Bot Token',
				'Токен хранится в /etc/wol-gateway.env с правами 600. Пустое поле сохраняет текущий токен.',
				'', 'password'),
			field('ALLOWED_USER_IDS', 'Разрешённые Telegram ID',
				'Числовые Telegram User ID. Несколько значений указываются через запятую.',
				config.ALLOWED_USER_IDS, 'text'),
			field('TARGET_NAMES', 'Алиасы устройств',
				'Уникальные алиасы из строчных латинских букв, цифр и дефисов. Значения через запятую.',
				config.TARGET_NAMES, 'text'),
			field('TARGET_LABELS', 'Названия устройств',
				'Отображаемые названия. Порядок и количество элементов должны совпадать с TARGET_NAMES.',
				config.TARGET_LABELS, 'textarea'),
			field('TARGET_MACS', 'MAC-адреса',
				'MAC каждого устройства через запятую, в том же порядке, что и TARGET_NAMES.',
				config.TARGET_MACS, 'text'),
			field('TARGET_IPS', 'IP-адреса',
				'IPv4 через запятую, в том же порядке, что и MAC-адреса. Если IP не нужен, укажите 0.',
				config.TARGET_IPS, 'text'),
			field('DEFAULT_TARGETS', 'Устройства по умолчанию',
				'Алиасы для /wake и /status без аргументов. Несколько алиасов — через запятую.',
				config.DEFAULT_TARGETS, 'text'),
			field('NETWORK_INTERFACE', 'Сетевой интерфейс',
				'LAN-интерфейс для отправки Magic Packet. Обычно br-lan.',
				config.NETWORK_INTERFACE || 'br-lan', 'text'),
			E('div', { 'class': 'cbi-page-actions' }, [
				save,
				E('button', {
					'class': 'btn cbi-button',
					'click': function(ev) {
						ev.preventDefault();
						checked(callTelegramTest()).then(function(result) {
							notify(result.message || 'Telegram API доступен', 'success');
						}).catch(function() {});
					}
				}, 'Проверить Telegram')
			])
		]);

		var statusSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', 'Управление службой'),
			E('p', [ 'Состояние: ', E('strong', { 'id': 'wg-running' }, status.running ? 'Работает' : 'Остановлена'),
				' · Автозапуск: ', E('strong', { 'id': 'wg-autostart' }, status.autostart ? 'Включён' : 'Выключен') ]),
			E('div', { 'class': 'cbi-page-actions' }, [
				serviceButton('Запустить', 'start'),
				serviceButton('Остановить', 'stop'),
				serviceButton('Перезапустить', 'restart'),
				serviceButton('Включить автозапуск', 'enable'),
				serviceButton('Отключить автозапуск', 'disable')
			])
		]);

		logBox = E('pre', {
			'class': 'well',
			'style': 'max-height: 320px; overflow: auto; white-space: pre-wrap;'
		}, data[2] && data[2].logs ? data[2].logs : 'Записей пока нет.');

		var logsSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', 'Журнал'),
			E('p', 'Журнал хранится в кольцевом буфере системного logd в RAM. Постоянный файл на flash не создаётся. При выключении подробного логирования критические ошибки продолжают записываться.'),
			E('label', {}, [
				E('input', {
					'type': 'checkbox',
					'id': 'wg-log-toggle',
					'checked': !!status.logging,
					'change': function(ev) {
						checked(callLogging(ev.target.checked ? 1 : 0)).then(function(result) {
							notify(result.message || 'Настройка сохранена');
							return callStatus();
						}).then(updateStatus).catch(function() {});
					}
				}),
				' Подробное логирование ',
				E('strong', { 'id': 'wg-logging-state' }, status.logging ? 'Включено' : 'Выключено')
			]),
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'btn cbi-button',
					'click': function(ev) { ev.preventDefault(); refreshLogs(); }
				}, 'Обновить журнал')
			]),
			logBox
		]);

		poll.add(function() {
			return Promise.all([ callStatus(), refreshLogs() ]).then(function(result) {
				updateStatus(result[0]);
			});
		}, 10);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', 'WOL Gateway'),
			E('p', 'Управление Telegram Wake-on-LAN Gateway. Основная служба и LuCI-интерфейс устанавливаются отдельными пакетами.'),
			statusSection,
			configSection,
			logsSection
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
