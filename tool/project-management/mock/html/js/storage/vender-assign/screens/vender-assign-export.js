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
      '<td>' + dashOr(r.mainTeachers, '人') + '</td>' +
      '<td>' + teacherLines.main + '</td>' +
      '<td>' + dashOr(r.subTeachers, '人') + '</td>' +
      '<td>' + teacherLines.sub + '</td>';
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
      var canRequest = tr.querySelectorAll('[data-vendor=""]').length > 0;
      var fitOk = fitVal === 'すべて' || (fitVal === 'あり') === canRequest;
      var practiceOk = practiceVal === 'すべて' || tr.getAttribute('data-practice') === practiceVal;
      var dateOk = dateMatch(tr.getAttribute('data-start'), tr.getAttribute('data-end'));
      var ok = (!kw || course.indexOf(kw) !== -1) && fitOk && practiceOk && dateOk;
      tr.style.display = ok ? '' : 'none';
      if (ok) visible++;
    });
    $('printCount').textContent = visible;
  }
  document.querySelector('.filter-panel .search-btn').addEventListener('click', applyFilter);
  $('keyword').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') document.querySelector('.filter-panel .search-btn').click();
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
      tr.children[7].innerHTML = teacherCells.main;
      tr.children[9].innerHTML = teacherCells.sub;
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
      setTimeout(function () { var search = document.querySelector('.filter-panel .search-btn'); if (search) search.click(); }, 0);
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
    var checkedCount = Array.prototype.filter.call(body.querySelectorAll('tr'), function (tr) {
      if (tr.style.display === 'none') return false;
      if (!tr.querySelector('.row-check') || !tr.querySelector('.row-check').checked) return false;
      return countChecked(tr, 'main') > 0 || countChecked(tr, 'sub') > 0;
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
      var mainCount = countChecked(tr, 'main');
      var subCount = countChecked(tr, 'sub');
      exportedIds.push({ id: id, main: mainCount, sub: subCount });
      var a = Object.assign({}, row.assign, { mainCount: mainCount, subCount: subCount });
      VenderAssignStore.upsert(a);
      if (mainCount || subCount) items.push({ cls: row.cls, assign: a });
    });
    var mainMax = 0, subMax = 0;
    items.forEach(function (it) {
      mainMax = Math.max(mainMax, it.assign.mainCount);
      subMax = Math.max(subMax, it.assign.subCount);
    });
    var header = ['年度', 'コース名', 'コースコード', 'レッスンNo', '開始日', '終了日'];
    var i;
    function zen(n) { return String.fromCharCode(0xFF10 + n); }
    for (i = 1; i <= mainMax; i++) header.push('講師（メイン' + zen(i) + '）');
    for (i = 1; i <= subMax; i++) header.push('講師（サブ' + zen(i) + '）');
    var aoa = [['講師ベンダー', vendor], [], header];
    items.forEach(function (it) {
      var c = C[it.cls.courseCode] || { name: it.cls.courseCode };
      var line = [
        (yearLabel(it.cls.year)),
        c.name,
        it.cls.courseCode,
        it.cls.lessonNo,
        it.cls.start,
        it.cls.end
      ];
      var namesOf = function (list) {
        return (list || []).filter(function (p) { return p.state === 'before' && p.vendor === vendorCode && p.teacherName; }).map(function (p) { return p.teacherName; });
      };
      var mainNames = namesOf(it.assign.mains);
      var subNames = namesOf(it.assign.subs);
      var people = [];
      for (i = 0; i < mainMax; i++) people.push(mainNames[i] || '');
      for (i = 0; i < subMax; i++) people.push(subNames[i] || '');
      aoa.push(line.concat(people));
    });
    var ws = XLSX.utils.aoa_to_sheet(aoa);
    var GRAY = { fill: { patternType: 'solid', fgColor: { rgb: 'D9D9D9' } } };
    items.forEach(function (it, ri) {
      for (var k = 0; k < mainMax + subMax; k++) {
        var used = k < mainMax ? k < it.assign.mainCount : (k - mainMax) < it.assign.subCount;
        if (used) continue;
        var addr = XLSX.utils.encode_cell({ r: ri + 3, c: 6 + k });
        if (!ws[addr]) ws[addr] = { t: 's', v: '' };
        ws[addr].s = GRAY;
      }
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
      var exMain = includePendSel ? 0 : existing.reduce(function (t, r) { return t + (r.main || 0); }, 0);
      var exSub = includePendSel ? 0 : existing.reduce(function (t, r) { return t + (r.sub || 0); }, 0);
      var reqs = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor !== vendorCode; });
      var dropBefore = function (list, n) {
        var left = n;
        return (list || []).filter(function (p) {
          if (left > 0 && p.state === 'before' && p.vendor === vendorCode) { left--; return false; }
          return true;
        });
      };
      var convertCount = function (role, list, n) {
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
      var cm = convertEntries(rec.mains, convertCount('main', rec.mains || [], x.main));
      var cs = convertEntries(rec.subs, convertCount('sub', rec.subs || [], x.sub));
      rec.mains = cm.list;
      rec.subs = cs.list;
      var addM = Math.max(0, exMain + x.main - cm.named);
      var addS = Math.max(0, exSub + x.sub - cs.named);
      if (addM || addS || exMain || exSub) reqs.push({ vendor: vendorCode, main: addM, sub: addS });
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
