(function () {

  var C = ClassStore.COURSES;
  var body = document.getElementById('venderBody');
  var list = ClassStore.load().filter(function (r) { return r.status !== OperatingStatusStore.labelOf('STOPPED'); });

  list.forEach(function (r) {
    var c = C[r.courseCode] || { name: r.courseCode };
    var a = VenderAssignStore.find(r.id);
    var S = VenderAssignStore.STATUS;
    function lines(items) {
      return items.length ? items.map(function (x) {
        return '<div data-vendor="' + esc(x.code || '') + '">' + esc(x.vendor) + '：' + esc(x.teacherName) + (x.status ? ' ' + VenderAssignStore.tag(x.status) : '') + '</div>';
      }).join('') : '-';
    }
    function statusOf(p) {
      if (p.state === 'done') return S.REQUESTED;
      if (p.state === 'requesting') return S.REQUESTING;
      if (p.state === 'before') return S.BEFORE;
      return null;
    }
    var mainLines = lines(a.mains.map(function (m) {
      return { code: m.vendor, vendor: TeacherVenderStore.nameOf(m.vendor) || '-', teacherName: m.teacherName || '', status: statusOf(m) };
    }));
    var subLines = lines(a.subs.map(function (s) {
      return { code: s.vendor, vendor: TeacherVenderStore.nameOf(s.vendor) || '-', teacherName: s.teacherName || '', status: statusOf(s) };
    }));
    var reqs = VenderAssignStore.requestsOf(a);
    var tot = VenderAssignStore.totalRequest(a);
    reqs.forEach(function (rq) {
      var reqText = esc(TeacherVenderStore.nameOf(rq.vendor) || '-') + '： ' + VenderAssignStore.tag(S.REQUESTING, '', 'fixed');
      for (var mi = 0; mi < (rq.main || 0); mi++) mainLines = (mainLines === '-' ? '' : mainLines) + '<div data-vendor="' + esc(rq.vendor) + '">' + reqText + '</div>';
      for (var si = 0; si < (rq.sub || 0); si++) subLines = (subLines === '-' ? '' : subLines) + '<div data-vendor="' + esc(rq.vendor) + '">' + reqText + '</div>';
    });
    var related = r.related && r.related.length ? r.related.slice().sort(function (a, b) { return String(a).localeCompare(String(b), 'ja', { numeric: true }); }).join(', ') : '-';
    var planMain = parseInt(r.mainTeachers, 10) || 0;
    var planSub = parseInt(r.subTeachers, 10) || 0;
    var reqOnly = VenderAssignStore.requestsOf(a).reduce(function (t, q) { t.main += q.main || 0; t.sub += q.sub || 0; return t; }, { main: 0, sub: 0 });
    var freeMain = Math.max(0, planMain - a.mains.length - reqOnly.main);
    var freeSub = Math.max(0, planSub - a.subs.length - reqOnly.sub);
    for (var fm = 0; fm < freeMain; fm++) mainLines = (mainLines === '-' ? '' : mainLines) + '<div data-vendor="">' + VenderAssignStore.tag(S.OPEN, '', 'fixed') + '</div>';
    for (var fs = 0; fs < freeSub; fs++) subLines = (subLines === '-' ? '' : subLines) + '<div data-vendor="">' + VenderAssignStore.tag(S.OPEN, '', 'fixed') + '</div>';
    var ps = ClassStore.practiceStatus(r);
    var tr = document.createElement('tr');
    var custCode = (ClassStore.PROJECTS[r.projectCode] || {}).customer;
    tr.innerHTML =
      '<td class="sticky col-practice">' + (ps ? '<span class="tag fixed ' + ClassStore.PRACTICE_CLASS[ps] + '">' + ps + '</span>' : '') + '</td>' +
      '<td class="sticky">' + esc(custCode ? CustomerStore.nameOf(custCode) : '-') + '</td>' +
      '<td class="sticky">' + esc(yearLabel(r.year)) + '</td>' +
      '<td class="sticky"><div>' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.courseCode) + '</div></td>' +
      '<td class="sticky"><div>' + esc(r.lessonNo) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(related) + '</div></td>' +
      '<td class="sticky">' + esc(r.start) + '</td>' +
      '<td class="sticky">' + esc(r.end) + '</td>' +
      '<td>' + dashOr(r.mainTeachers, '人') + '</td>' +
      '<td>' + mainLines + '</td>' +
      '<td>' + dashOr(r.subTeachers, '人') + '</td>' +
      '<td>' + subLines + '</td>' +
      '<td>' + (a.attendeeVendor || a.attendee ? '<div>' + dashOr(a.attendeeVendor) + '：' + dashOr(a.attendee) + '</div>' : '-') + '</td>' +
      '<td>' + (a.motivationVendor || a.motivationName ? '<div>' + esc(MotivationCompanyTypeStore.nameOf(a.motivationVendor) || '-') + '：' + dashOr(a.motivationName) + '</div>' : '-') + '</td>' +
      '<td class="memo-cell"' + (a.memo ? ' title="' + esc(a.memo) + '"' : '') + '>' + (a.memo ? '<span style="display:inline-block;width:16px;height:16px;line-height:16px;text-align:center;border-radius:50%;background:#fbd29b;color:#9a4a00;font-weight:700;font-size:12px;">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="vender_assign_modify.html?id=' + encodeURIComponent(r.id) + '">更新</a></td>';
    var names = a.mains.concat(a.subs, reqs).map(function (x) { return TeacherVenderStore.nameOf(x.vendor) || ''; }).filter(function (n, k, arr) { return n && arr.indexOf(n) === k; });
    tr.setAttribute('data-vendors', names.join('|'));
    body.appendChild(tr);
  });

  document.getElementById('vendorFilter').setAttribute('data-options', ['すべて'].concat(TeacherVenderStore.activeNames()).join(','));
  document.getElementById('venderCount').textContent = list.length;
  window.addEventListener('load', function () {
    var btn = document.querySelector('.filter-panel .search-btn');
    if (btn) btn.click();
  });
  document.querySelector('.filter-panel .search-btn').addEventListener('click', function () { setTimeout(applyVendorLines, 0); });
  function applyVendorLines() {
    var name = ownText(document.getElementById('vendorFilter'));
    var code = name && name !== 'すべて' ? TeacherVenderStore.codeOf(name) : '';
    Array.prototype.forEach.call(body.querySelectorAll('[data-vendor]'), function (el) {
      el.style.display = !code || el.getAttribute('data-vendor') === code ? '' : 'none';
    });
    var table = document.querySelector('.table-scroll table');
    if (table && table.__relayout) table.__relayout();
  }
})();
