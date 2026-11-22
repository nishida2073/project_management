(function () {

  var C = ClassStore.COURSES;
  var list = ClassStore.load().filter(function (r) { return r.status !== OperatingStatusStore.nameOf('STOPPED') && ClassStore.practiceStatus(r) !== PracticeStatusStore.nameOf('AFTER'); });
  var body = $('printBody');
  var rows = [];

  list.forEach(function (r) {
    var a = VenderAssignStore.find(r.id);
    rows.push({ cls: r, assign: a });
    var c = C[r.courseCode] || { name: r.courseCode };
    var namedMain = a.mains.filter(function (p) { return p.state === 'done'; }).length;
    var namedSub = a.subs.filter(function (p) { return p.state === 'done'; }).length;
    var remainMain = Math.max(0, (parseInt(r.mainTeachers, 10) || 0) - namedMain);
    var remainSub = Math.max(0, (parseInt(r.subTeachers, 10) || 0) - namedSub);
    var tr = document.createElement('tr');
    tr.setAttribute('data-id', r.id);
    tr.setAttribute('data-practice', ClassStore.practiceStatus(r));
    tr.setAttribute('data-start', r.start || '');
    tr.setAttribute('data-end', r.end || '');
    var fits = remainMain === 0 && remainSub === 0;
    tr.setAttribute('data-fit', fits ? 'in' : 'over');
    tr.setAttribute('data-remain-main', remainMain);
    tr.setAttribute('data-remain-sub', remainSub);
    var teacherLines = VenderLines.build(r, '');
    tr.innerHTML =
      '<td class="sticky vender-assign-center"><label class="check-box"><input type="checkbox" class="row-check" checked><span class="check-mark"></span></label></td>' +
      '<td class="sticky">' + esc(yearLabel(r.year)) + '</td>' +
      '<td class="sticky col-course"><div>' + esc(c.name) + '</div><div class="vender-assign-sub">' + esc(r.courseCode) + '</div></td>' +
      '<td class="sticky"><div>' + esc(r.lessonNo) + '</div></td>' +
      '<td class="sticky">' + esc(r.start) + '</td>' +
      '<td class="sticky">' + esc(r.end) + '</td>' +
      '<td>' + dashOr(classDays(r), '日') + '</td>' +
      '<td>' + dashOr(r.mainTeachers, '人') + '</td>' +
      '<td>' + teacherLines.main + '</td>' +
      '<td>' + dashOr(r.subTeachers, '人') + '</td>' +
      '<td>' + teacherLines.sub + '</td>' +
      '<td>' + dashOr(r.specialTeachers, '人') + '</td>' +
      '<td>' + teacherLines.special + '</td>';
    body.appendChild(tr);
  });

  $('printCount').textContent = list.length;
  function applyOptions() {
    $('requestVendor').setAttribute('data-options', TeacherVenderStore.activeNames().join(','));
  }
  applyOptions();

  function applyFilter() {
    var kw = $('keyword').value.trim().toLowerCase();
    var fitVal = placeholderToEmpty(ownText($('fitFilter'))) || 'すべて';
    var practiceVal = placeholderToEmpty(ownText($('practiceFilter'))) || 'すべて';
    var df = placeholderToEmpty(ownText($('dateFrom'))), dt = placeholderToEmpty(ownText($('dateTo')));
    var inRange = function (v, from, to) { if (from && (!v || v < from)) return false; if (to && (!v || v > to)) return false; return true; };
    var dateMatch = function (start, end) { if (!df && !dt) return true; return inRange(start, df, dt) || inRange(end, df, dt); };
    var visible = 0;
    body.querySelectorAll('tr').forEach(function (tr) {
      var course = tr.querySelector('.col-course').textContent.toLowerCase();
      var beforeName = SlotStatusStore.nameOf('BEFORE');
      var hasBefore = Array.prototype.some.call(tr.querySelectorAll('.state-tag'), function (t) { return t.textContent === beforeName; });
      var canRequest = tr.querySelectorAll('[data-vendor=""]').length > 0 || hasBefore;
      var fitOk = fitVal === 'すべて' || (fitVal === 'あり') === canRequest;
      var practiceOk = practiceVal === 'すべて' || tr.getAttribute('data-practice') === practiceVal;
      var dateOk = dateMatch(tr.getAttribute('data-start'), tr.getAttribute('data-end'));
      var ok = (!kw || course.indexOf(kw) !== -1) && fitOk && practiceOk && dateOk;
      tr.style.display = ok ? '' : 'none';
      if (ok) visible++;
    });
    $('printCount').textContent = visible;
  }
  document.querySelector('.filter-panel .nav-btn').addEventListener('click', applyFilter);
  $('keyword').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') document.querySelector('.filter-panel .nav-btn').click();
  });
  applyFilter();

  var appliedVendor = null;
  var includePendSel = true;
  function countChecked(tr, role) {
    return tr.querySelectorAll('.export-check[data-role="' + role + '"]:checked').length;
  }
  function eachCheck(tr, fn) {
    var n = { main: 0, sub: 0 };
    tr.querySelectorAll('.export-check').forEach(function (cb) {
      if (cb.hasAttribute('data-pending')) return;
      var key = cb.getAttribute('data-key');
      if (!key) {
        var role = cb.getAttribute('data-role');
        key = role + n[role];
        n[role]++;
      }
      fn(cb, key);
    });
  }
  function checkState(tr) {
    var map = {};
    eachCheck(tr, function (cb, key) { map[key] = cb.checked; });
    return map;
  }
  function restoreChecks(tr, map) {
    eachCheck(tr, function (cb, key) { if (key in map) cb.checked = map[key]; });
  }
  function applyVendor() {
    var code = TeacherVenderStore.codeOf(placeholderToEmpty(ownText($('requestVendor'))));
    body.querySelectorAll('tr').forEach(function (tr) {
      var id = tr.getAttribute('data-id');
      var row = rows.filter(function (x) { return x.cls.id === id; })[0];
      if (!row) return;
      var saved = checkState(tr);
      var teacherCells = VenderLines.build(row.cls, code, { check: !!code, includePend: includePendSel });
      tr.children[8].innerHTML = teacherCells.main;
      tr.children[10].innerHTML = teacherCells.sub;
      tr.children[12].innerHTML = teacherCells.special;
      restoreChecks(tr, saved);
    });
  }
  function syncVendor() {
    var v = placeholderToEmpty(ownText($('requestVendor')));
    if (v === appliedVendor) return;
    appliedVendor = v;
    applyVendor();
  }
  syncVendor();
  Array.prototype.forEach.call(document.querySelectorAll('#pendSelSeg .seg-opt'), function (btn) {
    btn.addEventListener('click', function () {
      includePendSel = btn.getAttribute('data-v') === 'in';
      Array.prototype.forEach.call(document.querySelectorAll('#pendSelSeg .seg-opt'), function (b2) { b2.classList.toggle('is-active', b2 === btn); });
      appliedVendor = null;
      syncVendor();
      setTimeout(function () { var search = document.querySelector('.filter-panel .nav-btn'); if (search) search.click(); }, 0);
    });
  });
  document.addEventListener('click', function () { setTimeout(syncVendor, 0); }, true);

  function visibleRows() {
    return Array.prototype.filter.call(body.querySelectorAll('tr'), function (tr) { return tr.style.display !== 'none'; });
  }
  function syncSelToggle() {
    var rows = visibleRows();
    var allOn = rows.length > 0 && rows.every(function (tr) { return tr.querySelector('.row-check').checked; });
    document.querySelector('.sel-toggle').classList.toggle('off', !allOn);
  }
  document.querySelector('.sel-toggle').addEventListener('click', function () {
    var on = document.querySelector('.sel-toggle').classList.contains('off');
    visibleRows().forEach(function (tr) { tr.querySelector('.row-check').checked = on; });
    syncSelToggle();
  });
  body.addEventListener('change', function (e) {
    if (e.target.classList.contains('row-check')) syncSelToggle();
  });

  function runExport() {
    var vendor = placeholderToEmpty(ownText($('requestVendor')));
    var vendorCode = TeacherVenderStore.codeOf(vendor);
    if (!vendor) {
      MessageDialog.required(['講師ベンダー']);
      return;
    }
    var ROLES = ['main', 'sub', 'special'];
    var LABEL = { main: 'メイン', sub: 'サブ', special: '特別' };
    var KEY = { main: 'mains', sub: 'subs', special: 'specials' };
    function countsOf(tr) {
      var c = {};
      ROLES.forEach(function (role) { c[role] = countChecked(tr, role); });
      return c;
    }
    var checkedCount = Array.prototype.filter.call(body.querySelectorAll('tr'), function (tr) {
      if (tr.style.display === 'none') return false;
      if (!tr.querySelector('.row-check') || !tr.querySelector('.row-check').checked) return false;
      var c = countsOf(tr);
      return c.main > 0 || c.sub > 0 || c.special > 0;
    }).length;
    if (!checkedCount) {
      MessageDialog.show('依頼するクラスの空き枠または依頼中を選択してください');
      return;
    }
    var items = [];
    var exportedIds = [];
    body.querySelectorAll('tr').forEach(function (tr) {
      if (tr.style.display === 'none') return;
      if (!tr.querySelector('.row-check').checked) return;
      var id = tr.getAttribute('data-id');
      var row = rows.filter(function (x) { return x.cls.id === id; })[0];
      if (!row) return;
      var c = countsOf(tr);
      exportedIds.push({ id: id, counts: c });
      var a = Object.assign({}, row.assign, { mainCount: c.main, subCount: c.sub, specialCount: c.special });
      VenderAssignStore.upsert(a);
      if (c.main || c.sub || c.special) items.push({ cls: row.cls, assign: a, counts: c });
    });
    var maxOf = {};
    ROLES.forEach(function (role) {
      maxOf[role] = 0;
      items.forEach(function (it) { maxOf[role] = Math.max(maxOf[role], it.counts[role]); });
    });
    if (items.some(function (it) { return it.cls.specialMemo; })) maxOf.special = Math.max(maxOf.special, 1);
    var header = ['年度', 'コース名', 'コースコード', 'レッスンNo', '開始日', '終了日', '日数'];
    var teacherStart = header.length;
    var i;
    function zen(n) { return String.fromCharCode(0xFF10 + n); }
    ROLES.forEach(function (role) {
      for (i = 1; i <= maxOf[role]; i++) header.push('講師（' + LABEL[role] + zen(i) + '）');
    });
    var aoa = [['講師ベンダー', vendor], [], header];
    items.forEach(function (it) {
      var c = C[it.cls.courseCode] || { name: it.cls.courseCode };
      var line = [
        (yearLabel(it.cls.year)),
        c.name,
        it.cls.courseCode,
        it.cls.lessonNo,
        it.cls.start,
        it.cls.end,
        classDays(it.cls)
      ];
      var namesOf = function (list) {
        return (list || []).filter(function (p) { return p.state === 'before' && p.vendor === vendorCode && p.teacherName; }).map(function (p) { return p.teacherName; });
      };
      ROLES.forEach(function (role) {
        var names = namesOf(it.assign[KEY[role]]);
        for (var k = 0; k < maxOf[role]; k++) line.push(names[k] || '');
      });
      aoa.push(line);
    });
    var ws = XLSX.utils.aoa_to_sheet(aoa);
    var GRAY = { fill: { patternType: 'solid', fgColor: { rgb: 'D9D9D9' } } };
    items.forEach(function (it, ri) {
      var col = teacherStart;
      ROLES.forEach(function (role) {
        for (var k = 0; k < maxOf[role]; k++) {
          if (k >= it.counts[role]) {
            var addr = XLSX.utils.encode_cell({ r: ri + 3, c: col });
            if (!ws[addr]) ws[addr] = { t: 's', v: '' };
            ws[addr].s = GRAY;
          }
          col++;
        }
      });
    });
    var specialStart = teacherStart + maxOf.main + maxOf.sub;
    items.forEach(function (it, ri) {
      if (!it.cls.specialMemo || !maxOf.special) return;
      var addr = XLSX.utils.encode_cell({ r: ri + 3, c: specialStart });
      if (!ws[addr]) ws[addr] = { t: 's', v: '' };
      ws[addr].c = [{ a: '備考', t: it.cls.specialMemo }];
    });
    var HEAD = { font: { bold: true, color: { rgb: 'FFFFFF' } }, fill: { patternType: 'solid', fgColor: { rgb: '1C2B45' } }, alignment: { horizontal: 'center', vertical: 'center', wrapText: true }, border: { top: { style: 'thin', color: { rgb: '8A94A6' } }, bottom: { style: 'thin', color: { rgb: '8A94A6' } }, left: { style: 'thin', color: { rgb: '8A94A6' } }, right: { style: 'thin', color: { rgb: '8A94A6' } } } };
    header.forEach(function (_, ci) {
      var addr = XLSX.utils.encode_cell({ r: 2, c: ci });
      if (!ws[addr]) ws[addr] = { t: 's', v: '' };
      ws[addr].s = HEAD;
    });
    ws['A1'].s = HEAD;
    ws['B1'].s = { border: HEAD.border, alignment: { vertical: 'center' } };
    ws['!cols'] = header.map(function (name, ci) {
      if (ci === 1) return { wch: 32 };
      if (ci === 6) return { wch: 8 };
      if (ci < 6) return { wch: 14 };
      return { wch: 28 };
    });
    ws['!rows'] = [{ hpt: 18 }, {}, { hpt: 18 }];
    Object.keys(ws).forEach(function (k) {
      if (k.charAt(0) === '!') return;
      var cell = ws[k];
      var st = cell.s || {};
      cell.s = Object.assign({}, st, { alignment: Object.assign({}, st.alignment || {}, { vertical: 'center' }) });
    });
    var wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, '登壇依頼');
    XLSX.writeFile(wb, '登壇依頼-' + vendor + '.xlsx');
    exportedIds.forEach(function (x) {
      var rec = VenderAssignStore.find(x.id);
      var existing = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor === vendorCode; });
      var reqs = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor !== vendorCode; });
      var exCount = {};
      ROLES.forEach(function (role) {
        exCount[role] = includePendSel ? 0 : existing.reduce(function (t, r) { return t + (r[role] || 0); }, 0);
      });
      var convertCount = function (role, n) {
        if (!includePendSel) return n;
        var exRole = existing.reduce(function (t, r) { return t + (r[role] || 0); }, 0);
        return Math.max(0, n - exRole);
      };
      var convertEntries = function (list, n) {
        var left = n, named = 0, out = [];
        (list || []).forEach(function (p) {
          if (left > 0 && p.state === 'before' && p.vendor === vendorCode) {
            left--;
            if (p.teacherName) { out.push({ vendor: p.vendor, teacherName: p.teacherName, state: 'requesting' }); named++; }
            return;
          }
          out.push(p);
        });
        return { list: out, named: named };
      };
      var named = {};
      ROLES.forEach(function (role) {
        var conv = convertEntries(rec[KEY[role]], convertCount(role, x.counts[role]));
        rec[KEY[role]] = conv.list;
        named[role] = conv.named;
      });
      var entry = { vendor: vendorCode };
      var any = false;
      ROLES.forEach(function (role) {
        var add = Math.max(0, exCount[role] + x.counts[role] - named[role]);
        entry[role] = add;
        if (add || exCount[role]) any = true;
      });
      if (any) reqs.push(entry);
      rec.requests = reqs;
      delete rec.requested;
      delete rec.requestMain;
      delete rec.requestSub;
      delete rec.requestVendor;
      VenderAssignStore.upsert(rec);
    });
    location.href = 'vender_assign_list.html';
  }
  $('printBtn').addEventListener('click', runExport);
})();
