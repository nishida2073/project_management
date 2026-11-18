(function () {
  var C = ClassStore.COURSES;
  var body = $('withdrawBody');
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
    var named = (role === 'sub' ? (a.subs || []) : (a.mains || [])).filter(function (p) { return code && p.vendor === code && p.state === 'requesting'; }).length;
    return fromRequests + named;
  }

  function stateOf(a, code) {
    if (!code) return 'open';
    if (requestsFor(a, code, 'main') + requestsFor(a, code, 'sub') > 0) return 'requesting';
    var has = (a.mains || []).concat(a.subs || []).some(function (p) { return p.state === 'before' && p.vendor === code; });
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
      if (planM === doneM && planS === doneS) return false;
      if (!kw) return true;
      var c = C[x.cls.courseCode] || { name: '' };
      return (String(x.cls.courseCode) + ' ' + String(c.name || '')).toLowerCase().indexOf(kw) >= 0;
    }).forEach(function (x) {
      var cur = stateOf(x.assign, code);
      var c = C[x.cls.courseCode] || { name: x.cls.courseCode };
      var tr = document.createElement('tr');
      tr.setAttribute('data-id', x.cls.id);
      tr.setAttribute('data-state', cur);
      var namedMain = x.assign.mains.filter(function (p) { return p.state === 'done'; }).length;
      var befSel = code ? x.assign.mains.filter(function (p) { return p.state === 'before' && p.vendor === code; }).length : 0;
      var midN = code ? requestsFor(x.assign, code, 'main') : 0;
      var doneSel = code ? x.assign.mains.filter(function (p) { return p.state === 'done' && p.vendor === code; }).length : 0;
      var namedSub = x.assign.subs.filter(function (p) { return p.state === 'done'; }).length;
      var befSubSel = code ? x.assign.subs.filter(function (p) { return p.state === 'before' && p.vendor === code; }).length : 0;
      var midSubN = code ? requestsFor(x.assign, code, 'sub') : 0;
      var doneSubSel = code ? x.assign.subs.filter(function (p) { return p.state === 'done' && p.vendor === code; }).length : 0;
      tr.innerHTML =
        '<td class="vender-assign-center"><label class="check-box"><input type="checkbox" class="row-check" checked><span class="check-mark"></span></label></td>' +
        '<td>' + esc(yearLabel(x.cls.year)) + '</td>' +
        '<td><div>' + esc(c.name) + '</div><div class="vender-assign-sub">' + esc(x.cls.courseCode) + '</div></td>' +
        '<td><div>' + esc(x.cls.lessonNo) + '</div></td>' +
        '<td>' + esc(x.cls.start) + '</td>' +
        '<td>' + esc(x.cls.end) + '</td>' +
        '<td>' + dashOr(x.cls.mainTeachers, '人') + '</td>' +
        '<td>' + namedMain + '人</td>' +
        '<td><div class="vender-assign-count-cell">' +
          '<span class="vender-assign-count-before">' + (code ? befSel + '人' : '-') + '</span>' +
          '<span class="vender-assign-count-requesting">' + (code ? midN + '人' : '-') + '</span>' +
          '<span class="vender-assign-count-done">' + (code ? doneSel + '人' : '-') + '</span>' +
        '</div></td>' +
        '<td>' + dashOr(x.cls.subTeachers, '人') + '</td>' +
        '<td>' + namedSub + '人</td>' +
        '<td><div class="vender-assign-count-cell">' +
          '<span class="vender-assign-count-before">' + (code ? befSubSel + '人' : '-') + '</span>' +
          '<span class="vender-assign-count-requesting">' + (code ? midSubN + '人' : '-') + '</span>' +
          '<span class="vender-assign-count-done">' + (code ? doneSubSel + '人' : '-') + '</span>' +
        '</div></td>';
      body.appendChild(tr);
    });
    $('withdrawCount').textContent = body.querySelectorAll('tr').length;
    syncSelToggle();
  }

  function apply(a, code, from, to) {
    if (to === 'open') {
      a.requests = VenderAssignStore.requestsOf(a).filter(function (q) { return q.vendor !== code; });
      a.mains = (a.mains || []).filter(function (p) { return !((p.state === 'before' || p.state === 'requesting') && p.vendor === code); });
      a.subs = (a.subs || []).filter(function (p) { return !((p.state === 'before' || p.state === 'requesting') && p.vendor === code); });
    } else if (to === 'before') {
      if (from === 'requesting') {
        var mainN = requestsFor(a, code, 'main');
        var subN = requestsFor(a, code, 'sub');
        for (var i = 0; i < mainN; i++) a.mains.push({ vendor: code, teacherName: '', state: 'before' });
        for (var j = 0; j < subN; j++) a.subs.push({ vendor: code, teacherName: '', state: 'before' });
        a.requests = VenderAssignStore.requestsOf(a).filter(function (q) { return q.vendor !== code; });
      } else if (from === 'open') {
        a.mains = (a.mains || []).concat([{ vendor: code, teacherName: '', state: 'before' }]);
      }
    }
    delete a.requested;
    delete a.requestMain;
    delete a.requestSub;
    delete a.requestVendor;
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
  document.querySelector('.filter-panel .search-btn').addEventListener('click', render);
  $('keyword').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') document.querySelector('.filter-panel .search-btn').click();
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
      if (from !== to) changes.push({ tr: tr, from: from, to: to });
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
        apply(x.assign, code, ch.from, ch.to);
        VenderAssignStore.upsert(x.assign);
      });
      location.href = 'vender_assign_list.html';
    });
  });

  render();
})();
