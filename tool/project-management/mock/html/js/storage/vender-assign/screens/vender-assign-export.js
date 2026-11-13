(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  function clean(s) { return s === '選択してください' ? '' : s; }

  var C = ClassStore.COURSES;
  var list = ClassStore.load().filter(function (r) { return r.status !== '停止中' && ClassStore.practiceStatus(r) !== '実施後'; });
  var body = $('printBody');
  var rows = [];

  list.forEach(function (r) {
    var a = VenderAssignStore.find(r.id);
    rows.push({ cls: r, assign: a });
    var c = C[r.courseCode] || { name: r.courseCode };
    var namedMain = a.mains.filter(function (p) { return p.staff; }).length;
    var namedSub = a.subs.filter(function (p) { return p.staff; }).length;
    var remainMain = Math.max(0, (parseInt(r.mainTeachers, 10) || 0) - namedMain);
    var remainSub = Math.max(0, (parseInt(r.subTeachers, 10) || 0) - namedSub);
    var reqTot = VenderAssignStore.totalRequest(a);
    var pendMain = reqTot.main;
    var pendSub = reqTot.sub;
    var befMain = a.mains.filter(function (p) { return p.vendor && !p.staff; }).length;
    var befSub = a.subs.filter(function (p) { return p.vendor && !p.staff; }).length;
    var reqMain = Math.max(0, remainMain - pendMain - befMain);
    var reqSub = Math.max(0, remainSub - pendSub - befSub);
    var tr = document.createElement('tr');
    tr.setAttribute('data-id', r.id);
    tr.setAttribute('data-practice', ClassStore.practiceStatus(r));
    var fits = remainMain === 0 && remainSub === 0;
    tr.setAttribute('data-fit', fits ? 'in' : 'over');
    tr.setAttribute('data-remain-main', remainMain);
    tr.setAttribute('data-remain-sub', remainSub);
    tr.innerHTML =
      '<td style="text-align: center;"><label class="check-box"><input type="checkbox" class="row-check" checked><span class="check-mark"></span></label></td>' +
      '<td>' + esc(r.year) + '</td>' +
      '<td><div style="font-weight:700;">' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.courseCode) + '</div></td>' +
      '<td><div style="font-weight:700;">' + esc(r.lessonNo) + '</div></td>' +
      '<td>' + esc(r.start) + '</td>' +
      '<td>' + esc(r.end) + '</td>' +
      '<td>' + (r.mainTeachers ? esc(r.mainTeachers) + '名' : '-') + '</td>' +
      '<td><div style="display:flex;align-items:center;gap:6px;white-space:nowrap;"><span class="cnt-bef-main" style="color:#d97c1e;font-size:12.5px;">' + befMain + '人</span><span class="cnt-pend-main" style="color:#2f6fed;font-size:12.5px;">' + pendMain + '人</span><span class="cnt-done-main" style="color:#279158;font-size:12.5px;">' + namedMain + '人</span></div></td>' +
      '<td><input type="number" class="form-control main-count" min="0" max="' + reqMain + '" value="' + reqMain + '" style="width:72px;height:28px;"></td>' +
      '<td>' + (r.subTeachers ? esc(r.subTeachers) + '名' : '-') + '</td>' +
      '<td><div style="display:flex;align-items:center;gap:6px;white-space:nowrap;"><span class="cnt-bef-sub" style="color:#d97c1e;font-size:12.5px;">' + befSub + '人</span><span class="cnt-pend-sub" style="color:#2f6fed;font-size:12.5px;">' + pendSub + '人</span><span class="cnt-done-sub" style="color:#279158;font-size:12.5px;">' + namedSub + '人</span></div></td>' +
      '<td><input type="number" class="form-control sub-count" min="0" max="' + reqSub + '" value="' + reqSub + '" style="width:72px;height:28px;"></td>';
    body.appendChild(tr);
  });

  $('printCount').textContent = list.length;
  $('requestVendor').setAttribute('data-options', TeacherVenderStore.activeNames().join(','));

  function applyFilter() {
    var kw = $('keyword').value.trim().toLowerCase();
    var fitVal = clean(ownText($('fitFilter'))) || 'すべて';
    var practiceVal = clean(ownText($('practiceFilter'))) || 'すべて';
    var visible = 0;
    body.querySelectorAll('tr').forEach(function (tr) {
      var course = tr.children[2].textContent.toLowerCase();
      var canRequest = parseInt(tr.querySelector('.main-count').max, 10) > 0 || parseInt(tr.querySelector('.sub-count').max, 10) > 0;
      var fitOk = fitVal === 'すべて' || (fitVal === 'あり') === canRequest;
      var practiceOk = practiceVal === 'すべて' || tr.getAttribute('data-practice') === practiceVal;
      var ok = (!kw || course.indexOf(kw) !== -1) && fitOk && practiceOk;
      tr.style.display = ok ? '' : 'none';
      if (ok) visible++;
    });
    $('printCount').textContent = visible;
  }
  document.querySelector('.filter-panel .search-btn').addEventListener('click', applyFilter);
  applyFilter();

  var appliedVendor = null;
  function applyVendor() {
    var code = TeacherVenderStore.codeOf(clean(ownText($('requestVendor'))));
    body.querySelectorAll('tr').forEach(function (tr) {
      var id = tr.getAttribute('data-id');
      var row = rows.filter(function (x) { return x.cls.id === id; })[0];
      if (!row) return;
      var reqs = VenderAssignStore.requestsOf(row.assign);
      ['main', 'sub'].forEach(function (role) {
        var list = role === 'main' ? row.assign.mains : row.assign.subs;
        var isOther = function (v) { return !code || v !== code; };
        var befOthers = list.filter(function (p) { return p.vendor && !p.staff && isOther(p.vendor); }).length;
        var befSel = list.filter(function (p) { return p.vendor && !p.staff && !isOther(p.vendor); }).length;
        var pendOthers = reqs.filter(function (q) { return isOther(q.vendor); }).reduce(function (t, q) { return t + (q[role] || 0); }, 0);
        var pendSel = reqs.filter(function (q) { return !isOther(q.vendor); }).reduce(function (t, q) { return t + (q[role] || 0); }, 0);
        var remain = parseInt(tr.getAttribute('data-remain-' + role), 10) || 0;
        var input = tr.querySelector('.' + role + '-count');
        var val = Math.max(0, remain - pendOthers - pendSel - befOthers);
        input.max = val;
        input.value = val;
        var doneVal = list.filter(function (p) { return p.staff && (!code || p.vendor === code); }).length;
        tr.querySelector('.cnt-bef-' + role).textContent = code ? befSel + '人' : '-';
        tr.querySelector('.cnt-pend-' + role).textContent = code ? pendSel + '人' : '-';
        tr.querySelector('.cnt-done-' + role).textContent = code ? doneVal + '人' : '-';
      });
    });
  }
  function syncVendor() {
    var v = clean(ownText($('requestVendor')));
    if (v === appliedVendor) return;
    appliedVendor = v;
    applyVendor();
  }
  syncVendor();
  document.addEventListener('click', function () { setTimeout(syncVendor, 0); }, true);

  function visibleRows() {
    return Array.prototype.filter.call(body.querySelectorAll('tr'), function (tr) { return tr.style.display !== 'none'; });
  }
  function syncSelToggle() {
    var rows = visibleRows();
    var allOn = rows.length > 0 && rows.every(function (tr) { return tr.querySelector('.row-check').checked; });
    $('selToggle').classList.toggle('off', !allOn);
  }
  $('selToggle').addEventListener('click', function () {
    var on = $('selToggle').classList.contains('off');
    visibleRows().forEach(function (tr) { tr.querySelector('.row-check').checked = on; });
    syncSelToggle();
  });
  body.addEventListener('input', function (e) {
    if (!e.target.matches('.main-count, .sub-count')) return;
    var max = parseInt(e.target.getAttribute('max'), 10) || 0;
    var v = parseInt(e.target.value, 10);
    if (isNaN(v) || v < 0) { e.target.value = v < 0 ? 0 : e.target.value; return; }
    if (v > max) e.target.value = max;
  });
  body.addEventListener('change', function (e) {
    if (e.target.classList.contains('row-check')) syncSelToggle();
  });

  $('printBtn').addEventListener('click', function () {
    var vendor = clean(ownText($('requestVendor')));
    var vendorCode = TeacherVenderStore.codeOf(vendor);
    if (!vendor) {
      MessageDialog.required(['講師ベンダー']);
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
      var mainCount = parseInt(tr.querySelector('.main-count').value, 10) || 0;
      var subCount = parseInt(tr.querySelector('.sub-count').value, 10) || 0;
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
        it.cls.year,
        c.name,
        it.cls.courseCode,
        it.cls.lessonNo,
        it.cls.start,
        it.cls.end
      ];
      var people = [];
      for (i = 0; i < mainMax + subMax; i++) people.push('');
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
      var exMain = existing.reduce(function (t, r) { return t + (r.main || 0); }, 0);
      var exSub = existing.reduce(function (t, r) { return t + (r.sub || 0); }, 0);
      var reqs = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor !== vendorCode; });
      if (x.main || x.sub || exMain || exSub) reqs.push({ vendor: vendorCode, main: exMain + x.main, sub: exSub + x.sub });
      var notYet = function (p) { return !(p.vendor === vendorCode && !p.staff); };
      rec.mains = (rec.mains || []).filter(notYet);
      rec.subs = (rec.subs || []).filter(notYet);
      rec.requests = reqs;
      delete rec.requested;
      delete rec.requestMain;
      delete rec.requestSub;
      delete rec.requestVendor;
      VenderAssignStore.upsert(rec);
    });
    location.href = 'vender_assign_list.html';
  });
})();
