(function () {
  var C = ClassStore.COURSES;
  var body = $('withdrawBody');
  var rows = [];
  var LABEL = { requesting: '依頼中', before: '依頼前', open: '依頼枠' };
  var TAG = { requesting: 'blue', before: 'orange', open: 'gray' };

  $('requestVendor').setAttribute('data-options', TeacherVenderStore.activeNames().join(','));

  function vendorCode() {
    return TeacherVenderStore.codeOf(placeholderToEmpty(ownText($('requestVendor'))));
  }

  function requestsFor(a, code, role) {
    return VenderAssignStore.requestsOf(a).filter(function (q) { return code && q.vendor === code; })
      .reduce(function (t, q) { return t + (q[role] || 0); }, 0);
  }

  function stateOf(a, code) {
    if (!code) return 'open';
    if (requestsFor(a, code, 'main') + requestsFor(a, code, 'sub') > 0) return 'requesting';
    var has = (a.mains || []).concat(a.subs || []).some(function (p) { return p.vendor === code && !p.teacherName; });
    return has ? 'before' : 'open';
  }


  ClassStore.load().filter(function (r) {
    return r.status !== '停止中' && ClassStore.practiceStatus(r) !== '実施後';
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
      var doneM = x.assign.mains.filter(function (p) { return p.teacherName; }).length;
      var doneS = x.assign.subs.filter(function (p) { return p.teacherName; }).length;
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
      var namedMain = x.assign.mains.filter(function (p) { return p.teacherName; }).length;
      var befSel = code ? x.assign.mains.filter(function (p) { return p.vendor === code && !p.teacherName; }).length : 0;
      var midN = code ? requestsFor(x.assign, code, 'main') : 0;
      var doneSel = code ? x.assign.mains.filter(function (p) { return p.teacherName && p.vendor === code; }).length : 0;
      var namedSub = x.assign.subs.filter(function (p) { return p.teacherName; }).length;
      var befSubSel = code ? x.assign.subs.filter(function (p) { return p.vendor === code && !p.teacherName; }).length : 0;
      var midSubN = code ? requestsFor(x.assign, code, 'sub') : 0;
      var doneSubSel = code ? x.assign.subs.filter(function (p) { return p.teacherName && p.vendor === code; }).length : 0;
      tr.innerHTML =
        '<td style="text-align:center;"><label class="check-box"><input type="checkbox" class="row-check" checked><span class="check-mark"></span></label></td>' +
        '<td>' + esc(yearLabel(x.cls.year)) + '</td>' +
        '<td><div style="font-weight:700;">' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(x.cls.courseCode) + '</div></td>' +
        '<td><div style="font-weight:700;">' + esc(x.cls.lessonNo) + '</div></td>' +
        '<td>' + esc(x.cls.start) + '</td>' +
        '<td>' + esc(x.cls.end) + '</td>' +
        '<td>' + dashOr(x.cls.mainTeachers, '人') + '</td>' +
        '<td>' + namedMain + '人</td>' +
        '<td><div style="display:flex;align-items:center;gap:6px;white-space:nowrap;">' +
          '<span style="color:#d97c1e;font-size:12.5px;">' + (code ? befSel + '人' : '-') + '</span>' +
          '<span style="color:#2f6fed;font-size:12.5px;">' + (code ? midN + '人' : '-') + '</span>' +
          '<span style="color:#2f8a5b;font-size:12.5px;">' + (code ? doneSel + '人' : '-') + '</span>' +
        '</div></td>' +
        '<td>' + dashOr(x.cls.subTeachers, '人') + '</td>' +
        '<td>' + namedSub + '人</td>' +
        '<td><div style="display:flex;align-items:center;gap:6px;white-space:nowrap;">' +
          '<span style="color:#d97c1e;font-size:12.5px;">' + (code ? befSubSel + '人' : '-') + '</span>' +
          '<span style="color:#2f6fed;font-size:12.5px;">' + (code ? midSubN + '人' : '-') + '</span>' +
          '<span style="color:#2f8a5b;font-size:12.5px;">' + (code ? doneSubSel + '人' : '-') + '</span>' +
        '</div></td>';
      body.appendChild(tr);
    });
    $('withdrawCount').textContent = body.querySelectorAll('tr').length;
    syncSelToggle();
  }

  function apply(a, code, from, to) {
    if (to === 'open') {
      a.requests = VenderAssignStore.requestsOf(a).filter(function (q) { return q.vendor !== code; });
      a.mains = (a.mains || []).filter(function (p) { return !(p.vendor === code && !p.teacherName); });
      a.subs = (a.subs || []).filter(function (p) { return !(p.vendor === code && !p.teacherName); });
    } else if (to === 'before') {
      if (from === 'requesting') {
        var mainN = requestsFor(a, code, 'main');
        var subN = requestsFor(a, code, 'sub');
        for (var i = 0; i < mainN; i++) a.mains.push({ vendor: code, teacherName: '' });
        for (var j = 0; j < subN; j++) a.subs.push({ vendor: code, teacherName: '' });
        a.requests = VenderAssignStore.requestsOf(a).filter(function (q) { return q.vendor !== code; });
      } else if (from === 'open') {
        a.mains = (a.mains || []).concat([{ vendor: code, teacherName: '' }]);
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
    $('selToggle').classList.toggle('off', !allOn);
  }
  $('selToggle').addEventListener('click', function () {
    var on = $('selToggle').classList.contains('off');
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
      var bulkTo = bulkLabel ? (bulkLabel === '依頼枠' ? 'open' : 'before') : '';
      var to = cb && cb.checked && bulkTo ? bulkTo : from;
      if (from !== to) changes.push({ tr: tr, from: from, to: to });
    });
    if (!changes.length) {
      MessageDialog.show('状態を変更してください');
      return;
    }
    var lines = changes.map(function (ch) {
      var x = findRow(ch.tr);
      var cc = C[x.cls.courseCode] || { name: x.cls.courseCode };
      return '・' + x.cls.courseCode + '　' + cc.name + '　' + x.cls.lessonNo + String.fromCharCode(10) + '　' + LABEL[ch.from] + ' → ' + LABEL[ch.to];
    });
    MessageDialog.confirm(['依頼枠の状態を変更します。', '以下に変更してよろしいですか？'].concat(lines).join(String.fromCharCode(10))).then(function (ok) {
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
