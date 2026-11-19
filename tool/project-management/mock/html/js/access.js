(function () {
  var MENU_BY_PAIR = {
    '案件/管理': ['project_list.html', 'project_progress_list.html'],
    '案件/実施': ['project_progress_list.html'],
    'クラス/管理': ['course_list.html', 'class_list.html', 'vender_assign_list.html', 'class_progress_list.html'],
    'クラス/実施': ['class_progress_list.html']
  };

  function allowedHrefs() {
    if (sessionStorage.getItem('loginUserCode') === null) return [];
    if (sessionStorage.getItem('loginIsAdmin') === '1') return null;
    var roleNames = JSON.parse(sessionStorage.getItem('loginRoleNames') || '[]');
    var jobNames = JSON.parse(sessionStorage.getItem('loginJobNames') || '[]');
    var allowed = [];
    roleNames.forEach(function (r) {
      jobNames.forEach(function (j) {
        (MENU_BY_PAIR[r + '/' + j] || []).forEach(function (h) {
          if (allowed.indexOf(h) === -1) allowed.push(h);
        });
      });
    });
    return allowed;
  }

  function listPageOf(page) {
    return page.replace(/_(regist|modify|copy|import|export|request_modify)\.html$/, '_list.html');
  }

  function deny(message) {
    sessionStorage.setItem('afterLogin', location.href);
    var toLogin = function () { location.href = 'login.html'; };
    if (window.MessageDialog) {
      MessageDialog.show(message, toLogin);
    } else {
      alert(message);
      toLogin();
    }
  }

  function pageName(href) {
    return href.split('?')[0].split('#')[0].split('/').pop() || 'index.html';
  }

  function denialMessage() {
    var page = pageName(location.href);
    if (page === 'login.html') return '';
    if (sessionStorage.getItem('loginUserCode') === null) return 'ログインしてください';
    var allowed = allowedHrefs();
    if (!allowed) return '';
    if (allowed.indexOf(listPageOf(page)) !== -1) return '';
    return 'この画面を表示する権限がありません';
  }

  function canOpen(href) {
    var allowed = allowedHrefs();
    return !allowed || allowed.indexOf(listPageOf(pageName(href))) !== -1;
  }

  var FIRST_ORDER = ['project_list.html', 'project_progress_list.html', 'course_list.html', 'class_list.html', 'vender_assign_list.html', 'class_progress_list.html', 'subject_list.html', 'location_list.html', 'customer_list.html', 'teacher_vender_list.html', 'staff_vender_list.html', 'staff_list.html', 'task_list.html', 'user_list.html'];

  function firstPage() {
    var allowed = allowedHrefs();
    return FIRST_ORDER.filter(function (h) { return !allowed || allowed.indexOf(h) !== -1; })[0] || null;
  }

  var denied = denialMessage();
  if (denied) document.documentElement.classList.add('access-denied');

  window.Access = { allowedHrefs: allowedHrefs, canOpen: canOpen, firstPage: firstPage };
  if (denied) document.addEventListener('DOMContentLoaded', function () { deny(denied); });
})();
