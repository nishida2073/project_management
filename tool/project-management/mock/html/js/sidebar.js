(function () {
  var ITEMS = [
    { title: '案件管理' },
    { key: 'project', label: '案件', href: 'project_list.html' },
    { key: 'project-progress', label: '進捗', href: 'project_progress_list.html' },
    { title: 'クラス管理' },
    { key: 'class', label: 'クラス', href: 'class_list.html' },
    { key: 'assign', label: '登壇依頼', href: 'vender_assign_list.html' },
    { key: 'unei', label: '進捗', href: 'class_progress_list.html' },
    { title: 'マスタ管理' },
    { sub: 'subject', label: '科目', href: 'subject_list.html' },
    { sub: 'course', label: 'コース', href: 'course_list.html' },
    { sub: 'location', label: 'ロケーション', href: 'location_list.html' },
    { sub: 'customer', label: '顧客', href: 'customer_list.html' },
    { sub: 'vendor', label: '講師ベンダー', href: 'teacher_vender_list.html' },
    { sub: 'staffVender', label: '実施担当ベンダー', href: 'staff_vender_list.html' },
    { sub: 'staff', label: '実施担当者', href: 'staff_list.html' },
    { sub: 'task', label: 'タスク', href: 'task_list.html' },
    { sub: 'customAttribute', label: '項目設定', href: 'custom_attribute_settings.html' },
    { title: 'システム管理' },
    { sub: 'user', label: 'ユーザー', href: 'user_list.html' }
  ];
  var CLOSED_KEY = 'displaySetting:sidebarClosed';
  var GROUPS_KEY = 'displaySetting:sidebarCollapsedGroups';

  function loadJson(key) {
    try { return JSON.parse(localStorage.getItem(key)); } catch (e) { return null; }
  }
  function saveJson(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) {}
  }

  var slot = document.getElementById('sidebar-slot');
  var app = document.querySelector('.app');
  if (!slot || !app) return;
  var activeKey = slot.getAttribute('data-active') || '';
  var activeSub = slot.getAttribute('data-sub') || '';

  var html = '<button type="button" class="sidebar-toggle" aria-label="サイドバーの開閉">☰</button>' +
    '<div class="logo" id="resetStorage" data-tip="保存データを初期化します">研修管理<br>システム</div>';
  var allowed = Access.allowedHrefs();
  var shown = [];
  var pendingTitle = null;
  ITEMS.forEach(function (it) {
    if (it.title) {
      pendingTitle = it;
      return;
    }
    if (allowed && allowed.indexOf(it.href) === -1) return;
    if (pendingTitle) {
      shown.push(pendingTitle);
      pendingTitle = null;
    }
    shown.push(it);
  });
  shown.forEach(function (it) {
    if (it.title) {
      html += '<div class="nav-group-title">' + it.title + '</div>';
    } else if (it.key) {
      html += '<a class="nav-item ' + (it.key === activeKey ? 'active' : 'disabled') + '" data-key="' + it.key + '" href="' + it.href + '">' + it.label + '</a>';
    } else {
      html += '<a class="nav-item ' + (it.sub === activeSub ? 'active' : 'disabled') + '" data-sub="' + it.sub + '" href="' + it.href + '">' + it.label + '</a>';
    }
  });

  var sidebar = document.createElement('div');
  sidebar.className = 'sidebar';
  sidebar.innerHTML = html;
  slot.parentNode.replaceChild(sidebar, slot);

  if (loadJson(CLOSED_KEY) === true || localStorage.getItem(CLOSED_KEY) === '1') app.classList.add('sidebar-closed');

  sidebar.querySelector('.sidebar-toggle').addEventListener('click', function () {
    app.classList.toggle('sidebar-closed');
    try { localStorage.setItem(CLOSED_KEY, app.classList.contains('sidebar-closed') ? '1' : '0'); } catch (e) {}
  });

  sidebar.querySelector('#resetStorage').addEventListener('click', function () {
    if (!confirm('保存されたデータをすべて消去して、初期状態に戻します。よろしいですか？')) return;
    try { localStorage.clear(); } catch (e) {}
    location.reload();
  });

  function setGroup(title, collapsed) {
    title.classList.toggle('collapsed', collapsed);
    var el = title.nextElementSibling;
    while (el && !el.classList.contains('nav-group-title')) {
      el.classList.toggle('acc-hidden', collapsed);
      el = el.nextElementSibling;
    }
  }
  function collapsedNames() {
    return Array.prototype.slice.call(sidebar.querySelectorAll('.nav-group-title.collapsed'))
      .map(function (t) { return t.textContent.trim(); });
  }
  var savedGroups = loadJson(GROUPS_KEY);
  sidebar.querySelectorAll('.nav-group-title').forEach(function (title) {
    var name = title.textContent.trim();
    setGroup(title, !Array.isArray(savedGroups) || savedGroups.indexOf(name) >= 0);
    title.addEventListener('click', function () {
      setGroup(title, !title.classList.contains('collapsed'));
      saveJson(GROUPS_KEY, collapsedNames());
    });
  });
})();
