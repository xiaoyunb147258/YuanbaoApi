(function () {
  'use strict';
  var N = window.YuanbaoNative;
  function $(id) { return document.getElementById(id); }

  function call(fn) {
    try { var raw = fn(); return raw ? JSON.parse(raw) : { ok: false, error: '空响应' }; }
    catch (e) { return { ok: false, error: String(e) }; }
  }

  function toast(msg) {
    var t = $('toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(function () { t.classList.remove('show'); }, 1800);
  }

  function openDrawer() { $('drawer').classList.add('show'); $('drawer-mask').classList.add('show'); loadSettings(); }
  function closeDrawer() { $('drawer').classList.remove('show'); $('drawer-mask').classList.remove('show'); }
  $('fab-settings').addEventListener('click', openDrawer);
  $('drawer-close').addEventListener('click', closeDrawer);
  $('drawer-mask').addEventListener('click', closeDrawer);

  var lastStatus = {};
  function refreshStatus() {
    var r = call(function () { return N.getStatus(); });
    if (!r.ok) return;
    var d = r.data;
    lastStatus = d;
    var running = d.running;
    $('pulse').classList.toggle('on', running);
    $('hdr-badge').classList.toggle('on', running);
    $('hdr-badge').textContent = running ? '运行中' : '离线';
    $('hero-state').textContent = running ? '运行中' : '未运行';
    $('hero-desc').textContent = running ? ('http://' + d.ip + ':' + d.port + '/v1') : '启动网关开始服务';
    $('btn-toggle').textContent = running ? '停止网关' : '启动网关';
    $('addr').textContent = 'http://' + d.ip + ':' + d.port + '/v1';
    $('stat-port').textContent = d.port;
    $('stat-req').textContent = d.requestCount;
    $('stat-acc').textContent = d.loggedIn ? '已登录' : '未登录';
    var ls = $('login-state');
    ls.textContent = d.loggedIn ? '已登录' : '未登录';
    ls.classList.toggle('on', d.loggedIn);
  }

  $('btn-toggle').addEventListener('click', function () {
    var r = call(function () { return N.getStatus(); });
    var running = r.ok && r.data.running;
    call(function () { return running ? N.stopService() : N.startService(); });
    toast(running ? '正在停止…' : '正在启动…');
    setTimeout(refreshStatus, 900);
  });
  $('btn-restart').addEventListener('click', function () {
    call(function () { return N.restartService(); });
    toast('正在重启…');
    setTimeout(refreshStatus, 1100);
  });
  $('btn-copy-url').addEventListener('click', function () {
    var url = 'http://' + lastStatus.ip + ':' + lastStatus.port + '/v1';
    var c = call(function () { return N.copyToClipboard(url); });
    toast(c.ok ? '已复制' : '复制失败');
  });
  $('btn-clear-log').addEventListener('click', function () {
    call(function () { return N.clearLogs(); });
    $('log').innerHTML = '';
  });

  window.onNativeLog = function (time, text) {
    var box = $('log');
    if (box.children.length > 300) box.removeChild(box.firstChild);
    var line = document.createElement('div');
    line.textContent = '[' + time + '] ' + text;
    box.appendChild(line);
    box.scrollTop = box.scrollHeight;
  };

  $('btn-login').addEventListener('click', function () {
    if (window.YuanbaoLogin) { window.YuanbaoLogin.openLogin(); closeDrawer(); }
    else { toast('登录入口不可用'); }
  });

  function loadSettings() {
    var r = call(function () { return N.getStatus(); });
    if (!r.ok) return;
    var d = r.data;
    $('in-port').value = d.configPort;
    $('in-key').value = d.apiKey;
    $('sw-auto').checked = !!d.autoStart;
    $('sw-float').checked = !!d.showFloat;
    var m = call(function () { return N.getModels(); });
    if (m.ok) {
      var box = $('model-list');
      box.innerHTML = '';
      (m.data || []).forEach(function (mo) {
        var item = document.createElement('div');
        item.className = 'model-item';
        item.innerHTML = '<span class="model-id">' + mo.id + '</span><span class="model-name">' + mo.name + '</span>';
        box.appendChild(item);
      });
    }
  }

  $('btn-save').addEventListener('click', function () {
    var port = parseInt($('in-port').value, 10);
    if (isNaN(port) || port < 1 || port > 65535) { toast('端口不合法'); return; }
    var r = call(function () { return N.saveSettings(port, $('in-key').value.trim()); });
    toast(r.ok ? '已保存' : r.error);
  });

  function bindSwitch(id, key) {
    $(id).addEventListener('change', function () {
      call(function () { return N.setSwitch(key, $(id).checked); });
      toast('已' + ($(id).checked ? '开启' : '关闭'));
    });
  }
  bindSwitch('sw-auto', 'autoStart');
  bindSwitch('sw-float', 'showFloat');

  $('btn-overlay').addEventListener('click', function () {
    call(function () { return N.requestOverlay(); });
    toast('请授予权限');
  });
  $('btn-battery').addEventListener('click', function () {
    call(function () { return N.requestBattery(); });
    toast('请允许忽略优化');
  });

  document.addEventListener('DOMContentLoaded', function () {
    refreshStatus();
    setInterval(refreshStatus, 3000);
  });
})();
