(function () {
  var C = ClassStore.COURSES;
  var body = $('updateBody');
  var rows = [];
  var KEY = { requesting: 'REQUESTING', before: 'BEFORE', open: 'OPEN' };
  function labelOf(state) { return SlotStatusStore.nameOf(KEY[state]); }

  function applyOptions() {
    $('requestVendor').setAttribute('data-options', TeacherVenderStore.activeNames().join(','));
  }
  applyOptions();

  function vendorCode() {
    return TeacherVenderStore.codeOf(placeholderToEmpty(ownText($('requestVendor'))));
  }

  function requestsFor(a, code, role) {
    var fromRequests = VenderAssignStore.requestsOf(a).filter(function (q) { return code && q.vendor === code; })
      .reduce(function (t, q) { return t + (q[role] || 0); }, 0);
    var named = (role === 'sub' ? (a.subs || []) : role === 'special' ? (a.specials || []) : (a.mains || [])).filter(function (p) { return code && p.vendor === code && p.state === 'requesting'; }).length;
    return fromRequests + named;
  }

  function stateOf(a, code) {
    if (!code) return 'open';
    if (requestsFor(a, code, 'main') + requestsFor(a, code, 'sub') + requestsFor(a, code, 'special') > 0) return 'requesting';
    var has = (a.mains || []).concat(a.subs || [], a.specials || []).some(function (p) { return p.state === 'before' && p.vendor === code; });
    return has ? 'before' : 'open';
  }


  ClassStore.load().filter(function (r) {
    return r.status !== OperatingStatusStore.nameOf('STOPPED') && ClassStore.practiceStatus(r) !== PracticeStatusStore.nameOf('AFTER');
  }).forEach(function (r) {
    rows.push({ cls: r, assign: VenderAssignStore.find(r.id) });
  });

  function findRow(tr) {
    return rows.filter(function (q) { return String(q.cls.id) === tr.getAttribute('data-id'); })[0];
  }

  function render() {
    var code = vendorCode();
    var kw = ($('keyword').value || '').trim().toLowerCase();
    var practiceVal = placeholderToEmpty(ownText($('practiceFilter'))) || 'すべて';
    var df = placeholderToEmpty(ownText($('dateFrom'))), dt = placeholderToEmpty(ownText($('dateTo')));
    var inRange = function (v, from, to) { if (from && (!v || v < from)) return false; if (to && (!v || v > to)) return false; return true; };
    var dateMatch = function (start, end) { if (!df && !dt) return true; return inRange(start, df, dt) || inRange(end, df, dt); };
    body.innerHTML = '';
    rows.filter(function (x) {
      if (practiceVal !== 'すべて' && ClassStore.practiceStatus(x.cls) !== practiceVal) return false;
      if (!dateMatch(x.cls.start, x.cls.end)) return false;
      var planM = parseInt(x.cls.mainTeachers, 10) || 0;
      var planS = parseInt(x.cls.subTeachers, 10) || 0;
      var doneM = x.assign.mains.filter(function (p) { return p.state === 'done'; }).length;
      var doneS = x.assign.subs.filter(function (p) { return p.state === 'done'; }).length;
      var planSp = parseInt(x.cls.specialTeachers, 10) || 0;
      var doneSp = (x.assign.specials || []).filter(function (p) { return p.state === 'done'; }).length;
      if (planM === doneM && planS === doneS && planSp === doneSp) return false;
      if (!kw) return true;
      var c = C[x.cls.courseCode] || { name: '' };
      return (String(x.cls.courseCode) + ' ' + String(c.name || '')).toLowerCase().indexOf(kw) >= 0;
    }).forEach(function (x) {
      var cur = stateOf(x.assign, code);
      var teacherLines = VenderLines.build(x.cls, code);
      var c = C[x.cls.courseCode] || { name: x.cls.courseCode };
      var tr = document.createElement('tr');
      tr.setAttribute('data-id', x.cls.id);
      tr.setAttribute('data-state', cur);
      tr.innerHTML =
        '<td class="vender-assign-center"><label class="check-box check-sm"><input type="checkbox" class="row-check" checked><span class="check-mark"></span></label></td>' +
        '<td>' + esc(yearLabel(x.cls.year)) + '</td>' +
        '<td><div>' + esc(c.name) + '</div><div class="vender-assign-sub">' + esc(x.cls.courseCode) + '</div></td>' +
        '<td><div>' + esc(x.cls.lessonNo) + '</div></td>' +
        '<td>' + esc(x.cls.start) + '</td>' +
        '<td>' + esc(x.cls.end) + '</td>' +
        '<td>' + dashOr(classDays(x.cls), '日') + '</td>' +
        '<td>' + dashOr(x.cls.mainTeachers, '人') + '</td>' +
        '<td>' + teacherLines.main + '</td>' +
        '<td>' + dashOr(x.cls.subTeachers, '人') + '</td>' +
        '<td>' + teacherLines.sub + '</td>' +
        '<td>' + dashOr(x.cls.specialTeachers, '人') + '</td>' +
        '<td>' + teacherLines.special + '</td>';
      body.appendChild(tr);
    });
    $('updateCount').textContent = body.querySelectorAll('tr').length;
    syncSelToggle();
  }

  function apply(a, code, from, to, cls) {
    if (to === 'open' || to === 'before') {
      VenderAssignChange.apply(a, code, to, cls);
    }
  }

  function syncSelToggle() {
    var boxes = Array.prototype.map.call(body.querySelectorAll('.row-check'), function (cb) { return cb.checked; });
    var allOn = boxes.length > 0 && boxes.every(function (v) { return v; });
    document.querySelector('.sel-toggle').classList.toggle('off', !allOn);
  }
  document.querySelector('.sel-toggle').addEventListener('click', function () {
    var on = document.querySelector('.sel-toggle').classList.contains('off');
    Array.prototype.forEach.call(body.querySelectorAll('.row-check'), function (cb) { cb.checked = on; });
    syncSelToggle();
  });
  body.addEventListener('change', function (e) {
    if (e.target.classList.contains('row-check')) syncSelToggle();
  });
  var lastPractice = placeholderToEmpty(ownText($('practiceFilter'))) || 'すべて';
  document.addEventListener('click', function () {
    setTimeout(function () {
      var p = placeholderToEmpty(ownText($('practiceFilter'))) || 'すべて';
      if (p !== lastPractice) { lastPractice = p; render(); }
    }, 0);
  }, true);
  $('requestVendor').addEventListener('click', function () { setTimeout(render, 0); }, true);
  document.querySelector('.filter-panel .nav-btn').addEventListener('click', render);
  $('keyword').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') document.querySelector('.filter-panel .nav-btn').click();
  });

  $('saveBtn').addEventListener('click', function () {
    var code = vendorCode();
    var name = placeholderToEmpty(ownText($('requestVendor')));
    if (!code) {
      MessageDialog.required(['講師ベンダー']);
      return;
    }
    if (!placeholderToEmpty(ownText($('bulkState')))) {
      MessageDialog.required(['変更後の状態']);
      return;
    }
    var changes = [];
    Array.prototype.forEach.call(body.querySelectorAll('tr'), function (tr) {
      var from = tr.getAttribute('data-state');
      var cb = tr.querySelector('.row-check');
      var bulkLabel = placeholderToEmpty(ownText($('bulkState')));
      var bulkTo = bulkLabel ? (bulkLabel === SlotStatusStore.nameOf('OPEN') ? 'open' : 'before') : '';
      var to = cb && cb.checked && bulkTo ? bulkTo : from;
      var hasFree = to === 'before' && ['main', 'sub', 'special'].some(function (role) {
        var x = findRow(tr);
        return x && VenderAssignChange.freeOf(x.assign, x.cls, role) > 0;
      });
      if (from !== to || hasFree) changes.push({ tr: tr, from: from, to: to });
    });
    if (!changes.length) {
      MessageDialog.show('状態を変更する依頼がありません');
      return;
    }
    var lines = changes.map(function (ch) {
      var x = findRow(ch.tr);
      var cc = C[x.cls.courseCode] || { name: x.cls.courseCode };
      return '・' + x.cls.courseCode + '　' + cc.name + '　' + x.cls.lessonNo + String.fromCharCode(10) + '　' + labelOf(ch.from) + ' → ' + labelOf(ch.to);
    });
    MessageDialog.confirm(['以下に変更してよろしいですか？'].concat(lines).join(String.fromCharCode(10))).then(function (ok) {
      if (!ok) return;
      changes.forEach(function (ch) {
        var x = findRow(ch.tr);
        apply(x.assign, code, ch.from, ch.to, x.cls);
        VenderAssignStore.upsert(x.assign);
      });
      location.href = 'vender_assign_list.html';
    });
  });

  render();
})();
